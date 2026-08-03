# Alia Flow - Semantic Lint (linguagem ubiqua)
# Linter que bloqueia vocabulario proibido/deprecated no motor (engine/ + scripts/*.ps1).
# Fonte dos termos: le a secao GUARD: de docs/CLAIMS.md (mesma fonte de verdade do smoke-test.ps1,
# bloco "Guard de vetos") - nao duplica a lista.
# Sem acentos, sem emojis. UTF-8 sem BOM.

param([switch]$Json)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot          # raiz do alia/
$engine = Join-Path $root "engine"
$scriptsDir = $PSScriptRoot

function ReadLines([string]$path) {
  return [System.IO.File]::ReadAllLines($path, (New-Object System.Text.UTF8Encoding($false)))
}

# --- Fonte dos termos proibidos: GUARD: em docs/CLAIMS.md ---
$claimsPath = Join-Path $root "docs\CLAIMS.md"
$guards = @()
if (Test-Path $claimsPath) {
  foreach ($line in (Get-Content -LiteralPath $claimsPath -Encoding UTF8)) {
    if ($line -match '^\s*GUARD:\s*(.+?)\s*$') { $guards += $Matches[1] }
  }
}

# --- Escopo de varredura: motor que faz ship ---
# engine/**/*.md, engine/**/*.yaml, scripts/*.ps1 (nao recursivo em scripts, so os .ps1 diretos).
$scanFiles = @()
if (Test-Path $engine) {
  $scanFiles += Get-ChildItem -LiteralPath $engine -Recurse -File -Include *.md,*.yaml -ErrorAction SilentlyContinue
}
if (Test-Path $scriptsDir) {
  # scripts internos do dono, excluidos do pacote publico por package-release.ps1 (nunca fazem
  # ship - migracao unica da maquina do dono, inuteis numa instalacao limpa). Nao sao "o motor".
  $internalScripts = @("migrate-to-studio.ps1", "extract-secrets.ps1")
  $scanFiles += Get-ChildItem -LiteralPath $scriptsDir -File -Include *.ps1 -ErrorAction SilentlyContinue |
    Where-Object { $internalScripts -notcontains $_.Name }
}

# --- Rodar cada regra contra o escopo, linha a linha ---
$rules = @()
$anyViolation = $false
foreach ($g in $guards) {
  $hits = @()
  foreach ($f in $scanFiles) {
    $lines = ReadLines $f.FullName
    for ($i = 0; $i -lt $lines.Length; $i++) {
      if ($lines[$i] -cmatch $g) {
        $hits += [PSCustomObject]@{ file = $f.FullName.Substring($root.Length + 1); line = $i + 1 }
      }
    }
  }
  $ok = ($hits.Count -eq 0)
  if (-not $ok) { $anyViolation = $true }
  $rules += [PSCustomObject]@{ pattern = $g; ok = $ok; hits = $hits }
}

$clean = (-not $anyViolation) -and ($guards.Count -gt 0)

if ($Json) {
  $out = [PSCustomObject]@{ rules = $rules; clean = $clean }
  $out | ConvertTo-Json -Depth 6
} else {
  Write-Host "=== Alia Flow - Semantic Lint (linguagem ubiqua) ==="
  Write-Host ("fonte: " + $claimsPath)
  Write-Host ""
  if ($guards.Count -eq 0) {
    Write-Host "[FALHA] nenhum GUARD: encontrado em docs/CLAIMS.md"
  } else {
    foreach ($r in $rules) {
      if ($r.ok) {
        Write-Host ("[OK] /" + $r.pattern + "/ -> 0 ocorrencias")
      } else {
        Write-Host ("[FALHA] /" + $r.pattern + "/ -> " + $r.hits.Count + " ocorrencia(s)")
        foreach ($h in $r.hits) {
          Write-Host ("       " + $h.file + ":" + $h.line)
        }
      }
    }
  }
  Write-Host ""
  $okCount = @($rules | Where-Object { $_.ok }).Count
  $badCount = @($rules | Where-Object { -not $_.ok }).Count
  Write-Host ($okCount.ToString() + " regras OK, " + $badCount.ToString() + " violadas")
  if ($clean) {
    Write-Host "LINGUAGEM LIMPA"
  } else {
    Write-Host "VOCABULARIO PROIBIDO ENCONTRADO"
  }
}

if ($clean) { exit 0 } else { exit 1 }
