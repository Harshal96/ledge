#!/bin/zsh
set -euo pipefail

root=${1:-${0:A:h:h}}
manifest="$root/Packages/LedgeKit/Package.swift"
[[ -f "$manifest" ]] || { print -u2 "Package manifest not found: $manifest"; exit 2; }

# The MVP intentionally has no third-party package dependencies. Keep this as a
# fail-closed source gate until a dependency is introduced with a provenance
# entry and an explicit SPDX license review.
if /usr/bin/grep -E -q 'package\(url:|\.package\(' "$manifest"; then
  print -u2 "Undeclared third-party package dependency found in $manifest"
  exit 1
fi

provenance="$root/docs/compliance/source-provenance.md"
[[ -f "$provenance" ]] || { print -u2 "Source provenance register is missing: $provenance"; exit 2; }
if /usr/bin/find "$root/Packages/LedgeKit/Sources" "$root/LedgeApp" -type f \( -name '*.swift' -o -name '*.h' -o -name '*.m' \) -exec /usr/bin/grep -El 'AGPL|LGPL|SSPL|BUSL|non-free|(^|[^A-Z])GPL([^A-Z]|$)' {} + | /usr/bin/grep -q .; then
  print -u2 "Forbidden or undeclared license marker found in first-party source"
  exit 1
fi
print "Third-party license gate passed: no external package dependency is declared."
