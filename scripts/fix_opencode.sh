#!/usr/bin/env bash
# fix_opencode.sh — Automation wrapper for OpenCode WSL setup
#
# This script can be run standalone to perform the full setup without
# the Claude skill orchestrating each step. It's also useful as a
# reference for what the skill does at each phase.
#
# Usage:
#   chmod +x fix_opencode.sh
#   ./fix_opencode.sh
#
# The script is idempotent — safe to run multiple times.

set -euo pipefail

# ─── Colors ───────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
fail()  { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }

# ─── Phase 0: Detect ─────────────────────────────────────────────────
info "Phase 0 — Detecting environment..."

WSL_USER=$(whoami)
OPENCODE_BIN="$HOME/.opencode/bin/opencode"
OPENCODE_DB="$HOME/.local/share/opencode/opencode.db"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ ! -f "$OPENCODE_BIN" ]; then
    fail "OpenCode binary not found at $OPENCODE_BIN"
    echo "Install it first: curl -fsSL https://opencode.ai/install | bash"
    exit 1
fi
ok "Binary found: $OPENCODE_BIN"

DB_STATUS="missing"
if [ -f "$OPENCODE_DB" ]; then
    DB_STATUS="exists"
    ok "Database found: $OPENCODE_DB"
else
    warn "No database yet (first run?). Skipping DB fix."
fi

SERVICE_STATUS="not_running"
if systemctl --user is-active opencode-web >/dev/null 2>&1; then
    SERVICE_STATUS="running"
    ok "Service already running"
else
    info "Service not running (will create/start)"
fi

# ─── Phase 1: Fix DB ─────────────────────────────────────────────────
if [ "$DB_STATUS" = "exists" ]; then
    info "Phase 1 — Checking database for mangled paths..."
    DB_FIX_SCRIPT="$SCRIPT_DIR/opencode_db_fix.py"

    if [ ! -f "$DB_FIX_SCRIPT" ]; then
        warn "opencode_db_fix.py not found at $DB_FIX_SCRIPT — skipping DB fix"
    else
        DRY_OUTPUT=$(python3 "$DB_FIX_SCRIPT" --dry-run 2>&1) || true
        if echo "$DRY_OUTPUT" | grep -q "No mangled paths"; then
            ok "Database paths are clean"
        else
            info "Mangled paths detected — applying fix..."
            python3 "$DB_FIX_SCRIPT" --apply
            ok "Database paths repaired"
        fi
    fi
else
    info "Phase 1 — Skipped (no database yet)"
fi

# ─── Phase 2: systemd service ────────────────────────────────────────
info "Phase 2 — Setting up systemd service..."

SERVICE_DIR="$HOME/.config/systemd/user"
SERVICE_FILE="$SERVICE_DIR/opencode-web.service"

mkdir -p "$SERVICE_DIR"

if [ "$SERVICE_STATUS" = "running" ]; then
    info "Stopping service for config updates..."
    systemctl --user stop opencode-web
fi

cat > "$SERVICE_FILE" << EOF
[Unit]
Description=OpenCode Web UI Server
After=network.target

[Service]
Type=simple
ExecStart=$HOME/.opencode/bin/opencode web --port 4096 --hostname 127.0.0.1
WorkingDirectory=$HOME
Restart=on-failure
RestartSec=5
Environment=HOME=$HOME

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable opencode-web
loginctl enable-linger "$WSL_USER"
ok "Service created and enabled (linger on)"

# ─── Phase 3: Windows launcher ───────────────────────────────────────
info "Phase 3 — Deploying Windows launcher..."

# Detect Windows username
WIN_USER=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r\n' || true)
if [ -z "$WIN_USER" ]; then
    warn "Could not detect Windows username. Skipping launcher."
else
    # Find Desktop path
    DESKTOP=""
    for candidate in \
        "/mnt/c/Users/$WIN_USER/OneDrive/Escritorio" \
        "/mnt/c/Users/$WIN_USER/OneDrive/Desktop" \
        "/mnt/c/Users/$WIN_USER/Desktop"; do
        if [ -d "$candidate" ]; then
            DESKTOP="$candidate"
            break
        fi
    done

    if [ -z "$DESKTOP" ]; then
        warn "No Desktop folder found. Skipping launcher."
    else
        cat > "$DESKTOP/OpenCode-WSL.bat" << 'BATEOF'
@echo off
title OpenCode WSL Launcher
echo Starting OpenCode Web UI...
wsl systemctl --user start opencode-web

:WAIT_LOOP
timeout /t 1 /nobreak >nul
curl -s -o nul -w "%%{http_code}" http://127.0.0.1:4096 | findstr "200" >nul
if errorlevel 1 goto WAIT_LOOP

echo OpenCode is ready!
start http://127.0.0.1:4096
exit
BATEOF
        ok "Launcher deployed to $DESKTOP/OpenCode-WSL.bat"
    fi
fi

# ─── Phase 4: Plugin ecosystem ───────────────────────────────────────
info "Phase 4 — Installing plugin ecosystem..."

PLUGIN_CONFIG="$HOME/.opencode/opencode.json"
USER_CONFIG="$HOME/.config/opencode/opencode.json"

# 4a: Plugin list
mkdir -p "$(dirname "$PLUGIN_CONFIG")"

python3 -c "
import json, os

config_path = '$PLUGIN_CONFIG'
plugins = [
    'opencode-swarm-plugin',
    'opencode-working-memory',
    'opencode-helicone-session',
    '@nick-vi/opencode-type-inject',
    'opencode-cc-safety-net',
    'opencode-plugin-auto-update',
    'opencode-snip',
    'opencode-mem',
    'opencode-envsitter',
    '$HOME/superpowers'
]

config = {}
if os.path.exists(config_path):
    with open(config_path) as f:
        config = json.load(f)

config['\$schema'] = 'https://opencode.ai/config.json'
config['plugin'] = plugins

with open(config_path, 'w') as f:
    json.dump(config, f, indent=2)
print('Plugin config updated')
"
ok "10 plugins configured"

# 4b: Clone superpowers
if [ ! -d "$HOME/superpowers" ]; then
    info "Cloning superpowers..."
    git -C "$HOME" clone https://github.com/obra/superpowers.git
    ok "superpowers cloned"
else
    ok "superpowers already present"
fi

# 4c: Context7 MCP
mkdir -p "$(dirname "$USER_CONFIG")"

python3 -c "
import json, os

config_path = '$USER_CONFIG'
config = {}
if os.path.exists(config_path):
    with open(config_path) as f:
        config = json.load(f)

if 'mcp' not in config:
    config['mcp'] = {}

# MUST be an array — string form crashes the service
config['mcp']['context7'] = {
    'type': 'local',
    'command': ['npx', '-y', '@upstash/context7-mcp']
}

with open(config_path, 'w') as f:
    json.dump(config, f, indent=2)
print('Context7 MCP configured')
"
ok "Context7 MCP configured (array format)"

# ─── Phase 5: Start and verify ───────────────────────────────────────
info "Phase 5 — Starting service..."

systemctl --user start opencode-web
sleep 2

if systemctl --user is-active opencode-web >/dev/null 2>&1; then
    ok "Service is running"
else
    fail "Service failed to start. Check: journalctl --user -u opencode-web --no-pager -n 20"
fi

echo ""
echo -e "${GREEN}✅ OpenCode WSL Setup Complete${NC}"
echo ""
echo "  - Service:     created & started"
echo "  - Linger:      enabled"
echo "  - Plugins:     10 plugins installed"
echo "  - superpowers: configured"
echo "  - Context7:    configured (array format ✓)"
echo ""
echo -e "  🌐 ${CYAN}http://127.0.0.1:4096${NC}"
echo ""
