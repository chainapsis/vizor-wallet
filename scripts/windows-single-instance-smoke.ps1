param(
  [Parameter(Mandatory = $true)]
  [string]$ExecutablePath,

  [int]$StartupTimeoutSeconds = 30,
  [int]$SecondaryExitTimeoutSeconds = 5,
  [switch]$ConfirmIsolatedStorage
)

$ErrorActionPreference = "Stop"

if (-not $ConfirmIsolatedStorage) {
  throw "This smoke test forcibly terminates Vizor. Run it only against a build with an isolated VIZOR_WINDOWS_STORAGE_PREFIX, then pass -ConfirmIsolatedStorage."
}

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
