pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

// ── Power Menu Dialog ──────────────────────────────────────────────────────────
// Android 16 long-press style. Material 3 compliant.
//
// Shape: only the outer edges of the stack are rounded (top corners of the
// first tile, bottom corners of the last tile). The middle tile — and the
// inner corners of the outer tiles — use a small "adjoining" radius, same
// pattern M3 uses for grouped/segmented items.
//
// Motion: two layers, offset on purpose.
//   1. STACK  - the tiles themselves: yScale 0.85 -> 1.0 + fade. Runs the
//      full duration.
//   2. CONTENT - icon + label per tile: fades in starting at the stack's
//      50% mark, finishing exactly when the stack finishes. Reversed on
//      close: content fades out over the first 50% of the exit, stack
//      keeps shrinking for the full exit duration.
// Durations are the literal constants androidx.compose.material3 uses for
// DropdownMenu (Menu.kt): 120ms in / 75ms out. Real Compose freezes scale on
// exit and only fades alpha (snapping the scale at the last ms) — we
// deliberately animate the scale back down instead, since a true reverse
// was asked for; everything else matches the source constants.
//
// Tail: fused to the bottom edge of the last tile, pointing down at the
// trigger button below it. Scale origin sits at that same point, so the
// stack visibly collapses back into the button on close.

Item {
    id: root

    readonly property int dialogWidth:   220
    readonly property int itemHeight:    58        // M3 standard menu item height + extra vertical padding
    readonly property int outerRadius:   Appearance.rounding.large   // exposed outer corners
    readonly property int innerRadius:   4                            // adjoining corners (M3 extra-small)
    readonly property int leadingPad:    20
    readonly property int trailingPad:   16
    readonly property int iconTextGap:   12
    readonly property int iconSize:      Appearance.font.pixelSize.larger * 1.2

    readonly property int groupGap:      2         // tight physical gap between tiles

    readonly property int tailWidth:     14
    readonly property int tailHeight:    8
    readonly property int tailCenterX:   180

    // Exact androidx.compose.material3 Menu.kt constants
    readonly property int enterDuration: 120
    readonly property int exitDuration:  75

    readonly property color cardColor: ColorUtils.applyAlpha(Appearance.m3colors.m3surfaceContainerHigh, 1.0)

    property bool open: false
    signal dismissed()

    implicitWidth:  dialogWidth
    implicitHeight: menuColumn.implicitHeight
    enabled: open

    // ── STACK animation (scale + fade, width held constant) ───────────────────
    opacity: open ? 1.0 : 0.0
    Behavior on opacity {
        NumberAnimation {
            duration: root.open ? root.enterDuration : root.exitDuration
            // enter: LinearOutSlowInEasing (0,0,0.2,1) · exit: FastOutLinearInEasing (0.4,0,1,1)
            easing.type:        Easing.BezierSpline
            easing.bezierCurve: root.open ? [0.0, 0.0, 0.2, 1.0, 1.0, 1.0]
                                           : [0.4, 0.0, 1.0, 1.0, 1.0, 1.0]
        }
    }

    transform: Scale {
        origin.x: root.tailCenterX
        origin.y: root.height          // bottom-anchored: collapses down into the tail/trigger
        xScale:   1.0
        yScale:   root.open ? 1.0 : 0.85

        Behavior on yScale {
            NumberAnimation {
                duration:           root.open ? root.enterDuration : root.exitDuration
                easing.type:        Easing.BezierSpline
                easing.bezierCurve: root.open ? [0.0, 0.0, 0.2, 1.0, 1.0, 1.0]
                                               : [0.4, 0.0, 1.0, 1.0, 1.0, 1.0]
            }
        }
    }

    Column {
        id: menuColumn
        width: root.dialogWidth
        spacing: 0

        // ── CARD: LOCK (outer radius on top corners) ───────────────────────
        Item {
            width:  root.dialogWidth
            height: root.itemHeight

            DropShadow {
                anchors.fill:      lockCard
                source:            lockCard
                radius:            8
                samples:           17
                color:             Appearance.colors.colShadow
                transparentBorder: true
            }

            Rectangle {
                id: lockCard
                anchors.fill:     parent
                topLeftRadius:    root.outerRadius
                topRightRadius:   root.outerRadius
                bottomLeftRadius: root.innerRadius
                bottomRightRadius: root.innerRadius

                color: lockMouse.pressed ? Qt.tint(root.cardColor, ColorUtils.applyAlpha(Appearance.m3colors.m3onSurface, 0.12)) :
                       lockMouse.containsMouse ? Qt.tint(root.cardColor, ColorUtils.applyAlpha(Appearance.m3colors.m3onSurface, 0.08)) :
                       root.cardColor

                Behavior on color { ColorAnimation { duration: 100 } }

                MouseArea {
                    id: lockMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        root.dismissed()
                        Session.lock()
                    }
                }

                RowLayout {
                    spacing:      root.iconTextGap
                    anchors.fill: parent
                    opacity: root.open ? 1.0 : 0.0

                    // ── CONTENT animation, offset from the stack ────────
                    Behavior on opacity {
                        SequentialAnimation {
                            PauseAnimation { duration: root.open ? root.enterDuration / 2 : 0 }
                            NumberAnimation {
                                duration:    root.open ? root.enterDuration / 2 : root.exitDuration / 2
                                easing.type: Easing.OutQuad
                            }
                        }
                    }

                    MaterialSymbol {
                        Layout.leftMargin: root.leadingPad
                        Layout.alignment:  Qt.AlignVCenter
                        text:     "lock"
                        iconSize: root.iconSize
                        fill:     0
                        color:    Appearance.m3colors.m3onSurfaceVariant
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        text:           "Lock"
                        font.pixelSize: Appearance.font.pixelSize.small * 1.2
                        color:          Appearance.m3colors.m3onSurface
                    }
                    Item { Layout.preferredWidth: root.trailingPad }
                }
            }
        }

        // GAP
        Item { width: root.dialogWidth; height: root.groupGap }

        // ── CARD: SHUT DOWN (consistent, uniform small radius) ─────────────
        Item {
            width:  root.dialogWidth
            height: root.itemHeight

            DropShadow {
                anchors.fill:      shutdownCard
                source:            shutdownCard
                radius:            8
                samples:           17
                color:             Appearance.colors.colShadow
                transparentBorder: true
            }

            Rectangle {
                id: shutdownCard
                anchors.fill: parent
                radius:       root.innerRadius

                color: shutdownMouse.pressed ? Qt.tint(root.cardColor, ColorUtils.applyAlpha(Appearance.m3colors.m3onSurface, 0.12)) :
                       shutdownMouse.containsMouse ? Qt.tint(root.cardColor, ColorUtils.applyAlpha(Appearance.m3colors.m3onSurface, 0.08)) :
                       root.cardColor

                Behavior on color { ColorAnimation { duration: 100 } }

                MouseArea {
                    id: shutdownMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        root.dismissed()
                        Session.poweroff()
                    }
                }

                RowLayout {
                    spacing:      root.iconTextGap
                    anchors.fill: parent
                    opacity: root.open ? 1.0 : 0.0

                    Behavior on opacity {
                        SequentialAnimation {
                            PauseAnimation { duration: root.open ? root.enterDuration / 2 : 0 }
                            NumberAnimation {
                                duration:    root.open ? root.enterDuration / 2 : root.exitDuration / 2
                                easing.type: Easing.OutQuad
                            }
                        }
                    }

                    MaterialSymbol {
                        Layout.leftMargin: root.leadingPad
                        Layout.alignment:  Qt.AlignVCenter
                        text:     "power_settings_new"
                        iconSize: root.iconSize
                        fill:     0
                        color:    Appearance.m3colors.m3onSurfaceVariant
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        text:           "Shut Down"
                        font.pixelSize: Appearance.font.pixelSize.small * 1.2
                        color:          Appearance.m3colors.m3onSurface
                    }
                    Item { Layout.preferredWidth: root.trailingPad }
                }
            }
        }

        // GAP
        Item { width: root.dialogWidth; height: root.groupGap }

        // ── CARD: REBOOT (outer radius on bottom corners) ──────────────────
        Item {
            width:  root.dialogWidth
            height: root.itemHeight

            DropShadow {
                anchors.fill:      rebootCard
                source:            rebootCard
                radius:            8
                samples:           17
                color:             Appearance.colors.colShadow
                transparentBorder: true
            }

            Rectangle {
                id: rebootCard
                anchors.fill:      parent
                topLeftRadius:     root.innerRadius
                topRightRadius:    root.innerRadius
                bottomLeftRadius:  root.outerRadius
                bottomRightRadius: root.outerRadius

                color: rebootMouse.pressed ? Qt.tint(root.cardColor, ColorUtils.applyAlpha(Appearance.m3colors.m3onSurface, 0.12)) :
                       rebootMouse.containsMouse ? Qt.tint(root.cardColor, ColorUtils.applyAlpha(Appearance.m3colors.m3onSurface, 0.08)) :
                       root.cardColor

                Behavior on color { ColorAnimation { duration: 100 } }

                MouseArea {
                    id: rebootMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        root.dismissed()
                        Session.reboot()
                    }
                }

                RowLayout {
                    spacing:      root.iconTextGap
                    anchors.fill: parent
                    opacity: root.open ? 1.0 : 0.0

                    Behavior on opacity {
                        SequentialAnimation {
                            PauseAnimation { duration: root.open ? root.enterDuration / 2 : 0 }
                            NumberAnimation {
                                duration:    root.open ? root.enterDuration / 2 : root.exitDuration / 2
                                easing.type: Easing.OutQuad
                            }
                        }
                    }

                    MaterialSymbol {
                        Layout.leftMargin: root.leadingPad
                        Layout.alignment:  Qt.AlignVCenter
                        text:     "restart_alt"
                        iconSize: root.iconSize * 1.12
                        fill:     0
                        color:    Appearance.m3colors.m3onSurfaceVariant
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        text:           "Reboot"
                        font.pixelSize: Appearance.font.pixelSize.small * 1.2
                        color:          Appearance.m3colors.m3onSurface
                    }
                    Item { Layout.preferredWidth: root.trailingPad }
                }
            }
        }

        // ── TAIL (fused to the bottom edge of the last tile) ───────────────
        Item {
            width:  root.dialogWidth
            height: root.tailHeight

            Shape {
                x: root.tailCenterX - root.tailWidth / 2
                width:  root.tailWidth
                height: root.tailHeight

                ShapePath {
                    fillColor:   root.cardColor
                    strokeColor: "transparent"
                    startX: 0;                    startY: 0
                    PathLine { x: root.tailWidth;      y: 0 }
                    PathLine { x: root.tailWidth / 2; y: root.tailHeight }
                    PathLine { x: 0;                   y: 0 }
                }
            }
        }
    }
}