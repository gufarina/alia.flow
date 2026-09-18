<#
  leitor-gate.ps1 - Hook de PreToolUse. Cerca do leitor barato (TASK-571, L66, decisao do CEO):
  especialista (sub-agente) pode acionar SO o leitor em massa (Agent/Task com
  subagent_type=Explore, model=haiku, prompt no molde de skills/leitura-em-massa/SKILL.md),
  nunca outra delegacao - isso seria fan-out sem teto.

  ESCOPO: so age quando tool_name é Task ou Agent E transcript_path contem "/subagents/" (apos
  normalizar barra invertida). Sessao PRINCIPAL (Alia) segue livre - retorno vazio.

  LIBERA quando tool_input satisfaz TODAS:
    - subagent_type == "Explore"
    - model == "haiku"
    - prompt contem "Contrato de saída" (ou "saida") E "Máximo 30 linhas" (ou "máx 30 linhas"/
      "max 30 linhas") E "offset/limit"
    - prompt com no maximo 2.500 caracteres
    - run_in_background ausente ou false

  DEFESA EM PROFUNDIDADE: transcript_path com DOIS "/subagents/" (2o nivel) -> deny sempre,
  mesmo que o resto bata. [LIDO] fato do host: o subagente Explore nao tem a ferramenta Agent/
  Task na propria lista de tools, entao nao ha 2o nivel na pratica - este deny e cinto extra.

  TETO: $env:ALIA_LEITOR_MAX_POR_ESPECIALISTA (default 3) leituras (tool_use Task/Agent) por
  transcript. Conta ocorrencias de tool_use com name Task ou Agent no transcript inteiro.

  LEDGER: studio/leitor-log.jsonl sob $Root (ou -LedgerPath) - {ts, session, transcript,
  decision, n, motivo}.

  BLINDAGEM: tudo em try/catch. Qualquer erro -> retorno vazio / fail-open.

  PARAMETROS DE TESTE (WARDEN): -Root, -LedgerPath sao overrides SO para fixture de smoke test.
#>
param(
  [string]$Root = "",
  [string]$LedgerPath = "",
  [string]$RawInput = $null
)

function Write-LeitorLedgerLine {
  param([string]$LedgerFile, $Entry)
  try {
    $dir = Split-Path -Parent $LedgerFile
    if (-not [string]::IsNullOrWhiteSpace($dir)) { New-Item -ItemType Directory -Force -Path $dir -ErrorAction SilentlyContinue | Out-Null }
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::AppendAllText($LedgerFile, (($Entry | ConvertTo-Json -Compress) + "`n"), $utf8)
  } catch { }
}

function Get-LeitorToolUseCount {
  param([string]$Path)
  $n = 0
  try {
    $matches = Select-String -LiteralPath $Path -Pattern '"type":"tool_use"[^\n]*"name":"(Task|Agent)"' -AllMatches -ErrorAction Stop
    foreach ($m in $matches) { $n += $m.Matches.Count }
  } catch {
    return -1
  }
  return $n
}

function New-LeitorDenyJson {
  param([string]$Reason)
  $out = [ordered]@{
    hookSpecificOutput = [ordered]@{
      hookEventName            = "PreToolUse"
      permissionDecision       = "deny"
      permissionDecisionReason = $Reason
    }
  }
  return ($out | ConvertTo-Json -Depth 5 -Compress)
}

function Get-LeitorAsciiFold {
  # remove acento (diacritico) pra tornar o casamento robusto a encoding do host que le o
  # .ps1 (Windows PowerShell 5.1 sem BOM as vezes le UTF-8 multibyte errado; o payload JSON
  # em runtime chega correto, mas o CASAMENTO nao pode depender do byte exato do acento).
  param([string]$Text)
  if ([string]::IsNullOrEmpty($Text)) { return "" }
  $norm = $Text.Normalize([System.Text.NormalizationForm]::FormD)
  $sb = New-Object System.Text.StringBuilder
  foreach ($ch in $norm.ToCharArray()) {
    $cat = [System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch)
    if ($cat -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($ch) }
  }
  return $sb.ToString()
}

function Test-LeitorPromptMolde {
  param([string]$Prompt)
  if ([string]::IsNullOrWhiteSpace($Prompt)) { return $false }
  if ($Prompt.Length -gt 2500) { return $false }
  # curinga na posicao do acento: tolera tanto o caractere correto quanto o byte trocado que
  # `powershell.exe` (Windows PowerShell 5.1) as vezes produz ao ler .ps1 sem BOM - o CASAMENTO
  # nao pode depender do byte exato do acento, so da presenca da frase.
  # `.{1,2}` porque powershell.exe as vezes le o multibyte do acento como DOIS chars trocados
  # (medido: "saída" com 108 chars corretos vira 110 quando o .ps1 e lido via -File sem BOM).
  $folded = $Prompt
  $temContrato = ($folded -match 'Contrato de sa.{1,2}da')
  $temMax30 = ($folded -match 'M.{1,2}ximo 30 linhas') -or ($folded -match 'm.{1,2}x\.? 30 linhas')
  $temOffsetLimit = ($folded -match 'offset/limit')
  return ($temContrato -and $temMax30 -and $temOffsetLimit)
}

function Invoke-LeitorGate {
  param(
    [string]$RawInput = $null,
    [string]$Root = "",
    [string]$LedgerPath = ""
  )

  $rootResolved = if (-not [string]::IsNullOrWhiteSpace($Root)) { $Root } else { Split-Path -Parent $PSScriptRoot }
  $ledgerFile = if (-not [string]::IsNullOrWhiteSpace($LedgerPath)) { $LedgerPath } else { Join-Path (Join-Path $rootResolved "studio") "leitor-log.jsonl" }
  $sessionId = ""
  $textoMoldeDeny = '[LEITOR-CERCA] Dentro de um especialista, a única delegação permitida é o leitor em massa: Agent(subagent_type="Explore", model="haiku", prompt=<molde de skills/leitura-em-massa/SKILL.md>). Outra delegação é fan-out sem teto e fica proibida; entregue você mesmo ou devolva ao Gateway.'

  try {
    if ([string]::IsNullOrWhiteSpace($RawInput)) { return "" }
    $h = $null
    try { $h = $RawInput | ConvertFrom-Json } catch { return "" }
    if ($null -eq $h) { return "" }

    $tool = ""
    try { $tool = [string]$h.tool_name } catch { }
    if ($tool -ne "Task" -and $tool -ne "Agent") { return "" }

    try { $sessionId = [string]$h.session_id } catch { }

    $transcript = ""
    try { $transcript = [string]$h.transcript_path } catch { }
    if ([string]::IsNullOrWhiteSpace($transcript)) { return "" }
    $normTranscript = $transcript.Replace('\', '/')
    if ($normTranscript -notmatch '/subagents/') { return "" }

    # defesa em profundidade: 2o nivel de sub-agente, nunca libera. Lookahead (?=...) pra contar
    # ocorrencias SOBREPOSTAS (".../subagents/subagents/..." tem 2 ocorrencias que compartilham
    # a barra do meio; sem lookahead o regex consome a barra e so acha 1).
    $subagentHits = ([regex]::Matches($normTranscript, '(?=/subagents/)')).Count
    if ($subagentHits -ge 2) {
      Write-LeitorLedgerLine -LedgerFile $ledgerFile -Entry ([ordered]@{ ts = (Get-Date).ToUniversalTime().ToString("o"); session = $sessionId; transcript = $transcript; decision = "deny"; n = -1; motivo = "segundo-nivel-subagente" })
      return New-LeitorDenyJson -Reason $textoMoldeDeny
    }

    $tin = $null
    try { $tin = $h.tool_input } catch { }
    $subagentType = ""
    $model = ""
    $prompt = ""
    $runBg = $false
    try { $subagentType = [string]$tin.subagent_type } catch { }
    try { $model = [string]$tin.model } catch { }
    try { $prompt = [string]$tin.prompt } catch { }
    try { if ($null -ne $tin.run_in_background) { $runBg = [bool]$tin.run_in_background } } catch { }

    $bateMolde = ($subagentType -eq "Explore") -and ($model -eq "haiku") -and (-not $runBg) -and (Test-LeitorPromptMolde -Prompt $prompt)

    if (-not $bateMolde) {
      Write-LeitorLedgerLine -LedgerFile $ledgerFile -Entry ([ordered]@{ ts = (Get-Date).ToUniversalTime().ToString("o"); session = $sessionId; transcript = $transcript; decision = "deny"; n = -1; motivo = "fora-do-molde" })
      return New-LeitorDenyJson -Reason $textoMoldeDeny
    }

    $teto = 3
    $tetoRaw = $env:ALIA_LEITOR_MAX_POR_ESPECIALISTA
    if (-not [string]::IsNullOrWhiteSpace($tetoRaw)) {
      $parsedTeto = 0
      if ([int]::TryParse($tetoRaw, [ref]$parsedTeto)) { $teto = $parsedTeto }
    }

    if (-not (Test-Path -LiteralPath $transcript -PathType Leaf)) {
      Write-LeitorLedgerLine -LedgerFile $ledgerFile -Entry ([ordered]@{ ts = (Get-Date).ToUniversalTime().ToString("o"); session = $sessionId; transcript = $transcript; decision = "allow"; n = 0; motivo = "sem-transcript-ainda" })
      return ""
    }

    $n = Get-LeitorToolUseCount -Path $transcript
    if ($n -lt 0) { return "" }

    if ($n -ge $teto) {
      Write-LeitorLedgerLine -LedgerFile $ledgerFile -Entry ([ordered]@{ ts = (Get-Date).ToUniversalTime().ToString("o"); session = $sessionId; transcript = $transcript; decision = "deny"; n = $n; motivo = "teto-excedido" })
      $reasonTeto = ('[LEITOR-CERCA] Este especialista já usou {0} leitores (teto {1}). Fatie com offset/limit ou entregue com o que tem.' -f $n, $teto)
      return New-LeitorDenyJson -Reason $reasonTeto
    }

    Write-LeitorLedgerLine -LedgerFile $ledgerFile -Entry ([ordered]@{ ts = (Get-Date).ToUniversalTime().ToString("o"); session = $sessionId; transcript = $transcript; decision = "allow"; n = $n; motivo = "no-molde" })
    return ""
  } catch {
    try {
      Write-LeitorLedgerLine -LedgerFile $ledgerFile -Entry ([ordered]@{ ts = (Get-Date).ToUniversalTime().ToString("o"); session = $sessionId; erro = $_.Exception.Message; fase = "Invoke-LeitorGate" })
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
    $result = Invoke-LeitorGate -RawInput $rawIn -Root $Root -LedgerPath $LedgerPath
    if (-not [string]::IsNullOrWhiteSpace($result)) { Write-Output $result }
  } catch { }
  exit 0
}
