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

    # Detect a working Python interpreter. On Windows, `python3` may be a
    # Microsoft Store redirector stub that exits non-zero without running.
    local PY=""
    for cand in python3 python py; do
        command -v "$cand" >/dev/null 2>&1 || continue
        if [ "$cand" = "py" ]; then
            "$cand" -3 -c "print(1)" >/dev/null 2>&1 && PY="py -3" && break
        else
            "$cand" -c "print(1)" >/dev/null 2>&1 && PY="$cand" && break
        fi
    done
    if [ -z "$PY" ]; then
        echo "Error: no working Python interpreter found (tried python3, python, py)."
        return 1
    fi

    _get_current() { [ -f "$CURRENT_FILE" ] && cat "$CURRENT_FILE" | tr -d '[:space:]' || echo ""; }
    _set_current() { echo "$1" > "$CURRENT_FILE"; }

    # Save credentials + identity fields only (~1 KB per account)
    _save_account() {
        local n="$1"
        local cred_src="$CLAUDE_DIR/.credentials.json"
        local out="$BACKUP_DIR/$n.creds.json"
        [ -f "$cred_src" ] || { echo "  no credentials file, nothing to save"; return 1; }
        $PY - "$cred_src" "$CLAUDE_CONFIG" "$out" <<'PYEOF'
import json, sys
creds = json.load(open(sys.argv[1], encoding="utf-8"))
config = {}
try:
    config = json.load(open(sys.argv[2], encoding="utf-8"))
except (FileNotFoundError, json.JSONDecodeError):
    pass
out = {
    "credentials": creds,
    "oauthAccount": config.get("oauthAccount"),
    "userID": config.get("userID"),
}
json.dump(out, open(sys.argv[3], "w", encoding="utf-8"), indent=2, ensure_ascii=False)
PYEOF
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
            for f in "$BACKUP_DIR"/*.creds.json; do
                [ -f "$f" ] || continue
                local n; n=$(basename "$f" .creds.json)
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
            local f="$BACKUP_DIR/$name.creds.json"
            [ -f "$f" ] || { echo "Account '$name' not found."; return 1; }
            rm -f "$f"
            local cur; cur=$(_get_current)
            [ "$cur" = "$name" ] && rm -f "$CURRENT_FILE"
            echo "Deleted '$name'"
            ;;
        refresh)
            local TOKEN_URL="https://platform.claude.com/v1/oauth/token"
            local CLIENT_ID="9d1c250a-e61b-44d9-88ed-5944d1962f5e"
            local SCOPE="user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload"
            local cur; cur=$(_get_current)
            local live_cred="$CLAUDE_DIR/.credentials.json"
            local refreshed_live=0

            for f in "$BACKUP_DIR"/*.creds.json; do
                [ -f "$f" ] || continue
                local acc; acc=$(basename "$f" .creds.json)
                local rt
                rt=$($PY - "$f" <<'PYEOF' 2>/dev/null
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
print(d["credentials"]["claudeAiOauth"]["refreshToken"])
PYEOF
)
                if [ -z "$rt" ]; then echo "  [$acc] no refresh token, skipping."; continue; fi

                echo "  Refreshing '$acc'..."
                local resp; resp=$(curl -s -X POST "$TOKEN_URL" \
                    -H "Content-Type: application/json" \
                    -d "{\"grant_type\":\"refresh_token\",\"refresh_token\":\"$rt\",\"client_id\":\"$CLIENT_ID\",\"scope\":\"$SCOPE\"}")

                if echo "$resp" | $PY -c "import json,sys; d=json.load(sys.stdin); exit(0 if 'access_token' in d else 1)" 2>/dev/null; then
                    local sync_live=0
                    [ "$acc" = "$cur" ] && sync_live=1
                    echo "$resp" | $PY - "$f" "$live_cred" "$sync_live" <<'PYEOF'
import json, sys, time
path, live_cred, sync_live = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
data = json.load(open(path, encoding="utf-8"))
resp = json.load(sys.stdin)
target = data["credentials"]
target["claudeAiOauth"]["accessToken"] = resp["access_token"]
if "refresh_token" in resp:
    target["claudeAiOauth"]["refreshToken"] = resp["refresh_token"]
if "expires_in" in resp:
    target["claudeAiOauth"]["expiresAt"] = int(time.time() * 1000) + resp["expires_in"] * 1000
json.dump(data, open(path, "w", encoding="utf-8"), indent=2, ensure_ascii=False)
if sync_live:
    json.dump(data["credentials"], open(live_cred, "w", encoding="utf-8"), indent=2, ensure_ascii=False)
PYEOF
                    [ "$acc" = "$cur" ] && refreshed_live=1
                    echo "    OK"
                else
                    local err; err=$(echo "$resp" | $PY -c "import json,sys; d=json.load(sys.stdin); e=d.get('error',{}); print(e.get('message',e) if isinstance(e,dict) else e)" 2>/dev/null)
                    echo "    FAILED: $err"
                fi
                sleep 2
            done

            # Refresh live credentials if not covered by any backup
            if [ $refreshed_live -eq 0 ] && [ -f "$live_cred" ]; then
                local rt; rt=$($PY -c "import json,sys; d=json.load(open(sys.argv[1], encoding='utf-8')); print(d['claudeAiOauth']['refreshToken'])" "$live_cred" 2>/dev/null)
                if [ -n "$rt" ]; then
                    echo "  Refreshing '(live)'..."
                    local resp; resp=$(curl -s -X POST "$TOKEN_URL" \
                        -H "Content-Type: application/json" \
                        -d "{\"grant_type\":\"refresh_token\",\"refresh_token\":\"$rt\",\"client_id\":\"$CLIENT_ID\",\"scope\":\"$SCOPE\"}")
                    if echo "$resp" | $PY -c "import json,sys; d=json.load(sys.stdin); exit(0 if 'access_token' in d else 1)" 2>/dev/null; then
                        echo "$resp" | $PY -c "
import json, sys, time
cred = json.load(open(sys.argv[1], encoding='utf-8'))
resp = json.load(sys.stdin)
cred['claudeAiOauth']['accessToken'] = resp['access_token']
if 'refresh_token' in resp:
    cred['claudeAiOauth']['refreshToken'] = resp['refresh_token']
if 'expires_in' in resp:
    cred['claudeAiOauth']['expiresAt'] = int(time.time() * 1000) + resp['expires_in'] * 1000
json.dump(cred, open(sys.argv[1], 'w', encoding='utf-8'), indent=2, ensure_ascii=False)
" "$live_cred"
                        echo "    OK"
                    fi
                fi
            fi
            ;;
        schedule)
            local SCRIPT="$HOME/.claude-switch/ccs.sh"
            local CRON_TAG="# ccs auto-refresh"
            local CRON_CMD="0 * * * * bash -c \". \\\"$SCRIPT\\\" && ccs refresh\" >> \"$HOME/.claude-accounts/refresh.log\" 2>&1  $CRON_TAG"
            if crontab -l 2>/dev/null | grep -qF "$CRON_TAG"; then
                echo "Already scheduled."
            else
                (crontab -l 2>/dev/null; echo "$CRON_CMD") | crontab -
                echo "Scheduled: 'ccs refresh' runs every hour."
                echo "  Log: $HOME/.claude-accounts/refresh.log"
            fi
            ;;
        unschedule)
            local CRON_TAG="# ccs auto-refresh"
            if crontab -l 2>/dev/null | grep -qF "$CRON_TAG"; then
                crontab -l | grep -vF "$CRON_TAG" | crontab -
                echo "Schedule removed."
            else
                echo "No schedule found."
            fi
            ;;
        uninstall)
            local INSTALL_DIR="$HOME/.claude-switch"

            # 1. Remove cron job
            local CRON_TAG="# ccs auto-refresh"
            if crontab -l 2>/dev/null | grep -qF "$CRON_TAG"; then
                crontab -l | grep -vF "$CRON_TAG" | crontab -
                echo "  Removed cron job."
            fi

            # 2. Remove source line from rc files
            for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.bash_profile"; do
                [ -f "$rc" ] || continue
                if grep -qF "$INSTALL_DIR" "$rc" 2>/dev/null; then
                    # Remove the "# Claude Code Switch" comment line and the source line below it
                    sed -i.bak "/# Claude Code Switch/{N;/claude-switch/d}" "$rc" 2>/dev/null || \
                    grep -vF "$INSTALL_DIR" "$rc" > "$rc.tmp" && mv "$rc.tmp" "$rc"
                    echo "  Removed entry from $rc"
                fi
            done

            # 3. Remove install directory (do this last — script may be running from it)
            if [ -d "$INSTALL_DIR" ]; then
                rm -rf "$INSTALL_DIR"
                echo "  Removed $INSTALL_DIR"
            fi

            echo "Uninstalled."
            echo "  Note: account backups in '$HOME/.claude-accounts/' were kept."
            echo "  Delete that folder manually if you no longer need them."
            ;;
        login)
            [ -z "$name" ] && echo "Usage: ccs login <n>" && return 1
            command -v claude >/dev/null 2>&1 || { echo "Error: 'claude' CLI not found in PATH."; return 1; }
            _autosave   # flush current state before login overwrites .credentials.json
            echo "Starting Claude Code login flow..."
            if claude auth login; then
                [ -f "$CLAUDE_DIR/.credentials.json" ] || { echo "Login completed but no credentials file was written."; return 1; }
                _save_account "$name"
                _set_current "$name"
                echo "Logged in as '$name'"
            else
                echo "Login failed or cancelled."
                return 1
            fi
            ;;
        switch)
            [ -z "$name" ] && echo "Usage: ccs switch <n>" && return 1
            local target="$name"
            local cur; cur=$(_get_current)
            if [ "$cur" = "$target" ]; then
                echo "Already on '$target'"
                return 0
            fi
            echo "Switching to '$target'..."
            local f="$BACKUP_DIR/$target.creds.json"
            [ -f "$f" ] || { echo "Account '$target' not found. Run: ccs save $target"; return 1; }

            _autosave   # flush live state → current account's backup

            mkdir -p "$CLAUDE_DIR"
            $PY - "$f" "$CLAUDE_DIR/.credentials.json" "$CLAUDE_CONFIG" <<'PYEOF'
import json, sys, os
src, live_creds, live_config = sys.argv[1:4]
data = json.load(open(src, encoding="utf-8"))
creds = data["credentials"]
oauth_account = data.get("oauthAccount")
user_id = data.get("userID")

json.dump(creds, open(live_creds, "w", encoding="utf-8"), indent=2, ensure_ascii=False)

# Merge identity fields into live .claude.json, preserving everything else
config = {}
if os.path.exists(live_config):
    try:
        config = json.load(open(live_config, encoding="utf-8"))
    except json.JSONDecodeError:
        pass
if oauth_account is not None:
    config["oauthAccount"] = oauth_account
if user_id is not None:
    config["userID"] = user_id
json.dump(config, open(live_config, "w", encoding="utf-8"), indent=2, ensure_ascii=False)
PYEOF
            _set_current "$target"
            echo "Switched to '$target'"
            ;;
        "")
            echo ""
            echo "  ccs login <n>      Log in via 'claude auth login' and save as <n>"
            echo "  ccs save <n>       Save current account"
            echo "  ccs switch <n>     Switch to account"
            echo "  ccs list           List accounts"
            echo "  ccs status         Show current account"
            echo "  ccs refresh        Refresh OAuth tokens for all accounts"
            echo "  ccs schedule       Register hourly auto-refresh (cron)"
            echo "  ccs unschedule     Remove the auto-refresh cron job"
            echo "  ccs delete <n>     Delete a saved account"
            echo "  ccs uninstall      Uninstall ccs"
            echo ""
            ;;
        *)
            echo "Unknown command: '$command'. Run 'ccs' for usage."
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
