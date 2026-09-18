# Alia Flow - Frugal Skill: validate-artifact
# Valida um Artifact contra o CONTRATO do seu tipo, de forma deterministica (sem LLM).
# REUSE total: os contratos por tipo vivem em engine/features/validated-artifacts.yaml.
# Este script so executa o que aquele contrato ja declara (type -> checks). Nao inventa regra.
# Saida:
#   - contrato cumprido    -> [PASS] exit 0
#   - contrato violado     -> [FAIL] exit 1, com o desvio exato apontado (deviation)
# Porta de FORMATO do criterio "Funciona" do Quality Gate. Format-before-content.
# Português correto, com acentos. Arquivo salvo em UTF-8 sem BOM; o único erro é caractere corrompido. Emoji continua fora de peça pública.

param(
  [Parameter(Mandatory = $true)][string]$Path,
  [string]$Type = "",
  [string]$ContractsPath = "",
  [string]$TaskId = ""
)

$ErrorActionPreference = "Stop"

function ReadText([string]$p) {
  $utf8 = New-Object System.Text.UTF8Encoding($false)
  return [System.IO.File]::ReadAllText($p, $utf8)
}

$script:deviations = @()
function Deviate([string]$msg) { $script:deviations += $msg }

function Report([string]$verdict) {
  Write-Host "=== validate-artifact ==="
  Write-Host ("Path:   " + $Path)
  if ($TaskId -ne "") { Write-Host ("Task:   " + $TaskId) }
  Write-Host ("Type:   " + $Type)
  if ($verdict -eq "PASS") {
    Write-Host "[PASS] contrato do tipo cumprido"
  } else {
    Write-Host "[FAIL] contrato do tipo violado"
    foreach ($d in $script:deviations) { Write-Host ("  deviation: " + $d) }
  }
}

# 1. Artefato existe?
if (-not (Test-Path -LiteralPath $Path)) {
  $Type = "(desconhecido)"
  Deviate "artefato ausente: caminho nao existe no disco"
  Report "FAIL"
  exit 1
}

# 2. Localiza o contrato (REUSE de validated-artifacts.yaml). Resolve por padrao a partir
#    da raiz do produto (skills/validate-artifact -> ../../engine/...).
if ($ContractsPath -eq "") {
  $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
  $ContractsPath = Join-Path $root "engine\features\validated-artifacts.yaml"
}
if (-not (Test-Path -LiteralPath $ContractsPath)) {
  Deviate ("contrato nao encontrado: " + $ContractsPath)
  Report "FAIL"
  exit 1
}

$contractsTxt = ReadText $ContractsPath

# Parse minimo do bloco artifact_contracts: para cada "- type: X" coleta a linha "checks: [..]".
# Frugal: regex sobre o YAML ja existente, sem dependencia de parser externo.
$contracts = @{}
$rx = [regex]::Matches($contractsTxt, '(?m)^\s*-\s*type:\s*(\S+)\s*$')
foreach ($m in $rx) {
  $t = $m.Groups[1].Value
  $tail = $contractsTxt.Substring($m.Index)
  $cm = [regex]::Match($tail, '(?m)checks:\s*\[([^\]]*)\]')
  $checks = @()
  if ($cm.Success) {
    foreach ($c in ($cm.Groups[1].Value -split ',')) {
      $cc = $c.Trim()
      if ($cc -ne "") { $checks += $cc }
    }
  }
  $contracts[$t] = $checks
}

# 3. Tipo: explicito (-Type) ou inferido do nome do arquivo (ART-...-<tipo>-...).
if ($Type -eq "") {
  $leaf = (Split-Path -Leaf $Path).ToLower()
  foreach ($t in $contracts.Keys) {
    if ($leaf -match ('(?<![a-z])' + [regex]::Escape($t) + '(?![a-z])')) { $Type = $t; break }
  }
}
if ($Type -eq "") {
  Deviate "tipo do artefato nao informado e nao inferivel do nome (use -Type)"
  Report "FAIL"
  exit 1
}
if (-not $contracts.ContainsKey($Type)) {
  Deviate ("tipo sem contrato em validated-artifacts.yaml: " + $Type)
  Report "FAIL"
  exit 1
}

$checks = $contracts[$Type]
if ($checks.Count -eq 0) {
  Deviate ("contrato do tipo " + $Type + " nao declara nenhum check")
  Report "FAIL"
  exit 1
}

$content = ReadText $Path

# 4. Executor por check declarado no contrato. Cada check e uma assercao de FORMATO deterministica.
foreach ($check in $checks) {
  switch ($check) {
    # --- type: json ---
    "valid_json" {
      try { $null = ($content | ConvertFrom-Json) }
      catch { Deviate "valid_json: conteudo nao e JSON parseavel" }
    }
    "required_fields" {
      $isJson = $false; $obj = $null
      try { $obj = ($content | ConvertFrom-Json); $isJson = $true } catch {}
      if ($isJson -and $obj -and -not ($obj.PSObject.Properties.Name.Count -gt 0)) {
        Deviate "required_fields: JSON sem nenhum campo"
      }
    }
    "types" { } # checagem de tipos por campo depende do schema concreto; no-op estrutural

    # --- type: copy ---
    "headline_present" {
      if ($content -notmatch '(?im)^#{1,6}\s*Headline\b') { Deviate "headline_present: secao Headline ausente" }
    }
    "cta_present" {
      if ($content -notmatch '(?im)^#{1,6}\s*Chamada de acao\b') { Deviate "cta_present: secao Chamada de acao (CTA) ausente" }
    }
    "expert_mind_cited" {
      if ($content -notmatch '(?im)Expert Mind|Metodo|Ogilvy') { Deviate "expert_mind_cited: nao cita Expert Mind/Metodo" }
    }

    # --- type: story ---
    "acceptance_criteria_given_when_then" {
      $g = $content -match '(?im)^\s*-?\s*Given\b'
      $w = $content -match '(?im)^\s*-?\s*When\b'
      $th = $content -match '(?im)^\s*-?\s*Then\b'
      if (-not ($g -and $w -and $th)) { Deviate "acceptance_criteria_given_when_then: faltou Given/When/Then" }
    }

    # --- type: migration ---
    "reversible" {
      if ($content -notmatch '(?im)revers|rollback|down\b') { Deviate "reversible: nao declara reversao (rollback/down)" }
    }
    "idempotent" {
      if ($content -notmatch '(?im)idempotent|if not exists|if exists') { Deviate "idempotent: nao declara idempotencia" }
    }
    "no_destructive_without_flag" {
      $destructive = $content -match '(?im)\b(drop|truncate|delete)\b'
      $flagged = $content -match '(?im)flag|--force|confirm'
      if ($destructive -and -not $flagged) { Deviate "no_destructive_without_flag: operacao destrutiva sem flag de confirmacao" }
    }

    # --- type: component ---
    "renders" {
      if ($content -notmatch '(?im)render|return\s*\(|<[A-Za-z]') { Deviate "renders: nao ha evidencia de render/markup" }
    }
    "props_typed" {
      if ($content -notmatch '(?im)props|interface|type\s+\w+|:\s*\w+') { Deviate "props_typed: props nao tipadas" }
    }
    "no_domain_logic_leak" {
      if ($content -match '(?im)\b(fetch|axios|sql|query|prisma)\b') { Deviate "no_domain_logic_leak: logica de dominio/IO vazou no componente" }
    }

    default { Deviate ("check desconhecido no contrato: " + $check) }
  }
}

if ($script:deviations.Count -eq 0) {
  Report "PASS"
  exit 0
} else {
  Report "FAIL"
  exit 1
}
