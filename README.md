# Git Commit Author

Git Commit Author keeps a commit's author and committer set to the configured Git user. When Git configuration is incomplete, it can use the authenticated GitHub CLI account.

The repository remains at `https://github.com/frankischilling/codex-git-author`. The skill, command, hook messages, and configuration use the name `git-commit-author`.

## Run from Linux Bash

Use the Bash entry point on Linux:

```bash
bash skills/git-commit-author/scripts/git-commit-author.sh check
bash skills/git-commit-author/scripts/git-commit-author.sh commit -m "Update the guide"
bash skills/git-commit-author/scripts/git-commit-author.sh amend-head
```

## Run from Windows PowerShell

The PowerShell entry point finds Git for Windows and runs the same checked implementation:

```powershell
$author = Resolve-Path 'skills/git-commit-author/scripts/git-commit-author.ps1'
& $author check
& $author commit -m 'Update the guide'
& $author amend-head
```

The remaining commands use the same names, including `install-repo-hook`, `install-global-hook`, and `uninstall-global-hook`. Set `GIT_COMMIT_AUTHOR_BASH` only when Git for Windows is installed in a location the PowerShell entry point cannot find.

Identity resolution follows this order:

1. Repository `user.name` and `user.email`
2. Global `user.name` and `user.email`
3. `gh api user` and `gh api user/emails`

When fallback is needed, the helper verifies the active GitHub CLI account before reading its profile. The check works with CLI versions with and without `gh auth status --active`. It uses `github.com` unless `GH_HOST` names another host.

If GitHub does not expose a public email, the helper uses GitHub's noreply address format:

```text
123456+username@users.noreply.github.com
```

The helper rejects author or committer values containing `codex`, `openai`, or `chatgpt`. Its `commit` and `amend-head` commands replace polluted identity environment variables with the resolved identity.

## Install a repository hook

Install a guard for the current repository when plain `git commit` commands also need protection:

```bash
bash skills/git-commit-author/scripts/git-commit-author.sh install-repo-hook
```

The installer asks Git for the active hook path. This works in a normal checkout and a linked worktree, where hooks belong to the shared repository. If another pre-commit hook exists, the installer backs it up beside the resolved hook and calls it after the author guard. Reinstalling the guard keeps that chain intact.

Hooks can block a bad commit, but they cannot change the environment of the parent `git commit` process. Use the helper's `commit` command when a commit must proceed from a polluted environment.

## Install a global hook

Install the guard for repositories that use the global Git configuration:

```bash
bash skills/git-commit-author/scripts/git-commit-author.sh install-global-hook
```

The command stores its hook under `${XDG_CONFIG_HOME:-$HOME/.config}/git-commit-author/git-hooks` and points global `core.hooksPath` there. It preserves and chains an earlier global hooks path. Reinstallation compares normalized paths, so Git for Windows cannot turn the guard into a recursive self-chain by rewriting path syntax.

Remove the global guard and restore the previous hooks path with:

```bash
bash skills/git-commit-author/scripts/git-commit-author.sh uninstall-global-hook
```

## Use it with Git Human Workflow

When `git-human-workflow` is active, use that skill for every Git and GitHub command, including commits. Its `git commit` wrapper already forces the same resolved identity and also checks public text. Do not nest the two commit helpers.

Git Commit Author remains useful on its own and as an existing hook guard. Git Human Workflow preserves and chains that hook. For a new setup using both skills, install only Git Human Workflow's repository hooks.

## Compatibility with earlier names

The old `git-human-author.sh` entry point remains available for existing installations. New documentation and generated hooks use `git-commit-author.sh`. Installing the global guard migrates `${XDG_CONFIG_HOME:-$HOME/.config}/codex-author-plugin/git-hooks` and `authorPlugin.previousHooksPath` to their `git-commit-author` names while preserving the earlier hook chain.

## Development

```bash
python /path/to/skill-creator/scripts/quick_validate.py skills/git-commit-author
bash tests/git-commit-author-test.sh
```

Run the native Windows test from PowerShell:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File tests/git-commit-author-test.ps1
```
