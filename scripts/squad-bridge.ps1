<#
  squad-bridge.ps1 - a ponte que falta entre persona em markdown e agente invocavel.

  Problema medido: os "especialistas" em clients\*\squad\agents\*.md sao personas em markdown,
  NAO agentes invocaveis (sem .claude\agents\, sem frontmatter YAML). Resultado: delegar custa
  mais que executar, e a lei "a coordenadora delega, nunca executa" nao tem como pegar. Este
  script gera, a partir da MESMA fonte:

    clients\{client}\squad\squad.yaml
    clients\{client}\squad\agents\{id}.yaml
    clients\{client}\squad\agents\{id}.md

  DOIS MODOS (mesmo contrato, doutrina de OPP-42 "delegacao portavel" -
  clients\alia-flow-lab\opportunities\OPP-42-delegacao-portavel.md - ainda nao implementada em
  orchestration.md/skills quando este script foi escrito; aqui so a GERACAO dos dois formatos de
  saida a partir da fonte unica, para nao travar quando skills\delegate existir):

  -Mode spawn (padrao) - host com sub-agente nativo (ex: Claude Code):
    escreve .claude\agents\{client}-{id}.md com frontmatter YAML valido (name/description/
    tools/model). description = role + dominio + gatilhos do yaml (o suficiente pro modelo saber
    QUANDO acionar). tools = tools[] do yaml filtrados contra a lista real do Claude Code; camada
    B/C (folha) nunca ganha Task/Agent; sem tools validos no yaml, cai no padrao por camada.
    model = camada A -> opus, B -> sonnet, C -> haiku. Corpo = o agents\{id}.md integral + "Antes
    de agir, carregue" (knowledge[] do yaml, caminho absoluto, + GRAPH_REPORT.md se existir) +,
    para B/C, "Voce e folha" (nao re-delega).

  -Mode opencode - host com sub-agente NATIVO de outro formato (OpenCode): escreve
    .opencode\agent\{client}-{id}.md com o frontmatter que O OPENCODE le (description, mode:
    subagent, permission, e model SO quando a persona declara um id de modelo de verdade no
    formato provider/modelo - tier "strong/standard/fast" nao e id de modelo e nunca vira model:).
    permission e a allow-list da persona TRADUZIDA para o vocabulario do OpenCode: edit allow se a
    persona tem Edit/Write, bash allow se tem Bash, webfetch allow se tem WebFetch/WebSearch -
    o que a persona nao tem nasce deny. Isso promove o OpenCode de context-load para SPAWN: o
    Specialist vira invocavel por @{client}-{id}, com escopo aplicado pelo host, nao so lido.

  -Mode context-load - host SEM sub-agente (ex: Codex): escreve
    .claude\agents\{client}-{id}.context-load.md, um BRIEFING PORTAVEL sem frontmatter de Claude
    Code (nenhum host alem do Claude Code le YAML frontmatter de agente). Contem: identidade
    (role/camada/brain), o escopo de ferramentas declarado em PROSA (a mesma lista do modo spawn -
    vestir o chapeu nao amplia acesso), a persona (agents\{id}.md integral), os mesmos caminhos de
    knowledge, e a regra de folha adaptada a context-load: produzir a entrega, devolver o
    Artifact, DESCARREGAR o bloco e voltar a coordenar (o Gate roda depois, fora do chapeu). O
    coordenador em host sem spawn le este arquivo inteiro e "veste" a persona nele descrita.

  Requisitos duros: idempotente (2a rodada nao duplica - so regrava se o conteudo mudou), UTF-8
  sem BOM, sem acentos e sem emojis nos arquivos que escreve, -DryRun so mostra, -Client filtra,
  erro em um agente nao derruba o resto (try/catch por arquivo), resumo final com contagem.

  Validacao de knowledge: cada entrada de knowledge[] no yaml e conferida contra o disco antes de
  virar caminho no briefing. Token que existe como arquivo -> caminho normal. Token conceitual
  "shared" (ou "all") -> resolve para a pasta squad\knowledge\ inteira (e o que "fatia
  compartilhada do segundo cerebro" quer dizer). Token que nao resolve em nada -> OMITIDO, com
  aviso no resumo final (nunca escreve caminho falso no briefing de um Specialist).

  CAMINHO DE KNOWLEDGE - PORTAVEL POR LEI (conserto de 05/09/2026, TASK-421): o caminho escrito no
  bloco "Antes de agir, carregue" nasce RELATIVO a $RepoRoot sempre que o arquivo alvo estiver
  DENTRO de $RepoRoot (ex: "clients/acme-saas/squad/knowledge/graphify-out/GRAPH_REPORT.md"),
  com barra normal. Caminho ABSOLUTO so quando o alvo estiver FORA de $RepoRoot (o studio privado
  do operador, que nunca viaja). Motivo medido: gerando para studio.example/ - a fixture PUBLICA
  que SHIPA no pacote - o caminho absoluto colocava a pasta de usuario do Windows dentro de 6 arquivos
  publicados, e o guard de path do package-release.ps1 reprovou o empacotamento (passo 3/3). Vale
  para os TRES modos (spawn, opencode, context-load) - a conversao acontece num ponto so.

  Validacao de MCP: toda tool que comeca com "mcp__" e conferida contra os servidores reais
  declarados em .mcp.json (na raiz do repo). Servidor real -> mantem. Correspondencia obvia (ex:
  "supabase" quando so existe "supabase-mos") -> corrige o namespace com aviso. Sem correspondencia
  (ex: "vercel", que nao esta declarado) -> DESCARTA a tool com aviso. Nunca escreve tool de
  servidor inexistente no frontmatter/briefing gerado.

  LIMITE CONHECIDO (nao e defeito de construcao): um agente gerado por este script NAO fica
  acionavel na sessao que o gerou. O harness do Claude Code le a lista de sub-agentes na ABERTURA
  da sessao; agentes novos em .claude\agents\ so valem a partir da proxima sessao. Se a delegacao
  precisar do especialista AGORA, use o modo -Mode context-load (o briefing portavel, sem depender
  de sub-agente nativo) em vez de esperar reabrir a sessao.

  Sem acentos, sem emojis (regra da casa) - inclusive neste proprio script.
#>

[CmdletBinding()]
param(
    [switch]$DryRun,
    [string]$Client,
    [string]$RepoRoot,
    [ValidateSet('spawn', 'context-load', 'opencode')]
 [string]$Mode = 'spawn',
 # -MigrateContract: unico caminho para os squads existentes ganharem os 4 campos novos
 # (entry_point/budget/output_contract/grounding) sem quebrar - adiciona so o que falta, com o
 # default da camada, nunca sobrescreve campo ja preenchido. Roda e sai (nao gera bundle).
 [switch]$MigrateContract,
 # -Only <client>: remove de .claude\agents\ os bundles de OUTROS Clients, mantendo sempre o
 # squad do engine_home (alia-flow-lab). Roda e sai (nao gera bundle). LIMITE: rodar no MEIO da
 # sessao nao recarrega o roster do Claude Code (ele le sub-agentes so na abertura da sessao) -
 # rodar SEMPRE antes de abrir a sessao.
 [string]$Only
)

$ErrorActionPreference = 'Stop'

if (-not $RepoRoot) {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
}

$clientsDir = Join-Path $RepoRoot 'clients'
# cada host le a sua propria pasta de sub-agente. spawn/context-load escrevem em .claude\agents
# (o segundo so um briefing portavel, sem frontmatter); o modo opencode escreve na pasta que o
# OpenCode le de verdade.
$outDir = if ($Mode -eq 'opencode') { Join-Path $RepoRoot '.opencode\agent' } else { Join-Path $RepoRoot '.claude\agents' }

if (-not (Test-Path $clientsDir)) {
    Write-Error "nao achei $clientsDir"
    exit 1
}

if (-not (Test-Path $outDir)) {
    if (-not $DryRun) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }

}

# ---- -Only: poda de bundles de outros Clients (roda e sai) ----
if ($Only) {
 $bundlesDir = Join-Path $RepoRoot '.claude\agents'
 $keep = @($Only, 'alia-flow-lab') | Select-Object -Unique
 $removedCount = 0
 if (Test-Path $bundlesDir) {
 $bundles = Get-ChildItem -Path $bundlesDir -Filter '*.md' -File -ErrorAction SilentlyContinue
 foreach ($b in $bundles) {
 $isKept = $false
 foreach ($k in $keep) { if ($b.BaseName -like "$k-*") { $isKept = $true; break } }
 if (-not $isKept) {
 if (-not $DryRun) { Remove-Item -LiteralPath $b.FullName -Force }
 Write-Host "[REMOVIDO] $($b.Name)"
 $removedCount++
}

}

}

 Write-Host "-Only $Only : $removedCount bundle(s) removido(s) (mantidos: $($keep -join ', ')). Rode ISTO antes de abrir a sessao - o Claude Code so le sub-agentes na abertura, rodar no meio nao recarrega o roster."
 exit 0
}

# ---- deteccao de harness (item e: context-load nunca gera bundle quando o host tem sub-agente
# nativo Claude Code - usa a mesma deteccao de detect-harness.ps1) ----
$detectedHarness = 'unknown'
try {
 $detectScript = Join-Path $PSScriptRoot 'detect-harness.ps1'
 if (Test-Path $detectScript) {
 $detectOut = & $detectScript
 foreach ($dl in $detectOut) {
 if ($dl -match '^harness=(.+)$') { $detectedHarness = $Matches[1] }
}

}

}
catch { }

if ($Mode -eq 'context-load' -and $detectedHarness -eq 'claude-code') {
 Write-Host "modo context-load pulado: harness detectado e claude-code (sub-agente nativo) - use -Mode spawn."
 exit 0
}

# ---- caminho portavel (ver cabecalho, "CAMINHO DE KNOWLEDGE - PORTAVEL POR LEI") ----
# Dentro de $RepoRoot -> relativo a raiz, com barra normal. Fora -> absoluto, como sempre foi.
$RepoRootFull = ((Resolve-Path -LiteralPath $RepoRoot).Path).TrimEnd('\', '/')

function ConvertTo-PortablePath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $full = $Path
    try { $full = [System.IO.Path]::GetFullPath($Path) } catch { }
    $prefix = $RepoRootFull + [System.IO.Path]::DirectorySeparatorChar
    if ($full.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        return ($full.Substring($prefix.Length) -replace '\\', '/')
    }

    return $full
}

# ---- lista real de tools do Claude Code (whitelist) ----
$ToolWhitelist = @('Read', 'Write', 'Edit', 'Grep', 'Glob', 'Bash', 'Task', 'WebFetch', 'WebSearch', 'NotebookEdit')

# ---- servidores MCP reais (medido em .mcp.json, nao inventado) ----
$mcpConfigPath = Join-Path $RepoRoot '.mcp.json'
$McpServers = @()
if (Test-Path $mcpConfigPath) {
    try {
        $mcpJson = Get-Content -Path $mcpConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($mcpJson.mcpServers) {
            $McpServers = @($mcpJson.mcpServers.PSObject.Properties.Name)
        }

    }

    catch {
        Write-Warning "nao consegui ler $mcpConfigPath : $($_.Exception.Message)"
    }

}

# valida uma tool "mcp__servidor__ferramenta" contra $McpServers.
# servidor real -> mantem. correspondencia obvia (prefixo, ex "supabase" -> "supabase-mos") ->
# corrige o namespace. sem correspondencia -> retorna $null (a tool e descartada).
function Resolve-McpTool {
    param(
        [Parameter(Mandatory = $true)][string]$Token,
        [string[]]$Servers,
        [Parameter(Mandatory = $true)][ref]$Warnings,
        [Parameter(Mandatory = $true)][string]$Context
    )

    $parts = $Token -split '__', 3
    if ($parts.Count -lt 3 -or $parts[0] -ne 'mcp') {
        [void]$Warnings.Value.Add("$Context : tool '$Token' fora do formato mcp__servidor__ferramenta - descartada")
        return $null
    }

    $server = $parts[1]
    $rest = $parts[2]

    if ($Servers -contains $server) {
        return $Token
    }

    $match = @($Servers | Where-Object { $_ -like "$server-*" -or $_ -like "$server*" }) | Select-Object -First 1
    if ($match) {
        $corrected = "mcp__${match}__$rest"
        [void]$Warnings.Value.Add("$Context : tool '$Token' - namespace corrigido para '$corrected' (servidor real: $match)")
        return $corrected
    }

    [void]$Warnings.Value.Add("$Context : tool '$Token' - servidor '$server' nao existe em .mcp.json - descartada")
    return $null
}

# ---- parser YAML minimo: so o que os arquivos de agente usam (chave: valor / chave: [lista] /
# lista indentada / mapa aninhado de UM nivel, ex "agent:\n  id: maya\n  layer: A" - o unico jeito
# que o exemplo real studio.example/clients/acme-saas declara os campos do agente). Um container de
# topo com valor vazio (ex "agent:") vira LISTA se a proxima linha indentada for "- item", ou vira
# MAPA (achatado/flatten pro nivel de topo) se a proxima linha indentada for "chave: valor" - o
# wrapper (ex "agent") em si nunca e consumido, so os subcampos importam. ----
function Read-SimpleYaml {
    param([Parameter(Mandatory = $true)][string]$Path)

    $data = @{}
    $currentKey = $null   # chave de lista (nivel 0) em construcao
    $nestedKey = $null    # chave que PODE virar mapa aninhado (nivel 0) em construcao
    $lines = Get-Content -Path $Path -Encoding UTF8

    foreach ($rawLine in $lines) {
        $line = $rawLine
        if ($line -match '^\s*#') { continue }
        if ($line -match '^\s*$') { continue }

        if ($line -match '^(\w[\w-]*):\s*(.*)$') {
            $key = $Matches[1]
            $val = $Matches[2]
            # tira comentario inline ("valor   # nota")
            $val = ($val -replace '\s+#.*$', '').TrimEnd()

            if ($val -eq '' -or $val -eq '[]') {
                $data[$key] = New-Object System.Collections.ArrayList
                $currentKey = $key
                $nestedKey = $key
            }

            elseif ($val -match '^\[(.*)\]$') {
                $inner = $Matches[1]
                $items = @()
                if ($inner.Trim() -ne '') {
                    $items = $inner -split ',' | ForEach-Object { $_.Trim().Trim('"').Trim("'") } | Where-Object { $_ -ne '' }
                }

                $list = New-Object System.Collections.ArrayList
                foreach ($it in $items) { [void]$list.Add($it) }
                $data[$key] = $list
                $currentKey = $null
                $nestedKey = $null
            }

            else {
                $data[$key] = $val.Trim()
                $currentKey = $null
                $nestedKey = $null
            }

            continue
        }

        if ($line -match '^\s+-\s*(.+)$') {
            $item = $Matches[1]
            $item = ($item -replace '\s+#.*$', '').Trim().Trim('"').Trim("'")
            if ($currentKey -and $data.ContainsKey($currentKey)) {
                if ($data[$currentKey] -is [System.Collections.ArrayList]) {
                    [void]$data[$currentKey].Add($item)
                }

            }

            $nestedKey = $null   # confirmado: e lista, nao mapa aninhado
            continue
        }

        if ($nestedKey -and $line -match '^\s+(\w[\w-]*):\s*(.*)$') {
            $subKey = $Matches[1]
            $subVal = ($Matches[2] -replace '\s+#.*$', '').TrimEnd().Trim('"').Trim("'")
            # achata pro nivel de topo; nao sobrescreve uma chave de topo real ja preenchida
            if (-not $data.ContainsKey($subKey) -or ($data[$subKey] -is [System.Collections.ArrayList] -and $data[$subKey].Count -eq 0)) {
                $data[$subKey] = $subVal
            }

            continue
        }

    }

    # o wrapper (ex "agent") nunca e consumido - se ficou vazio (virou mapa achatado), descarta
    if ($nestedKey -and $data.ContainsKey($nestedKey) -and $data[$nestedKey] -is [System.Collections.ArrayList] -and $data[$nestedKey].Count -eq 0) {
        $data.Remove($nestedKey) | Out-Null
    }

    return $data
}

function Get-ListValue {
    param($Data, [string]$Key)
    if ($Data.ContainsKey($Key) -and $Data[$Key] -is [System.Collections.ArrayList]) {
        return @($Data[$Key])
    }

    return @()
}

function Get-ScalarValue {
    param($Data, [string]$Key, [string]$Default = '')
    if ($Data.ContainsKey($Key) -and -not ($Data[$Key] -is [System.Collections.ArrayList])) {
        return [string]$Data[$Key]
    }

    return $Default
}

# squad.yaml e a fonte da verdade do time (assim declarado no cabecalho de cada squad.yaml
# medido). Os agents\{id}.yaml individuais podem ficar desatualizados apos promocao/rebaixamento
# de camada (medido: squad.yaml de um Client pode documentar promocao/rebaixamento de membro
# depois de reorganizacao - e os yaml individuais nunca foram atualizados).
# Le o campo camada/layer por id (override) E quem e o Gateway - as tres formas medidas no parque:
# "gateway: <id>" de topo (studio.example/acme-saas), "gateway: true" por membro (tambem
# acme-saas) e "squad: { owner: <id> }" aninhado (tambem acme-saas). O id do Gateway E camada A,
# sempre - quem governa e bate o Gate nao pode nascer sem Task (ver forcamento no loop principal).
function Read-SquadYamlInfo {
    param([Parameter(Mandatory = $true)][string]$Path)

    $map = @{}
    $curId = $null
    $topGateway = $null
    $memberGateway = $null
    $owner = $null
    $inSquadBlock = $false
    $lines = Get-Content -Path $Path -Encoding UTF8

    foreach ($line in $lines) {
        if ($line -match '^squad:\s*$') { $inSquadBlock = $true; continue }
        if ($inSquadBlock) {
            if ($line -match '^\S') { $inSquadBlock = $false }
            elseif ($line -match '^\s+owner:\s*([^\s#]+)') { $owner = $Matches[1].Trim() }
        }

        if ($line -match '^gateway:\s*([^\s#]+)') { $topGateway = $Matches[1].Trim(); continue }
        if ($line -match '^\s*-\s*id:\s*([^\s#]+)') {
            $curId = $Matches[1].Trim()
            continue
        }

        if ($curId) {
            if ($line -match '^\s*(?:camada|layer):\s*([^\s#]+)') {
                $map[$curId] = $Matches[1].Trim().ToUpper()
            }

            elseif ($line -match '^\s*gateway:\s*true\s*$') {
                $memberGateway = $curId
            }

        }

    }

    $gatewayId = if ($topGateway) { $topGateway } elseif ($memberGateway) { $memberGateway } elseif ($owner) { $owner } else { $null }

    return [pscustomobject]@{ Camadas = $map; GatewayId = $gatewayId }
}

# ---- bloco "Antes de agir" do contrato do especialista (auditoria-harness-v2.html, secao 03) ----
# entry_point primeiro (quando ha), depois assinatura/fatia, depois grounding (client.md), depois
# grafo. knowledge[] vira lista "docs disponiveis (abra pelo indice)" - nunca mais "carregue".
# Camada A dispensa Orcamento/Contrato de saida (Gateway orquestra, nao tem teto de execucao).
function New-BeforeActingBlock {
 param(
 [string]$Camada,
 [string]$EntryPointPath,
 [string]$GroundingPath,
 [string[]]$KnowledgeLines,
 [string]$BudgetToolCalls,
 [string]$OutputMaxLines,
 [string]$EvidenceTags,
 [string]$AuthorityDecides,
 [string]$AuthorityEscalatesTo
)

 $lines = New-Object System.Collections.ArrayList
 [void]$lines.Add('## Antes de agir (obrigatorio, nesta ordem)')
 [void]$lines.Add('')
 $step = 1
 if ($EntryPointPath) {
 [void]$lines.Add("$step. Leia $EntryPointPath (uma linha por doc). Nunca um doc inteiro sem achar a linha dele.")
 $step++
}

 [void]$lines.Add("$step. Ache a assinatura (titulo + primeiro paragrafo) antes de abrir o corpo.")
 $step++
 [void]$lines.Add("$step. Abra so a fatia (secao) que responde a pergunta.")
 $step++
 if ($GroundingPath) {
 [void]$lines.Add("$step. Antes de QUALQUER afirmacao sobre este Client, leia $GroundingPath. Nao afirme por lembranca ou nome parecido.")
 $step++
}

 [void]$lines.Add("$step. Se existir graphify-out/GRAPH_REPORT.md, leia God Nodes antes de Grep/Glob cego.")
 [void]$lines.Add('')
 [void]$lines.Add('docs disponiveis (abra pelo indice):')
 [void]$lines.Add('')
 if (-not $KnowledgeLines -or $KnowledgeLines.Count -eq 0) {
 [void]$lines.Add('- (nenhum knowledge declarado no yaml deste agente)')
}

 else {
 foreach ($kl in $KnowledgeLines) { [void]$lines.Add("- $kl") }
}

 if ($Camada -ne 'A') {
 [void]$lines.Add('')
 [void]$lines.Add('## Orcamento')
 [void]$lines.Add('')
 [void]$lines.Add("Maximo $BudgetToolCalls chamadas. Estourou, pare e entregue o que tem.")
}

 # ---- Contrato de saida (max_lines/evidence_tags): TODA camada, inclusive A - Gateway
 # tambem declara teto de linhas (TASK-509). ----
 [void]$lines.Add('')
 [void]$lines.Add('## Contrato de saida')
 [void]$lines.Add('')
 $tagList = ($EvidenceTags -replace "[\[\]]", "" -split ",\s*" | ForEach-Object { "[" + $_.Trim() + "]" }); $tagTxt = if ($tagList.Count -gt 1) { (($tagList[0..($tagList.Count-2)]) -join ", ") + " ou " + $tagList[-1] } else { $tagList -join "" }
 [void]$lines.Add("Maximo $OutputMaxLines linhas. Cada fato leva um rotulo: $tagTxt.")
 [void]$lines.Add('Afirmacao sem marca nao entra.')

 # ---- Autoridade (TASK-509, 6a definicao): o que decide sozinho e a quem escala. TODA camada. ----
 [void]$lines.Add('')
 [void]$lines.Add('## Autoridade')
 [void]$lines.Add('')
 [void]$lines.Add("Decide sozinho: $AuthorityDecides.")
 [void]$lines.Add("Escala para: $AuthorityEscalatesTo.")

 return $lines
}

# ---- -MigrateContract: adiciona os 4 campos novos do contrato (entry_point/budget/
# output_contract/grounding) so onde faltam, com o default da camada, sem tocar campo existente
# (roda e sai) ----
if ($MigrateContract) {
 $migClientDirs = Get-ChildItem -Path $clientsDir -Directory
 if ($Client) { $migClientDirs = $migClientDirs | Where-Object { $_.Name -eq $Client } }

 foreach ($clientDir in $migClientDirs) {
 $squadDirM = Join-Path $clientDir.FullName 'squad'
 $agentsDirM = Join-Path $squadDirM 'agents'
 $squadYamlM = Join-Path $squadDirM 'squad.yaml'
 if (-not (Test-Path $agentsDirM)) { continue }

 $squadInfoM = if (Test-Path $squadYamlM) { Read-SquadYamlInfo -Path $squadYamlM } else { $null }

 foreach ($yamlFileM in Get-ChildItem -Path $agentsDirM -Filter '*.yaml' -File) {
 $agentIdM = [System.IO.Path]::GetFileNameWithoutExtension($yamlFileM.Name)
 try {
 $rawM = Get-Content -Path $yamlFileM.FullName -Raw -Encoding UTF8
 $dataM = Read-SimpleYaml -Path $yamlFileM.FullName

 $camadaM = Get-ScalarValue $dataM 'camada' ''
 if (-not $camadaM) { $camadaM = Get-ScalarValue $dataM 'layer' '' }
 $camadaM = $camadaM.ToUpper()
 if ($squadInfoM -and $squadInfoM.Camadas.ContainsKey($agentIdM)) { $camadaM = $squadInfoM.Camadas[$agentIdM] }
 if ($squadInfoM -and $squadInfoM.GatewayId -eq $agentIdM) { $camadaM = 'A' }
 if ($camadaM -ne 'A' -and $camadaM -ne 'B' -and $camadaM -ne 'C') { $camadaM = 'B' }

 $defBudget = if ($camadaM -eq 'C') { 8 } else { 20 }
 $defLines = switch ($camadaM) { 'C' { 25 }; 'A' { 100 }; default { 60 } }
 # defaults GENERICOS de authority por camada (TASK-509) - migracao preenche isto so como
 # ponto de partida; CADA persona migrada precisa de ajuste a mao citando o dominio REAL dela
 # (o generico serve pra nao travar 54 arquivos de uma vez, nunca como texto final).
 $defDecides = switch ($camadaM) {
 'A' { 'roteamento das Tasks e veredito do Quality Gate' }
 'C' { 'o que a lente deste Specialist cobre' }
 default { 'as decisoes dentro do dominio deste Specialist' }
 }
 $defEscalatesTo = switch ($camadaM) {
 'A' { 'Operator, quando a decisao sai do escopo do squad' }
 'C' { 'o Specialist B do mesmo squad, fora da lente' }
 default { 'o Gateway do squad, quando sai do dominio' }
 }

 $knowledgeEntriesM = Get-ListValue $dataM 'knowledge'
 $addedFields = New-Object System.Collections.ArrayList
 $appendLines = New-Object System.Collections.ArrayList

 if ($knowledgeEntriesM.Count -gt 0 -and -not ($rawM -match '(?m)^entry_point:')) {
 [void]$appendLines.Add('entry_point: knowledge/MAP.md')
 [void]$addedFields.Add('entry_point')
}

 if ($camadaM -ne 'A') {
 if (-not ($rawM -match '(?m)^budget:')) {
 [void]$appendLines.Add('budget:')
 [void]$appendLines.Add(" tool_calls: $defBudget")
 [void]$appendLines.Add(' tokens: null')
 [void]$addedFields.Add('budget')
}

}

 if (-not ($rawM -match '(?m)^output_contract:')) {
 [void]$appendLines.Add('output_contract:')
 [void]$appendLines.Add(" max_lines: $defLines")
 [void]$appendLines.Add(' evidence_tags: [MEDIDO, LIDO, INFERIDO]')
 [void]$addedFields.Add('output_contract')
}

 if (-not ($rawM -match '(?m)^grounding:')) {
 [void]$appendLines.Add('grounding: client.md')
 [void]$addedFields.Add('grounding')
}

 if (-not ($rawM -match '(?m)^authority:') -and -not ($rawM -match '(?m)^decides:')) {
 [void]$appendLines.Add('authority:')
 [void]$appendLines.Add(" decides: $defDecides")
 [void]$appendLines.Add(" escalates_to: $defEscalatesTo")
 [void]$addedFields.Add('authority (GENERICO - ajuste a mao)')
}

 elseif (-not ($rawM -match '(?m)^escalates_to:')) {
 # tinha authority/escalates_to velho (escalar so, sem decides) - completa o que falta
 [void]$appendLines.Add("decides: $defDecides")
 [void]$addedFields.Add('decides (GENERICO - ajuste a mao)')
}

 if ($appendLines.Count -gt 0) {
 $newRawM = $rawM.TrimEnd() + "`n`n" + ($appendLines -join "`n") + "`n"
 if (-not $DryRun) {
 $utf8NoBomM = New-Object System.Text.UTF8Encoding($false)
 [System.IO.File]::WriteAllText($yamlFileM.FullName, $newRawM, $utf8NoBomM)
}

 Write-Host "[$($clientDir.Name)/$agentIdM] camada $camadaM - campos adicionados: $($addedFields -join ', ')"
}

 else {
 Write-Host "[$($clientDir.Name)/$agentIdM] camada $camadaM - ja tinha todos os campos do contrato"
}

}

 catch {
 Write-Warning "[$($clientDir.Name)/$agentIdM] erro na migracao: $($_.Exception.Message)"
}

}

}

 exit 0
}

# ---- geracao ----
$generated = 0
$updated = 0
$unchanged = 0
$errors = 0
$reportLines = New-Object System.Collections.ArrayList
$mcpWarnings = New-Object System.Collections.ArrayList
$knowledgeWarnings = New-Object System.Collections.ArrayList
$camadaWarnings = New-Object System.Collections.ArrayList

$clientDirs = Get-ChildItem -Path $clientsDir -Directory
if ($Client) {
    $clientDirs = $clientDirs | Where-Object { $_.Name -eq $Client }
    if (-not $clientDirs) {
        Write-Warning "cliente '$Client' nao encontrado em $clientsDir"
    }

}

foreach ($clientDir in $clientDirs) {
    $clientId = $clientDir.Name
    $squadDir = Join-Path $clientDir.FullName 'squad'
    $squadYaml = Join-Path $squadDir 'squad.yaml'
    $agentsDir = Join-Path $squadDir 'agents'

    if (-not (Test-Path $squadYaml)) { continue }
    if (-not (Test-Path $agentsDir)) { continue }

    $knowledgeDir = Join-Path $squadDir 'knowledge'
    $graphReport = Join-Path $knowledgeDir 'graphify-out\GRAPH_REPORT.md'
    $hasGraph = Test-Path $graphReport
    $squadInfo = Read-SquadYamlInfo -Path $squadYaml

    $agentYamls = Get-ChildItem -Path $agentsDir -Filter '*.yaml' -File
    foreach ($yamlFile in $agentYamls) {
        $agentId = [System.IO.Path]::GetFileNameWithoutExtension($yamlFile.Name)
        try {
            $mdPath = Join-Path $agentsDir "$agentId.md"
            if (-not (Test-Path $mdPath)) {
                Write-Warning "[$clientId/$agentId] falta $agentId.md - pulando"
                $errors++
                continue
            }

            $data = Read-SimpleYaml -Path $yamlFile.FullName
            $body = Get-Content -Path $mdPath -Raw -Encoding UTF8

            $role = Get-ScalarValue $data 'role' $agentId
            $domain = Get-ScalarValue $data 'domain' ''

            # ---- camada: campo canonico 'camada', sinonimos 'layer' e tier de modelo
            # (strong/standard/fast), depois override de squad.yaml (camada/layer por membro),
            # depois o Gateway declarado em squad.yaml - que SEMPRE vence e forca A. Nada
            # determinado -> nao assume B em silencio, avisa no resumo (fail-loud). ----
            $camada = Get-ScalarValue $data 'camada' ''
            if (-not $camada) { $camada = Get-ScalarValue $data 'layer' '' }
            if (-not $camada) {
                $tierVal = Get-ScalarValue $data 'tier' ''
                if (-not $tierVal) { $tierVal = Get-ScalarValue $data 'model' '' }
                $camada = switch ($tierVal.ToLower()) {
                    'strong' { 'A' }
                    'standard' { 'B' }
                    'fast' { 'C' }
                    default { '' }
                }

            }

            $camada = $camada.ToUpper()

            if ($squadInfo.Camadas.ContainsKey($agentId)) {
                $squadCamada = $squadInfo.Camadas[$agentId]
                if ($camada -and $camada -ne $squadCamada) {
                    [void]$camadaWarnings.Add("$clientId/$agentId : squad.yaml sobrescreve a camada '$camada' resolvida do yaml individual para '$squadCamada' - squad.yaml vence, DIVERGENCIA registrada")
                }

                $camada = $squadCamada
            }

            if ($squadInfo.GatewayId -and $squadInfo.GatewayId -eq $agentId) {
                if ($camada -and $camada -ne 'A') {
                    [void]$camadaWarnings.Add("$clientId/$agentId : squad.yaml declara este id como Gateway mas a camada resolvida era '$camada' - squad.yaml vence, forcado para A")
                }

                $camada = 'A'
            }

            if ($camada -ne 'A' -and $camada -ne 'B' -and $camada -ne 'C') {
                if ($camada) {
                    [void]$camadaWarnings.Add("$clientId/$agentId : camada '$camada' invalida (esperado A/B/C) - assumido B, CONFIRA a fonte")
                }

                else {
                    [void]$camadaWarnings.Add("$clientId/$agentId : camada indeterminavel (sem camada/layer/tier no yaml, sem override em squad.yaml, nao e o Gateway) - assumido B, CONFIRA a fonte")
                }

                $camada = 'B'
            }

            $triggers = Get-ListValue $data 'triggers'
            $knowledgeEntries = Get-ListValue $data 'knowledge'
            $rawTools = Get-ListValue $data 'tools'

 # ---- contrato do especialista (auditoria-harness-v2.html, secao 03; TASK-509 acrescenta a 6a
 # definicao, authority): entry_point, budget.tool_calls, output_contract.max_lines/evidence_tags,
 # grounding, authority.decides/escalates_to. Ausencia PARA o processo para AQUELE agente (throw,
 # capturado pelo try/catch do loop) - sem bundle, sem bypass. Camada A dispensa so
 # budget.tool_calls (Gateway nao tem teto de chamadas); output_contract e authority sao
 # obrigatorios em TODA camada, inclusive A - Gateway tambem declara teto de linhas e limite de
 # autoridade. ----
 $entryPointRaw = Get-ScalarValue $data 'entry_point' ''
 $budgetToolCalls = Get-ScalarValue $data 'tool_calls' ''
 $outputMaxLines = Get-ScalarValue $data 'max_lines' ''
 $evidenceTags = Get-ScalarValue $data 'evidence_tags' ''
 $groundingRaw = Get-ScalarValue $data 'grounding' ''
 $authorityDecides = Get-ScalarValue $data 'decides' ''
 $authorityEscalatesTo = Get-ScalarValue $data 'escalates_to' ''
 $defBudgetContract = if ($camada -eq 'C') { 8 } else { 20 }
 $defLinesContract = switch ($camada) { 'C' { 25 }; 'A' { 100 }; default { 60 } }
 $defAuthority = switch ($camada) {
 'A' { @{ decides = 'roteamento das Tasks e veredito do Quality Gate'; escalates_to = 'Operator, quando a decisao sai do escopo do squad' } }
 'C' { @{ decides = 'o que a lente deste Specialist cobre'; escalates_to = 'o Specialist B do mesmo squad, fora da lente' } }
 default { @{ decides = 'as decisoes dentro do dominio deste Specialist'; escalates_to = 'o Gateway do squad, quando sai do dominio' } }
 }

 if ($knowledgeEntries.Count -gt 0) {
 $mapPathCheck = Join-Path $knowledgeDir 'MAP.md'
 if (-not (Test-Path $mapPathCheck)) {
 throw "falta $mapPathCheck - rode: scripts/kb-index.ps1 -KnowledgePath `"$knowledgeDir`""
}

 if (-not $entryPointRaw) {
 throw "falta 'entry_point' no yaml (obrigatorio quando knowledge[] nao vazio). Sugestao: entry_point: knowledge/MAP.md"
}

}

                if ($camada -ne 'A') {
 if (-not $budgetToolCalls) {
 throw "falta 'budget.tool_calls' no yaml. Default sugerido para camada $camada`: $defBudgetContract"
}

}

 if (-not $outputMaxLines) {
 throw "falta 'output_contract.max_lines' no yaml (obrigatorio em toda camada, inclusive A). Sugestao para camada $camada`: $defLinesContract"
}

 if (-not $evidenceTags) {
 throw "falta 'output_contract.evidence_tags' no yaml. Sugestao: [MEDIDO, LIDO, INFERIDO]"
}

 if (-not $groundingRaw) {
 throw "falta 'grounding' no yaml (obrigatorio em toda camada, inclusive A/Gateway). Sugestao: grounding: client.md"
}

 if (-not $authorityDecides) {
 throw "falta 'authority.decides' no yaml (obrigatorio em toda camada - o que este agente fecha sozinho). Sugestao para camada $camada`: $($defAuthority.decides)"
}

 if (-not $authorityEscalatesTo) {
 throw "falta 'authority.escalates_to' no yaml (obrigatorio em toda camada - a quem sobe e em que caso). Sugestao para camada $camada`: $($defAuthority.escalates_to)"
}

            # ---- description ----
            $descParts = New-Object System.Collections.ArrayList
            [void]$descParts.Add($role)
            if ($domain) { [void]$descParts.Add("dominio: $domain") }
            if ($triggers.Count -gt 0) {
                $trigList = ($triggers | Select-Object -First 5) -join '; '
                [void]$descParts.Add("acionar quando: $trigList")
            }

            $description = ($descParts -join '. ') -replace '\s+', ' '
            $description = $description.Trim()
            if (-not $description) { $description = "$role ($clientId/$agentId)" }

            # ---- tools ----
            # mcp__* passa por validacao contra .mcp.json ANTES de entrar na whitelist (defeito
            # confirmado: ferramenta externa nao validada gerava mcp__vercel__* e namespace errado
            # mcp__supabase__* quando o servidor real e mcp__supabase-mos__*).
            $resolvedRawTools = New-Object System.Collections.ArrayList
            foreach ($t in $rawTools) {
                if ($t -like 'mcp__*') {
                    $resolvedTool = Resolve-McpTool -Token $t -Servers $McpServers -Warnings ([ref]$mcpWarnings) -Context "$clientId/$agentId"
                    if ($resolvedTool) { [void]$resolvedRawTools.Add($resolvedTool) }
                }

                else {
                    [void]$resolvedRawTools.Add($t)
                }

            }

            $rawTools = @($resolvedRawTools)

            $validTools = @($rawTools | Where-Object { ($ToolWhitelist -contains $_) -or ($_ -like 'mcp__*') })

            if ($camada -ne 'A') {
                $validTools = @($validTools | Where-Object { $_ -ne 'Task' -and $_ -ne 'Agent' })
            }

            if (-not $validTools -or $validTools.Count -eq 0) {
                switch ($camada) {
                    'A' { $validTools = @('Read', 'Grep', 'Glob', 'Task') }
                    'B' { $validTools = @('Read', 'Grep', 'Glob', 'Edit', 'Write', 'Bash') }
                    default { $validTools = @('Read', 'Grep', 'Glob') }
                }

            }

            elseif ($camada -eq 'A' -and ($validTools -notcontains 'Task')) {
                $validTools = @($validTools) + @('Task')
            }

            $toolsLine = ($validTools -join ', ')

            # ---- model ----
            $model = switch ($camada) {
                'A' { 'opus' }
                'B' { 'sonnet' }
                default { 'haiku' }
            }

            # ---- knowledge (caminhos absolutos, VALIDADOS contra disco) ----
            # defeito confirmado: "shared" e um token conceitual ("a fatia compartilhada do
            # segundo cerebro"), nao um nome de arquivo - gerar shared.md sem conferir produzia
            # caminho quebrado no briefing. "shared"/"all" resolvem para a pasta knowledge\
            # inteira; qualquer outro token que nao vire arquivo real e OMITIDO com aviso.
            $knowledgeLines = New-Object System.Collections.ArrayList
            foreach ($k in $knowledgeEntries) {
                $entry = $k.Trim()
                if (-not $entry) { continue }
                if ($entry -eq 'all' -or $entry -eq 'shared' -or $entry -match 'todo o knowledge') {
                    [void]$knowledgeLines.Add($knowledgeDir)
                    continue
                }

                $entry = $entry -replace '^knowledge[\\/]', ''
                if ($entry -notmatch '\.\w+$') { $entry = "$entry.md" }
                $entry = $entry -replace '/', '\'
                $resolvedPath = Join-Path $knowledgeDir $entry
                if (Test-Path $resolvedPath) {
                    [void]$knowledgeLines.Add($resolvedPath)
                }

                else {
                    [void]$knowledgeWarnings.Add("$clientId/$agentId : knowledge '$k' nao resolve em arquivo ($resolvedPath) - omitido")
                }

            }

            if ($hasGraph -and (-not ($knowledgeLines -contains $graphReport))) {
                [void]$knowledgeLines.Add($graphReport)
            }

            # dedupe primeiro (comparacao entre caminhos absolutos), depois torna PORTAVEL - o
            # que vai pro arquivo gerado e o caminho relativo a $RepoRoot quando o alvo mora dentro
            # dele. Um ponto so, valendo para os tres modos.
            $knowledgeLines = @($knowledgeLines | Select-Object -Unique | ForEach-Object { ConvertTo-PortablePath $_ })

 # ---- entry_point / grounding resolvidos e tornados portaveis (mesma regra acima) ----
 $entryPointPath = ''
 if ($entryPointRaw) {
 $entryPointFull = Join-Path $squadDir $entryPointRaw
 $entryPointPath = if (Test-Path $entryPointFull) { ConvertTo-PortablePath $entryPointFull } else { $entryPointRaw }
}

 $groundingPath = ''
 if ($groundingRaw) {
 $groundingFull = Join-Path $clientDir.FullName $groundingRaw
 $groundingPath = if (Test-Path $groundingFull) { ConvertTo-PortablePath $groundingFull } else { $groundingRaw }
}

            $name = ("$clientId-$agentId").ToLower()

            # ---- monta o arquivo (por modo) ----
            $sections = New-Object System.Collections.ArrayList

            if ($Mode -eq 'spawn') {

                [void]$sections.Add('---')
                [void]$sections.Add("name: $name")
                [void]$sections.Add("description: $description")
                [void]$sections.Add("tools: $toolsLine")
                [void]$sections.Add("model: $model")

                [void]$sections.Add('---')
                [void]$sections.Add('')
                [void]$sections.Add($body.Trim())
                [void]$sections.Add('')
 foreach ($bl in (New-BeforeActingBlock -Camada $camada -EntryPointPath $entryPointPath -GroundingPath $groundingPath -KnowledgeLines $knowledgeLines -BudgetToolCalls $budgetToolCalls -OutputMaxLines $outputMaxLines -EvidenceTags $evidenceTags -AuthorityDecides $authorityDecides -AuthorityEscalatesTo $authorityEscalatesTo)) { [void]$sections.Add($bl) }

                if ($camada -ne 'A') {
                    [void]$sections.Add('')
                    [void]$sections.Add('## Voce e folha')
                    [void]$sections.Add('')
                    [void]$sections.Add('Nao re-delegue e nao acione outro agente. Ao concluir, devolva Artifact (arquivo, path ou URL) e um resumo objetivo para quem acionou este agente.')
                }

            }

            elseif ($Mode -eq 'opencode') {
                # OpenCode tem sub-agente NATIVO, so que com outro frontmatter e outra pasta.
                # Traduz a mesma fonte unica para o vocabulario dele.
                $permEdit = if (($validTools -contains 'Edit') -or ($validTools -contains 'Write')) { 'allow' } else { 'deny' }
                $permBash = if ($validTools -contains 'Bash') { 'allow' } else { 'deny' }
                $permWeb = if (($validTools -contains 'WebFetch') -or ($validTools -contains 'WebSearch')) { 'allow' } else { 'deny' }

                # model SO quando a persona declara um id real de modelo (provider/modelo). Os
                # valores de TIER usados no yaml (strong/standard/fast) nao sao id de modelo em
                # host nenhum - escreve-los aqui geraria config invalida no OpenCode.
                $declaredModel = Get-ScalarValue $data 'model' ''

                [void]$sections.Add('---')
                [void]$sections.Add("description: $description")
                [void]$sections.Add('mode: subagent')
                if ($declaredModel -match '^[\w.-]+/[\w.:-]+$') {
                    [void]$sections.Add("model: $declaredModel")
                }

                [void]$sections.Add('permission:')
                [void]$sections.Add("  edit: $permEdit")
                [void]$sections.Add("  bash: $permBash")
                [void]$sections.Add("  webfetch: $permWeb")

                [void]$sections.Add('---')
                [void]$sections.Add('')
                [void]$sections.Add($body.Trim())
                [void]$sections.Add('')
                [void]$sections.Add('## Escopo de ferramentas declarado')
                [void]$sections.Add('')
                [void]$sections.Add("$toolsLine")
                [void]$sections.Add('')
 foreach ($bl in (New-BeforeActingBlock -Camada $camada -EntryPointPath $entryPointPath -GroundingPath $groundingPath -KnowledgeLines $knowledgeLines -BudgetToolCalls $budgetToolCalls -OutputMaxLines $outputMaxLines -EvidenceTags $evidenceTags -AuthorityDecides $authorityDecides -AuthorityEscalatesTo $authorityEscalatesTo)) { [void]$sections.Add($bl) }

                if ($camada -ne 'A') {
                    [void]$sections.Add('')
                    [void]$sections.Add('## Voce e folha')
                    [void]$sections.Add('')
                    [void]$sections.Add('Nao re-delegue e nao acione outro agente. Ao concluir, devolva Artifact (arquivo, path ou URL) e um resumo objetivo para quem acionou este agente.')
                }

            }

            else {
                # context-load (OPP-42): briefing portavel, sem frontmatter de Claude Code -
                # nenhum outro host le YAML de agente. O coordenador le isto inteiro e VESTE a
                # persona, produz a entrega, depois descarrega e volta a coordenar.
                [void]$sections.Add("# CONTEXT-LOAD BUNDLE - $name")
                [void]$sections.Add('# Modo: context-load (OPP-42, delegacao portavel) - para host sem sub-agente nativo')
                [void]$sections.Add("# Gerado de: clients\$clientId\squad\squad.yaml + agents\$agentId.yaml + agents\$agentId.md")
                [void]$sections.Add('')
                [void]$sections.Add('## Identidade')
                [void]$sections.Add('')
                [void]$sections.Add("Specialist: $role ($clientId/$agentId)")
                [void]$sections.Add("Camada: $camada")
                [void]$sections.Add('')
                [void]$sections.Add('## Escopo de ferramentas declarado')
                [void]$sections.Add('')
                [void]$sections.Add("$toolsLine")
                [void]$sections.Add('')
                [void]$sections.Add('Vestir este chapeu NAO amplia acesso alem desta lista - e o mesmo escopo do modo spawn.')
                [void]$sections.Add('')
                [void]$sections.Add('## Persona (vista este chapeu)')
                [void]$sections.Add('')
                [void]$sections.Add($body.Trim())
                [void]$sections.Add('')
                [void]$sections.Add('## Knowledge a carregar antes de produzir')
                [void]$sections.Add('')
                if ($knowledgeLines.Count -eq 0) {
                    [void]$sections.Add('- (nenhum knowledge declarado no yaml deste agente)')
                }

                else {
                    foreach ($kl in $knowledgeLines) { [void]$sections.Add("- $kl") }
                }

                [void]$sections.Add('')
                [void]$sections.Add('## Regra de folha (context-load)')
                [void]$sections.Add('')
                [void]$sections.Add('Nao invoque outro Specialist dentro deste contexto. Produza a entrega com o Artifact')
                [void]$sections.Add('esperado, DESCARREGUE este bloco e retome a coordenacao - o Quality Gate roda depois,')
                [void]$sections.Add('fora do chapeu, exatamente como no modo spawn.')
            }

            $finalContent = ($sections -join "`n").TrimEnd() + "`n"

            $fileSuffix = if ($Mode -eq 'context-load') { '.context-load.md' } else { '.md' }
            $outPath = Join-Path $outDir "$name$fileSuffix"
            $isNew = -not (Test-Path $outPath)
            $writeNeeded = $true
            if (-not $isNew) {
                $existing = Get-Content -Path $outPath -Raw -Encoding UTF8
                if ($existing -eq $finalContent) { $writeNeeded = $false }
            }

            if ($writeNeeded) {
                if ($DryRun) {
                    if ($isNew) { Write-Host "[DRYRUN] geraria: $outPath" }
                    else { Write-Host "[DRYRUN] atualizaria: $outPath" }
                }

                else {
                    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
                    [System.IO.File]::WriteAllText($outPath, $finalContent, $utf8NoBom)
                }

                if ($isNew) { $generated++ } else { $updated++ }
            }

            else {
                $unchanged++
            }

            [void]$reportLines.Add("$clientId/$agentId -> $name$fileSuffix (camada $camada, model $model, modo $Mode)")
        }

        catch {
            Write-Warning "[$clientId/$agentId] erro: $($_.Exception.Message)"
            $errors++
        }

    }

}

Write-Host ''
Write-Host "=== squad-bridge: resumo (modo $Mode) ==="
Write-Host "gerados:    $generated"
Write-Host "atualizados: $updated"
Write-Host "inalterados: $unchanged"
Write-Host "erros:      $errors"
if ($knowledgeWarnings.Count -gt 0) {

    Write-Host ''
    Write-Host "knowledge omitido (nao resolveu em arquivo real):"
    foreach ($kw in $knowledgeWarnings) { Write-Host "  - $kw" }
}
if ($camadaWarnings.Count -gt 0) {

    Write-Host ''
    Write-Host "camada: fonte ambigua ou indeterminavel (CONFIRA - fail-loud, nao assumido em silencio):"
    foreach ($cw in $camadaWarnings) { Write-Host "  - $cw" }
}
if ($mcpWarnings.Count -gt 0) {

    Write-Host ''
    Write-Host "tools MCP corrigidas ou descartadas:"
    foreach ($mw in $mcpWarnings) { Write-Host "  - $mw" }
}

Write-Host ''
foreach ($rl in $reportLines) { Write-Host $rl }
