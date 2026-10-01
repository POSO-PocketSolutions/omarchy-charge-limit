#!/bin/bash
set -euo pipefail

# Installs the privileged side of the charge-limit plugin: the CLI, a systemd
# unit that re-applies the saved limit on every boot/resume, and a scoped
# sudoers rule so the bar widget can toggle/set the limit without a password.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

install -m 0755 "$here/charge-limit" /usr/local/bin/charge-limit
install -m 0644 "$here/charge-limit.service" /etc/systemd/system/charge-limit.service

sudoers_out="/etc/sudoers.d/charge-limit"
tmp_sudoers="$(mktemp)"
trap 'rm -f "$tmp_sudoers"' EXIT
sed "s/__USER__/$target_user/" "$here/charge-limit.sudoers.in" >"$tmp_sudoers"
visudo -cf "$tmp_sudoers"
install -m 0440 -o root -g root "$tmp_sudoers" "$sudoers_out"

systemctl daemon-reload
systemctl enable charge-limit.service

echo
echo "Installed:"
echo "  /usr/local/bin/charge-limit"
echo "  /etc/systemd/system/charge-limit.service (enabled)"
echo "  $sudoers_out (user: $target_user)"
echo
echo "Set your limit, e.g.:  sudo charge-limit set 75 80"
