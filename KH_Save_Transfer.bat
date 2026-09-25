<# : batch launcher (this line is a label for cmd and a comment for PowerShell)
@echo off
setlocal
set "KHST_SELF=%~f0"
set "KHST_SOURCE=%~1"
powershell -NoProfile -ExecutionPolicy Bypass -Command "& ([ScriptBlock]::Create((Get-Content -LiteralPath $env:KHST_SELF -Raw -Encoding UTF8)))"
echo.
pause
exit /b
#>

# ---------------------------------------------------------------------------
# KH PC Save Transfer
# Makes a Kingdom Hearts HD 1.5+2.5 / 2.8 save container downloaded from
# someone else load on YOUR Steam account.
#
# How it works: the container is a PNG with an "sqEX" chunk. Only its first
# 256 bytes (header) depend on the account: they are XOR-ed with a 16-byte
# per-account key, and header row 0 must equal MD5("<SteamID64>1").
# The save data itself is not touched.
#   your key    = your header row 0  XOR  MD5("<your SteamID64>1")
#   source key  = the repeated row in the source header (empty rows)
# The header is decrypted with the source key, row 0 is replaced with your
# MD5, it is re-encrypted with your key and the PNG CRC is recomputed.
# ---------------------------------------------------------------------------

$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @"
public static class KhstCrc {
    static uint[] table;
    public static uint Crc32(byte[] data, int offset, int count) {
        if (table == null) {
            table = new uint[256];
            for (uint n = 0; n < 256; n++) {
                uint c = n;
                for (int k = 0; k < 8; k++) c = (c & 1) != 0 ? 0xEDB88320u ^ (c >> 1) : c >> 1;
                table[n] = c;
            }
        }
        uint crc = 0xFFFFFFFFu;
        for (int i = offset; i < offset + count; i++) crc = table[(crc ^ data[i]) & 0xFF] ^ (crc >> 8);
        return crc ^ 0xFFFFFFFFu;
    }
}
"@

function Fail([string]$message) {
    Write-Host ''
    Write-Host "ERROR: $message" -ForegroundColor Red
    exit 1
}

function Get-SqexChunk([byte[]]$data, [string]$label) {
    $signature = [byte[]](0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A)
    for ($i = 0; $i -lt 8; $i++) { if ($data[$i] -ne $signature[$i]) { Fail "$label is not a PNG save container." } }
    $pos = 8
    while ($pos + 12 -le $data.Length) {
        $length = ([int]$data[$pos] -shl 24) -bor ([int]$data[$pos+1] -shl 16) -bor ([int]$data[$pos+2] -shl 8) -bor [int]$data[$pos+3]
        $type = [Text.Encoding]::ASCII.GetString($data, $pos + 4, 4)
        if ($type -eq 'sqEX') {
            if ($length -lt 256 -or $pos + 12 + $length -gt $data.Length) { Fail "$label has a damaged sqEX chunk." }
            return [pscustomobject]@{ TypeOffset = $pos + 4; DataOffset = $pos + 8; Length = $length; CrcOffset = $pos + 8 + $length }
        }
        if ($type -eq 'IEND') { break }
        $pos += 12 + $length
    }
    Fail "$label has no sqEX chunk: it is not a Kingdom Hearts PC save container."
}

function Get-Row([byte[]]$data, [int]$offset) {
    $row = New-Object byte[] 16
    [Array]::Copy($data, $offset, $row, 0, 16)
    return ,$row
}

function Xor16([byte[]]$a, [byte[]]$b) {
    $out = New-Object byte[] 16
    for ($i = 0; $i -lt 16; $i++) { $out[$i] = $a[$i] -bxor $b[$i] }
    return ,$out
}

function RowKey([byte[]]$row) { ($row | ForEach-Object { $_.ToString('x2') }) -join '' }

Write-Host 'KH PC Save Transfer - Kingdom Hearts HD 1.5+2.5 / 2.8 (Steam)' -ForegroundColor Cyan
Write-Host ''

# 1. Source save -------------------------------------------------------------
$source = $env:KHST_SOURCE
if ([string]::IsNullOrWhiteSpace($source)) {
    Write-Host 'Tip: you can drag the downloaded .png save onto this .bat file.'
    $source = Read-Host 'Path of the downloaded save file (e.g. KHFM.png)'
}
$source = $source.Trim().Trim('"')
if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { Fail "File not found: $source" }
$sourceBytes = [IO.File]::ReadAllBytes($source)
$src = Get-SqexChunk $sourceBytes 'The downloaded file'

$base = [IO.Path]::GetFileNameWithoutExtension($source) -replace '_(WW|JP|EN|US|EU)$', ''
Write-Host "Source save : $source"
Write-Host "Game file   : $base"

# 2. Save folder and Steam ID ------------------------------------------------
$docs = if ($env:KHST_DOCUMENTS) { $env:KHST_DOCUMENTS } else { [Environment]::GetFolderPath('MyDocuments') }
$collections = @('KINGDOM HEARTS HD 1.5+2.5 ReMIX', 'KINGDOM HEARTS HD 2.8 Final Chapter Prologue')
$candidates = @()
foreach ($collection in $collections) {
    $steamRoot = Join-Path $docs "My Games\$collection\Steam"
    if (-not (Test-Path -LiteralPath $steamRoot)) { continue }
    foreach ($idFolder in Get-ChildItem -LiteralPath $steamRoot -Directory | Where-Object { $_.Name -match '^7656119\d{10}$' }) {
        foreach ($file in Get-ChildItem -LiteralPath $idFolder.FullName -File -Filter "$base*.png") {
            if ($file.BaseName -match "^$([regex]::Escape($base))(_[A-Z]{2})?$") {
                $candidates += [pscustomobject]@{ SteamId = $idFolder.Name; Path = $file.FullName; Collection = $collection }
            }
        }
    }
}
if ($candidates.Count -eq 0) {
    Fail ("No Steam save container named '$base*.png' was found under`n  $docs\My Games\...\Steam\<SteamID>\`n" +
          "Start that game once from Steam (reach the title screen), close it, and run this again.")
}
$target = $candidates[0]
if ($candidates.Count -gt 1) {
    Write-Host ''
    Write-Host 'Several save containers match:'
    for ($i = 0; $i -lt $candidates.Count; $i++) { Write-Host ("  [{0}] {1}" -f ($i + 1), $candidates[$i].Path) }
    $choice = Read-Host 'Choose a number'
    $index = 0
    if (-not [int]::TryParse($choice, [ref]$index) -or $index -lt 1 -or $index -gt $candidates.Count) { Fail 'Invalid choice.' }
    $target = $candidates[$index - 1]
}
Write-Host "Your SteamID: $($target.SteamId)"
Write-Host "Destination : $($target.Path)"

# 3. Safety checks -------------------------------------------------------------
$running = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like 'KINGDOM HEARTS*' }
if ($running) { Fail 'Close every Kingdom Hearts game and the collection launcher first.' }

$targetBytes = [IO.File]::ReadAllBytes($target.Path)
$dst = Get-SqexChunk $targetBytes 'Your save container'
if ($targetBytes.Length -ne $sourceBytes.Length -or $dst.Length -ne $src.Length) {
    Fail 'The downloaded save and your container have different sizes: probably a different game or version.'
}

# 4. Keys ----------------------------------------------------------------------
$md5 = [Security.Cryptography.MD5]::Create()
$check = $md5.ComputeHash([Text.Encoding]::ASCII.GetBytes($target.SteamId + '1'))
$dstKey = Xor16 (Get-Row $targetBytes $dst.DataOffset) $check

# Sanity check: with the right key most header rows of your container decrypt to zeros.
$zeroRows = 0
for ($r = 1; $r -lt 16; $r++) {
    $plain = Xor16 (Get-Row $targetBytes ($dst.DataOffset + 16 * $r)) $dstKey
    if (($plain | Where-Object { $_ -ne 0 }).Count -eq 0) { $zeroRows++ }
}
if ($zeroRows -lt 6) { Fail 'Your container does not match the expected format (unknown game or format change). Nothing was changed.' }

$counts = @{}
for ($r = 1; $r -lt 16; $r++) {
    $key = RowKey (Get-Row $sourceBytes ($src.DataOffset + 16 * $r))
    if ($counts.ContainsKey($key)) { $counts[$key]++ } else { $counts[$key] = 1 }
}
$best = $counts.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1
if ($best.Value -lt 6) { Fail 'Could not recognise the header of the downloaded save. Nothing was changed.' }
$srcKey = [byte[]]($best.Key -split '(..)' | Where-Object { $_ } | ForEach-Object { [Convert]::ToByte($_, 16) })

if ((RowKey (Get-Row $sourceBytes $src.DataOffset)) -eq (RowKey (Get-Row $targetBytes $dst.DataOffset)) -and (RowKey $srcKey) -eq (RowKey $dstKey)) {
    Fail 'The downloaded save already belongs to this Steam account; just copy it over your container.'
}

# 5. Re-key the header ---------------------------------------------------------
$output = [byte[]]$sourceBytes.Clone()
for ($r = 0; $r -lt 16; $r++) {
    $offset = $src.DataOffset + 16 * $r
    $plain = Xor16 (Get-Row $sourceBytes $offset) $srcKey
    if ($r -eq 0) { $plain = $check }
    $cipher = Xor16 $plain $dstKey
    [Array]::Copy($cipher, 0, $output, $offset, 16)
}
$crc = [KhstCrc]::Crc32($output, $src.TypeOffset, 4 + $src.Length)
$output[$src.CrcOffset]     = [byte](($crc -shr 24) -band 0xFF)
$output[$src.CrcOffset + 1] = [byte](($crc -shr 16) -band 0xFF)
$output[$src.CrcOffset + 2] = [byte](($crc -shr 8) -band 0xFF)
$output[$src.CrcOffset + 3] = [byte]($crc -band 0xFF)

# 6. Backup and write ----------------------------------------------------------
$here = Split-Path -Parent $env:KHST_SELF
$backupDir = Join-Path $here 'backups'
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = Join-Path $backupDir ("{0}_{1}_{2}.png" -f [IO.Path]::GetFileNameWithoutExtension($target.Path), $target.SteamId, $stamp)
Copy-Item -LiteralPath $target.Path -Destination $backup
[IO.File]::WriteAllBytes($target.Path, $output)

Write-Host ''
Write-Host 'Done! The save now belongs to your Steam account.' -ForegroundColor Green
Write-Host "Backup of your previous saves: $backup"
Write-Host 'To undo: copy that backup over the destination file (rename it back to its original name).'
Write-Host 'If Steam asks about a cloud conflict, keep the LOCAL files.'
