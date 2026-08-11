<#
  graph-check.ps1 - Grafo do segundo cerebro VIVO em TODO Client (OPP-68, endurecido).
  Varre os Clients de <studio>/clients/ e classifica o grafo de cada um em 4 estados:

    OK     grafo autentico (saida real do graphify) e em dia com a base que ele cobre.
    STALE  grafo autentico porem PODRE: arquivos da base mudaram depois do graph.json.
    FAKE   existe pasta graphify-out mas o conteudo NAO e saida do graphify (JSON escrito
           a mao, schema errado, sem graph.html). Pior que nao ter: tem cara de fonte curada.
    FALTA  sem graphify-out / sem GRAPH_REPORT.md / sem graph.json / grafo vazio.

  ESTADO DO CLIENT (OPP-77): a cobranca do mapa e SO do Client ativo. Client declarado pontual
  (ideia tocada uma vez) ou arquivado no registro (state.json, clients[].state) sai como linha
  informativa - nunca como reprovacao - e nao entra na conta de FAKE/FALTA. Client sem estado
  declarado = ativo (compatibilidade). O registro fica na camada do operador; um studio.json sem
  clients[] (o caso da fixture) segue cobrando de todo mundo, como antes.

  Por que endurecer (auditoria 04/08/2026, research/graph-engineering/03-auditoria-interna.md):
  a guarda antiga so olhava "existe GRAPH_REPORT.md e nodes > 0" - criterio falsificavel com um
  JSON de 5 minutos - e so rodava contra a fixture studio.example. Medido na instancia real:
  2 grafos falsos passavam e nenhum grafo estava em dia.

  AUTENTICIDADE (o que o graphify realmente escreve): pasta com GRAPH_REPORT.md + graph.html +
  graph.json no schema node-link do networkx (chaves directed/multigraph/nodes/links), nos com
  id + community + procedencia (source_file/file_type) e arestas com source/target.

  PODRIDAO: compara o mtime do graph.json com os arquivos-fonte da base que ele cobre (a pasta
  onde o graphify-out mora). Ignora ruido (.git, node_modules, _backups, cache, o proprio
  graphify-out). Acima de -MaxNewerFiles o grafo vira STALE.

  A GERACAO continua sendo da skill graphify (precisa do agente). Este script CONFERE; com
  -Refresh ele tenta a rota SEM custo de modelo (`graphify update <base>`) nos grafos podres.

  Uso:  powershell -ExecutionPolicy Bypass -File scripts/graph-check.ps1 [-Path <studio>]
                   [-MaxNewerFiles 10] [-AllowStale] [-Refresh]
        -Path (alias -StudioDir) default: studio.example na raiz do produto.
  exit 0 se nenhum Client reprova; 1 caso contrario (e sempre imprime a linha [FAIL], porque o
  exit code do PowerShell nao propaga por algumas rotas de shell). Sem acentos, sem emojis.
#>
param(
  [Alias("Path")][string]$StudioDir = "",
  [int]$MaxNewerFiles = 10,
  [switch]$AllowStale,
  [switch]$Refresh
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "_studio.ps1")   # Get-ClientStates: o estado do Client (OPP-77)
if ([string]::IsNullOrWhiteSpace($StudioDir)) { $StudioDir = Join-Path $root "studio.example" }
$utf8 = New-Object System.Text.UTF8Encoding($false)

# ruido que nunca conta como fonte do grafo.
$skipDirs = @(".git","node_modules","_backups","graphify-out","cache","dist","build",".next",
              "target","venv",".venv","__pycache__","_retired","coverage",".turbo")
$srcExt   = @(".md",".yaml",".yml",".json",".ps1",".ts",".tsx",".js",".jsx",".py",".rs",".go",
              ".html",".css",".sql",".txt",".toml",".sh")

function ReadText([string]$p) { return [System.IO.File]::ReadAllText($p, $utf8) }

function HasProp($obj, [string]$name) {
  if ($null -eq $obj) { return $false }
  return (($obj.PSObject.Properties.Name) -contains $name)
}

# --- autenticidade: e mesmo saida do graphify? ---
function InspectGraph([string]$gout) {
  $r = @{ status = "FALTA"; nodes = 0; links = 0; why = @(); stamp = $null }
  $report = Join-Path $gout "GRAPH_REPORT.md"
  $html   = Join-Path $gout "graph.html"
  $json   = Join-Path $gout "graph.json"

  if (-not (Test-Path -LiteralPath $gout))  { $r.why += "sem pasta graphify-out"; return $r }
  if (-not (Test-Path -LiteralPath $json))  { $r.why += "sem graph.json" }
  if (-not (Test-Path -LiteralPath $report)){ $r.why += "sem GRAPH_REPORT.md" }
  if ($r.why.Count -gt 0) { return $r }

  $r.stamp = (Get-Item -LiteralPath $json).LastWriteTime
  $g = $null
  try { $g = ReadText $json | ConvertFrom-Json } catch { $r.why += "graph.json ilegivel (json invalido)"; return $r }
  if ($null -eq $g) { $r.why += "graph.json vazio"; return $r }

  $nodes = @(); if (HasProp $g "nodes") { $nodes = @($g.nodes) }
  $links = @(); if (HasProp $g "links") { $links = @($g.links) }
  $r.nodes = $nodes.Count
  $r.links = $links.Count
  if ($r.nodes -le 0) { $r.why += "graph.json sem nos"; return $r }

  # daqui pra baixo existe grafo; o que se julga e se ele e AUTENTICO.
  $fake = @()
  if (-not (Test-Path -LiteralPath $html)) { $fake += "sem graph.html" }
  if (-not (HasProp $g "directed") -or -not (HasProp $g "multigraph")) { $fake += "schema fora do node-link (sem directed/multigraph)" }
  if (-not (HasProp $g "links")) { $fake += "sem 'links' (usa 'edges' de JSON escrito a mao)" }
  elseif ($r.links -le 0) { $fake += "sem arestas" }
  else {
    $l0 = $links[0]
    if (-not (HasProp $l0 "source") -or -not (HasProp $l0 "target")) { $fake += "aresta sem source/target" }
  }
  $hasId    = $false; $hasComm = $false; $hasProv = $false
  foreach ($n in $nodes) {
    if (HasProp $n "id") { $hasId = $true }
    if (HasProp $n "community") { $hasComm = $true }
    if ((HasProp $n "source_file") -or (HasProp $n "file_type")) { $hasProv = $true }
    if ($hasId -and $hasComm -and $hasProv) { break }
  }
  if (-not $hasId)   { $fake += "no sem id" }
  if (-not $hasComm) { $fake += "no sem community (clustering nunca rodou)" }
  if (-not $hasProv) { $fake += "no sem procedencia (source_file/file_type)" }

  if ($fake.Count -gt 0) { $r.status = "FAKE"; $r.why = $fake; return $r }
  $r.status = "OK"
  return $r
}

# --- podridao: quantos arquivos-fonte ficaram mais novos que o grafo ---
function NewerSince([string]$baseDir, [datetime]$since) {
  $out = @{ count = 0; newest = ""; newestTime = $since }
  $stack = New-Object System.Collections.Stack
  $stack.Push($baseDir)
  while ($stack.Count -gt 0) {
    $dir = $stack.Pop()
    $items = Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue
    foreach ($i in $items) {
      if ($i.PSIsContainer) {
        if ($skipDirs -contains $i.Name.ToLower()) { continue }
        $stack.Push($i.FullName)
      } else {
        if ($srcExt -notcontains $i.Extension.ToLower()) { continue }
        if ($i.LastWriteTime -gt $since) {
          $out.count++
          if ($i.LastWriteTime -gt $out.newestTime) { $out.newestTime = $i.LastWriteTime; $out.newest = $i.Name }
        }
      }
    }
  }
  return $out
}

# --- rota de regeneracao sem custo de modelo ---
# --- elo Client -> codebase externo (OPP-graph-map, 10/08/2026) ---
# O campo "- **codePath:** <caminho>" no client.md e o unico registro de onde mora o CODIGO
# do Client em disco (a maioria roda fora do studio, ex. Projetos/<client>). Sem esse elo ninguem
# sabe onde procurar o mapa do codebase - so o mapa do segundo cerebro (squad/knowledge) era
# conferido antes. Campo simples de proposito (reuse-first/frugalidade): nao criou registro
# novo, so um campo a mais no arquivo que ja e a fonte de verdade do Client.
function Get-ClientCodePath([string]$clientDir) {
  $md = Join-Path $clientDir "client.md"
  if (-not (Test-Path -LiteralPath $md)) { return $null }
  $text = $null
  try { $text = ReadText $md } catch { return $null }
  $m = [regex]::Match($text, '(?im)^\s*-\s*\*\*codePath:\*\*\s*(\S.*)$')
  if (-not $m.Success) { return $null }
  $p = $m.Groups[1].Value.Trim()
  if ($p -eq "") { return $null }
  return $p.TrimEnd('/', '\')
}

# --- monta uma linha de mapa (doc do squad OU codigo externo) - reuso entre os dois casos ---
function Build-GraphRow([string]$Label, [string]$gout, [string]$base, [switch]$DoRefresh, $Runner) {
  $insp = InspectGraph $gout
  $newer = 0; $newestName = ""
  if ($insp.status -eq "OK") {
    $n = NewerSince $base $insp.stamp
    $newer = $n.count; $newestName = $n.newest
    if ($newer -gt $MaxNewerFiles) { $insp.status = "STALE" }
  }

  $refreshNote = ""
  if ($DoRefresh -and ($insp.status -eq "STALE")) {
    if ($null -eq $Runner) {
      $refreshNote = "nao regenerado: graphify ausente na maquina"
    } else {
      $gArgs = @($Runner.pre + @("update", $base))
      $prevEap = $ErrorActionPreference
      $ErrorActionPreference = "Continue"
      $rawOut = (& $Runner.exe @gArgs 2>&1 | Out-String)
      $rc = $LASTEXITCODE
      $ErrorActionPreference = $prevEap
      $lastLine = ""
      $lines = @($rawOut -split "`r?`n" | Where-Object { $_.Trim() -ne "" })
      if ($lines.Count -gt 0) { $lastLine = $lines[-1].Trim() }
      if ($rc -eq 0) {
        $insp2 = InspectGraph $gout
        if ($insp2.status -eq "OK") {
          $n2 = NewerSince $base $insp2.stamp
          $newer = $n2.count; $newestName = $n2.newest
          $insp = $insp2
          if ($newer -gt $MaxNewerFiles) { $insp.status = "STALE"; $refreshNote = "update rodou mas o grafo continua atrasado (update so re-extrai codigo; docs exigem rebuild)" }
          else { $refreshNote = "regenerado por 'graphify update'" }
        } else { $refreshNote = "update rodou e o grafo ficou invalido: " + ($insp2.why -join "; ") }
      } else {
        $refreshNote = "'graphify update' nao regenerou (exit " + $rc + "): " + $lastLine
      }
    }
  } elseif ($DoRefresh -and (($insp.status -eq "FAKE") -or ($insp.status -eq "FALTA"))) {
    $refreshNote = "nao regeneravel sem custo de modelo: rode a skill graphify (/graphify " + $base + ")"
  }

  return [pscustomobject]@{
    Label = $Label; Status = $insp.status; Nodes = $insp.nodes; Links = $insp.links
    Newer = $newer; Newest = $newestName; Why = ($insp.why -join "; ")
    Stamp = $insp.stamp; Base = $base; Refresh = $refreshNote
  }
}

function FindGraphify() {
  $cmd = Get-Command graphify -ErrorAction SilentlyContinue
  if ($null -ne $cmd) { return @{ exe = $cmd.Source; pre = @() } }
  $py = Get-Command python -ErrorAction SilentlyContinue
  if ($null -ne $py) {
    & $py.Source -c "import graphify" 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { return @{ exe = $py.Source; pre = @("-m","graphify") } }
  }
  return $null
}

$clientsDir = Join-Path $StudioDir "clients"
$stateFile  = Join-Path $StudioDir "state.json"
$clientStates = Get-ClientStates $stateFile   # id -> ativo|pontual|arquivado (ausente = ativo)
if (-not (Test-Path -LiteralPath $clientsDir)) {
  Write-Host ("[ERRO] pasta de clientes nao encontrada: " + $clientsDir)
  Write-Host "[FAIL] graph-check nao conseguiu varrer nada."
  exit 1
}

$runner = $null
if ($Refresh) {
  $runner = FindGraphify
  if ($null -eq $runner) {
    Write-Host "[AVISO] -Refresh pedido mas o graphify nao esta instalado nesta maquina (nem CLI 'graphify' nem 'python -m graphify'). Seguindo so em diagnostico."
  }
}

$rows = @()
$clients = @(Get-ChildItem -Path $clientsDir -Directory -ErrorAction SilentlyContinue | Sort-Object Name)
foreach ($c in $clients) {
  # ESTADO DO CLIENT (OPP-77): pontual/arquivado nao tem mapa cobrado - entra como informacao.
  $cstate = Get-ClientStateOf $clientStates $c.Name
  if ($cstate -ne "ativo") {
    $rows += [pscustomobject]@{
      Name = $c.Name; Kind = "doc"; Label = ""; Status = $cstate.ToUpper(); Nodes = 0; Links = 0
      Newer = 0; Newest = ""; Why = "estado '" + $cstate + "' no registro: nao cobra mapa"
      Stamp = $null; Base = $c.FullName; Refresh = ""
    }
    continue
  }
  # LEI: o grafo do SEGUNDO CEREBRO mora em squad/knowledge; aceita a raiz do Client como
  # fallback (caso do proprio lab, cujo corpus e a pasta inteira). Este e o mapa dos DOCS do
  # squad (memoria, PRD, brand) - NAO o mapa do codigo do cliente.
  $cands = @((Join-Path $c.FullName "squad\knowledge\graphify-out"), (Join-Path $c.FullName "graphify-out"))
  $gout = $cands | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
  if ($null -eq $gout) { $gout = $cands[0] }
  $base = Split-Path -Parent $gout

  $docRow = Build-GraphRow -Label "segundo cerebro (docs do squad)" -gout $gout -base $base -DoRefresh:$Refresh -Runner $runner
  $rows += [pscustomobject]@{
    Name = $c.Name; Kind = "doc"; Label = $docRow.Label; Status = $docRow.Status
    Nodes = $docRow.Nodes; Links = $docRow.Links; Newer = $docRow.Newer; Newest = $docRow.Newest
    Why = $docRow.Why; Stamp = $docRow.Stamp; Base = $docRow.Base; Refresh = $docRow.Refresh
  }

  # MAPA DO CODIGO (OPP-graph-map): so existe se o Client declarar codePath no client.md - a
  # maioria do codigo real mora FORA do studio (Projetos/<client> e outros). Sem codePath declarado
  # nao ha o que cobrar (nao inventa FALTA para Client que nunca teve codebase externo).
  $codePath = Get-ClientCodePath $c.FullName
  if (-not [string]::IsNullOrWhiteSpace($codePath)) {
    if (Test-Path -LiteralPath $codePath) {
      $goutCode = Join-Path $codePath "graphify-out"
      $codeRow = Build-GraphRow -Label "codigo (codebase externo)" -gout $goutCode -base $codePath -DoRefresh:$Refresh -Runner $runner
      $rows += [pscustomobject]@{
        Name = $c.Name; Kind = "codigo"; Label = $codeRow.Label; Status = $codeRow.Status
        Nodes = $codeRow.Nodes; Links = $codeRow.Links; Newer = $codeRow.Newer; Newest = $codeRow.Newest
        Why = $codeRow.Why; Stamp = $codeRow.Stamp; Base = $codeRow.Base; Refresh = $codeRow.Refresh
      }
    } else {
      $rows += [pscustomobject]@{
        Name = $c.Name; Kind = "codigo"; Label = "codigo (codebase externo)"; Status = "FALTA"
        Nodes = 0; Links = 0; Newer = 0; Newest = ""
        Why = "codePath declarado (" + $codePath + ") mas a pasta nao existe em disco"
        Stamp = $null; Base = $codePath; Refresh = ""
      }
    }
  }
}

# --- divergencia de registro: pasta em disco vs state.json (4 clientes invisiveis, auditoria 4.4) ---
$regOnlyDisk = @(); $regOnlyState = @()
if (Test-Path -LiteralPath $stateFile) {
  try {
    $st = ReadText $stateFile | ConvertFrom-Json
    $stIds = @(); if (HasProp $st "clients") { $stIds = @($st.clients | ForEach-Object { $_.id }) }
    # state.json sem registro de Clients (caso da fixture) nao gera divergencia - so ruido.
    if ($stIds.Count -gt 0) {
      $diskIds = @($clients | ForEach-Object { $_.Name })
      $regOnlyDisk  = @($diskIds | Where-Object { $stIds -notcontains $_ })
      $regOnlyState = @($stIds  | Where-Object { $diskIds -notcontains $_ })
    }
  } catch { }
}

Write-Host ("=== graph-check: " + $clients.Count + " Client(s) em " + $clientsDir + " ===")
foreach ($r in $rows) {
  # sufixo " :: <label>" deixa claro QUAL mapa e (segundo cerebro/docs do squad vs codigo do
  # codebase externo) - dois Clients podem ter os dois mapas com o mesmo Name e status diferente.
  $suf = if ([string]::IsNullOrWhiteSpace($r.Label)) { "" } else { " :: " + $r.Label }
  switch ($r.Status) {
    "OK"    { Write-Host ("[OK]    " + $r.Name + $suf + " (" + $r.Nodes + " nos, " + $r.Links + " arestas, " + $r.Newer + " arquivo(s) mais novo(s))") }
    "STALE" { Write-Host ("[STALE] " + $r.Name + $suf + " (" + $r.Nodes + " nos; " + $r.Newer + " arquivo(s) mais novo(s) que o grafo de " + $r.Stamp.ToString("yyyy-MM-dd") + "; teto " + $MaxNewerFiles + "; mais recente: " + $r.Newest + ")") }
    "FAKE"  { Write-Host ("[FAKE]  " + $r.Name + $suf + " (" + $r.Nodes + " nos mas NAO e saida do graphify -> " + $r.Why + ")") }
    "PONTUAL"   { Write-Host ("[PONTUAL]   " + $r.Name + " - ideia pontual: nao cobra mapa (estado declarado no registro)") }
    "ARQUIVADO" { Write-Host ("[ARQUIVADO] " + $r.Name + " - encerrado: nao cobra mapa (historico e Tasks seguem intactos)") }
    "FALTA" { Write-Host ("[FALTA] " + $r.Name + $suf + ": " + $r.Why) }
    default { Write-Host ("[FALTA] " + $r.Name + $suf + ": " + $r.Why) }
  }
  if ($r.Refresh -ne "") { Write-Host ("        -Refresh: " + $r.Refresh) }
}

if ($regOnlyDisk.Count -gt 0)  { Write-Host ("[AVISO] registro: " + $regOnlyDisk.Count + " pasta(s) em clients/ fora do state.json (invisiveis para as provas): " + ($regOnlyDisk -join ", ")) }
if ($regOnlyState.Count -gt 0) { Write-Host ("[AVISO] registro: " + $regOnlyState.Count + " Client(s) no state.json sem pasta em disco: " + ($regOnlyState -join ", ")) }

$nOk    = @($rows | Where-Object { $_.Status -eq "OK" }).Count
$nStale = @($rows | Where-Object { $_.Status -eq "STALE" }).Count
$nFake  = @($rows | Where-Object { $_.Status -eq "FAKE" }).Count
$nMiss  = @($rows | Where-Object { $_.Status -eq "FALTA" }).Count
$nFora  = @($rows | Where-Object { ($_.Status -eq "PONTUAL") -or ($_.Status -eq "ARQUIVADO") }).Count
Write-Host ("=== sumario: " + $rows.Count + " Client(s) | OK " + $nOk + " | STALE " + $nStale + " | FAKE " + $nFake + " | FALTA " + $nMiss + " | fora da cobranca (pontual/arquivado) " + $nFora + " ===")

$bad = $nFake + $nMiss
if (-not $AllowStale) { $bad += $nStale }
if ($bad -gt 0) {
  $det = @()
  if ($nFake -gt 0)  { $det += ([string]$nFake + " falso(s)") }
  if ($nMiss -gt 0)  { $det += ([string]$nMiss + " sem grafo") }
  if (($nStale -gt 0) -and (-not $AllowStale)) { $det += ([string]$nStale + " podre(s)") }
  Write-Host ("[FAIL] " + $bad + " Client(s) reprovados: " + ($det -join ", ") + ". Gere/atualize com a skill graphify antes de operar.")
  exit 1
}
if ($nStale -gt 0) { Write-Host ("[AVISO] " + $nStale + " grafo(s) podre(s) tolerado(s) por -AllowStale.") }
Write-Host ("[PASS] todo Client ATIVO tem grafo autentico do segundo cerebro" + $(if ($nFora -gt 0) { " (" + $nFora + " fora da cobranca por estado declarado)" } else { "" }) + ".")
exit 0
