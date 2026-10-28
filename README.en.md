# Kyocera ECOSYS P8060cdn on new macOS (CUPS fix)

[日本語](README.md) | [繁體中文](README.zh-Hant.md) | [简体中文](README.zh-Hans.md) | **English**

Printing to a Kyocera ECOSYS P8060cdn (e.g. a campus BYOD print queue) from a recent macOS on Apple Silicon fails: jobs never print. This repository explains why and provides a script that works around it **without any third-party driver** — only the Kyocera PPD that is already installed, plus macOS's built-in CUPS filters.

> **Unofficial.** Kyocera provides official drivers for this printer. If your university distributes or supports a macOS driver, use that instead. This project is for universities that leave Mac users without driver support. It is not affiliated with or endorsed by Kyocera or any university, and comes with no warranty.

## Symptoms

- Jobs stop with an error, or leave the queue but never appear at the printer.
- `/var/log/cups/error_log` shows the Kyocera filters failing, for example:

  ```
  [Job 5] PID ... (/usr/libexec/cups/filter/kyoprefilter_F) stopped with status 1.
  [Job 5] 4   kyofilter_F   ... dumpRawPrintableIntoTempFile + 420
  [Job 5] PID ... (/usr/libexec/cups/filter/kyofilter_F) crashed on signal 6.
  ```

## Why it happens

A printer's PPD file tells CUPS which programs ("filters") convert a document into data the printer understands. The Kyocera PPD contains:

```
*cupsPreFilter: "application/pdf 0 kyoprefilter_F"
*cupsFilter: "application/vnd.cups-postscript 0 kyofilter_F"
```

so every job is pushed through Kyocera's own filters in `/usr/libexec/cups/filter/`. Those binaries are old Intel/PowerPC-only programs (`x86_64`, `i386`, `ppc_7400` — no `arm64`). On recent macOS on Apple Silicon (observed on macOS 27.2) they abort, so the job is lost.

## How the fix works

The P8060cdn understands **PostScript** natively, and macOS's CUPS already has a complete PostScript pipeline (`cgpdftops` → `pstops`). So the Kyocera filters are not actually needed:

1. **Remove the `*cupsFilter` / `*cupsPreFilter` lines** from a copy of the PPD. CUPS then falls back to its built-in filters. Everything else in the PPD stays, so print options still work: color mode, duplex and so on are injected as PostScript `setpagedevice` code, and the PJL job header comes from the PPD's JCL section.
2. **Make the student ID the job owner.** The print server matches jobs to accounts by user name. Without this, apps such as Preview or Chrome submit jobs as the Mac login name, and the job never shows up at the printer. Writing `User <student ID>` to `~/.cups/client.conf` makes every app on this Mac account submit as that user. It ends up in both the LPD control file (`P<user>`) and the PJL header (`@PJL SET USERNAME = "<user>"`).
3. **Default to grayscale** by changing `*DefaultColorModel` to `Gray`. Optional, but it avoids accidental color prints.
4. **Show Japanese file names correctly.** (v2) CUPS's `pstops` replaces non-ASCII characters in the PJL job name with `?`, so Japanese file names show up as boxes on the printer panel. The Japanese-market models expect Shift-JIS. A small filter, [`sjis-jobname`](sjis-jobname) (a shell script), is installed in `/Library/Printers/kyocera-p8060cdn-fix/` and registered in the PPD as a `*cupsFilter`. It rewrites only the `@PJL JOB NAME` line in Shift-JIS (also dropping prefixes such as "Microsoft Word - ") and passes the print data through unchanged.

You can check the result without printing:

```sh
cupsfilter -p ~/kyocera-p8060cdn-fix/p8060cdn.ppd -m printer/foo -U <student ID> test.txt | strings | grep @PJL
# @PJL SET USERNAME = "<student ID>"
```

## Usage

Requirements: the Kyocera macOS driver for the P8060cdn is installed (it provides the PPD), and you know the print server URI (for example `lpd://<server>/<queue>`; ask your IT office).

```sh
bash setup.sh
```

The script asks for your student ID, the printer URI, a printer name and the model. It then builds `~/kyocera-p8060cdn-fix/p8060cdn.ppd`, runs a conversion test, sets `~/.cups/client.conf` and applies the PPD with `sudo lpadmin`, which asks for your Mac password. Run it in Terminal, because `sudo` needs a real terminal.

After it finishes, quit (⌘Q) and reopen any app you print from. For color: Print → Printer Options → Printer Features → Graphics → Color Mode → Full Color.

## Caveats

- Features implemented only inside Kyocera's filters (some finishing, accounting or watermark functions) may not work. Plain printing, color/grayscale and duplex do work.
- `~/.cups/client.conf` sets the user name for **all** printers used from this Mac account.
- A driver update can overwrite the printer's PPD. If printing breaks again, run the script again.
- To undo: remove the `User` line from `~/.cups/client.conf`, and delete and re-add the printer in System Settings. You can also delete `/Library/Printers/kyocera-p8060cdn-fix/`.

## Changelog

- **v2.0**: Fix Japanese file names showing as boxes on the printer panel (`sjis-jobname` filter). If you set up v1, get the new repository and run `bash setup.sh` again.
- **v1.0**: First version. PPD without Kyocera's filters, student ID as user name, grayscale default.

## License

[Unlicense](LICENSE) (public domain).
