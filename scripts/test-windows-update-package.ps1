$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/../windows/runner/validate_update_package.ps1"
Add-Type -AssemblyName System.IO.Compression.FileSystem
$root = Join-Path ([IO.Path]::GetTempPath()) ('vizor-update-test-' + [guid]::NewGuid())
New-Item -ItemType Directory $root | Out-Null
try {
  $cases = @('x64', 'arm64', 'wrong-id', 'wrong-channel', 'wrong-version', 'wrong-rid',
    'wrong-machine', 'wrong-pe', 'missing-pe', 'duplicate-manifest', 'traversal', 'dtd', 'wrong-hash', 'trailing-dot', 'trailing-space', 'duplicate-case')
  foreach ($case in $cases) {
    $path = Join-Path $root "$case.nupkg"
    $arch = if ($case -eq 'x64') { 'x64' } else { 'arm64' }
    $id = 'com.keplr.vizor'; $version = '1.2.3'; $channel = "win-$arch-mainnet"
    $manifestId = if ($case -eq 'wrong-id') { 'com.keplr.vizor.testnet' } else { $id }
    $manifestChannel = if ($case -eq 'wrong-channel') { 'win-x64-testnet' } else { $channel }
    $manifestVersion = if ($case -eq 'wrong-version') { '1.2.4' } else { $version }
    $rid = if ($case -eq 'wrong-rid') { 'win-x86' } else { "win-$arch" }
    $machineArch = if ($case -eq 'wrong-machine') { 'x86' } else { $arch }
    $xml = "<package><metadata><id>$manifestId</id><version>$manifestVersion</version><channel>$manifestChannel</channel><os>win</os><rid>$rid</rid><machineArchitecture>$machineArch</machineArchitecture><mainExe>Vizor.exe</mainExe></metadata></package>"
    if ($case -eq 'dtd') { $xml = '<!DOCTYPE package [<!ENTITY bad SYSTEM "file:///nonexistent">]>' + $xml }
    $zip = [IO.Compression.ZipFile]::Open($path, [IO.Compression.ZipArchiveMode]::Create)
    try {
      $entry = $zip.CreateEntry('app.nuspec'); $writer = [IO.StreamWriter]::new($entry.Open())
      $writer.Write($xml); $writer.Dispose()
      if ($case -eq 'duplicate-manifest') { $null = $zip.CreateEntry('other.nuspec') }
      if ($case -eq 'trailing-dot') { $null = $zip.CreateEntry('lib/app/Vizor.exe.') }
      if ($case -eq 'trailing-space') { $null = $zip.CreateEntry('lib/app/Vizor.exe ') }
      if ($case -eq 'duplicate-case') { $null = $zip.CreateEntry('lib/app/VIZOR.EXE') }
      if ($case -eq 'traversal') { $null = $zip.CreateEntry('../bad.exe') }
      foreach ($name in @('Vizor.exe', 'flutter_windows.dll', 'rust_lib_zcash_wallet.dll')) {
        if ($case -eq 'missing-pe' -and $name -eq 'flutter_windows.dll') { continue }
        [byte[]]$bytes = New-Object byte[] 128
        $bytes[0] = 0x4d; $bytes[1] = 0x5a; $bytes[60] = 64; $bytes[64] = 0x50; $bytes[65] = 0x45
        $machine = if ($arch -eq 'x64' -or ($case -eq 'wrong-pe' -and $name -eq 'rust_lib_zcash_wallet.dll')) { 0x8664 } else { 0xaa64 }
        [BitConverter]::GetBytes([uint16]$machine).CopyTo($bytes, 68)
        $entry = $zip.CreateEntry("lib/app/$name"); $stream = $entry.Open()
        $stream.Write($bytes, 0, $bytes.Length); $stream.Dispose()
      }
    } finally { $zip.Dispose() }
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    if ($case -eq 'wrong-hash') { $hash = '0' * 64 }
    $failed = $false
    try { Assert-VizorUpdatePackage -Path $path -Id $id -Version $version -Channel $channel -Arch $arch -Sha256 $hash }
    catch { $failed = $true }
    if ($failed -ne ($case -notin @('x64', 'arm64'))) { throw "Unexpected validation result: $case" }
    Write-Host "PASS: $case"
  }
} finally { Remove-Item -LiteralPath $root -Recurse -Force }
