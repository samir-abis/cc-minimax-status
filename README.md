# cc-minimax-status

A Claude Code [statusLine](https://docs.claude.com/en/statusline) script that shows your live **MiniMax 5h quota** on every render. Context-window usage is intentionally not shown — Claude Code already surfaces that.

```
MiniMax: 100% / 5h (39m)
```

## Why

Claude Code's `rate_limits` block on stdin doesn't expose the MiniMax 5h limit — only Anthropic's own. This script fetches the real 5h limit directly from MiniMax's public API (`/v1/token_plan/remains`) using the same API key you already have wired up as `ANTHROPIC_AUTH_TOKEN`.

Context-window usage is **not** in this line on purpose: Claude Code already shows it (the statusline row and a transient warning near 80%), so duplicating it would just be visual noise.

## Install

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

### Manual install

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

### Requirements

- `bash` (any modern version)
- `curl`
- `jq` (only the installer needs it; the statusline script itself just shells out to it)
- The same MiniMax API key you already have configured as `ANTHROPIC_AUTH_TOKEN` for Claude Code — no new credentials.

## What it shows

| Segment | Source | Notes |
|---|---|---|
| `MiniMax: X% / 5h (Ym)` | Public `GET /v1/token_plan/remains` with `Authorization: Bearer $ANTHROPIC_AUTH_TOKEN` | The 5h limit is reported as remaining-percent + time-to-reset. The script picks the most-exhausted model slot (typically `general`) and shows `100 - remaining_percent` for the used number. |

The number turns **green below 40%**, **yellow from 40–59%**, and **red at 60% or above**.

## How it works

1. The script does a `curl GET https://www.minimax.io/v1/token_plan/remains` with the bearer token. The endpoint is rate-limit-friendly (`--max-time 5`) and a failed call degrades to `n/a` without breaking the line.
2. The result is colorized and printed on a single line.

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

The test suite covers the time-formatting, color-thresholds, model-slot selection, the `n/a` fallbacks for malformed / empty responses, and a sanity check that the script still points at the `minimax.io` token-plan endpoint.

## Known limitations

- **Credit balance is not shown.** The public API exposes percent + reset time for the 5h and weekly windows, but the credit-pool number (e.g. "19,944 credits") is in a separate dashboard store that's only accessible with a session cookie. If you want credits in the line, you'd need a cookie-based refresh script (out of scope for this project).
- **Numeric request counts (`X/Y reqs`) are not shown.** The public API returns `current_interval_total_count: 0` for bundled credit-based plans, so the only reliable number is percent.
- **The script targets `api.minimax.io` (international).** If you're on `api.minimaxi.com` (mainland China), edit the URL in the script.

## Requirements

- `bash` (any modern version)
- `curl`
- `jq`

## License

[MIT](LICENSE)
