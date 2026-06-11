#!/bin/sh
# Podkop Section Interface Patch
# Adds "Section Interface" dropdown to LuCI Podkop sections.
#
# Two modes (per section, selectable in LuCI):
#   lists (default) - only traffic matching the section's lists (community/user/remote)
#                     from the interface subnet goes through the section; the rest is direct
#   full            - all traffic from the interface subnet goes through the section
#
# Version-tolerant: patch points are located by code anchors, not by version number.
# If an anchor is missing, the script degrades gracefully or aborts with a clear message.
#
# Tested: Podkop v0.7.17 - v0.7.19, OpenWrt 23.x / 24.x
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

# --- Anchor detection (version compatibility) ---
ANCHOR_RULE='sing_box_cm_add_route_rule "$config" "$route_rule_tag" "$SB_TPROXY_INBOUND_TAG" "$outbound_tag"'

if ! grep -q "^include_source_ips_in_routing_handler() {" "$PODKOP_BIN"; then
    echo "ERROR: this podkop version is not supported (anchor function not found)."
    echo "       Please open an issue: https://github.com/AxelNerv/podkop-section-interface/issues"
    exit 1
fi

LISTS_MODE_OK=1
if ! grep -qF "$ANCHOR_RULE" "$PODKOP_BIN"; then
    LISTS_MODE_OK=0
    echo "WARN: 'lists' mode anchor not found in this podkop version."
    echo "      Only 'full' mode (route whole subnet) will work."
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

# Helpers + replacement for include_source_ips_in_routing_handler ('full' mode).
# psi_ = podkop-section-interface
cat > /tmp/_psi_func.sh << 'FUNC_EOF'
# --- podkop-section-interface patch ---
psi_get_iface_subnet() {
    local ifname="$1" iface_dev
    if ip link show "$ifname" > /dev/null 2>&1; then
        iface_dev="$ifname"
    else
        iface_dev=$(ifstatus "$ifname" 2>/dev/null | jsonfilter -e '@.l3_device' 2>/dev/null)
    fi
    [ -n "$iface_dev" ] || return 0
    ip addr show "$iface_dev" 2>/dev/null | awk '/inet / {print $2}' | head -1
}

psi_scope_route_rule_by_interface() {
    local section="$1" route_rule_tag="$2"
    local section_interface section_interface_mode subnet
    config_get section_interface "$section" "section_interface"
    config_get section_interface_mode "$section" "section_interface_mode" "lists"
    [ -n "$section_interface" ] || return 0
    [ "$section_interface_mode" = "lists" ] || return 0
    subnet=$(psi_get_iface_subnet "$section_interface")
    if [ -z "$subnet" ]; then
        log "section $section: interface '$section_interface' not found or has no IPv4 address, lists scope skipped" "warn"
        return 0
    fi
    config=$(sing_box_cm_patch_route_rule "$config" "$route_rule_tag" "source_ip_cidr" "$subnet")
    log "section $section: lists scoped to source $subnet (interface $section_interface)" "info"
}
# --- end podkop-section-interface patch ---

include_source_ips_in_routing_handler() {
    local section="$1"

    local fully_routed_ips rule_tag
    config_get fully_routed_ips "$section" "fully_routed_ips"

    local section_interface section_interface_mode interface_subnet
    config_get section_interface "$section" "section_interface"
    config_get section_interface_mode "$section" "section_interface_mode" "lists"
    if [ -n "$section_interface" ] && [ "$section_interface_mode" = "full" ]; then
        interface_subnet=$(psi_get_iface_subnet "$section_interface")
        if [ -z "$interface_subnet" ]; then
            log "section_interface '$section_interface' not found or has no IPv4 address" "warn"
        else
            log "section $section: adding subnet $interface_subnet from interface $section_interface to fully routed" "info"
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

# Step A: replace include_source_ips_in_routing_handler with helpers + new version.
# The original function ends at the first '}' in column 0.
awk -v funcfile="/tmp/_psi_func.sh" '
BEGIN { while ((getline line < funcfile) > 0) newfunc = newfunc line "\n" }
/^include_source_ips_in_routing_handler\(\) \{/ { printf "%s", newfunc; skip=1; next }
skip && /^\}/ { skip=0; next }
skip { next }
{ print }
' "$PODKOP_BIN" > /tmp/_psi_step_a

# Step B: insert the lists-mode scope call right after the section route rule is created.
if [ "$LISTS_MODE_OK" -eq 1 ]; then
    awk -v anchor="$ANCHOR_RULE" '
    { print }
    index($0, anchor) > 0 {
        print "        psi_scope_route_rule_by_interface \"$section\" \"$route_rule_tag\""
    }
    ' /tmp/_psi_step_a > /tmp/_psi_step_b
else
    cp /tmp/_psi_step_a /tmp/_psi_step_b
fi

# Syntax check before replacing
sh -n /tmp/_psi_step_b || { echo "ERROR: syntax check failed. Original file untouched. Aborting."; exit 1; }
cp /tmp/_psi_step_b "$PODKOP_BIN"
chmod +x "$PODKOP_BIN"
echo "      Done."

# Cleanup
rm -f /tmp/_psi_func.sh /tmp/_psi_step_a /tmp/_psi_step_b

echo ""
echo "=== Patch installed successfully! ==="
echo ""
echo "Next steps:"
echo "  1. Open LuCI -> Services -> Podkop -> Sections (Ctrl+Shift+R to refresh cache)"
echo "  2. Select a section, set 'Section Interface' and its mode"
echo "  3. Restart Podkop: /etc/init.d/podkop restart"
echo ""
echo "To uninstall: sh uninstall.sh"
