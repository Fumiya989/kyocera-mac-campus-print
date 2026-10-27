# 新しい macOS で Kyocera ECOSYS P8060cdn に印刷する（CUPS 修正）

[English](README.md) | **日本語** | [中文](README.zh.md)

Apple Silicon の新しい macOS から Kyocera ECOSYS P8060cdn（学内の BYOD 印刷キューなど）に印刷しても、プリンターから出てきません。このリポジトリでは、その原因と回避方法を説明し、設定スクリプトを提供します。**サードパーティ製ドライバーは不要**で、インストール済みの京セラ PPD と macOS 標準の CUPS フィルターだけを使います。

> **非公式です。** このプリンターには京セラの公式ドライバーがあります。大学が macOS 用ドライバーを配布・サポートしている場合は、そちらを使ってください。このプロジェクトは、Mac 向けのドライバーサポートがない大学のためのものです。京セラやいずれの大学とも関係はなく、公認も受けていません。無保証です。

## 症状

- ジョブがエラーで止まる、またはキューからは消えるのにプリンターに表示されない。
- `/var/log/cups/error_log` に、京セラのフィルターの失敗が記録されている。例：

  ```
  [Job 5] PID ... (/usr/libexec/cups/filter/kyoprefilter_F) stopped with status 1.
  [Job 5] 4   kyofilter_F   ... dumpRawPrintableIntoTempFile + 420
  [Job 5] PID ... (/usr/libexec/cups/filter/kyofilter_F) crashed on signal 6.
  ```

## 原因

プリンターの PPD ファイルには、文書をプリンター用のデータに変換するプログラム（フィルター）が指定されています。京セラの PPD には次の行があります。

```
*cupsPreFilter: "application/pdf 0 kyoprefilter_F"
*cupsFilter: "application/vnd.cups-postscript 0 kyofilter_F"
```

そのため、すべてのジョブが `/usr/libexec/cups/filter/` にある京セラ独自のフィルターを通ります。これらは Intel / PowerPC 専用の古いバイナリ（`x86_64`、`i386`、`ppc_7400`。`arm64` はなし）です。Apple Silicon の新しい macOS（macOS 27.2 で確認）では異常終了し、ジョブが失われます。

## 修正のしくみ

P8060cdn は **PostScript** をそのまま理解でき、macOS の CUPS には PostScript 用の変換経路（`cgpdftops` → `pstops`）が標準で備わっています。つまり京セラのフィルターは実は不要です。

1. **PPD のコピーから `*cupsFilter` / `*cupsPreFilter` の行を削除します。** すると CUPS は標準フィルターを使います。PPD のそれ以外の部分は残るので、印刷オプションはそのまま使えます。カラーモードや両面印刷などは PostScript の `setpagedevice` として、PJL ヘッダーは PPD の JCL 部分から挿入されます。
2. **学籍番号をジョブの所有者にします。** 印刷サーバーはユーザー名でジョブとアカウントを結び付けます。この設定がないと、プレビューや Chrome などのアプリは Mac のログイン名で送信するため、プリンター側にジョブが表示されません。`~/.cups/client.conf` に `User <学籍番号>` と書くと、この Mac アカウントのすべてのアプリがそのユーザー名で送信します。ユーザー名は LPD の制御ファイル（`P<ユーザー>`）と PJL ヘッダー（`@PJL SET USERNAME = "<ユーザー>"`）の両方に入ります。
3. **デフォルトを白黒にします。** `*DefaultColorModel` を `Gray` に変えます。任意ですが、うっかりカラー印刷するのを防げます。

印刷せずに結果を確認できます。

```sh
cupsfilter -p ~/kyocera-p8060cdn-fix/p8060cdn.ppd -m printer/foo -U <学籍番号> test.txt | strings | grep @PJL
# @PJL SET USERNAME = "<学籍番号>"
```

## 使い方

必要なもの：P8060cdn 用の京セラ macOS ドライバー（PPD はこれに含まれます）がインストール済みであること。印刷サーバーの URI（例：`lpd://<サーバー>/<キュー>`。情報システム担当に確認してください）。

```sh
bash setup.sh
```

スクリプトは学籍番号、プリンターの URI、プリンター名、機種を尋ねます。そのあと `~/kyocera-p8060cdn-fix/p8060cdn.ppd` を作成して変換テストを行い、`~/.cups/client.conf` を設定し、`sudo lpadmin` で PPD を適用します（Mac のパスワードを求められます）。`sudo` には本物のターミナルが必要なので、「ターミナル」で実行してください。

完了したら、印刷に使うアプリを一度終了（⌘Q）して開き直してください。カラー印刷は、印刷画面 →「プリンタオプション」→「プリンタの機能」→「グラフィックス」→「カラーモード」→「フルカラー」。

## 注意

- 京セラのフィルター内部でだけ実装されている機能（一部の仕上げ、部門管理、透かしなど）は動かない場合があります。通常の印刷、カラー／白黒、両面印刷は動作します。
- `~/.cups/client.conf` のユーザー名は、この Mac アカウントから使う**すべての**プリンターに適用されます。
- ドライバーを更新すると、プリンターの PPD が上書きされることがあります。また印刷できなくなったら、スクリプトをもう一度実行してください。
- 元に戻すには、`~/.cups/client.conf` から `User` 行を削除し、システム設定でプリンターを削除してから追加し直します。

## ライセンス

[Unlicense](LICENSE)（パブリックドメイン）。
