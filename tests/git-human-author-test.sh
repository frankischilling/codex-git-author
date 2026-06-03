#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$ROOT_DIR/skills/git-commit-author/scripts/git-human-author.sh"
FAILED=0

fail() {
  printf 'not ok - %s\n' "$1" >&2
  FAILED=1
}

pass() {
  printf 'ok - %s\n' "$1"
}

run_case() {
  local name=$1
  shift
  if "$@"; then
    pass "$name"
  else
    fail "$name"
  fi
}

new_repo() {
  local dir
  dir=$(mktemp -d)
  git -C "$dir" init -q
  git -C "$dir" config user.name "Frank Example"
  git -C "$dir" config user.email "frank@example.test"
  printf '%s\n' "$dir"
}

new_empty_repo() {
  local dir
  dir=$(mktemp -d)
  git -C "$dir" init -q
  printf '%s\n' "$dir"
}

fake_gh_bin() {
  local dir=$1
  mkdir -p "$dir/bin"
  cat >"$dir/bin/gh" <<'FAKE_GH'
#!/usr/bin/env bash
set -euo pipefail

if [[ ${1:-} == "api" && ${2:-} == "user" ]]; then
  case "${4:-}" in
    ".name // .login // empty") printf 'FrankHub\n' ;;
    ".email // empty") printf '\n' ;;
    ".login // empty") printf 'frankhub\n' ;;
    ".id // empty") printf '12345\n' ;;
    *) exit 1 ;;
  esac
elif [[ ${1:-} == "api" && ${2:-} == "user/emails" ]]; then
  printf '12345+frankhub@users.noreply.github.com\n'
else
  exit 1
fi
FAKE_GH
  chmod +x "$dir/bin/gh"
}

test_env_output_uses_git_config() {
  local repo output ok
  repo=$(new_repo)
  output=$(
    cd "$repo"
    GIT_AUTHOR_NAME=Codex \
      GIT_AUTHOR_EMAIL=codex@openai.com \
      GIT_COMMITTER_NAME=Codex \
      GIT_COMMITTER_EMAIL=codex@openai.com \
      "$SCRIPT" env
  )

  unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
  eval "$output"

  ok=0
  if [[ ${GIT_AUTHOR_NAME:-} == "Frank Example" ]] &&
    [[ ${GIT_AUTHOR_EMAIL:-} == "frank@example.test" ]] &&
    [[ ${GIT_COMMITTER_NAME:-} == "Frank Example" ]] &&
    [[ ${GIT_COMMITTER_EMAIL:-} == "frank@example.test" ]]; then
    ok=1
  fi
  unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
  [[ $ok -eq 1 ]]
}

test_commit_uses_git_config_identity() {
  local repo actual expected
  repo=$(new_repo)

  (
    cd "$repo"
    "$SCRIPT" commit --allow-empty -m "human author"
  )

  actual=$(git -C "$repo" log -1 --format='%an <%ae>|%cn <%ce>')
  expected="Frank Example <frank@example.test>|Frank Example <frank@example.test>"
  [[ $actual == "$expected" ]]
}

test_amend_removes_codex_author() {
  local repo actual expected
  repo=$(new_repo)

  (
    cd "$repo"
    GIT_AUTHOR_NAME=Codex \
      GIT_AUTHOR_EMAIL=codex@openai.com \
      GIT_COMMITTER_NAME=Codex \
      GIT_COMMITTER_EMAIL=codex@openai.com \
      git commit --allow-empty -q -m "bad author"
    "$SCRIPT" amend-head
  )

  actual=$(git -C "$repo" log -1 --format='%an <%ae>|%cn <%ce>')
  expected="Frank Example <frank@example.test>|Frank Example <frank@example.test>"
  [[ $actual == "$expected" ]]
}

test_github_cli_fallback_identity() {
  local tmp repo output
  tmp=$(mktemp -d)
  mkdir -p "$tmp/home" "$tmp/config"
  fake_gh_bin "$tmp"
  repo="$tmp/repo"
  git init -q "$repo"

  output=$(
    cd "$repo"
    HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" PATH="$tmp/bin:$PATH" "$SCRIPT" resolve
  )

  grep -qx 'name=FrankHub' <<<"$output" || return 1
  grep -qx 'email=12345+frankhub@users.noreply.github.com' <<<"$output"
}

test_install_repo_hook_blocks_codex_plain_commit() {
  local repo
  repo=$(new_repo)

  (
    cd "$repo"
    "$SCRIPT" install-repo-hook
    if GIT_AUTHOR_NAME=Codex \
      GIT_AUTHOR_EMAIL=codex@openai.com \
      GIT_COMMITTER_NAME=Codex \
      GIT_COMMITTER_EMAIL=codex@openai.com \
      git commit --allow-empty -m "blocked" >/tmp/git-human-author-block.log 2>&1; then
      return 1
    fi
    grep -qi 'codex/openai/chatgpt' /tmp/git-human-author-block.log || return 1
    ! git rev-parse --verify HEAD >/dev/null 2>&1
  )
}

test_install_repo_hook_allows_human_plain_commit() {
  local repo actual expected
  repo=$(new_repo)

  (
    cd "$repo"
    "$SCRIPT" install-repo-hook
    git commit --allow-empty -m "plain human"
  )

  actual=$(git -C "$repo" log -1 --format='%an <%ae>|%cn <%ce>')
  expected="Frank Example <frank@example.test>|Frank Example <frank@example.test>"
  [[ $actual == "$expected" ]]
}

test_install_repo_hook_configures_from_github() {
  local tmp repo actual expected
  tmp=$(mktemp -d)
  mkdir -p "$tmp/home" "$tmp/config"
  fake_gh_bin "$tmp"
  repo="$tmp/repo"
  git init -q "$repo"

  (
    export HOME="$tmp/home"
    export XDG_CONFIG_HOME="$tmp/config"
    export PATH="$tmp/bin:$PATH"
    cd "$repo"
    "$SCRIPT" install-repo-hook
    git commit --allow-empty -m "github identity"
  )

  actual=$(git -C "$repo" log -1 --format='%an <%ae>|%cn <%ce>')
  expected="FrankHub <12345+frankhub@users.noreply.github.com>|FrankHub <12345+frankhub@users.noreply.github.com>"
  [[ $actual == "$expected" ]]
}

test_install_global_hook_blocks_future_repo_codex_commit() {
  local tmp repo
  tmp=$(mktemp -d)
  mkdir -p "$tmp/home" "$tmp/config"
  fake_gh_bin "$tmp"

  HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" PATH="$tmp/bin:$PATH" "$SCRIPT" install-global-hook
  repo=$(HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" PATH="$tmp/bin:$PATH" new_empty_repo)

  (
    cd "$repo"
    if HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" PATH="$tmp/bin:$PATH" \
      GIT_AUTHOR_NAME=Codex \
      GIT_AUTHOR_EMAIL=codex@openai.com \
      GIT_COMMITTER_NAME=Codex \
      GIT_COMMITTER_EMAIL=codex@openai.com \
      git commit --allow-empty -m "blocked globally" >/tmp/git-human-author-global-block.log 2>&1; then
      return 1
    fi
    grep -qi 'codex/openai/chatgpt' /tmp/git-human-author-global-block.log || return 1
    ! git rev-parse --verify HEAD >/dev/null 2>&1
  )
}

test_reinstall_global_hook_preserves_previous_hook_chain() {
  local tmp repo marker previous
  tmp=$(mktemp -d)
  mkdir -p "$tmp/home" "$tmp/config" "$tmp/previous-hooks"
  fake_gh_bin "$tmp"
  marker="$tmp/previous-ran"
  previous="$tmp/previous-hooks/pre-commit"
  cat >"$previous" <<PREVIOUS
#!/usr/bin/env bash
printf ran >$(printf '%q' "$marker")
PREVIOUS
  chmod +x "$previous"

  HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" git config --global core.hooksPath "$tmp/previous-hooks"
  HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" PATH="$tmp/bin:$PATH" "$SCRIPT" install-global-hook
  HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" PATH="$tmp/bin:$PATH" "$SCRIPT" install-global-hook
  repo=$(HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" PATH="$tmp/bin:$PATH" new_empty_repo)

  (
    cd "$repo"
    HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" PATH="$tmp/bin:$PATH" git commit --allow-empty -m "chain previous"
  )

  [[ $(cat "$marker" 2>/dev/null || true) == "ran" ]]
}

run_case "env output uses git config" test_env_output_uses_git_config
run_case "commit uses git config identity" test_commit_uses_git_config_identity
run_case "amend removes codex author" test_amend_removes_codex_author
run_case "github cli fallback identity" test_github_cli_fallback_identity
run_case "install repo hook blocks codex plain commit" test_install_repo_hook_blocks_codex_plain_commit
run_case "install repo hook allows human plain commit" test_install_repo_hook_allows_human_plain_commit
run_case "install repo hook configures from github" test_install_repo_hook_configures_from_github
run_case "install global hook blocks future repo codex commit" test_install_global_hook_blocks_future_repo_codex_commit
run_case "reinstall global hook preserves previous hook chain" test_reinstall_global_hook_preserves_previous_hook_chain

if [[ $FAILED -ne 0 ]]; then
  exit 1
fi
