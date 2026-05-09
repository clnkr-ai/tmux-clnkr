# tmux-clnkr TPM entrypoint.
run-shell 'CURRENT_FILE="#{current_file}"; PLUGIN_DIR=$(cd "$(dirname "$CURRENT_FILE")" && pwd); "$PLUGIN_DIR/scripts/install.zsh" "$PLUGIN_DIR"'
