# OpenCode WSL Setup Skill

A [Claude Cowork](https://claude.ai) skill that fully automates the setup of [OpenCode](https://opencode.ai) on Windows Subsystem for Linux (WSL).

One prompt gets you a running web UI at `http://127.0.0.1:4096` with persistent sessions, auto-start on boot, a Desktop launcher, and 10 curated plugins — no manual configuration needed.

## What It Does

The skill runs a 6-phase automated workflow:

| Phase | What happens |
|-------|-------------|
| **0. Detect** | Probes the WSL environment — binary, database, service status, Windows username. Only asks the user a question when context genuinely can't be inferred. |
| **1. Fix DB** | Detects and repairs the known path-mangling bug where WSL paths get stored with mixed separators, causing the sidebar to show empty despite session data existing on disk. Auto-backs up before any writes. |
| **2. systemd Service** | Creates a `systemd --user` service for the OpenCode web UI server, enables it, and sets `loginctl enable-linger` so it survives WSL restarts. |
| **3. Windows Launcher** | Deploys an `OpenCode-WSL.bat` to the user's Desktop that starts the service, polls for readiness, and opens the browser. Handles OneDrive-synced Desktops and localized folder names (e.g., `Escritorio`). |
| **4. Plugin Ecosystem** | Installs 10 plugins (`swarm`, `working-memory`, `helicone-session`, `type-inject`, `cc-safety-net`, `auto-update`, `snip`, `mem`, `envsitter`, `superpowers`) plus the Context7 MCP server. |
| **5. Verify** | Starts the service, confirms it's running, and presents a clean summary. |

## Install

Download `opencode-wsl-setup-skill.skill` from [Releases](https://github.com/dmmdea/opencode-wsl-setup-skill/releases) and upload it in Claude Desktop via **Settings > Skills > Upload skill**.

Or clone and point Claude at the directory:

```bash
git clone https://github.com/dmmdea/opencode-wsl-setup-skill.git
```

## When It Triggers

The skill activates when you mention things like:

- "Set up OpenCode on WSL"
- "My OpenCode sessions keep disappearing after restart"
- "The sidebar is empty but session folders exist"
- "Install the full OpenCode plugin stack"
- "OpenCode web UI won't load on 127.0.0.1:4096"

## File Structure

```
opencode-wsl-setup-skill/
├── SKILL.md                          # Main skill instructions (124 lines)
├── scripts/
│   ├── opencode_db_fix.py            # SQLite path fixer (dry-run + apply)
│   └── fix_opencode.sh               # Standalone bash automation wrapper
├── references/
│   ├── templates.md                  # File templates (systemd, .bat, JSON configs)
│   └── troubleshooting.md            # Root causes and fixes per phase
└── evals/
    └── evals.json                    # 3 eval scenarios with assertions
```

The skill uses **progressive disclosure** to save tokens: `SKILL.md` is a lean router (124 lines), and the reference files are only loaded when the model actually needs to write files or troubleshoot errors.

## Key Technical Details

**The DB bug:** OpenCode's SQLite database at `~/.local/share/opencode/opencode.db` sometimes stores session paths with mixed separators (e.g., `/home/user\.local\share`) or Windows-style UNC prefixes. The bundled `opencode_db_fix.py` scans all text columns, detects these patterns, creates a timestamped backup, and normalizes the paths.

**Context7 array format:** The MCP config for Context7 requires `"command": ["npx", "-y", "@upstash/context7-mcp"]` (a JSON array). Using a string crashes the service with `Invalid input mcp.context7`. The skill enforces the correct format.

**Linger:** Without `loginctl enable-linger`, systemd user services only run while a WSL session is open. The skill enables linger so the service starts automatically when Windows boots.

## Plugin Stack

| Plugin | Purpose |
|--------|---------|
| `opencode-swarm-plugin` | Multi-agent orchestration |
| `opencode-working-memory` | Persistent context across sessions |
| `opencode-helicone-session` | Request logging and observability |
| `@nick-vi/opencode-type-inject` | Type injection for better completions |
| `opencode-cc-safety-net` | Safety guardrails |
| `opencode-plugin-auto-update` | Keeps plugins current |
| `opencode-snip` | Code snippet management |
| `opencode-mem` | Memory and recall |
| `opencode-envsitter` | Environment variable management |
| `superpowers` (local) | [obra/superpowers](https://github.com/obra/superpowers) toolkit |
| Context7 MCP | Library documentation via MCP |

## Running the Standalone Script

If you prefer to skip the Claude skill and run the setup directly:

```bash
cd opencode-wsl-setup-skill/scripts
chmod +x fix_opencode.sh
./fix_opencode.sh
```

The script is idempotent — safe to run multiple times.

## License

MIT
