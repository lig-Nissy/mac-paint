# MacPaint

macOS 向けのシンプルなホワイトボード / ペイントアプリ。Windows のペイントのような感覚で、ペン・図形・テキストを使って自由に描画できます。

SwiftUI + Swift Package Manager で構築されたネイティブアプリです。

## 主な機能

- **ペン**: フリーハンド描画（色・太さ調整可）。カーソルは鉛筆アイコン
- **消しゴム**: 実ピクセルを抜く真の消去（背景画像も透過）。太さに連動した円カーソル
- **図形**: 直線 / 四角 / 丸 / 三角 / 星 / 矢印（塗り / 枠線をトグル）
- **テキスト**: クリック位置に入力欄が表示、複数行対応
  - `Enter` で確定、`Shift + Enter` で改行
  - 確定後はドラッグで移動、ダブルクリックで再編集
  - 日本語入力（IME）対応
- **色選択**: ColorPicker から自由に指定
- **太さ / フォントサイズ**: スライダー（テキスト時はフォントサイズに自動切替）
- **Undo / Redo**: ストローク単位で巻き戻し（`Cmd+Z` / `Ctrl+Z` 両対応）
- **クリア**: 全ストローク削除
- **ファイル**:
  - PNG・JPEG 読み込み（背景として展開、画像サイズに合わせてウィンドウを自動リサイズ）
  - PNG 保存（プレビューシートで仕上がり・ピクセルサイズを確認してから書き出し）
- **アプリアイコン**: コード生成（画像ファイル不要）

## 動作環境

- macOS 13.0 (Ventura) 以上
- Apple Silicon / Intel 両対応
- Swift 5.9 以上

## クイックスタート

### 開発実行

```bash
swift run
```

ホットリロードはありませんが、ビルド〜起動が数秒で完了します。

### .app バンドルとしてビルド

Dock やランチャーから普通の Mac アプリとして起動したい場合:

```bash
bash scripts/build-app.sh
open build/MacPaint.app
```

`build/MacPaint.app` を `/Applications` にドラッグすればインストール完了です。

## ショートカット

| 操作 | キー |
|------|------|
| 元に戻す | `Cmd + Z` / `Ctrl + Z` |
| やり直し | `Cmd + Shift + Z` / `Ctrl + Shift + Z` |
| 新規 | `Cmd + N` |
| 開く | `Cmd + O` |
| 保存（プレビュー表示） | `Cmd + S` |
| 保存プレビュー: 確定 | `Enter` |
| 保存プレビュー: 取消 | `Esc` |
| テキスト確定 | `Enter` |
| テキスト改行 | `Shift + Enter` |

## 保存フロー

1. ツールバーの「保存」または `Cmd + S` でプレビューシートが開く
2. 仕上がりイメージと出力ピクセルサイズを確認
3. 「保存…」で `NSSavePanel` が開き、PNG として書き出し
4. 「キャンセル」または `Esc` で中断

プレビュー画像は表示中の SwiftUI ビューを `ImageRenderer` でラスタライズして生成しています。背景画像がある場合は、元画像のピクセル密度に合わせた高解像度で出力されます。

## プロジェクト構成

```
mac-paint/
├── Package.swift            Swift Package Manager 設定
├── Sources/MacPaint/
│   ├── MacPaintApp.swift    エントリポイント / メニュー / アプリアイコン生成
│   ├── CanvasModel.swift    状態管理 / 描画ロジック / PNG 出力
│   └── ContentView.swift    UI / 入力ハンドリング / ツールバー
├── scripts/
│   └── build-app.sh         .app バンドル生成スクリプト
├── docs/                    アーキテクチャ図（Mermaid）
└── build/                   生成された .app バンドルの出力先
```

## アーキテクチャ概要

- **データドリブン描画**: 描いたものは `Stroke` 構造体（種別 / 色 / 太さ / 点列 / 塗り / テキスト）の配列としてモデルに保持し、毎フレーム再描画する宣言的方式
- **画面描画**: SwiftUI の `Canvas` + `Path` + `GraphicsContext`
- **PNG 出力**: 表示中の `CanvasSnapshotView` を `ImageRenderer` でラスタライズ（WYSIWYG）。背景画像があれば元画像のピクセル密度に合わせて `renderer.scale` を調整
- **保存プレビュー**: `NSImage` を `sheet` 表示し、ユーザー確認後に `NSSavePanel` を開く（多重表示はガード）
- **消しゴム**: `blendMode = .destinationOut`（保存時は `CGBlendMode.clear`）で実ピクセルを抜く
- **テキスト入力**: `NSTextView` を `NSViewRepresentable` でラップし、IME / 改行 / 移動に対応
- **カーソル**: `NSTrackingArea` + 透明 `NSCursor` で標準カーソルを抑止
  - ペン時: SF Symbol `pencil` を SwiftUI で重ね描画
  - 消しゴム時: 太さ連動の円カーソルを SwiftUI で重ね描画
- **Ctrl+Z 対応**: `NSEvent.addLocalMonitorForEvents(.keyDown)` でグローバルに Ctrl+Z / Ctrl+Shift+Z を捕捉し undo/redo に渡す（テキスト編集中は `NSTextView` 標準 Undo に譲る）
- **アクティブ化**: `AppDelegate` で `setActivationPolicy(.regular)` + `activate(ignoringOtherApps:)` を呼び、`swift run` 起動時もメニューバーが正しく有効化される
- **画像読み込み**: 背景画像取得時に元画像のアスペクト比を保ったまま、画面に収まる最大サイズにウィンドウを自動リサイズ
- **アプリアイコン**: `CGContext` で起動時に動的生成し `NSApplication.applicationIconImage` に設定
- **配布**: `swift build -c release` → `.app` バンドル化（`Info.plist` + `.icns` + ad-hoc 署名）
- **アイコン .icns**: 実行ファイル自身を `--export-iconset` 引数で起動して PNG 群を吐かせ `iconutil` で変換

詳しくは `docs/architecture.mmd`、`docs/dataflow.mmd`、`docs/save-flow.mmd`（Mermaid 図）を参照してください。

## 使用技術

### 言語・ビルド
- Swift 5.9+
- Swift Package Manager（Xcode 不使用）

### UI フレームワーク
- **SwiftUI**: App / Scene / View、`Canvas`、`Path`、`GraphicsContext`、`DragGesture`、`onContinuousHover`、`ImageRenderer`、`sheet`、`@NSApplicationDelegateAdaptor`
- **AppKit**: `NSApplication` / `AppDelegate`、`NSImage`、`NSBitmapImageRep`、`NSCursor`、`NSTrackingArea`、`NSOpenPanel` / `NSSavePanel`、`NSTextView`、`NSViewRepresentable`、`NSEvent.addLocalMonitorForEvents`

### 描画・画像処理
- **Core Graphics**: `CGContext`、`CGPath`、`CGBlendMode`
- **Core Text**: `CTLineCreateWithAttributedString`、`CTLineDraw`
- **UniformTypeIdentifiers**: PNG / JPEG タイプ判定

### 配布・パッケージング
- Bash スクリプト
- `iconutil`（PNG群 → `.icns` 変換）
- `codesign`（ad-hoc 署名）
- `Info.plist`

## ライセンス

このプロジェクトはサンプル実装です。自由に改変・利用してください。
