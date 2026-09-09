<#
  graph-usage-sensor.ps1 - Hook de PreToolUse. SENSOR (mede) + GATE (recusa) da lei
  "grafo antes de varredura".

  HISTORICO: nasceu so como sensor (so anotava, nunca bloqueava). Medido depois: 8,9% de
  adesao em 45 pares sessao+projeto, com a lei escrita em 4 documentos, 1 regra dedicada,
  1 lembrete injetado a cada pedido (delegation-guard.ps1) e este sensor contando. Mais
  texto nao mudou o numero - bate com a pesquisa: um estudo com 1650 sessoes mediu que
  tamanho/posicao/estrutura do texto da regra NAO tem efeito; outro (mapa de codigo
  disponivel) mediu 58% de tentativas sem abrir o mapa nenhuma vez e concluiu "o gargalo
  nao e disponibilidade da ferramenta, e alinhamento comportamental". So estrutura
  resolve. Por isso este script GANHOU a segunda funcao: recusar a varredura.

  DECISAO DE DESENHO: gate foi FUNDIDO no sensor (nao um scripts/graph-gate.ps1 separado).
  Motivo, nesta ordem de peso:
    1. Reuse-first (LEI da casa): o sensor ja calcula $tool/$kind/$scope por evento; um
       segundo script recalcularia a mesma classificacao do zero.
    2. Custo medido: o proprio header original deste arquivo ja documentava que cada
       hook de PreToolUse com matcher custa ~450ms so de boot do powershell.exe. Dois
       scripts no mesmo matcher = dobra esse custo em TODA chamada de Read/Grep/Glob/Bash
       da sessao, nao so nas relevantes.
    3. Estado unico: o gate precisa saber "o mapa ja foi lido nesta sessao+escopo" e essa
       resposta mora no MESMO ledger que o sensor escreve (studio/graph-usage-log.jsonl).
       Um script separado leria o arquivo que o outro escreve - duas fontes falando do
       mesmo fato e exatamente o que a lei de reuse-first probe.
  O contador (scripts/graph-usage.ps1) continua um script a parte de proposito: ele so LE
  o ledger para relatorio/smoke, nunca decide nada em tempo real - papel diferente.

  O QUE O SCRIPT FAZ AGORA (nesta ordem, por evento de Read/Grep/Glob/Bash/PowerShell):
    (A) MEDE - grava uma linha no ledger, exatamente como antes (kind=map | kind=scan).
    (B) DECIDE - so quando kind=scan E o alvo tem escopo "clients/<id>" E aquele client
        TEM mapa em disco (graphify-out/GRAPH_REPORT.md existe):
          - mapa ja foi lido nesta sessao+escopo (ou ja houve escape, ver abaixo) -> libera,
            sem atrito, sem imprimir nada.
          - mapa NAO foi lido ainda:
              * 1a ou 2a tentativa de varredura nesta sessao+escopo -> RECUSA (PreToolUse
                permissionDecision=deny) com o caminho EXATO do GRAPH_REPORT.md a ler.
              * 3a tentativa seguida -> ESCAPE: libera com aviso (nunca trava em loop).
        client SEM mapa em disco (escopo "clients/<id>") -> nunca bloqueia (nao da pra exigir
        o que nao existe - gerar custa modelo, decisao do operador): libera SEMPRE, mas na
        PRIMEIRA varredura da sessao+escopo AVISA (uma vez so, nunca repetido) o custo de
        varrer as cegas e como gerar o mapa (CONSERTO 10/08/2026 - mandato do CEO: antes disso
        o gate ficava inerte pra quem nunca teve mapa nenhum, e so protegia quem ja tinha - o
        FURO que motivou este conserto). Escopo "external:*" fica de fora deste aviso por
        desenho: so existe quando um mapa ja foi achado subindo a arvore (passo 3) - cobrir
        "deveria ter mapa e nao tem nenhum" pra codebase externo exigiria um sinal diferente
        de "achei o mapa", fora do escopo deste conserto.

  CONTAGEM DO ESCAPE (sem inventar 2o registro): cada tentativa recusada JA fica no ledger
  como uma linha kind=scan (o sensor grava isso independente do gate - grava a TENTATIVA,
  nao o resultado). Antes de decidir, o gate conta quantas linhas kind=scan JA existem para
  este (session, scope) SEM nenhuma linha kind=map depois delas. Esse numero so pode ter
  crescido sob o proprio gate (e deterministico: sem mapa = recusa, ate a 3a), entao contar
  "quantos scans kind=scan already logados para este par" e o mesmo que contar "quantas
  recusas seguidas" - nao precisa de um kind=deny paralelo.

  PROTECOES DURAS (uma trava que atrapalha e pior que trava nenhuma):
    a) Escape na 3a tentativa seguida - ver acima. Depois do escape, o par (sessao, escopo)
       fica liberado pelo resto da sessao (nao volta a bloquear).
    b) So bloqueia Grep/Glob/Bash/PowerShell de varredura AMPLA sobre client com scope "clients/<id>".
       Read NUNCA bloqueia (nunca classificado kind=scan). Grep/Glob/Bash DENTRO do proprio
       graphify-out/ vira kind=map antes de kind=scan (ordem de classificacao existente, nao
       mudou). Caminhos de infra (memory/, _backups/, scratchpad, .claude/, node_modules)
       nunca caem em scope "clients/..." e por isso nunca sao avaliados pelo gate; ha uma
       trava explicita extra abaixo por seguranca.
    c) BLINDAGEM: toda a logica do gate roda dentro do try/catch que ja envolve o script
       inteiro. Qualquer excecao -> cai no catch -> exit 0 silencioso -> libera. O gate
       NUNCA pode ser a causa de um trabalho travado por bug do proprio script.
    d) INTERRUPTOR DE EMERGENCIA (desliga so o BLOQUEIO; a medida do sensor continua):
         - variavel de ambiente ALIA_GRAPH_GATE_OFF=1 (ou "true"), OU
         - arquivo-sentinela .claude/graph-gate.off (qualquer conteudo, so a presenca importa)
       Com qualquer um dos dois, o script volta a se comportar como sensor puro (so mede).
       Nao precisa reiniciar sessao nem ler codigo - so criar o arquivo ou exportar a env var.

  PRIVACIDADE (regra dura, sem mudanca): grava NOME de ferramenta e CAMINHO de arquivo.
  NUNCA grava conteudo de arquivo, NUNCA grava o texto do operador e NUNCA grava a linha de
  comando do Bash/PowerShell - so sai o TOKEN que casou (ex: "rg", "select-string", "graphify-query").

  Contrato do hook (stdin, JSON): session_id, cwd, hook_event_name, tool_name, tool_input.

  Contrato de RECUSA (o que o Claude Code entende): JSON no stdout, exit 0.
    {"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny",
     "permissionDecisionReason":"<texto que o modelo le - ensina o caminho certo>"}}
  (alternativa equivalente, nao usada aqui: exit code 2 com a razao no stderr.)

  CONSERTO 10/08/2026 (2 furos medidos por sessao de validacao independente, os dois na
  metade "avisar sem bloquear" da lei - a metade "recusar" ja funcionava):

  FURO 1 - o aviso [SEM-MAPA] (e o aviso de ESCAPE) nunca chegava ao modelo. Causa raiz:
  PreToolUse e DIFERENTE de UserPromptSubmit no contrato de hooks do Claude Code - so em
  UserPromptSubmit (e SessionStart/UserPromptExpansion) texto solto em stdout com exit 0 vira
  contexto do modelo. Em PreToolUse, texto solto em stdout e IGNORADO (nunca chega); so o JSON
  em hookSpecificOutput e lido. Confirmado por 2 fontes independentes (agente claude-code-guide +
  fetch direto de code.claude.com/docs/en/hooks.md, 10/08/2026): o campo "additionalContext" DENTRO
  de hookSpecificOutput e injetado como system-reminder "ao lado do resultado da tool" mesmo quando
  permissionDecision e "allow" (ou omitido) - ou seja, da pra avisar SEM bloquear. Escolhida em vez
  de (b) empilhar no delegation-guard.ps1 (UserPromptSubmit) porque: reuse-first (o mesmo hook ja
  teria que gravar um sinal pro OUTRO hook ler depois - estado duplicado, mais um arquivo pra
  sincronizar) e porque additionalContext e ENTREGUE NA MESMA CHAMADA (nao espera o proximo prompt
  do operador). Contrato agora, para AVISO sem bloqueio:
    {"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"<texto>"}}
  (permissionDecision fica de fora de proposito - "allow" e o default quando ausente; so RECUSA usa
  permissionDecision explicito.)

  FURO 2 - a ferramenta PowerShell (shell nativo do Windows, distinta de Bash/git-bash neste
  harness) varria clients/ por FORA do matcher do hook - nem contava no ledger, nem podia ser
  recusada. Medido: 1699+ linhas no ledger antes/depois de uma varredura por PowerShell num client
  COM mapa nao lido - zero registro. CONSERTO: matcher ganhou "|PowerShell" e o classificador de
  comando (abaixo) passou a reconhecer os idiomas de varredura do PowerShell (Select-String/sls,
  Get-ChildItem -Recurse/gci -r/dir /s), alem dos que ja cobria (rg/grep/findstr/find/...).

  FERRAMENTAS COBERTAS PELO MATCHER (levantamento real do harness, nao presumido) e POR QUE:
    - Read, Grep, Glob, Bash, PowerShell: os 5 jeitos de tocar arquivo em disco disponiveis nesta
      instancia. Read NUNCA vira kind=scan (design antigo, 2b) - so entra no matcher pra virar
      kind=map quando aponta pro GRAPH_REPORT.md. Grep/Glob sao busca ampla por natureza (sempre
      kind=scan). Bash/PowerShell so viram kind=scan quando o COMANDO bate um token de busca
      recursiva conhecido (nao todo Bash/PowerShell - "cat arquivo.py" nao e varredura).
    - FORA do matcher, com justificativa (nao e omissao, e decisao - custo de boot do powershell.exe
      por chamada e real, nao amplia sem motivo):
        Write/Edit/NotebookEdit - alvo e um caminho JA CONHECIDO (edicao pontual), nunca varredura.
        Agent - dispara um sub-agente com SUA PROPRIA sessao/hooks; as tool calls que ELE fizer
          (Bash/Grep/etc dentro do sub-agente) ja passam por este mesmo hook independentemente -
          nao ha rota de escape adicional em cobrir "Agent" em si (o tool_input dele nem tem
          path/command pra classificar).
        WebFetch/WebSearch/mcp__Claude_Browser__*/mcp__computer-use__* - navegam a WEB ou a TELA,
          nao o disco local; fora do escopo da lei do mapa (varrer o QUE, exatamente?).
        mcp__terminal__read_terminal - so LE o painel de terminal ja aberto pelo operador (sem
          path/command no schema, nao aceita direcionar busca nenhuma) - nao e capaz de varrer.
    Reavaliar esta lista se o harness ganhar uma ferramenta nova capaz de ler arquivo por caminho
    ou comando (novo MCP de shell, por exemplo) - o teste e sempre "aceita um path/command
    arbitrario apontando pro disco?", nao o nome da ferramenta.

  COMO LIGAR (.claude/settings.json ja tem isto - nao mudou o bloco, so o que o script faz):
    "PreToolUse": [
      {
        "matcher": "Read|Grep|Glob|Bash|PowerShell",
        "hooks": [
          {
            "type": "command",
            "command": "powershell -ExecutionPolicy Bypass -File \"${CLAUDE_PROJECT_DIR}/scripts/graph-usage-sensor.ps1\"",
            "timeout": 10
          }

        ]

      }

    ]

  PORTABILIDADE (produto roda em Claude Code, Codex e OpenCode - NAO implementado aqui,
  so mapeado para quem for portar nao ter que redescobrir):
    - Codex: contrato de hook quase identico ao do Claude Code - mesmo formato de decisao
      (permissionDecision: "deny"/"allow"/"ask") e mesmo exit code 2 + stderr como rota
      alternativa. Portar = trocar o transporte (onde o Codex espera o hook registrado,
      hoje AGENTS.md + config propria) e manter a MESMA logica de decisao (A/B/C acima);
      o corpo deste script (classificacao + contagem + JSON) e reaproveitavel quase 1:1.
    - OpenCode: hook e um PLUGIN TypeScript (tool.execute.before), nao um processo externo
      por stdin/stdout. A recusa e um `throw new Error(razao)` dentro do handler, nao um
      JSON. Portar = reescrever em TS chamando a mesma logica (ler o mesmo ledger, mesma
      janela de 2 recusas + escape na 3a), lancando throw no lugar do JSON de deny.
 Nenhum dos dois esta ligado hoje neste projeto (esta instancia roda em Claude Code). Escrita .NET UTF-8 sem BOM. Timeout de 2s no stdin.
#>
param([string]$LedgerPath = "", [string]$Root = "")

try {
  # (0) Payload do hook. So le stdin quando ele esta redirecionado (hook de verdade ou teste
  # por pipe); fora disso nem toca, pra nao travar shell interativo.
  if (-not [Console]::IsInputRedirected) { exit 0 }
  $readTask = [Console]::In.ReadToEndAsync()
  $raw = if ($readTask.Wait(2000)) { $readTask.Result } else { "" }
  if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }

  $h = $null
  try { $h = $raw | ConvertFrom-Json } catch { exit 0 }
  if ($null -eq $h) { exit 0 }

  $tool = ""
  try { $tool = [string]$h.tool_name } catch { }
  if ([string]::IsNullOrWhiteSpace($tool)) { exit 0 }

  $sessionId = ""
  try { $sessionId = [string]$h.session_id } catch { }
  $cwd = ""
  try { $cwd = [string]$h.cwd } catch { }

  # Raiz do projeto e caminho do ledger - resolvidos cedo porque o GATE (nao so a escrita
  # final) precisa ler o ledger e checar arquivos em disco antes de decidir. -Root e SO pra
  # teste isolado (fixture fora de clients/ real) - o hook de producao nunca passa esse param,
  # entao o default (script-relativo) e o comportamento de sempre.
  $root = if (-not [string]::IsNullOrWhiteSpace($Root)) { $Root } else { Split-Path -Parent $PSScriptRoot }
  if ([string]::IsNullOrWhiteSpace($LedgerPath)) {
    $LedgerPath = Join-Path (Join-Path $root "studio") "graph-usage-log.jsonl"
  }

  # (1) De onde sai o "alvo" de cada ferramenta.
  $filePath = ""
  $command  = ""
  try { if ($h.tool_input.file_path) { $filePath = [string]$h.tool_input.file_path } } catch { }
  try { if ([string]::IsNullOrWhiteSpace($filePath) -and $h.tool_input.path) { $filePath = [string]$h.tool_input.path } } catch { }
  try { if ($h.tool_input.command) { $command = [string]$h.tool_input.command } } catch { }

  $normPath = $filePath.Replace('\', '/').ToLowerInvariant()
  $normCmd  = $command.Replace('\', '/').ToLowerInvariant()

  # (2) Classificacao. MAP e testado ANTES de SCAN de proposito: um Grep DENTRO de graphify-out/
  # e leitura de mapa, nao varredura cega - isso tambem protege graphify-out/ do gate (2b).
  $kind  = ""
  $match = ""

  # Bash e PowerShell sao os 2 shells deste harness (git-bash/POSIX vs powershell.exe nativo) -
  # tratados igual daqui pra baixo: o que importa e o TOKEN dentro do $normCmd, nao o shell.
  $isShellTool = ($tool -eq 'Bash' -or $tool -eq 'PowerShell')

  if ($tool -eq 'Read' -or $tool -eq 'Grep' -or $tool -eq 'Glob') {
    if ($normPath -match 'graph_report\.md') { $kind = 'map'; $match = 'graph-report' }
    elseif ($normPath -match 'graph\.json')  { $kind = 'map'; $match = 'graph-json' }
    elseif ($normPath -match 'graphify-out') { $kind = 'map'; $match = 'graphify-out' }
  }
  if ($kind -eq '' -and $isShellTool) {
    if ($normCmd -match 'graphify\s+(query|explain|path)') { $kind = 'map'; $match = 'graphify-query' }
    elseif ($normCmd -match 'graph_report')                { $kind = 'map'; $match = 'graph-report' }
    elseif ($normCmd -match 'graphify-out')                { $kind = 'map'; $match = 'graphify-out' }
  }

  if ($kind -eq '') {
    if ($tool -eq 'Grep' -or $tool -eq 'Glob') {
      $kind = 'scan'; $match = $tool.ToLowerInvariant()
    }

 # WARDEN 09/09/2026: classificacao trocada de "substring em qualquer lugar do comando" (media
 # 13.822 de 20.903 Bash marcados scan so por conter "grep") para "PRIMEIRO TOKEN de cada
 # segmento do pipeline E alvo e diretorio, nao arquivo unico". wc/ls/cat/python -c/grep -c em
 # arquivo unico/head NAO sao scan (nao sao 1o token de busca, ou o alvo e um arquivo so).
 elseif ($isShellTool -and -not [string]::IsNullOrWhiteSpace($normCmd)) {
 $scanToolRegex = '^(rg|ripgrep|grep|egrep|findstr|ack|ag|find|select-string|sls)$'
 $segments = $normCmd -split '[|;]'
 foreach ($seg in $segments) {
 $segTrim = $seg.Trim()
 if ([string]::IsNullOrWhiteSpace($segTrim)) { continue }
 $tokens = @($segTrim -split '\s+')
 if ($tokens.Count -eq 0) { continue }
 $first = Split-Path -Leaf $tokens[0]
 $isRecurseGci = ($first -match '^(gci|dir|ls|get-childitem)$') -and ($segTrim -match '(-recurse\b|-r\b|/s\b)')
 $isScanTool = ($first -match $scanToolRegex)
 if (-not $isScanTool -and -not $isRecurseGci) { continue }

 # Alvo: para "find", o diretorio e o 1o posicional (find . -name x.py); para os demais,
 # o alvo costuma ser o ULTIMO posicional (grep pattern dir/, rg pattern dir/).
 $target = $null
 if ($first -eq 'find') {
 for ($i = 1; $i -lt $tokens.Count; $i++) {
 if ($tokens[$i] -notmatch '^-') { $target = $tokens[$i]; break }
    }

 } else {
 for ($i = $tokens.Count - 1; $i -ge 1; $i--) {
 if ($tokens[$i] -notmatch '^-') { $target = $tokens[$i]; break }
    }

  }

 # Arquivo unico = tem extensao curta no fim e nao termina em barra. Sem alvo (ex.: filtro
 # de stdout tipo "cmd | grep x") tambem NAO conta scan aqui - nao ha diretorio varrido.
 $isSingleFile = $false
 if ($target) {
 if ($target -match '\.[a-z0-9]{1,6}$' -and $target -notmatch '/$') { $isSingleFile = $true }
  }

 if ($isScanTool -and (-not $target -or $isSingleFile)) { continue }

 $kind = 'scan'
 $match = if ($isRecurseGci) { 'get-childitem-recurse' } else { $first }
 break
  }

  }

  }

  # Ferramenta irrelevante para a medida: sai sem gravar (ledger enxuto de proposito).
  if ($kind -eq '') { exit 0 }

  # (3) Escopo (o "codebase" daquela sessao). Ordem:
  #     a) caminho dentro de clients/<id>/  -> "clients/<id>" (o caso classico do studio).
  #     b) qualquer outro                   -> sobe a arvore de diretorios a partir do ALVO
  #        real da chamada procurando uma pasta "graphify-out/GRAPH_REPORT.md" (cobre
  #        codebase de cliente que mora FORA do studio, ex. Projetos/acme-saas). Achou -> escopo
  #        "external:<pasta que contem o graphify-out>". Nao achou -> nome da pasta do cwd
  #        (fallback antigo; sem mapa em lugar nenhum, nao ha o que exigir).
  #     A borda do "clients/" aceita inicio, barra OU separador de linha de comando (espaco,
  #     aspas): em Bash o alvo vem no meio do comando ("rg -n foo clients/acme-saas/src").
  function Find-AncestorMap([string]$StartPath) {
    # Sobe ate 20 niveis a partir de StartPath (arquivo ou pasta, existente ou nao) procurando
    # um irmao/ancestral "graphify-out/GRAPH_REPORT.md". Cobre tanto o caso externo
    # (Projetos/acme-saas/graphify-out) quanto o caso interno (clients/x/squad/knowledge/graphify-out) -
    # nos dois, subir a partir de dentro do codebase encontra a pasta graphify-out como filha
    # direta de algum ancestral. Devolve o caminho do GRAPH_REPORT.md ou $null.
    if ([string]::IsNullOrWhiteSpace($StartPath)) { return $null }
    $dir = $StartPath
    try { if (Test-Path -LiteralPath $dir -PathType Leaf) { $dir = Split-Path -Parent $dir } } catch { }
    $hops = 0
    while (-not [string]::IsNullOrWhiteSpace($dir) -and $hops -lt 20) {
      $cand = Join-Path $dir "graphify-out/GRAPH_REPORT.md"
      try { if (Test-Path -LiteralPath $cand) { return $cand } } catch { }
      $parent = $null
      try { $parent = Split-Path -Parent $dir } catch { }
      if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $dir) { break }
      $dir = $parent
      $hops++
    }

    return $null
  }

  # (3z) INJECAO ESTRUTURAL (TASK-169, 14/08/2026): em vez de so RECUSAR e esperar que alguem
  # lembre de ler o mapa, o gate agora ENTREGA o conteudo (God Nodes + Community Hubs) via
  # additionalContext no PRIMEIRO toque - o mapa chega ao modelo sem depender de habito. Escada
  # aplicada: menor mecanismo que garante isso e reusar o MESMO hook/ledger (zero servico novo,
  # zero campo novo no schema - so um novo valor de $match). Teto de tamanho evita pesar o turno.
  $INJECT_TETO = 2500
  function Get-MapInjection([string]$MapFile) {
    try { $txt = [System.IO.File]::ReadAllText($MapFile) } catch { return $null }
    $sections = ""
    foreach ($hdr in @('## God Nodes', '## Community Hubs')) {
      $m = [regex]::Match($txt, [regex]::Escape($hdr) + '.*?(?=\r?\n## |\z)', 'Singleline')
      if ($m.Success) { $sections += $m.Value.Trim() + "`n`n" }
    }

    $sections = $sections.Trim()
    if ([string]::IsNullOrWhiteSpace($sections)) { return $null }
    if ($sections.Length -gt $script:INJECT_TETO) {
      $cortado = $sections.Length - $script:INJECT_TETO
      $sections = $sections.Substring(0, $script:INJECT_TETO) + "`n`n[...TRUNCADO - " + $cortado + " caractere(s) cortado(s) pelo teto de tamanho da injecao; leia o arquivo completo: " + $MapFile + "]"
    }

    return $sections
  }

  # (3z2) SANITIZE NA INJECAO (TASK-213, item 5d): o conteudo do GRAPH_REPORT.md e DADO DE
  # CLIENTE (texto que um Specialist ou o proprio operador escreveu na documentacao do Client) -
  # antes de virar additionalContext (texto que o MODELO le como se fosse instrucao do sistema),
  # passa pelo mesmo sanitizador que qualquer outro payload de dominio (skills/sanitize-input).
  # FAIL-SOFT: skill ausente ou erro na chamada -> NAO injeta (silencio, nunca quebra o gate nem
  # injeta cru). Reusa o mecanismo existente (nao inventa um 2o sanitizador so pra isto).
  function Invoke-SanitizeMapContent([string]$Text) {

    try {
      # $PSScriptRoot (NUNCA $root): skills/ e parte da INSTALACAO do motor, no local real do
      # proprio script - $root pode ser sobrescrito via -Root em teste/fixture (escopo isolado
      # sem skills/ nenhuma), o que faria o sanitize sumir so por causa do isolamento de teste,
      # nao por falta real da skill (achado ao rodar o smoke inteiro, TASK-213).
      $sanScript = Join-Path (Split-Path -Parent $PSScriptRoot) "skills/sanitize-input/sanitize-input.ps1"
      if (-not (Test-Path -LiteralPath $sanScript)) { return $null }
      $sanOut = Join-Path ([System.IO.Path]::GetTempPath()) ("sanitize-map-" + [Guid]::NewGuid().ToString("N") + ".txt")
      & $sanScript -Text $Text -OutPath $sanOut 6>&1 | Out-Null
      if (-not (Test-Path -LiteralPath $sanOut)) { return $null }
      $clean = [System.IO.File]::ReadAllText($sanOut)
      Remove-Item -LiteralPath $sanOut -Force -ErrorAction SilentlyContinue
      if ([string]::IsNullOrWhiteSpace($clean)) { return $null }
      return $clean
    } catch {
      return $null
    }

  }

  $scope = ""
  $externalMapFile = $null
  $reScope = '(^|[^A-Za-z0-9_.-])clients/([A-Za-z0-9_.-]+)'
  if ($normPath -match $reScope) { $scope = 'clients/' + $matches[2] }
  elseif ($normCmd -match $reScope) { $scope = 'clients/' + $matches[2] }

  if ($scope -eq '') {
    # Alvo para o walk-up: file_path/path da ferramenta; se for Bash, o primeiro caminho
    # absoluto que aparecer no comando; sem nenhum dos dois, o cwd da chamada.
    $walkStart = $null
    if (-not [string]::IsNullOrWhiteSpace($filePath)) { $walkStart = $filePath }
    if ([string]::IsNullOrWhiteSpace($walkStart) -and -not [string]::IsNullOrWhiteSpace($command)) {
      # Caminho absoluto pode ter espaco (ex. "Jane Doe") e vem entre aspas no comando - tenta
      # aspas duplas, depois aspas simples, so por ultimo um token sem aspas (sem espaco).
      # Usa $command (case original) porque Test-Path e Windows sao case-insensitive de
      # qualquer forma - so evita normalizar sem necessidade.

      try {
        $normCmdRaw = $command.Replace('\', '/')
        $mQ = [System.Text.RegularExpressions.Regex]::Match($normCmdRaw, '"([A-Za-z]:/[^"]+)"')
        if (-not $mQ.Success) { $mQ = [System.Text.RegularExpressions.Regex]::Match($normCmdRaw, "'([A-Za-z]:/[^']+)'") }
        if ($mQ.Success) { $walkStart = $mQ.Groups[1].Value }
        else {
          $mU = [System.Text.RegularExpressions.Regex]::Match($normCmdRaw, '(^|[\s])([A-Za-z]:/[^\s"'']+)')
          if ($mU.Success) { $walkStart = $mU.Groups[2].Value }
        }

      } catch { }
    }

    if ([string]::IsNullOrWhiteSpace($walkStart)) { $walkStart = $cwd }

    try { $externalMapFile = Find-AncestorMap $walkStart } catch { $externalMapFile = $null }

    if ($null -ne $externalMapFile) {
      $codebaseRoot = Split-Path -Parent (Split-Path -Parent $externalMapFile)
      $scope = 'external:' + $codebaseRoot.Replace('\', '/').ToLowerInvariant()
    }

  }

  if ($scope -eq '') {
    if (-not [string]::IsNullOrWhiteSpace($cwd)) { $scope = Split-Path -Leaf $cwd } else { $scope = 'desconhecido' }
  }

  # (4) GATE - so entra aqui para kind=scan. Tudo dentro de try/catch proprio: erro aqui
  # NUNCA deve travar nada (2c) - so desiste da injecao e segue para a medida normal.
  $noMapMsg   = $null
  $injectMsg  = $null
  $needsInjectLedgerLine = $false
  if ($kind -eq 'scan') {

    try {
      # (4.0) Interruptor de emergencia (2d).
      $gateOff = $false
      if ($env:ALIA_GRAPH_GATE_OFF -eq '1' -or $env:ALIA_GRAPH_GATE_OFF -eq 'true') { $gateOff = $true }
      $sentinel = Join-Path $root ".claude/graph-gate.off"
      if (-not $gateOff -and (Test-Path -LiteralPath $sentinel)) { $gateOff = $true }

      # (4.1) Trava explicita extra para caminho de infra, mesmo que $scope por algum motivo
      # tenha casado "clients/" (defesa em profundidade - 2b).
      $isInfra = $false
      $reInfra = '(^|[/\s])(memory|_backups|\.claude|node_modules)(/|$|\s)'
      if ($normPath -match $reInfra -or $normCmd -match $reInfra -or
          $normPath -match 'scratchpad' -or $normCmd -match 'scratchpad') { $isInfra = $true }

      $isGateable = ($scope -like 'clients/*') -or ($scope -like 'external:*')
      if (-not $gateOff -and -not $isInfra -and $isGateable -and -not [string]::IsNullOrWhiteSpace($sessionId)) {
        # (4.2) O codebase TEM mapa em disco?
        #   - scope "clients/<id>"   -> so os 2 locais reais medidos no studio (mapa do
        #     segundo cerebro do squad).
        #   - scope "external:<dir>" -> o mapa ja foi achado no passo (3) subindo a arvore
        #     a partir do alvo real (cobre codebase de cliente fora do studio, ex. acme-saas).
        $clientId = $null
        $mapFile = $null
        if ($scope -like 'clients/*') {
          # CONSERTO (v1.56.1, achado do COURIER medido num Client real da instancia): o mapa do Client dentro
          # do studio mora em squad/knowledge/graphify-out (IRMAO de squad/agents, squad/artifacts
          # etc - nunca ancestral deles) - so cai pro walk-up de arvore quando o escopo NAO casa
          # "clients/<id>" (caso EXTERNAL, intocado). Esta ramificacao ja resolvia direto pelos 2
          # candidatos (nunca dependeu de subir arvore), mas a ORDEM foi alinhada aqui pra bater
          # com scripts/graph-check.ps1:248 ($cands, squad/knowledge/graphify-out PRIMEIRO) -
          # mesma fonte de verdade, reusada, nao uma 3a logica de resolucao.
          $clientId = $scope.Substring(8)
          $cand1 = Join-Path $root ($scope + "/squad/knowledge/graphify-out/GRAPH_REPORT.md")
          $cand2 = Join-Path $root ($scope + "/graphify-out/GRAPH_REPORT.md")
          if (Test-Path -LiteralPath $cand1) { $mapFile = $cand1 }
          elseif (Test-Path -LiteralPath $cand2) { $mapFile = $cand2 }
        } else {
          $mapFile = $externalMapFile
          $clientId = Split-Path -Leaf (Split-Path -Parent (Split-Path -Parent $mapFile))
        }

        if ($null -ne $mapFile) {
          # (4.3) Ja leu o mapa (ou ja recebeu injecao) nesta sessao+escopo? Le o ledger existente
          # (linhas gravadas em chamadas ANTERIORES desta mesma sessao - a linha desta
          # chamada ainda nao foi escrita).
          # Le com ReadAllLines (nao ReadLines+break) de proposito: ReadLines devolve um
          # enumerador preguicoso que so fecha o handle do arquivo no Dispose, e um
          # foreach com break pode deixar esse Dispose para o GC. Isso corre risco de
          # colidir com o AppendAllText la embaixo (passo 5) e perder a linha desta
          # propria chamada - medido durante a prova pelo negativo desta mudanca.
          # ReadAllLines fecha o handle antes de devolver o array: sem essa corrida.
          $alreadyOk = $false
          if (Test-Path -LiteralPath $LedgerPath) {
            $needMap = '"session":"' + $sessionId + '"'
            foreach ($ln in [System.IO.File]::ReadAllLines($LedgerPath)) {
              if ($ln.IndexOf($needMap, [StringComparison]::Ordinal) -lt 0) { continue }
              if ($ln.IndexOf('"scope":"' + $scope + '"', [StringComparison]::Ordinal) -lt 0) { continue }
              if ($ln.IndexOf('"kind":"map"', [StringComparison]::Ordinal) -ge 0) { $alreadyOk = $true; break }
            }

          }

          if (-not $alreadyOk) {
            # (4.4) INJECAO ESTRUTURAL (TASK-169): primeiro toque desta sessao+escopo com mapa em
            # disco - entrega o conteudo (God Nodes + Community Hubs) via additionalContext JUNTO
            # com a liberacao da varredura. A RECUSA (deny/escape das 2 tentativas) SAIU: ela
            # dependia do modelo lembrar de agir depois de ser barrado; a injecao nao depende de
            # nada, o mapa so chega no mesmo turno. $needsInjectLedgerLine sinaliza o passo (5) a
            # gravar uma 2a linha kind=map/match=map-injected pra este evento - reusa o MESMO
            # $alreadyOk (nao inventa campo novo): a proxima chamada acha essa linha e nao
            # reinjeta (anti-ruido, uma vez por par sessao+escopo).
            $mapContent = Get-MapInjection $mapFile
            if ($null -ne $mapContent) {
              # TASK-213 (item 5d): sanitiza ANTES de montar o additionalContext - conteudo cru de
              # cliente nunca chega ao modelo sem passar pela borda. Sanitize falhou -> nao injeta
              # (fail-soft, ver Invoke-SanitizeMapContent acima).
              $mapContentLimpo = Invoke-SanitizeMapContent $mapContent
              if ($null -ne $mapContentLimpo) {
                $injectMsg = "[MAPA INJETADO] " + $clientId + " - God Nodes + Community Hubs de " +
                  $mapFile + " (injecao automatica no 1o toque desta sessao+escopo, TASK-169;" +
                  " sanitizado antes da injecao, TASK-213):`n`n" +
                  $mapContentLimpo
                $needsInjectLedgerLine = $true
              }

            }

          }

        } elseif ($scope -like 'clients/*') {
          # (4.6) CONSERTO 10/08/2026 - o FURO fechado: client SEM mapa nenhum em disco nao pode
          # ser bloqueado (nao da pra exigir o que nao existe), mas ate agora tambem nao AVISAVA
          # nada - a lei do mapa so protegia quem ja tinha mapa. Agora: passa sempre, mas avisa
          # 1x por sessao+escopo na PRIMEIRA varredura (nunca repete - aviso repetido vira ruido
          # e o agente aprende a ignorar). So escopo "clients/<id>" entra aqui (ver nota no topo
          # do arquivo sobre por que "external:*" fica de fora).
          $priorScanNoMap = 0
          if (Test-Path -LiteralPath $LedgerPath) {
            $needMap2 = '"session":"' + $sessionId + '"'
            foreach ($ln in [System.IO.File]::ReadAllLines($LedgerPath)) {
              if ($ln.IndexOf($needMap2, [StringComparison]::Ordinal) -lt 0) { continue }
              if ($ln.IndexOf('"scope":"' + $scope + '"', [StringComparison]::Ordinal) -lt 0) { continue }
              if ($ln.IndexOf('"kind":"scan"', [StringComparison]::Ordinal) -ge 0) { $priorScanNoMap++ }
            }

          }

          if ($priorScanNoMap -eq 0) {
            $noMapMsg = "[SEM-MAPA] " + $clientId + " ainda nao tem mapa de conhecimento " +
              "(" + $cand1 + " nao existe). Varrer as cegas com " + $tool + " custa muito mais " +
              "token do que consultar um mapa pronto - e o que esta acontecendo agora. Para " +
              "gerar o mapa (custa modelo, decisao do operador, nunca automatica): rode " +
              "/graphify clients/" + $clientId + ". Este aviso aparece so uma vez por sessao " +
              "para este projeto; as proximas varreduras aqui seguem liberadas sem aviso."
          }

        }

      }

    } catch {
      $noMapMsg = $null; $injectMsg = $null; $needsInjectLedgerLine = $false
      # Freio que quebra passa a gritar (TASK-213): a decisao do gate (recusar/injetar) falhou -
      # grava no MESMO ledger e segue fail-open (o evento ainda vira MEDIDA no passo (5) abaixo).

      try {
        $errObjInner = [ordered]@{
          ts      = (Get-Date).ToString("o")
          session = $sessionId
          erro    = $_.Exception.GetType().Name
          fase    = "gate-decisao"
        }

        $errLineInner = ($errObjInner | ConvertTo-Json -Compress)
        $utf8NoBomInner = New-Object System.Text.UTF8Encoding($false)
        if (Test-Path -LiteralPath (Split-Path -Parent $LedgerPath)) {
          [System.IO.File]::AppendAllText($LedgerPath, $errLineInner + "`n", $utf8NoBomInner)
        }

      } catch { }
    }

  }

  # (5) Escreve a linha no ledger - MEDE sempre, independente da decisao do gate (a tentativa
  # aconteceu; e essa contagem que sustenta o escape em 4.3/4.4).
  $pathOut = ""
  if ($tool -ne 'Bash' -and -not [string]::IsNullOrWhiteSpace($filePath)) {
    $pathOut = $filePath.Replace('\', '/')
    if ($pathOut.Length -gt 200) { $pathOut = $pathOut.Substring(0, 200) }
  }

  # $tsNow capturado UMA vez e reusado na linha de injecao (5b) abaixo: se cada linha chamasse
  # Get-Date de novo, a linha map-injected sairia sempre ALGUNS MS DEPOIS da linha scan (I/O
  # sequencial), e a comparacao "firstMap -le firstScan" de graph-usage.ps1 marcaria a propria
  # injecao como FURO (mapa "depois" do scan) - o oposto do que a injecao entrega de verdade (o
  # mapa chega JUNTO com a liberacao do mesmo toque). Mesmo instante = mesmo evento.
  $tsNow = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
  $entry = [ordered]@{
    ts      = $tsNow
    session = $sessionId
    tool    = $tool
    kind    = $kind
    scope   = $scope
    match   = $match
    path    = $pathOut
  }
  $line = ($entry | ConvertTo-Json -Compress)

  $ledgerDir = Split-Path -Parent $LedgerPath
  if (-not (Test-Path -LiteralPath $ledgerDir)) {
    New-Item -ItemType Directory -Force -Path $ledgerDir -ErrorAction SilentlyContinue | Out-Null
  }

  # Append com 3 tentativas: PreToolUse pode disparar em paralelo (tool calls simultaneas) e o
  # arquivo fica travado por instantes. Perder uma linha nunca justifica travar a ferramenta.
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  for ($i = 0; $i -lt 3; $i++) {

    try {
      [System.IO.File]::AppendAllText($LedgerPath, $line + "`n", $utf8NoBom)
      break
    } catch {
      Start-Sleep -Milliseconds 40
    }

  }

  # (5b) INJECAO: grava uma 2a linha kind=map/match=map-injected pro MESMO evento (TASK-169) -
  # reusa o campo $match existente (nao inventa schema novo) pra marcar "leitura injetada",
  # distinta de "leu sozinho" (match=graph-report/graph-json/graphify-out/graphify-query). E
  # essa linha que faz $alreadyOk achar TRUE na proxima chamada (anti-reinjecao, passo 4.3).
  if ($needsInjectLedgerLine) {
    $injectEntry = [ordered]@{
      ts      = $tsNow
      session = $sessionId
      tool    = $tool
      kind    = "map"
      scope   = $scope
      match   = "map-injected"
      path    = ""
    }

    $injectLine = ($injectEntry | ConvertTo-Json -Compress)
    for ($i = 0; $i -lt 3; $i++) {

      try {
        [System.IO.File]::AppendAllText($LedgerPath, $injectLine + "`n", $utf8NoBom)
        break
      } catch {
        Start-Sleep -Milliseconds 40
      }

    }

  }

  # (6) Decisao final. INJECAO e AVISO (SEM-MAPA) imprimem JSON - "additionalContext" dentro de
  # hookSpecificOutput -, NUNCA Write-Host: em PreToolUse (diferente de UserPromptSubmit), texto
  # solto em stdout e IGNORADO pelo Claude Code, so o JSON chega ao modelo (CONSERTO 10/08/2026,
  # furo 1 - ver cabecalho). RECUSA/ESCAPE saem daqui (TASK-169): a injecao entrega o mapa no
  # mesmo turno, sem depender de ninguem lembrar de agir - nao ha mais nada pra "recusar".
  if ($null -ne $injectMsg) {
    $out = [ordered]@{
      hookSpecificOutput = [ordered]@{
        hookEventName     = "PreToolUse"
        additionalContext = $injectMsg
      }

    }

    Write-Output ($out | ConvertTo-Json -Depth 5 -Compress)

    exit 0
  }
  if ($null -ne $noMapMsg) {
    $out = [ordered]@{
      hookSpecificOutput = [ordered]@{
        hookEventName     = "PreToolUse"
        additionalContext = $noMapMsg
      }

    }

    Write-Output ($out | ConvertTo-Json -Depth 5 -Compress)

    exit 0
  }

  exit 0
} catch {
  # Freio que quebra passa a gritar (TASK-213): grava UMA linha no MESMO ledger que o sensor
  # ja escreve (nao inventa arquivo novo) e continua fail-open (exit 0 - sensor quebrado nunca
  # trava a ferramenta que ele estava medindo).

  try {
    $errRoot2 = if (-not [string]::IsNullOrWhiteSpace($Root)) { $Root } else { Split-Path -Parent $PSScriptRoot }
    $errLedger2 = if (-not [string]::IsNullOrWhiteSpace($LedgerPath)) { $LedgerPath } else { Join-Path (Join-Path $errRoot2 "studio") "graph-usage-log.jsonl" }
    $errDir2 = Split-Path -Parent $errLedger2
    if (-not (Test-Path -LiteralPath $errDir2)) { New-Item -ItemType Directory -Force -Path $errDir2 | Out-Null }
    $errSession2 = ""
    try { $errSession2 = [string]$sessionId } catch { }
    $errObj2 = [ordered]@{
      ts      = (Get-Date).ToString("o")
      session = $errSession2
      erro    = $_.Exception.GetType().Name
      fase    = "catch-geral"
    }

    $errLine2 = ($errObj2 | ConvertTo-Json -Compress)
    $utf8NoBomErr2 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::AppendAllText($errLedger2, $errLine2 + "`n", $utf8NoBomErr2)
  } catch { }

  exit 0
}

