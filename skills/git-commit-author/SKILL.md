---
name: git-commit-author
description: Use when making, amending, or checking git commits in Codex and the commit author must be the configured git user or authenticated GitHub account rather than Codex/OpenAI.
---

# Git Commit Author

## Overview

Use this skill whenever Codex is about to create, amend, or protect git commits. The commit author and committer must come from the repository/global git config, or from the authenticated GitHub CLI account when git config is incomplete.

## Workflow

1. Work from inside the target git repository.
2. Prefer installing the guard once for the repo:

```bash
bash "<path-to-skill>/scripts/git-human-author.sh" install-repo-hook
```

3. To protect every repo that uses the user's global Git config, install the global hook:

```bash
bash "<path-to-skill>/scripts/git-human-author.sh" install-global-hook
```

This sets global `core.hooksPath` to the plugin-managed hook directory. If another global hooks path already exists, the plugin stores it in `authorPlugin.previousHooksPath` and chains its `pre-commit` hook when possible.

4. Before committing without an installed hook, run:

```bash
bash "<path-to-skill>/scripts/git-human-author.sh" check
```

5. Create commits through the helper when you need the command itself to force the resolved identity, passing normal `git commit` arguments after `commit`:

```bash
bash "<path-to-skill>/scripts/git-human-author.sh" commit -m "your message"
```

6. If the latest commit was authored as Codex/OpenAI, amend only `HEAD` through:

```bash
bash "<path-to-skill>/scripts/git-human-author.sh" amend-head
```

Use `configure-local` only when the user wants this repo's `user.name` and `user.email` written from the resolved identity.

## Identity Order

- Current repository git config: `user.name`, `user.email`
- Global git config
- GitHub CLI account from `gh api user` and `gh api user/emails`

The helper ignores `GIT_AUTHOR_*` and `GIT_COMMITTER_*` values that contain `codex`, `openai`, or `chatgpt`. If no human identity is available, stop and ask the user to configure git or authenticate `gh`.

## Hook Behavior

- `install-repo-hook` writes `.git/hooks/pre-commit` for the current repo and configures local `user.name` and `user.email` from the resolved identity when needed.
- `install-global-hook` writes a global pre-commit hook under `${XDG_CONFIG_HOME:-$HOME/.config}/codex-author-plugin/git-hooks` and configures global `user.name` and `user.email` from the resolved identity when needed.
- Installed hooks block commits whose author or committer identity resolves to Codex/OpenAI/ChatGPT.
- Git hooks cannot rewrite the parent `git commit` process environment; they block bad identity commits instead. Use the helper's `commit` command when a commit must proceed despite polluted environment variables.
- Use `uninstall-global-hook` to restore the previous global hooks path or remove the plugin-managed global hook.

## Guardrails

- Do not run plain `git commit` while this skill is active unless `install-repo-hook` or `install-global-hook` is in place, or the helper already emitted exports and they were applied in the same shell.
- Do not set global git config from this skill unless the user explicitly asks.
- Do not rewrite commits beyond `HEAD` without explicit user approval.
- Do not preserve a user-provided `--author` argument that conflicts with the resolved identity.
