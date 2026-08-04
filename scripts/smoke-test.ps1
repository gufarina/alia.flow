# Alia Flow - Smoke Test (o trilho)
# Cobre exatamente: T01-T10, T13, T14 + ciclo E2E. Exit 0 se tudo verde, 1 caso contrario.
# T11 e T12 NAO sao cobertos aqui de proposito (sem spec de check neste harness);
# se precisarem virar check, adicionar bloco proprio e atualizar esta lista.
# Sem acentos, sem emojis. UTF-8 sem BOM.

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot          # raiz do alia/
$engine = Join-Path $root "engine"
$studio = Join-Path $root "studio.example"
$client = Join-Path $studio "clients\acme-saas"
$squad  = Join-Path $client "squad"

$script:fail = 0
$script:pass = 0

function Check([string]$name, [bool]$cond, [string]$detail = "") {
  if ($cond) {
    Write-Host ("[PASS] " + $name)
    $script:pass++
  } else {
    Write-Host ("[FAIL] " + $name + $(if ($detail) { " -> " + $detail } else { "" }))
    $script:fail++
  }
}

# Warn: aviso que NUNCA reprova o smoke (nao mexe em pass/fail). Uso: drift que so o CEO resolve
# (ex.: versao entre oficina/release/produto), nunca um defeito que o proprio motor devia corrigir.
function Warn([string]$name, [bool]$cond, [string]$detail = "") {
  if ($cond) {
    Write-Host ("[OK] " + $name)
  } else {
    Write-Host ("[AVISO] " + $name + $(if ($detail) { " -> " + $detail } else { "" }))
  }
}

function ReadText([string]$path) {
  $utf8 = New-Object System.Text.UTF8Encoding($false)
  return [System.IO.File]::ReadAllText($path, $utf8)
}

Write-Host "=== Alia Flow Smoke Test ==="
Write-Host ("root: " + $root)
Write-Host ""

# --- T01 ENGINE ---
Write-Host "-- T01 Engine --"
$engineFiles = @(
  "constitution.md","glossary.md","tools.md","engineering.md","orchestration.md","squad-system.md",
  "agents\alia.md","agents\persona.md","agents\squad-creator.md","agents\architect.md",
  "agents\data-engineer.md","agents\qa.md","agents\dev.md","agents\devops.md",
  "workflows\story-cycle.md","workflows\qa-loop.md",
  "governance\loops.md","governance\quality-gate.md","governance\memory-audit.md","governance\evolution-pipeline.md",
  "features\expert-minds.md","features\squad-templates.md","features\frugal-skills.md",
  "features\validated-artifacts.md","features\forja.md","features\bastao.md","features\bastao-template.yaml",
  "features\expert-minds\design\brad-frost.md","features\expert-minds\dev\kent-beck.md",
  "features\expert-minds\copy\ogilvy.md"
)
$missing = @()
foreach ($f in $engineFiles) { if (-not (Test-Path (Join-Path $engine $f))) { $missing += $f } }
Check "Engine: 7 agentes, workflows, governanca, features presentes" ($missing.Count -eq 0) ("faltando: " + ($missing -join ", "))

# --- T02 STUDIO ---
Write-Host "-- T02 Studio --"
Check "Studio: studio.yaml existe" (Test-Path (Join-Path $studio "studio.yaml"))
$stateOk = $false
$state = $null
try { $state = (ReadText (Join-Path $studio "state.json")) | ConvertFrom-Json; $stateOk = $true } catch { $stateOk = $false }
Check "Studio: state.json e JSON valido" $stateOk

# --- T03 SQUAD ---
Write-Host "-- T03 Squad --"
$squadYaml = Join-Path $squad "squad.yaml"
Check "Squad: squad.yaml existe" (Test-Path $squadYaml)
$specialists = @("maya","iris","rex","bruno","cleo","quinn")
$pairsOk = $true
foreach ($s in $specialists) {
  $md = Join-Path $squad ("agents\" + $s + ".md")
  $yaml = Join-Path $squad ("agents\" + $s + ".yaml")
  if (-not (Test-Path $md) -or -not (Test-Path $yaml)) { $pairsOk = $false }
}
Check "Squad: >=4 especialistas com par .md + .yaml" (($specialists.Count -ge 4) -and $pairsOk)

# --- T04 KNOWLEDGE ---
Write-Host "-- T04 Segundo cerebro --"
$know = Join-Path $squad "knowledge"
$knowFiles = Get-ChildItem -Path $know -Filter *.md -File -ErrorAction SilentlyContinue
Check "Knowledge: >=3 arquivos de contexto" ($knowFiles.Count -ge 3) ("achei: " + $knowFiles.Count)
$em = Join-Path $know "expert-minds"
$emFiles = Get-ChildItem -Path $em -Filter *.md -File -ErrorAction SilentlyContinue
Check "Knowledge: >=2 Expert Minds copiados" ($emFiles.Count -ge 2) ("achei: " + $emFiles.Count)

# --- T05 GRAPHIFY ---
Write-Host "-- T05 Graphify --"
$gout = Join-Path $know "graphify-out"
$graphJson = Join-Path $gout "graph.json"
$report = Join-Path $gout "GRAPH_REPORT.md"
Check "Graphify: GRAPH_REPORT.md existe" (Test-Path $report)
$nodesOk = $false
try {
  $g = (ReadText $graphJson) | ConvertFrom-Json
  $n = ($g.nodes | Measure-Object).Count
  $nodesOk = ($n -gt 0)
  Write-Host ("       grafo: " + $n + " nodes")
} catch { $nodesOk = $false }
Check "Graphify: graph.json com >0 nodes" $nodesOk

# --- T06/T07 ARTIFACTS ---
Write-Host "-- T06/T07 Artifacts --"
$art1 = Join-Path $client "artifacts\ART-001-landing-copy.md"
$art2 = Join-Path $client "artifacts\ART-002-story-painel-pulse.md"
Check "Artifact ART-001 existe" (Test-Path $art1)
Check "Artifact ART-002 existe" (Test-Path $art2)
if (Test-Path $art1) {
  $c1 = ReadText $art1
  Check "ART-001 cita Expert Mind (Ogilvy)" ($c1 -match "Ogilvy")
  Check "ART-001 tem Headline e CTA" (($c1 -match "Headline") -and ($c1 -match "Chamada de acao"))
}
if (Test-Path $art2) {
  $c2 = ReadText $art2
  Check "ART-002 tem AC Given/When/Then" (($c2 -match "Given") -and ($c2 -match "When") -and ($c2 -match "Then"))
}

# --- T08 GATES ---
Write-Host "-- T08 Quality Gate --"
$g1 = Join-Path $client "artifacts\gates\ART-001.gate.md"
$g2 = Join-Path $client "artifacts\gates\ART-002.gate.md"
foreach ($gp in @($g1,$g2)) {
  if (Test-Path $gp) {
    $gc = ReadText $gp
    $name = Split-Path $gp -Leaf
    $hasFive = ($gc -match "Funciona") -and ($gc -match "DDD") -and ($gc -match "Frugal") -and ($gc -match "Rastreavel") -and ($gc -match "Atrito")
    $hasVerdict = ($gc -match "Verdict")
    Check ("Gate " + $name + ": 5 criterios + verdict") ($hasFive -and $hasVerdict)
  } else {
    Check ("Gate " + (Split-Path $gp -Leaf) + ": existe") $false
  }
}

# --- T09 MEMORY ---
Write-Host "-- T09 Memory --"
$memDir = Join-Path $client "memory"
$memFiles = Get-ChildItem -Path $memDir -Filter *.md -File -ErrorAction SilentlyContinue
$memOk = $false
if ($memFiles.Count -ge 1) {
  $mc = ReadText $memFiles[0].FullName
  $memOk = ($mc -match "ART-001") -and ($mc -match "ART-002")
}
Check "Memory: nota liga ART-001 e ART-002" $memOk

# --- T10 STATE consistente ---
Write-Host "-- T10 Estado --"
$stateConsistent = $false
if ($stateOk -and $state -and (($state.tasks | Measure-Object).Count -gt 0)) {
  $stateConsistent = $true
  foreach ($t in $state.tasks) {
    if ($t.status -eq "done") {
      $apath = Join-Path $studio $t.artifact
      if (-not (Test-Path $apath)) { $stateConsistent = $false }
    }
  }
}
Check "Estado: toda task done tem artifact existente" $stateConsistent

# --- E2E chain ---
Write-Host "-- E2E (delega -> especialista -> gate -> artefato -> memoria) --"
$e2e = $false
if ($stateOk -and $state -and (($state.tasks | Measure-Object).Count -gt 0)) {
  $e2e = $true
  foreach ($t in $state.tasks) {
    $okA = Test-Path (Join-Path $studio $t.artifact)
    $okG = Test-Path (Join-Path $studio $t.gate)
    $okM = Test-Path (Join-Path $studio $t.memory)
    $okV = ($t.gate_verdict -eq "PASS")
    if (-not ($okA -and $okG -and $okM -and $okV)) { $e2e = $false }
  }
}
Check "E2E: cada Task tem artifact + gate PASS + memoria" $e2e

# --- Rastreabilidade dura + continuidade (OPP-66) ---
# A LEI de rastreabilidade (orchestration.md) exige que toda Task carregue a LINHAGEM completa:
# project + base_artifact + session. Ate aqui era regra escrita: o mission-control CONTAVA os furos
# (amarelo), mas nada REPROVAVA. Este check torna o furo uma falha dura - toda Task com artifact tem
# que ter project, base_artifact e session nao-vazios. Zera a fresta que gerou o incidente da LP
# (reconstruir sobre base obsoleta por nao registrar DE ONDE se partiu).
Write-Host ""
Write-Host "-- Rastreabilidade dura + continuidade (OPP-66) --"
$furos = @()
if ($stateOk -and $state -and (($state.tasks | Measure-Object).Count -gt 0)) {
  foreach ($t in $state.tasks) {
    $art = "$($t.artifact)"
    if ($art -ne "") {
      $miss = @()
      if ("$($t.project)" -eq "")       { $miss += "project" }
      if ("$($t.base_artifact)" -eq "") { $miss += "base_artifact" }
      if ("$($t.session)" -eq "")       { $miss += "session" }
      if ($miss.Count -gt 0) { $furos += ("$($t.id)(" + ($miss -join "+") + ")") }
    }
  }
}
Check "Rastreabilidade: toda Task com artifact tem linhagem completa (project+base_artifact+session)" ($furos.Count -eq 0) ("furos: " + ($furos -join ", "))

# Continuidade: o mecanismo task-context.ps1 devolve a "ultima revisao" de um Cliente (a base do
# proximo passo). Sem executor, "ler as Tasks primeiro" era intencao; aqui e um CLI barato e testado.
$tcScript = Join-Path $root "scripts\task-context.ps1"
Check "Continuidade: task-context.ps1 presente" (Test-Path $tcScript)
if ((Test-Path $tcScript) -and $stateOk) {
  $demoStatePath = Join-Path $studio "state.json"
  $tcOut = (& $tcScript -Client "acme-saas" -StateFile $demoStatePath 6>&1) -join "`n"; $tcExit = $LASTEXITCODE
  # tem que apontar a ULTIMA REVISAO e citar o base_artifact real da ultima Task (continuidade de verdade).
  $tcOk = ($tcExit -eq 0) -and ($tcOut -match 'ULTIMA REVISAO: TASK-ART-002') -and ($tcOut -match 'ART-001-landing-copy\.md')
  Check "Continuidade: task-context aponta a ultima revisao do cliente (com base_artifact)" $tcOk ("exit: " + $tcExit)
  # cliente sem historico -> ponto de partida limpo (nao quebra), exit 0.
  $tcEmpty = (& $tcScript -Client "__inexistente__" -StateFile $demoStatePath 6>&1) -join "`n"; $tcEmptyExit = $LASTEXITCODE
  Check "Continuidade: cliente sem Task -> ponto de partida limpo (exit 0)" (($tcEmptyExit -eq 0) -and ($tcEmpty -match 'partida limpo'))
}

# --- Alma de dono do Squad Owner (OPP-67) ---
# O Gateway (Squad Owner) tem que ser dono ativo, nao papel passivo. A LEI vive pareada: prosa em
# squad-system.md ("A alma do Squad Owner") + contrato owner_soul em agents/squad-creator.yaml. O
# check garante (a) o contrato declara os quatro tracos, e (b) o Gateway REAL do demo os carrega na
# persona (descoberto via squad.yaml -> owner), pra a regra nao apodrecer como texto solto.
Write-Host ""
Write-Host "-- Alma de dono do Squad Owner (OPP-67) --"
$scYaml = ReadText (Join-Path $engine "agents\squad-creator.yaml")
$soulContract = ($scYaml -match '(?im)^\s*owner_soul:') -and
                ($scYaml -match '(?i)incomodo_de_dono') -and ($scYaml -match '(?i)motor_ativo') -and
                ($scYaml -match '(?i)perguntas_inteligentes') -and ($scYaml -match '(?i)pragmatismo_de_processo')
$soulProse = ($sqSysTxt = ReadText (Join-Path $engine "squad-system.md")) -match '(?i)A alma do Squad Owner'
Check "Owner soul: contrato owner_soul (4 tracos) em squad-creator.yaml + doutrina em squad-system.md" ($soulContract -and $soulProse)
# Gateway real do demo: acha o owner no squad.yaml e confere que a persona dele carrega a alma.
$demoSquadYaml = Join-Path $squad "squad.yaml"
$ownerId = ""
if (Test-Path $demoSquadYaml) {
  $om = [regex]::Match((ReadText $demoSquadYaml), '(?im)^\s*owner:\s*([A-Za-z0-9._-]+)')
  if ($om.Success) { $ownerId = $om.Groups[1].Value }
}
$ownerHasSoul = $false
if ($ownerId -ne "") {
  $ownerMd = Join-Path $squad ("agents\" + $ownerId + ".md")
  if (Test-Path $ownerMd) {
    $omd = ReadText $ownerMd
    $ownerHasSoul = ($omd -match '(?i)incomodo de dono|entrega morna a incomoda') -and
                    ($omd -match '(?i)roda girar|motor ativo') -and
                    ($omd -match '(?i)pergunta[s]? inteligente|pergunta cirurgica') -and
                    ($omd -match '(?i)pragmatismo')
  }
}
Check ("Owner soul: Gateway do demo (" + $ownerId + ") carrega os 4 tracos na persona") $ownerHasSoul ("owner: " + $ownerId)

# --- Conhecimento por Client: consistencia + grafo garantido (OPP-68) ---
# (a) Especificacao de Entrega: todo Client carrega o contrato de consistencia no knowledge. A LEI
#     vive em squad-system.md; o demo tem que ter o doc real. (b) Grafo em todo Client via graph-check.
Write-Host ""
Write-Host "-- Conhecimento por Client (consistencia + grafo, OPP-68) --"
$specDoc = Get-ChildItem -Path $know -Filter "*especificacoes-de-entrega*.md" -File -ErrorAction SilentlyContinue | Select-Object -First 1
$specProse = ($sqSysTxt2 = ReadText (Join-Path $engine "squad-system.md")) -match '(?i)Especificacoes de entrega'
$specOk = ($null -ne $specDoc) -and $specProse
if ($null -ne $specDoc) {
  $sc = ReadText $specDoc.FullName
  # o contrato de consistencia tem que cobrir design + formato + checklist (nao ser um doc vazio).
  $specOk = $specOk -and ($sc -match '(?i)Design') -and ($sc -match '(?i)Checklist de consistencia')
}
Check "Consistencia: Especificacao de Entrega presente no knowledge do demo + LEI em squad-system.md" $specOk
$scStep = (ReadText (Join-Path $engine "agents\squad-creator.yaml")) -match '(?im)step:\s*g'
Check "Consistencia: squad-creator fecha com spec de entrega + grafo (step g)" $scStep

$gcScript = Join-Path $root "scripts\graph-check.ps1"
Check "Grafo: graph-check.ps1 presente" (Test-Path $gcScript)
if (Test-Path $gcScript) {
  $gcOut = (& $gcScript -StudioDir $studio 6>&1) -join "`n"; $gcExit = $LASTEXITCODE
  Check "Grafo: graph-check aprova todo Client do demo (exit 0)" (($gcExit -eq 0) -and ($gcOut -match '\[PASS\]')) ("exit: " + $gcExit)
  # discrimina: uma pasta de cliente sem grafo tem que REPROVAR (usa um studio temporario de fixture).
  $tmpStudio = Join-Path ([System.IO.Path]::GetTempPath()) ("gc-fixture-" + $PID)
  $tmpClient = Join-Path $tmpStudio "clients\sem-grafo\squad\knowledge"
  New-Item -ItemType Directory -Force -Path $tmpClient | Out-Null
  $gcBadOut = (& $gcScript -StudioDir $tmpStudio 6>&1) -join "`n"; $gcBadExit = $LASTEXITCODE
  if (Test-Path -LiteralPath $tmpStudio) { Remove-Item -Recurse -Force -LiteralPath $tmpStudio -ErrorAction SilentlyContinue }
  Check "Grafo: graph-check REPROVA client sem grafo (exit 1)" (($gcBadExit -eq 1) -and ($gcBadOut -match '\[FALTA\]'))
}

# --- Estrategia de leitura: indice mestre + assinatura + grep (OPP-69) ---
# LEI pareada (reading-strategy.md + .yaml) com os 3 padroes; mecanismo kb-index.ps1 gera/valida o
# indice mestre por Client (knowledge/MAP.md). Fecha o pedido de "ler sem gastar" e "mapas de codigo".
Write-Host ""
Write-Host "-- Estrategia de leitura (OPP-69) --"
$rsMd  = ReadText (Join-Path $engine "reading-strategy.md")
$rsYml = ReadText (Join-Path $engine "reading-strategy.yaml")
$rsOk = ($rsMd -match '(?i)Estrategia de Leitura') -and ($rsYml -match '(?im)^\s*id:\s*reading-strategy') -and
        ($rsYml -match '(?i)master_index') -and ($rsYml -match '(?i)signature_first') -and ($rsYml -match '(?i)section_grep')
Check "Leitura: reading-strategy pareado (md + yaml) com os 3 padroes" $rsOk
$kbScript = Join-Path $root "scripts\kb-index.ps1"
Check "Leitura: kb-index.ps1 presente" (Test-Path $kbScript)
$demoKnowMap = Join-Path $know "MAP.md"
Check "Leitura: indice mestre knowledge/MAP.md existe no demo" (Test-Path $demoKnowMap)
if (Test-Path $kbScript) {
  $kbOut = (& $kbScript -KnowledgePath $know -Validate 6>&1) -join "`n"; $kbExit = $LASTEXITCODE
  Check "Leitura: kb-index valida o indice do demo (PASS, exit 0)" (($kbExit -eq 0) -and ($kbOut -match '\[PASS\]')) ("exit: " + $kbExit)
  # discrimina: um doc sem assinatura (sem blockquote) tem que REPROVAR.
  $tmpKb = Join-Path ([System.IO.Path]::GetTempPath()) ("kb-fixture-" + $PID)
  New-Item -ItemType Directory -Force -Path $tmpKb | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $tmpKb "sem-assinatura.md"), "# Doc sem assinatura`r`nCorpo sem blockquote.`r`n", (New-Object System.Text.UTF8Encoding($false)))
  $kbBadOut = (& $kbScript -KnowledgePath $tmpKb -Validate 6>&1) -join "`n"; $kbBadExit = $LASTEXITCODE
  if (Test-Path -LiteralPath $tmpKb) { Remove-Item -Recurse -Force -LiteralPath $tmpKb -ErrorAction SilentlyContinue }
  Check "Leitura: kb-index REPROVA doc sem assinatura (exit 1)" (($kbBadExit -eq 1) -and ($kbBadOut -match 'sem assinatura'))
}

# --- Mission Control vivo: olhos da Alia em tarefas paradas (OPP-70) ---
# stale-tasks.ps1 lista as Tasks paradas (nao-done, paradas > N dias); o Mission Control as destaca.
# LEI em orchestration.md (anti-ociosidade). Determinismo via -Now fixo no teste.
Write-Host ""
Write-Host "-- Mission Control vivo: tarefas paradas (OPP-70) --"
$stScript = Join-Path $root "scripts\stale-tasks.ps1"
$stFixture = Join-Path $root "scripts\fixtures\stale-state.json"
Check "Paradas: stale-tasks.ps1 + fixture presentes" ((Test-Path $stScript) -and (Test-Path $stFixture))
if ((Test-Path $stScript) -and (Test-Path $stFixture)) {
  $stOut = (& $stScript -StateFile $stFixture -StaleDays 7 -Now "2026-07-03" 6>&1) -join "`n"; $stExit = $LASTEXITCODE
  # tem que pegar a antiga (TASK-OLD), NAO a recente (TASK-NEW) nem a done (TASK-DONE).
  $stOk = ($stExit -eq 0) -and ($stOut -match 'PARADAS: 1') -and ($stOut -match 'TASK-OLD') -and ($stOut -notmatch 'TASK-NEW') -and ($stOut -notmatch 'TASK-DONE')
  Check "Paradas: stale-tasks pega a antiga e ignora a recente/concluida (determinismo)" $stOk ("exit: " + $stExit)
}
# Mission Control declara a deteccao (param StaleDays + secao de paradas).
$mcTxt = ReadText (Join-Path $root "scripts\mission-control.ps1")
$mcStale = ($mcTxt -match '(?i)\$StaleDays') -and ($mcTxt -match '(?i)paradas / em risco')
Check "Paradas: mission-control.ps1 tem KPI/secao de paradas (StaleDays)" $mcStale
# LEI dos olhos da Alia pareada com o bastidor (nunca abre a conversa).
$orchTxt = ReadText (Join-Path $engine "orchestration.md")
Check "Paradas: LEI 'olhos da Alia' em orchestration.md (no bastidor)" (($orchTxt -match '(?i)olhos da Alia') -and ($orchTxt -match '(?i)bastidor'))

# --- T13 LOOP DESIGNER ---
Write-Host "-- T13 Loop Designer --"
Check "Loop Designer: feature spec existe" (Test-Path (Join-Path $engine "features\loop-designer.md"))
Check "Loop Designer: skill existe" (Test-Path (Join-Path $root "skills\loop-designer\SKILL.md"))
$loopPlan = Join-Path $client "loop-plan.md"
$loopsYaml = Join-Path $client "loops.yaml"
Check "Loop Designer: loop-plan.md (raciocinio) existe" (Test-Path $loopPlan)
Check "Loop Designer: loops.yaml existe" (Test-Path $loopsYaml)
if (Test-Path $loopsYaml) {
  $ly = ReadText $loopsYaml
  Check "Loops: tem deep-research diario" (($ly -match "id:\s*deep-research") -and ($ly -match "cadence:\s*daily"))
  # todo loop com id deve ter owner, cadence, status, review_on (lei do CEO: review_on obrigatorio)
  $idCount = ([regex]::Matches($ly, "(?m)^\s*-\s*id:")).Count
  $ownerCount = ([regex]::Matches($ly, "(?m)^\s+owner:")).Count
  $cadCount = ([regex]::Matches($ly, "(?m)^\s+cadence:")).Count
  $statusCount = ([regex]::Matches($ly, "(?m)^\s+status:")).Count
  $reviewCount = ([regex]::Matches($ly, "(?m)^\s+review_on:")).Count
  $allHave = ($idCount -gt 0) -and ($ownerCount -eq $idCount) -and ($cadCount -eq $idCount) -and ($statusCount -eq $idCount) -and ($reviewCount -eq $idCount)
  Check "Loops: todo loop tem owner+cadence+status+review_on" $allHave ("ids:" + $idCount + " owner:" + $ownerCount + " cad:" + $cadCount + " status:" + $statusCount + " review:" + $reviewCount)
  # Contrato de 6 elementos (OPP-57): todo loop do demo declara os 6 campos do orange-book.
  $six = @("discovery_source","state_file","evaluator","isolation","token_cap","human_review_point")
  $sixBad = @()
  foreach ($f6 in $six) {
    $c6 = ([regex]::Matches($ly, "(?m)^\s+" + $f6 + ":")).Count
    if ($c6 -ne $idCount) { $sixBad += ($f6 + ":" + $c6) }
  }
  Check "Loops: contrato de 6 elementos (OPP-57) em todo loop do demo" ($sixBad.Count -eq 0) ("incompleto vs ids:" + $idCount + " -> " + ($sixBad -join ", "))
}
Check "Loop Designer: mecanismo install-loops.ps1 existe" (Test-Path (Join-Path $root "scripts\install-loops.ps1"))
# deep-research e o loop que sustenta a promessa de RSI; o mecanismo (agente-driven via MCP) tem
# que estar declarado de verdade - o catalogo do Perplexity (busca normal Sonnet 4.6, jamais Sonar).
Check "Loop Designer: mecanismo de pesquisa (MCP perplexity) declarado" (Test-Path (Join-Path $root "optional-mcps\perplexity\manifest.yaml"))

# --- Loops agendados fiados no runner (anti-orfao) ---
# Todo loop scheduled do catalogo (loops.catalog.yaml) cujo mecanismo e um script (scripts/*.ps1)
# tem que estar mapeado no run-loops.ps1 (arrays $daily/$weekly). Sem isso o loop fica orfao: existe
# no catalogo e tem mecanismo, mas o runner padrao nunca o dispara (foi o bug do memory-curator).
# Loops com mecanismo agente-driven (deep-research, sem scripts/*.ps1) ficam de fora por contrato.
Write-Host ""
Write-Host "-- Loops agendados no runner (anti-orfao) --"
$catalogPath = Join-Path $engine "governance\loops.catalog.yaml"
$runnerPath  = Join-Path $root "scripts\run-loops.ps1"
$orphanLoops = @()
if ((Test-Path $catalogPath) -and (Test-Path $runnerPath)) {
  $catTxt = ReadText $catalogPath
  # ids dos loops com mechanism: scripts/<nome>.ps1 (basename = id no runner)
  $needed = @()
  foreach ($m in [regex]::Matches($catTxt, '(?im)^\s*mechanism:\s*scripts/([A-Za-z0-9._-]+)\.ps1\s*$')) {
    $needed += $m.Groups[1].Value
  }
  $needed = $needed | Select-Object -Unique
  # mapa do runner: conteudo dos arrays $daily e $weekly
  $runTxt = ReadText $runnerPath
  $mapped = @()
  foreach ($arr in @('daily','weekly')) {
    $am = [regex]::Match($runTxt, ('(?m)^\s*\$' + $arr + '\s*=\s*@\(([^)]*)\)'))
    if ($am.Success) {
      foreach ($q in [regex]::Matches($am.Groups[1].Value, '"([^"]+)"')) { $mapped += $q.Groups[1].Value }
    }
  }
  foreach ($id in $needed) { if ($mapped -notcontains $id) { $orphanLoops += $id } }
} else {
  $orphanLoops += "(catalogo ou runner ausente)"
}
Check "Loops: todo scheduled com mechanism=script esta no runner (sem orfao)" ($orphanLoops.Count -eq 0) ("orfao(s): " + ($orphanLoops -join ", "))

# --- T14 Knowledge Ablation (proxy) ---
Write-Host "-- T14 Knowledge Ablation (proxy) --"
$abl = Join-Path $client "tests\knowledge-ablation"
$ablFiles = @("test.yaml","score.py","out-blind.md","out-informed.md","RESULT.md")
$ablMissing = @()
foreach ($f in $ablFiles) { if (-not (Test-Path (Join-Path $abl $f))) { $ablMissing += $f } }
Check "Ablation: test.yaml, score.py, out-*.md, RESULT.md presentes" ($ablMissing.Count -eq 0) ("faltando: " + ($ablMissing -join ", "))
Check "Ablation: gate ART-003.gate.md existe" (Test-Path (Join-Path $client "artifacts\gates\ART-003.gate.md"))
$pythonCmd = Get-Command python -ErrorAction SilentlyContinue
if (-not $pythonCmd) {
  Check "Ablation: python disponivel no PATH" $false "python nao encontrado no PATH (falha de ambiente, nao do scorer)"
} else {
  Push-Location $abl
  $ablOut = (& python (Join-Path $abl "score.py") 2>&1) -join "`n"
  $ablExit = $LASTEXITCODE
  Pop-Location
  Check "Ablation: score.py sai PASS (exit 0)" ($ablExit -eq 0) ("exit: " + $ablExit)
  Check "Ablation: VERDICT PASS no output" ($ablOut -match 'VERDICT: PASS')
}

# --- Corrupcao de encoding ---
Write-Host "-- Encoding (corrupcao) --"
$corrupt = @()
$encScanRoots = @($studio, $engine, (Join-Path $root "scripts"), (Join-Path $root "skills")) | Where-Object { Test-Path $_ }
$allMd = Get-ChildItem -Path $encScanRoots -Recurse -Include *.md,*.yaml,*.json -File -ErrorAction SilentlyContinue
foreach ($file in $allMd) {
  $txt = ReadText $file.FullName
  if ($txt.IndexOf([char]0xFFFD) -ge 0) { $corrupt += $file.Name }
}
Check "Encoding: nenhum arquivo corrompido (0xFFFD)" ($corrupt.Count -eq 0) ("corrompidos: " + ($corrupt -join ", "))

# Lei do CEO: zero caractere non-ASCII em qualquer arquivo do produto.
# Le como BYTES (nao como texto) para pegar acento, em-dash (U+2014), middle-dot
# (U+00B7), aspas curvas, setas etc. Reusa os mesmos roots do check de 0xFFFD
# (studio.example, nunca o studio real do operador) e soma os scripts .ps1 e os
# arquivos de raiz versionados relevantes, quando acessiveis.
$nonAscii = @()
$asciiScan = @($allMd)
$asciiScan += Get-ChildItem -Path $encScanRoots -Recurse -Include *.ps1 -File -ErrorAction SilentlyContinue
# docs/ guarda a documentacao do produto (BRAND, DESIGN movidos da raiz). Incluir no scan ASCII.
$docsDir = Join-Path $root "docs"
if (Test-Path $docsDir) {
  $asciiScan += Get-ChildItem -Path $docsDir -Recurse -Include *.md -File -ErrorAction SilentlyContinue
}
$rootFiles = @("README.md","AGENTS.md","CLAUDE.md","CHANGELOG.md","VERSION","alia.config.json")
foreach ($rf in $rootFiles) {
  $rp = Join-Path $root $rf
  if (Test-Path $rp) { $asciiScan += Get-Item -LiteralPath $rp -ErrorAction SilentlyContinue }
}
foreach ($file in $asciiScan) {
  $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
  $hit = $false
  foreach ($b in $bytes) { if ($b -gt 127) { $hit = $true; break } }
  if ($hit) { $nonAscii += $file.FullName }
}
Check ("Encoding: zero non-ASCII (lei do CEO) em " + $asciiScan.Count + " arquivos") ($nonAscii.Count -eq 0) ("infratores (" + $nonAscii.Count + "): " + ($nonAscii -join ", "))

# --- Cadeado de versao: VERSION tem que bater com a ultima entrada do CHANGELOG (impede drift) ---
$verFile = ""
$verPath = Join-Path $root "VERSION"
if (Test-Path $verPath) { $verFile = ((Get-Content $verPath -ErrorAction SilentlyContinue) -join "").Trim() }
$verLog = ""
$logPath = Join-Path $root "CHANGELOG.md"
if (Test-Path $logPath) {
  $m = Select-String -Path $logPath -Pattern '^\s*##\s*\[([0-9]+\.[0-9]+\.[0-9]+)\]' -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($m) { $verLog = $m.Matches[0].Groups[1].Value }
}
Check ("Versao: VERSION (" + $verFile + ") bate com o topo do CHANGELOG (" + $verLog + ")") ($verFile -ne "" -and $verFile -eq $verLog) ("drift de versao: VERSION=" + $verFile + " vs CHANGELOG=" + $verLog)

# --- Guardrails da LEI de separacao de instancias (engine/governance/instance-separation.md) ---
Write-Host ""
Write-Host "-- Guardrails (separacao de instancias) --"

# (a) Raiz limpa: SO a allowlist canonica (nenhum arquivo vaza, nao so .md).
# Layout canonico em skills/file-organization/SKILL.md. Pastas livres; dotfiles (.git*) ignorados.
$rootAllow = @("README.md","PRIMEIROS-PASSOS.md","AGENTS.md","CLAUDE.md","CONTRIBUTING.md","CHANGELOG.md","CATALOG.md","LICENSE","CREDITS.md","VERSION","alia.config.json","iniciar-alia.bat","atualizar-alia.bat","mission-control.html","MANIFEST.sha256")
$sdir = ""
$cfgP = Join-Path $root "alia.config.json"
if (Test-Path $cfgP) { try { $sdir = "$((Get-Content $cfgP -Raw | ConvertFrom-Json).studio_dir)".Trim() } catch {} }
if ($sdir -eq ".") { $rootAllow += @("state.json","studio.yaml") }   # studio_dir="." => dados na raiz
$leak = Get-ChildItem -Path $root -File -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -notlike ".*" -and $rootAllow -notcontains $_.Name }
Check "Raiz limpa: so a allowlist canonica (nenhum arquivo vaza)" ($leak.Count -eq 0) ("vazou: " + (($leak | ForEach-Object { $_.Name }) -join ", "))

# (b) studio.example limpa: clients/ contem SO o demo (acme-saas). Allowlist do demo - qualquer
# outro id e dado de operador vazando para o produto (nao denylist: nao cravamos nome de cliente real).
$exClients = Join-Path $studio "clients"
$demoAllow = @("acme-saas")
$leaked = @()
if (Test-Path $exClients) {
  $exDirs = Get-ChildItem -Path $exClients -Directory -ErrorAction SilentlyContinue
  foreach ($d in $exDirs) { if ($demoAllow -notcontains $d.Name) { $leaked += $d.Name } }
}
Check "studio.example limpa: so o demo acme-saas em clients/" ($leaked.Count -eq 0) ("cliente fora do demo: " + ($leaked -join ", "))

# --- Validate Artifact (porta de FORMATO do Gate, Frugal Skill) ---
# A skill validate-artifact le os contratos por tipo (validated-artifacts.yaml) e valida um
# Artifact contra o contrato do seu tipo, sem LLM. O item so esta pronto quando o smoke FALHA se
# a regra for violada: fixture valido tem que dar PASS (exit 0); fixture malformado tem que dar
# FAIL (exit 1) com a deviation apontando o desvio exato. Sem o executor, esta regra era contrato
# lido, nao mecanismo - este check garante que o mecanismo existe e discrimina certo do errado.
Write-Host ""
Write-Host "-- Validate Artifact (Frugal Skill, formato) --"
$vaSkill   = Join-Path $root "skills\validate-artifact\validate-artifact.ps1"
$vaSkillMd = Join-Path $root "skills\validate-artifact\SKILL.md"
$fxValid   = Join-Path $root "skills\validate-artifact\fixtures\copy-valid.md"
$fxBad     = Join-Path $root "skills\validate-artifact\fixtures\copy-malformed.md"
Check "Validate Artifact: skill + SKILL.md presentes" ((Test-Path $vaSkill) -and (Test-Path $vaSkillMd))
if ((Test-Path $vaSkill) -and (Test-Path $fxValid) -and (Test-Path $fxBad)) {
  $okOut  = (& $vaSkill -Path $fxValid -Type copy 6>&1) -join "`n"; $okExit  = $LASTEXITCODE
  $badOut = (& $vaSkill -Path $fxBad  -Type copy 6>&1) -join "`n"; $badExit = $LASTEXITCODE
  Check "Validate Artifact: fixture valido -> PASS (exit 0)" (($okExit -eq 0) -and ($okOut -match '\[PASS\]')) ("exit: " + $okExit)
  $badFail = ($badExit -eq 1) -and ($badOut -match '\[FAIL\]')
  $badDeviation = ($badOut -match '(?im)deviation:\s*cta_present')
  Check "Validate Artifact: fixture malformado -> FAIL+deviation (cta_present)" ($badFail -and $badDeviation) ("exit: " + $badExit)
} else {
  Check "Validate Artifact: skill + fixtures presentes" $false "skill ou fixtures ausentes"
}

# --- State Resume (journal append-only + retomar de onde parou, Frugal Skill) ---
# events[] e um journal append-only no state.json: cada evento tem ts, task_id, step (5 passos),
# type e ref. A skill state-resume (a) valida o schema append-only/monotonico (-Validate) e
# (b) por Task aponta o ultimo passo bom / ponto de retomada. O item so esta pronto quando o
# smoke FALHA se a regra for violada: o events[] do demo tem que validar PASS; um fixture com
# ts retrocedendo tem que dar FAIL+deviation; e num fixture de Task interrompida (ultimo evento
# MONITORA/artifact) o resume tem que apontar MONITORA - nao re-rodar do zero. tasks[] segue
# valido (events[] e aditivo): a cadeia E2E acima ja garante isso.
Write-Host ""
Write-Host "-- State Resume (journal append-only, retomada) --"
$srSkill   = Join-Path $root "skills\state-resume\state-resume.ps1"
$srSkillMd = Join-Path $root "skills\state-resume\SKILL.md"
$srFxInt   = Join-Path $root "skills\state-resume\fixtures\state-interrupted.json"
$srFxBad   = Join-Path $root "skills\state-resume\fixtures\state-nonmonotonic.json"
$demoState = Join-Path $studio "state.json"
Check "State Resume: skill + SKILL.md presentes" ((Test-Path $srSkill) -and (Test-Path $srSkillMd))
# (a) o events[] do demo existe e e append-only/monotonico (schema valido).
$demoHasEvents = $false
if ($stateOk -and $state) { $demoHasEvents = (($state.events | Measure-Object).Count -gt 0) }
Check "State Resume: studio.example tem journal events[] (aditivo a tasks[])" $demoHasEvents
if ((Test-Path $srSkill) -and (Test-Path $srFxInt) -and (Test-Path $srFxBad)) {
  # demo: events[] valida append-only/monotonico (PASS exit 0)
  $okOut = (& $srSkill -StatePath $demoState -Validate 6>&1) -join "`n"; $okExit = $LASTEXITCODE
  Check "State Resume: events[] do demo append-only/monotonico -> PASS (exit 0)" (($okExit -eq 0) -and ($okOut -match '\[PASS\]')) ("exit: " + $okExit)
  # fixture adulterado (ts retrocede): tem que reprovar com deviation
  $badOut = (& $srSkill -StatePath $srFxBad -Validate 6>&1) -join "`n"; $badExit = $LASTEXITCODE
  $badFail = ($badExit -eq 1) -and ($badOut -match '\[FAIL\]') -and ($badOut -match '(?im)deviation:.*retrocede')
  Check "State Resume: journal nao-monotonico -> FAIL+deviation (ts retrocede)" $badFail ("exit: " + $badExit)
  # fixture de Task interrompida: resume aponta o passo certo (MONITORA, o ultimo passo bom)
  $resOut = (& $srSkill -StatePath $srFxInt 6>&1) -join "`n"; $resExit = $LASTEXITCODE
  $pointsRight = ($resExit -eq 0) -and ($resOut -match '(?im)INTERROMPIDA') -and ($resOut -match '(?im)RETOMAR de:\s*MONITORA')
  Check "State Resume: Task interrompida -> retoma do passo certo (MONITORA)" $pointsRight ("exit: " + $resExit)
} else {
  Check "State Resume: skill + fixtures presentes" $false "skill ou fixtures ausentes"
}

# --- Apply Safe Output (executor do block_when da provenance, Frugal Skill) ---
# A skill apply-safe-output le o campo provenance do alvo e executa o enforcement que ja vive em
# engine/governance/provenance.yaml:64-66: block_when (nucleo + automation) bloqueia; agent-authored
# por automacao exige diff+evidence. O item so esta pronto quando o smoke FALHA se a regra for
# violada (validado com fixtures): nucleo+automation -> exit!=0 (bloqueio); agent-authored sem diff
# -> reprova; agent-authored com diff+evidence -> permite. Sem isso, provenance.md era promessa
# dependente do modelo - este check garante que o bloqueio e mecanico.
Write-Host ""
Write-Host "-- Apply Safe Output (block_when da provenance) --"
$soSkill   = Join-Path $root "skills\apply-safe-output\apply-safe-output.ps1"
$soSkillMd = Join-Path $root "skills\apply-safe-output\SKILL.md"
$soFxN     = Join-Path $root "skills\apply-safe-output\fixtures\target-nucleo.yaml"
$soFxA     = Join-Path $root "skills\apply-safe-output\fixtures\target-agent-authored.yaml"
Check "Apply Safe Output: skill + SKILL.md presentes" ((Test-Path $soSkill) -and (Test-Path $soSkillMd))
if ((Test-Path $soSkill) -and (Test-Path $soFxN) -and (Test-Path $soFxA)) {
  # (a) nucleo + automation -> BLOQUEIO (exit!=0). O coracao do block_when.
  $nOut = (& $soSkill -Path $soFxN -Source automation 6>&1) -join "`n"; $nExit = $LASTEXITCODE
  $nBlocked = ($nExit -ne 0) -and ($nOut -match '\[FAIL\]') -and ($nOut -match '(?im)block_when:\s*nucleo \+ automation')
  Check "Apply Safe Output: nucleo + automation -> BLOQUEIO (exit!=0)" $nBlocked ("exit: " + $nExit)
  # (b) agent-authored + automation SEM diff -> reprova com deviation.
  $aOut = (& $soSkill -Path $soFxA -Source automation 6>&1) -join "`n"; $aExit = $LASTEXITCODE
  $aReproved = ($aExit -eq 1) -and ($aOut -match '\[FAIL\]') -and ($aOut -match '(?im)deviation:\s*require_for_agent_authored')
  Check "Apply Safe Output: agent-authored sem diff -> reprova (require diff+evidence)" $aReproved ("exit: " + $aExit)
  # (c) agent-authored + automation COM diff+evidence -> permite (exit 0). Discrimina certo do errado.
  $okOut = (& $soSkill -Path $soFxA -Source automation -Diff -Evidence 6>&1) -join "`n"; $okExit = $LASTEXITCODE
  $okAllowed = ($okExit -eq 0) -and ($okOut -match '\[PASS\]')
  Check "Apply Safe Output: agent-authored com diff+evidence -> permite (exit 0)" $okAllowed ("exit: " + $okExit)
} else {
  Check "Apply Safe Output: skill + fixtures presentes" $false "skill ou fixtures ausentes"
}

# --- Sanitize Input (borda que neutraliza texto perigoso, Frugal Skill, sob demanda) ---
# A skill sanitize-input desarma payload de dominio (briefing/email/retorno da pesquisa) por regex:
# tag <x> -> (x), @mention/bot-trigger inertes, URI nao-HTTPS -> (redacted), control chars/ANSI
# removidos, limite de tamanho. Defesa de ENTRADA (o ASCII do smoke e LEI de SAIDA). O item so esta
# pronto quando o smoke FALHA se a regra for violada (validado com fixture hostil): um payload com
# tag + mention + bot-trigger + URI insegura + ANSI tem que sair NEUTRALIZADO, e o link HTTPS seguro
# tem que SOBREVIVER (discrimina hostil de legitimo). Sem o executor, era contrato sem mecanismo.
Write-Host ""
Write-Host "-- Sanitize Input (borda anti-injecao) --"
$siSkill   = Join-Path $root "skills\sanitize-input\sanitize-input.ps1"
$siSkillMd = Join-Path $root "skills\sanitize-input\SKILL.md"
$siFxH     = Join-Path $root "skills\sanitize-input\fixtures\payload-hostile.txt"
Check "Sanitize Input: skill + SKILL.md presentes" ((Test-Path $siSkill) -and (Test-Path $siSkillMd))
if ((Test-Path $siSkill) -and (Test-Path $siFxH)) {
  $siOut = (& $siSkill -Path $siFxH 6>&1) -join "`n"; $siExit = $LASTEXITCODE
  # payload hostil tem que sair NEUTRALIZADO: nenhuma tag <...>, nenhum @mention cru, URI insegura
  # virou (redacted), ANSI/bell removidos, e o relatorio marcou que houve neutralizacao.
  $noRawTag     = ($siOut -notmatch '<[^<>\r\n]+>')
  $noRawMention = ($siOut -notmatch '(?<![\w/])@[A-Za-z0-9]')
  $noBadUri     = ($siOut -notmatch '(?i)(http|ftp|file)://' ) -and ($siOut -notmatch '(?i)javascript:')
  $noAnsi       = ($siOut -notmatch ([char]0x1B)) -and ($siOut -notmatch '[\x00-\x08\x0E-\x1F]')
  $neutralized  = ($siExit -eq 0) -and ($siOut -match '\[PASS\] payload neutralizado') -and $noRawTag -and $noRawMention -and $noBadUri -and $noAnsi
  Check "Sanitize Input: payload hostil -> neutralizado (tag/mention/URI/ANSI desarmados)" $neutralized ("exit: " + $siExit)
  # o link HTTPS legitimo tem que SOBREVIVER (nao e censura cega).
  $httpsSurvives = ($siOut -match 'https://docs\.alia\.flow/ok')
  Check "Sanitize Input: link HTTPS seguro sobrevive (nao censura cega)" $httpsSurvives
} else {
  Check "Sanitize Input: skill + fixture presentes" $false "skill ou fixture ausentes"
}

# --- Manifestos estruturados (pareamento prosa<->yaml) ---
# Todo .yaml de spec do engine que espelha uma prosa (.md de mesmo nome na mesma pasta)
# deve ter os DOIS lados presentes e nao-vazios. Pega o dano que a migracao do framework
# legado causou: manifesto orfao, sem leitor, ou prosa/yaml esvaziada. Os yaml de dado puro
# (sem .md irmao: registry, library, loops.catalog, loop-designer.rules) tem consumidor proprio
# e sao validados em outros checks (T01/T08/T13).
Write-Host ""
Write-Host "-- Manifestos estruturados --"
$allYaml = Get-ChildItem -Path $engine -Filter *.yaml -File -Recurse -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -notmatch "[\\/]_retired[\\/]" }
$pairs = 0
$brokenPairs = @()
foreach ($y in $allYaml) {
  $mdSibling = Join-Path $y.DirectoryName ($y.BaseName + ".md")
  if (Test-Path $mdSibling) {
    $pairs++
    $yEmpty  = ((Get-Item $y.FullName).Length -eq 0)
    $mdEmpty = ((Get-Item $mdSibling).Length -eq 0)
    if ($yEmpty -or $mdEmpty) {
      $rel = $y.FullName.Substring($engine.Length + 1)
      $brokenPairs += $rel + $(if ($yEmpty) { " (yaml vazio)" } else { " (.md vazio)" })
    }
  }
}
Check ("Manifestos: " + $pairs + " pares prosa<->yaml intactos (nenhum orfao/vazio)") ($brokenPairs.Count -eq 0) ("quebrado(s): " + ($brokenPairs -join ", "))

# --- Enforcement de delegacao no ponto de decisao (OPP-74) ---
# A lei DELEGA (orchestration.md) morava so em prosa de boot e reincidiu (02/ago, mOS): em sessao
# longa a Alia voltou a executar dominio com a propria mao. Mesma licao do veto COO: regra que nao
# vira guard de maquina reincide. O guard aqui e duplo: (a) o hook delegation-guard.ps1 existe;
# (b) esta LIGADO em .claude/settings.json como UserPromptSubmit. Projetado-mas-desligado reprova.
Write-Host ""
Write-Host "-- Enforcement de delegacao (hook ligado no ponto de decisao) --"
$dgScript = Join-Path $root "scripts\delegation-guard.ps1"
Check "Delegacao: scripts/delegation-guard.ps1 existe e cita a lei (DELEGA + fonte antes de varrer)" ((Test-Path $dgScript) -and ((ReadText $dgScript) -match 'DELEGA') -and ((ReadText $dgScript) -match 'graphify-out'))
$settingsPath = Join-Path $root ".claude\settings.json"
$settingsTxt = if (Test-Path $settingsPath) { ReadText $settingsPath } else { "" }
Check "Delegacao: hook delegation-guard LIGADO em .claude/settings.json (UserPromptSubmit)" (($settingsTxt -match 'UserPromptSubmit') -and ($settingsTxt -match 'delegation-guard\.ps1'))

# --- Allow-list de tools por persona (declaracao existe e nao e vazia) ---
# orchestration.md:100-107 declara que cada papel tem uma allow-list no campo "tools:" do seu .yaml,
# mas admite que o ENFORCEMENT duro (hook allow|deny por persona) ainda nao existe. O passo verificavel
# AGORA, sem inventar nomes nem empacotar um tool-registry (decisao de arquitetura propria, ver OPP-39),
# e garantir que a allow-list DECLARADA existe: todo agente executor em engine/agents/*.yaml tem um
# campo "tools:" nao-vazio. Sem isso, um agente subiria sem allow-list e o enforcement futuro nao teria
# o que ler. Excecao documentada: squad-creator e o META-AGENTE GERADOR (cria outros agentes); ele
# PRODUZ o campo tools dos integrantes (member_output_contract) e nao CONSOME tools de dominio - nao
# tem allow-list propria por design. O enforcement fail-closed real (allow|deny ligando native_read,
# mcp_manage... a tools concretas) fica pendente do tool-registry (OPP-39).
Write-Host ""
Write-Host "-- Allow-list de tools por persona (declarada e nao-vazia) --"
$agentsDir = Join-Path $engine "agents"
$generatorAgents = @("squad-creator")   # meta-agente: produz tools, nao consome (excecao documentada)
$nonPersonaYaml = @("model-matrix")     # config, nao persona (matriz de modelo por papel)
$noToolsList = @()
$agentYamls = Get-ChildItem -Path $agentsDir -Filter *.yaml -File -ErrorAction SilentlyContinue |
  Where-Object { $nonPersonaYaml -notcontains $_.BaseName }
foreach ($ay in $agentYamls) {
  if ($generatorAgents -contains $ay.BaseName) { continue }
  $ayTxt = ReadText $ay.FullName
  # tools: nao-vazio = lista com >=1 item OU bloco com >=1 hifen. Reprova ausente, "tools:" vazio e "tools: []".
  $hasInline = ($ayTxt -match '(?im)^\s*tools:\s*\[\s*[^\]\s][^\]]*\]')
  $hasBlock  = ($ayTxt -match '(?im)^\s*tools:\s*(#.*)?$') -and ($ayTxt -match '(?im)^\s*tools:\s*(#.*)?\r?\n(\s*#.*\r?\n)*\s*-\s+\S')
  if (-not ($hasInline -or $hasBlock)) { $noToolsList += $ay.Name }
}
Check ("Allow-list: todo agente executor tem campo tools: nao-vazio (" + ($agentYamls.Count - $generatorAgents.Count) + " agentes)") ($noToolsList.Count -eq 0) ("sem allow-list: " + ($noToolsList -join ", "))

# --- Modelo (LLM) por papel: tier declarado e valido na matriz ---
# orchestration.md (Delegacao=isolamento, item 4) declara que cada persona traz model: <tier> e a Alia
# resolve o modelo concreto em agents/model-matrix.yaml ao delegar. Passo verificavel: (a) a matriz
# existe e define os tiers; (b) todo agente executor declara um model: cujo tier existe na matriz.
# Excecao: o gerador (squad-creator) ATRIBUI tier aos integrantes (model_assignment), nao roda dominio.
Write-Host ""
Write-Host "-- Modelo (LLM) por papel (tier declarado e valido) --"
$matrixPath = Join-Path $agentsDir "model-matrix.yaml"
$matrixTxt = if (Test-Path $matrixPath) { ReadText $matrixPath } else { "" }
$tiersOk = ($matrixTxt -match '(?im)^\s*strong:') -and ($matrixTxt -match '(?im)^\s*standard:') -and ($matrixTxt -match '(?im)^\s*fast:')
Check "Modelo: matriz model-matrix.yaml existe e define strong/standard/fast" ((Test-Path $matrixPath) -and $tiersOk)
$badModel = @()
foreach ($ay in $agentYamls) {
  if ($generatorAgents -contains $ay.BaseName) { continue }
  $ayTxt = ReadText $ay.FullName
  $m = [regex]::Match($ayTxt, '(?im)^\s*model:\s*(strong|standard|fast)\b')
  if (-not $m.Success) { $badModel += $ay.Name }
}
Check ("Modelo: todo agente executor declara model: valido (" + ($agentYamls.Count - $generatorAgents.Count) + " agentes)") ($badModel.Count -eq 0) ("sem model valido: " + ($badModel -join ", "))

# --- Marcador de regra inviolavel (convencao "> LEI:") ---
# Os blocos inviolaveis do nucleo carregam o marcador uniforme "> LEI:" para que o inviolavel
# seja inconfundivel e auditavel (constitution.md principios, orchestration.md protocolo,
# quality-gate.md criterios). Convencao documentada em constitution.md.
Write-Host ""
Write-Host "-- Regras inviolaveis (marcador LEI) --"
$leiDocs = @(
  "constitution.md",
  "orchestration.md",
  "governance\quality-gate.md"
)
$leiMissing = @()
foreach ($rel in $leiDocs) {
  $p = Join-Path $engine $rel
  $hasLei = (Test-Path $p) -and ((ReadText $p) -match '(?m)^>\s*LEI:')
  if (-not $hasLei) { $leiMissing += $rel }
}
Check ("Marcador LEI presente nos " + $leiDocs.Count + " docs inviolaveis do nucleo") ($leiMissing.Count -eq 0) ("sem marcador: " + ($leiMissing -join ", "))

# --- Pesquisa segura (LEI anti-runaway) ---
# Garante que a LEI de pesquisa segura existe e e auditavel no produto: a prosa (tools.md) e o
# manifesto (tools.yaml) declaram a trava, e o catalogo de MCP de pesquisa (perplexity) liga so o
# caminho frugal/quota-aware. A trava nos agentes reais e validada pelo smoke do Studio.
Write-Host ""
Write-Host "-- Pesquisa segura (anti-runaway) --"
$toolsMd  = ReadText (Join-Path $engine "tools.md")
$toolsYml = ReadText (Join-Path $engine "tools.yaml")
$lawOk = ($toolsMd -match '(?i)Pesquisa segura') -and ($toolsMd -match 'self_spawn') -and ($toolsYml -match 'research_safety')
Check "LEI de pesquisa segura documentada (tools.md + tools.yaml)" $lawOk

# --- RSI: verificacao independente (CONFERE no passo APLICA) ---
# Fecha o furo do loop auto-referencial: quem PROPOE a melhoria nao a APROVA. O teste do passo APLICA
# roda numa instancia separada. A trava vive pareada (prosa rsi.md + manifesto rsi.yaml).
Write-Host ""
Write-Host "-- RSI: verificacao independente (CONFERE) --"
$rsiMd  = ReadText (Join-Path $engine "rsi\rsi.md")
$rsiYml = ReadText (Join-Path $engine "rsi\rsi.yaml")
$confereOk = ($rsiMd -match '(?i)Verificacao independente') -and ($rsiYml -match 'independent_verification:\s*true')
Check "RSI: CONFERE (verificacao independente) pareado em rsi.md + rsi.yaml" $confereOk "falta o guardrail de verificacao independente na prosa e/ou no yaml"

# --- AUTONOMIA COM FREIO: promocao de memoria autonoma pelo CONFERE, nucleo/gate no humano ---
# Decisao do CEO 30/jun: no fechamento do loop, o CONFERE independente auto-promove a nota que passa
# nos 4 crivos (SEGURA_AUTO) e escala pro humano so a duvidosa/arriscada. A politica machine-checkable
# vive em rsi.yaml (memory_promotion_policy, scope memory_only + os dois desfechos) pareada com a prosa
# do protocolo em session-reflection/SKILL.md. A fronteira dura (autonomia SO em memoria) tem que
# aparecer nos dois lados; sem isso, a regra apodrece como texto solto.
$reflectMd = ReadText (Join-Path $root "skills\session-reflection\SKILL.md")
$freioYaml = ($rsiYml -match '(?im)^\s*memory_promotion_policy:') -and
             ($rsiYml -match '(?im)^\s*scope:\s*memory_only') -and
             ($rsiYml -match '(?im)\bsafe_auto:') -and ($rsiYml -match '(?im)\bescalate_human:')
$freioMd = ($reflectMd -match '(?i)AUTONOMIA COM FREIO') -and ($reflectMd -match '(?i)SEGURA_AUTO') -and
           ($reflectMd -match '(?i)ESCALA_HUMANO') -and ($reflectMd -match '(?i)Fronteira dura')
Check "RSI: AUTONOMIA COM FREIO (promocao de memoria autonoma) pareada em rsi.yaml + SKILL.md" ($freioYaml -and $freioMd) "falta memory_promotion_policy no yaml e/ou o protocolo (SEGURA_AUTO/ESCALA_HUMANO/fronteira dura) na skill"

# --- Contrato de 6 elementos por loop (OPP-57): prosa <-> catalogo pareados ---
# Todo loop instanciado declara discovery_source, state_file, evaluator, isolation, token_cap e
# human_review_point. O contrato tem que viver nos DOIS lados: loops.md (prosa/LEI) e
# loops.catalog.yaml (instance_schema.required + contract_6_elements). Sem o cadeado, a regra
# apodrece como texto solto (mesmo padrao do OPP-56). A presenca nos loops REAIS da instancia e
# cobrada pelo smoke do Studio; aqui o T13 ja cobra no demo.
Write-Host ""
Write-Host "-- Contrato de 6 elementos por loop (OPP-57) --"
$loopsMd  = ReadText (Join-Path $engine "governance\loops.md")
$loopsCat = ReadText (Join-Path $engine "governance\loops.catalog.yaml")
$sixFields = @("discovery_source","state_file","evaluator","isolation","token_cap","human_review_point")
$catHasAll = $true
foreach ($f6 in $sixFields) {
  if ($loopsCat -notmatch [regex]::Escape($f6)) { $catHasAll = $false }
}
$catContract = ($loopsCat -match '(?im)^\s*contract_6_elements:') -and
               ($loopsCat -match '(?ims)required:\s*\[[^\]]*discovery_source[^\]]*human_review_point[^\]]*\]')
$mdContract = ($loopsMd -match '(?i)Contrato de 6 elementos')
foreach ($f6 in $sixFields) {
  if ($loopsMd -notmatch [regex]::Escape($f6)) { $mdContract = $false }
}
Check "Loops: contrato de 6 elementos pareado em loops.md + loops.catalog.yaml" ($catHasAll -and $catContract -and $mdContract) "falta o contrato (6 campos required + contract_6_elements) no catalogo e/ou a secao na prosa"

# --- Teto de gasto duro (OPP-58): contador frugal existe, morde e o runner freia ---
# budget-check.ps1 (sem LLM) le costs[] do state.json e compara com token_cap (per_round/daily).
# O item so esta pronto quando o smoke FALHA se a regra for violada: fixture estourado tem que dar
# exit 1 + PACOTE DE PROVA (o que rodou, quanto gastou, onde estourou, recomendacao); fixture dentro
# do teto tem que dar exit 0. E o runner (run-loops.ps1) tem que CHAMAR o contador no inicio de cada
# volta e PULAR o loop estourado - senao o freio e script solto sem pedal.
Write-Host ""
Write-Host "-- Teto de gasto duro (budget-check, OPP-58) --"
$bcScript = Join-Path $root "scripts\budget-check.ps1"
$bcFxOver = Join-Path $root "scripts\fixtures\budget-state-overbudget.json"
$bcFxUnder = Join-Path $root "scripts\fixtures\budget-state-underbudget.json"
Check "Budget: contador budget-check.ps1 + fixtures presentes" ((Test-Path $bcScript) -and (Test-Path $bcFxOver) -and (Test-Path $bcFxUnder))
if ((Test-Path $bcScript) -and (Test-Path $bcFxOver) -and (Test-Path $bcFxUnder)) {
  $overOut = (& $bcScript -Id "loop-teste" -CapRound 5000 -CapDaily 20000 -StatePath $bcFxOver -Date "2026-07-01" 6>&1) -join "`n"; $overExit = $LASTEXITCODE
  $overBlocked = ($overExit -eq 1) -and ($overOut -match 'PACOTE DE PROVA') -and ($overOut -match 'onde estourou: per_round')
  Check "Budget: fixture estourado -> exit 1 + pacote de prova (onde estourou)" $overBlocked ("exit: " + $overExit)
  $underOut = (& $bcScript -Id "loop-teste" -CapRound 5000 -CapDaily 20000 -StatePath $bcFxUnder -Date "2026-07-01" 6>&1) -join "`n"; $underExit = $LASTEXITCODE
  Check "Budget: fixture dentro do teto -> PASS (exit 0)" (($underExit -eq 0) -and ($underOut -match '\[PASS\]')) ("exit: " + $underExit)
}
$runnerTxt = ReadText (Join-Path $root "scripts\run-loops.ps1")
$runnerBrakes = ($runnerTxt -match 'budget-check\.ps1') -and ($runnerTxt -match '(?i)PULADO')
Check "Budget: run-loops.ps1 chama budget-check e PULA loop estourado" $runnerBrakes
$rsiBudget = ($rsiYml -match '(?im)^\s*source:\s*budget-check')
Check "Budget: rsi.yaml over-budget-path aponta o contador como fonte" $rsiBudget

# --- Avaliador que AGE (OPP-59): criterio Funciona exige prova de EXECUCAO ---
# Mudanca de Gate aprovada pelo CEO em 01/jul (human_approval_for: [gate] respeitado). O verdito
# PASS do criterio 1 exige evidencia de execucao [MEDIDO comando -> saida]; leitura nao e prova;
# postura "quebrado ate prova em contrario"; sem execucao possivel -> Concerns com motivo. O
# cadeado exige prosa (quality-gate.md) e politica (quality-gate.yaml) pareadas, mesmo padrao do
# OPP-56. Os outros 5 criterios NAO mudam.
Write-Host ""
Write-Host "-- Gate: avaliador que AGE (criterio Funciona, OPP-59) --"
$qgMd  = ReadText (Join-Path $engine "governance\quality-gate.md")
$qgYml = ReadText (Join-Path $engine "governance\quality-gate.yaml")
$ageYaml = ($qgYml -match '(?im)^\s*evidence:\s*execution') -and
           ($qgYml -match '(?im)^\s*evaluator_stance:\s*broken-until-proven') -and
           ($qgYml -match '(?im)^\s*proof_by_artifact_type:') -and
           ($qgYml -match '(?im)^\s*when_execution_impossible:\s*Concerns')
$ageMd = ($qgMd -match '(?i)EVIDENCIA DE EXECUCAO') -and ($qgMd -match '\[MEDIDO comando -> saida\]') -and
         ($qgMd -match '(?i)QUEBRADO ATE PROVA EM CONTRARIO') -and ($qgMd -match '(?i)Indisponibilidade nao e aprovacao')
$sixIntact = ($qgYml -match '(?im)^\s*name:\s*Aderente ao DDD') -and ($qgYml -match '(?im)^\s*name:\s*Frugal') -and
             ($qgYml -match '(?im)^\s*name:\s*Rastreavel') -and ($qgYml -match '(?im)^\s*name:\s*Simplicidade / Atrito') -and
             ($qgYml -match '(?im)^\s*name:\s*Fundamentada')
Check "Gate: criterio Funciona exige execucao, pareado em quality-gate.md + .yaml" ($ageYaml -and $ageMd) "falta evidence: execution / broken-until-proven / tipologia / Concerns no yaml e/ou a prosa"
Check "Gate: os outros 5 criterios seguem intactos" $sixIntact

# --- Ativos criticos presentes (guardrail anti-perda) ---
# Causa raiz do incidente da LP (24/jun): ativo critico do produto vivia fora do git e sumiu num move.
# Este check FALHA se um ativo critico nao existir mais no LAB. Mapa em CATALOG.md.
Write-Host ""
Write-Host "-- Ativos criticos (anti-perda) --"
# Sempre exigidos (existem no LAB E no pacote publico)
$always = @{ "Instalador" = "scripts\install.ps1"; "Onboarding" = "onboarding\index.html" }
$missing = @()
foreach ($k in $always.Keys) { if (-not (Test-Path (Join-Path $root $always[$k]))) { $missing += ($k + " (" + $always[$k] + ")") } }
# Marca/governanca: SO exigidos no LAB (brand/ existe). No pacote CLEAN (OSS) nao sobem - IP do dono.
if (Test-Path (Join-Path $root "brand")) {
  if (-not (Test-Path (Join-Path $root "brand\logo\alia-icone.svg"))) { $missing += "Logo (brand\logo\alia-icone.svg)" }
  if (-not (Test-Path (Join-Path $root "CATALOG.md"))) { $missing += "Catalogo (CATALOG.md)" }
  $lpDir = Join-Path $root "brand\landing"
  $lpHas = (Test-Path $lpDir) -and (@(Get-ChildItem $lpDir -Recurse -File -Filter *.html -EA SilentlyContinue).Count -gt 0)
  if (-not $lpHas) { $missing += "LP (brand\landing\*.html)" }
}
Check "Ativos criticos presentes (instalador, onboarding; +marca/LP/catalogo no LAB)" ($missing.Count -eq 0) ("faltando: " + ($missing -join "; "))

$pplxManifest = Join-Path $root "optional-mcps\perplexity\manifest.yaml"
$pplxOk = $false
if (Test-Path $pplxManifest) {
  $pm = ReadText $pplxManifest
  # caminho seguro ligado (pplx_usage para checar quota antes) + deep-research NAO default-on
  $pplxOk = ($pm -match '(?im)name:\s*pplx_usage') -and ($pm -match '(?im)approval:')
}
Check "Catalogo MCP: perplexity declarado com caminho de pesquisa seguro" $pplxOk

# --- Setup / onboarding (sem Python, cerebro obrigatorio) ---
# A Alia exige a memoria interna (Graphify, automatica) antes de operar (skills/setup-alia + AGENTS.md).
# A pagina de boas-vindas e estatica - sem Python, sem servidor, sem POST.
Write-Host ""
Write-Host "-- Setup / onboarding --"
Check "Setup: skill setup-alia presente" (Test-Path (Join-Path $root "skills\setup-alia\SKILL.md"))
Check "Setup: memoria nativa definida (notas; Graphify e turbo opcional)" ((ReadText (Join-Path $root "skills\setup-alia\SKILL.md")) -match '(?i)nativa')
$idx = Join-Path $root "onboarding\index.html"
$noServer = (Test-Path $idx) -and -not ((ReadText $idx) -match 'fetch\("/save"|server\.py')
Check "Onboarding: pagina estatica (sem Python/servidor)" $noServer
$bootSetup = (Test-Path (Join-Path $root "AGENTS.md")) -and ((ReadText (Join-Path $root "AGENTS.md")) -match '(?i)setup-alia')
Check "Setup: AGENTS.md exige o cerebro (setup-alia no boot)" $bootSetup

# --- Git-sync: commit+push sem git (OPP-72) ---
# git-sync.ps1 versiona uma pasta no GitHub via API HTTPS (sem git.exe). O item so esta pronto quando
# o smoke prova que ele discrimina: -DryRun com repo valido -> exit 0 + [DRY-RUN OK]; repo invalido
# -> exit 1 com erro claro (sem tocar a rede, sem token). O instalador tambem tem que apontar pro repo
# publico real (nao mais o placeholder).
Write-Host ""
Write-Host "-- Git-sync (commit+push sem git, OPP-72) --"
$gsScript = Join-Path $root "scripts\git-sync.ps1"
Check "Git-sync: git-sync.ps1 presente" (Test-Path $gsScript)
if (Test-Path $gsScript) {
  $gsOut = (& $gsScript -Repo "owner/repo" -Path (Join-Path $root "onboarding") -DryRun 6>&1) -join "`n"; $gsExit = $LASTEXITCODE
  Check "Git-sync: -DryRun com repo valido -> exit 0 + DRY-RUN OK" (($gsExit -eq 0) -and ($gsOut -match 'DRY-RUN OK')) ("exit: " + $gsExit)
  $gsBad = (& $gsScript -Repo "invalido" -DryRun 6>&1) -join "`n"; $gsBadExit = $LASTEXITCODE
  Check "Git-sync: repo invalido -> exit 1 com erro claro" (($gsBadExit -eq 1) -and ($gsBad -match "owner/repo"))
}
# Instalador aponta pro repo publico real (nao o placeholder ORG/alia-flow).
$instTxt = ReadText (Join-Path $root "scripts\install.ps1")
Check "Git-sync: install.ps1 aponta pro repo publico real (nao placeholder)" (($instTxt -match 'gufarina/alia\.flow') -and ($instTxt -notmatch '\$repo\s*=\s*"ORG/alia-flow"'))

# --- Updater diff-only + contrato de task tipado (1.39.0) ---
# Auditoria de fluxo da 1.39: (a) update-engine.ps1 deixou o espelho cego (/MIR) e virou diff-only
# com -Check (relatorio previo por SHA256) e backup por arquivo dentro do backup datado;
# (b) register-task.ps1 ganhou o contrato tipado (pesquisa|construcao|revisao) com regra dura por
# tipo NO ATO do registro, default open e -Project obrigatorio. O smoke prova executando.
Write-Host ""
Write-Host "-- Updater diff-only + task tipada (1.39.0) --"
$updTxt = ReadText (Join-Path $root "scripts\update-engine.ps1")
Check "Updater: diff-only com -Check (Get-MirrorDiff presente, robocopy /MIR banido)" (($updTxt -match 'Get-MirrorDiff') -and ($updTxt -match '\$Check') -and ($updTxt -notmatch 'robocopy[^\r\n]*/MIR'))
Check "Updater: backup por arquivo antes de sobrescrever/remover (Backup-InstanceFile)" ($updTxt -match 'Backup-InstanceFile')
Check "Updater: -DryRun continua valido (sinonimo de -Check)" ($updTxt -match '\$Check\s*=\s*\$true')
$rtScript = Join-Path $root "scripts\register-task.ps1"
$rtTxt = ReadText $rtScript
Check "Task tipada: -Type com ValidateSet(pesquisa,construcao,revisao)" ($rtTxt -match 'ValidateSet\("pesquisa","construcao","revisao"\)')
Check "Task tipada: Status default open (registrar ANTES de executar)" ($rtTxt -match '\$Status\s*=\s*"open"')
$rtState = Join-Path $studio "state.json"   # demo do studio.example: existe no lab E no pacote
$rtNoProj = (& $rtScript -Client "smoke" -Title "t" -StateFile $rtState -DryRun 6>&1) -join "`n"; $rtNoProjExit = $LASTEXITCODE
Check "Task tipada: sem -Project -> ERRO (exit 1)" (($rtNoProjExit -eq 1) -and ($rtNoProj -match 'sem -Project'))
$rtRev = (& $rtScript -Client "smoke" -Title "t" -Project "p" -Type revisao -Status done -StateFile $rtState -DryRun 6>&1) -join "`n"; $rtRevExit = $LASTEXITCODE
Check "Task tipada: revisao done sem -GateVerdict -> ERRO (exit 1)" (($rtRevExit -eq 1) -and ($rtRev -match 'verdito'))
$rtPesq = (& $rtScript -Client "acme-saas" -Title "t" -Project "p" -Type pesquisa -Artifact "a.md" -Specialist "quinn" -StateFile $rtState -DryRun 6>&1) -join "`n"; $rtPesqExit = $LASTEXITCODE
Check "Task tipada: pesquisa dispensa base_artifact (sem aviso falso, exit 0)" (($rtPesqExit -eq 0) -and ($rtPesq -notmatch 'AVISO'))

# --- Growth: especialista + skills de marketing (OPP-73) ---
# 1 especialista novo (growth) + 16 skills adaptadas do OpenClaudia (MIT) em 3 ondas. Guardrails:
# (a) presenca do par growth.md/.yaml; (b) presenca das 16 skills; (c) toda skill do pack declara
# provenance: openclaudia e o contrato Alia Flow (delegacao+Task+Gate+grounding); (d) roteamento da
# lente marketing -> growth no alia.yaml; (e) growth passa pelo quality-gate com grounding required.
Write-Host ""
Write-Host "-- Growth: especialista + 16 skills marketing (OPP-73) --"
Check "Growth: par growth.md + growth.yaml presente" ((Test-Path (Join-Path $agentsDir "growth.md")) -and (Test-Path (Join-Path $agentsDir "growth.yaml")))
$growthTxt = ReadText (Join-Path $agentsDir "growth.yaml")
Check "Growth: gate quality-gate + grounding required declarados" (($growthTxt -match '(?im)^\s*gate:\s*quality-gate') -and ($growthTxt -match '(?im)^\s*grounding:\s*required'))
$aliaTxt = ReadText (Join-Path $agentsDir "alia.yaml")
Check "Growth: lente marketing roteia pro growth (alia.yaml)" (($aliaTxt -match '(?im)lens:\s*marketing') -and ($aliaTxt -match '(?im)route_to:\s*growth'))
$mktSkills = @(
  "launch-strategy","icp-builder","competitor-analysis","pricing-strategy","page-cro","seo-audit",
  "content-strategy","content-calendar","write-blog","social-content","thread-writer","email-sequence","newsletter",
  "google-analytics","search-console","brand-monitor"
)
$mktMissing = @(); $mktNoProv = @(); $mktNoContract = @()
foreach ($ms in $mktSkills) {
  $msPath = Join-Path $root ("skills\" + $ms + "\SKILL.md")
  if (-not (Test-Path $msPath)) { $mktMissing += $ms; continue }
  $msTxt = ReadText $msPath
  if ($msTxt -notmatch '(?im)^\s*provenance:\s*openclaudia') { $mktNoProv += $ms }
  if ($msTxt -notmatch '(?i)Contrato Alia Flow') { $mktNoContract += $ms }
}
Check ("Growth: 16 skills do pack presentes (" + (16 - $mktMissing.Count) + "/16)") ($mktMissing.Count -eq 0) ("faltando: " + ($mktMissing -join ", "))
Check "Growth: toda skill do pack declara provenance: openclaudia" ($mktNoProv.Count -eq 0) ("sem provenance: " + ($mktNoProv -join ", "))
Check "Growth: toda skill do pack carrega o contrato Alia Flow (delegacao+Task+Gate+grounding)" ($mktNoContract.Count -eq 0) ("sem contrato: " + ($mktNoContract -join ", "))

# --- Release (open source) ---
# O produto e empacotavel: LICENSE (MIT), o empacotador CLEAN e o instalador de 1 linha existem,
# e o README ensina a instalar. (A publicacao no GitHub e o passo manual do DevOps.)
Write-Host ""
Write-Host "-- Release (open source) --"
Check "Release: LICENSE presente (MIT)" (Test-Path (Join-Path $root "LICENSE"))
Check "Release: empacotador package-release.ps1 presente" (Test-Path (Join-Path $root "scripts\package-release.ps1"))
Check "Release: instalador install.ps1 presente" (Test-Path (Join-Path $root "scripts\install.ps1"))
Check "Release: instalador e transacional (backup + rollback)" ((ReadText (Join-Path $root "scripts\install.ps1")) -match 'Backup-Dest' -and (ReadText (Join-Path $root "scripts\install.ps1")) -match 'Restore-Dest' -and (ReadText (Join-Path $root "scripts\install.ps1")) -match 'ROLLBACK')
Check "Release: updater online presente (update-online.ps1)" (Test-Path (Join-Path $root "scripts\update-online.ps1"))
Check "Release: updater online e transacional e protege dados do operador" ((ReadText (Join-Path $root "scripts\update-online.ps1")) -match 'Restore-Engine' -and (ReadText (Join-Path $root "scripts\update-online.ps1")) -match 'Assert-SafeCopySet' -and (ReadText (Join-Path $root "scripts\update-online.ps1")) -match 'state\.json')
Check "Release: atualizar-alia.bat escolhe o updater certo (lab local vs online)" ((ReadText (Join-Path $root "atualizar-alia.bat")) -match 'update-engine\.ps1' -and (ReadText (Join-Path $root "atualizar-alia.bat")) -match 'update-online\.ps1')
Check "Release: doctor.ps1 presente (diagnostico read-only)" (Test-Path (Join-Path $root "scripts\doctor.ps1"))
Check "Release: doctor.ps1 suporta saida -Json" ((ReadText (Join-Path $root "scripts\doctor.ps1")) -match '\[switch\]\$Json')
Check "Release: semantic-lint.ps1 presente (linter de linguagem ubiqua)" (Test-Path (Join-Path $root "scripts\semantic-lint.ps1"))
Check "Release: guard-core.ps1 presente (sentinela de fronteira do nucleo)" (Test-Path (Join-Path $root "scripts\guard-core.ps1"))
& (Join-Path $root "scripts\guard-core.ps1") *> $null
Check "Nucleo: integro vs baseline (sentinela; mudanca de nucleo exige -AllowCore)" ($LASTEXITCODE -eq 0)
Check "Release: semantic-lint reusa a fonte de verdade (le CLAIMS.md, nao duplica lista)" ((ReadText (Join-Path $root "scripts\semantic-lint.ps1")) -match 'CLAIMS\.md' -and (ReadText (Join-Path $root "scripts\semantic-lint.ps1")) -match 'GUARD')
Check "Release: workflow de CI presente (.github/workflows/smoke.yml)" (Test-Path (Join-Path $root ".github\workflows\smoke.yml"))
Check "Release: CI roda o trilho e o doctor" ((ReadText (Join-Path $root ".github\workflows\smoke.yml")) -match 'smoke-test\.ps1' -and (ReadText (Join-Path $root ".github\workflows\smoke.yml")) -match 'doctor\.ps1')
Check "Release: README ensina a instalar (cita install.ps1)" ((ReadText (Join-Path $root "README.md")) -match 'install\.ps1')
Check "Release: CONTRIBUTING.md presente" (Test-Path (Join-Path $root "CONTRIBUTING.md"))
Check "Release: docs/COMPATIBILIDADE.md presente (degradacao honesta por IDE)" (Test-Path (Join-Path $root "docs\COMPATIBILIDADE.md"))
Check "Release: manifesto de integridade (make/verify-manifest.ps1) presente" ((Test-Path (Join-Path $root "scripts\make-manifest.ps1")) -and (Test-Path (Join-Path $root "scripts\verify-manifest.ps1")))
Check "Release: package-release gera o MANIFEST.sha256" ((ReadText (Join-Path $root "scripts\package-release.ps1")) -match 'make-manifest\.ps1')
Check "Release: docs/INTEGRIDADE.md explica a verificacao" (Test-Path (Join-Path $root "docs\INTEGRIDADE.md"))
Check "Release: README aponta pra COMPATIBILIDADE.md" ((ReadText (Join-Path $root "README.md")) -match 'COMPATIBILIDADE\.md')
Check "Release: templates .github presentes (issue + PR)" ((Test-Path (Join-Path $root ".github\ISSUE_TEMPLATE\bug_report.md")) -and (Test-Path (Join-Path $root ".github\PULL_REQUEST_TEMPLATE.md")))
Check "Release: README cita o caminho real do scorer de ablacao" ((ReadText (Join-Path $root "README.md")) -match 'studio\.example/clients/acme-saas/tests/knowledge-ablation/score\.py')
Check "Release: o scorer de ablacao citado existe em disco" (Test-Path (Join-Path $root "studio.example\clients\acme-saas\tests\knowledge-ablation\score.py"))
Check "Release: CONTRIBUTING e .github no ship list do package-release" ((ReadText (Join-Path $root "scripts\package-release.ps1")) -match 'CONTRIBUTING\.md' -and (ReadText (Join-Path $root "scripts\package-release.ps1")) -match '\.github')
# Benchmarks entregues (TASK-015): a promessa "rode os benchmarks na sua maquina" so e verdade se
# a pasta viajar no pacote. O 1o check olha o ship list; o 2o roda no proprio pacote (o smoke do
# pacote usa $root = raiz do pacote) e prova que o runner chegou de verdade no destino.
Check "Release: benchmarks/ no ship list do package-release" ((ReadText (Join-Path $root "scripts\package-release.ps1")) -match '"benchmarks"')
Check "Release: benchmarks/run-all.py presente (runner dos 5 benchmarks)" ((Test-Path (Join-Path $root "benchmarks\run-all.py")) -and (Test-Path (Join-Path $root "benchmarks\README.md")))

# --- Ativacao: o produto tem que LIGAR sozinho quando o operador abre a pasta no Claude Code ---
# Bloqueador de release medido 03/ago: Claude Code le CLAUDE.md, NAO AGENTS.md (confirmado na doc
# oficial, code.claude.com/docs/en/memory, secao "AGENTS.md"). AGENTS.md sozinho era
# projetado-mas-desligado pra quem abre a pasta no Claude Code - a Alia nunca aparecia; virava
# agente generico. $root aqui e dinamico (definido na linha 8 deste script): quando este MESMO
# smoke roda dentro do pacote (package-release.ps1 chama scripts\smoke-test.ps1 do OUTPUT, nao da
# oficina), estes checks provam que os arquivos de ativacao chegaram no pacote de verdade - nao
# so que o ship-list os cita. Mesmo padrao de defesa em profundidade usado acima pros benchmarks.
Write-Host ""
Write-Host "-- Ativacao (CLAUDE.md/AGENTS.md/comando /alia) --"
Check "Ativacao: CLAUDE.md do produto presente na raiz (o que o Claude Code de fato le)" (Test-Path (Join-Path $root "CLAUDE.md"))
Check "Ativacao: CLAUDE.md importa o AGENTS.md (@AGENTS.md, fonte unica da identidade)" ((ReadText (Join-Path $root "CLAUDE.md")) -match '@AGENTS\.md')
Check "Ativacao: comando /alia presente (.claude/commands/alia.md, rede de seguranca)" (Test-Path (Join-Path $root ".claude\commands\alia.md"))
Check "Ativacao: .claude/settings.json presente (liga os hooks de governanca do proprio produto)" (Test-Path (Join-Path $root ".claude\settings.json"))
Check "Release: CLAUDE.md do produto no ship list do package-release.ps1" ((ReadText (Join-Path $root "scripts\package-release.ps1")) -match '"CLAUDE\.md"')
Check "Release: .claude (settings.json + comando /alia) no ship list do package-release.ps1" ((ReadText (Join-Path $root "scripts\package-release.ps1")) -match '"\.claude"')

# --- Guard de vetos: termo derrubado pelo CEO nunca vive no motor (07/jul) ---
# Le os GUARD: do docs/CLAIMS.md e reprova se qualquer regex aparecer em engine/.
# Transforma "confie que o veto foi cumprido" em "o teste prova". Molde do check de termo legado.
Write-Host ""
Write-Host "-- Guard de vetos (CLAIMS.md vs motor) --"
$claimsPath = Join-Path $root "docs\CLAIMS.md"
if (Test-Path $claimsPath) {
  $guards = @()
  foreach ($line in (Get-Content -LiteralPath $claimsPath -Encoding UTF8)) {
    if ($line -match '^\s*GUARD:\s*(.+?)\s*$') { $guards += $Matches[1] }
  }
  Check "Guard: CLAIMS.md declara termos proibidos (GUARD:)" ($guards.Count -gt 0) "nenhum GUARD: no CLAIMS.md"
  $engineFilesAll = Get-ChildItem -LiteralPath $engine -Recurse -File -Include *.md,*.yaml -ErrorAction SilentlyContinue
  foreach ($g in $guards) {
    $hits = @()
    foreach ($f in $engineFilesAll) {
      $txt = [System.IO.File]::ReadAllText($f.FullName)
      if ($txt -cmatch $g) { $hits += $f.FullName.Substring($engine.Length + 1) }
    }
    Check ("Guard: veto ausente do motor -> /" + $g + "/") ($hits.Count -eq 0) ("vazou em: " + ($hits -join ", "))
  }
} else {
  # docs/CLAIMS.md e doc interno (engine/governance/public-surface.md): NUNCA viaja no pacote
  # publico nem no repo publico (esta no .gitignore de la de proposito). Um clone/instalacao
  # publica legitimamente nao tem este arquivo - isso NAO e defeito. Degrada com honestidade:
  # nunca FAIL silencioso (era o que quebrava o smoke em clone limpo) nem PASS falso (fingir que
  # o guard rodou quando na verdade nao ha nada pra checar). $guards fica vazio de proposito, o
  # que faz os dois blocos de guard seguintes (superficie publica + scripts) pularem tambem.
  $guards = @()
  Warn "Guard: docs/CLAIMS.md ausente - guard de vetos pulado (doc interno, so existe na oficina)" $false "CLAIMS.md nao viaja no pacote/repo publico por LEI; nada a checar aqui"
}

# --- Guard de vetos: SUPERFICIE PUBLICA (o que o usuario final le) ---
# Mesma fonte unica (as linhas GUARD: do docs/CLAIMS.md - a lista NAO e duplicada aqui), agora
# tambem sobre os arquivos que chegam no cliente. Nasceu do incidente de 07/jul: o guard so
# olhava engine/, entao o lema APOSENTADO sobreviveu no fim do README (que vai no pacote
# publico), o cargo vetado "COO" continuou sendo ensinado no BRAND.md e o pack usava os dois.
#
# USO VIVO vs REGISTRO: doc de marca CITA o termo derrubado de proposito, para ensinar a nao
# usar. O guard so acusa USO VIVO. Uma linha e REGISTRO (ignorada) quando:
#   (a) traz um marcador de registro na propria linha: veto/vetado/derrubado/proibido/
#       aposentado/reprovado; ou
#   (b) esta sob um titulo de secao de registro (ex.: "## Guarda de vetos").
# Qualquer outra ocorrencia conta como uso vivo e REPROVA.
#
# FORA DO ESCOPO de proposito (historico, planejamento e build regerado - ninguem le como peca):
#   CHANGELOG.md, opportunities/, _retired/, _drafts/, _dev/, _backups/, release/ e o proprio
#   docs/CLAIMS.md (que E a lista de vetos).
# DIVIDA DECLARADA: brand/landing/ fica FORA por enquanto - a LP canonica tem vetos vivos
#   conhecidos e sera reescrita na TASK-016. Quando a reescrita entrar, basta acrescentar
#   "brand\landing" em $psDirs abaixo e a LP passa a ser protegida. Divida declarada, nunca
#   silenciosa.

function VetoScan([string[]]$files, [string[]]$guards) {
  $regLine    = '(?i)(vetad|veto|derrubad|proibid|aposentad|reprovad)'
  $regHeading = '(?i)(vetos?|proibid|banid|nunca usamos)'
  $hits = @()
  foreach ($file in $files) {
    if (-not (Test-Path -LiteralPath $file)) { continue }
    $inRegistrySection = $false
    $n = 0
    foreach ($line in (Get-Content -LiteralPath $file -Encoding UTF8)) {
      $n++
      if ($line -match '^\s{0,3}#{1,6}\s+(.+)$') { $inRegistrySection = ($Matches[1] -match $regHeading) }
      if ($inRegistrySection) { continue }
      if ($line -match $regLine) { continue }
      foreach ($g in $guards) {
        if ($line -cmatch $g) {
          $hits += [PSCustomObject]@{ file = $file; line = $n; term = $g; text = $line }
        }
      }
    }
  }
  return ,$hits
}

Write-Host ""
Write-Host "-- Guard de vetos (CLAIMS.md vs superficie publica) --"
if ($guards -and $guards.Count -gt 0) {
  # Escopo: arquivos de topo que entram no pacote + onboarding/ + docs/ + brand/marketing-pack-*.md
  $psFiles = @()
  foreach ($t in @("README.md","PRIMEIROS-PASSOS.md","CONTRIBUTING.md","CREDITS.md")) {
    $tp = Join-Path $root $t
    if (Test-Path -LiteralPath $tp) { $psFiles += $tp }
  }
  $psDirs = @("onboarding","docs")   # brand\landing entra aqui depois da TASK-016
  foreach ($d in $psDirs) {
    $dp = Join-Path $root $d
    if (-not (Test-Path -LiteralPath $dp)) { continue }
    # Exclusao avaliada no caminho RELATIVO a $root: o pacote gerado mora em release\alia-flow\,
    # entao filtrar por caminho absoluto zerava o escopo dentro do proprio pacote (falso verde).
    $psFiles += @(Get-ChildItem -LiteralPath $dp -Recurse -File -Include *.md,*.html -ErrorAction SilentlyContinue |
      Where-Object { ($_.FullName.Substring($root.Length + 1) -notmatch '\\(_retired|_drafts|_dev|_backups|release)\\') -and ($_.Name -ne "CLAIMS.md") -and ($_.Name -ne "CHANGELOG.md") } |
      ForEach-Object { $_.FullName })
  }
  $brandDir = Join-Path $root "brand"
  if (Test-Path -LiteralPath $brandDir) {
    $psFiles += @(Get-ChildItem -LiteralPath $brandDir -File -Filter "marketing-pack-*.md" -ErrorAction SilentlyContinue |
      ForEach-Object { $_.FullName })
  }
  Check ("Guard publico: escopo montado (" + $psFiles.Count + " arquivos de superficie)") ($psFiles.Count -gt 0) "nenhum arquivo de superficie encontrado"

  # Prova 1 (pega): a fixture suja tem um USO VIVO e uma linha de REGISTRO do mesmo termo.
  # O guard tem que acusar a primeira e ignorar a segunda - senao vira alarme falso e o time
  # aprende a ignorar o smoke.
  $fxDirty = Join-Path $root "scripts\fixtures\superficie-publica-suja.md"
  Check "Guard publico: fixture de prova presente" (Test-Path -LiteralPath $fxDirty)
  if (Test-Path -LiteralPath $fxDirty) {
    $fxHits = @(VetoScan @($fxDirty) $guards)
    $fxLive = @($fxHits | Where-Object { $_.text -match 'USO VIVO' })
    $fxReg  = @($fxHits | Where-Object { $_.text -match 'REGISTRO' })
    Check "Guard publico: REPROVA uso vivo de termo derrubado (fixture suja)" ($fxLive.Count -gt 0) "o guard nao pegou o uso vivo da fixture"
    Check "Guard publico: nao acusa linha que apenas REGISTRA o veto (sem falso positivo)" ($fxReg.Count -eq 0) ("acusou registro: " + (($fxReg | ForEach-Object { $_.term }) -join ", "))
  }

  # Prova 2 (nao da falso positivo): a superficie publica de hoje esta limpa, termo a termo.
  $psHits = @(VetoScan $psFiles $guards)
  foreach ($g in $guards) {
    $gh = @($psHits | Where-Object { $_.term -eq $g } |
      ForEach-Object { $_.file.Substring($root.Length + 1) + ":" + $_.line })
    Check ("Guard publico: veto ausente da superficie -> /" + $g + "/") ($gh.Count -eq 0) ("uso vivo em: " + ($gh -join ", "))
  }
}

# --- Guard de vetos: SCRIPTS QUE GERAM DADO NOVO (achado H5) ---
# Mesma fonte unica ($guards, ja lido do docs/CLAIMS.md - a lista NAO e duplicada aqui), agora
# sobre o CODIGO. O furo: um .ps1 que ESCREVE texto de marca/papel dentro de um arquivo que ele
# gera (state.json, studio.json, client.json) injeta o termo derrubado em dado FRESCO a cada
# execucao, e nenhum guard de doc enxerga - eles varrem texto de doc, nao a saida de script.
# Foi assim que o cargo derrubado sobreviveu no migrate-to-studio.ps1 ate 02/ago.
#
# USO VIVO vs REGISTRO: uma linha e REGISTRO (ignorada) quando traz um marcador de veto na
# propria linha (veto/vetado/derrubado/proibido/aposentado/reprovado) ou quando cita a fonte do
# guard (docs/CLAIMS.md, GUARD:) - e o caso do bloco que le a lista. Qualquer outra ocorrencia
# conta como uso vivo e REPROVA.
# Escopo: scripts/*.ps1 sem recursao; scripts/fixtures/ fica de fora de proposito (e a prova).

function ScriptVetoScan([string[]]$files, [string[]]$guards) {
  $regRegistro = '(?i)(vetad|veto|derrubad|proibid|aposentad|reprovad|CLAIMS\.md|GUARD:)'
  $hits = @()
  foreach ($file in $files) {
    if (-not (Test-Path -LiteralPath $file)) { continue }
    $n = 0
    foreach ($line in (Get-Content -LiteralPath $file -Encoding UTF8)) {
      $n++
      if ($line -match $regRegistro) { continue }
      foreach ($g in $guards) {
        if ($line -cmatch $g) {
          $hits += [PSCustomObject]@{ file = $file; line = $n; term = $g; text = $line }
        }
      }
    }
  }
  return ,$hits
}

Write-Host ""
Write-Host "-- Guard de vetos (CLAIMS.md vs scripts que geram dado) --"
if ($guards -and $guards.Count -gt 0) {
  $scFiles = @(Get-ChildItem -LiteralPath (Join-Path $root "scripts") -File -Filter *.ps1 -ErrorAction SilentlyContinue |
    ForEach-Object { $_.FullName })
  Check ("Guard scripts: escopo montado (" + $scFiles.Count + " scripts)") ($scFiles.Count -gt 0) "nenhum .ps1 em scripts/"

  # Prova 1 (pega): fixture de um script que GERA dado gravando o cargo derrubado, mais uma
  # linha que so registra a decisao. Tem que acusar a primeira e ignorar a segunda.
  $fxScript = Join-Path $root "scripts\fixtures\script-gera-dado-sujo.ps1"
  Check "Guard scripts: fixture de prova presente" (Test-Path -LiteralPath $fxScript)
  if (Test-Path -LiteralPath $fxScript) {
    $sfHits = @(ScriptVetoScan @($fxScript) $guards)
    $sfLive = @($sfHits | Where-Object { $_.text -match 'USO VIVO' })
    $sfReg  = @($sfHits | Where-Object { $_.text -match 'REGISTRO' })
    Check "Guard scripts: REPROVA script que grava termo derrubado (fixture suja)" ($sfLive.Count -gt 0) "o guard nao pegou o uso vivo da fixture"
    Check "Guard scripts: nao acusa linha que apenas REGISTRA o veto (sem falso positivo)" ($sfReg.Count -eq 0) ("acusou registro: " + (($sfReg | ForEach-Object { $_.term }) -join ", "))
  }

  # Prova 2 (nao da falso positivo): os scripts da casa estao limpos, termo a termo.
  $scHits = @(ScriptVetoScan $scFiles $guards)
  foreach ($g in $guards) {
    $sh = @($scHits | Where-Object { $_.term -eq $g } |
      ForEach-Object { $_.file.Substring($root.Length + 1) + ":" + $_.line })
    Check ("Guard scripts: veto ausente de scripts/*.ps1 -> /" + $g + "/") ($sh.Count -eq 0) ("uso vivo em: " + ($sh -join ", "))
  }
}

# --- Response Guard: o freio na porta de saida (M1, OPP-74 continuacao 03/ago) ---
# A lei DELEGA so tinha guarda na ENTRADA (delegation-guard.ps1, so lembra) e no FIM da sessao
# (session-reflection.ps1, tarde demais). response-guard.ps1 e hook de Stop: roda a CADA turno
# sobre o transcript real. Regra de ouro (o motor ja aprendeu isso do proprio OPP-74): um check
# que so ve o arquivo no disco reprova "projetado-mas-desligado" como se fosse "ligado" - por
# isso o 2o check abaixo tem que provar que o hook Stop esta LIGADO em .claude/settings.json.
Write-Host ""
Write-Host "-- Response Guard: o freio na porta de saida (M1) --"
$rgScript = Join-Path $root "scripts\response-guard.ps1"
$rgTxt = if (Test-Path -LiteralPath $rgScript) { ReadText $rgScript } else { "" }
Check "Response Guard: script existe e cita as 2 regras (DELEGA/GROUNDING)" ((Test-Path -LiteralPath $rgScript) -and ($rgTxt -match 'DELEGA') -and ($rgTxt -match 'GROUNDING'))

$settingsPath = Join-Path $root ".claude\settings.json"
$stopWired = $false
if (Test-Path -LiteralPath $settingsPath) {
  try {
    $settingsJson = (ReadText $settingsPath) | ConvertFrom-Json
    foreach ($stopEntry in @($settingsJson.hooks.Stop)) {
      foreach ($h in @($stopEntry.hooks)) {
        if ("$($h.command)" -match 'response-guard\.ps1') { $stopWired = $true }
      }
    }
  } catch { }
}
Check "Response Guard: hook Stop LIGADO em .claude/settings.json (nao so projetado)" $stopWired "projetado-mas-desligado reprova - o check tem que provar que esta LIGADO no settings, nao so que o arquivo existe"

$rgYamlPath = Join-Path $engine "governance\response-guard.yaml"
$rgYamlTxt = if (Test-Path -LiteralPath $rgYamlPath) { ReadText $rgYamlPath } else { "" }
Check "Response Guard: response-guard.yaml existe com mode valido (aviso|bloqueio)" ((Test-Path -LiteralPath $rgYamlPath) -and ($rgYamlTxt -match '(?m)^\s*mode\s*:\s*(aviso|bloqueio)\s*$'))

# --- Lentes: lista canonica + arquetipo agent-engineer (M2) --
# alia.yaml (routing.lenses) virou a UNICA lista de lentes; orchestration.md/constitution.md/
# constitution.yaml/alia.md pararam de duplicar e passaram a apontar pra ca. A lente nova
# "engenharia-de-agente" resolve pro arquetipo "agent-engineer" (par .md+.yaml em engine/agents/).
Write-Host ""
Write-Host "-- Lentes: lista canonica + arquetipo agent-engineer (M2) --"
$aliaYamlTxt = ReadText (Join-Path $agentsDir "alia.yaml")
$constMdTxt = ReadText (Join-Path $engine "constitution.md")
$constYamlTxt = ReadText (Join-Path $engine "constitution.yaml")
$orchTxt = ReadText (Join-Path $engine "orchestration.md")
$aliaMdTxt = ReadText (Join-Path $agentsDir "alia.md")
$lentesPointerOk = ($aliaYamlTxt -match 'lenses:') -and ($constMdTxt -match 'alia\.yaml') -and ($constYamlTxt -match 'alia\.yaml') -and ($orchTxt -match 'alia\.yaml') -and ($aliaMdTxt -match 'alia\.yaml')
Check "Lentes: lista canonica unica em alia.yaml (routing.lenses); constitution.md/.yaml + orchestration.md + alia.md apontam pra ca, nao duplicam" $lentesPointerOk

$aeMd = Join-Path $agentsDir "agent-engineer.md"
$aeYaml = Join-Path $agentsDir "agent-engineer.yaml"
$lentePronta = ($aliaYamlTxt -match 'lens:\s*engenharia-de-agente') -and ($aliaYamlTxt -match 'route_to:\s*agent-engineer') -and (Test-Path -LiteralPath $aeMd) -and (Test-Path -LiteralPath $aeYaml)
Check "Lentes: engenharia-de-agente resolve pro arquetipo agent-engineer (par .md + .yaml presente)" $lentePronta

# --- Ledger: contrato -Specialist obrigatorio, validado no ato (M3) ---
# register-task.ps1 perdeu o default "alia" pra -Specialist. 5 cenarios provam o contrato inteiro:
# sem -Specialist reprova; especialista fora do squad reprova citando os ids validos; especialista
# valido passa; "alia" (a coordenadora) so registra com -OperatorOrder (excecao auditavel a LEI DELEGA).
Write-Host ""
Write-Host "-- Ledger: contrato -Specialist obrigatorio (M3) --"
$ldNoSpec = (& $rtScript -Client "alia-flow-lab" -Title "t" -Project "p" -StateFile $rtState -DryRun 6>&1) -join "`n"; $ldNoSpecExit = $LASTEXITCODE
Check "Ledger: sem -Specialist -> exit 1" ($ldNoSpecExit -eq 1) ("exit: " + $ldNoSpecExit)
$ldBadSpec = (& $rtScript -Client "acme-saas" -Title "t" -Project "p" -Specialist "nao-existe" -StateFile $rtState -DryRun 6>&1) -join "`n"; $ldBadSpecExit = $LASTEXITCODE
Check "Ledger: -Specialist fora do squad -> exit 1 citando ids validos" (($ldBadSpecExit -eq 1) -and ($ldBadSpec -match 'quinn')) ("exit: " + $ldBadSpecExit)
$ldOkSpec = (& $rtScript -Client "alia-flow-lab" -Title "t" -Project "p" -Specialist "quality-runner" -StateFile $rtState -DryRun 6>&1) -join "`n"; $ldOkSpecExit = $LASTEXITCODE
Check "Ledger: -Specialist valido -> exit 0" ($ldOkSpecExit -eq 0) ("exit: " + $ldOkSpecExit)
$ldAliaNoOrder = (& $rtScript -Client "alia-flow-lab" -Title "t" -Project "p" -Specialist "alia" -StateFile $rtState -DryRun 6>&1) -join "`n"; $ldAliaNoOrderExit = $LASTEXITCODE
Check "Ledger: -Specialist alia sem -OperatorOrder -> exit 1" ($ldAliaNoOrderExit -eq 1) ("exit: " + $ldAliaNoOrderExit)
$ldAliaOrder = (& $rtScript -Client "alia-flow-lab" -Title "t" -Project "p" -Specialist "alia" -OperatorOrder -StateFile $rtState -DryRun 6>&1) -join "`n"; $ldAliaOrderExit = $LASTEXITCODE
Check "Ledger: -Specialist alia com -OperatorOrder -> exit 0" ($ldAliaOrderExit -eq 0) ("exit: " + $ldAliaOrderExit)

# --- Law Ledger: toda LEI declarada tem entrada arquivo:linha (M4) ---
# Varre engine/**.md atras dos 3 marcadores de declaracao de LEI e reprova se algum arquivo com
# marcador nao tiver NENHUMA entrada "arquivo:linha" pra ele em law-ledger.md. Checagem por
# ARQUIVO (nao pela linha exata do marcador): o proprio ledger cita, de proposito, a linha da
# frase normativa (ex.: public-surface.md:8), nao a linha do titulo "# LEI ..." (linha 1) - exigir
# a mesma linha do marcador daria falso-positivo numa cobertura legitima. O que importa e que o
# ARQUIVO nunca fique de fora do ledger. Barra: o ledger escreve com "/", Get-ChildItem devolve
# "\" no Windows - testa as duas formas.
Write-Host ""
Write-Host "-- Law Ledger: toda LEI com entrada no ledger (M4) --"
$lawLedgerPath = Join-Path $engine "governance\law-ledger.md"
$lawLedgerTxt = ReadText $lawLedgerPath
$leiMdFiles = @(Get-ChildItem -LiteralPath $engine -Filter *.md -Recurse -File -ErrorAction SilentlyContinue)
$leiMarker = '^(>\s*LEI|##\s*LEI|#\s*LEI)\b'
$leiMissing = New-Object System.Collections.Generic.List[string]
foreach ($f in $leiMdFiles) {
  $lines = Get-Content -LiteralPath $f.FullName -Encoding UTF8
  $hasLei = $false
  foreach ($ln in $lines) { if ($ln -cmatch $leiMarker) { $hasLei = $true; break } }
  if (-not $hasLei) { continue }
  $relFwd = $f.FullName.Substring($root.Length + 1).Replace('\', '/')
  $relBack = $relFwd.Replace('/', '\')
  $covered = ($lawLedgerTxt -match [regex]::Escape($relFwd) + ':\d+') -or ($lawLedgerTxt -match [regex]::Escape($relBack) + ':\d+')
  if (-not $covered) { $leiMissing.Add($relFwd) }
}
Check "Law Ledger: toda declaracao de LEI em engine/**.md tem entrada arquivo:linha em law-ledger.md" ($leiMissing.Count -eq 0) ("sem entrada no ledger: " + ($leiMissing -join ", "))

# --- Drift de versao: oficina vs release vs produto (M5, AVISO - nunca reprova) ---
# So o CEO resolve drift entre as 3 versoes (publicar e decisao dele). Isto e AVISO, nao Check:
# nunca pode reprovar o smoke, ou o proprio incentivo invertido deste cluster (tratar delegar/
# publicar como caro) reaparece disfarcado de "corrigir o smoke pra ficar verde".
# Fica ANTES do bloco GUARD-NUM de proposito (ver comentario abaixo): so usa Warn, nao Check,
# entao nao mexe na contagem que o GUARD-NUM mede.
Write-Host ""
Write-Host "-- Drift de versao: oficina vs release vs produto (AVISO, M5) --"
$verOficina = $verFile
$verReleasePath = Join-Path $root "release\alia-flow\VERSION"
$verRelease = if (Test-Path -LiteralPath $verReleasePath) { ((Get-Content -LiteralPath $verReleasePath -ErrorAction SilentlyContinue) -join "").Trim() } else { "(ausente)" }
# Caminho do repo publico calculado em runtime (NUNCA hardcoded): "alia-flow" mora irmao de
# "studio-farina" (3 niveis acima da oficina: clients -> studio-farina -> Projetos). Antes disto
# o caminho vinha cravado literal com o usuario Windows do dono direto num script que SHIPA no
# pacote publico - o proprio guard de path absoluto do package-release.ps1 pegou o vazamento.
$verProdutoPath = Join-Path (Split-Path (Split-Path (Split-Path $root -Parent) -Parent) -Parent) "alia-flow\VERSION"
$verProduto = if (Test-Path -LiteralPath $verProdutoPath) { ((Get-Content -LiteralPath $verProdutoPath -ErrorAction SilentlyContinue) -join "").Trim() } else { "(ausente)" }
Warn ("Versao: oficina=" + $verOficina + " release/alia-flow=" + $verRelease + " Projetos/alia-flow=" + $verProduto) (($verOficina -eq $verRelease) -and ($verOficina -eq $verProduto)) "drift so o CEO resolve, publicando"

# --- Numero publico: README.md (produto) e GUARD-NUM (oficina) - cada um trava so contra o
# total REAL do CONTEXTO onde faz sentido (M5) ---
# Dois numeros diferentes e legitimos, nunca somar (engine/governance/client-truth.md, LEI 2):
#   - README.md SHIPA no pacote/repo publico. O numero em prosa ("N na versao atual") tem que
#     bater com o total que O PRODUTO reporta (smoke rodando sem CLAIMS.md - ~19 checks a menos
#     que a oficina: sem os 3 guards de veto vs CLAIMS, sem Law Ledger etc). Por isso este Check
#     so BLOQUEIA (vira Check de verdade) quando CLAIMS.md esta ausente (contexto pacote/publico);
#     na oficina vira Warn informativo, porque a oficina tem MAIS checks que o produto e os dois
#     totais NUNCA vao coincidir por design - nao e drift a corrigir, e escopo diferente. A trava
#     que importa pro README acontece em package-release.ps1 (roda este mesmo smoke-test.ps1
#     DENTRO do pacote e aborta se nao ALL GREEN).
#   - GUARD-NUM em CLAIMS.md (doc interno, nunca shipa) anuncia o total da OFICINA - so existe e
#     so e checavel onde CLAIMS.md existe: Check na oficina, Warn no pacote/publico (sem mudanca).
# HISTORICO: ate a v1.42.4 o README era checado SEMPRE (mesmo na oficina) contra o total da
# oficina - inflava o numero do README pro valor da oficina (180), o que reprovava o proprio
# smoke DENTRO do pacote (o produto tem so 161 checks - CLAIMS.md e o que ele guarda nao viajam).
# v1.42.5 separou: cada numero trava so contra o total do contexto onde e medido de verdade.
# Fica perto do fim de proposito: nada depois deste bloco chama Check(), entao o total que o
# smoke VAI reportar em "Checks: X PASS, Y FAIL" e exatamente ($script:pass + $script:fail) ATE
# aqui, mais o UNICO Check() real deste bloco (README no pacote/publico OU GUARD-NUM na oficina -
# nunca os dois ao mesmo tempo, $numChecksNesteBloco e sempre 1) - calculado UMA vez antes de
# rodar, assim compara contra o MESMO total final previsto, nao contra o total parcial no meio.
Write-Host ""
Write-Host "-- Numero publico: README.md (produto) + GUARD-NUM (oficina) vs total real do contexto (M5) --"
$claimsPath = Join-Path $root "docs\CLAIMS.md"
$claimsExists = Test-Path -LiteralPath $claimsPath
$numChecksNesteBloco = 1  # sempre 1 Check real: README no pacote/publico OU GUARD-NUM na oficina
$expectedFinalCount = $script:pass + $script:fail + $numChecksNesteBloco

$readmePath = Join-Path $root "README.md"
$readmeTxt = ReadText $readmePath
$readmeM = [regex]::Match($readmeTxt, '\((\d+) na versao atual')
$readmeVal = -1
if ($readmeM.Success) { $readmeVal = [int]$readmeM.Groups[1].Value }
if ($claimsExists) {
  Warn "Numero publico: README.md - contexto oficina tem mais checks que o produto, nunca vai bater; trava real e no pacote" $readmeM.Success ("README.md diz " + $readmeVal + "; verificado a serio por package-release.ps1 dentro do pacote/repo publico")
} else {
  Check "Numero publico: README.md ('N na versao atual') bate com o total real executado pelo smoke" (($readmeM.Success) -and ($readmeVal -eq $expectedFinalCount)) ("README.md diz " + $readmeVal + "; total real que o smoke vai reportar = " + $expectedFinalCount)
}

if ($claimsExists) {
  $claimsTxt = ReadText $claimsPath
  $guardNumM = [regex]::Match($claimsTxt, 'GUARD-NUM:\s*VERIFICACOES_DETERMINISTICAS_OFICINA=(\d+)')
  $guardNumVal = -1
  if ($guardNumM.Success) { $guardNumVal = [int]$guardNumM.Groups[1].Value }
  Check "Numero publico: GUARD-NUM=VERIFICACOES_DETERMINISTICAS_OFICINA bate com o total real executado pelo smoke" (($guardNumM.Success) -and ($guardNumVal -eq $expectedFinalCount)) ("CLAIMS.md diz " + $guardNumVal + "; total real que o smoke vai reportar = " + $expectedFinalCount)
} else {
  # Mesmo motivo do guard de vetos acima: CLAIMS.md e interno, nao existe num clone/pacote
  # publico por LEI. Sem o Test-Path aqui o ReadText lancava excecao nao tratada e DERRUBAVA o
  # script inteiro (pior que um FAIL: nenhum check depois deste rodava). Pulado com honestidade.
  Warn "Numero publico: GUARD-NUM vs total real - pulado (CLAIMS.md ausente, doc interno)" $false "CLAIMS.md nao viaja no pacote/repo publico por LEI; nada a checar aqui"
}

# --- Resultado ---
Write-Host ""
Write-Host ("Checks: " + $script:pass + " PASS, " + $script:fail + " FAIL")
if ($script:fail -eq 0) {
  Write-Host "ALL GREEN"
  exit 0
} else {
  Write-Host "RED - ha falhas acima"
  exit 1
}
