<#
  validate-workflow.ps1 - o teste que libera a camada de execucao (squad-bridge.ps1).

  Problema que resolve: squad-bridge.ps1 gera 47 especialistas acionaveis (modo spawn, para
  .claude\agents\) e 47 briefings portateis (modo context-load, .context-load.md). Nada disso
  foi validado ponta a ponta - "criado" nao e "provado". Este script roda SEM agente nenhum e
  confere, item por item, se a ponte entre squad.yaml (fonte) e os dois formatos gerados esta
  correta, coerente com state.json e idempotente.

  NAO prova o modo spawn (subagente nativo do Claude Code): o harness so le .claude\agents\ na
  ABERTURA da sessao, e este script roda dentro da sessao que gerou/edita os arquivos. Essa prova
  fica para uma sessao nova (ver docs\TESTE-DE-LIBERACAO.md).

  Checks:
    1. Pareamento squad.yaml <-> .claude\agents\ (spawn .md e .context-load.md), nos dois sentidos
       (todo id do squad.yaml tem os dois arquivos; todo arquivo gerado tem id de origem).
    2. Frontmatter do spawn: linha 1 = "---", name/description/tools/model preenchidos, name
       unico no projeto todo.
    3. Camada B/C (folha) nunca carrega Agent ou Task nas tools.
    4. Todo caminho de conhecimento citado nos briefings (spawn e context-load) existe em disco.
    5. Toda tool mcp__servidor__* citada corresponde a um servidor real em .mcp.json.
    6. state.json parseia e cada Client com squad.yaml aparece em clients[] com gateway e
       specialists batendo com squad.yaml (specialists = todos os ids do squad.yaml exceto o
       gateway).
    7. squad-bridge.ps1 -DryRun (spawn e context-load) nao aponta gerados/atualizados pendentes -
       prova que o gerado bate com a fonte agora.

  Exit 0 = tudo passou. Exit 1 = pelo menos um FAIL. Erro num item nao derruba o resto (try/catch
  por item/agente). -Verbose lista cada checagem individual, nao so o resumo.

  Português correto, com acentos. Arquivo salvo em UTF-8 sem BOM; o único erro é caractere corrompido. Emoji continua fora de peça pública.
#>

[CmdletBinding()]
param(
    [string]$RepoRoot
)

$ErrorActionPreference = 'Stop'

if (-not $RepoRoot) {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
}

$clientsDir = Join-Path $RepoRoot 'clients'
$agentsDir = Join-Path $RepoRoot '.claude\agents'
$mcpConfigPath = Join-Path $RepoRoot '.mcp.json'
$statePath = Join-Path $RepoRoot 'state.json'
$bridgeScript = Join-Path $RepoRoot 'scripts\squad-bridge.ps1'

$isVerbose = [bool]$PSBoundParameters['Verbose']

$results = New-Object System.Collections.ArrayList
$passCount = 0
$failCount = 0

function Add-Result {
    param(
        [Parameter(Mandatory = $true)][string]$Category,
        [Parameter(Mandatory = $true)][ValidateSet('PASS', 'FAIL')][string]$Verdict,
        [Parameter(Mandatory = $true)][string]$Detail
    )
    $script:results.Add([pscustomobject]@{ Category = $Category; Verdict = $Verdict; Detail = $Detail }) | Out-Null
    if ($Verdict -eq 'PASS') { $script:passCount++ } else { $script:failCount++ }
    if ($Verdict -eq 'FAIL' -or $isVerbose) {
        $color = if ($Verdict -eq 'PASS') { 'Green' } else { 'Red' }
        Write-Host "[$Verdict] $Category - $Detail" -ForegroundColor $color
    }
}

function Read-SimpleYamlIds {
    # le so os ids de topo de lista ("- id: xxx") de um squad.yaml, na ordem do arquivo
    param([Parameter(Mandatory = $true)][string]$Path)
    $ids = New-Object System.Collections.ArrayList
    $lines = Get-Content -Path $Path -Encoding UTF8
    foreach ($line in $lines) {
        if ($line -match '^\s*-\s*id:\s*([^\s#]+)') {
            [void]$ids.Add($Matches[1].Trim())
        }
    }
    return @($ids)
}

function Get-SquadGateway {
    # aceita as tres formas medidas no parque: "gateway: <id>" de topo (studio.example/acme-saas),
    # "gateway: true" por membro e "squad: { owner: <id> }" aninhado (tambem acme-saas).
    # Mesma precedencia usada por Read-SquadYamlInfo em scripts\squad-bridge.ps1 - manter em sincronia.
    param([Parameter(Mandatory = $true)][string]$Path)
    $lines = Get-Content -Path $Path -Encoding UTF8
    $curId = $null
    $topGateway = $null
    $memberGateway = $null
    $owner = $null
    $inSquadBlock = $false
    foreach ($line in $lines) {
        if ($line -match '^squad:\s*$') { $inSquadBlock = $true; continue }
        if ($inSquadBlock) {
            if ($line -match '^\S') { $inSquadBlock = $false }
            elseif ($line -match '^\s+owner:\s*([^\s#]+)') { $owner = $Matches[1].Trim() }
        }
        if ($line -match '^gateway:\s*([^\s#]+)') { $topGateway = $Matches[1].Trim(); continue }
        if ($line -match '^\s*-\s*id:\s*([^\s#]+)') { $curId = $Matches[1].Trim(); continue }
        if ($curId -and ($line -match '^\s*gateway:\s*true\s*$')) { $memberGateway = $curId }
    }
    if ($topGateway) { return $topGateway }
    if ($memberGateway) { return $memberGateway }
    if ($owner) { return $owner }
    return $null
}

Write-Host "=== validate-workflow: validando a ponte squad.yaml -> .claude\agents\ ==="
Write-Host "repo: $RepoRoot"
Write-Host ""

# ---- CHECK 5 (setup): servidores MCP reais declarados em .mcp.json - precisa vir ANTES do loop
# principal porque o check de tools mcp__* (dentro do loop de Clients) depende desta lista ----
$script:mcpServers = @()
try {
    if (-not (Test-Path $mcpConfigPath)) {
        Add-Result -Category 'mcp-config' -Verdict 'FAIL' -Detail ".mcp.json nao existe em $mcpConfigPath - nenhuma tool mcp__ pode ser validada"
    }
    else {
        $mcpJson = Get-Content -Path $mcpConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($mcpJson.mcpServers) {
            $script:mcpServers = @($mcpJson.mcpServers.PSObject.Properties.Name)
        }
        Add-Result -Category 'mcp-config' -Verdict 'PASS' -Detail ".mcp.json parseou - servidores declarados: $($script:mcpServers -join ', ')"
    }
}
catch {
    Add-Result -Category 'mcp-config' -Verdict 'FAIL' -Detail ".mcp.json nao parseia - $($_.Exception.Message)"
}

# ---- descobre os Clients com squad.yaml (a fonte) ----
$squadClients = New-Object System.Collections.ArrayList
if (Test-Path $clientsDir) {
    $clientDirs = Get-ChildItem -Path $clientsDir -Directory
    foreach ($cd in $clientDirs) {
        $squadYaml = Join-Path $cd.FullName 'squad\squad.yaml'
        if (Test-Path $squadYaml) {
            [void]$squadClients.Add([pscustomobject]@{ Id = $cd.Name; SquadYaml = $squadYaml })
        }
    }
}
else {
    Add-Result -Category 'setup' -Verdict 'FAIL' -Detail "clients dir nao existe: $clientsDir"
}

# ============================================================
# CHECK 1 + 2 + 3: pareamento, frontmatter, folha sem re-delegacao
# ============================================================
$allSpawnNames = @{}   # name -> lista de arquivos que declaram esse name (deteccao de duplicata)
$knownGeneratedFiles = New-Object System.Collections.ArrayList  # todos os basenames esperados (para o check de orfao reverso)

foreach ($sc in $squadClients) {
    $clientId = $sc.Id
    try {
        $ids = Read-SimpleYamlIds -Path $sc.SquadYaml
        $gateway = Get-SquadGateway -Path $sc.SquadYaml

        if ($ids.Count -eq 0) {
            Add-Result -Category 'pareamento' -Verdict 'FAIL' -Detail "$clientId : squad.yaml sem nenhum '- id:' (parser ou fonte quebrada)"
            continue
        }

        foreach ($id in $ids) {
            $name = ("$clientId-$id").ToLower()
            $spawnPath = Join-Path $agentsDir "$name.md"
            $contextPath = Join-Path $agentsDir "$name.context-load.md"
            [void]$knownGeneratedFiles.Add("$name.md")
            [void]$knownGeneratedFiles.Add("$name.context-load.md")

            $agentYaml = Join-Path $clientsDir "$clientId\squad\agents\$id.yaml"
            $agentMd = Join-Path $clientsDir "$clientId\squad\agents\$id.md"
            if (-not (Test-Path $agentYaml) -or -not (Test-Path $agentMd)) {
                Add-Result -Category 'pareamento' -Verdict 'FAIL' -Detail "$clientId/$id : fonte incompleta (falta agents\$id.yaml ou agents\$id.md) - squad-bridge nao consegue gerar este par"
                continue
            }

            # --- pareamento (check 1): os dois arquivos gerados existem ---
            if (-not (Test-Path $spawnPath)) {
                Add-Result -Category 'pareamento' -Verdict 'FAIL' -Detail "$clientId/$id : falta o par spawn ($name.md) em .claude\agents\"
            }
            else {
                Add-Result -Category 'pareamento' -Verdict 'PASS' -Detail "$clientId/$id : spawn $name.md existe"
            }
            if (-not (Test-Path $contextPath)) {
                Add-Result -Category 'pareamento' -Verdict 'FAIL' -Detail "$clientId/$id : falta o par portavel ($name.context-load.md) em .claude\agents\"
            }
            else {
                Add-Result -Category 'pareamento' -Verdict 'PASS' -Detail "$clientId/$id : portavel $name.context-load.md existe"
            }

            # --- frontmatter do spawn (check 2) ---
            if (Test-Path $spawnPath) {
                try {
                    $lines = Get-Content -Path $spawnPath -Encoding UTF8
                    if ($lines.Count -eq 0 -or $lines[0].Trim() -ne '---') {
                        Add-Result -Category 'frontmatter' -Verdict 'FAIL' -Detail "$name : linha 1 nao e '---'"
                    }
                    else {
                        $closeIdx = -1
                        for ($i = 1; $i -lt $lines.Count; $i++) {
                            if ($lines[$i].Trim() -eq '---') { $closeIdx = $i; break }
                        }
                        if ($closeIdx -lt 0) {
                            Add-Result -Category 'frontmatter' -Verdict 'FAIL' -Detail "$name : frontmatter nunca fecha com '---'"
                        }
                        else {
                            $fm = @{}
                            for ($i = 1; $i -lt $closeIdx; $i++) {
                                if ($lines[$i] -match '^(\w[\w-]*):\s*(.*)$') {
                                    $fm[$Matches[1]] = $Matches[2].Trim()
                                }
                            }
                            $required = @('name', 'description', 'tools', 'model')
                            $missing = @($required | Where-Object { -not $fm.ContainsKey($_) -or [string]::IsNullOrWhiteSpace($fm[$_]) })
                            if ($missing.Count -gt 0) {
                                Add-Result -Category 'frontmatter' -Verdict 'FAIL' -Detail "$name : campo(s) vazio(s)/ausente(s): $($missing -join ', ')"
                            }
                            else {
                                Add-Result -Category 'frontmatter' -Verdict 'PASS' -Detail "$name : name/description/tools/model preenchidos"
                            }

                            if ($fm.ContainsKey('name')) {
                                $fmName = $fm['name']
                                if (-not $allSpawnNames.ContainsKey($fmName)) { $allSpawnNames[$fmName] = New-Object System.Collections.ArrayList }
                                [void]$allSpawnNames[$fmName].Add($name)
                            }

                            # --- check 3: camada B/C nao carrega Agent nem Task ---
                            $model = if ($fm.ContainsKey('model')) { $fm['model'] } else { '' }
                            $toolsLine = if ($fm.ContainsKey('tools')) { $fm['tools'] } else { '' }
                            $toolsList = @($toolsLine -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
                            if ($model -ne 'opus') {
                                $bad = @($toolsList | Where-Object { $_ -eq 'Task' -or $_ -eq 'Agent' })
                                if ($bad.Count -gt 0) {
                                    Add-Result -Category 'folha-sem-delegar' -Verdict 'FAIL' -Detail "$name : camada nao-A (model=$model) carrega $($bad -join ', ') - folha nao pode re-delegar"
                                }
                                else {
                                    Add-Result -Category 'folha-sem-delegar' -Verdict 'PASS' -Detail "$name : sem Task/Agent (model=$model)"
                                }
                            }

                            # --- check novo: o Gateway declarado em squad.yaml TEM que ter Task e
                            # model forte - a outra metade do check 3 que faltava (defeito medido:
                            # so se confirmava que camada B/C NAO tinha Task, nunca que a camada A
                            # TINHA - por isso um lider sem Task passava batido) ---
                            if ($gateway -and $id -eq $gateway) {
                                if ($model -ne 'opus') {
                                    Add-Result -Category 'gateway-forte' -Verdict 'FAIL' -Detail "$name : e o Gateway declarado em squad.yaml mas model='$model' (esperado opus/camada A)"
                                }
                                else {
                                    Add-Result -Category 'gateway-forte' -Verdict 'PASS' -Detail "$name : Gateway com model opus (camada A)"
                                }
                                if ($toolsList -notcontains 'Task') {
                                    Add-Result -Category 'gateway-com-task' -Verdict 'FAIL' -Detail "$name : e o Gateway declarado em squad.yaml mas NAO tem Task nas tools - lider que nao pode liderar"
                                }
                                else {
                                    Add-Result -Category 'gateway-com-task' -Verdict 'PASS' -Detail "$name : Gateway com Task nas tools"
                                }
                            }

                            # --- check 5: mcp__ tools contra .mcp.json (feito aqui, ja tenho a lista de tools) ---
                            $mcpTools = @($toolsList | Where-Object { $_ -like 'mcp__*' })
                            foreach ($mt in $mcpTools) {
                                $parts = $mt -split '__', 3
                                if ($parts.Count -lt 3 -or $parts[0] -ne 'mcp') {
                                    Add-Result -Category 'mcp-tools' -Verdict 'FAIL' -Detail "$name : tool '$mt' fora do formato mcp__servidor__ferramenta"
                                    continue
                                }
                                $server = $parts[1]
                                if ($script:mcpServers -contains $server) {
                                    Add-Result -Category 'mcp-tools' -Verdict 'PASS' -Detail "$name : '$mt' -> servidor '$server' declarado em .mcp.json"
                                }
                                else {
                                    Add-Result -Category 'mcp-tools' -Verdict 'FAIL' -Detail "$name : tool '$mt' - servidor '$server' NAO esta em .mcp.json"
                                }
                            }
                        }
                    }
                }
                catch {
                    Add-Result -Category 'frontmatter' -Verdict 'FAIL' -Detail "$name : erro lendo/parseando arquivo - $($_.Exception.Message)"
                }
            }

            # --- check 4: caminhos de knowledge citados existem em disco (spawn e context-load) ---
            foreach ($pair in @(@{Path = $spawnPath; Mode = 'spawn'; Marker = '## Antes de agir, carregue' }, @{Path = $contextPath; Mode = 'context-load'; Marker = '## Knowledge a carregar' })) {
                if (-not (Test-Path $pair.Path)) { continue }
                try {
                    $content = Get-Content -Path $pair.Path -Encoding UTF8
                    $inSection = $false
                    $foundAny = $false
                    foreach ($ln in $content) {
                        if ($ln.Trim() -eq $pair.Marker) { $inSection = $true; continue }
                        if ($inSection -and $ln -match '^##\s') { $inSection = $false; continue }
                        if ($inSection -and $ln -match '^-\s+(.+)$') {
                            $kpath = $Matches[1].Trim()
                            if ($kpath -match '^\(nenhum knowledge') { continue }
                            $foundAny = $true
                            if (Test-Path $kpath) {
                                Add-Result -Category 'knowledge-existe' -Verdict 'PASS' -Detail "$name ($($pair.Mode)) : $kpath existe"
                            }
                            else {
                                Add-Result -Category 'knowledge-existe' -Verdict 'FAIL' -Detail "$name ($($pair.Mode)) : $kpath NAO existe em disco - especialista cego"
                            }
                        }
                    }
                }
                catch {
                    Add-Result -Category 'knowledge-existe' -Verdict 'FAIL' -Detail "$($pair.Path) : erro lendo secao de knowledge - $($_.Exception.Message)"
                }
            }
        }

        # --- reverso do check 1: todo par gerado do prefixo deste Client tem id de origem ---
        $prefix = "$clientId-"
        $existingForClient = @(Get-ChildItem -Path $agentsDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$prefix*" })
        foreach ($ef in $existingForClient) {
            $base = $ef.Name -replace '\.context-load\.md$', '' -replace '\.md$', ''
            $expectedId = $base.Substring($prefix.Length)
            if ($ids -notcontains $expectedId) {
                Add-Result -Category 'pareamento' -Verdict 'FAIL' -Detail "$($ef.Name) : orfao - id '$expectedId' nao existe em $clientId/squad.yaml"
            }
        }
    }
    catch {
        Add-Result -Category 'pareamento' -Verdict 'FAIL' -Detail "$clientId : erro processando squad.yaml - $($_.Exception.Message)"
    }
}

# --- reverso global do check 1: arquivo em .claude\agents\ com prefixo de um Client SEM squad.yaml sao orfaos tambem, mas isso ja e coberto acima por Client; aqui so confere que nao sobrou lixo fora de qualquer prefixo de Client conhecido ---
try {
    if (Test-Path $agentsDir) {
        $allGenerated = @(Get-ChildItem -Path $agentsDir -File | Select-Object -ExpandProperty Name)
        $knownClientIds = @($squadClients | Select-Object -ExpandProperty Id)
        $unmatched = @($allGenerated | Where-Object {
                $f = $_
                -not ($knownClientIds | Where-Object { $f -like "$_-*" })
            })
        if ($unmatched.Count -gt 0) {
            foreach ($u in $unmatched) {
                Add-Result -Category 'pareamento' -Verdict 'FAIL' -Detail "$u : nao pertence a nenhum Client com squad.yaml conhecido - lixo em .claude\agents\"
            }
        }
        else {
            Add-Result -Category 'pareamento' -Verdict 'PASS' -Detail "nenhum arquivo em .claude\agents\ fora dos prefixos de Client conhecidos"
        }
    }
}
catch {
    Add-Result -Category 'pareamento' -Verdict 'FAIL' -Detail "varredura reversa de .claude\agents\ falhou - $($_.Exception.Message)"
}

# ============================================================
# CHECK 2b: name unico no projeto todo
# ============================================================
try {
    $dupNames = @($allSpawnNames.Keys | Where-Object { $allSpawnNames[$_].Count -gt 1 })
    if ($dupNames.Count -gt 0) {
        foreach ($dn in $dupNames) {
            Add-Result -Category 'name-unico' -Verdict 'FAIL' -Detail "name '$dn' duplicado em: $($allSpawnNames[$dn] -join ', ')"
        }
    }
    else {
        Add-Result -Category 'name-unico' -Verdict 'PASS' -Detail "$($allSpawnNames.Keys.Count) names, todos unicos no projeto"
    }
}
catch {
    Add-Result -Category 'name-unico' -Verdict 'FAIL' -Detail "erro checando unicidade de name - $($_.Exception.Message)"
}

# ============================================================
# CHECK 6: state.json parseia e bate com squad.yaml
# ============================================================
try {
    if (-not (Test-Path $statePath)) {
        Add-Result -Category 'state-json' -Verdict 'FAIL' -Detail "state.json nao existe em $statePath"
    }
    else {
        $stateRaw = Get-Content -Path $statePath -Raw -Encoding UTF8
        $stateObj = $stateRaw | ConvertFrom-Json
        Add-Result -Category 'state-json' -Verdict 'PASS' -Detail "state.json parseou (JSON valido)"

        $stateClients = @()
        if ($stateObj.clients) { $stateClients = @($stateObj.clients) }

        foreach ($sc in $squadClients) {
            $clientId = $sc.Id
            try {
                $ids = Read-SimpleYamlIds -Path $sc.SquadYaml
                $gateway = Get-SquadGateway -Path $sc.SquadYaml
                $expectedSpecialists = @($ids | Where-Object { $_ -ne $gateway })

                $stateEntry = $stateClients | Where-Object { $_.id -eq $clientId } | Select-Object -First 1
                if (-not $stateEntry) {
                    Add-Result -Category 'state-json' -Verdict 'FAIL' -Detail "$clientId : tem squad.yaml mas NAO aparece em state.json clients[]"
                    continue
                }

                $stateGateway = $stateEntry.squad.gateway
                if ($stateGateway -ne $gateway) {
                    Add-Result -Category 'state-json' -Verdict 'FAIL' -Detail "$clientId : gateway diverge (state.json='$stateGateway' vs squad.yaml='$gateway')"
                }
                else {
                    Add-Result -Category 'state-json' -Verdict 'PASS' -Detail "$clientId : gateway bate ('$gateway')"
                }

                $stateSpecialists = @()
                if ($stateEntry.squad.specialists) { $stateSpecialists = @($stateEntry.squad.specialists) }

                $missingInState = @($expectedSpecialists | Where-Object { $stateSpecialists -notcontains $_ })
                $extraInState = @($stateSpecialists | Where-Object { $expectedSpecialists -notcontains $_ })

                if ($missingInState.Count -eq 0 -and $extraInState.Count -eq 0) {
                    Add-Result -Category 'state-json' -Verdict 'PASS' -Detail "$clientId : specialists bate com squad.yaml ($($expectedSpecialists.Count) itens)"
                }
                else {
                    $detailParts = New-Object System.Collections.ArrayList
                    if ($missingInState.Count -gt 0) { [void]$detailParts.Add("faltam em state.json: $($missingInState -join ', ')") }
                    if ($extraInState.Count -gt 0) { [void]$detailParts.Add("sobram em state.json (nao existem no squad.yaml): $($extraInState -join ', ')") }
                    Add-Result -Category 'state-json' -Verdict 'FAIL' -Detail "$clientId : specialists diverge - $($detailParts -join ' | ')"
                }
            }
            catch {
                Add-Result -Category 'state-json' -Verdict 'FAIL' -Detail "$clientId : erro comparando com state.json - $($_.Exception.Message)"
            }
        }
    }
}
catch {
    Add-Result -Category 'state-json' -Verdict 'FAIL' -Detail "state.json nao parseia como JSON - $($_.Exception.Message)"
}

# ============================================================
# CHECK 7: squad-bridge.ps1 -DryRun idempotente (spawn e context-load)
# ============================================================
foreach ($mode in @('spawn', 'context-load')) {
    try {
        if (-not (Test-Path $bridgeScript)) {
            Add-Result -Category 'idempotencia' -Verdict 'FAIL' -Detail "scripts\squad-bridge.ps1 nao existe - nao consigo provar idempotencia"
            continue
        }
        $output = & $bridgeScript -DryRun -Mode $mode -RepoRoot $RepoRoot *>&1 | Out-String
        $genMatch = [regex]::Match($output, 'gerados:\s*(\d+)')
        $updMatch = [regex]::Match($output, 'atualizados:\s*(\d+)')
        if (-not $genMatch.Success -or -not $updMatch.Success) {
            Add-Result -Category 'idempotencia' -Verdict 'FAIL' -Detail "modo $mode : nao consegui ler o resumo da saida do squad-bridge.ps1 -DryRun"
            continue
        }
        $gerados = [int]$genMatch.Groups[1].Value
        $atualizados = [int]$updMatch.Groups[1].Value
        if ($gerados -eq 0 -and $atualizados -eq 0) {
            Add-Result -Category 'idempotencia' -Verdict 'PASS' -Detail "modo $mode : -DryRun mostra 0 gerados / 0 atualizados (gerado bate com a fonte)"
        }
        else {
            Add-Result -Category 'idempotencia' -Verdict 'FAIL' -Detail "modo $mode : -DryRun aponta $gerados gerados / $atualizados atualizados pendentes - fonte mudou e ninguem regerou (rode: scripts\squad-bridge.ps1 -Mode $mode)"
        }
    }
    catch {
        Add-Result -Category 'idempotencia' -Verdict 'FAIL' -Detail "modo $mode : erro rodando squad-bridge.ps1 -DryRun - $($_.Exception.Message)"
    }
}

# ============================================================
# resumo final
# ============================================================
Write-Host ""
Write-Host "=== resumo por categoria ==="
$byCategory = $results | Group-Object -Property Category
foreach ($g in $byCategory) {
    $p = @($g.Group | Where-Object { $_.Verdict -eq 'PASS' }).Count
    $f = @($g.Group | Where-Object { $_.Verdict -eq 'FAIL' }).Count
    $mark = if ($f -eq 0) { 'OK' } else { 'FAIL' }
    Write-Host ("  [{0,-4}] {1,-20} PASS={2} FAIL={3}" -f $mark, $g.Name, $p, $f)
}

Write-Host ""
Write-Host "=== veredito final ==="
Write-Host "PASS: $passCount"
Write-Host "FAIL: $failCount"

if ($failCount -gt 0) {
    Write-Host ""
    Write-Host "FALHOU. Itens em FAIL:"
    foreach ($r in ($results | Where-Object { $_.Verdict -eq 'FAIL' })) {
        Write-Host "  - [$($r.Category)] $($r.Detail)"
    }
    exit 1
}
else {
    Write-Host ""
    Write-Host "TUDO PASSOU."
    exit 0
}
