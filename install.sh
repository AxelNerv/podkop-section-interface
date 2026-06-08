#!/bin/sh
# Podkop Section Interface Patch
# Adds "Section Interface" dropdown to LuCI Podkop sections.
# When set, automatically routes all traffic from that interface subnet through the section.
#
# Supported: Podkop v0.7.17+, OpenWrt 23.x / 24.x
# Usage: sh install.sh

set -e

REPO_RAW="https://raw.githubusercontent.com/AxelNerv/podkop-section-interface/main"
SECTION_JS="/www/luci-static/resources/view/podkop/section.js"
PODKOP_BIN="/usr/bin/podkop"
BACKUP_DIR="/etc/podkop-patch-backup"

echo "=== Podkop Section Interface Patch ==="

# --- Check prerequisites ---
if [ ! -f "$PODKOP_BIN" ]; then
    echo "ERROR: podkop not found at $PODKOP_BIN"
    exit 1
fi
if [ ! -f "$SECTION_JS" ]; then
    echo "ERROR: LuCI section.js not found at $SECTION_JS"
    exit 1
fi

# --- Check if already patched ---
if grep -q "section_interface" "$PODKOP_BIN"; then
    echo "ERROR: patch already applied. To reinstall, run uninstall.sh first."
    exit 1
fi

# --- Backup originals ---
echo "[1/3] Creating backups in $BACKUP_DIR ..."
mkdir -p "$BACKUP_DIR"
cp "$SECTION_JS"  "$BACKUP_DIR/section.js.orig"
cp "$PODKOP_BIN"  "$BACKUP_DIR/podkop.orig"
echo "      Backups saved."

# --- Patch section.js ---
echo "[2/3] Patching LuCI section.js ..."
wget -q -O "$SECTION_JS" "$REPO_RAW/section.js"
echo "      Done."

# --- Patch /usr/bin/podkop ---
echo "[3/3] Patching /usr/bin/podkop ..."

# Write the new function to a temp file
cat > /tmp/_podkop_func.sh << 'FUNC_EOF'
include_source_ips_in_routing_handler() {
    local section="$1"

    local fully_routed_ips rule_tag
    config_get fully_routed_ips "$section" "fully_routed_ips"

    local section_interface interface_subnet
    config_get section_interface "$section" "section_interface"
    if [ -n "$section_interface" ]; then
        local iface_dev
        if ip link show "$section_interface" > /dev/null 2>&1; then
            iface_dev="$section_interface"
        else
            iface_dev=$(ifstatus "$section_interface" 2>/dev/null | jsonfilter -e '@.l3_device' 2>/dev/null)
        fi
        if [ -n "$iface_dev" ]; then
            interface_subnet=$(ip addr show "$iface_dev" 2>/dev/null | awk '/inet / {print $2}' | head -1)
        fi
        if [ -z "$interface_subnet" ]; then
            log "section_interface '$section_interface' not found or has no IPv4 address" "warn"
            section_interface=""
        else
            log "section $section: adding subnet $interface_subnet from interface $section_interface ($iface_dev) to fully routed" "info"
        fi
    fi

    if [ -n "$fully_routed_ips" ] || [ -n "$interface_subnet" ]; then
        rule_tag="$(gen_id)"
        config=$(
            sing_box_cm_add_route_rule \
                "$config" "$rule_tag" "$SB_TPROXY_INBOUND_TAG" "$(get_outbound_tag_by_section "$section")"
        )
        config_list_foreach "$section" "fully_routed_ips" include_source_ip_in_routing_handler "$rule_tag"
        if [ -n "$interface_subnet" ]; then
            include_source_ip_in_routing_handler "$interface_subnet" "$rule_tag"
        fi
    fi
}
FUNC_EOF

# Use awk to replace the function in /usr/bin/podkop
awk '
/^include_source_ips_in_routing_handler\(\) \{/ {
    skip=1; depth=0
}
skip {
    for(i=1;i<=length($0);i++){
        c=substr($0,i,1)
        if(c=="{") depth++
        if(c=="}") depth--
    }
    if(depth<=0){ skip=0; next }
    next
}
!skip { print }
' "$PODKOP_BIN" > /tmp/_podkop_part1.sh

# Insert new function at the right place and append the rest
grep -n "^include_source_ips_in_routing_handler" "$PODKOP_BIN" | head -1
LINE=$(grep -n "^include_source_ips_in_routing_handler" "$PODKOP_BIN" | head -1 | cut -d: -f1)
head -n "$((LINE-1))" "$PODKOP_BIN" > /tmp/_podkop_new
cat /tmp/_podkop_func.sh >> /tmp/_podkop_new

# Find end of original function and append rest of file
awk -v start="$LINE" '
NR < start { next }
NR == start { depth=0; in_func=1 }
in_func {
    for(i=1;i<=length($0);i++){
        c=substr($0,i,1)
        if(c=="{") depth++
        if(c=="}") { depth--; if(depth==0){ in_func=0; next } }
    }
    next
}
!in_func { print }
' "$PODKOP_BIN" >> /tmp/_podkop_new

chmod +x /tmp/_podkop_new
sh -n /tmp/_podkop_new || { echo "ERROR: syntax check failed. Aborting."; exit 1; }
cp /tmp/_podkop_new "$PODKOP_BIN"
echo "      Done."

# Cleanup
rm -f /tmp/_podkop_func.sh /tmp/_podkop_part1.sh /tmp/_podkop_new

echo ""
echo "=== Patch installed successfully! ==="
echo ""
echo "Next steps:"
echo "  1. Open LuCI → Services → Podkop → Sections"
echo "  2. Select a section and choose 'Section Interface'"
echo "  3. Restart Podkop: /etc/init.d/podkop restart"
echo ""
echo "To uninstall: sh uninstall.sh"
