# Material App Drawer — Quickshell Module

A Material You-styled app drawer for [IllogicalImpulse](https://github.com/end-4/dots-hyprland) (the `ii` Quickshell config). Slides up from the bottom of the screen, shows all installed desktop applications, supports category filtering, search, and swipe pagination.

> [!IMPORTANT]
> This module is written **for the IllogicalImpulse Quickshell config** (`~/.config/quickshell/ii`). It depends on singletons and services from that framework (`Appearance`, `DesktopEntries`, `GlobalFocusGrab`, `GlobalStates`, etc.). It will not work standalone.

---

## Features

- Slide-up / slide-down animation via Hyprland layer rules
- Material You theming via the existing `Appearance` singleton (follows matugen palette, dark/light mode, transparency)
- Category filter chips (All, Internet, Development, Office, System, Media)
- Live search
- Swipe-paginated app grid (5 × 4 per page)
- Animated pagination dots
- Click-outside-to-dismiss full-screen overlay
- Escape key to close
- Dock stays visible on top of the drawer during open/close animation
- IPC-controllable (`qs ipc call materialDrawer toggle/open/close`)
- Global shortcut registration (`quickshell:materialDrawerToggle`)

---

## File Structure

```
modules/
└── materialDrawer/
    ├── MaterialDrawerWindow.qml   ← Scope + PanelWindow wrapper
    └── DrawerSurface.qml          ← App drawer card UI
```

---

## Installation

### Step 1 — Copy the module

Copy the `materialDrawer/` directory into your Quickshell `ii` modules folder:

```bash
cp -r materialDrawer/ ~/.config/quickshell/ii/modules/materialDrawer/
```

Your directory should look like:

```
~/.config/quickshell/ii/modules/materialDrawer/
├── MaterialDrawerWindow.qml
└── DrawerSurface.qml
```

---

### Step 2 — Edit `shell.qml`

File: `~/.config/quickshell/ii/shell.qml`

**a) Add the import** near the top, alongside the other module imports:

```qml
import "modules/materialDrawer"
```

**b) Instantiate the window** inside `ShellRoot { }`, before `Component.onCompleted`:

```qml
MaterialDrawerWindow {
    id: customDrawerTest
}
```

**c) Register the global shortcut** (so Hyprland keybinds can trigger it):

```qml
GlobalShortcut {
    name: "materialDrawerToggle"
    description: "Toggle the Material app drawer"
    onPressed: customDrawerTest.toggle()
}
```

**d) Sync `GlobalStates.materialDrawerOpen`** so the dock knows when the drawer is active. The 350 ms delay keeps the dock elevated through the entire close animation (250 ms) before dropping back:

```qml
Connections {
    target: customDrawerTest
    function onDrawerOpenChanged() {
        if (customDrawerTest.drawerOpen) {
            GlobalStates.materialDrawerOpen = true
        } else {
            dockHideTimer.restart()
        }
    }
}

Timer {
    id: dockHideTimer
    interval: 350
    repeat: false
    onTriggered: GlobalStates.materialDrawerOpen = false
}
```

---

### Step 3 — Edit `GlobalStates.qml`

File: `~/.config/quickshell/ii/GlobalStates.qml`

Add this property inside the `Singleton { }` body (alongside the other `property bool` declarations):

```qml
property bool materialDrawerOpen: false
```

---

### Step 4 — Edit `Dock.qml`

File: `~/.config/quickshell/ii/modules/ii/dock/Dock.qml`

Two changes are needed so the dock appears **on top of the drawer** during its slide animation.

**a) Add `materialDrawerOpen` to the `reveal` condition** (keeps the dock visible while the drawer is open):

```qml
property bool reveal: root.pinned
    || (Config.options?.dock.hoverToReveal && dockMouseArea.containsMouse)
    || dockApps.requestDockShow
    || (!ToplevelManager.activeToplevel?.activated)
    || GlobalStates.materialDrawerOpen   // ← add this
```

**b) Dynamically elevate the dock to `WlrLayer.Overlay`** while the drawer is open, so it renders above the drawer's `WlrLayer.Top` surface:

```qml
// Before
WlrLayershell.layer: WlrLayer.Top

// After
WlrLayershell.layer: GlobalStates.materialDrawerOpen ? WlrLayer.Overlay : WlrLayer.Top
```

> [!NOTE]
> **Why `Overlay`?** Both the dock and the drawer window live on `WlrLayer.Top`. Within the same layer, the compositor controls z-order by map order — the drawer maps later, so it would render over the dock. Temporarily promoting the dock to `Overlay` (the layer above `Top`) ensures it paints on top of the drawer for the duration of the animation.

> [!WARNING]
> All docks on all monitors switch to `Overlay` when the drawer opens (since `materialDrawerOpen` is a global flag). On secondary monitors this is cosmetically invisible — nothing changes — but it is a minor side-effect.

---

### Step 5 — Edit Hyprland layer rules

File: `~/.config/hypr/custom/rules.lua` (or wherever your Hyprland Lua custom rules live)

Add these three rules:

```lua
-- Material drawer: blur, alpha handling, and slide-from-bottom animation
hl.layer_rule({ match = { namespace = "quickshell:material_drawer" }, blur = true })
hl.layer_rule({ match = { namespace = "quickshell:material_drawer" }, ignore_alpha = 0.5 })
hl.layer_rule({ match = { namespace = "quickshell:material_drawer" }, animation = "slide bottom 250 emphasizedDecel" })
```

- `blur = true` — applies the compositor blur to the card background.
- `ignore_alpha = 0.5` — tells Hyprland to treat pixels with alpha ≤ 0.5 as fully transparent for blur purposes, preventing the transparent full-screen window from blurring the entire screen.
- `animation = "slide bottom 250 emphasizedDecel"` — the open/close slide animation (250 ms, Material emphasized deceleration curve).

> [!NOTE]
> The animation name `emphasizedDecel` must be defined in your Hyprland `animations` config. IllogicalImpulse defines it by default.

---

### Step 6 — Add a keybind

File: `~/.config/hypr/custom/keybinds.lua`

The drawer exposes both a **global shortcut** (via Hyprland's `global` dispatcher) and an **IPC handler**. Due to a bug in the IllogicalImpulse Lua binding framework where `hl.dsp.global()` silently drops its function reference when combined with `release = true`, the recommended approach is to trigger the drawer via IPC using `exec_cmd`:

**Bare Super tap → toggle drawer:**

```lua
-- Remove the default Quickshell binds that use bare Super,
-- so this binding can take over the gesture cleanly.
hl.unbind("SUPER + SUPER_L")
hl.unbind("SUPER_L")

hl.bind("SUPER + SUPER_L",
        hl.dsp.exec_cmd("qs -p " .. os.getenv("HOME") .. "/.config/quickshell/ii ipc call materialDrawer toggle"),
        { release = true, description = "Toggle app drawer" })
```

> [!IMPORTANT]
> `release = true` is required for the "bare Super tap" pattern. Without it, the bind fires on key-down and triggers alongside every other `SUPER+X` combination.
>
> `os.getenv("HOME")` is used instead of `~` because the `exec_cmd` dispatcher may not expand shell tildes. This produces the full absolute path at bind-registration time in Lua.

**Alternative — `SUPER + Space` (no release flag needed):**

```qml
hl.bind("SUPER + Space", hl.dsp.global("quickshell:materialDrawerToggle"), { description = "Toggle app drawer" })
```

`hl.dsp.global()` works correctly without `release = true`.

---

## IPC

The drawer is controllable at any time via Quickshell IPC:

```bash
qs -p ~/.config/quickshell/ii ipc call materialDrawer toggle
qs -p ~/.config/quickshell/ii ipc call materialDrawer open
qs -p ~/.config/quickshell/ii ipc call materialDrawer close
```

---

## Customisation

All tuneable values live at the top of `DrawerSurface.qml` under the **Control Panel** section:

| Property | Default | Description |
|---|---|---|
| `columns` | `5` | App grid columns per page |
| `rows` | `4` | App grid rows per page |
| `iconChipSize` | `64` | Size of the icon background chip (px) |
| `iconSize` | `36` | Size of the app icon within the chip (px) |
| `appCellWidth` | `110` | Width of each app cell (px) |
| `appCellHeight` | `100` | Height of each app cell (px) |
| `categoryDefs` | see file | Category chip labels and XDG category mappings |

The card itself is **700 × 760 px**, positioned 82 px from the screen bottom (leaving space for the dock). This can be adjusted in `MaterialDrawerWindow.qml`:

```qml
anchors.bottomMargin: 82   // ← increase if your dock is taller
```

---

## Summary of All Changes

| File | Change |
|---|---|
| `modules/materialDrawer/MaterialDrawerWindow.qml` | **New file** — Scope + PanelWindow wrapper |
| `modules/materialDrawer/DrawerSurface.qml` | **New file** — App drawer card UI |
| `shell.qml` | Import, instantiate `MaterialDrawerWindow`, add `GlobalShortcut`, `Connections`, and `Timer` |
| `GlobalStates.qml` | Add `property bool materialDrawerOpen: false` |
| `modules/ii/dock/Dock.qml` | Add `materialDrawerOpen` to `reveal`; dynamic `WlrLayershell.layer` |
| `hypr/custom/rules.lua` | Three `hl.layer_rule` entries for blur, alpha, and animation |
| `hypr/custom/keybinds.lua` | Unbind defaults; bind bare Super via IPC exec |
