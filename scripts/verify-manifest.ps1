# Alia Flow - Verify Manifest (integridade do pacote, supply-chain leve)
# Le <Dir>/MANIFEST.sha256 (gerado por make-manifest.ps1), recalcula o hash de cada
# arquivo listado e compara. Reporta arquivos ALTERADOS (hash diferente), FALTANDO
# (listados no manifesto mas ausentes no disco) e EXTRA (presentes no disco, fora do
# manifesto). Isto prova INTEGRIDADE (o pacote nao foi corrompido/alterado depois de
# empacotado), nao autenticidade de origem (PKI). Ver docs/INTEGRIDADE.md.
# Sem acentos, sem emojis. UTF-8 sem BOM.

param(
  [Parameter(Mandatory)][string]$Dir,
  [switch]$Json
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $Dir -PathType Container)) {
  Write-Host ("[ERRO] pasta nao encontrada: " + $Dir)
  exit 1
}

$dirFull = (Get-Item -LiteralPath $Dir).FullName
$manifestPath = Join-Path $dirFull "MANIFEST.sha256"

if (-not (Test-Path -LiteralPath $manifestPath)) {
  Write-Host ("[ERRO] MANIFEST.sha256 nao encontrado em: " + $dirFull)
  exit 1
}

function ReadAsciiLines([string]$path) {
  $utf8 = New-Object System.Text.UTF8Encoding($false)
  $text = [System.IO.File]::ReadAllText($path, $utf8)
  return $text -split "`r?`n" | Where-Object { $_ -ne "" }
}

# Carrega o manifesto: mapa caminho relativo -> hash esperado.
$expected = [ordered]@{}
foreach ($line in (ReadAsciiLines $manifestPath)) {
  if ($line -match '^\s*([0-9a-fA-F]{64})\s\s(.+)\s*$') {
    $expected[$matches[2]] = $matches[1].ToLower()
  }
}

# Estado atual do disco (mesma regra de exclusao do make-manifest: sem o proprio manifesto, sem .git).
$diskFiles = Get-ChildItem -LiteralPath $dirFull -Recurse -File -Force |
  Where-Object {
    $rel = $_.FullName.Substring($dirFull.Length).TrimStart('\', '/')
    ($rel -ne "MANIFEST.sha256") -and ($rel -notmatch '(^|[\\/])\.git([\\/]|$)')
  }

$diskMap = [ordered]@{}
foreach ($f in $diskFiles) {
  $rel = $f.FullName.Substring($dirFull.Length).TrimStart('\', '/') -replace '\\', '/'
  $diskMap[$rel] = $f.FullName
}

$changed = @()
$missing = @()
$extra = @()

foreach ($rel in $expected.Keys) {
  if (-not $diskMap.Contains($rel)) {
    $missing += $rel
    continue
  }
  $actualHash = (Get-FileHash -LiteralPath $diskMap[$rel] -Algorithm SHA256).Hash.ToLower()
  if ($actualHash -ne $expected[$rel]) {
    $changed += $rel
  }
}

foreach ($rel in $diskMap.Keys) {
  if (-not $expected.Contains($rel)) {
    $extra += $rel
  }
}

$total = $expected.Count
$ok = ($changed.Count -eq 0) -and ($missing.Count -eq 0) -and ($extra.Count -eq 0)

if ($Json) {
  $result = [PSCustomObject]@{
    total   = $total
    changed = $changed
    missing = $missing
    extra   = $extra
    ok      = $ok
  }
  $result | ConvertTo-Json -Depth 3
} else {
  Write-Host "=== Alia Flow Verify Manifest ==="
  Write-Host ("  pasta:     " + $dirFull)
  Write-Host ("  manifesto: " + $manifestPath)
  Write-Host ("  esperado:  " + $total + " arquivos")
  Write-Host ""
  if ($ok) {
    Write-Host ("[OK] integridade confirmada: " + $total + " arquivos")
  } else {
    Write-Host "[FALHA] divergencia encontrada:"
    if ($changed.Count -gt 0) {
      Write-Host "  ALTERADOS:"
      foreach ($f in $changed) { Write-Host ("    - " + $f) }
    }
    if ($missing.Count -gt 0) {
      Write-Host "  FALTANDO:"
      foreach ($f in $missing) { Write-Host ("    - " + $f) }
    }
    if ($extra.Count -gt 0) {
      Write-Host "  EXTRA (nao listado no manifesto):"
      foreach ($f in $extra) { Write-Host ("    - " + $f) }
    }
  }
}

if ($ok) { exit 0 } else { exit 1 }
