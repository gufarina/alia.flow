<#
  revert-alia.ps1 - caminho de volta para quem rodou update-online.ps1/update-engine.ps1 e so
  percebeu o problema DEPOIS (o script deu tudo certo, mas o resultado nao serve). Lista os
  backups .alia-backup-<stamp> existentes na raiz, deixa escolher (ou assume o mais recente se so
  houver um), mostra o que vai ser restaurado ANTES de agir, e pede confirmacao explicita.

  Reusa (nao reimplementa) o miolo de update-online.ps1: dot-source em modo TEST_ONLY para pegar
  $protected, Restore-Engine e Assert-SafeCopySet - a MESMA lista de protegidos, nunca uma segunda.

  Uso (dois cliques via reverter-alia.bat, ou direto):
    powershell -ExecutionPolicy Bypass -File scripts/revert-alia.ps1
    powershell -ExecutionPolicy Bypass -File scripts/revert-alia.ps1 -BackupName ".alia-backup-20260910-120000"
    powershell -ExecutionPolicy Bypass -File scripts/revert-alia.ps1 -Yes   # sem prompt (automacao/teste)
#>
param(
  [string]$BackupName,
  [switch]$Yes,
  [string]$RootOverride
)

$ErrorActionPreference = "Stop"

# Dot-source PRIMEIRO (update-online.ps1 define sua propria $root com base no PSScriptRoot dele);
# so DEPOIS aplicamos $RootOverride, senao o dot-source pisa na nossa variavel.
$env:ALIA_UPDATE_ONLINE_TEST_ONLY = "1"
. (Join-Path $PSScriptRoot "update-online.ps1")
Remove-Item Env:\ALIA_UPDATE_ONLINE_TEST_ONLY -ErrorAction SilentlyContinue
if ($RootOverride) { $root = $RootOverride }

if (-not (Test-ValidAliaRoot -RootDir $root)) {
  Write-Host ("[ABORTADO] " + $root + " nao parece uma instancia Alia (falta VERSION+alia.config.json ou engine\constitution.md).")
  exit 1
}

$backups = @(Get-ChildItem -LiteralPath $root -Directory -Force -Filter ".alia-backup-*" -ErrorAction SilentlyContinue |
  Sort-Object Name -Descending)

if ($backups.Count -eq 0) {
  Write-Host "[SEM BACKUP] nenhum .alia-backup-* encontrado em $root - nao ha para onde reverter."
  Write-Host "             (backup automatico so existe apos rodar update-online.ps1 ou update-engine.ps1 pelo menos uma vez)"
  exit 1
}

function Get-BackupDate([string]$name) {
  if ($name -match '\.alia-backup-(\d{8})-(\d{6})$') {
    $d = $Matches[1]; $t = $Matches[2]
    try {
      return [datetime]::ParseExact("$d$t", "yyyyMMddHHmmss", $null).ToString("dd/MM/yyyy HH:mm:ss")
    } catch { return $name }
  }
  return $name
}

$chosen = $null
if ($BackupName) {
  $chosen = $backups | Where-Object { $_.Name -eq $BackupName } | Select-Object -First 1
  if (-not $chosen) {
    Write-Host ("[ABORTADO] backup '" + $BackupName + "' nao existe em " + $root)
    exit 1
  }
} elseif ($backups.Count -eq 1) {
  $chosen = $backups[0]
  Write-Host ("Unico backup encontrado: " + $chosen.Name + " (" + (Get-BackupDate $chosen.Name) + ")")
} else {
  Write-Host "Backups encontrados (do mais recente para o mais antigo):"
  for ($i = 0; $i -lt $backups.Count; $i++) {
    Write-Host ("  [" + ($i + 1) + "] " + $backups[$i].Name + "  (" + (Get-BackupDate $backups[$i].Name) + ")")
  }
  if ($Yes) {
    $chosen = $backups[0]
    Write-Host ("-Yes: usando o mais recente -> " + $chosen.Name)
  } else {
    $resp = Read-Host ("Qual restaurar? [1-" + $backups.Count + "] (Enter = 1, o mais recente)")
    $idx = 0
    if ($resp -and [int]::TryParse($resp, [ref]$idx) -and $idx -ge 1 -and $idx -le $backups.Count) {
      $chosen = $backups[$idx - 1]
    } else {
      $chosen = $backups[0]
    }
  }
}

$backupDir = $chosen.FullName
$items = @(Get-ChildItem -LiteralPath $backupDir -Force | Select-Object -ExpandProperty Name)

if ($items.Count -eq 0) {
  Write-Host ("[ABORTADO] " + $chosen.Name + " esta vazio - nada para restaurar.")
  exit 1
}

# Reusa a MESMA guarda de seguranca de update-online.ps1: nunca toca a camada do operador.
try {
  Assert-SafeCopySet -CopySet $items -Protected $protected
} catch {
  Write-Host ("[ABORTADO] " + $_.Exception.Message.Substring(12))
  exit 1
}

Write-Host ""
Write-Host ("Vou restaurar a partir de: " + $chosen.Name + "  (" + (Get-BackupDate $chosen.Name) + ")")
Write-Host "Isso vai SUBSTITUIR, na instalacao atual, exatamente estes itens do motor:"
foreach ($it in $items) { Write-Host ("  - " + $it) }
Write-Host "Sua camada de dados (clients, studio, memory, state.json, studio.yaml, alia.config.json) NAO e tocada."
Write-Host ""

if (-not $Yes) {
  $conf = Read-Host "Confirma a restauracao? Digite SIM para continuar"
  if ($conf -ne "SIM") {
    Write-Host "[CANCELADO] nada foi alterado."
    exit 0
  }
}

Restore-Engine -DestDir $root -BackupDir $backupDir -CopySet $items
Write-Host ("[OK] restaurado a partir de " + $chosen.Name + " (" + (Get-BackupDate $chosen.Name) + ").")
exit 0
