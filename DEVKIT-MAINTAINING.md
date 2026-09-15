# DEVKIT-MAINTAINING.md

AI 開発キットそのもの（`AGENTS.md`、`CLAUDE.md`、`DEVKIT-GUIDE.md`、`.claude/`、`tools/` など）を作る・直すときの注意です。

このファイルは、キットの配布元である konnoyayame のリポジトリにだけあります。nar、ネットワーク更新、キットの配布物のどれにも入りません（ルートの `.narignore` の `/DEVKIT-MAINTAINING.md`。`tools/devkit.json` の `files` にも載せない）。ゴーストを作るときの指示は `AGENTS.md`、作者向けのキットの使い方と、別のゴーストへのキットの導入手順は `DEVKIT-GUIDE.md`、konnoyayame に固有の情報は `GHOST.md`、konnoyayame の紹介は `README.md` にあります。

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
- ルートに新しいファイルを足すときは、`files` か `seed` に載せる。載せないと配布されない。
- 作者向けの説明は、キットに入る `DEVKIT-GUIDE.md`（キットの使い方と、別のゴーストへの導入手順）と、konnoyayame の `README.md`（ゴーストの紹介、手で改造するときの案内）に分けている。`DEVKIT-GUIDE.md` はどのゴーストにも入るので、上と同じく特定のゴーストに固有のことを書かない。`README.md` には、キットについては `DEVKIT-GUIDE.md` への案内だけを書く。導入手順を `DEVKIT-GUIDE.md` に置くのは、キットの説明を 1 か所にまとめ、キットを入れたゴーストからも別のゴーストに導入できるようにするため。
- キットの使い方が変わったら、`AGENTS.md` と `DEVKIT-GUIDE.md` の両方を直す。

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
- 終了コードをそろえる: 0 OK / 1 失敗・エラー / 2 注意が要る（SSP のエラーログの Error、`.devkit-new` の残りなど）/ 3 ツールや SSP が無くて確かめられない。
- 冒頭のコメントヘルプ（`.SYNOPSIS`、`.DESCRIPTION`、終了コード、`.EXAMPLE`）を書き、`AGENTS.md` のコマンド表も直す。
- ダウンロードして使うツールは `tools/tools.json` でバージョン、URL、SHA256 を固定する。上げるときは 3 つとも書き換え（SHA256 は `Get-FileHash -Algorithm SHA256`）、`tools/setup.ps1 -Tool <名前> -Force` で取得できることを確かめる。

## 実装メモ

- SSTP: `tools/sstp.ps1` は、`EXECUTE GetFMO` で調べたゴーストの識別 ID を `ID` ヘッダに付けて送る（Owned SSTP）。付けないと SSP は外部のプログラムからの要求として扱い、`\![reload,ghost]` などを黙って無視する（応答は 200 のまま）。
- SSP のログ: プロパティシステムの `developer.log.*` を `EXECUTE GetProperty` で読む。ログは種類ごとに新しいものから 50 件ほどしか残らず、発信元の名前は descript.txt の `name`（`sakura.name` ではない）になる。
- SSP 2.8.94 以降の機能: `tools/lib/common.ps1` の `$DevkitSspRecommendedVersion` を基準にする。版は `ssp.exe` のファイルバージョン（`2, 8, 94, 3000`）の上 3 つで比べ（`Get-DevkitSspVersion`）、doctor は古い版を recommended の不足として知らせる。古い版では、各スクリプトは今までどおりの動き（決まった時間だけ待つなど）に戻す。
  - `EXECUTE GetStatus`（`Get-DevkitSspStatus`）: SEND と NOTIFY は、スクリプトを再生する前に応答する。再生中は `talking` が付くので、`Wait-DevkitSspTalkEnd` でそれが消えるまで待ってからエラーログを読む。ゴーストの読み込み中は 400 が返り、`\![reload,ghost]` の後は `talking` → 400 → 200 と変わる（`Wait-DevkitSspReload`）。古い SSP も 200 を返さないので、要求を送る前に 1 回呼んで使えるか確かめる。
  - `Option: strict`: `tools/sstp.ps1` の `-Script` と `-Event` に付ける。解釈に失敗したタグは、再生がその位置に来たときに、Error として `[GHOST/Script] 理由 (詳細) at position 位置 : 抜粋` の形で記録される（位置はスクリプトの先頭を 0 とした文字数）。
  - `--dump-error-log`: ssp.exe の終了コードが、記録された最も重いレベルになる（0 Notice 以下 / 1 Warning / 2 Error / 3 Critical）。`tools/check-shell.ps1` はログから数えた件数と照らし合わせ、0〜3 以外は異常終了として扱う。
  - SERIKO のメッセージの定義位置（`<ファイル>:Line=<n>:`）: SSP の説明ではゴーストのフォルダからの相対パスだが、`--offline-dump` では絶対パスになる（2.8.94 で確認）。`ConvertTo-DevkitRelativeText` がどちらも `/` 区切りの相対パスにそろえ、`check-shell.ps1 -Ci` はそれを GitHub Actions の注釈の `file` と `line` にする。
- `.narignore` / `.updateignore`（SSP の `sp_gitignorefilter.cpp` の挙動）: `tools/lib/ignore.ps1` をこれにそろえている。
  - ルートに置いたものだけを読む。
  - 行頭が `include:相対パス` の行はディレクティブとして扱う。
  - パスは、その行が書かれたファイルのフォルダを基準に解決する（ルート固定ではない）。
  - 取り込んだ先でも `include:` を書ける。最初のファイルが深さ 0 で、深さ 3 を超えると読まれない（`SP_GITIGNORE_FILTER_MAX_INCLUDE_DEPTH`）。
  - 区切りは `/` でも `\` でもよい。
  - 今の構成は `.updateignore` → `.narignore` → `tools/devkit.narignore` の深さ 2。キット側でこれ以上 `include:` を重ねるときは、上限に注意する。
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
   - キットから外したファイルは消える
   - `GHOST.md` とルートの `.gitignore` は変わらない
   - `DEVKIT-MAINTAINING.md` はコピーされない
3. 導入のシナリオ: `ghost/` と `shell/` だけのフォルダに `-Target` で導入する。
   - seed がそろう
   - `doctor.ps1` が `GHOST.md` の未記入を知らせる
   - `check.ps1` が動く
4. `tools/build-nar.ps1 -ListOnly` で、`tools/bin/`、`build/`、`*.devkit-new`、`DEVKIT-MAINTAINING.md` が入っていない。
