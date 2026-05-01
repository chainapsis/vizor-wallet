[CmdletBinding()]
param(
  [string]$Version = "",
  [string]$PackId = "com.keplr.vizor.dev",
  [string]$PackTitle = "Vizor Dev",
  [string]$OutputDir = "build\velopack",
  [switch]$Msi,
  [switch]$Clean
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path (Join-Path $scriptDir "..")).Path
Set-Location $repoRoot

function Add-PathIfExists($path) {
  if ($path -and (Test-Path $path)) {
    $env:PATH = "$path;$env:PATH"
  }
}

function Resolve-Command($name, $fallbacks, $installHint) {
  $command = Get-Command $name -ErrorAction SilentlyContinue
  if ($command) {
    return $command.Source
  }

  foreach ($fallback in $fallbacks) {
    if ($fallback -and (Test-Path $fallback)) {
      return $fallback
    }
  }

  throw "$name was not found on PATH. $installHint"
}

function Get-FvmVersion {
  if (-not (Test-Path ".fvmrc")) {
    return $null
  }

  $config = Get-Content -Raw -Path ".fvmrc" | ConvertFrom-Json
  return $config.flutter
}

function Get-PubspecVersion {
  $versionLine = Get-Content -Path "pubspec.yaml" |
    Where-Object { $_ -match '^version:\s*' } |
    Select-Object -First 1
  if (-not $versionLine) {
    throw "Could not find a version: line in pubspec.yaml."
  }

  $rawVersion = ($versionLine -replace '^version:\s*', '').Trim()
  return ($rawVersion -split '\+')[0]
}

$fvmVersion = Get-FvmVersion
if ($fvmVersion) {
  $fvmSdk = Join-Path $env:USERPROFILE "fvm\versions\$fvmVersion"
  Add-PathIfExists (Join-Path $fvmSdk "bin\cache\dart-sdk\bin")
  Add-PathIfExists (Join-Path $fvmSdk "bin")
}
Add-PathIfExists "C:\Program Files\Git\cmd"
$dotnetRoot = Join-Path $env:USERPROFILE ".dotnet"
if (Test-Path $dotnetRoot) {
  $env:DOTNET_ROOT = $dotnetRoot
  Add-PathIfExists $dotnetRoot
  Add-PathIfExists (Join-Path $dotnetRoot "tools")
}

$fvmExe = Resolve-Command `
  "fvm" `
  @((Join-Path $env:LOCALAPPDATA "Pub\Cache\bin\fvm.bat")) `
  "Install FVM, then run this script again."
$vpkExe = Resolve-Command `
  "vpk" `
  @((Join-Path $env:USERPROFILE ".dotnet\tools\vpk.exe")) `
  "Install the Velopack CLI with: dotnet tool install -g vpk"

if ([string]::IsNullOrWhiteSpace($Version)) {
  $Version = Get-PubspecVersion
  if ($PackId.EndsWith(".dev") -and $Version -notmatch '-') {
    $Version = "$Version-dev.1"
  }
}

$packDir = Join-Path $repoRoot "build\windows\x64\runner\Release"
$mainExe = Join-Path $packDir "Vizor.exe"
$resolvedOutputDir = Join-Path $repoRoot $OutputDir

if ($Clean) {
  $buildRoot = [System.IO.Path]::GetFullPath((Join-Path $repoRoot "build"))
  if (-not $buildRoot.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
    $buildRoot = "$buildRoot$([System.IO.Path]::DirectorySeparatorChar)"
  }
  $outputFullPath = [System.IO.Path]::GetFullPath($resolvedOutputDir)
  if (-not $outputFullPath.StartsWith($buildRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to clean output directory outside build directory: $outputFullPath"
  }
  if (Test-Path $outputFullPath) {
    Remove-Item -LiteralPath $outputFullPath -Recurse -Force
  }
}

& $fvmExe flutter build windows --release

if (-not (Test-Path $mainExe)) {
  throw "Windows release build did not produce $mainExe"
}

$packArgs = @(
  "pack",
  "--packId", $PackId,
  "--packTitle", $PackTitle,
  "--packVersion", $Version,
  "--packDir", $packDir,
  "--mainExe", "Vizor.exe",
  "--outputDir", $resolvedOutputDir,
  "--icon", (Join-Path $repoRoot "windows\runner\resources\app_icon.ico"),
  "--delta", "None",
  "--noPortable",
  "--skipVeloAppCheck"
)

if ($Msi) {
  $packArgs += "--msi"
}

& $vpkExe @packArgs

Write-Host "Velopack package created in $resolvedOutputDir"
