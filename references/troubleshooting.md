# Troubleshooting Guide

Common failure modes encountered during OpenCode WSL setup, organized by phase.

## Table of Contents

1. [Phase 0 — Environment Detection](#phase-0)
2. [Phase 1 — Database Fix](#phase-1)
3. [Phase 2 — systemd Service](#phase-2)
4. [Phase 3 — Windows Launcher](#phase-3)
5. [Phase 4 — Plugin Installation](#phase-4)
6. [Phase 5 — Verification](#phase-5)

---

## Phase 0 — Environment Detection {#phase-0}

### `wsl whoami` returns nothing or errors

**Root cause:** WSL not installed or no default distribution set.

**Fix:** The user needs to install WSL first. Guide them to:
```powershell
wsl --install
```
Then restart and retry.

### Windows username detection fails

**Root cause:** `cmd.exe` not accessible from WSL, or PATH issues.

**Fix:** Fall back to asking the user for their Windows username. It's
usually visible in `C:\Users\` and often differs from the WSL username
(e.g., WSL `dmmdea` vs Windows `dmmde`).

### Binary exists but wrong version

**Root cause:** Old version installed that doesn't support `opencode web`.

**Fix:**
```bash
curl -fsSL https://opencode.ai/install | bash
```
This overwrites the old binary.

---

## Phase 1 — Database Fix {#phase-1}

### `opencode_db_fix.py` finds no mangled paths but sidebar is still empty

**Possible causes:**
1. Sessions were never created (fresh install). This is not a bug — there's
   simply no data yet.
2. The DB has a different schema than expected. Run:
   ```bash
   sqlite3 ~/.local/share/opencode/opencode.db ".tables"
   ```
   to see what tables exist.
3. Paths are correct but files were deleted from disk. Check if the session
   directories actually exist:
   ```bash
   ls ~/.local/share/opencode/sessions/
   ```

### Permission denied on database

**Root cause:** Another process has a lock, or file permissions are wrong.

**Fix:**
```bash
# Check who's using it
fuser ~/.local/share/opencode/opencode.db

# Fix permissions if needed
chmod 644 ~/.local/share/opencode/opencode.db
```

### Python not available

**Root cause:** `python3` not installed in WSL.

**Fix:**
```bash
sudo apt update && sudo apt install -y python3
```

---

## Phase 2 — systemd Service {#phase-2}

### `systemctl --user` says "Failed to connect to bus"

**Root cause:** systemd not enabled in WSL. Older WSL versions don't
support systemd by default.

**Fix:** Edit `/etc/wsl.conf`:
```ini
[boot]
systemd=true
```
Then restart WSL:
```powershell
wsl --shutdown
```
Re-open WSL and retry.

### `loginctl enable-linger` permission denied

**Root cause:** User doesn't have permission for linger. This is unusual
on default WSL setups.

**Fix:**
```bash
sudo loginctl enable-linger $(whoami)
```

### Service starts but exits immediately

**Root cause:** Usually port 4096 is already in use, or the binary crashed.

**Fix:**
```bash
# Check if port is in use
ss -tlnp | grep 4096

# Check the actual error
journalctl --user -u opencode-web --no-pager -n 30

# Try a different port
# Edit the service file to use --port 4097 instead
```

---

## Phase 3 — Windows Launcher {#phase-3}

### No Desktop folder found

**Root cause:** Non-standard Windows profile location or corporate policies
redirecting Desktop elsewhere.

**Fix:** Ask the user where they want the launcher file. Alternatively,
the user can create a shortcut manually that runs:
```
wsl systemctl --user start opencode-web
```

### `curl` not available in batch file

**Root cause:** curl is not on the Windows PATH. This is rare on Windows 10+
but can happen.

**Fix:** Replace the curl health check with a PowerShell equivalent, or
just use a fixed timeout:
```batch
timeout /t 5 /nobreak >nul
start http://127.0.0.1:4096
```

---

## Phase 4 — Plugin Installation {#phase-4}

### Context7 MCP crashes with "Invalid input mcp.context7"

**Root cause:** The `command` field was set as a string instead of an array.

**Wrong:**
```json
"command": "npx -y @upstash/context7-mcp"
```

**Correct:**
```json
"command": ["npx", "-y", "@upstash/context7-mcp"]
```

This is the single most common configuration error. Always verify the
command is an array after writing.

### `git clone` fails for superpowers

**Root cause:** git not installed, or network issues.

**Fix:**
```bash
sudo apt install -y git
git -C ~ clone https://github.com/obra/superpowers.git
```

If it's a network issue (corporate proxy, etc.), the user may need to
configure git proxy settings.

### Plugins not loading after restart

**Root cause:** The plugin config file (`~/.opencode/opencode.json`) might
have a JSON syntax error, or the service didn't fully restart.

**Fix:**
```bash
# Validate JSON
python3 -m json.tool ~/.opencode/opencode.json

# Full restart
systemctl --user stop opencode-web
sleep 2
systemctl --user start opencode-web
```

---

## Phase 5 — Verification {#phase-5}

### Service shows "active" but web UI doesn't load

**Root cause:** The service bound to a different interface, or a firewall
is blocking localhost.

**Fix:**
```bash
# Check what it's listening on
ss -tlnp | grep opencode

# If bound to 0.0.0.0 or a different port, update the service file
# It should be: --hostname 127.0.0.1 --port 4096
```

### Web UI loads but shows empty sidebar

If the DB fix (Phase 1) already ran and found nothing, this might be a
UI caching issue. Try:
1. Hard refresh (Ctrl+Shift+R)
2. Clear browser cache for localhost:4096
3. Check browser console for JavaScript errors

If sessions existed before and are now gone, check if a backup was
restored incorrectly:
```bash
ls -la ~/.local/share/opencode/opencode.db*
```
The `.bak.*` files are timestamped backups from the fix script.
