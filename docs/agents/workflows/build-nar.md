# nar の作成

## 使うとき

作者が「nar を作って」「配布用のファイルを作って」「配布用に固めて」「リリースしたい」と言ったとき。

**作者にはっきり頼まれたときだけ行う。自分から始めない。**

## 手順

1. `powershell -NoProfile -ExecutionPolicy Bypass -File tools/check.ps1` を通す。error が残っているうちは作らない。
2. `tools/build-nar.ps1 -ListOnly` で入るファイルと除外されるファイルを表示し、個人データ、ローカル設定、ビルド生成物が混ざっていないか確かめる。
   - nar から除外するファイルは `.narignore`（`.gitignore` と同じ書き方）で指定する。ネットワーク更新からの除外は `.updateignore`（先頭の `include:.narignore` で共通部分を取り込んでいる）。どちらも SSP の nar・更新ファイル作成機能と同じファイル。
   - `.narinclude`（ホワイトリスト形式）は `tools/build-nar.ps1` が対応していないので使わない。
   - git の作業コピーでは、追跡されていないファイルは入らない。新しく作ったファイルを入れたいときは `git add` が必要なことを作者に伝える。
3. `tools/build-nar.ps1` で `build/<install.txt の directory>.nar` を作る。
4. 作者が望んだときだけ `-Install` を付けて SSP にインストールする。SSP 側の同じゴーストが上書きされるので、必ず先に確認を取る。

## 関連

- `.narignore` / `.updateignore` の書き方: `docs/agents/layout.md`
- 開発キットを配布物に含めるかどうか: `DEVKIT-GUIDE.md`
