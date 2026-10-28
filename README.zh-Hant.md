# 在新版 macOS 上使用京瓷 ECOSYS P8060cdn 列印（CUPS 修復）

[日本語](README.md) | **繁體中文** | [简体中文](README.zh-Hans.md) | [English](README.en.md)

在 Apple Silicon 的新版 macOS 上，向京瓷 ECOSYS P8060cdn（例如校園的 BYOD 列印佇列）列印時，文件印不出來。本儲存庫說明了原因和解決方法，並提供一個設定腳本。**不需要任何第三方驅動程式**，只使用已經安裝好的京瓷 PPD 和 macOS 內建的 CUPS 濾鏡。

> **非官方。** 京瓷為這台印表機提供了官方驅動程式。如果你的學校提供或支援 macOS 驅動程式，請優先使用官方的。本專案是為不對 Mac 使用者提供驅動程式支援的大學準備的，與京瓷和任何大學都沒有關係，也未獲得它們的認可，不提供任何擔保。

## 症狀

- 工作出錯停止，或是從佇列中消失了，但印表機上看不到。
- `/var/log/cups/error_log` 中記錄了京瓷濾鏡失敗，例如：

  ```
  [Job 5] PID ... (/usr/libexec/cups/filter/kyoprefilter_F) stopped with status 1.
  [Job 5] 4   kyofilter_F   ... dumpRawPrintableIntoTempFile + 420
  [Job 5] PID ... (/usr/libexec/cups/filter/kyofilter_F) crashed on signal 6.
  ```

## 原因

印表機的 PPD 檔案規定了用哪些程式（濾鏡）把文件轉換成印表機能辨識的資料。京瓷的 PPD 中有這兩行：

```
*cupsPreFilter: "application/pdf 0 kyoprefilter_F"
*cupsFilter: "application/vnd.cups-postscript 0 kyofilter_F"
```

所以每個工作都會經過 `/usr/libexec/cups/filter/` 中京瓷自己的濾鏡。這些是只支援 Intel / PowerPC 的舊程式（`x86_64`、`i386`、`ppc_7400`，沒有 `arm64`）。在 Apple Silicon 的新版 macOS 上（已在 macOS 27.2 確認）它們會異常結束，工作就遺失了。

## 修復原理

P8060cdn 本身就能辨識 **PostScript**，而 macOS 的 CUPS 內建完整的 PostScript 轉換流程（`cgpdftops` → `pstops`）。所以京瓷的濾鏡其實不是必要的：

1. **從 PPD 的副本中刪除 `*cupsFilter` / `*cupsPreFilter` 這兩行。** CUPS 就會改用內建的濾鏡。PPD 的其餘部分都保留，所以列印選項照樣能用：色彩模式、雙面列印等以 PostScript 的 `setpagedevice` 寫入，PJL 工作標頭來自 PPD 的 JCL 部分。
2. **讓學號成為工作的提交者。** 列印伺服器依使用者名稱把工作歸到帳號下。不做這一步的話，「預覽程式」、Chrome 等 App 會用 Mac 的登入名稱提交，印表機上就看不到工作。在 `~/.cups/client.conf` 中寫入 `User <學號>` 後，這個 Mac 帳號下的所有 App 都會用這個使用者名稱提交。使用者名稱會同時寫入 LPD 控制檔（`P<使用者名稱>`）和 PJL 工作標頭（`@PJL SET USERNAME = "<使用者名稱>"`）。
3. **預設改成黑白。** 把 `*DefaultColorModel` 改成 `Gray`。這一步可選，可以避免不小心印成彩色。
4. **正確顯示日文檔名。**（v2）CUPS 的 `pstops` 會把 PJL 工作名稱中的非 ASCII 字元換成 `?`，所以日文檔名在印表機面板上會顯示成方塊。日本型號的印表機要求 Shift-JIS 編碼。腳本會把一個小濾鏡 [`sjis-jobname`](sjis-jobname)（shell 腳本）安裝到 `/Library/Printers/kyocera-p8060cdn-fix/`，並在 PPD 中註冊為 `*cupsFilter`。它只用 Shift-JIS 重寫 `@PJL JOB NAME` 這一行（順便去掉「Microsoft Word - 」等前綴），列印資料原樣通過。

不列印也能檢查結果：

```sh
cupsfilter -p ~/kyocera-p8060cdn-fix/p8060cdn.ppd -m printer/foo -U <學號> test.txt | strings | grep @PJL
# @PJL SET USERNAME = "<學號>"
```

## 使用方法

前提：已經安裝了 P8060cdn 的京瓷 macOS 驅動程式（PPD 包含在其中），並且知道列印伺服器的位址（例如 `lpd://<伺服器>/<佇列>`，可以向學校的資訊單位確認）。

```sh
bash setup.sh
```

腳本會詢問學號、印表機位址、印表機名稱和型號。接著產生 `~/kyocera-p8060cdn-fix/p8060cdn.ppd`，做一次轉換測試，設定 `~/.cups/client.conf`，再用 `sudo lpadmin` 套用 PPD（會要求輸入 Mac 登入密碼）。`sudo` 需要真正的終端機，所以請在「終端機」中執行。

完成後，把用來列印的 App 完全結束（⌘Q）再重新開啟。彩色列印：列印視窗 →「印表機選項」→「印表機功能」→「グラフィックス」→「カラーモード」→「フルカラー」。

## 注意事項

- 只在京瓷濾鏡內部實作的功能（部分裝訂、部門管理、浮水印等）可能無法使用。一般列印、彩色／黑白和雙面列印都沒問題。
- `~/.cups/client.conf` 中的使用者名稱對這個 Mac 帳號使用的**所有**印表機都有效。
- 更新驅動程式可能會覆蓋印表機的 PPD。如果又無法列印，重新執行一次腳本即可。
- 還原方法：從 `~/.cups/client.conf` 刪除 `User` 那一行，然後在系統設定中刪除印表機再重新加入。也可以刪除 `/Library/Printers/kyocera-p8060cdn-fix/`。

## 更新紀錄

- **v2.0**：修正日文檔名在印表機面板上顯示成方塊的問題（`sjis-jobname` 濾鏡）。如果你用的是 v1，請下載新版儲存庫後重新執行 `bash setup.sh`。
- **v1.0**：第一版。拿掉京瓷濾鏡的 PPD、以學號作為使用者名稱、預設黑白。

## 授權

[Unlicense](LICENSE)（公眾領域）。
