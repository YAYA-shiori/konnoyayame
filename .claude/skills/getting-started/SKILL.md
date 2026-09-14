---
name: getting-started
description: 開発環境の初回セットアップを代行する。足りないアプリ（Git、Node.js、SSP）の確認と案内、submodule とチェック用ツールの取得、SSP の場所の設定、動作確認までを行う。ユーザーが「セットアップして」「始めたい」と言ったとき、または起動時の環境チェックで不足が伝えられたときに使う。
---

# 初回セットアップの代行

作者には創作に集中してもらい、決まった作業はこちらで引き受ける。ただし、アプリのインストールなどユーザーの PC に関わる操作は、何のために必要かを説明して了承を得てから行う。

1. 診断する: `powershell -NoProfile -ExecutionPolicy Bypass -File tools/doctor.ps1 -Json`
   - 各項目の `level` は `required`（ないとチェックが動かない）、`recommended`、`optional`。`purpose` が用途、`fix` が直し方。
2. 足りないアプリがあれば、用途を一言で説明して、入手を提案する。
   - **Git**: `fix` に winget のコマンドがあれば、了承を得てから実行する。winget がなければダウンロード先を案内する。
   - **SSP**: https://ssp.shillest.net/ から入手してもらう。すでに入っているのに見つからない場合は、`ssp.exe` の場所を聞いて `tools/local.json` に `{"sspPath": "C:\\path\\to\\ssp.exe"}` と書く（`tools/local.example.json` 参照）。
   - **Node.js 20 以上**: 仕様検索 MCP にだけ使う。なくても開発はできることを伝え、希望されたら Git と同じ手順で入れる。
   - アプリを入れた直後は PATH が反映されていないことがある。見つからないままなら、ターミナル（Claude Code）を起動し直してもらう。
3. `powershell -NoProfile -ExecutionPolicy Bypass -File tools/setup.ps1` を実行する。git clone したフォルダなら submodule を取得し、チェック用ツールを GitHub からダウンロードする（ダウンロードを伴うことを一言伝える）。最後に doctor の結果が出るので、`required` がすべて ok になったか確かめる。
4. `powershell -NoProfile -ExecutionPolicy Bypass -File tools/check.ps1` で、辞書・シェル・lint のチェックが通ることを確かめる。
5. doctor の `ghost-profile` が ok でなければ（`GHOST.md` が無い、または先頭に `<!-- devkit:ghost-template -->` が残っている）、`GHOST.md` を下書きする。
   - 無ければ `tools/devkit/seed/GHOST.md` を複製して始める。
   - `ghost/master/descript.txt`、`ghost/master/yaya.txt`、辞書（`dic/` 以下のファイル名と、どのイベントがどこにあるか）、`shell/master/surfaces.txt` と `surfacetable.txt`、`shell/master/descript.txt`（シェルの作者とライセンス）、既存のトークを読んで埋める。
   - 人物像やトークの決まりは、既存の台詞から読み取れる範囲にとどめ、推測で足さない。わからない欄は空けたまま、作者に聞く。
   - 下書きを見せて確かめてもらい、了承を得てから書き込む。書き終えたら先頭のマーカーの 2 行を消す。
6. ユーザーが望めば `powershell -NoProfile -ExecutionPolicy Bypass -File tools/run-ssp.ps1` でゴーストを起動して見せる（デスクトップにゴーストが現れる）。
7. 最後に次のことを伝える。
   - 編集後の自動チェックと仕様検索 MCP（ukagaka-doc）は、Claude Code を起動し直すと有効になる。MCP は初回に承認を求められる。
   - 次にできること: トークを書く・直す（`/try-in-ssp` で実機確認）、テンプレートから自分のゴーストを作る（`/new-ghost`）。
