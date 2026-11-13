# 0004 — Menu bar: the icons under the camera, in the notch

Status: accepted for 0.15.0 (2026-11-13). Answers at the end.

## Problem

On a Mac with a notch, the menu bar is split in two. When the right side fills up, macOS doesn't wrap or scroll: the icons that don't fit sit **under the camera**, invisible and unclickable. People lose apps they installed on purpose (a VPN, a clipboard manager) and don't know where they went.

The notch is exactly where those icons disappear, so it's where they should come back.

## What macOS 26 does

Measured on this Mac (macOS 26.5.1, 14" MacBook Pro) with the window list:

- Every menu bar item is a window at the status layer (25), **owned by Control Center**, whatever app it belongs to. The window list no longer says which app an icon is.
- Without Screen Recording, a window has no name either. Bounds are free: 15 items, two of them (x 771 and 809) inside the camera's gap (663–848), marked off-screen.
- `NSScreen.auxiliaryTopLeftArea` / `auxiliaryTopRightArea` give the two halves of the menu bar, so "under the camera" is a plain rectangle test.
- System Settings → Menu Bar now lets people turn apps' items off. It hides; it doesn't bring back what the camera covers.

So knowing **which** icon is under the camera, and pressing it, needs Accessibility: each app's `AXExtrasMenuBar` lists its items with their frames, and `AXPress` opens the real menu.

## Decision

A built-in **Menu Bar** feature, off by default. It needs Accessibility; Screen Recording is optional, for exact icon images. It's not an extension API: other apps' menu bar items are too tied to the system and too revealing (what you run) to hand to extension code.

### Where the icons go

In the open notch, the header has empty space left of the camera; Home and Settings sit on the right. The icons hidden under the camera appear **there, on the left of the header**, in their menu bar order, like the missing piece of the menu bar.

- Up to five icons; with more, four and a `+N` that opens a Menu Bar page in place, a grid of every hidden icon at Home's tile size, the same no-scroll rule.
- Nothing hidden, nothing shown: the header stays as it is today.
- Clicking an icon closes the notch and opens that app's real menu, as clicking it in the menu bar would.

### Icons

- With Screen Recording: the item's own image, captured once when the notch opens and cached, never a continuous recording.
- Without it: the app's icon; Control Center's items get the SF Symbol macOS uses for them, and a helper with no app (a script's tray icon) its initial. Asking for Screen Recording to show an icon is a lot, so it's **Show exact icons**, off by default.
- A captured image is trimmed to what's drawn. A grey one is a template drawn in the menu bar's ink, which may be dark: the notch redraws it white. A wide one, such as the clock's date, would shrink to nothing and keeps the symbol.

### Moving icons off the menu bar

NotchNotch adds one status item, a divider, as Bartender and Ice do. While hidden it's 10 000 pt wide and pushes every icon left of it off the menu bar; those are the ones the notch shows. The first time, it goes right after the last icon a live activity's wings (96 pt) would cover, so the notch never sits over half an icon.

It takes no slot of its own: no chevron to show the icons. macOS needs ⌘ held to drag a status item, so **holding ⌘ with the pointer in the menu bar** brings the hidden icons back with the divider, a thin bar; dragging one across it moves it in or out, and letting go of ⌘ hides them again, unless a menu is open or a drag goes on. For finding it: **Rearrange Menu Bar…** in Settings, with the ⌘ hint, and at the bottom of the `+N` page, shows them for a few seconds, until the pointer leaves the menu bar. The ⌘ check is a global `flagsChanged` monitor, which sees modifier keys only, never typing.

The wings never grow to cover an icon: macOS never puts an app's menus under the camera, it moves them past it, and wider wings would cover them.

### What counts as hidden

Two things hide an icon, and both count:

- **macOS** hides the ones that don't fit beside the camera. The window list marks them off-screen; macOS also keeps a few points' margin, so an item just right of the camera can be hidden too. Read the flag, don't compute it.
- **NotchNotch's own silhouette** covers more: the wings of a live activity (up to 96 pt each side) and of extra live activities (132 pt). Those icons are on screen for macOS, but under our black shape. The covered band is the current compact silhouette's width, so it changes as wings grow and shrink, and the list follows it.

### Opening a hidden item's menu

An item under the camera still has a frame, so `AXPress` opens its menu below the notch where the item really is. An item pushed off the menu bar opens its menu off the screen, so pressing one shows the hidden icons first (they come back in their places, under the camera too) and presses it once the menu bar has settled; they hide again when its menu closes.

## Rules

1. Off by default; turning it on asks for Accessibility with a sentence on why. Without the grant, the setting explains and links to System Settings.
2. Reads menu bar items when an app launches or the status windows change, off the main thread, never on a timer.
3. Never moves, hides or rearranges anyone's items in 0.15.
4. Nothing about menu bar items leaves the app, and extensions never see them.

## Later, not in 0.15

**A hint in Home** when the feature is off and icons are hidden ("3 menu bar icons are under the camera. Show them in the notch?").

**Moving icons for the person.** The divider starts right of what the notch covers, and the person moves icons across it with ⌘-drag while ⌘ shows them, as with Bartender and Ice. Choosing them from NotchNotch's settings would need synthesized ⌘-drags, which NotchNotch doesn't do. NotchNotch's divider also competes with Ice's or Bartender's; with one of those running, theirs decides.

## Spike (2026-11-13, macOS 26.5.1, 14" MacBook Pro)

A throwaway probe with Accessibility, run from Terminal (an ad-hoc signed app without a window couldn't be added to the Accessibility list on macOS 26).

- **`AXExtrasMenuBar` works.** Each app still lists its items with frames: Claude, CleanShot X, Memory Cleaner, Throne… System items come from Control Center with identifiers (`com.apple.menuextra.battery`, `…clock`) and spoken titles; third-party items mostly have no title, so the app's name and icon name them.
- **Frames don't equal windows.** AX gives the icon's box, the window adds padding (window 849 w 38, item 856 w 24). Match by the item's center inside a window, not by equal frames.
- **Control Center reports zero-sized items** for system extras that are turned off. Skip them.
- **`AXPress` works on an item under the camera** (Claude's, at x 808): the action succeeds and its menu opens below the notch, where the item is.
- **Our wings hide more than the camera.** With the camera alone, one icon was hidden; under 96 pt wings, three more (Yojam, an app called tray_darwin_release, Throne); under 132 pt wings, Now Playing too.
- **A full scan is slow: 5.7 s for 122 apps**, because unresponsive apps wait out the AX timeout. So the app never scans on open: it keeps each app's items, scans an app when it launches or its status windows change, off the main thread with a short timeout, and skips apps that never had an item.

- **A spacer of our own works, once it's placed.** Our first spacer came up hidden only because a new status item goes to the far left, which on a full menu bar is under the camera. With `NSStatusItem Preferred Position <autosaveName>` set before the item is made, it goes elsewhere; at length 10 000 every item left of it moves off the screen (negative x, window off-screen), and back at 20 they return in order. The front app's menus stay where they are and take clicks; the empty bar still belongs to the app.
- **`Preferred Position` is a sort key, not a place.** Items are ordered by it, larger further left; it reads like points from the right edge only because macOS writes it that way when an item is dragged, and other apps' keys go stale. 0 puts an item right of every app's, beside Control Center. A key that puts the divider right after a given icon can't be computed, so the first time it's found by bisection: try a key, wait until the menu bar stops moving (items slide in, a removed one fades), see whether anything the notch covers is still right of the divider. About twelve tries, some 20 s, once; macOS keeps the key after that, and a ⌘-drag changes it.
- **Pressing an item off the screen doesn't show its menu**: it opens at the item's place, off the screen too. Shrinking the spacer first and pressing 0.1 s later works: the menu opens below the item, under the notch even when macOS hides the item beside the camera.
- **So the wings never grow to cover a half-cut icon.** That was tried and dropped: macOS never puts an app's menus under the camera, it moves them past it, and wider wings would cover them.
- A menu bar helper outside any app (node-systray's `tray_darwin_release`, started by `node ~/.local/bin/9router`) has no icon on disk: it's named after the script that launched it and drawn as its initial, until exact images.

Still to check while building: the real menu over an open notch (close the notch first, most likely), and ScreenCaptureKit for exact images.

## Answered

1. **Placement**: the left of the header. When there are more than fit (five), four and `+N`; `+N` opens the Menu Bar page in place, laid out by Home's rules: up to three rows, widening up to six columns, then a More list. The camera covers about 185 pt, five or six icons, so most Macs never see the page; it exists for the Mac with a full menu bar, and for wide wings, which cover three or four more.
2. **Icons**: app icons without extra permission; exact images when the person turns on Screen Recording under Settings → Menu Bar.
3. **Scope**: 0.15 brings back only what macOS hides. Moving any icon into the notch waits for its spike.
