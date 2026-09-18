# release-gate.ps1 - portao final antes do push do repo publico do Alia Flow.
# Incidente real (TASK-565, relatado pelo CEO via Codex, 14/09/2026): o commit 2763d59 aplicou o
# pacote no repo do produto (Projetos/alia-flow) por robocopy manual (o Courier faz esse passo a
# mao, nao existe script que copie e ja empurre), mas um git checkout restaurou o README.md antigo
# da oficina DEPOIS do MANIFEST.sha256 ter sido gerado com o README novo - o manifesto ficou
# divergente do disco (README.md ALTERADO, docs/assets/olho-alia.gif EXTRA) e so foi descoberto
# porque o instalador publico (irm .../install.ps1 | iex) ABORTA por integridade. Ninguem rodou
# verify-manifest.ps1 DEPOIS de aplicar o pacote no repo, so DENTRO do pacote em staging.
#
# Este script fecha esse buraco: roda check-public-surface.ps1 + verify-manifest.ps1 no REPO DO
# PRODUTO (o alvo real do robocopy, nao o staging), e sai 1 se qualquer um reprovar. Regra: o
# push do produto so acontece com este script verde (ver docs/INTEGRIDADE.md).
#
# Uso: powershell -File scripts/release-gate.ps1 -Repo <caminho do repo do produto>
#
# TASK-617 (mandato do CEO, 17/09/2026): o commit 62ff860 do repo publico saiu com o e-mail
# PESSOAL do CEO no campo committer - so foi achado porque o CEO pediu revisao adversarial DEPOIS
# do push. `grep` por committer/GIT_AUTHOR/%ae/%ce em scripts/*.ps1 desta oficina dava ZERO: nenhum
# script conferia identidade de commit, entao mesmo rodando este gate o vazamento passava. Passo
# 1/4 abaixo fecha esse buraco - varre TODOS os commits do repo alvo contra uma allowlist estreita.
#
# TASK-618 (mandato do CEO, 17/09/2026): o ZIP publico do GitHub falhava verify-manifest.ps1 na mao
# do cliente porque `.opencode/.gitignore` se auto-ignora (linha 5 = ".gitignore") - o git nunca o
# rastreia, o ZIP nunca o entrega, mas make-manifest.ps1 lia o DISCO (onde o arquivo existe) e
# prometia o arquivo no manifesto. release-gate.ps1 rodava contra a pasta local, onde o arquivo
# existe em disco, e passava verde com o cliente quebrado. Passo 3/4 abaixo fecha esse buraco -
# compara o conjunto do manifesto com `git ls-files` nos dois sentidos.

[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Repo
)

$ErrorActionPreference = "Stop"

# Allowlist de identidade de commit (TASK-617). Nasce ESTREITA e NOMEADA aqui - qualquer nome ou
# e-mail de commit (author OU committer) fora desta lista reprova o gate. Autores multiplos so
# entram aqui por decisao explicita, nunca por conveniencia de quem esta publicando.
$AllowedCommitIdentities = @(
  @{ Name = "Alia Flow"; Email = "noreply@alia-flow.local" }
)

function Test-CommitIdentities {
  param([string]$RepoPath, [array]$Allowlist)
  $result = [ordered]@{ Ok = $true; Skipped = $false; Violations = @() }
  Push-Location -LiteralPath $RepoPath
  try {
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue"
    & git rev-parse --is-inside-work-tree 1>$null 2>$null
    $rc = $LASTEXITCODE
    $ErrorActionPreference = $prevEap
    if ($rc -ne 0) { $result.Skipped = $true; return $result }
    $lines = & git log --all --format='%H|%an|%ae|%cn|%ce' 2>$null
    $violations = @()
    foreach ($line in $lines) {
      if ([string]::IsNullOrWhiteSpace($line)) { continue }
      $parts = $line -split '\|', 5
      if ($parts.Count -lt 5) { continue }
      $hashShort = $parts[0].Substring(0, [Math]::Min(10, $parts[0].Length))
      $an = $parts[1]; $ae = $parts[2]; $cn = $parts[3]; $ce = $parts[4]
      $authorOk = @($Allowlist | Where-Object { $_.Name -eq $an -and $_.Email -eq $ae }).Count -gt 0
      $committerOk = @($Allowlist | Where-Object { $_.Name -eq $cn -and $_.Email -eq $ce }).Count -gt 0
      if (-not $authorOk) { $violations += ("commit " + $hashShort + ", campo author: nome='" + $an + "' email='" + $ae + "' fora da allowlist") }
      if (-not $committerOk) { $violations += ("commit " + $hashShort + ", campo committer: nome='" + $cn + "' email='" + $ce + "' fora da allowlist") }
    }
    $result.Violations = $violations
    $result.Ok = ($violations.Count -eq 0)
  } finally {
    Pop-Location
  }
  return $result
}

function Test-ManifestVsGitLsFiles {
  param([string]$RepoPath, [string]$ScriptDir)
  $result = [ordered]@{ Ok = $true; Skipped = $false; NotTrackedByGit = @(); MissingFromManifest = @() }
  $manifestPath = Join-Path $RepoPath "MANIFEST.sha256"
  if (-not (Test-Path -LiteralPath $manifestPath)) { $result.Skipped = $true; return $result }
  $prevEap = $ErrorActionPreference
  $ErrorActionPreference = "SilentlyContinue"
  & git -C $RepoPath rev-parse --is-inside-work-tree 1>$null 2>$null
  $rc = $LASTEXITCODE
  $ErrorActionPreference = $prevEap
  if ($rc -ne 0) { $result.Skipped = $true; return $result }

  . (Join-Path $ScriptDir "_manifest-exclude.ps1")

  $manifestPaths = @(Get-Content -LiteralPath $manifestPath | ForEach-Object {
    if ($_ -match '^[0-9a-f]{64}  (.+)$') { $Matches[1] }
  } | Where-Object { $_ })

  $gitPaths = @(& git -C $RepoPath ls-files | Where-Object { -not (Test-ManifestExcluded $_) })

  $manifestSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$manifestPaths)
  $gitSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$gitPaths)

  $result.NotTrackedByGit = @($manifestPaths | Where-Object { -not $gitSet.Contains($_) })
  $result.MissingFromManifest = @($gitPaths | Where-Object { -not $manifestSet.Contains($_) })
  $result.Ok = ($result.NotTrackedByGit.Count -eq 0 -and $result.MissingFromManifest.Count -eq 0)
  return $result
}

if (-not (Test-Path -LiteralPath $Repo -PathType Container)) {
  Write-Host ("[ERRO] pasta do repo nao encontrada: " + $Repo)
  exit 1
}

$repoFull = (Get-Item -LiteralPath $Repo).FullName
$here = Split-Path -Parent $PSCommandPath

Write-Host "=== release-gate: portao final antes do push ==="
Write-Host ("  repo: " + $repoFull)
Write-Host ""

$fail = 0

Write-Host "-- 1/4: identidade de commit (allowlist, TASK-617) --"
$idResult = Test-CommitIdentities -RepoPath $repoFull -Allowlist $AllowedCommitIdentities
if ($idResult.Skipped) {
  Write-Host "[AVISO] repo nao e um repositorio git (.git ausente ou invalido) - pulando checagem de identidade"
} elseif (-not $idResult.Ok) {
  $fail++
  Write-Host "[FAIL] identidade de commit fora da allowlist:" -ForegroundColor Red
  foreach ($v in $idResult.Violations) { Write-Host ("  - " + $v) -ForegroundColor Red }
} else {
  Write-Host "[OK] todo commit (author e committer) bate com a allowlist"
}
Write-Host ""

Write-Host "-- 2/4: check-public-surface.ps1 --"
& powershell -ExecutionPolicy Bypass -File (Join-Path $here "check-public-surface.ps1") -Repo $repoFull
if ($LASTEXITCODE -ne 0) { $fail++; Write-Host "[FAIL] superficie publica reprovada" -ForegroundColor Red }
Write-Host ""

Write-Host "-- 3/4: manifesto vs git ls-files (TASK-618) --"
$manifestGitResult = Test-ManifestVsGitLsFiles -RepoPath $repoFull -ScriptDir $here
if ($manifestGitResult.Skipped) {
  Write-Host "[AVISO] MANIFEST.sha256 ausente ou repo nao e git - pulando comparacao manifesto vs git ls-files"
} elseif (-not $manifestGitResult.Ok) {
  $fail++
  Write-Host "[FAIL] manifesto divergente de git ls-files:" -ForegroundColor Red
  foreach ($p in $manifestGitResult.NotTrackedByGit) { Write-Host ("  - NO MANIFESTO MAS NAO RASTREADO PELO GIT: " + $p) -ForegroundColor Red }
  foreach ($p in $manifestGitResult.MissingFromManifest) { Write-Host ("  - RASTREADO PELO GIT MAS FALTANDO NO MANIFESTO: " + $p) -ForegroundColor Red }
} else {
  Write-Host "[OK] manifesto bate exatamente com git ls-files"
}
Write-Host ""

Write-Host "-- 4/4: verify-manifest.ps1 (integridade pos-aplicacao, extracao limpa via git archive HEAD, TASK-618) --"
$manifestPath = Join-Path $repoFull "MANIFEST.sha256"
if (-not (Test-Path -LiteralPath $manifestPath)) {
  Write-Host "[AVISO] MANIFEST.sha256 nao encontrado no repo - pulando verificacao de integridade (nada a comparar)"
} else {
  $prevEapArchive = $ErrorActionPreference
  $ErrorActionPreference = "SilentlyContinue"
  & git -C $repoFull rev-parse --is-inside-work-tree 1>$null 2>$null
  $isGitRepo4 = ($LASTEXITCODE -eq 0)
  $ErrorActionPreference = $prevEapArchive

  if (-not $isGitRepo4) {
    # sem git: nao ha "o que sera publicado" para extrair - mantem o comportamento antigo
    # (verifica a propria pasta), unica opcao possivel fora de um repo.
    & powershell -ExecutionPolicy Bypass -File (Join-Path $here "verify-manifest.ps1") -Dir $repoFull
    if ($LASTEXITCODE -ne 0) { $fail++; Write-Host "[FAIL] integridade do manifesto reprovada" -ForegroundColor Red }
  } else {
    # TASK-618 (retrabalho, mandato do CEO): o passo 4 rodava contra a COPIA DE TRABALHO, onde
    # arquivo nao rastreado (ex.: .opencode/.gitignore, legitimo na pasta local) fica em disco e
    # vira "EXTRA" falso - a MESMA causa raiz desta Task, agora dentro do proprio portao. Corrige
    # extraindo `git archive HEAD` (exatamente o que o usuario recebe) para pasta temporaria e
    # rodando verify-manifest.ps1 LA, nunca na working copy. O MANIFEST.sha256 da working copy
    # (recem-gerado, pode ainda nao estar commitado) sobrescreve o da extracao, para validar o
    # manifesto que sera de fato publicado.
    $archiveDir = Join-Path ([System.IO.Path]::GetTempPath()) ("release-gate-archive-" + [guid]::NewGuid().ToString("N"))
    $archiveZip = Join-Path ([System.IO.Path]::GetTempPath()) ("release-gate-archive-" + [guid]::NewGuid().ToString("N") + ".zip")
    try {
      New-Item -ItemType Directory -Path $archiveDir -Force | Out-Null
      & git -C $repoFull archive --format=zip -o $archiveZip HEAD
      if ($LASTEXITCODE -ne 0) {
        $fail++
        Write-Host "[FAIL] git archive HEAD falhou - nao foi possivel montar a extracao limpa" -ForegroundColor Red
      } else {
        Expand-Archive -LiteralPath $archiveZip -DestinationPath $archiveDir -Force
        Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $archiveDir "MANIFEST.sha256") -Force
        Write-Host ("  extracao limpa (git archive HEAD): " + $archiveDir)
        & powershell -ExecutionPolicy Bypass -File (Join-Path $here "verify-manifest.ps1") -Dir $archiveDir
        if ($LASTEXITCODE -ne 0) { $fail++; Write-Host "[FAIL] integridade do manifesto reprovada (extracao limpa)" -ForegroundColor Red }
      }
    } finally {
      Remove-Item -LiteralPath $archiveDir -Recurse -Force -ErrorAction SilentlyContinue
      Remove-Item -LiteralPath $archiveZip -Force -ErrorAction SilentlyContinue
    }
  }
}
Write-Host ""

if ($fail -gt 0) {
  Write-Host ("REPROVADO: " + $fail + " gate(s) falharam. NAO faca push.") -ForegroundColor Red
  exit 1
}

Write-Host "release-gate: PASS - push liberado" -ForegroundColor Green
exit 0
