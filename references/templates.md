# File Templates

Exact file contents for each phase. Replace `WSL_USER` and `WIN_USER` with
the actual values detected in Phase 0.

## systemd Service Unit

Path: `~/.config/systemd/user/opencode-web.service`

```ini
[Unit]
Description=OpenCode Web UI Server
After=network.target

[Service]
Type=simple
ExecStart=/home/WSL_USER/.opencode/bin/opencode web --port 4096 --hostname 127.0.0.1
WorkingDirectory=/home/WSL_USER
Restart=on-failure
RestartSec=5
Environment=HOME=/home/WSL_USER

[Install]
WantedBy=default.target
```

## Windows Launcher

Path: auto-detect Desktop (see SKILL.md Phase 3 for detection order).
Filename: `OpenCode-WSL.bat`

```batch
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
```

## Plugin Config

Path: `~/.opencode/opencode.json`
Merge into existing file — preserve any keys already present.

```json
{
  "$schema": "https://opencode.ai/config.json",
  "plugin": [
    "opencode-swarm-plugin",
    "opencode-working-memory",
    "opencode-helicone-session",
    "@nick-vi/opencode-type-inject",
    "opencode-cc-safety-net",
    "opencode-plugin-auto-update",
    "opencode-snip",
    "opencode-mem",
    "opencode-envsitter",
    "/home/WSL_USER/superpowers"
  ]
}
```

The superpowers entry uses an absolute path (local clone, not npm).

## Context7 MCP Config

Path: `~/.config/opencode/opencode.json`
Merge — this file likely has model/provider settings. Preserve everything,
add/update only `mcp.context7`.

```json
{
  "mcp": {
    "context7": {
      "type": "local",
      "command": ["npx", "-y", "@upstash/context7-mcp"]
    }
  }
}
```

The `command` value MUST be a JSON array. A string like
`"npx -y @upstash/context7-mcp"` crashes the service with
`Invalid input mcp.context7`.

## Final Summary Template

```
✅ OpenCode WSL Setup Complete

  - DB:         [X paths fixed / already clean / no DB yet]
  - Service:    [created & started / already running]
  - Linger:     [enabled / already set]
  - Launcher:   [deployed to C:\Users\...\Desktop\OpenCode-WSL.bat]
  - Plugins:    10 plugins installed
  - superpowers: [cloned / already present]
  - Context7:   configured (array format ✓)

🌐 http://127.0.0.1:4096
```
