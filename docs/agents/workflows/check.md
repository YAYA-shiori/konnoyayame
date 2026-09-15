# ゴーストの一括チェック

## 使うとき

作者が「チェックして」「エラーが出ていないか見て」「おかしくない？」「辞書のエラーを直して」「lint かけて」「コミットする前に確認して」と言ったとき。辞書やシェルをまとめて変更した後、コミットや nar 作成の前にも、自分から行ってよい。

## 手順

1. `powershell -NoProfile -ExecutionPolicy Bypass -File tools/check.ps1` を実行する。
   - `skipped (tool not available)` と出た項目は、ツールが入っていないか SSP が見つからない。`tools/setup.ps1` はダウンロードを伴うので、作者に一言断ってから実行する。SSP の場所は `tools/local.json` か環境変数 `SSP_PATH` で指定してもらう。
2. 結果は次の優先順で扱う。
   1. **check-dic の error**: 辞書が読み込めず、ゴーストが緊急モードで起動してしまう。最優先で直す。
   2. **check-shell の Error / Warning**: 直す。SSP 2.8.94 以降では `[SERIKO] shell/master/surfaces.txt:Line=123:Surface=10 ...` のように定義位置が出るので、そのファイルと行を直す。二重定義のエラーには、先に定義された側の位置も ` (ファイル名:Line=n)` として付く。位置が出ない（古い SSP か、位置の無い種類の Notice）ときは、`Surface=` の番号から探す。Notice（使われていないサーフェスなど）は報告だけにする。シェルの画像そのものは、`GHOST.md` でライセンスを確かめるまで編集しない（改変を禁じているシェルがある）。
   3. **lint の `read undefined variable / function`**: 打ち間違いの可能性が高い。前後を読んで確かめてから直す。`unused function / variable` は報告だけにして、勝手に消さない。
3. 直したら 1 をもう一度実行し、error がなくなるまで繰り返す。
   - 辞書の関数を直したときは、`powershell -NoProfile -ExecutionPolicy Bypass -File tools/shiori.ps1 -Eval '関数名'` でも呼び出す。存在しない関数の呼び出し（E0071）のような実行時のエラーは、1 のチェックでは見つからない。終了コード 2 なら、表示された位置を直す。ファイルの書き込みや外部プログラムの実行をする関数は本当に動くので、中身を読んでから呼ぶ。
4. SSP でこのゴーストを動かしている場合は、`powershell -NoProfile -ExecutionPolicy Bypass -File tools/ssp-log.ps1` で実行時のエラーログも見る（終了コード 3 なら SSP が起動していないので飛ばす）。古いエラーも残っているので、直したものは `tools/sstp.ps1 -Reload ghost` で読み込ませ、新しいエラーが出ないことを確かめる。
5. 最後に、直したことと残っている警告を短くまとめて報告する。

## 関連

- コマンドと終了コードの一覧: `docs/agents/commands.md`
- 実機で確かめる: `docs/agents/workflows/try-in-ssp.md`
