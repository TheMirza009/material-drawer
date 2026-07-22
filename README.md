# Material App Drawer — Quickshell Module

**Version:** 2.0.0  
**Last Updated:** July 22, 2026

A Material You-styled app drawer for [IllogicalImpulse](https://github.com/end-4/dots-hyprland) (the `ii` Quickshell config). Slides up from the bottom of the screen, shows all installed desktop applications, supports category filtering, search, and swipe pagination.

> [!IMPORTANT]
> This module is written specifically **for the IllogicalImpulse Quickshell configuration** (`~/.config/quickshell/ii`). It relies on singletons and services provided by the framework (such as `Appearance`, `DesktopEntries`, `GlobalFocusGrab`, and `GlobalStates`). It is not designed to run standalone.

<!-- TODO: screenshots / demo GIF here — recommended before posting to r/unixporn or similar -->

---

## Features

- Slide-up / slide-down animation via Hyprland layer rules
- Material You theming via the existing `Appearance` singleton (follows matugen palette, dark/light mode, transparency)
- Category filter chips (All, Internet, Development, Office, System, Media)
- Live search
- Swipe-paginated app grid (5 × 4 per page)
- Animated pagination dots
- User avatar with quick-access to account settings
- Floating Power Menu (Lock, Shut Down, Reboot) with staggered cinematic transitions
- Click-outside-to-dismiss full-screen overlay
- Escape key to close
- Dock stays visible on top of the drawer during open/close animation
- IPC-controllable (`qs ipc call materialDrawer toggle/open/close`)
- Global shortcut registration (`quickshell:materialDrawerToggle`)
- Automatic backup, reinstall, uninstall, and status checking (see below)

---

## File Structure

```
modules/
└── materialDrawer/
    ├── MaterialDrawerWindow.qml   ← Scope + PanelWindow wrapper
    ├── DrawerSurface.qml          ← Main drawer card UI
    ├── components/
    │   ├── core/                  ← Grid, Search, Chips, Pagination
    │   └── buttons/               ← Power Menu, User Avatar, Ripples
    └── docs/                      ← Architectural specs & workflows
```

---

## Installation

### 1. Automated Installation

You can install Material App Drawer using the automated helper script.

#### Quick Command
```bash
curl -fsSL https://raw.githubusercontent.com/TheMirza009/material-drawer/main/install.sh | bash
```

> [!NOTE]
> Piping scripts directly into `bash` is convenient, but inspecting scripts prior to execution is good practice. If you prefer reviewing code before executing, use the Git clone workflow below.
</br>
---

#### Git Clone & Setup
If you prefer inspecting the script locally or maintaining updates via `git pull`:

```bash
git clone https://github.com/TheMirza009/material-drawer
cd material-drawer
chmod +x install.sh
./install.sh
```

Both methods automatically create backups of modified files, apply required patches, install the module files, and clean up temporary files. After installation, **restart Quickshell and reload your Hyprland configuration** to apply the changes.

### Helper Script Commands

The `install.sh` script provides simple management flags:

| Command | Action |
|---|---|
| `./install.sh status` | Inspect installed files, configuration drift, or missing components |
| `./install.sh reinstall` | Restore baseline backups and reapply module patches (ideal for updates) |
| `./install.sh uninstall` | Safely restore original configuration files and remove the module |
| `./install.sh --dry-run` | Preview actions without modifying any files |
| `./install.sh --yes` | Skip interactive prompts (ideal for automated setup scripts) |

> [!WARNING]
> Running `uninstall` or `reinstall` restores configuration files from backups created during initial installation. Any manual changes made to those specific files after installing will be reverted. If you have custom edits in `Dock.qml` or `shell.qml`, please back them up beforehand.

Backups are stored safely in `~/.local/state/material-drawer/backups/`, independent of the cloned repository folder.

---

### 2. Manual Integration (Fallback)

If you prefer to integrate the module manually, or the automated script reports an anchor mismatch on your setup, follow the steps below.

**Optional — back up first.** The automated script does this for you; if you're doing it by hand, it's worth doing yourself too:

```bash
cp ~/.config/quickshell/ii/shell.qml{,.bak}
cp ~/.config/quickshell/ii/GlobalStates.qml{,.bak}
cp ~/.config/quickshell/ii/modules/ii/dock/Dock.qml{,.bak}
cp ~/.config/hypr/custom/rules.lua{,.bak}
cp ~/.config/hypr/custom/keybinds.lua{,.bak}
```

#### Step 1 — Copy the module

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
> All docks on all monitors switch to `Overlay` when the drawer opens (since `materialDrawerOpen` is a global flag). On secondary monitors this is cosmetically invisible — nothing changes — but it is a minor side-effect, not a bug.

---

### Step 5 — Edit Hyprland layer rules

File: `~/.config/hypr/custom/rules.lua`

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

```lua
hl.unbind("SUPER + SUPER_L")
hl.unbind("SUPER_L")

hl.bind("SUPER + SUPER_L",
        hl.dsp.exec_cmd("qs -p " .. os.getenv("HOME") .. "/.config/quickshell/ii ipc call materialDrawer toggle"),
        { release = true, description = "Toggle app drawer" })
```

> [!IMPORTANT]
> `release = true` is required for the "bare Super tap" pattern. Without it, the bind fires on key-down and triggers alongside every other `SUPER+X` combination.
>
> `os.getenv("HOME")` is used instead of `~` because the `exec_cmd` dispatcher may not expand shell tildes.

**Alternative — `SUPER + Space` (no release flag needed):**

```lua
hl.bind("SUPER + Space", hl.dsp.global("quickshell:materialDrawerToggle"), { description = "Toggle app drawer" })
```

---

## IPC

```bash
qs -p ~/.config/quickshell/ii ipc call materialDrawer toggle
qs -p ~/.config/quickshell/ii ipc call materialDrawer open
qs -p ~/.config/quickshell/ii ipc call materialDrawer close
```

---

## Customization

All tuneable values live at the top of `DrawerSurface.qml` under the **Control Panel** section:

| Property | Default | Description |
|---|---|---|
| `columns` | `5` | App grid columns per page |
| `rows` | `4` | App grid rows per page |
| `iconChipSize` | `64` | Size of the icon background chip (px) |
| `iconSize` | `60` | Size of the app icon within the chip (px) |
| `appCellWidth` | `100` | Width of each app cell (px) |
| `appCellHeight` | `110` | Height of each app cell (px) |
| `categoryDefs` | see file | Category chip labels and XDG category mappings |

Adjust in `MaterialDrawerWindow.qml`:

```qml
anchors.bottomMargin: 75   // ← increase if your dock is taller
```

---

## Compatibility

| Component | Tested Version | Notes |
|---|---|---|
| Quickshell | `0.2.1+` (`quickshell-git`) | Requires Qt6 & WlrLayershell support |
| Hyprland | `0.55.4+` | Tested with custom layer rules and keybindings |
| IllogicalImpulse | `0.1.0.r1-8` (`dots-hyprland`) | Requires `Appearance`, `DesktopEntries`, and `GlobalStates` singletons |

If `install.sh status` reports "drift detected" on a file, it usually means the installed IllogicalImpulse config has moved past what this module's anchor checks expect — feel free to open an issue with your `status` output.

---

## Troubleshooting

- **Drawer doesn't open at all** — run `./install.sh status` to check which files patched cleanly.
- **Dock renders behind the drawer** — likely means `Dock.qml`'s anchor check failed during install; see the install output for an `anchor_not_found` warning and re-check Step 4 manually.
- **Dock briefly elevates on other monitors when I open the drawer** — expected, see the note under Step 4. Not a bug.
- **I want it fully gone** — `./install.sh uninstall` restores your original files and removes the module.

<!-- TODO: expand as real issues come in from users -->

---

## Uninstalling

```bash
./install.sh uninstall
```

Restores your original `shell.qml`, `GlobalStates.qml`, `Dock.qml`, `rules.lua`, and `keybinds.lua` from the backups taken at install time, and removes the copied module directory. See the warning under Installation about edits made after install also being reverted.

---

## Credits

Built for and depends on [IllogicalImpulse](https://github.com/end-4/dots-hyprland) by **end-4** — this module wouldn't function without its `Appearance`, `DesktopEntries`, and `GlobalStates` singletons.

---

## License

MIT — see [LICENSE](./LICENSE).

<!-- TODO: CHANGELOG.md and git tags once a release cadence exists;
     CONTRIBUTING.md if/when open to external PRs. -->

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
