# TokenBar

A local macOS menu bar app for tracking AI coding usage and limits. It shows the
current session and weekly rate-limit usage (and reset times) for Claude
(Claude Code / claude.ai subscription) and Codex (ChatGPT subscription), read from
the account-side usage APIs using the credentials the `claude` and `codex` CLIs
already store on your machine. See `PLAN.md` for the full design.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode Command Line Tools with a Swift 6 toolchain (`xcode-select --install`)

No third-party dependencies.

## Build and run

```sh
make run        # builds build/TokenBar.app (ad-hoc signed) and opens it
```

Other targets:

```sh
make build      # swift build (debug)
make test       # swift test
make app        # release build + assemble build/TokenBar.app
make scan-secrets  # fail if a tracked file holds a credential-shaped string
make clean
```

The app is menu-bar only: it has no Dock icon and no main window. Click the gauge
icon in the menu bar to open the popover; use Quit in the popover to exit.

## Continuous integration

Every pull request and every push to `main` runs three checks on GitHub Actions
(`.github/workflows/ci.yml`):

- **Build and test** — `make build` then `make test` on a macOS runner. The live
  tests stay skipped because they need `TOKENBAR_LIVE=1` and a signed-in CLI.
- **Bundle app** — runs `make app`, checks the bundle layout and the ad-hoc
  signature, and uploads `TokenBar.app` as a downloadable artifact.
- **Secret scan** — `scripts/scan-secrets.sh` fails the build if a tracked file
  contains anything shaped like a token, a JWT or a personal email address.

`main` is protected: the three checks must pass before a pull request can merge.
Administrators can still push directly when needed.

## Popover and states

Each provider block shows the current-session and weekly bars as *remaining*
percentage (a full bar means plenty left; accent > 30 % left, orange 10–30 %
left, red < 10 % left), the session reset time and the weekly reset as a
caption. The menu-bar text shows the remaining session percentage.
Other states:

- **Loading** – first fetch in progress.
- **Not signed in** – no credentials found for that CLI. *Open Terminal* runs
  `claude` / `codex` so you can sign in.
- **Session expired** – the stored token was rejected (HTTP 401/403). Run the CLI
  once to refresh it; *Open Terminal* does that for you.
- **Offline / HTTP error** – the last good data stays visible, dimmed, with a
  caption such as `Offline · showing data from 3 min ago` and a *Retry* button.
  On 429/5xx the app backs off exponentially (up to 10 min).
- **Limit reached** – a window is at 0 % left; the reset line turns red.
- **Resets available** (Codex only) – how many rate-limit reset credits the
  ChatGPT account holds. The *Reset limits…* button asks for confirmation, then
  redeems one credit, which resets both the 5-hour and weekly windows.
  **Redeeming is irreversible**: the credit is spent immediately and cannot be
  restored. The button is disabled when the count is 0.

## Settings

Open with the gear button (or `Cmd-,` while the popover is open):

- **Refresh every** 30 s / 1 min / 5 min (15 s while the popover is open).
- **Refresh faster while Claude or Codex are in use** – see *Activity-driven
  refresh* below.
- **Show remaining % in menu bar** – toggles the text next to the icon.
- **Menu bar shows** – *Lowest remaining* across providers, or Claude / Codex only.
- **Launch at login** – registers via `SMAppService`; errors are shown inline.
  Only works from a `.app` bundle (`make app`), not the bare binary.
- **Providers** – enable/disable Claude and Codex; takes effect immediately.

Set `TOKENBAR_DEBUG_DUMP=1` when launching the binary to print a token-free
summary (percentages, reset times, plan, status, active providers) after the
first refresh.

## Activity-driven refresh

While you are actively using a CLI, TokenBar polls that provider at its own
minimum interval (Codex every 15 s, Claude every ~2 min) for 5 minutes after
the last sign of activity, regardless of the configured refresh interval. The
popover footer shows a small "● active" caption while this is in effect.

Activity is detected by watching the directories the CLIs write session data
to, using FSEvents:

- Claude Code: `$CLAUDE_CONFIG_DIR/projects` (default `~/.claude/projects`)
- Codex: `$CODEX_HOME/sessions` (default `~/.codex/sessions`)

Only the fact that *something* changed under those directories is used; file
names and contents are never read. Directories that do not exist yet are
checked once a minute and watched once they appear. Turn the feature off with
the *Refresh faster while Claude or Codex are in use* setting.

A second trigger works across machines: if a provider's used percentage goes up between two
polls, the account is being used somewhere (for example on another computer), so the provider
is treated as active for the same five-minute window even though no local files changed.

## Notes

- **No App Sandbox.** TokenBar reads `~/.codex/auth.json` and the Claude Code
  login-keychain item, which a sandboxed app could not do. It never writes to
  these locations and never refreshes tokens itself.
- **One-time Keychain prompt.** The first time TokenBar reads the Claude Code
  credential item, macOS shows a "TokenBar wants to access…" dialog. Choose
  **Always Allow** so it does not ask again. (Because the app is ad-hoc signed, a
  rebuild may trigger the prompt once more.)
- Both usage endpoints are unofficial and undocumented; TokenBar polls them
  gently (no faster than every 15 s) with an identifiable User-Agent.

## License

MIT — see `LICENSE`.
