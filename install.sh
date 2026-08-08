#!/usr/bin/env bash
set -euo pipefail

{ # download guard — prevents partial execution if connection drops

# --- Colors (only if terminal) ---
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    BOLD='\033[1m'
    RESET='\033[0m'
else
    RED=''
    GREEN=''
    BOLD=''
    RESET=''
fi

error() { echo -e "${RED}error${RESET}: $*" >&2; exit 1; }
info()  { echo -e "${BOLD}$*${RESET}"; }

# --- Help ---
if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    echo "SDLC Harness Installer"
    echo ""
    echo "Usage:"
    echo "  curl -fsSL <url> | bash              Install to current project"
    echo "  curl -fsSL <url> | bash -s -- --global  Install CLI globally"
    echo ""
    echo "Options:"
    echo "  --global    Install sdlc-wizard CLI globally via npm"
    echo "  --help, -h  Show this help message"
    echo ""
    echo "Requires Node.js >= 18 and npm."
    exit 0
fi

# --- Unknown argument check ---
if [ -n "${1:-}" ] && [ "${1:-}" != "--global" ]; then
    error "Unknown option: $1 (use --help for usage)"
fi

# --- Check Node.js ---
if ! command -v node >/dev/null 2>&1; then
    error "Node.js is required but not found. Install from https://nodejs.org"
fi

NODE_VERSION=$(node -v | sed 's/v//')
NODE_MAJOR=$(echo "$NODE_VERSION" | cut -d. -f1)
if [ "$NODE_MAJOR" -lt 18 ]; then
    error "Node.js >= 18 required (found v${NODE_VERSION}). Update from https://nodejs.org"
fi

# --- Check npm ---
if ! command -v npm >/dev/null 2>&1; then
    error "npm is required but not found. It ships with Node.js — reinstall from https://nodejs.org"
fi

if ! command -v npx >/dev/null 2>&1; then
    error "npx is required but not found. It ships with npm — reinstall from https://nodejs.org"
fi

# --- Install ---
if [ "${1:-}" = "--global" ]; then
    info "Installing agentic-sdlc-wizard globally..."
    npm install -g agentic-sdlc-wizard

    if command -v sdlc-wizard >/dev/null 2>&1; then
        echo -e "${GREEN}Installed successfully${RESET}: sdlc-wizard $(sdlc-wizard --version)"
        echo ""
        echo "Run in any project directory:"
        echo "  sdlc-wizard init"
    else
        error "Installation completed but sdlc-wizard not found on PATH"
    fi
else
    info "Installing SDLC Harness to current project..."
    npx -y agentic-sdlc-wizard init

    if [ -f ".claude/hooks/sdlc-prompt-check.sh" ]; then
        echo ""
        echo -e "${GREEN}Installed successfully${RESET}"
        echo "Restart Claude Code to activate hooks: type /exit then claude"
    else
        error "Installation completed but wizard files not found. Check output above for errors"
    fi
fi

} # end download guard
