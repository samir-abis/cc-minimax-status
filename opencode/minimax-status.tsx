/** @jsxImportSource @opentui/solid */
// cc-minimax-status — opencode TUI plugin.
//
// Registers a row in the TUI sidebar (between Context and MCP) that
// shows the live MiniMax 5h quota, updated on a timer. Reuses the
// statusline.sh script (also used by the Claude Code installer) so the
// data source stays in one place.
//
// opencode has two distinct plugin systems with two separate config
// files:
//   - The server `Plugin` API: registered in `opencode.json[c]`
//     `plugin:`, auto-loaded from `~/.config/opencode/plugins/*.{ts,js}`.
//   - The TUI `TuiPlugin` API (this one): registered in `tui.json[c]`
//     `plugin:` at the same config dirs. The TUI config is the one
//     `cli/cmd/tui.ts` reads via `TuiConfig.get()` and passes to
//     `TuiPluginRuntime.init` — opencode.json[c] is invisible to it.
//
// This file is `.tsx` because the slot renderer returns JSX. Bun's
// default TS/JSX transform honors the `@jsxImportSource @opentui/solid`
// pragma at the top of the file, so the JSX is compiled against the
// same runtime opencode uses internally (no tsconfig.json needed).
//
// Config (env vars, all optional):
//   OPENCODE_MINIMAX_SCRIPT        path to the statusline script
//                                  (default: ~/.claude/statusline.sh)
//   OPENCODE_MINIMAX_REFRESH_MS    poll interval in ms (default: 30000,
//                                  minimum: 5000)
//   OPENCODE_MINIMAX_TOKEN_VAR     name of the env var holding the
//                                  MiniMax bearer token (default: unset;
//                                  the script's own fallback chain is
//                                  $MINIMAX_API_KEY -> $ANTHROPIC_AUTH_TOKEN)

import type { TuiPlugin, TuiPluginModule } from "@opencode-ai/plugin/tui"
import { createSignal } from "solid-js"
import { existsSync } from "node:fs"
import { homedir } from "node:os"
import { join } from "node:path"

const DEFAULT_SCRIPT = join(homedir(), ".claude", "statusline.sh")

const SCRIPT_PATH =
  process.env.OPENCODE_MINIMAX_SCRIPT && process.env.OPENCODE_MINIMAX_SCRIPT.length > 0
    ? process.env.OPENCODE_MINIMAX_SCRIPT
    : DEFAULT_SCRIPT

const TOKEN_VAR =
  process.env.OPENCODE_MINIMAX_TOKEN_VAR && process.env.OPENCODE_MINIMAX_TOKEN_VAR.length > 0
    ? process.env.OPENCODE_MINIMAX_TOKEN_VAR
    : null

const REFRESH_MS = Math.max(
  5_000,
  Number(process.env.OPENCODE_MINIMAX_REFRESH_MS ?? 30_000) | 0,
)

async function readQuota(): Promise<string | null> {
  if (!existsSync(SCRIPT_PATH)) return null
  try {
    const env: Record<string, string> = {}
    if (TOKEN_VAR) env.MINIMAX_TOKEN_VAR = TOKEN_VAR
    const proc = Bun.spawn(["bash", SCRIPT_PATH], {
      env: { ...process.env, ...env },
      stdout: "pipe",
      stderr: "pipe",
    })
    const out = await new Response(proc.stdout).text()
    await proc.exited
    return sanitize(out)
  } catch {
    return null
  }
}

// The Claude Code statusline formats the line as
//   "MiniMax: <color>47% / 5h (1h 29m)</color>"
// — both the leading "MiniMax: " label and the raw ANSI color escapes.
// opencode's sidebar JSX renderer doesn't interpret ANSI (it just
// shows the bytes as text), and the title is already rendered by the
// sidebar's bold first row. Strip both. Leading whitespace is
// trimmed first so an accidentally-indented script line still drops
// its "MiniMax: " prefix.
function sanitize(raw: string | null): string | null {
  if (!raw) return null
  const stripped = raw
    .trim()
    .replace(/\x1b\[[0-9;]*m/g, "")          // ANSI SGR (colors, reset)
    .replace(/\x1b\[[0-9;]*[A-Za-z]/g, "")    // any other CSI sequences
    .replace(/^MiniMax:\s*/i, "")            // the script's own "MiniMax: " prefix
    .trim()
  return stripped.length > 0 ? stripped : null
}

const tui: TuiPlugin = async (api) => {
  // Mark the opencode log so we can verify the plugin actually loaded.
  // Look for "minimax-status plugin: tui() invoked" in
  // ~/.local/share/opencode/log/opencode.log after restart.
  try {
    await api.client.app.log({
      body: {
        service: "cc-minimax-status",
        level: "info",
        message: "minimax-status plugin: tui() invoked",
      },
    })
  } catch {}

  const [line, setLine] = createSignal<string | null>(null)

  let stopped = false
  async function tick() {
    if (stopped) return
    const next = await readQuota()
    setLine(next)
  }

  // Run once on mount, then poll.
  await tick()
  const handle = setInterval(tick, REFRESH_MS)

  // Cleanly tear down on plugin dispose.
  api.lifecycle.onDispose(() => {
    stopped = true
    clearInterval(handle)
  })


  // Register the sidebar row. Order 150 places it between the built-in
  // Context row (100) and the MCP row (200). Shape matches the built-in
  // Context / LSP / MCP plugins exactly: bare <box>, <b>Title</b> in the
  // first <text>, then plain <text fg={textMuted}> rows. No semantic
  // coloring, no extra padding, no per-cell <span>s — the other rows
  // don't do that, and trying to color the percent caused the
  // script's raw ANSI escapes (still on the line) to leak into the
  // opencode TUI sidebar where they render as literal text.
  api.slots.register({
    id: "cc-minimax-status",
    order: 150,
    slots: {
      sidebar_content() {
        const theme = () => api.theme.current
        const value = () => line() ?? "n/a"
        return (
          <box>
            <text fg={theme().text}>
              <b>MiniMax</b>
            </text>
            <text fg={theme().textMuted}>{value()}</text>
          </box>
        )
      },
    },
  })
}

const plugin: TuiPluginModule & { id: string } = {
  id: "cc-minimax-status",
  tui,
}

export default plugin
