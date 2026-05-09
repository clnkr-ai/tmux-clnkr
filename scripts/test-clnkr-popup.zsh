#!/usr/bin/env zsh

emulate -L zsh
set -eu

repo_root=${0:A:h:h}
server="tmux-clnkr-test-$$"
tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/tmux-clnkr-test.XXXXXX")
fakebin="$tmpdir/bin"
attach_pid=

tmux_test() {
  tmux -L "$server" -f /dev/null "$@"
}

cleanup() {
  [[ -n ${attach_pid:-} ]] && kill "$attach_pid" 2>/dev/null || true
  tmux_test kill-server 2>/dev/null || true
  rm -rf "$tmpdir"
}

fail() {
  print -u2 -r -- "FAIL: $1"
  exit 1
}

wait_for() {
  local description=$1
  shift
  local deadline=$((SECONDS + 5))

  until "$@"; do
    (( SECONDS < deadline )) || fail "$description"
    sleep 0.1
  done
}

has_attached_client() {
  [[ -n $(tmux_test list-clients -F '#{client_name}' 2>/dev/null) ]]
}

open_popup() {
  local client_name

  client_name=$(tmux_test list-clients -F '#{client_name}' | head -n 1)
  tmux_test run-shell -b "TMUX_CLNKR_CLIENT=$client_name $repo_root/scripts/clnkr-popup.zsh"
}

open_popup_sync() {
  local client_name

  client_name=$(tmux_test list-clients -F '#{client_name}' | head -n 1)
  tmux_test run-shell "TMUX_CLNKR_CLIENT=$client_name $repo_root/scripts/clnkr-popup.zsh"
}

agent_has_live_pane() {
  tmux_test list-panes -t __clnkr_agent -F '#{pane_dead}' 2>/dev/null | rg -qx '0'
}

agent_has_dead_pane() {
  tmux_test list-panes -t __clnkr_agent -F '#{pane_dead}' 2>/dev/null | rg -qx '1'
}

trap cleanup EXIT

mkdir -p "$fakebin"
{
  print -r -- '#!/usr/bin/env zsh'
  print -r -- 'emulate -L zsh'
  print -r -- 'set -eu'
  print -r -- 'print -r -- "fake-clnkr args=$* model=${CLNKR_MODEL:-}"'
  print -r -- 'if [[ $* == --list-sessions ]]; then'
  print -r -- '  if [[ ${TMUX_CLNKR_FAKE_NO_SESSIONS:-off} == on ]]; then'
  print -r -- '    print -r -- "No sessions found for this project."'
  print -r -- '  else'
  print -r -- '    print -r -- "session-1"'
  print -r -- '  fi'
  print -r -- '  exit 0'
  print -r -- 'fi'
  print -r -- 'if [[ ${TMUX_CLNKR_FAKE_NO_SESSIONS:-off} == on && $* == --continue ]]; then'
  print -r -- '  print -u2 -r -- "Error: no session found for this project."'
  print -r -- '  exit 1'
  print -r -- 'fi'
  print -r -- 'trap "exit 0" INT TERM'
  print -r -- 'while true; do sleep 1; done'
} >"$fakebin/clnkr"
chmod +x "$fakebin/clnkr"

PATH="$fakebin:$PATH" tmux_test new-session -d -s outer -c "$repo_root" zsh
tmux_test set-environment -g PATH "$fakebin:$PATH"
tmux_test set-option -g prefix C-a
tmux_test set-option -g @clnkr-popup-model gpt-5.5
tmux_test run-shell "$repo_root/tmux-clnkr.tmux"

TERM=xterm-256color script -qfec "tmux -L $server -f /dev/null attach-session -t outer" /dev/null >/dev/null 2>&1 &
attach_pid=$!
wait_for 'attached client did not start' has_attached_client

tmux_test list-keys -T prefix A | rg -Fq 'clnkr-popup.zsh' || fail 'prefix+A binding is not installed'
open_popup
wait_for 'agent did not start from prefix+A' agent_has_live_pane

[[ $(tmux_test show-option -t __clnkr_agent -qv status) == off ]] || fail 'agent status is not off'
[[ $(tmux_test show-option -t __clnkr_agent -qv prefix) == C-b ]] || fail 'agent prefix is not C-b'
[[ $(tmux_test show-option -t __clnkr_agent -qv remain-on-exit) == on ]] || fail 'agent remain-on-exit is not on'
tmux_test list-keys -T root C-g | rg -Fq '#{client_session},__clnkr_agent' || fail 'C-g binding is not scoped to agent session'
tmux_test list-keys -T root C-g | rg -Fq 'detach-client' || fail 'C-g is not bound to detach-client'
tmux_test capture-pane -pt __clnkr_agent -S -5 | rg -Fq 'fake-clnkr args= model=gpt-5.5' || fail 'agent did not receive model'

tmux_test send-keys -t __clnkr_agent C-c
wait_for 'agent pane did not die after C-c' agent_has_dead_pane

open_popup
wait_for 'dead agent was not recreated from prefix+A' agent_has_live_pane
tmux_test capture-pane -pt __clnkr_agent -S -5 | rg -Fq 'fake-clnkr args=--continue model=gpt-5.5' || fail 'recreated agent did not resume'

tmux_test kill-session -t __clnkr_agent
tmux_test set-environment -g TMUX_CLNKR_FAKE_NO_SESSIONS on
open_popup
wait_for 'agent did not fall back after missing resume session' agent_has_live_pane
tmux_test capture-pane -pt __clnkr_agent -S -5 | rg -Fq 'fake-clnkr args= model=gpt-5.5' || fail 'agent did not fall back to plain clnkr'
tmux_test set-environment -gu TMUX_CLNKR_FAKE_NO_SESSIONS

tmux_test kill-session -t __clnkr_agent
tmux_test run-shell -b "sleep 0.2; tmux -L $server -f /dev/null kill-session -t __clnkr_agent"
open_popup_sync || fail 'agent exit leaked as clnkr-popup.zsh exit 1'

print -r -- 'ok'
