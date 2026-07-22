#!/usr/bin/env bash
#
# Material Drawer — Installer
#
# Subcommands:
#   install     (default)   back up + patch configs, copy module files
#   uninstall               restore pristine backups, remove module files
#   reinstall               uninstall, then install fresh (also used for updates)
#   status                  report what's installed / drifted / missing
#
# Flags:
#   --dry-run    show what would happen, change nothing
#   --yes        skip confirmation prompts (for curl-pipe / scripted use)
#
set -uo pipefail

VERSION="2.1.0"
REPO_URL="https://github.com/TheMirza009/material-drawer"

# Minimum supported versions — update these once real minimums are known.
# For now these are placeholders; the check is skipped with a warning if
# either command's --version output can't be parsed.
MIN_QS_VERSION=""
MIN_HYPR_VERSION=""

# ---------------------------------------------------------------------------
# Colors / logging
# ---------------------------------------------------------------------------
C_RESET='\033[0m'; C_CYAN='\033[1;36m'; C_GREEN='\033[1;32m'
C_YELLOW='\033[1;33m'; C_RED='\033[1;31m'; C_DIM='\033[2m'

log()   { echo -e "${C_CYAN}[*]${C_RESET} $*"; }
ok()    { echo -e "    ${C_GREEN}+ $*${C_RESET}"; }
skip()  { echo -e "    ${C_DIM}- $*${C_RESET}"; }
warn()  { echo -e "${C_YELLOW}[WARNING]${C_RESET} $*"; }
err()   { echo -e "${C_RED}[ERROR]${C_RESET} $*"; }

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
CONFIG_DIR="$HOME/.config/quickshell/ii"
HYPR_DIR="$HOME/.config/hypr"
TARGET_DIR="$CONFIG_DIR/modules/materialDrawer"

STATE_DIR="$HOME/.local/state/material-drawer"
BACKUP_DIR="$STATE_DIR/backups"
MANIFEST="$STATE_DIR/manifest.json"

SHELL_QML="$CONFIG_DIR/shell.qml"
GLOBAL_STATES="$CONFIG_DIR/GlobalStates.qml"
DOCK_QML="$CONFIG_DIR/modules/ii/dock/Dock.qml"
RULES_LUA="$HYPR_DIR/custom/rules.lua"
KEYBINDS_LUA="$HYPR_DIR/custom/keybinds.lua"

DRY_RUN=0
ASSUME_YES=0
ERRORS=0

# touched-this-run list, for rollback on failure (separate from the
# persistent manifest, which is only written on confirmed success)
TOUCHED_THIS_RUN=()

# ---------------------------------------------------------------------------
# Arg parsing
# ---------------------------------------------------------------------------
CMD="install"
for arg in "$@"; do
    case "$arg" in
        install|uninstall|reinstall|status) CMD="$arg" ;;
        --dry-run) DRY_RUN=1 ;;
        --yes|-y) ASSUME_YES=1 ;;
        --help|-h)
            echo "Usage: $0 [install|uninstall|reinstall|status] [--dry-run] [--yes]"
            exit 0
            ;;
        *) warn "Unknown argument: $arg (ignored)" ;;
    esac
done

# ---------------------------------------------------------------------------
# Rollback trap — if we exit non-zero mid-run, restore anything touched
# in THIS invocation from its backup, so a crashed install never leaves a
# half-patched state.
# ---------------------------------------------------------------------------
rollback() {
    local status=$?
    if [ "$status" -ne 0 ] && [ "${#TOUCHED_THIS_RUN[@]}" -gt 0 ] && [ "$DRY_RUN" -eq 0 ]; then
        err "Install failed — rolling back ${#TOUCHED_THIS_RUN[@]} modified file(s)."
        for f in "${TOUCHED_THIS_RUN[@]}"; do
            local base backup
            base="$(basename "$f")"
            backup="$BACKUP_DIR/$base.orig"
            if [ -f "$backup" ]; then
                cp -f "$backup" "$f"
                skip "Restored $base from backup."
            fi
        done
    fi
    if [ -n "${TMP_CLONE_DIR:-}" ] && [ -d "$TMP_CLONE_DIR" ]; then
        rm -rf "$TMP_CLONE_DIR"
    fi
}
trap rollback EXIT

# ---------------------------------------------------------------------------
# Self-bootstrap: if the module files aren't sitting next to this script
# (i.e. we were piped in via curl, not run from inside a clone), clone the
# repo into a temp dir and re-exec the copy that lives there.
# ---------------------------------------------------------------------------
bootstrap_if_needed() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)" || script_dir=""

    if [ -n "$script_dir" ] && [ -f "$script_dir/MaterialDrawerWindow.qml" ] && [ -f "$script_dir/DrawerSurface.qml" ]; then
        SCRIPT_DIR="$script_dir"
        return 0
    fi

    log "Running standalone (curl-piped) — cloning repo to a temp directory..."
    if ! command -v git >/dev/null 2>&1; then
        err "git is required but not installed. Install it first: sudo pacman -S git"
        exit 1
    fi

    TMP_CLONE_DIR="$(mktemp -d)"
    if ! git clone --depth 1 "$REPO_URL" "$TMP_CLONE_DIR" >/dev/null 2>&1; then
        err "Failed to clone $REPO_URL"
        exit 1
    fi
    ok "Cloned to temporary directory (will be removed when the script exits)."
    SCRIPT_DIR="$TMP_CLONE_DIR"
}

repo_commit_hash() {
    # Hash of the source we're installing from (temp clone or local checkout)
    git -C "$SCRIPT_DIR" rev-parse HEAD 2>/dev/null || echo "unknown"
}

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
preflight() {
    for cmd in awk sed grep git; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            err "Required command '$cmd' is not installed. Aborting."
            exit 1
        fi
    done

    if ! command -v qs >/dev/null 2>&1; then
        err "Quickshell ('qs') not found on PATH. This tool requires Quickshell + IllogicalImpulse."
        exit 1
    fi
    if ! command -v hyprctl >/dev/null 2>&1; then
        err "Hyprland ('hyprctl') not found on PATH. This tool requires Hyprland."
        exit 1
    fi

    # Version gate — best-effort, only enforced if minimums are actually set.
    if [ -n "$MIN_QS_VERSION" ] || [ -n "$MIN_HYPR_VERSION" ]; then
        warn "Version minimums are configured but comparison isn't implemented yet — skipping."
    fi

    mkdir -p "$BACKUP_DIR"
}

# ---------------------------------------------------------------------------
# Manifest (simple hand-rolled JSON — no jq dependency)
# ---------------------------------------------------------------------------
declare -A FILE_STATUS   # key: base filename -> ok | anchor_not_found | skipped | missing

manifest_write() {
    [ "$DRY_RUN" -eq 1 ] && return 0
    local now hash
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    hash="$(repo_commit_hash)"
    {
        echo "{"
        echo "  \"installed_at\": \"$now\","
        echo "  \"script_version\": \"$VERSION\","
        echo "  \"source_commit\": \"$hash\","
        echo "  \"files\": {"
        local i=0 total=${#FILE_STATUS[@]}
        for name in "${!FILE_STATUS[@]}"; do
            i=$((i+1))
            local comma=","
            [ "$i" -eq "$total" ] && comma=""
            echo "    \"$name\": \"${FILE_STATUS[$name]}\"$comma"
        done
        echo "  }"
        echo "}"
    } > "$MANIFEST"
}

manifest_get_field() {
    # $1 = field name (top-level string field)
    grep -oP "\"$1\":\s*\"\K[^\"]*" "$MANIFEST" 2>/dev/null | head -n1
}

# ---------------------------------------------------------------------------
# Backup-once helper
# ---------------------------------------------------------------------------
backup_once() {
    # $1 = full path to the live file
    local file="$1" base backup
    base="$(basename "$file")"
    backup="$BACKUP_DIR/$base.orig"
    if [ -f "$backup" ]; then
        skip "Backup for $base already exists, not overwriting."
        return 0
    fi
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "    (dry-run) would back up $file -> $backup"
        return 0
    fi
    cp -f "$file" "$backup"
    ok "Backed up $base -> $backup"
}

file_ready() {
    # $1 = path, prints warning + returns 1 if missing
    if [ ! -f "$1" ]; then
        warn "File not found: $1 — skipping this file's changes."
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Per-file install steps
# ---------------------------------------------------------------------------
install_shell_qml() {
    file_ready "$SHELL_QML" || { FILE_STATUS[shell.qml]="missing"; ERRORS=$((ERRORS+1)); return; }
    log "Processing $(basename "$SHELL_QML")..."

    if ! grep -q '^import' "$SHELL_QML"; then
        err "Anchor not found in shell.qml (no 'import' line) — unsupported file layout."
        FILE_STATUS[shell.qml]="anchor_not_found"; ERRORS=$((ERRORS+1)); return
    fi

    backup_once "$SHELL_QML"
    TOUCHED_THIS_RUN+=("$SHELL_QML")
    [ "$DRY_RUN" -eq 1 ] && { echo "    (dry-run) would inject import + MaterialDrawerWindow block"; FILE_STATUS[shell.qml]="ok"; return; }

    if ! grep -q 'import "modules/materialDrawer"' "$SHELL_QML"; then
        ok "Injecting materialDrawer import"
        awk '/^import/ && !done { print; print "import \"modules/materialDrawer\""; done=1; next } 1' \
            "$SHELL_QML" > "${SHELL_QML}.tmp" && mv "${SHELL_QML}.tmp" "$SHELL_QML"
    else
        skip "Import already present."
    fi

    if ! grep -q 'MaterialDrawerWindow {' "$SHELL_QML"; then
        ok "Injecting MaterialDrawerWindow component and shortcuts"
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
        skip "MaterialDrawerWindow already present."
    fi

    if grep -q 'import "modules/materialDrawer"' "$SHELL_QML" && grep -q 'MaterialDrawerWindow {' "$SHELL_QML"; then
        FILE_STATUS[shell.qml]="ok"
    else
        err "Post-edit verification failed for shell.qml."
        FILE_STATUS[shell.qml]="anchor_not_found"; ERRORS=$((ERRORS+1))
    fi
}

install_global_states() {
    file_ready "$GLOBAL_STATES" || { FILE_STATUS[GlobalStates.qml]="missing"; ERRORS=$((ERRORS+1)); return; }
    log "Processing $(basename "$GLOBAL_STATES")..."

    if ! grep -q 'Singleton {' "$GLOBAL_STATES"; then
        err "Anchor not found in GlobalStates.qml (no 'Singleton {') — unsupported file layout."
        FILE_STATUS[GlobalStates.qml]="anchor_not_found"; ERRORS=$((ERRORS+1)); return
    fi

    backup_once "$GLOBAL_STATES"
    TOUCHED_THIS_RUN+=("$GLOBAL_STATES")
    [ "$DRY_RUN" -eq 1 ] && { echo "    (dry-run) would inject materialDrawerOpen property"; FILE_STATUS[GlobalStates.qml]="ok"; return; }

    if ! grep -q 'property bool materialDrawerOpen' "$GLOBAL_STATES"; then
        ok "Injecting materialDrawerOpen property"
        awk '/Singleton \{/ { print; print "    property bool materialDrawerOpen: false"; next } 1' \
            "$GLOBAL_STATES" > "${GLOBAL_STATES}.tmp" && mv "${GLOBAL_STATES}.tmp" "$GLOBAL_STATES"
    else
        skip "Property already present."
    fi

    if grep -q 'property bool materialDrawerOpen' "$GLOBAL_STATES"; then
        FILE_STATUS[GlobalStates.qml]="ok"
    else
        err "Post-edit verification failed for GlobalStates.qml."
        FILE_STATUS[GlobalStates.qml]="anchor_not_found"; ERRORS=$((ERRORS+1))
    fi
}

install_dock_qml() {
    file_ready "$DOCK_QML" || { FILE_STATUS[Dock.qml]="missing"; ERRORS=$((ERRORS+1)); return; }
    log "Processing $(basename "$DOCK_QML")..."

    local already_installed=0
    grep -q 'GlobalStates.materialDrawerOpen' "$DOCK_QML" && already_installed=1

    if [ "$already_installed" -eq 0 ]; then
        if ! grep -q '!ToplevelManager\.activeToplevel?\.activated' "$DOCK_QML"; then
            err "Anchor not found in Dock.qml (reveal condition) — Dock.qml may be customized or IllogicalImpulse version unsupported."
            FILE_STATUS[Dock.qml]="anchor_not_found"; ERRORS=$((ERRORS+1)); return
        fi
        if ! grep -q 'WlrLayershell\.layer: WlrLayer\.Top' "$DOCK_QML"; then
            err "Anchor not found in Dock.qml (WlrLayershell.layer line) — Dock.qml may be customized or IllogicalImpulse version unsupported."
            FILE_STATUS[Dock.qml]="anchor_not_found"; ERRORS=$((ERRORS+1)); return
        fi
    fi

    backup_once "$DOCK_QML"
    TOUCHED_THIS_RUN+=("$DOCK_QML")
    [ "$DRY_RUN" -eq 1 ] && { echo "    (dry-run) would update reveal condition + WlrLayershell.layer"; FILE_STATUS[Dock.qml]="ok"; return; }

    if [ "$already_installed" -eq 0 ]; then
        ok "Updating dock reveal condition and WlrLayer"
        sed -i 's/|| (!ToplevelManager\.activeToplevel?\.activated)/|| (!ToplevelManager.activeToplevel?.activated) || GlobalStates.materialDrawerOpen/' "$DOCK_QML"
        sed -i 's/WlrLayershell\.layer: WlrLayer\.Top/WlrLayershell.layer: GlobalStates.materialDrawerOpen ? WlrLayer.Overlay : WlrLayer.Top/' "$DOCK_QML"
    else
        skip "Dock bindings already present."
    fi

    if grep -q 'GlobalStates.materialDrawerOpen' "$DOCK_QML"; then
        FILE_STATUS[Dock.qml]="ok"
    else
        err "Post-edit verification failed for Dock.qml — the sed substitution did not take effect."
        FILE_STATUS[Dock.qml]="anchor_not_found"; ERRORS=$((ERRORS+1))
    fi
}

install_rules_lua() {
    file_ready "$RULES_LUA" || { FILE_STATUS[rules.lua]="missing"; ERRORS=$((ERRORS+1)); return; }
    log "Processing $(basename "$RULES_LUA")..."

    backup_once "$RULES_LUA"
    TOUCHED_THIS_RUN+=("$RULES_LUA")
    [ "$DRY_RUN" -eq 1 ] && { echo "    (dry-run) would append layer rules"; FILE_STATUS[rules.lua]="ok"; return; }

    if ! grep -q 'quickshell:material_drawer' "$RULES_LUA"; then
        ok "Injecting Hyprland layer rules"
        cat << 'EOF' >> "$RULES_LUA"

-- Material drawer: blur, alpha handling, and slide-from-bottom animation
hl.layer_rule({ match = { namespace = "quickshell:material_drawer" }, blur = true })
hl.layer_rule({ match = { namespace = "quickshell:material_drawer" }, ignore_alpha = 0.5 })
hl.layer_rule({ match = { namespace = "quickshell:material_drawer" }, animation = "slide bottom 250 emphasizedDecel" })
EOF
    else
        skip "Layer rules already present."
    fi
    FILE_STATUS[rules.lua]="ok"
}

install_keybinds_lua() {
    file_ready "$KEYBINDS_LUA" || { FILE_STATUS[keybinds.lua]="missing"; ERRORS=$((ERRORS+1)); return; }
    log "Processing $(basename "$KEYBINDS_LUA")..."

    backup_once "$KEYBINDS_LUA"
    TOUCHED_THIS_RUN+=("$KEYBINDS_LUA")
    [ "$DRY_RUN" -eq 1 ] && { echo "    (dry-run) would append keybind block"; FILE_STATUS[keybinds.lua]="ok"; return; }

    if ! grep -q 'ipc call materialDrawer toggle' "$KEYBINDS_LUA"; then
        ok "Injecting bare Super toggle keybind"
        cat << 'EOF' >> "$KEYBINDS_LUA"

-- Material Drawer Toggle (Bare Super)
hl.unbind("SUPER + SUPER_L")
hl.unbind("SUPER_L")

hl.bind("SUPER + SUPER_L",
        hl.dsp.exec_cmd("qs -p " .. os.getenv("HOME") .. "/.config/quickshell/ii ipc call materialDrawer toggle"),
        { release = true, description = "Toggle app drawer" })
EOF
    else
        skip "Keybind already present."
    fi
    FILE_STATUS[keybinds.lua]="ok"
}

copy_module_files() {
    log "Copying module files to $TARGET_DIR..."

    # The repo ships MaterialDrawerWindow.qml, DrawerSurface.qml, and
    # components/ directly at its root — there is no materialDrawer/
    # wrapper subfolder in the source. List what we expect explicitly so a
    # missing file is a loud error, not a silent partial copy.
    local required=("MaterialDrawerWindow.qml" "DrawerSurface.qml" "components")
    local missing=0
    for item in "${required[@]}"; do
        if [ ! -e "$SCRIPT_DIR/$item" ]; then
            err "Expected source file/dir not found: $SCRIPT_DIR/$item"
            missing=1
        fi
    done
    if [ "$missing" -eq 1 ]; then
        err "Module source is incomplete — refusing to copy a partial module."
        ERRORS=$((ERRORS+1))
        return
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        echo "    (dry-run) would copy MaterialDrawerWindow.qml, DrawerSurface.qml, components/ -> $TARGET_DIR"
        return
    fi

    mkdir -p "$TARGET_DIR"
    if ! cp -r "$SCRIPT_DIR/MaterialDrawerWindow.qml" "$SCRIPT_DIR/DrawerSurface.qml" "$SCRIPT_DIR/components" "$TARGET_DIR/"; then
        err "Copy failed — module files were NOT fully installed."
        ERRORS=$((ERRORS+1))
        return
    fi

    # Verify the copy actually landed before declaring success.
    if [ -f "$TARGET_DIR/MaterialDrawerWindow.qml" ] && [ -f "$TARGET_DIR/DrawerSurface.qml" ] && [ -d "$TARGET_DIR/components" ]; then
        ok "Module files copied."
    else
        err "Post-copy verification failed — files missing from $TARGET_DIR."
        ERRORS=$((ERRORS+1))
    fi
}

confirm() {
    [ "$ASSUME_YES" -eq 1 ] && return 0
    [ "$DRY_RUN" -eq 1 ] && return 0
    read -rp "Continue? [Y/n] " reply
    case "$reply" in
        [nN]*) echo "Aborted."; exit 0 ;;
        *) return 0 ;;
    esac
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------
cmd_install() {
    echo -e "${C_CYAN}=================================================${C_RESET}"
    echo -e "${C_CYAN}  Material Drawer Installer v${VERSION}${C_RESET}"
    echo -e "${C_CYAN}=================================================${C_RESET}"

    if [ -f "$MANIFEST" ]; then
        local installed_hash current_hash
        installed_hash="$(manifest_get_field source_commit)"
        current_hash="$(repo_commit_hash)"
        if [ "$installed_hash" = "$current_hash" ]; then
            echo "Material Drawer is already installed and up to date."
            confirm_prompt="Reinstall anyway?"
        else
            echo "Installed version differs from the latest available."
            confirm_prompt="Update now?"
        fi
        if [ "$ASSUME_YES" -eq 0 ] && [ "$DRY_RUN" -eq 0 ]; then
            read -rp "$confirm_prompt [Y/n] " reply
            case "$reply" in [nN]*) echo "Nothing to do."; exit 0 ;; esac
        fi
    fi

    echo
    echo "This will back up and modify the following files (backups saved to $BACKUP_DIR):"
    for f in "$SHELL_QML" "$GLOBAL_STATES" "$DOCK_QML" "$RULES_LUA" "$KEYBINDS_LUA"; do
        echo "  - $f"
    done
    echo
    confirm

    install_shell_qml
    install_global_states
    install_dock_qml
    install_rules_lua
    install_keybinds_lua
    copy_module_files
    manifest_write

    echo
    if [ "$DRY_RUN" -eq 1 ]; then
        echo -e "${C_CYAN}Dry run complete — nothing was changed.${C_RESET}"
    elif [ "$ERRORS" -eq 0 ]; then
        echo -e "${C_GREEN}=================================================${C_RESET}"
        echo -e "${C_GREEN}  Material Drawer installed successfully!${C_RESET}"
        echo -e "${C_GREEN}=================================================${C_RESET}"
        echo "Restart Quickshell and reload Hyprland to apply the changes."
    else
        echo -e "${C_YELLOW}=================================================${C_RESET}"
        echo -e "${C_YELLOW}  Completed with $ERRORS issue(s). See warnings above.${C_RESET}"
        echo -e "${C_YELLOW}=================================================${C_RESET}"
        echo "Affected files may need manual integration — see README.md."
    fi
}

cmd_uninstall() {
    if [ ! -f "$MANIFEST" ]; then
        echo "Material Drawer does not appear to be installed (no manifest found). Nothing to do."
        exit 0
    fi

    echo "This will restore the original backed-up versions of:"
    for f in "$SHELL_QML" "$GLOBAL_STATES" "$DOCK_QML" "$RULES_LUA" "$KEYBINDS_LUA"; do
        [ -f "$BACKUP_DIR/$(basename "$f").orig" ] && echo "  - $f"
    done
    warn "Any manual edits you made to these files AFTER installing will also be reverted —"
    warn "restoring the backup can't distinguish our changes from yours."
    confirm

    [ "$DRY_RUN" -eq 1 ] && { echo "(dry-run) would restore backups and remove $TARGET_DIR"; return; }

    for f in "$SHELL_QML" "$GLOBAL_STATES" "$DOCK_QML" "$RULES_LUA" "$KEYBINDS_LUA"; do
        local backup="$BACKUP_DIR/$(basename "$f").orig"
        if [ -f "$backup" ]; then
            cp -f "$backup" "$f"
            ok "Restored $(basename "$f")"
        fi
    done

    rm -rf "$TARGET_DIR"
    mv "$MANIFEST" "$MANIFEST.uninstalled-$(date +%s)" 2>/dev/null || rm -f "$MANIFEST"
    echo -e "${C_GREEN}Material Drawer uninstalled.${C_RESET} Restart Quickshell / reload Hyprland."
}

cmd_reinstall() {
    cmd_uninstall
    cmd_install
}

cmd_status() {
    if [ ! -f "$MANIFEST" ]; then
        echo "Material Drawer: not installed."
        exit 0
    fi
    echo "Material Drawer status:"
    echo "  Installed at:    $(manifest_get_field installed_at)"
    echo "  Source commit:   $(manifest_get_field source_commit)"
    echo
    for pair in "shell.qml:$SHELL_QML" "GlobalStates.qml:$GLOBAL_STATES" "Dock.qml:$DOCK_QML" \
                "rules.lua:$RULES_LUA" "keybinds.lua:$KEYBINDS_LUA"; do
        name="${pair%%:*}"; path="${pair#*:}"
        if [ ! -f "$path" ]; then
            echo "  $name: missing (file not found)"
        elif grep -q "materialDrawer" "$path" 2>/dev/null || grep -q "material_drawer" "$path" 2>/dev/null; then
            echo "  $name: ok"
        else
            echo "  $name: drift detected (expected markers not found)"
        fi
    done
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
bootstrap_if_needed
preflight

case "$CMD" in
    install)   cmd_install ;;
    uninstall) cmd_uninstall ;;
    reinstall) cmd_reinstall ;;
    status)    cmd_status ;;
esac

exit "$([ "$ERRORS" -gt 0 ] && echo 1 || echo 0)"