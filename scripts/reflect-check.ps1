<#
  reflect-check.ps1 - Hook de SessionStart. O GATILHO do loop de RSI (antes era PLACEHOLDER).

  Detecta digests de sessao pendentes de julgamento (reflection-inbox-*.md) em
  memory/_proposals/ e injeta um lembrete no contexto da Alia, pra ela fechar o loop no
  inicio da sessao: julgar (skills/session-reflection) -> cartao S/N -> promover
  (scripts/promote-memory.ps1). O passo de julgamento exige um agente vivo, por isso roda no
  SessionStart (boot), nao no SessionEnd (que so roda o digest deterministico).

  O stdout e adicionado ao contexto pelo Claude Code. NUNCA bloqueia o boot: exit 0 sempre,
  envolto em try/catch. Sem acentos, sem emojis.
#>
param([string]$ProposalsDir = "")
try {
  $root = Split-Path -Parent $PSScriptRoot
  if ([string]::IsNullOrWhiteSpace($ProposalsDir)) { $ProposalsDir = Join-Path $root "memory\_proposals" }
  if (-not (Test-Path -LiteralPath $ProposalsDir)) { exit 0 }

  $pending = @(Get-ChildItem -LiteralPath $ProposalsDir -Filter "reflection-inbox-*.md" -File -ErrorAction SilentlyContinue)
  if ($pending.Count -eq 0) { exit 0 }

  # Idade do digest mais ANTIGO parado (em dias). >2 dias = o loop apodreceu: vira BANDEIRA VERMELHA.
  $oldest = ($pending | Sort-Object LastWriteTime | Select-Object -First 1)
  $ageDays = [math]::Floor(((Get-Date) - $oldest.LastWriteTime).TotalDays)
  $STALE = 2

  if ($ageDays -gt $STALE) {
    Write-Host ("[ALIA - bastidor - URGENTE] " + $pending.Count + " aprendizado(s) de sessoes anteriores PARADO(S) ha ate " + $ageDays + " dias em memory/_proposals/ (a prova da instancia FALHA com aprendizado parado > 3 dias). Nao adie nesta sessao.")
  } else {
    Write-Host ("[ALIA - bastidor] " + $pending.Count + " aprendizado(s) de sessoes anteriores aguardando processamento em memory/_proposals/:")
  }
  foreach ($f in $pending) { Write-Host ("  - " + $f.Name) }
  Write-Host ""
  Write-Host "PROTOCOLO DE BASTIDOR (persona.md, regra dura de linguagem - isto NUNCA vira assunto com o operador):"
  Write-Host "1. Atenda PRIMEIRO o que o operador pedir. A primeira fala da sessao e sobre o pedido DELE, nunca sobre manutencao interna. Nao anuncie que vai 'fechar loop' nem cite RSI/digest/inbox/julgamento - vocabulario proibido na conversa."
  Write-Host "2. DEPOIS de encaminhar o pedido (ou num momento morto do trabalho), processe em silencio: julgamento da skill session-reflection (heuristicas Hermes) + CONFERE independente + scripts/promote-memory.ps1 -ArchiveInbox. Sem narrar."
  Write-Host "3. So mencione isso ao operador se o CONFERE escalar algo (ESCALA_HUMANO). Ai e UMA pergunta simples, em linguagem de negocio, no fim de uma resposta: 'Da ultima vez anotei que [licao, em palavras do dia a dia]. Guardo isso pra valer daqui pra frente?' Nada de cartao/digest/promocao/aprovacao S/N tecnica."
  Write-Host "4. Se nada escalar, o operador nao fica sabendo - a unica evidencia e a memoria melhor. Processar continua OBRIGATORIO nesta sessao; invisivel nao e opcional."
  exit 0
} catch {
  exit 0
}
