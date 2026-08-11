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
    REGRA 1 (DELEGA): Write/Edit/NotebookEdit em qualquer arquivo de dominio (clients/, engine/,
      docs/, skills/, scripts/, AGENTS.md, CLAUDE.md, raiz - fora de memory/, _proposals/,
      _backups/, scratchpad, state.json) sem nenhuma chamada de Agent/Task no turno.
    REGRA 2 (GROUNDING): 3+ "afirmacoes de peso" (referencia a arquivo por extensao, ou padrao
      arquivo:linha) no texto da ultima mensagem do assistente, sem nenhum rotulo [MEDIDO],
      [INFERIDO] ou [LIDO] em algum ponto do texto.

  A VALVULA (excecao legitima da REGRA 1, 09/08/2026): a lei DELEGA sempre teve uma excecao
  doutrinaria - o Operator pode mandar a coordenadora executar dominio ela mesma (ver
  engine/orchestration.md e engine/governance/client-truth.md, "excecao so por ordem explicita do
  Operator, registrada na Task"). Ate aqui essa excecao nao tinha maquina: ou o guard bloqueava
  trabalho legitimo, ou alguem desligava o modo bloqueio inteiro. A valvula fecha isso com 5
  propriedades (doutrina completa em response-guard.md):
    a) Ativada por LINGUAGEM NATURAL do Operator na propria mensagem do turno (regex sobre o texto
       digitado por humano - nunca sobre config; o Operator nao edita arquivo nenhum).
    b) Escopo de UM TURNO: so olha o texto do proprio turno (a janela ja isolada pela REGRA 1),
       nunca vaza para o proximo pedido.
    c) AUDITAVEL: so abre se, no MESMO turno, uma tool de shell (Bash ou PowerShell) chamou
       scripts/register-task.ps1 com -OperatorOrder e o registro deu certo ("[OK] tarefa
       registrada" no resultado da tool) - REUSA
       o mecanismo que ja existe (register-task.ps1 grava operator_order:true na Task), nao inventa
       um segundo conceito paralelo. O log grava valvula_aberta=true, nunca so "sem violacao".
    d) FAIL-CLOSED: linguagem detectada sem o registro auditavel (ou vice-versa) NAO abre a
       valvula - o turno segue como violacao normal se sinal_dominio existir.
    e) A valvula so desarma a REGRA 1 (DELEGA). A REGRA 2 (GROUNDING) e o resto do guard continuam
       intactos - a excecao e sobre QUEM executa, nunca sobre citar fonte sem rotular.

  Doutrina completa (os 2 modos, a rampa, a valvula, a limitacao aceita) em
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

function Get-ToolResultsFromContent {
  # Blocos type='tool_result' de uma mensagem (role user costuma carregar o resultado da tool
  # chamada pelo assistant). Devolve objetos {tool_use_id, text} - so o que a VALVULA precisa pra
  # confirmar que scripts/register-task.ps1 -OperatorOrder rodou com sucesso NO MESMO turno.
  param($content)
  $out = New-Object System.Collections.Generic.List[object]
  if ($null -eq $content -or ($content -is [string])) { return $out.ToArray() }
  foreach ($block in @($content)) {
    $bt = $null
    try { $bt = $block.type } catch { }
    if ($bt -ne 'tool_result') { continue }
    $tuid = $null
    try { $tuid = [string]$block.tool_use_id } catch { }
    $rc = $null
    try { $rc = $block.content } catch { }
    $rtext = ""
    if ($rc -is [string]) { $rtext = $rc }
    else { $rtext = ((Get-TextFromContent $rc) -join "`n") }
    $out.Add([pscustomobject]@{ tool_use_id = $tuid; text = $rtext })
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
  # -Encoding UTF8 explicito (CONSERTO achado ao provar a VALVULA pelo negativo, 09/08/2026): sem
  # isso o Get-Content do Windows PowerShell 5.1 le o .jsonl (UTF-8 sem BOM, como todo transcript
  # real) na codepage ANSI do sistema - todo acento do Operator (fala normal em portugues, LEI e so
  # de ARQUIVO) vira 2 bytes soltos em vez de 1 char, e a deteccao de linguagem natural da valvula
  # nunca casava. As 2 regras originais (extensao de arquivo, rotulo [MEDIDO/INFERIDO/LIDO]) nunca
  # pegaram este furo por serem puro ASCII.
  $tailCap = 2000
  $rawLines = @(Get-Content -LiteralPath $transcriptPath -Tail $tailCap -Encoding UTF8 -ErrorAction Stop)

  $objects = New-Object System.Collections.Generic.List[object]
  foreach ($rl in $rawLines) {
    if ([string]::IsNullOrWhiteSpace($rl)) { continue }
    $o = $null
    try { $o = $rl | ConvertFrom-Json } catch { continue }
    if ($null -eq $o) { continue }
    $objects.Add($o)
  }
  if ($objects.Count -eq 0) { exit 0 }

  # (2) Isola o TURNO ATUAL: da ULTIMA mensagem GENUINA de role "user" ate o fim. Se nenhuma
  # aparecer na janela lida (turno maior que o teto), usa a janela inteira (limitacao aceita).
  # CONSERTO (09/08/2026, achado ao provar a VALVULA pelo negativo): no contrato da API, todo
  # tool_result tambem chega como uma mensagem de role "user" - sem filtrar isso, "ultima
  # mensagem user" quase sempre caia num tool_result (o ultimo da cadeia de tools do turno), NUNCA
  # na instrucao real do Operator. turnLines cortava fora TODO tool_use anterior a esse tool_result
  # - inclusive o Write/Edit que a REGRA 1 (DELEGA) existe para pegar. So conta como inicio de
  # turno uma mensagem "user" que carrega TEXTO genuino (string ou bloco type='text'); mensagem
  # "user" que so tem tool_result nao conta.
  $turnStart = 0
  for ($i = $objects.Count - 1; $i -ge 0; $i--) {
    $t = $null
    try { $t = $objects[$i].type } catch { }
    if ($t -ne 'user') { continue }
    $m = $null
    try { $m = $objects[$i].message } catch { }
    $c = $null
    try { $c = $m.content } catch { }
    if (@(Get-TextFromContent $c).Count -eq 0) { continue }
    $turnStart = $i
    break
  }
  $turnLines = @($objects[$turnStart..($objects.Count - 1)])

  # (3) Coleta todo tool_use do turno (para a REGRA 1), o texto da ULTIMA mensagem assistant
  # (para a REGRA 2), e - para a VALVULA - todo texto digitado pelo Operator (role "user") e todo
  # tool_result do turno (para confirmar o register-task.ps1 -OperatorOrder).
  $allToolUses = New-Object System.Collections.Generic.List[object]
  $allToolResults = New-Object System.Collections.Generic.List[object]
  $operatorTexts = New-Object System.Collections.Generic.List[string]
  $lastAssistantIdx = -1
  for ($i = 0; $i -lt $turnLines.Count; $i++) {
    $entry = $turnLines[$i]
    $etype = $null
    try { $etype = $entry.type } catch { }
    $msg = $null
    try { $msg = $entry.message } catch { }
    $content = $null
    try { $content = $msg.content } catch { }
    if ($etype -eq 'user') {
      # Get-TextFromContent so devolve blocos type='text' (ou content string) - blocos
      # type='tool_result' ficam de fora daqui, entao isto pega SO texto de fato digitado pelo
      # Operator, nunca saida de tool disfarcada de "user" (contrato da API).
      foreach ($t in (Get-TextFromContent $content)) { $operatorTexts.Add($t) }
      foreach ($tr in (Get-ToolResultsFromContent $content)) { $allToolResults.Add($tr) }
      continue
    }
    if ($etype -ne 'assistant') { continue }
    foreach ($tu in (Get-ToolUsesFromContent $content)) { $allToolUses.Add($tu) }
    $lastAssistantIdx = $i
  }
  $operatorText = ($operatorTexts -join "`n")

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
  # CONSERTO (auditoria forense, defeito 6): a exclusao tinha 'scripts/' na lista (nunca sinaliza) E
  # o gatilho so disparava para caminho '(^|/)clients/' - editar engine/, docs/, skills/, scripts/,
  # AGENTS.md, CLAUDE.md ou qualquer arquivo de raiz NUNCA levantava sinal, so trabalho dentro de um
  # Client. Isso mediu sinal_dominio=0 em 81+ turnos mesmo com trabalho de dominio real acontecendo
  # fora de clients/ (este proprio conserto e um exemplo: escreve em scripts/ e engine/governance/).
  # Escopo agora e "qualquer escrita que NAO esteja numa exclusao legitima" - cobre clients/,
  # engine/, docs/, skills/, scripts/, AGENTS.md, CLAUDE.md e raiz. As exclusoes legitimas
  # (memoria/estado/backup/scratchpad - nunca sao "execucao de dominio") continuam de fora.
  $excludeSubstrings = @('memory/', '_proposals/', '_backups/', 'scratchpad', 'state.json')
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
        $excluded = $false
        foreach ($ex in $excludeSubstrings) { if ($norm.Contains($ex)) { $excluded = $true; break } }
        if (-not $excluded) { $sinalDominio = $true }
      }
    }
  }
  # (4b) A VALVULA - excecao legitima a REGRA 1 (doutrina completa no header deste script e em
  # response-guard.md). Fail-closed por construcao: SO abre com as duas pernas provadas no MESMO
  # turno; qualquer uma faltando (ou ambigua) deixa a valvula fechada e o turno segue regra normal.
  #   perna 1 (linguagem natural) - o Operator escreveu uma ordem explicita de execucao direta.
  #   perna 2 (registro auditavel) - scripts/register-task.ps1 -OperatorOrder rodou e teve sucesso
  #     no turno (reusa o mecanismo que ja grava operator_order:true na Task - nao duplica conceito).
  # Acentos via [char]0xNNNN (nao literal no arquivo - arquivo fica ASCII) mas o padrao ainda casa
  # fala do Operator com acento (conversa e com acento, so ARQUIVO e ASCII).
  $cCed = [char]0x00E7   # c-cedilha (ca -> faca)
  $aTil = [char]0x00E3   # a-til (nao)
  $eCir = [char]0x00EA   # e-circunflexo (voce)
  # CONSERTO: cada elemento precisa de parenteses proprios - "," tem precedencia MENOR que "+" no
  # PowerShell ('a' + 'b', 'c' vira 'a' + ('b','c'), nao ('a'+'b'), 'c') - sem isolar cada
  # concatenacao, o array virava 1 elemento so (os demais absorvidos e colados com espaco).
  $ordemPatterns = @(
    ('fa[' + $cCed + 'c]a?\s+(voc[' + $eCir + ']|vc)\s+mesm[ao]'),
    ('resolv\w*\s+direto'),
    ('execut\w*\s+(voc[' + $eCir + ']|vc)\s+mesm[ao]'),
    ('n[' + $aTil + 'a]o\s+delegu?e?\b'),
    ('sem\s+delegar'),
    ('sem\s+delega[' + $cCed + 'c][' + $aTil + 'a]o'),
    ('sem\s+especialista'),
    ('sem\s+agente'),
    ('voc[' + $eCir + ']\s+mesma\s+resolve'),
    ('n[' + $aTil + 'a]o\s+precisa\s+delegar')
  )
  $ordemRegex = '(' + ($ordemPatterns -join '|') + ')'
  $ordemDetectada = [bool]([regex]::IsMatch($operatorText, $ordemRegex, 'IgnoreCase'))

  $ordemRegistrada = $false
  foreach ($tu in $allToolUses) {
    $tname = $null
    try { $tname = [string]$tu.name } catch { }
    if ($tname -ne 'Bash' -and $tname -ne 'PowerShell') { continue }
    $cmd = $null
    try { $cmd = [string]$tu.input.command } catch { }
    if ([string]::IsNullOrWhiteSpace($cmd)) { continue }
    if ($cmd -notmatch 'register-task\.ps1' -or $cmd -notmatch '-OperatorOrder') { continue }
    $tuid = $null
    try { $tuid = [string]$tu.id } catch { }
    foreach ($tr in $allToolResults) {
      if ($tr.tool_use_id -ne $tuid) { continue }
      if ($tr.text -match '\[OK\] tarefa registrada') { $ordemRegistrada = $true }
    }
  }
  $valvulaAberta = $ordemDetectada -and $ordemRegistrada

  $violacaoDelega = $sinalDominio -and (-not $houveDelegacao) -and (-not $valvulaAberta)
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
    ordem_detectada  = $ordemDetectada
    ordem_registrada = $ordemRegistrada
    valvula_aberta   = $valvulaAberta
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
        $reasons.Add("Turno escreveu/editou arquivo de dominio sem chamar Agent/Task (falta delegacao) - delegue ao especialista mais capaz, ou - se foi ordem explicita do Operator pra executar direto - registre com 'scripts/register-task.ps1 ... -OperatorOrder' no mesmo turno pra abrir a valvula (ver response-guard.md).")
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
    " valvula_aberta=" + $valvulaAberta +
    " qtd_afirmacoes=" + $qtdAfirmacoes + " chars_resposta=" + $charsResposta +
    " informativo_sem_delegacao=" + $informativo)
  exit 0
} catch {
  exit 0
}
