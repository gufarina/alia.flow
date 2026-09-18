<#
  budget-gate.ps1 - Hook de PreToolUse. Teto de chamadas de ferramenta por especialista
  (sub-agente), como MAQUINA, nao como frase de brief (TASK-569, L64).

  MEDIDO (30 dias, transcricoes de sub-agente): mediana 32, media 49 turnos por especialista;
  um caso isolado passou de 198 mil tokens de transcript sem nenhuma medida. 62% do volume de
  chamada de ferramenta do studio sai de dentro de especialista, nao da sessao principal.

  ESCOPO: so age quando o payload do hook tem `transcript_path` contendo "/subagents/" (apos
  normalizar barra invertida) - a SESSAO PRINCIPAL nunca e limitada, so o especialista. Sem
  esse campo (ou fora do padrao), retorno vazio - "allow" e o default quando o hook nao imprime
  nada, identico ao contrato de graph-usage-sensor.ps1 / read-shunt-guard.ps1.

  CONTAGEM: le o transcript inteiro (JSONL) e conta ocorrencias de '"type":"tool_use"' via
  Select-String -AllMatches (soma de $_.Matches.Count por linha). MEDIDO (WARDEN, TASK-569):
  fixture de ~2,3 MB / 4.500 ocorrencias -> 121ms na chamada de Invoke-BudgetGate (bem abaixo
  do timeout de 10s do hook).

  TETO: $env:ALIA_SUBAGENT_MAX_CALLS (default 40 - acima da mediana 32 e abaixo da media 49
  medidas, folga deliberada pra nao travar o caso comum). Acima do teto -> deny com o texto
  fixo abaixo (acentos integros, UTF-8 sem BOM, igual ao padrao do read-shunt-guard.ps1).

  INTERRUPTOR DE EMERGENCIA: env ALIA_BUDGET_GATE_OFF=1 (ou "true") OU arquivo
  .claude/budget-gate.off (qualquer conteudo) desligam SO o bloqueio.

  LEDGER: studio/budget-log.jsonl sob $Root (ou -LedgerPath) - {ts, session, transcript, tool,
  n, teto, decision}. Grava em toda avaliacao de sub-agente (allow e deny), pra medir adocao.

  BLINDAGEM: tudo em try/catch. Qualquer erro -> retorno vazio / fail-open. Guarda quebrado
  nunca trava o especialista.

  PARAMETROS DE TESTE (WARDEN): -Root, -LedgerPath sao overrides SO para fixture de smoke test
  (mesmo padrao dos outros guards). O hook de producao nunca passa esses params.
#>
param(
  [string]$Root = "",
  [string]$LedgerPath = "",
  [string]$RawInput = $null
)

function Write-BudgetLedgerLine {
  param([string]$LedgerFile, $Entry)
  try {
    $dir = Split-Path -Parent $LedgerFile
    if (-not [string]::IsNullOrWhiteSpace($dir)) { New-Item -ItemType Directory -Force -Path $dir -ErrorAction SilentlyContinue | Out-Null }
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::AppendAllText($LedgerFile, (($Entry | ConvertTo-Json -Compress) + "`n"), $utf8)
  } catch { }
}

function Get-BudgetToolUseCount {
  param([string]$Path)
  $n = 0
  try {
    $matches = Select-String -LiteralPath $Path -Pattern '"type":"tool_use"' -AllMatches -ErrorAction Stop
    foreach ($m in $matches) { $n += $m.Matches.Count }
  } catch {
    return -1
  }
  return $n
}

function New-BudgetDenyJson {
  param([int]$N, [int]$Teto)
  $reason = ('[ORÇAMENTO] Este especialista já fez {0} chamadas (teto {1}). Entregue agora com o que tem, rotulando o que ficou por conferir como [FALTA]; sem nova chamada de ferramenta. Teto: ALIA_SUBAGENT_MAX_CALLS. Desligar: ALIA_BUDGET_GATE_OFF=1 ou .claude/budget-gate.off.' -f $N, $Teto)
  $out = [ordered]@{
    hookSpecificOutput = [ordered]@{
      hookEventName            = "PreToolUse"
      permissionDecision       = "deny"
      permissionDecisionReason = $reason
    }
  }
  return ($out | ConvertTo-Json -Depth 5 -Compress)
}

function Invoke-BudgetGate {
  param(
    [string]$RawInput = $null,
    [string]$Root = "",
    [string]$LedgerPath = ""
  )

  $rootResolved = if (-not [string]::IsNullOrWhiteSpace($Root)) { $Root } else { Split-Path -Parent $PSScriptRoot }
  $ledgerFile = if (-not [string]::IsNullOrWhiteSpace($LedgerPath)) { $LedgerPath } else { Join-Path (Join-Path $rootResolved "studio") "budget-log.jsonl" }
  $sessionId = ""

  try {
    if ([string]::IsNullOrWhiteSpace($RawInput)) { return "" }
    $h = $null
    try { $h = $RawInput | ConvertFrom-Json } catch { return "" }
    if ($null -eq $h) { return "" }

    $tool = ""
    try { $tool = [string]$h.tool_name } catch { }
    try { $sessionId = [string]$h.session_id } catch { }

    $transcript = ""
    try { $transcript = [string]$h.transcript_path } catch { }
    if ([string]::IsNullOrWhiteSpace($transcript)) { return "" }
    $normTranscript = $transcript.Replace('\', '/')
    if ($normTranscript -notmatch '/subagents/') { return "" }

    $offEnv = $env:ALIA_BUDGET_GATE_OFF
    $budgetOff = ($offEnv -eq "1") -or ($offEnv -eq "true")
    $offFile = Join-Path $rootResolved ".claude\budget-gate.off"
    if (Test-Path -LiteralPath $offFile) { $budgetOff = $true }
    if ($budgetOff) { return "" }

    if (-not (Test-Path -LiteralPath $transcript -PathType Leaf)) { return "" }

    $teto = 40
    $tetoRaw = $env:ALIA_SUBAGENT_MAX_CALLS
    if (-not [string]::IsNullOrWhiteSpace($tetoRaw)) {
      $parsedTeto = 0
      if ([int]::TryParse($tetoRaw, [ref]$parsedTeto)) { $teto = $parsedTeto }
    }

    $n = Get-BudgetToolUseCount -Path $transcript
    if ($n -lt 0) { return "" }

    $decision = if ($n -gt $teto) { "deny" } else { "allow" }
    Write-BudgetLedgerLine -LedgerFile $ledgerFile -Entry ([ordered]@{ ts = (Get-Date).ToUniversalTime().ToString("o"); session = $sessionId; transcript = $transcript; tool = $tool; n = $n; teto = $teto; decision = $decision })

    if ($decision -eq "deny") { return New-BudgetDenyJson -N $n -Teto $teto }
    return ""
  } catch {
    try {
      Write-BudgetLedgerLine -LedgerFile $ledgerFile -Entry ([ordered]@{ ts = (Get-Date).ToUniversalTime().ToString("o"); session = $sessionId; erro = $_.Exception.Message; fase = "Invoke-BudgetGate" })
    } catch { }
    return ""
  }
}

if ($MyInvocation.InvocationName -ne '.') {
  try {
    try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }
    $rawIn = $RawInput
    if ([string]::IsNullOrWhiteSpace($rawIn) -and [Console]::IsInputRedirected) {
      try {
        $readTask = [Console]::In.ReadToEndAsync()
        if ($readTask.Wait(2000)) { $rawIn = $readTask.Result }
      } catch { }
    }
    $result = Invoke-BudgetGate -RawInput $rawIn -Root $Root -LedgerPath $LedgerPath
    if (-not [string]::IsNullOrWhiteSpace($result)) { Write-Output $result }
  } catch { }
  exit 0
}
