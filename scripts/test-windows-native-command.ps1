# Round-trip arguments through a real native child process, not a PowerShell mock.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'windows-native-command.ps1')
$root = Join-Path ([System.IO.Path]::GetTempPath()) ('vizor native argv ' + [guid]::NewGuid())
try {
  New-Item -ItemType Directory -Path $root | Out-Null
  $child = Join-Path $root 'child.ps1'
  $result = Join-Path $root 'argv.json'
  Set-Content -LiteralPath $child -Encoding utf8 -Value @'
$out = $args[0]
[string[]]$received = @($args | Select-Object -Skip 1)
ConvertTo-Json -InputObject $received -Compress | Set-Content -LiteralPath $out -Encoding utf8
exit 7
'@
  $shellName = if ($PSVersionTable.PSEdition -eq 'Desktop') { 'powershell.exe' } elseif ($env:OS -eq 'Windows_NT') { 'pwsh.exe' } else { 'pwsh' }
  $shell = Join-Path $PSHOME $shellName
  [string[]]$expected = @(
    '--signTemplate',
    '"C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\arm64\signtool.exe" sign /sha1 FIXTURE /tr http://timestamp.digicert.com /td SHA256 /fd SHA256 {{file}}',
    'C:\directory with spaces\',
    'backslashes\\"quoted"',
    'plain',
    '한글 경로 (test)',
    'a & b',
    ''
  )
  $exitCode = Invoke-WindowsNativeCommand -FilePath $shell -ArgumentList (@('-NoProfile', '-File', $child, $result) + $expected)
  if ($exitCode -ne 7) { throw "Child exit code was not preserved: $exitCode" }
  $rawJson = Get-Content -LiteralPath $result -Raw
  # Windows PowerShell 5.1 emits the JSON array as one pipeline object.
  # @(... | ConvertFrom-Json) would wrap it again and report Count=1.
  $actual = $rawJson | ConvertFrom-Json
  if ($actual -isnot [System.Array] -or $actual.Count -ne $expected.Count) {
    $actualType = if ($null -eq $actual) { '<null>' } else { $actual.GetType().FullName }
    throw "Argument shape changed: type=$actualType; count=$($actual.Count); expected=$($expected.Count); raw JSON=$rawJson"
  }
  for ($i = 0; $i -lt $expected.Count; $i++) {
    if ($actual[$i] -cne $expected[$i]) { throw "Argument $i changed: expected '$($expected[$i])', received '$($actual[$i])'; raw JSON=$rawJson" }
  }
  Write-Host "PASS: native argv round-trip and exit code ($($PSVersionTable.PSVersion))"
} finally {
  if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Force -Recurse }
}
