# FolderRedirect.ps1 - v1.0.2
# !!! USE AT YOUR OWN RISK !!!
# This tool moves a folder, deletes the original after copying, and replaces it
# with a junction. If used incorrectly, applications may stop working and data
# may be lost. Always back up first and test on an unimportant folder.
# The author accepts no liability. See README.md and LICENSE.
#
# Generic tool: moves any folder to a target drive and points the original
# path at it with a junction, so apps keep seeing the original path.
# NOTE: This file is intentionally ASCII-only. Windows PowerShell 5.1 reads
# UTF-8 files without BOM as the system ANSI code page, which corrupts
# non-ASCII text and breaks parsing.
#
# CLI:
#   .\FolderRedirect.ps1 -ListJunctions
#   .\FolderRedirect.ps1 -Redirect "C:\Users\you\SomeFolder" [-DestRoot "E:\"] [-Dest "E:\Data\Foo"]
#   .\FolderRedirect.ps1 -Undo     "C:\Users\you\SomeFolder"
# GUI:
#   .\FolderRedirect.ps1

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
    # <root>\<drive>\<original structure>  e.g. C:\Users\x\Foo -> E:\C\Users\x\Foo
    $drive = $src.Substring(0,1)
    Join-Path (Join-Path $root $drive) $src.Substring(3)
}
function Get-SizeGB($p) {
    if (-not (Test-Path $p)) { return 0 }
    $s = (Get-ChildItem $p -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    if (-not $s) { 0 } else { [math]::Round($s / 1GB, 2) }
}

function Do-Redirect($src, $root, $dst) {
    if (-not $src) { return "No target specified." }
    $src = $src.TrimEnd('\')
    if ($src -match '^[A-Za-z]:$') { return "Drive root cannot be a target." }
    # Safety guard: block system trees (prefix) and a few roots (exact match only)
    $blockedPrefix = @($env:windir, "C:\Program Files", "C:\Program Files (x86)", "C:\ProgramData\Microsoft", "C:\Recovery", "C:\System Volume Information")
    $blockedExact  = @($env:USERPROFILE, "C:\Users")
    foreach ($b in $blockedPrefix) {
        if ($b -and ($src -ieq $b -or $src.StartsWith($b.TrimEnd('\') + '\', [System.StringComparison]::OrdinalIgnoreCase))) {
            return "Aborted (safety guard): system folders cannot be targets: $src"
        }
    }
    foreach ($b in $blockedExact) {
        if ($b -and ($src -ieq $b)) {
            return "Aborted (safety guard): this folder itself cannot be a target: $src"
        }
    }
    if (Is-Junction $src) { return "Already a junction: $src" }
    if (-not $dst) { $dst = Default-Dest $src $root }
    if (Test-Path $dst) {
        $empty = -not (Get-ChildItem $dst -Force -ErrorAction SilentlyContinue)
        if (-not $empty) { return "Aborted: destination already has content: $dst" }
    }
    New-Item -ItemType Directory -Path $dst -Force | Out-Null
    if (Test-Path $src) {
        robocopy $src $dst /E /COPY:DAT /R:1 /W:1 /NFL /NDL /NJH /NJS | Out-Null
        if ($LASTEXITCODE -ge 8) { return "Failed (copy, robocopy=$LASTEXITCODE): $src . Close the app using it and retry." }
        $a = Get-SizeGB $src; $b = Get-SizeGB $dst
        if ([math]::Abs($a - $b) -gt 0.05 -and $a -gt 0) { return "Aborted: size mismatch src=$a GB dst=$b GB (original kept)" }
        Remove-Item $src -Recurse -Force
    }
    New-Item -ItemType Directory -Path (Split-Path $src) -Force | Out-Null
    cmd /c mklink /J "`"$src`"" "`"$dst`"" | Out-Null
    if (Is-Junction $src) { "OK: $src -> $dst" } else { "Failed (junction): $src (data is in $dst)" }
}

function Do-Undo($src) {
    $src = $src.TrimEnd('\')
    if (-not (Is-Junction $src)) { return "Not a junction: $src" }
    $target = (Get-Item $src -Force).Target; if ($target -is [array]) { $target = $target[0] }
    cmd /c rmdir "`"$src`"" | Out-Null
    robocopy $target $src /E /MOVE /COPY:DAT /R:1 /W:1 /NFL /NDL /NJH /NJS | Out-Null
    if ($LASTEXITCODE -ge 8) { return "Failed (undo, robocopy=$LASTEXITCODE): data remains in $target" }
    "Restored: $src"
}

function Find-Junctions {
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
$form.Text = "Folder Redirect"
$form.Size = New-Object Drawing.Size(780, 500)

$lbl = New-Object Windows.Forms.Label
$lbl.Text = "Target drive:"; $lbl.Location = New-Object Drawing.Point(10,12); $lbl.AutoSize = $true
$form.Controls.Add($lbl)

$destBox = New-Object Windows.Forms.TextBox
$destBox.Text = $DestRoot; $destBox.Location = New-Object Drawing.Point(110,10); $destBox.Size = New-Object Drawing.Size(70,22)
$form.Controls.Add($destBox)

$pathBox = New-Object Windows.Forms.TextBox
$pathBox.Location = New-Object Drawing.Point(10,42); $pathBox.Size = New-Object Drawing.Size(620,22)
$form.Controls.Add($pathBox)

$btnPick = New-Object Windows.Forms.Button
$btnPick.Text = "Pick folder"; $btnPick.Location = New-Object Drawing.Point(640,40); $btnPick.Size = New-Object Drawing.Size(110,26)
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
    if ($listBox.Items.Count -eq 0) { [void]$listBox.Items.Add("(no junctions)") }
}
Refresh-List

$btnGo = New-Object Windows.Forms.Button
$btnGo.Text = "Move this folder to target drive"; $btnGo.Location = New-Object Drawing.Point(10,78); $btnGo.Size = New-Object Drawing.Size(220,30)
$btnGo.Add_Click({
    $r = Do-Redirect $pathBox.Text $destBox.Text ""
    $logBox.AppendText($r + "`r`n"); Refresh-List
})
$form.Controls.Add($btnGo)

$btnUndo = New-Object Windows.Forms.Button
$btnUndo.Text = "Restore selected junction"; $btnUndo.Location = New-Object Drawing.Point(240,78); $btnUndo.Size = New-Object Drawing.Size(230,30)
$btnUndo.Add_Click({
    if ($listBox.SelectedItem -and $listBox.SelectedItem -match '^(.*?)\s+->') {
        $r = Do-Undo $Matches[1]
        $logBox.AppendText($r + "`r`n"); Refresh-List
    }
})
$form.Controls.Add($btnUndo)

$btnRef = New-Object Windows.Forms.Button
$btnRef.Text = "Refresh list"; $btnRef.Location = New-Object Drawing.Point(480,78); $btnRef.Size = New-Object Drawing.Size(110,30)
$btnRef.Add_Click({ Refresh-List })
$form.Controls.Add($btnRef)

[void]$form.ShowDialog()
