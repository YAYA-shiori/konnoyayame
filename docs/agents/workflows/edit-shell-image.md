# シェルの画像を編集する

## 使うとき

作者が「シェルの画像を直して」「画像を編集して」「表情のパーツを作って」「立ち絵を縮小して」「32bit PNG にして」「半透明にして」と言ったとき。サーフェスの画像、`element` や `animation` のパーツ、メニューの画像などを、`tools/image.ps1` で作ったり直したりする。

何をどう変えたいのか（どのサーフェスの、どの部分を、どんな見た目に）が会話から分からなければ、作者に聞く。

## 前提

- **`GHOST.md` でシェルのライセンスを確かめる。** 改変を禁じているシェル（CC BY-ND、CC BY-NC-ND など）の画像は編集しない。改変した画像は配布できないので、作者にそう伝えて止める。`GHOST.md` に書かれていなければ、シェルの `readme.txt` や `descript.txt` を読み、それでも分からなければ作者に確かめる。
- 他のゴーストのシェル画像を、切り貼りしたり似せて描いたりして持ち込まない（`AGENTS.md` の「AI を使ったゴースト制作のガイドライン」）。
- 画像を読めるエージェントであること。読めなければ、`info` と `diff` の数字だけでは仕上がりが分からないので、見た目は作者に確かめてもらう。

## 手順

1. 元に戻せるようにする。git で管理しているなら、元の画像がコミット済みか `git status` で確かめる。git が無ければ、作者に断って、元の画像を一時フォルダにコピーしておく。
2. 今の状態を調べる。
   - `powershell -NoProfile -ExecutionPolicy Bypass -File tools/image.ps1 info 'shell/master/*.png'` で、各画像の大きさ、透過の持ち方（パレット、RGBA、`.pna` など）、SSP で何が透過になるかを見る。
   - `shell/master/surfaces.txt` を読み、直したい画像がどのサーフェスのどこに使われているか（`element`、`animation` のパターン、その座標）を確かめる。1 枚のパーツが複数のサーフェスで使われていることがある。
   - 合成された姿は `tools/dump-surface.ps1 -Surface <番号>`、当たり判定は `-Collision` を付けて見る。
3. 作業は一時フォルダで行い、確かめながら進める。
   - 位置を決めるときは `tools/image.ps1 view <ファイル> -Rect x,y,w,h -Zoom 8` で拡大し、目盛りの座標を読む。作業前と作業後を並べて渡すと見比べられる。
   - 表情などの差分パーツは、`diff <元> <変えた後> -Part <パーツ.png>` で違う画素だけを切り出せる。表示された位置が、`element` / `animation` に書く座標になる。
   - 1 回の `edit` で複数の操作を順に当てられる。操作の一覧は `docs/agents/commands.md` の「画像の編集」。
4. 透過の扱いを決める。`tools/image.ps1` の出力はすべて 32bit RGBA PNG なので、SSP にアルファを使わせる設定が要る。
   - シェルの `descript.txt` に `seriko.use_self_alpha,1` が無ければ、足すことを作者に提案する。無いままだと、SSP はアルファを無視して左上の画素の色で抜く（完全に透明な画素は黒く出る）。
   - 足す前に、手順 2 の `info` で**アルファを持つ既存の画像**（`RGBA`、`grayscale+alpha`）を探す。設定を足すとそのアルファが使われるようになるので、左上の色で抜くつもりだった画像（アルファがすべて不透明なものなど）は、`colorkey` で 32bit に直しておく。アルファの無い画像は、設定を足しても今までどおり左上の色で抜かれる。
   - 左上の色で抜いていた画像を 32bit にするときは `colorkey`、`.pna` を使っていた画像は `pna` の操作でアルファに移す。移したら `.pna` は消す（アルファと `.pna` の両方があると、どちらが使われるか資料に書かれていない）。ネットワーク更新で配布しているゴーストでは、消した `.pna` を `delete.txt` に書くことを提案する（書式は https://ssp.shillest.net/ukadoc/manual/descript_install.html ）。
5. シェルのフォルダに書き戻す（`edit ... -Out shell/master/<ファイル名>.png`）。終了コード 2 なら、表示された注意（`seriko.use_self_alpha` が無い、`.pna` が隣にある）に対処する。
   - 画像の大きさや位置を変えたら、`surfaces.txt` の `collision`、`element` と `animation` の座標、`descript.txt` の吹き出しの位置など、座標を使う設定も合わせる。書式は推測で書かずに調べる（`AGENTS.md` の「仕様の調べ方」）。
6. 確かめる。
   - `tools/check-shell.ps1` を通す。
   - `tools/dump-surface.ps1 -Surface <番号>` で、SSP が合成した姿を見る（当たり判定を動かしたなら `-Collision` も）。`element` の抜けや位置のずれは、チェックが通っても見つからない。
   - SSP で動かしているなら、`tools/sstp.ps1 -Reload shell` で読み込み直し、`tools/sstp.ps1 -Script '\0\s[<番号>]\e'` で表示する。
7. 変えた画像、足した設定、消したファイルをまとめて報告する。作業前と作業後を `view` で並べた画像のパスも伝え、見た目の最終判断は作者にしてもらう。

## 関連

- コマンドと操作の一覧: `docs/agents/commands.md`
- シェルのチェック: `docs/agents/workflows/check.md`
- 実機で確かめる: `docs/agents/workflows/try-in-ssp.md`
