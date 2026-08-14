<#
  reflect-check.ps1 - Hook de SessionStart. O GATILHO do loop de RSI (antes era PLACEHOLDER).

  Detecta digests de sessao pendentes de julgamento (reflection-inbox-*.md) em
  memory/_proposals/ e injeta um lembrete no contexto da Alia, pra ela fechar o loop no
  inicio da sessao: julgar (skills/session-reflection) -> cartao S/N -> promover
  (scripts/promote-memory.ps1). O passo de julgamento exige um agente vivo, por isso roda no
  SessionStart (boot), nao no SessionEnd (que so roda o digest deterministico).

  CONSERTO (TASK-159, fecho): agora conta os 3 tipos conhecidos de staging (digest, atrito,
  padrao) - patterns-*.md (rsi-patterns.ps1, PECA 3) e relatorio de candidato a padrao esperando
  DECISAO HUMANA (vira candidato RSI ou nao); ficar invisivel no boot e o mesmo "cair no
  esquecimento" que motivou monitorar friction-*.md. Alem disso, qualquer .md de formato
  DESCONHECIDO em staging (nao bate prop-/reflection-inbox-/friction-/patterns-) vira aviso
  [FORMATO-DESCONHECIDO] separado - sinal cedo de nome errado ou mecanismo novo sem contrato
  ainda, sem esperar o smoke ou o promote-memory.ps1 (que so roda sob demanda) pra notar.

  O stdout e adicionado ao contexto pelo Claude Code. NUNCA bloqueia o boot: exit 0 sempre,
  envolto em try/catch. Sem acentos, sem emojis.
#>
param([string]$ProposalsDir = "")
try {
  $root = Split-Path -Parent $PSScriptRoot
  if ([string]::IsNullOrWhiteSpace($ProposalsDir)) { $ProposalsDir = Join-Path $root "memory\_proposals" }
  if (-not (Test-Path -LiteralPath $ProposalsDir)) { exit 0 }

  $pending = @(Get-ChildItem -LiteralPath $ProposalsDir -Filter "reflection-inbox-*.md" -File -ErrorAction SilentlyContinue)
  # PECA 2 (RSI, canal do dono): friction-*.md conta junto - atrito parado e tao pendencia quanto
  # digest parado (os dois esperam o mesmo julgamento no inicio da sessao).
  $frictionPending = @(Get-ChildItem -LiteralPath $ProposalsDir -Filter "friction-*.md" -File -ErrorAction SilentlyContinue)
  # PECA 3 (RSI): patterns-*.md e relatorio de candidato esperando decisao humana - mesma classe
  # de pendencia, nao promovido automaticamente por design (ver promote-memory.ps1).
  $patternsPending = @(Get-ChildItem -LiteralPath $ProposalsDir -Filter "patterns-*.md" -File -ErrorAction SilentlyContinue)

  # Qualquer .md de staging fora dos 4 padroes conhecidos (prop-, reflection-inbox-, friction-,
  # patterns-) e formato desconhecido - mesmo criterio que promote-memory.ps1 usa pra [ORFAO],
  # reusado aqui pra avisar CEDO, no boot, antes de qualquer promocao rodar.
  $unknownFormat = @(Get-ChildItem -LiteralPath $ProposalsDir -Filter "*.md" -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notlike "prop-*" -and $_.Name -notlike "reflection-inbox-*" -and
                   $_.Name -notlike "friction-*" -and $_.Name -notlike "patterns-*" })

  if ($pending.Count -eq 0 -and $frictionPending.Count -eq 0 -and $patternsPending.Count -eq 0 -and $unknownFormat.Count -eq 0) { exit 0 }

  # Idade do item mais ANTIGO parado entre os 3 tipos conhecidos (em dias). >2 dias = o loop
  # apodreceu: BANDEIRA VERMELHA. Formato desconhecido fica de fora da idade (nao sabemos o
  # contrato dele pra julgar "atrasado"), mas sempre aparece listado - nunca silencioso.
  $allPending = @($pending) + @($frictionPending) + @($patternsPending)
  $totalCount = $pending.Count + $frictionPending.Count + $patternsPending.Count
  $STALE = 2

  if ($allPending.Count -gt 0) {
    $oldest = ($allPending | Sort-Object LastWriteTime | Select-Object -First 1)
    $ageDays = [math]::Floor(((Get-Date) - $oldest.LastWriteTime).TotalDays)
    if ($ageDays -gt $STALE) {
      Write-Host ("[ALIA - bastidor - URGENTE] " + $totalCount + " item(ns) de sessoes anteriores PARADO(S) ha ate " + $ageDays + " dias em memory/_proposals/ (" + $pending.Count + " digest, " + $frictionPending.Count + " atrito, " + $patternsPending.Count + " padrao) - a prova da instancia FALHA com aprendizado parado > 3 dias. Nao adie nesta sessao.")
    } else {
      Write-Host ("[ALIA - bastidor] " + $totalCount + " item(ns) de sessoes anteriores aguardando processamento em memory/_proposals/ (" + $pending.Count + " digest, " + $frictionPending.Count + " atrito, " + $patternsPending.Count + " padrao):")
    }
    foreach ($f in $pending) { Write-Host ("  - " + $f.Name) }
    foreach ($f in $frictionPending) { Write-Host ("  - " + $f.Name + " [ATRITO]") }
    foreach ($f in $patternsPending) { Write-Host ("  - " + $f.Name + " [PADRAO - decisao humana: vira candidato RSI ou nao]") }
  }

  if ($unknownFormat.Count -gt 0) {
    Write-Host ("[FORMATO-DESCONHECIDO] " + $unknownFormat.Count + " arquivo(s) em memory/_proposals/ nao batem nenhum padrao conhecido (prop-*.md, reflection-inbox-*.md, friction-*.md, patterns-*.md):")
    foreach ($f in $unknownFormat) { Write-Host ("  - " + $f.Name) }
  }

  if ($allPending.Count -gt 0 -or $unknownFormat.Count -gt 0) {
    Write-Host ""
    Write-Host "PROTOCOLO DE BASTIDOR (persona.md, regra dura de linguagem - isto NUNCA vira assunto com o operador):"
    Write-Host "1. Atenda PRIMEIRO o que o operador pedir. A primeira fala da sessao e sobre o pedido DELE, nunca sobre manutencao interna. Nao anuncie que vai 'fechar loop' nem cite RSI/digest/inbox/julgamento - vocabulario proibido na conversa."
    Write-Host "2. DEPOIS de encaminhar o pedido (ou num momento morto do trabalho), processe em silencio: julgamento da skill session-reflection (heuristicas Hermes) + CONFERE independente + scripts/promote-memory.ps1 -ArchiveInbox. Sem narrar. Item [PADRAO] exige decisao humana explicita (vira candidato em engine/rsi/_candidates/ ou nao) - nao promova sozinho. Item [FORMATO-DESCONHECIDO] exige olhar o arquivo: nome errado de um padrao conhecido, ou mecanismo novo sem contrato ainda."
    Write-Host "3. So mencione isso ao operador se o CONFERE escalar algo (ESCALA_HUMANO). Ai e UMA pergunta simples, em linguagem de negocio, no fim de uma resposta: 'Da ultima vez anotei que [licao, em palavras do dia a dia]. Guardo isso pra valer daqui pra frente?' Nada de cartao/digest/promocao/aprovacao S/N tecnica."
    Write-Host "4. Se nada escalar, o operador nao fica sabendo - a unica evidencia e a memoria melhor. Processar continua OBRIGATORIO nesta sessao; invisivel nao e opcional."
  }
  exit 0
} catch {
  exit 0
}
