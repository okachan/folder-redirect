# FolderRedirect

Windows tool (PowerShell) that moves any folder to another drive and leaves a
**junction** at the original path, so applications keep working with the old
path while the data physically lives on the target drive.

Useful when software insists on installing / storing data on `C:` and you want
it on `E:` (or any other drive) instead.

---

## ⚠️ WARNING — USE AT YOUR OWN RISK / 利用は自己責任で

> **This tool MOVES folders and DELETES the original folder after copying,
> replacing it with a junction. If used incorrectly, applications may stop
> working and, in the worst case, data may be lost.**
>
> - **Always make a full backup before using it.**
> - **Test it first on an unimportant folder.**
> - Close the application that uses the target folder before moving it.
> - Do **not** use it on system folders. The script blocks `C:\Windows`,
>   `C:\Program Files`, `C:\Program Files (x86)`, the user profile root, etc.,
>   but this guard is not a guarantee.
> - Do not use it on folders synced by OneDrive / Dropbox / Google Drive, or on
>   database / VM files while they are in use.
> - The author provides this software "AS IS", **without warranty of any kind**
>   (see [LICENSE](LICENSE)), and accepts **no liability** for any damage or
>   data loss arising from its use.
>
> 日本語：このツールはフォルダを移動し、元フォルダを削除してジャンクションに
> 置き換えます。必ずバックアップを取り、最初は重要でないフォルダで試してください。
> 使用によって生じたいかなる損害・データ損失についても作者は責任を負いません。

---

## How it works

1. Copies the source folder to `<DestRoot>\<drive>\<original structure>`
   (e.g. `C:\Users\you\Foo` → `E:\C\Users\you\Foo`) with `robocopy`.
2. Verifies the copied size matches; if not, it aborts and keeps the original.
3. Deletes the original and creates a junction at the original path.

Undo copies the data back and removes the junction.

## Usage

GUI:

```bat
Run-FolderRedirect.bat
```

CLI:

```powershell
.\FolderRedirect.ps1 -ListJunctions
.\FolderRedirect.ps1 -Redirect "C:\Users\you\SomeAppData"
.\FolderRedirect.ps1 -Redirect "C:\Users\you\SomeAppData" -DestRoot "D:\"
.\FolderRedirect.ps1 -Redirect "C:\Users\you\SomeAppData" -Dest "D:\Data\SomeAppData"
.\FolderRedirect.ps1 -Undo "C:\Users\you\SomeAppData"
```

## Requirements

- Windows 10/11, Windows PowerShell 5.1 (built in). No installation needed.

## License

MIT — see [LICENSE](LICENSE). No warranty.
