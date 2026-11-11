# TouchBuddy — Claude Code status on the MacBook Pro Touch Bar

Date: 2026-11-11
Status: Draft for review

## Intent

The owner runs several Claude Code sessions at once in iTerm and loses track of which one is waiting on them. Today their Touch Bar does almost nothing beyond the Control Strip (play/pause, volume, mute, screensaver, expanded strip for keyboard brightness). TouchBuddy turns the Touch Bar into a **glanceable dashboard** of Claude Code session state, fronted by an animated avatar that speaks on Claude's behalf, without taking away the controls they already use.

Success: the owner never has to cycle through terminal tabs to find the session that's blocked on them — the Touch Bar tells them, and one tap takes them there.

## Target environment (verified)

- MacBook Pro 16" 2019 (`MacBookPro16,1`, Intel i7-9750H), Touch Bar present, `TouchBarServer` running
- macOS 26.6.2 (Tahoe)
- Terminal: iTerm2 (`TERM_PROGRAM=iTerm.app`); Claude desktop app (`Claude.app`) also installed
- Toolchain: Swift 6.3.2, `xcodebuild` available
- `~/.claude/settings.json` already defines hooks for `PreToolUse`, `PostToolUse`, `Notification`, `SessionStart`, `UserPromptSubmit`. **It is synced across machines from the owner's dotfiles — TouchBuddy must never write to it.**
- Touch Bar setting: "Touch Bar shows: App Controls" with the Control Strip shown (collapsed strip on the right, expandable via the arrow). This is the mode in which a DFRFoundation Control Strip item appears; the go/no-go spike must confirm it.

## Goals

1. Show the live state of every running Claude Code session: **needs input**, **working**, **finished**, **idle**.
2. Keep the owner's existing Control Strip intact; TouchBuddy adds **one** item to it.
3. Pop the full dashboard open automatically **only** when a session needs input; otherwise stay out of the way.
4. An animated avatar delivers a short, factual status line with a bit of character flair.
5. Avatars are customizable: several original characters ship built in; the owner can add their own (e.g. Gengar, Gabumon) by dropping sprite files into a folder.
6. Optional text-to-speech for the avatar's lines.

## Non-goals

- Mac App Store distribution (private Touch Bar APIs rule it out; this is a personal tool).
- Tracking plain chat conversations in the Claude desktop app or claude.ai — there's no reliable signal. Stretch goal only; do not build in v1.
- Re-implementing media/volume/brightness controls. The native Control Strip stays as-is.
- Shipping any Pokémon/Digimon or other third-party copyrighted art.
- LLM-generated speech. Lines come from per-character templates.
- Any network access.

## Anti-goals (would make this a failure even if it "works")

- Breaking, hiding, or replacing the owner's existing Touch Bar controls when the dashboard is not open.
- Clobbering or reordering the owner's existing Claude Code hooks.
- Slowing Claude Code down: hook invocations must be near-instant, never block, and always exit 0, even if TouchBuddy isn't running.
- Popping up for anything that isn't "needs input" (no popups for "finished", tool calls, etc.).
- Ghost sessions that linger forever after a terminal is closed.

## User-facing behaviour (decided with the owner)

### Resting state
The Touch Bar looks exactly like today. One TouchBuddy icon sits in the Control Strip. Its colour reflects the most urgent session state:

| State | Colour | Meaning |
|---|---|---|
| needs input | orange (pulses) | permission prompt, question, or other blocking request |
| working | blue | Claude is processing / running tools |
| finished | green | Claude stopped and handed back to the user |
| idle | grey | session open, nothing recent |

A small badge shows the count of active sessions.

### Auto-popup (option C — chosen by owner)
When any session **transitions into** needs-input, TouchBuddy presents its dashboard over the whole Touch Bar: avatar (animated, "needs input" animation) + speech bubble + session chips. It auto-dismisses after a few seconds (default 8s, configurable) or immediately on tap of ✕. Only the needs-input transition triggers a popup.

### Manual open
Tapping the Control Strip icon opens the same dashboard with all sessions. ✕ closes it and restores the normal bar.

### Session chips
One chip per session: status dot + project name (basename of the session's cwd), sorted most-urgent first. If they don't fit, the chip area scrolls horizontally. **Tapping a chip focuses that session's iTerm tab** (or activates Claude.app if the session came from the desktop app's Code tab).

### Speech
- Facts first, with character flair. Example: `Psst — touchbar-app wants to run bun test. Your call 👀`
- Text scrolls (marquee) if it's longer than the bubble.
- **TTS toggle, off by default.** When on, the line is spoken with macOS speech synthesis on popup.

### Avatars
- Ship **4 original, fully animated characters**, each with a looping animation per state (needs input, working, finished, idle). Default is an original Claude-inspired mascot (warm orange, pixel-art style). Concepts for the other three are the builder's call, but they must be original designs (not lookalikes of existing franchises) and visually distinct from each other.
- Users can add custom characters by dropping a folder into `~/Library/Application Support/TouchBuddy/Characters/`. Custom characters appear in the picker alongside built-ins.
- Each character has its own speech templates (personality). A custom character without templates falls back to the default character's lines.

## How it's built (builder's calls, explained to and accepted by owner)

### App shape
- Native **Swift / AppKit** app, menu-bar only (`LSUIElement`), no Dock icon.
- Uses the private `DFRFoundation` / `NSTouchBar` system-modal APIs (the same approach MTMR and Pock use) to (a) add a Control Strip item and (b) present a system-modal Touch Bar over all apps. Expose them through a small Objective-C bridging header.
- Menu-bar menu provides: character picker, TTS toggle, popup duration, launch at login (`SMAppService`), install/uninstall hooks, "open characters folder", quit.

### Getting status from Claude Code
A small CLI helper (`touchbuddy-hook`, shipped inside the app bundle, same Swift package so it shares the state model) is registered as the command for Claude Code hooks. It reads the hook JSON from stdin, maps it to a state, and writes `~/Library/Application Support/TouchBuddy/sessions/<session_id>.json` atomically (write temp + rename). The app watches that directory. File-based handoff means state survives the app being restarted and the hook never depends on the app being up.

Event → state mapping:

| Hook event | Resulting state | Notes |
|---|---|---|
| `SessionStart` | idle | record cwd, iTerm session id, PID |
| `UserPromptSubmit` | working | |
| `PreToolUse` | working, except `AskUserQuestion` → **needs input** | record tool name / short summary for speech |
| `PostToolUse` | working | |
| `Notification` (permission prompt / elicitation) | **needs input** | use the notification message text in speech |
| `Notification` (idle reminder) | no state change | must not trigger a popup |
| `Stop` | finished | |
| `SessionEnd` | remove session file | |

Finished decays to idle after a quiet period (builder's call, e.g. 10 min).

The helper also records `ITERM_SESSION_ID` and the parent Claude PID. The app prunes sessions whose PID is gone (no ghost sessions).

### Hook installation
"Install hooks" in the menu merges TouchBuddy's entries into **`~/.claude/settings.local.json`** (owner's decision: `settings.json` is dotfile-synced and must not be touched). Create the file if missing; back it up first if present; append to existing per-event arrays (never replace); idempotent (re-running doesn't duplicate); "Uninstall hooks" removes only TouchBuddy's entries. If `settings.local.json` is a symlink, write through to its target rather than replacing the link. TouchBuddy entries are identified by their command path so uninstall can find them.

### Jumping to a session
Use AppleScript against iTerm2 to select the session whose unique id matches the recorded `ITERM_SESSION_ID`. Falls back to just activating iTerm if not found. Requires the macOS Automation permission for iTerm, requested on first use.

### Speech templates
Per-character JSON: a list of lines per event type with placeholders (`{project}`, `{tool}`, `{detail}`); pick one at random. Pure function, unit-tested.

### Custom character format
```
Characters/<name>/
  character.json      # display name, fps, optional voice, optional speech templates
  needs_input.gif     # or needs_input/ folder of numbered PNG frames
  working.gif
  finished.gif
  idle.gif
```
Missing state animations fall back to `idle`. Sprites are scaled to fit the ~30pt-tall bar, with nearest-neighbour scaling for pixel art.

### Built-in art
Built-ins are produced by the builder as original pixel-art frame sequences (e.g. generated from code-defined pixel grids and exported to PNG frames at build time, or drawn at runtime) — builder's call, as long as they're genuinely animated per state.

## Calls made by the designer (owner to sanity-check)

- **Go/no-go spike first.** The plan opens with a minimal app that adds a Control Strip item and presents/dismisses a system-modal Touch Bar on this exact machine (macOS 26.6, Intel). If the private APIs don't work, stop and return to the owner — do not silently fall back to another design.
- **Stable signing identity.** Sign with a stable local self-signed code-signing certificate (or Developer ID if one exists), not ad-hoc, so the iTerm Automation permission and launch-at-login survive rebuilds.
- **Desktop app Code tab sessions: best effort.** If they fire hooks from the user-level settings, they appear like any other session; detect them by the absence of `ITERM_SESSION_ID` (plus any entrypoint env var Claude Code exposes) and have their chip activate Claude.app. Not a v1 acceptance criterion.
- **Jump-to-session is local-iTerm only.** For sessions inside tmux or over SSH, the chip just activates iTerm; status still shows wherever hooks run locally.
- **Hook helper path.** Hooks point at the helper inside `/Applications/TouchBuddy.app`; the hook command must exit 0 silently if the helper is missing (e.g. app deleted).

## Quality bar

- Unit tests for: hook-event → state reducer, settings.json merge/unmerge (including the owner's existing hook shape), template rendering, character folder loading/fallbacks, stale-session pruning.
- Manual verification on the real Touch Bar: Control Strip icon visible in other apps; popup on a real permission prompt in a live Claude Code session; auto-dismiss; ✕ restores the native bar; chip tap focuses the right iTerm tab.
- Hook helper performance: measure wall time; target well under 50ms.
- Project follows the owner's conventions: `trunk` branch, conventional commits, `CLAUDE.md` + `ROADMAP.md` maintained.

## Left to the builder

- App name in code/bundle id (working name "TouchBuddy").
- The three non-default character concepts and all sprite art.
- Exact colours, timings, fonts, chip sizing, marquee speed.
- Build tooling (SwiftPM + bundle script vs. an Xcode project), as long as there's a one-command build that produces a runnable `.app`.
