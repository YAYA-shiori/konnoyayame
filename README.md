# 「YAYA」テンプレートゴースト 紺野ややめ

- original author : umeici
- change by : ukiya
- modernized by : ponapalt and contributors

https://ms.shillest.net/yayame.xhtml

# GitHubからダウンロードする方へ

GitHubのプロジェクトページ

https://github.com/YAYA-shiori/konnoyayame

からダウンロードしようとしている方は、右横のReleasesからダウンロードしてください。

このリポジトリをzipで取得しても不完全です。

# AI エージェントで開発する (Vibe Coding)

このゴーストには、AI コーディングエージェント（Claude Code、Codex、GitHub Copilot など）で開発するための開発キットが入っています。
リポジトリを clone したフォルダでも、nar を SSP にインストールしたフォルダ（`<SSP>/ghost/konnoyayame/`）でも使えます。

- `AGENTS.md` : エージェント向けの指示書（構成、ルール、YAYA とさくらスクリプトの要点、独立ゴーストにするときのチェックリスト）
- `GHOST.md` : このゴーストに固有の情報（キャラクター、サーフェス、ライセンス、辞書の構成）。自分のゴーストを作ったら、その内容に書き直します
- `CLAUDE.md` / `.claude/` / `.mcp.json` : Claude Code 用の設定（編集後の自動チェック、スキル、仕様調査用サブエージェント、ドキュメント検索 MCP）
- `tools/` : 辞書チェック（tamac）、シェルチェック（SSP）、yayalint、SSTP での実機確認と SSP のログ取得、nar 作成、yaya.dll と開発キットの更新のスクリプト

## はじめかた

このフォルダで AI エージェントを起動し（Claude Code なら `claude`）、「セットアップして」と頼んでください。足りないアプリ（Git、Node.js、SSP）の確認と案内、チェック用ツールの取得、動作確認までを代行します（Claude Code では `/getting-started` スキル）。アプリのインストールは、確認を取ってから行います。

自分で行う場合は、次を実行してください（Windows）。

```
powershell -NoProfile -ExecutionPolicy Bypass -File tools/doctor.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/setup.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check.ps1
```

- `tools/doctor.ps1` は、必要なものがそろっているかと、足りないものの入手方法を表示します（何も変更しません）。
- `tools/setup.ps1` は、git clone したフォルダなら submodule を取得し、チェック用ツール（tamac、yayalint）をダウンロードします。
- SSP の場所は `.nar` の関連付けなどから自動で探します。見つからない場合は環境変数 `SSP_PATH` か `tools/local.json`（`tools/local.example.json` を複製）で指定してください。
- ドキュメント検索 MCP（[ukagaka-doc-mcp](https://github.com/finelagusaz/ukagaka-doc-mcp)）には Node.js 20 以上が必要です。

## 開発キットの更新

開発キットは、ゴーストの辞書やシェルとは別に更新できます。このゴーストを元に自分のゴーストを作った後でも、キットの部分だけを新しくできます（Claude Code では `/update-devkit` スキル）。

```
powershell -NoProfile -ExecutionPolicy Bypass -File tools/update-devkit.ps1 -DryRun
powershell -NoProfile -ExecutionPolicy Bypass -File tools/update-devkit.ps1
```

- 辞書、シェル、`GHOST.md`、`README.md` などは変わりません。どのファイルがキットのものかは `AGENTS.md` に書いてあります。
- 自分で手を入れたキットのファイルは上書きされません。新しい版でも変わっていた場合は、新しい版が `<ファイル名>.devkit-new` として横に置かれるので、マージしてから消してください。
- 別の YAYA ゴーストにキットを入れるときは、次の「別の YAYA ゴーストに開発キットを入れる」を見てください。

# 別の YAYA ゴーストに開発キットを入れる

紺野ややめを元にしていない、手元の YAYA ゴーストにも、開発キットだけを入れられます。辞書やシェルには手を加えません。

## 入れられるゴースト

- SHIORI が YAYA で、ゴーストのフォルダに `ghost/master/descript.txt` と `ghost/master/yaya.dll` があること
- Windows であること（スクリプトは、Windows に最初から入っている PowerShell 5.1 で動きます）
- SSP にインストールしたフォルダでも、git で管理しているフォルダでもかまいません

## 入るファイル

| 区分 | ファイル | 入れるとき・更新するとき |
|---|---|---|
| キット | `AGENTS.md`、`CLAUDE.md`、`.mcp.json`、`.claude/`、`.github/workflows/auto_check.yml`、`tools/` | 入れたときに作られ、キットを更新すると新しい版に置き換わります |
| 初回だけ作るもの | `GHOST.md`、`.narignore`、`.updateignore`、`.gitattributes`、`.editorconfig`、`ghost/master/yayalint_config.lua` | 無いときだけ作られます。あとはゴーストのものです |

それ以外のファイル（辞書、シェル、`descript.txt`、readme など）は変わりません。同じ名前のファイル（たとえば自分で書いた `AGENTS.md`）がすでにあるときは上書きせず、キットの版を `<ファイル名>.devkit-new` として横に置きます。

## 手順

作業の前に、ゴーストのフォルダをバックアップしてください（git で管理しているなら、コミットしておけば十分です）。

1. PowerShell を開き、次を実行して、導入に使うスクリプトを取得します。最後の行の `C:\SSP\ghost\myghost` は、キットを入れるゴーストのフォルダ（`ghost` と `shell` があるフォルダ）に置き換えてください。`-DryRun` を付けているので、ここでは何も書き込まず、作られるファイルの一覧だけが表示されます。

   ```powershell
   [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
   $work = Join-Path $env:TEMP 'ghost-devkit'
   Remove-Item $work, "$work.zip" -Recurse -Force -ErrorAction SilentlyContinue
   Invoke-WebRequest -UseBasicParsing https://github.com/YAYA-shiori/konnoyayame/archive/refs/heads/master.zip -OutFile "$work.zip"
   Expand-Archive "$work.zip" $work
   powershell -NoProfile -ExecutionPolicy Bypass -File "$work\konnoyayame-master\tools\update-devkit.ps1" -Target 'C:\SSP\ghost\myghost' -DryRun
   ```

2. 一覧を確かめたら、`-DryRun` を外して最後の行をもう一度実行します。キットそのものは、このリポジトリの最新リリース（自動チェックを通った版）から取得されます。

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "$work\konnoyayame-master\tools\update-devkit.ps1" -Target 'C:\SSP\ghost\myghost'
   ```

   最後に `merge each file below ...` と表示されたら、`.devkit-new` ができています（下の「すでにあるファイルとの関係」を見てください）。

3. ゴーストのフォルダで AI エージェントを起動し（Claude Code なら、そのフォルダで `claude`）、「セットアップして」と頼みます。チェック用ツールの取得、SSP の場所の設定、動作確認に加えて、辞書とシェルを読んで `GHOST.md` の下書きを作ります（Claude Code では `/getting-started` スキル）。
4. `GHOST.md` の下書きを読んで、キャラクターの人物像、使えるサーフェス、シェルのライセンス、トークの書き方の決まりなどを直してください。AI エージェントは作業の前に必ずこのファイルを読むので、ここが正確なほど、書かれるトークや修正がゴーストに合ったものになります。書き終えたら、先頭にある `<!-- devkit:ghost-template -->` の 2 行を消します。
5. 取得に使った `%TEMP%\ghost-devkit` フォルダと `ghost-devkit.zip` は、消してかまいません。

導入そのものを AI エージェントに頼むこともできます。その場合は、この README の URL を示して「『別の YAYA ゴーストに開発キットを入れる』の手順で、<ゴーストのフォルダ> に入れて」と頼んでください。

## すでにあるファイルとの関係

- **`AGENTS.md`、`CLAUDE.md`、`.claude/settings.json` などを自分で置いていた場合**: 上書きされず、キットの版が `<ファイル名>.devkit-new` として置かれます。見比べて、必要な部分を元のファイルにまとめてから、`.devkit-new` を消してください。Claude Code では `/update-devkit` スキルでマージを手伝わせることができます。自分のゴーストだけの決まりは `GHOST.md` に移しておくと、次にキットを更新したときに衝突しません。
- **`.narignore` をすでに使っていた場合**: 上書きされません。ダウンロードしたツールや各自の設定を nar から除外するために、`.narignore` に次の 1 行を足してください。足さないと、`tools/bin/` や `tools/local.json` が nar に入ってしまいます。

  ```
  include:tools/devkit.narignore
  ```

  `.updateignore` を使っていて、その中で `include:.narignore` をしていない場合は、`.updateignore` にも同じ行を足します。
- **古い形式の `developer_options.txt` を使っている場合**: `.narignore` と両方あると、両方が処理されて紛らわしくなります。`.narignore` / `.updateignore` に移すことをおすすめします。
- **`.gitignore`**: 追記は要りません。除外が必要なものは、キットの `tools/.gitignore` と `.claude/.gitignore` で除外しています。
- **GitHub**: `.github/workflows/auto_check.yml` が入り、`main` / `master` ブランチに push するたびに辞書チェックが走ります。要らなければ消してかまいません（消したファイルは、キットを更新しても戻りません）。自動リリースのワークフローは入りません。

## 配布物（nar）に開発キットを含めるかどうか

そのままでは、キットのファイルも nar とネットワーク更新に入ります。ゴーストをインストールした人が、そのフォルダでそのまま AI エージェントを使って改造を始められるようにするためです。配布物に含めたくない場合は、`.narignore` に次を足してください（`.updateignore` が `.narignore` を取り込んでいれば、ネットワーク更新からも除外されます）。

```
/AGENTS.md
/CLAUDE.md
/GHOST.md
/.mcp.json
/.claude/
/.github/
/tools/
```

## 導入した後の更新

キットの更新は、ゴーストのフォルダで行います（上の「開発キットの更新」と同じです）。

```
powershell -NoProfile -ExecutionPolicy Bypass -File tools/update-devkit.ps1 -DryRun
powershell -NoProfile -ExecutionPolicy Bypass -File tools/update-devkit.ps1
```

`tools/devkit.lock.json` は、どの版のキットを入れたかの記録です。消さずに残し、git で管理しているならコミットしてください。

# ライセンス

Public Domain (Unlicense)

煮るなり焼くなり好きにしてください。
