# AGENTS.md

Rules for agents working in this repository.

- `wt` is one Bash script. Keep it compatible with Bash 3.2 (macOS default): no associative arrays, no `mapfile`, and guard empty array expansions under `set -u`.
- Prefer Git's own parsing (`git config -f`, pathspecs, `--porcelain`) over hand-written parsers.
- Messages go to stderr. Stdout is reserved for data such as paths, so `cd "$(wt go x)"` works.
- Every behavior change gets a test in `test/run.sh` that builds a real temporary repository. No mocks of Git.
- Before committing, run `./test/run.sh` and `shellcheck wt test/run.sh install.sh assets/demo/scenario.sh`. Both must pass.
- Update `README.md` and `wt help` when a command, flag, or config key changes.
- Never commit secrets, tokens, or references to private projects.
