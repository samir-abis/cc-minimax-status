# cc-minimax-status

A Claude Code [statusLine](https://docs.claude.com/en/statusline) script that shows your live **MiniMax 5h quota** and **context-window usage** on every render.

```
MiniMax: 100% / 5h (39m) | Ctx: 12%
```

## Why

Claude Code's `rate_limits` block on stdin doesn't expose the MiniMax 5h limit — only Anthropic's own. This script fetches the real 5h limit directly from MiniMax's public API (`/v1/token_plan/remains`) using the same API key you already have wired up as `ANTHROPIC_AUTH_TOKEN`, and combines it with the context-window percentage Claude Code computes locally.

## Install

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
    "padding": 2
  }
}
```

**3. Restart Claude Code** so the `statusLine` config takes effect.

That's it. The script reads `$ANTHROPIC_AUTH_TOKEN` from the environment, which is the same MiniMax API key you already have configured for Claude Code. No new credentials, no cookies, no extra setup.

## What it shows

| Segment | Source | Notes |
|---|---|---|
| `MiniMax: X% / 5h (Ym)` | Public `GET /v1/token_plan/remains` with `Authorization: Bearer $ANTHROPIC_AUTH_TOKEN` | The 5h limit is reported as remaining-percent + time-to-reset. The script picks the most-exhausted model slot (typically `general`) and shows `100 - remaining_percent` for the used number. |
| `Ctx: X%` | `context_window.used_percentage` from Claude Code's stdin JSON | Always available; doesn't require any network call. |

Both numbers turn **green below 40%**, **yellow from 40–59%**, and **red at 60% or above**.

## How it works

1. Claude Code pipes a JSON blob describing the current session to the script on stdin.
2. The script reads the context-window percentage out of that JSON.
3. In parallel, the script does a `curl GET https://www.minimax.io/v1/token_plan/remains` with the bearer token. The endpoint is rate-limit-friendly (`--max-time 5`) and a failed call degrades to `n/a` without breaking the line.
4. Both numbers are colorized and printed on a single line.

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
