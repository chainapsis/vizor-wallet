[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$parameters = New-Object System.Security.Cryptography.CngKeyCreationParameters
$parameters.ExportPolicy = [System.Security.Cryptography.CngExportPolicies]::AllowPlaintextExport
$keyName = "vizor-update-feed-" + [Guid]::NewGuid().ToString("N")
$key = [System.Security.Cryptography.CngKey]::Create(
  [System.Security.Cryptography.CngAlgorithm]::ECDsaP256,
  $keyName,
  $parameters
)

try {
  $blob = $key.Export([System.Security.Cryptography.CngKeyBlobFormat]::EccPrivateBlob)
  if ($blob.Length -ne 104) {
    throw "Unexpected ECDSA P-256 private blob length: $($blob.Length)"
  }

  $rawPrivateKey = New-Object byte[] 96
  [Array]::Copy($blob, 8, $rawPrivateKey, 0, 96)
  $rawPublicKey = New-Object byte[] 64
  [Array]::Copy($rawPrivateKey, 0, $rawPublicKey, 0, 64)

  [pscustomobject]@{
    VIZOR_UPDATE_FEED_SIGNING_KEY_B64 = [Convert]::ToBase64String($rawPrivateKey)
    VIZOR_UPDATE_FEED_PUBLIC_KEY_B64 = [Convert]::ToBase64String($rawPublicKey)
  } | ConvertTo-Json
} finally {
  $key.Delete()
}
