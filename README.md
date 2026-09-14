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
- 別の YAYA ゴーストにキットを入れるときは、`-Target <そのゴーストのフォルダ>` を付けて実行します。

# ライセンス

Public Domain (Unlicense)

煮るなり焼くなり好きにしてください。
