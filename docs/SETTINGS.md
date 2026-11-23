# ユーザー設定

`Settings/AppSettings.swift` の全プロパティです。設定は UserDefaults に即時保存され、読み込み時に検証されます(未知の値は既定値に戻り、数値は範囲内に丸められます)。設定ウィンドウは `⌘,`。表示、ツールバー、アンドゥ段数などは即時反映、**言語は再起動後**に反映されます。設定ウィンドウの「Restore Defaults…」ボタン(確認ダイアログ付き)が `resetToDefaults()` を呼びます(`resetToDefaults()` 自体は SettingsTests でテスト済み。ボタンの実機操作は未確認)。設定ウィンドウは実機GUIでは操作確認していません(テストと全プロパティの参照確認のみ)。

## 一般

| プロパティ | 既定 | 範囲/選択肢 | 効果 |
|---|---|---|---|
| language | system | system / ja / en | UI 言語。system は優先言語の先頭が日本語なら日本語、他は英語。再起動が必要 |
| appearance | system | system / light / dark | アプリの外観 |
| startupMode | automatic | automatic / photo / paint | 引数なし起動時の動作。automatic と paint は空の Paint キャンバス、photo は「開く」パネル。ファイル指定の起動は常に Photo |
| recentDocumentsLimit | 20 | 0〜50 | 最近使った項目の数 |
| restoreWindows | true | オン/オフ | 終了時のウィンドウ保持(`NSQuitAlwaysKeepsWindows` を設定)。復元は AppKit 任せで実機未検証 |
| confirmUnsavedOnClose | true | オン/オフ | 未保存の変更がある書類を閉じる前に確認 |
| showStatusBar | true | オン/オフ | ステータスバー表示 |
| showToolbar | true | オン/オフ | ツールバー表示 |

## Photo

| プロパティ | 既定 | 範囲/選択肢 | 効果 |
|---|---|---|---|
| photoInitialZoom | fitWindow | fitWindow / actualSize / fitWidth / fitHeight | 画像を開いたときの初期ズーム |
| photoInterpolation | automatic | automatic / smooth / nearestNeighbor | 拡大縮小時の補間。automatic は縮小・中程度のズームで滑らか、高倍率で最近傍 |
| photoBrowserStyle | tiles | tiles / list | 画像一覧の表示形式(一覧のヘッダで切替) |
| photoBrowserIncludeSubfolders | false | オン/オフ | 画像一覧にサブフォルダの画像も含める |
| photoBackground | darkGray | darkGray / black / lightGray / white / window | 表示背景色。Photo ツールバーの「背景」ボタン、右クリックメニュー、表示 > 背景 からも切替可(v0.1.0) |
| photoCheckerboard | true | オン/オフ | 透明部分の市松模様 |
| photoWheel | scroll | scroll / zoom / navigate | ホイールの動作 |
| photoCommandWheel | zoom | scroll / zoom / navigate | ⌘+ホイールの動作 |
| photoZoomAtCursor | true | オン/オフ | カーソル位置を中心にズーム |
| photoFolderNavigation | true | オン/オフ | 同じフォルダの他画像を前後移動で閲覧(要フォルダアクセス許可) |
| photoSortOrder | naturalName | naturalName / name / modificationDate / creationDate | 閲覧順 |
| photoLoopNavigation | false | オン/オフ | 最初と最後でループ |
| photoPreloadCount | 2 | 0〜5 | 先読みする前後の枚数 |
| photoAutoplayGIF | true | オン/オフ | GIF の自動再生 |
| photoZoomOnNavigate | automatic | automatic / keep | 画像切替時に初期ズーム規則を再適用するか、倍率を維持するか |
| photoDoubleClick | toggleFitActual | toggleFitActual / toggleFullScreen / none | ダブルクリック動作 |

## Paint

| プロパティ | 既定 | 範囲/選択肢 | 効果 |
|---|---|---|---|
| paintDefaultWidth | 1920 | 1〜16384 | 新規キャンバスの幅(⌘N のダイアログの初期値。起動時の自動キャンバスはこの値) |
| paintDefaultHeight | 1080 | 1〜16384 | 新規キャンバスの高さ |
| paintDefaultBackground | 白 | 色 | 新規キャンバスの背景色(ダイアログの初期値) |
| paintTransparentBackground | false | オン/オフ | 新規キャンバスを透明にする |
| paintInitialTool | pen | ToolKind の raw 値(ツール層で検証) | 起動時のツール |
| paintInitialLineWidth | 3 | 1〜500 | 初期の線幅 |
| paintInitialColor | 黒 | 色 | 初期の前景色 |
| paintAntialiasing | true | オン/オフ | アンチエイリアス(ブラシは設定に関わらず常に AA) |
| paintShowGrid | false | オン/オフ | グリッド表示 |
| paintGridSpacing | 16 | 2〜512 | グリッド間隔(px) |
| paintPixelGrid | highZoom | off / highZoom | 高倍率でのピクセルグリッド |
| paintShowSelectionOutline | true | オン/オフ | 選択範囲の輪郭表示 |
| paintRememberToolSettings | true | オン/オフ | ツールごとの設定を記憶(`toolState.` キー) |
| paintUndoLevels | 50 | 5〜200 | アンドゥ段数(メモリ上限はバイトではなく段数のみ) |
| paintToolPalettePosition | top | top / left | ツールパレットの位置(v0.1.0)。top = キャンバス上部の横一列リボン(ツール・色・カラーパレット・AI 編集)、left = 従来の左側の縦パレット。即時反映 |

## 保存

| プロパティ | 既定 | 範囲/選択肢 | 効果 |
|---|---|---|---|
| saveDefaultFormat | png | png / jpeg / heic / tiff / bmp | 既定の保存形式(heic は OS が対応する場合のみ実際に使用可) |
| saveJPEGQuality | 0.9 | 0.1〜1.0 | JPEG 品質 |
| saveColorProfile | preserve | preserve / convertToSRGB | 保存時のカラープロファイル方針 |
| saveStripGPS | true | オン/オフ | GPS 情報を削除 |
| saveKeepMetadata | true | オン/オフ | EXIF / IPTC などを引き継ぐ |
| saveOverwriteConfirmation | whenNeeded | whenNeeded / always | 上書き確認。whenNeeded は情報が失われる場合(統合・非可逆形式)のみ |
| saveAutoRecover | true | オン/オフ | 回復用コピーの自動保存(有効時 15 秒間隔、無効時 0)。原本は上書きしない |
| saveJPEGBackground | 白 | 色 | JPEG で透明部分を合成する下地色 |

## スライドショー

| プロパティ | 既定 | 範囲/選択肢 | 効果 |
|---|---|---|---|
| slideshowInterval | 5 | 1〜60 秒 | 表示間隔 |
| slideshowLoop | true | オン/オフ | 最後まで行ったら最初へ |
| slideshowShuffle | false | オン/オフ | シャッフル(各巡で全画像を1回ずつ) |
| slideshowFullScreen | true | オン/オフ | フルスクリーンで開始。スライドショー中は設定に関わらずツールバーとステータスバーを隠し、フルスクリーン時はメニューバーも自動的に隠す。「フィット」は小さい画像も画面いっぱいに拡大(v0.1.0) |
| slideshowFit | fit | fit / actualSize | 画像サイズの扱い |
| slideshowTransition | none | none / dissolve | 切替効果 |

## 性能

| プロパティ | 既定 | 範囲/選択肢 | 効果 |
|---|---|---|---|
| performancePreset | automatic | automatic / lowMemory / highQuality | 下記の値を一括設定 |
| performanceCacheMB | 512 | 64〜4096 | 表示画像キャッシュ上限(MB) |
| performancePreloadEnabled | true | オン/オフ | 先読みの有効化(オフなら先読み 0 枚) |
| performanceHighQualityInterpolation | true | オン/オフ | 高品質スケーリング |
| performanceReleaseOnMemoryPressure | true | オン/オフ | メモリ圧迫時にキャッシュ破棄 |

プリセットの内容: automatic = キャッシュ 512MB・先読み 2・高品質 オン / lowMemory = 128MB・1・オフ / highQuality = 1536MB・3・オン(いずれも先読み有効、メモリ圧迫時破棄オン)。プリセット選択後に個別値を変えても、プリセット表示は「カスタム」に変わりません(軽微な既知の挙動)。
