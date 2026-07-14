pragma ComponentBehavior: Bound
import QtQuick
import Qt5Compat.GraphicalEffects
import qs.modules.common

Item {
    id: avatarItem
    
    property int size: 32
    property string avatarPath: ""
    
    signal clicked()

    width: size
    height: size

    Item {
        id: avatarClip
        anchors.fill: parent

        Image {
            id: avatarImage
            anchors.fill: parent
            source: avatarItem.avatarPath.length > 0 ? ("file://" + avatarItem.avatarPath) : ""
            fillMode: Image.PreserveAspectCrop
            visible: false
            smooth: true
            asynchronous: true
            cache: true
        }

        Rectangle {
            id: avatarMask
            anchors.fill: parent
            radius: avatarItem.size / 2
            visible: false
        }

        OpacityMask {
            anchors.fill: parent
            source: avatarImage
            maskSource: avatarMask
            visible: avatarItem.avatarPath.length > 0
                     && avatarImage.status !== Image.Error
                     && avatarImage.status !== Image.Null
        }

        // Fallback: Material person icon when no avatar available
        Text {
            anchors.centerIn: parent
            visible: !parent.children[2].visible
            text: "person"
            font.family: Appearance.font.family.iconMaterial
            font.pixelSize: Appearance.font.pixelSize.large
            color: Appearance.colors.colOnLayer2
        }

        Rectangle {
            anchors.fill: parent
            radius: avatarItem.size / 2
            color: "transparent"
            border.color: Appearance.colors.colOnLayer1Inactive
            border.width: 1
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: avatarItem.clicked()
    }
}
