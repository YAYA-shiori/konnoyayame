@AGENTS.md
@GHOST.md

# Claude Code 向けの補足

## 起動時の診断（hooks）

- 編集のたびに走る自動チェックは置いていない（コンテキストを無駄に消費するため）。辞書やシェルを編集したら、一区切りついたところで `tools/check-dic.ps1` や `tools/check-shell.ps1` を自分で実行する（`AGENTS.md` の作業のルート 1）。
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
- Windows の Bash ツールでは、コマンドの中の `\\` が bash に届く前に `\` 1 つになる（シングルクォートの中でも、`<<'EOF'` のヒアドキュメントでも）。`\\` を含むもの（JSON のエスケープ、正規表現、辞書の文字列）は、Write / Edit ツールでファイルに書くか、PowerShell ツールから渡す。思いがけない結果が出たら、まず書いたファイルのバイトを確かめる。
