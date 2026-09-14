---
name: update-yaya
description: ghost/master/yaya.dll を YAYA の最新リリース（または指定したタグ）に更新し、辞書チェックが通ることを確かめる。
disable-model-invocation: true
argument-hint: "[タグ（省略すると最新）]"
---

# yaya.dll の更新

1. `powershell -NoProfile -ExecutionPolicy Bypass -File tools/update-yaya.ps1 -DryRun` で、今のバージョンと更新先を確かめてユーザーに伝える。タグを指定するときは `-Tag <タグ>` を付ける。
2. SSP でこのゴーストを起動していると yaya.dll が使用中で置き換えられない。ゴーストを終了してもらう。
3. `tools/update-yaya.ps1` を実行する。新しい dll で辞書チェックに失敗した場合は、自動で元の dll に戻る。
4. 出力に表示されたリリースノートの URL を読み、互換性に関わる変更があれば要約して伝える。

$ARGUMENTS
