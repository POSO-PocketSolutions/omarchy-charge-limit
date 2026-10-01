#!/bin/bash
set -euo pipefail

# Removes the privileged side of the charge-limit plugin installed by
# install.sh: the systemd unit, the CLI, and the scoped sudoers rule. The
# battery is released to 0/100 before the unit is removed so no limit is
# left applied without anything managing it.

if [[ $EUID -ne 0 ]]; then
  echo "charge-limit uninstall: re-running with sudo" >&2
  exec sudo -E "$0" "$@"
fi

if [[ -x /usr/local/bin/charge-limit ]]; then
  /usr/local/bin/charge-limit off || true
fi

systemctl disable --now charge-limit.service 2>/dev/null || true
rm -f /etc/systemd/system/charge-limit.service
systemctl daemon-reload

rm -f /usr/local/bin/charge-limit
rm -f /etc/sudoers.d/charge-limit
rm -f /etc/charge-limit.conf

echo "Removed charge-limit CLI, service, sudoers rule and config."
echo "The battery limit was released to 0/100."
