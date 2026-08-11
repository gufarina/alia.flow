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

  -Mode context-load - host SEM sub-agente (ex: Codex, opencode): escreve
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
    [ValidateSet('spawn', 'context-load')]
    [string]$Mode = 'spawn'
)

$ErrorActionPreference = 'Stop'

if (-not $RepoRoot) {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
}

$clientsDir = Join-Path $RepoRoot 'clients'
$outDir = Join-Path $RepoRoot '.claude\agents'

if (-not (Test-Path $clientsDir)) {
    Write-Error "nao achei $clientsDir"
    exit 1
}

if (-not (Test-Path $outDir)) {
    if (-not $DryRun) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }
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
                $camada = $squadInfo.Camadas[$agentId]
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
            $knowledgeLines = @($knowledgeLines | Select-Object -Unique)

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
                [void]$sections.Add('## Antes de agir, carregue (obrigatorio)')
                [void]$sections.Add('')
                if ($knowledgeLines.Count -eq 0) {
                    [void]$sections.Add('- (nenhum knowledge declarado no yaml deste agente)')
                }
                else {
                    foreach ($kl in $knowledgeLines) { [void]$sections.Add("- $kl") }
                }

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

            $fileSuffix = if ($Mode -eq 'spawn') { '.md' } else { '.context-load.md' }
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
