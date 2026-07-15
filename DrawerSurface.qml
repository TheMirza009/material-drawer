pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "components/core"
import "components/buttons"

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

    // Category chips
    readonly property bool showCategoryIcons:  true

    readonly property var categoryDefs: [
        { label: "All",         categories: [], icon: "apps" },
        { label: "Internet",    categories: ["Network"], icon: "language" },
        { label: "Development", categories: ["Development"], icon: "code" },
        { label: "Office",      categories: ["Office", "Education"], icon: "work" },
        { label: "System",      categories: ["Settings", "System", "Utility", "Science"], icon: "settings" },
        { label: "Media",       categories: ["AudioVideo", "Graphics"], icon: "play_circle" },
    ]

    // ── Debug ──────────────────────────────────────────────────────────────────
    // TEMPORARY diagnostic logging. Remove once the root cause is confirmed.
    function dbg(msg) {
        console.log("[DRAWER]", Date.now() % 100000, msg)
    }

    // ── Open/close ─────────────────────────────────────────────────────────────

    signal closeRequested

    focus: true
    Keys.onEscapePressed: root.closeRequested()
    Keys.onPressed: (event) => {
        if (searchHasText) {
            if (event.key === Qt.Key_Right)   { _navigateGrid(1, true);         event.accepted = true; return }
            if (event.key === Qt.Key_Left)    { _navigateGrid(-1, true);        event.accepted = true; return }
            if (event.key === Qt.Key_Down)    { _navigateGrid(columns, false);  event.accepted = true; return }
            if (event.key === Qt.Key_Up)      { _navigateGrid(-columns, false); event.accepted = true; return }
            if (event.key === Qt.Key_PageDown) { _jumpPage(1);                  event.accepted = true; return }
            if (event.key === Qt.Key_PageUp)   { _jumpPage(-1);                 event.accepted = true; return }
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                if (appGrid.keyboardIndex >= 0) { launchApp(filteredApps[appGrid.keyboardIndex]); event.accepted = true; return }
            }
        }
        if (event.text.length > 0 && !searchBar.searchFieldActiveFocus) {
            searchBar.forceActiveFocus()
        }
    }
    Keys.forwardTo: [searchBar.searchField]

    Component.onCompleted: {
        appGrid.commitApps(filteredApps)
        resolveUserAvatar()
    }
    onVisibleChanged: {
        if (visible) {
            appGrid.commitApps(filteredApps)
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
    onFilteredAppsChanged: dbg("filteredApps CHANGED -> len=" + filteredApps.length)

    onAllAppsChanged: {
        dbg("allApps CHANGED -> len=" + allApps.length)
        if (visible && !filterAnimating && !filterPending) {
            appGrid.commitApps(filteredApps)
        }
    }

    property int pageCount: Math.max(1, Math.ceil(displayedApps.length / appsPerPage))
    onPageCountChanged: dbg("pageCount CHANGED -> " + pageCount)

    // ── Filter animation state ─────────────────────────────────────────────────
    property var  displayedApps:   []
    property bool filterAnimating: false
    property bool filterPending:   false

    onDisplayedAppsChanged: dbg("displayedApps CHANGED -> len=" + displayedApps.length)

    // ── Search bar state ───────────────────────────────────────────────────────
    property bool searchHasText: false

    // ── User avatar ────────────────────────────────────────────────────────────
    property string userAvatarPath: ""

    // ── Handlers ───────────────────────────────────────────────────────────────



    function selectCategory(index) {
        dbg("selectCategory(" + index + ")")
        selectedCategory = index
        triggerFilterAnimation()
    }

    function onSearchChanged(text) {
        dbg("onSearchChanged('" + text + "')")
        searchText = text
        searchHasText = text.length > 0
        triggerFilterAnimation()
    }

    function launchApp(entry) {
        entry.execute()
        root.closeRequested()
    }

    function appsEqual(a, b) {
        if (!a || !b) return false
        if (a.length !== b.length) return false
        for (let i = 0; i < a.length; i++) {
            if (a[i] !== b[i]) return false
        }
        return true
    }

    function triggerFilterAnimation() {
        if (appsEqual(filteredApps, appGrid.appsModel)) {
            dbg("triggerFilterAnimation -> state identical, skipping animation")
            return
        }

        dbg("triggerFilterAnimation: animating=" + filterAnimating + " pending(before)=" + filterPending)
        if (filterAnimating) {
            filterPending = true
            return
        }
        filterAnimating = true
        gridFadeOut.start()
    }

    // Called when a fade cycle completes. If a filter request arrived
    // mid-animation, it was queued via filterPending — honor it now
    // against the current (up-to-date) filteredApps rather than losing it.
    function onFilterAnimationFinished() {
        dbg("onFilterAnimationFinished: pending=" + filterPending
            + " displayedApps.len=" + displayedApps.length
            + " pageCount=" + appGrid.pageCount
            + " swipeView.count=" + appGrid.pageCount
            + " currentIndex=" + appGrid.currentIndex
            + " appGrid.swipeViewOpacity=" + appGrid.swipeViewOpacity)
        filterAnimating = false

        // Explicit geometry fix means we no longer need the visibility hack

        if (filterPending) {
            filterPending = false
            triggerFilterAnimation()
        }
    }

    function commitFilteredApps() {
        dbg("commitFilteredApps START")
        appGrid.keyboardIndex = searchHasText ? 0 : -1
        appGrid.commitApps(filteredApps)
        dbg("commitFilteredApps END")
    }

    function clearSearch() {
        dbg("clearSearch()")
        searchBar.clear()
        searchBar.searchField.focus = false
        root.forceActiveFocus()
    }

    function _navigateGrid(delta, wrap) {
        const count = filteredApps.length
        if (count === 0) return
        if (appGrid.keyboardIndex < 0) {
            appGrid.keyboardIndex = 0
            appGrid.currentIndex  = 0
            return
        }
        const next = wrap
            ? (appGrid.keyboardIndex + delta + count) % count
            : Math.max(0, Math.min(appGrid.keyboardIndex + delta, count - 1))
        appGrid.keyboardIndex = next
        appGrid.currentIndex  = Math.floor(next / appsPerPage)
    }

    function _jumpPage(direction) {
        const newPage = Math.max(0, Math.min(appGrid.currentIndex + direction, appGrid.pageCount - 1))
        if (newPage === appGrid.currentIndex) return
        appGrid.currentIndex  = newPage
        appGrid.keyboardIndex = newPage * appsPerPage
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

        onStarted: root.dbg("gridFadeOut STARTED")
        onStopped: {
            root.dbg("gridFadeOut STOPPED (raw signal, deferring finish handler)")
            Qt.callLater(root.onFilterAnimationFinished)
        }

        NumberAnimation {
            target: appGrid
            property: "opacity"
            to: 0
            duration: 125 // Appearance.animation.elementMoveExit.duration
            easing.type: Easing.InOutQuad
        }

        ScriptAction {
            script: root.commitFilteredApps()
        }

        NumberAnimation {
            target: appGrid
            property: "opacity"
            to: 1
            duration: 125 // Appearance.animation.elementMoveEnter.duration
            easing.type: Easing.InOutQuad
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
            root.dbg("ROOT SURFACE CLICKED: appGrid.swipeViewOpacity=" + appGrid.swipeViewOpacity
                + " currentIndex=" + appGrid.currentIndex
                + " displayedApps.len=" + displayedApps.length
                + " pageCount=" + appGrid.pageCount
                + " swipeView.count=" + appGrid.pageCount)
            searchBar.searchField.focus = false
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

            SearchBar {
                id: searchBar
                anchors.centerIn: parent
                collapsedWidth: root.searchBarCollapsedWidth
                expandedWidth: root.searchBarExpandedWidth
                iconPixelSize: root.searchIconPixelSize
                hasText: root.searchHasText

                onSearchTextChanged: text => root.onSearchChanged(text)
                onClearRequested: root.clearSearch()
                onEmptyFocusLost: root.forceActiveFocus()
                onNavigationKeyPressed: (key) => {
                    if (!searchHasText) return
                    if      (key === Qt.Key_Right)    _navigateGrid(1, true)
                    else if (key === Qt.Key_Left)     _navigateGrid(-1, true)
                    else if (key === Qt.Key_Down)     _navigateGrid(columns, false)
                    else if (key === Qt.Key_Up)       _navigateGrid(-columns, false)
                    else if (key === Qt.Key_PageDown) _jumpPage(1)
                    else if (key === Qt.Key_PageUp)   _jumpPage(-1)
                    else if (key === Qt.Key_Return || key === Qt.Key_Enter) {
                        if (appGrid.keyboardIndex >= 0) launchApp(filteredApps[appGrid.keyboardIndex])
                    }
                }
            }
        }

        // CATEGORY CHIPS
        Item { Layout.preferredHeight: 14 }

        CategoryChips {
            Layout.alignment: Qt.AlignHCenter
            categoryDefs: root.categoryDefs
            selectedCategory: root.selectedCategory
            showIcons: root.showCategoryIcons
            onCategorySelected: index => root.selectCategory(index)
        }

        // APP GRID
        Item { Layout.preferredHeight: 18 }

        AppGrid {
            id: appGrid
            Layout.preferredWidth: root.gridContentWidth
            Layout.preferredHeight: root.gridContentHeight
            
            columns: root.columns
            rows: root.rows
            appCellWidth: root.appCellWidth
            appCellHeight: root.appCellHeight
            dynamicColSpacing: root.dynamicColSpacing
            dynamicRowSpacing: root.dynamicRowSpacing
            iconChipSize: root.iconChipSize
            iconShape: root.iconShape
            iconSize: root.iconSize
            filterStaggerMs: root.filterStaggerMs
            
            filterAnimating: root.filterAnimating
            
            onAppClicked: entry => root.launchApp(entry)
        }

        // FOOTER
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: root.paginationRowHeight

            PaginationDots {
                anchors.fill: parent
                pageCount: appGrid.pageCount
                currentIndex: appGrid.currentIndex
                onDotClicked: index => appGrid.currentIndex = index
            }
        }
    }

    // ── Corner Buttons ─────────────────────────────────────────────────────────

    UserAvatar {
        anchors {
            left: parent.left
            bottom: parent.bottom
            leftMargin: 36
            bottomMargin: 32
        }
        size: root.avatarSize
        avatarPath: root.userAvatarPath
        onClicked: {
            Quickshell.execDetached(["systemsettings", "kcm_users"])
            root.closeRequested()
        }
    }

    PowerButton {
        anchors {
            right: parent.right
            bottom: parent.bottom
            rightMargin: 36
            bottomMargin: 32
        }
        size: root.avatarSize
        onClicked: GlobalStates.sessionOpen = true
    }
}
