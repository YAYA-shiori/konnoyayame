@AGENTS.md

# Claude Code 向けの補足

## 編集後の自動チェック（hooks）

- `.claude/settings.json` の PostToolUse hook（`tools/hooks/post-edit.ps1`）により、`ghost/` の `.dic` / `.txt` を編集すると `tools/check-dic.ps1` が、`shell/` の `.txt` を編集すると `tools/check-shell.ps1` が自動で実行される。
- チェックに失敗すると、その出力が返ってくる。次の作業に進む前に直すこと。
- ツールが入っていない、または SSP が見つからない場合は、何も言わずにスキップされる。自動チェックが動いていないようなら `tools/setup.ps1` を実行する（ダウンロードを伴うので、ユーザーに一言断る）。

## スキル

| スキル | 用途 |
|---|---|
| `/ghost-check` | 辞書・シェル・lint をまとめてチェックし、問題を直す |
| `/try-in-ssp` | 起動中の SSP でトークやイベントを再生して確かめる |
| `/build-nar` | nar を作る（ユーザーが呼び出す） |
| `/update-yaya` | yaya.dll を更新する（ユーザーが呼び出す） |
| `/new-ghost` | テンプレートから独立したゴーストを作る（ユーザーが呼び出す） |

## 仕様の調査

- さくらスクリプト、SHIORI イベント、YAYA の関数、SSTP、設定ファイルの書式などの確認は、サブエージェント `ukagaka-researcher`（haiku）に任せる。メインの会話で長い Web 検索をしない。
- MCP サーバー `ukagaka-doc`（`.mcp.json`）は、初めて使うときに承認が必要。Node.js 20 以上が要る。

## コマンドの実行

- `tools/*.ps1` は、Bash ツールからでも PowerShell ツールからでも `powershell -NoProfile -ExecutionPolicy Bypass -File tools/<name>.ps1 ...` の形で呼ぶ。この形のチェック用スクリプトは `.claude/settings.json` で許可済み。
- さくらスクリプトを引数で渡すときは、`\` が解釈されないようにシングルクォートで囲む。
