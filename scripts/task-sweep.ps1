<#
  task-sweep.ps1 - Varredura periodica de Tasks abertas (TASK-510, mandato do CEO 09/09/2026):
  "tem tarefas que eu nao vou fechar, voce sempre tem que fechar evitando ficar com ponta solta,
  se nao faz bola de neve, pensa em como gerir isso". Antes: 117 Tasks abertas no state.json, sem
  mecanismo nenhum de limpeza - so acumulava. Este script e o mecanismo: classifica Task aberta
  (open|todo|doing|blocked) por EVIDENCIA OBJETIVA (artifact existe em disco, idade em dias desde
  o ultimo movimento), nunca por julgamento de conteudo.

  4 baldes:
    ENTREGUE   - artifact existe em disco (arquivo com tamanho maior que 0, ou pasta com 1+ item).
                 Acao: fecha done com gate_verdict "PASS retroativo" (mesma FORMA usada 9x no
                 ledger para TASK-287, ARCHIVE, 25/08/2026 - grep por essa frase em state.json).
                 Nao e reabertura dos 6 criterios do Gate, so evidencia minima.
    ABANDONADA - sem artifact em disco E parada ha mais de MaxAge dias (default 45).
                 Acao: retired com motivo "sem movimento por N dias, sem entrega registrada
                 (varredura DD/MM/AAAA)".
    PARADA     - entre 21 e MaxAge dias. Acao: NENHUMA, so lista no relatorio como aviso.
    VIVA       - menos de 21 dias. Nao toca.

  AVISO DE SOBREPOSICAO (nao classifica, so reporta): quando client+project tem 3+ Tasks abertas,
  lista juntas - sinal de versoes sucessivas do mesmo trabalho, que so um humano separa.

  IDADE = dias desde o movimento mais recente conhecido (o maior entre created e updated, quando
  updated existe - a maioria das Tasks so tem created, ver register-task.ps1). Task sem created
  nao entra na contagem de idade (fica listada a parte, SEM DATA).

  REVERSIVEL, SEMPRE: retired preserva o registro e a linhagem (NUNCA apaga Task). Desfazer:
    scripts/register-task.ps1 -Id ID -Status open -Specialist especialista-original

  MOTIVO TECNICO PARA NAO REUSAR register-task.ps1 -Id no balde ENTREGUE (unico ponto de escrita
  direta deste script): desde a TASK-509 (M5), register-task.ps1 -Id EXIGE -Tokens/-ToolUses
  sempre que o novo Status vira done ou review e o Specialist nao e alia - trava pensada pra
  fechamento NOVO de Task delegada, nao pra fechamento RETROATIVO de Task antiga sem custo
  registrado (o mesmo caso do sweep de TASK-287, que tambem escreveu gate_verdict direto no JSON).
  Como este sweep nao tem como inventar tokens/tool_uses nunca medidos, o balde ENTREGUE escreve
  direto no state.json (mesma tecnica de leitura/escrita UTF-8 sem BOM de register-task.ps1).
  O balde ABANDONADA (retired) NAO tem essa trava (M5 so cobre done/review) - por isso ele chama
  register-task.ps1 -Id -Status retired, reuse-first de verdade, sem reimplementar escrita.

  Uso:
    DRY-RUN (default, seguro):
      powershell -ExecutionPolicy Bypass -File task-sweep.ps1 -StateFile p -Client id -MaxAge 45
    APLICAR:
      powershell -ExecutionPolicy Bypass -File task-sweep.ps1 -Apply
    Casos que a regua automatica nao pega (decisao humana explicita), exigem -Apply junto:
      -Retire TASK-001,TASK-002   vai pra retired, motivo "superada por decisao do Operator"
      -Close  TASK-003,TASK-004   fecha done como se fosse ENTREGUE, mesmo texto de gate_verdict
#>
param(
  [string]$StateFile = "",
  [string]$Client = "",
  [int]$MaxAge = 45,
  [string]$Retire = "",
  # TASK-510: SUPERADA POR PROGRESSO. O sinal mais forte de ponta solta neste studio nao e a idade,
  # e o Client ter ANDADO sem a Task: lote de sessao registrado, trabalho seguiu, ninguem voltou.
  # Medido em 09/09/2026: 62 das 89 abertas tinham 5 ou mais Tasks fechadas depois no mesmo Client.
  # -SupersededMin 0 desliga a regra (default LIGADO em 5; o corte fino esta em Get-Superseded).
  [int]$SupersededMin = 5,
  # Nunca arquivar estas, mesmo batendo a regra (decisao explicita do Operator na varredura).
  [string]$Protect = "",
  [string]$Close = "",
  [switch]$Apply
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($StateFile)) { $StateFile = Join-Path $root "state.json" }
if (-not (Test-Path -LiteralPath $StateFile)) { Write-Host ("[ERRO] state.json nao encontrado: " + $StateFile); exit 1 }
$StateFile = (Resolve-Path -LiteralPath $StateFile).ProviderPath
$studioRoot = Split-Path -Parent $StateFile
$utf8 = New-Object System.Text.UTF8Encoding($false)
$registerScript = Join-Path $PSScriptRoot "register-task.ps1"
$nowDate = Get-Date
$hoje = $nowDate.ToString("dd/MM/yyyy")

$openStatuses = @("open", "todo", "doing", "blocked")

function Field($t, $name) {
  $v = $null
  try { $v = $t.PSObject.Properties[$name].Value } catch {}
  if ($null -eq $v) { return "" } else { return "$v" }
}

function Test-ArtifactExists {
  param([string]$ArtifactPath, [string]$StudioRoot)
  if ([string]::IsNullOrWhiteSpace($ArtifactPath)) { return $false }
  $p = $ArtifactPath
  if (-not [System.IO.Path]::IsPathRooted($p)) { $p = Join-Path $StudioRoot $p }
  if (-not (Test-Path -LiteralPath $p)) { return $false }
  $item = Get-Item -LiteralPath $p
  if ($item.PSIsContainer) {
    return (@(Get-ChildItem -LiteralPath $p -Force -ErrorAction SilentlyContinue).Count -gt 0)
  }
  return ($item.Length -gt 0)
}
$json = [System.IO.File]::ReadAllText($StateFile) | ConvertFrom-Json
$tasks = @(); if ($json.tasks) { $tasks = @($json.tasks) }

$retireIds = @($Retire -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
$protectIds = @($Protect -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
$closeIds  = @($Close  -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })

$gateText = "PASS retroativo (TASK-510, ARCHIVE, " + $hoje + "): artifact medido em disco (existe, tamanho maior que 0, path coerente com o titulo); nao e reabertura dos 6 criterios completos do Gate, so a evidencia minima de entrega. Registrado por task-sweep.ps1 porque a Task ficou aberta com prova disponivel."

# TASK-510: quantas Tasks do MESMO Client foram fechadas DEPOIS desta. E a medida de "o Client
# andou sem ela". Nao olha titulo nem conteudo - so data e status, tudo objetivo.
function Get-DoneAfter($allTasks, $client, $created) {
  if ([string]::IsNullOrWhiteSpace($created)) { return 0 }
  $n = 0
  foreach ($x in $allTasks) {
    if ((Field $x "client") -ne $client) { continue }
    if ((Field $x "status") -ne "done") { continue }
    $c = (Field $x "created")
    if ([string]::IsNullOrWhiteSpace($c)) { continue }
    if ($c.Substring(0,[Math]::Min(10,$c.Length)) -gt $created.Substring(0,[Math]::Min(10,$created.Length))) { $n++ }
  }
  return $n
}

$entregue = @()
$superada = @()
$abandonada = @()
$parada = @()
$viva = @()
$semData = @()
$overlapMap = @{}

foreach ($t in $tasks) {
  $status = Field $t "status"
  if ($openStatuses -notcontains $status) { continue }
  $cli = Field $t "client"
  if (-not [string]::IsNullOrWhiteSpace($Client) -and $cli -ne $Client) { continue }
  $proj = Field $t "project"
  $key = $cli + "::" + $proj
  if (-not $overlapMap.ContainsKey($key)) { $overlapMap[$key] = New-Object System.Collections.Generic.List[string] }
  $overlapMap[$key].Add((Field $t "id") + " | " + (Field $t "title"))

  $created = Field $t "created"
  $updated = Field $t "updated"
  $lastMove = $null
  foreach ($cand in @($created, $updated)) {
    if ($cand -eq "") { continue }
    try {
      $d = [datetime]::Parse($cand)
      if ($null -eq $lastMove -or $d -gt $lastMove) { $lastMove = $d }
    } catch {}
  }
  if ($null -eq $lastMove) { $semData += (Field $t "id"); continue }
  $age = [math]::Floor(($nowDate - $lastMove).TotalDays)

  $artifact = Field $t "artifact"
  $hasArtifact = Test-ArtifactExists -ArtifactPath $artifact -StudioRoot $studioRoot

  $row = [PSCustomObject]@{ id=(Field $t "id"); title=(Field $t "title"); client=$cli; project=$proj; age=$age; artifact=$artifact; hasArtifact=$hasArtifact }

  if ($hasArtifact) { $entregue += $row; continue }
  if ($age -gt $MaxAge -and -not (((Field $t "sweep_protect") -eq "True") -or ((Field $t "sweep_protect") -eq "true") -or ($protectIds -contains (Field $t "id")))) { $abandonada += $row; continue }
  # TASK-510: a protecao mora NA TASK (campo sweep_protect), nao so no parametro - decisao do
  # Operator sobre uma Task especifica nao pode depender de alguem lembrar da flag na proxima vez.
  $protegida = ($protectIds -contains $row.id) -or ((Field $t "sweep_protect") -eq "True") -or ((Field $t "sweep_protect") -eq "true")
  if ($SupersededMin -gt 0 -and -not $protegida) {
    $doneAfter = Get-DoneAfter $tasks $cli (Field $t "created")
    if ($doneAfter -ge (2 * $SupersededMin) -or ($age -ge 21 -and $doneAfter -ge $SupersededMin)) {
      $row | Add-Member -NotePropertyName doneAfter -NotePropertyValue $doneAfter -Force
      $superada += $row; continue
    }
  }
  if ($age -ge 21) { $parada += $row; continue }
  $viva += $row
}
Write-Host ("=== task-sweep.ps1 - varredura de Tasks abertas (ref " + $nowDate.ToString("yyyy-MM-dd") + ", MaxAge=" + $MaxAge + "d) ===")
Write-Host ("state: " + $StateFile)
Write-Host ("modo:  " + $(if ($Apply) { "APLICAR" } else { "DRY-RUN (nada sera gravado)" }))
Write-Host ""
Write-Host ("ENTREGUE (artifact em disco -> fecha done):   " + $entregue.Count)
foreach ($r in $entregue) { Write-Host ("  - " + $r.id + " [" + $r.client + "/" + $r.project + "] " + $r.title + " :: " + $r.artifact) }
Write-Host ""
Write-Host ("SUPERADA POR PROGRESSO (o Client fechou Tasks depois -> retired): " + $superada.Count)
foreach ($r in $superada) { Write-Host ("  - " + $r.id + " [" + $r.age + "d, " + $r.doneAfter + " fechadas depois] [" + $r.client + "/" + $r.project + "] " + $r.title) }
Write-Host ""
Write-Host ("ABANDONADA (sem artifact, parada acima de " + $MaxAge + "d -> retired): " + $abandonada.Count)
foreach ($r in $abandonada) { Write-Host ("  - " + $r.id + " [" + $r.age + "d] [" + $r.client + "/" + $r.project + "] " + $r.title) }
Write-Host ""
Write-Host ("PARADA (21 a " + $MaxAge + "d, so aviso, nao toca): " + $parada.Count)
foreach ($r in $parada) { Write-Host ("  - " + $r.id + " [" + $r.age + "d] [" + $r.client + "/" + $r.project + "] " + $r.title) }
Write-Host ""
Write-Host ("VIVA (menos de 21d, nao toca): " + $viva.Count)
if ($semData.Count -gt 0) { Write-Host ("SEM DATA (nao medivel): " + ($semData -join ", ")) }

Write-Host ""
Write-Host "=== AVISO DE SOBREPOSICAO (client+project com 3 ou mais Tasks abertas) ==="
$overlapAny = $false
foreach ($k in ($overlapMap.Keys | Sort-Object)) {
  if ($overlapMap[$k].Count -ge 3) {
    $overlapAny = $true
    Write-Host ("- " + $k + " (" + $overlapMap[$k].Count + " abertas):")
    foreach ($line in $overlapMap[$k]) { Write-Host ("    " + $line) }
  }
}
if (-not $overlapAny) { Write-Host "Nenhuma sobreposicao (nenhum client+project com 3 ou mais Tasks abertas)." }

Write-Host ""
Write-Host "=== Por Client ==="
$byClient = @{}
foreach ($r in @($entregue + $abandonada + $superada + $parada + $viva)) {
  if (-not $byClient.ContainsKey($r.client)) { $byClient[$r.client] = 0 }
  $byClient[$r.client]++
}
foreach ($k in ($byClient.Keys | Sort-Object)) { Write-Host ("- " + $k + ": " + $byClient[$k]) }
if (-not $Apply) {
  if ($retireIds.Count -gt 0 -or $closeIds.Count -gt 0) {
    Write-Host ""
    Write-Host "[AVISO] -Retire/-Close informados mas -Apply nao foi passado: nada sera gravado (DRY-RUN)."
  }
  Write-Host ""
  Write-Host "[DRY-RUN] nada foi gravado. Rode com -Apply para executar as acoes acima."
  exit 0
}

$closedCount = 0
$retiredCount = 0
$falhas = @()

$toClose = @{}
foreach ($r in $entregue) { $toClose[$r.id] = $true }
foreach ($id in $closeIds) { $toClose[$id] = $true }

if ($toClose.Count -gt 0) {
  for ($i = 0; $i -lt $tasks.Count; $i++) {
    $tid = Field $tasks[$i] "id"
    if ($toClose.ContainsKey($tid)) {
      $tasks[$i].status = "done"
      foreach ($propName in @("gate_verdict","sweep_reason","updated")) {
        if (-not ($tasks[$i].PSObject.Properties.Name -contains $propName)) { $tasks[$i] | Add-Member -NotePropertyName $propName -NotePropertyValue $null -Force }
      }
      $tasks[$i].gate_verdict = $gateText
      $tasks[$i].sweep_reason = "task-sweep.ps1: artifact medido em disco em " + $hoje
      $tasks[$i].updated = $nowDate.ToString("yyyy-MM-ddTHH:mm:ssZ")
      $closedCount++
    }
  }
  $json.tasks = @($tasks)
  $json.updated = $nowDate.ToString("yyyy-MM-dd")
  $out = $json | ConvertTo-Json -Depth 32
  [System.IO.File]::WriteAllText($StateFile, $out, $utf8)
}

$toRetire = @{}
foreach ($r in $superada) { $toRetire[$r.id] = "o Client fechou " + $r.doneAfter + " Tasks depois desta sem que ela fosse retomada (varredura " + $hoje + ")" }
foreach ($r in $abandonada) { $toRetire[$r.id] = "sem movimento por " + $r.age + " dias, sem entrega registrada (varredura " + $hoje + ")" }
foreach ($id in $retireIds) { $toRetire[$id] = "superada por decisao do Operator na varredura" }

foreach ($id in $toRetire.Keys) {
  $t = $tasks | Where-Object { (Field $_ "id") -eq $id } | Select-Object -First 1
  if ($null -eq $t) { Write-Host ("[AVISO] " + $id + " nao encontrada em tasks, pulando -Retire."); continue }
  $specialist = Field $t "specialist"
  if ([string]::IsNullOrWhiteSpace($specialist)) { $specialist = "alia" }
  $taskClient = Field $t "client"
  # TASK-510: a varredura E ordem do Operator (registrada na Task que a autoriza), entao SEMPRE
  # passa -OperatorOrder. Antes so passava quando o specialist era "alia", e 4 Tasks de squad
  # falharam em virar retired sem mensagem util - medido em 09/09/2026, consertado aqui.
  $opOrderArgs = @("-OperatorOrder")
  # TASK-510: sem client, register-task.ps1 aborta por parametro obrigatorio - e o splatting
  # engolia o erro, contando como retirada o que nunca foi gravado. Barra antes de chamar.
  if ([string]::IsNullOrWhiteSpace($taskClient)) {
    Write-Host ("[AVISO] " + $id + " sem campo client no ledger - nao da para retirar, pulando.")
    $falhas += $id
    continue
  }
  & powershell -ExecutionPolicy Bypass -File $registerScript -Id $id -Client $taskClient -Status "retired" -Specialist $specialist -StateFile $StateFile @opOrderArgs | Out-Null
  if ($LASTEXITCODE -ne 0) { Write-Host ("[AVISO] register-task.ps1 falhou ao retirar " + $id + " (exit " + $LASTEXITCODE + "), pulando."); $falhas += $id; continue }
  $refreshed = [System.IO.File]::ReadAllText($StateFile) | ConvertFrom-Json
  $refreshedTasks = @($refreshed.tasks)
  for ($i = 0; $i -lt $refreshedTasks.Count; $i++) {
    if ((Field $refreshedTasks[$i] "id") -eq $id) {
      if (-not ($refreshedTasks[$i].PSObject.Properties.Name -contains "sweep_reason")) { $refreshedTasks[$i] | Add-Member -NotePropertyName sweep_reason -NotePropertyValue $null -Force }
      $refreshedTasks[$i].sweep_reason = $toRetire[$id]
      $refreshed.tasks = @($refreshedTasks)
      $out2 = $refreshed | ConvertTo-Json -Depth 32
      [System.IO.File]::WriteAllText($StateFile, $out2, $utf8)
      break
    }
  }
  # TASK-510: PROVA, nao promessa. Rele o ledger e confere que o status virou retired de verdade
  # antes de contar. O resumo desta varredura reporta o que foi CONFERIDO, nunca o que foi tentado.
  $conf = [System.IO.File]::ReadAllText($StateFile) | ConvertFrom-Json
  $confT = @($conf.tasks) | Where-Object { (Field $_ "id") -eq $id } | Select-Object -First 1
  if ($null -ne $confT -and (Field $confT "status") -eq "retired") {
    $retiredCount++
  } else {
    Write-Host ("[AVISO] " + $id + ": status em disco nao virou retired - nao conto como retirada.")
    $falhas += $id
  }
}

Write-Host ""
Write-Host ("[OK] fechadas done: " + $closedCount + " | retiradas: " + $retiredCount + " (conferido em disco)")
if ($falhas.Count -gt 0) {
  Write-Host ("[FALHA] " + $falhas.Count + " Task(s) NAO mudaram: " + ($falhas -join ", "))
  exit 1
}
exit 0
