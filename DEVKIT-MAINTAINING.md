# DEVKIT-MAINTAINING.md

AI 開発キットそのもの（`AGENTS.md`、`CLAUDE.md`、`DEVKIT-GUIDE.md`、`docs/agents/`、`.claude/`、`tools/` など）を作る・直すときの注意です。

このファイルは、キットの配布元である konnoyayame のリポジトリにだけあります。nar、ネットワーク更新、キットの配布物のどれにも入りません（ルートの `.narignore` の `/DEVKIT-MAINTAINING.md`。`tools/devkit.json` の `files` にも載せない）。ゴーストを作るときの指示は `AGENTS.md` と `docs/agents/`、作者向けのキットの使い方と、別のゴーストへのキットの導入手順は `DEVKIT-GUIDE.md`、konnoyayame に固有の情報は `GHOST.md`、konnoyayame の紹介は `README.md` にあります。

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
  - 版を固定する（yayalint）: `version`、`url`、`sha256` を書く。上げるときは 3 つとも書き換え（SHA256 は `Get-FileHash -Algorithm SHA256`）、`tools/setup.ps1 -Tool <名前>` で取り直せることを確かめる（取得済みの exe の SHA256 が違えば取り直す）。
  - 最新リリースを使う（tamac。YAYA のプロジェクトが出しているツールで、新しい機能をキットの更新を待たずに使えるようにするため）: `version` を `latest` にし、`repository`、`asset`（リリースのファイル名）、`minimumVersion` を書く。1 つの exe のツールだけに使う（zip では、取得済みのものが最新か見分けられない）。
    - `tools/setup.ps1` は GitHub API で最新リリースを調べ、GitHub が各ファイルに付けている SHA256（`digest`）で照合する。`digest` が無ければ失敗させる。GitHub Actions では、匿名の API 呼び出しの回数制限を避けるため、`auto_check.yml` から `GITHUB_TOKEN` を渡している（`Get-DevkitLatestReleaseAsset` は、トークンが拒否されたら付けずにやり直す）。
    - `doctor.ps1` と `tools/shiori.ps1` はネットワークに出ずに、exe のファイルバージョンが `minimumVersion` 以上かを見る（`Test-DevkitToolCurrent`）。キットのスクリプトが新しいオプションを使い始めたら `minimumVersion` を上げる。
    - 新しいリリースで挙動が変わると、すべてのゴーストの auto check に影響する。tamac のリリースの前に、このリポジトリで `tools/check.ps1` と `tools/shiori.ps1` を試す。

## 実装メモ

- SSTP: `tools/sstp.ps1` は、`EXECUTE GetFMO` で調べたゴーストの識別 ID を `ID` ヘッダに付けて送る（Owned SSTP）。付けないと SSP は外部のプログラムからの要求として扱い、`\![reload,ghost]` などを黙って無視する（応答は 200 のまま）。
- SSP のログ: プロパティシステムの `developer.log.*` を `EXECUTE GetProperty` で読む。ログは種類ごとに新しいものから 50 件ほどしか残らず、発信元の名前は descript.txt の `name`（`sakura.name` ではない）になる。
- SSP 2.8.94 以降の機能: `tools/lib/common.ps1` の `$DevkitSspRecommendedVersion` を基準にする。版は `ssp.exe` のファイルバージョン（`2, 8, 94, 3000`）の上 3 つで比べ（`Get-DevkitSspVersion`）、doctor は古い版を recommended の不足として知らせる。古い版では、各スクリプトは今までどおりの動き（決まった時間だけ待つなど）に戻す。
  - `EXECUTE GetStatus`（`Get-DevkitSspStatus`）: SEND と NOTIFY は、スクリプトを再生する前に応答する。再生中は `talking` が付くので、`Wait-DevkitSspTalkEnd` でそれが消えるまで待ってからエラーログを読む。ゴーストの読み込み中は 400 が返り、`\![reload,ghost]` の後は `talking` → 400 → 200 と変わる（`Wait-DevkitSspReload`）。古い SSP も 200 を返さないので、要求を送る前に 1 回呼んで使えるか確かめる。
  - `Option: strict`: `tools/sstp.ps1` の `-Script` と `-Event` に付ける。解釈に失敗したタグは、再生がその位置に来たときに、Error として `[GHOST/Script] 理由 (詳細) at position 位置 : 抜粋` の形で記録される（位置はスクリプトの先頭を 0 とした文字数）。
  - `--dump-error-log`: ssp.exe の終了コードが、記録された最も重いレベルになる（0 Notice 以下 / 1 Warning / 2 Error / 3 Critical）。`tools/check-shell.ps1` はログから数えた件数と照らし合わせ、0〜3 以外は異常終了として扱う。
  - SERIKO のメッセージの定義位置（`<ファイル>:Line=<n>:`）: SSP の説明ではゴーストのフォルダからの相対パスだが、`--offline-dump` では絶対パスになる（2.8.94 で確認）。`ConvertTo-DevkitRelativeText` がどちらも `/` 区切りの相対パスにそろえ、`check-shell.ps1 -Ci` はそれを GitHub Actions の注釈の `file` と `line` にする。
- tamac.exe の `-r`（v1.0.3.25 以降。`tools/shiori.ps1`）:
  - 標準入力を EOF まで読んでリクエストにし（改行を CRLF にそろえ、終わりの空行を足し、先頭の BOM を外す）、応答を標準出力に、ログをすべて標準エラー出力に出す。1 回に送れるのは 1 リクエストだけ。
  - dll は絶対パスで渡す（`Invoke-DevkitTamac`）。相対パスだと `yaya.txt` を探すフォルダが空になり、読み込めない。
  - 終了コード: 0 / 1（dll が読めない、空のリクエスト、空の応答）/ 2（読み込み中か処理中に `-l` 以上のログ。応答は出る）。環境変数 `GITHUB_ACTIONS` があると `--ci` の出力に切り替わるので、`shiori.ps1` は子プロセスに渡さない。
  - ログには、読み込み（`// request` の次の行がゴーストのフォルダ）、送ったリクエスト、解放の順に、`// request` と本文が並ぶ。`shiori.ps1` は、送ったリクエストの 1 行目より前のエラーを読み込みエラーとして扱う。緊急モードでも `?? 1+2` に答える（konnoyayame で確認）ので、応答だけでは見分けられない。
  - `?? コード` には、yaya-dic の `shiori3.dic`（`AyaTest.Eval`）が `!! 結果` で答える。行ごとに `EVAL` して結果をつなげ、配列は `,` で JOIN する。ローカル変数は次の行に残らない。`EVAL` に失敗すると結果はコードそのものになり、E0071 などが `shiori3.dic` の行で記録される。
  - システム辞書は、リクエストの `Charset` で `charset.output` を切り替える（`SETSETTING`）。`-Event` は `yaya.txt` の `charset.output` を送り、UTF-8 を決め打ちしない。`Sender` は `basewarename` になり、テンプレートは `SSP` かどうかで分岐するので、`SSP` を送る。
  - YAYA は解放のときに `yaya_variable.cfg` を保存するので、`Invoke-DevkitTamac` が前後で退避して戻す（`check-dic.ps1` も同じ）。
  - `.claude/settings.json` の許可リストに入れている。`-Eval` は任意の YAYA のコード（`EXECUTE`、`FWRITE` など）を実行できるが、辞書の関数を試すたびに確認が出ると使われなくなるため、使いやすさを優先した。ファイルの書き込みや外部プログラムの実行をする関数は中身を読んでから呼ぶことを、`AGENTS.md` と `docs/agents/workflows/check.md` に書いている。
- `tools/update-yaya.ps1` のシステム辞書（yaya-dic）:
  - yaya-dic にはリリースもタグも無いので、既定のブランチの最新のコミットを使う。git のチェックアウトでは `git fetch origin HEAD` の `FETCH_HEAD`、それ以外では GitHub API の `commits/HEAD` の SHA の zip。
  - 今の構成かどうかは `yaya_base/shiori3.dic` の有無で見る（`Test-DevkitYayaDicLayout`）。yaya-dic は 2022-06-17 に `yaya_shiori3.dic` などをフォルダに分けて改名した。古い名前は `$DevkitOldSystemDicNames` にあり（`yaya_config.txt` は古いテンプレートがゴースト側に置いていた設定辞書）、`Find-DevkitOldSystemDicFiles` が `ghost/master` の下を探す。古い構成は自動では直さず、終了コード 2 で手順書の再編に回す。doctor も、`yaya_shiori3.dic` が見つかれば system-dic を不足にしない（ゴーストは動くため）。
  - 普通のファイルには、lock のような「入れた版」の記録が無い。作者が変えることのある `yaya_base/config.dic` と `_loading_order.txt` は、新しい版と違えば置き換えずに `.yaya-dic-new` を横に置く（上流が変えただけでも衝突になるが、手順書でエージェントがマージする）。それ以外は作者が変えない前提で置き換える。`.github/` など先頭がドットのものは取り込まない。
  - git のチェックアウトは、未コミットの変更か、今のコミットが新しいコミットの祖先でなければ切り替えない。`.gitmodules` に載っていても、ルートに `.git` が無いフォルダ（nar など）は submodule として扱わない。
  - 辞書チェックは yaya.dll とシステム辞書のそれぞれの後で行い、失敗した部分だけを戻す。どちらが原因かを分けるため。
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
   - キットから外したファイルは消える。作者が手を入れていたものは `keep` で残る
   - `GHOST.md` とルートの `.gitignore` は変わらない
   - `DEVKIT-MAINTAINING.md` はコピーされない
   - `docs/agents/` の外にある作者自身の `docs/` は巻き込まれない
   - 手元と新しい版の両方で `docs/agents/` のファイルを変えておくと、`.devkit-new` が書かれ、終了コードが 2 になり、`doctor.ps1` の `devkit-conflicts` にもそのパスが出る（`Get-DevkitConflictFiles` の走査フォルダの確認）
   - `AGENTS.md` を手元で変えてあると `CONFLICT` になる。本体が古いままでも、`.devkit-new` が残っていることが doctor と起動時の hook から伝わる
3. 導入のシナリオ: `ghost/` と `shell/` だけのフォルダに `-Target` で導入する。
   - seed がそろう
   - `doctor.ps1` が `GHOST.md` の未記入を知らせる
   - `check.ps1` が動く
4. `tools/build-nar.ps1 -ListOnly` で、`docs/agents/` のファイルが入っていて（git の作業コピーでは `git add` 済みであること）、`tools/bin/`、`build/`、`*.devkit-new`、`DEVKIT-MAINTAINING.md` が入っていない。
5. `AGENTS.md` の索引（「こう頼まれたら」「資料」）と、`docs/agents/` の中から指しているパスが、すべて実在する。
