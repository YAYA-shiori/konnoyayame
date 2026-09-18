# SSP との連携

`tools/sstp.ps1`、`tools/ssp-log.ps1`、`tools/check-shell.ps1`、`tools/run-ssp.ps1` が頼っている SSP の挙動。

- SSTP: `tools/sstp.ps1` は、`EXECUTE GetFMO` で調べたゴーストの識別 ID を `ID` ヘッダに付けて送る（Owned SSTP）。付けないと SSP は外部のプログラムからの要求として扱い、`\![reload,ghost]` などを黙って無視する（応答は 200 のまま）。
- SSP のログ: プロパティシステムの `developer.log.*` を `EXECUTE GetProperty` で読む。ログは種類ごとに新しいものから 50 件ほどしか残らず、発信元の名前は descript.txt の `name`（`sakura.name` ではない）になる。
- SSP の版: 機能ごとに `tools/lib/common.ps1` の定数を基準にする（2.8.94 の機能は `$DevkitSspDiagnosticsVersion`、2.8.97 の試験用 SSP は `$DevkitSspIsolatedVersion`）。doctor は `$DevkitSspRecommendedVersion`（今は 2.8.97）より古い版を recommended の不足として知らせる。版は `ssp.exe` のファイルバージョン（`2, 8, 94, 3000`）の上 3 つで比べる（`Get-DevkitSspVersion`）。古い版では、各スクリプトは今までどおりの動き（決まった時間だけ待つなど）に戻す。2.8.94 の機能は次のとおり。
  - `EXECUTE GetStatus`（`Get-DevkitSspStatus`）: SEND と NOTIFY は、スクリプトを再生する前に応答する。再生中は `talking` が付くので、`Wait-DevkitSspTalkEnd` でそれが消えるまで待ってからエラーログを読む。ゴーストの読み込み中は 400 が返り、`\![reload,ghost]` の後は `talking` → 400 → 200 と変わる（`Wait-DevkitSspReload`）。古い SSP も 200 を返さないので、要求を送る前に 1 回呼んで使えるか確かめる。
  - `Option: strict`: `tools/sstp.ps1` の `-Script` と `-Event` に付ける。解釈に失敗したタグは、再生がその位置に来たときに、Error として `[GHOST/Script] 理由 (詳細) at position 位置 : 抜粋` の形で記録される（位置はスクリプトの先頭を 0 とした文字数）。
  - `--dump-error-log`: ssp.exe の終了コードが、記録された最も重いレベルになる（0 Notice 以下 / 1 Warning / 2 Error / 3 Critical）。`tools/check-shell.ps1` はログから数えた件数と照らし合わせ、0〜3 以外は異常終了として扱う。
  - SERIKO のメッセージの定義位置（`<ファイル>:Line=<n>:`）: SSP の説明ではゴーストのフォルダからの相対パスだが、`--offline-dump` では絶対パスになる（2.8.94 で確認）。`ConvertTo-DevkitRelativeText` がどちらも `/` 区切りの相対パスにそろえ、`check-shell.ps1 -Ci` はそれを GitHub Actions の注釈の `file` と `line` にする。
- SSP 2.8.97 以降の試験用 SSP（`tools/run-ssp.ps1`。基準は `$DevkitSspIsolatedVersion`）:
  - `--option readonly --sstp-listen <ポート> --ghost <フォルダ>` で起動する。readonly は `bootunlock,standalone` を含むので、起動中の SSP に処理を渡さず、別のプロセスになる。設定、起動履歴、キャッシュなどを保存せず、vanish してもゴーストのフォルダを消さない。YAYA が書く `yaya_variable.cfg` は SSP の保存とは別なので、ふだんどおり書かれる。
  - ポートは 9822〜10999 で、IPv4 と IPv6 のループバックの両方に bind できる最初のもの（`Find-DevkitSspFreePort`）。9801、9821、11000 は伺かのほかのプログラムの既定値なので避ける。
  - 起動した SSP のポート、PID、プロセスの開始時刻、ゴーストのフォルダを、一時フォルダの `ghost-devkit/ssp-<キットのフォルダのハッシュ>.json` に記録する（`Save-DevkitSspSession`）。ゴーストのフォルダに置かないのは、nar や git の除外を増やさないため。PID が生きていて開始時刻も同じときだけ有効とし（PID の再利用対策）、それ以外は消す。
  - `tools/sstp.ps1` と `tools/ssp-log.ps1` の `-Port` の既定値は 0 で、`Resolve-DevkitSspPort` が、記録が有効ならそのポート、無ければ 9801 にする。
  - `-Stop` は Owned SSTP で `\-` を送ってゴーストを閉じ（`OnClose` が動き、YAYA が変数を保存する）、閉じなければプロセスを止める。ゴーストが 1 体なら SSP も終わる（2.8.97 で確認）。
  - readonly は二重起動のチェックに関わらないので、記録が有効な間は新しく立てず、そのことを表示して終わる。別のフォルダ（`-Root`）の記録が有効なら、先に `-Stop` するよう促して 1 で終わる。
