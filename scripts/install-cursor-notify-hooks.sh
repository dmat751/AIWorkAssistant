#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="${REPO_ROOT}/cursor-hooks"
TARGET_DIR="${HOME}/.cursor"
HOOKS_DIR="${TARGET_DIR}/hooks"
HOOKS_JSON="${TARGET_DIR}/hooks.json"
NOTIFY_ENV="${HOOKS_DIR}/notify.env"

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "Missing source directory: ${SOURCE_DIR}"
  exit 1
fi

mkdir -p "$HOOKS_DIR"

for script in notify-ntfy.sh on-stop.sh; do
  install -m 755 "${SOURCE_DIR}/${script}" "${HOOKS_DIR}/${script}"
done

for stale in approval-notify.sh on-before-shell.sh on-before-mcp.sh; do
  if [[ -f "${HOOKS_DIR}/${stale}" ]]; then
    rm -f "${HOOKS_DIR}/${stale}"
    echo "Removed leftover ${HOOKS_DIR}/${stale}"
  fi
done

if [[ ! -f "$NOTIFY_ENV" ]]; then
  install -m 600 "${SOURCE_DIR}/notify.env.example" "$NOTIFY_ENV"
  echo "Created ${NOTIFY_ENV}"
else
  echo "Keeping existing ${NOTIFY_ENV}"
fi

if [[ -f "$HOOKS_JSON" ]]; then
  backup="${HOOKS_JSON}.bak.$(date +%Y%m%d%H%M%S)"
  cp "$HOOKS_JSON" "$backup"
  echo "Backed up existing hooks.json to ${backup}"
fi

python3 - "$HOOKS_JSON" <<'PY'
import json
import pathlib
import sys

hooks_json = pathlib.Path(sys.argv[1])
stale_commands = {
    "./hooks/on-before-shell.sh",
    "./hooks/on-before-mcp.sh",
}

if hooks_json.exists():
    data = json.loads(hooks_json.read_text())
else:
    data = {"version": 1, "hooks": {}}

data.setdefault("version", 1)
data.setdefault("hooks", {})

def merge_hook(hook_name, command, matcher=None):
    hooks = data["hooks"].setdefault(hook_name, [])
    already_installed = any(
        hook.get("command") == command
        for hook in hooks
        if isinstance(hook, dict)
    )
    if already_installed:
        return
    entry = {"command": command}
    if matcher:
        entry["matcher"] = matcher
    hooks.append(entry)

def strip_stale(hook_name):
    hooks = data["hooks"].get(hook_name)
    if not isinstance(hooks, list):
        return
    filtered = [
        hook for hook in hooks
        if not (isinstance(hook, dict) and hook.get("command") in stale_commands)
    ]
    if filtered:
        data["hooks"][hook_name] = filtered
    else:
        data["hooks"].pop(hook_name, None)

merge_hook("stop", "./hooks/on-stop.sh", "Stop")
strip_stale("beforeShellExecution")
strip_stale("beforeMCPExecution")

hooks_json.write_text(json.dumps(data, indent=2) + "\n")
PY

echo "Updated ${HOOKS_JSON}"

topic="$(grep -E '^NTFY_TOPIC=' "$NOTIFY_ENV" | cut -d= -f2- || true)"

echo ""
if [[ -n "$topic" && "$topic" != "your-topic-name" ]]; then
  echo "Sending test notification to ntfy.sh/${topic}..."
  if curl -fsS -d "AI Work Assistant: Cursor notify hooks installed" "https://ntfy.sh/${topic}"; then
    echo ""
    echo "Test notification sent."
  else
    echo ""
    echo "Warning: test notification failed. Check network access and topic name."
  fi
else
  echo "Skipped test notification. Set NTFY_TOPIC in ${NOTIFY_ENV} first."
fi

echo ""
echo "Installed Cursor notify hooks."
echo "Restart Cursor, then verify in Customize → Hooks."
echo "Uninstall with: scripts/uninstall-cursor-notify-hooks.sh"
