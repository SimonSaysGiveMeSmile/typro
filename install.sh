#!/bin/zsh
set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
BINARY=/usr/local/bin/typro-fix
CONFIG=~/.typro

echo "Building typro-fix..."
cd "$REPO_DIR"
swift build -c release --product typro-fix
sudo cp .build/release/typro-fix "$BINARY"
echo "Installed $BINARY"

# Write default config if missing
if [[ ! -f "$CONFIG" ]]; then
    echo "auto_replace=false" > "$CONFIG"
    echo "Created $CONFIG (set auto_replace=true to skip confirmation)"
fi

# Shell integration block
SHELL_BLOCK='
# --- typro-fix ---
_typro_auto() {
    local cfg=~/.typro
    [[ -f "$cfg" ]] && grep -q "auto_replace=true" "$cfg"
}

# fix <cmd>: run with typo correction + optional confirmation
fix() {
    local fixed
    fixed=$(typro-fix "$@") || { eval "$@"; return; }
    if [[ "$fixed" == "$*" ]]; then
        eval "$@"
    elif _typro_auto; then
        echo "typro: $*  →  $fixed"
        eval "$fixed"
    else
        echo "→ $fixed"
        read -q "REPLY?Run? [y/n] " && echo && eval "$fixed" || echo
    fi
}

# Ctrl+F: fix the current line buffer in-place, then accept
_typro_fix_line() {
    local fixed
    fixed=$(typro-fix "${(z)BUFFER}") 2>/dev/null || return
    if [[ "$fixed" != "$BUFFER" ]]; then
        BUFFER="$fixed"
        CURSOR=${#BUFFER}
    fi
    zle accept-line
}
zle -N _typro_fix_line
bindkey "^F" _typro_fix_line
# --- end typro-fix ---'

ZSHRC=~/.zshrc
if grep -q "typro-fix" "$ZSHRC" 2>/dev/null; then
    echo "Shell integration already present in $ZSHRC — skipping."
else
    echo "$SHELL_BLOCK" >> "$ZSHRC"
    echo "Added shell integration to $ZSHRC"
fi

echo ""
echo "Done. Restart your terminal or run:  source ~/.zshrc"
echo ""
echo "Usage:"
echo "  fix gti comit -m 'mesage'   # confirm before running"
echo "  <type command> then Ctrl+F  # fix in-place and execute"
echo "  echo 'auto_replace=true' > ~/.typro  # skip confirmation"
