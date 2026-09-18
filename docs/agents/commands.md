# 開発コマンド

`tools/` の開発用スクリプトの一覧と、終了コードの意味。

以下の `<ps>` は `powershell -NoProfile -ExecutionPolicy Bypass -File` の略。Windows PowerShell 5.1 でも PowerShell 7 でも動く。

| コマンド | 内容 | 終了コード |
|---|---|---|
| `<ps> tools/doctor.ps1` | 開発環境を診断し、足りないもの（Git、SSP、チェック用ツール、`GHOST.md` など）の用途と入手方法を表示する。何も変更しない（`-Json` で機械向けの出力） | 0 必須はそろっている / 1 必須が足りない |
| `<ps> tools/setup.ps1` | git clone したフォルダなら submodule を取得し、tamac.exe を `tools/bin/` に取得する（最新リリースを、GitHub が公開している SHA256 で照合して取得する。ツールは `tools/tools.json` に書く）。取得済みでも版が違えば取り直す。最後に doctor の結果を表示する | 0 成功 / 1 失敗、または必須が足りない |
| `<ps> tools/check-dic.ps1` | tamac.exe で辞書を実際に読み込み、エラーを表示する | 0 OK / 1 エラー / 3 ツール未導入 |
| `<ps> tools/check-shell.ps1` | `ssp.exe --offline-dump` でシェルを検査する（Error / Warning / Notice）。SSP 2.8.94 以降では、問題の定義位置（`shell/master/surfaces.txt:Line=123`）も表示する | 0 OK / 1 Error あり / 3 SSP が見つからない |
| `<ps> tools/lint.ps1` | 未定義・未使用の変数と関数、条件式の中の代入を探す（参考情報）。tamac.exe でゴーストを読み込み、システム辞書の `SHIORI3FW.Lint.Run`（yaya-dic の `yaya_base/lint.dic`）が yaya.dll の `LINT.*` 関数で辞書を調べる。`ファイル:行: 種類 '名前' in 関数名` の形で表示し、桁は出ない。システム辞書の結果は `-IncludeSystem` のときだけ表示する。`tools/shiori.ps1 -Eval 'SHIORI3FW.Lint.Run'` でも同じ結果を得られる | 0（`-Strict` なら未定義があると 1）/ 1 辞書の読み込みエラーなど / 3 tamac.exe が無いか古い、yaya.dll が Tc574-1 より古い、システム辞書に `lint.dic` が無い |
| `<ps> tools/check.ps1` | 上の 3 つを順に実行する | 0 / 1 |
| `<ps> tools/dump-surface.ps1 -Surface 0,5,10` | `ssp.exe --offline-dump` で、サーフェスを surfaces.txt の定義どおりに重ね合わせた PNG を作り、そのパスを表示する（ゴーストは起動しない）。画像を読めるエージェントが表情や重ね合わせを目で確かめるためのもの。`-Surface` は番号のほか `0-7` のような surfaces.txt の拡張形式も使える。`-Backlog` で顔のまわり（約 80×80）だけを切り抜き、`-Sheet` で全部を番号付きで 1 枚に並べた `sheet.png` も作る。`-Scope` / `-Shell` で対象を変える。出力先は既定で一時フォルダの `ghost-devkit/surfaces-<ハッシュ>/`（実行のたびに中の PNG を消す）。シェルのライセンスによっては改変した画像を配布できないので、ゴーストのフォルダやリポジトリには置かない | 0 全部出た / 1 1 枚も出ない、引数の誤り / 2 見つからない番号があった、または SSP がエラーを記録した / 3 SSP が見つからない |
| `<ps> tools/shiori.ps1 -Eval '関数名や式'` | SSP を使わずに、tamac.exe でこのゴーストの yaya.dll に SHIORI リクエストを 1 回送る。`-Eval` は YAYA のコードを評価して結果を表示する（関数名なら返すトーク、組み込み関数なら実際の戻り値。システム辞書の `??` を使う）。`-Event <ID> -Reference '0,0,0,0,Head'` は SSP と同じ形の GET（`-Notify` で NOTIFY）、`-Request` は生のリクエスト。呼ぶたびに辞書を読み込み直し（`OnBoot` などは先に送らない）、`yaya_variable.cfg` は元に戻す | 0 / 1 失敗（辞書の読み込みエラー、エラー応答など）/ 2 処理中に YAYA がエラーを出した / 3 tamac.exe が無いか古い |
| `<ps> tools/run-ssp.ps1` | このフォルダのゴーストを SSP で直接起動し（`ssp.exe --ghost <フォルダ>`。インストール不要）、応答するまで待つ。SSP 2.8.97 以降では、作者の SSP とは別の試験用 SSP を `--option readonly --sstp-listen <ポート>` で立てる（設定や起動履歴を保存せず、vanish してもフォルダを消さない。ポートは 9822〜10999 の空いている最初のもの）。すでに動いていればそのままにする。`-Stop` で閉じ、`-Shared` なら今までどおり作者の SSP（9801）で動かす。起動中に SSP のエラーログに増えた警告・エラーを表示する（SSP 2.8.94 以降では、起動時のトークが終わるのを待ってから読む） | 0 起動した（`-Stop` は閉じた、または動いていなかった）/ 1 応答なし、起動できない / 2 起動したが、エラーログに Error か Critical が増えた / 3 SSP が見つからない |
| `<ps> tools/sstp.ps1 -Reload ghost` | 起動中の SSP にゴーストを再読み込みさせ、その間に SSP のエラーログに増えた警告・エラー（YAYA の辞書エラーなど）を表示する | 0 / 1 エラー応答 / 2 エラーログに Error か Critical が増えた / 3 SSP に接続できない |
| `<ps> tools/sstp.ps1 -Script '\0\s[0]テスト\e'` | さくらスクリプトを実際のゴーストで再生する。SSP 2.8.94 以降では、SSP が解釈できなかったタグ（存在しないサーフェス、閉じていない `[` など）が `[GHOST/Script]` のエラーとして表示され（`Option: strict`）、ログはゴーストが話し終わるのを待ってから読む | 同上 |
| `<ps> tools/sstp.ps1 -Event OnAiTalk` | イベントを発生させる（この例はランダムトーク）。応答の `Script:` に、ゴーストが実際に返したスクリプトが入る。そのスクリプトも `-Script` と同じように検査する（SSP 2.8.94 以降） | 同上 |
| `<ps> tools/sstp.ps1 -Execute GetStatus` | ゴーストの今の状態（`talking`、`choosing`、`online`、`opening(...)` などのカンマ区切り。当てはまるものが無ければ空）を表示する（SSP 2.8.94 以降） | 0 / 1 / 3 |
| `<ps> tools/ssp-log.ps1` | 起動中の SSP のログを表示する。読み取りのみ。既定はこのゴーストのエラーログで、`-Kind script` で再生されたスクリプト（ほかに `network` / `update`）、`-All` で発信元を問わず全部、`-Json` で機械向けの出力 | 0 / 1 SSP が developer.log に未対応 / 2 Error か Critical がある / 3 SSP に接続できない |
| `<ps> tools/build-nar.ps1` | SSP 2.8.98 以降で、`build/<directory>.nar` と、ネットワーク更新ファイル `build/updates2.dau`・`build/updates.txt` を作る（試験用 SSP でゴーストを起動し、`\![execute,createupdatedata,<ファイル>]` と `\![execute,createnar,<ファイル>]` を実行させる。自分で立てた試験用 SSP は最後に閉じる）。SSP はフォルダの中身をそのまま固めるので、git に追加していないファイルも入る。`-UpdateOnly` で更新ファイルだけ、`-OutFile` で nar の出力先（更新ファイルはその横）、`-ListOnly` で `.narignore` から見た中身の一覧だけを表示する。`-Builtin` と GitHub Actions では SSP を使わず、git が追跡しているファイルからスクリプト自身が nar だけを作る | 0 / 1 失敗（SSP が 2.8.98 より古い場合も）/ 2 作ったが、その間に SSP のエラーログに Error か Critical が増えた / 3 SSP が見つからない |
| `<ps> tools/update-yaya.ps1` | yaya.dll を最新リリースに、システム辞書（yaya-dic）を最新のコミットに更新する。システム辞書は、git のチェックアウト（submodule など）なら git で切り替え、普通のファイルなら zip から置き換える（`config.dic` と `_loading_order.txt` は、手元と違えば `<ファイル>.yaya-dic-new` を横に置く）。それぞれの後で辞書チェックを行い、失敗したら元に戻す。`-DryRun` で確認のみ、`-Tag` で yaya.dll の版を指定、`-SkipDll` / `-SkipSystemDic` で片方だけ、`-SystemDicDir dic/system` で新しいフォルダに yaya-dic を置く | 0 / 1 失敗 / 2 システム辞書に手作業が要る（古い構成、手元の変更、`.yaya-dic-new` のマージ待ち） |
| `<ps> tools/update-devkit.ps1` | 開発キットだけを最新版に更新する（`-DryRun` で確認のみ、`-Ref` で版を指定）。別の YAYA ゴーストにキットを入れるときは `-Target <そのゴーストのフォルダ>` | 0 / 1 失敗 / 2 マージ待ちの `.devkit-new` がある |

`tools/sstp.ps1` と `tools/ssp-log.ps1` は、`run-ssp.ps1` が立てた試験用 SSP が動いている間は、そのポートに送る（ポートは一時フォルダの `ghost-devkit/` に記録される）。それ以外は 9801。`-Port` で指定もできる。

SSP の場所は次の順に探す: `-SspPath` 引数 → 環境変数 `SSP_PATH` → `tools/local.json` の `sspPath`（`tools/local.example.json` を複製して作る）→ SSP にインストールされたフォルダなら `../../ssp.exe` → `.nar` のファイル関連付け。
