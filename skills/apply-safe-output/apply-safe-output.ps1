# Alia Flow - Frugal Skill: apply-safe-output
# Executor deterministico (sem LLM) do block_when da provenance. Le o campo provenance do ALVO
# e aplica a regra que ja vive em engine/governance/provenance.yaml:64-66:
#   block_when:              provenance == nucleo AND change_source == automation  -> BLOQUEIA
#   require_for_agent_authored: [diff, evidence]                                   -> sem os dois, reprova
# REUSE total: nao inventa politica; so executa o contrato declarado em provenance.yaml.
# E o primeiro mecanismo do "hook futuro" admitido em orchestration.md:104-107 - a porta de
# escrita aprovada por resultado deixa de depender de adesao do modelo.
#
# Saida:
#   permitido (allow)      -> [PASS] exit 0
#   bloqueado/reprovado    -> [FAIL] exit 1, com o desvio exato apontado (deviation)
# Português correto, com acentos. Arquivo salvo em UTF-8 sem BOM; o único erro é caractere corrompido. Emoji continua fora de peça pública.

param(
  [Parameter(Mandatory = $true)][string]$Path,
  [ValidateSet("automation", "operator")][string]$Source = "automation",
  [switch]$Diff,
  [switch]$Evidence,
  [string]$ManifestPath = ""
)

$ErrorActionPreference = "Stop"

function ReadText([string]$p) {
  $utf8 = New-Object System.Text.UTF8Encoding($false)
  return [System.IO.File]::ReadAllText($p, $utf8)
}

$script:deviations = @()
function Deviate([string]$msg) { $script:deviations += $msg }

# Resolve a provenance do alvo. Ordem (a excecao explicita vence o padrao):
#   1. Campo top-level "provenance:" no proprio alvo (.yaml/SKILL.md frontmatter).
#   2. Mapa de provenance.yaml: nucleo[] / agent_authored[] (match por basename ou glob *.yaml).
#   3. Defaults: engine/ = nucleo; studio/ = agent-authored.
function ResolveProvenance([string]$target, [string]$manifestTxt) {
  # 1. Campo no proprio alvo.
  if (Test-Path -LiteralPath $target) {
    $c = ReadText $target
    $fm = [regex]::Match($c, '(?im)^\s*provenance:\s*(nucleo|agent-authored)\s*$')
    if ($fm.Success) { return $fm.Groups[1].Value }
  }

  $norm = ($target -replace '\\', '/')
  $leaf = (Split-Path -Leaf $target)

  # 2. Mapa explicito de provenance.yaml. Coleta as duas listas.
  function MatchList([string]$listName) {
    $lm = [regex]::Match($manifestTxt, ('(?ms)^\s*' + $listName + ':\s*\n((?:\s+-\s+.*\n)+)'))
    if (-not $lm.Success) { return $false }
    foreach ($ln in [regex]::Matches($lm.Groups[1].Value, '(?m)^\s*-\s*"?([^"\r\n]+?)"?\s*$')) {
      $entry = $ln.Groups[1].Value.Trim()
      if ($entry -eq "") { continue }
      # glob *.yaml -> compara extensao na mesma pasta; senao compara por sufixo de caminho/basename.
      if ($entry -match '\*') {
        $rx = '^' + [regex]::Escape($entry).Replace('\*', '[^/]*') + '$'
        $dir = ($entry -replace '/[^/]+$', '')
        $tdir = ($norm -replace '/[^/]+$', '')
        if (($tdir -like ('*' + $dir)) -and ($leaf -match ($rx -replace '.*/', '^'))) { return $true }
        if ($leaf -match ('^' + [regex]::Escape((Split-Path -Leaf $entry)).Replace('\*', '[^.]*') + '$')) { return $true }
      } else {
        $entryLeaf = Split-Path -Leaf $entry
        if (($norm -like ('*' + $entry)) -or ($leaf -eq $entryLeaf)) { return $true }
      }
    }
    return $false
  }

  if (MatchList "nucleo") { return "nucleo" }
  if (MatchList "agent_authored") { return "agent-authored" }

  # 3. Defaults por arvore.
  if ($norm -match '(^|/)engine/') { return "nucleo" }
  if ($norm -match '(^|/)studio') { return "agent-authored" }

  return "(indeterminado)"
}

# Resolve o manifesto (fonte da verdade do block_when).
if ($ManifestPath -eq "") {
  $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
  $ManifestPath = Join-Path $root "engine\governance\provenance.yaml"
}
if (-not (Test-Path -LiteralPath $ManifestPath)) {
  Write-Host "=== apply-safe-output ==="
  Write-Host ("Alvo:   " + $Path)
  Write-Host "[FAIL] saida insegura bloqueada"
  Write-Host ("  deviation: manifesto de provenance ausente: " + $ManifestPath)
  exit 1
}

$manifestTxt = ReadText $ManifestPath
$prov = ResolveProvenance $Path $manifestTxt

Write-Host "=== apply-safe-output ==="
Write-Host ("Alvo:        " + $Path)
Write-Host ("Provenance:  " + $prov)
Write-Host ("Origem:      " + $Source)

# block_when: provenance == nucleo AND change_source == automation -> BLOQUEIO duro.
if ($prov -eq "nucleo" -and $Source -eq "automation") {
  Deviate "block_when: nucleo + automation -> auto-edicao em nucleo e bloqueada. So o operador muda."
}

# require_for_agent_authored: [diff, evidence] - a automacao SEMPRE propoe via diff, com evidencia.
if ($prov -eq "agent-authored" -and $Source -eq "automation") {
  if (-not $Diff) { Deviate "require_for_agent_authored: falta o diff (a automacao nunca aplica direto, so propoe diff)" }
  if (-not $Evidence) { Deviate "require_for_agent_authored: falta a evidence que justifica a mudanca" }
}

if ($prov -eq "(indeterminado)") {
  Deviate "provenance do alvo indeterminada: sem campo proprio, fora do mapa e fora de engine/|studio/"
}

if ($script:deviations.Count -eq 0) {
  Write-Host "[PASS] saida permitida (provenance + origem dentro da regra)"
  exit 0
} else {
  Write-Host "[FAIL] saida insegura bloqueada"
  foreach ($d in $script:deviations) { Write-Host ("  deviation: " + $d) }
  exit 1
}
