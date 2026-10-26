#!/bin/zsh
set -euo pipefail

mode=${1:---project}
if [[ "$mode" == "--summary-json" ]]; then
  summary_json=${2:?usage: verify-test-targets.sh --summary-json fixture.json}
elif [[ "$mode" == "--result" ]]; then
  result_bundle=${2:?usage: verify-test-targets.sh --result bundle.xcresult}
  [[ -e "$result_bundle" ]] || { print -u2 "Test result bundle not found: $result_bundle"; exit 2; }
  summary_json=$(mktemp "${TMPDIR:-/tmp}/ledge-test-summary.XXXXXX.json")
  trap 'rm -f "$summary_json"' EXIT
  xcrun xcresulttool get test-results summary --path "$result_bundle" > "$summary_json"
elif [[ "$mode" == "--project" ]]; then
  project_json=$(mktemp "${TMPDIR:-/tmp}/ledge-project.XXXXXX.json")
  list_output=$(mktemp "${TMPDIR:-/tmp}/ledge-target-list.XXXXXX.txt")
  plans_output=$(mktemp "${TMPDIR:-/tmp}/ledge-test-plans.XXXXXX.txt")
  trap 'rm -f "$project_json" "$list_output" "$plans_output"' EXIT
  plutil -convert json -o "$project_json" Ledge.xcodeproj/project.pbxproj
  xcodebuild -list -project Ledge.xcodeproj -scheme Ledge -derivedDataPath .build/DerivedData > "$list_output"
  xcodebuild -showTestPlans -project Ledge.xcodeproj -scheme Ledge -derivedDataPath .build/DerivedData > "$plans_output"
  /usr/bin/python3 - "$project_json" "$list_output" <<'PY'
import json
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

project = json.loads(Path(sys.argv[1]).read_text())
objects = project["objects"]
scheme = ET.parse("Ledge.xcodeproj/xcshareddata/xcschemes/Ledge.xcscheme")
listed = Path(sys.argv[2]).read_text()
expected = {
    "LedgeIntegrationTests": "com.apple.product-type.bundle.unit-test",
    "LedgeUITests": "com.apple.product-type.bundle.ui-testing",
    "LedgePerformanceTests": "com.apple.product-type.bundle.unit-test",
}
testables = {
    ref.attrib["BlueprintIdentifier"]
    for ref in scheme.findall("./TestAction/Testables/TestableReference[@skipped='NO']/BuildableReference")
}
if not testables:
    raise SystemExit("Scheme has no enabled testables")
for name, kind in expected.items():
    matches = [(key, value) for key, value in objects.items()
               if value.get("isa") == "PBXNativeTarget" and value.get("name") == name]
    if len(matches) != 1:
        raise SystemExit(f"Missing or duplicate target: {name}")
    key, target = matches[0]
    if target.get("productType") != kind or key not in testables:
        raise SystemExit(f"{name}: wrong product type or absent from TestAction")
    if name not in listed:
        raise SystemExit(f"{name}: absent from xcodebuild -list")
    groups = target.get("fileSystemSynchronizedGroups", [])
    if not groups or not any(objects[group].get("path") == name for group in groups):
        raise SystemExit(f"{name}: source directory is not registered")
    sources = list(Path(name).glob("*.swift"))
    if not sources or not any("func test" in path.read_text() for path in sources):
        raise SystemExit(f"{name}: no runnable test methods in registered sources")
    phases = [objects[phase]["isa"] for phase in target["buildPhases"]]
    if "PBXSourcesBuildPhase" not in phases:
        raise SystemExit(f"{name}: no source build phase")
print("Registered Xcode test targets: " + ", ".join(expected))
PY
  exit 0
else
  print -u2 "usage: verify-test-targets.sh [--project | --result bundle.xcresult | --summary-json fixture.json]"
  exit 2
fi

/usr/bin/python3 - "$summary_json" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as handle:
        summary = json.load(handle)
    total = summary["totalTestCount"]
    passed = summary["passedTests"]
    failed = summary["failedTests"]
    if any(type(value) is not int or value < 0 for value in (total, passed, failed)):
        raise ValueError("invalid test counts")
    if total == 0 or passed == 0:
        raise ValueError("no tests executed and passed")
    if failed or summary["result"] != "Passed":
        raise ValueError(f"test result is {summary['result']} with {failed} failures")
    print(f"Executed {total} tests: {passed} passed, {failed} failed")
except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as error:
    print(f"Test execution evidence invalid: {error}", file=sys.stderr)
    sys.exit(1)
PY
