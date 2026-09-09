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
 graph-check.ps1), entao quem integrar deve casar o TEXTO "[FAIL]" / "[AVISO]", nao o $LASTEXITCODE. So leitura: este script nunca escreve nada.
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
    match   = [string]$o.match
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

# CONSERTO (TASK-159, MEDIDO antes de mexer - ver relatorio da Task): o denominador antigo contava
# TODO par (sessao, escopo) que varreu, inclusive escopo sem mapa nenhum em disco (fallback
# "studio-farina", Client sem squad como "clients/brax") - ler o mapa ali e IMPOSSIVEL, entao esses
# pares estavam matematicamente condenados a "furo" por um motivo que nao tem nada a ver com o
# gate falhar. Medido em 13/08/2026 contra o ledger real: 23 dos 49 pares da janela da trava
# (47%) eram nao-gateaveis; removendo-os, a adocao sobe de 12.2% pra 15.4% - real, mas nao explica
# o buraco todo (a causa dominante, medida e REPORTADA mas NAO consertada aqui por decisao
# conservadora, esta no relatorio da Task: a metrica de hoje nao da credito a correcao rapida
# depois do 1o bloqueio - o proprio desenho do gate espera 1-2 tentativas antes de ensinar).
# Has-Map espelha EXATAMENTE a mesma logica de gateabilidade de graph-usage-sensor.ps1 (4.2): so
# "clients/<id>" com GRAPH_REPORT.md em disco, ou "external:*" (que so existe quando um mapa JA
# foi achado subindo a arvore - sempre gateavel por construcao).
$hasMapCache = @{}
function Has-Map([string]$Scope) {
  if ($hasMapCache.ContainsKey($Scope)) { return $hasMapCache[$Scope] }
  $result = $false
  if ($Scope -like "external:*") {
    $result = $true
  } elseif ($Scope -like "clients/*") {
    $cand1 = Join-Path $root ($Scope + "/graphify-out/GRAPH_REPORT.md")
    $cand2 = Join-Path $root ($Scope + "/squad/knowledge/graphify-out/GRAPH_REPORT.md")
    $result = (Test-Path -LiteralPath $cand1) -or (Test-Path -LiteralPath $cand2)
  }

  $hasMapCache[$Scope] = $result
  return $result
}
$histEventsGateavel   = @($histEvents   | Where-Object { Has-Map $_.scope })
$janelaEventsGateavel = @($janelaEvents | Where-Object { Has-Map $_.scope })

function Measure-Adocao([object[]]$events) {
  $pairs = @{}
  foreach ($e in $events) {
    $key = $e.session + "|" + $e.scope
    if (-not $pairs.ContainsKey($key)) {
      $pairs[$key] = [pscustomobject]@{
        session   = $e.session
        scope     = $e.scope
        firstMap  = $null
        firstMapMatch = ""
        firstScan = $null
        scanTool  = ""
      }

    }

    $p = $pairs[$key]
    if ($e.kind -eq 'map'  -and ($null -eq $p.firstMap  -or $e.ts -lt $p.firstMap))  { $p.firstMap  = $e.ts; $p.firstMapMatch = $e.match }
    if ($e.kind -eq 'scan' -and ($null -eq $p.firstScan -or $e.ts -lt $p.firstScan)) { $p.firstScan = $e.ts; $p.scanTool = $e.tool }
  }

  $comVarredura = @($pairs.Values | Where-Object { $null -ne $_.firstScan })
  $adotaram = @($comVarredura | Where-Object { $null -ne $_.firstMap -and $_.firstMap -le $_.firstScan })
  $furos    = @($comVarredura | Where-Object { $null -eq $_.firstMap -or $_.firstMap -gt $_.firstScan })
  $soMapa   = @($pairs.Values | Where-Object { $null -eq $_.firstScan }).Count
  $total = $comVarredura.Count
  $pct = 0
  if ($total -gt 0) { $pct = [math]::Round((100.0 * $adotaram.Count / $total), 1) }
  # TASK-169: distingue ADOCAO por INJECAO (o gate entregou o mapa sozinho, match=map-injected)
  # de ADOCAO AUTONOMA (leitura genuina do agente antes de qualquer injecao - Read/graphify query
  # no GRAPH_REPORT.md/graph.json, match != map-injected). A medida continua honesta: nao
  # esconde que a maior parte da adocao agora vem de MAQUINA, nao de habito.
  $injetados = @($adotaram | Where-Object { $_.firstMapMatch -eq 'map-injected' })
  $autonomos = @($adotaram | Where-Object { $_.firstMapMatch -ne 'map-injected' })
  # TASK-213 (item 3, benchmark DeepSeek Harness): o numerador da ADOCAO passa a ser SO os
  # autonomos - injecao automatica (a maquina entregando o mapa sozinha) nao e merito do agente,
  # e MERITO DO GATE. Misturar os dois no mesmo numerador escondia que quase toda "adocao" de hoje
  # vem de maquina, nao de habito - o oposto do que a lei do grafo tenta medir.
  $pctAutonomo = 0
  if ($total -gt 0) { $pctAutonomo = [math]::Round((100.0 * $autonomos.Count / $total), 1) }
  return [pscustomobject]@{
    pares         = $pairs
    comVarredura  = $comVarredura
    adotaram      = $adotaram
    injetados     = $injetados
    autonomos     = $autonomos
    furos         = $furos
    soMapa        = $soMapa
    total         = $total
    pct           = $pct
    pctAutonomo   = $pctAutonomo
  }

}

$mHist   = Measure-Adocao $histEvents
$mJanela = Measure-Adocao $janelaEvents
$mHistG   = Measure-Adocao $histEventsGateavel
$mJanelaG = Measure-Adocao $janelaEventsGateavel

$nMap  = @($allEvents | Where-Object { $_.kind -eq 'map' }).Count
$nScan = @($allEvents | Where-Object { $_.kind -eq 'scan' }).Count
Write-Host ("[OK] eventos no ledger: " + $totalLines + " | total lido: " + $allEvents.Count +
  " (mapa: " + $nMap + " | varredura: " + $nScan + ")")
Write-Host ("[OK] pares (sessao, escopo) que varreram - janela da trava: " + $mJanela.total +
  " (so leram o mapa e nao varreram: " + $mJanela.soMapa + ", fora da conta) | historico completo: " +
  $mHist.total + " (so leram o mapa e nao varreram: " + $mHist.soMapa + ", fora da conta)")
Write-Host ("[OK] dos pares acima, GATEAVEIS DE VERDADE (escopo com mapa em disco - so onde ler o" +
  " mapa era POSSIVEL): " + $mJanelaG.total + " na janela da trava (de " + $mJanela.total +
  " totais) | " + $mHistG.total + " no historico completo (de " + $mHist.total + " totais). O" +
  " resto e escopo sem mapa nenhum (fallback, Client sem squad) - contava como furo garantido" +
  " antes do conserto de 13/08/2026 (TASK-159), por um motivo que nao e culpa do gate.")
Write-Host ""

# TASK-213 (item 3, benchmark DeepSeek Harness): as 3 perguntas que este contador responde sao
# INDEPENDENTES uma da outra - amostra pequena nao vira "PASS" escondido, cobertura nao decide
# adocao, e injecao automatica nao vira merito na adocao. Antes disto um unico VEREDITO aninhava
# as tres (amostra insuficiente virava [PASS] disfarcado; o numerador da adocao somava injetado +
# autonomo, escondendo que quase toda "adocao" vinha de maquina, nao de habito). Cada pergunta
# agora imprime a sua MEDIDA e o seu VEREDITO proprio, nunca dentro do outro.
Write-Host ("AMOSTRA (janela da trava, so gateaveis): " + $mJanelaG.total + "/" + $MIN_AMOSTRA +
  " minimo -> " + $(if ($mJanelaG.total -ge $MIN_AMOSTRA) { "suficiente" } else { "insuficiente" }))
Write-Host ("ADOCAO AUTONOMA: " + $mJanelaG.autonomos.Count + "/" + $mJanelaG.total + " = " +
  ([string]::Format($inv, "{0:0.0}", $mJanelaG.pctAutonomo)) + "%   (numerador SO autonomos - injecao" +
  " automatica do gate NAO conta como merito do agente; alvo >= " + $ALVO_PCT + "%)")
Write-Host ("  DESTES " + $mJanelaG.total + " par(es) gateaveis: injetados pelo gate (TASK-169, match=map-injected): " +
  $mJanelaG.injetados.Count + " | autonomos (leitura genuina, antes de qualquer injecao): " + $mJanelaG.autonomos.Count)
Write-Host ("COBERTURA: " + $mJanelaG.total + "/" + $mJanela.total + " = " +
  $(if ($mJanela.total -gt 0) { [string]::Format($inv, "{0:0.0}", (100.0 * $mJanelaG.total / $mJanela.total)) } else { "0.0" }) +
  "%   (pares em escopo COM mapa em disco vs todos os pares que varreram, janela da trava - o" +
  " resto e escopo sem mapa nenhum, fallback/Client sem squad, fora do alcance do gate)")
Write-Host ("historico completo (referencia, nao decide veredito): ADOCAO AUTONOMA " + $mHistG.autonomos.Count +
  "/" + $mHistG.total + " = " + ([string]::Format($inv, "{0:0.0}", $mHistG.pctAutonomo)) +
  "%   | COBERTURA " + $mHistG.total + "/" + $mHist.total)
Write-Host ("FUROS SO GATEAVEIS (janela da trava): " + $mJanelaG.furos.Count + " par(es) varreram sem consultar o mapa antes, em escopo QUE TINHA mapa pra ler.")
Write-Host ("FUROS (janela da trava): " + $mJanela.furos.Count + " par(es) varreram sem consultar o mapa antes. (todos os pares, gateaveis ou nao - referencia)")
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

if ($mJanelaG.furos.Count -gt 0) {
  Write-Host ("Ultimos furos GATEAVEIS na janela da trava (ate " + $Top + " - so escopo que TINHA mapa pra ler):")
  foreach ($f in @($mJanelaG.furos | Sort-Object firstScan -Descending | Select-Object -First $Top)) {
    $sid = $f.session
    if ($sid.Length -gt 8) { $sid = $sid.Substring(0, 8) }
    if ([string]::IsNullOrWhiteSpace($sid)) { $sid = "(sem id)" }
    $nota = if ($null -eq $f.firstMap) { "nunca leu o mapa" } else { "leu o mapa DEPOIS de varrer" }
    Write-Host ("  " + $f.firstScan.ToString("yyyy-MM-dd HH:mm") + "  escopo " + $f.scope +
      "  sessao " + $sid + "  1a varredura: " + $f.scanTool + "  (" + $nota + ")")
  }

  Write-Host ""

}

# 3 VEREDITOS INDEPENDENTES (TASK-213, item 3) - a linha que o smoke le. Julgados SOBRE A JANELA
# DA TRAVA, SO PARES GATEAVEIS (CONSERTO TASK-159, preservado): escopo sem mapa nenhum fica fora
# (nao pode ser cobrado por algo que nao existe), mas continua contado e mostrado acima. NUNCA
# aninhados: amostra insuficiente NAO vira "adocao PASS" disfarcado (o bug que este item fecha) -
# ela emite [SEM AMOSTRA] e para ali; cobertura e puramente informativa (nunca decide PASS/FAIL).
# TASK-169 (14/08/2026): o gate deixou de so RECUSAR e passou a INJETAR o mapa (God Nodes +
# Community Hubs) via additionalContext no 1o toque de todo par gateavel. Por isso a injecao NUNCA
# conta como adocao autonoma - ela e o gate fazendo o trabalho, nao o agente desenvolvendo habito.

if ($mJanelaG.total -lt $MIN_AMOSTRA) {
  Write-Host ("VEREDITO AMOSTRA: [SEM AMOSTRA] " + $mJanelaG.total + " par(es) gateaveis na janela da trava" +
    " (desde " + $GateLigadoUtc.ToString("yyyy-MM-dd") + "), minimo " + $MIN_AMOSTRA +
    " - sensor vivo, medindo, amostra pequena demais pra julgar.")
} else {
  Write-Host ("VEREDITO AMOSTRA: [SUFICIENTE] " + $mJanelaG.total + " par(es) gateaveis na janela da trava" +
    " (desde " + $GateLigadoUtc.ToString("yyyy-MM-dd") + "), minimo " + $MIN_AMOSTRA + ".")
}

if ($mJanelaG.total -lt $MIN_AMOSTRA) {
  Write-Host ("VEREDITO ADOCAO AUTONOMA: [SEM AMOSTRA] nao julgavel com amostra insuficiente (ver" +
    " VEREDITO AMOSTRA acima) - NUNCA [PASS] so por falta de dado. historico completo (referencia):" +
    " " + $mHistG.autonomos.Count + "/" + $mHistG.total + " = " +
    ([string]::Format($inv, "{0:0.0}", $mHistG.pctAutonomo)) + "%.")
} elseif ($mJanelaG.pctAutonomo -lt $ALVO_PCT) {
  Write-Host ("VEREDITO ADOCAO AUTONOMA: [AVISO] " + $mJanelaG.autonomos.Count + "/" + $mJanelaG.total + " = " +
    ([string]::Format($inv, "{0:0.0}", $mJanelaG.pctAutonomo)) + "% abaixo do alvo de " + $ALVO_PCT +
    "% (injecao automatica excluida do numerador - so leitura genuina do agente). historico completo" +
    " (referencia): " + $mHistG.autonomos.Count + "/" + $mHistG.total + " = " +
    ([string]::Format($inv, "{0:0.0}", $mHistG.pctAutonomo)) + "%.")
} else {
  Write-Host ("VEREDITO ADOCAO AUTONOMA: [PASS] " + $mJanelaG.autonomos.Count + "/" + $mJanelaG.total + " = " +
    ([string]::Format($inv, "{0:0.0}", $mJanelaG.pctAutonomo)) + "% no alvo (>= " + $ALVO_PCT +
    "%), leitura genuina do agente - nao depende da injecao automatica do gate.")
}

Write-Host ("VEREDITO COBERTURA: [INFO] " + $mJanelaG.total + "/" + $mJanela.total + " = " +
  $(if ($mJanela.total -gt 0) { [string]::Format($inv, "{0:0.0}", (100.0 * $mJanelaG.total / $mJanela.total)) } else { "0.0" }) +
  "% dos pares que varreram tinham mapa em disco (o resto e escopo sem mapa nenhum - nao e culpa" +
  " do gate; puramente informativo, nunca decide PASS/FAIL sozinho).")

# WARDEN 09/09/2026: graph-usage-sensor.ps1 mudou a classificacao de scan (era substring "grep"
# em qualquer lugar do comando; agora e 1o token do pipeline + alvo = diretorio, nao arquivo
# unico). O ledger NAO grava o comando bruto (so tool/kind/scope/match) - reclassificacao
# retroativa fiel de linhas ANTIGAS e IMPOSSIVEL. Honesto: eventos scan de Bash/PowerShell
# gravados ANTES do conserto (sem como confirmar se o alvo era diretorio) sao EXCLUIDOS da leitura
# "novo" (nao contam nem a favor nem contra) - o numero "novo" so fica 100% comparavel a partir de
# quando o sensor corrigido comecar a gravar ledger novo.
$SENSOR_FIX_UTC = [datetime]::Parse("2026-09-09T00:00:00.000Z", $inv, $styles)
$legacyUnknownCount = 0
$allEventsReclass = New-Object System.Collections.Generic.List[object]
foreach ($e in $allEvents) {
 if ($e.kind -eq 'scan' -and ($e.tool -eq 'Bash' -or $e.tool -eq 'PowerShell') -and $e.ts -lt $SENSOR_FIX_UTC) {
 $legacyUnknownCount++
 continue
}

 $allEventsReclass.Add($e)
}
$histEventsReclass = @($allEventsReclass | Where-Object { $_.ts -ge (Get-Date).ToUniversalTime().AddDays(-100000) })
if ($Days -gt 0) {
 $cutoffLegado2 = (Get-Date).ToUniversalTime().AddDays(-$Days)
 $histEventsReclass = @($allEventsReclass | Where-Object { $_.ts -ge $cutoffLegado2 })
}
$janelaEventsReclass = @($allEventsReclass | Where-Object { $_.ts -ge $GateLigadoUtc })
$mHistReclass = Measure-Adocao $histEventsReclass
$mJanelaReclass = Measure-Adocao $janelaEventsReclass
Write-Host ("[RECLASSIFICACAO scan, WARDEN 09/09] adocao ANTIGA (classificacao pre-conserto, como sempre foi): janela " +
 $mJanela.adotaram.Count + "/" + $mJanela.total + " = " + ([string]::Format($inv, "{0:0.0}", $mJanela.pct)) +
 "% | historico " + $mHist.adotaram.Count + "/" + $mHist.total + " = " + ([string]::Format($inv, "{0:0.0}", $mHist.pct)) + "%.")
Write-Host ("[RECLASSIFICACAO scan, WARDEN 09/09] adocao NOVA (1o token + alvo=diretorio; " +
 $legacyUnknownCount + " evento(s) scan de Bash/PowerShell legado excluido(s) por falta do comando bruto no ledger): janela " +
 $mJanelaReclass.adotaram.Count + "/" + $mJanelaReclass.total + " = " + ([string]::Format($inv, "{0:0.0}", $mJanelaReclass.pct)) +
 "% | historico " + $mHistReclass.adotaram.Count + "/" + $mHistReclass.total + " = " + ([string]::Format($inv, "{0:0.0}", $mHistReclass.pct)) + "%.")

exit 0
