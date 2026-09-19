# DEVKIT-MAINTAINING.md

AI 開発キットそのもの（`AGENTS.md`、`CLAUDE.md`、`DEVKIT-GUIDE.md`、`docs/agents/`、`.claude/`、`tools/` など）を作る・直すときの注意です。

このファイルと、スクリプトごとの実装メモを置いた `docs/devkit-maintaining/` は、キットの配布元である konnoyayame のリポジトリにだけあります。nar、ネットワーク更新、キットの配布物のどれにも入りません（ルートの `.narignore` の `/DEVKIT-MAINTAINING.md` と `/docs/devkit-maintaining/`。`tools/devkit.json` の `files` にも載せない）。ゴーストを作るときの指示は `AGENTS.md` と `docs/agents/`、作者向けのキットの使い方と、別のゴーストへのキットの導入手順は `DEVKIT-GUIDE.md`、konnoyayame に固有の情報は `GHOST.md`、konnoyayame の紹介は `README.md` にあります。

## キットの範囲

`tools/devkit.json` で決める。

- `source`: 配布元のリポジトリ。`tools/update-devkit.ps1` はここから取得する。
- `files` / `exclude`: キットが持つファイル（`.gitignore` と同じ glob。`tools/lib/ignore.ps1` の変換を使う）。更新で置き換わる。
- `seed`: 無いときだけ作るファイル。キーが作る先、値が元のファイル。元のファイルは `tools/devkit/seed/` に、先頭のドットを外した名前で置く（`.editorconfig` や `.gitattributes` はサブフォルダに置いてもエディタや git に読まれてしまうため。`.narignore` / `.updateignore` は SSP がルートのものしか読まないので害はないが、名前をそろえている）。

それ以外（辞書、シェル、`GHOST.md`、`README.md`、`.gitignore`、`.github/workflows/auto_release.yml` など）はゴーストのもので、キットは触らない。

範囲を決めるときの注意:

- キットのファイルと seed の元ファイルは、YAYA のゴーストならどれにでも入る。**ややめ、マック朗、サーフェス番号、konnoyayame の URL など、特定のゴーストに固有のことを書かない。** 固有のことは各ゴーストの `GHOST.md` に書く（konnoyayame 自身の分はルートの `GHOST.md`）。ただし、キットの配布元（`source`）としての konnoyayame のリポジトリの URL は、`DEVKIT-GUIDE.md` の導入手順に書いてよい。`source` を変えたら、そこも直す。
- ゴーストのファイルに行を足さないと動かない仕組みにしない。今は次のようにしている。
  - nar の除外: `tools/devkit.narignore`（`.narignore` から `include:`）
  - git の除外: `tools/.gitignore` と `.claude/.gitignore`
  - `build/`: `tools/build-nar.ps1` が作る `build/.gitignore`
- `auto_release.yml` は既存のリリースとタグをすべて消すので、キットにも seed にも入れない。
- ルートに新しいファイルを足すときは、`files` か `seed` に載せる。載せないと配布されない。glob はパス全体にフル一致するので、フォルダは `docs/agents/**` の形で書く。
- ルートに新しいフォルダを足すときは、`tools/lib/devkit.ps1` の `Get-DevkitConflictFiles` が走査するフォルダにも足す。足さないと、そのフォルダの `.devkit-new` が `update-devkit.ps1` の終了コード 2 にも doctor の `devkit-conflicts` にも出ず、作者が気づけない。
- 作者向けの説明は、キットに入る `DEVKIT-GUIDE.md`（キットの使い方と、別のゴーストへの導入手順）と、konnoyayame の `README.md`（ゴーストの紹介、手で改造するときの案内）に分けている。`DEVKIT-GUIDE.md` はどのゴーストにも入るので、上と同じく特定のゴーストに固有のことを書かない。`README.md` には、キットについては `DEVKIT-GUIDE.md` への案内だけを書く。導入手順を `DEVKIT-GUIDE.md` に置くのは、キットの説明を 1 か所にまとめ、キットを入れたゴーストからも別のゴーストに導入できるようにするため。
- キットの使い方が変わったら、`AGENTS.md` と `DEVKIT-GUIDE.md` の両方を直す。
- エージェント向けの文書は `AGENTS.md` と `docs/agents/` に分けている。
  - `AGENTS.md` には、どの作業でも効くもの（作業のルール、YAYA 辞書とトークの書き方の要点、仕様の調べ方、ガイドライン）と、「こう頼まれたら」「資料」の 2 つの索引を置く。辞書とトークの要点を残すのは、`AGENTS.md` しか読まないエージェントが書いても、よくある失敗を避けられるようにするため。
  - 調べるときにだけ要る資料（コマンド表、ディレクトリ構成など）と、特定の作業の手順書は `docs/agents/` に置き、索引に行を足す。資料の索引には、`AGENTS.md` にあったときの節名を書く（`GHOST.md` や派生ゴーストの `README.md` が「`AGENTS.md` の『テンプレートから独立させるとき』」のように節名で参照しているため）。
- `docs/agents/workflows/` に手順書を足したら、`AGENTS.md` の「こう頼まれたら」の表にも行を足す。作者の言い回しは、その文書の「使うとき」とそろえる。スラッシュコマンドは使わない前提で書く（想定している作者は、コーディングエージェントに不慣れで、自然な言葉で頼む）。
- 手順書のパスは `tools/doctor.ps1` の `fix` と `tools/hooks/session-start.ps1` の出力にも書かれている。パスを変えるときは両方直す。

## lock ファイル

`tools/devkit.lock.json` は、キットのファイルごとに「導入した版の上流の内容」の SHA256 を記録する（CRLF を LF にそろえて計算）。`tools/update-devkit.ps1` は、lock（B）、手元（L）、新しい版（N）を比べて、作者の変更を見分ける。

| 状態 | 動作 | lock |
|---|---|---|
| L が無く、B も無い | 作る | N |
| L が無く、B はある（作者が消した） | 作らない | B のまま |
| L = N | 何もしない | N |
| L = B（作者は変えていない） | N で上書きする | N |
| B = N（上流は変わっていない） | 手元を残す | N |
| それ以外（両方変わった、または基準が無い） | `<path>.devkit-new` を書く | N |
| 新しい版に無く、L = B | 消す | 載せない |
| 新しい版に無く、L ≠ B | 残して知らせる | 載せない |

- 衝突したファイルの lock を N にしておくので、作者がマージして `.devkit-new` を消した後の実行は「上流は変わっていない」に当たり、そのまま受け入れられる。
- **このリポジトリでキットのファイルを変えたら、コミットの前に `powershell -NoProfile -ExecutionPolicy Bypass -File tools/update-devkit.ps1 -WriteLock` を実行する。** 忘れると GitHub Actions の auto check（`-VerifyLock`）が落ちる。
- konnoyayame から作ったゴーストは、この lock を引き継ぐ。lock が古いと、作者が変えていないファイルまで衝突として扱われる。
- `-VerifyLock` は、GitHub Actions では `source` のリポジトリでだけ動く。派生ゴーストで、作者の変更によって落ちないようにするため。
- 派生ゴーストで `-WriteLock` を使うと、作者の変更が「上流の内容」として記録され、次の更新で上書きされてしまう。作者向けの説明（`DEVKIT-GUIDE.md`、`README.md`）には書かない。

## 配布

- `tools/update-devkit.ps1` は、既定で `source` の最新リリースのタグを GitHub API でコミット SHA に解決し、`https://github.com/<source>/archive/<sha>.zip` からキットを取り出す。auto check が通って auto release が作られた時点で、キットも配布されることになる。
- auto release は push のたびに古いリリースとタグを消す。lock には SHA を記録するので、古い版のアーカイブも取れる。
- `-Ref` でタグ・ブランチ・コミットを、`-Source` でローカルのフォルダや zip を指定できる。別のゴーストへの導入は `-Target`。

## `tools/*.ps1` の書き方

- Windows PowerShell 5.1 と PowerShell 7 の両方で動かす。`??`、`?.`、三項演算子、パイプラインの `&&` など、7 だけの構文は使わない。GitHub Actions では pwsh（Windows と Ubuntu）でも動く。
- **ASCII 文字だけで書く**（BOM のないファイルに日本語を書くと、5.1 で文字化けする）。
- 冒頭で `. (Join-Path $PSScriptRoot 'lib/common.ps1')` を読み、`Initialize-DevkitConsole` を呼ぶ。パスは `$DevkitRoot` から組み立て、`ghost/master` と `shell/master` を前提にしてよい。
- システム辞書は `ghost/master/dic/system` と決め打ちしない。`ghost/master/system` に置くゴーストもあるので、`tools/lib/common.ps1` の `$DevkitSystemDicDirs`（探す順）、`Get-DevkitSystemDicDir`、`Test-DevkitSystemDicPath` を使う。
- 終了コードをそろえる: 0 OK / 1 失敗・エラー / 2 注意が要る（SSP のエラーログの Error、`.devkit-new` の残りなど）/ 3 ツールや SSP が無くて確かめられない。
- 冒頭のコメントヘルプ（`.SYNOPSIS`、`.DESCRIPTION`、終了コード、`.EXAMPLE`）を書き、`docs/agents/commands.md` のコマンド表も直す。
- ダウンロードして使うツールは `tools/tools.json` に書く。書き方は 2 通りある。
  - 版を固定する（今は使っているツールが無い。以前は yayalint）: `version`、`url`、`sha256` を書く。上げるときは 3 つとも書き換え（SHA256 は `Get-FileHash -Algorithm SHA256`）、`tools/setup.ps1 -Tool <名前>` で取り直せることを確かめる（取得済みの exe の SHA256 が違えば取り直す）。
  - 最新リリースを使う（tamac。YAYA のプロジェクトが出しているツールで、新しい機能をキットの更新を待たずに使えるようにするため）: `version` を `latest` にし、`repository`、`asset`（リリースのファイル名）、`minimumVersion` を書く。1 つの exe のツールだけに使う（zip では、取得済みのものが最新か見分けられない）。
    - `tools/setup.ps1` は GitHub API で最新リリースを調べ、GitHub が各ファイルに付けている SHA256（`digest`）で照合する。`digest` が無ければ失敗させる。GitHub Actions では、匿名の API 呼び出しの回数制限を避けるため、`auto_check.yml` から `GITHUB_TOKEN` を渡している（`Get-DevkitLatestReleaseAsset` は、トークンが拒否されたら付けずにやり直す）。
    - `doctor.ps1` と `tools/shiori.ps1` はネットワークに出ずに、exe のファイルバージョンが `minimumVersion` 以上かを見る（`Test-DevkitToolCurrent`）。キットのスクリプトが新しいオプションを使い始めたら `minimumVersion` を上げる。
    - 新しいリリースで挙動が変わると、すべてのゴーストの auto check に影響する。tamac のリリースの前に、このリポジトリで `tools/check.ps1` と `tools/shiori.ps1` を試す。

## 実装メモ

スクリプトが頼っている外部のプログラムの挙動と、そう実装した理由は、話題ごとに `docs/devkit-maintaining/` に書いている。そのスクリプトを変えるときに読む。新しい話題はファイルを足し、この表に行を足す。

| ファイル | 中身 |
|---|---|
| `ssp.md` | SSTP（Owned SSTP）、SSP のログ、SSP の版の扱い、使っている機能（`GetStatus`、`Option: strict`、`--dump-error-log`）、試験用 SSP（`tools/run-ssp.ps1`） |
| `dump-surface.md` | `tools/dump-surface.ps1` と `--offline-dump` の `--dump-surface-list` |
| `tamac.md` | tamac.exe の `-r` と `tools/shiori.ps1` |
| `update-yaya.md` | `tools/update-yaya.ps1` のシステム辞書（yaya-dic）の取得と置き換え |
| `ignore.md` | `.narignore` / `.updateignore` の解釈（`tools/lib/ignore.ps1`） |

どのスクリプトにも関わる短いものは、ここに書く。

- hooks: `.claude/settings.json` に書いている。
  - SessionStart: `tools/hooks/session-start.ps1` が、doctor の recommended 以上の不足と直し方を Claude に伝える。
  - PostToolUse: `tools/hooks/post-edit.ps1` が、`ghost/` と `shell/` の編集後にチェックを走らせる。
  - hook のコマンドは `${CLAUDE_PROJECT_DIR}` を使い、ゴーストのフォルダ名に依存させない。
- doctor に項目を足すときは `Add-DoctorItem` を使う。`level` が recommended 以上なら、起動時に Claude Code へ伝わる。

## キットを変えたときの確認

1. `tools/check.ps1` が通り、`tools/update-devkit.ps1 -WriteLock` の後で `-VerifyLock` が 0 になる。
2. 更新のシナリオ: 一時フォルダにこのリポジトリを 2 つコピーし、片方を「新しい版」として手を加え、もう片方に `-Source` で当てる。
   - 手を付けていないファイルは置き換わる
   - 作者だけが変えたファイルは残る
   - 両方が変えたファイルは `.devkit-new` が書かれ、終了コードが 2 になる
   - マージして `.devkit-new` を消して再実行すると 0 になる
   - キットから外したファイルは消える。作者が手を入れていたものは `keep` で残る
   - `GHOST.md` とルートの `.gitignore` は変わらない
   - `DEVKIT-MAINTAINING.md` と `docs/devkit-maintaining/` はコピーされない
   - `docs/agents/` の外にある作者自身の `docs/` は巻き込まれない
   - 手元と新しい版の両方で `docs/agents/` のファイルを変えておくと、`.devkit-new` が書かれ、終了コードが 2 になり、`doctor.ps1` の `devkit-conflicts` にもそのパスが出る（`Get-DevkitConflictFiles` の走査フォルダの確認）
   - `AGENTS.md` を手元で変えてあると `CONFLICT` になる。本体が古いままでも、`.devkit-new` が残っていることが doctor と起動時の hook から伝わる
3. 導入のシナリオ: `ghost/` と `shell/` だけのフォルダに `-Target` で導入する。
   - seed がそろう
   - `doctor.ps1` が `GHOST.md` の未記入を知らせる
   - `check.ps1` が動く
4. `tools/build-nar.ps1 -ListOnly` で、`docs/agents/` のファイルが入っていて（git の作業コピーでは `git add` 済みであること）、`tools/bin/`、`build/`、`*.devkit-new`、`DEVKIT-MAINTAINING.md`、`docs/devkit-maintaining/` が入っていない。
5. `AGENTS.md` の索引（「こう頼まれたら」「資料」）と、`docs/agents/` の中から指しているパスが、すべて実在する。
