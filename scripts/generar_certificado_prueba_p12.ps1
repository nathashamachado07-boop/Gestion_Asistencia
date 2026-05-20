param(
  [string]$CommonName = "PruebaFirmaInterna",
  [string]$Password = "ClavePrueba123!",
  [string]$OutputDirectory = "",
  [int]$ValidityDays = 365,
  [switch]$Overwrite
)

$ErrorActionPreference = "Stop"

function New-SafeFileName {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Value
  )

  $safe = $Value -replace "[^a-zA-Z0-9._-]", "_"
  $safe = $safe.Trim("._-")
  if ([string]::IsNullOrWhiteSpace($safe)) {
    return "certificado_prueba"
  }
  return $safe
}

if ([string]::IsNullOrWhiteSpace($Password)) {
  throw "Debes indicar una clave para proteger el archivo .p12."
}

if ($ValidityDays -lt 1) {
  throw "ValidityDays debe ser mayor que 0."
}

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
  $OutputDirectory = Join-Path $PSScriptRoot "generated-certificates"
}

$baseName = New-SafeFileName -Value $CommonName
$pfxPath = Join-Path $OutputDirectory "$baseName.pfx"
$p12Path = Join-Path $OutputDirectory "$baseName.p12"
$cerPath = Join-Path $OutputDirectory "$baseName.cer"

if ((Test-Path -LiteralPath $pfxPath) -and -not $Overwrite) {
  throw "Ya existe $pfxPath. Usa -Overwrite para reemplazarlo."
}

if ((Test-Path -LiteralPath $p12Path) -and -not $Overwrite) {
  throw "Ya existe $p12Path. Usa -Overwrite para reemplazarlo."
}

if ((Test-Path -LiteralPath $cerPath) -and -not $Overwrite) {
  throw "Ya existe $cerPath. Usa -Overwrite para reemplazarlo."
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

$securePassword = ConvertTo-SecureString -String $Password -Force -AsPlainText
$notAfter = (Get-Date).AddDays($ValidityDays)

$cert = New-SelfSignedCertificate 
  -Type Custom `
  -Subject "CN=$CommonName" `
  -CertStoreLocation "Cert:\CurrentUser\My" `
  -KeyExportPolicy Exportable `
  -KeySpec Signature `
  -KeyUsage DigitalSignature `
  -KeyAlgorithm RSA `
  -KeyLength 2048 `
  -HashAlgorithm SHA256 `
  -NotAfter $notAfter

Export-PfxCertificate `
  -Cert $cert `
  -FilePath $pfxPath `
  -Password $securePassword `
  -ChainOption EndEntityCertOnly `
  -NoProperties | Out-Null

Copy-Item -LiteralPath $pfxPath -Destination $p12Path -Force

Export-Certificate `
  -Cert $cert `
  -FilePath $cerPath `
  -Type CERT | Out-Null

Write-Host ""
Write-Host "Certificado de prueba generado correctamente." -ForegroundColor Green
Write-Host "CN: $CommonName"
Write-Host "Vence: $($notAfter.ToString('yyyy-MM-dd'))"
Write-Host "Thumbprint: $($cert.Thumbprint)"
Write-Host ""
Write-Host "Archivos creados:"
Write-Host " - PFX: $pfxPath"
Write-Host " - P12: $p12Path"
Write-Host " - CER: $cerPath"
Write-Host ""
Write-Host "Usa en tu sistema el archivo .p12 y la clave que pasaste con -Password."
Write-Host "Nota: .pfx y .p12 son contenedores PKCS#12 equivalentes; se crea ambos para que pruebes sin friccion."
Write-Host ""
Write-Host "Si luego quieres quitar este certificado del almacen de Windows:"
Write-Host "Remove-Item -LiteralPath `"Cert:\CurrentUser\My\$($cert.Thumbprint)`""
