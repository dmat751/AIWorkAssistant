#!/bin/bash
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root: sudo $0"
  exit 1
fi

USERNAME="${SUDO_USER:-$(logname 2>/dev/null || stat -f%Su /dev/console 2>/dev/null || echo "$USER")}"
if [[ -z "$USERNAME" || "$USERNAME" == "root" ]]; then
  echo "Could not determine the installing user."
  exit 1
fi

SUDOERS_FILE="/etc/sudoers.d/aiworkassistant-commute"
TMP_FILE="$(mktemp)"

cat >"$TMP_FILE" <<EOF
# AI Work Assistant commute mode — narrowly scoped pmset disablesleep access
${USERNAME} ALL=(ALL) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0
EOF

if ! visudo -cf "$TMP_FILE"; then
  echo "Generated sudoers entry failed validation."
  rm -f "$TMP_FILE"
  exit 1
fi

install -o root -g wheel -m 0440 "$TMP_FILE" "$SUDOERS_FILE"
rm -f "$TMP_FILE"

echo "Installed $SUDOERS_FILE for user ${USERNAME}."
echo "Uninstall with: sudo scripts/uninstall-commute-permission.sh"
