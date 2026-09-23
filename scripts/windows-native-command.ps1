# Pass an argv array through .NET without PowerShell 5.1's native quote rewriting.
# Windows executables parse this quoting according to CommandLineToArgvW/CRT rules.
function ConvertTo-WindowsNativeArgument([AllowEmptyString()][string]$Value) {
  $escaped = [regex]::Replace($Value, '(\\*)"', '$1$1\"')
  $escaped = [regex]::Replace($escaped, '(\\+)$', '$1$1')
  return '"' + $escaped + '"'
}

function Invoke-WindowsNativeCommand {
  param(
    [Parameter(Mandatory)][string]$FilePath,
    [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$ArgumentList
  )
  $startInfo = New-Object System.Diagnostics.ProcessStartInfo
  $startInfo.FileName = $FilePath
  $startInfo.UseShellExecute = $false
  $startInfo.WorkingDirectory = (Get-Location).Path
  $startInfo.Arguments = (($ArgumentList | ForEach-Object { ConvertTo-WindowsNativeArgument $_ }) -join ' ')
  $process = [System.Diagnostics.Process]::Start($startInfo)
  try {
    $process.WaitForExit()
    return $process.ExitCode
  } finally {
    $process.Dispose()
  }
}
