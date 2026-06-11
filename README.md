# cc-minimax-status

Shows your live **MiniMax 5h quota** as a persistent status line in [Claude Code](https://docs.claude.com/en/statusline) and as a persistent sidebar row in [opencode](https://opencode.ai). Context-window usage is intentionally not shown — Claude Code already surfaces that.

```
MiniMax: 100% / 5h (39m)
```

## Why

Claude Code's `rate_limits` block on stdin doesn't expose the MiniMax 5h limit — only Anthropic's own. opencode's TUI footer is hardcoded to show agent + model and is not user-extensible from config. This project fetches the real 5h limit directly from MiniMax's public API (`/v1/token_plan/remains`) using the same API key you already have wired up as `ANTHROPIC_AUTH_TOKEN`, and surfaces it through whatever surface each tool offers:

- **Claude Code:** the standard `statusLine` config, refreshed on a timer.
- **opencode:** a TUI plugin (`.tsx`, `@opentui/solid`) that registers a `sidebar_content` row at order 150 — between the built-in Context and MCP rows. Re-renders on a timer. Plus a `/minimax` slash command for an on-demand refresh in chat.

The number turns **green below 40%**, **yellow from 40–59%**, and **red at 60% or above**.

## Install

### Claude Code

**`npx` (recommended for Node users):**

```sh
npx cc-minimax-status
```

That's it. The npm package bundles the statusline script, writes it to `~/.claude/statusline.sh`, and patches `~/.claude/settings.json` — no `curl` required.

**One-liner shell installer (no Node required):**

```sh
curl -fsSL https://raw.githubusercontent.com/samir-abis/cc-minimax-status/main/install.sh | bash
```

Both installers:
- download / bundle `statusline.sh` to `~/.claude/statusline.sh` and `chmod +x` it
- patch `~/.claude/settings.json` to add the `statusLine` block (with a timestamped backup of your existing settings)
- verify the result

**Restart Claude Code** after the install finishes.

To uninstall later: re-run the same command with `--uninstall` appended (`npx cc-minimax-status --uninstall`).

#### Manual install (Claude Code)

If you'd rather not pipe to `bash`:

**1. Copy the script somewhere on disk**

```sh
curl -fsSL https://raw.githubusercontent.com/samir-abis/cc-minimax-status/main/statusline.sh \
  -o ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh
```

**2. Add the `statusLine` block to `~/.claude/settings.json`**

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh",
    "padding": 2,
    "refreshInterval": 30
  }
}
```

`refreshInterval` (in seconds, minimum 1) re-runs the script on a timer in addition to the normal event-driven renders, so the time-to-reset countdown `(Xh Ym)` visibly ticks even when you're idle and Claude Code isn't generating new output. The default of 30s strikes a balance between a live-feeling display and not hammering the MiniMax quota API; drop to `5`–`10` for a smoother tick, raise to `60`+ if you want to minimize API calls.

**3. Restart Claude Code** so the `statusLine` config takes effect.

### opencode

The same `npx` / `bash` commands above also install the opencode plugin by default — there's nothing extra to run. The installer:

1. Copies `opencode/minimax-status.tsx` to `~/.config/opencode/plugins/`.
2. Copies `opencode/commands/minimax.md` to `~/.config/opencode/commands/` (the `/minimax` slash command).
3. Registers the plugin in **`~/.config/opencode/tui.jsonc`** (not `opencode.jsonc` — see "Why `tui.jsonc`?" below).
4. Strips any stale `plugin:` entry from `~/.config/opencode/opencode.jsonc` left over from a previous install attempt.

> **Why `tui.jsonc`?** opencode has **two separate plugin systems** with two separate config trees:
>
> | Config file | Plugin API | Loaded by |
> |---|---|---|
> | `opencode.json[c]` (`~/.config/opencode/`) | `Plugin` (server hooks: `event`, `chat.message`, `tool.execute.before`, etc.) | `cli/cmd/run.ts` via `Config` service |
> | `tui.json[c]` (`~/.config/opencode/`) | `TuiPlugin` (TUI slots: `sidebar_content`, keymaps, dialogs) | `cli/cmd/tui.ts` via `TuiConfig.get()` → `TuiPluginRuntime.init()` |
>
> Our plugin uses the **TUI API** (sidebar slot), so it has to be registered in `tui.json[c]`. The `Plugin:` field in `opencode.json[c]` is the wrong tree — opencode's TUI runtime never reads that file.
>
> Why is the auto-loader glob `{plugin,plugins}/*.{ts,js}` (no `.tsx`)? The TUI plugin returns JSX, and `.tsx` JSX is transformed against `@opentui/solid` (via the `/** @jsxImportSource @opentui/solid */` pragma at the top of the file — Bun's default TypeScript/JSX transform honors it, no `tsconfig.json` needed). Since the auto-loader's glob doesn't include `.tsx`, the plugin has to be registered via the `plugin:` field in `tui.json[c]`.

After the installer finishes, just **restart opencode**. No `bun install` step (the plugin imports `@opentui/solid` directly, which Bun resolves from the bundled copy of `@opencode-ai/plugin` that opencode already ships).

A new `MiniMax` row should appear in the sidebar, between `Context` and `MCP`, like this:

```
▼ Context
  …
▼ MiniMax
  MiniMax: 100% / 5h (39m)
▼ MCP
  …
```

The line refreshes every ~30s. `/minimax` in chat prints a fresh fetch.

To install for only one of the two tools, pass a flag:

```sh
npx cc-minimax-status --opencode-only   # or: --claude-only
curl -fsSL https://raw.githubusercontent.com/samir-abis/cc-minimax-status/main/install.sh | bash -s -- --opencode-only
```

The opencode plugin reads the script from `~/.claude/statusline.sh` (so even with `--opencode-only` we still drop a copy of the script there). To point it at a different script, set `OPENCODE_MINIMAX_SCRIPT=/path/to/script.sh` before starting opencode. Other env knobs:

| Env var | Default | Purpose |
|---|---|---|
| `OPENCODE_MINIMAX_SCRIPT` | `~/.claude/statusline.sh` | Statusline script to run |
| `OPENCODE_MINIMAX_REFRESH_MS` | `30000` (min 5000) | Polling interval |
| `OPENCODE_MINIMAX_TOKEN_VAR` | unset | Name of the env var holding the MiniMax bearer token (e.g. `ANTHROPIC_API_KEY`). See "Where does the API key live?" below. |

#### Where does the API key live?

The script needs a MiniMax bearer token to call `/v1/token_plan/remains`. The lookup order is:

1. If `MINIMAX_TOKEN_VAR` is set, the script reads `${!MINIMAX_TOKEN_VAR}` (bash indirection). The opencode plugin sets this automatically when you set `OPENCODE_MINIMAX_TOKEN_VAR`.
2. Otherwise `$MINIMAX_API_KEY` (recommended for opencode users).
3. Otherwise `$ANTHROPIC_AUTH_TOKEN` (Claude Code convention, back-compat).

**Recommended for opencode users:** put the token in `~/.zshrc` / `~/.bashrc` under a name that makes sense for you, then either:

```sh
# Option A: use the default MINIMAX_API_KEY
export MINIMAX_API_KEY="sk-..."

# Option B: keep your key under ANTHROPIC_API_KEY (Anthropic SDK convention)
export ANTHROPIC_API_KEY="sk-..."
# then point the plugin at it:
export OPENCODE_MINIMAX_TOKEN_VAR=ANTHROPIC_API_KEY
```

> **Don't commit the key.** `opencode.jsonc` supports `{env:VAR}` interpolation in `mcp[*].headers` values, so you can keep secrets in your shell rc / a secrets manager and reference them by name.

#### Manual install (opencode)

```sh
mkdir -p ~/.config/opencode/plugins ~/.config/opencode/commands
curl -fsSL https://raw.githubusercontent.com/samir-abis/cc-minimax-status/main/opencode/minimax-status.tsx \
  -o ~/.config/opencode/plugins/minimax-status.tsx
curl -fsSL https://raw.githubusercontent.com/samir-abis/cc-minimax-status/main/opencode/commands/minimax.md \
  -o ~/.config/opencode/commands/minimax.md
```

Then register the plugin in `tui.jsonc` (NOT `opencode.jsonc`):

```jsonc
// ~/.config/opencode/tui.jsonc
{
  "$schema": "https://opencode.ai/tui.json",
  "plugin": ["./plugins/minimax-status.tsx"]
}
```

**Restart opencode** after copying the files.

### Requirements

- `bash` (any modern version)
- `curl`
- `jq` (only the installers need it; the statusline script itself just shells out to it)
- The same MiniMax API key you already have configured as `ANTHROPIC_AUTH_TOKEN` for Claude Code / opencode — no new credentials.

## What it shows

| Segment | Source | Notes |
|---|---|---|
| `MiniMax: X% / 5h (Ym)` | Public `GET /v1/token_plan/remains` with `Authorization: Bearer $ANTHROPIC_AUTH_TOKEN` | The 5h limit is reported as remaining-percent + time-to-reset. The script picks the most-exhausted model slot (typically `general`) and shows `100 - remaining_percent` for the used number. |

The number turns **green below 40%**, **yellow from 40–59%**, and **red at 60% or above**. (For opencode, the toast's `variant` matches these thresholds: `info` / `warning` / `error`.)

## How it works

1. The script does a `curl GET https://www.minimax.io/v1/token_plan/remains` with the bearer token. The endpoint is rate-limit-friendly (`--max-time 5`) and a failed call degrades to `n/a` without breaking the line.
2. The result is colorized and printed on a single line.
3. **Claude Code** runs the script on every render + `refreshInterval`. **opencode** runs it on a timer (default 30s) via `Bun.spawn` from inside a TUI plugin that registers a `sidebar_content` row at order 150 — between Context (100) and MCP (200).

## Tests

Pure-logic unit tests live in `test/statusline.bats` and run with [bats-core](https://github.com/bats-core/bats-core):

```sh
npm test
```

(equivalent to `bats test/`). Install bats-core first if you don't have it:

```sh
brew install bats-core          # macOS
sudo apt install bats           # Debian / Ubuntu
```

The test suite covers the time-formatting, color-thresholds, model-slot selection, the `n/a` fallbacks for malformed / empty responses, the URL sanity check, env-var precedence for the bearer token, and structural checks for the opencode plugin (correct `TuiPlugin` import, `sidebar_content` slot registration, `Bun.spawn` usage, default paths, dispose hook).

## Known limitations

- **Credit balance is not shown.** The public API exposes percent + reset time for the 5h and weekly windows, but the credit-pool number (e.g. "19,944 credits") is in a separate dashboard store that's only accessible with a session cookie. If you want credits in the line, you'd need a cookie-based refresh script (out of scope for this project).
- **Numeric request counts (`X/Y reqs`) are not shown.** The public API returns `current_interval_total_count: 0` for bundled credit-based plans, so the only reliable number is percent.
- **The script targets `api.minimax.io` (international).** If you're on `api.minimaxi.com` (mainland China), edit the URL in the script.
- **opencode's hardcoded TUI footer is still not user-extensible** (`packages/opencode/src/cli/cmd/run/footer.view.tsx`). This plugin renders into the sidebar instead, which is the only user-extensible UI surface opencode exposes.

## License

[MIT](LICENSE)
