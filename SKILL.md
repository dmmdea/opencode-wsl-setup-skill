---
name: opencode-wsl-setup-skill
description: >
  Full automated setup of OpenCode on WSL — fixes broken session history
  (DB path mangling bug), creates a systemd auto-start service, deploys a
  Windows Desktop launcher, and installs the complete curated plugin ecosystem
  (10 plugins + Context7 MCP). Use this skill whenever the user mentions:
  setting up OpenCode on WSL, OpenCode sessions not persisting or disappearing,
  OpenCode web UI not loading, OpenCode losing sessions after restart, the
  sidebar being empty after restart, installing OpenCode plugins, or any request
  to get OpenCode running on Windows with WSL. Also triggers on "opencode web",
  "opencode keeps losing my sessions", "opencode plugin stack", "opencode
  systemd", or "opencode wsl setup". Always use this skill proactively — if the
  user is clearly dealing with OpenCode on WSL, jump in without waiting for an
  explicit request.
---

# OpenCode WSL Setup

Automated 6-phase workflow. Detect environment → fix DB → create service →
deploy launcher → install plugins → verify. Zero unnecessary prompts — if
information can be inferred from the environment, infer it.

**Reference files** (read on demand, not upfront):
- `references/templates.md` — exact file contents for service, launcher, configs
- `references/troubleshooting.md` — root causes and failure modes per phase

**Critical gotchas** (keep in mind throughout):
1. Context7 MCP `command` must be a JSON **array** `["npx", "-y", "@upstash/context7-mcp"]` — string form crashes the service
2. The DB path mangling bug stores WSL paths with mixed separators; the bundled `scripts/opencode_db_fix.py` fixes this with auto-backup
3. `loginctl enable-linger` is required or the service dies when WSL closes

---

## Phase 0 — Detect Environment

```bash
WSL_USER=$(wsl whoami)
wsl test -f ~/.opencode/bin/opencode && echo "BINARY_OK" || echo "BINARY_MISSING"
wsl test -f ~/.local/share/opencode/opencode.db && echo "DB_EXISTS" || echo "DB_MISSING"
wsl systemctl --user is-active opencode-web 2>/dev/null || echo "SERVICE_NOT_RUNNING"
WIN_USER=$(wsl cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r')
```

**Route based on results:**
- `BINARY_MISSING` → hard stop, tell user to install OpenCode first
- `DB_MISSING` → skip Phase 1
- `SERVICE_NOT_RUNNING` → normal, proceed
- `WIN_USER` empty → ask user (the only legitimate prompt)

Store both usernames for later phases.

---

## Phase 1 — Fix Database (only if DB_EXISTS)

1. Copy `scripts/opencode_db_fix.py` to `/tmp/` in WSL
2. Dry-run: `wsl python3 /tmp/opencode_db_fix.py --dry-run`
3. If mangled paths found → auto-apply without confirmation:
   `wsl python3 /tmp/opencode_db_fix.py --apply`
   (backup is automatic — no need to ask permission)
4. If clean → skip silently, don't announce it

Record fix count for the final summary.

---

## Phase 2 — Create systemd Service (if not active)

Read `references/templates.md` → "systemd Service Unit" section for the
exact unit file. Write it to `~/.config/systemd/user/opencode-web.service`.

Then:
```bash
wsl systemctl --user daemon-reload
wsl systemctl --user enable opencode-web
wsl loginctl enable-linger $WSL_USER
```

Do NOT start the service yet — Phase 4 edits configs first.

---

## Phase 3 — Deploy Windows Launcher

Auto-detect Desktop by checking in order:
1. `C:\Users\WIN_USER\OneDrive\Escritorio\` (Spanish OneDrive)
2. `C:\Users\WIN_USER\OneDrive\Desktop\` (English OneDrive)
3. `C:\Users\WIN_USER\Desktop\` (local)

Read `references/templates.md` → "Windows Launcher" for the `.bat` content.
Write as `OpenCode-WSL.bat` to the detected Desktop path.

---

## Phase 4 — Install Plugin Ecosystem

Stop service first: `wsl systemctl --user stop opencode-web 2>/dev/null || true`

Read `references/templates.md` for all three config templates, then:

**4a.** Write/merge plugin list into `~/.opencode/opencode.json` (preserve existing keys)

**4b.** Clone superpowers if missing:
`wsl test -d ~/superpowers || wsl git -C ~ clone https://github.com/obra/superpowers.git`

**4c.** Merge Context7 MCP into `~/.config/opencode/opencode.json`
— remember: `command` MUST be an array, not a string

---

## Phase 5 — Start, Verify, Report

```bash
wsl systemctl --user start opencode-web
sleep 2
wsl systemctl --user is-active opencode-web
```

If not active → check `wsl journalctl --user -u opencode-web --no-pager -n 20`
and read `references/troubleshooting.md`.

Present summary using the template from `references/templates.md`.
Mention the launcher for convenience and that linger keeps it alive across reboots.
