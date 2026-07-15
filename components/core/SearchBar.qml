pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import qs.modules.common

Rectangle {
    id: searchBar

    property int collapsedWidth: 500
    property int expandedWidth: 694
    property int iconPixelSize: 24
    property bool hasText: false
    property alias searchFieldActiveFocus: searchField.activeFocus
    property alias searchField: searchField

    signal searchTextChanged(string text)
    signal clearRequested()
    signal emptyFocusLost()
    signal navigationKeyPressed(int key)

    width: (searchField.activeFocus || hasText) ? expandedWidth : collapsedWidth
    height: 48
    radius: Appearance.rounding.full

    color: searchField.activeFocus ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer1

    Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }
    Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.InOutQuad } }

    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: "transparent"
        border.width: 2
        border.color: searchField.activeFocus ? Appearance.m3colors.m3primary : "transparent"
        opacity: searchField.activeFocus ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }
    }

    Row {
        id: searchBarRow
        anchors {
            verticalCenter: parent.verticalCenter
            left: parent.left
            right: parent.right
            leftMargin: 16
            rightMargin: 8
        }
        spacing: 10

        Text {
            id: searchIconText
            text: "󰍉"
            font.pixelSize: searchBar.iconPixelSize
            font.family: Appearance.font.family.iconNerd
            color: searchField.activeFocus ? Appearance.m3colors.m3primary : Appearance.colors.colOnLayer1
            anchors.verticalCenter: parent.verticalCenter
            Behavior on color {
                ColorAnimation {
                    duration: Appearance.animation.elementMoveSmall.duration
                    easing.type: Appearance.animation.elementMoveSmall.type
                    easing.bezierCurve: Appearance.animation.elementMoveSmall.bezierCurve
                }
            }
        }

        TextInput {
            id: searchField
            width: searchBarRow.width - searchIconText.implicitWidth - clearButtonContainer.width - searchBarRow.spacing * 2
            anchors.verticalCenter: parent.verticalCenter
            color: Appearance.colors.colOnLayer0
            font.pixelSize: Appearance.font.pixelSize.small
            font.family: Appearance.font.family.main
            selectionColor: Appearance.m3colors.m3primary
            selectedTextColor: Appearance.m3colors.m3onPrimary
            onTextChanged: {
                searchBar.searchTextChanged(text)
                if (text.length === 0) {
                    focus = false
                    searchBar.emptyFocusLost()
                }
            }

            Keys.onPressed: (event) => {
                if (event.key === Qt.Key_Left   || event.key === Qt.Key_Right   ||
                    event.key === Qt.Key_Up     || event.key === Qt.Key_Down    ||
                    event.key === Qt.Key_PageUp || event.key === Qt.Key_PageDown ||
                    event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    searchBar.navigationKeyPressed(event.key)
                    event.accepted = true
                }
            }

            Text {
                anchors.fill: parent
                text: "Type to search…"
                color: Appearance.colors.colOnLayer1
                font: searchField.font
                visible: searchField.text.length === 0 && !searchField.activeFocus
            }
        }

        Item {
            id: clearButtonContainer
            width: 32
            height: 32
            anchors.verticalCenter: parent.verticalCenter
            opacity: searchBar.hasText ? 1.0 : 0.0

            Behavior on opacity {
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: Appearance.rounding.full
                color: clearMouse.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"
                Behavior on color {
                    ColorAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Appearance.animation.elementMoveFast.type
                        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                text: "󰅖"
                font.pixelSize: Appearance.font.pixelSize.normal
                font.family: Appearance.font.family.iconNerd
                color: Appearance.colors.colOnLayer1
            }

            MouseArea {
                id: clearMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                enabled: searchBar.hasText
                onClicked: searchBar.clearRequested()
            }
        }
    }

    function clear() { searchField.clear() }
    function forceActiveFocus() { searchField.forceActiveFocus() }
}
