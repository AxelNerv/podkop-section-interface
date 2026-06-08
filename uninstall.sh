#!/bin/sh
# Uninstall Podkop Section Interface Patch — restores original files.
# Usage: sh uninstall.sh

BACKUP_DIR="/etc/podkop-patch-backup"
SECTION_JS="/www/luci-static/resources/view/podkop/section.js"
PODKOP_BIN="/usr/bin/podkop"

echo "=== Podkop Section Interface Patch — Uninstall ==="

if [ ! -d "$BACKUP_DIR" ]; then
    echo "ERROR: backup directory $BACKUP_DIR not found."
    echo "Cannot restore. Manual recovery needed."
    exit 1
fi

if [ ! -f "$BACKUP_DIR/podkop.orig" ] || [ ! -f "$BACKUP_DIR/section.js.orig" ]; then
    echo "ERROR: backup files missing in $BACKUP_DIR"
    exit 1
fi

echo "Restoring original files..."
cp "$BACKUP_DIR/section.js.orig" "$SECTION_JS"
cp "$BACKUP_DIR/podkop.orig"     "$PODKOP_BIN"
chmod +x "$PODKOP_BIN"

echo "Removing backup directory..."
rm -rf "$BACKUP_DIR"

echo ""
echo "=== Uninstalled. Original files restored. ==="
echo "Reload LuCI (Ctrl+Shift+R in browser) and restart Podkop:"
echo "  /etc/init.d/podkop restart"
