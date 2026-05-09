#!/usr/bin/env zsh

emulate -L zsh
set -eu

PLUGIN_DIR=${0:A:h}
"$PLUGIN_DIR/scripts/install.zsh" "$PLUGIN_DIR"
