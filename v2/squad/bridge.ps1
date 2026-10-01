<#
  bridge.ps1 - NUCLEO unico da ponte persona -> agente invocavel.

  Fonte unica: clients\<id>\squad\agents\<id>.{md,yaml} (+ squad.yaml) e os 3 macro em
  engine\macro\agents\{leitor,prova,texto}.{md,yaml}. Nada de saida e editado a mao.

  O nucleo le a fonte, valida o contrato, aplica a regra "persona sem fantasia" e monta UM objeto
  neutro por agente. Cada saida e um modulo pequeno em v2\squad\targets\<alvo>.ps1 que devolve
  @{ Name; Render = {param($a,$ctx)}; Clean = {param($ctx,$clientIds)} }. O nucleo nao conhece
  formato de host. Alvo novo = arquivo novo.

    -Target claude        .claude\agents\<client>-<id>.md           (padrao)
    -Target opencode      .opencode\agent\<client>-<id>.md
    -Target pi            .alia\pi\<client>-<id>.system.md + .json  (o Pi nao tem pasta de agentes)
    -Target context-load  .claude\agents\<client>-<id>.context-load.md (host sem sub-agente)

  Roster da sessao = 3 macro + o Client ativo: `-Only <client>` gera o Client mais os macro;
  `-Only <client> -Prune` ainda remove do .claude\agents o que nao e do Client, nem macro, nem
  de -Keep. A reserva .claude\squads NAO existe mais: v2\bin\client.py use chama este script.

  Todo bundle termina com `<!-- source_hash: <16 hex> -->` = sha256(md + yaml + squad.yaml)[0..15].
  Falha de contrato em um agente: throw, NENHUM modulo publica aquele agente.

  LIMITE: agente novo so vale na PROXIMA abertura de sessao do host.
  Idempotente (so regrava se o conteudo mudou). UTF-8 sem BOM. -DryRun so mostra.
#>
[CmdletBinding()]
param(
    [switch]$DryRun,
    [string]$Client,
    # alvo de geracao: Client, id do especialista ou bundle {client}-{id}. Client => inclui os macro.
    [string]$Only,
    # claude | opencode | pi | context-load; aceita "claude,pi" mesmo via -File (validado abaixo)
    [string[]]$Target = @('claude'),
    [string]$RepoRoot,
    [string]$MacroDir,
    [string]$ClaudeOut,
    [string]$OpenCodeOut,
    [string]$PiOut,
    # poda explicita (exige -Only <client existente>): tira de .claude\agents o que nao e do
    # Client, nem macro, nem de -Keep. Compara dono em minusculas (corrige _owner_of do client.py).
    [switch]$Prune,
    [string]$Keep = ''
)

$ErrorActionPreference = 'Stop'
$Target = @($Target | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
foreach ($t in $Target) {
    if ($t -notin @('claude', 'opencode', 'pi', 'context-load')) { Write-Error "alvo '$t' invalido (claude, opencode, pi, context-load)"; exit 1 }
}
if (-not $RepoRoot) { $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$RepoRootFull = ((Resolve-Path -LiteralPath $RepoRoot).Path).TrimEnd('\', '/')
if (-not $MacroDir) { $MacroDir = Join-Path $RepoRootFull 'engine\macro' }
if (-not $ClaudeOut) { $ClaudeOut = Join-Path $RepoRootFull '.claude\agents' }
if (-not $OpenCodeOut) { $OpenCodeOut = Join-Path $RepoRootFull '.opencode\agent' }
if (-not $PiOut) { $PiOut = Join-Path $RepoRootFull '.alia\pi' }
$clientsDir = Join-Path $RepoRootFull 'clients'
if (-not (Test-Path $clientsDir)) { Write-Error "nao achei $clientsDir"; exit 1 }

. (Join-Path $PSScriptRoot 'lib.ps1')

$ctx = @{
    RepoRoot = $RepoRootFull; DryRun = [bool]$DryRun
    Out      = @{ 'claude' = $ClaudeOut; 'context-load' = $ClaudeOut; 'opencode' = $OpenCodeOut; 'pi' = $PiOut }
}

# ---- modulos de saida ----
$targets = @{}
$missingTargets = New-Object System.Collections.ArrayList
foreach ($t in ($Target | Select-Object -Unique)) {
    $f = Join-Path $PSScriptRoot "targets\$t.ps1"
    if (-not (Test-Path -LiteralPath $f)) { [void]$missingTargets.Add($t); Write-Warning "modulo de saida ausente: $f - alvo '$t' pulado, os outros seguem"; continue }
    try { $targets[$t] = & $f } catch { [void]$missingTargets.Add($t); Write-Warning "modulo '$t' nao carregou: $($_.Exception.Message)" }
}

# ---- fontes: Clients + macro ----
$allClientIds = @(Get-ChildItem -Path $clientsDir -Directory | ForEach-Object { $_.Name })
if ($Client -and ($allClientIds -notcontains $Client)) { Write-Warning "cliente '$Client' nao encontrado em $clientsDir" }
$sources = New-Object System.Collections.ArrayList
foreach ($cid in $allClientIds) {
    if ($Client -and $cid -ne $Client) { continue }
    $sq = Join-Path $clientsDir "$cid\squad"
    if ((Test-Path (Join-Path $sq 'squad.yaml')) -and (Test-Path (Join-Path $sq 'agents'))) {
        [void]$sources.Add([pscustomobject]@{ Id = $cid; SquadDir = $sq; ClientDir = (Join-Path $clientsDir $cid); IsMacro = $false })
    }
}
$macroAgents = Join-Path $MacroDir 'agents'
$wantMacro = (Test-Path $macroAgents) -and ((-not $Only) -or ($Only -eq 'macro') -or ($allClientIds -contains $Only) -or ($Only -like 'macro-*') -or ($Client))
if ((Test-Path $macroAgents) -and $Only -and -not $wantMacro) {
    # -Only <id de especialista>: macro entra so se o id casar com um macro
    $wantMacro = [bool](Test-Path (Join-Path $macroAgents "$Only.yaml"))
}
if ($wantMacro) { [void]$sources.Add([pscustomobject]@{ Id = 'macro'; SquadDir = $MacroDir; ClientDir = $MacroDir; IsMacro = $true }) }

# ---- MCP real ----
$McpServers = @()
$mcpPath = Join-Path $RepoRootFull '.mcp.json'
if (Test-Path $mcpPath) {
    try { $mj = Get-Content -Path $mcpPath -Raw -Encoding UTF8 | ConvertFrom-Json; if ($mj.mcpServers) { $McpServers = @($mj.mcpServers.PSObject.Properties.Name) } }
    catch { Write-Warning "nao consegui ler $mcpPath : $($_.Exception.Message)" }
}
$ToolWhitelist = @('Read', 'Write', 'Edit', 'Grep', 'Glob', 'Bash', 'Task', 'WebFetch', 'WebSearch', 'NotebookEdit')

# ---- bloco operacional, neutro de host (antes de agir, checklist, orcamento, contrato, autoridade, folha) ----
function New-Operating {
    param($A, [bool]$NoTask)
    $l = New-Object System.Collections.ArrayList
    [void]$l.Add('## Antes de agir (obrigatorio, nesta ordem)'); [void]$l.Add('')
    $n = 1
    if ($A.IsMacro) {
        [void]$l.Add("$n. Leia o brief que a Alia montou (Client, objetivo, arquivos). Voce nao carrega conhecimento de Client: nao afirme nada fora do brief e dos arquivos citados."); $n++
    } else {
        if ($A.EntryPointPath) { [void]$l.Add("$n. Leia $($A.EntryPointPath) (uma linha por doc). Nunca um doc inteiro sem achar a linha dele."); $n++ }
        [void]$l.Add("$n. Ache a assinatura (titulo + primeiro paragrafo) antes de abrir o corpo."); $n++
        [void]$l.Add("$n. Abra so a fatia (secao) que responde a pergunta."); $n++
        if ($A.GroundingPath) { [void]$l.Add("$n. Antes de QUALQUER afirmacao sobre este Client, leia $($A.GroundingPath). Nao afirme por lembranca ou nome parecido."); $n++ }
        [void]$l.Add("$n. Se existir graphify-out/GRAPH_REPORT.md, leia God Nodes antes de Grep/Glob cego.")
    }
    [void]$l.Add(''); [void]$l.Add('docs disponiveis (abra pelo indice):'); [void]$l.Add('')
    if ($A.KnowledgeLines.Count -eq 0) { [void]$l.Add('- (nenhum knowledge declarado no yaml deste agente)') }
    else { foreach ($k in $A.KnowledgeLines) { [void]$l.Add("- $k") } }
    if ($A.Checklist.Count -gt 0) {
        [void]$l.Add(''); [void]$l.Add('## Checklist (confira antes de entregar)'); [void]$l.Add('')
        foreach ($c in $A.Checklist) { [void]$l.Add("- [ ] $c") }
    }
    if ($A.Camada -ne 'A') {
        [void]$l.Add(''); [void]$l.Add('## Orcamento'); [void]$l.Add('')
        [void]$l.Add("Maximo $($A.Budget) chamadas. Estourou, pare e entregue o que tem.")
    }
    $tl = @($A.Tags -replace '[\[\]]', '' -split ',\s*' | ForEach-Object { '[' + $_.Trim() + ']' })
    $tagTxt = if ($tl.Count -gt 1) { (($tl[0..($tl.Count - 2)]) -join ', ') + ' ou ' + $tl[-1] } else { $tl -join '' }
    [void]$l.Add(''); [void]$l.Add('## Contrato de saida'); [void]$l.Add('')
    [void]$l.Add("Maximo $($A.MaxLines) linhas. Cada fato leva um rotulo: $tagTxt."); [void]$l.Add('Afirmacao sem marca nao entra.')
    [void]$l.Add(''); [void]$l.Add('## Autoridade'); [void]$l.Add('')
    [void]$l.Add("Decide sozinho: $($A.Decides)."); [void]$l.Add("Escala para: $($A.Escalates).")
    if ($A.Camada -ne 'A') {
        [void]$l.Add(''); [void]$l.Add('## Voce e folha'); [void]$l.Add('')
        [void]$l.Add('Nao re-delegue e nao acione outro agente. Ao concluir, devolva Artifact (arquivo, path ou URL) e um resumo objetivo para quem acionou este agente.')
        if (-not $NoTask) {
            [void]$l.Add('')
            [void]$l.Add('Voce pode acionar apenas o leitor em massa (Explore em Haiku, molde em skills/leitura-em-massa/SKILL.md), no maximo 3 vezes; qualquer outra delegacao e bloqueada pelo motor.')
        }
    }
    return (($l -join "`n").TrimEnd())
}

# ---- resolve uma lista de knowledge para caminhos portaveis (valida contra o disco) ----
function Resolve-Knowledge {
    param($Src, [string[]]$Entries, [string[]]$Focus, [string]$Ctx, $Warn)
    $knowledgeDir = Join-Path $Src.SquadDir 'knowledge'
    $out = New-Object System.Collections.ArrayList
    $one = {
        param([string]$raw, [bool]$isFocus)
        $e = $raw.Trim(); if (-not $e) { return }
        if ($e -match '^(engine|skills|docs)/') {      # ativo do motor, relativo a raiz do repo
            $p = Join-Path $RepoRootFull ($e -replace '/', '\')
        } else {
            $e = $e -replace '^knowledge[\\/]', ''
            if ($e -notmatch '\.\w+$') { $e = "$e.md" }
            $p = Join-Path $knowledgeDir ($e -replace '/', '\')
        }
        if (Test-Path -LiteralPath $p) { [void]$out.Add($p) } else { [void]$Warn.Add("$Ctx : knowledge '$raw' nao resolve em arquivo ($p) - omitido") }
    }
    foreach ($k in $Entries) {
        $e = $k.Trim()
        if ($e -eq 'all' -or $e -eq 'shared' -or $e -match 'todo o knowledge') {
            if ($Focus.Count -gt 0) { foreach ($f in $Focus) { & $one $f $true } } else { [void]$out.Add($knowledgeDir) }
        } else { & $one $e $false }
    }
    $graph = Join-Path $knowledgeDir 'graphify-out\GRAPH_REPORT.md'
    if ((Test-Path $graph) -and ($out -notcontains $graph)) { [void]$out.Add($graph) }
    return @($out | Select-Object -Unique | ForEach-Object { ConvertTo-PortablePath $_ })
}

# ---- fonte -> objeto neutro (throw = nenhum modulo publica este agente) ----
function New-NeutralAgent {
    param($Src, [string]$AgentId, $Info, $McpWarn, $KnowWarn, $CamWarn)
    $agentsDir = Join-Path $Src.SquadDir 'agents'
    $yamlPath = Join-Path $agentsDir "$AgentId.yaml"; $mdPath = Join-Path $agentsDir "$AgentId.md"
    $cid = $Src.Id; $ctxName = "$cid/$AgentId"
    if (-not (Test-Path $mdPath)) { throw "falta $AgentId.md" }
    $data = Read-SimpleYaml -Path $yamlPath
    $role = Get-ScalarValue $data 'role' $AgentId
    $domain = Get-ScalarValue $data 'domain' ''

    $camada = Get-ScalarValue $data 'camada' ''
    if (-not $camada) { $camada = Get-ScalarValue $data 'layer' '' }
    if (-not $camada) {
        $tier = Get-ScalarValue $data 'tier' ''; if (-not $tier) { $tier = Get-ScalarValue $data 'model' '' }
        $camada = switch ($tier.ToLower()) { 'strong' { 'A' } 'standard' { 'B' } 'fast' { 'C' } default { '' } }
    }
    $camada = $camada.ToUpper()
    if ($Info.Camadas.ContainsKey($AgentId)) {
        if ($camada -and $camada -ne $Info.Camadas[$AgentId]) { [void]$CamWarn.Add("$ctxName : squad.yaml sobrescreve a camada '$camada' por '$($Info.Camadas[$AgentId])'") }
        $camada = $Info.Camadas[$AgentId]
    }
    if ($Info.GatewayId -and $Info.GatewayId -eq $AgentId) { $camada = 'A' }
    if ($camada -notin @('A', 'B', 'C')) { [void]$CamWarn.Add("$ctxName : camada '$camada' indeterminavel - assumido B, CONFIRA"); $camada = 'B' }

    $entryRaw = Get-ScalarValue $data 'entry_point' ''
    $budget = Get-ScalarValue $data 'tool_calls' ''
    $maxLines = Get-ScalarValue $data 'max_lines' ''
    $tags = Get-ScalarValue $data 'evidence_tags' ''
    $groundRaw = Get-ScalarValue $data 'grounding' ''
    $decides = Get-ScalarValue $data 'decides' ''
    $escal = Get-ScalarValue $data 'escalates_to' ''
    $knowEntries = Get-ListValue $data 'knowledge'
    $checklist = Get-ListValue $data 'checklist'
    $defBudget = if ($camada -eq 'C') { 8 } else { 20 }
    $defLines = switch ($camada) { 'C' { 25 } 'A' { 100 } default { 60 } }

    if ($knowEntries.Count -gt 0 -and -not $Src.IsMacro) {
        $map = Join-Path $Src.SquadDir 'knowledge\MAP.md'
        if (-not (Test-Path $map)) { throw "falta $map - rode: scripts/kb-index.ps1 -KnowledgePath `"$(Join-Path $Src.SquadDir 'knowledge')`"" }
        if (-not $entryRaw) { throw "falta 'entry_point' no yaml (obrigatorio quando knowledge[] nao vazio). Sugestao: entry_point: knowledge/MAP.md" }
    }
    if ($camada -ne 'A' -and -not $budget) { throw "falta 'budget.tool_calls' no yaml. Default sugerido para camada ${camada}: $defBudget" }
    if (-not $maxLines) { throw "falta 'output_contract.max_lines' no yaml. Sugestao para camada ${camada}: $defLines" }
    if (-not $tags) { throw "falta 'output_contract.evidence_tags' no yaml. Sugestao: [MEDIDO, LIDO, INFERIDO]" }
    if (-not $groundRaw) { throw "falta 'grounding' no yaml (macro: grounding: brief-da-alia; Client: grounding: client.md)" }
    if (-not $decides) { throw "falta 'authority.decides' no yaml" }
    if (-not $escal) { throw "falta 'authority.escalates_to' no yaml" }
    if ($Src.IsMacro) {
        # macro: conhecimento, checklist e aceite sao obrigatorios. Sem eles, nao publica.
        if ($knowEntries.Count -eq 0) { throw "macro sem knowledge[]" }
        if ($checklist.Count -eq 0) { throw "macro sem checklist[] (5 a 10 linhas verificaveis)" }
        $acc = Join-Path $agentsDir "$AgentId.accept.json"
        if (-not (Test-Path $acc)) { throw "macro sem $AgentId.accept.json (teste de aceite: p, deve[], nao[])" }
        $aj = Get-Content -Path $acc -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $aj.p -or -not $aj.deve -or @($aj.deve).Count -eq 0) { throw "$AgentId.accept.json sem 'p' ou sem 'deve[]'" }
    }

    # tools: mcp validado; whitelist; padrao por camada; Task so nos casos de antes (cerca leitor-gate)
    $raw = New-Object System.Collections.ArrayList
    foreach ($t in (Get-ListValue $data 'tools')) {
        if ($t -like 'mcp__*') { $r = Resolve-McpTool -Token $t -Servers $McpServers -Warnings $McpWarn -Context $ctxName; if ($r) { [void]$raw.Add($r) } }
        else { [void]$raw.Add($t) }
    }
    $tools = @($raw | Where-Object { ($ToolWhitelist -contains $_) -or ($_ -like 'mcp__*') })
    $noTask = (Get-ScalarValue $data 'task' '') -eq 'false'   # macro: tools minimas, sem Task
    if ($tools.Count -eq 0) {
        $tools = switch ($camada) { 'B' { @('Read', 'Grep', 'Glob', 'Edit', 'Write', 'Bash', 'Task') } default { @('Read', 'Grep', 'Glob', 'Task') } }
    } elseif ($tools -notcontains 'Task' -and -not $noTask) { $tools = @($tools) + @('Task') }
    if ($noTask) { $tools = @($tools | Where-Object { $_ -ne 'Task' }) }

    $know = Resolve-Knowledge -Src $Src -Entries $knowEntries -Focus (Get-ListValue $data 'knowledge_focus') -Ctx $ctxName -Warn $KnowWarn
    $entryPath = ''
    if ($entryRaw) { $ef = Join-Path $Src.SquadDir $entryRaw; $entryPath = if (Test-Path $ef) { ConvertTo-PortablePath $ef } else { $entryRaw } }
    $groundPath = ''
    if ($groundRaw -and -not $Src.IsMacro) { $gf = Join-Path $Src.ClientDir $groundRaw; $groundPath = if (Test-Path $gf) { ConvertTo-PortablePath $gf } else { $groundRaw } }

    $descParts = @($role); if ($domain) { $descParts += "dominio: $domain" }
    $desc = (($descParts -join '. ') -replace '\s+', ' ').Trim()

    $persona = Remove-FantasySections (Get-Content -Path $mdPath -Raw -Encoding UTF8)
    $a = [pscustomobject]@{
        Id = $AgentId; Client = $cid; Name = ("$cid-$AgentId").ToLower(); Role = $role; Domain = $domain
        Description = $desc; Camada = $camada; IsMacro = $Src.IsMacro
        TierModel = $(switch ($camada) { 'A' { 'opus' } 'B' { 'sonnet' } default { 'haiku' } })
        DeclaredModel = (Get-ScalarValue $data 'model' '')
        Persona = $persona; Tools = $tools; KnowledgeLines = $know; Checklist = $checklist
        EntryPointPath = $entryPath; GroundingPath = $groundPath; Budget = $budget; MaxLines = $maxLines
        Tags = $tags; Decides = $decides; Escalates = $escal
        SourceHash = (Get-SourceHash @($mdPath, $yamlPath, (Join-Path $Src.SquadDir 'squad.yaml')))
    }
    $a | Add-Member -NotePropertyName Operating -NotePropertyValue (New-Operating -A $a -NoTask $noTask)
    $a | Add-Member -NotePropertyName OperatingNoTask -NotePropertyValue (New-Operating -A $a -NoTask $true)
    return $a
}

# ---- geracao ----
$generated = 0; $updated = 0; $unchanged = 0; $errors = 0; $onlyMatched = 0
$report = New-Object System.Collections.ArrayList
$mcpWarn = New-Object System.Collections.ArrayList
$knowWarn = New-Object System.Collections.ArrayList
$camWarn = New-Object System.Collections.ArrayList
$noAccept = New-Object System.Collections.ArrayList
$utf8 = New-Object System.Text.UTF8Encoding($false)
$processedClients = New-Object System.Collections.ArrayList

foreach ($src in $sources) {
    $info = if (Test-Path (Join-Path $src.SquadDir 'squad.yaml')) { Read-SquadYamlInfo -Path (Join-Path $src.SquadDir 'squad.yaml') } else { [pscustomobject]@{ Camadas = @{}; GatewayId = $null } }
    foreach ($yf in (Get-ChildItem -Path (Join-Path $src.SquadDir 'agents') -Filter '*.yaml' -File)) {
        $aid = [System.IO.Path]::GetFileNameWithoutExtension($yf.Name)
        if ($Only -and $Only -ne $src.Id -and $Only -ne $aid -and $Only -ne "$($src.Id)-$aid" -and -not ($src.IsMacro -and $allClientIds -contains $Only)) { continue }
        $onlyMatched++
        try {
            $a = New-NeutralAgent -Src $src -AgentId $aid -Info $info -McpWarn $mcpWarn -KnowWarn $knowWarn -CamWarn $camWarn
            if (-not $src.IsMacro -and -not (Test-Path (Join-Path $src.SquadDir "agents\$aid.accept.json"))) { [void]$noAccept.Add("$($src.Id)/$aid") }
            # render de TODOS os modulos antes de gravar qualquer um (um falha = nenhum grava este agente)
            $files = New-Object System.Collections.ArrayList
            foreach ($tn in $targets.Keys) { $render = $targets[$tn].Render; foreach ($f in @(& $render $a $ctx)) { [void]$files.Add($f) } }
            foreach ($f in $files) {
                $existing = if (Test-Path -LiteralPath $f.path) { Get-Content -Path $f.path -Raw -Encoding UTF8 } else { $null }
                if ($existing -eq $f.content) { $unchanged++; continue }
                if ($DryRun) { Write-Host "[DRYRUN] $(if ($null -eq $existing) { 'geraria' } else { 'atualizaria' }): $($f.path)" }
                else {
                    $dir = Split-Path -Parent $f.path
                    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
                    [System.IO.File]::WriteAllText($f.path, $f.content, $utf8)
                }
                if ($null -eq $existing) { $generated++ } else { $updated++ }
            }
            [void]$report.Add("$($src.Id)/$aid -> $($a.Name) (camada $($a.Camada), alvos: $($targets.Keys -join ','), hash $($a.SourceHash))")
        }
        catch { Write-Warning "[$($src.Id)/$aid] erro: $($_.Exception.Message)"; $errors++ }
    }
    [void]$processedClients.Add($src.Id)
}

# ---- Clean dos modulos (ex.: .brief.md velho) ----
foreach ($tn in $targets.Keys) { $clean = $targets[$tn].Clean; if ($clean) { & $clean $ctx @($processedClients) } }

# ---- -Prune ----
$removed = 0
if ($Prune) {
    if (-not $Only -or ($allClientIds -notcontains $Only)) { Write-Error "-Prune exige -Only <Client existente em clients\>. Nada foi apagado."; exit 1 }
    $keepIds = @($Only, 'macro') + @($Keep -split ',' | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ }) | ForEach-Object { $_.ToLower() }
    $known = @($allClientIds | ForEach-Object { $_.ToLower() }) + 'macro' | Sort-Object { $_.Length } -Descending
    if (Test-Path $ClaudeOut) {
        foreach ($b in (Get-ChildItem -Path $ClaudeOut -Filter '*.md' -File)) {
            $owner = $known | Where-Object { $b.Name.ToLower().StartsWith("$_-") } | Select-Object -First 1
            if ($owner -and ($keepIds -notcontains $owner)) {
                if (-not $DryRun) { Remove-Item -LiteralPath $b.FullName -Force }
                Write-Host "[REMOVIDO] $($b.Name)"; $removed++
            }
        }
    }
}

Write-Host ''
Write-Host "=== bridge: resumo (alvos: $($targets.Keys -join ', ')) ==="
Write-Host "gerados:     $generated"
Write-Host "atualizados: $updated"
Write-Host "inalterados: $unchanged"
Write-Host "erros:       $errors"
if ($Prune) { Write-Host "podados:     $removed" }
foreach ($pair in @(@('knowledge omitido', $knowWarn), @('camada (CONFIRA)', $camWarn), @('tools MCP corrigidas/descartadas', $mcpWarn))) {
    if ($pair[1].Count -gt 0) { Write-Host ''; Write-Host "$($pair[0]):"; foreach ($w in $pair[1]) { Write-Host "  - $w" } }
}
if ($noAccept.Count -gt 0) { Write-Host ''; Write-Host "SEM ACEITE ($($noAccept.Count) agentes de Client sem <id>.accept.json - aviso, nao bloqueia)" }
Write-Host ''
foreach ($r in $report) { Write-Host $r }

if ($Only -and $onlyMatched -eq 0) { Write-Warning "-Only '$Only' nao casou com nada (nada gerado nem apagado)."; exit 1 }
if ($errors -gt 0 -or $missingTargets.Count -gt 0) { exit 1 }
exit 0
