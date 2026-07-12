# Material Drawer — Android 17 Refactor
## Complete Implementation Plan (LLM Handoff Document)

---

## 0. Context & Constraints

### What this is
A surgical refactor of two files in the Quickshell `ii` (illogical-impulse) config:
- `~/.config/quickshell/ii/modules/materialDrawer/DrawerSurface.qml` — primary
- `~/.config/quickshell/ii/modules/materialDrawer/MaterialDrawerWindow.qml` — minor

### Files NOT touched
`shell.qml`, `GlobalStates.qml`, `Appearance.qml`, `keybinds.lua`, `rules.lua`, `SidebarRightContent.qml`, and any file under `modules/settings/`. Every changed line must trace directly to a task in this document.

### Rules of execution
1. **Surgical changes only.** Do not reformat, rename, or restructure anything not listed here.
2. **No hardcoded durations, easing curves, or font sizes.** All animation values must reference `Appearance.animation.*` or `Appearance.animationCurves.*` tokens. All font sizes must reference `Appearance.font.pixelSize.*`.
3. **No new imports** unless a specific one is listed in this plan and the reason is stated.
4. **Verify before writing.** Read the full file before touching it. Confirm the line a change targets exists before editing it.
5. **String-match icon shape enum.** QML does not have native enums; use string literals `"Circular"`, `"Rounded"`, `"None"` for the `iconShape` control panel property.
6. **No extraction of widgets** into separate methods or components unless a widget subtree appears 3+ times in the file AND is used across multiple files.
7. **One continuous QML object tree** per component. No `_buildX()`-style functions.

### Singletons available (do not reimport, they are globally registered)
- `Appearance` — colors, rounding, fonts, animation tokens
- `GlobalStates` — global state flags (e.g. `sessionOpen`)
- `SystemInfo` — `username` (string, populated by `whoami` at startup)
- `DesktopEntries` — application list
- `Quickshell` — `execDetached()`

---

## 1. Full File Inventory & Current State

### DrawerSurface.qml — current structure (top to bottom)
```
Rectangle (root, 700×760, card)
└── MouseArea (background click absorber)
└── Rectangle (border)
└── ColumnLayout (anchors: fill, margins 28/22/28/28)
    ├── Rectangle (search bar, fillWidth, h:48)
    │   └── Row
    │       ├── Text (search icon, Nerd font 󰍉)
    │       └── TextInput (id: searchField, w:580)
    │           └── Text (placeholder)
    ├── Item (spacer, h:14)
    ├── Row (category chips, AlignHCenter)
    │   └── Repeater → Rectangle (chip) → Text (chipLabel)
    ├── Item (spacer, h:18)
    ├── SwipeView (id: swipeView, fillWidth, fillHeight)
    │   └── Repeater (model: pageCount) → Item (pageItem)
    │       └── Grid (columns:5, rowSpacing:8, columnSpacing:0)
    │           └── Repeater (model: pageApps) → Item (appCell)
    │               ├── Column
    │               │   ├── Rectangle (icon chip, 64×64, rounding.normal)
    │               │   │   ├── Scale transform (press bounce)
    │               │   │   └── Image (id: appIcon, 36×36, async)
    │               │   │       └── Text (fallback letter)
    │               │   └── Text (app label)
    │               └── MouseArea (id: appMouse)
    ├── Item (spacer, h:12)
    └── Row (pagination dots, AlignHCenter)
        └── Repeater → Rectangle (dot, 8px or 20px wide)
```

### MaterialDrawerWindow.qml — current structure
```
Scope (root)
├── IpcHandler (target: "materialDrawer")
└── PanelWindow (id: drawerWindow)
    ├── Region (emptyRegion)
    ├── Item (fullArea)
    ├── Region (fullRegion)
    ├── Connections (GlobalFocusGrab → hide)
    ├── MouseArea (dismiss overlay)
    └── DrawerSurface (id: drawerSurface)
```

---

## 2. Control Panel — Complete New Property List

Replace the existing Control Panel block at the top of `DrawerSurface.qml` with the following. Properties already present keep their names. New properties are marked `[NEW]`.

```qml
// ── Control Panel ──────────────────────────────────────────────────────────
// All tuneable values live here. Adjust here only — do not hardcode elsewhere.

// Grid layout
readonly property int columns:        5
readonly property int rows:           4
readonly property int appsPerPage:    columns * rows
readonly property int appCellWidth:   120                // [CHANGED] was 110
readonly property int appCellHeight:  130                // [CHANGED] was 100
readonly property int rowSpacing:     24                 // [NEW] was hardcoded 8 in Grid
readonly property int columnSpacing:  16                 // [NEW] was hardcoded 0 in Grid

// Icon appearance
readonly property int    iconChipSize: 64
readonly property int    iconSize:     36
readonly property string iconShape:   "Circular"        // [NEW] "Circular" | "Rounded" | "None"

// Search bar
readonly property int searchBarCollapsedWidth: 420      // [NEW] width when unfocused & empty
readonly property int searchBarExpandedWidth:  644      // [NEW] width when focused or has text (700 - 28*2 margins)
readonly property int searchIconPixelSize: Appearance.font.pixelSize.huge   // [NEW] was .large

// Footer / bottom row
readonly property int paginationRowHeight: 40           // [NEW]
readonly property int avatarSize:          32           // [NEW] profile picture diameter
readonly property int filterStaggerMs:     18           // [NEW] ms delay per icon in float-in animation

// Category definitions (unchanged)
readonly property var categoryDefs: [
    { label: "All",         categories: [] },
    { label: "Internet",    categories: ["Network"] },
    { label: "Development", categories: ["Development"] },
    { label: "Office",      categories: ["Office", "Education"] },
    { label: "System",      categories: ["Settings", "System", "Utility", "Science"] },
    { label: "Media",       categories: ["AudioVideo", "Graphics"] },
]
```

**Important:** `appCellWidth` increased to 120 to accommodate the wider `columnSpacing`. The card is 700px wide, 28px margins each side = 644px usable. 5 columns × 120px + 4 gaps × 16px = 600 + 64 = 664px — slightly over. Adjust: `appCellWidth: 116` and `columnSpacing: 14` puts it at 580 + 56 = 636px, comfortably within 644px. The implementor should verify this arithmetic at runtime and adjust one value by 1–2px if clipping occurs. Final values to use: **`appCellWidth: 116`, `columnSpacing: 14`**.

---

## 3. State — New Properties

Add these after the existing state block (after `property int pageCount`):

```qml
// ── Filter animation state ─────────────────────────────────────────────────
property var  displayedApps:    []       // grid renders this, not filteredApps directly
property bool filterAnimating:  false    // true during fade-out/in; gates stagger trigger
property bool filterTrigger:    false    // toggled to signal icon delegates to re-animate

// ── Search bar state ───────────────────────────────────────────────────────
property bool searchHasText:    false    // drives clear button visibility & bar width

// ── User avatar ────────────────────────────────────────────────────────────
property string userAvatarPath: ""       // resolved in Component.onCompleted via Process
```

---

## 4. Handler Functions — Changes & Additions

### 4a. Change `onSearchChanged`

```qml
// BEFORE:
function onSearchChanged(text) {
    searchText = text
    swipeView.currentIndex = 0
}

// AFTER:
function onSearchChanged(text) {
    searchText = text
    searchHasText = text.length > 0
    // Do not reset swipeView.currentIndex here —
    // the filter animation sequence handles it while the grid is invisible.
    triggerFilterAnimation()
}
```

### 4b. Change `selectCategory`

```qml
// BEFORE:
function selectCategory(index) {
    selectedCategory = index
    swipeView.currentIndex = 0
}

// AFTER:
function selectCategory(index) {
    selectedCategory = index
    triggerFilterAnimation()
}
```

### 4c. Add `triggerFilterAnimation` (new function)

```qml
function triggerFilterAnimation() {
    if (filterAnimating) return
    filterAnimating = true
    gridFadeOut.start()
}
```

### 4d. Add `commitFilteredApps` (new function, called mid-animation)

```qml
function commitFilteredApps() {
    displayedApps = filteredApps
    swipeView.currentIndex = 0
    filterTrigger = !filterTrigger   // flip to signal delegates
}
```

### 4e. Keep `launchApp` unchanged.

### 4f. Add `clearSearch` (new function, called by clear button)

```qml
function clearSearch() {
    searchField.clear()
    searchField.focus = false
    // onSearchChanged fires automatically via TextInput.onTextChanged
}
```

### 4g. Add `resolveUserAvatar` (new function, called in Component.onCompleted)

```qml
function resolveUserAvatar() {
    avatarProbeProcess.running = true
}
```

---

## 5. Processes & Lifecycle

### 5a. Avatar probe Process — add inside the root Rectangle

```qml
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
```

**Import required:** `Quickshell.Io` is already imported in `MaterialDrawerWindow.qml` but NOT in `DrawerSurface.qml`. Add `import Quickshell.Io` to `DrawerSurface.qml`'s import block.

### 5b. Update `Component.onCompleted`

```qml
// BEFORE:
Component.onCompleted: searchField.forceActiveFocus()

// AFTER:
Component.onCompleted: {
    displayedApps = filteredApps
    resolveUserAvatar()
    searchField.forceActiveFocus()
}
```

### 5c. Update `onVisibleChanged`

```qml
// BEFORE:
onVisibleChanged: if (visible) searchField.forceActiveFocus()

// AFTER:
onVisibleChanged: {
    if (visible) {
        displayedApps = filteredApps
        searchField.forceActiveFocus()
    }
}
```

**Note:** When the drawer becomes visible, `displayedApps` is refreshed so any apps installed while the drawer was closed appear immediately without needing a filter animation.

---

## 6. SequentialAnimation — Grid Fade Out/In

Add this `SequentialAnimation` inside the root Rectangle, as a sibling of the `ColumnLayout` (not inside it — it is a non-visual element):

```qml
SequentialAnimation {
    id: gridFadeOut

    // Phase 1: fade SwipeView out
    NumberAnimation {
        target: swipeView
        property: "opacity"
        to: 0
        duration: Appearance.animation.elementMoveExit.duration   // 200ms
        easing.type: Appearance.animation.elementMoveExit.type
        easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
    }

    // Phase 2: commit new data while invisible
    ScriptAction {
        script: root.commitFilteredApps()
    }

    // Phase 3: fade SwipeView back in
    NumberAnimation {
        target: swipeView
        property: "opacity"
        to: 1
        duration: Appearance.animation.elementMoveEnter.duration  // 400ms
        easing.type: Appearance.animation.elementMoveEnter.type
        easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
    }

    // Phase 4: unlock
    ScriptAction {
        script: root.filterAnimating = false
    }
}
```

---

## 7. Search Bar — Full Replacement

Replace the entire search bar `Rectangle` block (currently lines ~120–172) with:

```qml
// SEARCH BAR
Rectangle {
    id: searchBar
    Layout.alignment: Qt.AlignHCenter
    // NOTE: NOT Layout.fillWidth — width is animated between two fixed values
    width: (searchField.activeFocus || root.searchHasText)
               ? root.searchBarExpandedWidth
               : root.searchBarCollapsedWidth
    height: 48
    radius: Appearance.rounding.full
    color: searchField.activeFocus
        ? Appearance.colors.colLayer2Hover
        : Appearance.colors.colLayer1

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

    Row {
        id: searchBarRow
        anchors {
            verticalCenter: parent.verticalCenter
            left: parent.left
            right: parent.right
            leftMargin: 16
            rightMargin: 12
        }
        spacing: 10

        // Search icon
        Text {
            id: searchIconText
            text: "󰍉"
            font.pixelSize: root.searchIconPixelSize         // was .large, now .huge
            font.family: Appearance.font.family.iconNerd
            color: Appearance.colors.colOnLayer1
            anchors.verticalCenter: parent.verticalCenter
        }

        // Text input — fills remaining space between icons
        TextInput {
            id: searchField
            width: searchBarRow.width
                   - searchIconText.width
                   - clearButton.width
                   - searchBarRow.spacing * 2
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

        // Clear button
        Text {
            id: clearButton
            text: "󰅖"                                // Nerd font: nf-md-close_circle
            font.pixelSize: Appearance.font.pixelSize.normal
            font.family: Appearance.font.family.iconNerd
            color: Appearance.colors.colOnLayer1
            anchors.verticalCenter: parent.verticalCenter
            opacity: root.searchHasText ? 1.0 : 0.0

            Behavior on opacity {
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                enabled: root.searchHasText
                onClicked: root.clearSearch()
            }
        }
    }
}
```

---

## 8. Category Chips Row — Minor Change

Add `id: chipsRow` to the `Row` element so it can be referenced if needed. No other changes to this section.

```qml
// CHANGE: add id only
Row {
    id: chipsRow
    Layout.alignment: Qt.AlignHCenter
    spacing: 8
    // ... rest unchanged
}
```

---

## 9. SwipeView & Grid — Full Replacement

Replace the entire `SwipeView` block with the following. Key structural changes:
- `SwipeView` model now driven by `displayedApps` (via `pageCount` computed from `displayedApps.length`) rather than `filteredApps` directly.
- Each page `Item` is wrapped in a `Loader` that only activates for current/adjacent pages (lazy loading — the biggest performance win).
- Each app delegate gets a stagger float-in animation gated by `filterTrigger`.
- Icon chip `radius` is driven by `iconShape`.
- `rowSpacing` and `columnSpacing` now reference control panel properties.

### 9a. Update `pageCount` computed property

```qml
// CHANGE: was filteredApps, now displayedApps
property int pageCount: Math.max(1, Math.ceil(displayedApps.length / appsPerPage))
```

Also add a helper that operates on `displayedApps`:

```qml
// CHANGE: was filteredApps
function getPage(pageIndex) {
    return displayedApps.slice(pageIndex * appsPerPage, (pageIndex + 1) * appsPerPage)
}
```

### 9b. SwipeView replacement

```qml
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

            // Lazy loading: only render this page and the adjacent ones.
            // This is the primary performance improvement for large app lists.
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
                        rowSpacing: root.rowSpacing        // was hardcoded 8
                        columnSpacing: root.columnSpacing  // was hardcoded 0

                        Repeater {
                            model: root.getPage(pageItem.index)

                            delegate: Item {
                                id: appCell
                                required property var modelData
                                required property int index

                                // Cached icon source — avoids re-evaluating the
                                // ?? chain on every render pass.
                                readonly property string iconSource:
                                    "image://icon/" + (modelData.iconName
                                                    ?? modelData.icon
                                                    ?? modelData.iconPath
                                                    ?? "")

                                width: root.appCellWidth
                                height: root.appCellHeight

                                // ── Filter float-in animation ──────────────────
                                // Fires when filterTrigger flips AND filterAnimating
                                // is true (i.e. triggered by filter/search, not by
                                // manual page swipe).
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
                                    duration: Appearance.animation.elementMoveEnter.duration
                                    easing.type: Appearance.animation.elementMoveEnter.type
                                    easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
                                }
                                NumberAnimation {
                                    id: floatInOpacity
                                    target: appCell
                                    property: "opacity"
                                    from: 0
                                    to: 1
                                    duration: Appearance.animation.elementMoveEnter.duration
                                    easing.type: Appearance.animation.elementMoveEnter.type
                                    easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
                                }
                                transform: Translate { y: appCell.animY }

                                Column {
                                    anchors.centerIn: parent
                                    spacing: 8

                                    // ICON CHIP
                                    Rectangle {
                                        width: root.iconChipSize
                                        height: root.iconChipSize

                                        // iconShape drives radius and background
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
                                            source: appCell.iconSource   // cached property
                                            sourceSize: Qt.size(root.iconSize, root.iconSize)
                                            width: root.iconSize
                                            height: root.iconSize
                                            smooth: true
                                            asynchronous: true
                                            cache: true

                                            // Fallback letter when icon fails
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
```

---

## 10. Bottom Row — Full Replacement

Replace the existing `Item { Layout.preferredHeight: 12 }` spacer and the `Row` (pagination dots block) with the following single `Item`:

```qml
// FOOTER
Item {
    Layout.fillWidth: true
    Layout.preferredHeight: root.paginationRowHeight

    // LEFT — User profile picture
    Item {
        id: avatarContainer
        anchors {
            left: parent.left
            verticalCenter: parent.verticalCenter
        }
        width: root.avatarSize
        height: root.avatarSize

        // Circular clip container
        Rectangle {
            id: avatarClip
            anchors.fill: parent
            radius: root.avatarSize / 2
            color: Appearance.colors.colLayer2
            clip: true

            // Avatar image (shown when path resolved)
            Image {
                id: avatarImage
                anchors.fill: parent
                source: root.userAvatarPath.length > 0 ? root.userAvatarPath : ""
                fillMode: Image.PreserveAspectCrop
                visible: root.userAvatarPath.length > 0
                         && status !== Image.Error
                         && status !== Image.Null
                smooth: true
                asynchronous: true
                cache: true
            }

            // Fallback: Material person icon
            Text {
                anchors.centerIn: parent
                visible: !avatarImage.visible
                text: "person"
                font.family: Appearance.font.family.iconMaterial
                font.pixelSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnLayer2
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: Quickshell.execDetached(["gnome-control-center", "user-accounts"])
        }
    }

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

    // RIGHT — Power / session button
    Item {
        id: powerContainer
        anchors {
            right: parent.right
            verticalCenter: parent.verticalCenter
        }
        width: root.avatarSize
        height: root.avatarSize

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
```

---

## 11. Import Block — DrawerSurface.qml

The current import block:
```qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.services
```

Add one import:
```qml
import Quickshell.Io
```

Reason: `Process` (used for avatar path probe) is defined in `Quickshell.Io`. This import is already present in `MaterialDrawerWindow.qml` but not in `DrawerSurface.qml` where the `Process` now lives.

---

## 12. MaterialDrawerWindow.qml — No Changes Required

The avatar probe `Process` lives in `DrawerSurface.qml` (which has access to `SystemInfo.username` via the globally registered singleton). No changes to `MaterialDrawerWindow.qml` are needed.

---

## 13. `filteredApps` — No Changes

The existing computed `filteredApps` property stays exactly as written. The animation system uses `displayedApps` (a plain `property var`) as the grid's data source. `filteredApps` continues to be the reactive computed source; `displayedApps` is what the grid renders, updated only after fade-out completes.

---

## 14. Complete DrawerSurface.qml — Structural Skeleton

For clarity, the final top-level structure of the file after all changes (non-visual elements shown inline):

```
pragma ComponentBehavior: Bound
[imports including Quickshell.Io]

Rectangle {
    id: root

    // ── Control Panel ──────────────────────────────
    [all tuneables from Section 2]

    // ── Signals ────────────────────────────────────
    signal closeRequested

    // ── Lifecycle ──────────────────────────────────
    focus: true
    Keys.onEscapePressed: root.closeRequested()
    Component.onCompleted: { displayedApps = filteredApps; resolveUserAvatar(); searchField.forceActiveFocus() }
    onVisibleChanged: { if (visible) { displayedApps = filteredApps; searchField.forceActiveFocus() } }

    // ── State ──────────────────────────────────────
    property int selectedCategory: 0
    property string searchText: ""
    property var allApps: DesktopEntries.applications.values ?? []
    property var filteredApps: { ... }     // unchanged
    property int pageCount: Math.max(1, Math.ceil(displayedApps.length / appsPerPage))
    property var  displayedApps:   []
    property bool filterAnimating: false
    property bool filterTrigger:   false
    property bool searchHasText:   false
    property string userAvatarPath: ""

    // ── Avatar probe ───────────────────────────────
    Process { id: avatarProbeProcess; ... }

    // ── Grid fade animation ────────────────────────
    SequentialAnimation { id: gridFadeOut; ... }

    // ── Handlers ───────────────────────────────────
    function getPage(pageIndex) { ... }
    function selectCategory(index) { ... }
    function onSearchChanged(text) { ... }
    function launchApp(entry) { ... }
    function triggerFilterAnimation() { ... }
    function commitFilteredApps() { ... }
    function clearSearch() { ... }
    function resolveUserAvatar() { ... }

    // ── Root card visuals ──────────────────────────
    width: 700
    height: 760
    radius: 45
    color: Appearance.colors.colLayer0

    MouseArea { anchors.fill: parent }

    Rectangle { /* border */ }

    ColumnLayout {
        anchors { fill: parent; topMargin: 28; bottomMargin: 22; leftMargin: 28; rightMargin: 28 }
        spacing: 0

        // SEARCH BAR
        Rectangle { id: searchBar; ... }

        // CATEGORY CHIPS
        Item { Layout.preferredHeight: 14 }
        Row { id: chipsRow; ... }

        // APP GRID
        Item { Layout.preferredHeight: 18 }
        SwipeView { id: swipeView; ... }

        // FOOTER
        Item { /* avatar + pagination + power */ }
    }
}
```

---

## 15. Verification Checklist

The implementing LLM must confirm each item before considering the task complete:

**Functional**
- [ ] Drawer opens → search bar is expanded (focused) and app grid shows all apps
- [ ] Clicking away from search bar with no text → bar animates to collapsed width (420px)
- [ ] Clicking away from search bar WITH text → bar stays expanded, text preserved
- [ ] Typing in search bar → bar expands if not already, clear button fades in
- [ ] Pressing clear button → text clears, bar collapses, clear button fades out, focus drops
- [ ] Selecting a category chip → grid fades out, updates, fades in with icon float-in stagger
- [ ] Typing a search query → same fade+float animation triggers (once per `triggerFilterAnimation()` call, not per keystroke if `filterAnimating` is true)
- [ ] Manual page swipe → NO float-in animation (gated by `filterAnimating` flag)
- [ ] Escape key → drawer closes
- [ ] Click outside card → drawer closes

**Visual**
- [ ] Icons are circular (default `iconShape: "Circular"` → `radius = iconChipSize / 2`)
- [ ] Changing `iconShape` to `"Rounded"` → `radius = Appearance.rounding.normal`
- [ ] Changing `iconShape` to `"None"` → no background rectangle visible, icon floats on card
- [ ] Row spacing is visibly increased vs. original (24px rows, 14px columns)
- [ ] Search icon is larger than original (`huge` = 22px vs previous `large` = 17px)
- [ ] Bottom row: avatar circle on left, pagination dots centered, power icon on right
- [ ] Avatar shows user's profile picture if `~/.face.icon`, `~/.face`, or `/var/lib/AccountsService/icons/$USER` exists
- [ ] Avatar falls back to `person` Material symbol when no file found
- [ ] Power icon hover → color animates to `colOnLayer0`

**Performance**
- [ ] Pages not adjacent to current page are not rendered (Loader inactive)
- [ ] No console warnings about binding loops or undefined properties
- [ ] Icon images load asynchronously with no UI stutter on first open

**Code hygiene**
- [ ] `import Quickshell.Io` added to DrawerSurface.qml
- [ ] No hardcoded duration numbers anywhere in the file
- [ ] No hardcoded easing curve arrays anywhere in the file
- [ ] No `_buildX()` functions created
- [ ] `filteredApps` property is untouched
- [ ] `MaterialDrawerWindow.qml` is untouched

---

## 16. Known Edge Cases & How to Handle Them

| Edge case | Expected behaviour |
|---|---|
| `avatarProbeProcess` finds no file | `userAvatarPath` stays `""` → `avatarImage.visible = false` → `person` icon shows |
| `avatarImage` loads but returns `Image.Error` | Same fallback via `visible` binding on `avatarImage` |
| `filteredApps` is empty (no search match) | `displayedApps = []` → `pageCount = 1` → grid shows empty page (no crash) |
| `filterAnimating = true` when another filter change arrives | `triggerFilterAnimation()` returns early — the in-flight animation completes first, then the stale data shows briefly. Acceptable; the animation duration is short (600ms total). |
| `displayedApps` updates before `gridFadeOut` fires `commitFilteredApps` | Not possible — `displayedApps` is only written in `commitFilteredApps()` and `Component.onCompleted` / `onVisibleChanged`. `filteredApps` is the reactive computed property; `displayedApps` is the manual mirror. |
| `SwipeView.isCurrentItem` unavailable on a page inside a `Repeater` | This is a valid attached property in Qt 6 / Quickshell. If a QML error is thrown, replace `shouldLoad` with `Math.abs(swipeView.currentIndex - pageItem.index) <= 1` as fallback. |
| `gnome-control-center user-accounts` not available | The avatar `MouseArea` click fails silently (no crash). Acceptable for now; this is a known limitation of targeting a GNOME command in a Hyprland session. |

---

## 17. Future Work (Out of Scope — Do Not Implement Now)

### Settings page integration
The tuneable control panel values (`iconShape`, `rowSpacing`, `columnSpacing`, `searchBarCollapsedWidth`, `searchBarExpandedWidth`, `filterStaggerMs`, `avatarSize`, `columns`, `rows`, `iconChipSize`, `iconSize`) should eventually be moved to `Config.options` and exposed in the illogical-impulse settings app under a new **"App Drawer"** settings page.

The settings app (`~/.config/quickshell/ii/settings.qml`) loads pages from `modules/settings/*.qml`. A new page would follow the same pattern as `InterfaceConfig.qml` or `GeneralConfig.qml` — a `ScrollView` containing a `ColumnLayout` of setting rows using the common widget set (`StyledText`, `RippleButton`, toggle switches, sliders). The navigation entry would be added to the `pages` array in `settings.qml` with icon `"grid_view"` and name `"App Drawer"`.

Once `Config.options.materialDrawer.*` properties are defined (requires changes to the config schema), `DrawerSurface.qml`'s control panel properties become bindings to `Config.options.materialDrawer.*` rather than hardcoded values, and the Process / `Component.onCompleted` logic stays identical.

**This is a separate task. Do not touch `settings.qml` or any file under `modules/settings/` in this implementation.**

### Suggestions for a future Android 17 pass
| Feature | Notes |
|---|---|
| Smooth sliding page indicator | Replace the expanding-dot pagination with a pill that translates horizontally between positions. Very high value, low effort. |
| Scroll-wheel page navigation | Add `onWheel` to the `SwipeView`'s `MouseArea` to page left/right. |
| Ripple press effect on icon | Radial `Rectangle` expand from tap point on `appMouse.onClicked`. |
| Pinned / recent apps row | A horizontal strip above category chips showing the 4 most-recently-launched apps, persisted via a small JSON file in `~/.config/quickshell/`. |
| App long-press context menu | Floating `Rectangle` popup with "App info" (`Quickshell.execDetached(["gnome-software", "--details=<id>"])`) and "Uninstall". |

---

## 18. Animation Token Reference

All animation values in this implementation must use these tokens. No numeric literals.

| Use case | Token |
|---|---|
| Search bar width change | `Appearance.animation.elementMoveSmall` |
| Search bar color change | `Appearance.animation.elementMoveSmall` (ColorAnimation) |
| Clear button fade in/out | `Appearance.animation.elementMoveFast` |
| Grid fade out | `Appearance.animation.elementMoveExit` |
| Grid fade in | `Appearance.animation.elementMoveEnter` |
| Icon float-in (y + opacity) | `Appearance.animation.elementMoveEnter` |
| Chip color change | `Appearance.animation.elementMoveSmall` (unchanged) |
| Icon chip color on hover | `Appearance.animation.elementMoveSmall` (unchanged) |
| Icon chip scale on press | `Appearance.animation.elementMoveSmall` (unchanged) |
| Pagination dot width/color | `Appearance.animation.elementMoveSmall` (unchanged) |
| Power icon color on hover | `Appearance.animation.elementMoveSmall` |

Token property access pattern:
```qml
duration: Appearance.animation.elementMoveSmall.duration
easing.type: Appearance.animation.elementMoveSmall.type
easing.bezierCurve: Appearance.animation.elementMoveSmall.bezierCurve
```

---

*Plan version: 1.0 — covers DrawerSurface.qml and MaterialDrawerWindow.qml only.*
*Author context: Mirza's illogical-impulse Quickshell config, EndeavourOS + Hyprland, GNOME fallback.*