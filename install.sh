#!/usr/bin/env bash
# Claude Code Switch - Installer
# Supports: macOS, Linux, WSL, Git Bash
# Usage: curl -fsSL https://raw.githubusercontent.com/Yuelioi/claude-code-switch/main/install.sh | bash

REPO="https://raw.githubusercontent.com/Yuelioi/claude-code-switch/main"
INSTALL_DIR="$HOME/.claude-switch"
TARGET="$INSTALL_DIR/ccs.sh"

mkdir -p "$INSTALL_DIR"

# ── Download or copy ccs.sh ───────────────────────────────────
if [ -t 0 ] && [ -f "$(dirname "$0")/ccs.sh" ]; then
    cp "$(dirname "$0")/ccs.sh" "$TARGET"
    echo "Copied ccs.sh -> $TARGET"
else
    echo "Downloading ccs.sh..."
    curl -fsSL "$REPO/ccs.sh" -o "$TARGET" || { echo "Download failed"; exit 1; }
    echo "  -> $TARGET"
fi

chmod +x "$TARGET"

# ── Detect which rc files to update ──────────────────────────
SOURCE_LINE=". \"$TARGET\""

# Collect candidate rc files based on available shells
RC_FILES=()

# Current shell first
CURRENT_SHELL=$(basename "$SHELL")
case "$CURRENT_SHELL" in
    zsh)  RC_FILES+=("$HOME/.zshrc") ;;
    bash) RC_FILES+=("$HOME/.bashrc") ;;
esac

# Always check the rest too (user may use multiple shells)
for rc in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile"; do
    [ -f "$rc" ] || continue
    # Avoid duplicates
    already=0
    for added in "${RC_FILES[@]}"; do [ "$added" = "$rc" ] && already=1 && break; done
    [ $already -eq 0 ] && RC_FILES+=("$rc")
done

# If nothing found, create rc for current shell
if [ ${#RC_FILES[@]} -eq 0 ]; then
    case "$CURRENT_SHELL" in
        zsh)  touch "$HOME/.zshrc";  RC_FILES+=("$HOME/.zshrc") ;;
        *)    touch "$HOME/.bashrc"; RC_FILES+=("$HOME/.bashrc") ;;
    esac
fi

# ── Write source line ─────────────────────────────────────────
for rc in "${RC_FILES[@]}"; do
    if ! grep -qF "$TARGET" "$rc" 2>/dev/null; then
        printf "\n# Claude Code Switch\n%s\n" "$SOURCE_LINE" >> "$rc"
        echo "Added to $rc"
    else
        echo "Already in $rc"
    fi
done

# ── Done ──────────────────────────────────────────────────────
# Determine reload hint for current shell
case "$CURRENT_SHELL" in
    zsh)  RELOAD="source ~/.zshrc" ;;
    *)    RELOAD="source ~/.bashrc" ;;
esac

echo ""
echo "Installed!"
echo ""
echo "Reload your shell:"
echo "  $RELOAD"
echo ""
echo "Usage:"
echo "  ccs save <name>     Save current account"
echo "  ccs switch <name>   Switch account"
echo "  ccs list            List accounts"
echo "  ccs status          Show current account"
echo "  ccs refresh         Refresh OAuth tokens for all accounts"
echo "  ccs schedule        Register hourly auto-refresh (cron)"
echo "  ccs unschedule      Remove the auto-refresh cron job"
echo "  ccs delete <name>   Delete a saved account"
echo ""
echo "  clauded             claude --dangerously-skip-permissions"
