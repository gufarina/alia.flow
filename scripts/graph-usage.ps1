<#
  graph-usage.ps1 - O CONTADOR da lei "grafo antes de varredura".

  Le o ledger append-only gravado por scripts/graph-usage-sensor.ps1 (hook de PreToolUse) e
  responde a UNICA pergunta que importa: em cada sessao, naquele codebase, o mapa de conhecimento
  foi lido ANTES da primeira varredura?

  Motivo (research/graph-engineering/03-auditoria-interna.md, secao 2.3): a lei do grafo esta
  escrita em 3 lugares do motor e registrada como "COBERTA" no law-ledger, mas nada nunca mediu a
  aderencia. O estudo CodeCompass mostrou o tamanho do buraco: quando o agente consulta o grafo o
  acerto e 99,5%, mas sem cobranca forte ele so consulta em 42% dos casos. Sem contador, a lei e fe.

  UNIDADE DE MEDIDA: o par (sessao, escopo). Uma sessao que varre dois clientes conta duas vezes,
  porque a lei e por codebase - ler o grafo de um Client nao autoriza varrer OUTRO as cegas.
    - ADOCAO  = par que teve pelo menos uma leitura de mapa ANTES da primeira varredura.
    - FURO    = par que varreu sem nenhuma leitura de mapa antes.
    - Par que so leu o mapa e nunca varreu NAO entra na conta (nao houve risco a medir).

  CONSERTO 11/08/2026 - A JANELA HONESTA (antes deste conserto, a metrica misturava toda a
  historia do ledger num numero so - "10,7% em 56 pares" - contando sessoes de ANTES do gate
  (scripts/graph-usage-sensor.ps1) sequer recusar varredura. Julgar a lei por um periodo em que
  ela nao tinha como pegar ninguem e injusto com a propria lei (e disfarca se o hook desligar de
  novo). A partir de agora a metrica PRINCIPAL e a da JANELA DA TRAVA: so pares cuja primeira
  varredura aconteceu DEPOIS do gate comecar a recusar.

  DE ONDE VEM $GateLigadoUtc (a data do corte, nao inventada):
    Confirmado por DIFF DE DISCO entre dois backups automaticos do updater (nunca apagados,
    nunca editados a mao):
      - _backups/RESGATE-2026-08-09-pre-1.0/scripts/graph-usage-sensor.ps1 (168 linhas) - SO
        sensor, sem nenhuma logica de recusa (grep por "denyReason"/"permissionDecision" = 0).
      - _backups/pre-update-1.48.0-para-1.50.0-20260810-154713/scripts/graph-usage-sensor.ps1
        (389 linhas, timestamp do backup 2026-08-10T15:47:13) - JA TEM a logica de recusa inteira
        (denyReason, permissionDecision=deny, escape na 3a tentativa).
    Ou seja: o gate nasceu em algum momento ENTRE 09/08 e 10/08 15:47 - o CHANGELOG.md nao tem uma
    entrada dedicada a esse exato commit (o texto de 1.44.0 que criou o sensor e explicito: "Nao
    bloqueia, nao julga" - so a partir de aqui e que virou 2 funcoes). Corte adotado, conservador
    de proposito (nao favorece a nota): 2026-08-10T00:00:00Z, o INICIO do dia em que o backup
    confirma o gate ja ligado - isto inclui na janela algumas horas da manha de 10/08 em que o gate
    talvez ainda nao estivesse ativo, o que so PODE fazer a adocao medida parecer PIOR do que a
    realidade, nunca melhor. Se um dia surgir um fato mais preciso (linha exata do CHANGELOG,
    hash do commit), troque so a constante abaixo.

  A saida agora mostra OS DOIS numeros, sempre, sem esconder nenhum: a adocao NA JANELA DA TRAVA
  (o veredito, o que o smoke reprova) e a adocao NO HISTORICO COMPLETO (todo o ledger, nunca
  apagado, so para nao perder contexto de onde a casa partiu).

  Parametros: -Days N (LEGADO - nao filtra mais o veredito, so limita quanto o "historico
  completo" mostra na tendencia por dia; default 0 = sem limite, todo o ledger), -Path (ledger
  alternativo), -Top N (furos listados).

  VEREDITO (o criterio que o smoke deve adotar - ver o fim da saida, agora sobre a JANELA):
    - ledger ausente                        -> [FAIL]  sensor desligado (a medida nao existe)
    - amostra da janela >= 5 pares e adocao < 70% -> [AVISO] a lei nao esta pegando
    - resto                                 -> [PASS]
  A rota de shell do Windows nem sempre propaga o exit code (medido na auditoria com o
  graph-check.ps1), entao quem integrar deve casar o TEXTO "[FAIL]" / "[AVISO]", nao o $LASTEXITCODE.

  Sem acentos, sem emojis. So leitura: este script nunca escreve nada.
#>
param(
  [int]$Days = 0,
  [string]$Path = "",
  [int]$Top = 5
)

$ErrorActionPreference = "Stop"

# Cercas do veredito (unico lugar onde os numeros moram).
$ALVO_PCT    = 70
$MIN_AMOSTRA = 5

# A data do corte - ver o bloco "DE ONDE VEM" no cabecalho. So troque isto se surgir um fato
# mais preciso que o diff de backup usado para derivar 2026-08-10.
$GateLigadoUtc = [datetime]::new(2026, 8, 10, 0, 0, 0, [System.DateTimeKind]::Utc)

$root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($Path)) {
  $Path = Join-Path (Join-Path $root "studio") "graph-usage-log.jsonl"
}

Write-Host "=== Graph Usage - o mapa foi lido antes da varredura? ==="
Write-Host ("ledger: " + $Path)
Write-Host ("janela da trava: desde " + $GateLigadoUtc.ToString("yyyy-MM-dd") + " (data em que o gate comecou a recusar varredura, ver cabecalho do script)")
Write-Host ""

if (-not (Test-Path -LiteralPath $Path)) {
  Write-Host ("[FAIL] ledger ausente - o sensor esta DESLIGADO, a aderencia a lei do grafo nao esta sendo medida.")
  Write-Host ("       esperado em: " + $Path)
  Write-Host ("       conserto: registrar scripts/graph-usage-sensor.ps1 como hook PreToolUse em .claude/settings.json.")
  Write-Host ""
  Write-Host "VEREDITO: [FAIL] sensor desligado (ledger inexistente)."
  exit 1
}

$inv    = [System.Globalization.CultureInfo]::InvariantCulture
$styles = [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal

$allEvents = New-Object System.Collections.Generic.List[object]
$totalLines = 0
foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
  if ([string]::IsNullOrWhiteSpace($line)) { continue }
  $totalLines++
  $o = $null
  try { $o = $line | ConvertFrom-Json } catch { continue }
  if ($null -eq $o) { continue }
  $ts = $null
  try { $ts = [datetime]::ParseExact([string]$o.ts, "yyyy-MM-ddTHH:mm:ss.fffZ", $inv, $styles) } catch { continue }
  $allEvents.Add([pscustomobject]@{
    ts      = $ts
    session = [string]$o.session
    tool    = [string]$o.tool
    kind    = [string]$o.kind
    scope   = [string]$o.scope
  })
}

# Historico completo NUNCA se apaga - so encolhe se -Days > 0 for passado explicitamente (legado).
$histEvents = $allEvents
if ($Days -gt 0) {
  $cutoffLegado = (Get-Date).ToUniversalTime().AddDays(-$Days)
  $histEvents = @($allEvents | Where-Object { $_.ts -ge $cutoffLegado })
}

# A janela da trava - o corte que importa para o veredito.
$janelaEvents = @($allEvents | Where-Object { $_.ts -ge $GateLigadoUtc })

function Measure-Adocao([object[]]$events) {
  $pairs = @{}
  foreach ($e in $events) {
    $key = $e.session + "|" + $e.scope
    if (-not $pairs.ContainsKey($key)) {
      $pairs[$key] = [pscustomobject]@{
        session   = $e.session
        scope     = $e.scope
        firstMap  = $null
        firstScan = $null
        scanTool  = ""
      }
    }
    $p = $pairs[$key]
    if ($e.kind -eq 'map'  -and ($null -eq $p.firstMap  -or $e.ts -lt $p.firstMap))  { $p.firstMap  = $e.ts }
    if ($e.kind -eq 'scan' -and ($null -eq $p.firstScan -or $e.ts -lt $p.firstScan)) { $p.firstScan = $e.ts; $p.scanTool = $e.tool }
  }
  $comVarredura = @($pairs.Values | Where-Object { $null -ne $_.firstScan })
  $adotaram = @($comVarredura | Where-Object { $null -ne $_.firstMap -and $_.firstMap -le $_.firstScan })
  $furos    = @($comVarredura | Where-Object { $null -eq $_.firstMap -or $_.firstMap -gt $_.firstScan })
  $soMapa   = @($pairs.Values | Where-Object { $null -eq $_.firstScan }).Count
  $total = $comVarredura.Count
  $pct = 0
  if ($total -gt 0) { $pct = [math]::Round((100.0 * $adotaram.Count / $total), 1) }
  return [pscustomobject]@{
    pares         = $pairs
    comVarredura  = $comVarredura
    adotaram      = $adotaram
    furos         = $furos
    soMapa        = $soMapa
    total         = $total
    pct           = $pct
  }
}

$mHist   = Measure-Adocao $histEvents
$mJanela = Measure-Adocao $janelaEvents

$nMap  = @($allEvents | Where-Object { $_.kind -eq 'map' }).Count
$nScan = @($allEvents | Where-Object { $_.kind -eq 'scan' }).Count
Write-Host ("[OK] eventos no ledger: " + $totalLines + " | total lido: " + $allEvents.Count +
  " (mapa: " + $nMap + " | varredura: " + $nScan + ")")
Write-Host ("[OK] pares (sessao, escopo) que varreram - janela da trava: " + $mJanela.total +
  " (so leram o mapa e nao varreram: " + $mJanela.soMapa + ", fora da conta) | historico completo: " +
  $mHist.total + " (so leram o mapa e nao varreram: " + $mHist.soMapa + ", fora da conta)")
Write-Host ""

Write-Host ("ADOCAO (janela da trava, desde " + $GateLigadoUtc.ToString("yyyy-MM-dd") + "): " +
  $mJanela.adotaram.Count + "/" + $mJanela.total + " = " +
  ([string]::Format($inv, "{0:0.0}", $mJanela.pct)) + "%   (alvo >= " + $ALVO_PCT + "%)")
Write-Host ("ADOCAO (historico completo, desde o inicio do ledger): " +
  $mHist.adotaram.Count + "/" + $mHist.total + " = " +
  ([string]::Format($inv, "{0:0.0}", $mHist.pct)) + "%")
Write-Host ("FUROS (janela da trava): " + $mJanela.furos.Count + " par(es) varreram sem consultar o mapa antes.")
Write-Host ("FUROS (historico completo): " + $mHist.furos.Count + " par(es) varreram sem consultar o mapa antes.")
Write-Host ""

if ($mHist.total -gt 0) {
  Write-Host "Tendencia por dia (historico completo, dia da PRIMEIRA varredura de cada par):"
  $porDia = $mHist.comVarredura | Group-Object { $_.firstScan.ToString("yyyy-MM-dd") } | Sort-Object Name
  foreach ($g in $porDia) {
    $ok = @($g.Group | Where-Object { $null -ne $_.firstMap -and $_.firstMap -le $_.firstScan }).Count
    $p2 = [math]::Round((100.0 * $ok / $g.Count), 0)
    $marca = if ([datetime]::Parse($g.Name, $inv, $styles) -ge $GateLigadoUtc) { "  [na janela da trava]" } else { "" }
    Write-Host ("  " + $g.Name + "   varreram: " + $g.Count + "   com mapa antes: " + $ok +
      "   adocao: " + $p2 + "%" + $marca)
  }
  Write-Host ""
}

if ($mJanela.furos.Count -gt 0) {
  Write-Host ("Ultimos furos na janela da trava (ate " + $Top + "):")
  foreach ($f in @($mJanela.furos | Sort-Object firstScan -Descending | Select-Object -First $Top)) {
    $sid = $f.session
    if ($sid.Length -gt 8) { $sid = $sid.Substring(0, 8) }
    if ([string]::IsNullOrWhiteSpace($sid)) { $sid = "(sem id)" }
    $nota = if ($null -eq $f.firstMap) { "nunca leu o mapa" } else { "leu o mapa DEPOIS de varrer" }
    Write-Host ("  " + $f.firstScan.ToString("yyyy-MM-dd HH:mm") + "  escopo " + $f.scope +
      "  sessao " + $sid + "  1a varredura: " + $f.scanTool + "  (" + $nota + ")")
  }
  Write-Host ""
}

# VEREDITO - a linha que o smoke le. Julgado SOBRE A JANELA DA TRAVA (nao sobre o historico
# completo, que mistura era-sem-lei com era-com-lei). Proibido afrouxar o alvo para passar: se a
# janela reprovar, o veredito reprova com o numero real.
if ($mJanela.total -ge $MIN_AMOSTRA -and $mJanela.pct -lt $ALVO_PCT) {
  Write-Host ("VEREDITO: [AVISO] adocao " + ([string]::Format($inv, "{0:0.0}", $mJanela.pct)) + "% em " +
    $mJanela.total + " par(es) desde " + $GateLigadoUtc.ToString("yyyy-MM-dd") +
    " (quando a trava entrou) - abaixo do alvo de " + $ALVO_PCT +
    "%. historico completo: " + ([string]::Format($inv, "{0:0.0}", $mHist.pct)) + "% em " + $mHist.total +
    " par(es). A lei do grafo nao esta pegando no ponto de decisao.")
  exit 0
}
if ($mJanela.total -lt $MIN_AMOSTRA) {
  Write-Host ("VEREDITO: [PASS] amostra insuficiente na janela da trava para julgar (" + $mJanela.total +
    " de " + $MIN_AMOSTRA + " pares minimos, desde " + $GateLigadoUtc.ToString("yyyy-MM-dd") +
    ") - sensor vivo, medindo. historico completo: " +
    ([string]::Format($inv, "{0:0.0}", $mHist.pct)) + "% em " + $mHist.total + " par(es).")
  exit 0
}
Write-Host ("VEREDITO: [PASS] adocao " + ([string]::Format($inv, "{0:0.0}", $mJanela.pct)) + "% em " +
  $mJanela.total + " par(es) desde " + $GateLigadoUtc.ToString("yyyy-MM-dd") +
  " (quando a trava entrou) - no alvo (>= " + $ALVO_PCT + "%). historico completo: " +
  ([string]::Format($inv, "{0:0.0}", $mHist.pct)) + "% em " + $mHist.total + " par(es).")
exit 0
