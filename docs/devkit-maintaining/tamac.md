# tamac

- tamac.exe の `-r`（v1.0.3.25 以降。`tools/shiori.ps1`）:
  - 標準入力を EOF まで読んでリクエストにし（改行を CRLF にそろえ、終わりの空行を足し、先頭の BOM を外す）、応答を標準出力に、ログをすべて標準エラー出力に出す。1 回に送れるのは 1 リクエストだけ。
  - dll は絶対パスで渡す（`Invoke-DevkitTamac`）。相対パスだと `yaya.txt` を探すフォルダが空になり、読み込めない。
  - 終了コード: 0 / 1（dll が読めない、空のリクエスト、空の応答）/ 2（読み込み中か処理中に `-l` 以上のログ。応答は出る）。環境変数 `GITHUB_ACTIONS` があると `--ci` の出力に切り替わるので、`shiori.ps1` は子プロセスに渡さない。
  - ログには、読み込み（`// request` の次の行がゴーストのフォルダ）、送ったリクエスト、解放の順に、`// request` と本文が並ぶ。`shiori.ps1` は、送ったリクエストの 1 行目より前のエラーを読み込みエラーとして扱う。緊急モードでも `?? 1+2` に答える（konnoyayame で確認）ので、応答だけでは見分けられない。
  - `?? コード` には、yaya-dic の `shiori3.dic`（`AyaTest.Eval`）が `!! 結果` で答える。行ごとに `EVAL` して結果をつなげ、配列は `,` で JOIN する。ローカル変数は次の行に残らない。`EVAL` に失敗すると結果はコードそのものになり、E0071 などが `shiori3.dic` の行で記録される。
  - システム辞書は、リクエストの `Charset` で `charset.output` を切り替える（`SETSETTING`）。`-Event` は `yaya.txt` の `charset.output` を送り、UTF-8 を決め打ちしない。`Sender` は `basewarename` になり、テンプレートは `SSP` かどうかで分岐するので、`SSP` を送る。
  - YAYA は解放のときに `yaya_variable.cfg` を保存するので、`Invoke-DevkitTamac` が前後で退避して戻す（`check-dic.ps1` も同じ）。
  - `.claude/settings.json` の許可リストに入れている。`-Eval` は任意の YAYA のコード（`EXECUTE`、`FWRITE` など）を実行できるが、辞書の関数を試すたびに確認が出ると使われなくなるため、使いやすさを優先した。ファイルの書き込みや外部プログラムの実行をする関数は中身を読んでから呼ぶことを、`AGENTS.md` と `docs/agents/workflows/check.md` に書いている。
