#!/usr/bin/env zsh

emulate -L zsh
set -eu

plugin_dir=${1:?plugin directory required}
runner_path="$plugin_dir/scripts/clnkr-popup.zsh"

get_tmux_option() {
  emulate -L zsh
  local name=$1
  local fallback=${2:-}
  local value

  value=$(tmux show-option -gqv "$name")
  print -r -- "${value:-$fallback}"
}

main() {
  local key installed_key quoted_key quoted_runner_path

  key=$(get_tmux_option '@clnkr-popup-key' 'A')
  installed_key=$(get_tmux_option '@clnkr-popup-installed-key' '')

  if [[ -n $installed_key && ( $installed_key != "$key" || $key == none ) ]]; then
    tmux unbind-key "$installed_key" 2>/dev/null || true
  fi

  if [[ $key == none ]]; then
    tmux set-option -gq @clnkr-popup-installed-key ''
    return 0
  fi

  quoted_key=$(printf '%q' "$key")
  quoted_runner_path=$(printf '%q' "$runner_path")

  tmux unbind-key "$key" 2>/dev/null || true
  tmux source-file - <<TMUX
bind-key $quoted_key run-shell "TMUX_CLNKR_CLIENT=#{q:client_name} $quoted_runner_path"
TMUX
  tmux set-option -gq @clnkr-popup-installed-key "$key"
}

main
