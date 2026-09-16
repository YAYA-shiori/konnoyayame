# ディレクトリ構成

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
| `ghost/master/dic/system/` | システム辞書（[yaya-dic](https://github.com/YAYA-shiori/yaya-dic)。git clone したフォルダでは submodule）。ゴーストによっては `ghost/master/system/` にあり、開発キットのスクリプトはどちらにも対応している。古いゴーストでは `ghost/master/` の直下などに古い名前（`yaya_shiori3.dic` など）で置かれていることもある（`docs/agents/workflows/update-yaya.md`）。**編集しない**。更新は `tools/update-yaya.ps1` で行う |
| `ghost/master/yaya.dll` | SHIORI 本体。`tools/update-yaya.ps1` 以外で差し替えない |
| `shell/master/surfaces.txt` | サーフェス（表情、アニメーション、当たり判定）の定義 |
| `shell/master/surfacetable.txt` | サーフェス番号と表情名の一覧 |
| `shell/master/descript.txt` | シェルの情報、メニューや吹き出し位置の設定 |
| `install.txt` | インストール設定（名前とインストール先フォルダ名） |
| `.narignore` / `.updateignore` | nar / ネットワーク更新から除外するファイル。書き方は `.gitignore` と同じで、`include:ファイル名` で別のファイルを取り込める（パスはその行を書いたファイルのフォルダからの相対。取り込んだ先でも `include:` を書け、3 段まで）。キット用の除外は `tools/devkit.narignore` を取り込んでいる。SSP と `tools/build-nar.ps1` の両方が使い、どちらもルートに置いたものだけを読む（サブフォルダに置いても効かない）。古い形式の `developer_options.txt` は、併用すると両方が処理されて紛らわしいので作らない |
| `delete.txt` | ネットワーク更新のときに削除するファイル |
| `tools/` | 開発用スクリプト（一覧は `docs/agents/commands.md`） |
| `DEVKIT-GUIDE.md` | 開発キットの使い方（作者向け）。キットについて作者に説明するときは、ここを案内する |
| `docs/agents/` | エージェント向けの資料（一覧は `AGENTS.md` の「資料」）と、`workflows/` の作業手順書 |
| `CLAUDE.md`, `.claude/`, `.mcp.json` | Claude Code 用の設定（編集後の自動チェックと起動時の診断、調査用サブエージェント、仕様検索 MCP） |
| `.github/workflows/auto_check.yml` | push ごとに辞書チェック（tamac）する |

実行時に作られるもの（編集もコミットもしない）: `ghost/master/yaya_variable.cfg`（グローバル変数の保存先）、`ghost/master/profile/`、`shell/master/profile/`、`tools/bin/`（ダウンロードしたツール）、`tools/local.json`（各自の設定）、`build/`。
