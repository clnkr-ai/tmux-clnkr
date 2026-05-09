# tmux-clnkr

Persistent clnkr chat in a tmux popup.

Press `prefix + A` to open one global clnkr agent session. Closing the popup leaves the agent running. Reopen the popup to return to the same chat.

## Requirements

- tmux 3.2 or newer
- zsh
- clnkr

## Install with TPM

Add the plugin to `tmux.conf`:

```tmux
set -g @plugin 'clnkr-ai/tmux-clnkr'
```

Reload tmux config and install TPM plugins.

## Usage

Press `prefix + A`.

The plugin creates a hidden tmux session and starts `clnkr` there. Reopening the popup returns to the same chat.

The popup attaches a nested tmux client to the hidden agent session. Detach from that nested client to close the popup while leaving clnkr running. With the default tmux prefix, that is usually `prefix + d` inside the popup.

## Configuration

`@clnkr-popup-key` defaults to `A`, so the default binding is `prefix + A`.

```tmux
set -g @clnkr-popup-key 'A'
set -g @clnkr-popup-session-name '__clnkr_agent'
set -g @clnkr-popup-width '80%'
set -g @clnkr-popup-height '80%'
set -g @clnkr-popup-working-dir '~'
set -g @clnkr-popup-full-send 'off'
```

Disable the default binding:

```tmux
set -g @clnkr-popup-key 'none'
```

Manual binding:

```tmux
bind-key G run-shell '~/.tmux/plugins/tmux-clnkr/scripts/clnkr-popup.zsh'
```

Provider and model options:

```tmux
set -g @clnkr-popup-model 'gpt-5.5'
set -g @clnkr-popup-api-key 'sk-...'
set -g @clnkr-popup-base-url 'https://api.openai.com/v1'
set -g @clnkr-popup-provider-api 'openai-responses'
```

`@clnkr-popup-full-send` defaults to `off`. Turn it on only when you want clnkr to execute act batches without interactive approval:

```tmux
set -g @clnkr-popup-full-send 'on'
```

## Provider environment

clnkr reads `CLNKR_*` variables. This plugin can translate common provider env vars before starting clnkr.

Precedence:

1. `@clnkr-popup-*` tmux options when set
2. existing `CLNKR_*`
3. `ANTHROPIC_*`
4. `OPENAI_*`

Mappings:

- `ANTHROPIC_API_KEY` -> `CLNKR_API_KEY`
- `ANTHROPIC_BASE_URL` -> `CLNKR_BASE_URL`
- `OPENAI_API_KEY` -> `CLNKR_API_KEY`
- `OPENAI_BASE_URL` -> `CLNKR_BASE_URL`

If Anthropic is selected and no base URL is set, the plugin uses `https://api.anthropic.com`.

If OpenAI is selected and no base URL is set, the plugin uses `https://api.openai.com/v1`.

When provider env is partial or mixed, the plugin chooses one provider source for both API key and base URL. Provider API key variables choose the source before base-url-only variables. A partial `CLNKR_API_KEY` remains a CLNKR value and does not receive a provider-derived base URL unless it matches that provider's API key value.

The plugin does not set `CLNKR_PROVIDER` for normal Anthropic or OpenAI use. clnkr infers provider from `CLNKR_BASE_URL`. Set `@clnkr-popup-provider` only for provider-compatible endpoints where inference would be wrong.

`@clnkr-popup-provider` only exports `CLNKR_PROVIDER`; it does not choose the API key or base URL source. For provider-compatible endpoints, set `@clnkr-popup-api-key` and `@clnkr-popup-base-url` with it.

`@clnkr-popup-provider-api` defaults to clnkr auto behavior. Unset or `auto` removes inherited `CLNKR_PROVIDER_API` for the agent process. Set it only when you need a concrete OpenAI API surface.
