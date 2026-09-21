# nar とネットワーク更新ファイルの作成

## 使うとき

作者が「nar を作って」「配布用のファイルを作って」「配布用に固めて」「リリースしたい」「更新ファイルを作って」「ネットワーク更新の準備をして」と言ったとき。

**作者にはっきり頼まれたときだけ行う。自分から始めない。**

## 前提

- SSP 2.9.01 以降が要る。`tools/build-nar.ps1` は `ssp.exe --offline-tool` で作る。ゴーストは起動せず、SSP が動いていてもいなくても同じように作れる。
- SSP が古いと失敗する（終了コード 1）。SSP の更新を作者に勧める。
- GitHub Actions（`GITHUB_ACTIONS=true`）と `-Builtin` のときだけは、SSP を使わずにスクリプト自身が nar を作る（更新ファイルは作れない）。

## 手順

1. `powershell -NoProfile -ExecutionPolicy Bypass -File tools/check.ps1` を通す。error が残っているうちは作らない。
2. `tools/build-nar.ps1 -ListOnly` で入るファイルと除外されるファイルを表示し、個人データ、ローカル設定、ビルド生成物が混ざっていないか確かめる。
   - nar から除外するファイルは `.narignore`（`.gitignore` と同じ書き方）で指定する。ネットワーク更新からの除外は `.updateignore`（先頭の `include:.narignore` で共通部分を取り込んでいる）。どちらも SSP が読むファイルで、`-ListOnly` は `.narignore` を SSP と同じように解釈して表示する。
   - SSP はフォルダの中身をそのまま固める。git の作業コピーでも、追跡されていないファイルは入る。`-ListOnly` の最後に件数が出るので、入れたくないものがあれば `.narignore` に足すか、消すかを作者に確かめる。
   - `.narinclude`（ホワイトリスト形式）は SSP が読むが、`-ListOnly` では一覧を出せない。
3. 作る。
   - nar を頼まれたとき: `tools/build-nar.ps1` で、`build/<install.txt の directory>.nar` と、同じフォルダに `updates2.dau` と `updates.txt` を作る。
   - 更新ファイルだけを頼まれたとき: `tools/build-nar.ps1 -UpdateOnly` で、`build/updates2.dau` と `build/updates.txt` だけを作る。
   - 出力先は `-OutFile <nar のパス>` で変えられる（更新ファイルはその横に作る）。
4. 作者が望んだときだけ `-Install` を付けて SSP にインストールする。SSP 側の同じゴーストが上書きされるので、必ず先に確認を取る。
5. ネットワーク更新では、ゴーストのファイルと一緒に `updates2.dau` と `updates.txt` をサーバーのゴーストのルート（`On_homeurl` の URL）に置く。アップロードは作者に任せる（エージェントが行うときは、先に確認を取る）。

## 関連

- `.narignore` / `.updateignore` の書き方: `docs/agents/layout.md`
- 開発キットを配布物に含めるかどうか: `DEVKIT-GUIDE.md`
