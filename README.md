# TouchBuddy

A macOS menu-bar app that shows the status of your Claude Code sessions on the Touch Bar Control Strip: a small animated companion that reacts to what each session is doing, shows what it needs from you, and lets you approve or deny tool calls and jump to the session's terminal.

Requires a Mac with a Touch Bar and macOS 14 or later. Hooks reach the app through a local Claude Code plugin that TouchBuddy writes on launch.

## Install

### From source (recommended)

```sh
scripts/make-signing-identity.sh   # once; creates a local signing identity
scripts/build-app.sh install       # release build, sign, copy to /Applications, relaunch
```

A stable signing identity keeps your macOS Automation and Accessibility grants across updates. Then choose "Set up Claude Code plugin…" from the menu-bar item.

### From a release zip

1. Download `TouchBuddy-<version>-macos-universal.zip` from the [Releases](../../releases) page (Intel and Apple silicon).
2. Unzip and move `TouchBuddy.app` to `/Applications`.
3. The app is ad-hoc signed, not notarized. Open it once with right-click, then Open, or clear the quarantine flag:
   ```sh
   xattr -dr com.apple.quarantine /Applications/TouchBuddy.app
   ```
4. Grant the Automation (iTerm) and Accessibility prompts. They appear again after each update, because an ad-hoc signature changes with every build.
5. Choose "Set up Claude Code plugin…" from the menu-bar item.

## Development

```sh
swift test
scripts/build-app.sh [debug|release]   # -> build/TouchBuddy.app
```

Release builds are universal (arm64 and x86_64); debug builds are host-only.

## CI and releases

- `ci.yml` runs `swift test` and a universal release build on `macos-26` for every pull request and push to `trunk`, and asserts both binaries contain `arm64` and `x86_64`.
- `release.yml` runs release-please on `trunk`. It keeps a Release PR open (bumping `Resources/Info.plist` and `CHANGELOG.md` from Conventional Commits). Merging it tags the release, then builds the universal app, zips it with `ditto`, and attaches it to the GitHub Release.
- `ai-review.yml`, `ai-triage.yml` and `ai-agent.yml` (`@claude` mentions) run Claude Code on PRs and issues. `dependabot-triage.yml` auto-merges green Dependabot PRs.
- The `reusable-*.yml` workflows are vendored from `srepollock/ci-toolkit` v1.3.0; see `CLAUDE.md`.

### Repository secrets

| Secret | Required | Used by |
|---|---|---|
| `CLAUDE_CODE_OAUTH_TOKEN` | for the AI workflows | `ai-review`, `ai-triage`, `ai-agent` |
| `DEPENDABOT_MERGE_TOKEN` | optional | `dependabot-triage` (a PAT with contents, pull-requests and issues write, so merges re-trigger CI) |

Also enable "Allow GitHub Actions to create and approve pull requests" under Settings, Actions, General, or release-please cannot open its PR.

## License

Apache-2.0. See `LICENSE`.
