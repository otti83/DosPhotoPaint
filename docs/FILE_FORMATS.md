# 対応ファイル形式

形式の可否は `Imaging/ImageTypes.swift` の定義に従い、**実行時に Image I/O へ問い合わせた結果**で決まります(宣言リストと OS 対応リストの積集合)。

## 読み込み / 書き出し

| 形式 | 読み込み | 書き出し | 備考 |
|---|---|---|---|
| PNG | 可 | 可 | アルファ保持 |
| JPEG | 可 | 可 | 品質(既定 0.9、0.1〜1.0)と、透明部分の下地色(既定 白)を指定。アルファは下地色で合成 |
| HEIC | 可(OS が復号可能な場合) | **OS がエンコード可能な場合のみ** | 非可逆。保存時に劣化の確認あり |
| HEIF | 可(OS が復号可能な場合) | 不可(宣言リストに含まれない) | Viewer ロール |
| BMP | 可 | 可 | アルファ非対応(JPEG 同様に合成) |
| TIFF | 可 | 可 | |
| GIF | 可(アニメ再生あり) | 不可 | Viewer ロール。下記参照 |
| WebP | **OS の Image I/O が復号可能と報告した場合のみ** | 不可 | Info.plist では imported type(org.webmproject.webp)として宣言し、`CGImageSourceCopyTypeIdentifiers()` に無ければ開けない形式として扱う |
| .dpp | 可 | 可 | 本アプリ独自のレイヤー保持プロジェクト(下記) |

- 読み込み可能リスト: `[png, jpeg, heic, heif, bmp, tiff, gif, webp]` を `CGImageSourceCopyTypeIdentifiers()` でフィルタ。
- 書き出し可能リスト: `[png, jpeg, heic, tiff, bmp]` を `CGImageDestinationCopyTypeIdentifiers()` でフィルタ。
- 書き出し時はレイヤーを統合します(複数レイヤーなら警告と `.dpp` 保存の提案)。
- 自動テストで開く形式の確認はあるが(testOpenEachFormatInPhotoModeWithoutTouchingOriginal)、BMP / TIFF / HEIC の保存往復専用テストはありません。

## アニメーション GIF

- Photo モード: `CGAnimateImageAtURLWithBlock` で無限ループ再生(設定 “Play animated GIFs automatically”でオン/オフ)。再生自体は自動テスト・実機とも未確認。
- Paint モード: **最初のフレームのみ**が編集対象。入る際にその旨のアラートを表示(テスト済み)。保存しても全フレームのアニメーションは保持されません。

## .dpp(プロジェクト)パッケージ

UTI `com.dosphotopaint.dpp`(パッケージ型、Owner ランク)。ディレクトリ構成:

```
Name.dpp/
  manifest.json      バージョン付きメタデータ
  layers/*.png       レイヤーごとの PNG(下から上の順)
  colorProfile.icc   カラープロファイル
  preview.png        プレビュー
```

`manifest.json` のキー: `formatVersion`(現在 1)、`generator`、`width`、`height`、`activeLayerID`、`layers`(各 `id` / `name` / `isVisible` / `opacity` / `file`)。

- 読み込み側は未知のキーを無視し、現行より新しい `formatVersion` は拒否します。
- 検証: マニフェスト欠落、破損、サイズ不正(0 以下、150MP 超)、レイヤー ID 重複、レイヤー画像サイズ不一致はエラーになります。
- テスト: testProjectRoundTripPreservesLayers。壊れた/新しいバージョンのパッケージを開くテストは見つかっていません。

## カラープロファイル

- 開いた画像のキャンバスは元の色空間(RGB プロファイル)で作られ、新規キャンバスは sRGB。8bit RGBA プリマルチプライドで保持します。
- 非対応のビットマップ色空間は sRGB にフォールバック(テスト済み)。P3 キャンバスのペン色は変換され、再解釈されません(テスト済み)。
- 保存時のポリシー(設定 > 保存): 「保持」(既定)または「sRGB に変換」。`.dpp` は `colorProfile.icc` を書き込みます。
- 保存ファイルへの埋め込みプロファイル保持を直接確認するテストはありません。

## EXIF 向き

- 読み込み時に向きを適用して正立で表示・編集します(全 8 種を Image I/O と同一に復号することをテスト済み)。不正な向き値は「上」にフォールバック。
- 書き出し時は画素を正立にした上で向きを 1(上)に設定し、TIFF 向きも除去します(二重回転を防止)。
- 情報パネルは 90 度系の向きで幅と高さを入れ替えて表示します。

## メタデータと GPS

- 保存時に元のメタデータ(EXIF/IPTC など)を引き継ぐかは設定 “Keep metadata (EXIF, IPTC)”(既定 オン)。
- GPS は既定で **削除**(設定 “Remove location (GPS) information”、既定 オン)。“Keep metadata” がオフなら GPS も出力されません。
- 情報パネルは、ファイルに実在する項目のみ表示し(カメラ/GPS セクションは該当データがある時のみ)、欠けた項目を作りません。編集済みの場合は「ディスク上のファイルの情報」である旨を表示します。
- ファイルサイズ・日付・ピクセル数は常に表示されます。

## 制限

- 編集は 8bit(16bit/浮動小数は 8bit に変換される)。
- 編集可能な最大ピクセル数は 150 メガピクセル。超えると編集は `tooLarge` エラーになり、閲覧はダウンサンプルしたプレビューで可能。
