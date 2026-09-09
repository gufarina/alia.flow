<#
  memory-curator.ps1 - Mecanismo do loop agendado memory-curator (cadence: weekly, owner: alia).
  Spec: engine/governance/loops.catalog.yaml (scheduled_loops: memory-curator).
  Pergunta que responde: a memoria/regras do Client tem redundancia ou notas stale acumuladas?
  Curador semanal do loop de aprendizado: consolida memorias/regras e arquiva o que envelheceu.
  Espelha evolution-scan/debt-scan (semanais, dono alia). Le studio/clients/{Client}.
  Provenance (engine/governance/provenance.md): so toca agent-authored em studio/. NUNCA toca
  nucleo (arquivo com "provenance: nucleo"), NUNCA toca engine/, e NUNCA deleta. Para stale,
  ARQUIVA movendo para studio/clients/{Client}/_retired/ com motivo+data (caminho irma _retired/).
  Em -DryRun so LISTA - nada e movido. Frugal: so le mtime/git log e compara titulos.
  TTL (engine/governance/memory-types.md): alem do stale-por-data, honra o campo opcional
  `expires: YYYY-MM-DD`. Memoria tipo Estado com expires no passado expirou e e proposta para
  arquivamento; memoria critica (type: Decisoes|Preferencias) NUNCA expira por TTL (ignora expires).
  Escrita .NET UTF-8 sem BOM. RSI propoe, Gate aprova.

  ---------------------------------------------------------------------------------------
  MODO -Validade (memoria com validade no tempo / bi-temporal).
  Spec: research/graph-engineering/spec-memoria-com-validade.md.
  Le os DOIS cofres de notas do operador (o `memory/` da instancia do studio e o cofre do
  harness em ~/.claude/projects/<instancia>/memory) e reporta o ESTADO de cada fato:
  VIGENTE / VENCIDO / SUPERSEDIDO, derivado dos campos de janela de validade no cabecalho.
  Fecha o furo 5 da auditoria (dois cofres que se ignoram, `[[ligacoes]]` que nada le).

  SEMPRE somente-leitura. A unica escrita possivel e a migracao cirurgica de UMA nota, via
  -Fechar <slug> + -Aplicar (com backup datado em _backups/ antes de tocar no arquivo).
  Sem -Aplicar, o -Fechar so mostra as linhas que inseriria (dry-run por padrao).

  Achados (cada nome diz exatamente o que ele detecta - sem prometer magia):
   [FATO-MORTO-VIVO]  cabecalho diz VIGENTE mas a tarja da nota (description + 3 primeiras
                      linhas do corpo) declara supersessao. E o unico achado que REPROVA.
                      Escape honesto: `validade: registro` na nota que REGISTRA supersessao
                      de terceiro em vez de estar morta ela mesma.
   [CITA-VENCIDO]     nota/indice VIGENTE cita um fato VENCIDO/SUPERSEDIDO por `[[link]]`
                      (ou link md, em indice) sem marcar na mesma linha que ele morreu.
   [ASSUNTO-DUPLO]    duas notas VIGENTES com assunto sobreposto (>=2 tokens de slug) e sem
                      ligacao entre si. Suspeita de contradicao/duplicata - NUNCA resolvida
                      pela maquina; a heuristica e de nome de arquivo, nao de semantica.
   [LINK-QUEBRADO]    `[[link]]` que nao existe em nenhum dos dois cofres.
  ---------------------------------------------------------------------------------------
#>
param(
  [string]$Client = "",
  [int]$StaleDays = 90,
  [switch]$DryRun,
  # --- modo -Validade (auditoria bi-temporal dos cofres do operador) ---
  [switch]$Validade,
  [string[]]$Vault = @(),
  [switch]$IncluirVencidas,
  [string]$Fechar = "",
  [string]$ValidoDe = "",
  [string]$ValidoAte = "",
  [string]$SubstituidoPor = "",
  [string]$Substitui = "",
  [string]$Fonte = "",
  [switch]$Registro,
  [switch]$Aplicar
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "_studio.ps1")
$studioRoot = Get-StudioRoot $root

# =========================================================================================
# MODO -Validade: memoria com validade no tempo (bi-temporal em ARQUIVO, sem banco de grafo)
# =========================================================================================

# Marcadores de morte de fato. Ficam de proposito CURTOS e inequivocos: cada palavra aqui
# so aparece numa tarja quando alguem esta dizendo "isto nao vale mais".
$script:ReMorte = '(?i)(SUPERSEDED|SUPERSEDID[AO]|SUPERAD[AO]|DERRUBAD[AO]|REVERTID[AO]|APOSENTAD[AO]|NAO VALE MAIS|NAO E MAIS VALID[AO])'

# Tokens que nao distinguem assunto nenhum nesta casa - fora da heuristica de assunto duplo.
$script:StopTokens = @('alia','flow','studio','ceo','nao','com','para','como','que',
  'dos','das','uma','sem','pelo','pela','este','esta','isso','fatos','estado','sobre','mais')

function Get-FmField {
  param([string]$Block, [string]$Field)
  if ([string]::IsNullOrEmpty($Block)) { return "" }
  $m = [regex]::Match($Block, '(?im)^[ \t]*' + $Field + '[ \t]*:[ \t]*(.+?)[ \t]*$')
  if ($m.Success) { return $m.Groups[1].Value.Trim().Trim('"').Trim("'").Trim() }
  return ""
}

function ConvertTo-IsoDate {
  param([string]$Raw)
  if ([string]::IsNullOrWhiteSpace($Raw)) { return $null }
  $m = [regex]::Match($Raw, '(\d{4}-\d{2}-\d{2})')
  if (-not $m.Success) { return $null }
  return ($m.Groups[1].Value -as [datetime])
}

# Descobre os dois cofres do operador. -Vault sobrescreve (util em teste/outra instancia).
function Get-ValidadeVaults {
  param([string]$LabRoot, [string[]]$Explicit)
  if ($Explicit -and $Explicit.Count -gt 0) { return @($Explicit) }
  $out = New-Object System.Collections.Generic.List[string]
  # Este script roda em DOIS lugares: na oficina (<instancia>/clients/alia-flow-lab) e na propria
  # instancia (o updater espelha scripts/ pra la - e la que o smoke da instancia o chama). O cofre
  # do operador esta SEMPRE na instancia. Discriminador deterministico: se a pasta-pai se chama
  # "clients", isto e uma oficina/cliente e a instancia esta dois niveis acima; senao ja estamos
  # na instancia. Sem esta cerca, rodar da instancia procurava memory/ em Projetos/.. e saia com
  # "nenhum cofre encontrado" (medido na integracao 04/08).
  $parentDir = Split-Path $LabRoot -Parent
  $instance = $LabRoot
  if ((Split-Path $parentDir -Leaf) -eq "clients") { $instance = Split-Path $parentDir -Parent }
  $v1 = Join-Path $instance "memory"
  if (Test-Path -LiteralPath $v1) { $out.Add($v1) }
  # Cofre do harness (Claude Code): ~/.claude/projects/<caminho-com-hifens>/memory
  $slug = ($instance -replace '[^A-Za-z0-9]', '-')
  $v2 = Join-Path $env:USERPROFILE (".claude\projects\" + $slug + "\memory")
  if (Test-Path -LiteralPath $v2) { $out.Add($v2) }
  return @($out.ToArray())
}

function Read-MemoryNote {
  param([System.IO.FileInfo]$File, [string]$VaultLabel, [datetime]$Now)
  $text = [System.IO.File]::ReadAllText($File.FullName)
  $fm = ""
  $body = $text
  $mfm = [regex]::Match($text, '(?s)^\s*---\r?\n(.*?)\r?\n---\r?\n?(.*)$')
  if ($mfm.Success) { $fm = $mfm.Groups[1].Value; $body = $mfm.Groups[2].Value }

  $name = Get-FmField $fm 'name'
  if ([string]::IsNullOrWhiteSpace($name)) { $name = $File.BaseName }

  # Campos NOVOS (spec-memoria-com-validade.md) + os LEGADOS ja em uso na casa.
  $validoDe   = ConvertTo-IsoDate (Get-FmField $fm 'valido_de')
  $validoAte  = ConvertTo-IsoDate (Get-FmField $fm 'valido_ate')
  $substPor   = Get-FmField $fm 'substituido_por'
  $substitui  = Get-FmField $fm 'substitui'
  $fonte      = Get-FmField $fm 'fonte'
  $validade   = Get-FmField $fm 'validade'
  $status     = Get-FmField $fm 'status'
  $legSupBy   = Get-FmField $fm 'superseded_by'
  $legSupOn   = ConvertTo-IsoDate (Get-FmField $fm 'superseded_on')
  $memType    = Get-FmField $fm 'type'
  $expires    = ConvertTo-IsoDate (Get-FmField $fm 'expires')
  $promotedOn = ConvertTo-IsoDate (Get-FmField $fm 'promoted_on')
  $isCritical = ($memType -ieq 'Decisoes' -or $memType -ieq 'Preferencias')

  # Migracao suave: nota sem NENHUMA declaracao de validade (nova ou legada) vale como
  # VIGENTE de janela aberta. Nada quebra; a nota antiga continua valendo.
  $temValidade = -not (
    [string]::IsNullOrWhiteSpace((Get-FmField $fm 'valido_de')) -and
    $null -eq $validoAte -and [string]::IsNullOrWhiteSpace($substPor) -and
    [string]::IsNullOrWhiteSpace($substitui) -and [string]::IsNullOrWhiteSpace($legSupBy) -and
    $null -eq $expires -and ($status -inotmatch '^supersed'))

  # Derivacao do estado. Precedencia: SUPERSEDIDO > VENCIDO > VIGENTE.
  $estado = "VIGENTE"
  $motivo = "janela aberta"
  if (-not [string]::IsNullOrWhiteSpace($substPor)) {
    $estado = "SUPERSEDIDO"; $motivo = "substituido_por: " + $substPor
  } elseif (-not [string]::IsNullOrWhiteSpace($legSupBy) -or $status -imatch '^supersed') {
    $estado = "SUPERSEDIDO"
    $motivo = "legado: " + $(if ($legSupBy) { "superseded_by " + $legSupBy } else { "status " + $status })
  } elseif ($null -ne $validoAte -and $validoAte -lt $Now) {
    $estado = "VENCIDO"; $motivo = "valido_ate " + $validoAte.ToString("yyyy-MM-dd") + " ja passou"
  } elseif ($null -ne $expires -and -not $isCritical -and $expires -lt $Now) {
    $estado = "VENCIDO"; $motivo = "legado: expires " + $expires.ToString("yyyy-MM-dd") + " ja passou"
  } elseif ($null -ne $validoAte) {
    $motivo = "janela fecha em " + $validoAte.ToString("yyyy-MM-dd")
  }

  # Tarja = onde a casa escreve "isto morreu": o description + as 3 primeiras linhas do corpo.
  $desc = Get-FmField $fm 'description'
  $bodyLines = @(($body -split "\r?\n") | Where-Object { $_.Trim() -ne "" })
  $tarja = $desc + " " + (($bodyLines | Select-Object -First 3) -join " ")
  $tarjaMorte = [regex]::IsMatch($tarja, $script:ReMorte)

  # Ligacoes [[...]] - o grafo de citacoes que hoje ninguem le (furo 5 da auditoria).
  $links = New-Object System.Collections.Generic.List[object]
  foreach ($lm in [regex]::Matches($text, '\[\[([^\]\|#]+)')) {
    $alvo = $lm.Groups[1].Value.Trim()
    $linha = ""
    foreach ($l in ($text -split "\r?\n")) { if ($l.Contains("[[" + $alvo)) { $linha = $l; break } }
    if ($alvo.ToLowerInvariant().EndsWith(".md")) { $alvo = $alvo.Substring(0, $alvo.Length - 3) }
    $links.Add([pscustomobject]@{ alvo = $alvo; linha = $linha })
  }
  $ehIndice = ($File.Name -ieq "_index.md" -or $File.Name -ieq "MEMORY.md")
  if ($ehIndice) {
    foreach ($lm in [regex]::Matches($text, '\]\(([A-Za-z0-9\-_]+)\.md\)')) {
      $alvo = $lm.Groups[1].Value.Trim()
      $linha = ""
      foreach ($l in ($text -split "\r?\n")) { if ($l.Contains("(" + $alvo + ".md)")) { $linha = $l; break } }
      $links.Add([pscustomobject]@{ alvo = $alvo; linha = $linha })
    }
  }

  return [pscustomobject]@{
    file = $File.FullName; vault = $VaultLabel; name = $name; slug = $File.BaseName
    estado = $estado; motivo = $motivo; temValidade = $temValidade
    validoDe = $validoDe; validoAte = $validoAte; substPor = $substPor; substitui = $substitui
    fonte = $fonte; validade = $validade; promotedOn = $promotedOn
    tarjaMorte = $tarjaMorte; ehIndice = $ehIndice; links = @($links.ToArray())
  }
}

function Get-SubjectTokens {
  param([string]$Slug)
  $t = @(($Slug.ToLowerInvariant() -split '[^a-z0-9]+') | Where-Object {
    $_.Length -ge 4 -and $script:StopTokens -notcontains $_
  })
  return $t
}

function Invoke-ValidadeAudit {
  param([string[]]$Vaults, [datetime]$Now, [switch]$Verboso)

  $notes = New-Object System.Collections.Generic.List[object]
  foreach ($v in $Vaults) {
    $label = Split-Path (Split-Path $v -Parent) -Leaf
    $files = @(Get-ChildItem -LiteralPath $v -Filter "*.md" -File -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -notlike "prop-*" -and $_.Name -notlike "reflection-inbox-*" })
    foreach ($f in $files) { $notes.Add((Read-MemoryNote -File $f -VaultLabel $label -Now $Now)) }
  }

  $porSlug = @{}
  foreach ($n in $notes) { if (-not $porSlug.ContainsKey($n.slug)) { $porSlug[$n.slug] = $n } }
  foreach ($n in $notes) { if (-not $porSlug.ContainsKey($n.name)) { $porSlug[$n.name] = $n } }

  # ---- Contagem por cofre ----
  Write-Host "--- Estado por cofre ---"
  foreach ($v in $Vaults) {
    $label = Split-Path (Split-Path $v -Parent) -Leaf
    $sub = @($notes | Where-Object { $_.vault -eq $label -and -not $_.ehIndice })
    $vig = @($sub | Where-Object { $_.estado -eq "VIGENTE" }).Count
    $ven = @($sub | Where-Object { $_.estado -eq "VENCIDO" }).Count
    $sup = @($sub | Where-Object { $_.estado -eq "SUPERSEDIDO" }).Count
    $sem = @($sub | Where-Object { -not $_.temValidade }).Count
    Write-Host ("[COFRE] " + $v)
    Write-Host ("    notas: " + $sub.Count + " | VIGENTE: " + $vig + " | VENCIDO: " + $ven +
      " | SUPERSEDIDO: " + $sup + " | sem nenhuma declaracao de validade (vigente por migracao suave): " + $sem)
  }

  $naoVigentes = @($notes | Where-Object { $_.estado -ne "VIGENTE" -and -not $_.ehIndice })
  Write-Host ""
  if ($naoVigentes.Count -eq 0) {
    Write-Host "[OK] nenhum fato fora da janela de validade."
  } else {
    Write-Host "--- Fatos fora da janela (ficam no disco, auditaveis) ---"
    foreach ($n in $naoVigentes) {
      Write-Host ("[" + $n.estado + "] " + $n.vault + "/" + $n.slug + " | " + $n.motivo)
    }
  }

  # ---- Achado 1: FATO-MORTO-VIVO (o unico que reprova) ----
  $mortoVivo = @($notes | Where-Object {
    $_.estado -eq "VIGENTE" -and $_.tarjaMorte -and -not $_.ehIndice -and $_.validade -ine "registro"
  })
  Write-Host ""
  if ($mortoVivo.Count -eq 0) {
    Write-Host "[OK] nenhum fato morto se passando por vigente."
  } else {
    foreach ($n in $mortoVivo) {
      Write-Host ("[FATO-MORTO-VIVO] " + $n.vault + "/" + $n.slug +
        " - a tarja declara supersessao mas o cabecalho nao fecha a janela (sem valido_ate/substituido_por).")
    }
  }

  # ---- Achado 2: CITA-VENCIDO ----
  $citaVencido = New-Object System.Collections.Generic.List[object]
  $quebrado = New-Object System.Collections.Generic.List[object]
  foreach ($n in $notes) {
    if ($n.estado -ne "VIGENTE") { continue }
    foreach ($lk in $n.links) {
      if (-not $porSlug.ContainsKey($lk.alvo)) {
        $quebrado.Add([pscustomobject]@{ de = $n; alvo = $lk.alvo }); continue
      }
      $alvo = $porSlug[$lk.alvo]
      if ($alvo.estado -eq "VIGENTE") { continue }
      # Excecao honesta: a linha que cita ja avisa que o fato morreu.
      if ([regex]::IsMatch($lk.linha, $script:ReMorte)) { continue }
      $citaVencido.Add([pscustomobject]@{ de = $n; alvo = $alvo })
    }
  }
  Write-Host ""
  if ($citaVencido.Count -eq 0) {
    Write-Host "[OK] nenhum fato vencido citado como se fosse vigente."
  } else {
    foreach ($c in $citaVencido) {
      Write-Host ("[CITA-VENCIDO] " + $c.de.vault + "/" + $c.de.slug + " cita " +
        $c.alvo.vault + "/" + $c.alvo.slug + " (" + $c.alvo.estado + ") sem marcar na linha.")
    }
  }

  # ---- Achado 3: ASSUNTO-DUPLO (heuristica fraca, declarada como suspeita) ----
  $vigentes = @($notes | Where-Object { $_.estado -eq "VIGENTE" -and -not $_.ehIndice })
  $dupes = New-Object System.Collections.Generic.List[object]
  for ($i = 0; $i -lt $vigentes.Count; $i++) {
    for ($j = $i + 1; $j -lt $vigentes.Count; $j++) {
      $a = $vigentes[$i]; $b = $vigentes[$j]
      $ta = Get-SubjectTokens $a.slug; $tb = Get-SubjectTokens $b.slug
      $comum = @($ta | Where-Object { $tb -contains $_ })
      if ($comum.Count -lt 2) { continue }
      $ligados = $false
      foreach ($lk in $a.links) { if ($lk.alvo -eq $b.slug -or $lk.alvo -eq $b.name) { $ligados = $true } }
      foreach ($lk in $b.links) { if ($lk.alvo -eq $a.slug -or $lk.alvo -eq $a.name) { $ligados = $true } }
      if ($a.substitui -eq $b.slug -or $b.substitui -eq $a.slug) { $ligados = $true }
      if ($ligados) { continue }
      $dupes.Add([pscustomobject]@{ a = $a; b = $b; comum = ($comum -join ",") })
    }
  }
  Write-Host ""
  if ($dupes.Count -eq 0) {
    Write-Host "[OK] nenhum par de notas vigentes com assunto sobreposto e sem ligacao."
  } else {
    foreach ($d in $dupes) {
      $cruza = if ($d.a.vault -ne $d.b.vault) { " [CRUZA COFRE]" } else { "" }
      Write-Host ("[ASSUNTO-DUPLO] " + $d.a.vault + "/" + $d.a.slug + " x " + $d.b.vault + "/" +
        $d.b.slug + " (tokens: " + $d.comum + ")" + $cruza + " - suspeita, decisao humana.")
    }
  }

  # ---- Achado 4: LINK-QUEBRADO ----
  Write-Host ""
  if ($quebrado.Count -eq 0) {
    Write-Host "[OK] nenhuma ligacao [[...]] apontando para nota inexistente."
  } else {
    foreach ($q in $quebrado) {
      Write-Host ("[LINK-QUEBRADO] " + $q.de.vault + "/" + $q.de.slug + " -> [[" + $q.alvo + "]] nao existe.")
    }
  }

  Write-Host ""
  $totNotas = @($notes | Where-Object { -not $_.ehIndice }).Count
  $totSem   = @($notes | Where-Object { -not $_.ehIndice -and -not $_.temValidade }).Count
  Write-Host ("Resumo: " + $totNotas + " nota(s) em " + $Vaults.Count + " cofre(s) | " +
    $totSem + " sem declaracao de validade | " + $mortoVivo.Count + " fato-morto-vivo | " +
    $citaVencido.Count + " cita-vencido | " + $dupes.Count + " assunto-duplo | " +
    $quebrado.Count + " link-quebrado")

  if ($mortoVivo.Count -gt 0) {
    Write-Host ("RESULTADO: FAIL (" + $mortoVivo.Count + " fato-morto-vivo)")
    return 1
  }
  Write-Host "RESULTADO: PASS"
  return 0
}

# Migracao cirurgica de UMA nota: insere os campos de validade no bloco metadata:.
# Backup datado ANTES de tocar. Sem -Aplicar, so mostra as linhas que inseriria.
function Invoke-FecharNota {
  param([string[]]$Vaults, [string]$Slug, [hashtable]$Campos, [switch]$Escrever, [string]$LabRoot, [string]$Today)
  $alvo = $null
  foreach ($v in $Vaults) {
    $p = Join-Path $v ($Slug + ".md")
    if (Test-Path -LiteralPath $p) { $alvo = Get-Item -LiteralPath $p; break }
  }
  if ($null -eq $alvo) { Write-Host ("[ERRO] nota nao encontrada em nenhum cofre: " + $Slug); return 1 }

  $text = [System.IO.File]::ReadAllText($alvo.FullName)
  $mMeta = [regex]::Match($text, '(?m)^([ \t]*)metadata[ \t]*:[ \t]*\r?$')
  if (-not $mMeta.Success) {
    Write-Host ("[ERRO] " + $alvo.FullName + " nao tem bloco 'metadata:' no frontmatter - migracao manual.")
    return 1
  }
  $novas = New-Object System.Collections.Generic.List[string]
  foreach ($k in @('valido_de','valido_ate','substituido_por','substitui','fonte','validade')) {
    if ($Campos.ContainsKey($k) -and -not [string]::IsNullOrWhiteSpace([string]$Campos[$k])) {
      if ([regex]::IsMatch($text, '(?im)^[ \t]*' + $k + '[ \t]*:')) {
        Write-Host ("[SKIP] campo ja existe na nota: " + $k); continue
      }
      $novas.Add("  " + $k + ": " + $Campos[$k])
    }
  }
  if ($novas.Count -eq 0) { Write-Host "[OK] nada a inserir."; return 0 }

  Write-Host ("[ALVO] " + $alvo.FullName)
  Write-Host "[DIFF] linhas a inserir logo apos 'metadata:'"
  foreach ($l in $novas) { Write-Host ("  + " + $l) }

  if (-not $Escrever) { Write-Host "[DRY-RUN] nada escrito (rode de novo com -Aplicar)."; return 0 }

  $bkDir = Join-Path $LabRoot ("_backups\memory-validade-" + $Today)
  New-Item -ItemType Directory -Force -Path $bkDir | Out-Null
  $bkName = ((Split-Path (Split-Path $alvo.DirectoryName -Parent) -Leaf) + "--" + $alvo.Name)
  $bk = Join-Path $bkDir $bkName
  [System.IO.File]::WriteAllText($bk, $text, (New-Object System.Text.UTF8Encoding($false)))
  Write-Host ("[BACKUP] " + $bk)

  $eol = if ($text -match "`r`n") { "`r`n" } else { "`n" }
  $insercao = ($novas -join $eol) + $eol
  $idx = $mMeta.Index + $mMeta.Length
  # pula a quebra de linha logo apos a linha metadata:
  while ($idx -lt $text.Length -and ($text[$idx] -eq "`r" -or $text[$idx] -eq "`n")) { $idx++ }
  $novo = $text.Substring(0, $idx) + $insercao + $text.Substring($idx)
  [System.IO.File]::WriteAllText($alvo.FullName, $novo, (New-Object System.Text.UTF8Encoding($false)))
  Write-Host ("[OK] migrada: " + $alvo.FullName)
  return 0
}

if ($Validade) {
  $nowV   = Get-Date
  $todayV = $nowV.ToString("yyyy-MM-dd")
  $vaults = Get-ValidadeVaults -LabRoot $root -Explicit $Vault
  Write-Host "=== Memory Curator - modo VALIDADE (bi-temporal) ==="
  Write-Host ("data: " + $todayV + " | cofres: " + $vaults.Count + " | modo: SOMENTE LEITURA" +
    $(if ($Fechar) { " + migracao de 1 nota (" + $(if ($Aplicar) { "APLICAR" } else { "dry-run" }) + ")" } else { "" }))
  Write-Host ""
  if ($vaults.Count -eq 0) { Write-Host "[ERRO] nenhum cofre de memoria encontrado. Use -Vault <caminho>."; exit 1 }

  if ($Fechar) {
    $campos = @{
      valido_de = $ValidoDe; valido_ate = $ValidoAte; substituido_por = $SubstituidoPor
      substitui = $Substitui; fonte = $Fonte; validade = $(if ($Registro) { "registro" } else { "" })
    }
    $rcF = Invoke-FecharNota -Vaults $vaults -Slug $Fechar -Campos $campos -Escrever:$Aplicar -LabRoot $root -Today $todayV
    Write-Host ""
    if ($rcF -ne 0) { exit $rcF }
  }

  $rc = Invoke-ValidadeAudit -Vaults $vaults -Now $nowV
  exit $rc
}

if ([string]::IsNullOrWhiteSpace($Client)) {
  Write-Host "[ERRO] informe -Client <id> (curadoria por Client) ou -Validade (auditoria bi-temporal dos cofres do operador)."
  exit 1
}

# Aceita ambos os layouts: studio real OU studio.example (briefing). O real vence se existir.
$clientDir = Join-Path $studioRoot ("clients\" + $Client)
if (-not (Test-Path -LiteralPath $clientDir)) {
  $alt = Join-Path $root ("studio.example\clients\" + $Client)
  if (Test-Path -LiteralPath $alt) { $clientDir = $alt }
}
$knowDir = Join-Path $clientDir "squad\knowledge"

$utf8  = New-Object System.Text.UTF8Encoding($false)
$today = (Get-Date).ToString("yyyy-MM-dd")
$now   = Get-Date

Write-Host "=== Memory Curator Loop ==="
Write-Host ("client: " + $Client + " | data: " + $today + " | limiar stale: " + $StaleDays + " dia(s)")
Write-Host ("modo: " + $(if ($DryRun) { "DRY-RUN (so analisa, nada e movido)" } else { "RUN (arquiva stale em _retired/)" }))
Write-Host ""

if (-not (Test-Path -LiteralPath $clientDir)) {
  Write-Host ("[ERRO] diretorio do Client ausente: " + $clientDir)
  exit 1
}

# Ultima atividade por arquivo: git log -1 (data do ultimo commit), fallback mtime.
function Get-LastActivity {
  param([string]$path)
  try {
    $iso = & git -C $root log -1 --format=%cI -- "$path" 2>$null
    if ($LASTEXITCODE -eq 0 -and $iso) {
      $d = ([string]$iso).Trim() -as [datetime]
      if ($null -ne $d) { return @{ when = $d; via = "git" } }
    }
  } catch { }
  $fi = Get-Item -LiteralPath $path
  return @{ when = $fi.LastWriteTime; via = "mtime" }
}

# Normaliza um titulo/nome para comparar similaridade (heuristica simples de duplicata).
function Normalize-Title {
  param([string]$s)
  $t = ([string]$s).ToLowerInvariant()
  $t = ($t -replace '[^a-z0-9 ]', ' ')
  $t = ($t -replace '\s+', ' ').Trim()
  return $t
}

# (1) Coleta de candidatos: .md agent-authored em memory/ e squad/knowledge/.
# Exclui loop-reports/ (saida do proprio loop) e _retired/ (ja arquivado).
$scanRoots = @()
$memRoot = Join-Path $clientDir "memory"
if (Test-Path -LiteralPath $memRoot) { $scanRoots += $memRoot }
if (Test-Path -LiteralPath $knowDir) { $scanRoots += $knowDir }

$candidates = New-Object System.Collections.Generic.List[object]
$skippedNucleo = 0

foreach ($sr in $scanRoots) {
  $mds = @(Get-ChildItem -LiteralPath $sr -Filter "*.md" -File -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '\\loop-reports\\' -and $_.FullName -notmatch '\\_retired\\' })
  foreach ($f in $mds) {
    $text = [System.IO.File]::ReadAllText($f.FullName)
    # Provenance: pula qualquer arquivo marcado como nucleo (so o operador toca).
    if ($text -match '(?im)^\s*provenance\s*:\s*nucleo\b') {
      $skippedNucleo++
      continue
    }
    # Titulo = primeiro cabecalho "# ..."; fallback = nome base sem extensao.
    $title = ""
    $m = [regex]::Match($text, '(?m)^\s*#\s+(.+?)\s*$')
    if ($m.Success) { $title = $m.Groups[1].Value } else { $title = $f.BaseName }
    # Tipagem de memoria (engine/governance/memory-types.md): tipo opcional e TTL opcional.
    # type: Preferencias|Decisoes|Estado | expires: YYYY-MM-DD (so Estado expira).
    $memType = ""
    $mt = [regex]::Match($text, '(?im)^\s*type\s*:\s*(\S+)')
    if ($mt.Success) { $memType = $mt.Groups[1].Value }
    # Critica = Decisoes/Preferencias: nunca expira por TTL (so revogacao do operador).
    $isCritical = ($memType -ieq 'Decisoes' -or $memType -ieq 'Preferencias')
    $expiresOn = $null
    $me = [regex]::Match($text, '(?im)^\s*expires\s*:\s*(\d{4}-\d{2}-\d{2})\b')
    if ($me.Success) {
      $parsed = $me.Groups[1].Value -as [datetime]
      if ($null -ne $parsed) { $expiresOn = $parsed }
    }
    $act = Get-LastActivity $f.FullName
    $candidates.Add([pscustomobject]@{
      file       = $f.FullName
      rel        = $f.FullName.Substring($clientDir.Length).TrimStart('\')
      title      = $title
      norm       = (Normalize-Title $title)
      lastWhen   = $act.when
      via        = $act.via
      ageDays    = [math]::Round(($now - $act.when).TotalDays, 1)
      memType    = $memType
      isCritical = $isCritical
      expiresOn  = $expiresOn
    })
  }
}

Write-Host ("[OK] candidatos agent-authored: " + $candidates.Count + " (nucleo ignorado: " + $skippedNucleo + ")")
foreach ($c in $candidates) {
  Write-Host ("    - " + $c.rel + " | atividade ha " + $c.ageDays + " dia(s) [" + $c.via + "]")
}

# (2) Duplicatas/orfas: titulos normalizados iguais (heuristica simples e frugal).
$dups = New-Object System.Collections.Generic.List[object]
$byNorm = $candidates | Group-Object -Property norm | Where-Object { $_.Count -gt 1 }
foreach ($g in $byNorm) {
  $names = ($g.Group | ForEach-Object { $_.rel }) -join " ; "
  $dups.Add([pscustomobject]@{ norm = $g.Name; count = $g.Count; files = $names })
}

Write-Host ""
if ($dups.Count -eq 0) {
  Write-Host "[OK] nenhuma duplicata por titulo detectada."
} else {
  foreach ($d in $dups) {
    Write-Host ("[DUP] " + $d.count + " arquivos com titulo similar: " + $d.files)
  }
}

# (3) Stale por data: atividade mais antiga que StaleDays.
$stale = @($candidates | Where-Object { $_.ageDays -gt $StaleDays })

Write-Host ""
if ($stale.Count -eq 0) {
  Write-Host ("[OK] nenhum arquivo stale (> " + $StaleDays + " dia(s)).")
} else {
  foreach ($s in $stale) {
    Write-Host ("[STALE] " + $s.rel + " | atividade ha " + $s.ageDays + " dia(s) [" + $s.via + "]")
  }
}

# (3b) Expirou por declaracao (TTL): memoria Estado com `expires:` no passado.
# Memory tipada (engine/governance/memory-types.md): so Estado expira; Decisoes/Preferencias
# (critica) nunca expiram por prazo - sao ignoradas aqui mesmo que tragam `expires`.
$expired = @($candidates | Where-Object {
  $null -ne $_.expiresOn -and -not $_.isCritical -and $_.expiresOn -lt $now
})

Write-Host ""
if ($expired.Count -eq 0) {
  Write-Host "[OK] nenhuma memoria expirada por TTL (campo expires no passado)."
} else {
  foreach ($e in $expired) {
    Write-Host ("[EXPIRED] " + $e.rel + " | type: " + $(if ($e.memType) { $e.memType } else { "(sem type)" }) +
      " | expires: " + $e.expiresOn.ToString("yyyy-MM-dd"))
  }
}
# Aviso de tipagem: memoria critica que traz `expires` (ignorado) - sinal, nao acao.
$criticalWithExpires = @($candidates | Where-Object { $null -ne $_.expiresOn -and $_.isCritical })
foreach ($cw in $criticalWithExpires) {
  Write-Host ("[AVISO] " + $cw.rel + " e " + $cw.memType + " (critica): campo expires ignorado (nao expira por TTL).")
}

# (4) Acao de arquivamento (NUNCA deleta). Em DryRun so propoe; senao move para _retired/.
# Une stale + expirou-por-TTL sem arquivar o mesmo arquivo duas vezes (chave = caminho).
$archived = New-Object System.Collections.Generic.List[object]
$retiredDir = Join-Path $clientDir "_retired"

$toArchive = New-Object System.Collections.Generic.List[object]
$seen = New-Object System.Collections.Generic.HashSet[string]
foreach ($s in $stale) {
  if ($seen.Add($s.file)) {
    $reason = "stale: sem atividade ha " + $s.ageDays + " dia(s) (limiar " + $StaleDays + ")"
    $toArchive.Add([pscustomobject]@{ item = $s; reason = $reason })
  }
}
foreach ($e in $expired) {
  if ($seen.Add($e.file)) {
    $reason = "expirou (TTL): expires " + $e.expiresOn.ToString("yyyy-MM-dd") + " ja passou (tipo Estado)"
    $toArchive.Add([pscustomobject]@{ item = $e; reason = $reason })
  }
}

foreach ($a in $toArchive) {
  $s = $a.item
  $reason = $a.reason
  if ($DryRun) {
    Write-Host ("    -> PROPOR arquivar: " + $s.rel + " (" + $reason + ")")
    $archived.Add([pscustomobject]@{ rel = $s.rel; action = "proposto"; reason = $reason })
  } else {
    New-Item -ItemType Directory -Force -Path $retiredDir | Out-Null
    $destName = (Split-Path $s.file -Leaf)
    $dest = Join-Path $retiredDir $destName
    if (Test-Path -LiteralPath $dest) {
      $dest = Join-Path $retiredDir ((Split-Path $s.file -LeafBase) + "-" + $today + ".md")
    }
    # Preserva o arquivo: prefixa cabecalho de arquivamento com motivo+data, sem perder conteudo.
    $orig = [System.IO.File]::ReadAllText($s.file)
    $header = "<!-- retired_on: " + $today + " | retired_reason: " + $reason + " -->" + "`r`n`r`n"
    [System.IO.File]::WriteAllText($dest, $header + $orig, $utf8)
    Remove-Item -LiteralPath $s.file -Force
    Write-Host ("    -> ARQUIVADO: " + $s.rel + " -> _retired\" + (Split-Path $dest -Leaf))
    $archived.Add([pscustomobject]@{ rel = $s.rel; action = "arquivado"; reason = $reason })
  }
}

# (5) Resumo estruturado.
Write-Host ""
Write-Host ("Resumo: " + $candidates.Count + " candidato(s) | " + $dups.Count + " grupo(s) duplicado(s) | " +
  $stale.Count + " stale | " + $expired.Count + " expirado(s) por TTL | " +
  $archived.Count + " " + $(if ($DryRun) { "proposto(s)" } else { "arquivado(s)" }))

# (6) Relatorio datado em loop-reports/ (igual aos outros scans: so grava fora do DryRun).
if (-not $DryRun) {
$outDir = Join-Path $knowDir "loop-reports"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$outFile = Join-Path $outDir ($today + "-memory-curator.md")
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("# Memory Curator - " + $Client + " (" + $today + ")")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("> Mecanismo: scripts/memory-curator.ps1. Curador semanal de memoria e regras.")
[void]$sb.AppendLine("> So agent-authored; nunca nucleo; nunca deleta (arquiva em _retired/).")
[void]$sb.AppendLine("> Modo: " + $(if ($DryRun) { "DRY-RUN (nada movido)" } else { "RUN" }) +
  " | limiar stale: " + $StaleDays + " dia(s)")
[void]$sb.AppendLine("> Candidatos: " + $candidates.Count + " | nucleo ignorado: " + $skippedNucleo)
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## Consolidacoes propostas (titulos similares)")
[void]$sb.AppendLine("")
if ($dups.Count -eq 0) {
  [void]$sb.AppendLine("Nenhuma duplicata por titulo detectada.")
} else {
  [void]$sb.AppendLine("| Titulo normalizado | Qtd | Arquivos |")
  [void]$sb.AppendLine("|--------------------|-----|----------|")
  foreach ($d in $dups) {
    $files = ($d.files -replace '\|', '\')
    [void]$sb.AppendLine("| " + $d.norm + " | " + $d.count + " | " + $files + " |")
  }
}
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## Memoria expirada por TTL (campo expires)")
[void]$sb.AppendLine("")
if ($expired.Count -eq 0) {
  [void]$sb.AppendLine("Nenhuma memoria Estado com expires no passado.")
} else {
  [void]$sb.AppendLine("| Arquivo | Tipo | Expires |")
  [void]$sb.AppendLine("|---------|------|---------|")
  foreach ($e in $expired) {
    $tp = $(if ($e.memType) { $e.memType } else { "(sem type)" })
    [void]$sb.AppendLine("| " + $e.rel + " | " + $tp + " | " + $e.expiresOn.ToString("yyyy-MM-dd") + " |")
  }
}
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## Arquivamentos (" + $(if ($DryRun) { "propostos" } else { "realizados" }) + ")")
[void]$sb.AppendLine("")
if ($archived.Count -eq 0) {
  [void]$sb.AppendLine("Nenhum arquivo stale para arquivar.")
} else {
  [void]$sb.AppendLine("| Arquivo | Acao | Motivo |")
  [void]$sb.AppendLine("|---------|------|--------|")
  foreach ($a in $archived) {
    [void]$sb.AppendLine("| " + $a.rel + " | " + $a.action + " | " + $a.reason + " |")
  }
}
[System.IO.File]::WriteAllText($outFile, $sb.ToString(), $utf8)
Write-Host ("[OK] relatorio: " + $outFile)
} else {
  Write-Host "[OK] DRY-RUN: relatorio nao gravado (so listagem acima)."
}

# Achar debito de curadoria e sinal, nao erro: exit 0 quando rodou bem.
exit 0
