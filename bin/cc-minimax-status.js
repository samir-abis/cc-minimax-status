#!/usr/bin/env node
// cc-minimax-status — install/uninstall a Claude Code statusLine that shows
// your live MiniMax 5h quota + context-window usage.
//
// Mirrors install.sh but uses Node's stdlib so it doesn't need `jq`.

'use strict';

const fs = require('fs');
const path = require('path');
const os = require('os');

const HOME = os.homedir();
const CLAUDE_DIR = path.join(HOME, '.claude');
const SCRIPT_PATH = path.join(CLAUDE_DIR, 'statusline.sh');
const SETTINGS_PATH = path.join(CLAUDE_DIR, 'settings.json');
// The statusline.sh script ships at the package root, sibling to bin/.
const BUNDLED_SCRIPT = path.join(__dirname, '..', 'statusline.sh');

const STATUSLINE_BLOCK = {
  type: 'command',
  command: '~/.claude/statusline.sh',
  padding: 2,
};

// --- Tiny ANSI helpers (no deps) ---
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

// --- Parse args ---
const args = process.argv.slice(2);
const FORCE = args.includes('--force') || args.includes('-f');
const UNINSTALL = args.includes('--uninstall');
const HELP = args.includes('--help') || args.includes('-h');

if (HELP) {
  console.log(`cc-minimax-status — install the MiniMax 5h + context-window statusLine.

Usage:
  npx cc-minimax-status [options]

Options:
  --uninstall    Remove the statusline script and the statusLine block
  --force, -f    Overwrite the script even if ~/.claude/statusline.sh exists
  --help, -h     Show this help

After install, restart Claude Code to see:
  MiniMax: 100% / 5h (39m) | Ctx: 12%`);
  process.exit(0);
}

function backupName() {
  const stamp = new Date()
    .toISOString()
    .replace(/[-:T.Z]/g, '')
    .slice(0, 14);
  return `${SETTINGS_PATH}.bak.${stamp}`;
}

function ensureClaudeDir() {
  fs.mkdirSync(CLAUDE_DIR, { recursive: true });
}

function readSettings() {
  if (!fs.existsSync(SETTINGS_PATH)) return {};
  try {
    return JSON.parse(fs.readFileSync(SETTINGS_PATH, 'utf8'));
  } catch (e) {
    err(`Failed to parse ${SETTINGS_PATH}: ${e.message}`);
    process.exit(1);
  }
}

function install() {
  log('Installing cc-minimax-status');
  ensureClaudeDir();

  // 1. Install the statusline script
  if (fs.existsSync(SCRIPT_PATH) && !FORCE) {
    warn(`${SCRIPT_PATH} already exists; skipping copy. Use --force to overwrite.`);
  } else {
    if (!fs.existsSync(BUNDLED_SCRIPT)) {
      err(`Bundled script not found at ${BUNDLED_SCRIPT}.`);
      err('The npm package may be broken — try reinstalling.');
      process.exit(1);
    }
    fs.copyFileSync(BUNDLED_SCRIPT, SCRIPT_PATH);
    fs.chmodSync(SCRIPT_PATH, 0o755);
    ok(`Installed statusline.sh -> ${SCRIPT_PATH}`);
  }

  // 2. Patch settings.json (with timestamped backup)
  const settingsExisted = fs.existsSync(SETTINGS_PATH);
  let backupPath = null;
  if (settingsExisted) {
    backupPath = backupName();
    fs.copyFileSync(SETTINGS_PATH, backupPath);
  }

  const settings = readSettings();
  settings.statusLine = STATUSLINE_BLOCK;
  const next = JSON.stringify(settings, null, 2) + '\n';

  try {
    fs.writeFileSync(SETTINGS_PATH, next);
  } catch (e) {
    err(`Failed to write ${SETTINGS_PATH}: ${e.message}`);
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

  // 3. Verify
  const verify = readSettings();
  if (!verify.statusLine || !verify.statusLine.command) {
    err('Post-install verification failed: statusLine.command is missing.');
    process.exit(1);
  }

  console.log('');
  ok('Install complete.');
  console.log('');
  console.log(`   ${bold('Next step:')} restart Claude Code to see the status line.`);
  console.log('   The line will look like:');
  console.log('');
  console.log('     MiniMax: 100% / 5h (39m) | Ctx: 12%');
  console.log('');
  console.log('   Need to uninstall?  Re-run with --uninstall.');
}

function uninstall() {
  log('Uninstalling cc-minimax-status');

  if (fs.existsSync(SCRIPT_PATH)) {
    fs.unlinkSync(SCRIPT_PATH);
    ok(`Removed ${SCRIPT_PATH}`);
  }

  if (fs.existsSync(SETTINGS_PATH)) {
    const backupPath = backupName();
    fs.copyFileSync(SETTINGS_PATH, backupPath);
    const settings = readSettings();
    delete settings.statusLine;
    fs.writeFileSync(SETTINGS_PATH, JSON.stringify(settings, null, 2) + '\n');
    ok(`Removed statusLine from ${SETTINGS_PATH} (backup: ${backupPath})`);
  }

  console.log('\nRestart Claude Code to apply.');
}

if (UNINSTALL) {
  uninstall();
} else {
  install();
}
