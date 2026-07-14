pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.common

Item {
    id: powerItem
    
    property int size: 32
    
    signal clicked()

    width: size
    height: size

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.full
        color: powerMouse.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"

        Behavior on color {
            ColorAnimation {
                duration: Appearance.animation.elementMoveSmall.duration
                easing.type: Appearance.animation.elementMoveSmall.type
                easing.bezierCurve: Appearance.animation.elementMoveSmall.bezierCurve
            }
        }
    }

    Text {
        id: powerIcon
        anchors.centerIn: parent
        text: "power_settings_new"
        font.family: Appearance.font.family.iconMaterial
        font.pixelSize: Appearance.font.pixelSize.large
        color: powerMouse.containsMouse ? Appearance.colors.colOnLayer0 : Appearance.colors.colOnLayer1

        Behavior on color {
            ColorAnimation {
                duration: Appearance.animation.elementMoveSmall.duration
                easing.type: Appearance.animation.elementMoveSmall.type
                easing.bezierCurve: Appearance.animation.elementMoveSmall.bezierCurve
            }
        }
    }

    MouseArea {
        id: powerMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: powerItem.clicked()
    }
}
