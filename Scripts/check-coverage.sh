#!/bin/zsh
set -euo pipefail

# Test bundles are not product code. All app/package targets with executable
# lines remain in the gate; no low-coverage target can be masked by another.
result_bundle=${1:-.build/LedgeTests.xcresult}
report_json=""
temporary_report=""
if [[ "$result_bundle" == "--report-json" ]]; then
  report_json=${2:?usage: check-coverage.sh --report-json fixture.json}
else
  [[ -e "$result_bundle" ]] || { print -u2 "Coverage result bundle not found: $result_bundle"; exit 2; }
  temporary_report=$(mktemp "${TMPDIR:-/tmp}/ledge-coverage.XXXXXX.json")
  trap 'rm -f "$temporary_report"' EXIT
  if ! xcrun xccov view --report --json "$result_bundle" > "$temporary_report"; then
    print -u2 "Cannot read xccov report from $result_bundle"
    exit 2
  fi
  report_json=$temporary_report
fi

/usr/bin/python3 - "$report_json" <<'PY'
import json
import sys

EXCLUDED_SUFFIXES = (".xctest",)  # XCTest bundles, not the product under test.
MIN_TARGET_COVERAGE = 80.0

try:
    with open(sys.argv[1], encoding="utf-8") as handle:
        report = json.load(handle)
    targets = report["targets"]
    if not isinstance(targets, list) or not targets:
        raise ValueError("no coverage targets")
    counted = []
    for target in targets:
        name = target["name"]
        if not isinstance(name, str) or not name:
            raise ValueError("target without a name")
        if name.endswith(EXCLUDED_SUFFIXES):
            print(f"EXCLUDED {name}: XCTest bundle")
            continue
        files = target["files"]
        if not isinstance(files, list) or not files:
            raise ValueError(f"{name}: no file-level line data")
        covered = executable = 0
        for source in files:
            source_name = source.get("path") or source.get("name") or "<unknown>"
            lines = source["executableLines"]
            hit = source["coveredLines"]
            if (type(lines) is not int or type(hit) is not int or
                    lines < 0 or hit < 0 or hit > lines):
                raise ValueError(f"{name}/{source_name}: invalid line counts")
            covered += hit
            executable += lines
        if executable == 0:
            raise ValueError(f"{name}: zero executable source lines")
        if (target.get("coveredLines") != covered or
                target.get("executableLines") != executable):
            raise ValueError(f"{name}: target and file line counts disagree")
        percent = 100.0 * covered / executable
        counted.append((name, covered, executable, percent))
    if not counted:
        raise ValueError("no product targets with coverage")
    failed = False
    for name, covered, executable, percent in counted:
        print(f"{name}: {covered}/{executable} lines ({percent:.2f}%)")
        if percent < MIN_TARGET_COVERAGE:
            failed = True
    total_covered = sum(row[1] for row in counted)
    total_executable = sum(row[2] for row in counted)
    print(f"Weighted product total: {total_covered}/{total_executable} lines "
          f"({100.0 * total_covered / total_executable:.2f}%)")
    if failed:
        print(f"Coverage gate failed: every product target needs {MIN_TARGET_COVERAGE:.0f}% line coverage", file=sys.stderr)
        sys.exit(1)
except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as error:
    print(f"Coverage evidence invalid: {error}", file=sys.stderr)
    sys.exit(2)
PY
