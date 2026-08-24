<#
Build an isolated executable before running this destructive smoke test:

  powershell.exe -NoProfile -ExecutionPolicy Bypass `
    -File scripts/package-windows-velopack.ps1 `
    -Network mainnet `
    -PackId com.keplr.vizor.single-instance-smoke `
    -PackTitle "Vizor Single Instance Smoke" `
    -WindowsStoragePrefix VizorSingleInstanceSmoke `
    -Channel win-x64-single-instance-smoke `
    -OutputDir build\velopack\single-instance-smoke

The PackTitle isolates the application-support directory used by the wallet
database and flutter_secure_storage. WindowsStoragePrefix separately isolates
the single-instance lock. Both values are required for this destructive smoke.
#>

param(
  [Parameter(Mandatory = $true)]
  [string]$ExecutablePath,

  [int]$StartupTimeoutSeconds = 30,
  [int]$SecondaryExitTimeoutSeconds = 5,
  [switch]$ConfirmIsolatedStorage
)

$ErrorActionPreference = "Stop"
$requiredProductName = "Vizor Single Instance Smoke"
$requiredStoragePrefix = "VizorSingleInstanceSmoke"

function Wait-ForMainWindow {
  param(
    [System.Diagnostics.Process]$Process,
    [int]$TimeoutSeconds
  )

  $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
  while ([DateTime]::UtcNow -lt $deadline) {
    if ($Process.HasExited) {
      throw "Vizor exited before creating its main window (exit code $($Process.ExitCode))."
    }
    $Process.Refresh()
    if ($Process.MainWindowHandle -ne [IntPtr]::Zero) {
      return
    }
    Start-Sleep -Milliseconds 100
  }
  throw "Vizor did not create a main window within $TimeoutSeconds seconds."
}

function Stop-OwnedProcess {
  param([System.Diagnostics.Process]$Process)

  if ($null -eq $Process -or $Process.HasExited) {
    return
  }
  Stop-Process -Id $Process.Id -Force
  $Process.WaitForExit(5000) | Out-Null
}

$resolvedExecutable = (Resolve-Path -LiteralPath $ExecutablePath).Path
$versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($resolvedExecutable)
$actualProductName = $versionInfo.ProductName
$productionProductNames = @("Vizor", "Vizor Testnet")

if ([string]::IsNullOrWhiteSpace($actualProductName)) {
  throw "The executable has no VERSIONINFO ProductName and cannot be verified as storage-isolated: $resolvedExecutable"
}
if ($productionProductNames -contains $actualProductName) {
  throw "Refusing to run the destructive smoke test against production ProductName '$actualProductName'. Build with -PackTitle '$requiredProductName'."
}
if (-not [string]::Equals(
    $actualProductName,
    $requiredProductName,
    [System.StringComparison]::Ordinal)) {
  throw "Executable ProductName '$actualProductName' does not match required smoke ProductName '$requiredProductName'."
}
if (-not $ConfirmIsolatedStorage) {
  throw "This smoke test forcibly terminates Vizor. ProductName '$actualProductName' and storage prefix '$requiredStoragePrefix' must be isolated; pass -ConfirmIsolatedStorage to continue."
}

Write-Host "Verified isolated ProductName: $actualProductName"
Write-Host "Using isolated storage prefix: $requiredStoragePrefix"

$primary = $null
$secondary = $null
$replacement = $null
$delayedRelay = $null
$delayedPrimary = $null
$delayedLockStream = $null
$delayedLockHeld = $false

try {
  $lockDirectory = Join-Path $env:LOCALAPPDATA "com.keplr\VizorInstanceLocks"
  New-Item -ItemType Directory -Path $lockDirectory -Force | Out-Null
  $lockPath = Join-Path $lockDirectory "$requiredStoragePrefix.lock"
  $delayedLockStream = [System.IO.File]::Open(
    $lockPath,
    [System.IO.FileMode]::OpenOrCreate,
    [System.IO.FileAccess]::ReadWrite,
    [System.IO.FileShare]::ReadWrite
  )
  $delayedLockStream.Lock(0, 1)
  $delayedLockHeld = $true

  Write-Host "Starting payment-link relay while the primary window is delayed"
  $delayedRelay = Start-Process `
    -FilePath $resolvedExecutable `
    -ArgumentList "vizor://payment-link?payload=single-instance-smoke" `
    -PassThru
  Start-Sleep -Milliseconds 2500
  $delayedRelay.Refresh()
  if ($delayedRelay.HasExited) {
    throw "Payment-link relay exited before the delayed lock was released."
  }

  $delayedLockStream.Unlock(0, 1)
  $delayedLockHeld = $false
  $delayedLockStream.Dispose()
  $delayedLockStream = $null

  $delayedPrimary = Start-Process -FilePath $resolvedExecutable -PassThru
  Wait-ForMainWindow `
    -Process $delayedPrimary `
    -TimeoutSeconds $StartupTimeoutSeconds
  if (-not $delayedRelay.WaitForExit($SecondaryExitTimeoutSeconds * 1000)) {
    throw "Payment-link relay did not exit after the delayed primary created its window."
  }
  if ($delayedRelay.ExitCode -ne 0) {
    throw "Payment-link relay exited with code $($delayedRelay.ExitCode) after delayed primary startup."
  }
  if ($delayedPrimary.HasExited) {
    throw "Delayed primary exited while receiving the payment link."
  }
  Stop-OwnedProcess -Process $delayedPrimary
  $delayedPrimary = $null

  Write-Host "Starting primary: $resolvedExecutable"
  $primary = Start-Process -FilePath $resolvedExecutable -PassThru
  Wait-ForMainWindow -Process $primary -TimeoutSeconds $StartupTimeoutSeconds

  Write-Host "Starting secondary"
  $secondary = Start-Process -FilePath $resolvedExecutable -PassThru
  if (-not $secondary.WaitForExit($SecondaryExitTimeoutSeconds * 1000)) {
    throw "Secondary Vizor process did not exit within $SecondaryExitTimeoutSeconds seconds."
  }
  if ($secondary.ExitCode -ne 0) {
    throw "Secondary Vizor process exited with code $($secondary.ExitCode)."
  }
  if ($primary.HasExited) {
    throw "Primary Vizor process exited while the secondary was starting."
  }

  Write-Host "Forcibly terminating primary to verify OS lock recovery"
  Stop-OwnedProcess -Process $primary
  $primary = $null

  $replacement = Start-Process -FilePath $resolvedExecutable -PassThru
  Wait-ForMainWindow -Process $replacement -TimeoutSeconds $StartupTimeoutSeconds

  Write-Host "PASS: delayed payment-link relay, secondary blocking, and lock recovery succeeded."
} finally {
  if ($delayedLockHeld -and $null -ne $delayedLockStream) {
    try {
      $delayedLockStream.Unlock(0, 1)
    } catch {
      Write-Warning "Could not release delayed-start lock: $_"
    }
  }
  if ($null -ne $delayedLockStream) {
    try {
      $delayedLockStream.Dispose()
    } catch {
      Write-Warning "Could not dispose delayed-start lock stream: $_"
    }
  }
  foreach ($ownedProcess in @(
      $delayedRelay,
      $delayedPrimary,
      $secondary,
      $primary,
      $replacement
    )) {
    try {
      Stop-OwnedProcess -Process $ownedProcess
    } catch {
      Write-Warning "Could not stop an owned smoke-test process: $_"
    }
  }
}
