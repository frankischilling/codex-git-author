---
name: git-commit-author
description: Keep Git commit authors and committers set to the configured Git user or authenticated GitHub account. Use when creating or amending commits, installing identity guards, handling polluted Git identity variables, or working with hooks in linked worktrees.
---

# Git Commit Author

Use this skill to create, amend, or guard commits with the repository user's identity. Resolve the name and email from repository configuration, global configuration, then the authenticated GitHub CLI account.

## Compose with Git Human Workflow

If `git-human-workflow` is active, use its helper for every Git and GitHub command, including `git commit`. It already forces the resolved author and committer and also checks public text. Do not nest the two commit helpers.

An existing Git Commit Author hook may stay installed. Git Human Workflow backs it up and chains it. On a new setup that uses both skills, install only Git Human Workflow's repository hooks.

Follow the standalone workflow below when Git Human Workflow is not active.

## Standalone workflow

Work from inside the target repository. On Linux, use the Bash entry point:

```bash
bash "<skill-path>/scripts/git-commit-author.sh" check
bash "<skill-path>/scripts/git-commit-author.sh" commit -m "Update the guide"
```

On Windows, use the PowerShell entry point. It accepts the same commands and arguments:

```powershell
$author = Resolve-Path '<skill-path>/scripts/git-commit-author.ps1'
& $author check
& $author commit -m 'Update the guide'
```

The PowerShell entry point finds Git for Windows. Set `GIT_COMMIT_AUTHOR_BASH` only when that Bash executable is installed in a location it cannot find.

The `commit` command accepts normal `git commit` arguments and forces the resolved identity. Use it when hooks are absent or identity environment variables may be polluted.

Install a repository guard when plain Git commands also need protection:

```bash
bash "<skill-path>/scripts/git-commit-author.sh" install-repo-hook
```

The installer resolves the active hooks directory, including the shared directory used by linked worktrees. It backs up and chains an existing pre-commit hook. Reinstalling the guard preserves that chain.

Install a global guard only when the user asks to protect repositories through global Git configuration:

```bash
bash "<skill-path>/scripts/git-commit-author.sh" install-global-hook
```

Use `configure-local` only when the user wants the resolved name and email written to the repository's Git configuration.

If `HEAD` alone has the wrong author, amend it with:

```bash
bash "<skill-path>/scripts/git-commit-author.sh" amend-head
```

Rewriting commits older than `HEAD` requires explicit user approval.

## Identity and hook behavior

- Identity order is repository Git configuration, global Git configuration, then `gh api user` and `gh api user/emails`.
- Before using GitHub fallback, the helper verifies the active account. It supports CLI versions with and without `gh auth status --active`, and uses `GH_HOST` when set.
- The helper ignores identity values containing `codex`, `openai`, or `chatgpt`. If no human identity is available, ask the user to configure Git or authenticate `gh`.
- Repository and global hooks block commits whose effective author or committer contains a prohibited identity value.
- Hooks cannot rewrite the parent `git commit` environment. Use the helper's `commit` command when the commit must proceed.
- The global hook lives under `${XDG_CONFIG_HOME:-$HOME/.config}/git-commit-author/git-hooks`. It preserves an earlier global hooks path in `gitCommitAuthor.previousHooksPath` and chains its pre-commit hook.
- `uninstall-global-hook` restores that earlier path or removes the managed `core.hooksPath` setting.

The earlier `git-human-author.sh` entry point remains as a compatibility path. Use `git-commit-author.sh` in new commands and generated hooks.

## Guardrails

- Create commits through the helper unless a repository or global guard is installed.
- Write global Git configuration only when the user explicitly asks for global protection.
- Do not rewrite a commit older than `HEAD` without explicit user approval.
- Reject a user-provided `--author` value that conflicts with the resolved identity.
