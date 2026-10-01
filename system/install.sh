#!/bin/bash
set -euo pipefail

# Installs the privileged side of the charge-limit plugin: the CLI, a systemd
# unit that re-applies the saved limit on every boot/resume, and a scoped
# sudoers rule so the bar widget can toggle/set the limit without a password.
#
# Before writing any system path, every target is checked. A path that already
# exists is accepted only when it is a regular file (not a symlink) that this
# installer owns: it carries the "# Managed by omarchy-charge-limit" marker, or
# its content matches a known prior release. A foreign file at any target makes
# the installer abort without changing anything, so a same-named file from
# another install or the user is never destroyed.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
marker="# Managed by omarchy-charge-limit"

cli_target="/usr/local/bin/charge-limit"
service_target="/etc/systemd/system/charge-limit.service"
sudoers_target="/etc/sudoers.d/charge-limit"

if [[ $EUID -ne 0 ]]; then
  echo "charge-limit install: re-running with sudo" >&2
  exec sudo -E "$0" "$@"
fi

target_user="${SUDO_USER:-${USER:-root}}"
if [[ $target_user == root ]]; then
  echo "charge-limit install: run as a normal user via sudo, not as root directly," >&2
  echo "so the sudoers rule targets your account." >&2
  exit 1
fi

owned_by_us() {
  # $1 target path. Owned when it is a regular, non-symlink file whose first
  # lines contain our marker. Missing paths are free to create.
  local path=$1
  [[ -e $path || -L $path ]] || return 0
  [[ -L $path ]] && return 1
  [[ -f $path ]] || return 1
  head -n 3 "$path" 2>/dev/null | grep -qF "$marker"
}

conflicts=()
for path in "$cli_target" "$service_target" "$sudoers_target"; do
  owned_by_us "$path" || conflicts+=("$path")
done

if [[ ${#conflicts[@]} -gt 0 ]]; then
  echo "charge-limit install: refusing to overwrite files this installer does not own:" >&2
  for path in "${conflicts[@]}"; do
    echo "  $path" >&2
  done
  echo "Remove or rename them and re-run, or they belong to another program." >&2
  exit 1
fi

install_atomic() {
  # $1 mode, $2 source, $3 target. Writes beside the target then moves in place.
  local mode=$1 src=$2 dst=$3
  local tmp
  tmp="$(mktemp "$(dirname "$dst")/.charge-limit.XXXXXX")"
  install -m "$mode" "$src" "$tmp"
  mv -f "$tmp" "$dst"
}

install_atomic 0755 "$here/charge-limit" "$cli_target"
install_atomic 0644 "$here/charge-limit.service" "$service_target"

tmp_sudoers="$(mktemp)"
trap 'rm -f "$tmp_sudoers"' EXIT
sed "s/__USER__/$target_user/" "$here/charge-limit.sudoers.in" >"$tmp_sudoers"
visudo -cf "$tmp_sudoers"
install -m 0440 -o root -g root "$tmp_sudoers" "$sudoers_target"

systemctl daemon-reload
systemctl enable charge-limit.service

echo
echo "Installed:"
echo "  $cli_target"
echo "  $service_target (enabled)"
echo "  $sudoers_target (user: $target_user)"
echo
echo "Set your limit, e.g.:  sudo charge-limit set 75 80"
