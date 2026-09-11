# Alia Flow - Frugal Skill: verify-artifact-persisted
# Confirma que um Artifact foi PERSISTIDO de verdade no git, nao so produzido.
# Deterministico, sem LLM. Cobre o delta de persistencia que Validated Artifacts (formato) nao cobre.
# Modos:
#   - arquivo ausente no disco         -> [FAIL]    exit 1
#   - existe, fora do git              -> [CONCERN] exit 0 (ou [FAIL] exit 1 com -RequireCommitted)
#   - existe e versionado no git       -> [PASS]    exit 0, reporta o hash do ultimo commit
# Português correto, com acentos. Arquivo salvo em UTF-8 sem BOM; o único erro é caractere corrompido. Emoji continua fora de peça pública.

param(
  [Parameter(Mandatory = $true)][string]$Path,
  [string]$TaskId = "",
  [switch]$RequireCommitted
)

$ErrorActionPreference = "Stop"

function Report([string]$verdict, [string]$summary, [string]$commit = "") {
  Write-Host "=== verify-artifact-persisted ==="
  Write-Host ("Path:   " + $Path)
  if ($TaskId -ne "") { Write-Host ("Task:   " + $TaskId) }
  if ($commit -ne "") { Write-Host ("Commit: " + $commit) }
  Write-Host ("[" + $verdict + "] " + $summary)
}

# 1. Existe no disco?
if (-not (Test-Path -LiteralPath $Path)) {
  Report "FAIL" "artefato ausente: caminho nao existe no disco"
  exit 1
}

# 2. Esta rastreado pelo git?
& git ls-files --error-unmatch -- $Path 2>$null | Out-Null
$tracked = ($LASTEXITCODE -eq 0)

if (-not $tracked) {
  if ($RequireCommitted) {
    Report "FAIL" "persistido em disco mas nao versionado no git (-RequireCommitted exige commit)"
    exit 1
  }
  Report "CONCERN" "persistido em disco, nao commitado no git (divida rastreada)"
  exit 0
}

# 3. Rastreado: pega o hash do ultimo commit que tocou o arquivo.
$commit = (& git log -1 --format=%h -- $Path 2>$null)
if ([string]::IsNullOrWhiteSpace($commit)) { $commit = "(sem commit no historico)" }

Report "PASS" "persistido e versionado no git" $commit
exit 0
