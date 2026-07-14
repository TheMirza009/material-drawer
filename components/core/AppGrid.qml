pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common

Item {
    id: appGridContainer

    property var appsModel: []
    property int columns: 5
    property int rows: 4
    property int appCellWidth: 100
    property int appCellHeight: 110
    property int dynamicColSpacing: 48
    property int dynamicRowSpacing: 16
    property int iconChipSize: 64
    property int iconSize: 48
    property string iconShape: "Circular"
    property int filterStaggerMs: 9

    property alias currentIndex: swipeView.currentIndex
    property alias pageCount: swipeView.count
    
    // We mock this property to avoid DrawerSurface breaking since it expects it from SwipeView
    property real swipeViewOpacity: 1.0

    signal appClicked(var entry)

    // internal logic for paging
    readonly property int appsPerPage: columns * rows
    readonly property int computedPageCount: Math.ceil(appsModel.length / appsPerPage)

    property bool filterTrigger: false
    property bool filterAnimating: false

    function getPage(pageIndex) {
        return appsModel.slice(pageIndex * appsPerPage, (pageIndex + 1) * appsPerPage)
    }

    function commitApps(newApps) {
        appsModel = newApps
        filterTrigger = !filterTrigger

        Qt.callLater(() => {
            swipeView.currentIndex = 0
            if (swipeView.contentItem && swipeView.contentItem.contentX !== undefined) {
                swipeView.contentItem.contentX = 0
            }
        })
    }

    ListView {
        id: swipeView
        anchors.fill: parent
        clip: true
        currentIndex: 0
        orientation: ListView.Horizontal
        snapMode: ListView.SnapOneItem
        highlightRangeMode: ListView.StrictlyEnforceRange
        boundsBehavior: Flickable.StopAtBounds
        
        // M3 standard for long spatial transitions (swiping pages)
        highlightMoveDuration: 300
        highlightMoveVelocity: -1

        model: appGridContainer.computedPageCount

        delegate: Item {
            id: pageItem
            required property int index

            width: swipeView.width
            height: swipeView.height

            readonly property var pageApps: {
                var dummy = appGridContainer.appsModel
                return appGridContainer.getPage(pageItem.index)
            }

            Grid {
                anchors.left: parent.left
                anchors.top: parent.top
                columns: appGridContainer.columns
                rowSpacing: appGridContainer.dynamicRowSpacing
                columnSpacing: appGridContainer.dynamicColSpacing

                Repeater {
                    model: pageItem.pageApps

                    delegate: Item {
                        id: appCell
                        required property var modelData
                        required property int index

                        readonly property string iconSource:
                            "image://icon/" + (modelData.iconName
                                            ?? modelData.icon
                                            ?? modelData.iconPath
                                            ?? "")

                        width: appGridContainer.appCellWidth
                        height: appGridContainer.appCellHeight

                        property real animY: 0

                        Connections {
                            target: appGridContainer
                            function onFilterTriggerChanged() {
                                if (!appGridContainer.filterAnimating) return
                                floatInY.stop()
                                floatInOpacity.stop()
                                appCell.opacity = 0
                                appCell.animY = 15
                                floatInDelay.interval = appCell.index * appGridContainer.filterStaggerMs
                                floatInDelay.restart()
                            }
                        }

                        Timer {
                            id: floatInDelay
                            repeat: false
                            onTriggered: {
                                floatInY.start()
                                floatInOpacity.start()
                            }
                        }

                        NumberAnimation {
                            id: floatInY
                            target: appCell
                            property: "animY"
                            from: 15
                            to: 0
                            duration: 150
                            easing.type: Easing.OutCubic
                        }

                        NumberAnimation {
                            id: floatInOpacity
                            target: appCell
                            property: "opacity"
                            from: 0
                            to: 1
                            duration: 150
                            easing.type: Easing.OutCubic
                        }

                        transform: Translate { y: appCell.animY }

                        Column {
                            anchors.centerIn: parent
                            spacing: 8

                            Rectangle {
                                width: appGridContainer.iconChipSize
                                height: appGridContainer.iconChipSize

                                radius: appGridContainer.iconShape === "Circular" ? appGridContainer.iconChipSize / 2
                                      : appGridContainer.iconShape === "Rounded"  ? Appearance.rounding.normal
                                      : 0

                                color: appGridContainer.iconShape === "None"
                                    ? "transparent"
                                    : (appMouse.containsMouse
                                        ? Appearance.colors.colLayer2Hover
                                        : Appearance.colors.colLayer2)

                                anchors.horizontalCenter: parent.horizontalCenter

                                Behavior on color {
                                    ColorAnimation {
                                        duration: Appearance.animation.elementMoveSmall.duration
                                        easing.type: Appearance.animation.elementMoveSmall.type
                                        easing.bezierCurve: Appearance.animation.elementMoveSmall.bezierCurve
                                    }
                                }

                                transform: Scale {
                                    xScale: appMouse.pressed ? 0.93 : 1.0
                                    yScale: appMouse.pressed ? 0.93 : 1.0
                                    origin.x: appGridContainer.iconChipSize / 2
                                    origin.y: appGridContainer.iconChipSize / 2
                                    Behavior on xScale {
                                        NumberAnimation {
                                            duration: Appearance.animation.elementMoveSmall.duration
                                            easing.type: Appearance.animation.elementMoveSmall.type
                                            easing.bezierCurve: Appearance.animation.elementMoveSmall.bezierCurve
                                        }
                                    }
                                    Behavior on yScale {
                                        NumberAnimation {
                                            duration: Appearance.animation.elementMoveSmall.duration
                                            easing.type: Appearance.animation.elementMoveSmall.type
                                            easing.bezierCurve: Appearance.animation.elementMoveSmall.bezierCurve
                                        }
                                    }
                                }

                                Image {
                                    id: appIcon
                                    anchors.centerIn: parent
                                    source: appCell.iconSource
                                    sourceSize: Qt.size(appGridContainer.iconSize, appGridContainer.iconSize)
                                    width: appGridContainer.iconSize
                                    height: appGridContainer.iconSize
                                    smooth: true
                                    asynchronous: true
                                    cache: true

                                    Text {
                                        anchors.centerIn: parent
                                        visible: appIcon.status === Image.Error || appIcon.status === Image.Null
                                        text: (appCell.modelData.name ?? "?").charAt(0).toUpperCase()
                                        color: Appearance.colors.colOnLayer2
                                        font.pixelSize: Appearance.font.pixelSize.huge
                                        font.family: Appearance.font.family.main
                                        font.weight: Font.Medium
                                    }
                                }
                            }

                            Text {
                                width: appGridContainer.appCellWidth - 8
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: appCell.modelData.name ?? ""
                                color: Appearance.colors.colOnLayer0
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.family: Appearance.font.family.main
                                elide: Text.ElideRight
                                horizontalAlignment: Text.AlignHCenter
                                maximumLineCount: 1
                            }
                        }

                        MouseArea {
                            id: appMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: appGridContainer.appClicked(appCell.modelData)
                        }
                    }
                }
            }
        }
    }
}
