<#
  response-guard.ps1 - Hook de Stop. O ENFORCEMENT da lei de delegacao na PORTA DE SAIDA (M1,
  "o freio").

  Por que existe: a lei "a coordenadora delega dominio, nunca executa" so tinha guarda de
  maquina na ENTRADA do pedido (scripts/delegation-guard.ps1, hook de UserPromptSubmit - so
  lembra, nunca verifica) e no FIM DA SESSAO (scripts/session-reflection.ps1, captura
  aprendizado depois que ja acabou). No momento em que a RESPOSTA sai para o operador nao havia
  verificacao nenhuma. Uma auditoria mediu: a lei foi violada em menos de 24h com o lembrete de
  entrada ja ligado. Este hook fecha esse furo, rodando a CADA turno sobre o que de fato
  aconteceu no transcript (nao sobre o que foi prometido no boot).

  Contrato do hook Stop: JSON no STDIN com session_id, transcript_path (.jsonl da sessao) e
  stop_hook_active (bool). stop_hook_active=true -> exit 0 IMEDIATO (regra dura anti-loop
  infinito: o proprio Stop hook dispara de novo quando ele bloqueia, e essa flag sinaliza que
  ja estamos num loop de bloqueio).

  2 regras deterministicas (sem LLM, sem rede) sobre o TURNO ATUAL (da ultima mensagem de role
  "user" ate o fim do transcript):
    REGRA 1 (DELEGA): Write/Edit/NotebookEdit em clients/... (fora de memory/, _proposals/,
      _backups/, scratchpad, state.json, scripts/) sem nenhuma chamada de Agent/Task no turno.
    REGRA 2 (GROUNDING): 3+ "afirmacoes de peso" (referencia a arquivo por extensao, ou padrao
      arquivo:linha) no texto da ultima mensagem do assistente, sem nenhum rotulo [MEDIDO],
      [INFERIDO] ou [LIDO] em algum ponto do texto.

  Doutrina completa (os 2 modos, a rampa, a excecao legitima, a limitacao aceita) em
  engine/governance/response-guard.md. Limiares e modo vem de engine/governance/response-guard.yaml
  (default se faltar/ilegivel: mode=aviso).

  Modo aviso: NUNCA bloqueia, so grava studio/response-guard-log.jsonl (uma linha por turno,
  violacao ou nao - e esse log que mede aderencia antes de virar bloqueio) e imprime um resumo
  de uma linha no stdout. Modo bloqueio: havendo violacao, stdout vira
  {"decision":"block","reason":"..."}; sem violacao, exit 0 silencioso. Log sempre grava, nos
  dois modos.

  BLINDAGEM: try/catch em tudo. QUALQUER erro -> exit 0 silencioso. O guard NUNCA pode derrubar
  nem travar a sessao do operador (mesmo risco que travou este item no backlog antes: "hook
  bloqueante trava instancia viva"). Teto de leitura: so as ultimas ~2000 linhas do jsonl
  (transcript pode ser grande; timeout do hook e 15s).

  Sem acentos, sem emojis. Escrita .NET UTF-8 sem BOM.
#>

function Get-TextFromContent {
  param($content)
  if ($null -eq $content) { return @() }
  if ($content -is [string]) { return @($content) }
  $out = New-Object System.Collections.Generic.List[string]
  foreach ($block in @($content)) {
    if ($block -is [string]) { $out.Add($block); continue }
    $bt = $null
    try { $bt = $block.type } catch { }
    if ($bt -eq 'text') {
      try { if ($block.text) { $out.Add([string]$block.text) } } catch { }
    }
  }
  return $out.ToArray()
}

function Get-ToolUsesFromContent {
  param($content)
  $out = New-Object System.Collections.Generic.List[object]
  if ($null -eq $content -or ($content -is [string])) { return $out.ToArray() }
  foreach ($block in @($content)) {
    $bt = $null
    try { $bt = $block.type } catch { }
    if ($bt -eq 'tool_use') { $out.Add($block) }
  }
  return $out.ToArray()
}

function Get-ResponseGuardConfig {
  param([string]$Path)
  $cfg = [ordered]@{ mode = "aviso"; min_claims = 3; min_chars_informativo = 1500 }
  try {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $cfg }
    if (-not (Test-Path -LiteralPath $Path)) { return $cfg }
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $raw = [System.IO.File]::ReadAllText($Path, $utf8)
    foreach ($line in ($raw -split "`r?`n")) {
      $l = $line
      $hashIdx = $l.IndexOf('#')
      if ($hashIdx -ge 0) { $l = $l.Substring(0, $hashIdx) }
      $l = $l.Trim()
      if ($l -eq "") { continue }
      if ($l -match '^([A-Za-z_][A-Za-z0-9_]*)\s*:\s*(.+)$') {
        $key = $matches[1]
        $val = $matches[2].Trim()
        if ($key -eq 'mode') { $cfg.mode = $val.ToLowerInvariant() }
        elseif ($key -eq 'min_claims') { $n = 0; if ([int]::TryParse($val, [ref]$n)) { $cfg.min_claims = $n } }
        elseif ($key -eq 'min_chars_informativo') { $n = 0; if ([int]::TryParse($val, [ref]$n)) { $cfg.min_chars_informativo = $n } }
      }
    }
  } catch { }
  if ($cfg.mode -ne 'aviso' -and $cfg.mode -ne 'bloqueio') { $cfg.mode = 'aviso' }
  return $cfg
}

try {
  # (0) Payload do hook: JSON no stdin. Le so quando stdin esta redirecionado (contexto de hook
  # de verdade ou teste manual via pipe); fora disso nem toca (evita travar shell interativo).
  $stdinRaw = ""
  try {
    if ([Console]::IsInputRedirected) {
      $readTask = [Console]::In.ReadToEndAsync()
      if ($readTask.Wait(5000)) { $stdinRaw = $readTask.Result } else { $stdinRaw = "" }
    }
  } catch { $stdinRaw = "" }

  if ([string]::IsNullOrWhiteSpace($stdinRaw)) { exit 0 }

  $hookObj = $null
  try { $hookObj = $stdinRaw | ConvertFrom-Json } catch { exit 0 }
  if ($null -eq $hookObj) { exit 0 }

  # REGRA DURA: stop_hook_active=true -> exit 0 IMEDIATO, antes de qualquer outra coisa.
  $stopHookActive = $false
  try { $stopHookActive = [bool]$hookObj.stop_hook_active } catch { }
  if ($stopHookActive) { exit 0 }

  $sessionId = ""
  try { $sessionId = [string]$hookObj.session_id } catch { }
  $transcriptPath = ""
  try { $transcriptPath = [string]$hookObj.transcript_path } catch { }

  if ([string]::IsNullOrWhiteSpace($transcriptPath)) { exit 0 }
  if (-not (Test-Path -LiteralPath $transcriptPath)) { exit 0 }

  $root = Split-Path -Parent $PSScriptRoot
  $cfg = Get-ResponseGuardConfig (Join-Path $root "engine\governance\response-guard.yaml")

  # (1) Le so o TETO de linhas (perf: transcript pode ser grande, timeout do hook e 15s).
  $tailCap = 2000
  $rawLines = @(Get-Content -LiteralPath $transcriptPath -Tail $tailCap -ErrorAction Stop)

  $objects = New-Object System.Collections.Generic.List[object]
  foreach ($rl in $rawLines) {
    if ([string]::IsNullOrWhiteSpace($rl)) { continue }
    $o = $null
    try { $o = $rl | ConvertFrom-Json } catch { continue }
    if ($null -eq $o) { continue }
    $objects.Add($o)
  }
  if ($objects.Count -eq 0) { exit 0 }

  # (2) Isola o TURNO ATUAL: da ULTIMA mensagem de role "user" ate o fim. Se nenhuma "user"
  # aparecer na janela lida (turno maior que o teto), usa a janela inteira (limitacao aceita).
  $turnStart = 0
  for ($i = $objects.Count - 1; $i -ge 0; $i--) {
    $t = $null
    try { $t = $objects[$i].type } catch { }
    if ($t -eq 'user') { $turnStart = $i; break }
  }
  $turnLines = @($objects[$turnStart..($objects.Count - 1)])

  # (3) Coleta todo tool_use do turno (para a REGRA 1) e o texto da ULTIMA mensagem assistant
  # (para a REGRA 2).
  $allToolUses = New-Object System.Collections.Generic.List[object]
  $lastAssistantIdx = -1
  for ($i = 0; $i -lt $turnLines.Count; $i++) {
    $entry = $turnLines[$i]
    $etype = $null
    try { $etype = $entry.type } catch { }
    if ($etype -ne 'assistant') { continue }
    $msg = $null
    try { $msg = $entry.message } catch { }
    $content = $null
    try { $content = $msg.content } catch { }
    foreach ($tu in (Get-ToolUsesFromContent $content)) { $allToolUses.Add($tu) }
    $lastAssistantIdx = $i
  }

  $lastAssistantText = ""
  if ($lastAssistantIdx -ge 0) {
    $msg = $null
    try { $msg = $turnLines[$lastAssistantIdx].message } catch { }
    $content = $null
    try { $content = $msg.content } catch { }
    $texts = Get-TextFromContent $content
    $lastAssistantText = ($texts -join "`n")
  }

  # (4) REGRA 1 - DELEGA.
  $excludeSubstrings = @('memory/', '_proposals/', '_backups/', 'scratchpad', 'state.json', 'scripts/')
  $sinalDominio = $false
  $houveDelegacao = $false
  foreach ($tu in $allToolUses) {
    $tname = $null
    try { $tname = [string]$tu.name } catch { }
    if ($tname -eq 'Agent' -or $tname -eq 'Task') { $houveDelegacao = $true }
    if ($tname -eq 'Write' -or $tname -eq 'Edit' -or $tname -eq 'NotebookEdit') {
      $fp = $null
      try { $fp = [string]$tu.input.file_path } catch { }
      if ([string]::IsNullOrWhiteSpace($fp)) {
        try { $fp = [string]$tu.input.notebook_path } catch { }
      }
      if (-not [string]::IsNullOrWhiteSpace($fp)) {
        $norm = $fp.Replace('\', '/').ToLowerInvariant()
        if ($norm -match '(^|/)clients/') {
          $excluded = $false
          foreach ($ex in $excludeSubstrings) { if ($norm.Contains($ex)) { $excluded = $true; break } }
          if (-not $excluded) { $sinalDominio = $true }
        }
      }
    }
  }
  $violacaoDelega = $sinalDominio -and (-not $houveDelegacao)
  $delegaOk = -not $violacaoDelega

  # (5) REGRA 2 - GROUNDING.
  $extMatches = [regex]::Matches($lastAssistantText, '\.(ps1|md|ya?ml|json|html|js|ts|py)\b', 'IgnoreCase').Count
  $lineMatches = [regex]::Matches($lastAssistantText, '[\w\-./\\]+:\d+').Count
  $qtdAfirmacoes = $extMatches + $lineMatches
  $hasLabel = $false
  if ($lastAssistantText.Contains('[MEDIDO') -or $lastAssistantText.Contains('[INFERIDO') -or $lastAssistantText.Contains('[LIDO')) {
    $hasLabel = $true
  }
  $violacaoGrounding = ($qtdAfirmacoes -ge $cfg.min_claims) -and (-not $hasLabel)
  $groundingOk = -not $violacaoGrounding

  $charsResposta = $lastAssistantText.Length

  # (6) LOG: uma linha JSON por turno, sempre - independente do modo (e o entregavel principal
  # do M1: mede aderencia antes de virar bloqueio).
  $studioDir = Join-Path $root "studio"
  New-Item -ItemType Directory -Force -Path $studioDir -ErrorAction SilentlyContinue | Out-Null
  $logFile = Join-Path $studioDir "response-guard-log.jsonl"
  $logEntry = [ordered]@{
    timestamp        = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    session_id       = $sessionId
    modo             = $cfg.mode
    delega_ok        = $delegaOk
    grounding_ok     = $groundingOk
    sinal_dominio    = $sinalDominio
    houve_delegacao  = $houveDelegacao
    qtd_afirmacoes   = $qtdAfirmacoes
    chars_resposta   = $charsResposta
  }
  $logLine = ($logEntry | ConvertTo-Json -Compress)
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::AppendAllText($logFile, $logLine + "`n", $utf8NoBom)

  # (7) Saida conforme o modo.
  $anyViolation = (-not $delegaOk) -or (-not $groundingOk)

  if ($cfg.mode -eq 'bloqueio') {
    if ($anyViolation) {
      $reasons = New-Object System.Collections.Generic.List[string]
      if (-not $delegaOk) {
        $reasons.Add("Turno escreveu/editou arquivo em clients/ sem chamar Agent/Task (falta delegacao) - delegue ao especialista mais capaz, ou registre ordem explicita do Operator na Task.")
      }
      if (-not $groundingOk) {
        $reasons.Add("Resposta tem " + $qtdAfirmacoes + " referencia(s) a arquivo sem rotulo [MEDIDO]/[INFERIDO]/[LIDO] - rotule a fonte de cada afirmacao de peso antes de fechar.")
      }
      $blockObj = [ordered]@{ decision = "block"; reason = ($reasons -join " ") }
      Write-Output ($blockObj | ConvertTo-Json -Compress)
      exit 0
    }
    exit 0
  }

  # aviso (default): nunca bloqueia, so resume em uma linha no stdout.
  $informativo = ($charsResposta -gt $cfg.min_chars_informativo) -and (-not $houveDelegacao)
  Write-Host ("[RESPONSE-GUARD][aviso] delega_ok=" + $delegaOk + " grounding_ok=" + $groundingOk +
    " sinal_dominio=" + $sinalDominio + " houve_delegacao=" + $houveDelegacao +
    " qtd_afirmacoes=" + $qtdAfirmacoes + " chars_resposta=" + $charsResposta +
    " informativo_sem_delegacao=" + $informativo)
  exit 0
} catch {
  exit 0
}
