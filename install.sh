#!/data/data/com.termux/files/usr/bin/bash
# EasyCompressor Installer

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$HOME/.local/bin"
INSTALL_PATH="$BIN_DIR/easycompressor"

echo ""
echo "  EasyCompressor — Installer"
echo "  ──────────────────────────"
echo ""

# Check Termux
if [[ -z "$TERMUX_VERSION" && ! -d "/data/data/com.termux" ]]; then
    echo "  ⚠  This script is designed for Termux on Android."
    echo "     Proceeding anyway…"
    echo ""
fi

# Check source file
if [[ ! -f "$SCRIPT_DIR/easycompressor.sh" ]]; then
    echo "  ✗  easycompressor.sh not found in $SCRIPT_DIR"
    exit 1
fi

# Check / install dependencies
echo "  Checking dependencies…"
missing=()
command -v ffmpeg        >/dev/null 2>&1 || missing+=("ffmpeg")
command -v termux-dialog >/dev/null 2>&1 || missing+=("termux-api")

if [[ ${#missing[@]} -gt 0 ]]; then
    echo ""
    echo "  Missing: ${missing[*]}"
    echo "  Installing with pkg…"
    pkg install -y "${missing[@]}" 2>&1 | tail -3
    echo ""
fi

# Create bin directory
mkdir -p "$BIN_DIR"

# Copy and link
cp "$SCRIPT_DIR/easycompressor.sh" "$INSTALL_PATH"
chmod +x "$INSTALL_PATH"

# Ensure ~/.local/bin is on PATH
if ! echo "$PATH" | grep -q "$BIN_DIR"; then
    local_rc="$HOME/.bashrc"
    [[ -f "$HOME/.zshrc" ]] && local_rc="$HOME/.zshrc"
    echo "export PATH=\"$BIN_DIR:\$PATH\"" >> "$local_rc"
    echo "  Added $BIN_DIR to PATH in $local_rc"
fi

echo ""
echo "  ✓ Installed:  $INSTALL_PATH"
echo ""
echo "  Run with:     easycompressor"
echo ""
echo "  Also install 'Termux:API' from F-Droid if not done yet."
echo ""
