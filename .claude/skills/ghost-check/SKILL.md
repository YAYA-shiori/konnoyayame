---
name: ghost-check
description: ゴーストの辞書（tamac）、シェル（SSP offline-dump）、静的解析（yayalint）をまとめて実行し、見つかった問題を直す。辞書やシェルをまとめて変更した後や、コミット・nar 作成の前に使う。
---

# ゴーストの一括チェック

1. `powershell -NoProfile -ExecutionPolicy Bypass -File tools/check.ps1` を実行する。
   - `skipped (tool not available)` と出た項目は、ツールが入っていないか SSP が見つからない。`tools/setup.ps1` はダウンロードを伴うので、ユーザーに一言断ってから実行する。SSP の場所は `tools/local.json` か環境変数 `SSP_PATH` で指定してもらう。
2. 結果は次の優先順で扱う。
   1. **check-dic の error**: 辞書が読み込めず、ゴーストが緊急モードで起動してしまう。最優先で直す。
   2. **check-shell の Error / Warning**: 直す。Notice（使われていないサーフェスなど）は報告だけにする。`shell/master/` の画像は CC BY-NC-ND なので、画像そのものは編集しない。
   3. **lint の `read undefined variable / function`**: 打ち間違いの可能性が高い。前後を読んで確かめてから直す。`unused function / variable` は報告だけにして、勝手に消さない。
3. 直したら 1 をもう一度実行し、error がなくなるまで繰り返す。
4. 最後に、直したことと残っている警告を短くまとめて報告する。
