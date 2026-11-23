# DosPhotoPaint — Architecture

This document records the key design decisions. Contributors (human or agent) must follow it; if you need to deviate, update this file and explain why.

## 1. Platform & toolchain

- macOS 15.0+, Swift 6 language mode, **default actor isolation = MainActor** (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`). Everything is main-actor unless marked `nonisolated`. Pure image-processing code (Imaging/) is `nonisolated` and works on `Sendable` values (`CGImage`, value structs).
- Project is generated with **XcodeGen** from `project.yml` (sources are globbed by directory; just add files — never hand-edit the `.xcodeproj`). Run `xcodegen generate` after adding/removing files.
- No third-party dependencies.
- Not sandboxed since 0.1.1 (Developer ID distribution, hardened runtime, empty `DosPhotoPaint.entitlements`): the app reads images wherever the user can; macOS TCC asks once per protected location unless Full Disk Access is granted (`Shared/FileAccess.swift` offers to open System Settings on first launch and in Settings ▸ General). The security-scoped folder bookmark code (`FolderAccess`) remains as a fallback when a folder listing is denied.

## 2. App lifecycle (AppKit, not SwiftUI `App`)

`App/main.swift` → `AppLanguage.applyAtLaunch()` (must run before any bundle string lookup) → `NSApplication` with `AppDelegate`.

Launch-mode decision uses **AppKit's own Apple Event semantics**, no timers:

| Event | AppKit callback | Behaviour |
|---|---|---|
| Launch without files (`oapp`) | `applicationShouldOpenUntitledFile` → `applicationOpenUntitledFile` → `openUntitledDocumentAndDisplay` (dialog-free; only `DocumentController.newDocument(_:)` / ⌘N shows the New Canvas dialog) | New untitled Paint canvas (unless startup-mode setting says Photo → open panel) |
| Launch with files / files opened while running (`odoc`) | AppKit routes document types to `DocumentController.openDocument(withContentsOf:display:)` (the `application(_:open:)` delegate is only a fallback for non-document URLs) | `DocumentController.openForViewing(_:)` → Photo Mode, **no** untitled canvas is created (AppKit does not send `oapp` in that case) |
| Dock click (`rapp`) | `applicationShouldHandleReopen(_:hasVisibleWindows:)` | Visible windows → left alone; a minimized main window is deminiaturized; no windows → untitled Paint canvas |
| Window restoration | NSDocumentController restoration | Restored windows suppress the untitled canvas; Finder-opened files are ordered front afterwards |

Multiple files from Finder (one `odoc` event) → **one** window whose `BrowsingSession` contains exactly those files (sorted by the user's sort order). A single file → session = the file's folder (if readable) positioned at that file.

Already-open file → existing window is brought to front (no duplicate).

## 3. Documents

`ImageDocument: NSDocument` is the single document class (images + `.dpp` projects + untitled canvases).

- **Lazy materialization.** Opening an image for viewing does *not* build an editable canvas. `read(from:ofType:)` only records the URL and reads lightweight properties (pixel size, type, orientation). The viewer displays a downsampled image from `ImageCache`. The full-resolution editable `CanvasModel` is created on demand (`ImageDocument.materializeCanvas()` – async, decodes off the main thread) when the user enters Paint Mode or performs an edit (e.g. rotate in Photo Mode).
- Once materialized, the canvas lives as long as the document. Photo ↔ Paint switching never reloads, never resets zoom, never touches undo.
- `autosavesInPlace == false` — autosave-in-place would overwrite originals. Crash recovery uses NSDocument's separate autosave location with `autosavingFileType = dpp` (layers preserved). Untitled canvases are autosaved too.
- Saving writes via NSDocument's safe-save (temp file + atomic replace). Writing an image type flattens the layers; if the document has more than one layer the user is warned and offered "Save as Project (.dpp)".
- Opening/viewing never writes. Only explicit Save/Save As/Export writes.
- Undo uses the document's `NSUndoManager`. Mode switches are not undoable actions.

## 4. Window

`MainWindowController` (one per window) owns:

- `WindowState` (`@Observable`): mode (`.photo` / `.paint`), zoom, cursor position, status text…
- `BrowsingSession`: ordered list of URLs + current index (Photo navigation). Navigating replaces the window's document (`removeWindowController` / `addWindowController`). A clean document is closed when navigated away from; a dirty one triggers the standard save/don't-save/cancel sheet first.
- Layout: `NSSplitViewController` — [tool palette | canvas | inspector]. Photo Mode collapses both side panes. Status bar at the bottom (SwiftUI). Two NSToolbars (photo / paint) swapped on mode change.
- A single `CanvasScrollView` (`NSScrollView` with magnification 0.1…32) + `CanvasView` is shared by both modes — that is why switching modes keeps zoom/scroll.

## 5. Canvas engine (Editor/Model, Editor/View)

- `RasterBuffer`: 8-bit RGBA premultiplied bitmap `CGContext` in the document colour space (sRGB for new canvases; the source RGB profile for opened images, so ICC profiles are preserved). Provides zero-copy sub-rect `CGImage` views (`withImage(in:)`) for drawing and copy-out (`copyImage(in:)`) for undo.
- `Layer`: id, name, visibility, opacity, `RasterBuffer`.
- `CanvasModel` (`@Observable`): size, colour space, layers, active layer, selection, composite cache. Change notification: `onInvalidate(rect)` closure for the view (pixel-rect granularity — no full redraws while painting).
- `CanvasRenderer`: composites visible layers into the composite buffer **only for the dirty rect**, including the live stroke buffer of the active tool (normal or destination-out for the eraser) inside a transparency layer so that stroke opacity is uniform.
- Coordinates: **image pixel space** is the canvas view's own coordinate space (1 image pixel = 1 point at magnification 1, y-down via `isFlipped`). The scroll view's `magnification` is the zoom. 100 % = 1 px per point; "Actual pixels" = 1 px per device pixel (`1 / backingScaleFactor`). Window/screen ↔ image conversion is done only via `CanvasView.convert(_:from:)`; never hand-roll zoom math.

## 6. Undo strategy

- Painting (pen/brush/eraser/shape/fill/text commit): **region undo** — the pixels of the affected rect *before* the edit are copied once (`RasterBuffer.copyImage(in:)`) and registered with the undo manager; undo swaps them back and registers the inverse. One stroke = one undo action.
- Structural edits (resize, crop, rotate, flip, layer add/delete/merge/reorder/properties): **snapshot undo** of the affected layers (`CanvasSnapshot`).
- `levelsOfUndo` is limited (setting, default 50, range 5...200) to bound memory. There is no byte-based cap on the undo stack (see PERFORMANCE.md).

## 7. Imaging (nonisolated)

- `ImageLoader`: Image I/O. `loadDisplayImage(url:maxPixelSize:)` uses `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceCreateThumbnailWithTransform` (EXIF orientation applied, downsampled). `loadFullImage(url:)` decodes full resolution and applies the EXIF orientation explicitly.
- `ImageEncoder`: Image I/O destinations; supported write types are taken from `CGImageDestinationCopyTypeIdentifiers()` at runtime (HEIC only if the OS can encode it). JPEG: quality + background colour for transparency. GPS stripped by default.
- `ImageCache`: `NSCache` keyed by URL + size class, cost-limited (eviction is NSCache's, approximately LRU rather than an explicit LRU list), in-flight decodes are shared, cleared on memory pressure (`DispatchSource.makeMemoryPressureSource`) when the setting is on. `cancelPrefetch` only drops queued prefetches, not decodes already running.
- Supported read types: from `CGImageSourceCopyTypeIdentifiers()` intersected with the declared list (PNG, JPEG, HEIC/HEIF, BMP, TIFF, GIF, WebP). WebP is only advertised if the OS decoder exists.

## 8. Localization

English (development language) + Japanese, String Catalogs (`*.xcstrings`), one table per module (`Documents`, `Menu`, `Paint`, `Settings`, `Toolbar`, `Viewer`, `Window`, plus `InfoPlist`). Use `String(localized: "key", table: "Viewer")` with an English default value.
Language setting (System / 日本語 / English) is applied at launch through the argument domain (`AppleLanguages`), so it never permanently pollutes defaults. "System" means: Japanese if the first preferred language is Japanese, English otherwise. Changing it asks to relaunch.

## 9. Settings

`AppSettings` (`Settings/AppSettings.swift`) is the single source of truth: keys, defaults, ranges, validation. UI binds to it; other code reads typed properties. Invalid stored values fall back to defaults; numeric values are clamped.

## 10. Module ownership

| Folder | Contents |
|---|---|
| App/ | main, AppDelegate, menus, actions protocol, language |
| Documents/ | ImageDocument, DocumentController, DPP format |
| Window/ | MainWindowController (+ extensions), WindowState, toolbars, split layout, context menus, drop handling |
| Window/Panels | tool palette, inspector, layers panel, status bar, option views, resize/canvas-size sheets, image info view |
| Viewer/ | BrowsingSession, preloading, slideshow, info panel, GIF playback |
| Editor/Model | RasterBuffer, Layer, CanvasModel, renderer, selection model (`CanvasSnapshot` is defined in Layer.swift) |
| Editor/View | CanvasScrollView, CanvasView, TextEditingOverlay |
| Tools/ | Tool protocol + each tool |
| Imaging/ | loader, encoder, metadata, cache, transforms (nonisolated) |
| Settings/ | AppSettings + settings UI |
| Shared/ | small helpers |
