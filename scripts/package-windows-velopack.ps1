[CmdletBinding()]
param(
  [string]$Version = "",
  [ValidateSet("mainnet", "testnet")]
  [string]$Network = "mainnet",
  [string]$PackId = "",
  [string]$PackTitle = "",
  [string]$Channel = "",
  [string]$OutputDir = "",
  [string]$UpdateFeedSigningKey = $env:VIZOR_UPDATE_FEED_SIGNING_KEY_B64,
  [string]$UpdateFeedPublicKey = $env:VIZOR_UPDATE_FEED_PUBLIC_KEY_B64,
  [string]$UpdateRepositoryUrl = $env:VIZOR_UPDATE_GITHUB_REPO_URL,
  [string]$UpdateReleaseBaseUrl = $env:VIZOR_UPDATE_RELEASE_BASE_URL,
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

function Initialize-UpdateFeedSigner {
  if ("VizorUpdateFeedSigner" -as [type]) {
    return
  }

  Add-Type -TypeDefinition @"
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.Cryptography;

public static class VizorUpdateFeedSigner
{
    private const int BCRYPT_ECDSA_PRIVATE_P256_MAGIC = 0x32534345;
    private const int KeySize = 32;

    [DllImport("bcrypt.dll", CharSet = CharSet.Unicode)]
    private static extern int BCryptOpenAlgorithmProvider(
        out IntPtr phAlgorithm,
        string pszAlgId,
        string pszImplementation,
        int dwFlags);

    [DllImport("bcrypt.dll", CharSet = CharSet.Unicode)]
    private static extern int BCryptImportKeyPair(
        IntPtr hAlgorithm,
        IntPtr hImportKey,
        string pszBlobType,
        out IntPtr phKey,
        byte[] pbInput,
        int cbInput,
        int dwFlags);

    [DllImport("bcrypt.dll")]
    private static extern int BCryptSignHash(
        IntPtr hKey,
        IntPtr pPaddingInfo,
        byte[] pbInput,
        int cbInput,
        byte[] pbOutput,
        int cbOutput,
        out int pcbResult,
        int dwFlags);

    [DllImport("bcrypt.dll")]
    private static extern int BCryptDestroyKey(IntPtr hKey);

    [DllImport("bcrypt.dll")]
    private static extern int BCryptCloseAlgorithmProvider(IntPtr hAlgorithm, int dwFlags);

    public static byte[] SignP256(byte[] rawPrivateKey, byte[] data)
    {
        if (rawPrivateKey == null || rawPrivateKey.Length != 96)
        {
            throw new ArgumentException("Expected a 96-byte raw P-256 key: X || Y || D.");
        }

        byte[] blob = new byte[8 + rawPrivateKey.Length];
        Array.Copy(BitConverter.GetBytes(BCRYPT_ECDSA_PRIVATE_P256_MAGIC), 0, blob, 0, 4);
        Array.Copy(BitConverter.GetBytes(KeySize), 0, blob, 4, 4);
        Array.Copy(rawPrivateKey, 0, blob, 8, rawPrivateKey.Length);

        byte[] hash;
        using (SHA256 sha256 = SHA256.Create())
        {
            hash = sha256.ComputeHash(data);
        }

        IntPtr algorithm = IntPtr.Zero;
        IntPtr key = IntPtr.Zero;
        try
        {
            Check(BCryptOpenAlgorithmProvider(out algorithm, "ECDSA_P256", null, 0));
            Check(BCryptImportKeyPair(algorithm, IntPtr.Zero, "ECCPRIVATEBLOB", out key, blob, blob.Length, 0));

            int signatureLength;
            Check(BCryptSignHash(key, IntPtr.Zero, hash, hash.Length, null, 0, out signatureLength, 0));
            byte[] signature = new byte[signatureLength];
            Check(BCryptSignHash(key, IntPtr.Zero, hash, hash.Length, signature, signature.Length, out signatureLength, 0));
            if (signatureLength != signature.Length)
            {
                Array.Resize(ref signature, signatureLength);
            }
            if (signature.Length != 64)
            {
                throw new InvalidOperationException("Expected a 64-byte P1363 ECDSA signature.");
            }
            return signature;
        }
        finally
        {
            if (key != IntPtr.Zero)
            {
                BCryptDestroyKey(key);
            }
            if (algorithm != IntPtr.Zero)
            {
                BCryptCloseAlgorithmProvider(algorithm, 0);
            }
        }
    }

    private static void Check(int status)
    {
        if (status < 0)
        {
            throw new Win32Exception(status);
        }
    }
}
"@
}

function Get-UpdateFeedSigningKeyBytes($signingKeyBase64) {
  $bytes = [Convert]::FromBase64String($signingKeyBase64.Trim())
  if ($bytes.Length -ne 96) {
    throw "VIZOR_UPDATE_FEED_SIGNING_KEY_B64 must be a 96-byte raw P-256 key: X || Y || D."
  }
  return $bytes
}

function Get-UpdateFeedPublicKeyBase64($signingKeyBase64) {
  $keyBytes = Get-UpdateFeedSigningKeyBytes $signingKeyBase64
  $publicKey = New-Object byte[] 64
  [Array]::Copy($keyBytes, 0, $publicKey, 0, 64)
  return [Convert]::ToBase64String($publicKey)
}

function Write-UpdateFeedSignature($feedPath, $signingKeyBase64) {
  if (-not (Test-Path $feedPath)) {
    throw "Could not find Velopack release feed: $feedPath"
  }

  Initialize-UpdateFeedSigner
  $keyBytes = Get-UpdateFeedSigningKeyBytes $signingKeyBase64
  $feedBytes = [System.IO.File]::ReadAllBytes($feedPath)
  $signature = [VizorUpdateFeedSigner]::SignP256($keyBytes, $feedBytes)
  [System.IO.File]::WriteAllText(
    "$feedPath.sig",
    [Convert]::ToBase64String($signature),
    [System.Text.Encoding]::ASCII
  )
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
}

if ($Network -eq "mainnet") {
  if ([string]::IsNullOrWhiteSpace($PackId)) {
    $PackId = "com.keplr.vizor"
  }
  if ([string]::IsNullOrWhiteSpace($PackTitle)) {
    $PackTitle = "Vizor"
  }
  if ([string]::IsNullOrWhiteSpace($Channel)) {
    $Channel = "win-x64-mainnet"
  }
  if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = "build\velopack\mainnet"
  }
  $NetworkDartDefine = "main"
} else {
  if ([string]::IsNullOrWhiteSpace($PackId)) {
    $PackId = "com.keplr.vizor.testnet"
  }
  if ([string]::IsNullOrWhiteSpace($PackTitle)) {
    $PackTitle = "Vizor Testnet"
  }
  if ([string]::IsNullOrWhiteSpace($Channel)) {
    $Channel = "win-x64-testnet"
  }
  if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = "build\velopack\testnet"
  }
  $NetworkDartDefine = "test"
}

if (-not [string]::IsNullOrWhiteSpace($UpdateFeedSigningKey)) {
  $env:VIZOR_UPDATE_FEED_SIGNING_KEY_B64 = $UpdateFeedSigningKey.Trim()
  $derivedPublicKey = Get-UpdateFeedPublicKeyBase64 $UpdateFeedSigningKey

  if ([string]::IsNullOrWhiteSpace($UpdateFeedPublicKey)) {
    $UpdateFeedPublicKey = $derivedPublicKey
  } elseif ($UpdateFeedPublicKey.Trim() -ne $derivedPublicKey) {
    throw "VIZOR_UPDATE_FEED_PUBLIC_KEY_B64 does not match VIZOR_UPDATE_FEED_SIGNING_KEY_B64."
  }
}

if ([string]::IsNullOrWhiteSpace($UpdateFeedPublicKey)) {
  $env:VIZOR_UPDATE_FEED_PUBLIC_KEY_B64 = ""
  Write-Warning "VIZOR_UPDATE_FEED_PUBLIC_KEY_B64 is not set. Windows update checks will be disabled in this build."
} else {
  $env:VIZOR_UPDATE_FEED_PUBLIC_KEY_B64 = $UpdateFeedPublicKey.Trim()
}
if (-not [string]::IsNullOrWhiteSpace($UpdateRepositoryUrl)) {
  $env:VIZOR_UPDATE_GITHUB_REPO_URL = $UpdateRepositoryUrl.Trim()
}
if (-not [string]::IsNullOrWhiteSpace($UpdateReleaseBaseUrl)) {
  $env:VIZOR_UPDATE_RELEASE_BASE_URL = $UpdateReleaseBaseUrl.Trim()
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

$flutterBuildArgs = @(
  "flutter",
  "build",
  "windows",
  "--release",
  "--dart-define=ZCASH_DEFAULT_NETWORK=$NetworkDartDefine",
  "--dart-define=VIZOR_RELEASE_VERSION=$Version"
)

$cmakeCache = Join-Path $repoRoot "build\windows\x64\CMakeCache.txt"
if (Test-Path $cmakeCache) {
  Remove-Item -LiteralPath $cmakeCache -Force
}

& $fvmExe @flutterBuildArgs

if (-not (Test-Path $mainExe)) {
  throw "Windows release build did not produce $mainExe"
}

$packArgs = @(
  "pack",
  "--packId", $PackId,
  "--packTitle", $PackTitle,
  "--packVersion", $Version,
  "--channel", $Channel,
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

if (-not [string]::IsNullOrWhiteSpace($UpdateFeedSigningKey)) {
  $releaseFeedPath = Join-Path $resolvedOutputDir "releases.$Channel.json"
  if (-not (Test-Path $releaseFeedPath)) {
    throw "Could not find Velopack release feed: $releaseFeedPath"
  }
  Write-UpdateFeedSignature $releaseFeedPath $UpdateFeedSigningKey
  $signedPublicKey = Get-UpdateFeedPublicKeyBase64 $UpdateFeedSigningKey
  if ($signedPublicKey.Trim() -ne $env:VIZOR_UPDATE_FEED_PUBLIC_KEY_B64) {
    throw "Signed release feed public key does not match the app build public key."
  }
  Write-Host "Signed Velopack release feed: $releaseFeedPath.sig"
} else {
  Write-Warning "VIZOR_UPDATE_FEED_SIGNING_KEY_B64 is not set. Release feed signature was not created."
}

Write-Host "Velopack $Network package created in $resolvedOutputDir"
