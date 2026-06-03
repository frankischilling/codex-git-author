# Commit Author Guard

Commit Author Guard is a Codex plugin that keeps git commits authored as the configured git user, or as the authenticated GitHub CLI account when git config is incomplete.

An example GitHub repository that shows it in use is available below: 

`https://github.com/frankischilling/codex-skill-test-repo`

The plugin provides the `git-commit-author` skill and a bundled helper:

```bash
bash skills/git-commit-author/scripts/git-human-author.sh check
bash skills/git-commit-author/scripts/git-human-author.sh commit -m "message"
bash skills/git-commit-author/scripts/git-human-author.sh amend-head
```

To avoid calling the helper for every commit, install a guard hook once:

```bash
# Current repository only.
bash skills/git-commit-author/scripts/git-human-author.sh install-repo-hook

# All repositories that use the user's global Git config.
bash skills/git-commit-author/scripts/git-human-author.sh install-global-hook
```

The repo hook writes `.git/hooks/pre-commit`. The global hook writes a hook under `${XDG_CONFIG_HOME:-$HOME/.config}/codex-author-plugin/git-hooks` and points global `core.hooksPath` there. If a previous global hooks path exists, it is saved in `authorPlugin.previousHooksPath` and its `pre-commit` hook is chained when possible.

Identity resolution order:

1. Repository `user.name` and `user.email`
2. Global `user.name` and `user.email`
3. `gh api user` and `gh api user/emails`

The helper and installed hooks reject author or committer values containing `codex`, `openai`, or `chatgpt`. Hooks block bad commits; they cannot rewrite the parent `git commit` process environment.

## Examples

### Protect One Repository

Run this from inside a git repository:

```bash
bash /home/frank/plugins/author-plugin/skills/git-commit-author/scripts/git-human-author.sh install-repo-hook
```

After that, normal commits are checked automatically:

```bash
git add README.md
git commit -m "Update README"
```

If the commit environment says `Codex`, `OpenAI`, or `ChatGPT`, the pre-commit hook blocks the commit before it is created.

### Protect All Repositories

Install the global hook once:

```bash
bash /home/frank/plugins/author-plugin/skills/git-commit-author/scripts/git-human-author.sh install-global-hook
```

This sets global `core.hooksPath`, so future normal `git commit` commands are checked in any repo that uses the global Git config.

### Use GitHub CLI Fallback

If git config is missing, the helper can resolve your identity from the logged-in GitHub CLI account:

```bash
gh auth status
bash /home/frank/plugins/author-plugin/skills/git-commit-author/scripts/git-human-author.sh resolve
```

If GitHub does not expose a public email, the helper uses GitHub's noreply address format:

```text
123456+username@users.noreply.github.com
```

### Prove A Bad Commit Is Blocked

With the repo or global hook installed, this should fail:

```bash
GIT_AUTHOR_NAME=Codex \
GIT_AUTHOR_EMAIL=codex@openai.com \
GIT_COMMITTER_NAME=Codex \
GIT_COMMITTER_EMAIL=codex@openai.com \
git commit --allow-empty -m "bad author"
```

Check the log after the failed command:

```bash
git log --format='%h %an <%ae> | %cn <%ce> | %s' --max-count=5
```

No committed author or committer should contain `Codex`, `OpenAI`, or `ChatGPT`.

### Force A Safe Commit From A Polluted Environment

Hooks can block a polluted plain `git commit`, but they cannot rewrite the parent command's environment. When you need the commit to proceed anyway, use the helper's commit command:

```bash
GIT_AUTHOR_NAME=Codex \
GIT_AUTHOR_EMAIL=codex@openai.com \
GIT_COMMITTER_NAME=Codex \
GIT_COMMITTER_EMAIL=codex@openai.com \
bash /home/frank/plugins/author-plugin/skills/git-commit-author/scripts/git-human-author.sh commit -m "safe author"
```

### Fix The Latest Bad Commit

If `HEAD` is the only commit that has a bad author, amend it:

```bash
bash /home/frank/plugins/author-plugin/skills/git-commit-author/scripts/git-human-author.sh amend-head
```

Do not use this to rewrite shared history unless you intend to force-push or coordinate with other collaborators.

To remove the global hook:

```bash
bash skills/git-commit-author/scripts/git-human-author.sh uninstall-global-hook
```
