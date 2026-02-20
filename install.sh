#!/bin/sh

# gft installer
# Usage: curl -fsSL https://cdn.sylvain.pro/bash/gft@latest/install.sh | sh

set -e

VERSION="1.0.0"
CDN="https://cdn.sylvain.pro/bash"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[1;94m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
NC='\033[0m'

printf "${BLUE}gft %s installer${NC}\n" "$VERSION"
printf "\n"

# ─── Install directory ───────────────────────────────────────────────

if [ -w "/usr/local/bin" ]; then
    INSTALL_DIR="/usr/local/bin"
elif [ -w "$HOME/.local/bin" ]; then
    INSTALL_DIR="$HOME/.local/bin"
    mkdir -p "$INSTALL_DIR"
else
    INSTALL_DIR="$HOME/bin"
    mkdir -p "$INSTALL_DIR"
fi

printf "${BLUE}Install directory:${NC} %s\n" "$INSTALL_DIR"

# ─── Download gft ───────────────────────────────────────────────────

printf "${BLUE}Downloading gft...${NC}\n"

if curl -fsSL "${CDN}/gft@${VERSION}/gft" -o "$INSTALL_DIR/gft"; then
    printf "${GREEN}Downloaded${NC}\n"
else
    printf "${RED}Download failed${NC}\n"
    exit 1
fi

chmod +x "$INSTALL_DIR/gft"
ln -sf "$INSTALL_DIR/gft" "$INSTALL_DIR/gfv"
printf "${GREEN}gft installed (alias: gfv)${NC}\n"

# ─── Bash completion ─────────────────────────────────────────────────

BASH_COMP_DIR="/usr/share/bash-completion/completions"
LOCAL_BASH_COMP_DIR="$HOME/.local/share/bash-completion/completions"

BASH_COMP_DEST=""
if [ -w "$BASH_COMP_DIR" ]; then
    BASH_COMP_DEST="$BASH_COMP_DIR/gft"
elif mkdir -p "$LOCAL_BASH_COMP_DIR" 2>/dev/null; then
    BASH_COMP_DEST="$LOCAL_BASH_COMP_DIR/gft"
fi

if [ -n "$BASH_COMP_DEST" ]; then
    if curl -fsSL "${CDN}/gft@${VERSION}/completions/gft.bash" -o "$BASH_COMP_DEST" 2>/dev/null; then
        printf "${GREEN}Bash completion installed${NC}\n"
    fi
fi

# ─── Zsh completion ──────────────────────────────────────────────────

ZSH_COMP_DIR="/usr/share/zsh/vendor-completions"
LOCAL_ZSH_COMP_DIR="$HOME/.local/share/zsh/site-functions"

ZSH_COMP_DEST=""
if [ -w "$ZSH_COMP_DIR" ]; then
    ZSH_COMP_DEST="$ZSH_COMP_DIR/_gft"
elif mkdir -p "$LOCAL_ZSH_COMP_DIR" 2>/dev/null; then
    ZSH_COMP_DEST="$LOCAL_ZSH_COMP_DIR/_gft"
fi

if [ -n "$ZSH_COMP_DEST" ]; then
    if curl -fsSL "${CDN}/gft@${VERSION}/completions/_gft" -o "$ZSH_COMP_DEST" 2>/dev/null; then
        printf "${GREEN}Zsh completion installed${NC}\n"
    fi
fi

# ─── PATH ────────────────────────────────────────────────────────────

case ":$PATH:" in
    *":$INSTALL_DIR:"*) ;;
    *)
        SHELL_CONFIG=""
        if [ -n "${ZSH_VERSION:-}" ]; then
            SHELL_CONFIG="$HOME/.zshrc"
        elif [ -f "$HOME/.bashrc" ]; then
            SHELL_CONFIG="$HOME/.bashrc"
        elif [ -f "$HOME/.bash_profile" ]; then
            SHELL_CONFIG="$HOME/.bash_profile"
        elif [ -f "$HOME/.profile" ]; then
            SHELL_CONFIG="$HOME/.profile"
        fi

        if [ -n "$SHELL_CONFIG" ]; then
            printf "\n# Added by gft installer\nexport PATH=\"%s:\$PATH\"\n" "$INSTALL_DIR" >> "$SHELL_CONFIG"
            printf "${YELLOW}PATH updated in %s — reload your shell${NC}\n" "$SHELL_CONFIG"
        else
            printf "${YELLOW}Add to your shell config: export PATH=\"%s:\$PATH\"${NC}\n" "$INSTALL_DIR"
        fi
        ;;
esac

# ─── Done ────────────────────────────────────────────────────────────

printf "\n${GREEN}Done!${NC} Run: ${CYAN}gft --help${NC}\n"
