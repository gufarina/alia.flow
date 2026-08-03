# Smoke Test - Studio Farina (espelho)
# Valida engine, N clientes (lidos do state.json), squads (gateway A brain full + especialista B expert_mind),
# state.json, arquivos raiz, encoding (0xFFFD) e ausencia de "aiox".
# UTF-8 sem BOM, sem acentos, sem emojis.

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot   # raiz do espelho (parent de scripts/)
. (Join-Path $PSScriptRoot "_studio.ps1")
$studioRoot = Get-StudioRoot $root         # pasta de dados (studio_dir): raiz se "."

$pass = 0
$fail = 0
$failures = New-Object System.Collections.Generic.List[string]

function Check {
    param([string]$name, [bool]$ok, [string]$detail = "")
    if ($ok) {
        Write-Host ("[PASS] " + $name)
        $script:pass++
    } else {
        $line = "[FAIL] " + $name
        if ($detail) { $line += " - " + $detail }
        Write-Host $line
        $script:fail++
        $script:failures.Add($name + $(if ($detail) { " (" + $detail + ")" } else { "" }))
    }
}

function FileHas {
    param([string]$path, [string]$pattern)
    if (-not (Test-Path -LiteralPath $path)) { return $false }
    $content = [System.IO.File]::ReadAllText($path)
    return ($content -match $pattern)
}

Write-Host "=== Studio Farina Smoke Test ==="
Write-Host ("Root: " + $root)
Write-Host ""

# ---------------------------------------------------------------------------
# (a) Engine presente
# ---------------------------------------------------------------------------
Write-Host "--- (a) Engine ---"
$engineFiles = @(
    "engine/constitution.md",
    "engine/agents/squad-creator.md",
    "engine/features/squad-templates/README.md"
)
foreach ($rel in $engineFiles) {
    $p = Join-Path $root $rel
    Check ("engine: " + $rel) (Test-Path -LiteralPath $p)
}

# ---------------------------------------------------------------------------
# (b) + (c) Clientes e squads
# Lista de clientes lida dinamicamente do state.json (clients[].id).
# Importar um cliente novo nunca quebra o teste por contagem.
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "--- (b)(c) Clientes + Squads ---"
$statePath = Join-Path $studioRoot "state.json"
$clients = @()
if (Test-Path -LiteralPath $statePath) {
    try {
        $stateTxt = [System.IO.File]::ReadAllText($statePath)
        $state = $stateTxt | ConvertFrom-Json
        if ($null -ne $state.clients) {
            $clients = @($state.clients | ForEach-Object { $_.id } | Where-Object { $_ })
        }
    } catch {
        $clients = @()
    }
}
Write-Host ("Clientes no state.json: " + ($clients -join ", "))

foreach ($cid in $clients) {
    $cdir = Join-Path $studioRoot ("clients/" + $cid)
    $sdir = Join-Path $cdir "squad"
    $adir = Join-Path $sdir "agents"
    $kdir = Join-Path $sdir "knowledge"

    # (b) squad.yaml
    $squadYaml = Join-Path $sdir "squad.yaml"
    Check ($cid + ": squad/squad.yaml") (Test-Path -LiteralPath $squadYaml)

    # (b) pelo menos 1 par agents/*.md + *.yaml
    $pairOk = $false
    if (Test-Path -LiteralPath $adir) {
        $mds = Get-ChildItem -LiteralPath $adir -Filter "*.md" -File -ErrorAction SilentlyContinue
        foreach ($md in $mds) {
            $yamlPeer = Join-Path $adir ($md.BaseName + ".yaml")
            if (Test-Path -LiteralPath $yamlPeer) { $pairOk = $true; break }
        }
    }
    Check ($cid + ": pelo menos 1 par agents/*.md+*.yaml") $pairOk

    # (b) knowledge/ nao vazio
    $kOk = $false
    if (Test-Path -LiteralPath $kdir) {
        $kfiles = Get-ChildItem -LiteralPath $kdir -File -ErrorAction SilentlyContinue
        $kOk = ($kfiles.Count -gt 0)
    }
    Check ($cid + ": knowledge/ nao vazio") $kOk

    # (c) gateway camada A com brain full
    $gatewayOk = $false
    $specialistOk = $false
    if (Test-Path -LiteralPath $adir) {
        $yamls = Get-ChildItem -LiteralPath $adir -Filter "*.yaml" -File -ErrorAction SilentlyContinue
        foreach ($y in $yamls) {
            $txt = [System.IO.File]::ReadAllText($y.FullName)

            $isA = ($txt -match "(?im)^\s*camada\s*:\s*A\b")
            $hasFull = ($txt -match "(?im)^\s*brain\s*:\s*full\b")
            if ($isA -and $hasFull) { $gatewayOk = $true }

            $isB = ($txt -match "(?im)^\s*camada\s*:\s*B\b")
            if ($isB) {
                # expert_mind: <valor> inline OU expert_minds: seguido de item de lista "- ..."
                $inlineSingular = ($txt -match "(?im)^\s*expert_mind\s*:\s*\S")
                $inlinePlural   = ($txt -match "(?im)^\s*expert_minds\s*:\s*\[?\s*\S")  # nao-vazio na mesma linha
                $listPlural     = ($txt -match "(?ims)^\s*expert_minds\s*:\s*$.*?^\s*-\s*\S")
                if ($inlineSingular -or $inlinePlural -or $listPlural) { $specialistOk = $true }
            }
        }
    }
    Check ($cid + ": gateway camada A com brain full") $gatewayOk
    Check ($cid + ": especialista camada B com expert_mind") $specialistOk
}

# ---------------------------------------------------------------------------
# (d) state.json JSON valido com N clientes (N >= 1)
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "--- (d) state.json ---"
$stateOk = $false
$stateClients = -1
if (Test-Path -LiteralPath $statePath) {
    try {
        $stateTxt2 = [System.IO.File]::ReadAllText($statePath)
        $state2 = $stateTxt2 | ConvertFrom-Json
        if ($null -ne $state2.clients) {
            $ids = @($state2.clients | ForEach-Object { $_.id } | Where-Object { $_ })
            $stateClients = $ids.Count
            $stateOk = ($stateClients -ge 1)
        }
    } catch {
        $stateOk = $false
    }
}
Check ("state.json valido com " + $stateClients + " clientes") $stateOk ("clients=" + $stateClients)

# ---------------------------------------------------------------------------
# (e) Arquivos raiz / skill
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "--- (e) Arquivos raiz ---"
$rootFiles = @(
    "AGENTS.md",
    "README.md",
    "alia.config.json",
    "skills/file-organization/SKILL.md"
)
foreach ($rel in $rootFiles) {
    $p = Join-Path $root $rel
    Check ("raiz: " + $rel) (Test-Path -LiteralPath $p)
}

# Raiz limpa: SO a allowlist canonica (nada vaza). Layout: skills/file-organization/SKILL.md.
# Pastas livres; dotfiles (.git*) ignorados; state.json/studio.yaml so contam se studio_dir=".".
$rootAllow = @("README.md","PRIMEIROS-PASSOS.md","AGENTS.md","CONTRIBUTING.md","CHANGELOG.md","CATALOG.md","LICENSE","CREDITS.md","VERSION","alia.config.json","iniciar-alia.bat","atualizar-alia.bat","mission-control.html","CLAUDE.md","PRODUCT.md","DESIGN.md")
$sdir = ""
$cfgP = Join-Path $root "alia.config.json"
if (Test-Path $cfgP) { try { $sdir = "$((Get-Content $cfgP -Raw | ConvertFrom-Json).studio_dir)".Trim() } catch {} }
if ($sdir -eq ".") { $rootAllow += @("state.json","studio.yaml") }
$leak = Get-ChildItem -Path $root -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notlike ".*" -and $rootAllow -notcontains $_.Name }
Check "Raiz limpa: so a allowlist canonica (nenhum arquivo vaza)" ($leak.Count -eq 0) ("vazou: " + (($leak | ForEach-Object { $_.Name }) -join ", "))

# ---------------------------------------------------------------------------
# (f) Encoding: 0 caracteres 0xFFFD em todo o espelho
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "--- (f) Encoding (0xFFFD) ---"
$textExt = @(".md", ".yaml", ".yml", ".json", ".txt", ".ps1", ".js", ".ts", ".mjs", ".cjs", ".html", ".css", ".csv")
$badEnc = New-Object System.Collections.Generic.List[string]
$selfPath = $PSCommandPath   # o proprio script (referencia "aiox" so para testar)
# Sub-repos aninhados (ex.: o laboratorio do produto em clients/alia-flow-lab) tem .git proprio e
# se validam pelo proprio smoke - a instancia nao policia o conteudo deles.
$nestedRepos = @()
$clientsRoot = Join-Path $studioRoot "clients"
if (Test-Path -LiteralPath $clientsRoot) {
  foreach ($d in (Get-ChildItem -LiteralPath $clientsRoot -Directory -ErrorAction SilentlyContinue)) {
    if (Test-Path -LiteralPath (Join-Path $d.FullName ".git")) { $nestedRepos += ($d.FullName + [IO.Path]::DirectorySeparatorChar) }
  }
}
function Test-InNestedRepo([string]$p) {
  foreach ($r in $nestedRepos) { if ($p.StartsWith($r, [StringComparison]::OrdinalIgnoreCase)) { return $true } }
  return $false
}
$allFiles = Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { ($textExt -contains $_.Extension.ToLower()) -and ($_.FullName -ne $selfPath) -and -not (Test-InNestedRepo $_.FullName) -and ($_.FullName -notmatch "[\\/](release|_retired|target|node_modules|dist|\.git)[\\/]") }
foreach ($f in $allFiles) {
    $content = [System.IO.File]::ReadAllText($f.FullName)
    if ($content.IndexOf([char]0xFFFD) -ge 0) {
        $badEnc.Add($f.FullName.Substring($root.Length + 1))
    }
}
$encOk = ($badEnc.Count -eq 0)
Check ("encoding: 0 caracteres 0xFFFD") $encOk ($badEnc.Count.ToString() + " arquivo(s) afetado(s)")
if (-not $encOk) {
    foreach ($b in $badEnc) { Write-Host ("    0xFFFD em: " + $b) }
}

# ---------------------------------------------------------------------------
# (g) Zero "aiox" (case-insensitive) no espelho que faz ship
# Exclusoes (nao policiar planejamento nem dado vivo - nada disso sobe pro git open source):
#   - studio/clients/*/opportunities/ : notas de planejamento exploratorio do operador.
#   - studio/research/ : relatorios/estudos do operador (podem CITAR o termo ao descrever historico/incidente).
#   - studio/memory/_proposals/ : digests de memoria a curar (dado vivo, podem citar o termo legado).
#   - studio/state.json : dado vivo (descricoes de tarefa), nao codigo.
#   - _drafts/ : rascunhos do operador (LP antigas etc.), nao fazem ship.
#   - clients/*/artifacts/ : paineis/relatorios internos do cliente (ex.: auditoria executiva
#     que narra a absorcao do aiox, assunto que o proprio CREDITS.md credita abertamente); por
#     LEI (raiz CLAUDE.md, "git e vitrine, nao gaveta") material de cliente NUNCA e versionado -
#     mesma classe de opportunities/ e research/, que ja sao isentos.
#   - o proprio script (self) : contem "aiox" como padrao de busca.
# Encoding (secao f) segue cobrindo tudo; so o scan de termo legado e que filtra.
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "--- (g) Zero aiox ---"
$sep = [IO.Path]::DirectorySeparatorChar
$oppMarker = $sep + "opportunities" + $sep
$researchMarker = $sep + "research" + $sep
$proposalsMarker = $sep + "_proposals" + $sep
$draftsMarker = $sep + "_drafts" + $sep
$backupsMarker = $sep + "_backups" + $sep   # backups automaticos do updater copiam dado vivo (state.json) - mesma isencao do vivo
$clientsMarker = $sep + "clients" + $sep
$artifactsMarker = $sep + "artifacts" + $sep
$statePathFull = (Join-Path $studioRoot "state.json")
$aioxHits = New-Object System.Collections.Generic.List[string]
foreach ($f in $allFiles) {
    if ($f.FullName.IndexOf($oppMarker, [StringComparison]::OrdinalIgnoreCase) -ge 0) { continue }
    if ($f.FullName.IndexOf($researchMarker, [StringComparison]::OrdinalIgnoreCase) -ge 0) { continue }
    if ($f.FullName.IndexOf($proposalsMarker, [StringComparison]::OrdinalIgnoreCase) -ge 0) { continue }
    if ($f.FullName.IndexOf($draftsMarker, [StringComparison]::OrdinalIgnoreCase) -ge 0) { continue }
    if ($f.FullName.IndexOf($backupsMarker, [StringComparison]::OrdinalIgnoreCase) -ge 0) { continue }
    if (($f.FullName.IndexOf($clientsMarker, [StringComparison]::OrdinalIgnoreCase) -ge 0) -and ($f.FullName.IndexOf($artifactsMarker, [StringComparison]::OrdinalIgnoreCase) -ge 0)) { continue }
    if ($f.FullName -eq $statePathFull) { continue }
    if ($f.Name -eq "smoke-test-studio.ps1") { continue }   # qualquer copia do proprio script contem "aiox" como padrao de busca (a oficina deixou de ser repo git, entao as copias dela agora sao varridas)
    if (@("CREDITS.md","README.md","CHANGELOG.md","PRD.md","ARQUITETURA.md") -contains $f.Name) { continue }   # docs de produto creditam a origem de proposito (PRD cita o molde do descritor; ARQUITETURA descreve a absorcao); ambos sao internos (docs/product nao vai pro pacote publico). O check guarda o CODIGO, nao a atribuicao
    $content = [System.IO.File]::ReadAllText($f.FullName)
    if ($content -match "(?i)aiox") {
        $aioxHits.Add($f.FullName.Substring($root.Length + 1))
    }
}
$aioxOk = ($aioxHits.Count -eq 0)
Check ("grep aiox = 0") $aioxOk ($aioxHits.Count.ToString() + " arquivo(s) com 'aiox'")
if (-not $aioxOk) {
    foreach ($h in $aioxHits) { Write-Host ("    aiox em: " + $h) }
}

# ---------------------------------------------------------------------------
# (h) Guardrail da LEI: alia-flow CLEAN (so manutencao de engenharia).
# engine/governance/instance-separation.md: o nosso marketing/comercial vive em
# studio-farina, nunca dentro de alia-flow. Falha se houver pasta com 'marketing'
# ou 'comercial' no nome dentro de studio/clients/alia-flow/.
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "--- (h) alia-flow CLEAN ---"
$aliaFlowDir = Join-Path $studioRoot "clients/alia-flow-lab"
$dirty = @()
if (Test-Path -LiteralPath $aliaFlowDir) {
    $subdirs = Get-ChildItem -LiteralPath $aliaFlowDir -Recurse -Directory -ErrorAction SilentlyContinue
    foreach ($sd in $subdirs) {
        if ($sd.Name -match "(?i)marketing|comercial") { $dirty += $sd.Name }
    }
}
Check "alia-flow CLEAN: sem pasta marketing/comercial" ($dirty.Count -eq 0) ("achei: " + ($dirty -join ", "))

# ---------------------------------------------------------------------------
# (i) LEI de Pesquisa Segura: todo agente de pesquisa declara a trava anti-runaway.
# engine/tools.md (research_safety): agente com second_brain_engines (notebooklm/perplexity...)
# NAO pode rodar sem research_limits (max_parallel:1 + self_spawn:forbidden). Esta e a garantia
# de que pesquisa nunca vira enxame/loop (o episodio dos 100 agentes nao se repete).
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "--- (i) Pesquisa segura (anti-runaway) ---"
$researchAgents = 0
$unsafe = @()
$clientsRoot = Join-Path $studioRoot "clients"
if (Test-Path -LiteralPath $clientsRoot) {
    $agentYamls = Get-ChildItem -Path $clientsRoot -Recurse -Filter "*.yaml" -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match "[\\/]squad[\\/]agents[\\/]" }
    foreach ($ay in $agentYamls) {
        $atxt = [System.IO.File]::ReadAllText($ay.FullName)
        if ($atxt -match "(?im)^\s*second_brain_engines\s*:") {
            $researchAgents++
            $hasLimits = ($atxt -match "(?im)research_limits\s*:")
            $seq       = ($atxt -match "(?im)max_parallel\s*:\s*1\b")
            $noSpawn   = ($atxt -match "(?im)self_spawn\s*:\s*forbidden\b")
            if (-not ($hasLimits -and $seq -and $noSpawn)) { $unsafe += $ay.BaseName }
        }
    }
}
Check ("Pesquisa segura: " + $researchAgents + " agente(s) de pesquisa, todos com trava (max_parallel:1 + self_spawn:forbidden)") ($unsafe.Count -eq 0) ("sem trava: " + ($unsafe -join ", "))

# ---------------------------------------------------------------------------
# (i) Vivacidade do RSI: digest parado em memory/_proposals/ FALHA (cadeado anti-loop-aberto)
# O loop de aprendizado e o que o produto vende. reflect-check (lembrete) podia ser ignorado;
# este check e a TRAVA DE MAQUINA: se um digest fica > STALE dias sem ser julgado/promovido/
# arquivado, o smoke FALHA. Fecha o furo do "loop fecha so na base da boa vontade".
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "--- (i) Vivacidade do RSI (digest parado = FALHA) ---"
$RSI_STALE_DIAS = 3
# O pipeline de reflexao (reflect-check / session-reflection / promote-memory) usa memory/_proposals
# na RAIZ da instalacao (parent de scripts/), nao em studio_dir. O cadeado tem que olhar ONDE o digest
# realmente cai, senao passa vazio enquanto o digest apodrece (furo medido 29/jun).
$propDir = Join-Path $root "memory/_proposals"
$staleDigests = New-Object System.Collections.Generic.List[string]
if (Test-Path -LiteralPath $propDir) {
    $digs = @(Get-ChildItem -LiteralPath $propDir -Filter "reflection-inbox-*.md" -File -ErrorAction SilentlyContinue)
    foreach ($d in $digs) {
        $idade = [math]::Floor(((Get-Date) - $d.LastWriteTime).TotalDays)
        if ($idade -gt $RSI_STALE_DIAS) { $staleDigests.Add($d.Name + " (" + $idade + "d)") }
    }
}
Check ("RSI vivo: nenhum digest parado > " + $RSI_STALE_DIAS + " dias em _proposals/") ($staleDigests.Count -eq 0) ("PARADOS: " + ($staleDigests -join ", ") + " -> feche o loop (julgar/promover/arquivar)")

# ---------------------------------------------------------------------------
# (j) Contrato de 6 elementos por loop (OPP-57): loop ACTIVE sem os 6 campos = FALHA
# engine/governance/loops.md + loops.catalog.yaml (instance_schema): todo loop instanciado declara
# discovery_source, state_file, evaluator, isolation, token_cap (per_round+daily) e
# human_review_point. Sao as guardas do orange-book que decidem se o loop se enrasca; o teto
# (token_cap) e o que o budget-check (OPP-58) morde. Check de PRESENCA/formato; a verdade do
# valor e cobrada pelo Gate normal.
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "--- (j) Contrato de 6 elementos por loop (OPP-57) ---"
$sixFields = @("discovery_source", "state_file", "evaluator", "isolation", "human_review_point")
foreach ($cid in $clients) {
    $loopsPath = Join-Path $studioRoot ("clients/" + $cid + "/loops.yaml")
    if (-not (Test-Path -LiteralPath $loopsPath)) { continue }   # cliente sem loops instanciados: nada a validar
    $loopsTxt = [System.IO.File]::ReadAllText($loopsPath)
    $incomplete = @()
    $activeCount = 0
    # blocos por loop: de "- id:" ate o proximo "- id:" (ou fim do arquivo)
    foreach ($blk in [regex]::Matches($loopsTxt, '(?ms)^\s*-\s*id:\s*(\S+)\s*$(.*?)(?=^\s*-\s*id:|\z)')) {
        $lid = $blk.Groups[1].Value
        $body = $blk.Groups[2].Value
        if ($body -notmatch "(?m)^\s*status:\s*active\b") { continue }   # so loop ATIVO exige o contrato
        $activeCount++
        $missing6 = @()
        foreach ($f6 in $sixFields) {
            if ($body -notmatch ("(?m)^\s*" + $f6 + ":\s*\S")) { $missing6 += $f6 }
        }
        if ($body -notmatch "token_cap:\s*\{\s*per_round:\s*\d+\s*,\s*daily:\s*\d+\s*\}") { $missing6 += "token_cap" }
        if ($missing6.Count -gt 0) { $incomplete += ($lid + " [" + ($missing6 -join ",") + "]") }
    }
    Check ($cid + ": " + $activeCount + " loop(s) active com os 6 elementos (OPP-57)") ($incomplete.Count -eq 0) ("incompleto: " + ($incomplete -join "; "))
}

# ---------------------------------------------------------------------------
# (k) Squad YAML integro: nenhuma chave engolida por comentario na mesma linha
# Bug real (01/jul): comentario inline em squad.yaml terminava em "... knowledge:" - a chave
# knowledge: virou parte do comentario e a lista abaixo ficou orfa (YAML invalido). Assinatura
# do defeito: linha com comentario (#) que TERMINA em "algo:". Check barato por linha.
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "--- (k) Squad YAML integro (chave engolida por comentario) ---"
$swallowed = @()
if (Test-Path -LiteralPath $clientsRoot) {
    $squadYamls = Get-ChildItem -Path $clientsRoot -Recurse -Filter "*.yaml" -File -ErrorAction SilentlyContinue |
        Where-Object { ($_.FullName -match "[\\/]squad[\\/]") -and -not (Test-InNestedRepo $_.FullName) }
    foreach ($sy in $squadYamls) {
        $lines = [System.IO.File]::ReadAllLines($sy.FullName)
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match "#[^#\r\n]*\b\w+:\s*$") {
                $swallowed += ($sy.Name + ":" + ($i + 1))
            }
        }
    }
}
Check "Squad YAML: nenhuma chave engolida por comentario inline" ($swallowed.Count -eq 0) ("linha(s): " + ($swallowed -join ", "))

# ---------------------------------------------------------------------------
# Resumo
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== Resumo ==="
Write-Host ("PASS: " + $pass)
Write-Host ("FAIL: " + $fail)

if ($fail -eq 0) {
    Write-Host ""
    Write-Host "ALL GREEN"
    exit 0
} else {
    Write-Host ""
    Write-Host "FAILURES:"
    foreach ($x in $failures) { Write-Host ("  - " + $x) }
    Write-Host ""
    Write-Host "NOT GREEN"
    exit 1
}
