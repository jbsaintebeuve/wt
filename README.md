<img src="assets/icon.svg" width="64" height="64" alt="">

# wt

[![ci](https://github.com/jbsaintebeuve/wt/actions/workflows/ci.yml/badge.svg)](https://github.com/jbsaintebeuve/wt/actions/workflows/ci.yml)

One worktree per branch, without the "already checked out" dance.
One command to end a ticket: fetch, rebase on the base branch, and refuse to ship docs or mocks you never meant to commit.

`wt` is a single Bash script. It needs only `bash` (3.2 or later) and `git` (2.36 or later).

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/jbsaintebeuve/wt/main/install.sh | bash
```

This puts `wt` in `~/.local/bin` (set `WT_INSTALL_DIR` to change it). You can also copy the `wt` file anywhere on your `PATH`.

To make `wt go` change directory, add this line to `~/.zshrc` or `~/.bashrc`:

```sh
eval "$(wt shell-init)"
```

## Usage

| Command | What it does |
| --- | --- |
| `wt go <branch> [--from <ref>]` | Opens the worktree that holds `<branch>`. If none exists, creates one: from the local branch, from `origin/<branch>`, or as a new branch from `origin/<base>`. |
| `wt ls` | Lists worktrees. `*` marks the current one, `!` marks uncommitted changes. |
| `wt path <branch>` | Prints the path of the worktree that holds `<branch>`. |
| `wt rm <branch> [--force] [--delete-branch]` | Removes the worktree. Refuses if it has uncommitted changes, unless `--force`. |
| `wt finish [--base <b>] [--no-fetch] [--push]` | Fetches, checks excluded paths, then rebases the current branch onto `origin/<base>`. `--push` pushes with `--force-with-lease`. |
| `wt config` | Shows the effective configuration. |

`wt go` is idempotent. If the branch is already checked out somewhere, including in your main checkout, you land there instead of getting an error. New worktrees go in a directory that mirrors the branch name, so `feature/login` lives in `../app.worktrees/feature/login`.

### Example

```console
~/code/app $ wt go feature/search
wt: created branch feature/search from origin/develop
~/code/app.worktrees/feature/search $ git add -A
~/code/app.worktrees/feature/search $ wt finish
wt: refusing to finish: excluded paths are staged:
  docs/notes.md
  src/mocks/user.json
unstage them with: git restore --staged <path>
~/code/app.worktrees/feature/search $ git restore --staged docs src/mocks
~/code/app.worktrees/feature/search $ git commit -m "Add search"
~/code/app.worktrees/feature/search $ wt finish --push
wt: fetching origin
wt: rebasing feature/search onto origin/develop
wt: pushing feature/search
wt: feature/search is up to date with origin/develop
~/code/app.worktrees/feature/search $ wt go main
~/code/app $ wt ls
*  main                           ~/code/app
 ! feature/search                 ~/code/app.worktrees/feature/search
~/code/app $ wt rm feature/search --force --delete-branch
wt: removed ~/code/app.worktrees/feature/search
Deleted branch feature/search (was 9550f95).
```

## What `wt finish` does

1. Refuses if any staged file matches an excluded path, and lists those files.
2. Runs `git fetch <remote>`. Skip it with `--no-fetch`.
3. Refuses if any commit on the branch (`<remote>/<base>..HEAD`) touches an excluded path, even if a later commit reverts it.
4. Runs `git rebase --autostash <remote>/<base>`. Your uncommitted local edits, such as notes in `docs/`, are put back after the rebase. If they conflict with it, `wt` stops before pushing and the stash stays in `git stash list`.
5. With `--push`, refuses if `<remote>/<branch>` has commits you do not have, then pushes with a lease pinned to the remote tip it just checked. A teammate's push is never overwritten.

If the rebase hits a conflict, `wt` stops and leaves you in Git's normal rebase state.

## Configuration

`wt` reads settings from these sources, first match wins:

1. `.wt.conf` at the root of the current worktree.
2. `.wt.conf` at the root of the main checkout. An uncommitted file there applies to every worktree.
3. `git config` (for example `git config wt.base main`).

`.wt.conf` uses Git's config syntax:

```ini
[wt]
	base = develop
	remote = origin
	exclude = docs/**
	exclude = **/mocks/**
```

| Key | Default | Meaning |
| --- | --- | --- |
| `wt.base` | `develop` | Branch that `finish` rebases onto, and that new branches start from. |
| `wt.remote` | `origin` | Remote to fetch from and rebase onto. |
| `wt.dir` | `../<repo>.worktrees` | Where new worktrees go. Relative paths start at the main checkout. |
| `wt.exclude` | none | Glob that must never be committed. Repeat the key for more globs. Values from every source are combined. |

Exclude globs are matched from the repository root, from any subdirectory. They are [Git pathspecs](https://git-scm.com/docs/gitglossary#Documentation/gitglossary.txt-aiddefpathspecapathspec) with `glob` magic: `*` stays inside one directory and `**` crosses directories. A value that starts with `:` is used as a raw pathspec.

`wt` stops with an error if a `.wt.conf` cannot be parsed, so a typo never disables your excludes. To keep `.wt.conf` out of a shared repository, add it to `.git/info/exclude`.

## Known limitations

- Worktree paths that contain a newline or a tab are not supported.
- In a repository created with `git init --separate-git-dir`, run `wt` from the main checkout. From a linked worktree, Git reports the wrong main checkout path, so `wt` cannot find an uncommitted `.wt.conf` there. Use `git config wt.exclude` in that case.
- `finish --push` refuses when the remote branch has a merge commit that your local branch lacks, even if you rebased it away on purpose. Push by hand in that case.

## Development

```sh
./test/run.sh            # all tests
./test/run.sh finish     # tests whose name matches "finish"
shellcheck wt test/run.sh install.sh
```

Each test builds a throwaway bare remote and clone in a temporary directory. CI runs the suite on Ubuntu and macOS, the latter with the system Bash 3.2.

The choice of Bash is explained in [docs/adr/0001-bash.md](docs/adr/0001-bash.md).

## License

[MIT](LICENSE)
