@AGENTS.md
@GHOST.md

# Claude Code 向けの補足

## 編集後の自動チェック（hooks）

- `.claude/settings.json` の PostToolUse hook（`tools/hooks/post-edit.ps1`）により、`ghost/` の `.dic` / `.txt` を編集すると `tools/check-dic.ps1` が、`shell/` の `.txt` を編集すると `tools/check-shell.ps1` が自動で実行される。
- チェックに失敗すると、その出力が返ってくる。次の作業に進む前に直すこと。
- ツールが入っていない、または SSP が見つからない場合は、何も言わずにスキップされる。自動チェックが動いていないようなら `tools/setup.ps1` を実行する（ダウンロードを伴うので、ユーザーに一言断る）。
- 起動時には SessionStart hook（`tools/hooks/session-start.ps1`）が `tools/doctor.ps1` で環境を診断し、必須または推奨のものが足りないときだけ、その項目と直し方が伝えられる。そのときは、ほかの作業に入る前に対応をユーザーに提案する。
  - セットアップの不足、`GHOST.md` の未記入: `docs/agents/workflows/setup.md` の手順で対応する
  - `.devkit-new` の残り: `docs/agents/workflows/update-devkit.md` の手順でマージする

## 手順書

- スキル（スラッシュコマンド）は置いていない。作業の手順は、どのエージェントでも読める `docs/agents/workflows/` の手順書にあり、どの依頼でどれを読むかは `AGENTS.md` の「こう頼まれたら」にある。

## 仕様の調査

- さくらスクリプト、SHIORI イベント、YAYA の関数、SSTP、設定ファイルの書式などの確認は、サブエージェント `ukagaka-researcher`（haiku）に任せる。メインの会話で長い Web 検索をしない。
- YAYA の関数の戻り値や、辞書の関数が返すトークは、メインの会話で `tools/shiori.ps1 -Eval` を実行して実際に確かめられる（サブエージェントはコマンドを実行できない）。
- MCP サーバー `ukagaka-doc`（`.mcp.json`）は、初めて使うときに承認が必要。オンラインのサーバー（`https://ssp.shillest.net/ukadoc/mcp`）なので、インターネットへの接続が要る。

## コマンドの実行

- `tools/*.ps1` は、Bash ツールからでも PowerShell ツールからでも `powershell -NoProfile -ExecutionPolicy Bypass -File tools/<name>.ps1 ...` の形で呼ぶ。この形のチェック用スクリプトは `.claude/settings.json` で許可済み。
- さくらスクリプトを引数で渡すときは、`\` が解釈されないようにシングルクォートで囲む。
