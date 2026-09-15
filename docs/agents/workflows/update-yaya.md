# yaya.dll の更新

## 使うとき

作者が「yaya.dll を更新して」「YAYA を新しくして」「SHIORI を最新に」と言ったとき。

**作者にはっきり頼まれたときだけ行う。自分から始めない。**

## 手順

1. `powershell -NoProfile -ExecutionPolicy Bypass -File tools/update-yaya.ps1 -DryRun` で、今のバージョンと更新先を確かめて作者に伝える。作者がタグを指定したときだけ `-Tag <タグ>` を付ける（指定が無ければ最新リリース）。
2. SSP でこのゴーストを起動していると yaya.dll が使用中で置き換えられない。ゴーストを終了してもらう。
3. `tools/update-yaya.ps1` を実行する。新しい dll で辞書チェックに失敗した場合は、自動で元の dll に戻る。
4. 出力に表示されたリリースノートの URL を読み、互換性に関わる変更があれば要約して伝える。
