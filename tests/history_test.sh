#!/bin/bash
set -euo pipefail

plugin_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
mkdir -p "$tmp_dir/bin"

cat > "$tmp_dir/bin/busctl" <<'SCRIPT'
#!/bin/bash
if [[ ${HISTORY_TEST_FAILURE:-0} == 1 ]]; then
  exit 1
fi
printf '%s\n' '{"type":"a(udu)","data":[[[300,80,2],[100,60,1],[200,70,4],[400,90,5]]]}'
SCRIPT
chmod +x "$tmp_dir/bin/busctl"

result=$(PATH="$tmp_dir/bin:/usr/bin" "$plugin_dir/scripts/history")
jq -e '
  .available == true and
  .hours == 24 and
  (.points | length) == 4 and
  [.points[].timestamp] == [100, 200, 300, 400] and
  [.points[].level] == [60, 70, 80, 90] and
  [.points[].state] == ["charging", "full", "discharging", "pending-charge"]
' <<< "$result" >/dev/null
printf 'ok - normalizes and orders UPower history\n'

failure_result=$(HISTORY_TEST_FAILURE=1 PATH="$tmp_dir/bin:/usr/bin" "$plugin_dir/scripts/history")
jq -e '.available == false and .points == [] and (.error | length > 0)' <<< "$failure_result" >/dev/null
printf 'ok - returns valid JSON when UPower history is unavailable\n'
