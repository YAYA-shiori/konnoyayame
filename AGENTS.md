# AGENTS.md

AI コーディングエージェント（Claude Code、Codex、GitHub Copilot、Cursor など）がこのゴーストを開発するときの、共通の指示書です。人間の開発者が読んでもわかるように書いています。

## このプロジェクトについて

- 伺か（ukagaka）のゴースト「紺野ややめ」。SHIORI「YAYA」の**テンプレートゴースト**で、これを土台にして自分のゴーストを作ってもらうためのもの。
- ベースウェアは SSP を前提にしている。開発用スクリプトも Windows の PowerShell を前提にしている。
- 次のどちらのフォルダでも、同じ手順で開発できる。
  - GitHub のリポジトリを clone したフォルダ
  - `.nar` を SSP にインストールしたフォルダ（`<SSP>/ghost/konnoyayame/`）
- ライセンス: シェル以外（辞書など）は Public Domain (Unlicense)。**シェル `shell/master/` は SATO M 氏の作品で、CC BY-NC-ND 2.1 JP**（`shell/master/descript.txt` 参照）。改変した画像の配布や商用利用はできない。

## ディレクトリ構成

| パス | 内容 |
|---|---|
| `ghost/master/descript.txt` | ゴーストの基本情報（名前、作者、使う SHIORI） |
| `ghost/master/yaya.txt` | YAYA の基本設定。文字コードと、読み込む辞書フォルダ（`dicdir, dic/normal`） |
| `ghost/master/yaya_emerg.txt` | 辞書エラー時の緊急モードの設定（`dic/emerg` を読む） |
| `ghost/master/system_config.txt` | システム辞書の読み込みとログの設定 |
| `ghost/master/dic/normal/*.dic` | **ゴーストの辞書本体。主に編集するのはここ** |
| `ghost/master/dic/emerg/*.dic` | 緊急モード用の最小限の辞書 |
| `ghost/master/dic/system/` | システム辞書（git submodule: [yaya-dic](https://github.com/YAYA-shiori/yaya-dic)）。**編集しない** |
| `ghost/master/yaya.dll` | SHIORI 本体。`tools/update-yaya.ps1` 以外で差し替えない |
| `ghost/master/yayalint_config.lua` | yayalint の設定 |
| `shell/master/surfaces.txt` | サーフェス（表情、アニメーション、当たり判定）の定義 |
| `shell/master/surfacetable.txt` | サーフェス番号と表情名の一覧 |
| `shell/master/descript.txt` | シェルの情報、メニューや吹き出し位置の設定 |
| `install.txt` | インストール設定（名前とインストール先フォルダ名） |
| `.narignore` / `.updateignore` | nar / ネットワーク更新から除外するファイル。書き方は `.gitignore` と同じで、`include:ファイル名` で別のファイルを取り込める。SSP と `tools/build-nar.ps1` の両方が使う。古い形式の `developer_options.txt` は、併用すると両方が処理されて紛らわしいので作らない |
| `delete.txt` | ネットワーク更新のときに削除するファイル |
| `tools/` | 開発用スクリプト（下記） |
| `CLAUDE.md`, `.claude/`, `.mcp.json` | Claude Code 用の設定 |
| `.github/workflows/` | push ごとに辞書チェック（tamac）し、通れば nar を自動リリースする |

実行時に作られるもの（編集もコミットもしない）: `ghost/master/yaya_variable.cfg`（グローバル変数の保存先）、`ghost/master/profile/`、`shell/master/profile/`、`tools/bin/`（ダウンロードしたツール）、`tools/local.json`（各自の設定）、`build/`。

## 開発コマンド

以下の `<ps>` は `powershell -NoProfile -ExecutionPolicy Bypass -File` の略。Windows PowerShell 5.1 でも PowerShell 7 でも動く。

| コマンド | 内容 | 終了コード |
|---|---|---|
| `<ps> tools/doctor.ps1` | 開発環境を診断し、足りないもの（Git、Node.js、SSP、チェック用ツールなど）の用途と入手方法を表示する。何も変更しない（`-Json` で機械向けの出力） | 0 必須はそろっている / 1 必須が足りない |
| `<ps> tools/setup.ps1` | git clone したフォルダなら submodule を取得し、tamac.exe と yayalint を `tools/bin/` に取得する（バージョンと SHA256 は `tools/tools.json` で固定）。最後に doctor の結果を表示する | 0 成功 / 1 失敗、または必須が足りない |
| `<ps> tools/check-dic.ps1` | tamac.exe で辞書を実際に読み込み、エラーを表示する | 0 OK / 1 エラー / 3 ツール未導入 |
| `<ps> tools/check-shell.ps1` | `ssp.exe --offline-dump` でシェルを検査する（Error / Warning / Notice） | 0 OK / 1 Error あり / 3 SSP が見つからない |
| `<ps> tools/lint.ps1` | yayalint で未定義・未使用の変数と関数を探す（参考情報） | 0（`-Strict` なら未定義があると 1）/ 3 |
| `<ps> tools/check.ps1` | 上の 3 つを順に実行する | 0 / 1 |
| `<ps> tools/run-ssp.ps1` | このフォルダのゴーストを SSP で直接起動し（`ssp.exe --ghost <フォルダ>`。インストール不要）、応答するまで待つ。起動中に SSP のエラーログに増えた警告・エラーを表示する | 0 起動した / 1 応答なし / 2 起動したが、エラーログに Error か Critical が増えた / 3 SSP が見つからない |
| `<ps> tools/sstp.ps1 -Reload ghost` | 起動中の SSP にゴーストを再読み込みさせ、その間に SSP のエラーログに増えた警告・エラー（YAYA の辞書エラーなど）を表示する | 0 / 1 エラー応答 / 2 エラーログに Error か Critical が増えた / 3 SSP に接続できない |
| `<ps> tools/sstp.ps1 -Script '\0\s[5]テスト\e'` | さくらスクリプトを実際のゴーストで再生する | 同上 |
| `<ps> tools/sstp.ps1 -Event OnAiTalk` | イベントを発生させる（この例はランダムトーク）。応答の `Script:` に、ゴーストが実際に返したスクリプトが入る | 同上 |
| `<ps> tools/ssp-log.ps1` | 起動中の SSP のログを表示する。読み取りのみ。既定はこのゴーストのエラーログで、`-Kind script` で再生されたスクリプト（ほかに `network` / `update`）、`-All` で発信元を問わず全部、`-Json` で機械向けの出力 | 0 / 1 SSP が developer.log に未対応 / 2 Error か Critical がある / 3 SSP に接続できない |

`tools/sstp.ps1` は、`EXECUTE GetFMO` で調べたゴーストの識別 ID を `ID` ヘッダに付けて送る（Owned SSTP）。付けないと SSP は外部のプログラムからの要求として扱い、`\![reload,ghost]` などを黙って無視する（応答は 200 のまま）。SSP のログは、プロパティシステムの `developer.log.*` を `EXECUTE GetProperty` で読む。ログは種類ごとに新しいものから 50 件ほどしか残らず、発信元の名前は descript.txt の `name`（`sakura.name` ではない）になる。
| `<ps> tools/build-nar.ps1` | `build/<directory>.nar` を作る（`-ListOnly` で中身の一覧だけ表示） | 0 / 1 |
| `<ps> tools/update-yaya.ps1` | yaya.dll を最新リリースに更新する。辞書チェックに失敗したら元に戻す（`-DryRun` で確認のみ） | 0 / 1 |

SSP の場所は次の順に探す: `-SspPath` 引数 → 環境変数 `SSP_PATH` → `tools/local.json` の `sspPath`（`tools/local.example.json` を複製して作る）→ SSP にインストールされたフォルダなら `../../ssp.exe` → `.nar` のファイル関連付け。

## 初回セットアップ（エージェントが代行する）

作者には創作に集中してもらい、環境づくりのような決まった作業はエージェントが引き受ける。ユーザーに「セットアップして」と頼まれたとき、または `tools/doctor.ps1` で足りないものが見つかったときは、次の順に進める。

1. `tools/doctor.ps1 -Json` で診断する。各項目に `level`（`required` / `recommended` / `optional`）、用途、直し方が入っている。
2. 足りないアプリがあれば、何に使うかを一言で説明して入手を提案する。**アプリのインストールは、必ずユーザーの了承を得てから行う。**
   - Git（推奨）: 変更履歴と GitHub での自動チェック・リリース。winget があれば `winget install --id Git.Git -e`
   - SSP（推奨）: シェルのチェックと、実際のゴーストでの確認。https://ssp.shillest.net/ から入手してもらう。入っているのに見つからない場合は、場所を聞いて `tools/local.json` に書く
   - Node.js 20 以上（任意）: 仕様検索 MCP。winget があれば `winget install --id OpenJS.NodeJS.LTS -e`
   - インストールした直後は PATH が反映されず、ターミナルやエージェントの再起動が必要なことがある
3. `tools/setup.ps1` を実行する（submodule の取得と、チェック用ツールのダウンロード）。
4. `tools/check.ps1` でチェックが通ることを確かめる。
5. 望まれたら `tools/run-ssp.ps1` でゴーストを起動して見せる。
6. 次にできること（トークを書く、テンプレートから独立したゴーストを作る）を案内する。

## 作業のルール

1. **辞書や `ghost/master/*.txt` を変更したら、必ず `tools/check-dic.ps1` を通す。** エラーが残ったゴーストは緊急モードで起動し、ほとんど話さなくなる。`shell/` を変更したら `tools/check-shell.ps1` も通す。SSP で動かして確かめるときは、`tools/sstp.ps1` や `tools/run-ssp.ps1` が表示する SSP のエラーログ（終了コード 2）も見る。
2. 仕様（さくらスクリプトのタグ、SHIORI イベントの名前と Reference、YAYA の関数、descript.txt や surfaces.txt の項目）を**推測で書かない**。確かでないときは「仕様の調べ方」に従って確かめる。
3. 文字コードは UTF-8（BOM なし）、改行は LF、辞書のインデントはタブ（`.editorconfig` 参照）。ただし `readme-aya.txt` と `readme-yaya.txt` は Shift_JIS なので、文字コードを変えない。
4. 編集しないもの: `ghost/master/dic/system/`（submodule。変更が必要なら上流の yaya-dic に提案する）、`yaya.dll`、実行時に作られるファイル。
5. `tools/*.ps1` は Windows PowerShell 5.1 でも動くように書き、**ASCII 文字だけで書く**（BOM のないファイルに日本語を書くと 5.1 で文字化けするため）。
6. 既存のトークや作者が書いた台詞を、頼まれていないのに大量に書き換えたり消したりしない。未使用の関数や変数が見つかっても、報告するだけにする。
7. アプリのインストール、SSP へのゴーストのインストール、yaya.dll の更新、リリース、ネットワーク更新ファイルのアップロードなど、手元のファイル編集を超える操作は、作者の確認を取ってから行う。

## YAYA 辞書の書き方の要点

- 関数は `関数名 { ... }` で定義する。`{ }` の中に文字列を並べると、呼ばれるたびにその中から 1 つが選ばれる。`関数名 : nonoverlap { ... }` とすると、一巡するまで同じものを選ばない。
- `--` を挟むと、前後のブロックの結果をつなげて 1 つの出力にする（`yaya_aitalk.dic` の `OnMinuteChange` 参照）。
- 文字列:
  - `"..."` の中では `%(変数名)` や `%(関数名)` が展開される。`"` そのものは `""` と重ねて書く。
  - `'...'` の中は展開されない。
  - 例外として、ランダムトーク本体の `RandomTalkEx` は `'...'` で書くが、呼び出し側の `RandomTalk` が展開するので `%(username)` などが使える。
  - バックスラッシュはエスケープ文字ではない。`'\0\s[0]'` はそのままさくらスクリプトとして出力される。
- 行末に `/` を書くと、次の行に続けて書ける。
- `_` で始まる変数はローカル変数。それ以外はグローバル変数で、`yaya_variable.cfg` に自動で保存され、次に起動したときに戻る。
- イベントの引数は `reference[0]`、`reference[1]`、…（`reference0` の形でも読める）。
- 制御構文は `if` / `elseif` / `else`、`case 値 { when 'a' { ... } others { ... } }`、`while`、`for`、`foreach`。条件に `( )` は要らない。
- コメントは `//` と `/* */`。
- チェイントーク: トークの最後に `\e:chain=ラベル` と書くと、その後のランダムトークが `ラベル {{CHAIN ... }}CHAIN` に並べたトークから順に選ばれる。`{ }` で囲んだ部分はその中からランダムに選ばれる（`yaya_aitalk.dic` の `siritori` 参照）。
- 関数の一覧や細かい文法は YAYA Wiki で確かめる。

## イベントと辞書ファイルの対応

| ファイル（`ghost/master/dic/normal/`） | 主な中身 |
|---|---|
| `yaya_aitalk.dic` | ランダムトーク（`RandomTalkEx`）、チェイントーク、キー入力 `OnKeyPress`、時報と重なり `OnMinuteChange`、見切れ |
| `yaya_bootend.dic` | 初回起動 `OnFirstBoot`、起動 `OnBoot`、終了 `OnClose`、時間帯の判定 `GetTimeSlot` |
| `yaya_mouse.dic` | なで・つつきへの反応。関数名は「種別＋スコープ番号＋当たり判定名」（例: `MouseMove0Head`、`MouseDoubleClick1`）。種別は `MouseMove`、`MouseDoubleClick`、`MouseWheelUp`、`MouseWheelDown`。テンプレートが自動で呼ぶ |
| `yaya_menu.dic` | メニュー `OpenMenu` と、選択肢ごとの処理 `Menu_*` |
| `yaya_communicate.dic` | ユーザーとの会話、他のゴーストとの会話（`TalkTo*` / `ReplyTo*`） |
| `yaya_change.dic` | ゴーストの切り替えや呼び出しのときのトーク |
| `yaya_etc.dic` | シェル変更、インストール、消滅（vanish）、ネットワーク更新、ヘッドライン、時刻合わせなどのイベント |
| `yaya_string.dic` | ユーザー名の初期値、メニュー項目の文字列などのリソース（`On_*`） |
| `yaya_word.dic` | トーク中に `%(ms)` のように埋め込む単語 |
| `yaya_homeurl.dic` | ネットワーク更新の URL（`On_homeurl`） |
| `yaya_tmpl_util.dic` | テンプレートの内部処理（`AYATEMPLATE.*`）。必要なとき以外は触らない |

新しいイベントに反応させるには、イベント名と同じ名前の関数を、内容の近い辞書ファイルに書く。`dic/normal/` に新しい `.dic` ファイルを置いた場合も自動で読み込まれる。

## キャラクターとサーフェス

| スコープ | キャラクター | 人物像（既存のトークから） | 使えるサーフェス |
|---|---|---|---|
| `\0`（`\h`） | 紺野ややめ | 一人称「わたし」。元気で天然ボケ、子どもっぽい。「ぷー」「えへへ」。自分がサンプルゴーストだと知っていて、メタな発言が多い | 0 素 / 1 照れ / 2 驚き / 3 不安 / 4 はうー / 5 笑い / 6 目閉じ / 7 怒り |
| `\1`（`\u`） | マック朗 | 一人称「おれ」。ツッコミ役で、口が悪い（「〜だろ」「やめろ」）。リンゴ（かじられた跡）にまつわるネタが多い | 10 素 / 11 刮目 |

- ややめの当たり判定（`surfaces.txt` の `collision`）は `Head`、`Face`、`Bust`、`Twintail`。
- 1030〜1033 と 1040〜1043 はアニメーション用の部品（`surfacetable.txt` の `__disabled` グループ）なので、トークでは使わない。
- 表情を増やすにはシェルの画像が必要になる。トークでは上の表にある番号だけを使う。

## トーク（さくらスクリプト）の書き方

このゴーストの書き方:

- 話し始める側のスコープと表情を最初に指定する（`\0\s[5]...`）。両方の表情を先に決める `\u\s[10]\0\s[3]...` という書き方もある。
- 話し手を交代する前に `\w8` を入れる。同じ話し手の中の間は `\w5`〜`\w9`（`\w1` がおよそ 50 ミリ秒）。沈黙の「‥‥」は `‥\w5‥\w5` と書く。
- 同じ話し手の中で改行するときは `\w9\n`。
- すでに話したスコープに戻って話すときは、`\n\n` で空行を入れてから続ける。
- トークの最後は `\e`。
- ユーザーは `%(username)` で呼ぶ。

例（`yaya_aitalk.dic` より）:

```
'\0\s[1]マック朗って‥\w5‥\w5\w8\1なんだ？\w8\0\s[4]\n\n美味しくなさそうだよね。\w8\1\n\n‥\w5‥\w5かじったの、お前じゃないのか。\e'
```

AI がやりがちな失敗:

- 1 つの台詞が長すぎる。吹き出しの幅はバルーンによって違うので、全角 20〜25 字くらいを目安に `\n` で区切り、仕上がりは `tools/sstp.ps1` を使って実際の画面で確かめてもらう。
- 存在しないサーフェス番号を使う。
- `'...'` の中に `%(変数)` を書いて、展開されない（`RandomTalkEx` は例外）。
- 話し手の口調が混ざる（ややめが「おれ」と言う、マック朗が丁寧語で話す、など）。
- `\` を `\\` と重ねて書く。YAYA では重ねる必要がなく、さくらスクリプトの `\\` は「\」という文字の表示になる。
- ランダムトークの候補どうしで、同じ展開やオチを繰り返す。
- 頼まれていないのに、`\![open,...]`、`\![execute,...]`、`\-`（終了）など、ユーザーの PC やゴーストの動作に影響するタグを入れる。

## 仕様の調べ方

さくらスクリプトのタグ、SHIORI イベントの名前と Reference、YAYA の関数、各種設定ファイルの項目は、推測で書かずに次の順で調べる。

1. MCP サーバー `ukagaka-doc`（UKADOC、YAYA Wiki などをオフラインで検索できる。起動コマンドは `npx -y ukagaka-doc-mcp`、Node.js 20 以上が必要）。Claude Code では `.mcp.json` で設定済み。他のツールでは、そのツールの MCP 設定に stdio サーバーとして登録する（Windows では `cmd /c npx -y ukagaka-doc-mcp`）。
2. 一次資料を読む。
   - さくらスクリプト一覧: https://ssp.shillest.net/ukadoc/manual/list_sakura_script.html
   - SHIORI イベント一覧: https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html
   - SHIORI リソース一覧: https://ssp.shillest.net/ukadoc/manual/list_shiori_resource.html
   - ゴーストの descript.txt: https://ssp.shillest.net/ukadoc/manual/descript_ghost.html
   - シェルの descript.txt: https://ssp.shillest.net/ukadoc/manual/descript_shell.html
   - surfaces.txt: https://ssp.shillest.net/ukadoc/manual/descript_shell_surfaces.html
   - SSTP: https://ssp.shillest.net/ukadoc/manual/spec_sstp.html
   - install.txt / .narignore / .updateignore / delete.txt: https://ssp.shillest.net/ukadoc/manual/descript_install.html
   - ネットワーク更新: https://ssp.shillest.net/ukadoc/manual/dev_update.html
   - YAYA Wiki（文法と関数）: https://emily.shillest.net/ayaya/
   - システム辞書 yaya-dic: https://github.com/YAYA-shiori/yaya-dic
3. それでもわからなければ Web 検索する。

調べものは、小さく速いモデルのサブエージェントに任せるとよい（Claude Code では `ukagaka-researcher`）。

## 独立ゴーストにするときのチェックリスト

テンプレートを改造して、自分のゴーストとして配布するときは、少なくとも次を変える。

- [ ] `ghost/master/descript.txt`: `name`、`sakura.name`、`kero.name`、`craftman`（半角英数）、`craftmanw`、`craftmanurl`
- [ ] `install.txt`: `name`、`directory`（インストール先のフォルダ名。半角英数で、他のゴーストと重ならないもの）
- [ ] ネットワーク更新の URL: `ghost/master/dic/normal/yaya_homeurl.dic` と `ghost/master/dic/emerg/yaya_homeurl.dic` の `On_homeurl`。自分の URL に変えるか、更新しないなら関数ごと消す。**元の URL のまま配布すると、元のゴーストの更新で、改造した内容が上書きされてしまう。**
- [ ] シェル: `shell/master/` は CC BY-NC-ND なので、改変した画像は配布できない。自作のシェルか利用許可のあるシェルに差し替え、シェルの `descript.txt`（`name`、`craftman` など）も変える。
- [ ] `README.md`、`thumbnail.pnr`、`delete.txt`（テンプレートの更新用なので、自分のゴーストに合わせて見直す）
- [ ] 名前やキャラクター設定に関わる台詞（`OnFirstBoot` の自己紹介、ランダムトーク、マウスへの反応など）
- [ ] 辞書に直接書かれたゴースト名: `yaya_menu.dic` の `OnStampInfo`（スタンプ帳で自分のスタンプを見分けるための `'はろーYAYAわーるど'` / `'紺野ややめ'`）
- [ ] GitHub で自動リリースする場合は、`.github/workflows/auto_release.yml` の nar ファイル名とリリースの説明文。このワークフローは push のたびに**既存のリリースとタグをすべて削除して**作り直すので、残したいリリースがあるリポジトリでは書き換える。nar をインストールしたフォルダから始めた場合、`ghost/master/dic/system/` は submodule ではなく普通のフォルダとしてコミットしてよい
- [ ] 元にしたテンプレートのクレジット（義務ではないが、慣習としておすすめ）。例:「紺野ややめ（https://github.com/YAYA-shiori/konnoyayame）をもとに作成」

## AI を使ったゴースト制作のガイドライン

伺かは、作者が手作りしたゴーストを配り合う文化の上に成り立っている。AI エージェントは次を守ること。

- 他のゴーストの台詞、シェル画像、辞書を、コピーしたり言い換えたりして持ち込まない。参考にしてよいのは、公開されている仕様と、このリポジトリのテンプレートだけ。
- 実在の人物を模したキャラクターを作らない。既存の作品の二次創作は、作者が原作のガイドラインを確かめた上で行う。AI の側から既存のキャラクターを持ち込まない。
- 生成したトークは、作者が読んで確かめてから公開するものとして書く。数を増やすための大量生成はせず、キャラクターの口調と設定の一貫性を優先する。
- AI の手を借りて作ったことを、readme などに書いておくことをすすめる（義務ではない）。配布サイトや交流の場に AI 生成物についての決まりがあるときは、作者に確認してもらう。
- ユーザーの PC に影響する処理（外部プログラムの実行、ファイルの書き込みや削除、ネットワーク通信、`SHIORI3FW.ENABLE_DELAYED_EVAL` の有効化など）は、作者にはっきり頼まれない限り書かない。

## ツールごとの補足

- Claude Code: `CLAUDE.md` がこのファイルを読み込み、編集後の自動チェック、スキル、調査用サブエージェントを追加している。
- それ以外のツール: 編集後の自動チェックがないので、辞書やシェルを変更するたびに `tools/check-dic.ps1` や `tools/check-shell.ps1` を自分で実行する。
