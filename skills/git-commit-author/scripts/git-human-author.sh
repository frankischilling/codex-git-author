#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: git-human-author.sh <command> [git commit args...]

Commands:
  check             Resolve identity and fail if HEAD is authored by Codex/OpenAI.
  resolve           Print the resolved name and email.
  env               Print shell exports for author and committer identity.
  configure-local   Write the resolved identity to this repo's git config.
  install-repo-hook Install a pre-commit guard in the current repository.
  install-global-hook
                    Install a global pre-commit guard through core.hooksPath.
  uninstall-global-hook
                    Remove the global guard installed by this script.
  commit            Run git commit with the resolved identity.
  amend-head        Amend HEAD with the resolved identity.

Identity order: repo git config, global git config, then authenticated GitHub CLI.
USAGE
}

die() {
  printf 'git-human-author: %s\n' "$*" >&2
  exit 1
}

inside_git_repo() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

first_line() {
  sed -n '1p'
}

is_codex_value() {
  local value=${1,,}
  [[ $value == *codex* || $value == *openai* || $value == *chatgpt* ]]
}

valid_identity_value() {
  local value=${1:-}
  [[ -n $value ]] && ! is_codex_value "$value"
}

git_config_value() {
  local scope=$1
  local key=$2

  case "$scope" in
    local)
      inside_git_repo || return 1
      git config --local --get "$key" 2>/dev/null | first_line
      ;;
    global)
      git config --global --get "$key" 2>/dev/null | first_line
      ;;
    *)
      return 1
      ;;
  esac
}

resolve_git_value() {
  local key=$1
  local scope value

  for scope in local global; do
    value=$(git_config_value "$scope" "$key" || true)
    if valid_identity_value "$value"; then
      printf '%s\n' "$value"
      return 0
    fi
  done

  return 1
}

gh_user_field() {
  local jq_expr=$1
  command_exists gh || return 1
  gh api user --jq "$jq_expr" 2>/dev/null | first_line
}

resolve_gh_name() {
  local value
  value=$(gh_user_field '.name // .login // empty' || true)
  if valid_identity_value "$value"; then
    printf '%s\n' "$value"
    return 0
  fi
  return 1
}

resolve_gh_email() {
  local value login user_id

  value=$(gh_user_field '.email // empty' || true)
  if valid_identity_value "$value"; then
    printf '%s\n' "$value"
    return 0
  fi

  if command_exists gh; then
    value=$(
      gh api user/emails \
        --jq '.[] | select(.primary == true and .verified == true) | .email' \
        2>/dev/null | first_line
    ) || true
    if valid_identity_value "$value"; then
      printf '%s\n' "$value"
      return 0
    fi
  fi

  login=$(gh_user_field '.login // empty' || true)
  user_id=$(gh_user_field '.id // empty' || true)
  if valid_identity_value "$login" && [[ -n $user_id ]]; then
    printf '%s+%s@users.noreply.github.com\n' "$user_id" "$login"
    return 0
  fi

  return 1
}

resolve_name() {
  resolve_git_value user.name || resolve_gh_name
}

resolve_email() {
  resolve_git_value user.email || resolve_gh_email
}

resolve_identity() {
  AUTHOR_NAME=$(resolve_name || true)
  AUTHOR_EMAIL=$(resolve_email || true)

  valid_identity_value "$AUTHOR_NAME" || die "could not resolve a non-Codex author name"
  valid_identity_value "$AUTHOR_EMAIL" || die "could not resolve a non-Codex author email"
}

shell_quote() {
  local value=${1//\'/\'\\\'\'}
  printf "'%s'" "$value"
}

print_env_exports() {
  printf 'export GIT_AUTHOR_NAME=%s\n' "$(shell_quote "$AUTHOR_NAME")"
  printf 'export GIT_AUTHOR_EMAIL=%s\n' "$(shell_quote "$AUTHOR_EMAIL")"
  printf 'export GIT_COMMITTER_NAME=%s\n' "$(shell_quote "$AUTHOR_NAME")"
  printf 'export GIT_COMMITTER_EMAIL=%s\n' "$(shell_quote "$AUTHOR_EMAIL")"
}

require_repo() {
  inside_git_repo || die "run this command from inside a git repository"
}

head_exists() {
  git rev-parse --verify HEAD >/dev/null 2>&1
}

head_contains_codex_author() {
  local value
  head_exists || return 1
  while IFS= read -r value; do
    if is_codex_value "$value"; then
      return 0
    fi
  done < <(git log -1 --format='%an%n%ae%n%cn%n%ce')
  return 1
}

reject_author_arg() {
  local arg
  for arg in "$@"; do
    case "$arg" in
      --author|--author=*)
        die "do not pass --author; the resolved identity is enforced"
        ;;
    esac
  done
}

effective_git_config_value() {
  local key=$1
  git config --get "$key" 2>/dev/null | first_line
}

effective_identity_is_valid() {
  local name email
  name=$(effective_git_config_value user.name || true)
  email=$(effective_git_config_value user.email || true)
  valid_identity_value "$name" && valid_identity_value "$email"
}

global_identity_is_valid() {
  local name email
  name=$(git_config_value global user.name || true)
  email=$(git_config_value global user.email || true)
  valid_identity_value "$name" && valid_identity_value "$email"
}

configure_local_if_needed() {
  effective_identity_is_valid && return 0
  resolve_identity
  git config user.name "$AUTHOR_NAME"
  git config user.email "$AUTHOR_EMAIL"
}

configure_global_if_needed() {
  global_identity_is_valid && return 0
  resolve_identity
  git config --global user.name "$AUTHOR_NAME"
  git config --global user.email "$AUTHOR_EMAIL"
}

git_var_value() {
  local key=$1
  git var "$key" 2>/dev/null | first_line
}

reject_codex_ident() {
  local label=$1
  local value=$2
  if is_codex_value "$value"; then
    die "$label resolves to Codex/OpenAI/ChatGPT; clear GIT_AUTHOR_*/GIT_COMMITTER_* or use git-human-author.sh commit"
  fi
}

hook_pre_commit() {
  require_repo
  configure_local_if_needed
  reject_codex_ident "author" "$(git_var_value GIT_AUTHOR_IDENT || true)"
  reject_codex_ident "committer" "$(git_var_value GIT_COMMITTER_IDENT || true)"
}

script_path() {
  local source=${BASH_SOURCE[0]}
  cd "$(dirname "$source")" && printf '%s/%s\n' "$PWD" "$(basename "$source")"
}

write_pre_commit_hook() {
  local hook_path=$1
  local helper_path=$2
  local previous_hook=${3:-}

  mkdir -p "$(dirname "$hook_path")"
  cat >"$hook_path" <<HOOK
#!/usr/bin/env bash
set -euo pipefail
# author-plugin managed pre-commit hook
HELPER=$(shell_quote "$helper_path")
PREVIOUS_HOOK=$(shell_quote "$previous_hook")

"\$HELPER" hook-pre-commit

if [[ -n "\$PREVIOUS_HOOK" && -x "\$PREVIOUS_HOOK" ]]; then
  exec "\$PREVIOUS_HOOK" "\$@"
fi
HOOK
  chmod +x "$hook_path"
}

install_repo_hook() {
  local git_dir hook_path backup_path helper_path timestamp
  require_repo
  configure_local_if_needed

  git_dir=$(git rev-parse --git-dir)
  hook_path=$(git rev-parse --git-path hooks/pre-commit)
  helper_path=$(script_path)

  if [[ -f $hook_path ]] && ! grep -q 'author-plugin managed pre-commit hook' "$hook_path"; then
    timestamp=$(date -u +%Y%m%d%H%M%S)
    backup_path="$git_dir/hooks/pre-commit.author-plugin-backup.$timestamp"
    mv "$hook_path" "$backup_path"
  else
    backup_path=""
  fi

  write_pre_commit_hook "$hook_path" "$helper_path" "$backup_path"
  printf 'installed repo pre-commit author guard: %s\n' "$hook_path"
}

global_hooks_dir() {
  local config_home=${XDG_CONFIG_HOME:-${HOME:?HOME is required}/.config}
  printf '%s/codex-author-plugin/git-hooks\n' "$config_home"
}

global_hook_path_from_hooks_path() {
  local hooks_path=$1
  if [[ -z $hooks_path ]]; then
    return 1
  fi
  case "$hooks_path" in
    /*) printf '%s/pre-commit\n' "$hooks_path" ;;
    ~/*) printf '%s/pre-commit\n' "${hooks_path/#\~/$HOME}" ;;
    *) printf '%s/pre-commit\n' "$hooks_path" ;;
  esac
}

install_global_hook() {
  local hooks_dir hook_path previous_hooks_path previous_hook helper_path stored_previous_hooks_path
  configure_global_if_needed

  hooks_dir=$(global_hooks_dir)
  hook_path="$hooks_dir/pre-commit"
  helper_path=$(script_path)
  previous_hooks_path=$(git config --global --get core.hooksPath 2>/dev/null || true)
  stored_previous_hooks_path=$(git config --global --get authorPlugin.previousHooksPath 2>/dev/null || true)
  previous_hook=""

  if [[ $previous_hooks_path == "$hooks_dir" ]]; then
    previous_hooks_path=$stored_previous_hooks_path
  elif [[ -n $previous_hooks_path ]]; then
    git config --global authorPlugin.previousHooksPath "$previous_hooks_path"
  fi
  previous_hook=$(global_hook_path_from_hooks_path "$previous_hooks_path" || true)

  write_pre_commit_hook "$hook_path" "$helper_path" "$previous_hook"
  git config --global core.hooksPath "$hooks_dir"
  printf 'installed global pre-commit author guard: %s\n' "$hook_path"
}

uninstall_global_hook() {
  local hooks_dir previous_hooks_path current_hooks_path
  hooks_dir=$(global_hooks_dir)
  current_hooks_path=$(git config --global --get core.hooksPath 2>/dev/null || true)
  if [[ $current_hooks_path != "$hooks_dir" ]]; then
    die "global core.hooksPath is not managed by author-plugin"
  fi

  previous_hooks_path=$(git config --global --get authorPlugin.previousHooksPath 2>/dev/null || true)
  if [[ -n $previous_hooks_path ]]; then
    git config --global core.hooksPath "$previous_hooks_path"
    git config --global --unset authorPlugin.previousHooksPath || true
    printf 'restored previous global core.hooksPath: %s\n' "$previous_hooks_path"
  else
    git config --global --unset core.hooksPath || true
    printf 'removed author-plugin global core.hooksPath\n'
  fi
}

run_git_commit() {
  GIT_AUTHOR_NAME=$AUTHOR_NAME \
    GIT_AUTHOR_EMAIL=$AUTHOR_EMAIL \
    GIT_COMMITTER_NAME=$AUTHOR_NAME \
    GIT_COMMITTER_EMAIL=$AUTHOR_EMAIL \
    git commit --author="$AUTHOR_NAME <$AUTHOR_EMAIL>" "$@"
}

cmd=${1:-check}
case "$cmd" in
  -h|--help|help)
    usage
    ;;
  check|--check)
    resolve_identity
    printf 'resolved author: %s <%s>\n' "$AUTHOR_NAME" "$AUTHOR_EMAIL"
    if inside_git_repo && head_contains_codex_author; then
      die "HEAD still contains a Codex/OpenAI author or committer; run amend-head if rewriting HEAD is intended"
    fi
    ;;
  resolve|--resolve)
    resolve_identity
    printf 'name=%s\n' "$AUTHOR_NAME"
    printf 'email=%s\n' "$AUTHOR_EMAIL"
    ;;
  env|--env)
    resolve_identity
    print_env_exports
    ;;
  configure-local|--configure-local)
    require_repo
    resolve_identity
    git config user.name "$AUTHOR_NAME"
    git config user.email "$AUTHOR_EMAIL"
    printf 'configured local git author: %s <%s>\n' "$AUTHOR_NAME" "$AUTHOR_EMAIL"
    ;;
  install-repo-hook|--install-repo-hook)
    install_repo_hook
    ;;
  install-global-hook|--install-global-hook)
    install_global_hook
    ;;
  uninstall-global-hook|--uninstall-global-hook)
    uninstall_global_hook
    ;;
  hook-pre-commit)
    hook_pre_commit
    ;;
  commit)
    shift
    require_repo
    reject_author_arg "$@"
    resolve_identity
    run_git_commit "$@"
    ;;
  amend-head|--amend-head)
    shift
    require_repo
    head_exists || die "HEAD does not exist"
    reject_author_arg "$@"
    resolve_identity
    if [[ $# -eq 0 ]]; then
      set -- --no-edit
    fi
    GIT_AUTHOR_NAME=$AUTHOR_NAME \
      GIT_AUTHOR_EMAIL=$AUTHOR_EMAIL \
      GIT_COMMITTER_NAME=$AUTHOR_NAME \
      GIT_COMMITTER_EMAIL=$AUTHOR_EMAIL \
      git commit --amend --reset-author --allow-empty "$@"
    ;;
  *)
    usage >&2
    die "unknown command: $cmd"
    ;;
esac
