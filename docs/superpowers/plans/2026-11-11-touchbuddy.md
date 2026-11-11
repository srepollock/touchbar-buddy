# TouchBuddy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A menu-bar macOS app that shows live Claude Code session status in the Touch Bar Control Strip, pops an animated-avatar dashboard when a session needs input, and jumps to the session's iTerm tab on tap.

**Architecture:** One SwiftPM package. A pure-Swift `TouchBuddyCore` library holds every decision (hook-event reducer, session store, view logic, hook installer, speech templates, character loading) and is unit-tested. A tiny `touchbuddy-hook` CLI is the Claude Code hook command; it writes one JSON file per session. The `TouchBuddy` AppKit app watches that directory and drives the Touch Bar through an Objective-C shim (`TouchBarPrivate`) over private DFRFoundation/NSTouchBar APIs. `scripts/build-app.sh` assembles and signs `TouchBuddy.app`.

**Tech Stack:** Swift 6.3 (language mode 6), SwiftPM, AppKit, ImageIO, AVFoundation (TTS), ServiceManagement (launch at login), os.Logger, Swift Testing (`import Testing`), Objective-C (private API shim), Bash (build scripts).

**Spec:** `docs/superpowers/specs/2026-11-11-touchbuddy-design.md`

## Global Constraints

- Target: macOS 26.6, Intel `MacBookPro16,1`; `Package.swift` platform `.macOS(.v14)`; build for the host arch.
- **Never write to `~/.claude/settings.json`.** Hooks go only in `~/.claude/settings.local.json`.
- Hook command must be fast (target < 50 ms wall time), never block, and **always exit 0**, including when the helper binary is missing, stdin is empty, or JSON is malformed.
- Only the transition **into** `needs_input` pops the dashboard. Nothing else pops it.
- TTS **off by default**. Popup auto-dismiss default **8 s**. `finished` decays to `idle` after **600 s**.
- State colours: needs input orange `#F5A623` (pulses), working blue `#4A90E2`, finished green `#7ED321`, idle grey `#666666`.
- App is `LSUIElement` (no Dock icon). Bundle id `ca.spollock.touchbuddy`. Installed path `/Applications/TouchBuddy.app`.
- Data root: `~/Library/Application Support/TouchBuddy/` (`sessions/`, `Characters/`), overridable with env `TOUCHBUDDY_HOME` (tests and the hook helper both honour it).
- No network access. No `print` in shipped code; use `os.Logger(subsystem: "ca.spollock.touchbuddy", category: …)`.
- No third-party copyrighted art in the repo. Built-in characters are original.
- Quick replies type only whitelisted keystrokes into the exact iTerm session, and only after re-validating the session is still in needs input and unchanged.
- Conventional commits on `trunk`; each task ends with one commit. Update `ROADMAP.md` checkboxes as tasks land (Task 13 adds the new Task 12 "Quick replies" line).

## Review Focus

1. **Malformed hook input** (empty stdin, non-JSON, unknown `hook_event_name`, missing `session_id`) → helper exits 0 and writes nothing. Test in Task 3.
2. **Torn or corrupt session file** (two hooks racing, a crash mid-write) → writes are atomic and `loadAll` skips unreadable files instead of failing the whole load. Test in Task 3.
3. **`settings.local.json` is invalid JSON, or has unrelated keys** (`permissions`, `env`) → install refuses to touch invalid JSON and preserves every unrelated key byte-for-byte in meaning. Test in Task 5.
4. **Many sessions or long project names** (8+ sessions, 60-char directory names) → chip titles truncate with `…` and chips scroll. Test in Task 4.
5. **Broken custom character** (missing `idle`, corrupt GIF) or the selected character being deleted → it's skipped from the picker and selection falls back to the default `sparky`. Test in Task 7.

---

## File Structure

```
Package.swift
CLAUDE.md, ROADMAP.md
scripts/build-app.sh              # swift build + assemble + sign .app
scripts/make-signing-identity.sh  # one-time self-signed code-signing cert
Resources/Info.plist
Resources/Characters/<id>/{character.json, idle/, working/, needs_input/, finished/}
Sources/TouchBarPrivate/          # ObjC shim over private APIs
  include/TouchBarPrivate.h
  TouchBarPrivate.m
Sources/TouchBuddyCore/
  SessionModel.swift      # SessionState, SessionRecord
  HookPayload.swift       # Decodable hook stdin
  SessionReducer.swift    # payload + existing record -> update
  SessionStore.swift      # paths, atomic read/write/delete
  ProcessInfoLookup.swift # ancestor PID lookup, liveness
  SessionViewLogic.swift  # decay, ordering, overall state, popup triggers, pruning, chip titles
  JSONValue.swift
  HookInstaller.swift     # settings.local.json merge/unmerge
  SpeechTemplates.swift
  Characters.swift        # manifest, loader, discovery, selection fallback
  AnimationFrames.swift   # GIF / PNG-folder decoding
Sources/touchbuddy-hook/main.swift
Sources/sprite-gen/       # generates built-in character PNG frames (dev tool)
  main.swift, Sprites+<id>.swift
Sources/TouchBuddy/
  main.swift, AppDelegate.swift
  Preferences.swift
  SessionWatcher.swift
  ControlStripController.swift
  DashboardController.swift
  SpriteView.swift, MarqueeLabel.swift
  Speaker.swift
  SessionFocuser.swift
  StatusMenu.swift
Tests/TouchBuddyCoreTests/*.swift
```

---

### Task 1: Scaffold + go/no-go spike on the private Touch Bar APIs

The whole design depends on this. If it fails, **stop and report to the owner**. Do not fall back to another design.

**Files:**
- Create: `Package.swift`, `Sources/TouchBarPrivate/include/TouchBarPrivate.h`, `Sources/TouchBarPrivate/TouchBarPrivate.m`, `Sources/TouchBuddy/main.swift`, `Sources/TouchBuddy/AppDelegate.swift`, `Sources/TouchBuddyCore/SessionModel.swift` (empty placeholder type ok), `Tests/TouchBuddyCoreTests/SmokeTests.swift`, `Resources/Info.plist`, `scripts/build-app.sh`, `CLAUDE.md`, `ROADMAP.md`

**Interfaces:**
- Produces (ObjC, visible to Swift as `import TouchBarPrivate`):
  ```objc
  void TBPSetControlStripPresence(NSString *identifier, BOOL present);
  void TBPShowCloseBoxWhenFrontMost(BOOL show);
  void TBPAddSystemTrayItem(NSTouchBarItem *item);
  void TBPRemoveSystemTrayItem(NSTouchBarItem *item);
  void TBPPresentSystemModal(NSTouchBar *bar, NSString *trayIdentifier);
  void TBPMinimizeSystemModal(NSTouchBar *bar);
  void TBPDismissSystemModal(NSTouchBar *bar);
  BOOL TBPPrivateAPIsAvailable(void);
  ```
- Produces: `scripts/build-app.sh [debug|release]` → `build/TouchBuddy.app`; signs with identity `$TOUCHBUDDY_SIGN_IDENTITY` (default `"TouchBuddy Local Signing"`) if it exists in `security find-identity -p codesigning`, else ad-hoc (`-`) with a warning on stderr.

- [ ] **Step 1: Write `Package.swift`**: tools-version 6.0; products and targets `TouchBarPrivate` (ObjC, links `AppKit`), `TouchBuddyCore` (library), `TouchBuddy` (executable; deps Core + TouchBarPrivate), `touchbuddy-hook` (executable; dep Core), `sprite-gen` (executable; dep Core), test target `TouchBuddyCoreTests`. Leave `touchbuddy-hook/main.swift` and `sprite-gen/main.swift` as one-line stubs until their tasks.

- [ ] **Step 2: Implement the shim in `TouchBarPrivate.m`.** Resolve the C functions `DFRElementSetControlStripPresenceForIdentifier` and `DFRSystemModalShowsCloseBoxWhenFrontMost` with `dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_LAZY)` + `dlsym`. Don't link the framework, because the SDK ships no `.tbd` for it. Call the class methods `+[NSTouchBarItem addSystemTrayItem:]`, `+[NSTouchBarItem removeSystemTrayItem:]`, `+[NSTouchBar presentSystemModalTouchBar:systemTrayItemIdentifier:]`, `+[NSTouchBar minimizeSystemModalTouchBar:]` and `+[NSTouchBar dismissSystemModalTouchBar:]` through `respondsToSelector:` guards, and declare them in a private category in the `.m`. `TBPPrivateAPIsAvailable` returns YES only if both symbols resolved and all five selectors respond. Each wrapper is a no-op when unavailable.

- [ ] **Step 3: Write the spike app.** `AppDelegate` (`@MainActor`):
  - Call `NSApplication.shared.setActivationPolicy(.accessory)`.
  - Create an `NSCustomTouchBarItem(identifier: "ca.spollock.touchbuddy.strip")` with an orange `NSButton` titled "TB".
  - Call `TBPAddSystemTrayItem`, then `TBPSetControlStripPresence(id, true)`.
  - Tapping the button presents a modal `NSTouchBar` holding one label, "TouchBuddy spike ✅", via `TBPShowCloseBoxWhenFrontMost(true)` and `TBPPresentSystemModal(bar, id)`.
  - It minimizes after 8 s.
  - At launch, log `TBPPrivateAPIsAvailable()` with os.Logger.

- [ ] **Step 4: Write `Resources/Info.plist`** (`CFBundleIdentifier` `ca.spollock.touchbuddy`, `CFBundleExecutable` `TouchBuddy`, `LSUIElement` true, `LSMinimumSystemVersion` 14.0, `NSAppleEventsUsageDescription` "TouchBuddy brings the Claude Code session you tap to the front in iTerm.") and **`scripts/build-app.sh`**, which:
  - runs `swift build -c <cfg>`;
  - creates `build/TouchBuddy.app/Contents/{MacOS,Resources}`;
  - copies the `TouchBuddy` and `touchbuddy-hook` binaries into `MacOS/`, `Info.plist` into `Contents/`, and `Resources/Characters` into `Resources/Characters` if it exists;
  - runs `codesign --force --deep --options runtime --sign <identity>`.

  Use `set -euo pipefail`.

- [ ] **Step 5: Add a smoke test and run it.** `@Test func packageBuilds() { #expect(true) }`. Run `swift test`. Expected: 1 test passed.

- [ ] **Step 6: Build and launch the spike.** Run `scripts/build-app.sh debug && open build/TouchBuddy.app`. Expected: the log shows the private APIs as available (`log show --last 1m --predicate 'subsystem == "ca.spollock.touchbuddy"'`).

- [ ] **Step 7: GO/NO-GO checkpoint with the owner.** Ask the owner to confirm three things on the physical Touch Bar, with "Touch Bar shows: App Controls" and the Control Strip on:
  1. An orange "TB" item is in the Control Strip while another app (e.g. Finder) is frontmost.
  2. Tapping it shows "TouchBuddy spike ✅" over the whole bar with a ✕.
  3. After 8 s, or on ✕, the normal bar comes back with media and volume controls intact.

  **If any of these fails, stop the plan and report.**

- [ ] **Step 8: Write `CLAUDE.md`** (build/test commands, layout, the "never touch settings.json" rule, how to read logs) **and `ROADMAP.md`** (v1 tasks 1–12 as a checklist; stretch: desktop-app chats, tmux/SSH jump). Commit:
  ```bash
  git add -A && git commit -m "feat(spike): scaffold package and prove private Touch Bar APIs"
  ```

---

### Task 2: Session model, hook payload, reducer

**Files:**
- Create: `Sources/TouchBuddyCore/SessionModel.swift`, `HookPayload.swift`, `SessionReducer.swift`
- Test: `Tests/TouchBuddyCoreTests/SessionReducerTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public enum SessionState: String, Codable, Sendable, CaseIterable { case needsInput = "needs_input", working, finished, idle }
  public enum SpeechKind: String, Codable, Sendable { case permission, question, working, finished, idle, allClear = "all_clear" }
  public struct SessionRecord: Codable, Equatable, Sendable {
    public var sessionID: String; public var cwd: String; public var projectName: String
    public var state: SessionState; public var speechKind: SpeechKind
    public var detail: String?          // tool summary or notification message
    public var toolName: String?
    public var updatedAt: Date; public var startedAt: Date
    public var claudePID: Int32?; public var itermSessionID: String?; public var entrypoint: String?
  }
  public struct HookPayload: Decodable, Sendable {   // snake_case keys from Claude Code
    public let sessionID: String; public let cwd: String?; public let hookEventName: String
    public let toolName: String?; public let toolInput: ToolInputSummary?
    public let message: String?; public let notificationType: String?
  }
  public struct ToolInputSummary: Decodable, Sendable { public let command: String?; public let filePath: String?; public let description: String? }
  public struct HookContext: Sendable { public let claudePID: Int32?; public let itermSessionID: String?; public let entrypoint: String?; public let now: Date }
  public enum SessionUpdate: Equatable, Sendable { case upsert(SessionRecord), delete(sessionID: String), unchanged }
  public func reduce(existing: SessionRecord?, payload: HookPayload, context: HookContext) -> SessionUpdate
  public func toolSummary(toolName: String?, input: ToolInputSummary?) -> String?
  ```

- [ ] **Step 1: Write failing tests** in `SessionReducerTests.swift`, one `@Test` each:
  - `sessionStartCreatesIdle`: `SessionStart` with cwd `/Users/x/projects/touchbar-app`. Expect `.upsert` with `state == .idle`, `projectName == "touchbar-app"`, and PID/iTerm id copied from the context.
  - `userPromptSubmitIsWorking` → `.working`, `speechKind == .working`.
  - `preToolUseBashIsWorkingWithSummary`: tool `Bash`, command `bun test`. Expect `.working`, `toolName == "Bash"`, `detail == "bun test"`.
  - `preToolUseAskUserQuestionNeedsInput` → `.needsInput`, `speechKind == .question`.
  - `postToolUseIsWorking` → `.working`.
  - `notificationPermissionNeedsInput`: `notificationType == "permission_prompt"`, message `"Claude needs your permission to use Bash"`. Expect `.needsInput`, `.permission`, and the detail is the message.
  - `notificationElicitationNeedsInput`: `"elicitation_dialog"` → `.needsInput`.
  - `notificationIdlePromptUnchanged`: `"idle_prompt"` → `.unchanged`.
  - `notificationWithoutTypeFallsBackToMessage`: nil type, message contains "permission" → `.needsInput`; nil type, message `"Claude is waiting for your input"` → `.unchanged`.
  - `stopIsFinished` → `.finished`, `.finished`.
  - `sessionEndDeletes` → `.delete(sessionID:)`.
  - `unknownEventUnchanged`: `"SubagentStop"` → `.unchanged`.
  - `eventWithoutExistingCreatesRecord`: `PreToolUse` with nil existing → upsert, `startedAt == now`.
  - `existingFieldsPreserved`: existing `startedAt` and `itermSessionID` survive an update when the context values are nil.
  - `toolSummaryTruncates`: a 120-char command → 40 chars ending in `…`; Edit with `filePath` `/a/b/main.swift` → `"main.swift"`; unknown tool with no input → the tool name.

- [ ] **Step 2: Run** `swift test --filter SessionReducerTests`. Expected: FAIL to compile (types undefined).

- [ ] **Step 3: Implement** the types and `reduce` / `toolSummary`. `HookPayload` uses explicit `CodingKeys` (`session_id`, `hook_event_name`, `tool_name`, `tool_input`, `notification_type`); `ToolInputSummary` uses `file_path`. `projectName` is `URL(fileURLWithPath: cwd).lastPathComponent`, or `"unknown"` when cwd is nil.

- [ ] **Step 4: Run** `swift test --filter SessionReducerTests`. Expected: all pass.

- [ ] **Step 5: Commit** `feat(core): add session model and hook event reducer`

---

### Task 3: Session store + `touchbuddy-hook` CLI

**Files:**
- Create: `Sources/TouchBuddyCore/SessionStore.swift`, `Sources/TouchBuddyCore/ProcessInfoLookup.swift`, `Sources/touchbuddy-hook/main.swift`
- Test: `Tests/TouchBuddyCoreTests/SessionStoreTests.swift`, `Tests/TouchBuddyCoreTests/HookRunnerTests.swift`

**Interfaces:**
- Consumes: Task 2 types and `reduce`.
- Produces:
  ```swift
  public struct TouchBuddyPaths: Sendable { public let root: URL; public var sessions: URL; public var characters: URL
    public static func resolve(environment: [String: String] = ProcessInfo.processInfo.environment) -> TouchBuddyPaths }
  public struct SessionStore: Sendable { public init(directory: URL)
    public func load(sessionID: String) -> SessionRecord?
    public func loadAll() -> [SessionRecord]          // skips unreadable/corrupt files
    public func write(_ record: SessionRecord) throws  // atomic: temp file in same dir + rename
    public func delete(sessionID: String) }
  public func runHook(stdin: Data, environment: [String: String], store: SessionStore, claudePID: Int32?, now: Date) -> Int32   // always returns 0
  public func findClaudeAncestorPID(startingAt pid: Int32) -> Int32?   // walk parents via sysctl KERN_PROC_PID; first whose p_comm is "claude" or "node"; else the grandparent
  public func isProcessAlive(_ pid: Int32) -> Bool                     // kill(pid, 0) == 0 || errno == EPERM
  ```
  The session filename is `<sessionID>.json`. Sanitise the session ID to `[A-Za-z0-9_-]`, and drop the payload if the result is empty.

- [ ] **Step 1: Write failing tests.**
  - `SessionStoreTests`:
    - `writeThenLoadRoundTrips`.
    - `loadAllSkipsCorruptFile`: write one valid record and one file containing `{"sessio`. Expect `loadAll().count == 1`.
    - `deleteRemovesFile`.
    - `pathsHonourTouchBuddyHome`: `TOUCHBUDDY_HOME=/tmp/x` → `sessions == /tmp/x/sessions`.
    - `sessionIDIsSanitised`: ID `../../etc` must never write outside the directory.
  - `HookRunnerTests`, all using a temp dir:
    - `emptyStdinReturnsZeroWritesNothing`.
    - `garbageStdinReturnsZeroWritesNothing`.
    - `missingSessionIDWritesNothing`.
    - `validPreToolUseWritesRecord`: env `ITERM_SESSION_ID=w0t1p0:ABCD-1234` and `CLAUDE_CODE_ENTRYPOINT=cli` are recorded.
    - `sessionEndDeletesFile`.

- [ ] **Step 2: Run** `swift test --filter "SessionStoreTests|HookRunnerTests"`. Expected: FAIL.

- [ ] **Step 3: Implement** the store, `runHook` (decode → `store.load` → `reduce` → apply; catch everything, log at `.debug`, return 0), and the process helpers. `main.swift` reads all of stdin, calls `runHook(… claudePID: findClaudeAncestorPID(startingAt: getppid()) …)`, then `exit(0)`.

- [ ] **Step 4: Run tests.** Expected: pass.

- [ ] **Step 5: Measure performance.** Run:

  ```bash
  swift build -c release
  echo '{"session_id":"perf","cwd":"/tmp","hook_event_name":"UserPromptSubmit"}' | TOUCHBUDDY_HOME=$(mktemp -d) /usr/bin/time -p .build/release/touchbuddy-hook
  ```

  Expected: `real` < 0.05, exit 0.

- [ ] **Step 6: Commit** `feat(hook): add session store and touchbuddy-hook CLI`

---

### Task 4: Session view logic

**Files:**
- Create: `Sources/TouchBuddyCore/SessionViewLogic.swift`
- Test: `Tests/TouchBuddyCoreTests/SessionViewLogicTests.swift`

**Interfaces:**
- Consumes: `SessionRecord`, `SessionState`.
- Produces:
  ```swift
  public let finishedDecaySeconds: TimeInterval = 600
  public let staleNoPIDSeconds: TimeInterval = 86_400
  public func effectiveState(_ r: SessionRecord, now: Date) -> SessionState          // finished older than 600s -> idle
  public func statePriority(_ s: SessionState) -> Int                                // needsInput 0, working 1, finished 2, idle 3
  public func orderedForDisplay(_ rs: [SessionRecord], now: Date) -> [SessionRecord] // priority asc, then updatedAt desc
  public func overallState(_ rs: [SessionRecord], now: Date) -> SessionState?        // nil when empty
  public func popupTriggers(old: [SessionRecord], new: [SessionRecord], now: Date) -> [SessionRecord] // effective needsInput in new AND (absent in old OR not needsInput in old OR updatedAt changed)
  public func partitionDead(_ rs: [SessionRecord], now: Date, isAlive: (Int32) -> Bool) -> (alive: [SessionRecord], deadIDs: [String]) // dead = PID not alive, or no PID and updatedAt older than 24h
  public func chipTitle(_ projectName: String, maxChars: Int = 18) -> String         // truncate with "…"
  ```

- [ ] **Step 1: Write failing tests:**
  - `finishedDecaysToIdleAfter600s`: at 599 s it's still finished; at 601 s it's idle.
  - `orderingIsUrgencyThenRecency`.
  - `overallIsMostUrgent`, `overallNilWhenEmpty`.
  - `popupOnTransitionIntoNeedsInput`.
  - `noPopupWhenStillNeedsInputUnchanged`.
  - `popupOnRepeatedPermissionPrompt`: same state, newer `updatedAt`.
  - `noPopupForFinished`.
  - `deadPIDPartitioned`.
  - `noPIDStaleAfter24h`.
  - `chipTitleTruncates`: a 60-char name → 18 chars ending in `…`; a short name is unchanged.
  - `orderingHandlesTwelveSessions`.

- [ ] **Step 2: Run** `swift test --filter SessionViewLogicTests`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Expected: pass.
- [ ] **Step 5: Commit** `feat(core): add session ordering, decay, popup and pruning logic`

---

### Task 5: Hook installer for `settings.local.json`

**Files:**
- Create: `Sources/TouchBuddyCore/JSONValue.swift`, `Sources/TouchBuddyCore/HookInstaller.swift`
- Test: `Tests/TouchBuddyCoreTests/HookInstallerTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public indirect enum JSONValue: Codable, Equatable, Sendable { case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null }
  public enum HookInstaller {
    public static let events = ["SessionStart","UserPromptSubmit","PreToolUse","PostToolUse","Notification","Stop","SessionEnd"]
    public static let marker = "touchbuddy-hook"
    public static func hookCommand(helperPath: String) -> String
      // exactly: "[ -x '<path>' ] && '<path>'; exit 0"
    public static func install(into settings: JSONValue, command: String) -> JSONValue   // append {"hooks":[{"type":"command","command":cmd,"timeout":5}]} per event, idempotent
    public static func uninstall(from settings: JSONValue) -> JSONValue                   // remove only groups whose commands contain marker; drop emptied event arrays and an emptied "hooks" object
    public static func isInstalled(in settings: JSONValue) -> Bool
    public static func installFile(at url: URL, command: String, now: Date) throws        // resolve symlinks; missing file -> start from {}; existing -> backup "<name>.touchbuddy-backup-<yyyyMMdd-HHmmss>"; invalid JSON -> throw HookInstallerError.invalidJSON, file untouched; atomic write, pretty-printed + sorted keys
    public static func uninstallFile(at url: URL, now: Date) throws
  }
  public enum HookInstallerError: Error, Equatable { case invalidJSON, notAnObject }
  ```
  ```swift
  public static func defaultSettingsURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL
     // $TOUCHBUDDY_CLAUDE_SETTINGS_LOCAL if set, else ~/.claude/settings.local.json
  ```
  `helperPath` is `/Applications/TouchBuddy.app/Contents/MacOS/touchbuddy-hook`. Add a test, `defaultSettingsURLHonoursOverride`.

- [ ] **Step 1: Write failing tests:**
  - `installIntoEmpty`: all 7 events are present.
  - `installPreservesExistingHooks`: use a fixture that mirrors the owner's shape, with existing `PreToolUse` and `Notification` groups using other commands. Expect them intact and ours appended after them.
  - `installPreservesUnrelatedKeys`: `permissions.allow` and `env` are unchanged.
  - `installIsIdempotent`: installing twice equals installing once.
  - `uninstallRemovesOnlyOurs`.
  - `uninstallDropsEmptiedHooksObject`.
  - `installFileCreatesMissingFile`.
  - `installFileBacksUpExisting`.
  - `installFileRefusesInvalidJSON`: the original bytes are unchanged and it throws `.invalidJSON`.
  - `installFileWritesThroughSymlink`: the link is still a symlink and the target is updated.
  - `hookCommandExitsZeroWhenMissing`: run `/bin/sh -c hookCommand(helperPath: "/nonexistent")` with `Process` and expect termination status 0.

- [ ] **Step 2: Run** `swift test --filter HookInstallerTests`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Expected: pass.
- [ ] **Step 5: Commit** `feat(core): add settings.local.json hook installer`

---

### Task 6: Speech templates

**Files:**
- Create: `Sources/TouchBuddyCore/SpeechTemplates.swift`
- Test: `Tests/TouchBuddyCoreTests/SpeechTemplatesTests.swift`

**Interfaces:**
- Consumes: `SessionRecord`, `SpeechKind`.
- Produces:
  ```swift
  public struct SpeechTemplates: Codable, Equatable, Sendable { public var lines: [SpeechKind: [String]] }  // JSON: {"permission": [...], "question": [...], ...}
  public func renderTemplate(_ template: String, values: [String: String]) -> String   // replaces {project} {tool} {detail}; unknown or missing placeholders become ""
  public func speechLine(for session: SessionRecord?, templates: SpeechTemplates, fallback: SpeechTemplates, pick: ([String]) -> String?) -> String
     // nil session -> .allClear; kind missing/empty in templates -> fallback's; empty everywhere -> factual default "{project}: {detail}"
  ```
  Whitespace collapses after rendering, so missing values don't leave double spaces.

- [ ] **Step 1: Write failing tests:**
  - `rendersPlaceholders`: `"Psst — {project} wants to run {detail}."` → `"Psst — touchbar-app wants to run bun test."`
  - `missingValueCollapsesWhitespace`.
  - `nilSessionUsesAllClear`.
  - `missingKindFallsBack`.
  - `emptyEverywhereUsesFactualDefault`.
  - `decodesFromJSONKeys`: the `"all_clear"` key maps to `.allClear`.

- [ ] **Step 2–4: Run (expect FAIL) → implement → run (expect pass).**
- [ ] **Step 5: Commit** `feat(core): add per-character speech templates`

---

### Task 7: Character format, discovery, frame decoding

**Files:**
- Create: `Sources/TouchBuddyCore/Characters.swift`, `Sources/TouchBuddyCore/AnimationFrames.swift`
- Test: `Tests/TouchBuddyCoreTests/CharactersTests.swift` (fixtures are generated in-test into a temp dir: write tiny PNGs and a 2-frame GIF with ImageIO)

**Interfaces:**
- Consumes: `SessionState`, `SpeechTemplates`.
- Produces:
  ```swift
  public struct CharacterManifest: Codable, Sendable { public var displayName: String; public var fps: Double?; public var voice: String?; public var speech: SpeechTemplates? }
  public enum AnimationSource: Equatable, Sendable { case gif(URL), frames([URL]) }   // frames sorted by numeric filename
  public struct CharacterDescriptor: Equatable, Sendable { public let id: String  // "builtin/<folder>" or "user/<folder>"
    public let manifest: CharacterManifest; public let animations: [SessionState: AnimationSource]  // every state present after idle fallback
    public func animation(for s: SessionState) -> AnimationSource }
  public enum CharacterError: Error, Equatable { case missingManifest, missingIdle, unreadable(String) }
  public func loadCharacter(at dir: URL, idPrefix: String) throws -> CharacterDescriptor
     // per state: "<state>.gif" or "<state>/" folder of *.png; idle required; other states fall back to idle
  public func discoverCharacters(builtInDir: URL, userDir: URL) -> [CharacterDescriptor]   // built-ins first, each sorted by displayName; invalid folders skipped + logged
  public func resolveSelectedCharacter(id: String?, available: [CharacterDescriptor], defaultID: String = "builtin/sparky") -> CharacterDescriptor?
  public struct AnimationFrame: @unchecked Sendable { public let image: CGImage; public let duration: TimeInterval }
  public func loadFrames(_ source: AnimationSource, fps: Double) throws -> [AnimationFrame]   // GIF uses per-frame delay (min 0.02s); PNG uses 1/fps; default fps 8
  ```

- [ ] **Step 1: Write failing tests:**
  - `loadsPNGFolderCharacter`.
  - `loadsGIFCharacter`.
  - `missingStatesFallBackToIdle`.
  - `missingIdleThrows`.
  - `missingManifestThrows`.
  - `discoverSkipsBrokenAndOrdersBuiltinsFirst`.
  - `resolveFallsBackToDefaultWhenSelectedDeleted`.
  - `resolveUsesFirstWhenDefaultMissing`.
  - `gifFramesDecodeWithDelays`: 2 frames with a 0.1 s delay.
  - `pngFramesSortedNumerically`: `2.png` comes before `10.png`.
  - `corruptGIFThrowsUnreadable`.

- [ ] **Step 2–4: Run (expect FAIL) → implement → run (expect pass).**
- [ ] **Step 5: Commit** `feat(core): add character loading and animation decoding`

---

### Task 8: Built-in original characters

**Files:**
- Create: `Sources/sprite-gen/main.swift`, `Sources/sprite-gen/Sprites+Sparky.swift`, `Sprites+Glitch.swift`, `Sprites+Moss.swift`, `Sprites+Nyx.swift`
- Create (generated, committed): `Resources/Characters/{sparky,glitch,moss,nyx}/character.json` and `{idle,working,needs_input,finished}/<n>.png`
- Test: `Tests/TouchBuddyCoreTests/BuiltInCharactersTests.swift`

**Interfaces:**
- Consumes: `loadCharacter`, `loadFrames`, `SpeechTemplates`.
- Produces: 4 character folders loadable by `discoverCharacters`, with ids `builtin/sparky` (default), `builtin/glitch`, `builtin/moss` and `builtin/nyx`.

Art rules:
- Each frame is a **24×24 pixel grid** with ≤ 8 palette colours and a transparent background. Define the grids in Swift as string arrays, one character per pixel and one palette char per colour.
- `sprite-gen` writes each grid scaled **×2 with nearest-neighbour** (48×48 PNG).
- Each state has **≥ 4 frames**:
  - idle: breathing or blinking;
  - working: busy motion (typing, spinning, gears);
  - needs_input: waving or bouncing, with a `!`;
  - finished: celebration jump.

Characters (designer's call; must be original):
- **Sparky** (default): a warm orange (`#D97757`) round blob with a white asterisk-sparkle on its head. Claude-inspired, friendly. Voice: upbeat and encouraging.
- **Glitch**: a tiny retro CRT-monitor robot whose screen shows its face. Voice: dry and terse.
- **Moss**: a little mushroom sprout. Voice: calm and cosy.
- **Nyx**: a small moth carrying a lantern. Voice: dramatic.

Each `character.json` has a `displayName`, `fps: 8`, and `speech` with ≥ 3 lines for every `SpeechKind`. **Every line must contain `{project}`**, plus `{detail}` for permission and question lines. Example for Sparky permission: `"Psst — {project} wants to {detail}. Your call! 👀"`.

- [ ] **Step 1: Write failing tests:**
  - `allBuiltinsLoad`: `discoverCharacters(builtInDir: <repo>/Resources/Characters, userDir: emptyTmp)` returns 4 characters, with `builtin/sparky` among them.
  - `everyStateHasAtLeast4Frames`: no idle fallback is used, and each state decodes ≥ 4 frames of size 48×48.
  - `everySpeechKindHas3LinesWithProject`.
  - `permissionAndQuestionLinesIncludeDetail`.

  Locate the repo with `#filePath`.

- [ ] **Step 2: Run** `swift test --filter BuiltInCharactersTests`. Expected: FAIL.
- [ ] **Step 3: Implement `sprite-gen`** (`swift run sprite-gen Resources/Characters` regenerates every frame and manifest) **and author the 4 characters' grids and lines.**
- [ ] **Step 4: Generate the art and run the tests.** Run `swift run sprite-gen Resources/Characters && swift test --filter BuiltInCharactersTests`. Expected: pass. Open a few PNGs (`open Resources/Characters/sparky/needs_input/1.png`) and check them visually; they should read as the described character.
- [ ] **Step 5: Commit** `feat(characters): add four original animated built-in characters`

---

### Task 9: App shell: watcher, Control Strip icon, status menu, preferences

**Files:**
- Create: `Sources/TouchBuddy/Preferences.swift`, `SessionWatcher.swift`, `ControlStripController.swift`, `StatusMenu.swift`
- Modify: `Sources/TouchBuddy/AppDelegate.swift` (replace the spike UI; keep the shim calls)

**Interfaces:**
- Consumes: `TouchBuddyPaths`, `SessionStore`, `orderedForDisplay`, `overallState`, `partitionDead`, `isProcessAlive`, `popupTriggers`, `HookInstaller`, `discoverCharacters`, `resolveSelectedCharacter`, and the `TBP*` shim.
- Produces:
  ```swift
  @MainActor final class Preferences { var characterID: String?; var ttsEnabled: Bool /*default false*/; var popupSeconds: Double /*default 8*/ }  // UserDefaults-backed
  @MainActor final class SessionWatcher { init(store: SessionStore); var onChange: (_ sessions: [SessionRecord], _ triggers: [SessionRecord]) -> Void; func start() }
     // DispatchSource on sessions dir (.write) + 2 s timer; each tick: loadAll -> partitionDead (delete dead files) -> orderedForDisplay -> popupTriggers vs previous -> onChange
  @MainActor final class ControlStripController { static let identifier = "ca.spollock.touchbuddy.strip"; init(onTap: @escaping () -> Void); func update(overall: SessionState?, count: Int) }
     // NSCustomTouchBarItem showing the selected character (SpriteView playing character.animation(for: overall ?? .idle), aspect-fit to the strip height) on a status-coloured ring + count badge; needsInput ring pulses (alpha 0.4<->1.0, 0.8 s). init gains `character: CharacterDescriptor`, plus `func setCharacter(_ c: CharacterDescriptor)` called when the menu selection changes. SpriteView is created here in Task 9 (Task 10 reuses it).
  ```
  Menu items: Character ▸ (radio list from `discoverCharacters`), Speak lines aloud (checkbox, TTS), Popup duration ▸ (4 / 8 / 15 s), Install Claude Code hooks, Uninstall Claude Code hooks (show only the applicable one using `isInstalled`), Open Characters Folder (creates the user dir), Launch at Login (checkbox via `SMAppService.mainApp`), Quit. The menu-bar icon mirrors the overall state colour. Install errors (`invalidJSON`) show an `NSAlert` naming the file.

- [ ] **Step 1: Implement the four files and wire `AppDelegate`.** The dashboard tap callback is a stub that logs until Task 10.
- [ ] **Step 2: Build and run** `swift test && scripts/build-app.sh debug && open build/TouchBuddy.app`. Expected: tests pass and the menu-bar icon appears.
- [ ] **Step 3: Verify manually with fake sessions.** Run:

  ```bash
  echo '{"session_id":"demo1","cwd":"/tmp/touchbar-app","hook_event_name":"UserPromptSubmit"}' | build/TouchBuddy.app/Contents/MacOS/touchbuddy-hook
  ```

  The Control Strip icon turns blue with badge 1. Send `Notification` with `notification_type` `permission_prompt` and the icon turns orange and pulses. Send `SessionEnd` and the icon goes grey or empty. Test hook install/uninstall against a scratch file by launching the binary directly:

  ```bash
  TOUCHBUDDY_CLAUDE_SETTINGS_LOCAL=$(mktemp -d)/settings.local.json build/TouchBuddy.app/Contents/MacOS/TouchBuddy
  ```

  Then use the menu and inspect that file. Don't touch the real `settings.local.json` until Task 12.
- [ ] **Step 4: Commit** `feat(app): add session watcher, Control Strip status icon and menu`

---

### Task 10: Dashboard, auto-popup, speech, TTS

**Files:**
- Create: `Sources/TouchBuddy/DashboardController.swift`, `MarqueeLabel.swift`, `Speaker.swift`
- Modify: `Sources/TouchBuddy/AppDelegate.swift` (`SpriteView.swift` already exists from Task 9; reuse it)

**Interfaces:**
- Consumes: `CharacterDescriptor`, `loadFrames`, `speechLine`, `chipTitle`, `effectiveState`, `Preferences`, `TBPPresentSystemModal`/`TBPMinimizeSystemModal`, `ControlStripController.identifier`.
- Produces:
  ```swift
  @MainActor final class SpriteView: NSView { func play(_ frames: [AnimationFrame]) }   // CALayer contents swap on timer; magnificationFilter = .nearest; aspect-fit to 30pt height
  @MainActor final class MarqueeLabel: NSView { var text: String }                       // static if it fits, else scroll ~30 pt/s with 1 s pause at start
  @MainActor final class Speaker { func speak(_ line: String, voice: String?) }          // AVSpeechSynthesizer; strips emoji before speaking
  @MainActor final class DashboardController {
    init(prefs: Preferences, onChipTap: @escaping (SessionRecord) -> Void)
    func show(sessions: [SessionRecord], focus: SessionRecord?, character: CharacterDescriptor, autoDismiss: Bool)
    func dismiss() }
  ```
  Layout, left to right: the system ✕ (from `TBPShowCloseBoxWhenFrontMost(true)`), a `SpriteView` playing `character.animation(for: effectiveState(focus))` (idle if focus is nil), a `MarqueeLabel` in a rounded bubble (max ~360 pt), then one chip per session (status dot + `chipTitle`) in a horizontally scrolling `NSScrollView`. Tapping the avatar or the bubble dismisses.

  Popup flow: when `SessionWatcher.onChange` delivers non-empty `triggers`:
  - show with `focus = triggers.first` and `autoDismiss: true`;
  - minimize after `prefs.popupSeconds`, and reset the timer if another trigger arrives;
  - speak only when `prefs.ttsEnabled`.

  On a manual tap of the Control Strip icon, show with `focus = ordered.first` and `autoDismiss: false`. While the dashboard is visible, live updates refresh the chips in place.

- [ ] **Step 1: Implement the four files and wire the popup and manual-open flows.**
- [ ] **Step 2: Build and run** `swift test && scripts/build-app.sh debug && open build/TouchBuddy.app`.
- [ ] **Step 3: Verify manually with fake events** (same commands as Task 9 Step 3):
  - A permission notification pops the dashboard over Finder, with Sparky's needs_input animation and a line naming the project and detail.
  - It goes away after 8 s, and the bar returns with media controls intact.
  - Sending the same notification while it's still in needs_input with no newer `updatedAt` doesn't re-pop.
  - `Stop` does **not** pop.
  - Tapping the icon opens the dashboard; ✕ closes it.
  - Switching to Glitch from the menu shows Glitch on the next open.
  - 10 fake sessions with long names scroll.
  - With TTS toggled on, the line is spoken; TTS is off on first launch.
- [ ] **Step 4: Commit** `feat(app): add animated dashboard with auto-popup and optional TTS`

---

### Task 11: Jump to session

**Files:**
- Create: `Sources/TouchBuddy/SessionFocuser.swift`, `Sources/TouchBuddyCore/FocusTarget.swift`
- Test: `Tests/TouchBuddyCoreTests/FocusTargetTests.swift`
- Modify: `Sources/TouchBuddy/AppDelegate.swift` (`onChipTap` → focuser, then dismiss the dashboard)
- Create: `Resources/TouchBuddy.entitlements` (`com.apple.security.automation.apple-events` = true)
- Modify: `scripts/build-app.sh`:
  - sign `Contents/MacOS/touchbuddy-hook` explicitly first, then the bundle with `--options runtime --entitlements Resources/TouchBuddy.entitlements`, and drop `--deep`. (Controller ruling from the Task 1 review: hardened runtime blocks Apple Events without this entitlement.)
  - capture the `security find-identity` output into a variable before grepping, which avoids a SIGPIPE false-negative under pipefail.

**Interfaces:**
- Produces:
  ```swift
  public enum FocusTarget: Equatable, Sendable { case itermSession(uniqueID: String), claudeDesktop, itermApp }
  public func focusTarget(for r: SessionRecord) -> FocusTarget
     // valid ITERM_SESSION_ID "w<n>t<n>p<n>:<UUID>" -> .itermSession(UUID); entrypoint containing "desktop" (case-insensitive) and no iTerm id -> .claudeDesktop; else .itermApp
  public func itermUniqueID(from itermSessionID: String) -> String?   // returns UUID only if it matches ^[0-9A-Fa-f-]{36}$, else nil
  public func itermSelectScript(uniqueID: String) -> String          // AppleScript: iterate windows/tabs/sessions of application "iTerm2"; on match select window, tab, session; activate
  @MainActor final class SessionFocuser { func focus(_ r: SessionRecord) }   // NSAppleScript; on error or no match -> activate iTerm; .claudeDesktop -> NSWorkspace activate bundle id "com.anthropic.claudefordesktop"
  ```

- [ ] **Step 1: Write failing tests:**
  - `parsesValidItermID`.
  - `rejectsInjectionAttempt`: `w0t0p0:" & do shell script "x` → nil, giving `.itermApp`.
  - `desktopEntrypointTargetsClaude`.
  - `noIdsTargetsItermApp`.
  - `scriptContainsOnlyTheUUID`.

- [ ] **Step 2–4: Run (expect FAIL) → implement → run (expect pass).**
- [ ] **Step 5: Verify manually.** Open two iTerm tabs. In each, send a fake `UserPromptSubmit` with that tab's real `$ITERM_SESSION_ID` in the env and a distinct `session_id`. Tapping each chip should bring its own tab to the front. The first tap shows the macOS Automation prompt for iTerm, and that's expected.
- [ ] **Step 6: Commit** `feat(app): jump to the tapped session's iTerm tab`

---

### Task 12: Quick replies from the Touch Bar

Owner request added mid-build. See the spec section "Quick replies from the Touch Bar".

**Files:**
- Modify: `Sources/TouchBuddyCore/SessionModel.swift`, `HookPayload.swift`, `SessionReducer.swift` (record `AskUserQuestion` options)
- Create: `Sources/TouchBuddyCore/QuickReply.swift`, `Sources/TouchBuddy/ReplySender.swift`
- Modify: `Sources/TouchBuddy/DashboardController.swift` (reply buttons), `Sources/TouchBuddy/AppDelegate.swift`
- Test: `Tests/TouchBuddyCoreTests/QuickReplyTests.swift`, `Tests/TouchBuddyCoreTests/SessionReducerTests.swift`

**Interfaces:**
- Consumes: `SessionRecord`, `SessionStore.load(sessionID:)`, `itermUniqueID(from:)` (Task 11), `DashboardController`.
- Produces:
  ```swift
  // SessionRecord gains two optional fields; session files without them still decode:
  public var pendingQuestion: String?; public var pendingOptions: [String]?
  // ToolInputSummary gains (lenient decode, like its other fields):
  public let questions: [QuestionSummary]?
  public struct QuestionSummary: Decodable, Sendable { public let question: String?; public let multiSelect: Bool?; public let options: [String]? }  // options = labels from [{label, description}]
  public enum QuickReply: Equatable, Sendable { case allow, allowAlways, deny, choose(index: Int, label: String) }   // index is 1-based
  public func quickReplies(for r: SessionRecord) -> [QuickReply]
     // [] unless state == .needsInput AND itermUniqueID(from: r.itermSessionID) != nil
     // speechKind .permission -> [.allow, .allowAlways, .deny]
     // speechKind .question with pendingOptions non-empty -> choose(1...n, label)
  public func keystrokes(for reply: QuickReply) -> String
     // whitelist: allow "1", allowAlways "2", deny "\u{1B}" (Esc), choose(i) -> "\(i)"; i outside 1...9 -> ""
     // PROVISIONAL: confirm or correct in Step 5
  public func isReplyStillValid(shownFor: SessionRecord, current: SessionRecord?) -> Bool
     // current != nil, current.state == .needsInput, current.updatedAt == shownFor.updatedAt
  public func itermWriteScript(uniqueID: String, keystrokes: String) -> String
     // AppleScript: find the session by unique id, then `tell s to write text <k> newline NO`
     // Esc is emitted as (character id 27), never as a raw literal; the script embeds only the UUID and the whitelisted keystrokes
  @MainActor final class ReplySender { func send(_ reply: QuickReply, shownFor: SessionRecord) -> Bool }
     // re-load from the store; if !isReplyStillValid -> return false (nothing sent); else run the script; true on success
  ```
  Reducer changes:
  - `PreToolUse` `AskUserQuestion` with exactly one question, where `multiSelect != true` → set `pendingQuestion` and `pendingOptions` (labels).
  - Any update whose resulting state isn't `.needsInput` clears both fields.
  - Permission notifications leave them nil.

  Dashboard changes:
  - When `quickReplies(for: focus)` is non-empty, show one button per reply between the bubble and the chips: "Allow", "Always", "Deny", or the option label run through `chipTitle(_, maxChars: 14)`.
  - The bubble shrinks to fit.
  - On tap, call `ReplySender.send`. If it returns `true`, dismiss the dashboard. If `false`, grey out all reply buttons and leave the dashboard open.
  - The buttons also grey out on any live update that changes the focus session's `updatedAt` or state.

- [ ] **Step 1: Write failing tests:**
  - `QuickReplyTests`:
    - `permissionGivesAllowAlwaysDeny`.
    - `questionGivesNumberedChoices`.
    - `noRepliesWhenNotNeedsInput`.
    - `noRepliesWithoutValidItermID`.
    - `keystrokeWhitelist`: allow "1", allowAlways "2", deny "\u{1B}", choose(3) "3", choose(12) "".
    - `staleWhenUpdatedAtChanged`, `staleWhenStateChanged`, `staleWhenSessionGone`, `validWhenUnchanged`.
    - `writeScriptEmbedsOnlyUUIDAndKeys`: no `do shell script`, and contains `newline NO`.
  - `SessionReducerTests`:
    - `askUserQuestionRecordsOptions`.
    - `multiSelectQuestionRecordsNoOptions`.
    - `multipleQuestionsRecordNoOptions`.
    - `leavingNeedsInputClearsOptions`.
    - `oldSessionFileWithoutNewFieldsDecodes`.
- [ ] **Step 2–4: Run (expect FAIL) → implement → run (expect pass).**
- [ ] **Step 5: Verify keystrokes against live Claude Code.** In an iTerm tab, run `claude` in a scratch dir and trigger:
  - (a) a Bash permission prompt;
  - (b) an Edit permission prompt;
  - (c) an `AskUserQuestion` with 3 options.

  For each, send each candidate keystroke from a second tab via `osascript` using `itermWriteScript`, and record what Claude Code did. Update `keystrokes(for:)` and its test to match what was observed. If "Always allow" isn't option 2 in every prompt tested, remove `.allowAlways` from `quickReplies`, and note it in the report so the controller can tell the owner. Record the observed prompt layouts in the report.
- [ ] **Step 6: Build and run, then check on the Touch Bar.** Run `swift test && scripts/build-app.sh debug && open build/TouchBuddy.app`. With the controller and owner, on a live permission prompt:
  - tapping Allow approves it and the dashboard closes;
  - answering at the keyboard first greys out the buttons, and a later tap sends nothing.
- [ ] **Step 7: Commit** `feat(app): reply to permission prompts and questions from the Touch Bar`

---

### Task 13: Signing, install, end-to-end verification

**Files:**
- Create: `scripts/make-signing-identity.sh`
- Modify: `scripts/build-app.sh` (add an `install` mode: release build, then `ditto` to `/Applications/TouchBuddy.app`), `CLAUDE.md`, `ROADMAP.md`

**Interfaces:**
- Produces: a code-signing identity named `TouchBuddy Local Signing` in the login keychain. To create it, `openssl` generates a key and a self-signed cert with `extendedKeyUsage=codeSigning`, which is exported to p12 and imported with `security import … -T /usr/bin/codesign`. The script is idempotent and skips if the identity already exists.

- [ ] **Step 1: Write `make-signing-identity.sh`.** **The owner runs it** (`! scripts/make-signing-identity.sh`) because it needs keychain interaction. Verify with `security find-identity -p codesigning | grep "TouchBuddy Local Signing"`.
- [ ] **Step 2: Install.** Run `scripts/build-app.sh install && open /Applications/TouchBuddy.app`. Expected: `codesign -dv /Applications/TouchBuddy.app 2>&1 | grep Authority=TouchBuddy`.
- [ ] **Step 3: Install hooks for real.** Choose "Install Claude Code hooks" from the menu, then verify:

  ```bash
  git -C ~ diff --no-index /dev/null ~/.claude/settings.local.json | head -60
  shasum ~/.claude/settings.json
  ```

  `settings.json`'s hash must be unchanged from before; record it before installing.
- [ ] **Step 4: Check end to end with a live session.** In a new iTerm tab, run `claude` in this repo and ask it to run `ls`, with no auto-approve. Expected:
  - the icon turns blue while it works;
  - on the permission prompt, the dashboard pops with the avatar's line about `ls`;
  - tapping the chip focuses that tab;
  - after approval, the icon goes blue, then green on finish, with no popup;
  - `/exit` removes the chip.

  Cite the observed sequence and the session file contents in the summary.
- [ ] **Step 5: Test ghost-session cleanup.** Start `claude` in a tab, then close the tab without exiting. The chip should disappear within one watcher tick, about 2 s, once the PID is gone.
- [ ] **Step 6: Commit** `chore(release): add local signing, install mode and v1 docs`
