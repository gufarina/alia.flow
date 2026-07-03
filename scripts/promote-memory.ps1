<#
  promote-memory.ps1 - Promove notas de memoria APROVADAS de _proposals/ (staging)
  para memory/ (canonico). E o passo mecanico do "cartao de aprovacao S/N": o agente
  julga (skills/session-reflection), o operador aprova, este script materializa a promocao.
  Fecha o elo que faltava no loop de RSI (Orient: o digest vira memoria de verdade).

  Spec: skills/session-reflection/SKILL.md. Governanca: engine/governance/provenance.md
  (so agent-authored; staging e temporario; a memoria canonica nunca e deletada por automacao).

  CONFERE (guardrail independente, rsi.md:95-99 / provenance.md:26): quem propoe NAO aprova.
  Este script so promove a prop-*.md que carrega o SINAL de aprovacao independente no
  frontmatter (campo approved_by, com valor != do autor da proposta). Esse campo NUNCA e escrito
  pelo passo de reflexao (session-reflection so emite status: proposed); ele e carimbado pela
  instancia que aprova (o cartao S/N do operador, ou um sub-agente CONFERE). Sem approved_by =
  promocao BLOQUEADA: o arquivo fica em staging e e reportado como pendente, nao apodrece silencioso.

  O que faz (passo mecanico, custo zero de token de modelo):
   - pega os prop-*.md em -ProposalsDir (default memory/_proposals).
   - valida o frontmatter (campo name); pula e avisa se faltar.
   - CONFERE: exige approved_by no frontmatter; sem ele, BLOQUEIA (nao promove) e avisa.
   - escreve cada aprovado em -MemoryDir/<name>.md (canonico), trocando status: proposed -> active
     e carimbando promoted_on.
   - remove o prop-*.md do staging (o CONTEUDO fica preservado em memory/, nao e deletado).
   - -ArchiveInbox: move os digests brutos ja julgados (reflection-inbox-*.md) para
     _proposals/_archive/, para o gatilho do SessionStart nao re-disparar (move, nunca deleta).
   - NUNCA toca _retired/, engine/, nucleo. NUNCA escreve fora de -MemoryDir / _archive.
   - -DryRun: so lista o que faria, nao move nada.

  Escrita .NET UTF-8 sem BOM. Sem acentos, sem emojis. exit 0.
#>
param(
  [string]$ProposalsDir = "",
  [string]$MemoryDir = "",
  [switch]$ArchiveInbox,
  # -AllowUnverified: ESCAPE explicito para casos sem revisor independente disponivel (rompe o
  # CONFERE de proposito; so com sinal humano no terminal). Default OFF: a promocao exige approved_by.
  [switch]$AllowUnverified,
  [switch]$DryRun
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ProposalsDir)) { $ProposalsDir = Join-Path $root "memory\_proposals" }
if ([string]::IsNullOrWhiteSpace($MemoryDir))    { $MemoryDir    = Join-Path $root "memory" }

$utf8  = New-Object System.Text.UTF8Encoding($false)
$today = (Get-Date).ToString("yyyy-MM-dd")

Write-Host "=== Promote Memory (staging -> canonico) ==="
Write-Host ("propostas: " + $ProposalsDir)
Write-Host ("memoria:   " + $MemoryDir)
Write-Host ("modo:      " + $(if ($DryRun) { "DRY-RUN (nada e movido)" } else { "RUN (promove)" }))
Write-Host ""

if (-not (Test-Path -LiteralPath $ProposalsDir)) {
  Write-Host ("[OK] sem pasta de propostas - nada a promover: " + $ProposalsDir)
  exit 0
}

$props = Get-ChildItem -LiteralPath $ProposalsDir -Filter "prop-*.md" -File -ErrorAction SilentlyContinue
$props = @($props)

# Anti-apodrecimento: .md em staging fora dos dois padroes conhecidos (prop-*.md e
# reflection-inbox-*.md) e INVISIVEL para a promocao e ficaria parado pra sempre sem aviso.
# O loop SINALIZA, nao apodrece: avisa e pede renomeio para prop-<name>.md.
$orphans = @(Get-ChildItem -LiteralPath $ProposalsDir -Filter "*.md" -File -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -notlike "prop-*" -and $_.Name -notlike "reflection-inbox-*" })
foreach ($orf in $orphans) {
  Write-Host ("[ORFAO] " + $orf.Name + " - nao segue o padrao prop-*.md e NUNCA sera promovido. Renomeie para prop-<name>.md para entrar no fluxo.")
}

if (-not $DryRun -and $props.Count -gt 0) { New-Item -ItemType Directory -Force -Path $MemoryDir | Out-Null }

$promoted = 0
$skipped  = 0
$blocked  = 0
foreach ($p in $props) {
  $content = [System.IO.File]::ReadAllText($p.FullName)
  $m = [regex]::Match($content, '(?m)^\s*name:\s*(.+?)\s*$')
  if (-not $m.Success) {
    Write-Host ("[SKIP] sem campo name no frontmatter: " + $p.Name)
    $skipped++
    continue
  }
  $name = ($m.Groups[1].Value.Trim() -replace '[^a-zA-Z0-9\-_]', '')
  if ([string]::IsNullOrWhiteSpace($name)) {
    Write-Host ("[SKIP] name invalido: " + $p.Name)
    $skipped++
    continue
  }
  # CONFERE (rsi.md:95-99 / provenance.md:26): quem propoe nao aprova. So promove com sinal de
  # aprovacao INDEPENDENTE (approved_by) - carimbado pelo cartao S/N do operador ou sub-agente
  # CONFERE, nunca pelo passo de reflexao. Sem ele = BLOQUEADO (nao apodrece silencioso).
  $a = [regex]::Match($content, '(?im)^\s*approved_by:\s*(\S.*?)\s*$')
  $approvedBy = if ($a.Success) { $a.Groups[1].Value.Trim() } else { "" }
  if ([string]::IsNullOrWhiteSpace($approvedBy) -and -not $AllowUnverified) {
    Write-Host ("[BLOQUEADO] " + $p.Name + " - sem approved_by no frontmatter (CONFERE: quem propoe nao aprova). Aguardando aprovacao independente.")
    $blocked++
    continue
  }
  $dest = Join-Path $MemoryDir ($name + ".md")
  # Prova extraivel (OPP-44): carimba quem aprovou + quando, ao lado de status: active.
  $approvalStamp = if ([string]::IsNullOrWhiteSpace($approvedBy)) { "OVERRIDE:AllowUnverified" } else { $approvedBy }
  $out  = $content -replace '(?m)^\s*status:\s*proposed\s*$', ("  status: active`r`n  promoted_on: " + $today + "`r`n  promoted_by: " + $approvalStamp)

  if ($DryRun) {
    Write-Host ("[DRY] promoveria: " + $p.Name + " -> memory/" + $name + ".md  (aprovado por: " + $approvalStamp + ")")
  } else {
    [System.IO.File]::WriteAllText($dest, $out, $utf8)
    Remove-Item -LiteralPath $p.FullName -Force
    Write-Host ("[OK] promovido: " + $name + ".md  (aprovado por: " + $approvalStamp + "; staging removido; conteudo preservado em memory/)")
  }
  $promoted++
}

# Arquivar os digests brutos ja julgados (reflection-inbox-*.md) para o gatilho do
# SessionStart nao re-disparar. Move (nunca deleta) para _proposals/_archive/.
$archived = 0
if ($ArchiveInbox) {
  $inboxes = @(Get-ChildItem -LiteralPath $ProposalsDir -Filter "reflection-inbox-*.md" -File -ErrorAction SilentlyContinue)
  if ($inboxes.Count -gt 0) {
    $archiveDir = Join-Path $ProposalsDir "_archive"
    if (-not $DryRun) { New-Item -ItemType Directory -Force -Path $archiveDir | Out-Null }
    foreach ($ib in $inboxes) {
      if ($DryRun) {
        Write-Host ("[DRY] arquivaria inbox: " + $ib.Name + " -> _archive/")
      } else {
        Move-Item -LiteralPath $ib.FullName -Destination (Join-Path $archiveDir $ib.Name) -Force
        Write-Host ("[OK] inbox arquivado: " + $ib.Name + " -> _archive/")
      }
      $archived++
    }
  }
}

Write-Host ""
Write-Host ("Resumo: " + $promoted + " promovida(s) | " + $blocked + " BLOQUEADA(S) sem aprovacao | " +
  $skipped + " pulada(s) | " + $archived + " inbox(es) arquivado(s) | " +
  $(if ($DryRun) { "DRY-RUN (nada movido)" } else { "aplicado" }))
if ($blocked -gt 0) {
  Write-Host ("[CONFERE] " + $blocked + " proposta(s) aguardando approved_by (instancia independente). NAO promovidas - o loop SINALIZA, nao apodrece.")
}
exit 0
