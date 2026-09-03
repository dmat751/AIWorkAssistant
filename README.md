# DesktopNumber

A macOS menu bar app that shows the active desktop number (e.g. `3` or `3/5`) and today's Cursor usage cost (e.g. `3/5 · $0.42`), so you don't have to press Ctrl+↑ to check which desktop you're on or open the Cursor dashboard to see today's spend.

It also includes:

- **Office / Power status** — read-only check that your Mac is configured for lock-screen safety on AC power (`Prevent automatic sleeping on power adapter when the display is off`).
- **Commute mode** — keeps the Mac awake with the lid closed for local Cursor agents during a commute, with automatic safety cutoffs.

See [Quick Start](#quick-start) to build and run in one step.

## Requirements

- macOS 13 (Ventura) or later
- Xcode 15+

## Quick Start

From the repo root:

```bash
git clone <repo-url>
cd <repo-directory>
./scripts/build-and-open-desktop-number.sh
```

The script builds a Release build with `xcodebuild -derivedDataPath build` and opens:

```
build/Build/Products/Release/DesktopNumber.app
```

The menu bar icon appears immediately. The app runs as an agent (`LSUIElement`) — it has no Dock icon.

## Using the app

The menu bar label shows the current desktop number. When Cursor usage data is available, it also shows today's cost, for example `3/5 · $0.42`. When commute mode is active, the label also shows a coffee indicator.

Clicking the icon opens a menu with:

- current desktop number
- today's Cursor cost, token usage, and **Refresh Cursor Usage**
- **Cursor Agent Push** — toggles for finish and approve notifications, **ntfy topic** field, and **Send Test Push**
- **Office / Power** status (AC, prevent-sleep setting, lock-screen safety) and **Refresh Power Status**
- **Commute Mode** controls, **Grant Access**, and safety status
- **Quit**

## Commute mode setup

Commute mode uses `pmset -a disablesleep` so a MacBook can stay awake with the lid closed. This requires narrowly scoped, passwordless `sudo` access for exactly two commands.

Install once from the menu (**Grant Access** next to Start Commute Mode) or manually:

```bash
sudo ./scripts/install-commute-permission.sh
```

Uninstall:

```bash
sudo ./scripts/uninstall-commute-permission.sh
```

The installer writes `/etc/sudoers.d/desktopnumber-commute` allowing only:

- `/usr/bin/pmset -a disablesleep 1`
- `/usr/bin/pmset -a disablesleep 0`

## Office vs commute

| Scenario | What to use |
| --- | --- |
| Office, plugged in, Ctrl+Cmd+Q lock screen | macOS Battery setting **Prevent automatic sleeping on power adapter when the display is off** — check status in the menu |
| Commute, lid closed, local Cursor agent | **Commute mode** in the menu (90-minute limit) |
| Safest closed-lid workflow | Cursor **Cloud Agent** — laptop can sleep |

Commute mode does **not** use `caffeinate`. That tool does not prevent sleep when the lid is closed.

## Cursor agent notifications (optional)

Send push notifications via [ntfy.sh](https://ntfy.sh) when a local Cursor agent finishes or needs your approval.

There are two push paths:

| Notification | How it works | DesktopNumber must be running? |
| --- | --- | --- |
| Agent finished | Cursor `stop` hook in `~/.cursor/hooks/` | No (Cursor runs the hook) |
| Approve needed | DesktopNumber log monitor tails Cursor logs | Yes |

Install from the DesktopNumber menu by enabling **Push when agent finishes** or **Push when approve needed**, or from the terminal:

```bash
./scripts/install-cursor-notify-hooks.sh
```

Uninstall:

```bash
./scripts/uninstall-cursor-notify-hooks.sh
```

The installer:

- copies hook scripts to `~/.cursor/hooks/`
- merges the `stop` hook into `~/.cursor/hooks.json` (backs up any existing file first)
- removes leftover DesktopNumber `beforeShellExecution` / `beforeMCPExecution` hooks if a previous version installed them
- creates `~/.cursor/hooks/notify.env` from `notify.env.example` (set your ntfy topic there)
- sends a test push when `NTFY_TOPIC` is configured

Set your ntfy topic in the menu **ntfy topic** field or in `~/.cursor/hooks/notify.env`:

```bash
NTFY_TOPIC=your-topic-name
NTFY_ENABLED=1
NTFY_APPROVE_ENABLED=1
```

Send a test push from the menu (**Send Test Push**) or via the install script when `NTFY_TOPIC` is already set.

Enable or disable push notifications from the DesktopNumber menu bar toggles:

- **Push when agent finishes** — installs or removes the Cursor `stop` hook and writes `NTFY_ENABLED=1` or `0`
- **Push when approve needed** — starts or stops DesktopNumber log monitoring and writes `NTFY_APPROVE_ENABLED=1` or `0`

No Cursor restart is required for toggle changes. After installing or updating hooks, restart Cursor once and verify them in **Customize → Hooks**. If finish notifications do not arrive, open the **Hooks** output channel for errors.

**Approve coverage:** DesktopNumber does **not** install `beforeShellExecution` or `beforeMCPExecution` hooks, so Cursor's native shell and MCP approval prompts stay in control. Approve pushes come only from the log monitor (`Shell permissions: requesting shell approval`, sandbox shell runs with `allCommandsPreapproved` + not allowlisted, and `shouldBlockMcp: needsApproval`). Shell approvals wait briefly for Cursor's approval gate outcome, so auto-rejected or auto-allowed commands do not trigger a push.

After updating DesktopNumber, launch the app once. It auto-migrates hook scripts in `~/.cursor/hooks/` on startup. If the menu shows that hooks were updated, restart Cursor once.

## Commute mode safety

When commute mode is enabled, the app and an embedded `CommuteFailsafe` helper monitor:

- **90-minute timer** — auto-disable after 90 minutes
- **Battery ≤ 20% on battery power** — auto-disable so the Mac can sleep
- **Thermal pressure (`serious` / `critical`)** — auto-disable so the Mac can sleep and cool down; finish the task at home
- **App quit** — disables commute mode on normal quit
- **Fail-safe helper** — if the menu app crashes, the helper still disables sleep when limits are hit

**Risks:** heat buildup in a bag, faster battery drain, and interrupted agent tasks after automatic shutdown. Do not leave commute mode running indefinitely.

## Launch at login (optional)

1. Open **System Settings** → **General** → **Login Items & Extensions** → **Open at Login**.
2. Click **+** and select `DesktopNumber.app`.

Alternatively, you can copy the app to `/Applications` and add it from there.

## Scripts

All scripts live in `scripts/` and should be run from the repo root:

| Script | Purpose |
| --- | --- |
| `./scripts/build-and-open-desktop-number.sh` | Build Release and open the app |
| `./scripts/install-commute-permission.sh` | Install commute-mode sudoers entry (run with `sudo`) |
| `./scripts/uninstall-commute-permission.sh` | Remove commute-mode sudoers entry (run with `sudo`) |
| `./scripts/install-cursor-notify-hooks.sh` | Install Cursor notify hooks into `~/.cursor/` |
| `./scripts/uninstall-cursor-notify-hooks.sh` | Remove DesktopNumber Cursor notify hooks |

## Manual build

If you prefer not to use the build script, from the repo root:

```bash
xcodebuild -scheme DesktopNumber -configuration Release -derivedDataPath build build
open build/Build/Products/Release/DesktopNumber.app
```

When building from Xcode (without `-derivedDataPath build`), check the path in the `xcodebuild` log.

## Testing

```bash
xcodebuild -scheme DesktopNumber -configuration Debug -derivedDataPath build test
```

Unit tests use mocks and do not change system power settings.

## Notes

- The app uses private CoreGraphics APIs (`CGSCopyManagedDisplaySpaces`) to detect desktops — a common approach in tools like this, but the API may change in future macOS versions.
- Desktop order is sorted according to the visual layout from Mission Control (file `~/Library/Preferences/com.apple.spaces.plist`).
- Cursor usage is read from the local Cursor session database (`~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`) and fetched from Cursor's dashboard API. You must be logged into Cursor on the same Mac.
- The Cursor usage API is unofficial and may change without notice. If usage cannot be loaded, the desktop number still works and the menu shows the error.
