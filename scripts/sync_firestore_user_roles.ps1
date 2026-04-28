param(
  [string]$ProjectId = "tesis-intesud"
)

$ErrorActionPreference = "Stop"

function Get-AccessToken {
  $nodeScript = @"
const fs=require('fs');
const auth=require(process.env.APPDATA+'\\\\npm\\\\node_modules\\\\firebase-tools\\\\lib\\\\auth.js');
const cfg=JSON.parse(fs.readFileSync(process.env.USERPROFILE+'\\\\.config\\\\configstore\\\\firebase-tools.json','utf8'));
auth.getAccessToken(cfg.tokens.refresh_token, []).then(t=>process.stdout.write(t.access_token||'')).catch(e=>{console.error(e); process.exit(1);});
"@
  $token = node -e $nodeScript
  if ([string]::IsNullOrWhiteSpace($token)) {
    throw "No se pudo obtener un access token valido."
  }
  return $token.Trim()
}

function Get-StringField($fields, $name) {
  if ($null -eq $fields.$name) { return "" }
  if ($null -ne $fields.$name.stringValue) { return [string]$fields.$name.stringValue }
  return ""
}

function Get-ArrayStrings($fields, $name) {
  $result = @()
  if ($null -eq $fields.$name) { return $result }
  $values = $fields.$name.arrayValue.values
  if ($null -eq $values) { return $result }
  foreach ($item in $values) {
    if ($null -ne $item.stringValue) {
      $result += [string]$item.stringValue
    }
  }
  return $result
}

function Resolve-SedeId($fields) {
  $sedeId = (Get-StringField $fields "sedeId").Trim().ToLower()
  if ($sedeId) { return $sedeId }
  $sede = (Get-StringField $fields "sede").Trim().ToLower()
  if ($sede -like "*norte*") { return "princesa_gales_norte" }
  if ($sede -like "*centro*") { return "princesa_gales_centro" }
  if ($sede -like "*cre ser*") { return "instituto_cre_ser" }
  return "matriz"
}

function New-StringField($value) {
  return @{ stringValue = [string]$value }
}

function New-ArrayField($values) {
  return @{
    arrayValue = @{
      values = @($values | ForEach-Object { @{ stringValue = [string]$_ } })
    }
  }
}

$primaryReviewerEmail = "nathashamachado07@gmail.com"
$finalReviewerEmails = @(
  "oscar@sudamericano.edu.ec",
  "yadira@sudamericano.edu.ec"
)
$allSedeIds = @(
  "matriz",
  "princesa_gales_norte",
  "princesa_gales_centro",
  "instituto_cre_ser"
)

$token = Get-AccessToken
$headers = @{ Authorization = "Bearer $token" }
$listUrl = "https://firestore.googleapis.com/v1/projects/$ProjectId/databases/(default)/documents/usuarios?pageSize=250"
$response = Invoke-RestMethod -Uri $listUrl -Headers $headers -Method Get

$updated = 0

foreach ($doc in $response.documents) {
  $fields = $doc.fields
  $correo = (Get-StringField $fields "correo").Trim().ToLower()
  $rolActual = (Get-StringField $fields "rol").Trim()
  $rolNormalizado = $rolActual.ToLower()
  $sedeId = Resolve-SedeId $fields

  $patchFields = @{}
  $updateMask = @()

  if ($correo -eq $primaryReviewerEmail) {
    if ($rolActual -ne "Admin") {
      $patchFields["rol"] = (New-StringField "Admin")
      $updateMask += "rol"
    }
    $patchFields["allowedSedeIds"] = (New-ArrayField $allSedeIds)
    $patchFields["matrizFlowRole"] = (New-StringField "primary")
    if ($updateMask -notcontains "allowedSedeIds") { $updateMask += "allowedSedeIds" }
    if ($updateMask -notcontains "matrizFlowRole") { $updateMask += "matrizFlowRole" }
  }
  elseif ($finalReviewerEmails -contains $correo) {
    if ($rolActual -ne "RRHH") {
      $patchFields["rol"] = (New-StringField "RRHH")
      $updateMask += "rol"
    }
    $patchFields["allowedSedeIds"] = (New-ArrayField @("matriz"))
    $patchFields["matrizFlowRole"] = (New-StringField "final")
    if ($updateMask -notcontains "allowedSedeIds") { $updateMask += "allowedSedeIds" }
    if ($updateMask -notcontains "matrizFlowRole") { $updateMask += "matrizFlowRole" }
  }
  elseif ($rolNormalizado -eq "administrativo" -or $rolNormalizado -eq "personal administrativo") {
    if ($rolActual -ne "Personal administrativo") {
      $patchFields["rol"] = (New-StringField "Personal administrativo")
      $updateMask += "rol"
    }
  }
  elseif ($rolNormalizado -eq "rrhh") {
    $patchFields["allowedSedeIds"] = (New-ArrayField @($sedeId))
    if ($updateMask -notcontains "allowedSedeIds") { $updateMask += "allowedSedeIds" }
  }

  if ($updateMask.Count -eq 0) {
    continue
  }

  $patchUrl = $doc.name -replace "^projects/$ProjectId/databases/\(default\)/documents/", ""
  $maskQuery = ($updateMask | ForEach-Object { "updateMask.fieldPaths=$([uri]::EscapeDataString($_))" }) -join "&"
  $url = "https://firestore.googleapis.com/v1/projects/$ProjectId/databases/(default)/documents/$patchUrl?$maskQuery"
  $body = @{
    fields = $patchFields
  } | ConvertTo-Json -Depth 8

  try {
    Invoke-RestMethod -Uri $url -Headers $headers -Method Patch -ContentType "application/json" -Body $body | Out-Null
  } catch {
    if ($_.Exception.Response -ne $null) {
      $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
      $reader.BaseStream.Position = 0
      $reader.DiscardBufferedData()
      $errorBody = $reader.ReadToEnd()
      throw "Error actualizando $correo: $errorBody"
    }
    throw
  }
  $updated += 1
  Write-Host "Actualizado $correo -> $($updateMask -join ', ')"
}

Write-Host "Sincronizacion completada. Documentos actualizados: $updated"
