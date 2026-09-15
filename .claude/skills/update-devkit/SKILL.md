---
name: update-devkit
description: 開発キット（AGENTS.md、CLAUDE.md、.claude/、tools/ など）だけを新しい版に更新する。作者が手を入れたファイルは壊さず、衝突したファイルのマージを手伝う。別の YAYA ゴーストにキットを導入するときにも使う。
disable-model-invocation: true
argument-hint: "[版（タグ・ブランチ・コミット。省略すると最新リリース）]"
---

# 開発キットの更新

辞書、シェル、`GHOST.md`、`README.md` などゴーストのファイルは変わらない。どのファイルがキットのものかは `AGENTS.md` の「開発キットとファイルの持ち主」を参照。

1. 確認だけを行う（GitHub からダウンロードすることを一言伝える。版の指定があれば `-Ref <版>` を付ける）:
   `powershell -NoProfile -ExecutionPolicy Bypass -File tools/update-devkit.ps1 -DryRun`
   - 出力の各行: `create`（新しく作る）、`update`（新しい版に置き換える）、`seed`（無かったので作る）、`delete`（キットから外れたので消す）、`keep`（手元の変更を残す）、`skip`（作者が消したので作らない）、`CONFLICT`（手元と上流の両方が変わった）。
   - 何が変わるかを短くまとめて伝える。`CONFLICT` と `keep` は、どのファイルかも伝える。
2. 了承を得てから、`-DryRun` を外して実行する。最後に doctor の結果が表示される。
   - `tools/tools.json` が `update` になったとき、または doctor が tamac.exe の版の不足を知らせたときは、`powershell -NoProfile -ExecutionPolicy Bypass -File tools/setup.ps1` でツールを取り直す（ダウンロードを伴うことを一言伝える）。
3. 終了コードが 2 なら、`<ファイル>.devkit-new` が残っている。1 つずつ次のように片付ける。
   1. 手元のファイルと `.devkit-new` の差分を読む（git があれば `git diff --no-index <ファイル> <ファイル>.devkit-new`）。
   2. 新しい版を土台に、手元で加えられていた変更を活かしたマージ案を作り、差分を見せる。
      - 手元の変更が、このゴーストだけの決まりなら `GHOST.md` に、Claude Code の個人設定なら `.claude/settings.local.json` に移すことを提案する。移せば、次からは衝突しなくなる。
   3. 了承を得てから元のファイルに書き込み、`.devkit-new` を消す。
   4. すべて片付いたら、もう一度 `tools/update-devkit.ps1` を実行し、終了コードが 0 になることを確かめる。
4. `skip` や、キットから外れたのに残した `keep` のファイルがあれば、そのままでよいか確かめる。
5. `GHOST.md` が `seed` で作られた（まだ書かれていない）なら、`/getting-started` の手順 5 に沿って下書きする。
6. `powershell -NoProfile -ExecutionPolicy Bypass -File tools/check.ps1` を通す。
7. hooks、スキル、MCP の変更は、Claude Code を起動し直すと有効になることを伝える。git の作業コピーなら、変更をコミットするか聞く（勝手にコミットしない）。

## 別の YAYA ゴーストに導入する

キットが入っているゴースト（このフォルダ）から、導入先のフォルダを `-Target` で指定する。導入先には `ghost/master/descript.txt` と `ghost/master/yaya.dll` が要る。

`powershell -NoProfile -ExecutionPolicy Bypass -File tools/update-devkit.ps1 -Target <導入先のゴーストのフォルダ> -DryRun`

- 導入先にもともと同じ名前のファイル（`AGENTS.md`、`.editorconfig` など）があれば、上書きせずに `CONFLICT` になる。上と同じ手順でマージする。
- 導入した後は、導入先のフォルダで Claude Code を起動し直し、`/getting-started` でセットアップと `GHOST.md` の下書きを行う。

$ARGUMENTS
