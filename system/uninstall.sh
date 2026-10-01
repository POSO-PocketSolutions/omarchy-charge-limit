#!/bin/bash
set -euo pipefail

# Removes the privileged side of the charge-limit plugin installed by
# install.sh. It only removes files this installer owns: a regular, non-symlink
# file carrying the "# Managed by omarchy-charge-limit" marker. A foreign or
# hand-edited file at any of these paths is left in place and reported, so the
# documented removal never destroys unrelated system configuration.

marker="# Managed by omarchy-charge-limit"

cli_target="/usr/local/bin/charge-limit"
service_target="/etc/systemd/system/charge-limit.service"
sudoers_target="/etc/sudoers.d/charge-limit"
config_target="/etc/charge-limit.conf"

if [[ $EUID -ne 0 ]]; then
  echo "charge-limit uninstall: re-running with sudo" >&2
  exec sudo -E "$0" "$@"
fi

owned_by_us() {
  local path=$1
  [[ -e $path || -L $path ]] || return 1
  [[ -L $path ]] && return 1
  [[ -f $path ]] || return 1
  head -n 3 "$path" 2>/dev/null | grep -qF "$marker"
}

config_is_ours() {
  # The config is edited by hand and by `charge-limit set`, so it has no marker.
  # Accept only a plain root-owned file that holds nothing but comments, blanks,
  # and the known settings.
  local path=$1
  [[ -f $path && ! -L $path ]] || return 1
  [[ "$(stat -c '%U' "$path")" == root ]] || return 1
  if grep -qvE '^\s*(#.*)?$|^\s*(START|END|ENABLED)=[0-9A-Za-z]*\s*$' "$path"; then
    return 1
  fi
  return 0
}

skipped=()

if owned_by_us "$cli_target"; then
  "$cli_target" off || true
fi

if owned_by_us "$service_target"; then
  systemctl disable --now charge-limit.service 2>/dev/null || true
  rm -f "$service_target"
  systemctl daemon-reload
else
  [[ -e $service_target || -L $service_target ]] && skipped+=("$service_target")
fi

if owned_by_us "$cli_target"; then
  rm -f "$cli_target"
else
  [[ -e $cli_target || -L $cli_target ]] && skipped+=("$cli_target")
fi

if owned_by_us "$sudoers_target"; then
  rm -f "$sudoers_target"
else
  [[ -e $sudoers_target || -L $sudoers_target ]] && skipped+=("$sudoers_target")
fi

if config_is_ours "$config_target"; then
  rm -f "$config_target"
elif [[ -e $config_target || -L $config_target ]]; then
  skipped+=("$config_target")
fi

echo "Removed charge-limit files owned by this installer."
echo "The battery limit was released to 0/100."

if [[ ${#skipped[@]} -gt 0 ]]; then
  echo
  echo "Left in place (not owned by this installer, or hand-edited):" >&2
  for path in "${skipped[@]}"; do
    echo "  $path" >&2
  done
fi
