# サーフェスの画像化

- `tools/dump-surface.ps1`（`--offline-dump` の `--dump-surface-list`。版による分岐はしない）:
  - 出力のファイル名は `<--dump-output-prefix><番号>.png`。プレフィックスを省くと `surface` になる。スクリプトは通常 `surface`、`-Backlog` では `backlog` を明示して渡す。
  - 無い番号は黙って飛ばされ、終了コードは 0 のまま。空のフォルダに出してから移し、`-Surface` の単純な番号と出たファイルを突き合わせて知らせる。範囲などの拡張形式は突き合わせない。
  - `--dump-shell` に無いシェルを渡すと、黙って既定のシェルになる。スクリプトが先に `shell/` のフォルダ名と descript.txt の `name` で確かめる。
  - `--dump-surface-list` の `surface10` の形は、2.8.97 では出力されなかった。スクリプトが番号だけにして渡す。
  - `--dump-scope` は、別のスコープの番号（スコープ 1 で 0 など）でもそのまま出力する。
  - 出力先を既定で一時フォルダにするのは、改変を禁じたシェル（CC BY-NC-ND など）の合成画像を、ゴーストのフォルダや nar、リポジトリに紛れ込ませないため。
  - `-Sheet` は System.Drawing で並べる。Windows PowerShell 5.1 と Windows の pwsh で動く。失敗しても個々の画像はあるので、注意を出すだけにする。
  - `.claude/settings.json` の許可リストに入れている（書き込むのは一時フォルダだけ）。
