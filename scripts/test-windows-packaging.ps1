# Runs the real packaging script in a disposable repo with fake FVM and vpk.
# No Windows build, signing credentials, or wallet data is used.
# -NativeProbe runs a real child process to exercise stderr and exit codes.
# Run both modes under Windows PowerShell 5.1 and PowerShell 7 on Windows.
param([switch]$NativeProbe)

$ErrorActionPreference = "Stop"
$sourceScripts = $PSScriptRoot
$originalLocation = Get-Location
$originalEnvironment = @{}
Get-ChildItem Env: | ForEach-Object { $originalEnvironment[$_.Name] = $_.Value }
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("vizor-packaging-test-" + [guid]::NewGuid())
$createdCDrive = $false

function Assert-Equal($actual, $expected) {
  if ($actual -cne $expected) { throw "Expected '$expected', got '$actual'." }
}

try {
  $fixtureScripts = New-Item -ItemType Directory -Path (Join-Path $testRoot "scripts") -Force
  $mockBin = New-Item -ItemType Directory -Path (Join-Path $testRoot "tools") -Force
  if (-not (Get-PSDrive C -ErrorAction SilentlyContinue)) {
    New-PSDrive -Name C -PSProvider FileSystem -Root $testRoot | Out-Null
    $createdCDrive = $true
  }
  Copy-Item (Join-Path $sourceScripts "package-windows-velopack.ps1") $fixtureScripts
  Copy-Item (Join-Path $sourceScripts "windows-build-arch.dart") $fixtureScripts
  $packageScript = Join-Path $fixtureScripts "package-windows-velopack.ps1"
  Set-Content (Join-Path $testRoot '.fvmrc') '{"flutter":"3.47.2"}'
  # Existing SDK directories must not take priority over the host Dart PATH.
  $fakeSdk = Join-Path $testRoot 'fvm/versions/3.47.2'
  New-Item -ItemType Directory -Path (Join-Path $fakeSdk 'bin/cache/dart-sdk/bin') -Force | Out-Null
  $env:VIZOR_TEST_FORBIDDEN_PATH = $fakeSdk
  $env:VIZOR_TEST_NATIVE_PROBE = "$NativeProbe"
  $shellName = if ($PSVersionTable.PSEdition -eq 'Desktop') { 'powershell.exe' } elseif ($env:OS -eq 'Windows_NT') { 'pwsh.exe' } else { 'pwsh' }
  $env:VIZOR_TEST_SHELL = Join-Path $PSHOME $shellName
  $env:VIZOR_TEST_PROBE_SCRIPT = Join-Path $testRoot 'native-probe.ps1'
  Set-Content $env:VIZOR_TEST_PROBE_SCRIPT @'
if ($env:PATH.Contains($env:VIZOR_TEST_FORBIDDEN_PATH)) {
  [Console]::Error.WriteLine('Host Dart PATH was replaced by the Flutter SDK')
  exit 99
}
if ($env:VIZOR_TEST_PROBE_STDERR) { [Console]::Error.WriteLine($env:VIZOR_TEST_PROBE_STDERR) }
[Console]::Out.WriteLine($env:VIZOR_TEST_PROBE)
exit ([int]$env:VIZOR_TEST_PROBE_EXIT)
'@
  $env:USERPROFILE = $testRoot
  $env:LOCALAPPDATA = $testRoot
  $env:DOTNET_ROOT = ""
  # Keep real FVM/.NET installations out of command resolution.
  $env:PATH = $mockBin.FullName
  $env:VIZOR_TEST_ROOT = $testRoot
  $env:VIZOR_TEST_FVM_LOG = Join-Path $testRoot "build.json"
  $env:VIZOR_TEST_VPK_LOG = Join-Path $testRoot "pack.json"

  Set-Content (Join-Path $mockBin "fvm.ps1") @'
if ($args[0] -eq 'dart') {
  if (-not (Test-Path $args[1])) { throw 'Missing ABI probe script.' }
  if ($env:PATH.Contains($env:VIZOR_TEST_FORBIDDEN_PATH)) { throw 'Host Dart PATH was replaced' }
  if ($env:VIZOR_TEST_NATIVE_PROBE -eq 'True') {
    & $env:VIZOR_TEST_SHELL -NoProfile -File $env:VIZOR_TEST_PROBE_SCRIPT
    $global:LASTEXITCODE = $LASTEXITCODE
    return
  }
  Write-Output 'FVM informational output'
  Write-Output $env:VIZOR_TEST_PROBE
  $global:LASTEXITCODE = [int]$env:VIZOR_TEST_PROBE_EXIT
  return
}
if ($args[0] -ne 'flutter' -or $args[1] -ne 'build' -or $args[2] -ne 'windows') {
  throw 'Unexpected FVM invocation.'
}
ConvertTo-Json -InputObject @($args) | Set-Content $env:VIZOR_TEST_FVM_LOG
$releaseDir = Join-Path $env:VIZOR_TEST_ROOT "build/windows/$env:VIZOR_TEST_SDK_ARCH/runner/Release"
New-Item -ItemType Directory -Path $releaseDir -Force | Out-Null
Set-Content (Join-Path $releaseDir 'Vizor.exe') 'fake executable'
$global:LASTEXITCODE = 0
'@
  Set-Content (Join-Path $mockBin "vpk.ps1") @'
ConvertTo-Json -InputObject @($args) | Set-Content $env:VIZOR_TEST_VPK_LOG
$global:LASTEXITCODE = 0
'@

  $cases = @(
    @{ Name = "ARM64 native signing template"; Sdk = "arm64"; Arch = "arm64"; Network = "mainnet"; NativeSigning = $true },
    @{ Name = "testnet ignores signing override"; Sdk = "arm64"; Arch = "arm64"; Network = "testnet"; NativeSigning = $true },
    @{ Name = "default x64 on ARM OS"; Sdk = "x64"; Arch = $null; Network = "mainnet" },
    @{ Name = "explicit x64 testnet"; Sdk = "x64"; Arch = "x64"; Network = "testnet" },
    @{ Name = "explicit ARM64 mainnet"; Sdk = "arm64"; Arch = "ARM64"; Network = "mainnet" },
    @{ Name = "explicit arm64 testnet"; Sdk = "arm64"; Arch = "arm64"; Network = "testnet" },
    @{ Name = "default rejects ARM SDK"; Sdk = "arm64"; Arch = $null; Error = "Requested Windows x64" },
    @{ Name = "ARM request rejects x64 SDK"; Sdk = "x64"; Arch = "arm64"; Error = "Requested Windows arm64" },
    @{ Name = "stderr warning with successful probe"; Sdk = "x64"; Network = "mainnet"; Stderr = "harmless native warning" },
    @{ Name = "stderr with failed probe"; Sdk = "x64"; Exit = 7; Stderr = "native probe failure detail"; Error = "probe failed" },
    @{ Name = "missing probe result"; Sdk = "x64"; Probe = ""; Error = "unique Windows architecture" },
    @{ Name = "duplicate same ABI"; Sdk = "x64"; Probe = "VIZOR_WINDOWS_BUILD_ARCH=x64`nVIZOR_WINDOWS_BUILD_ARCH=x64"; Error = "unique Windows architecture" },
    @{ Name = "failed probe"; Sdk = "x64"; Exit = 1; Error = "probe failed" },
    @{ Name = "unrecognized probe"; Sdk = "x64"; Probe = "unknown"; Error = "unique Windows architecture" },
    @{ Name = "conflicting probe"; Sdk = "x64"; Probe = "VIZOR_WINDOWS_BUILD_ARCH=x64`nVIZOR_WINDOWS_BUILD_ARCH=arm64"; Error = "unique Windows architecture" }
  )
  foreach ($case in $cases) {
    $env:PROCESSOR_ARCHITECTURE = "ARM64"
    $env:VIZOR_TEST_PROBE_STDERR = $case.Stderr
    $env:VIZOR_TEST_SDK_ARCH = $case.Sdk
    $env:VIZOR_TEST_PROBE = if ($case.ContainsKey("Probe")) { $case.Probe } else { "VIZOR_WINDOWS_BUILD_ARCH=$($case.Sdk)" }
    $env:VIZOR_TEST_PROBE_EXIT = if ($case.ContainsKey("Exit")) { "$($case.Exit)" } else { "0" }
    Remove-Item $env:VIZOR_TEST_FVM_LOG, $env:VIZOR_TEST_VPK_LOG -ErrorAction SilentlyContinue
    $sentinel = Join-Path $testRoot "build/velopack/mainnet/keep.txt"
    New-Item -ItemType Directory -Path (Split-Path $sentinel) -Force | Out-Null
    Set-Content $sentinel "keep"
    $options = @{
      Version = "1.2.3"; Clean = $true
      UpdateFeedSigningKey = ""; UpdateFeedPublicKey = ""
      UpdateRepositoryUrl = ""; UpdateReleaseBaseUrl = ""
      SignToolPath = ""; CodeSignParams = ""; CodeSignParallel = ""; CodeSignExclude = ""
    }
    if ($case.Arch) { $options.Arch = $case.Arch }
    if ($case.Network) { $options.Network = $case.Network }
    if ($case.NativeSigning) {
      $signTool = Join-Path $mockBin 'native signtool.exe'
      Set-Content -LiteralPath $signTool -Value 'fixture'
      $options.SignToolPath = $signTool
      $options.CodeSignParams = '/sha1 FIXTURE /fd SHA256'
    }
    $failure = $null
    try { & $packageScript @options } catch { $failure = $_.Exception.Message }
    if ($case.Error) {
      if (-not $failure -or -not $failure.Contains($case.Error)) { throw "$($case.Name): unexpected error '$failure'." }
      Assert-Equal (Test-Path $env:VIZOR_TEST_FVM_LOG) $false
      Assert-Equal (Test-Path $env:VIZOR_TEST_VPK_LOG) $false
      Assert-Equal (Test-Path $sentinel) $true
    } else {
      if ($failure) { throw "$($case.Name): $failure" }
      $packArgs = @(Get-Content -Raw $env:VIZOR_TEST_VPK_LOG | ConvertFrom-Json)
      if ($case.NativeSigning -and $case.Network -eq 'mainnet') {
        Assert-Equal $packArgs.Contains('--signParams') $false
        Assert-Equal $packArgs[$packArgs.IndexOf('--signTemplate') + 1] ('"' + $signTool + '" sign /sha1 FIXTURE /fd SHA256 {{file}}')
      } else {
        Assert-Equal $packArgs.Contains('--signTemplate') $false
      }
      $channel = "win-$($case.Sdk)-$($case.Network)"
      Assert-Equal $packArgs[$packArgs.IndexOf("--channel") + 1] $channel
      Assert-Equal $packArgs[$packArgs.IndexOf("--packId") + 1] $(if ($case.Network -eq "mainnet") { "com.keplr.vizor" } else { "com.keplr.vizor.testnet" })
      Assert-Equal $packArgs[$packArgs.IndexOf("--mainExe") + 1] "Vizor.exe"
      Assert-Equal $env:VIZOR_WINDOWS_STORAGE_PREFIX $(if ($case.Network -eq "mainnet") { "Vizor" } else { "VizorTestnet" })
      Assert-Equal ([System.IO.Path]::GetFullPath($packArgs[$packArgs.IndexOf("--packDir") + 1])) (Join-Path $testRoot "build/windows/$($case.Sdk)/runner/Release")
      if ($case.Sdk -eq "arm64") {
        Assert-Equal $packArgs[$packArgs.IndexOf("--runtime") + 1] "win-arm64"
      } else {
        Assert-Equal $packArgs.Contains("--runtime") $false
      }
    }
    Write-Host "PASS: $($case.Name)"
  }
} finally {
  Set-Location $originalLocation
  Get-ChildItem Env: | Where-Object { -not $originalEnvironment.ContainsKey($_.Name) } | ForEach-Object { Remove-Item "Env:$($_.Name)" }
  foreach ($name in $originalEnvironment.Keys) { Set-Item "Env:$name" $originalEnvironment[$name] }
  if ($createdCDrive) { Remove-PSDrive C }
  if (Test-Path $testRoot) { Remove-Item $testRoot -Recurse -Force }
}
