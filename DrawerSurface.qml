pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.services

Rectangle {
    id: root

    // ── Control Panel ──────────────────────────────────────────────────────────
    // All tuneable values live here. Adjust here only — do not hardcode elsewhere.

    // Grid layout
    readonly property int columns:        5
    readonly property int rows:           4
    readonly property int appsPerPage:    columns * rows
    readonly property int appCellWidth:   100
    readonly property int appCellHeight:  110
    readonly property int dynamicColSpacing: 48
    readonly property int dynamicRowSpacing: 16
    
    readonly property int gridContentWidth:  (columns * appCellWidth)  + ((columns - 1) * dynamicColSpacing)
    readonly property int gridContentHeight: (rows * appCellHeight) + ((rows - 1) * dynamicRowSpacing)

    // Icon appearance
    readonly property int    iconChipSize: 64
    readonly property int    iconSize:     60
    readonly property string iconShape:    "Circular"   // "Circular" | "Rounded" | "None"

    // Search bar
    readonly property int searchBarCollapsedWidth: 500
    readonly property int searchBarExpandedWidth:  694
    readonly property int searchIconPixelSize: Appearance.font.pixelSize.huge
    readonly property bool resetSearchOnClose: true

    // Footer / bottom row
    readonly property int paginationRowHeight: 40
    readonly property int avatarSize:          32
    readonly property int filterStaggerMs:     9

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
    Keys.onPressed: (event) => {
        if (event.text.length > 0 && !searchField.activeFocus) {
            searchField.forceActiveFocus()
        }
    }
    Keys.forwardTo: [searchField]

    Component.onCompleted: {
        displayedApps = filteredApps
        resolveUserAvatar()
    }
    onVisibleChanged: {
        if (visible) {
            displayedApps = filteredApps
            root.forceActiveFocus()
        } else {
            if (resetSearchOnClose) clearSearch()
        }
    }

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

    property int pageCount: Math.max(1, Math.ceil(displayedApps.length / appsPerPage))

    // ── Filter animation state ─────────────────────────────────────────────────
    property var  displayedApps:   []
    property bool filterAnimating: false
    property bool filterTrigger:   false

    // ── Search bar state ───────────────────────────────────────────────────────
    property bool searchHasText: false

    // ── User avatar ────────────────────────────────────────────────────────────
    property string userAvatarPath: ""

    // ── Handlers ───────────────────────────────────────────────────────────────

    function getPage(pageIndex) {
        return displayedApps.slice(pageIndex * appsPerPage, (pageIndex + 1) * appsPerPage)
    }

    function selectCategory(index) {
        selectedCategory = index
        triggerFilterAnimation()
    }

    function onSearchChanged(text) {
        searchText = text
        searchHasText = text.length > 0
        triggerFilterAnimation()
    }

    function launchApp(entry) {
        entry.execute()
        root.closeRequested()
    }

    function triggerFilterAnimation() {
        if (filterAnimating) return
        filterAnimating = true
        gridFadeOut.start()
    }

    function commitFilteredApps() {
        displayedApps = filteredApps
        swipeView.currentIndex = 0
        filterTrigger = !filterTrigger
    }

    function clearSearch() {
        searchField.clear()
        searchField.focus = false
        root.forceActiveFocus()
    }

    function resolveUserAvatar() {
        avatarProbeProcess.running = true
    }

    // ── Avatar probe ───────────────────────────────────────────────────────────
    Process {
        id: avatarProbeProcess
        running: false
        command: [
            "bash", "-c",
            "for f in \"$HOME/.face.icon\" \"$HOME/.face\" \"/var/lib/AccountsService/icons/$USER\"; do [ -f \"$f\" ] && echo \"$f\" && break; done"
        ]
        stdout: SplitParser {
            onRead: data => {
                root.userAvatarPath = data.trim()
            }
        }
    }

    // ── Grid fade animation ────────────────────────────────────────────────────
    SequentialAnimation {
        id: gridFadeOut

        NumberAnimation {
            target: swipeView
            property: "opacity"
            to: 0
            duration: 125 // Appearance.animation.elementMoveExit.duration
            easing.type: Easing.InOutQuad
        }

        ScriptAction {
            script: root.commitFilteredApps()
        }

        NumberAnimation {
            target: swipeView
            property: "opacity"
            to: 1
            duration: 125 // Appearance.animation.elementMoveEnter.duration
            easing.type: Easing.InOutQuad
        }

        ScriptAction {
            script: root.filterAnimating = false
        }
    }

    // ── Root Card ──────────────────────────────────────────────────────────────

    width:  Math.round((rootLayout.implicitWidth + 96) * 1.15)
    height: rootLayout.implicitHeight + 80
    radius: 45
    color:  Appearance.colors.colLayer0

    MouseArea {
        anchors.fill: parent
        onClicked: {
            searchField.focus = false
            root.forceActiveFocus()
        }
    }

    // Border
    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: "transparent"
        border.color: Appearance.colors.colLayer0Border
        border.width: 1
    }

    ColumnLayout {
        id: rootLayout
        anchors.centerIn: parent
        spacing: 0

        // SEARCH BAR CONTAINER
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 48

            Rectangle {
                id: searchBar
                anchors.centerIn: parent
                width: (searchField.activeFocus || root.searchHasText)
                           ? root.searchBarExpandedWidth
                           : root.searchBarCollapsedWidth
                height: 48
                radius: Appearance.rounding.full

                // Fill color — layer1 at rest, layer2Hover when focused
                color: searchField.activeFocus
                    ? Appearance.colors.colLayer2Hover
                    : Appearance.colors.colLayer1

                Behavior on width {
                    NumberAnimation {
                        duration: 200
                        easing.type: Easing.InOutQuad
                    }
                }
                Behavior on color {
                    ColorAnimation {
                        duration: 200
                        easing.type: Easing.InOutQuad
                    }
                }

                // Focus border — fades in as a primary-color ring when focused
                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: "transparent"
                    border.width: 2
                    border.color: searchField.activeFocus
                        ? Appearance.m3colors.m3primary
                        : "transparent"
                    opacity: searchField.activeFocus ? 1.0 : 0.0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 200
                            easing.type: Easing.InOutQuad
                        }
                    }
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

                // Search icon
                Text {
                    id: searchIconText
                    text: "󰍉"
                    font.pixelSize: root.searchIconPixelSize
                    font.family: Appearance.font.family.iconNerd
                    color: searchField.activeFocus
                        ? Appearance.m3colors.m3primary
                        : Appearance.colors.colOnLayer1
                    anchors.verticalCenter: parent.verticalCenter

                    Behavior on color {
                        ColorAnimation {
                            duration: Appearance.animation.elementMoveSmall.duration
                            easing.type: Appearance.animation.elementMoveSmall.type
                            easing.bezierCurve: Appearance.animation.elementMoveSmall.bezierCurve
                        }
                    }
                }

                // Text input — fills space between the two flanking icons
                TextInput {
                    id: searchField
                    // Width: total row width minus both icon widths and both spacings
                    // clearButton is always in the layout (visibility via opacity only),
                    // so we always subtract its full width to prevent layout jitter.
                    width: searchBarRow.width
                           - searchIconText.implicitWidth
                           - clearButtonContainer.width
                           - searchBarRow.spacing * 2
                    anchors.verticalCenter: parent.verticalCenter
                    color: Appearance.colors.colOnLayer0
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.family: Appearance.font.family.main
                    selectionColor: Appearance.m3colors.m3primary
                    selectedTextColor: Appearance.m3colors.m3onPrimary
                    onTextChanged: {
                        root.onSearchChanged(text)
                        if (text.length > 0 && !searchField.activeFocus) {
                            searchField.forceActiveFocus()
                        }
                        if (text.length === 0) {
                            focus = false
                            root.forceActiveFocus()
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

                // Clear button — styled as an icon button with padding (like Flutter's IconButton)
                // Always occupies its width in the Row to prevent layout jitter on show/hide.
                Item {
                    id: clearButtonContainer
                    width: 32    // fixed width: 24px icon + 4px padding each side
                    height: 32
                    anchors.verticalCenter: parent.verticalCenter
                    opacity: root.searchHasText ? 1.0 : 0.0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Appearance.animation.elementMoveFast.type
                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                        }
                    }

                    // Hover background pill
                    Rectangle {
                        anchors.fill: parent
                        radius: Appearance.rounding.full
                        color: clearMouse.containsMouse
                            ? Appearance.colors.colLayer1Hover
                            : "transparent"

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
                        enabled: root.searchHasText
                        onClicked: root.clearSearch()
                    }
                }
            }
            } // searchBar
        } // search container

        // CATEGORY CHIPS
        Item { Layout.preferredHeight: 14 }

        Row {
            id: chipsRow
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
            Layout.preferredWidth: root.gridContentWidth
            Layout.preferredHeight: root.gridContentHeight
            clip: true
            currentIndex: 0

            Repeater {
                model: root.pageCount

                delegate: Item {
                    id: pageItem
                    required property int index

                    readonly property bool shouldLoad: SwipeView.isCurrentItem
                                                    || SwipeView.isPreviousItem
                                                    || SwipeView.isNextItem

                    Loader {
                        anchors.fill: parent
                        active: pageItem.shouldLoad

                        sourceComponent: Component {
                            Grid {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: parent.top
                                columns: root.columns
                                rowSpacing: root.dynamicRowSpacing
                                columnSpacing: root.dynamicColSpacing

                                Repeater {
                                    model: root.getPage(pageItem.index)

                                    delegate: Item {
                                        id: appCell
                                        required property var modelData
                                        required property int index

                                        readonly property string iconSource:
                                            "image://icon/" + (modelData.iconName
                                                            ?? modelData.icon
                                                            ?? modelData.iconPath
                                                            ?? "")

                                        width: root.appCellWidth
                                        height: root.appCellHeight

                                        // ── Filter float-in animation ──────────────
                                        property real animY: 0

                                        Connections {
                                            target: root
                                            function onFilterTriggerChanged() {
                                                if (!root.filterAnimating) return
                                                floatInY.stop()
                                                floatInOpacity.stop()
                                                appCell.opacity = 0
                                                appCell.animY = 15
                                                floatInDelay.interval = appCell.index * root.filterStaggerMs
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
                                            duration: 125 // Appearance.animation.elementMoveEnter.duration
                                            easing.type: Easing.InOutQuad
                                        }

                                        NumberAnimation {
                                            id: floatInOpacity
                                            target: appCell
                                            property: "opacity"
                                            from: 0
                                            to: 1
                                            duration: 125 // Appearance.animation.elementMoveEnter.duration
                                            easing.type: Easing.InOutQuad
                                        }

                                        transform: Translate { y: appCell.animY }

                                        Column {
                                            anchors.centerIn: parent
                                            spacing: 8

                                            // ICON CHIP
                                            Rectangle {
                                                width: root.iconChipSize
                                                height: root.iconChipSize

                                                radius: root.iconShape === "Circular" ? root.iconChipSize / 2
                                                      : root.iconShape === "Rounded"  ? Appearance.rounding.normal
                                                      : 0

                                                color: root.iconShape === "None"
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
                                                    source: appCell.iconSource
                                                    sourceSize: Qt.size(root.iconSize, root.iconSize)
                                                    width: root.iconSize
                                                    height: root.iconSize
                                                    smooth: true
                                                    asynchronous: true
                                                    cache: true

                                                    Text {
                                                        anchors.centerIn: parent
                                                        visible: appIcon.status === Image.Error
                                                              || appIcon.status === Image.Null
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
            }
        }

        // FOOTER SPACER
        Item { Layout.preferredHeight: 32 }

        // FOOTER
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: root.paginationRowHeight

            // CENTER — Pagination dots
            Row {
                id: paginationRow
                anchors.centerIn: parent
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

    // ── Corner Buttons ─────────────────────────────────────────────────────────

    // LEFT — User profile picture (clipped circle, opens user settings on click)
    Item {
        id: avatarContainer
        parent: root
        anchors {
            left: parent.left
            bottom: parent.bottom
            leftMargin: 36
            bottomMargin: 32
        }
        width: root.avatarSize
        height: root.avatarSize

        Item {
            id: avatarClip
            anchors.fill: parent

            Image {
                id: avatarImage
                anchors.fill: parent
                source: root.userAvatarPath.length > 0 ? ("file://" + root.userAvatarPath) : ""
                fillMode: Image.PreserveAspectCrop
                visible: false
                smooth: true
                asynchronous: true
                cache: true
            }

            Rectangle {
                id: avatarMask
                anchors.fill: parent
                radius: root.avatarSize / 2
                visible: false
            }

            OpacityMask {
                anchors.fill: parent
                source: avatarImage
                maskSource: avatarMask
                visible: root.userAvatarPath.length > 0
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
                radius: root.avatarSize / 2
                color: "transparent"
                border.color: Appearance.colors.colOnLayer1Inactive
                border.width: 1
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                Quickshell.execDetached(["systemsettings", "kcm_users"])
                root.closeRequested()
            }
        }
    }

    // RIGHT — Power / session button
    Item {
        id: powerContainer
        parent: root
        anchors {
            right: parent.right
            bottom: parent.bottom
            rightMargin: 36
            bottomMargin: 32
        }
        width: root.avatarSize
        height: root.avatarSize

        // Hover background pill
        Rectangle {
            anchors.fill: parent
            radius: Appearance.rounding.full
            color: powerMouse.containsMouse
                ? Appearance.colors.colLayer1Hover
                : "transparent"

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
            color: powerMouse.containsMouse
                ? Appearance.colors.colOnLayer0
                : Appearance.colors.colOnLayer1

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
            onClicked: GlobalStates.sessionOpen = true
        }
    }
}