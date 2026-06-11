#!/usr/bin/env node
// cc-minimax-status — install/uninstall a Claude Code statusLine and/or
// an opencode TUI plugin (sidebar row) + /minimax slash command that
// show your live MiniMax 5h quota.

'use strict';

const fs = require('fs');
const path = require('path');
const os = require('os');

const HOME = os.homedir();
const CLAUDE_DIR = path.join(HOME, '.claude');
const SCRIPT_PATH = path.join(CLAUDE_DIR, 'statusline.sh');
const SETTINGS_PATH = path.join(CLAUDE_DIR, 'settings.json');

const OPENCODE_DIR = path.join(HOME, '.config', 'opencode');
const OPENCODE_PLUGINS_DIR = path.join(OPENCODE_DIR, 'plugins');
const PLUGIN_PATH = path.join(OPENCODE_PLUGINS_DIR, 'minimax-status.tsx');
const OPENCODE_COMMANDS_DIR = path.join(OPENCODE_DIR, 'commands');
const COMMAND_PATH = path.join(OPENCODE_COMMANDS_DIR, 'minimax.md');
const TUI_JSONC = path.join(OPENCODE_DIR, 'tui.jsonc');
const TUI_JSON = path.join(OPENCODE_DIR, 'tui.json');
const OPENCODE_JSONC = path.join(OPENCODE_DIR, 'opencode.jsonc');
const OPENCODE_JSON = path.join(OPENCODE_DIR, 'opencode.json');
const OPENCODE_PKG_PATH = path.join(OPENCODE_DIR, 'package.json');

const BUNDLED_SCRIPT = path.join(__dirname, '..', 'statusline.sh');
const BUNDLED_PLUGIN = path.join(__dirname, '..', 'opencode', 'minimax-status.tsx');
const BUNDLED_COMMAND = path.join(__dirname, '..', 'opencode', 'commands', 'minimax.md');

const STATUSLINE_BLOCK = {
  type: 'command',
  command: '~/.claude/statusline.sh',
  padding: 2,
  refreshInterval: 30,
};

const wrap = (code) => (s) => `\x1b[${code}m${s}\x1b[0m`;
const cyan = wrap(36);
const green = wrap(32);
const yellow = wrap(33);
const red = wrap(31);
const bold = wrap(1);

const log = (m) => console.log(`${cyan('==>')} ${m}`);
const ok = (m) => console.log(`${green(' ✓')} ${m}`);
const warn = (m) => console.log(`${yellow(' !')} ${m}`);
const err = (m) => console.error(`${red(' ✗')} ${m}`);

const args = process.argv.slice(2);
const FORCE = args.includes('--force') || args.includes('-f');
const UNINSTALL = args.includes('--uninstall');
const HELP = args.includes('--help') || args.includes('-h');
const CLAUDE_ONLY = args.includes('--claude-only');
const OPENCODE_ONLY = args.includes('--opencode-only');

if (CLAUDE_ONLY && OPENCODE_ONLY) {
  err('--claude-only and --opencode-only are mutually exclusive.');
  process.exit(1);
}
const INSTALL_CLAUDE = !OPENCODE_ONLY;
const INSTALL_OPENCODE = !CLAUDE_ONLY;

if (HELP) {
  console.log(`cc-minimax-status — install the MiniMax 5h statusLine / opencode TUI plugin.

Usage:
  npx cc-minimax-status [options]

Options:
  --uninstall         Remove the statusline script, the Claude Code
                      statusLine block, the opencode plugin, and the
                      /minimax slash command
  --claude-only       Only patch ~/.claude/ (skip opencode)
  --opencode-only     Only install the opencode bits (skip ~/.claude/)
  --force, -f         Overwrite files even if they already exist
  --help, -h          Show this help

After install, restart Claude Code and/or opencode to see the line:
  MiniMax: 100% / 5h (39m)`);
  process.exit(0);
}

function backupName(target) {
  const stamp = new Date()
    .toISOString()
    .replace(/[-:T.Z]/g, '')
    .slice(0, 14);
  return `${target}.bak.${stamp}`;
}

function readJsonSafe(p) {
  if (!fs.existsSync(p)) return {};
  try {
    return JSON.parse(fs.readFileSync(p, 'utf8'));
  } catch (e) {
    err(`Failed to parse ${p}: ${e.message}`);
    process.exit(1);
  }
}

function writeJsonAtomic(p, value) {
  const text = JSON.stringify(value, null, 2) + '\n';
  try {
    fs.writeFileSync(p, text);
  } catch (e) {
    err(`Failed to write ${p}: ${e.message}`);
    throw e;
  }
}

function installScript() {
  if (fs.existsSync(SCRIPT_PATH) && !FORCE) {
    warn(`${SCRIPT_PATH} already exists; skipping copy. Use --force to overwrite.`);
    return;
  }
  if (!fs.existsSync(BUNDLED_SCRIPT)) {
    err(`Bundled script not found at ${BUNDLED_SCRIPT}.`);
    err('The npm package may be broken — try reinstalling.');
    process.exit(1);
  }
  fs.copyFileSync(BUNDLED_SCRIPT, SCRIPT_PATH);
  fs.chmodSync(SCRIPT_PATH, 0o755);
  ok(`Installed statusline.sh -> ${SCRIPT_PATH}`);
}

function installClaudeSettings() {
  const settingsExisted = fs.existsSync(SETTINGS_PATH);
  let backupPath = null;
  if (settingsExisted) {
    backupPath = backupName(SETTINGS_PATH);
    fs.copyFileSync(SETTINGS_PATH, backupPath);
  }

  const settings = readJsonSafe(SETTINGS_PATH);
  settings.statusLine = STATUSLINE_BLOCK;

  try {
    writeJsonAtomic(SETTINGS_PATH, settings);
  } catch (e) {
    if (backupPath) {
      try {
        fs.copyFileSync(backupPath, SETTINGS_PATH);
        err(`Restored from backup ${backupPath}.`);
      } catch (e2) {
        err(`Backup restore also failed: ${e2.message}`);
      }
    }
    process.exit(1);
  }

  if (backupPath) {
    ok(`Patched ${SETTINGS_PATH} (backup: ${backupPath})`);
  } else {
    ok(`Created ${SETTINGS_PATH}`);
  }

  const verify = readJsonSafe(SETTINGS_PATH);
  if (!verify.statusLine || !verify.statusLine.command) {
    err('Post-install verification failed: statusLine.command is missing.');
    process.exit(1);
  }
}

function opencodeAvailable() {
  return fs.existsSync(OPENCODE_DIR);
}

function installOpencodePlugin() {
  if (!opencodeAvailable()) {
    warn(`${OPENCODE_DIR} not found; skipping opencode install.`);
    warn('(Install opencode first, or run with --claude-only to silence this.)');
    return;
  }
  fs.mkdirSync(OPENCODE_PLUGINS_DIR, { recursive: true });
  if (fs.existsSync(PLUGIN_PATH) && !FORCE) {
    warn(`${PLUGIN_PATH} already exists; skipping copy. Use --force to overwrite.`);
  } else {
    if (!fs.existsSync(BUNDLED_PLUGIN)) {
      err(`Bundled plugin not found at ${BUNDLED_PLUGIN}.`);
      err('The npm package may be broken — try reinstalling.');
      process.exit(1);
    }
    fs.copyFileSync(BUNDLED_PLUGIN, PLUGIN_PATH);
    ok(`Installed minimax-status.tsx -> ${PLUGIN_PATH}`);
  }
}

function installOpencodeCommand() {
  if (!opencodeAvailable()) return;
  fs.mkdirSync(OPENCODE_COMMANDS_DIR, { recursive: true });
  if (fs.existsSync(COMMAND_PATH) && !FORCE) {
    warn(`${COMMAND_PATH} already exists; skipping copy. Use --force to overwrite.`);
    return;
  }
  if (!fs.existsSync(BUNDLED_COMMAND)) {
    err(`Bundled command not found at ${BUNDLED_COMMAND}.`);
    err('The npm package may be broken — try reinstalling.');
    process.exit(1);
  }
  fs.copyFileSync(BUNDLED_COMMAND, COMMAND_PATH);
  ok(`Installed /minimax command -> ${COMMAND_PATH}`);
}

// Register the TUI plugin in tui.json[c]. opencode's TUI runtime reads
// this file (via TuiConfig.get() in cli/cmd/tui.ts) — opencode.json[c]
// is for the SERVER plugin runtime and is ignored here. The auto-loader
// glob is `{plugin,plugins}/*.{ts,js}` which doesn't include .tsx, so
// we have to register explicitly. This is idempotent: if the entry is
// already there, we leave it alone.
function ensureTuiPluginEntry() {
  if (!opencodeAvailable()) return;
  const target = fs.existsSync(TUI_JSONC) ? TUI_JSONC :
                 fs.existsSync(TUI_JSON)  ? TUI_JSON  :
                 TUI_JSONC;  // default to JSONC if neither exists
  const PLUGIN_PATH_RE = /"(?:\.\/plugins\/minimax-status\.tsx|~?\/?[^"\n]*minimax-status\.tsx)"\s*[,}\]]/;
  if (fs.existsSync(target) && PLUGIN_PATH_RE.test(fs.readFileSync(target, 'utf8'))) {
    log(`${target} already references minimax-status.tsx.`);
    return;
  }
  let cfg = {};
  if (fs.existsSync(target)) {
    try {
      const stripped = fs.readFileSync(target, 'utf8')
        .replace(/^\s*\/\/.*$/gm, '')
        .replace(/\/\*[\s\S]*?\*\//g, '');
      cfg = JSON.parse(stripped);
    } catch (e) {
      err(`Failed to parse ${target}: ${e.message}`);
      err('Add the plugin manually: "plugin": ["./plugins/minimax-status.tsx"]');
      return;
    }
  }
  cfg.$schema = cfg.$schema || 'https://opencode.ai/tui.json';
  cfg.plugin = Array.isArray(cfg.plugin) ? cfg.plugin : [];
  if (!cfg.plugin.some((p) => typeof p === 'string' && p.includes('minimax-status.tsx'))) {
    cfg.plugin.push('./plugins/minimax-status.tsx');
  }
  const backupPath = fs.existsSync(target) ? backupName(target) : null;
  if (backupPath) fs.copyFileSync(target, backupPath);
  writeJsonAtomic(target, cfg);
  if (backupPath) {
    ok(`Patched ${target} (backup: ${backupPath}, added TUI plugin entry)`);
  } else {
    ok(`Created ${target} (added TUI plugin entry)`);
  }
}

// If a stale v0.3.0/v0.4.0 install wrote `plugin: [...]` to opencode.json[c],
// strip it. opencode.json[c] is the SERVER config — our TUI plugin
// belongs in tui.json[c]. Leaving the stale entry pointing at a .ts
// file that doesn't exist would cause opencode to log a load error
// every time it tries to register it as a server plugin.
function stripLegacyServerPluginEntry() {
  if (!opencodeAvailable()) return;
  const target = fs.existsSync(OPENCODE_JSONC) ? OPENCODE_JSONC :
                 fs.existsSync(OPENCODE_JSON)  ? OPENCODE_JSON  :
                 null;
  if (!target) return;
  let cfg;
  try {
    const stripped = fs.readFileSync(target, 'utf8')
      .replace(/^\s*\/\/.*$/gm, '')
      .replace(/\/\*[\s\S]*?\*\//g, '');
    cfg = JSON.parse(stripped);
  } catch { return; }
  if (!Array.isArray(cfg.plugin) || cfg.plugin.length === 0) {
    // Either no plugin array, or it's already empty — drop the key
    // entirely so we don't leave a noisy `"plugin": []` behind.
    if (cfg && 'plugin' in cfg) {
      delete cfg.plugin;
      const backupPath = backupName(target);
      fs.copyFileSync(target, backupPath);
      writeJsonAtomic(target, cfg);
      ok(`Removed empty plugin key from ${target} (backup: ${backupPath})`);
    }
    return;
  }
  const before = JSON.stringify(cfg.plugin);
  cfg.plugin = cfg.plugin.filter((p) =>
    typeof p === 'string'
      ? !p.includes('minimax-status')
      : Array.isArray(p) && typeof p[0] === 'string' && !p[0].includes('minimax-status')
  );
  if (cfg.plugin.length === 0) delete cfg.plugin;
  if (JSON.stringify(cfg.plugin) === before) return;
  const backupPath = backupName(target);
  fs.copyFileSync(target, backupPath);
  writeJsonAtomic(target, cfg);
  ok(`Removed stale plugin entry from ${target} (the TUI plugin belongs in tui.json[c], backup: ${backupPath})`);
}

// Drop @opentui/{core,solid} from the user's opencode package.json if
// they were added by an earlier install attempt. The .tsx plugin imports
// @opentui/solid directly; if the user's package.json doesn't list it,
// the import resolves to opencode's bundled copy (opencode's binary
// ships @opentui/solid as a peer dep of @opencode-ai/plugin). Listing
// it in ~/.config/opencode/package.json is unnecessary and just bloats
// the install.
function dropLegacyOtentuiDeps() {
  if (!fs.existsSync(OPENCODE_PKG_PATH)) return;
  let pkg;
  try { pkg = JSON.parse(fs.readFileSync(OPENCODE_PKG_PATH, 'utf8')); }
  catch { return; }
  if (!pkg.dependencies) return;
  let changed = false;
  for (const k of ['@opentui/core', '@opentui/solid']) {
    if (k in pkg.dependencies) { delete pkg.dependencies[k]; changed = true; }
  }
  if (!changed) return;
  const backupPath = backupName(OPENCODE_PKG_PATH);
  fs.copyFileSync(OPENCODE_PKG_PATH, backupPath);
  writeJsonAtomic(OPENCODE_PKG_PATH, pkg);
  ok(`Removed @opentui/* from ${OPENCODE_PKG_PATH} (backup: ${backupPath})`);
}

function install() {
  log('Installing cc-minimax-status');

  if (INSTALL_CLAUDE) {
    fs.mkdirSync(CLAUDE_DIR, { recursive: true });
    installScript();
    installClaudeSettings();
  } else {
    log('Skipping Claude Code (--opencode-only)');
  }

  if (INSTALL_OPENCODE) {
    if (!INSTALL_CLAUDE) {
      fs.mkdirSync(CLAUDE_DIR, { recursive: true });
      installScript();
    }
    installOpencodePlugin();
    installOpencodeCommand();
    stripLegacyServerPluginEntry();
    ensureTuiPluginEntry();
    dropLegacyOtentuiDeps();
  } else {
    log('Skipping opencode (--claude-only)');
  }

  console.log('');
  ok('Install complete.');
  console.log('');
  if (INSTALL_CLAUDE) {
    console.log(`   ${bold('Claude Code:')} restart Claude Code to see the status line.`);
  }
  if (INSTALL_OPENCODE && opencodeAvailable()) {
    console.log(`   ${bold('opencode:')} restart opencode. A new "MiniMax" row should`);
    console.log('   appear in the sidebar (between Context and MCP), refreshing every ~30s.');
    console.log('   Also try /minimax in chat for an on-demand refresh.');
    console.log('   The script is read from ~/.claude/statusline.sh');
    console.log('   (override with $OPENCODE_MINIMAX_SCRIPT).');
    console.log('');
    console.log('   The row will show "n/a" until a MiniMax API key is in the');
    console.log('   opencode process env. Add to ~/.zshrc (or ~/.bashrc) and restart:');
    console.log('');
    console.log('     export MINIMAX_API_KEY="sk-..."');
    console.log('');
    console.log('   Or if you already keep it under another name (e.g. ANTHROPIC_API_KEY):');
    console.log('');
    console.log('     export OPENCODE_MINIMAX_TOKEN_VAR=ANTHROPIC_API_KEY');
  }
  console.log('');
  console.log('   The line will look like:');
  console.log('');
  console.log('     MiniMax: 100% / 5h (39m)');
  console.log('');
  console.log('   Need to uninstall?  Re-run with --uninstall.');
}

function uninstall() {
  log('Uninstalling cc-minimax-status');

  if (fs.existsSync(SCRIPT_PATH)) {
    fs.unlinkSync(SCRIPT_PATH);
    ok(`Removed ${SCRIPT_PATH}`);
  } else {
    log(`${SCRIPT_PATH} not present, nothing to remove.`);
  }

  if (fs.existsSync(SETTINGS_PATH)) {
    const backupPath = backupName(SETTINGS_PATH);
    fs.copyFileSync(SETTINGS_PATH, backupPath);
    const settings = readJsonSafe(SETTINGS_PATH);
    delete settings.statusLine;
    writeJsonAtomic(SETTINGS_PATH, settings);
    ok(`Removed statusLine from ${SETTINGS_PATH} (backup: ${backupPath})`);
  } else {
    log(`${SETTINGS_PATH} not present, nothing to remove.`);
  }

  for (const p of [PLUGIN_PATH, COMMAND_PATH]) {
    if (fs.existsSync(p)) {
      fs.unlinkSync(p);
      ok(`Removed ${p}`);
    } else {
      log(`${p} not present, nothing to remove.`);
    }
  }

  stripLegacyServerPluginEntry();

  console.log('\nRestart Claude Code and/or opencode to apply.');
}

if (UNINSTALL) {
  uninstall();
} else {
  install();
}
