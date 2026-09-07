#!/bin/bash
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root: sudo $0"
  exit 1
fi

SUDOERS_FILES=(
  "/etc/sudoers.d/aiworkassistant-commute"
  "/etc/sudoers.d/desktopnumber-commute"
)

removed_any=0
for SUDOERS_FILE in "${SUDOERS_FILES[@]}"; do
  if [[ -f "$SUDOERS_FILE" ]]; then
    rm -f "$SUDOERS_FILE"
    echo "Removed $SUDOERS_FILE"
    removed_any=1
  fi
done

if [[ "$removed_any" -eq 0 ]]; then
  echo "No commute permission files found."
fi
