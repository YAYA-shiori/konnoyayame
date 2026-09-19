# ゴーストの一括チェック

## 使うとき

作者が「チェックして」「エラーが出ていないか見て」「おかしくない？」「辞書のエラーを直して」「lint かけて」「コミットする前に確認して」と言ったとき。辞書やシェルをまとめて変更した後、コミットや nar 作成の前にも、自分から行ってよい。

## 手順

1. `powershell -NoProfile -ExecutionPolicy Bypass -File tools/check.ps1` を実行する。
   - `skipped (tool not available)` と出た項目は、ツールが入っていないか SSP が見つからない。`tools/setup.ps1` はダウンロードを伴うので、作者に一言断ってから実行する。SSP の場所は `tools/local.json` か環境変数 `SSP_PATH` で指定してもらう。
2. 結果は次の優先順で扱う。
   1. **check-dic の error**: 辞書が読み込めず、ゴーストが緊急モードで起動してしまう。最優先で直す。
   2. **check-shell の Error / Warning**: 直す。`[SERIKO] shell/master/surfaces.txt:Line=123:Surface=10 ...` のように定義位置が出るので、そのファイルと行を直す。二重定義のエラーには、先に定義された側の位置も ` (ファイル名:Line=n)` として付く。位置が出ない（位置の無い種類の Notice）ときは、`Surface=` の番号から探す。Notice（使われていないサーフェスなど）は報告だけにする。シェルの画像そのものは、`GHOST.md` でライセンスを確かめるまで編集しない（改変を禁じているシェルがある。編集の手順は `docs/agents/workflows/edit-shell-image.md`）。`surfaces.txt` の重ね合わせ（`element` など）を直したときは、チェックが通っても位置のずれやパーツの抜けは見つからないので、画像を読めるなら `tools/dump-surface.ps1 -Surface <番号>` で仕上がりを見る。当たり判定（`collision` など）を直したときは `-Collision` を付けて、枠の位置と名前を見る。
   3. **lint の `read undefined variable` / `read undefined local variable`**: 打ち間違い（`did you mean:` に候補が出る）や、ブロック `{ }` の中で作ったローカル変数をブロックの外で読んでいる可能性が高い。前後を読んで確かめてから直す。`assignment in condition` は `==` の書き間違いのことが多いので確かめる。`unused function / variable / local variable` は報告だけにして、勝手に消さない。
      - 文字列の中で組み立てた名前（`EVAL('Mouse' + _part)` など）で呼ばれる関数は、未使用に見える。そういう関数は、辞書に `OnSHIORI3FW.Lint.UsedFunctions` という関数を書き、名前の正規表現の配列を返すと報告されなくなる（グローバル変数は `OnSHIORI3FW.Lint.UsedVariables`）。例: `OnSHIORI3FW.Lint.UsedFunctions { (IARRAY, '^Mouse', '^TalkTo') }`。作者に確かめてから足す。
      - `lint: SKIPPED` のときは、yaya.dll かシステム辞書が古い。更新するかは作者に確かめる（`docs/agents/workflows/update-yaya.md`）。
3. 直したら 1 をもう一度実行し、error がなくなるまで繰り返す。
   - 辞書の関数を直したときは、`powershell -NoProfile -ExecutionPolicy Bypass -File tools/shiori.ps1 -Eval '関数名'` でも呼び出す。存在しない関数の呼び出し（E0071）のような実行時のエラーは、1 のチェックでは見つからない。終了コード 2 なら、表示された位置を直す。ファイルの書き込みや外部プログラムの実行をする関数は本当に動くので、中身を読んでから呼ぶ。
4. SSP でこのゴーストを動かしている場合は、`powershell -NoProfile -ExecutionPolicy Bypass -File tools/ssp-log.ps1` で実行時のエラーログも見る（終了コード 3 なら SSP が起動していないので飛ばす）。古いエラーも残っているので、直したものは `tools/sstp.ps1 -Reload ghost` で読み込ませ、新しいエラーが出ないことを確かめる。
5. 最後に、直したことと残っている警告を短くまとめて報告する。

## 関連

- コマンドと終了コードの一覧: `docs/agents/commands.md`
- 実機で確かめる: `docs/agents/workflows/try-in-ssp.md`
