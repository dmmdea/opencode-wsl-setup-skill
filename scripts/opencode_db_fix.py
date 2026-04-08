#!/usr/bin/env python3
"""
OpenCode DB Path Fixer
======================
Detects and repairs mangled file paths in the OpenCode SQLite database.

The bug: WSL paths like /home/user/.local/share/opencode/sessions/abc123/
sometimes get stored with mixed separators or Windows-style prefixes,
causing the web UI to show an empty sidebar even though session data exists.

Usage:
    python3 opencode_db_fix.py --dry-run     # Show what would be fixed
    python3 opencode_db_fix.py --apply        # Fix paths (auto-backup first)

The script always creates a timestamped backup before modifying the database.
"""

import argparse
import os
import re
import shutil
import sqlite3
import sys
from datetime import datetime
from pathlib import Path


DEFAULT_DB_PATH = os.path.expanduser("~/.local/share/opencode/opencode.db")


def find_mangled_paths(cursor):
    """
    Scan all text columns in all tables for paths that look like they've been
    mangled — Windows drive letters, backslashes, or mixed separators in what
    should be Unix paths.
    """
    mangled = []

    # Get all tables
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
    tables = [row[0] for row in cursor.fetchall()]

    for table in tables:
        # Get column info
        cursor.execute(f"PRAGMA table_info({table});")
        columns = cursor.fetchall()
        text_cols = [col[1] for col in columns if col[2].upper() in ("TEXT", "VARCHAR", "")]

        if not text_cols:
            continue

        # Check each text column for mangled paths
        pk_col = next((col[1] for col in columns if col[5] == 1), columns[0][1])

        for col in text_cols:
            cursor.execute(f"SELECT rowid, [{col}] FROM [{table}] WHERE [{col}] IS NOT NULL;")
            for rowid, value in cursor.fetchall():
                if not isinstance(value, str):
                    continue

                # Patterns that indicate mangling:
                # 1. Windows drive letter prefix: C:\... or C:/...
                # 2. Backslashes in paths that should be Unix
                # 3. Mixed separators: /home/user\\.local
                # 4. UNC-style: \\wsl$\... or \\wsl.localhost\...
                patterns = [
                    (r'[A-Z]:\\', "Windows drive letter"),
                    (r'\\\\wsl', "UNC WSL path"),
                    (r'/home/[^/]+\\', "Mixed separators after /home/"),
                    (r'\\\.local\\', "Backslash in .local path"),
                ]

                for pattern, reason in patterns:
                    if re.search(pattern, value):
                        mangled.append({
                            "table": table,
                            "column": col,
                            "rowid": rowid,
                            "original": value,
                            "reason": reason,
                        })
                        break  # One match per cell is enough

    return mangled


def fix_path(original):
    """
    Convert a mangled path back to a proper Unix path.

    Examples:
        C:\\Users\\user\\...\\opencode\\sessions\\abc → /home/user/.local/share/opencode/sessions/abc
        /home/user\\.local\\share → /home/user/.local/share
        \\\\wsl$\\Ubuntu\\home\\user\\.local → /home/user/.local
    """
    path = original

    # Strip UNC WSL prefix
    path = re.sub(r'^\\\\wsl[\$\.]?\\[^\\]+', '', path)
    path = re.sub(r'^\\\\wsl\.localhost\\[^\\]+', '', path)

    # Strip Windows drive letter prefix and try to find the /home/ anchor
    if re.match(r'[A-Z]:', path):
        # Look for /home/ or \home\ in the path
        home_match = re.search(r'[/\\](home[/\\])', path)
        if home_match:
            path = '/' + path[home_match.start() + 1:]
        else:
            # No /home/ anchor — just strip the drive letter
            path = path[2:]

    # Normalize all backslashes to forward slashes
    path = path.replace('\\', '/')

    # Collapse multiple slashes
    path = re.sub(r'/+', '/', path)

    return path


def main():
    parser = argparse.ArgumentParser(description="Fix mangled paths in OpenCode database")
    parser.add_argument("--db", default=DEFAULT_DB_PATH, help="Path to opencode.db")
    parser.add_argument("--dry-run", action="store_true", help="Show what would be fixed without changing anything")
    parser.add_argument("--apply", action="store_true", help="Apply fixes (creates backup first)")

    args = parser.parse_args()

    if not args.dry_run and not args.apply:
        parser.error("Specify either --dry-run or --apply")

    db_path = args.db
    if not os.path.exists(db_path):
        print(f"ERROR: Database not found at {db_path}")
        sys.exit(1)

    print(f"Scanning: {db_path}")

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    mangled = find_mangled_paths(cursor)

    if not mangled:
        print("No mangled paths found. Database is clean.")
        conn.close()
        sys.exit(0)

    print(f"\nFound {len(mangled)} mangled path(s):\n")

    for i, entry in enumerate(mangled, 1):
        fixed = fix_path(entry["original"])
        print(f"  [{i}] {entry['table']}.{entry['column']} (row {entry['rowid']})")
        print(f"      Reason:   {entry['reason']}")
        print(f"      Original: {entry['original'][:120]}...")
        print(f"      Fixed:    {fixed[:120]}...")
        print()

    if args.dry_run:
        print(f"Dry run complete. {len(mangled)} path(s) would be fixed.")
        print("Run with --apply to fix them.")
        conn.close()
        sys.exit(0)

    # Create backup
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_path = f"{db_path}.bak.{timestamp}"
    shutil.copy2(db_path, backup_path)
    print(f"Backup created: {backup_path}")

    # Apply fixes
    fixed_count = 0
    for entry in mangled:
        fixed = fix_path(entry["original"])
        if fixed != entry["original"]:
            cursor.execute(
                f"UPDATE [{entry['table']}] SET [{entry['column']}] = ? WHERE rowid = ?;",
                (fixed, entry["rowid"]),
            )
            fixed_count += 1

    conn.commit()
    conn.close()

    print(f"\nDone. Fixed {fixed_count} path(s).")
    print(f"Backup at: {backup_path}")


if __name__ == "__main__":
    main()
