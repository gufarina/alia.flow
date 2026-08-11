<#
  lineage-graph.ps1 - Le o ledger de Tasks (state.json) como MAPA de linhagem, nao como lista.

  O ledger ja e um grafo: cada Task carrega client, project, artifact (o que entregou),
  base_artifact (de onde partiu) e session (quem executou). task-context.ps1 le esse rastro
  por Cliente (a linha do tempo); mission-control.ps1 desenha o painel. Falta a leitura em
  GRAFO: seguir a aresta base_artifact -> artifact de Task em Task, nos dois sentidos.

  Isso responde duas perguntas que hoje ninguem consegue responder sem ler 86 Tasks na mao:
    -Impact  "o que quebra / o que depende disto se eu mexer aqui" (a cadeia PRA FRENTE)
    -Trace   "de onde isto veio, elo por elo, ate a raiz"          (a cadeia PRA TRAS)
    -Health  a saude do proprio rastro, em numeros (nao em adjetivos)
    -Html    o mesmo mapa como pagina navegavel, autocontida (zero rede, zero servidor)

  Como as arestas sao inferidas: `artifact` e `base_artifact` sao TEXTO LIVRE, entao o script
  extrai os tokens de caminho de cada campo (expande {a,b}.ps1, corta #ancora e @versao,
  normaliza \ e caminho absoluto do studio) e liga base -> entrega por igualdade, por sufixo
  de segmento (docs/CLAIMS.md casa com clients/x/docs/CLAIMS.md) ou por pasta-pai. Alem disso
  respeita a citacao direta "TASK-060" dentro do base_artifact. Toda aresta so vale se o
  produtor for ANTERIOR no tempo ao consumidor - isso mantem o mapa aciclico e honesto.

  Uso:
    powershell -ExecutionPolicy Bypass -File scripts/lineage-graph.ps1 -Impact <arquivo>
    powershell -ExecutionPolicy Bypass -File scripts/lineage-graph.ps1 -Trace  <TASK-084|caminho>
    powershell -ExecutionPolicy Bypass -File scripts/lineage-graph.ps1 -Health
    powershell -ExecutionPolicy Bypass -File scripts/lineage-graph.ps1 -Html <saida.html>
    [-StateFile <caminho>] [-Depth 4]

  SOMENTE LEITURA do state.json - este script nunca escreve no ledger.
  Sem acentos, sem emojis nos arquivos de script. exit 0 (leitura vazia tambem e informacao).
#>
param(
  [string]$Impact = "",
  [string]$Trace = "",
  [switch]$Health,
  [string]$Html = "",
  [int]$Depth = 4,
  [string]$StateFile = ""
)
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------- fonte
$root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($StateFile)) {
  $StateFile = Join-Path $root "state.json"
  # na oficina (clients/alia-flow-lab) o ledger vivo mora 2 niveis acima, na raiz da instancia
  if (-not (Test-Path -LiteralPath $StateFile)) {
    $alt = Join-Path (Split-Path -Parent (Split-Path -Parent $root)) "state.json"
    if (Test-Path -LiteralPath $alt) { $StateFile = $alt }
  }
}
if (-not (Test-Path -LiteralPath $StateFile)) {
  Write-Host ("[ERRO] state.json nao encontrado: " + $StateFile)
  Write-Host "Passe -StateFile <caminho> apontando para o ledger da instancia."
  exit 1
}
$StateFile = (Resolve-Path -LiteralPath $StateFile).Path
$studioRoot = Split-Path -Parent $StateFile

$utf8 = New-Object System.Text.UTF8Encoding($false)
$raw = [System.IO.File]::ReadAllText($StateFile)
if ($raw.Length -gt 0 -and $raw[0] -eq [char]0xFEFF) { $raw = $raw.Substring(1) }
$st = $raw | ConvertFrom-Json
$tasks = @(); if ($st.tasks) { $tasks = @($st.tasks) }

# ---------------------------------------------------------------- utilitarios
$script:ExtOk = @('md','ps1','html','htm','json','js','mjs','ts','tsx','jsx','py','yaml','yml',
                  'zip','css','png','jpg','jpeg','svg','sh','txt','exe','rs','sql','csv','pdf','xml','toml')

function ConvertTo-NormPath([string]$s) {
  if ($null -eq $s) { return "" }
  $x = $s.Replace('\','/')
  # cola espaco DENTRO de caminho absoluto ("C:/Users/Jane Doe/Projetos" -> "Jane_Doe").
  # So com letra de unidade: sem essa cerca, "landing/lp.html (26/06)" viraria um token corrompido.
  return [regex]::Replace($x, '(?<=[A-Za-z]:/[^\s]*)[ ]+(?=[^\s]*/)', '_')
}
function Test-HasExt([string]$k) {
  $leaf = $k.Split('/')[-1]
  return ($leaf -match '\.[A-Za-z0-9]{1,6}$')
}
function Expand-BraceToken([string]$tok) {
  $out = @()
  $m = [regex]::Match($tok, '^(.*?)\{([^{}]+)\}(.*)$')
  if ($m.Success) {
    foreach ($p in $m.Groups[2].Value.Split(',')) {
      $out += @(Expand-BraceToken ($m.Groups[1].Value + $p.Trim() + $m.Groups[3].Value))
    }
  } else { $out += $tok }
  return $out
}
$script:RootLow = (ConvertTo-NormPath $studioRoot).ToLowerInvariant().TrimEnd('/')

function Get-PathKeys([string]$rawText) {
  $res = @{}
  if ([string]::IsNullOrWhiteSpace($rawText)) { return @() }
  $s = ConvertTo-NormPath $rawText
  $rx = '(?:[A-Za-z]:/)?[\w\.\-]+(?:/[\w\.\-\{\}\,#@]+)+|[\w\-]+\.[A-Za-z0-9]{1,6}'
  foreach ($m in [regex]::Matches($s, $rx)) {
    # token cortado por curinga ("PROVA-*.png") nao e caminho concreto - nao vira chave
    $after = ''
    if (($m.Index + $m.Length) -lt $s.Length) { $after = $s[$m.Index + $m.Length] }
    if ($after -eq '*' -or $after -eq '?') { continue }
    $t = $m.Value.Split('#')[0].Split('@')[0].TrimEnd('.',',',';',':','/','-')
    if ($t -eq '') { continue }
    foreach ($e in @(Expand-BraceToken $t)) {
      $k = $e.ToLowerInvariant().Trim().TrimEnd('/')
      if ($k.Length -lt 3) { continue }
      if ($k -match '^\d{1,4}/\d{1,4}(/\d{1,4})?$') { continue }  # "(26/06)" e data, nao caminho
      if ($k -notlike '*/*') {
        $ext = ''
        if ($k -match '\.([A-Za-z0-9]+)$') { $ext = $Matches[1] }
        if ($script:ExtOk -notcontains $ext) { continue }
      }
      if ($script:RootLow -ne '' -and $k.StartsWith($script:RootLow + '/')) { $k = $k.Substring($script:RootLow.Length + 1) }
      if ($k.Length -lt 3) { continue }
      $res[$k] = $true
    }
  }
  return @($res.Keys)
}
# mesmo alvo, escrito com qualificacao diferente (docs/CLAIMS.md == clients/x/docs/CLAIMS.md)
function Test-KeySame([string]$a, [string]$b) {
  if ($a -eq $b) { return $true }
  if ($a.EndsWith('/' + $b)) { return $true }
  if ($b.EndsWith('/' + $a)) { return $true }
  return $false
}
# dependencia e DIRECIONAL: quem consome pode citar um arquivo DENTRO da pasta entregue,
# mas quem declara a pasta inteira como base ("clients/alia-flow-lab") nao depende de cada
# arquivo dela - isso e base grossa demais, furo de rastreio, nao aresta.
function Test-KeyDepends([string]$consumed, [string]$produced) {
  if (Test-KeySame $consumed $produced) { return $true }
  if (-not (Test-HasExt $produced) -and $consumed.StartsWith($produced + '/')) { return $true }
  return $false
}
# a entrega responde pela consulta (o alvo, ou um arquivo dentro da pasta consultada)
function Test-KeyProduces([string]$produced, [string]$query) {
  if (Test-KeySame $produced $query) { return $true }
  if (-not (Test-HasExt $query) -and $produced.StartsWith($query + '/')) { return $true }
  return $false
}
function Field($t, $name) {
  $v = $null; try { $v = $t.PSObject.Properties[$name].Value } catch { }
  if ($null -eq $v) { return "" } else { return "$v" }
}
function Cut([string]$s, [int]$n) {
  if ($null -eq $s) { return "" }
  if ($s.Length -le $n) { return $s }
  return ($s.Substring(0, $n - 3) + "...")
}
function Get-Created($t) {
  $c = Field $t 'created'
  if ($c -eq '') { return [datetime]::MinValue }
  try { return [datetime]::Parse($c, [Globalization.CultureInfo]::InvariantCulture) } catch { return [datetime]::MinValue }
}

# ---------------------------------------------------------------- indexacao (o grafo)
$nodes = @()
$i = 0
foreach ($t in $tasks) {
  $i++
  $nodes += [PSCustomObject]@{
    key      = ((Field $t 'id') + "#" + $i)   # chave unica: o ledger tem id repetido
    id       = (Field $t 'id')
    t        = $t
    produces = @(Get-PathKeys (Field $t 'artifact'))
    consumes = @(Get-PathKeys (Field $t 'base_artifact'))
    refs     = @([regex]::Matches((Field $t 'base_artifact'), 'TASK-\d{3}') | ForEach-Object { $_.Value })
    created  = (Get-Created $t)
  }
}
$byKey = @{}; foreach ($n in $nodes) { $byKey[$n.key] = $n }

# arestas produtor -> consumidor (so quando o produtor e ANTERIOR no tempo: linhagem e temporal)
# Por chave de base, so a ULTIMA REVISAO anterior vale como pai (mesma regra que o
# task-context.ps1 aplica na linha do tempo: o proximo passo parte da ultima revisao,
# nao de todas). Sem isso, um nome generico como DESIGN.md abre um leque de 7 pais.
$edges = @()
foreach ($c in $nodes) {
  $best = @{}
  foreach ($p in $nodes) {
    if ($p.key -eq $c.key) { continue }
    if ($p.created -gt $c.created) { continue }
    foreach ($ck in $c.consumes) {
      $hit = $false
      foreach ($pk in $p.produces) { if (Test-KeyDepends $ck $pk) { $hit = $true; break } }
      if ($hit) {
        if (-not $best.ContainsKey($ck)) { $best[$ck] = $p }
        elseif ($p.created -gt $best[$ck].created) { $best[$ck] = $p }
      }
    }
    if ($c.refs -contains $p.id) {
      $vk = $p.id + " (citada)"
      if (-not $best.ContainsKey($vk)) { $best[$vk] = $p }
    }
  }
  $seenP = @{}
  foreach ($kv in ($best.GetEnumerator() | Sort-Object Key)) {
    if ($seenP.ContainsKey($kv.Value.key)) { continue }
    $seenP[$kv.Value.key] = $true
    $edges += [PSCustomObject]@{ from = $kv.Value.key; to = $c.key; via = $kv.Key }
  }
}
$outAdj = @{}; $inAdj = @{}
foreach ($e in $edges) {
  if (-not $outAdj.ContainsKey($e.from)) { $outAdj[$e.from] = @() }
  if (-not $inAdj.ContainsKey($e.to))   { $inAdj[$e.to]   = @() }
  $outAdj[$e.from] += $e
  $inAdj[$e.to]    += $e
}

function Show-Node($n, [string]$head) {
  $t = $n.t
  $pad = " " * $head.Length
  $art = Field $t 'artifact'; $base = Field $t 'base_artifact'; $ses = Field $t 'session'
  Write-Host ($head + (Field $t 'id') + " [" + (Field $t 'status') + "] " + (Cut (Field $t 'title') 96))
  Write-Host ($pad + "    cliente:  " + (Field $t 'client') + " / " + $(if ((Field $t 'project') -eq '') { "(sem projeto - FURO de rastreio)" } else { Field $t 'project' }))
  Write-Host ($pad + "    entregou: " + $(if ($art -eq '') { "(nao registrado - FURO de rastreio)" } else { Cut $art 110 }))
  Write-Host ($pad + "    partiu de:" + " " + $(if ($base -eq '') { "(nao registrado - FURO de rastreio)" } else { Cut $base 110 }))
  Write-Host ($pad + "    sessao:   " + $(if ($ses -eq '') { "(nao registrada)" } else { $ses }) + " | " + (Field $t 'created') + " | gate: " + $(if ((Field $t 'gate_verdict') -eq '') { "(sem veredito)" } else { Field $t 'gate_verdict' }))
}

# ---------------------------------------------------------------- -Impact
function Invoke-Impact([string]$q) {
  $qn = (ConvertTo-NormPath $q).ToLowerInvariant().Trim().TrimEnd('/')
  if ($script:RootLow -ne '' -and $qn.StartsWith($script:RootLow + '/')) { $qn = $qn.Substring($script:RootLow.Length + 1) }
  Write-Host ("=== IMPACTO: '" + $q + "' ===")
  Write-Host ("fonte: " + $StateFile + " | " + $nodes.Count + " Task(s) | " + $edges.Count + " aresta(s) de linhagem")
  Write-Host ""

  $prod = @($nodes | Where-Object { $n = $_; @($n.produces | Where-Object { Test-KeyProduces $_ $qn }).Count -gt 0 } | Sort-Object created -Descending)
  Write-Host ("QUEM ENTREGOU ISTO (" + $prod.Count + "):")
  if ($prod.Count -eq 0) { Write-Host "  (nenhuma Task registrou este arquivo como entrega)" }
  foreach ($n in $prod) { Show-Node $n "  - " }
  Write-Host ""

  $visited = @{}
  $frontier = @()
  $totalChain = 0; $sessions = @{}; $derived = @{}
  Write-Host ("QUEM DEPENDE DISTO (cadeia transitiva, profundidade <= " + $Depth + "):")
  for ($d = 1; $d -le $Depth; $d++) {
    $hits = @()
    if ($d -eq 1) {
      # nivel 1: quem declarou ESTE arquivo como base
      foreach ($n in $nodes) {
        $match = $false
        foreach ($ck in $n.consumes) { if (Test-KeyDepends $ck $qn) { $match = $true; break } }
        if ($match) { $hits += $n }
      }
    } else {
      # niveis seguintes: segue as arestas do grafo (que ja respeitam a ordem do tempo)
      $seenLvl = @{}
      foreach ($f in $frontier) {
        if (-not $outAdj.ContainsKey($f.key)) { continue }
        foreach ($e in $outAdj[$f.key]) {
          if ($visited.ContainsKey($e.to) -or $seenLvl.ContainsKey($e.to)) { continue }
          $seenLvl[$e.to] = $true
          $hits += $byKey[$e.to]
        }
      }
    }
    if ($hits.Count -eq 0) { break }
    $lbl = if ($d -eq 1) { "partiu DIRETO deste arquivo" } else { "saiu do que o nivel " + ($d - 1) + " entregou" }
    Write-Host ("")
    Write-Host ("  [nivel " + $d + "] " + $lbl + " - " + $hits.Count + " Task(s)")
    $next = @()
    foreach ($n in ($hits | Sort-Object created -Descending)) {
      $visited[$n.key] = $true
      $totalChain++
      $s = Field $n.t 'session'; if ($s -ne '') { $sessions[$s] = $true }
      foreach ($pk in $n.produces) { $derived[$pk] = $true }
      $next += $n
      Show-Node $n "  - "
    }
    $frontier = $next
  }
  Write-Host ""
  if ($totalChain -eq 0) {
    Write-Host "  Nada depende disto no ledger: nenhuma Task declarou este arquivo como base."
  } else {
    Write-Host ("RESUMO: " + $totalChain + " Task(s) na cadeia de impacto | " + $derived.Count + " entrega(s) derivada(s) | " + $sessions.Count + " sessao(oes) envolvida(s).")
  }
}

# ---------------------------------------------------------------- -Trace
function Invoke-Trace([string]$q) {
  $qq = $q.Trim()
  $start = @()
  if ($qq -match '^(?i)(task-)?0*(\d{1,3})$') {
    $idw = "TASK-" + ([int]$Matches[2]).ToString("000")
    $start = @($nodes | Where-Object { $_.id -eq $idw })
  }
  if ($start.Count -eq 0) {
    $qn = (ConvertTo-NormPath $qq).ToLowerInvariant().TrimEnd('/')
    if ($script:RootLow -ne '' -and $qn.StartsWith($script:RootLow + '/')) { $qn = $qn.Substring($script:RootLow.Length + 1) }
    $start = @($nodes | Where-Object { $n = $_; @($n.produces | Where-Object { Test-KeyProduces $_ $qn }).Count -gt 0 } | Sort-Object created -Descending)
  }
  Write-Host ("=== LINHAGEM (de onde veio): '" + $q + "' ===")
  Write-Host ("fonte: " + $StateFile + " | " + $nodes.Count + " Task(s) | " + $edges.Count + " aresta(s)")
  Write-Host ""
  if ($start.Count -eq 0) {
    Write-Host "Nao achei Task com esse id nem entrega com esse caminho no ledger."
    return
  }
  foreach ($s0 in $start) {
    Show-Node $s0 ""
    $seen = @{ $s0.key = $true }
    Walk-Back $s0 1 $seen
    Write-Host ""
  }
}
function Walk-Back($n, [int]$lvl, $seen) {
  $pad = "  " * $lvl
  if ($lvl -gt $Depth) { Write-Host ($pad + "<- (profundidade " + $Depth + " atingida - use -Depth maior)"); return }
  $parents = @()
  if ($inAdj.ContainsKey($n.key)) {
    $parents = @($inAdj[$n.key] | ForEach-Object { $byKey[$_.from] } | Where-Object { -not $seen.ContainsKey($_.key) } | Sort-Object created -Descending)
  }
  if ($parents.Count -eq 0) {
    $b = Field $n.t 'base_artifact'
    if ($b -eq '') { Write-Host ($pad + "<- RAIZ: base nao registrada - FURO de rastreio (a cadeia morre aqui)") }
    else { Write-Host ($pad + "<- RAIZ: '" + (Cut $b 100) + "' - base EXTERNA ao ledger (nenhuma Task a produziu)") }
    return
  }
  foreach ($p in $parents) {
    $seen[$p.key] = $true
    $via = @($inAdj[$n.key] | Where-Object { $_.from -eq $p.key })[0].via
    Write-Host ($pad + "<- via '" + (Cut $via 70) + "'")
    Show-Node $p ($pad + "   ")
    Walk-Back $p ($lvl + 1) $seen
  }
}

# ---------------------------------------------------------------- -Health
function Get-HealthData() {
  $h = @{}
  $h.total = $nodes.Count
  $h.completa = 0; $h.orfas = 0; $h.semEntrega = 0; $h.semBase = 0; $h.semSessao = 0; $h.semProjeto = 0; $h.semGate = 0
  foreach ($n in $nodes) {
    $a = Field $n.t 'artifact'; $b = Field $n.t 'base_artifact'; $s = Field $n.t 'session'; $p = Field $n.t 'project'; $g = Field $n.t 'gate_verdict'
    if ($a -ne '' -and $b -ne '' -and $s -ne '' -and $p -ne '') { $h.completa++ }
    if ($a -ne '' -and $b -eq '') { $h.orfas++ }
    if ($a -eq '') { $h.semEntrega++ }
    if ($b -eq '') { $h.semBase++ }
    if ($s -eq '') { $h.semSessao++ }
    if ($p -eq '') { $h.semProjeto++ }
    if ($g -eq '') { $h.semGate++ }
  }
  # base GROSSA: declarou uma pasta inteira ("clients/alia-flow-lab") em vez do arquivo que usou.
  # Nao da pra responder impacto a partir disso - o rastro existe, mas nao aponta pra nada.
  $h.baseGrossa = 0
  foreach ($n in $nodes) {
    if ((Field $n.t 'base_artifact') -eq '') { continue }
    if ($n.consumes.Count -eq 0) { $h.baseGrossa++; continue }
    $temArquivo = $false
    foreach ($k in $n.consumes) { if (Test-HasExt $k) { $temArquivo = $true; break } }
    if (-not $temArquivo) { $h.baseGrossa++ }
  }
  $h.edges = $edges.Count
  $h.ilhadas = @($nodes | Where-Object { -not $outAdj.ContainsKey($_.key) -and -not $inAdj.ContainsKey($_.key) }).Count
  # ids repetidos
  $dup = @()
  foreach ($g in ($nodes | Group-Object id)) { if ($g.Count -gt 1) { $dup += ($g.Name + " x" + $g.Count) } }
  $h.dupIds = $dup

  # ponteiros: caminho relativo que deveria existir no disco do studio
  $topDirs = @{}
  foreach ($d in (Get-ChildItem -LiteralPath $studioRoot -Directory -ErrorAction SilentlyContinue)) { $topDirs[$d.Name.ToLowerInvariant()] = $true }
  $mortos = @(); $foraDoStudio = 0; $naoResolviveis = @(); $vistos = @{}
  foreach ($n in $nodes) {
    foreach ($k in (@($n.produces) + @($n.consumes))) {
      if ($vistos.ContainsKey($k)) { continue }
      $vistos[$k] = $true
      if ($k -match '^[a-z]:/') { $foraDoStudio++; continue }
      $first = $k.Split('/')[0]
      if (-not $topDirs.ContainsKey($first)) { $naoResolviveis += $k; continue }
      if (-not (Test-Path -LiteralPath (Join-Path $studioRoot ($k -replace '/','\')))) { $mortos += ($k + "  <- " + $n.id) }
    }
  }
  $h.chaves = $vistos.Count
  $h.mortos = $mortos
  $h.foraDoStudio = $foraDoStudio
  $h.naoResolviveis = $naoResolviveis

  # clientes: disco vs ledger vs tasks
  $ledger = @{}
  if ($st.clients) { foreach ($c in @($st.clients)) { $ledger["$($c.id)"] = $true } }
  $disco = @()
  $cdir = Join-Path $studioRoot "clients"
  if (Test-Path -LiteralPath $cdir) { $disco = @((Get-ChildItem -LiteralPath $cdir -Directory | ForEach-Object { $_.Name })) }
  $h.ledgerClients = @($ledger.Keys)
  $h.discoForaDoLedger = @($disco | Where-Object { -not $ledger.ContainsKey($_) })
  $usados = @{}; foreach ($n in $nodes) { $usados[(Field $n.t 'client')] = $true }
  $h.tasksForaDoLedger = @($usados.Keys | Where-Object { $_ -ne '' -and -not $ledger.ContainsKey($_) })
  return $h
}
function Invoke-Health() {
  $h = Get-HealthData
  Write-Host "=== SAUDE DO RASTRO (numeros do ledger, sem adjetivo) ==="
  Write-Host ("fonte: " + $StateFile)
  Write-Host ""
  Write-Host ("Tasks no ledger ............................ " + $h.total)
  Write-Host ("  linhagem COMPLETA (entrega+base+projeto+sessao) " + $h.completa + "  (" + [math]::Round(100.0 * $h.completa / [math]::Max(1, $h.total)) + "%)")
  Write-Host ("  ORFAS (entregou mas nao declarou base) ....... " + $h.orfas)
  Write-Host ("  base GROSSA (pasta inteira, nao o arquivo) ... " + $h.baseGrossa)
  Write-Host ("  sem entrega registrada ....................... " + $h.semEntrega)
  Write-Host ("  sem base registrada .......................... " + $h.semBase)
  Write-Host ("  sem sessao registrada ........................ " + $h.semSessao)
  Write-Host ("  sem projeto registrado ....................... " + $h.semProjeto)
  Write-Host ("  sem veredito de Gate ......................... " + $h.semGate)
  Write-Host ""
  Write-Host ("Arestas de linhagem inferidas ................ " + $h.edges)
  Write-Host ("  Tasks ILHADAS (sem elo pra frente nem pra tras) " + $h.ilhadas)
  Write-Host ("  ids repetidos no ledger ...................... " + $h.dupIds.Count + $(if ($h.dupIds.Count -gt 0) { "  [" + ($h.dupIds -join ', ') + "]" } else { "" }))
  Write-Host ""
  Write-Host ("Chaves de caminho distintas no rastro ........ " + $h.chaves)
  Write-Host ("  APONTAM PRA ARQUIVO QUE NAO EXISTE MAIS ...... " + $h.mortos.Count)
  foreach ($m in ($h.mortos | Select-Object -First 15)) { Write-Host ("    - " + $m) }
  if ($h.mortos.Count -gt 15) { Write-Host ("    ... (+" + ($h.mortos.Count - 15) + ")") }
  Write-Host ("  fora do studio (caminho absoluto, nao verificado) " + $h.foraDoStudio)
  Write-Host ("  relativos a repo externo (nao resolviveis aqui) .. " + $h.naoResolviveis.Count)
  Write-Host ""
  Write-Host ("Clientes no ledger ........................... " + $h.ledgerClients.Count + "  [" + (($h.ledgerClients | Sort-Object) -join ', ') + "]")
  Write-Host ("  em DISCO mas fora do ledger ................. " + $h.discoForaDoLedger.Count + $(if ($h.discoForaDoLedger.Count -gt 0) { "  [" + (($h.discoForaDoLedger | Sort-Object) -join ', ') + "]" } else { "" }))
  Write-Host ("  citados por Task mas fora do ledger ......... " + $h.tasksForaDoLedger.Count + $(if ($h.tasksForaDoLedger.Count -gt 0) { "  [" + (($h.tasksForaDoLedger | Sort-Object) -join ', ') + "]" } else { "" }))
}

# ---------------------------------------------------------------- -Html
function JEsc([string]$s) {
  if ($null -eq $s) { return "" }
  $o = New-Object System.Text.StringBuilder
  foreach ($ch in $s.ToCharArray()) {
    $c = [int]$ch
    if ($ch -eq '"') { [void]$o.Append('\"') }
    elseif ($ch -eq '\') { [void]$o.Append('\\') }
    elseif ($ch -eq '<') { [void]$o.Append('\u003c') }
    elseif ($ch -eq '>') { [void]$o.Append('\u003e') }
    elseif ($ch -eq '&') { [void]$o.Append('\u0026') }
    elseif ($c -lt 32 -or $c -gt 126) { [void]$o.Append('\u' + $c.ToString('x4')) }
    else { [void]$o.Append($ch) }
  }
  return $o.ToString()
}
function HEsc([string]$s) {
  if ($null -eq $s) { return "" }
  return $s.Replace('&','&amp;').Replace('<','&lt;').Replace('>','&gt;').Replace('"','&quot;')
}
function JArr($items) {
  $p = @(); foreach ($x in $items) { $p += ('"' + (JEsc "$x") + '"') }
  return "[" + ($p -join ",") + "]"
}
function Invoke-Html([string]$out) {
  $h = Get-HealthData
  $stamp = (Get-Date).ToString("yyyy-MM-dd HH:mm")
  $sb = New-Object System.Text.StringBuilder

  $head = @'
<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Mapa de linhagem do ledger - Studio Farina</title>
<style>
  :root{
    --x-canvas:#0a0a0a; --x-canvas-card:#191919; --x-canvas-mid:#363a3f;
    --x-hairline:#212327; --x-pillline:rgba(255,255,255,.25);
    --x-ink:#ffffff; --x-body:#dadbdf; --x-mute:#7d8187;
    --x-sunset:#ff7a17; --x-sunset-soft:#ffc285; --x-critical:#e64545;
    --sans:'Public Sans','Inter',system-ui,-apple-system,'Segoe UI',sans-serif;
    --mono:'JetBrains Mono','Geist Mono',Consolas,ui-monospace,monospace;
  }
  *{margin:0;padding:0;box-sizing:border-box}
  body{background:var(--x-canvas);color:var(--x-ink);font-family:var(--sans);font-size:16px;line-height:1.5}
  .wrap{max-width:1180px;margin:0 auto;padding:0 24px}
  section{padding:44px 0;border-bottom:1px solid var(--x-hairline)}
  .eyebrow{font-family:var(--mono);font-size:12px;letter-spacing:1.4px;text-transform:uppercase;color:var(--x-ink);margin-bottom:12px}
  .eyebrow .m{color:var(--x-mute)}
  h1{font-size:clamp(30px,5vw,52px);font-weight:400;line-height:1.08;letter-spacing:-1.4px}
  h1 b{font-weight:700}h1 .a{color:var(--x-sunset)}
  h2.sec{font-size:clamp(24px,3vw,34px);font-weight:400;letter-spacing:-.8px;margin-bottom:8px}
  h2.sec b{font-weight:700}
  .sub{color:var(--x-body);font-size:16px;line-height:25px;max-width:70ch;margin-bottom:28px}
  .kgrid{display:grid;grid-template-columns:repeat(5,1fr);gap:12px;margin-top:32px}
  @media(max-width:900px){.kgrid{grid-template-columns:repeat(2,1fr)}}
  .kpi{background:var(--x-canvas-card);border:1px solid var(--x-hairline);border-radius:8px;padding:18px 20px}
  .kpi .n{font-size:30px;letter-spacing:-.6px;font-variant-numeric:tabular-nums}
  .kpi .n b{font-weight:700}.kpi .n.warn b{color:var(--x-sunset)}.kpi .n.crit b{color:var(--x-critical)}
  .kpi .t{font-family:var(--mono);font-size:10.5px;letter-spacing:1px;text-transform:uppercase;color:var(--x-mute);margin-top:8px;line-height:1.5}
  .grid2{display:grid;grid-template-columns:360px 1fr;gap:20px;align-items:start}
  @media(max-width:900px){.grid2{grid-template-columns:1fr}}
  .panel{background:var(--x-canvas-card);border:1px solid var(--x-hairline);border-radius:8px;padding:16px}
  input[type=search]{width:100%;background:#0f0f0f;border:1px solid var(--x-hairline);color:var(--x-ink);
    font-family:var(--mono);font-size:12.5px;padding:10px 12px;border-radius:6px;outline:none}
  input[type=search]:focus{border-color:var(--x-sunset)}
  .list{max-height:560px;overflow:auto;margin-top:10px}
  .it{display:block;width:100%;text-align:left;background:none;border:0;border-bottom:1px solid var(--x-hairline);
    color:var(--x-body);font-family:var(--mono);font-size:11.5px;padding:9px 6px;cursor:pointer;line-height:1.45}
  .it:hover{background:#101010;color:var(--x-ink)}
  .it.on{background:#131313;color:var(--x-ink);box-shadow:inset 2px 0 0 var(--x-sunset)}
  .it .c{color:var(--x-mute)}
  .st{display:inline-flex;align-items:center;gap:7px;border:1px solid var(--x-pillline);border-radius:9999px;padding:3px 11px;
    font-family:var(--mono);font-size:10px;letter-spacing:1.1px;text-transform:uppercase;white-space:nowrap}
  .st .d{width:6px;height:6px;border-radius:50%;background:var(--x-ink)}
  .st.wait{color:var(--x-sunset);border-color:rgba(255,122,23,.4)}.st.wait .d{background:var(--x-sunset)}
  .lvl{font-family:var(--mono);font-size:11px;letter-spacing:1.2px;text-transform:uppercase;color:var(--x-sunset);margin:22px 0 10px}
  .node{border-left:1px solid var(--x-hairline);padding:0 0 14px 16px;margin-left:4px;position:relative}
  .node::before{content:'';position:absolute;left:-4px;top:7px;width:7px;height:7px;border-radius:50%;background:var(--x-canvas-mid)}
  .node.hit::before{background:var(--x-sunset)}
  .node h4{font-size:14px;font-weight:600;line-height:1.35;margin-bottom:5px}
  .node h4 span{font-family:var(--mono);font-size:11px;color:var(--x-sunset);margin-right:8px}
  .node .meta{font-family:var(--mono);font-size:10.5px;color:var(--x-mute);line-height:1.75;word-break:break-word}
  .node .meta b{color:var(--x-body);font-weight:400}
  .node .meta .miss{color:var(--x-sunset)}
  .dead{font-family:var(--mono);font-size:11px;color:var(--x-body);line-height:1.9;word-break:break-all}
  .dead .who{color:var(--x-mute)}
  table{width:100%;border-collapse:collapse;font-size:13px}
  td{border-top:1px solid var(--x-hairline);padding:9px 6px;color:var(--x-body)}
  td.k{font-family:var(--mono);font-size:11px;color:var(--x-mute);width:60%}
  td.v{text-align:right;font-variant-numeric:tabular-nums;font-size:17px}
  td.v.warn{color:var(--x-sunset)}
  .ft{padding:26px 0 60px;font-family:var(--mono);font-size:10.5px;letter-spacing:.6px;color:var(--x-mute)}
  .hint{font-family:var(--mono);font-size:11px;color:var(--x-mute);margin-top:10px;line-height:1.7}
</style>
</head>
<body>
'@
  [void]$sb.AppendLine($head)
  [void]$sb.AppendLine('<section style="border-bottom:1px solid var(--x-hairline)"><div class="wrap">')
  [void]$sb.AppendLine('<div class="eyebrow">Alia Flow <span class="m">/ leitura do ledger como grafo</span></div>')
  [void]$sb.AppendLine('<h1>Mapa de <b>linhagem</b><br>do <span class="a">rastro que ja existe</span></h1>')
  [void]$sb.AppendLine('<p class="sub" style="margin-top:20px">Cada Task do <code>state.json</code> declara o que entregou, de onde partiu e em que sessao. Ligando esses campos, o ledger responde &quot;o que depende disto se eu mexer aqui&quot; e &quot;de onde isto veio, elo por elo&quot;. Gerado em ' + $stamp + ' - fonte: ' + (HEsc $StateFile) + '</p>')
  [void]$sb.AppendLine('<div class="kgrid">')
  [void]$sb.AppendLine('<div class="kpi"><div class="n"><b>' + $h.total + '</b></div><div class="t">tarefas no ledger</div></div>')
  [void]$sb.AppendLine('<div class="kpi"><div class="n"><b>' + $h.edges + '</b></div><div class="t">arestas de linhagem</div></div>')
  [void]$sb.AppendLine('<div class="kpi"><div class="n"><b>' + $h.completa + '</b></div><div class="t">linhagem completa</div></div>')
  [void]$sb.AppendLine('<div class="kpi"><div class="n warn"><b>' + $h.orfas + '</b></div><div class="t">entregas sem base</div></div>')
  [void]$sb.AppendLine('<div class="kpi"><div class="n crit"><b>' + $h.mortos.Count + '</b></div><div class="t">ponteiros mortos</div></div>')
  [void]$sb.AppendLine('</div></div></section>')

  [void]$sb.AppendLine('<section><div class="wrap">')
  [void]$sb.AppendLine('<h2 class="sec">O <b>mapa</b> navegavel</h2>')
  [void]$sb.AppendLine('<p class="sub">Escolha uma tarefa ou um arquivo-base. A direita: a cadeia para frente (o que depende) e para tras (de onde veio).</p>')
  [void]$sb.AppendLine('<div class="grid2"><div class="panel">')
  [void]$sb.AppendLine('<input type="search" id="q" placeholder="filtrar por id, arquivo, cliente...">')
  [void]$sb.AppendLine('<div class="list" id="list"></div>')
  [void]$sb.AppendLine('<div class="hint">Topo da lista: os arquivos-base mais reusados (os hubs do rastro).</div>')
  [void]$sb.AppendLine('</div><div class="panel" id="detail"></div></div></div></section>')

  [void]$sb.AppendLine('<section><div class="wrap">')
  [void]$sb.AppendLine('<h2 class="sec">A saude do <b>proprio rastro</b></h2>')
  [void]$sb.AppendLine('<p class="sub">Numeros medidos no ledger. O que esta furado aqui e o que o mapa nao consegue responder depois.</p>')
  [void]$sb.AppendLine('<table>')
  $rows = @(
    @("linhagem completa (entrega + base + projeto + sessao)", $h.completa, $false),
    @("orfas: entregaram mas nao declararam base", $h.orfas, $true),
    @("base grossa: declararam a pasta, nao o arquivo", $h.baseGrossa, $true),
    @("sem entrega registrada", $h.semEntrega, $true),
    @("sem sessao registrada", $h.semSessao, $true),
    @("sem projeto registrado", $h.semProjeto, $true),
    @("sem veredito de Gate", $h.semGate, $true),
    @("tarefas ilhadas (nenhum elo, pra frente ou pra tras)", $h.ilhadas, $true),
    @("ids repetidos no ledger", $h.dupIds.Count, $true),
    @("chaves de caminho distintas no rastro", $h.chaves, $false),
    @("ponteiros para arquivo que nao existe mais", $h.mortos.Count, $true),
    @("caminhos absolutos fora do studio (nao verificaveis)", $h.foraDoStudio, $false),
    @("caminhos de repo externo (nao resolviveis aqui)", $h.naoResolviveis.Count, $false),
    @("clientes em disco fora do ledger", $h.discoForaDoLedger.Count, $true),
    @("clientes citados por Task mas fora do ledger", $h.tasksForaDoLedger.Count, $true)
  )
  foreach ($r in $rows) {
    $cls = if ($r[2] -and [int]$r[1] -gt 0) { " warn" } else { "" }
    [void]$sb.AppendLine('<tr><td class="k">' + $r[0] + '</td><td class="v' + $cls + '">' + $r[1] + '</td></tr>')
  }
  [void]$sb.AppendLine('</table>')
  if ($h.mortos.Count -gt 0) {
    [void]$sb.AppendLine('<div class="lvl">Ponteiros mortos (arquivo sumiu do disco, o rastro ficou pendurado)</div>')
    foreach ($m in ($h.mortos | Select-Object -First 40)) {
      $parts = $m -split '  <- '
      [void]$sb.AppendLine('<div class="dead">' + $parts[0] + ' <span class="who">&lt;- ' + $parts[1] + '</span></div>')
    }
  }
  if ($h.discoForaDoLedger.Count -gt 0) {
    [void]$sb.AppendLine('<div class="lvl">Clientes em disco que o ledger nao enxerga</div>')
    [void]$sb.AppendLine('<div class="dead">' + (($h.discoForaDoLedger | Sort-Object) -join ' &middot; ') + '</div>')
  }
  [void]$sb.AppendLine('</div></section>')
  [void]$sb.AppendLine('<div class="wrap ft">// SEM REGISTRO = NAO ACONTECEU &middot; SEM LINHAGEM = SEM CONTINUIDADE &middot; leitura em grafo do state.json (somente leitura) &middot; scripts/lineage-graph.ps1</div>')

  # ------- dados
  $jt = @()
  foreach ($n in $nodes) {
    $t = $n.t
    $jt += ('{"k":"' + (JEsc $n.key) + '","id":"' + (JEsc $n.id) + '","cl":"' + (JEsc (Field $t 'client')) +
            '","pr":"' + (JEsc (Field $t 'project')) + '","ti":"' + (JEsc (Field $t 'title')) +
            '","stt":"' + (JEsc (Field $t 'status')) + '","ar":"' + (JEsc (Field $t 'artifact')) +
            '","ba":"' + (JEsc (Field $t 'base_artifact')) + '","se":"' + (JEsc (Field $t 'session')) +
            '","cr":"' + (JEsc (Field $t 'created')) + '","sp":"' + (JEsc (Field $t 'specialist')) +
            '","pk":' + (JArr $n.produces) + '}')
  }
  $je = @()
  foreach ($e in $edges) { $je += ('{"f":"' + (JEsc $e.from) + '","t":"' + (JEsc $e.to) + '","v":"' + (JEsc $e.via) + '"}') }
  # hubs: chave-base mais reusada
  $cnt = @{}
  foreach ($n in $nodes) {
    foreach ($k in $n.consumes) {
      if (-not (Test-HasExt $k)) { continue }   # hub e ARQUIVO reusado; pasta inteira e base grossa
      if ($cnt.ContainsKey($k)) { $cnt[$k]++ } else { $cnt[$k] = 1 }
    }
  }
  $jh = @()
  foreach ($p in ($cnt.GetEnumerator() | Where-Object { $_.Value -ge 2 } | Sort-Object -Property Value -Descending | Select-Object -First 30)) {
    $jh += ('{"k":"' + (JEsc $p.Key) + '","n":' + $p.Value + '}')
  }
  [void]$sb.AppendLine('<script>')
  [void]$sb.AppendLine('var TASKS=[' + ($jt -join ',') + '];')
  [void]$sb.AppendLine('var EDGES=[' + ($je -join ',') + '];')
  [void]$sb.AppendLine('var HUBS=[' + ($jh -join ',') + '];')

  $js = @'
var BY={},OUT={},IN={};
TASKS.forEach(function(t){BY[t.k]=t;});
EDGES.forEach(function(e){(OUT[e.f]=OUT[e.f]||[]).push(e);(IN[e.t]=IN[e.t]||[]).push(e);});
function esc(s){return (s||"").replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;");}
function miss(s,txt){return s?esc(s):'<span class="miss">'+txt+'</span>';}
function keyMatch(a,b){if(a===b)return true;
  if(a.length>b.length){var x=a;a=b;b=x;}
  if(b.slice(-(a.length+1))==="/"+a)return true;
  if(a.split("/").pop().indexOf(".")<0&&b.indexOf(a+"/")===0)return true;
  return false;}
function nodeHtml(t,hit){
  return '<div class="node'+(hit?' hit':'')+'"><h4><span>'+esc(t.id)+'</span>'+esc(t.ti)+'</h4>'+
   '<div class="meta"><b>cliente:</b> '+esc(t.cl)+' / '+miss(t.pr,'sem projeto')+' &nbsp;|&nbsp; <b>status:</b> '+esc(t.stt)+' &nbsp;|&nbsp; <b>quem:</b> '+esc(t.sp)+'<br>'+
   '<b>entregou:</b> '+miss(t.ar,'nao registrado')+'<br><b>partiu de:</b> '+miss(t.ba,'nao registrado')+'<br>'+
   '<b>sessao:</b> '+miss(t.se,'nao registrada')+' &nbsp;|&nbsp; '+esc(t.cr)+'</div></div>';
}
function forward(startKeys,seed){
  var seen={},out=[],frontier=startKeys.slice();
  (seed||[]).forEach(function(k){seen[k]=1;});
  for(var d=1;d<=4;d++){
    var hits=[];
    TASKS.forEach(function(t){
      if(seen[t.k])return;
      var ok=false;
      for(var i=0;i<frontier.length;i++){ if(baseHas(t,frontier[i])){ok=true;break;} }
      if(ok)hits.push(t);
    });
    if(!hits.length)break;
    hits.forEach(function(t){seen[t.k]=1;});
    hits.sort(function(a,b){return a.cr<b.cr?1:-1;});
    out.push({d:d,items:hits});
    var nf=[];hits.forEach(function(t){(t.pk||[]).forEach(function(k){nf.push(k);});});
    if(!nf.length)break;frontier=nf;
  }
  return out;
}
var CONS={};
TASKS.forEach(function(t){CONS[t.k]=(t.ba||"").toLowerCase().replace(/\\/g,"/");});
function baseHas(t,key){var s=CONS[t.k];if(!s)return false;
  if(s.indexOf(key)>=0)return true;
  var leaf=key.split("/").pop();
  return leaf.length>4&&leaf.indexOf(".")>0&&s.indexOf(leaf)>=0;}
function back(t,lvl,seen,acc){
  if(lvl>4)return;
  var ps=(IN[t.k]||[]).map(function(e){return {t:BY[e.f],v:e.v};}).filter(function(p){return p.t&&!seen[p.t.k];});
  if(!ps.length){acc.push({lvl:lvl,root:true,txt:t.ba});return;}
  ps.forEach(function(p){seen[p.t.k]=1;acc.push({lvl:lvl,via:p.v,t:p.t});back(p.t,lvl+1,seen,acc);});
}
function showTask(k){
  var t=BY[k];if(!t)return;
  var h='<div class="lvl">a tarefa</div>'+nodeHtml(t,true);
  var seen={};seen[k]=1;var acc=[];back(t,1,seen,acc);
  h+='<div class="lvl">de onde veio (elo por elo, ate a raiz)</div>';
  if(!acc.length){h+='<div class="meta" style="font-family:var(--mono);color:var(--x-mute)">sem elo anterior no ledger.</div>';}
  acc.forEach(function(a){
    var pad='margin-left:'+((a.lvl-1)*14)+'px';
    if(a.root){h+='<div class="node" style="'+pad+'"><div class="meta">RAIZ: '+(a.txt?esc(a.txt):'<span class="miss">base nao registrada - furo de rastreio</span>')+'</div></div>';}
    else{h+='<div style="'+pad+'"><div class="meta" style="font-family:var(--mono);font-size:10.5px;color:var(--x-sunset)">&lt;- via '+esc(a.via)+'</div>'+nodeHtml(a.t,false)+'</div>';}
  });
  var lv=forward(t.pk||[],[k]);
  h+='<div class="lvl">o que depende desta entrega</div>';
  if(!lv.length){h+='<div class="meta" style="font-family:var(--mono);color:var(--x-mute)">nada partiu daqui (ainda).</div>';}
  lv.forEach(function(g){h+='<div class="lvl" style="color:var(--x-mute)">nivel '+g.d+' - '+g.items.length+' tarefa(s)</div>';
    g.items.forEach(function(x){h+=nodeHtml(x,g.d===1);});});
  document.getElementById('detail').innerHTML=h;
}
function showHub(key){
  var prod=TASKS.filter(function(t){return (t.pk||[]).some(function(k){return keyMatch(k,key);});})
                .sort(function(a,b){return a.cr<b.cr?1:-1;});
  var h='<div class="lvl">arquivo-base: '+esc(key)+'</div>';
  h+='<div class="lvl" style="color:var(--x-mute)">quem entregou ('+prod.length+')</div>';
  if(!prod.length)h+='<div class="meta" style="font-family:var(--mono);color:var(--x-mute)">nenhuma tarefa registrou este arquivo como entrega.</div>';
  prod.forEach(function(t){h+=nodeHtml(t,true);});
  var lv=forward([key],prod.map(function(t){return t.k;}));
  h+='<div class="lvl">o que depende disto</div>';
  if(!lv.length)h+='<div class="meta" style="font-family:var(--mono);color:var(--x-mute)">nada depende disto no ledger.</div>';
  lv.forEach(function(g){h+='<div class="lvl" style="color:var(--x-mute)">nivel '+g.d+' - '+g.items.length+' tarefa(s)</div>';
    g.items.forEach(function(x){h+=nodeHtml(x,g.d===1);});});
  document.getElementById('detail').innerHTML=h;
}
function render(f){
  f=(f||"").toLowerCase();
  var el=document.getElementById('list'),h='';
  HUBS.forEach(function(x){
    if(f&&x.k.indexOf(f)<0)return;
    h+='<button class="it" data-hub="'+esc(x.k)+'"><span class="c">['+x.n+' dependem]</span> '+esc(x.k)+'</button>';
  });
  TASKS.slice().sort(function(a,b){return a.cr<b.cr?1:-1;}).forEach(function(t){
    var blob=(t.id+' '+t.cl+' '+t.pr+' '+t.ti+' '+t.ar+' '+t.ba).toLowerCase();
    if(f&&blob.indexOf(f)<0)return;
    h+='<button class="it" data-task="'+esc(t.k)+'">'+esc(t.id)+' <span class="c">'+esc(t.cl)+'</span> '+esc(t.ti.slice(0,64))+'</button>';
  });
  el.innerHTML=h||'<div class="hint">nada bate com esse filtro.</div>';
  Array.prototype.forEach.call(el.querySelectorAll('.it'),function(b){
    b.onclick=function(){
      Array.prototype.forEach.call(el.querySelectorAll('.it'),function(o){o.classList.remove('on');});
      b.classList.add('on');
      if(b.dataset.hub)showHub(b.dataset.hub);else showTask(b.dataset.task);
    };
  });
}
document.getElementById('q').addEventListener('input',function(e){render(e.target.value);});
render('');
if(HUBS.length)showHub(HUBS[0].k);else if(TASKS.length)showTask(TASKS[TASKS.length-1].k);
'@
  [void]$sb.AppendLine($js)
  [void]$sb.AppendLine('</script></body></html>')

  $outDir = Split-Path -Parent $out
  if ($outDir -ne "" -and -not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
  [System.IO.File]::WriteAllText($out, $sb.ToString(), $utf8)
  Write-Host ("=== Mapa de linhagem gerado ===")
  Write-Host ("tarefas: " + $h.total + " | arestas: " + $h.edges + " | linhagem completa: " + $h.completa + " | ponteiros mortos: " + $h.mortos.Count)
  Write-Host ("saida:   " + $out)
}

# ---------------------------------------------------------------- roteador
Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue
$did = $false
if ($Impact -ne "") { Invoke-Impact $Impact; $did = $true }
if ($Trace  -ne "") { if ($did) { Write-Host "" }; Invoke-Trace $Trace; $did = $true }
if ($Health)        { if ($did) { Write-Host "" }; Invoke-Health; $did = $true }
if ($Html   -ne "") { if ($did) { Write-Host "" }; Invoke-Html $Html; $did = $true }
if (-not $did) {
  Write-Host "lineage-graph.ps1 - le o ledger de Tasks como mapa de linhagem (somente leitura)."
  Write-Host ("ledger: " + $StateFile + " (" + $nodes.Count + " Task(s), " + $edges.Count + " aresta(s))")
  Write-Host ""
  Write-Host "  -Impact <arquivo>   o que depende disto (cadeia pra frente, com sessao de cada elo)"
  Write-Host "  -Trace  <id|arquivo> de onde isto veio, elo por elo, ate a raiz"
  Write-Host "  -Health             saude do rastro em numeros (orfas, ponteiros mortos, clientes fora do ledger)"
  Write-Host "  -Html   <saida>     o mesmo mapa como pagina navegavel autocontida"
  Write-Host "  -Depth  <n>         profundidade da cadeia (default 4)   -StateFile <caminho>"
}
exit 0
