## What changed

<!-- One or two sentences. Link the issue if there is one. -->

## How it was verified

- [ ] `make test` passes
- [ ] `make app` runs and the menu bar item behaves as expected

## Credential safety

- [ ] No real tokens, account ids, or personal emails in the diff (fixtures say `redacted`)
- [ ] No new code path writes to credential files or refreshes a token in-process
