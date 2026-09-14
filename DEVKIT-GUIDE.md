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
- キットは、`tools/devkit.json` の `source` に書かれた GitHub のリポジトリから取得します。別の YAYA ゴーストにキットを入れる手順は、そのリポジトリの README にあります。

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
