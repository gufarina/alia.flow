<#
  delegation-gate.ps1 - Hook de PreToolUse. GUARDA NO ATO: bloqueia escrita de dominio pela
  coordenadora ANTES do arquivo ser gravado (nao so depois, no Stop - ver response-guard.ps1).

  INCIDENTE que motivou (07/09/2026, sessao 4f2b4cf2): a coordenadora escreveu ~10 arquivos de
  engine/, scripts/, docs/ com a propria mao, num turno so, sem Task e sem Specialist. 5 Whys
  mediu 4 causas-raiz (ver engine/governance/response-guard.md e law-ledger L45/L46); esta e a
  resposta a causa-raiz R1: "nao existe guarda no ATO de escrever - so no Stop, tarde demais".

  MEDIDO ANTES DE ESCREVER (WARDEN, 07/09/2026): o payload do hook PreToolUse NAO distingue
  chamada do loop principal de chamada de um sub-agente. Prova: instrumentei
  graph-usage-sensor.ps1 pra gravar transcript_path de toda chamada, e rodei Bash de DENTRO de um
  sub-agente Task (este proprio WARDEN e um). Resultado (4 linhas medidas, removido depois de
  provar): session_id e transcript_path do sub-agente sao IDENTICOS aos do turno pai
  (transcript_path aponta pro .jsonl de TOPO da sessao, nunca pro layout
  <sessId>/subagents/agent-<hash>.jsonl que response-guard.ps1 usa DEPOIS, no Stop, via
  .meta.json). Ou seja: em tempo real (PreToolUse), nao ha campo no payload que separe "isto e o
  loop principal" de "isto e um Specialist chamado via Task". Por isso este gate usa o FALLBACK
  honesto pedido: ao inves de tentar identificar quem chama, ele conta se JA HOUVE uma chamada de
  Task (subagent) NESTA SESSAO antes desta escrita - matcher do hook inclui "Task" alem de
  "Edit|Write|NotebookEdit" so pra ISSO: quando tool_name=Task, o script so grava um marcador
  (studio/delegation-seen.jsonl) e libera, nunca bloqueia Task. Limitacao aceita e nomeada: isto e
  MAIS FRACO que a REGRA 1 do response-guard.ps1 (que sabe isolar o TURNO ATUAL lendo o
  transcript) - aqui a janela e a SESSAO inteira, entao uma delegacao feita ha varios turnos
  "libera" escritas de dominio de turnos futuros que nao delegaram nada. Por isso este gate NUNCA
  substitui response-guard.ps1 (que continua sendo o freio fino, por turno) - e uma segunda
  camada, mais grossa, mas que age ANTES do arquivo ser gravado.

  Contrato do hook: JSON no STDIN (session_id, transcript_path, tool_name, tool_input.file_path
  ou tool_input.notebook_path). Contrato de RECUSA identico ao de graph-usage-sensor.ps1 (mesmo
  formato ja provado em producao - reuse-first):
    {"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny",
     "permissionDecisionReason":"<texto>"}}
  Sem violacao (ou tool_name=Task, ou fora de escopo): exit 0 silencioso (sem stdout) - "allow" e
  o default quando o hook nao imprime nada.

  ESCOPO DE DOMINIO: MESMA lista de substrings de exclusao da REGRA 1 do response-guard.ps1 (nao
  duplica um segundo criterio) + as exclusoes extras pedidas por esta tarefa (.claude/, studio/,
  node_modules, *baseline*.txt). Dominio positivo = clients/, engine/, docs/, skills/, scripts/,
  AGENTS.md, CLAUDE.md, ou arquivo de raiz - fora das exclusoes.

  A VALVULA: mesma doutrina do response-guard.ps1 (ordem explicita do Operator registrada via
  scripts/register-task.ps1 -OperatorOrder), mas auditada de outra forma - aqui nao ha texto do
  Operator disponivel no payload PreToolUse (so vem no UserPromptSubmit/Stop), entao a valvula
  soh confere a PERNA AUDITAVEL: existe em state.json (studio/state.json por padrao) uma Task com
  session == session_id desta chamada e operator_order == true? Se sim, a valvula esta aberta
  para toda escrita de dominio do RESTO da sessao (mesma limitacao de granularidade de sessao
  documentada acima, aceita pelo mesmo motivo).

  INTERRUPTOR DE EMERGENCIA (mesmo padrao do graph-usage-sensor.ps1): env
  ALIA_DELEGATION_GATE_OFF=1 (ou "true") OU arquivo .claude/delegation-gate.off (qualquer
  conteudo) desligam SO o bloqueio - o script fica mudo (nem grava o marcador de Task), fail-soft.

  BLINDAGEM: tudo dentro de try/catch. Qualquer erro -> exit 0 silencioso. Guarda quebrado nunca
  trava o operador.

  PARAMETROS DE TESTE (WARDEN): -Root, -MarkerPath, -StateFile sao overrides SO para fixture de
  smoke test (mesmo padrao de -Root em graph-usage-sensor.ps1 e -LogPath/-ConfigPath em
 response-guard.ps1). O hook de producao nunca passa esses params. Escrita .NET UTF-8 sem BOM.
#>
# WARDEN 09/09/2026: logica movida para funcao Invoke-DelegationGate (aceita -RawInput) para
# permitir chamada em-processo por scripts/pre-tool-use.ps1 (1 spawn em vez de 2). Rodar este
# arquivo direto (powershell -File) continua identico - o footer chama a funcao e usa Console.In
# quando -RawInput nao e passado.
param(
  [string]$Root = "",
  [string]$MarkerPath = "",
 [string]$StateFile = "",
 [string]$RawInput = $null
)

function Invoke-DelegationGate {
param(
 [string]$Root = "",
 [string]$MarkerPath = "",
 [string]$StateFile = "",
 [string]$RawInput = $null
)

try {
  $offEnv = $env:ALIA_DELEGATION_GATE_OFF
  $gateOff = ($offEnv -eq "1") -or ($offEnv -eq "true")

  $raw = ""
 if (-not [string]::IsNullOrWhiteSpace($RawInput)) {
 $raw = $RawInput
 } else {
 if (-not [Console]::IsInputRedirected) { return }

  try {
    $readTask = [Console]::In.ReadToEndAsync()
    if ($readTask.Wait(5000)) { $raw = $readTask.Result } else { $raw = "" }
  } catch { $raw = "" }
  }

 if ([string]::IsNullOrWhiteSpace($raw)) { return }

  $h = $null
 try { $h = $raw | ConvertFrom-Json } catch { return }
 if ($null -eq $h) { return }

  $tool = ""
  try { $tool = [string]$h.tool_name } catch { }
 if ([string]::IsNullOrWhiteSpace($tool)) { return }

  $sessionId = ""
  try { $sessionId = [string]$h.session_id } catch { }

  $root = if (-not [string]::IsNullOrWhiteSpace($Root)) { $Root } else { Split-Path -Parent $PSScriptRoot }
  $offFile = Join-Path $root ".claude\delegation-gate.off"
  if (Test-Path -LiteralPath $offFile) { $gateOff = $true }

  $markerFile = if (-not [string]::IsNullOrWhiteSpace($MarkerPath)) { $MarkerPath } else { Join-Path $root "studio\delegation-seen.jsonl" }

  # (A0) transcript_path apontando pra dentro de .../subagents/... (o layout que
  # response-guard.ps1 usa DEPOIS, no Stop, via .meta.json - Find-SubagentTranscript). MEDIDO
  # (WARDEN, 07/09/2026): em producao, o payload de PreToolUse de uma chamada feita de DENTRO de
  # um sub-agente Task NAO carrega esse layout - session_id e transcript_path saem identicos ao
  # do turno pai (ver header). Este check fica como belt-and-suspenders honesto: SE algum dia (ou
  # em algum host) o payload vier com esse caminho, o gate libera de imediato; no caso comum
  # medido hoje, quem faz o trabalho e o fallback do marcador (A/B) abaixo.
  $transcriptPath = ""
  try { $transcriptPath = [string]$h.transcript_path } catch { }
 if (-not [string]::IsNullOrWhiteSpace($transcriptPath) -and ($transcriptPath.Replace('\', '/') -match '/subagents/')) { return }

  # (A) tool_name=Task -> so grava o marcador "houve delegacao nesta sessao" e libera. NUNCA
  # bloqueia Task (bloquear a propria delegacao seria contraditorio com a lei que este gate
  # aplica). Roda mesmo com gateOff (medida nao custa nada e nao bloqueia nada).
  if ($tool -eq 'Task' -or $tool -eq 'Agent') {

    try {
      $mdir = Split-Path -Parent $markerFile
      if (-not [string]::IsNullOrWhiteSpace($mdir)) { New-Item -ItemType Directory -Force -Path $mdir -ErrorAction SilentlyContinue | Out-Null }
      $entry = [ordered]@{ ts = (Get-Date).ToUniversalTime().ToString("o"); session_id = $sessionId }
      $utf8 = New-Object System.Text.UTF8Encoding($false)
      [System.IO.File]::AppendAllText($markerFile, (($entry | ConvertTo-Json -Compress) + "`n"), $utf8)
    } catch { }
 return
  }

 if ($tool -ne 'Edit' -and $tool -ne 'Write' -and $tool -ne 'NotebookEdit') { return }
 if ($gateOff) { return }

  $fp = ""
  try { $fp = [string]$h.tool_input.file_path } catch { }
  if ([string]::IsNullOrWhiteSpace($fp)) { try { $fp = [string]$h.tool_input.notebook_path } catch { } }
 if ([string]::IsNullOrWhiteSpace($fp)) { return }

  $norm = $fp.Replace('\', '/').ToLowerInvariant()

  # Exclusoes: as mesmas da REGRA 1 do response-guard.ps1 + as pedidas nesta tarefa.
  $excludeSubstrings = @('memory/', '_proposals/', '_backups/', 'scratchpad', 'state.json',
    'artifacts/coordination/', '.claude/', '/studio/', 'node_modules', 'baseline.txt')
 foreach ($ex in $excludeSubstrings) { if ($norm.Contains($ex)) { return } }
 if ($norm -match 'baseline') { return }

  # Dominio positivo: clients/, engine/, docs/, skills/, scripts/, AGENTS.md, CLAUDE.md, ou raiz.
  $isDomain = $false
  if ($norm -match '(^|/)(clients|engine|docs|skills|scripts)/') { $isDomain = $true }
  if ($norm -match '(^|/)agents\.md$') { $isDomain = $true }
  if ($norm -match '(^|/)claude\.md$') { $isDomain = $true }
  # arquivo solto na raiz do projeto (sem "/" depois de remover a letra de drive/prefixo) tambem
  # conta - mas so quando nao caiu em nenhuma exclusao acima.
  if (-not $isDomain) {
    $leaf = $norm -replace '^[a-z]:', ''
    if ($leaf -match '^/?[^/]+\.(md|json|ya?ml|ps1)$') { $isDomain = $true }
  }
 if (-not $isDomain) { return }

  # (B) fallback honesto (MEDIDO): sem como distinguir loop principal de sub-agente no payload,
  # a pergunta vira "ja houve QUALQUER Task/Agent nesta sessao?" - marcador gravado no passo (A).
  $houveDelegacaoNaSessao = $false
  if (Test-Path -LiteralPath $markerFile) {

    try {
      $lines = @(Get-Content -LiteralPath $markerFile -Encoding UTF8 -ErrorAction SilentlyContinue)
      foreach ($l in $lines) {
        if ([string]::IsNullOrWhiteSpace($l)) { continue }
        $o = $null
        try { $o = $l | ConvertFrom-Json } catch { continue }
        if ($null -eq $o) { continue }
        $sid = ""
        try { $sid = [string]$o.session_id } catch { }
        if ($sid -eq $sessionId) { $houveDelegacaoNaSessao = $true; break }
      }

    } catch { }
  }
 if ($houveDelegacaoNaSessao) { return }

  # (C) a valvula: Task com session==session_id e operator_order==true em state.json.
  $stateFile = if (-not [string]::IsNullOrWhiteSpace($StateFile)) { $StateFile } else { Join-Path $root "state.json" }
  $valvulaAberta = $false
  if (Test-Path -LiteralPath $stateFile) {

    try {
      $st = (Get-Content -LiteralPath $stateFile -Raw -Encoding UTF8) | ConvertFrom-Json
      foreach ($t in @($st.tasks)) {
        $tsid = ""
        try { $tsid = [string]$t.session } catch { }
        $oo = $false
        try { $oo = [bool]$t.operator_order } catch { }
        if ($tsid -eq $sessionId -and $oo) { $valvulaAberta = $true; break }
      }

    } catch { }
  }
 if ($valvulaAberta) { return }

  # (D) violacao: dominio + sem delegacao vista na sessao + valvula fechada -> RECUSA.
  $reason = "[DELEGA] escrita de dominio pela coordenadora: delegue ao Specialist (.claude/agents/<client>-*.md ou alia-flow-lab-*) ou registre a ordem do operador com register-task.ps1 -OperatorOrder"
  $out = [ordered]@{
    hookSpecificOutput = [ordered]@{
      hookEventName = "PreToolUse"
      permissionDecision = "deny"
      permissionDecisionReason = $reason
    }

  }
  Write-Output ($out | ConvertTo-Json -Depth 5 -Compress)
 return
} catch {
 return
  }

  }

if ($MyInvocation.InvocationName -ne '.') {
 Invoke-DelegationGate -Root $Root -MarkerPath $MarkerPath -StateFile $StateFile -RawInput $RawInput
  exit 0
}

