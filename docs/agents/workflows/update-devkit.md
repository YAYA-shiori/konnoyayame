# 開発キットの更新

## 使うとき

作者が「開発キットを更新して」「キットを最新にして」「`.devkit-new` を片付けて」「別のゴーストにキットを入れて」と言ったとき。

**作者にはっきり頼まれたときだけ行う。自分から始めない。** GitHub からのダウンロードとキットのファイルの置き換えを伴う。

辞書、シェル、`GHOST.md`、`README.md` などゴーストのファイルは変わらない。どのファイルがキットのものかは `docs/agents/devkit-files.md` を参照。

## 手順

1. 確認だけを行う（GitHub からダウンロードすることを一言伝える。作者が版（タグ・ブランチ・コミット）を指定したときだけ `-Ref <版>` を付け、指定が無ければ最新リリースを使う）:
   `powershell -NoProfile -ExecutionPolicy Bypass -File tools/update-devkit.ps1 -DryRun`
   - 出力の各行: `create`（新しく作る）、`update`（新しい版に置き換える）、`seed`（無かったので作る）、`delete`（キットから外れたので消す）、`keep`（手元の変更を残す）、`skip`（作者が消したので作らない）、`CONFLICT`（手元と上流の両方が変わった）。
   - 何が変わるかを短くまとめて伝える。`CONFLICT` と `keep` は、どのファイルかも伝える。
2. 了承を得てから、`-DryRun` を外して実行する。最後に doctor の結果が表示される。
   - `tools/tools.json` が `update` になったとき、または doctor が tamac.exe の版の不足を知らせたときは、`powershell -NoProfile -ExecutionPolicy Bypass -File tools/setup.ps1` でツールを取り直す（ダウンロードを伴うことを一言伝える）。
3. 終了コードが 2 なら、`<ファイル>.devkit-new` が残っている。1 つずつ次のように片付ける。`AGENTS.md.devkit-new` があれば、それを最初に片付ける（手順書の索引が `AGENTS.md` にあるため）。
   1. 手元のファイルと `.devkit-new` の差分を読む（git があれば `git diff --no-index <ファイル> <ファイル>.devkit-new`）。
   2. 新しい版を土台に、手元で加えられていた変更を活かしたマージ案を作り、差分を見せる。
      - 手元の変更が、このゴーストだけの決まりなら `GHOST.md` に、Claude Code の個人設定なら `.claude/settings.local.json` に移すことを提案する。移せば、次からは衝突しなくなる。
      - 新しい版で、`AGENTS.md` の節が `docs/agents/` に移っていることがある。手元の変更がその節に対するものなら、移った先のファイルに当てる。
   3. 了承を得てから元のファイルに書き込み、`.devkit-new` を消す。
   4. すべて片付いたら、もう一度 `tools/update-devkit.ps1` を実行し、終了コードが 0 になることを確かめる。
4. `skip` や、キットから外れたのに残した `keep` のファイルがあれば、そのままでよいか確かめる。
   - `.claude/skills/` に `keep` で残ったものは、`docs/agents/workflows/` の手順書に置き換わった古い版のスキルに、作者が手を入れたもの。手を入れた内容を見せて、手順書や `GHOST.md` に移すか、消すかを作者に聞く。作者が自分で作ったスキルは、`update-devkit.ps1` も触らないので、そのままにする。
5. `GHOST.md` が `seed` で作られた（まだ書かれていない）なら、`docs/agents/workflows/setup.md` の手順 5 に沿って下書きする。
6. `powershell -NoProfile -ExecutionPolicy Bypass -File tools/check.ps1` を通す。
7. `AGENTS.md`、`CLAUDE.md`、hooks、MCP の変更は、エージェントを起動し直すと読み込まれることを伝える。git の作業コピーなら、変更をコミットするか聞く（勝手にコミットしない）。

## 別の YAYA ゴーストに導入する

キットが入っているゴースト（このフォルダ）から、導入先のフォルダを `-Target` で指定する。導入先には `ghost/master/descript.txt` と `ghost/master/yaya.dll` が要る。

`powershell -NoProfile -ExecutionPolicy Bypass -File tools/update-devkit.ps1 -Target <導入先のゴーストのフォルダ> -DryRun`

- 導入先にもともと同じ名前のファイル（`AGENTS.md`、`.editorconfig` など）があれば、上書きせずに `CONFLICT` になる。上と同じ手順でマージする。
- 導入した後は、導入先のフォルダでエージェントを起動し直し、`docs/agents/workflows/setup.md` の手順でセットアップと `GHOST.md` の下書きを行う。
