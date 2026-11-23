# DosPhotoPaint — Performance

Measured by `DosPhotoPaintTests/PerformanceTests.swift`. Every number is printed as `PERF <name>: <value>`:

    xcodebuild ... test -only-testing:DosPhotoPaintTests/PerformanceTests | grep PERF

## Conditions

- Machine: `sysctl hw.model` = **Mac17,3**, 32 GB RAM, macOS 27 (Darwin 27.2), local SSD.
- **Debug** configuration (the test host is the Debug app). Image I/O / Core Graphics are system code and
  perform like Release; app code (window creation, SwiftUI, tool code) is slower than Release, so
  absolute numbers of app-side steps are upper bounds. `xcodebuild -configuration Release build` succeeds.
- Images are synthetic JPEGs (gradient + 4 px-blocky noise, quality 0.85): 4000×3000 (12 MP) and
  6000×4000 (24 MP). Display budget 5120 px (2560×1600 @2x screen).
- Run inside the XCTest host (activation policy `.prohibited`): no real on-screen compositing. "Draw"
  means `CanvasView.draw(_:)` into an offscreen `CGContext`.
- Timing: `ContinuousClock`; memory: `task_info(TASK_VM_INFO).phys_footprint`.
- Numbers are single runs on a machine doing other work; treat differences below ~10 % as noise.

## Method

| Area | How |
|---|---|
| Cold path | `DocumentController.openForViewing([24 MP jpg])` until the window's `CanvasView.content` is `.preview`; 3 runs, run 1 includes first-use costs (SwiftUI, Image I/O init) |
| ImageCache | `displayImage` uncached vs cached hit; stepping through 20 files with no cache vs with `ImagePreloader` neighbours prefetched (400 ms dwell per image) |
| Memory | footprint while stepping through 30 × 12 MP files (prefetch 2 ahead, 512 MB cache); footprint delta after creating a 6000×4000 `CanvasModel` |
| Brush | `StrokeTool.mouseDragged` (24 px segments) + `updateComposite()` + `CanvasView.draw(dirty)` on a 4000×3000 canvas at zoom 1 and 0.25, hard 20 px and soft 40 px brush |
| Recomposite | `invalidateAll()` + `updateComposite()`, 1 and 2 layers |
| Undo | `CanvasModel.regionUndoBytesRegistered` (debug counter: bytes handed to undo) for 50 strokes vs 50 × full layer (`byteCount`) |
| Launch | `LaunchTiming` (debug-only static; stamp at first line of `main.swift` and at the end of `applicationDidFinishLaunching`) read by a test |

**Launch limitation:** the GUI app cannot be launched from tests/CI here, so launch time is only the
in-process span `main()` → `applicationDidFinishLaunching` in the test host (≈130 ms Debug, the host skips
window creation and menu bar visibility). It excludes dyld/process start, Launch Services and first window
display. It is compiled out in Release (`#if DEBUG`).

## Results

### Before / after

| Measurement | Before | After | Change |
|---|---|---|---|
| Soft brush (40 px), per drag segment, 4000×3000, zoom 1 | 30.9 ms (p95 34.8) | 0.11 ms | 280× |
| Soft brush, zoom 0.25 | 30.9 ms | 0.11 ms | 280× |
| 50 long diagonal strokes (bbox ≈ canvas), undo bytes retained | 2124 MB (93 % of naive) | 247 MB (11 %) | 8.6× less |
| Cold open 24 MP JPEG → preview shown, median of 3 | 234 ms | 155 ms | −34 % |
| Cold open, run 1 (first use) | 397 ms | 181–212 ms | −50 % |
| Preview draw of opaque photo (full 24 MP frame, p95 / avg) | 6.7 / 10.0 ms | 3.5 / 6.7 ms (first sample is warm-up) | ≈ −50 % steady state |

### Unchanged (already good)

| Measurement | Value |
|---|---|
| Display decode, 12 MP, uncached / cached hit | 31 ms / 0.06 ms |
| Display decode, 24 MP at 5120 px, uncached / cached hit | 131 ms / 0.07 ms |
| 24 MP decode at 3000 px (JPEG DCT ½ scaling) / 1024 px | 34 ms / 28 ms |
| Stepping through 20 × 12 MP images, uncached vs preloaded (avg) | 33 ms vs 0.24 ms (max 0.35) |
| Footprint while stepping 30 × 12 MP | plateaus: first-half peak ≈ second-half peak (series ends below its start; cache cost limit 512 MB) |
| 6000×4000 canvas (layer + composite) | +183 MB footprint (= 2 × 96 MB buffers) |
| Hard brush segment (tool + composite + draw), zoom 1 / 0.25 | 0.05 / 0.06 ms |
| Full recomposite 4000×3000, 1 layer / 2 layers | 1.5 ms / 3.0 ms |
| Draw 1400×900 viewport at zoom 1 (canvas) | 2.5 ms (1.1 ms of it is the checkerboard fill, see below) |
| 50 compact strokes (≈1200×240 bbox) undo | 62 MB vs 2289 MB naive (3 %) |
| `main()` → `applicationDidFinishLaunching` (Debug, test host) | ≈ 130 ms |

## Bottlenecks found and fixes

1. **Soft brush dabs cost ~6 ms each on large canvases.** `drawRadialGradient` with
   `.drawsBeforeStartLocation` was evaluated over the whole canvas-sized clip, so cost scaled with canvas
   area, not dab size. The dab is now clipped to its own bounding box (and the `CGGradient` is built once
   per stroke instead of per dab). Output is identical (the gradient is transparent outside the radius).
   `StrokeTool.softDab`.
2. **Undo memory for sparse strokes.** Region undo saved the stroke's bounding box, so a long diagonal
   stroke retained ≈ the whole layer (48 MB at 4000×3000; with 50 levels > 2 GB, 4.8 GB at 6000×4000).
   The live preview now records which 128×128 tiles it touched; commit saves only those tiles when they
   cover < 60 % of the bounding box. Still one undo step per stroke, exact pixel restore
   (`testTiledStrokeUndoRedoRestoresPixelsExactly`). `CanvasModel.applyRegionEdit(undoTiles:)`.
3. **Cold open serialised decode behind document + window creation.** The decode (130 ms for 24 MP) only
   started once the window existed. `DocumentController.openForViewing` now starts the display decode
   for the first image immediately; the window's request joins the in-flight decode
   (`ImageCache` already shares in-flight work), so decode and window construction overlap.
   Additionally, for sources ≥ 4096 px the window shows a half-size DCT-scaled decode (≈ 1/4 of the
   cost) first and swaps in the sharp image when ready (same pixel size → zoom/scroll unaffected);
   this mainly helps navigating to images not yet preloaded. `MainWindowController.loadPreview`.
4. **Checkerboard under opaque previews.** The pattern was always filled below the photo, doubling the
   draw cost of a full-screen image. It is skipped when the preview `CGImage` has no alpha.
   `CanvasView.draw`.

## Remaining limits

- Canvas checkerboard is still filled under editable canvases (≈ 1 ms per 1400×900 viewport); skipping it
  would need an "is fully opaque" flag maintained per layer.
- Undo granularity is 128 px tiles; a dense stroke covering most of its bounding box still retains the
  bounding box (50 levels × layer size worst case: 50 × 96 MB at 6000×4000 for full-canvas fills).
  Unbounded snapshots are avoided but there is no byte budget for the undo stack.
- Large images: a 6000×4000 canvas costs 192 MB (layer + composite) plus 96 MB per extra layer and the
  stroke scratch buffer; 150 MP images are allowed by `maxEditablePixels` (≈ 1.2 GB for layer + composite).
- 24 MP sharp display decode is 130 ms regardless of the app: JPEG decoding at full size is Image I/O
  bound. The quick half-size stage hides this only for sources ≥ 4096 px.
- Phys-footprint plateau numbers depend on the system's purgeable decoded-image memory; they are
  indicative, not a hard bound. The cache cost limit (default 512 MB) is the actual bound.
- Window creation (~55–100 ms Debug) remains on the main thread; it is not parallelisable with AppKit.
- Launch time is measured only in-process (see Method); cold process start is not measured.
