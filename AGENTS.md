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

## こう頼まれたら

作者は、スラッシュコマンドや決まった呼び方ではなく、「〜して」と普通の言葉で頼む。次のような依頼を受けたら、**対応する手順書を読んでから作業する**。

| 作者の言い方（例） | 読む手順書 |
|---|---|
| 「セットアップして」「始めたい」「足りないものを入れて」 | `docs/agents/workflows/setup.md` |
| 「チェックして」「エラーが出ていないか見て」「辞書のエラーを直して」 | `docs/agents/workflows/check.md` |
| 「SSP で試して」「動かして見せて」「このトークを再生して」 | `docs/agents/workflows/try-in-ssp.md` |
| 「nar を作って」「配布用のファイルを作って」「リリースしたい」 | `docs/agents/workflows/build-nar.md` |
| 「YAYA を更新して」「yaya.dll を更新して」「システム辞書を更新して」「yaya-dic を更新して」 | `docs/agents/workflows/update-yaya.md` |
| 「開発キットを更新して」「別のゴーストにキットを入れて」 | `docs/agents/workflows/update-devkit.md` |
| 「自分のゴーストを作りたい」「テンプレートから独立させたい」 | `docs/agents/workflows/new-ghost.md` |

作者はこの表を知らない。何ができるのかを聞かれたときや、セットアップを終えたときは、「〜と頼んでください」の形で例を示す。

## 資料

次の資料は、この指示書と一緒には読み込まれない。必要になったときに読む。

| 資料 | 中身 |
|---|---|
| `docs/agents/commands.md` | 開発コマンド。`tools/` のスクリプトの使い方と終了コード、SSP の探し方 |
| `docs/agents/layout.md` | ディレクトリ構成。どのファイルが何をするか、実行時に作られるもの |
| `docs/agents/devkit-files.md` | 開発キットとファイルの持ち主。どれがキットのファイルで、キットを更新すると何が起きるか |
| `docs/agents/standalone.md` | テンプレートから独立させるとき。自分のゴーストとして配布する前に変えるものの一覧 |

## 作業のルール

1. **辞書や `ghost/master/*.txt` を変更したら、必ず `tools/check-dic.ps1` を通す。** エラーが残ったゴーストは緊急モードで起動し、ほとんど話さなくなる。`shell/` を変更したら `tools/check-shell.ps1` も通す。辞書の関数を書いたり直したりしたら、`tools/shiori.ps1 -Eval '関数名'` で呼び出して、返すスクリプトと、実行時のエラー（存在しない関数の呼び出しなど。読み込みのチェックでは見つからない）も確かめる（ファイルの書き込みや外部プログラムの実行をする関数は本当に動くので、中身を読んでから呼ぶ）。SSP で動かして確かめるときは、`tools/sstp.ps1` や `tools/run-ssp.ps1` が表示する SSP のエラーログ（終了コード 2）も見る。SSP 2.8.94 以降では、書いたトークを `tools/sstp.ps1 -Script` や `-Event` で再生すると、解釈できなかったタグが `[GHOST/Script]` のエラーとして出るので、それも直す。
2. 仕様（さくらスクリプトのタグ、SHIORI イベントの名前と Reference、YAYA の関数、descript.txt や surfaces.txt の項目）を**推測で書かない**。確かでないときは「仕様の調べ方」に従って確かめる。
3. 文字コードは UTF-8（BOM なし）、改行は LF、辞書のインデントはタブ（`.editorconfig` 参照）。ただし `readme-aya.txt` と `readme-yaya.txt` は Shift_JIS なので、文字コードを変えない。
4. 編集しないもの: `ghost/master/dic/system/` または `ghost/master/system/`（システム辞書。submodule のことも普通のファイルのこともある。変更が必要なら上流の yaya-dic に提案する）、`yaya.dll`、実行時に作られるファイル。yaya.dll とシステム辞書の更新は `docs/agents/workflows/update-yaya.md` の手順で行う。
5. 開発キットのファイル（`docs/agents/devkit-files.md` の表）は、頼まれない限り変えない。`tools/` に自分のスクリプトを足すときは、Windows PowerShell 5.1 でも動くように書き、**ASCII 文字だけで書く**（BOM のないファイルに日本語を書くと 5.1 で文字化けするため）。
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

## AI を使ったゴースト制作のガイドライン

伺かは、作者が手作りしたゴーストを配り合う文化の上に成り立っている。AI エージェントは次を守ること。

- 他のゴーストの台詞、シェル画像、辞書を、コピーしたり言い換えたりして持ち込まない。参考にしてよいのは、公開されている仕様と、このゴースト自身の辞書（元にしたテンプレートを含む）だけ。
- 実在の人物を模したキャラクターを作らない。既存の作品の二次創作は、作者が原作のガイドラインを確かめた上で行う。AI の側から既存のキャラクターを持ち込まない。
- 生成したトークは、作者が読んで確かめてから公開するものとして書く。数を増やすための大量生成はせず、キャラクターの口調と設定の一貫性を優先する。
- AI の手を借りて作ったことを、readme などに書いておくことをすすめる（義務ではない）。配布サイトや交流の場に AI 生成物についての決まりがあるときは、作者に確認してもらう。
- ユーザーの PC に影響する処理（外部プログラムの実行、ファイルの書き込みや削除、ネットワーク通信、`SHIORI3FW.ENABLE_DELAYED_EVAL` の有効化など）は、作者にはっきり頼まれない限り書かない。

## ツールごとの補足

- この指示書、`GHOST.md`、`docs/agents/` 以下の文書は、どのエージェントでも同じように読める素のテキストにしてある。ツール固有の設定は、それだけでは足りないものを補うためだけに置いている。
- Claude Code: `CLAUDE.md` がこのファイルと `GHOST.md` を読み込む。加えて、編集後の自動チェックと起動時の診断（hooks、`.claude/settings.json`）、仕様調査用のサブエージェント（`.claude/agents/`）、仕様検索 MCP（`.mcp.json`）が使える。
- それ以外のツール: `GHOST.md` を自分で読む。編集後の自動チェックがないので、辞書やシェルを変更するたびに `tools/check-dic.ps1` や `tools/check-shell.ps1` を自分で実行する。`.mcp.json` と同じ MCP サーバーは、そのツールの設定に登録すれば使える（「仕様の調べ方」）。
