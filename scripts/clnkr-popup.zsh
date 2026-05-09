#!/usr/bin/env zsh

emulate -L zsh
set -eu

SCRIPT_PATH=${${(%):-%x}:A}

get_tmux_option() {
  emulate -L zsh
  local name=$1
  local fallback=${2:-}
  local value

  value=$(tmux show-option -gqv "$name")
  print -r -- "${value:-$fallback}"
}

show_status_message() {
  emulate -L zsh
  local message=$1
  local client_name=${2:-}

  if [[ -n $client_name ]]; then
    tmux display-message -c "$client_name" "$message"
  else
    tmux display-message "$message"
  fi
}

tmux_supports_popup() {
  emulate -L zsh
  local version major minor rest

  version=$(tmux -V 2>/dev/null) || return 1
  version=${version#tmux }
  major=${version%%.*}
  rest=${version#*.}
  minor=${rest%%[^0-9]*}

  [[ $major == <-> && $minor == <-> ]] || return 1
  (( major > 3 || (major == 3 && minor >= 2) ))
}

truthy() {
  emulate -L zsh
  local value=${1:-}

  case ${value:l} in
    1|on|true|yes)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

clnkr_has_sessions() {
  emulate -L zsh
  local output

  output=$(clnkr --list-sessions 2>/dev/null) || return 1
  [[ -n $output && $output != *"No sessions found"* ]]
}

shell_quote_words() {
  emulate -L zsh
  local word

  for word in "$@"; do
    printf '%q ' "$word"
  done
}

session_has_live_pane() {
  emulate -L zsh
  local session_name=$1
  local dead

  for dead in ${(f)"$(tmux list-panes -t "$session_name" -F '#{pane_dead}' 2>/dev/null)"}; do
    [[ $dead == 0 ]] && return 0
  done

  return 1
}

agent_mode() {
  emulate -L zsh
  local env_file=${1:-}
  local -a clnkr_argv

  if [[ -n $env_file && -f $env_file ]]; then
    source "$env_file"
    rm -f "$env_file"
  fi

  if ! command -v clnkr >/dev/null 2>&1; then
    print -u2 -r -- 'tmux-clnkr: clnkr not found in PATH.'
    print -u2 -r -- 'Install clnkr, then close this shell and reopen the popup.'
    exec ${SHELL:-zsh}
  fi

  clnkr_argv=(clnkr)
  if truthy "${TMUX_CLNKR_RESUME:-off}" && clnkr_has_sessions; then
    clnkr_argv+=(--continue)
  fi
  if truthy "${TMUX_CLNKR_FULL_SEND:-off}"; then
    clnkr_argv+=(--full-send)
  fi

  exec "${clnkr_argv[@]}"
}

append_export() {
  emulate -L zsh
  local file=$1
  local name=$2
  local value=$3

  [[ -n $value ]] || return 0
  print -r -- "typeset -gx $name=$(printf '%q' "$value")" >>"$file"
}

write_agent_env_file() {
  emulate -L zsh
  local resume=${1:-off}
  local env_file full_send provider_source
  local opt_api_key opt_base_url opt_provider opt_provider_api opt_model
  local api_key base_url model

  env_file=$(mktemp "${TMPDIR:-/tmp}/tmux-clnkr-env.XXXXXX")
  chmod 600 "$env_file"

  full_send=$(get_tmux_option '@clnkr-popup-full-send' 'off')
  opt_api_key=$(get_tmux_option '@clnkr-popup-api-key' '')
  opt_base_url=$(get_tmux_option '@clnkr-popup-base-url' '')
  opt_provider=$(get_tmux_option '@clnkr-popup-provider' '')
  opt_provider_api=$(get_tmux_option '@clnkr-popup-provider-api' '')
  opt_model=$(get_tmux_option '@clnkr-popup-model' '')

  {
    print -r -- "typeset -gx TMUX_CLNKR_FULL_SEND=$(printf '%q' "$full_send")"
    print -r -- "typeset -gx TMUX_CLNKR_RESUME=$(printf '%q' "$resume")"
  } >"$env_file"
  append_export "$env_file" PATH "$PATH"

  api_key=$opt_api_key
  base_url=$opt_base_url
  model=$opt_model
  provider_source=none

  if [[ -z $api_key ]]; then
    api_key=${CLNKR_API_KEY:-}
  fi
  if [[ -z $base_url ]]; then
    base_url=${CLNKR_BASE_URL:-}
  fi

  if [[ -z $api_key && -z $base_url ]]; then
    if [[ -n ${ANTHROPIC_API_KEY:-} ]]; then
      provider_source=anthropic
    elif [[ -n ${OPENAI_API_KEY:-} ]]; then
      provider_source=openai
    elif [[ -n ${ANTHROPIC_BASE_URL:-} ]]; then
      provider_source=anthropic
    elif [[ -n ${OPENAI_BASE_URL:-} ]]; then
      provider_source=openai
    fi
  fi

  case $provider_source in
    anthropic)
      [[ -n $api_key ]] || api_key=${ANTHROPIC_API_KEY:-}
      [[ -n $base_url ]] || base_url=${ANTHROPIC_BASE_URL:-https://api.anthropic.com}
      ;;
    openai)
      [[ -n $api_key ]] || api_key=${OPENAI_API_KEY:-}
      [[ -n $base_url ]] || base_url=${OPENAI_BASE_URL:-https://api.openai.com/v1}
      ;;
  esac

  if [[ -n $api_key && -z $base_url && $api_key == ${ANTHROPIC_API_KEY:-__tmux_clnkr_no_anthropic_key__} ]]; then
    base_url=${ANTHROPIC_BASE_URL:-https://api.anthropic.com}
  elif [[ -n $api_key && -z $base_url && $api_key == ${OPENAI_API_KEY:-__tmux_clnkr_no_openai_key__} ]]; then
    base_url=${OPENAI_BASE_URL:-https://api.openai.com/v1}
  fi

  if [[ -z $model ]]; then
    model=${CLNKR_MODEL:-}
  fi

  append_export "$env_file" CLNKR_API_KEY "$api_key"
  append_export "$env_file" CLNKR_BASE_URL "$base_url"
  append_export "$env_file" CLNKR_MODEL "$model"

  if [[ -n $opt_provider ]]; then
    append_export "$env_file" CLNKR_PROVIDER "$opt_provider"
  elif [[ -n ${CLNKR_PROVIDER:-} ]]; then
    append_export "$env_file" CLNKR_PROVIDER "$CLNKR_PROVIDER"
  fi

  if [[ -n $opt_provider_api && $opt_provider_api != auto ]]; then
    append_export "$env_file" CLNKR_PROVIDER_API "$opt_provider_api"
  else
    print -r -- "unset CLNKR_PROVIDER_API" >>"$env_file"
  fi

  print -r -- "$env_file"
}

ensure_agent_session() {
  emulate -L zsh
  local session_name working_dir env_file command_line close_key resume

  session_name=$(get_tmux_option '@clnkr-popup-session-name' '__clnkr_agent')
  working_dir=$(get_tmux_option '@clnkr-popup-working-dir' '~')
  close_key=$(get_tmux_option '@clnkr-popup-close-key' 'C-g')
  resume=$(get_tmux_option '@clnkr-popup-resume-next' 'off')
  working_dir=${~working_dir}

  if tmux has-session -t "$session_name" 2>/dev/null; then
    if session_has_live_pane "$session_name"; then
      print -r -- "$session_name"
      return 0
    fi

    tmux kill-session -t "$session_name" 2>/dev/null || true
    resume=on
  fi

  env_file=$(write_agent_env_file "$resume")
  command_line=$(shell_quote_words "$SCRIPT_PATH" --agent "$env_file")

  if ! tmux new-session -d -s "$session_name" -c "$working_dir" "$command_line"; then
    rm -f "$env_file"
    return 1
  fi

  tmux set-option -t "$session_name" status off
  tmux set-option -t "$session_name" prefix C-b
  tmux bind-key -n "$close_key" if-shell -F "#{==:#{client_session},$session_name}" 'detach-client' "send-keys $close_key"
  tmux set-option -gq @clnkr-popup-resume-next on

  print -r -- "$session_name"
}

open_popup() {
  emulate -L zsh
  local session_name=$1
  local client_name=${TMUX_CLNKR_CLIENT:-}
  local width height socket_path attach_command
  local -a client_flag

  if [[ -z $client_name ]]; then
    client_name=$(tmux display-message -p '#{client_name}' 2>/dev/null || true)
  fi

  [[ -n $client_name ]] || return 0

  width=$(get_tmux_option '@clnkr-popup-width' '80%')
  height=$(get_tmux_option '@clnkr-popup-height' '80%')
  socket_path=$(tmux display-message -p '#{socket_path}')
  attach_command=$(shell_quote_words env -u TMUX tmux -S "$socket_path" attach-session -t "$session_name")

  client_flag=(-c "$client_name")

  if tmux display-popup "${client_flag[@]}" -T 'clnkr' -w "$width" -h "$height" -E "$attach_command"; then
    return 0
  fi

  return 0
}

main() {
  local session_name client_name=${TMUX_CLNKR_CLIENT:-}

  if [[ ${1:-} == --agent ]]; then
    shift
    agent_mode "${1:-}"
  fi

  if ! tmux_supports_popup; then
    show_status_message 'tmux-clnkr requires tmux 3.2+ for display-popup.' "$client_name"
    return 1
  fi

  session_name=$(ensure_agent_session) || {
    show_status_message 'tmux-clnkr failed to create hidden clnkr session.' "$client_name"
    return 1
  }

  open_popup "$session_name" || {
    show_status_message 'tmux-clnkr failed to open popup.' "$client_name"
    return 1
  }
}

main "$@"
