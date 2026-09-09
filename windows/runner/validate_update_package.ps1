# Compiled into the runner. Only reads the package; never extracts or executes it.
function Assert-VizorUpdatePackage {
  param([string]$Path, [string]$Id, [string]$Version, [string]$Channel,
        [string]$Arch, [string]$Sha256)
  $ErrorActionPreference = 'Stop'
  Add-Type -AssemblyName System.IO.Compression
  $file = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
  try {
    $hash = [Security.Cryptography.SHA256]::Create()
    try { $actual = [BitConverter]::ToString($hash.ComputeHash($file)).Replace('-', '') }
    finally { $hash.Dispose() }
    if ($actual -ine $Sha256) { throw 'Package checksum mismatch.' }
    $file.Position = 0
    $zip = [IO.Compression.ZipArchive]::new($file, [IO.Compression.ZipArchiveMode]::Read, $true)
    try {
      $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
      foreach ($entry in $zip.Entries) {
        $name = $entry.FullName
        # Windows normalizes trailing dots/spaces. Reject aliases before checking
        # the PE entries so extraction cannot overwrite an already validated file.
        foreach ($part in $name.TrimEnd('/').Split('/')) {
          if ([string]::IsNullOrEmpty($part) -or $part.EndsWith('.') -or $part.EndsWith(' ') -or
              $part -match '[<>"|?*\x00-\x1f]') { throw 'Ambiguous Windows archive path.' }
        }
        if (-not $names.Add($name) -or $name.Contains('\') -or $name.Contains(':') -or
            $name.StartsWith('/') -or @($name.Split('/') | Where-Object { $_ -eq '..' -or $_ -eq '.' }).Count) {
          throw 'Invalid or duplicate archive path.'
        }
      }
      $manifests = @($zip.Entries | Where-Object { $_.FullName.EndsWith('.nuspec', [StringComparison]::OrdinalIgnoreCase) })
      if ($manifests.Count -ne 1 -or $manifests[0].FullName.Contains('/') -or $manifests[0].Length -gt 1048576) {
        throw 'Invalid package manifest.'
      }
      $stream = $manifests[0].Open()
      try {
        $settings = [Xml.XmlReaderSettings]::new()
        $settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
        $settings.XmlResolver = $null
        $settings.MaxCharactersInDocument = 1048576
        $reader = [Xml.XmlReader]::Create($stream, $settings)
        try { $doc = [Xml.XmlDocument]::new(); $doc.XmlResolver = $null; $doc.Load($reader) }
        finally { $reader.Dispose() }
      } finally { $stream.Dispose() }
      $metadata = $doc.SelectNodes('/*[local-name()="package"]/*[local-name()="metadata"]')
      if ($metadata.Count -ne 1) { throw 'Invalid package metadata.' }
      $expected = @{id=$Id; version=$Version; channel=$Channel; os='win'; rid="win-$Arch"; machineArchitecture=$Arch; mainExe='Vizor.exe'}
      foreach ($key in $expected.Keys) {
        $nodes = $metadata[0].SelectNodes("*[local-name()='$key']")
        if ($nodes.Count -ne 1 -or $nodes[0].InnerText -cne $expected[$key]) { throw "Unexpected manifest $key." }
      }
      $machine = if ($Arch -eq 'arm64') { 0xaa64 } elseif ($Arch -eq 'x64') { 0x8664 } else { throw 'Invalid architecture.' }
      foreach ($name in @('Vizor.exe', 'flutter_windows.dll', 'rust_lib_zcash_wallet.dll')) {
        $entry = $zip.GetEntry("lib/app/$name")
        if ($null -eq $entry) { throw "Missing $name." }
        $stream = $entry.Open()
        $reader = [IO.BinaryReader]::new($stream)
        try {
          if ($reader.ReadUInt16() -ne 0x5a4d) { throw 'Missing DOS header.' }
          if ($reader.ReadBytes(58).Length -ne 58) { throw 'Truncated DOS header.' }
          $offset = $reader.ReadUInt32()
          if ($offset -lt 64 -or $offset -gt 1048576) { throw 'Invalid PE offset.' }
          if ($reader.ReadBytes([int]$offset - 64).Length -ne ($offset - 64) -or
              $reader.ReadUInt32() -ne 0x4550 -or $reader.ReadUInt16() -ne $machine) { throw "Wrong PE architecture: $name." }
        } finally { $reader.Dispose(); $stream.Dispose() }
      }
    } finally { $zip.Dispose() }
  } finally { $file.Dispose() }
}
