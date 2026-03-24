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
    local CURRENT_FILE="$BACKUP_DIR/.current"   # tracks active account name

    mkdir -p "$BACKUP_DIR"

    _get_current() { [ -f "$CURRENT_FILE" ] && cat "$CURRENT_FILE" | tr -d '[:space:]' || echo ""; }
    _set_current() { echo "$1" > "$CURRENT_FILE"; }

    _save_account() {
        local n="$1"
        [ -f "$CLAUDE_CONFIG" ] && cp "$CLAUDE_CONFIG" "$BACKUP_DIR/$n.json"
        if [ -d "$CLAUDE_DIR" ]; then
            rm -rf "$BACKUP_DIR/$n-dir"
            cp -r "$CLAUDE_DIR" "$BACKUP_DIR/$n-dir"
        fi
    }

    _autosave() {
        local cur; cur=$(_get_current)
        [ -z "$cur" ] && return
        echo "  Auto-saving '$cur'..."
        _save_account "$cur"
    }

    case "$command" in
        save)
            [ -z "$name" ] && echo "Usage: ccs save <n>" && return 1
            [ -f "$CLAUDE_CONFIG" ] || { echo "No Claude config found."; return 1; }
            _save_account "$name"
            _set_current "$name"
            echo "Saved as '$name'"
            ;;
        list)
            local cur; cur=$(_get_current)
            echo "Saved accounts:"
            local found=0
            for f in "$BACKUP_DIR"/*.json; do
                [ -f "$f" ] || continue
                local n; n=$(basename "$f" .json)
                if [ "$n" = "$cur" ]; then
                    echo "  * $n (current)"
                else
                    echo "  - $n"
                fi
                found=1
            done
            [ $found -eq 0 ] && echo "  (none)"
            ;;
        status)
            local cur; cur=$(_get_current)
            if [ -n "$cur" ]; then
                echo "Current: $cur"
            else
                echo "Current: unknown (run 'ccs save <n>' first)"
            fi
            ;;
        delete)
            [ -z "$name" ] && echo "Usage: ccs delete <n>" && return 1
            local tj="$BACKUP_DIR/$name.json"
            [ -f "$tj" ] || { echo "Account '$name' not found."; return 1; }
            rm -f "$tj"
            rm -rf "$BACKUP_DIR/$name-dir"
            # Clear marker if we deleted the active account
            local cur; cur=$(_get_current)
            [ "$cur" = "$name" ] && rm -f "$CURRENT_FILE"
            echo "Deleted '$name'"
            ;;
        "")
            echo ""
            echo "  ccs save <n>    Save current account"
            echo "  ccs <n>         Switch to account"
            echo "  ccs list           List accounts"
            echo "  ccs status         Show current account"
            echo "  ccs delete <n>  Delete a saved account"
            echo ""
            ;;
        *)
            local target="$command"
            local cur; cur=$(_get_current)
            if [ "$cur" = "$target" ]; then
                echo "Already on '$target'"
                return 0
            fi
            echo "Switching to '$target'..."
            local tj="$BACKUP_DIR/$target.json"
            [ -f "$tj" ] || { echo "Account '$target' not found. Run: ccs save $target"; return 1; }

            _autosave   # flush live state → current account's backup

            cp "$tj" "$CLAUDE_CONFIG"
            local td="$BACKUP_DIR/$target-dir"
            if [ -d "$td" ]; then
                rm -rf "$CLAUDE_DIR"
                cp -r "$td" "$CLAUDE_DIR"
            fi
            _set_current "$target"
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
