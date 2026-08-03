# Alia Flow - Guard Core (sentinela de fronteira do nucleo)
# Protege o NUCLEO do motor (engine/constitution.md, glossary.md, agents/persona.md,
# orchestration.md - os L1 listados em engine/MAP.md, "Nucleo (ja carregado no boot)") de
# edicao acidental. Compara o conteudo atual contra um baseline de hashes SHA256
# (engine/.core-baseline.sha256). Mudanca sem -AllowCore = bloqueio: forca a pessoa a
# confirmar que a mudanca no nucleo foi intencional. Espelha a fronteira ja definida em
# engine/governance/provenance.md (nucleo = so o operador humano muda, fora do ciclo automatico).
# Sem acentos, sem emojis. UTF-8 sem BOM.

param([switch]$AllowCore, [switch]$Json)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot          # raiz do alia/
$engine = Join-Path $root "engine"

# Lista de NUCLEO protegido (L1) - facil de estender.
$coreFiles = @(
  "constitution.md",
  "glossary.md",
  "agents\persona.md",
  "orchestration.md"
)

$baselinePath = Join-Path $engine ".core-baseline.sha256"

function WriteAsciiFile([string]$path, [string]$content) {
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($path, $content, $utf8NoBom)
}

function LoadBaseline([string]$path) {
  $map = @{}
  if (Test-Path -LiteralPath $path) {
    foreach ($line in Get-Content -LiteralPath $path) {
      if ($line -match '^\s*([^\s]+)\s+(.+)\s*$') {
        $map[$matches[1]] = $matches[2]
      }
    }
  }
  return $map
}

$baselineExists = Test-Path -LiteralPath $baselinePath
$baseline = LoadBaseline $baselinePath

# Hash atual de cada arquivo de nucleo.
$core = @()
foreach ($f in $coreFiles) {
  $full = Join-Path $engine $f
  $hash = ""
  if (Test-Path -LiteralPath $full) {
    $hash = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash
  }
  $prev = $null
  if ($baseline.ContainsKey($f)) { $prev = $baseline[$f] }
  $changed = ($null -ne $prev) -and ($prev -ne $hash)
  $core += [PSCustomObject]@{
    file    = $f
    hash    = $hash
    changed = $changed
  }
}

$changedFiles = @($core | Where-Object { $_.changed })
$blocked = $false
$mode = ""
$message = ""

if (-not $baselineExists) {
  # Primeira execucao: cria o baseline a partir do estado atual.
  $lines = foreach ($c in $core) { $c.file + " " + $c.hash }
  WriteAsciiFile $baselinePath (($lines -join "`n") + "`n")
  $mode = "baseline-created"
  $message = "[OK] baseline inicial do nucleo criado"
  $blocked = $false
} elseif ($AllowCore) {
  # Recalcula e grava o baseline (registra a mudanca como autorizada).
  $lines = foreach ($c in $core) { $c.file + " " + $c.hash }
  WriteAsciiFile $baselinePath (($lines -join "`n") + "`n")
  $mode = "baseline-updated"
  $message = "[OK] baseline do nucleo atualizado"
  $blocked = $false
} elseif ($changedFiles.Count -gt 0) {
  $mode = "blocked"
  $names = ($changedFiles | ForEach-Object { $_.file }) -join ", "
  $message = "[BLOQUEIO] mudanca no nucleo detectada: " + $names + ". Se foi intencional, rode de novo com -AllowCore para registrar o novo baseline."
  $blocked = $true
} else {
  $mode = "intact"
  $message = "[OK] nucleo integro"
  $blocked = $false
}

if ($Json) {
  $result = [PSCustomObject]@{
    core           = $core
    baselineExists = $baselineExists
    blocked        = $blocked
  }
  $result | ConvertTo-Json -Depth 5
} else {
  Write-Host "=== Alia Flow Guard Core ==="
  foreach ($c in $core) {
    $tag = if ($c.changed) { "[MUDOU]" } else { "[OK]" }
    Write-Host ("  " + $tag + " " + $c.file)
  }
  Write-Host ""
  Write-Host $message
}

if ($blocked) { exit 1 } else { exit 0 }
