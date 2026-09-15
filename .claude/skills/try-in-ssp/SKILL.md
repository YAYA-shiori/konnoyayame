---
name: try-in-ssp
description: 起動中の SSP に SSTP を送り、書いたトークやイベントの反応を実際のゴーストで再生して確かめる。SSP のエラーログから、実行時の辞書エラーなども拾う。トークを追加・修正した後に、表示や掛け合いのテンポを見たいときに使う。
argument-hint: "[試したい関数名・イベント名・さくらスクリプト]"
---

# SSP で実際に動かして確かめる

前提: SSP で、このフォルダのゴーストが動いていること。

関数が返すスクリプトや実行時のエラーだけを見るなら、SSP は要らない。`powershell -NoProfile -ExecutionPolicy Bypass -File tools/shiori.ps1 -Eval '関数名'`（イベントなら `-Event OnMouseDoubleClick -Reference '0,0,0,0,Head'`）で、tamac.exe がその場で辞書を読み込んで答える。SSP では、表示、表情、掛け合いのテンポ、SSP が解釈できないタグを確かめる。

0. 動いていなければ `powershell -NoProfile -ExecutionPolicy Bypass -File tools/run-ssp.ps1` で起動する。`ssp.exe --ghost <このフォルダ>` を使うので、SSP にインストールしなくても作業中のフォルダがそのまま動く。ユーザーのデスクトップにゴーストが現れるので、一言断ってから起動する。起動中に SSP のエラーログに増えた警告・エラーも表示される。
1. 辞書を変更したなら、先に `tools/check-dic.ps1` を通す。
2. 変更を読み込ませる:
   `powershell -NoProfile -ExecutionPolicy Bypass -File tools/sstp.ps1 -Reload ghost`
   - 再読み込みの後、SSP のエラーログに増えたものが表示される。`[Critical] ... error E0094 ...` のような辞書エラーが出たら、ゴーストは緊急モードになっている（イベントに `204 No Content` しか返さなくなる）。直してからもう一度読み込ませる。
3. 試したい内容に合わせて送る。
   - さくらスクリプトをそのまま再生する（1 行で書き、`\` が解釈されないようシングルクォートで囲む。サーフェス番号は `GHOST.md` の表にあるものを使う）:
     `tools/sstp.ps1 -Script '\0\s[0]テストだよ。\w8\1\s[10]おう。\e'`
   - イベントを発生させる:
     - ランダムトーク: `tools/sstp.ps1 -Event OnAiTalk`
     - つつき反応（`MouseDoubleClick0Head` など）: `tools/sstp.ps1 -Event OnMouseDoubleClick -Reference '0,0,0,0,Head'`（Reference3 がスコープ、Reference4 が当たり判定の名前）
   - 特定の関数の中身を試すときは、その関数のトークを `-Script` に貼って再生する。
   - `-Event` の応答の `Script:` ヘッダーには、ゴーストが実際に返したスクリプトが入る。どの候補が選ばれたか、`%()` がどう展開されたかをここで確かめられる。
   - どの場合も、送った後に SSP のエラーログに増えた Warning 以上が表示される（Info と Notice は件数だけ）。SSP 2.8.94 以降では、ゴーストが話し終わるのを待ってから読む（`\x` のクリック待ちなどで話し終わらないときは `-TimeoutSeconds` 秒で打ち切る）。
   - SSP 2.8.94 以降では、`-Script` と `-Event` で再生したスクリプトのうち、SSP が解釈できなかったタグが `[Error] ... [GHOST/Script] 理由 (詳細) at position 位置 : 抜粋` として出る（`Option: strict`）。位置はスクリプトの先頭を 0 とした文字数で、抜粋は問題のタグから始まる。例: `surface not found (abc)`（存在しないサーフェス）、`Unclosed '['`（`]` の閉じ忘れ）。`-Event` なら応答の `Script:` から、辞書のどのトークかを探して直す。
4. ゴーストの今の状態を見る（SSP 2.8.94 以降）: `tools/sstp.ps1 -Execute GetStatus`
   - `talking`（話している）、`choosing`（選択肢を待っている）、`opening(...)`（入力ボックスなどが開いている）などがカンマ区切りで返る。当てはまるものが無ければ空。
   - 次のイベントを送る前に、前のトークや入力ボックスが残っていないか確かめるのに使う。
5. SSP のログをまとめて見る（読み取りのみ）:
   - エラーログ（このゴーストの分）: `tools/ssp-log.ps1`。Info や Notice も含めて全部出る。発信元を問わず見るなら `-All`。SSP 2.8.94 以降では、シェルの問題（`[SERIKO]`）に定義位置（`shell/master/surfaces.txt:Line=123`）が付く
   - 再生されたスクリプト: `tools/ssp-log.ps1 -Kind script -Max 5`。ゴーストが自分から話したトークも、どのイベントで出たかと一緒に確かめられる
   - ログは新しいものから 50 件ほどしか残らず、直す前の古いエラーも残っている。時刻を見て、今回のものか確かめる
6. 終了コードの意味: 2 は SSP のエラーログに Error か Critical が増えた（`sstp.ps1`、`run-ssp.ps1`）、またはそれが表示された（`ssp-log.ps1`）。3 は SSP に接続できない（起動していない）。404 が返ったらゴーストが見つからない（`-Ghost <\0 の名前>` か `-AnyGhost` を指定）。
7. 吹き出しからのはみ出し、改行位置、表情はユーザーの画面にしか出ない。何を再生したかを伝えて、見た目を確認してもらう。

補足: `tools/sstp.ps1` は、`EXECUTE GetFMO` で調べたゴーストの識別 ID を `ID` ヘッダに付けて送る（Owned SSTP）。付けないと SSP は外部のプログラムからの要求として扱い、`\![reload,ghost]` などを黙って無視する（応答は 200 のまま）。`-AnyGhost` のときは ID を付けない。

$ARGUMENTS
