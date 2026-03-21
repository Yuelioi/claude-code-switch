#!/usr/bin/env bash
# ── Claude Code Account Switcher ──────────────────────────────
# Works both as a sourced function and as a direct script.
# Supports: Git Bash, WSL, Linux, macOS

ccs() {
    local command="${1:-}"
    local name="${2:-}"

    local CLAUDE_CONFIG="$HOME/.claude.json"
    local CLAUDE_DIR="$HOME/.claude"
    local BACKUP_DIR="$HOME/.claude-accounts"

    mkdir -p "$BACKUP_DIR"

    _hash() {
        [ -f "$1" ] || return
        if command -v md5sum &>/dev/null; then
            md5sum "$1" | cut -d' ' -f1          # Linux / Git Bash / WSL
        else
            md5 -q "$1"                           # macOS
        fi
    }
    _eq()   { local a b; a=$(_hash "$1"); b=$(_hash "$2"); [ -n "$a" ] && [ "$a" = "$b" ]; }

    _autosave() {
        [ -f "$CLAUDE_CONFIG" ] || return
        for f in "$BACKUP_DIR"/*.json; do
            [ -f "$f" ] || continue
            local n; n=$(basename "$f" .json)
            if _eq "$CLAUDE_CONFIG" "$f"; then
                cp "$CLAUDE_CONFIG" "$f"
                local d="$BACKUP_DIR/${n}-dir"
                if [ -d "$CLAUDE_DIR" ]; then
                    rm -rf "$d"
                    cp -r "$CLAUDE_DIR" "$d"
                fi
                break
            fi
        done
    }

    case "$command" in
        save)
            [ -z "$name" ] && echo "Usage: ccs save <name>" && return 1
            [ -f "$CLAUDE_CONFIG" ] || { echo "No Claude config found."; return 1; }
            cp "$CLAUDE_CONFIG" "$BACKUP_DIR/$name.json"
            if [ -d "$CLAUDE_DIR" ]; then
                rm -rf "$BACKUP_DIR/$name-dir"
                cp -r "$CLAUDE_DIR" "$BACKUP_DIR/$name-dir"
            fi
            echo "Saved as '$name'"
            ;;
        list)
            echo "Saved accounts:"
            local found=0
            for f in "$BACKUP_DIR"/*.json; do
                [ -f "$f" ] || continue
                echo "  - $(basename "$f" .json)"
                found=1
            done
            [ $found -eq 0 ] && echo "  (none)"
            ;;
        status)
            local cur="unknown"
            for f in "$BACKUP_DIR"/*.json; do
                [ -f "$f" ] || continue
                if _eq "$CLAUDE_CONFIG" "$f"; then
                    cur=$(basename "$f" .json)
                    break
                fi
            done
            if [ "$cur" != "unknown" ]; then
                echo "Current: $cur"
            else
                echo "Current: unknown (not saved yet)"
            fi
            ;;
        delete)
            [ -z "$name" ] && echo "Usage: ccs delete <name>" && return 1
            local tj="$BACKUP_DIR/$name.json"
            [ -f "$tj" ] || { echo "Account '$name' not found."; return 1; }
            rm -f "$tj"
            rm -rf "$BACKUP_DIR/$name-dir"
            echo "Deleted '$name'"
            ;;
        "")
            echo ""
            echo "  ccs save <name>     Save current account"
            echo "  ccs <name>          Switch account"
            echo "  ccs list            List accounts"
            echo "  ccs status          Show current account"
            echo "  ccs delete <name>   Delete a saved account"
            echo ""
            ;;
        *)
            local target="$command"
            echo "Switching to '$target'..."
            _autosave
            local tj="$BACKUP_DIR/$target.json"
            [ -f "$tj" ] || { echo "Account '$target' not found. Run: ccs save $target"; return 1; }
            cp "$tj" "$CLAUDE_CONFIG"
            local td="$BACKUP_DIR/$target-dir"
            if [ -d "$td" ]; then
                rm -rf "$CLAUDE_DIR"
                cp -r "$td" "$CLAUDE_DIR"
            fi
            echo "Switched to '$target'"
            ;;
    esac
}

clauded() { claude --dangerously-skip-permissions "$@"; }

# If executed directly as a script (not sourced), forward args to the function
# Compatible with bash and zsh
_ccs_is_sourced() {
    if [ -n "$ZSH_VERSION" ]; then
        [[ $ZSH_EVAL_CONTEXT == *:file* ]]
    else
        [ "${BASH_SOURCE[0]}" != "${0}" ]
    fi
}
_ccs_is_sourced || ccs "$@"
# ──────────────────────────────────────────────────────────────
