pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.services

Rectangle {
    id: root

    // ── Control Panel ──────────────────────────────────────────────────────────

    readonly property int columns:       5
    readonly property int rows:          4
    readonly property int appsPerPage:   columns * rows
    readonly property int iconChipSize:  64
    readonly property int iconSize:      36
    readonly property int appCellWidth:  110
    readonly property int appCellHeight: 100

    readonly property var categoryDefs: [
        { label: "All",         categories: [] },
        { label: "Internet",    categories: ["Network"] },
        { label: "Development", categories: ["Development"] },
        { label: "Office",      categories: ["Office", "Education"] },
        { label: "System",      categories: ["Settings", "System", "Utility", "Science"] },
        { label: "Media",       categories: ["AudioVideo", "Graphics"] },
    ]

    // ── Open/close ─────────────────────────────────────────────────────────────

    signal closeRequested

    focus: true
    Keys.onEscapePressed: root.closeRequested()
    Component.onCompleted: searchField.forceActiveFocus()
    onVisibleChanged: if (visible) searchField.forceActiveFocus()

    // ── State ──────────────────────────────────────────────────────────────────

    property int selectedCategory: 0
    property string searchText: ""
    property var allApps: DesktopEntries.applications.values ?? []

    property var filteredApps: {
        let apps = [...allApps].filter(app => !app.noDisplay && !app.hidden)

        const cat = categoryDefs[selectedCategory]
        if (cat.categories.length > 0) {
            apps = apps.filter(app => {
                const appCats = app.categories ?? []
                return cat.categories.some(c => appCats.includes(c))
            })
        }

        const query = searchText.trim().toLowerCase()
        if (query.length > 0) {
            apps = apps.filter(app => (app.name ?? "").toLowerCase().includes(query))
        }

        return apps.sort((a, b) => (a.name ?? "").localeCompare(b.name ?? ""))
    }

    property int pageCount: Math.max(1, Math.ceil(filteredApps.length / appsPerPage))

    // ── Handlers ───────────────────────────────────────────────────────────────

    function getPage(pageIndex) {
        return filteredApps.slice(pageIndex * appsPerPage, (pageIndex + 1) * appsPerPage)
    }

    function selectCategory(index) {
        selectedCategory = index
        swipeView.currentIndex = 0
    }

    function onSearchChanged(text) {
        searchText = text
        swipeView.currentIndex = 0
    }

    function launchApp(entry) {
        entry.execute()
        root.closeRequested()
    }

    // ── Root Card ──────────────────────────────────────────────────────────────
    // All colors, rounding, and font from Appearance — follows system theme,
    // matugen palette, dark/light mode, and transparency settings automatically.

    width:  700
    height: 760
    radius: 45 // Appearance.rounding.windowRounding
    color:  Appearance.colors.colLayer0

    // Absorbs background clicks within the card so they don't reach the window-level dismiss overlay
    MouseArea { anchors.fill: parent }

    // Border
    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: "transparent"
        border.color: Appearance.colors.colLayer0Border
        border.width: 1
    }

    ColumnLayout {
        anchors {
            fill: parent
            topMargin: 28
            bottomMargin: 22
            leftMargin: 28
            rightMargin: 28
        }
        spacing: 0

        // SEARCH BAR
        Rectangle {
            Layout.fillWidth: true
            height: 48
            radius: Appearance.rounding.full
            color: searchField.activeFocus
                ? Appearance.colors.colLayer2Hover
                : Appearance.colors.colLayer1

            Behavior on color {
                ColorAnimation {
                    duration: Appearance.animation.elementMoveSmall.duration
                    easing.type: Appearance.animation.elementMoveSmall.type
                    easing.bezierCurve: Appearance.animation.elementMoveSmall.bezierCurve
                }
            }

            Row {
                anchors {
                    verticalCenter: parent.verticalCenter
                    left: parent.left
                    leftMargin: 16
                }
                spacing: 10

                Text {
                    text: "󰍉"
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.family: Appearance.font.family.iconNerd
                    color: Appearance.colors.colOnLayer1
                    anchors.verticalCenter: parent.verticalCenter
                }

                TextInput {
                    id: searchField
                    width: 580
                    anchors.verticalCenter: parent.verticalCenter
                    color: Appearance.colors.colOnLayer0
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.family: Appearance.font.family.main
                    selectionColor: Appearance.m3colors.m3primary
                    selectedTextColor: Appearance.m3colors.m3onPrimary
                    onTextChanged: root.onSearchChanged(text)

                    Text {
                        anchors.fill: parent
                        text: "Type to search…"
                        color: Appearance.colors.colOnLayer1
                        font: searchField.font
                        visible: searchField.text.length === 0 && !searchField.activeFocus
                    }
                }
            }
        }

        // CATEGORY CHIPS
        Item { Layout.preferredHeight: 14 }

        Row {
            Layout.alignment: Qt.AlignHCenter
            spacing: 8

            Repeater {
                model: root.categoryDefs

                delegate: Rectangle {
                    id: chip
                    required property var modelData
                    required property int index

                    readonly property bool active: root.selectedCategory === index

                    width: chipLabel.implicitWidth + 24
                    height: 32
                    radius: Appearance.rounding.full
                    color: active
                        ? Appearance.m3colors.m3primaryContainer
                        : (chipMouse.containsMouse ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2)

                    Behavior on color {
                        ColorAnimation {
                            duration: Appearance.animation.elementMoveSmall.duration
                            easing.type: Appearance.animation.elementMoveSmall.type
                            easing.bezierCurve: Appearance.animation.elementMoveSmall.bezierCurve
                        }
                    }

                    Text {
                        id: chipLabel
                        anchors.centerIn: parent
                        text: chip.modelData.label
                        color: active
                            ? Appearance.m3colors.m3onPrimaryContainer
                            : Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.family: Appearance.font.family.main
                        font.weight: active ? Font.Medium : Font.Normal

                        Behavior on color {
                            ColorAnimation {
                                duration: Appearance.animation.elementMoveSmall.duration
                                easing.type: Appearance.animation.elementMoveSmall.type
                                easing.bezierCurve: Appearance.animation.elementMoveSmall.bezierCurve
                            }
                        }
                    }

                    MouseArea {
                        id: chipMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.selectCategory(chip.index)
                    }
                }
            }
        }

        // APP GRID
        Item { Layout.preferredHeight: 18 }

        SwipeView {
            id: swipeView
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            currentIndex: 0

            Repeater {
                model: root.pageCount

                delegate: Item {
                    id: pageItem
                    required property int index
                    readonly property var pageApps: root.getPage(pageItem.index)

                    Grid {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        columns: root.columns
                        rowSpacing: 8
                        columnSpacing: 0

                        Repeater {
                            model: pageItem.pageApps

                            delegate: Item {
                                id: appCell
                                required property var modelData

                                width: root.appCellWidth
                                height: root.appCellHeight

                                Column {
                                    anchors.centerIn: parent
                                    spacing: 8

                                    // ICON CHIP
                                    Rectangle {
                                        width: root.iconChipSize
                                        height: root.iconChipSize
                                        radius: Appearance.rounding.normal
                                        color: appMouse.containsMouse
                                            ? Appearance.colors.colLayer2Hover
                                            : Appearance.colors.colLayer2
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
                                            origin.x: root.iconChipSize / 2
                                            origin.y: root.iconChipSize / 2
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
                                            source: "image://icon/" + (appCell.modelData.iconName ?? appCell.modelData.icon ?? appCell.modelData.iconPath ?? "")
                                            sourceSize: Qt.size(root.iconSize, root.iconSize)
                                            width: root.iconSize
                                            height: root.iconSize
                                            smooth: true
                                            asynchronous: true

                                            // Fallback letter when icon fails
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

                                    // APP LABEL
                                    Text {
                                        width: root.appCellWidth - 8
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
                                    onClicked: root.launchApp(appCell.modelData)
                                }
                            }
                        }
                    }
                }
            }
        }

        // PAGINATION DOTS
        Item { Layout.preferredHeight: 12 }

        Row {
            Layout.alignment: Qt.AlignHCenter
            spacing: 7

            Repeater {
                model: swipeView.count

                delegate: Rectangle {
                    required property int index

                    readonly property bool active: swipeView.currentIndex === index

                    width:  active ? 20 : 8
                    height: 8
                    radius: Appearance.rounding.full
                    color:  active
                        ? Appearance.colors.colOnLayer0
                        : Appearance.colors.colOnLayer1Inactive

                    Behavior on width {
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveSmall.duration
                            easing.type: Appearance.animation.elementMoveSmall.type
                            easing.bezierCurve: Appearance.animation.elementMoveSmall.bezierCurve
                        }
                    }
                    Behavior on color {
                        ColorAnimation {
                            duration: Appearance.animation.elementMoveSmall.duration
                            easing.type: Appearance.animation.elementMoveSmall.type
                            easing.bezierCurve: Appearance.animation.elementMoveSmall.bezierCurve
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: swipeView.currentIndex = index
                    }
                }
            }
        }
    }
}