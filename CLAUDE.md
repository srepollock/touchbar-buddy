# TouchBuddy

Menu-bar macOS app (Swift 6, SwiftPM) that shows Claude Code session status in the Touch Bar Control Strip. Design: `docs/superpowers/specs/2026-11-11-touchbuddy-design.md`. Plan: `docs/superpowers/plans/`.

## Commands

- Test: `swift test`
- Build app bundle: `scripts/build-app.sh [debug|release]` -> `build/TouchBuddy.app`
- Run: `open build/TouchBuddy.app`; quit: `pkill -x TouchBuddy`
- Signing: identity `$TOUCHBUDDY_SIGN_IDENTITY` (default "TouchBuddy Local Signing"); falls back to ad-hoc with a warning.

## Environment

- `TOUCHBUDDY_CHATTY_SECONDS=<n>`: overrides the Chatty mode interval (seconds, +/-30% jitter) for testing ambient strolls.

## Layout

- `Sources/TouchBarPrivate` - ObjC shim over private DFRFoundation / NSTouchBar system-modal APIs (resolved via dlopen/dlsym, no-ops if unavailable)
- `Sources/TouchBuddyCore` - testable logic library
- `Sources/TouchBuddy` - the menu-bar app
- `Sources/touchbuddy-hook` - Claude Code hook executable
- `Sources/sprite-gen` - sprite generator
- `Resources/` - Info.plist, Characters
- `Tests/TouchBuddyCoreTests` - Swift Testing

## Rules

- Never touch `~/.claude/settings.json` or `settings.local.json`.
- No `print` in shipped code; use `os.Logger` (subsystem `ca.spollock.touchbuddy`).
- Conventional commits.

## Logs

`/usr/bin/log show --last 5m --info --predicate 'subsystem == "ca.spollock.touchbuddy"'`
(use the full path; `log` is shadowed in zsh)
