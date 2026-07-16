#!/usr/bin/env bash
#
# MaterialDrawer - Automated Installation Script
# This script automatically injects the necessary bindings and properties into the
# IllogicalImpulse Quickshell and Hyprland configurations to support the Material App Drawer.
# It is idempotent (safe to run multiple times).
#

set -e

VERSION="1.0.0"

# ANSI Colors
C_RESET='\033[0m'
C_CYAN='\033[1;36m'
C_GREEN='\033[1;32m'
C_YELLOW='\033[1;33m'
C_RED='\033[1;31m'
C_DIM='\033[2m'

echo -e "${C_CYAN}=================================================${C_RESET}"
echo -e "${C_CYAN}  MaterialDrawer Installer v${VERSION}${C_RESET}"
echo -e "${C_CYAN}=================================================${C_RESET}"
echo ""

# Dependency check
for cmd in awk sed grep; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo -e "${C_RED}[ERROR] Required command '$cmd' is not installed. Aborting.${C_RESET}"
        exit 1
    fi
done

CONFIG_DIR="$HOME/.config/quickshell/ii"
HYPR_DIR="$HOME/.config/hypr"

SHELL_QML="$CONFIG_DIR/shell.qml"
GLOBAL_STATES="$CONFIG_DIR/GlobalStates.qml"
DOCK_QML="$CONFIG_DIR/modules/ii/dock/Dock.qml"
RULES_LUA="$HYPR_DIR/custom/rules.lua"
KEYBINDS_LUA="$HYPR_DIR/custom/keybinds.lua"

# Track errors
ERRORS=0

function check_file_exists() {
    if [ ! -f "$1" ]; then
        echo -e "${C_YELLOW}[WARNING] File not found: $1${C_RESET}"
        echo -e "${C_DIM}          Skipping injections for this file.${C_RESET}"
        return 1
    fi
    return 0
}

# 1. shell.qml injections
if check_file_exists "$SHELL_QML"; then
    echo -e "${C_CYAN}[*] Processing $(basename "$SHELL_QML")...${C_RESET}"
    if ! grep -q 'import "modules/materialDrawer"' "$SHELL_QML"; then
        echo -e "    ${C_GREEN}+ Injecting materialDrawer import${C_RESET}"
        awk '/^import/ && !done { print; print "import \"modules/materialDrawer\""; done=1; next } 1' "$SHELL_QML" > "${SHELL_QML}.tmp" && mv "${SHELL_QML}.tmp" "$SHELL_QML"
    else
        echo -e "    ${C_DIM}- Import already exists. Skipping.${C_RESET}"
    fi

    if ! grep -q 'MaterialDrawerWindow {' "$SHELL_QML"; then
        echo -e "    ${C_GREEN}+ Injecting MaterialDrawerWindow component and shortcuts${C_RESET}"
        awk '/Component\.onCompleted: \{/ {
            print "    MaterialDrawerWindow {"
            print "        id: customDrawerTest"
            print "    }"
            print ""
            print "    GlobalShortcut {"
            print "        name: \"materialDrawerToggle\""
            print "        description: \"Toggle the Material app drawer\""
            print "        onPressed: customDrawerTest.toggle()"
            print "    }"
            print ""
            print "    Connections {"
            print "        target: customDrawerTest"
            print "        function onDrawerOpenChanged() {"
            print "            if (customDrawerTest.drawerOpen) {"
            print "                GlobalStates.materialDrawerOpen = true"
            print "            } else {"
            print "                dockHideTimer.restart()"
            print "            }"
            print "        }"
            print "    }"
            print ""
            print "    Timer {"
            print "        id: dockHideTimer"
            print "        interval: 350"
            print "        repeat: false"
            print "        onTriggered: GlobalStates.materialDrawerOpen = false"
            print "    }"
            print ""
        } 1' "$SHELL_QML" > "${SHELL_QML}.tmp" && mv "${SHELL_QML}.tmp" "$SHELL_QML"
    else
        echo -e "    ${C_DIM}- MaterialDrawerWindow already exists. Skipping.${C_RESET}"
    fi
else
    ((ERRORS++))
fi

# 2. GlobalStates.qml injection
if check_file_exists "$GLOBAL_STATES"; then
    echo -e "${C_CYAN}[*] Processing $(basename "$GLOBAL_STATES")...${C_RESET}"
    if ! grep -q 'property bool materialDrawerOpen' "$GLOBAL_STATES"; then
        echo -e "    ${C_GREEN}+ Injecting materialDrawerOpen property${C_RESET}"
        awk '/Singleton \{/ {
            print
            print "    property bool materialDrawerOpen: false"
            next
        } 1' "$GLOBAL_STATES" > "${GLOBAL_STATES}.tmp" && mv "${GLOBAL_STATES}.tmp" "$GLOBAL_STATES"
    else
        echo -e "    ${C_DIM}- Property already exists. Skipping.${C_RESET}"
    fi
else
    ((ERRORS++))
fi

# 3. Dock.qml injection
if check_file_exists "$DOCK_QML"; then
    echo -e "${C_CYAN}[*] Processing $(basename "$DOCK_QML")...${C_RESET}"
    if ! grep -q 'GlobalStates.materialDrawerOpen' "$DOCK_QML"; then
        echo -e "    ${C_GREEN}+ Updating dock reveal condition and WlrLayer${C_RESET}"
        sed -i 's/|| (!ToplevelManager\.activeToplevel?.activated)/|| (!ToplevelManager.activeToplevel?.activated) || GlobalStates.materialDrawerOpen/' "$DOCK_QML"
        sed -i 's/WlrLayershell\.layer: WlrLayer\.Top/WlrLayershell.layer: GlobalStates.materialDrawerOpen ? WlrLayer.Overlay : WlrLayer.Top/' "$DOCK_QML"
    else
        echo -e "    ${C_DIM}- Dock bindings already exist. Skipping.${C_RESET}"
    fi
else
    ((ERRORS++))
fi

# 4. Hyprland rules.lua injection
if check_file_exists "$RULES_LUA"; then
    echo -e "${C_CYAN}[*] Processing $(basename "$RULES_LUA")...${C_RESET}"
    if ! grep -q 'quickshell:material_drawer' "$RULES_LUA"; then
        echo -e "    ${C_GREEN}+ Injecting Hyprland layer rules${C_RESET}"
        cat << 'EOF' >> "$RULES_LUA"

-- Material drawer: blur, alpha handling, and slide-from-bottom animation
hl.layer_rule({ match = { namespace = "quickshell:material_drawer" }, blur = true })
hl.layer_rule({ match = { namespace = "quickshell:material_drawer" }, ignore_alpha = 0.5 })
hl.layer_rule({ match = { namespace = "quickshell:material_drawer" }, animation = "slide bottom 250 emphasizedDecel" })
EOF
    else
        echo -e "    ${C_DIM}- Layer rules already exist. Skipping.${C_RESET}"
    fi
else
    ((ERRORS++))
fi

# 5. Hyprland keybinds.lua injection
if check_file_exists "$KEYBINDS_LUA"; then
    echo -e "${C_CYAN}[*] Processing $(basename "$KEYBINDS_LUA")...${C_RESET}"
    if ! grep -q 'ipc call materialDrawer toggle' "$KEYBINDS_LUA"; then
        echo -e "    ${C_GREEN}+ Injecting bare Super toggle keybind${C_RESET}"
        cat << 'EOF' >> "$KEYBINDS_LUA"

-- Material Drawer Toggle (Bare Super)
-- Remove the default Quickshell binds that use bare Super,
-- so this binding can take over the gesture cleanly.
hl.unbind("SUPER + SUPER_L")
hl.unbind("SUPER_L")

hl.bind("SUPER + SUPER_L",
        hl.dsp.exec_cmd("qs -p " .. os.getenv("HOME") .. "/.config/quickshell/ii ipc call materialDrawer toggle"),
        { release = true, description = "Toggle app drawer" })
EOF
    else
        echo -e "    ${C_DIM}- Keybind already exists. Skipping.${C_RESET}"
    fi
else
    ((ERRORS++))
fi

echo ""
if [ $ERRORS -eq 0 ]; then
    echo -e "${C_GREEN}=================================================${C_RESET}"
    echo -e "${C_GREEN}  Material Drawer added successfully!${C_RESET}"
    echo -e "${C_GREEN}=================================================${C_RESET}"
    echo -e "Please restart Quickshell and reload Hyprland to apply the changes."
else
    echo -e "${C_YELLOW}=================================================${C_RESET}"
    echo -e "${C_YELLOW}  Installation completed with $ERRORS warnings.${C_RESET}"
    echo -e "${C_YELLOW}=================================================${C_RESET}"
    echo -e "Some files could not be found. You may need to manually integrate those sections."
fi
