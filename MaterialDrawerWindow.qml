import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.services


Scope {
    id: root

    // ── State ──────────────────────────────────────────────────────────────────
    property bool drawerOpen: false

    function toggle() { drawerOpen = !drawerOpen }
    function close()  { drawerOpen = false }

    // ── IPC ────────────────────────────────────────────────────────────────────
    IpcHandler {
        target: "materialDrawer"
        function toggle(): void { root.toggle() }
        function open():   void { root.drawerOpen = true }
        function close():  void { root.close() }
    }

    // ── Window (always alive, visibility drives the animation) ─────────────────
    // Copied from SidebarLeft pattern: visible toggles trigger Hyprland's
    // layerrule animation = "slide bottom", bounded by the window's position.

    PanelWindow {
        id: drawerWindow
        visible: root.drawerOpen

        WlrLayershell.namespace: "quickshell:material_drawer"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

        exclusionMode: ExclusionMode.Ignore

        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true
        color: "transparent"

        mask: drawerOpen ? fullRegion : emptyRegion
        Region { id: emptyRegion }
        Item  { id: fullArea; anchors.fill: parent }
        Region { id: fullRegion; item: fullArea }

        function hide() { root.drawerOpen = false }

        onVisibleChanged: {
            if (visible) {
                GlobalFocusGrab.addDismissable(drawerWindow)
            } else {
                GlobalFocusGrab.removeDismissable(drawerWindow)
            }
        }

        Connections {
            target: GlobalFocusGrab
            function onDismissed() { drawerWindow.hide() }
        }

        // ── Dismiss overlay (behind the card) ───────────────────────────────────────
        MouseArea {
            anchors.fill: parent
            onClicked: drawerWindow.hide()
        }

        // ── Drawer surface ─────────────────────────────────────────────────────────
        DrawerSurface {
            id: drawerSurface
            onCloseRequested: drawerWindow.hide()

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 75
        }
    }
}