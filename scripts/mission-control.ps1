<#
  mission-control.ps1 - Gera o Mission Control: a vista humana do ledger de Tasks.
  Le o state.json (Cliente > Projeto > Tarefa) e gera mission-control.html - um painel
  ESTATICO e auto-contido (zero rede, zero LLM, abre por duplo clique) que conta a
  historia da operacao: quem pediu o que, o que foi produzido, DE ONDE se partiu
  (base_artifact - a linhagem), qual sessao executou e qual foi o veredito do Gate.

  E a materializacao visual da LEI de rastreabilidade (engine/orchestration.md):
  se este painel nao conta a historia da operacao, o registro esta falhando.

  ESTADO DO CLIENT (OPP-77): o painel respeita o estado declarado no registro. Client pontual
  (ideia tocada uma vez) e arquivado (encerrado) NAO entram na fila de "paradas / prato caindo" -
  o dia a dia cobra so quem esta ativo -, mas as Tasks deles continuam listadas e rastreaveis, com
  o estado marcado ao lado do nome. Client sem estado declarado = ativo (compatibilidade).

  Uso:  powershell -ExecutionPolicy Bypass -File scripts/mission-control.ps1
        -StateFile <caminho>  (default: state.json na raiz da instancia)
        -OutFile <caminho>    (default: mission-control.html ao lado do state.json)
  Escrita .NET UTF-8 sem BOM. Sem acentos, sem emojis. exit 0.
#>
param(
  [string]$StateFile = "",
  [string]$OutFile = "",
  [int]$StaleDays = 7
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "_studio.ps1")   # Get-ClientStates: o estado do Client (OPP-77)
if ([string]::IsNullOrWhiteSpace($StateFile)) { $StateFile = Join-Path $root "state.json" }
if (-not (Test-Path -LiteralPath $StateFile)) { Write-Host ("[ERRO] state.json nao encontrado: " + $StateFile); exit 1 }
if ([string]::IsNullOrWhiteSpace($OutFile)) { $OutFile = Join-Path (Split-Path -Parent $StateFile) "mission-control.html" }
$utf8 = New-Object System.Text.UTF8Encoding($false)

$st = [System.IO.File]::ReadAllText($StateFile) | ConvertFrom-Json
$tasks = @(); if ($st.tasks) { $tasks = @($st.tasks) }
$studioName = if ($st.studio) { "$($st.studio)" } else { "Alia Flow" }
$ver = ""; $vf = Join-Path $root "VERSION"; if (Test-Path $vf) { $ver = ([System.IO.File]::ReadAllText($vf)).Trim() }
$stamp = (Get-Date).ToString("yyyy-MM-dd HH:mm")

function Esc([string]$s) {
  if ($null -eq $s) { return "" }
  return $s.Replace('&','&amp;').Replace('<','&lt;').Replace('>','&gt;').Replace('"','&quot;')
}
function Field($t, $name) {
  $v = $null; try { $v = $t.PSObject.Properties[$name].Value } catch { }
  if ($null -eq $v) { return "" } else { return "$v" }
}

$done = @($tasks | Where-Object { (Field $_ 'status') -eq 'done' }).Count
$open = $tasks.Count - $done
$noLineage = @($tasks | Where-Object { (Field $_ 'base_artifact') -eq '' -and (Field $_ 'artifact') -ne '' }).Count
$noProject = @($tasks | Where-Object { (Field $_ 'project') -eq '' }).Count

# Os olhos da Alia no que EMPACOU (OPP-70): Task nao-done, com data, parada ha mais de StaleDays.
# Mesma regra do scripts/stale-tasks.ps1 (a fila de cobranca do Owner). Task sem 'created' nao mede.
$nowDate = (Get-Date)
$clientStates = Get-ClientStates $StateFile
$staleList = @()
$foraCobranca = 0
foreach ($t in $tasks) {
  if ((Field $t 'status') -eq 'done') { continue }
  $cr = Field $t 'created'
  if ($cr -eq '') { continue }
  $age = ($nowDate - [datetime]::Parse($cr)).Days
  if ($age -gt $StaleDays) {
    # OPP-77: so o Client ATIVO entra na fila de cobranca. Pontual/arquivado conta a parte.
    if ((Get-ClientStateOf $clientStates (Field $t 'client')) -ne 'ativo') { $foraCobranca++; continue }
    $staleList += [PSCustomObject]@{ t=$t; age=$age }
  }
}
$stale = $staleList.Count

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('<!doctype html><html lang="pt-BR"><head><meta charset="utf-8">')
[void]$sb.AppendLine('<meta name="viewport" content="width=device-width, initial-scale=1.0">')
[void]$sb.AppendLine('<title>Mission Control - ' + (Esc $studioName) + '</title>')
[void]$sb.AppendLine('<style>')
[void]$sb.AppendLine(':root{--rose:#f5569b;--g20:#d2d2d2;--g30:#9a9a9a;--g40:#6e6e6e;--g60:#2a2a2a;--g70:#1c1c1c;--g90:#0a0a0a}')
[void]$sb.AppendLine('*{box-sizing:border-box;margin:0}body{background:#000;color:#fff;font-family:Consolas,"JetBrains Mono",monospace;padding:28px 4vw 80px}')
[void]$sb.AppendLine('.hd{display:flex;flex-wrap:wrap;align-items:baseline;gap:14px;border-bottom:1px solid var(--g60);padding-bottom:18px;margin-bottom:8px}')
[void]$sb.AppendLine('.hd h1{font-size:22px;letter-spacing:.04em;text-transform:uppercase}.hd h1 b{color:var(--rose)}')
[void]$sb.AppendLine('.hd .m{font-size:11px;color:var(--g40);letter-spacing:.08em}')
[void]$sb.AppendLine('.kpis{display:flex;flex-wrap:wrap;gap:12px;margin:18px 0 26px}')
[void]$sb.AppendLine('.kpi{border:1px solid var(--g60);background:var(--g90);border-radius:12px;padding:12px 18px;min-width:130px}')
[void]$sb.AppendLine('.kpi b{display:block;font-size:26px;color:var(--rose)}.kpi span{font-size:10px;letter-spacing:.12em;color:var(--g30);text-transform:uppercase}')
[void]$sb.AppendLine('.kpi--warn b{color:#e0b13f}.kpi--stale b{color:var(--rose)}')
[void]$sb.AppendLine('.alert{border:1px solid var(--rose);border-radius:12px;padding:14px 18px;margin:0 0 26px}')
[void]$sb.AppendLine('.alert__h{color:var(--rose);font-size:12px;letter-spacing:.12em;text-transform:uppercase;margin-bottom:10px}')
[void]$sb.AppendLine('.alert__row{font-size:12px;color:var(--g20);line-height:1.9;border-top:1px solid var(--g70);padding-top:6px}')
[void]$sb.AppendLine('.alert__row:first-of-type{border-top:0}.alert__age{color:var(--rose);font-weight:700}.alert__c{color:var(--g40)}')
[void]$sb.AppendLine('.cli{margin:26px 0 8px;font-size:15px;letter-spacing:.14em;text-transform:uppercase;color:#fff}.cli::before{content:"// ";color:var(--rose)}')
[void]$sb.AppendLine('.proj{margin:12px 0 6px 6px;font-size:11px;letter-spacing:.1em;color:var(--g30);text-transform:uppercase}')
[void]$sb.AppendLine('.tk{border:1px solid var(--g70);border-left:3px solid var(--g60);background:var(--g90);border-radius:10px;padding:12px 16px;margin:8px 0 8px 6px}')
[void]$sb.AppendLine('.tk--done{border-left-color:var(--rose)}.tk--open{border-left-color:#e0b13f}')
[void]$sb.AppendLine('.tk__top{display:flex;flex-wrap:wrap;gap:10px;align-items:baseline}')
[void]$sb.AppendLine('.tk__id{color:var(--rose);font-size:11px;letter-spacing:.08em}.tk__st{font-size:9px;letter-spacing:.14em;text-transform:uppercase;border:1px solid var(--g60);border-radius:6px;padding:2px 8px;color:var(--g20)}')
[void]$sb.AppendLine('.tk__t{font-size:13px;color:var(--g20);line-height:1.5;margin:6px 0}')
[void]$sb.AppendLine('.tk__meta{font-size:10.5px;color:var(--g40);line-height:1.7}.tk__meta b{color:var(--g30);font-weight:400}')
[void]$sb.AppendLine('.tk__meta .miss{color:#e0b13f}')
[void]$sb.AppendLine('.ft{margin-top:44px;border-top:1px solid var(--g60);padding-top:14px;font-size:10px;letter-spacing:.1em;color:var(--g40)}')
[void]$sb.AppendLine('</style></head><body>')
[void]$sb.AppendLine('<div class="hd"><h1>Mission <b>Control</b></h1><span class="m">' + (Esc $studioName) + ' - motor v' + (Esc $ver) + ' - gerado ' + $stamp + ' - fonte: state.json</span></div>')
[void]$sb.AppendLine('<div class="kpis">')
[void]$sb.AppendLine('<div class="kpi"><b>' + $tasks.Count + '</b><span>tarefas registradas</span></div>')
[void]$sb.AppendLine('<div class="kpi"><b>' + $done + '</b><span>concluidas</span></div>')
[void]$sb.AppendLine('<div class="kpi' + $(if ($open -gt 0) { ' kpi--warn' } else { '' }) + '"><b>' + $open + '</b><span>abertas / em revisao</span></div>')
[void]$sb.AppendLine('<div class="kpi' + $(if (($noLineage + $noProject) -gt 0) { ' kpi--warn' } else { '' }) + '"><b>' + ($noLineage + $noProject) + '</b><span>furos de rastreio</span></div>')
[void]$sb.AppendLine('<div class="kpi' + $(if ($stale -gt 0) { ' kpi--stale' } else { '' }) + '"><b>' + $stale + '</b><span>paradas / em risco</span></div>')
[void]$sb.AppendLine('</div>')

# Os olhos da Alia: o que empacou vem PRIMEIRO, em destaque - e a fila de cobranca do Owner.
if ($stale -gt 0) {
  [void]$sb.AppendLine('<div class="alert"><div class="alert__h">// PARADAS - PRATO CAINDO (parado > ' + $StaleDays + ' dias)</div>')
  foreach ($s in ($staleList | Sort-Object -Property age -Descending)) {
    $t = $s.t
    [void]$sb.AppendLine('<div class="alert__row"><span class="alert__age">' + $s.age + 'd</span> <b>' + (Esc (Field $t 'id')) + '</b> ' + (Esc (Field $t 'title')) + ' <span class="alert__c">' + (Esc (Field $t 'client')) + ' / ' + (Esc (Field $t 'project')) + '</span></div>')
  }
  [void]$sb.AppendLine('</div>')
}

if ($tasks.Count -eq 0) {
  [void]$sb.AppendLine('<p style="color:var(--g30)">Nenhuma tarefa registrada ainda. A primeira demanda vira TASK-001.</p>')
} else {
  $byClient = $tasks | Group-Object { Field $_ 'client' }
  foreach ($cg in $byClient) {
    # OPP-77: o estado do Client aparece ao lado do nome - pontual/arquivado e informacao, nunca alarme.
    $cSt = Get-ClientStateOf $clientStates $cg.Name
    $cTag = ''
    if ($cSt -ne 'ativo') { $cTag = ' <span style="font-size:9px;letter-spacing:.14em;text-transform:uppercase;border:1px solid var(--g60);border-radius:6px;padding:2px 8px;color:var(--g30)">' + (Esc $cSt) + '</span>' }
    [void]$sb.AppendLine('<div class="cli">' + (Esc $cg.Name) + ' <span style="color:var(--g40);font-size:10px">(' + $cg.Count + ')</span>' + $cTag + '</div>')
    $byProj = $cg.Group | Group-Object { $p = Field $_ 'project'; if ($p -eq '') { '(sem projeto - furo de rastreio)' } else { $p } }
    foreach ($pg in $byProj) {
      [void]$sb.AppendLine('<div class="proj">' + (Esc $pg.Name) + '</div>')
      foreach ($t in ($pg.Group | Sort-Object { Field $_ 'id' })) {
        $stt = Field $t 'status'
        $cls = if ($stt -eq 'done') { 'tk--done' } else { 'tk--open' }
        [void]$sb.AppendLine('<div class="tk ' + $cls + '">')
        [void]$sb.AppendLine('<div class="tk__top"><span class="tk__id">' + (Esc (Field $t 'id')) + '</span><span class="tk__st">' + (Esc $stt) + '</span><span class="tk__st">' + (Esc (Field $t 'specialist')) + '</span><span style="font-size:10px;color:var(--g40)">' + (Esc (Field $t 'created')) + '</span></div>')
        [void]$sb.AppendLine('<div class="tk__t">' + (Esc (Field $t 'title')) + '</div>')
        $art = Field $t 'artifact'; $base = Field $t 'base_artifact'; $ses = Field $t 'session'; $gate = Field $t 'gate_verdict'
        $meta = '<b>entregou:</b> ' + $(if ($art -eq '') { '<span class="miss">nao registrado</span>' } else { Esc $art })
        $meta += ' &nbsp;|&nbsp; <b>partiu de:</b> ' + $(if ($base -eq '') { '<span class="miss">nao registrado</span>' } else { Esc $base })
        $meta += '<br><b>gate:</b> ' + $(if ($gate -eq '') { '<span class="miss">sem veredito</span>' } else { Esc $gate })
        $meta += ' &nbsp;|&nbsp; <b>sessao:</b> ' + $(if ($ses -eq '') { '<span class="miss">nao registrada</span>' } else { Esc $ses })
        [void]$sb.AppendLine('<div class="tk__meta">' + $meta + '</div>')
        [void]$sb.AppendLine('</div>')
      }
    }
  }
}
[void]$sb.AppendLine('<div class="ft">// SEM REGISTRO = NAO ACONTECEU &middot; SEM LINHAGEM = SEM CONTINUIDADE &middot; engine/orchestration.md (LEI de rastreabilidade)</div>')
[void]$sb.AppendLine('</body></html>')

[System.IO.File]::WriteAllText($OutFile, $sb.ToString(), $utf8)
Write-Host ("=== Mission Control gerado ===")
Write-Host ("tarefas: " + $tasks.Count + " (" + $done + " done, " + $open + " abertas) | furos de rastreio: " + ($noLineage + $noProject) + " | paradas (> " + $StaleDays + "d): " + $stale + " | fora da cobranca (Client pontual/arquivado): " + $foraCobranca)
Write-Host ("saida:   " + $OutFile)
exit 0
