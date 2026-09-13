#!/bin/sh
# Fails if a tracked file looks like it contains a real credential or personal email.
# TokenBar reads live tokens at runtime, so fixtures must stay redacted. Run locally
# with `make scan-secrets`; CI runs it on every pull request.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

status=0
report() {
  status=1
  printf '\n%s\n' "$1"
  printf '%s\n' "$2"
}

# Only tracked, non-binary files. The scanner itself is excluded: it holds the patterns.
files=$(git ls-files -- . ':!:scripts/scan-secrets.sh' ':!:*.png' ':!:*.icns' ':!:*.jpg')

scan() {
  pattern="$1"
  label="$2"
  hits=$(printf '%s\n' "$files" | tr '\n' '\0' | xargs -0 grep -InE "$pattern" 2>/dev/null || true)
  # Placeholders in fixtures are intentional and always say so.
  hits=$(printf '%s\n' "$hits" | grep -vE 'redacted|not-a-jwt|placeholder|example\.com|EXAMPLE' || true)
  [ -n "$hits" ] && report "Possible $label:" "$hits"
  return 0
}

scan 'sk-ant-[A-Za-z0-9_-]{10,}' 'Anthropic API key'
scan 'sk-(proj-)?[A-Za-z0-9]{24,}' 'OpenAI API key'
scan 'gh[pousr]_[A-Za-z0-9]{20,}' 'GitHub token'
scan 'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.' 'JWT'
scan '"(access_token|accessToken|refresh_token|refreshToken|id_token|account_id|accountId)" *: *"[A-Za-z0-9_.+/-]{16,}"' 'credential value'
# Personal addresses. Commit trailers live in git metadata, not in tracked files.
scan '[A-Za-z0-9._%+-]+@(gmail|outlook|hotmail|yahoo|icloud|proton(mail)?)\.[A-Za-z]{2,}' 'personal email address'

if [ "$status" -eq 0 ]; then
  echo "Secret scan clean: no credential-shaped strings in tracked files."
else
  printf '\nSecret scan failed. Redact the values above before committing.\n'
fi
exit "$status"
