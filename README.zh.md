# 在新版 macOS 上使用京瓷 ECOSYS P8060cdn 打印（CUPS 修复）

[English](README.md) | [日本語](README.ja.md) | **中文**

在 Apple Silicon 的新版 macOS 上，向京瓷 ECOSYS P8060cdn（例如校园的 BYOD 打印队列）打印时，文件打不出来。本仓库说明了原因和解决办法，并提供一个设置脚本。**不需要任何第三方驱动**，只用已经安装好的京瓷 PPD 和 macOS 自带的 CUPS 滤镜。

> **非官方。** 京瓷为这台打印机提供了官方驱动。如果你的学校提供或支持 macOS 驱动，请优先使用官方的。本项目是给不为 Mac 用户提供驱动支持的大学准备的，与京瓷和任何大学都没有关系，也没有得到它们的认可，不提供任何担保。

## 症状

- 任务报错停止，或者从队列里消失了，但打印机上看不到。
- `/var/log/cups/error_log` 里记录了京瓷滤镜失败，例如：

  ```
  [Job 5] PID ... (/usr/libexec/cups/filter/kyoprefilter_F) stopped with status 1.
  [Job 5] 4   kyofilter_F   ... dumpRawPrintableIntoTempFile + 420
  [Job 5] PID ... (/usr/libexec/cups/filter/kyofilter_F) crashed on signal 6.
  ```

## 原因

打印机的 PPD 文件规定了用哪些程序（滤镜）把文档转换成打印机能识别的数据。京瓷的 PPD 里有这两行：

```
*cupsPreFilter: "application/pdf 0 kyoprefilter_F"
*cupsFilter: "application/vnd.cups-postscript 0 kyofilter_F"
```

所以每个任务都会经过 `/usr/libexec/cups/filter/` 里京瓷自己的滤镜。这些是只支持 Intel / PowerPC 的老程序（`x86_64`、`i386`、`ppc_7400`，没有 `arm64`）。在 Apple Silicon 的新版 macOS 上（在 macOS 27.2 上确认）它们会异常退出，任务就丢了。

## 修复原理

P8060cdn 本身就能识别 **PostScript**，而 macOS 的 CUPS 自带完整的 PostScript 转换流程（`cgpdftops` → `pstops`）。所以京瓷的滤镜其实不是必需的：

1. **从 PPD 的副本里删掉 `*cupsFilter` / `*cupsPreFilter` 这两行。** CUPS 就会改用自带的滤镜。PPD 的其余部分都保留，所以打印选项照样能用：颜色模式、双面打印等以 PostScript 的 `setpagedevice` 写入，PJL 任务头来自 PPD 的 JCL 部分。
2. **让学号成为任务的提交者。** 打印服务器按用户名把任务归到账号下。不做这一步的话，「预览」、Chrome 等应用会用 Mac 的登录名提交，打印机上就看不到任务。在 `~/.cups/client.conf` 里写入 `User <学号>` 后，这个 Mac 账号下的所有应用都会用这个用户名提交。用户名会同时写进 LPD 控制文件（`P<用户名>`）和 PJL 任务头（`@PJL SET USERNAME = "<用户名>"`）。
3. **默认改成黑白。** 把 `*DefaultColorModel` 改成 `Gray`。这一步可选，可以避免不小心打成彩色。

不打印也能检查结果：

```sh
cupsfilter -p ~/kyocera-p8060cdn-fix/p8060cdn.ppd -m printer/foo -U <学号> test.txt | strings | grep @PJL
# @PJL SET USERNAME = "<学号>"
```

## 使用方法

前提：已经安装了 P8060cdn 的京瓷 macOS 驱动（PPD 包含在里面），并且知道打印服务器的地址（例如 `lpd://<服务器>/<队列>`，可以向学校的信息部门确认）。

```sh
bash setup.sh
```

脚本会询问学号、打印机地址、打印机名称和型号。然后生成 `~/kyocera-p8060cdn-fix/p8060cdn.ppd`，做一次转换测试，设置 `~/.cups/client.conf`，再用 `sudo lpadmin` 应用 PPD（会要求输入 Mac 登录密码）。`sudo` 需要真正的终端，所以请在「终端」里运行。

完成后，把用来打印的应用完全退出（⌘Q）再重新打开。彩色打印：打印窗口 →「打印机选项」→「打印机功能」→「グラフィックス」→「カラーモード」→「フルカラー」。

## 注意事项

- 只在京瓷滤镜内部实现的功能（部分装订、部门管理、水印等）可能用不了。普通打印、彩色／黑白和双面打印都没问题。
- `~/.cups/client.conf` 里的用户名对这个 Mac 账号使用的**所有**打印机都生效。
- 更新驱动可能会覆盖打印机的 PPD。如果又打印不了，重新运行一次脚本就行。
- 还原方法：从 `~/.cups/client.conf` 删掉 `User` 那一行，然后在系统设置里删除打印机再重新添加。

## 许可证

[Unlicense](LICENSE)（公共领域）。
