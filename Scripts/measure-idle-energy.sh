#!/bin/zsh
set -euo pipefail

archive=${1:-}
duration=${LEDGE_ENERGY_SECONDS:-600}
if [[ -z "$archive" || ! -e "$archive" ]]; then
  print -u2 "Usage: $0 /path/to/Ledge.xcarchive"
  exit 2
fi
[[ "$duration" == <-> && "$duration" -gt 0 ]] || { print -u2 "LEDGE_ENERGY_SECONDS must be a positive integer"; exit 2; }

app="$archive/Products/Applications/Ledge.app"
[[ -d "$app" ]] || { print -u2 "Archived app not found: $app"; exit 2; }

log_dir=${TMPDIR:-/tmp}/ledge-energy-$(date +%Y%m%d-%H%M%S)
/bin/mkdir -p "$log_dir"
print "Ledge idle-energy measurement" | tee "$log_dir/README.txt"
sw_vers | tee -a "$log_dir/README.txt"
uname -a | tee -a "$log_dir/README.txt"
print "duration_seconds=$duration" | tee -a "$log_dir/README.txt"

open -na "$app" --args -ledge-energy-fixture >"$log_dir/open.log" 2>&1 || {
  print -u2 "Could not launch archived app; energy evidence is incomplete"
  exit 2
}
pid=$(/usr/bin/pgrep -n -f '/Ledge.app/Contents/MacOS/Ledge' || true)
if [[ -z "$pid" ]]; then
  print -u2 "Could not identify Ledge process; energy evidence is incomplete"
  exit 2
fi
trap '/usr/bin/kill "$pid" 2>/dev/null || true' EXIT

for ((second=0; second<duration; second+=5)); do
  /bin/date +%s | tr '\n' ' ' >>"$log_dir/ps.tsv"
  /bin/ps -p "$pid" -o pid=,pcpu=,rss=,etime= >>"$log_dir/ps.tsv" || break
  /bin/sleep 5
done

if command -v powermetrics >/dev/null 2>&1; then
  print "powermetrics is available; run an interactive Energy Log for wakeups (sudo may be required)." | tee -a "$log_dir/README.txt"
else
  print "powermetrics unavailable; wakeup evidence is incomplete." | tee -a "$log_dir/README.txt"
fi
if command -v nettop >/dev/null 2>&1; then
  nettop -P -L 1 -J bytes_in,bytes_out -p "$pid" -c 1 >"$log_dir/nettop.txt" 2>&1 || true
else
  print "nettop unavailable; network-byte evidence is incomplete." | tee -a "$log_dir/README.txt"
fi
print "Raw measurements: $log_dir"
