# SSP との連携

`tools/sstp.ps1`、`tools/ssp-log.ps1`、`tools/check-shell.ps1`、`tools/run-ssp.ps1` が頼っている SSP の挙動。

- SSTP: `tools/sstp.ps1` は、`EXECUTE GetFMO` で調べたゴーストの識別 ID を `ID` ヘッダに付けて送る（Owned SSTP）。付けないと SSP は外部のプログラムからの要求として扱い、`\![reload,ghost]` などを黙って無視する（応答は 200 のまま）。
- SSP のログ: プロパティシステムの `developer.log.*` を `EXECUTE GetProperty` で読む。ログは種類ごとに新しいものから 50 件ほどしか残らず、発信元の名前は descript.txt の `name`（`sakura.name` ではない）になる。
- SSP の版: 各スクリプトは `tools/lib/common.ps1` の `$DevkitSspRecommendedVersion`（今は 2.9.02）以降を前提にし、版による分岐はしない。版を見るのは doctor だけで、それより古い版を recommended の不足として知らせる。版は `ssp.exe` のファイルバージョン（`2, 9, 1, 3000`）の上 3 つで比べる（`Get-DevkitSspVersion`）。新しい SSP の機能を使い始めたら、分岐を足さずに `$DevkitSspRecommendedVersion` を上げる。使っている機能は次のとおり。
  - `EXECUTE GetStatus`（`Get-DevkitSspStatus`）: SEND と NOTIFY は、スクリプトを再生する前に応答する。再生中は `talking` が付くので、`Wait-DevkitSspTalkEnd` でそれが消えるまで待ってからエラーログを読む。ゴーストの読み込み中は 400 が返り、`\![reload,ghost]` の後は `talking` → 400 → 200 と変わる（`Wait-DevkitSspReload`）。`tools/sstp.ps1` は要求を送る前に 1 回呼び、200 が返らなければ（読み込み中など）決まった時間だけ待つ。
  - `Option: strict`: `tools/sstp.ps1` の `-Script` と `-Event` に付ける。解釈に失敗したタグは、再生がその位置に来たときに、Error として `[GHOST/Script] 理由 (詳細) at position 位置 : 抜粋` の形で記録される（位置はスクリプトの先頭を 0 とした文字数）。
  - `\![execute,dumpballoon,フォルダ,スコープ]`（2.9.02。`tools/sstp.ps1 -Balloon`）: その時点でバルーンに描かれている内容を `balloon<スコープ>.png` に書く。キットはこう使っている（2.9.02 で確認）。
    - 撮るタイミング: `Wait-DevkitSspTalkEnd` で話し終わるのを待ってから、`\C\![execute,dumpballoon,...]...` だけのスクリプトを別の SEND で送る。先頭の `\C` を外すと、新しいスクリプトの開始でバルーンが消え、空の吹き出しが写る。`-Script` の `\e` の前に差し込む方法は、SHIORI が返すスクリプトに差し込めない `-Event` で使えないので採らなかった。話し終わらない（クリック待ち、選択肢など）ときは、新しい SEND が再生中のスクリプトを切ってしまうので撮らない。
    - 出力先: 相対パスは、そのゴーストの `ghost/master/` から解決される。SSP が管理するフォルダの外（一時フォルダなど）を指定すると、何も書かれず、エラーログにも記録されず、応答も 200 のまま。そこで、`ghost/master/devkit-balloon-<GUID>/` に書かせ（場所は GetFMO の `ghostpath` から求める。`Get-DevkitSspGhost`）、一時フォルダの `ghost-devkit/balloons-<ハッシュ>/` に移してから消す。`-AnyGhost` では `ghostpath` が分からないので使えない。
    - SEND はスクリプトの再生前に応答するので、画像ができるまで待つ。スコープの数だけそろうか、1 秒増えなくなるか、10 秒で打ち切る。吹き出しの無いスコープは何も書かず、ほかのスコープの出力は妨げない。
    - `-BalloonScope` は `[string[]]` で受けてカンマで分ける。`[int[]]` だと `-File` で渡した `0,1,2` が 1 つの文字列になり、桁区切りとして読まれて 12 になる。
    - 画像の下端の `from ghost-devkit (local)` は、SSTP の `Sender` を SSP が表示したもの。
  - `--dump-error-log`: ssp.exe の終了コードが、記録された最も重いレベルになる（0 Notice 以下 / 1 Warning / 2 Error / 3 Critical）。`tools/check-shell.ps1` はログから数えた件数と照らし合わせ、0〜3 以外は異常終了として扱う。
  - SERIKO のメッセージの定義位置（`<ファイル>:Line=<n>:`）: SSP の説明ではゴーストのフォルダからの相対パスだが、`--offline-dump` では絶対パスになる（2.8.94 で確認）。`ConvertTo-DevkitRelativeText` がどちらも `/` 区切りの相対パスにそろえ、`check-shell.ps1 -Ci` はそれを GitHub Actions の注釈の `file` と `line` にする。
- 試験用 SSP（`tools/run-ssp.ps1`）:
  - `--option readonly --sstp-listen <ポート> --ghost <フォルダ>` で起動する。readonly は `bootunlock,standalone` を含むので、起動中の SSP に処理を渡さず、別のプロセスになる。設定、起動履歴、キャッシュなどを保存せず、vanish してもゴーストのフォルダを消さない。YAYA が書く `yaya_variable.cfg` は SSP の保存とは別なので、ふだんどおり書かれる。
  - ポートは 9822〜10999 で、IPv4 と IPv6 のループバックの両方に bind できる最初のもの（`Find-DevkitSspFreePort`）。9801、9821、11000 は伺かのほかのプログラムの既定値なので避ける。
  - 起動した SSP のポート、PID、プロセスの開始時刻、ゴーストのフォルダを、一時フォルダの `ghost-devkit/ssp-<キットのフォルダのハッシュ>.json` に記録する（`Save-DevkitSspSession`）。ゴーストのフォルダに置かないのは、nar や git の除外を増やさないため。PID が生きていて開始時刻も同じときだけ有効とし（PID の再利用対策）、それ以外は消す。
  - `tools/sstp.ps1` と `tools/ssp-log.ps1` の `-Port` の既定値は 0 で、`Resolve-DevkitSspPort` が、記録が有効ならそのポート、無ければ 9801 にする。
  - `-Stop` は Owned SSTP で `\-` を送ってゴーストを閉じ（`OnClose` が動き、YAYA が変数を保存する）、閉じなければプロセスを止める。ゴーストが 1 体なら SSP も終わる（2.8.97 で確認）。
  - readonly は二重起動のチェックに関わらないので、記録が有効な間は新しく立てず、そのことを表示して終わる。別のフォルダ（`-Root`）の記録が有効なら、先に `-Stop` するよう促して 1 で終わる。
- nar と更新定義ファイルの作成（`tools/build-nar.ps1`）:
  - `ssp.exe --offline-tool <nar|updatedata> --target-dir <ゴーストのルート> --output <出力先>`（2.9.01 以降）で、1 回に 1 つのファイルを作る。ゴーストを起動せず、ウィンドウも作らずに終わるので、試験用 SSP も SSTP も使わない。SSP が動いていても作れる（2.9.01 で、`tools/run-ssp.ps1` の試験用 SSP を動かしたまま確認）。`\![execute,createnar]` / `\![execute,createupdatedata]` と同じ処理で、出力先は既存のファイルを上書きし、ゴーストのフォルダ内ならそのファイル自身は収録しない。出力先のフォルダはあらかじめ作っておく必要がある。
  - `updatedata` は、出力先が `.dau` で終われば updates2.dau の形式、それ以外は updates.txt の形式で 1 つだけ作る。ふだんの出力先（ゴーストのルートと `ghost/master`）の updates2.dau / updates.txt は作りも消しもしない。キットは更新定義 2 つ → nar の順に 3 回呼ぶ。
  - ssp.exe の終了コードは 0 成功 / 1 引数が不正 / 2 作成に失敗。古い SSP はこのオプションを知らないので、1 のときは版が足りない可能性も表示する。ゴーストのイベントは起きないので、SSP のエラーログは読まない。
  - SSP はフォルダの中身をそのまま固める（git の追跡状態は見ない）。`.narignore` の解釈は `tools/lib/ignore.ps1` と一致することを、konnoyayame で nar の中身と `-Builtin -FromWorkingTree -ListOnly` の一覧を比べて確かめた（2.8.98 の SSTP 経由、2.9.01 の `--offline-tool`）。SSP の nar にはフォルダの項目（`ghost/` など）も入る。
  - GitHub Actions には SSP が無いので、`GITHUB_ACTIONS=true` か `-Builtin` のときは、今までどおりスクリプト自身が git の追跡しているファイルから nar を作る。派生ゴーストの `auto_release.yml` は `-Builtin` を付けずに呼んでいるので、この自動の切り替えを外さない。
