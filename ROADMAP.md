# Roadmap

## v1
- [x] 1. Scaffold + go/no-go spike on the private Touch Bar APIs
- [x] 2. Session model, hook payload, reducer
- [x] 3. Session store + `touchbuddy-hook` CLI
- [x] 4. Session view logic
- [x] 5. Hook installer for `settings.local.json` (superseded by 13b; only the owner-initiated legacy removal remains)
- [x] 6. Speech templates
- [x] 7. Character format, discovery, frame decoding
- [x] 8. Built-in original characters
- [x] 8b. Six more built-in characters
- [x] 9. App shell: watcher, Control Strip icon, status menu, preferences
- [x] 10. Dashboard, auto-popup, speech, TTS
- [x] 11. Jump to session
- [x] 12. Quick replies from the Touch Bar
- [x] 12b. Chatty mode (wandering avatar and random updates)
- [x] 13b. Hooks shipped as a local Claude Code plugin (`touchbuddy@touchbuddy-local`), versioned by hooks.json content hash
- [x] CI and release adoption: ci.yml, release-please, vendored ci-toolkit v1.3.0 AI/Dependabot workflows, universal release builds
- [x] 13. Signing, install, end-to-end verification
- [x] Final-review fix wave: needs-input survives parallel tool calls, one popup per prompt, safe iTerm focus fallbacks, bounded AppleScript, speech decay, dead installer code removed

See `docs/superpowers/plans/2026-11-11-touchbuddy.md` for task definitions.

## Known limitations
- After a keyboard approval the session stays orange until the tool finishes (no hook fires on approval).
- Quick replies are hidden while more than one tool call is in flight (fail closed).
- Desktop-app chats are not tracked.
- tmux / SSH sessions only bring iTerm forward; they cannot be targeted individually.
- AppleScript runs on the main thread (bounded by 5 s timeouts).

## Stretch
- Desktop-app chats
- tmux / SSH jump
- In-app update check against GitHub Releases (post-v1)
