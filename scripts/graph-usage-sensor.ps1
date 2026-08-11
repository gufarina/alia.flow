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
    Nenhum dos dois esta ligado hoje neste projeto (esta instancia roda em Claude Code).

  Sem acentos, sem emojis. Escrita .NET UTF-8 sem BOM. Timeout de 2s no stdin.
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
    # Busca recursiva por token de linha de comando - cobre rg/grep POSIX (Bash) e os idiomas
    # nativos do PowerShell (Select-String/sls, findstr tambem existe no PowerShell). "find" cobre
    # o find POSIX; o equivalente PowerShell (Get-ChildItem -Recurse) e um padrao a parte abaixo
    # porque precisa do FLAG, nao so do nome do cmdlet (Get-ChildItem sozinho e so "ls").
    elseif ($isShellTool -and $normCmd -match '(^|[|;&(\s])(rg|ripgrep|grep|egrep|findstr|ack|ag|find|select-string|sls)\s') {
      $kind = 'scan'; $match = $matches[2]
    }
    # Get-ChildItem/gci/dir/ls SO conta como varredura quando pedir recursao (-recurse/-r) ou for
    # o idioma cmd.exe "dir /s" - sem isso e so listagem de uma pasta (equivalente a "ls" comum,
    # que este sensor tambem nunca classificou como scan).
    elseif ($isShellTool -and $normCmd -match '(^|[|;&(\s])(gci|dir|ls|get-childitem)\b[^|;&]*(-recurse\b|-r\b|/s\b)') {
      $kind = 'scan'; $match = 'get-childitem-recurse'
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
  # NUNCA deve gerar recusa (2c) - so desiste de bloquear e segue para a medida normal.
  $denyReason = $null
  $escapeMsg  = $null
  $noMapMsg   = $null
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
          $clientId = $scope.Substring(8)
          $cand1 = Join-Path $root ($scope + "/graphify-out/GRAPH_REPORT.md")
          $cand2 = Join-Path $root ($scope + "/squad/knowledge/graphify-out/GRAPH_REPORT.md")
          if (Test-Path -LiteralPath $cand1) { $mapFile = $cand1 }
          elseif (Test-Path -LiteralPath $cand2) { $mapFile = $cand2 }
        } else {
          $mapFile = $externalMapFile
          $clientId = Split-Path -Leaf (Split-Path -Parent (Split-Path -Parent $mapFile))
        }

        if ($null -ne $mapFile) {
          # (4.3) Ja leu o mapa (ou ja teve escape) nesta sessao+escopo? Le o ledger existente
          # (linhas gravadas em chamadas ANTERIORES desta mesma sessao - a linha desta
          # chamada ainda nao foi escrita).
          # Le com ReadAllLines (nao ReadLines+break) de proposito: ReadLines devolve um
          # enumerador preguicoso que so fecha o handle do arquivo no Dispose, e um
          # foreach com break pode deixar esse Dispose para o GC. Isso corre risco de
          # colidir com o AppendAllText la embaixo (passo 5) e perder a linha desta
          # propria chamada - medido durante a prova pelo negativo desta mudanca.
          # ReadAllLines fecha o handle antes de devolver o array: sem essa corrida.
          $alreadyOk = $false
          $priorScanCount = 0
          if (Test-Path -LiteralPath $LedgerPath) {
            $needMap = '"session":"' + $sessionId + '"'
            foreach ($ln in [System.IO.File]::ReadAllLines($LedgerPath)) {
              if ($ln.IndexOf($needMap, [StringComparison]::Ordinal) -lt 0) { continue }
              if ($ln.IndexOf('"scope":"' + $scope + '"', [StringComparison]::Ordinal) -lt 0) { continue }
              if ($ln.IndexOf('"kind":"map"', [StringComparison]::Ordinal) -ge 0) { $alreadyOk = $true; break }
              if ($ln.IndexOf('"kind":"scan"', [StringComparison]::Ordinal) -ge 0) { $priorScanCount++ }
            }
          }

          if (-not $alreadyOk) {
            if ($priorScanCount -ge 2) {
              # (4.4) Escape na 3a tentativa seguida (2a) - libera com aviso, nunca trava em loop.
              $escapeMsg = "[GRAPH-GATE] liberado por escape: " + $priorScanCount +
                " recusa(s) seguida(s) em " + $scope + " sem leitura do mapa. Leia " +
                $mapFile + " quando puder - a partir de agora esta sessao nao bloqueia mais " +
                "varreduras neste client (regra anti-loop)."
            } else {
              # (4.5) Recusa - ensina o caminho exato, nao so proibe.
              $tentativa = $priorScanCount + 1
              $denyReason = "LEI DO MAPA: antes de varrer " + $clientId + " com " + $tool +
                ", leia primeiro " + $mapFile + " (secoes God Nodes e Community Hubs). " +
                "Esta e a tentativa " + $tentativa + " de 2 sem ler o mapa; a 3a libera " +
                "automaticamente para nao travar o trabalho. Depois de ler o mapa, toda " +
                "varredura neste client libera sem atrito nesta sessao."
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
    } catch { $denyReason = $null; $escapeMsg = $null; $noMapMsg = $null }
  }

  # (5) Escreve a linha no ledger - MEDE sempre, independente da decisao do gate (a tentativa
  # aconteceu; e essa contagem que sustenta o escape em 4.3/4.4).
  $pathOut = ""
  if ($tool -ne 'Bash' -and -not [string]::IsNullOrWhiteSpace($filePath)) {
    $pathOut = $filePath.Replace('\', '/')
    if ($pathOut.Length -gt 200) { $pathOut = $pathOut.Substring(0, 200) }
  }

  $entry = [ordered]@{
    ts      = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
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

  # (6) Decisao final. RECUSA imprime o JSON de deny (contrato do PreToolUse). ESCAPE e AVISO
  # (SEM-MAPA) tambem imprimem JSON - "additionalContext" dentro de hookSpecificOutput -, NUNCA
  # Write-Host: em PreToolUse (diferente de UserPromptSubmit), texto solto em stdout e IGNORADO
  # pelo Claude Code, so o JSON chega ao modelo (CONSERTO 10/08/2026, furo 1 - ver cabecalho).
  if ($null -ne $denyReason) {
    $out = [ordered]@{
      hookSpecificOutput = [ordered]@{
        hookEventName            = "PreToolUse"
        permissionDecision       = "deny"
        permissionDecisionReason = $denyReason
      }
    }
    Write-Output ($out | ConvertTo-Json -Depth 5 -Compress)
    exit 0
  }
  if ($null -ne $escapeMsg) {
    $out = [ordered]@{
      hookSpecificOutput = [ordered]@{
        hookEventName     = "PreToolUse"
        additionalContext = $escapeMsg
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
  exit 0
}
