# サーフェスの画像化

- `tools/dump-surface.ps1`（`--offline-dump` の `--dump-surface-list`。版による分岐はしない）:
  - 出力のファイル名は `<--dump-output-prefix><番号>.png`。プレフィックスを省くと `surface` になる。スクリプトは通常 `surface`、`-Backlog` では `backlog` を明示して渡す。
  - 無い番号は黙って飛ばされ、終了コードは 0 のまま。空のフォルダに出してから移し、`-Surface` の単純な番号と出たファイルを突き合わせて知らせる。範囲などの拡張形式は突き合わせない。
  - `--dump-shell` に無いシェルを渡すと、黙って既定のシェルになる。スクリプトが先に `shell/` のフォルダ名と descript.txt の `name` で確かめる。
  - `--dump-surface-list` の `surface10` の形は、2.8.97 では出力されなかった。スクリプトが番号だけにして渡す。
  - `-Collision` は `--dump-surface-option collision`（当たり判定の形と名前を描き込む。2.8.98 の 2026-09-19 のビルドで確認）。`--dump-surface-option` は最後の 1 つだけが効くので、`-Backlog` と合わせるときは `backlog,collision` とカンマでつないで 1 つで渡す。
  - `--dump-scope` は、別のスコープの番号（スコープ 1 で 0 など）でもそのまま出力する。
  - 出力先を既定で一時フォルダにするのは、改変を禁じたシェル（CC BY-NC-ND など）の合成画像を、ゴーストのフォルダや nar、リポジトリに紛れ込ませないため。
  - `-Sheet` は System.Drawing で並べる。Windows PowerShell 5.1 と Windows の pwsh で動く。失敗しても個々の画像はあるので、注意を出すだけにする。
  - `.claude/settings.json` の許可リストに入れている（書き込むのは一時フォルダだけ）。
- `-Compare`（別の版との画素単位の比較）:
  - 相手がフォルダならそのまま `--offline-dump` に渡す。そうでなければ git のリビジョンとみなし、`git archive --format=zip <rev>:<prefix> -- shell ghost/master/descript.txt` を一時フォルダに展開して渡す（`<prefix>` は `rev-parse --show-prefix`。ゴーストがリポジトリのサブフォルダにあっても、そのフォルダの木を取り出す）。`git checkout` や `--work-tree` は index や作業ツリーに触れるので使わない。`descript.txt` がその版に無いときは `shell` だけを取り出す。`--offline-dump` は、この 2 つだけのフォルダでも合成できる（SSP 2.9.04 で確認）。
  - 両方を同じ引数（`-Backlog`、`-Collision`、`-Shell`、`-Scope`）で書き出し、比べるのは画像エンジン（`tools/lib/image.cs` の `Commands.Compare`）。エンジンの読み込みは `tools/lib/image-engine.ps1` にまとめ、`tools/image.ps1` と共用している。
  - 相手側のエラーログは表示しない（昔の版の警告を今の問題と取り違えないため）。
  - 違いがあっても終了コードは変えない（違いは確かめるための情報で、失敗ではない）。比べられなかったとき（git が無い、リビジョンが無い、`git archive` の失敗）は 1。
  - 違いの図は、変わった範囲に 8 ピクセルの余白を付けて切り出し、`View.Render` の自動の倍率（最大 16 倍）で拡大する。1 ドットの違いも見えるようにするため。
