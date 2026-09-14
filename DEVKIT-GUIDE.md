# DEVKIT-GUIDE.md

AI コーディングエージェントでゴーストを開発するための開発キットの、使い方の説明です（ゴーストの作者向け）。

このファイルは開発キットの一部で、キットを更新すると新しい版に置き換わります。ゴーストの紹介や、このゴーストだけの説明は、ゴーストの README などに書いてください。

## 開発キットについて

このゴーストのフォルダには、AI コーディングエージェント（Claude Code、Codex、GitHub Copilot など）で開発するための開発キットが入っています。
git で管理しているフォルダでも、nar を SSP にインストールしたフォルダ（`<SSP>/ghost/<フォルダ名>/`）でも使えます。

- `DEVKIT-GUIDE.md` : このファイル。作者向けの使い方
- `AGENTS.md` : エージェント向けの指示書（構成、ルール、YAYA とさくらスクリプトの要点、独立ゴーストにするときのチェックリスト）。人が読んでもわかるように書いてあります
- `GHOST.md` : このゴーストに固有の情報（キャラクター、サーフェス、ライセンス、辞書の構成）。エージェントは作業の前に必ず読みます
- `CLAUDE.md` / `.claude/` / `.mcp.json` : Claude Code 用の設定（編集後の自動チェック、スキル、仕様調査用サブエージェント、ドキュメント検索 MCP）
- `tools/` : 辞書チェック（tamac）、シェルチェック（SSP）、yayalint、SSTP での実機確認と SSP のログ取得、nar 作成、yaya.dll と開発キットの更新のスクリプト

AI エージェントを使わずに、`tools/` のスクリプトだけを使うこともできます。

キットの入っていない YAYA ゴーストにキットを入れる手順は、このファイルの最後の「別の YAYA ゴーストに開発キットを入れる」にあります。

## あらかじめ入れておくもの

開発キットは Windows を前提にしています（YAYA、SSP、辞書チェックに使う tamac.exe が Windows 用のため）。

| もの | 必要か | 用途 | 入手先 |
|---|---|---|---|
| AI コーディングエージェント | AI に頼むなら必須 | Claude Code、Codex、GitHub Copilot など。キットの指示書とスキルに沿って、開発を手伝います | 各ツールの案内に従ってください |
| PowerShell | 必須 | `tools/` のスクリプト | Windows には最初から入っています（Windows PowerShell 5.1）。mac・Linux は下の「mac・Linux で使う場合」 |
| SSP | 推奨 | シェルのチェック、実際のゴーストでの確認 | https://ssp.shillest.net/ |
| Git | 推奨 | 変更履歴、GitHub での自動チェック、システム辞書（submodule）の取得 | https://git-scm.com/ |
| Node.js 20 以上 | 任意 | 仕様を検索する MCP サーバー（ukagaka-doc） | https://nodejs.org/ |

Windows で最初に入れておく必要があるのは、AI エージェントだけです。SSP、Git、Node.js は、AI エージェントに「セットアップして」と頼めば、足りないものを調べて入手方法を案内します（インストールは確認を取ってから行います）。

### mac・Linux で使う場合

PowerShell 7 を入れてください。mac は、Microsoft の案内（https://learn.microsoft.com/powershell/scripting/install/install-powershell-on-macos ）にあるリリースページから `.pkg` をダウンロードして開くのが簡単です。Linux は、同じ Microsoft のドキュメントにある Linux 向けの手順を見てください。入れた後は、ターミナルで `pwsh` と打つと起動します。

ただし、mac・Linux で使えるのは開発キットの一部だけです。

- 使えるもの: `AGENTS.md` と `GHOST.md` に沿った AI エージェントでの辞書の編集、開発キットの導入と更新（`tools/update-devkit.ps1`）、nar の作成（`tools/build-nar.ps1`）
- 使えないもの: 辞書・シェルのチェックと lint（`tools/check.ps1` など）、SSP での起動と確認（`tools/run-ssp.ps1`、`tools/sstp.ps1`、`tools/ssp-log.ps1`）、チェック用ツールの取得（`tools/setup.ps1`。取得するツールが Windows 用）、yaya.dll の更新
- Claude Code の編集後の自動チェックと起動時の診断（hooks）は Windows PowerShell（`powershell.exe`）を呼ぶので、mac・Linux ではエラーが表示されます。
- `tools/doctor.ps1` は、Windows と Windows PowerShell が無いことを「必須が足りない」と表示します。
- このファイルのコマンドにある `powershell -NoProfile -ExecutionPolicy Bypass -File` は、`pwsh -NoProfile -File` に読み替えてください。
- 辞書にエラーがあると、ゴーストは緊急モードで起動してしまいます。配布する前に、Windows でチェックしてください。
- mac・Linux での動作は、Windows ほど確かめられていません。

## はじめかた

このフォルダで AI エージェントを起動し（Claude Code なら `claude`）、「セットアップして」と頼んでください。足りないアプリ（Git、Node.js、SSP）の確認と案内、チェック用ツールの取得、動作確認までを代行します。`GHOST.md` がまだ書かれていなければ、辞書とシェルを読んで下書きも作ります（Claude Code では `/getting-started` スキル）。アプリのインストールは、確認を取ってから行います。

自分で行う場合は、次を実行してください（Windows）。

```
powershell -NoProfile -ExecutionPolicy Bypass -File tools/doctor.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/setup.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check.ps1
```

- `tools/doctor.ps1` は、必要なものがそろっているかと、足りないものの入手方法を表示します（何も変更しません）。
- `tools/setup.ps1` は、git clone したフォルダなら submodule を取得し、チェック用ツール（tamac、yayalint）をダウンロードします。
- `tools/check.ps1` は、辞書のチェック、シェルのチェック、yayalint を順に実行します。
- SSP の場所は `.nar` の関連付けなどから自動で探します。見つからない場合は環境変数 `SSP_PATH` か `tools/local.json`（`tools/local.example.json` を複製）で指定してください。
- ドキュメント検索 MCP（[ukagaka-doc-mcp](https://github.com/finelagusaz/ukagaka-doc-mcp)）には Node.js 20 以上が必要です。
- ほかのスクリプト（SSP での起動、SSTP でのトークの再生、nar の作成など）は、`AGENTS.md` の「開発コマンド」に一覧があります。

## GHOST.md を仕上げる

`GHOST.md` には、キャラクターの人物像、使えるサーフェス、シェルのライセンス、辞書の構成、トークの書き方の決まりなど、このゴーストに固有の情報を書きます。AI エージェントは作業の前に必ずこのファイルを読むので、ここが正確なほど、書かれるトークや修正がゴーストに合ったものになります。

エージェントが下書きを作ったときは、読んで直してください。書き終えたら、先頭にある `<!-- devkit:ghost-template -->` の 2 行を消します。

## 開発キットの更新

開発キットは、ゴーストの辞書やシェルとは別に更新できます。

AI エージェントに「開発キットを更新して」と頼んでください（Claude Code では `/update-devkit` スキル）。変わるファイルの一覧を見せてから、了承を得て更新します。

自分で行う場合は、次を実行してください。

```
powershell -NoProfile -ExecutionPolicy Bypass -File tools/update-devkit.ps1 -DryRun
powershell -NoProfile -ExecutionPolicy Bypass -File tools/update-devkit.ps1
```

- 辞書、シェル、`GHOST.md`、`README.md` などは変わりません。どのファイルがキットのものかは `AGENTS.md` の「開発キットとファイルの持ち主」に書いてあります。
- 自分で手を入れたキットのファイルは上書きされません。新しい版でも変わっていた場合は、新しい版が `<ファイル名>.devkit-new` として横に置かれるので、マージしてから消してください。
- `tools/devkit.lock.json` は、どの版のキットを入れたかの記録です。消さずに残し、git で管理しているならコミットしてください。
- キットは、`tools/devkit.json` の `source` に書かれた GitHub のリポジトリから取得します。

## 配布物（nar）に開発キットを含めるかどうか

そのままでは、キットのファイルも nar とネットワーク更新に入ります。ゴーストをインストールした人が、そのフォルダでそのまま AI エージェントを使って改造を始められるようにするためです。ダウンロードしたツールや各自の設定は、`.narignore` の `include:tools/devkit.narignore` の行で除外しています（この行が無いと、`tools/bin/` や `tools/local.json` が nar に入ってしまいます）。

キットを配布物に含めたくない場合は、`.narignore` に次を足してください（`.updateignore` が `.narignore` を取り込んでいれば、ネットワーク更新からも除外されます）。

```
/AGENTS.md
/CLAUDE.md
/DEVKIT-GUIDE.md
/GHOST.md
/.mcp.json
/.claude/
/.github/
/tools/
```

## 別の YAYA ゴーストに開発キットを入れる

キットの入っていない手元の YAYA ゴーストにも、開発キットだけを入れられます。辞書やシェルには手を加えません。
先に上の「あらかじめ入れておくもの」を見て、AI エージェント（自分で入れる場合は PowerShell）を用意してください。

### 入れられるゴースト

- SHIORI が YAYA で、ゴーストのフォルダに `ghost/master/descript.txt` と `ghost/master/yaya.dll` があること
- Windows であること（mac・Linux では、上の「mac・Linux で使う場合」の範囲で使えます）
- SSP にインストールしたフォルダでも、git で管理しているフォルダでもかまいません

### 入るファイル

| 区分 | ファイル | 入れるとき・更新するとき |
|---|---|---|
| キット | `AGENTS.md`<br>`CLAUDE.md`<br>`DEVKIT-GUIDE.md`<br>`.mcp.json`<br>`.claude/`<br>`.github/workflows/auto_check.yml`<br>`tools/` | 入れたときに作られ、キットを更新すると新しい版に置き換わります |
| 初回だけ作るもの | `GHOST.md`<br>`.narignore`<br>`.updateignore`<br>`.gitattributes`<br>`.editorconfig`<br>`ghost/master/yayalint_config.lua` | 無いときだけ作られます。あとはゴーストのものです |

それ以外のファイル（辞書、シェル、`descript.txt`、readme など）は変わりません。同じ名前のファイル（たとえば自分で書いた `AGENTS.md`）がすでにあるときは上書きせず、キットの版を `<ファイル名>.devkit-new` として横に置きます。

### AI エージェントに頼んで入れる

作業の前に、ゴーストのフォルダをバックアップしてください（git で管理しているなら、コミットしておけば十分です）。

1. キットを入れたいゴーストのフォルダ（`ghost` と `shell` があるフォルダ）で、AI エージェントを起動します（Claude Code なら、そのフォルダで `claude`）。
2. 次のように頼みます。

   ```
   https://github.com/YAYA-shiori/konnoyayame/blob/master/DEVKIT-GUIDE.md にある「別の YAYA ゴーストに開発キットを入れる」の手順で、このフォルダに開発キットを入れてください。
   ```

   エージェントは導入に使うスクリプトを取得し、作られるファイルの一覧を見せてから、了承を得て導入します。同じ名前のファイルがあったときは、マージを手伝います。
3. 導入が終わったら、AI エージェントを起動し直します（キットの指示書、スキル、自動チェックは、起動したときに読み込まれます）。
4. 「セットアップして」と頼みます。チェック用ツールの取得、SSP の場所の設定、動作確認に加えて、辞書とシェルを読んで `GHOST.md` の下書きを作ります（Claude Code では `/getting-started` スキル）。
5. `GHOST.md` の下書きを読んで、キャラクターの人物像、使えるサーフェス、シェルのライセンス、トークの書き方の決まりなどを直してください（上の「GHOST.md を仕上げる」）。

#### 導入を頼まれた AI エージェントへ

この手順で導入を頼まれた AI エージェントは、次を守ってください。

1. 導入先が「入れられるゴースト」の条件を満たしているか確かめる。
2. 下の「自分で入れる」の手順 1 と 2 のコマンドでスクリプトを取得し、`-DryRun` で実行する。GitHub からダウンロードすることを、先に作者に伝える。
3. 作られるファイル、`CONFLICT`（同じ名前のファイルがすでにある）、`seed`（無かったので作る）を作者に伝え、了承を得てから `-DryRun` を外して実行する。
4. `.devkit-new` ができたら、1 つずつ差分を見せ、作者のファイルの内容を活かしたマージ案を示し、了承を得てから書き込んで `.devkit-new` を消す。ゴーストだけの決まりは `GHOST.md` に移すことを提案する。
5. 下の「すでにあるファイルとの関係」に当てはまるもの（既存の `.narignore` など）があれば、対応を提案する。
6. 取得に使った一時フォルダを消し、作者に、エージェントを起動し直してから手順 4 以降に進むよう伝える。

### 自分で入れる

作業の前に、ゴーストのフォルダをバックアップしてください。

キットの入ったゴーストが手元にあれば、下の手順 1 と 4 は要りません。手順 2 と 3 のコマンドの `$installer` を、そのゴーストの `tools/update-devkit.ps1` のパスに置き換えて実行してください。キットは、そのゴーストのファイルからではなく、そのゴーストの `tools/devkit.json` の `source` に書かれたリポジトリの最新リリースから取得されます。

1. PowerShell を開き（Windows はスタートメニューの「Windows PowerShell」、mac・Linux はターミナルで `pwsh`）、次を実行して、導入に使うスクリプトを取得します。

   ```powershell
   [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
   $work = Join-Path ([IO.Path]::GetTempPath()) 'ghost-devkit'
   Remove-Item $work, "$work.zip" -Recurse -Force -ErrorAction SilentlyContinue
   Invoke-WebRequest -UseBasicParsing https://github.com/YAYA-shiori/konnoyayame/archive/refs/heads/master.zip -OutFile "$work.zip"
   Expand-Archive "$work.zip" $work
   $installer = Join-Path $work 'konnoyayame-master/tools/update-devkit.ps1'
   ```

2. 同じ PowerShell で、`-DryRun` を付けて実行します。ここでは何も書き込まず、作られるファイルの一覧だけが表示されます。`-Target` のフォルダは、キットを入れるゴーストのフォルダ（`ghost` と `shell` があるフォルダ）に置き換えてください。

   Windows:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target 'C:\SSP\ghost\myghost' -DryRun
   ```

   mac・Linux:

   ```powershell
   pwsh -NoProfile -File $installer -Target '/Users/me/ghosts/myghost' -DryRun
   ```

3. 一覧を確かめたら、`-DryRun` を外して同じコマンドをもう一度実行します。キットそのものは、配布元のリポジトリの最新リリース（自動チェックを通った版）から取得されます。最後に `merge each file below ...` と表示されたら、`.devkit-new` ができています（下の「すでにあるファイルとの関係」を見てください）。
4. 取得に使った一時フォルダは、消してかまいません（`Remove-Item $work, "$work.zip" -Recurse -Force`）。
5. その後は、上の「AI エージェントに頼んで入れる」の手順 3 から続けてください。

### すでにあるファイルとの関係

- **`AGENTS.md`、`CLAUDE.md`、`.claude/settings.json` などを自分で置いていた場合**: 上書きされず、キットの版が `<ファイル名>.devkit-new` として置かれます。見比べて、必要な部分を元のファイルにまとめてから、`.devkit-new` を消してください。AI エージェントにマージを頼むこともできます（Claude Code では `/update-devkit` スキル）。自分のゴーストだけの決まりは `GHOST.md` に移しておくと、次にキットを更新したときに衝突しません。
- **`.narignore` をすでに使っていた場合**: 上書きされません。ダウンロードしたツールや各自の設定を nar から除外するために、`.narignore` に次の 1 行を足してください。足さないと、`tools/bin/` や `tools/local.json` が nar に入ってしまいます。

  ```
  include:tools/devkit.narignore
  ```

  `.updateignore` を使っていて、その中で `include:.narignore` をしていない場合は、`.updateignore` にも同じ行を足します。
- **古い形式の `developer_options.txt` を使っている場合**: `.narignore` と両方あると、両方が処理されて紛らわしくなります。`.narignore` / `.updateignore` に移すことをおすすめします。
- **`.gitignore`**: 追記は要りません。除外が必要なものは、キットの `tools/.gitignore` と `.claude/.gitignore` で除外しています。
- **GitHub**: `.github/workflows/auto_check.yml` が入り、`main` / `master` ブランチに push するたびに辞書チェックが走ります。要らなければ消してかまいません（消したファイルは、キットを更新しても戻りません）。自動リリースのワークフローは入りません。

### 導入した後

導入先にも、この `DEVKIT-GUIDE.md` が入ります。キットの更新や、配布物（nar）にキットを含めるかどうかは、上の「開発キットの更新」と「配布物（nar）に開発キットを含めるかどうか」を見てください。

`tools/devkit.lock.json` は、どの版のキットを入れたかの記録です。消さずに残し、git で管理しているならコミットしてください。
