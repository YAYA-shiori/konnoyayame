# .narignore と .updateignore

- `.narignore` / `.updateignore`（SSP の `sp_gitignorefilter.cpp` の挙動）: `tools/lib/ignore.ps1` をこれにそろえている。
  - ルートに置いたものだけを読む。
  - 行頭が `include:相対パス` の行はディレクティブとして扱う。
  - パスは、その行が書かれたファイルのフォルダを基準に解決する（ルート固定ではない）。
  - 取り込んだ先でも `include:` を書ける。最初のファイルが深さ 0 で、深さ 3 を超えると読まれない（`SP_GITIGNORE_FILTER_MAX_INCLUDE_DEPTH`）。
  - 区切りは `/` でも `\` でもよい。
  - 今の構成は `.updateignore` → `.narignore` → `tools/devkit.narignore` の深さ 2。キット側でこれ以上 `include:` を重ねるときは、上限に注意する。
