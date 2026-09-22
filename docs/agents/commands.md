# 開発コマンド

`tools/` の開発用スクリプトの一覧と、終了コードの意味。

以下の `<ps>` は `powershell -NoProfile -ExecutionPolicy Bypass -File` の略。Windows PowerShell 5.1 でも PowerShell 7 でも動く。

| コマンド | 内容 | 終了コード |
|---|---|---|
| `<ps> tools/doctor.ps1` | 開発環境を診断し、足りないもの（Git、SSP、チェック用ツール、`GHOST.md` など）の用途と入手方法を表示する。何も変更しない（`-Json` で機械向けの出力） | 0 必須はそろっている / 1 必須が足りない |
| `<ps> tools/setup.ps1` | git clone したフォルダなら submodule を取得し、tamac.exe を `tools/bin/` に取得する（最新リリースを、GitHub が公開している SHA256 で照合して取得する。ツールは `tools/tools.json` に書く）。取得済みでも版が違えば取り直す。最後に doctor の結果を表示する | 0 成功 / 1 失敗、または必須が足りない |
| `<ps> tools/check-dic.ps1` | tamac.exe で辞書を実際に読み込み、エラーを表示する | 0 OK / 1 エラー / 3 ツール未導入 |
| `<ps> tools/check-shell.ps1` | `ssp.exe --offline-dump` でシェルを検査する（Error / Warning / Notice）。問題の定義位置（`shell/master/surfaces.txt:Line=123`）も表示する | 0 OK / 1 Error あり / 3 SSP が見つからない |
| `<ps> tools/lint.ps1` | 未定義・未使用の変数と関数、条件式の中の代入を探す（参考情報）。tamac.exe でゴーストを読み込み、システム辞書の `SHIORI3FW.Lint.Run`（yaya-dic の `yaya_base/lint.dic`）が yaya.dll の `LINT.*` 関数で辞書を調べる。`ファイル:行: 種類 '名前' in 関数名` の形で表示し、桁は出ない。システム辞書の結果は `-IncludeSystem` のときだけ表示する。`tools/shiori.ps1 -Eval 'SHIORI3FW.Lint.Run'` でも同じ結果を得られる | 0（`-Strict` なら未定義があると 1）/ 1 辞書の読み込みエラーなど / 3 tamac.exe が無いか古い、yaya.dll が Tc574-1 より古い、システム辞書に `lint.dic` が無い |
| `<ps> tools/check.ps1` | 上の 3 つを順に実行する | 0 / 1 |
| `<ps> tools/dump-surface.ps1 -Surface 0,5,10` | `ssp.exe --offline-dump` で、サーフェスを surfaces.txt の定義どおりに重ね合わせた PNG を作り、そのパスを表示する（ゴーストは起動しない）。画像を読めるエージェントが表情や重ね合わせを目で確かめるためのもの。`-Surface` は番号のほか `0-7` のような surfaces.txt の拡張形式も使える。`-Backlog` で顔のまわり（約 80×80）だけを切り抜き、`-Collision` で当たり判定（`collision` の形と名前）を描き込み、`-Sheet` で全部を番号付きで 1 枚に並べた `sheet.png` も作る。`-Scope` / `-Shell` で対象を変える。出力先は既定で一時フォルダの `ghost-devkit/surfaces-<ハッシュ>/`（実行のたびに中の PNG を消す）。シェルのライセンスによっては改変した画像を配布できないので、ゴーストのフォルダやリポジトリには置かない | 0 全部出た / 1 1 枚も出ない、引数の誤り / 2 見つからない番号があった、または SSP がエラーを記録した / 3 SSP が見つからない |
| `<ps> tools/image.ps1 <サブコマンド> ...` | 画像を調べる・編集する・比べる・拡大して見る（主にシェルの画像）。書き出す画像は必ず 32bit RGBA PNG。`info` は大きさ、ファイルの透過の持ち方、見えている範囲、`-At x,y,...` の画素の値と、シェルのフォルダにある画像なら SSP で何が透過になるか（`seriko.use_self_alpha`）を表示する。`edit <入力> -Out <出力> '<操作>' ...` は操作を順に当てて書き出す。`view` は拡大図（座標の目盛り付き、複数なら横に並べる）を書き、`diff` は 2 枚の違う範囲を表示し、`-Part` で違う画素だけをパーツとして切り出す。操作と使い方は下の「画像の編集」 | 0 / 1 失敗（引数の誤り、読めないファイル、未知の操作）/ 2 `edit` は書いたが、そのままでは SSP がアルファを使わない（隣に `.pna` がある、シェルに `seriko.use_self_alpha,1` が無い） |
| `<ps> tools/shiori.ps1 -Eval '関数名や式'` | SSP を使わずに、tamac.exe でこのゴーストの yaya.dll に SHIORI リクエストを 1 回送る。`-Eval` は YAYA のコードを評価して結果を表示する（関数名なら返すトーク、組み込み関数なら実際の戻り値。システム辞書の `??` を使う）。`-Event <ID> -Reference '0,0,0,0,Head'` は SSP と同じ形の GET（`-Notify` で NOTIFY）、`-Request` は生のリクエスト。呼ぶたびに辞書を読み込み直し（`OnBoot` などは先に送らない）、`yaya_variable.cfg` は元に戻す | 0 / 1 失敗（辞書の読み込みエラー、エラー応答など）/ 2 処理中に YAYA がエラーを出した / 3 tamac.exe が無いか古い |
| `<ps> tools/run-ssp.ps1` | このフォルダのゴーストを SSP で直接起動し（`ssp.exe --ghost <フォルダ>`。インストール不要）、応答するまで待つ。作者の SSP とは別の試験用 SSP を `--option readonly --sstp-listen <ポート>` で立てる（設定や起動履歴を保存せず、vanish してもフォルダを消さない。ポートは 9822〜10999 の空いている最初のもの）。すでに動いていればそのままにする。`-Stop` で閉じ、`-Shared` なら今までどおり作者の SSP（9801）で動かす。起動中に SSP のエラーログに増えた警告・エラーを、起動時のトークが終わるのを待ってから表示する | 0 起動した（`-Stop` は閉じた、または動いていなかった）/ 1 応答なし、起動できない / 2 起動したが、エラーログに Error か Critical が増えた / 3 SSP が見つからない |
| `<ps> tools/sstp.ps1 -Reload ghost` | 起動中の SSP にゴーストを再読み込みさせ、その間に SSP のエラーログに増えた警告・エラー（YAYA の辞書エラーなど）を表示する | 0 / 1 エラー応答 / 2 エラーログに Error か Critical が増えた / 3 SSP に接続できない |
| `<ps> tools/sstp.ps1 -Script '\0\s[0]テスト\e'` | さくらスクリプトを実際のゴーストで再生する。SSP が解釈できなかったタグ（存在しないサーフェス、閉じていない `[` など）が `[GHOST/Script]` のエラーとして表示され（`Option: strict`）、ログはゴーストが話し終わるのを待ってから読む | 同上 |
| `<ps> tools/sstp.ps1 -Event OnAiTalk` | イベントを発生させる（この例はランダムトーク）。応答の `Script:` に、ゴーストが実際に返したスクリプトが入る。そのスクリプトも `-Script` と同じように検査する | 同上 |
| `<ps> tools/sstp.ps1 -Script '...' -Balloon` | `-Script` か `-Event` に付けると、話し終わった後の吹き出しを `\![execute,dumpballoon]` で PNG にし（`\0` なら `balloon0.png`、`\1` なら `balloon1.png`）、そのパスを表示する。画像を読めるエージェントが、吹き出しに収まっているか、どこで折り返したか、改行や空行の見た目を自分で確かめるためのもの。`-BalloonScope 0,1,2` で撮るスコープを変える（既定は 0,1。吹き出しの無いスコープは撮れない）。出力先は一時フォルダの `ghost-devkit/balloons-<ハッシュ>/`（実行のたびに中の PNG を消す）。下の `from ghost-devkit (local)` の行は SSTP で送ったときに SSP が付ける表示で、トークの一部ではない。`-AnyGhost` とは使えない | 上と同じ。ほかに、1 枚も撮れなかったら 2 |
| `<ps> tools/sstp.ps1 -Execute GetStatus` | ゴーストの今の状態（`talking`、`choosing`、`online`、`opening(...)` などのカンマ区切り。当てはまるものが無ければ空）を表示する | 0 / 1 / 3 |
| `<ps> tools/ssp-log.ps1` | 起動中の SSP のログを表示する。読み取りのみ。既定はこのゴーストのエラーログで、`-Kind script` で再生されたスクリプト（ほかに `network` / `update`）、`-All` で発信元を問わず全部、`-Json` で機械向けの出力 | 0 / 1 SSP が developer.log に未対応 / 2 Error か Critical がある / 3 SSP に接続できない |
| `<ps> tools/build-nar.ps1` | SSP で、`build/<directory>.nar` と、ネットワーク更新ファイル `build/updates2.dau`・`build/updates.txt` を作る（`ssp.exe --offline-tool` を使う。ゴーストは起動せず、SSP が動いていても関係なく作れる）。SSP はフォルダの中身をそのまま固めるので、git に追加していないファイルも入る。`-UpdateOnly` で更新ファイルだけ、`-OutFile` で nar の出力先（更新ファイルはその横）、`-ListOnly` で `.narignore` から見た中身の一覧だけを表示する。`-Builtin` と GitHub Actions では SSP を使わず、git が追跡しているファイルからスクリプト自身が nar だけを作る | 0 / 1 失敗 / 3 SSP が見つからない |
| `<ps> tools/update-yaya.ps1` | yaya.dll を最新リリースに、システム辞書（yaya-dic）を最新のコミットに更新する。システム辞書は、git のチェックアウト（submodule など）なら git で切り替え、普通のファイルなら zip から置き換える（`config.dic` と `_loading_order.txt` は、手元と違えば `<ファイル>.yaya-dic-new` を横に置く）。それぞれの後で辞書チェックを行い、失敗したら元に戻す。`-DryRun` で確認のみ、`-Tag` で yaya.dll の版を指定、`-SkipDll` / `-SkipSystemDic` で片方だけ、`-SystemDicDir dic/system` で新しいフォルダに yaya-dic を置く | 0 / 1 失敗 / 2 システム辞書に手作業が要る（古い構成、手元の変更、`.yaya-dic-new` のマージ待ち） |
| `<ps> tools/update-devkit.ps1` | 開発キットだけを最新版に更新する（`-DryRun` で確認のみ、`-Ref` で版を指定）。別の YAYA ゴーストにキットを入れるときは `-Target <そのゴーストのフォルダ>` | 0 / 1 失敗 / 2 マージ待ちの `.devkit-new` がある |

`tools/sstp.ps1` と `tools/ssp-log.ps1` は、`run-ssp.ps1` が立てた試験用 SSP が動いている間は、そのポートに送る（ポートは一時フォルダの `ghost-devkit/` に記録される）。それ以外は 9801（作者がふだん使っている SSP）。`-Port` で指定もできる。さくらスクリプトやイベントを試すときは、**先に `run-ssp.ps1` で試験用 SSP を立ててから送る**。作者の SSP には、作者に頼まれたとき（`run-ssp.ps1 -Shared`）以外は送らない。

SSP の場所は次の順に探す: `-SspPath` 引数 → 環境変数 `SSP_PATH` → `tools/local.json` の `sspPath`（`tools/local.example.json` を複製して作る）→ SSP にインストールされたフォルダなら `../../ssp.exe` → `.nar` のファイル関連付け。

## 画像の編集（`tools/image.ps1`）

```
<ps> tools/image.ps1 info <ファイル>... [-At x,y,x,y...]
<ps> tools/image.ps1 edit <入力> -Out <出力.png> '<操作>' '<操作>' ...
<ps> tools/image.ps1 view <ファイル>... [-Rect x,y,w,h] [-Zoom 8] [-Grid 10] [-Background checker] [-Out <出力.png>]
<ps> tools/image.ps1 diff <A> <B> [-Part <出力.png>] [-View] [-Tolerance 0]
```

- 書き出す画像は、元の形式（パレット、RGB、グレースケール、16bit など）にかかわらず、すべて 8bit×4ch の RGBA PNG（カラータイプ 6）になる。完全に透明な画素の色は `#00000000` にそろえる。
- **SSP は、シェルの `descript.txt` に `seriko.use_self_alpha,1`（または `full`）が無いと、PNG のアルファを無視して左上の画素の色を透過色にする**（完全に透明な画素は黒く出る）。`1` にしても、アルファの無い画像は今までどおり左上の色で抜かれる。`edit` の出力先がそういうシェルの中なら、注意を出して終了コード 2 になる。同じ名前の `.pna` が隣にあるときも同じ（アルファと `.pna` のどちらが使われるかは資料に書かれていないので、どちらか一方にする）。
- 入力は PNG（すべてのカラータイプとビット深度、インターレース、tRNS）、BMP、JPEG、GIF。`new:幅x高さ` または `new:幅x高さ:#色` で空の画像から始められる。
- `view` と `diff -View` の出力先は、`-Out` を省くと一時フォルダの `ghost-devkit/image/`（`view.png`、`diff.png`。毎回上書き）。画像を読めるエージェントが目で確かめるためのもので、目盛りの数字は元の画像の座標。`-Zoom` を省くと 480 ピクセルほどに収まる倍率、`-Grid` を省くと倍率に合った間隔になる。`-Background` は `checker`（市松模様）、`white`、`black`、`#rrggbb`、`alpha`（アルファをグレーで）、`opaque`（アルファを無視した色）。
- `diff` は同じ大きさの 2 枚を比べ、違う画素の数と範囲（x,y,w,h）を表示する。完全に透明な画素どうしは色が違っても同じとみなす。`-Part` は B のうち A と違う画素だけを、その範囲で切り出して書き、貼る位置を表示する（A に `paste` すると B になる。`element` や `animation` のパーツ作りに使う）。
- 引数は PowerShell の外から渡すことを前提にしている（`<ps>` の形）。`-At` と `-Rect` はカンマ区切りの 1 つの値で渡す。

### 操作

1 つの操作を 1 つの引数にする（空白を含むので `'...'` で囲む）。名前、位置で決まる値、`キー=値` のオプションを空白で区切る。空白を含む値は `'...'` か `"..."` で囲む（PowerShell の外からなら `"text 'こんにちは' 5,5"` のように）。座標は左上が 0,0 のピクセル、矩形は `x,y,w,h`、色は `#rgb`、`#rrggbb`、`#rrggbbaa`、`black`、`white`、`transparent`。割合は `0.5` でも `50%` でもよい。未知のオプションや余った値はエラーになる。

| 操作 | 内容 |
|---|---|
| `crop x,y,w,h` | 切り抜く。はみ出した部分は透明 |
| `trim [pad=N] [alpha=N]` | 見えている範囲（アルファが `alpha` より大きい画素）に切り詰める。元の画像のどこを残したかを表示する |
| `canvas WxH [x,y｜center] [color=]` | キャンバスの大きさを変え、今の画像を x,y（既定 0,0）に置く |
| `pad N` / `pad 左,上,右,下 [color=]` | 周りを広げる（負の値で削る） |
| `offset dx,dy` | 大きさはそのままで中身をずらす |
| `resize WxH [filter=]` | 拡大縮小。`200x` や `x100` なら縦横比を保つ。`filter` は `bicubic`（既定）、`lanczos`、`bilinear`、`box`（縮小向き）、`nearest`（ドット絵向き） |
| `scale 倍率 [filter=]` | 倍率で拡大縮小（`0.5`、`200%`） |
| `flip h｜v` | 左右（h）・上下（v）反転 |
| `rotate 角度 [expand=0]` | 時計回りに回す。90 の倍数は劣化しない。それ以外はキャンバスが広がる（`expand=0` で元の大きさ） |
| `paste ファイル [x,y] [mode=] [opacity=]` | 別の画像を重ねる。`mode` は `over`（既定。普通に重ねる）、`under`（下に敷く）、`replace`（アルファごと置き換える）、`erase`（重ねた画像の形に消す）、`clip`（重ねた画像の形だけ残す）、`multiply`（乗算） |
| `colorkey [色｜topleft] [tolerance=N]` | その色（既定は左上の画素の色）を透明にする。アルファの無いシェル画像を 32bit にするときに使う |
| `pna [ファイル]` | `.pna`（グレースケール。白が不透明）を読んでアルファにする。省くと入力と同じ名前の `.pna` |
| `mask ファイル [at=x,y] [channel=alpha｜gray] [invert]` | 別の画像のアルファ（`gray` なら明るさ）をかけて、形を切り抜く |
| `opacity 割合` | 不透明度をかける |
| `threshold N` | アルファを N 以上は不透明、未満は透明の 2 値にする（既定 128） |
| `flatten [色]` | その色（既定は白）の上に重ねて不透明にする |
| `fill 色` / `clear` | 塗りつぶす / 透明にする（`rect=` などで範囲を絞る） |
| `floodfill x,y 色 [tolerance=N]` | x,y とつながった似た色の範囲を塗る（`transparent` で消す） |
| `replace 色 新しい色 [tolerance=N]` | 色を置き換える |
| `adjust [hue=度] [sat=%] [light=%] [bright=%] [contrast=%] [gamma=]` | 色相を回す、彩度・明度・明るさ・コントラストを ±% で変える、ガンマ補正 |
| `colorize 色 [amount=]` | 明暗を保ったままその色に染める |
| `grayscale` / `invert` | グレースケール / 色の反転 |
| `blur 半径` / `sharpen [半径] [amount=]` | ぼかす（ガウス）/ くっきりさせる（アンシャープマスク） |
| `outline 太さ [color=]` | 輪郭の外側に縁取りを付ける |
| `shadow dx,dy [blur=] [color=] [opacity=]` | 影を付ける（キャンバスは広げないので、先に `pad` する） |
| `rect x,y,w,h` / `ellipse x,y,w,h` | 矩形・楕円を描く。`width=` を付けると枠線（矩形の内側に収まる）、付けなければ塗りつぶし |
| `line x1,y1,x2,y2,...` / `polygon x1,y1,x2,y2,x3,y3,...` | 折れ線 / 多角形。座標は画素の中心 |
| `text '文字' x,y [size=] [font=] [bold] [italic] [align=left｜center｜right]` | 文字を描く（`\n` で改行。既定のフォントは Meiryo） |

- 色を変える操作（`fill`、`clear`、`replace`、`adjust`、`colorize`、`grayscale`、`invert`、`opacity`、`blur`、`sharpen`）は、`rect=x,y,w,h` と `mask=ファイル`（そのアルファを重みにする。同じ大きさの画像）で範囲を絞れる。
- 描く操作（`rect`、`ellipse`、`line`、`polygon`、`text`）は、`color=`（既定は黒）、`mode=over｜replace｜erase`（`erase` は描いた形に消す）、`aa=0`（アンチエイリアスなし）を付けられる。
- 半透明の境目がにじまないよう、拡大縮小、回転、ぼかしはアルファを考慮して計算する。
