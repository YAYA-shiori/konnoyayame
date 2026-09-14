---
name: try-in-ssp
description: 起動中の SSP に SSTP を送り、書いたトークやイベントの反応を実際のゴーストで再生して確かめる。トークを追加・修正した後に、表示や掛け合いのテンポを見たいときに使う。
argument-hint: "[試したい関数名・イベント名・さくらスクリプト]"
---

# SSP で実際に動かして確かめる

前提: SSP で、このフォルダのゴーストが動いていること。

0. 動いていなければ `powershell -NoProfile -ExecutionPolicy Bypass -File tools/run-ssp.ps1` で起動する。`ssp.exe --ghost <このフォルダ>` を使うので、SSP にインストールしなくても作業中のフォルダがそのまま動く。ユーザーのデスクトップにゴーストが現れるので、一言断ってから起動する。
1. 辞書を変更したなら、先に `tools/check-dic.ps1` を通す。
2. 変更を読み込ませる:
   `powershell -NoProfile -ExecutionPolicy Bypass -File tools/sstp.ps1 -Reload ghost`
3. 試したい内容に合わせて送る。
   - さくらスクリプトをそのまま再生する（1 行で書き、`\` が解釈されないようシングルクォートで囲む）:
     `tools/sstp.ps1 -Script '\0\s[5]テストだよ。\w8\1\s[10]おう。\e'`
   - イベントを発生させる:
     - ランダムトーク: `tools/sstp.ps1 -Event OnAiTalk`
     - つつき反応（`MouseDoubleClick0Head` など）: `tools/sstp.ps1 -Event OnMouseDoubleClick -Reference '0,0,0,0,Head'`（Reference3 がスコープ、Reference4 が当たり判定の名前）
   - 特定の関数の中身を試すときは、その関数のトークを `-Script` に貼って再生する。
   - `-Event` の応答の `Script:` ヘッダーには、ゴーストが実際に返したスクリプトが入る。どの候補が選ばれたか、`%()` がどう展開されたかをここで確かめられる。
4. 終了コードの意味: 3 は SSP に接続できない（起動していない）。404 が返ったらゴーストが見つからない（`-Ghost <\0 の名前>` か `-AnyGhost` を指定）。
5. 吹き出しからのはみ出し、改行位置、表情はユーザーの画面にしか出ない。何を再生したかを伝えて、見た目を確認してもらう。

$ARGUMENTS
