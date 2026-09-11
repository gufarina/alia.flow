<#
  promote-memory.ps1 - Promove notas de memoria de _proposals/ (staging) para memory/
  (canonico) ou roteia para outro destino. Passo mecanico do CONFERE: o agente propoe
  (skills/session-reflection), o CONFERE classifica, este script materializa o destino.
  Fecha o elo que faltava no loop de RSI (Orient: o digest vira memoria de verdade).

  Spec: skills/session-reflection/SKILL.md. Governanca: engine/governance/provenance.md
  (so agent-authored; staging e temporario; a memoria canonica nunca e deletada por automacao).

  DECISAO DO CEO (10/09/2026): "a alia deve aprender sozinha, sem eu ter que aprovar nada".
  O desfecho ESCALA_HUMANO (cartao S/N ao operador) MORREU para memoria. Nao existe mais saida
  "fica em staging esperando o operador" - toda prop-*.md termina a passada com um dos QUATRO
  destinos abaixo, todos automaticos. O CONFERE (guardrail independente, quem propoe nao aprova)
  continua vivo, mas como CLASSIFICADOR, nunca como fila.

  Contrato de classificacao (frontmatter da prop-*.md, escrito pelo CONFERE):
   - approved_by: <instancia != autor>            -> exige-se para promover (SEMPRE).
   - confidence: low  (+ valid_until: YYYY-MM-DD)  -> promove em PROBATION (nao precisa dos 4
     crivos completos; duvida no crivo 1/2/4). Quem retira e o TEMPO (memory-curator.ps1
     -Validade), nunca o humano.
   - discard: true  (+ discard_reason: <motivo>)   -> AUTO_DISCARD. Nao promove; move o
     prop-*.md para memory/_proposals/_archive/ com status: discarded. Nunca deleta.
   - route_to_rsi: true (+ route_reason opcional)  -> ROUTE_TO_RSI. Crivo 3 (Aditiva/SEGURA)
     reprovado (toca nucleo/engine/constituicao/Gate, ou envolve gasto/credencial/acao
     destrutiva). Nao vira memoria; vira candidato em engine/rsi/_candidates/. Isso NAO e
     aprovacao de memoria, e roteamento para o cano de mudanca de MOTOR (L04 / -AllowCore).

  Os QUATRO destinos, todos automaticos:
   - safe_auto: approved_by presente, sem discard/route/probation -> promove, status: active.
   - auto_promote_probation: approved_by presente + confidence: low -> promove, status: active,
     confidence: low, valid_until preservado (30 dias, retirado por memory-curator.ps1).
   - auto_discard: discard: true -> arquiva com discard_reason, nunca promove, nunca deleta.
   - route_to_rsi: route_to_rsi: true -> vira candidato em engine/rsi/_candidates/, nunca memoria.
   - SEM classificacao nenhuma (sem approved_by, sem discard, sem route_to_rsi): e ERRO do ciclo,
     nao espera - tratado como auto_discard com discard_reason: nao_classificada.

  O que faz (passo mecanico, custo zero de token de modelo):
   - pega os prop-*.md em -ProposalsDir (default memory/_proposals).
   - valida o frontmatter (campo name); pula e avisa se faltar.
   - classifica pelo contrato acima e resolve um dos 4 destinos - NUNCA fica esperando humano.
   - escreve cada promovido em -MemoryDir/<name>.md (canonico), trocando status: proposed -> active
     e carimbando promoted_on.
   - remove o prop-*.md do staging (o CONTEUDO fica preservado em memory/ ou nos destinos acima,
     nao e deletado).
   - -ArchiveInbox: move os digests brutos ja julgados (reflection-inbox-*.md) para
     _proposals/_archive/, para o gatilho do SessionStart nao re-disparar (move, nunca deleta).
   - NUNCA toca _retired/, engine/, nucleo (exceto engine/rsi/_candidates/, destino explicito do
     route_to_rsi). NUNCA escreve fora de -MemoryDir / _archive / _candidates.
   - -DryRun: so lista o que faria, nao move nada.

  Escrita .NET UTF-8 sem BOM. exit 0.
#>
param(
  [string]$ProposalsDir = "",
  [string]$MemoryDir = "",
  [switch]$ArchiveInbox,
  # -AllowUnverified: ESCAPE explicito para casos sem revisor independente disponivel (rompe o
  # CONFERE de proposito; so com sinal humano no terminal). Default OFF: a promocao exige approved_by.
  [switch]$AllowUnverified,
  [string]$CandidatesDir = "",
  [switch]$DryRun
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ProposalsDir))  { $ProposalsDir  = Join-Path $root "memory\_proposals" }
if ([string]::IsNullOrWhiteSpace($MemoryDir))     { $MemoryDir     = Join-Path $root "memory" }
if ([string]::IsNullOrWhiteSpace($CandidatesDir)) { $CandidatesDir = Join-Path $root "engine\rsi\_candidates" }

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

# Anti-apodrecimento: .md em staging fora dos padroes conhecidos e INVISIVEL para a promocao e
# ficaria parado pra sempre sem aviso. O loop SINALIZA, nao apodrece.
#
# CONSERTO (TASK-159, MEDIDO contra engine/rsi/rsi.md antes de mexer): friction-*.md
# (session-reflection.ps1, PECA 2) e patterns-*.md (rsi-patterns.ps1 -Write, PECA 3) NAO sao
# propostas de memoria e NUNCA deveriam ser promovidas por este script - sao insumo de OUTRO
# pipeline (RSI de engine, nao promocao de memoria): friction-*.md alimenta rsi-patterns.ps1
# (PECA 3), que detecta padrao (3+ sessoes) e pode escrever patterns-*.md; um humano DECIDE se
# um patterns-*.md vira candidato em engine/rsi/_candidates/<slug>/, aplicado so pelo portao
# rsi-apply.ps1 (PECA 1) - "a promocao de um item de atrito recorrente em melhoria de verdade
# passa pela PECA 3 e pela PECA 1 - nunca automatico" (rsi.md:167-168). O gerador (PECA 2/PECA 3)
# esta CERTO no nome; era este script que tratava as duas classes conhecidas como lixo
# desconhecido. Antes do conserto: 100% dos friction-*.md/patterns-*.md gerados pelo motor
# nasciam [ORFAO] (aviso que nao aponta pro fluxo certo, e morre so impresso - nada os arquiva).
# Depois: reconhecidas por nome, roteadas com a instrucao certa; [ORFAO] fica so pra nome
# desconhecido de verdade (lixo ou erro de digitacao).
$allStagingMd = @(Get-ChildItem -LiteralPath $ProposalsDir -Filter "*.md" -File -ErrorAction SilentlyContinue)
$rsiFriction = @($allStagingMd | Where-Object { $_.Name -like "friction-*" })
$rsiPatterns = @($allStagingMd | Where-Object { $_.Name -like "patterns-*" })
$orphans = @($allStagingMd | Where-Object {
  $_.Name -notlike "prop-*" -and $_.Name -notlike "reflection-inbox-*" -and
  $_.Name -notlike "friction-*" -and $_.Name -notlike "patterns-*"
})
foreach ($fr in $rsiFriction) {
  Write-Host ("[STAGING] " + $fr.Name + " - insumo da PECA 2 (session-reflection.ps1), NAO e proposta de memoria: nunca e promovido por este script. Destino certo: scripts/rsi-patterns.ps1 (PECA 3) le este arquivo pra detectar padrao recorrente (3+ sessoes) - rode-o pra ver se ja virou candidato. Doutrina: engine/rsi/rsi.md.")
}
foreach ($pt in $rsiPatterns) {
  Write-Host ("[STAGING] " + $pt.Name + " - relatorio da PECA 3 (rsi-patterns.ps1), NAO e proposta de memoria: nunca e promovido por este script. Destino certo: revisao HUMANA decide se vira candidato em engine/rsi/_candidates/<slug>/, aplicado so pelo portao PECA 1 (scripts/rsi-apply.ps1). Doutrina: engine/rsi/rsi.md.")
}
foreach ($orf in $orphans) {
  Write-Host ("[ORFAO] " + $orf.Name + " - nao segue nenhum padrao conhecido (prop-*.md, reflection-inbox-*.md, friction-*.md, patterns-*.md) e NUNCA sera promovido. Renomeie para prop-<name>.md para entrar no fluxo de memoria, ou confira se pertence a outro mecanismo do motor.")
}

if (-not $DryRun -and $props.Count -gt 0) { New-Item -ItemType Directory -Force -Path $MemoryDir | Out-Null }

$promoted   = 0
$probation  = 0
$discarded  = 0
$routedRsi  = 0
$skipped    = 0
$archiveDirEarly = Join-Path $ProposalsDir "_archive"

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

  # DESFECHO ESCALA_HUMANO MORTO (decisao do CEO, 10/09/2026): nenhuma prop-*.md termina a
  # passada esperando humano. O CONFERE classifica com estes campos de frontmatter; este script
  # so resolve o destino - sempre um dos 4, nunca fila.
  $a         = [regex]::Match($content, '(?im)^\s*approved_by:\s*(\S.*?)\s*$')
  $approvedBy = if ($a.Success) { $a.Groups[1].Value.Trim() } else { "" }
  $conf      = [regex]::Match($content, '(?im)^\s*confidence:\s*(\S.*?)\s*$')
  $confidence = if ($conf.Success) { $conf.Groups[1].Value.Trim().ToLowerInvariant() } else { "" }
  $vu        = [regex]::Match($content, '(?im)^\s*valid_until:\s*(\S.*?)\s*$')
  $validUntil = if ($vu.Success) { $vu.Groups[1].Value.Trim() } else { "" }
  $disc      = [regex]::Match($content, '(?im)^\s*discard:\s*(true|sim)\s*$')
  $discReason = [regex]::Match($content, '(?im)^\s*discard_reason:\s*(\S.*?)\s*$')
  $isDiscard = $disc.Success
  $rte       = [regex]::Match($content, '(?im)^\s*route_to_rsi:\s*(true|sim)\s*$')
  $isRoute   = $rte.Success

  # ERRO do ciclo (nenhuma classificacao) vira auto_discard com motivo explicito - nunca espera.
  $unclassified = [string]::IsNullOrWhiteSpace($approvedBy) -and -not $isDiscard -and -not $isRoute -and -not $AllowUnverified

  if ($isRoute) {
    # ROUTE_TO_RSI: crivo 3 (Aditiva/SEGURA) reprovado - toca nucleo/engine/gate, ou envolve
    # gasto/credencial/acao destrutiva. NAO vira memoria; vira candidato pro cano de mudanca de
    # MOTOR (L04 / -AllowCore em rsi-apply.ps1). Move (nunca deleta).
    $reasonMatch = [regex]::Match($content, '(?im)^\s*route_reason:\s*(\S.*?)\s*$')
    $reason = if ($reasonMatch.Success) { $reasonMatch.Groups[1].Value.Trim() } else { "aditiva_safe_reprovado" }
    if ($DryRun) {
      Write-Host ("[DRY] rotearia p/ RSI: " + $p.Name + " -> engine/rsi/_candidates/  (motivo: " + $reason + ")")
    } else {
      New-Item -ItemType Directory -Force -Path $CandidatesDir | Out-Null
      $rsiOut = $content -replace '(?m)^\s*status:\s*proposed\s*$', ("  status: rsi_candidate`r`n  routed_on: " + $today + "`r`n  route_reason: " + $reason)
      [System.IO.File]::WriteAllText((Join-Path $CandidatesDir $p.Name), $rsiOut, $utf8)
      Remove-Item -LiteralPath $p.FullName -Force
      Write-Host ("[ROUTE_TO_RSI] " + $p.Name + " -> engine/rsi/_candidates/" + $p.Name + "  (nao e memoria, motivo: " + $reason + ")")
    }
    $routedRsi++
    continue
  }

  if ($isDiscard -or $unclassified) {
    # AUTO_DISCARD: reprova clara (nao fundamentada / duplicata / nao duravel) OU proposta sem
    # classificacao (erro do ciclo, tratado como discard com motivo explicito). Nunca promove,
    # nunca deleta - arquiva em _archive/ com discard_reason.
    $reason = if ($discReason.Success) { $discReason.Groups[1].Value.Trim() } `
              elseif ($unclassified) { "nao_classificada" } else { "sem_motivo_informado" }
    if ($DryRun) {
      Write-Host ("[DRY] descartaria: " + $p.Name + " -> _archive/  (discard_reason: " + $reason + ")")
    } else {
      New-Item -ItemType Directory -Force -Path $archiveDirEarly | Out-Null
      $discOut = $content -replace '(?m)^\s*status:\s*proposed\s*$', ("  status: discarded`r`n  discarded_on: " + $today + "`r`n  discard_reason: " + $reason)
      [System.IO.File]::WriteAllText((Join-Path $archiveDirEarly $p.Name), $discOut, $utf8)
      Remove-Item -LiteralPath $p.FullName -Force
      Write-Host ("[AUTO_DISCARD] " + $p.Name + " -> _archive/" + $p.Name + "  (discard_reason: " + $reason + ")")
    }
    $discarded++
    continue
  }

  # SAFE_AUTO ou AUTO_PROMOTE_PROBATION: passou (ou entrou em duvida controlada) com approved_by
  # presente. Probation = confidence: low (duvida no crivo 1/2/4); o TEMPO retira via
  # memory-curator.ps1 -Validade, nunca o humano.
  $dest = Join-Path $MemoryDir ($name + ".md")
  $approvalStamp = if ([string]::IsNullOrWhiteSpace($approvedBy)) { "OVERRIDE:AllowUnverified" } else { $approvedBy }
  $isProbation = ($confidence -eq "low")
  $extraFields = "  status: active`r`n  promoted_on: " + $today + "`r`n  promoted_by: " + $approvalStamp
  if ($isProbation) {
    $vuFinal = if ([string]::IsNullOrWhiteSpace($validUntil)) { (Get-Date).AddDays(30).ToString("yyyy-MM-dd") } else { $validUntil }
    $extraFields += "`r`n  confidence: low`r`n  valid_until: " + $vuFinal
  }
  $out = $content -replace '(?m)^\s*status:\s*proposed\s*$', $extraFields

  if ($DryRun) {
    $label = if ($isProbation) { "PROBATION" } else { "SAFE_AUTO" }
    Write-Host ("[DRY] promoveria (" + $label + "): " + $p.Name + " -> memory/" + $name + ".md  (aprovado por: " + $approvalStamp + ")")
  } else {
    [System.IO.File]::WriteAllText($dest, $out, $utf8)
    Remove-Item -LiteralPath $p.FullName -Force
    if ($isProbation) {
      Write-Host ("[AUTO_PROMOTE_PROBATION] " + $name + ".md  (aprovado por: " + $approvalStamp + "; confidence: low; valid_until: " + $vuFinal + "; retirada e por tempo, memory-curator.ps1 -Validade)")
    } else {
      Write-Host ("[OK] promovido: " + $name + ".md  (aprovado por: " + $approvalStamp + "; staging removido; conteudo preservado em memory/)")
    }
  }
  if ($isProbation) { $probation++ } else { $promoted++ }
}

# Arquivar os digests brutos ja julgados (reflection-inbox-*.md) para o gatilho do
# SessionStart nao re-disparar. Move (nunca deleta) para _proposals/_archive/.
#
# DECISAO (TASK-159, fecho): o LATTICE pediu -ArchiveInbox varrendo os 3 padroes
# (reflection-inbox/friction/patterns). MEDIDO antes de decidir (rsi-patterns.ps1, PECA 3):
#   - reflection-inbox-*.md: seguro arquivar sempre. Ja foi julgado (cartao S/N); o script de
#     deteccao (rsi-patterns.ps1) LE explicitamente staging E _archive/ pra este padrao (linha
#     "$inboxFiles += Get-ChildItem ... $archiveDir ..."), entao arquivar nunca perde deteccao.
#     Comportamento INALTERADO.
#   - friction-*.md: rsi-patterns.ps1 TAMBEM le staging + _archive pra este padrao (mesma
#     duplicacao de fonte) - arquivar cedo NAO mata deteccao de recorrencia por si so. MAS
#     arquivar ANTES de qualquer sessao de deteccao ter rodado apaga a VISIBILIDADE humana (o
#     boot de reflect-check.ps1 so varre staging, nunca _archive) sem ninguem ter olhado -
#     exatamente o "cair no esquecimento" que este cluster existe pra evitar. Contrato adotado:
#     arquiva SO o friction-*.md que ja foi CONSUMIDO por rsi-patterns.ps1 - o sinal e o proprio
#     nome do arquivo aparecer citado como "Fonte" dentro de um patterns-*.md ja escrito (campo
#     $it.Fonte no relatorio, ver rsi-patterns.ps1 linha ~64/92/159). Sem essa citacao, o
#     friction fica em staging (visivel no boot) ate ser varrido pelo menos uma vez. "Varrido pelo
#     menos uma vez" deixou de exigir comando manual separado (rsi-patterns.ps1 -Write) desde o
#     CONSERTO logo abaixo (WARDEN, 30/08/2026) - este script agora dispara a varredura sozinho
#     quando ha friction pendente, porque o protocolo padrao de boot (reflect-check.ps1) nunca
#     chamava -Write por conta propria.
#   - patterns-*.md: NUNCA arquivado por este script. E um relatorio de DECISAO HUMANA pendente
#     (vira candidato em engine/rsi/_candidates/ ou nao) - nao e "processado" ate um humano agir;
#     arquivar sozinho esconderia uma decisao aberta. Diferente do desenho original do LATTICE
#     (que pedia varrer as 3 classes) - PONTO DE DIVERGENCIA, documentado aqui por decisao: o
#     contrato medido (nada cai no esquecimento sem humano ver) vence o desenho generico.
$archived = 0
$archivedFriction = 0
if ($ArchiveInbox) {
  $archiveDir = Join-Path $ProposalsDir "_archive"

  $inboxes = @(Get-ChildItem -LiteralPath $ProposalsDir -Filter "reflection-inbox-*.md" -File -ErrorAction SilentlyContinue)
  if ($inboxes.Count -gt 0 -and -not $DryRun) { New-Item -ItemType Directory -Force -Path $archiveDir | Out-Null }
  foreach ($ib in $inboxes) {
    if ($DryRun) {
      Write-Host ("[DRY] arquivaria inbox: " + $ib.Name + " -> _archive/")
    } else {
      Move-Item -LiteralPath $ib.FullName -Destination (Join-Path $archiveDir $ib.Name) -Force
      Write-Host ("[OK] inbox arquivado: " + $ib.Name + " -> _archive/")
    }
    $archived++
  }

  # CONSERTO (WARDEN, 30/08/2026, ordem do CEO "defeito de motor" - friction nunca saia de
  # staging): MEDIDO contra reflect-check.ps1 (PROTOCOLO DE BASTIDOR, passo 2) antes de mexer -
  # o fluxo padrao de boot so instrui "scripts/promote-memory.ps1 -ArchiveInbox"; rsi-patterns.ps1
  # -Write so aparece num aviso SEPARADO (janela de 7 dias sem varredura), nunca como parte do
  # processamento normal de cada sessao. Como o arquivamento de friction-*.md abaixo dependia de
  # citacao num patterns-*.md JA ESCRITO em disco, e -Write e o UNICO jeito de escrever esse
  # relatorio, seguir o protocolo padrao ao pe da letra nunca escrevia o relatorio - friction
  # ficava em staging para sempre, mesmo com o bucket ja acima do MinSessions. PROVADO pelo
  # negativo em sandbox: copiando os 9 friction-*.md reais e rodando so -ArchiveInbox em loop
  # (sem nenhum patterns-*.md em staging), os 9 voltavam identicos a cada rodada com
  # "[STAGING] ainda NAO consumido". Conserto: -ArchiveInbox agora chama rsi-patterns.ps1 -Write
  # ele mesmo (mesmo ProposalsDir) antes de checar citacao, sempre que ha friction pendente - o
  # passo de deteccao deixa de depender de alguem lembrar do comando separado. A visibilidade
  # humana nao muda (o relatorio continua persistido em disco, nunca auto-arquivado por este
  # script - ver aviso [STAGING] de patterns-*.md logo abaixo).
  if (-not $DryRun -and $rsiFriction.Count -gt 0) {
    $rsiPatternsScript = Join-Path $PSScriptRoot "rsi-patterns.ps1"
    if (Test-Path -LiteralPath $rsiPatternsScript) {
      try {
        Write-Host "[RSI] friction-*.md pendente - rodando rsi-patterns.ps1 -Write para fechar o loop sem comando manual separado..."
        & $rsiPatternsScript -ProposalsDir $ProposalsDir -Write | Out-Null
      } catch {
        Write-Host ("[AVISO] rsi-patterns.ps1 -Write falhou (" + $_.Exception.Message + ") - friction segue em staging ate a proxima tentativa.")
      }
    }
  }

  # friction-*.md CONSUMIDO: nome citado como "Fonte" em algum patterns-*.md (staging OU
  # _archive - o relatorio em si pode ja ter sido arquivado numa rodada anterior). Reglob (nao
  # reusa $rsiPatterns capturado no topo do script): a chamada acima pode ter acabado de escrever
  # um patterns-*.md novo no staging.
  $allPatternsTxt = ""
  $patternsEverywhere = @(Get-ChildItem -LiteralPath $ProposalsDir -Filter "patterns-*.md" -File -ErrorAction SilentlyContinue)
  if (Test-Path -LiteralPath $archiveDir) {
    $patternsEverywhere += @(Get-ChildItem -LiteralPath $archiveDir -Filter "patterns-*.md" -File -ErrorAction SilentlyContinue)
  }
  foreach ($pf in $patternsEverywhere) {
    $allPatternsTxt += "`n" + [System.IO.File]::ReadAllText($pf.FullName)
  }
  foreach ($fr in $rsiFriction) {
    if ($allPatternsTxt.Contains($fr.Name)) {
      if ($DryRun) {
        Write-Host ("[DRY] arquivaria friction CONSUMIDO por rsi-patterns.ps1 (citado num patterns-*.md): " + $fr.Name + " -> _archive/")
      } else {
        New-Item -ItemType Directory -Force -Path $archiveDir | Out-Null
        Move-Item -LiteralPath $fr.FullName -Destination (Join-Path $archiveDir $fr.Name) -Force
        Write-Host ("[OK] friction arquivado (ja consumido por rsi-patterns.ps1): " + $fr.Name + " -> _archive/")
      }
      $archivedFriction++
    } else {
      Write-Host ("[STAGING] " + $fr.Name + " - ainda NAO consumido por rsi-patterns.ps1 (nao citado em nenhum patterns-*.md ainda); fica em staging ate a proxima varredura, visivel no boot de reflect-check.ps1.")
    }
  }
  # Reglob (nao $rsiPatterns do topo): conta so o que esta em staging AGORA, incluindo o
  # patterns-<data>.md que a chamada acima pode ter acabado de escrever.
  $rsiPatternsStagingAgora = @(Get-ChildItem -LiteralPath $ProposalsDir -Filter "patterns-*.md" -File -ErrorAction SilentlyContinue)
  if ($rsiPatternsStagingAgora.Count -gt 0) {
    Write-Host ("[STAGING] " + $rsiPatternsStagingAgora.Count + " patterns-*.md NUNCA arquivado por -ArchiveInbox - e decisao humana pendente (vira candidato RSI ou nao), nao processo automatico. Divergencia do desenho LATTICE documentada no cabecalho deste bloco.")
  }
}

Write-Host ""
Write-Host ("Resumo: " + $promoted + " safe_auto | " + $probation + " auto_promote_probation | " +
  $discarded + " auto_discard | " + $routedRsi + " route_to_rsi | " + $skipped + " pulada(s) sem name | " +
  $archived + " inbox(es) arquivado(s) | " + $archivedFriction +
  " friction(s) arquivado(s) (ja consumido por rsi-patterns) | " +
  $rsiFriction.Count + " friction(s) + " + $rsiPatterns.Count + " pattern(s) roteados pro STAGING (nao promovidos, nao orfaos) | " +
  $orphans.Count + " orfao(s) de verdade | " +
  $(if ($DryRun) { "DRY-RUN (nada movido)" } else { "aplicado" }))
Write-Host ("[INVARIANTE] nenhuma prop-*.md termina a sessao esperando humano - todo item recebeu um dos 4 destinos automaticos (safe_auto / auto_promote_probation / auto_discard / route_to_rsi).")
exit 0
