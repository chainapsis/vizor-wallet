# Runs the real packaging script in a disposable repo with fake FVM and vpk.
# No Windows build, signing credentials, or wallet data is used.
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
    @{ Name = "default x64 on ARM OS"; Sdk = "x64"; Arch = $null; Network = "mainnet" },
    @{ Name = "explicit x64 testnet"; Sdk = "x64"; Arch = "x64"; Network = "testnet" },
    @{ Name = "explicit ARM64 mainnet"; Sdk = "arm64"; Arch = "ARM64"; Network = "mainnet" },
    @{ Name = "explicit arm64 testnet"; Sdk = "arm64"; Arch = "arm64"; Network = "testnet" },
    @{ Name = "default rejects ARM SDK"; Sdk = "arm64"; Arch = $null; Error = "Requested Windows x64" },
    @{ Name = "ARM request rejects x64 SDK"; Sdk = "x64"; Arch = "arm64"; Error = "Requested Windows arm64" },
    @{ Name = "failed probe"; Sdk = "x64"; Exit = 1; Error = "probe failed" },
    @{ Name = "unrecognized probe"; Sdk = "x64"; Probe = "unknown"; Error = "unique Windows architecture" },
    @{ Name = "conflicting probe"; Sdk = "x64"; Probe = "VIZOR_WINDOWS_BUILD_ARCH=x64`nVIZOR_WINDOWS_BUILD_ARCH=arm64"; Error = "unique Windows architecture" }
  )
  foreach ($case in $cases) {
    $env:PROCESSOR_ARCHITECTURE = "ARM64"
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
      CodeSignParams = ""; CodeSignParallel = ""; CodeSignExclude = ""
    }
    if ($case.Arch) { $options.Arch = $case.Arch }
    if ($case.Network) { $options.Network = $case.Network }
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
