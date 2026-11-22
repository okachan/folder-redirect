# FolderRedirect.ps1 - v1.0
# !!! USE AT YOUR OWN RISK / 利用は自己責任 !!!
# このツールはフォルダを移動し、元フォルダを削除してジャンクションに置き換えます。
# 使い方を誤るとアプリが動かなくなったり、最悪データが失われる可能性があります。
# 必ずバックアップを取り、最初は重要でないフォルダで試してください。作者は一切の責任を負いません。
#
# 任意のフォルダを、指定ドライブへ実体を移してジャンクションで元パスへ向ける汎用ツール。
# アプリからは元パス（C:\...）に見えるので再設定不要。
#
# CLI:
#   .\FolderRedirect.ps1 -ListJunctions                 … 既存ジャンクション一覧
#   .\FolderRedirect.ps1 -Redirect "C:\Users\x\AppData\Local\Foo" [-DestRoot "E:\"] [-Dest "E:\Data\Foo"]
#   .\FolderRedirect.ps1 -Undo     "C:\Users\x\AppData\Local\Foo"
# GUI:
#   .\FolderRedirect.ps1                                 … フォルダを選んで移動／戻す

param(
    [switch]$ListJunctions,
    [string]$Redirect,
    [string]$Undo,
    [string]$DestRoot = "E:\",
    [string]$Dest = ""
)

$ErrorActionPreference = "Stop"

function Is-Junction($p) {
    (Test-Path $p) -and ((Get-Item $p -Force).LinkType -eq "Junction")
}
function Default-Dest($src, $root) {
    # <root>\<元のドライブ名>\<構造そのまま>  例: C:\Users\x\Foo -> E:\C\Users\x\Foo
    $drive = $src.Substring(0,1)
    Join-Path (Join-Path $root $drive) $src.Substring(3)
}
function Get-SizeGB($p) {
    if (-not (Test-Path $p)) { return 0 }
    $s = (Get-ChildItem $p -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    if (-not $s) { 0 } else { [math]::Round($s / 1GB, 2) }
}

function Do-Redirect($src, $root, $dst) {
    if (-not $src) { return "対象が空です" }
    $src = $src.TrimEnd('\')
    if ($src -match '^[A-Za-z]:$') { return "ドライブ直下は対象にできません" }
    # 安全ガード：システム系・プロファイル直下は拒否
    $blocked = @($env:windir, "C:\Program Files", "C:\Program Files (x86)", "C:\ProgramData\Microsoft", $env:USERPROFILE, "C:\Users", "C:\Recovery", "C:\System Volume Information")
    foreach ($b in $blocked) {
        if ($b -and ($src -ieq $b -or $src.StartsWith($b.TrimEnd('\') + '\', [System.StringComparison]::OrdinalIgnoreCase))) {
            return "中止（安全ガード）: システム系フォルダは対象にできません: $src"
        }
    }
    if (Is-Junction $src) { return "済み（既にジャンクション）: $src" }
    if (-not $dst) { $dst = Default-Dest $src $root }
    if (Test-Path $dst) {
        $empty = -not (Get-ChildItem $dst -Force -ErrorAction SilentlyContinue)
        if (-not $empty) { return "中止: 移動先に既に中身があります: $dst" }
    }
    # 実行中プロセスが掴んでいそうな場合は robocopy 失敗で検出される。先に案内だけ。
    New-Item -ItemType Directory -Path $dst -Force | Out-Null
    if (Test-Path $src) {
        robocopy $src $dst /E /COPY:DAT /R:1 /W:1 /NFL /NDL /NJH /NJS | Out-Null
        if ($LASTEXITCODE -ge 8) { return "失敗（コピー、robocopy=$LASTEXITCODE）: $src 。対象アプリを終了して再実行してください" }
        $a = Get-SizeGB $src; $b = Get-SizeGB $dst
        if ([math]::Abs($a - $b) -gt 0.05 -and $a -gt 0) { return "中止: サイズ不一致 元=$a GB 先=$b GB（元は残してあります）" }
        Remove-Item $src -Recurse -Force
    }
    New-Item -ItemType Directory -Path (Split-Path $src) -Force | Out-Null
    cmd /c mklink /J "`"$src`"" "`"$dst`"" | Out-Null
    if (Is-Junction $src) { "OK: $src -> $dst" } else { "失敗（リンク作成）: $src （データは $dst）" }
}

function Do-Undo($src) {
    $src = $src.TrimEnd('\')
    if (-not (Is-Junction $src)) { return "ジャンクションではありません: $src" }
    $target = (Get-Item $src -Force).Target; if ($target -is [array]) { $target = $target[0] }
    cmd /c rmdir "`"$src`"" | Out-Null
    robocopy $target $src /E /MOVE /COPY:DAT /R:1 /W:1 /NFL /NDL /NJH /NJS | Out-Null
    if ($LASTEXITCODE -ge 8) { return "失敗（戻し、robocopy=$LASTEXITCODE）: データは $target に残っています" }
    "戻した: $src"
}

function Find-Junctions {
    # よく使う配下だけを走査（全ドライブ走査は遅いのでしない）
    $roots = @("$env:USERPROFILE", "$env:LOCALAPPDATA", "$env:APPDATA", "$env:ProgramData", "C:\Program Files", "C:\Program Files (x86)")
    $out = @()
    foreach ($r in $roots) {
        if (-not (Test-Path $r)) { continue }
        Get-ChildItem $r -Directory -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.LinkType -eq "Junction" } |
            ForEach-Object { $out += [PSCustomObject]@{ Path = $_.FullName; Target = ($_.Target -join ',') } }
    }
    $out
}

if ($ListJunctions) { Find-Junctions | Format-Table -AutoSize; return }
if ($Redirect) { Write-Host (Do-Redirect $Redirect $DestRoot $Dest); return }
if ($Undo)     { Write-Host (Do-Undo $Undo); return }

# --- GUI ---
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$form = New-Object Windows.Forms.Form
$form.Text = "Folder Redirect （汎用）"
$form.Size = New-Object Drawing.Size(780, 500)

$lbl = New-Object Windows.Forms.Label
$lbl.Text = "移動先ドライブ:"; $lbl.Location = New-Object Drawing.Point(10,12); $lbl.AutoSize = $true
$form.Controls.Add($lbl)

$destBox = New-Object Windows.Forms.TextBox
$destBox.Text = $DestRoot; $destBox.Location = New-Object Drawing.Point(110,10); $destBox.Size = New-Object Drawing.Size(70,22)
$form.Controls.Add($destBox)

$pathBox = New-Object Windows.Forms.TextBox
$pathBox.Location = New-Object Drawing.Point(10,42); $pathBox.Size = New-Object Drawing.Size(620,22)
$pathBox.PlaceholderText = "対象フォルダ（C:\...）"
$form.Controls.Add($pathBox)

$btnPick = New-Object Windows.Forms.Button
$btnPick.Text = "フォルダ選択"; $btnPick.Location = New-Object Drawing.Point(640,40); $btnPick.Size = New-Object Drawing.Size(110,26)
$btnPick.Add_Click({
    $d = New-Object Windows.Forms.FolderBrowserDialog
    if ($d.ShowDialog() -eq "OK") { $pathBox.Text = $d.SelectedPath }
})
$form.Controls.Add($btnPick)

$logBox = New-Object Windows.Forms.TextBox
$logBox.Multiline = $true; $logBox.ScrollBars = "Vertical"; $logBox.ReadOnly = $true
$logBox.Location = New-Object Drawing.Point(10,120); $logBox.Size = New-Object Drawing.Size(740,180)
$form.Controls.Add($logBox)

$listBox = New-Object Windows.Forms.ListBox
$listBox.Location = New-Object Drawing.Point(10,315); $listBox.Size = New-Object Drawing.Size(740,110)
$form.Controls.Add($listBox)

function Refresh-List {
    $listBox.Items.Clear()
    Find-Junctions | ForEach-Object { [void]$listBox.Items.Add("$($_.Path)  ->  $($_.Target)") }
    if ($listBox.Items.Count -eq 0) { [void]$listBox.Items.Add("（ジャンクションなし）") }
}
Refresh-List

$btnGo = New-Object Windows.Forms.Button
$btnGo.Text = "このフォルダを指定ドライブへ"; $btnGo.Location = New-Object Drawing.Point(10,78); $btnGo.Size = New-Object Drawing.Size(220,30)
$btnGo.Add_Click({
    $r = Do-Redirect $pathBox.Text $destBox.Text ""
    $logBox.AppendText($r + "`r`n"); Refresh-List
})
$form.Controls.Add($btnGo)

$btnUndo = New-Object Windows.Forms.Button
$btnUndo.Text = "選択中のジャンクションを戻す"; $btnUndo.Location = New-Object Drawing.Point(240,78); $btnUndo.Size = New-Object Drawing.Size(230,30)
$btnUndo.Add_Click({
    if ($listBox.SelectedItem -and $listBox.SelectedItem -match '^(.*?)\s+->') {
        $r = Do-Undo $Matches[1]
        $logBox.AppendText($r + "`r`n"); Refresh-List
    }
})
$form.Controls.Add($btnUndo)

$btnRef = New-Object Windows.Forms.Button
$btnRef.Text = "一覧を更新"; $btnRef.Location = New-Object Drawing.Point(480,78); $btnRef.Size = New-Object Drawing.Size(110,30)
$btnRef.Add_Click({ Refresh-List })
$form.Controls.Add($btnRef)

[void]$form.ShowDialog()
