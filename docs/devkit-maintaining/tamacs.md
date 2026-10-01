# tamacs

yaya.dll を SSP なしで読み込むツール。`tools/check-dic.ps1`、`tools/shiori.ps1`、`tools/lint.ps1` が使う。tamac.exe（https://github.com/YAYA-shiori/tama ）を C# に移したもので、コマンドライン、出力、終了コードは tamac に合わせている。

## ビルド

- ソースは `tools/lib/tamacs.cs`。`tools/lib/common.ps1` の `Get-DevkitTamacs` が、使うときにビルドする（`tools/setup.ps1` も呼ぶ）。ダウンロードするツールを減らし、キットの更新だけで直せるようにするため、exe は配らない。
- コンパイラは Windows に入っている .NET Framework 4 の `csc.exe`（`%windir%\Microsoft.NET\Framework\v4.0.30319\`、無ければ `Framework64`）。C# 5 までしか使えないので、`$"..."`、`?.`、式形式のメンバーなどは書かない。`tools/*.ps1` と同じく ASCII 文字だけで書き、全角の文字は C# の Unicode エスケープ（バックスラッシュ、`u`、16 進 4 桁）で書く。エージェントのツールによっては、書いたエスケープが本物の文字に変わってしまうので、書いたあとで ASCII だけか確かめる。
- ソースは里々版のキット（POST_and_KOMAINU）と同じファイル。直したら両方に入れる。
- yaya.dll は 32bit なので `/platform:x86` でビルドする。呼び出す PowerShell が 64bit でも pwsh 7 でも、子プロセスとして 32bit で動く。`Add-Type` で PowerShell のプロセスに読み込む方法は、PowerShell のビット数に縛られるので使わない。
- 出力は `tools/bin/tamacs-<ソースの SHA256 の先頭 16 桁>.exe`。ソースが変わると名前が変わってビルドし直し、古いものを消す（実行中のものは消せずに残り、次のビルドで消える）。同時に 2 つのプロセスがビルドしても壊れないよう、一時ファイルに書いてから移す。ビルドは 0.5 秒ほど。
- `tools/doctor.ps1` はビルドしない（何も変えないため）。ビルド済みか、`csc.exe` があれば ok にする。
- ビルドの処理は `Get-DevkitCsTool`（`tools/bin/<名前>-<ハッシュ>.exe`）にまとめてあり、`Get-DevkitTamacs` と `Get-DevkitTamacsw` はそれを呼ぶだけ。

## tamacsw（ログ受信ウインドウ）

- `tools/lib/tamacsw.cs` は、SSP で動いている SHIORI のログを `WM_COPYDATA` で受け取って表示する GUI（`Get-DevkitTamacsw` が `/target:winexe` でビルドする）。tama と同じ `TamaWndClass` のウインドウを作るので、tama と同時には開けない。
- tamacs と同じく両方のキットで共用するが、使うのは里々版だけ（POST_and_KOMAINU の `ghost/master/receiver.bat` → `receiver.ps1`。里々は読み込まれたあと自分で `TamaWndClass` を探してログを送る）。YAYA のゴーストは tama をそのまま使うので、このキットには起動用のファイルを置かない。
- 詳しくは、POST_and_KOMAINU の `docs/devkit-maintaining/tamacs.md` の「tamacsw.exe（ログ受信ウインドウ）」。

## tamac との違い

- ログは `Set_loghandler`（YAYA が出すコールバックの口）だけで受け取る。tamac のようにメッセージ専用ウィンドウを作って `logsend(hwnd)` で渡す経路は持たない。`Set_loghandler` が無い SHIORI では、`load` を呼ばずに終了コード 3 で終わる（スクリプトは SKIPPED と表示する）。YAYA は以前から持っていて、里々は Mc201-10 から持つ（YAYA と同じ型。最初に `E_UTF8` を通知し、id は常に 0）。
  - YAYA は `loghandler` があればそれを呼び、ウィンドウには送らない（`log.cpp` の `CLog::Call_loghandler`）。
  - tamac は `load` の前に `logsend` を呼ぶので、YAYA が設定ファイルを読む前にログを始め、先頭の行が英語の既定の見出し（`// AYA request log (before loading base configure file)`）になる。tamacs ではゴーストの `messagetxt` の見出しになる。スクリプトはこの行を読まない。
- ログの文字コードの通知（mode 16 / 17 / 32）は捨てる。YAYA が通知するのはログファイルの文字コード（`basis.cpp` の `log_charset`）で、リクエストの文字コードではないため。リクエストは常に UTF-8 で送り、応答も UTF-8 として読む（tamac も、コールバックで受け取ったときは同じ）。
- 改行はすべて CRLF にそろえる。tamac は標準出力をテキストモードで開いているので、YAYA のメッセージに含まれる `\r\n` が `\r\r\n` になっていた。
- `--ci` のアノテーションは、メッセージ末尾の改行を落として 1 行にする（tamac は後ろに空行が出ていた）。
- `CI_check_failed` が無いという警告は `--ci` のときだけ出す（`tools/shiori.ps1` は `[tamacs]` の行を処理中のメッセージとして数えるため）。
- 終了コードは、`unload` まで済ませてから決める。`unload` の中で出たエラーも 2 に数える（tamac は `unload` の前に決めていた）。

## `-r` と `tools/shiori.ps1`

- 標準入力を EOF まで読んでから UTF-8 として変換し（先頭の BOM を外す）、改行を CRLF にそろえ、終わりの空行を足してリクエストにする。応答を標準出力に、ログをすべて標準エラー出力に出す。1 回に送れるのは 1 リクエストだけ。
- dll は絶対パスで渡す（`Invoke-DevkitTamacs`）。`load` には dll のフォルダを、末尾の `\` 付きで、ANSI のコードページで渡す（tamac と同じ）。
- 終了コード: 0 / 1（dll が読めない、`load` が失敗した、空のリクエスト、空の応答。`--ci` では `CI_check_failed`）/ 2（`-l` 以上のログ。応答は出る）/ 3（`Set_loghandler` が無い）。環境変数 `GITHUB_ACTIONS` があると `--ci` の出力に切り替わるので、`shiori.ps1` と `lint.ps1` は子プロセスに渡さない。
- ログには、読み込み（`// request` の次の行がゴーストのフォルダ）、送ったリクエスト、解放の順に、`// request` と本文が並ぶ。`shiori.ps1` は、送ったリクエストの 1 行目より前のエラーを読み込みエラーとして扱う。緊急モードでも `?? 1+2` に答える（konnoyayame で確認）ので、応答だけでは見分けられない。
- `?? コード` には、yaya-dic の `shiori3.dic`（`AyaTest.Eval`）が `!! 結果` で答える。行ごとに `EVAL` して結果をつなげ、配列は `,` で JOIN する。ローカル変数は次の行に残らない。`EVAL` に失敗すると結果はコードそのものになり、E0071 などが `shiori3.dic` の行で記録される。
- システム辞書は、リクエストの `Charset` で `charset.output` を切り替える（`SETSETTING`）。`-Event` は `yaya.txt` の `charset.output` を送り、UTF-8 を決め打ちしない。`Sender` は `basewarename` になり、テンプレートは `SSP` かどうかで分岐するので、`SSP` を送る。
- YAYA は解放のときに `yaya_variable.cfg` を保存するので、`Invoke-DevkitTamacs` が前後で退避して戻す（`check-dic.ps1` も同じ）。
- `.claude/settings.json` の許可リストに入れている。`-Eval` は任意の YAYA のコード（`EXECUTE`、`FWRITE` など）を実行できるが、辞書の関数を試すたびに確認が出ると使われなくなるため、使いやすさを優先した。ファイルの書き込みや外部プログラムの実行をする関数は中身を読んでから呼ぶことを、`AGENTS.md` と `docs/agents/workflows/check.md` に書いている。
