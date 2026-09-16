# 開発キットとファイルの持ち主

このフォルダには、ゴースト本体と一緒に、AI エージェントで開発するための開発キットが入っている。キットは `tools/update-devkit.ps1` で、ゴーストとは別に更新できる。

| 区分 | ファイル | キットを更新するとき |
|---|---|---|
| キット | `AGENTS.md`、`CLAUDE.md`、`DEVKIT-GUIDE.md`、`docs/agents/`、`.mcp.json`、`.claude/`（`settings.local.json` を除く）、`.github/workflows/auto_check.yml`、`tools/`（`bin/`、`local.json`、`devkit.lock.json` を除く） | 新しい版に置き換わる。手元で変えたファイルは残り、新しい版と両方が変わっていれば、新しい版が `<ファイル名>.devkit-new` として横に置かれる |
| 初回だけ作るもの | `GHOST.md`、`.narignore`、`.updateignore`、`.gitattributes`、`.editorconfig` | 無いときだけ作られる。あとはゴーストのもの |
| ゴースト | それ以外（辞書、シェル、`README.md`、`.gitignore`、`docs/agents/` 以外の `docs/`、ほかのワークフローなど） | 触らない |

- 正確な一覧は `tools/devkit.json`、導入した版の記録は `tools/devkit.lock.json` にある。
- キットのファイルは、なるべく直接変えない。このゴーストだけの決まりは `GHOST.md` に、Claude Code の個人設定は `.claude/settings.local.json` に書く。
- `.devkit-new` ができたら、手元の変更を活かしながら中身を元のファイルにマージし、`.devkit-new` を消す（手順は `docs/agents/workflows/update-devkit.md`）。
- ルートに `DEVKIT-MAINTAINING.md` があるフォルダは、キットの配布元のリポジトリ。キットのファイルや `tools/devkit/` を変える前に `DEVKIT-MAINTAINING.md` を読む。
