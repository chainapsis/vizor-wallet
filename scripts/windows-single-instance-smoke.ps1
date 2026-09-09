<#
Build an isolated executable before running this destructive smoke test:

  powershell.exe -NoProfile -ExecutionPolicy Bypass `
    -File scripts/package-windows-velopack.ps1 `
    -Network mainnet `
    -PackId com.keplr.vizor.single-instance-smoke `
    -PackTitle "Vizor Single Instance Smoke" `
    -Channel win-x64-single-instance-smoke `
    -OutputDir build\velopack\single-instance-smoke

Use win-arm64-single-instance-smoke as the channel on ARM64 hosts.

The PackTitle sets the executable's VERSIONINFO ProductName, which determines
the Windows application-support directory used by the wallet database and
flutter_secure_storage. Changing only VIZOR_WINDOWS_STORAGE_PREFIX does not
isolate those files.
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
  throw "This smoke test forcibly terminates Vizor. ProductName '$actualProductName' is storage-isolated; pass -ConfirmIsolatedStorage to continue."
}

Write-Host "Verified isolated ProductName: $actualProductName"

$primary = $null
$secondary = $null
$replacement = $null

try {
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

  Write-Host "PASS: secondary execution was blocked and the lock recovered after termination."
} finally {
  Stop-OwnedProcess -Process $secondary
  Stop-OwnedProcess -Process $primary
  Stop-OwnedProcess -Process $replacement
}
