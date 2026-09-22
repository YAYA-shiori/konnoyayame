# 初回セットアップの代行

## 使うとき

作者が「セットアップして」「始めたい」「準備して」「環境を整えて」「足りないものを入れて」と言ったとき。起動時の環境チェックで不足を伝えられたときも、ほかの作業に入る前にこれを提案する。

作者には創作に集中してもらい、決まった作業はこちらで引き受ける。ただし、アプリのインストールなど作者の PC に関わる操作は、何のために必要かを説明して了承を得てから行う。

## 手順

1. 診断する: `powershell -NoProfile -ExecutionPolicy Bypass -File tools/doctor.ps1 -Json`
   - 各項目の `level` は `required`（ないとチェックが動かない）、`recommended`、`optional`。`purpose` が用途、`fix` が直し方。
2. 足りないアプリがあれば、用途を一言で説明して、入手を提案する。**インストールは必ず了承を得てから行う。**
   - **Git**（推奨）: 変更履歴と GitHub での自動チェック・リリース。`fix` に winget のコマンドがあれば、了承を得てから実行する（`winget install --id Git.Git -e`）。winget がなければダウンロード先を案内する。
   - **SSP**（推奨）: 2.9.02 以降を使う。https://ssp.shillest.net/ から入手してもらう。すでに入っているのに見つからない場合は、`ssp.exe` の場所を聞いて `tools/local.json` に `{"sspPath": "C:\\path\\to\\ssp.exe"}` と書く（`tools/local.example.json` 参照）。見つかったのに `ssp` が ok でないときは版が古いので、更新を提案する（開発キットのスクリプトはこの版を前提にしていて、古い版では動かなかったり、問題を見落としたりする）。
   - アプリを入れた直後は PATH が反映されていないことがある。見つからないままなら、ターミナル（エージェント）を起動し直してもらう。
3. `powershell -NoProfile -ExecutionPolicy Bypass -File tools/setup.ps1` を実行する。git clone したフォルダなら submodule を取得し、チェック用ツールを GitHub からダウンロードする（ダウンロードを伴うことを一言伝える）。最後に doctor の結果が出るので、`required` がすべて ok になったか確かめる。
4. `powershell -NoProfile -ExecutionPolicy Bypass -File tools/check.ps1` で、辞書・シェル・lint のチェックが通ることを確かめる。
5. doctor の `ghost-profile` が ok でなければ（`GHOST.md` が無い、または先頭に `<!-- devkit:ghost-template -->` が残っている）、`GHOST.md` を下書きする。
   - 無ければ `tools/devkit/seed/GHOST.md` を複製して始める。
   - `ghost/master/descript.txt`、`ghost/master/yaya.txt`、辞書（`dic/` 以下のファイル名と、どのイベントがどこにあるか）、`shell/master/surfaces.txt` と `surfacetable.txt`、`shell/master/descript.txt`（シェルの作者とライセンス）、既存のトークを読んで埋める。
   - 「使えるサーフェス」の表情の説明は、`surfacetable.txt` や既存のトークで使われている場面に加えて、画像を読めるなら実際の見た目で確かめる: `powershell -NoProfile -ExecutionPolicy Bypass -File tools/dump-surface.ps1 -Surface 0-9 -Backlog -Sheet`（`sheet.png` に顔のまわりが番号付きで並ぶ。番号は surfaces.txt に合わせる。`\1` 側は `-Scope 1` を付ける）。当たり判定の名前と位置は、`-Surface 0 -Collision` で見られる。
   - 人物像やトークの決まりは、既存の台詞から読み取れる範囲にとどめ、推測で足さない。わからない欄は空けたまま、作者に聞く。
   - 下書きを見せて確かめてもらい、了承を得てから書き込む。書き終えたら先頭のマーカーの 2 行を消す。
6. 作者が望めば `powershell -NoProfile -ExecutionPolicy Bypass -File tools/run-ssp.ps1` でゴーストを起動して見せる（デスクトップにゴーストが現れる。試験用の SSP が別に立つので、見せ終わったら `tools/run-ssp.ps1 -Stop` で閉じてよいか聞く）。
7. 最後に次のことを伝える。
   - Claude Code では、編集後の自動チェック（hooks）と仕様検索 MCP（ukagaka-doc）は、起動し直すと有効になる。MCP は初回に承認を求められる。ほかのエージェントで仕様検索 MCP を使うときは、`AGENTS.md` の「仕様の調べ方」に沿って、そのツールの設定に登録する。
   - 次にできること。作者はコマンド名を知らないので、**「〜と頼んでください」の形で 2〜3 個示す**。例:「トークを書いて」「SSP で動かして見せて」「自分のゴーストにしたい」。

## 関連

- 手順書の一覧と、作者の言い回しとの対応: `AGENTS.md` の「こう頼まれたら」
- トークを実機で確かめる: `docs/agents/workflows/try-in-ssp.md`
- テンプレートから自分のゴーストを作る: `docs/agents/workflows/new-ghost.md`
