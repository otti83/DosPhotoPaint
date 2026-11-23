# キーボードショートカット

`App/MainMenu.swift` のコード上のキー設定をそのまま記載しています(⌘=Command、⌥=Option、⇧=Shift、⌃=Control)。メニュー項目名は英語表記で、日本語 UI では訳されます。設定 > ショートカット でも(読み取り専用で)確認できます。キーの再割り当てはできません。

## App

| 操作 | キー |
|---|---|
| Settings… | ⌘, |
| Hide DosPhotoPaint | ⌘H |
| Hide Others | ⌥⌘H |
| Quit | ⌘Q |

## File

| 操作 | キー |
|---|---|
| New Canvas(ダイアログを表示) | ⌘N |
| New from Clipboard | ⌥⌘N |
| Open… | ⌘O |
| Close | ⌘W |
| Save… | ⌘S |
| Save As… | ⇧⌘S |
| Export… | ⇧⌘E |
| Show in Finder | ⇧⌘R |
| Copy Image Path | ⌥⌘C |
| Page Setup… | ⇧⌘P |
| Print… | ⌘P |

キー無し: Open in New Window、Duplicate、Save as Project…、Revert to Saved、Allow Access to Folder…、Share…、Open Recent。

## Edit

| 操作 | キー |
|---|---|
| Undo | ⌘Z |
| Redo | ⇧⌘Z |
| Cut | ⌘X |
| Copy | ⌘C |
| Paste | ⌘V |
| Paste as New Layer | ⇧⌘V |
| Paste as New Image | ⌥⌘V |
| Select All | ⌘A |
| Deselect | ⇧⌘A |

キー無し: Delete(Paint モードのキャンバス上では Delete / Forward Delete キーでも実行)。Cut / Delete は Paint モードで選択範囲があるときのみ、Paste / Paste as New Layer は Paint モードでクリップボードに画像があるときのみ有効(Paste as New Image はクリップボードに画像があれば常に有効)。Copy は画像があれば Photo モードでも有効。

## View

| 操作 | キー |
|---|---|
| Photo / Paint Mode | ⌘E |
| Zoom In | ⌘+(隠し項目として ⌘= も有効) |
| Zoom Out | ⌘- |
| Zoom to Fit | ⌘0 |
| Actual Size (100%) | ⌘1 |
| Actual Pixels | ⌥⌘1 |
| Zoom To… | ⌥⌘Z |
| Previous Image | ⌘[ |
| Next Image | ⌘] |
| First Image | ⌥⌘[ |
| Last Image | ⌥⌘] |
| Slideshow | ⇧⌘F |
| Image Browser | ⌘B |
| Image Info | ⌘I |
| Compare with Original | ⌥⌘O |
| Hide Toolbar | ⌥⌘T |
| Show Status Bar | ⌘/ |
| Show Tool Palette | ⌃⌘1 |
| Show Inspector | ⌃⌘2 |
| Enter Full Screen | ⌃⌘F |

キー無し: Fit Width、Fit Height、Sort Images By、Background、Transparency Checkerboard。

## Image

| 操作 | キー |
|---|---|
| Rotate Left | ⌘L |
| Rotate Right | ⌘R |
| Resize Image… | ⌥⌘R |
| Canvas Size… | ⌥⇧⌘C |
| Crop to Selection | ⌘K |
| New Layer | ⇧⌘N |
| Duplicate Layer | ⌘J |
| Merge Down | ⌥⌘E |
| Flatten Image | ⌥⇧⌘F |

キー無し: Rotate 180°、Flip Horizontal / Vertical、Delete Layer、Move Layer Up / Down。

## Tools / Window / Help

| 操作 | キー |
|---|---|
| Show Colors | ⇧⌘C |
| Show Fonts | ⌘T |
| Minimize | ⌘M |
| DosPhotoPaint Help | ⌘?(コード上のキーは `?`) |

Tools メニューの各ツール項目、Swap Colors、Increase / Decrease Size にはメニューのキーはありません。単キーはキャンバスが処理します(下記)。

## キャンバスの単キー(Paint モード、修飾キーなし)

テキスト入力中(IME 変換中を含む)はテキストビューがキーを受け取るため、これらは発動しません(設計上。専用テストはなし)。

| キー | 動作 |
|---|---|
| V | 矩形選択 |
| L | 投げ縄(自由選択) |
| C | 切り抜き |
| P | ペン |
| B | ブラシ |
| E | 消しゴム |
| G | 塗りつぶし |
| I | スポイト |
| T | テキスト |
| U | 図形 |
| H | 手のひら |
| X | 前景色と背景色を入れ替え |
| ] / [ | ツールサイズを +1 / -1(Shift 併用時も処理) |
| Delete / Forward Delete | 選択範囲の削除 |
| Esc | フルスクリーン中なら解除(それ以外は何もしない) |
| Space(ドラッグ) | 一時的な手のひら(パン) |
| Shift / Option | ツールごとの補助(図形で正方形・円・45度固定 / 中心から、選択で縦横比維持、など) |

## Photo モード(修飾キーなし)

| キー | 動作 |
|---|---|
| ← / → | 前 / 次の画像 |
| Home / End | 最初 / 最後の画像 |
| Space | スライドショー中のみ一時停止/再開(それ以外は無反応) |
| Esc | スライドショー停止、またはフルスクリーン解除(それ以外は無反応) |
| ダブルクリック | 設定に従う(既定: フィット / 100% 切替) |
