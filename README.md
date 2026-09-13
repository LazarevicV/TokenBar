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
make clean
```

The app is menu-bar only: it has no Dock icon and no main window. Click the gauge
icon in the menu bar to open the popover; use Quit in the popover to exit.

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
