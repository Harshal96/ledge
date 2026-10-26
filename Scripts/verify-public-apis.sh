#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
repository_root=${script_dir:h}
target=${1:-}
forbidden=(
  "Media""Remote"
  "(^|[^A-Za-z0-9_])CGS[A-Z][A-Za-z0-9_]+"
  "Scripting""Bridge"
  "AXUI""Element"
  "CGEvent""Post"
  "SMJob""Bless"
)

scan_text() {
  local path=$1
  local pattern
  for pattern in "${forbidden[@]}"; do
    if /usr/bin/grep -E -q -- "$pattern" "$path"; then
      print -u2 "Forbidden public-API boundary violation: $path"
      exit 1
    fi
  done
}

while IFS= read -r -d '' source; do
  scan_text "$source"
done < <(/usr/bin/find "$repository_root/Packages/LedgeKit/Sources" "$repository_root/LedgeApp" -type f \( -name '*.swift' -o -name '*.m' -o -name '*.mm' -o -name '*.h' -o -name '*.c' -o -name '*.cc' -o -name '*.cpp' \) -print0)

if [[ -n "$target" ]]; then
  [[ -e "$target" ]] || { print -u2 "Scan target does not exist: $target"; exit 2; }
  while IFS= read -r -d '' candidate; do
    if /usr/bin/file -b "$candidate" | /usr/bin/grep -q 'Mach-O'; then
      scan_text "$candidate"
      for pattern in "${forbidden[@]}"; do
        if /usr/bin/nm -u "$candidate" 2>/dev/null | /usr/bin/grep -E -q -- "$pattern"; then
          print -u2 "Forbidden linked symbol: $candidate"
          exit 1
        fi
      done
    else
      scan_text "$candidate"
    fi
  done < <(/usr/bin/find "$target" -type f -print0)

  if [[ -d "$target" ]]; then
    while IFS= read -r -d '' executable; do
      case "$executable" in
        *.app/Contents/MacOS/Ledge|*.app/Contents/MacOS/LedgeAgent|*.app/Contents/MacOS/ledge-cli) ;;
        *) print -u2 "Non-system embedded executable: $executable"; exit 1 ;;
      esac
    done < <(/usr/bin/find "$target" -type f -perm -111 -print0)
  fi
fi

print "Public API scan passed."
