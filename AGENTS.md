# AGENTS.md

AI コーディングエージェント（Claude Code、Codex、GitHub Copilot、Cursor など）が YAYA のゴーストを開発するときの、共通の指示書です。人間の開発者が読んでもわかるように書いています。

**作業を始める前に、ルートの `GHOST.md` も必ず読むこと。** ゴーストの名前、キャラクターと使えるサーフェス、ライセンス、辞書の構成、トークの書き方の決まりなど、このゴーストに固有の情報はそちらにある。`GHOST.md` が無いときや、先頭に `<!-- devkit:ghost-template -->` が残っている（まだ書かれていない）ときは、辞書とシェルを読んで下書きすることを作者に提案する。

このファイルは開発キットの一部で、キットの更新で新しい版に置き換わる。このゴーストだけの決まりは `GHOST.md` に書く。

## このプロジェクトについて

- 伺か（ukagaka）のゴースト。SHIORI は YAYA。
- ベースウェアは SSP を前提にしている。開発用スクリプトも Windows の PowerShell を前提にしている。
- 次のどちらのフォルダでも、同じ手順で開発できる。
  - GitHub などのリポジトリを clone したフォルダ
  - `.nar` を SSP にインストールしたフォルダ（`<SSP>/ghost/<フォルダ名>/`）

## 開発キットとファイルの持ち主

このフォルダには、ゴースト本体と一緒に、AI エージェントで開発するための開発キットが入っている。キットは `tools/update-devkit.ps1` で、ゴーストとは別に更新できる。

| 区分 | ファイル | キットを更新するとき |
|---|---|---|
| キット | `AGENTS.md`、`CLAUDE.md`、`DEVKIT-GUIDE.md`、`.mcp.json`、`.claude/`（`settings.local.json` を除く）、`.github/workflows/auto_check.yml`、`tools/`（`bin/`、`local.json`、`devkit.lock.json` を除く） | 新しい版に置き換わる。手元で変えたファイルは残り、新しい版と両方が変わっていれば、新しい版が `<ファイル名>.devkit-new` として横に置かれる |
| 初回だけ作るもの | `GHOST.md`、`.narignore`、`.updateignore`、`.gitattributes`、`.editorconfig`、`ghost/master/yayalint_config.lua` | 無いときだけ作られる。あとはゴーストのもの |
| ゴースト | それ以外（辞書、シェル、`README.md`、`.gitignore`、ほかのワークフローなど） | 触らない |

- 正確な一覧は `tools/devkit.json`、導入した版の記録は `tools/devkit.lock.json` にある。
- キットのファイルは、なるべく直接変えない。このゴーストだけの決まりは `GHOST.md` に、Claude Code の個人設定は `.claude/settings.local.json` に書く。
- `.devkit-new` ができたら、手元の変更を活かしながら中身を元のファイルにマージし、`.devkit-new` を消す（Claude Code では `/update-devkit`）。
- ルートに `DEVKIT-MAINTAINING.md` があるフォルダは、キットの配布元のリポジトリ。キットのファイルや `tools/devkit/` を変える前に `DEVKIT-MAINTAINING.md` を読む。

## ディレクトリ構成

テンプレート（紺野ややめ）から作ったゴーストの標準的な構成。このゴーストで違うところは `GHOST.md` に書く。

| パス | 内容 |
|---|---|
| `GHOST.md` | **このゴーストに固有の情報**（キャラクター、サーフェス、ライセンス、辞書の構成） |
| `ghost/master/descript.txt` | ゴーストの基本情報（名前、作者、使う SHIORI） |
| `ghost/master/yaya.txt` | YAYA の基本設定。文字コードと、読み込む辞書フォルダ（`dicdir, dic/normal`） |
| `ghost/master/yaya_emerg.txt` | 辞書エラー時の緊急モードの設定（`dic/emerg` を読む） |
| `ghost/master/system_config.txt` | システム辞書の読み込みとログの設定 |
| `ghost/master/dic/normal/*.dic` | **ゴーストの辞書本体。主に編集するのはここ** |
| `ghost/master/dic/emerg/*.dic` | 緊急モード用の最小限の辞書 |
| `ghost/master/dic/system/` | システム辞書（git submodule: [yaya-dic](https://github.com/YAYA-shiori/yaya-dic)）。ゴーストによっては `ghost/master/system/` にあり、開発キットのスクリプトはどちらにも対応している。**編集しない** |
| `ghost/master/yaya.dll` | SHIORI 本体。`tools/update-yaya.ps1` 以外で差し替えない |
| `ghost/master/yayalint_config.lua` | yayalint の設定 |
| `shell/master/surfaces.txt` | サーフェス（表情、アニメーション、当たり判定）の定義 |
| `shell/master/surfacetable.txt` | サーフェス番号と表情名の一覧 |
| `shell/master/descript.txt` | シェルの情報、メニューや吹き出し位置の設定 |
| `install.txt` | インストール設定（名前とインストール先フォルダ名） |
| `.narignore` / `.updateignore` | nar / ネットワーク更新から除外するファイル。書き方は `.gitignore` と同じで、`include:ファイル名` で別のファイルを取り込める（パスはその行を書いたファイルのフォルダからの相対。取り込んだ先でも `include:` を書け、3 段まで）。キット用の除外は `tools/devkit.narignore` を取り込んでいる。SSP と `tools/build-nar.ps1` の両方が使い、どちらもルートに置いたものだけを読む（サブフォルダに置いても効かない）。古い形式の `developer_options.txt` は、併用すると両方が処理されて紛らわしいので作らない |
| `delete.txt` | ネットワーク更新のときに削除するファイル |
| `tools/` | 開発用スクリプト（下記） |
| `DEVKIT-GUIDE.md` | 開発キットの使い方（作者向け）。キットについて作者に説明するときは、ここを案内する |
| `CLAUDE.md`, `.claude/`, `.mcp.json` | Claude Code 用の設定 |
| `.github/workflows/auto_check.yml` | push ごとに辞書チェック（tamac）する |

実行時に作られるもの（編集もコミットもしない）: `ghost/master/yaya_variable.cfg`（グローバル変数の保存先）、`ghost/master/profile/`、`shell/master/profile/`、`tools/bin/`（ダウンロードしたツール）、`tools/local.json`（各自の設定）、`build/`。

## 開発コマンド

以下の `<ps>` は `powershell -NoProfile -ExecutionPolicy Bypass -File` の略。Windows PowerShell 5.1 でも PowerShell 7 でも動く。

| コマンド | 内容 | 終了コード |
|---|---|---|
| `<ps> tools/doctor.ps1` | 開発環境を診断し、足りないもの（Git、Node.js、SSP、チェック用ツール、`GHOST.md` など）の用途と入手方法を表示する。何も変更しない（`-Json` で機械向けの出力） | 0 必須はそろっている / 1 必須が足りない |
| `<ps> tools/setup.ps1` | git clone したフォルダなら submodule を取得し、tamac.exe と yayalint を `tools/bin/` に取得する（tamac.exe は最新リリースを、GitHub が公開している SHA256 で照合して取得する。yayalint はバージョンと SHA256 を `tools/tools.json` で固定）。取得済みでも版が違えば取り直す。最後に doctor の結果を表示する | 0 成功 / 1 失敗、または必須が足りない |
| `<ps> tools/check-dic.ps1` | tamac.exe で辞書を実際に読み込み、エラーを表示する | 0 OK / 1 エラー / 3 ツール未導入 |
| `<ps> tools/check-shell.ps1` | `ssp.exe --offline-dump` でシェルを検査する（Error / Warning / Notice）。SSP 2.8.94 以降では、問題の定義位置（`shell/master/surfaces.txt:Line=123`）も表示する | 0 OK / 1 Error あり / 3 SSP が見つからない |
| `<ps> tools/lint.ps1` | yayalint で未定義・未使用の変数と関数を探す（参考情報） | 0（`-Strict` なら未定義があると 1）/ 3 |
| `<ps> tools/check.ps1` | 上の 3 つを順に実行する | 0 / 1 |
| `<ps> tools/shiori.ps1 -Eval '関数名や式'` | SSP を使わずに、tamac.exe でこのゴーストの yaya.dll に SHIORI リクエストを 1 回送る。`-Eval` は YAYA のコードを評価して結果を表示する（関数名なら返すトーク、組み込み関数なら実際の戻り値。システム辞書の `??` を使う）。`-Event <ID> -Reference '0,0,0,0,Head'` は SSP と同じ形の GET（`-Notify` で NOTIFY）、`-Request` は生のリクエスト。呼ぶたびに辞書を読み込み直し（`OnBoot` などは先に送らない）、`yaya_variable.cfg` は元に戻す | 0 / 1 失敗（辞書の読み込みエラー、エラー応答など）/ 2 処理中に YAYA がエラーを出した / 3 tamac.exe が無いか古い |
| `<ps> tools/run-ssp.ps1` | このフォルダのゴーストを SSP で直接起動し（`ssp.exe --ghost <フォルダ>`。インストール不要）、応答するまで待つ。起動中に SSP のエラーログに増えた警告・エラーを表示する（SSP 2.8.94 以降では、起動時のトークが終わるのを待ってから読む） | 0 起動した / 1 応答なし / 2 起動したが、エラーログに Error か Critical が増えた / 3 SSP が見つからない |
| `<ps> tools/sstp.ps1 -Reload ghost` | 起動中の SSP にゴーストを再読み込みさせ、その間に SSP のエラーログに増えた警告・エラー（YAYA の辞書エラーなど）を表示する | 0 / 1 エラー応答 / 2 エラーログに Error か Critical が増えた / 3 SSP に接続できない |
| `<ps> tools/sstp.ps1 -Script '\0\s[0]テスト\e'` | さくらスクリプトを実際のゴーストで再生する。SSP 2.8.94 以降では、SSP が解釈できなかったタグ（存在しないサーフェス、閉じていない `[` など）が `[GHOST/Script]` のエラーとして表示され（`Option: strict`）、ログはゴーストが話し終わるのを待ってから読む | 同上 |
| `<ps> tools/sstp.ps1 -Event OnAiTalk` | イベントを発生させる（この例はランダムトーク）。応答の `Script:` に、ゴーストが実際に返したスクリプトが入る。そのスクリプトも `-Script` と同じように検査する（SSP 2.8.94 以降） | 同上 |
| `<ps> tools/sstp.ps1 -Execute GetStatus` | ゴーストの今の状態（`talking`、`choosing`、`online`、`opening(...)` などのカンマ区切り。当てはまるものが無ければ空）を表示する（SSP 2.8.94 以降） | 0 / 1 / 3 |
| `<ps> tools/ssp-log.ps1` | 起動中の SSP のログを表示する。読み取りのみ。既定はこのゴーストのエラーログで、`-Kind script` で再生されたスクリプト（ほかに `network` / `update`）、`-All` で発信元を問わず全部、`-Json` で機械向けの出力 | 0 / 1 SSP が developer.log に未対応 / 2 Error か Critical がある / 3 SSP に接続できない |
| `<ps> tools/build-nar.ps1` | `build/<directory>.nar` を作る（`-ListOnly` で中身の一覧だけ表示） | 0 / 1 |
| `<ps> tools/update-yaya.ps1` | yaya.dll を最新リリースに更新する。辞書チェックに失敗したら元に戻す（`-DryRun` で確認のみ） | 0 / 1 |
| `<ps> tools/update-devkit.ps1` | 開発キットだけを最新版に更新する（`-DryRun` で確認のみ、`-Ref` で版を指定）。別の YAYA ゴーストにキットを入れるときは `-Target <そのゴーストのフォルダ>` | 0 / 1 失敗 / 2 マージ待ちの `.devkit-new` がある |

SSP の場所は次の順に探す: `-SspPath` 引数 → 環境変数 `SSP_PATH` → `tools/local.json` の `sspPath`（`tools/local.example.json` を複製して作る）→ SSP にインストールされたフォルダなら `../../ssp.exe` → `.nar` のファイル関連付け。

## 初回セットアップ（エージェントが代行する）

作者には創作に集中してもらい、環境づくりのような決まった作業はエージェントが引き受ける。ユーザーに「セットアップして」と頼まれたとき、または `tools/doctor.ps1` で足りないものが見つかったときは、次の順に進める。

1. `tools/doctor.ps1 -Json` で診断する。各項目に `level`（`required` / `recommended` / `optional`）、用途、直し方が入っている。
2. 足りないアプリがあれば、何に使うかを一言で説明して入手を提案する。**アプリのインストールは、必ずユーザーの了承を得てから行う。**
   - Git（推奨）: 変更履歴と GitHub での自動チェック・リリース。winget があれば `winget install --id Git.Git -e`
   - SSP 2.8.94 以降（推奨）: シェルのチェックと、実際のゴーストでの確認。https://ssp.shillest.net/ から入手してもらう。入っているのに見つからない場合は、場所を聞いて `tools/local.json` に書く。古い版でも動くが、シェルの問題の位置、再生したスクリプトの検査、トークが終わるのを待ってからのログの確認が使えないので、更新を提案する
   - Node.js 20 以上（任意）: 仕様検索 MCP。winget があれば `winget install --id OpenJS.NodeJS.LTS -e`
   - インストールした直後は PATH が反映されず、ターミナルやエージェントの再起動が必要なことがある
3. `tools/setup.ps1` を実行する（submodule の取得と、チェック用ツールのダウンロード）。
4. `tools/check.ps1` でチェックが通ることを確かめる。
5. `GHOST.md` がまだ書かれていなければ、辞書、`descript.txt`、`surfaces.txt` を読んで下書きし、作者に確かめてもらう。
6. 望まれたら `tools/run-ssp.ps1` でゴーストを起動して見せる。
7. 次にできること（トークを書く、テンプレートから独立したゴーストを作る）を案内する。

## 作業のルール

1. **辞書や `ghost/master/*.txt` を変更したら、必ず `tools/check-dic.ps1` を通す。** エラーが残ったゴーストは緊急モードで起動し、ほとんど話さなくなる。`shell/` を変更したら `tools/check-shell.ps1` も通す。辞書の関数を書いたり直したりしたら、`tools/shiori.ps1 -Eval '関数名'` で呼び出して、返すスクリプトと、実行時のエラー（存在しない関数の呼び出しなど。読み込みのチェックでは見つからない）も確かめる（ファイルの書き込みや外部プログラムの実行をする関数は本当に動くので、中身を読んでから呼ぶ）。SSP で動かして確かめるときは、`tools/sstp.ps1` や `tools/run-ssp.ps1` が表示する SSP のエラーログ（終了コード 2）も見る。SSP 2.8.94 以降では、書いたトークを `tools/sstp.ps1 -Script` や `-Event` で再生すると、解釈できなかったタグが `[GHOST/Script]` のエラーとして出るので、それも直す。
2. 仕様（さくらスクリプトのタグ、SHIORI イベントの名前と Reference、YAYA の関数、descript.txt や surfaces.txt の項目）を**推測で書かない**。確かでないときは「仕様の調べ方」に従って確かめる。
3. 文字コードは UTF-8（BOM なし）、改行は LF、辞書のインデントはタブ（`.editorconfig` 参照）。ただし `readme-aya.txt` と `readme-yaya.txt` は Shift_JIS なので、文字コードを変えない。
4. 編集しないもの: `ghost/master/dic/system/` または `ghost/master/system/`（システム辞書の submodule。変更が必要なら上流の yaya-dic に提案する）、`yaya.dll`、実行時に作られるファイル。
5. 開発キットのファイル（上の「開発キットとファイルの持ち主」）は、頼まれない限り変えない。`tools/` に自分のスクリプトを足すときは、Windows PowerShell 5.1 でも動くように書き、**ASCII 文字だけで書く**（BOM のないファイルに日本語を書くと 5.1 で文字化けするため）。
6. 既存のトークや作者が書いた台詞を、頼まれていないのに大量に書き換えたり消したりしない。未使用の関数や変数が見つかっても、報告するだけにする。
7. シェルの画像は、`GHOST.md` でライセンスを確かめるまで編集しない（改変を禁じているシェルがある）。
8. アプリのインストール、SSP へのゴーストのインストール、yaya.dll や開発キットの更新、リリース、ネットワーク更新ファイルのアップロードなど、手元のファイル編集を超える操作は、作者の確認を取ってから行う。

## YAYA 辞書の書き方の要点

- 関数は `関数名 { ... }` で定義する。`{ }` の中に文字列を並べると、呼ばれるたびにその中から 1 つが選ばれる。`関数名 : nonoverlap { ... }` とすると、一巡するまで同じものを選ばない。
- `--` を挟むと、前後のブロックの結果をつなげて 1 つの出力にする。
- 文字列:
  - `"..."` の中では `%(変数名)` や `%(関数名)` が展開される。`"` そのものは `""` と重ねて書く。
  - `'...'` の中は展開されない。
  - テンプレートから作ったゴーストでは、ランダムトーク本体の `RandomTalkEx` は `'...'` で書くが、呼び出し側の `RandomTalk` が展開するので `%(username)` などが使える。
  - バックスラッシュはエスケープ文字ではない。`'\0\s[0]'` はそのままさくらスクリプトとして出力される。
- 行末に `/` を書くと、次の行に続けて書ける。
- `_` で始まる変数はローカル変数。それ以外はグローバル変数で、`yaya_variable.cfg` に自動で保存され、次に起動したときに戻る。
- イベントの引数は `reference[0]`、`reference[1]`、…（`reference0` の形でも読める）。
- 制御構文は `if` / `elseif` / `else`、`case 値 { when 'a' { ... } others { ... } }`、`while`、`for`、`foreach`。条件に `( )` は要らない。
- コメントは `//` と `/* */`。
- チェイントーク: トークの最後に `\e:chain=ラベル` と書くと、その後のランダムトークが `ラベル {{CHAIN ... }}CHAIN` に並べたトークから順に選ばれる。`{ }` で囲んだ部分はその中からランダムに選ばれる。
- 新しいイベントに反応させるには、イベント名と同じ名前の関数を書く。どの辞書ファイルに書くかは `GHOST.md` の「イベントと辞書ファイルの対応」を見る。`yaya.txt` が読み込むフォルダに新しい `.dic` ファイルを置いた場合も自動で読み込まれる。
- 関数の一覧や細かい文法は YAYA Wiki で確かめる。

## トーク（さくらスクリプト）の書き方

間の取り方、改行の入れ方、話し手の交代などの決まりと例は、`GHOST.md` の「トークの書き方」にある。どのゴーストにも共通すること:

- 話し始める側のスコープ（`\0` / `\h`、`\1` / `\u`）と表情（`\s[番号]`）を最初に指定する。サーフェス番号は `GHOST.md` の表にあるものだけを使う。
- `\w1` はおよそ 50 ミリ秒の待ち、`\n` は改行、トークの最後は `\e`。

AI がやりがちな失敗:

- 1 つの台詞が長すぎる。吹き出しの幅はバルーンによって違うので、全角 20〜25 字くらいを目安に `\n` で区切り、仕上がりは `tools/sstp.ps1` を使って実際の画面で確かめてもらう。
- 存在しないサーフェス番号を使う。表情を増やすにはシェルの画像が必要になる。
- `'...'` の中に `%(変数)` を書いて、展開されない（`RandomTalkEx` は例外）。
- 話し手の口調が混ざる（`GHOST.md` の人物像と違う一人称や口調で話す）。
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

YAYA の関数の戻り値や細かい挙動は、調べたうえで、`tools/shiori.ps1 -Eval` でこのゴーストの yaya.dll に実際に評価させて確かめられる（例: `tools/shiori.ps1 -Eval "SPLIT('a,b', ',')"`）。

調べものは、小さく速いモデルのサブエージェントに任せるとよい（Claude Code では `ukagaka-researcher`）。

## テンプレートから独立させるとき

テンプレートとして配られているゴーストを改造して、自分のゴーストとして配布するときは、少なくとも次を変える。テンプレートに固有の項目は、テンプレートの `GHOST.md` に書かれている（Claude Code では `/new-ghost`）。

- [ ] `ghost/master/descript.txt`: `name`、`sakura.name`、`kero.name`、`craftman`（半角英数）、`craftmanw`、`craftmanurl`
- [ ] `install.txt`: `name`、`directory`（インストール先のフォルダ名。半角英数で、他のゴーストと重ならないもの）
- [ ] ネットワーク更新の URL（`On_homeurl`）。自分の URL に変えるか、更新しないなら関数ごと消す。**元の URL のまま配布すると、元のゴーストの更新で、改造した内容が上書きされてしまう。**
- [ ] シェル: 元のシェルの利用条件を `GHOST.md` で確かめる。改変した画像の配布が許されていなければ、自作のシェルか利用許可のあるシェルに差し替え、シェルの `descript.txt`（`name`、`craftman` など）も変える。
- [ ] `README.md`、`thumbnail.pnr`、`delete.txt`（元のゴーストの更新用なので、自分のゴーストに合わせて見直す）
- [ ] 名前やキャラクター設定に関わる台詞（初回起動の自己紹介、ランダムトーク、マウスへの反応など）
- [ ] `GHOST.md` を、自分のゴーストの内容に書き直す
- [ ] GitHub の自動リリースなど、元のゴーストから引き継いだワークフロー
- [ ] 元にしたテンプレートのクレジット（義務ではないが、慣習としておすすめ）

## AI を使ったゴースト制作のガイドライン

伺かは、作者が手作りしたゴーストを配り合う文化の上に成り立っている。AI エージェントは次を守ること。

- 他のゴーストの台詞、シェル画像、辞書を、コピーしたり言い換えたりして持ち込まない。参考にしてよいのは、公開されている仕様と、このゴースト自身の辞書（元にしたテンプレートを含む）だけ。
- 実在の人物を模したキャラクターを作らない。既存の作品の二次創作は、作者が原作のガイドラインを確かめた上で行う。AI の側から既存のキャラクターを持ち込まない。
- 生成したトークは、作者が読んで確かめてから公開するものとして書く。数を増やすための大量生成はせず、キャラクターの口調と設定の一貫性を優先する。
- AI の手を借りて作ったことを、readme などに書いておくことをすすめる（義務ではない）。配布サイトや交流の場に AI 生成物についての決まりがあるときは、作者に確認してもらう。
- ユーザーの PC に影響する処理（外部プログラムの実行、ファイルの書き込みや削除、ネットワーク通信、`SHIORI3FW.ENABLE_DELAYED_EVAL` の有効化など）は、作者にはっきり頼まれない限り書かない。

## ツールごとの補足

- Claude Code: `CLAUDE.md` がこのファイルと `GHOST.md` を読み込み、編集後の自動チェック、スキル、調査用サブエージェントを追加している。
- それ以外のツール: `GHOST.md` を自分で読む。編集後の自動チェックがないので、辞書やシェルを変更するたびに `tools/check-dic.ps1` や `tools/check-shell.ps1` を自分で実行する。
