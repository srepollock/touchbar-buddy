# TouchBuddy

Menu-bar macOS app (Swift 6, SwiftPM) that shows Claude Code session status in the Touch Bar Control Strip. Design: `docs/superpowers/specs/2026-11-11-touchbuddy-design.md`. Plan: `docs/superpowers/plans/`.

## Commands

- Test: `swift test`
- Build app bundle: `scripts/build-app.sh [debug|release]` -> `build/TouchBuddy.app`
- Run: `open build/TouchBuddy.app`; quit: `pkill -x TouchBuddy`
- Install: `scripts/make-signing-identity.sh` once (owner runs it; keychain prompts), then `scripts/build-app.sh install` = release build + sign + copy to `/Applications/TouchBuddy.app` + relaunch. Install refuses ad-hoc signed builds.
- Signing: identity `$TOUCHBUDDY_SIGN_IDENTITY` (default "TouchBuddy Local Signing"); falls back to ad-hoc with a warning.

## Environment

- `TOUCHBUDDY_CHATTY_SECONDS=<n>`: overrides the Chatty mode interval (seconds, +/-30% jitter) for testing ambient strolls.

## Hooks

- Hooks ship as a local Claude Code plugin: on every launch the app writes a marketplace (`touchbuddy-local`) + plugin (`touchbuddy`) to `<TOUCHBUDDY_HOME or ~/Library/Application Support/TouchBuddy>/claude-plugin` (`ClaudePlugin`, idempotent). Claude Code 2.1.323 ignores hooks in `~/.claude/settings.local.json`. The owner installs once via menu "Set up Claude Code plugin…" (`claude plugin marketplace add "<dir>"`, `claude plugin install touchbuddy@touchbuddy-local`). After any change to the hooks (events, command), relaunch the app so it rewrites the plugin, then run `claude plugin update touchbuddy@touchbuddy-local` and restart Claude Code sessions. The plugin version is `<CFBundleShortVersionString>+<first 8 hex of SHA-256 of hooks.json>`; Claude Code compares versions by string equality, so the hash makes every hooks change an update. Events: SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, PostToolUseFailure, PermissionRequest, Notification, Stop, SessionEnd. Validate with `claude plugin validate --strict <dir>`.
- Menu status reads `~/.claude/plugins/installed_plugins.json` (read-only). "Remove old settings.local.json hooks" appears only while legacy hooks remain there (`HookInstaller`, timestamped backup). TouchBuddy never writes `~/.claude`, except the owner-initiated legacy removal of `settings.local.json` hooks.
- Session lock files open with `O_NOFOLLOW`; a symlinked lock path is refused and the hook proceeds unlocked.
- Quick replies (Allow/Deny/choices) are offered only when exactly one tool call is in flight; with several, the bubble shows the PermissionRequest's own label but no buttons.

## Layout

- `Sources/TouchBarPrivate` - ObjC shim over private DFRFoundation / NSTouchBar system-modal APIs (resolved via dlopen/dlsym, no-ops if unavailable)
- `Sources/TouchBuddyCore` - testable logic library
- `Sources/TouchBuddy` - the menu-bar app
- `Sources/touchbuddy-hook` - Claude Code hook executable
- `Sources/sprite-gen` - sprite generator
- `Resources/` - Info.plist, Characters
- `Tests/TouchBuddyCoreTests` - Swift Testing

## Rules

- Never touch `~/.claude/settings.json` or `settings.local.json`, except the owner-initiated legacy hook removal from `settings.local.json` (menu item, with backup).
- No `print` in shipped code; use `os.Logger` (subsystem `ca.spollock.touchbuddy`).
- Conventional commits.

## Logs

`/usr/bin/log show --last 5m --info --predicate 'subsystem == "ca.spollock.touchbuddy"'`
(use the full path; `log` is shadowed in zsh)
