#!/bin/bash
set -euo pipefail

TARGET_DIR="${HOME}/.cursor"
HOOKS_DIR="${TARGET_DIR}/hooks"
HOOKS_JSON="${TARGET_DIR}/hooks.json"

HOOK_COMMANDS=(
  "./hooks/on-stop.sh"
  "./hooks/on-before-shell.sh"
  "./hooks/on-before-mcp.sh"
)

removed_any=false

for script in notify-ntfy.sh approval-notify.sh on-stop.sh on-before-shell.sh on-before-mcp.sh; do
  target="${HOOKS_DIR}/${script}"
  if [[ -f "$target" ]]; then
    rm -f "$target"
    echo "Removed ${target}"
    removed_any=true
  fi
done

if [[ -f "$HOOKS_JSON" ]]; then
  backup="${HOOKS_JSON}.bak.$(date +%Y%m%d%H%M%S)"
  cp "$HOOKS_JSON" "$backup"
  echo "Backed up hooks.json to ${backup}"

  python3 - "$HOOKS_JSON" "${HOOK_COMMANDS[@]}" <<'PY'
import json
import pathlib
import sys

hooks_json = pathlib.Path(sys.argv[1])
commands_to_remove = set(sys.argv[2:])

data = json.loads(hooks_json.read_text())
hooks = data.get("hooks", {})

for hook_name, entries in list(hooks.items()):
    if not isinstance(entries, list):
        continue
    filtered = [
        hook for hook in entries
        if not (isinstance(hook, dict) and hook.get("command") in commands_to_remove)
    ]
    if filtered:
        hooks[hook_name] = filtered
    else:
        del hooks[hook_name]

if hooks:
    data["hooks"] = hooks
elif "hooks" in data:
    del data["hooks"]

hooks_json.write_text(json.dumps(data, indent=2) + "\n")
PY

  echo "Removed AI Work Assistant hook entries from ${HOOKS_JSON}"
  removed_any=true
fi

if [[ "$removed_any" == false ]]; then
  echo "No AI Work Assistant Cursor notify hooks found."
else
  echo "Uninstalled Cursor notify hooks."
  echo "Restart Cursor to apply changes."
fi
