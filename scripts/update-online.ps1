<#
  update-online.ps1 - Atualiza uma instalacao SEM laboratorio local (o caso normal de quem
  recebeu o pacote pronto): baixa o zip mais recente do GitHub, compara versao, e troca SO o
  motor (engine, scripts, skills, onboarding, optional-mcps + arquivos de produto do topo).

  NUNCA toca a camada do operador: studio/, clients/, memory/, state.json, studio.yaml,
  alia.config.json. Antes de aplicar, aborta se por algum motivo esse conjunto de dados entrar
  no que seria copiado (guarda de seguranca, igual ao update-engine.ps1).

  Uso (rode da raiz da instalacao):
    powershell -ExecutionPolicy Bypass -File scripts/update-online.ps1            # aplica
    powershell -ExecutionPolicy Bypass -File scripts/update-online.ps1 -Check     # so relata
    powershell -ExecutionPolicy Bypass -File scripts/update-online.ps1 -Json      # saida JSON
    powershell -ExecutionPolicy Bypass -File scripts/update-online.ps1 -EventLog <arquivo>

  TRANSACIONAL: faz backup timestampado (.alia-backup-<yyyyMMdd-HHmmss>/) do motor atual antes de
  substituir. Depois de aplicar, roda o smoke-test; se vermelho, ROLLBACK completo a partir do
  backup. Erros classificados por fase (download, extracao, copia). Temporarios limpos no finally.

  -EventLog <arquivo>: emite progresso em JSONL append-only (fases download|extract|guard|
    backup|copy|smoke|rollback|done) para a UI do launcher fazer tail. A linha "done" reusa
    exatamente o objeto que -Json ja monta (fromVersion, toVersion, changed, smokeGreen,
    rolledBack). Sem -EventLog, o comportamento de hoje fica identico. Contrato completo:
    docs/product/alia-launcher-specs/contrato-launcher-motor.md secao 3. UTF-8 sem BOM.
#>
param(
  [switch]$Check,
  [switch]$DryRun,
  [switch]$Json,
  [string]$EventLog,
  [switch]$ConfirmMajor
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

# Repo publico do Alia Flow (open source). Branch main.
$repo   = "gufarina/alia.flow"
$branch = "main"
$zipUrl = "https://github.com/$repo/archive/refs/heads/$branch.zip"

$isCheck = $Check -or $DryRun

# --- O que e PRODUTO (atualiza) vs o que e do OPERADOR (nunca aparece aqui, nunca e tocado) ---
$engineDirs   = @("engine","scripts","skills","onboarding","optional-mcps","v2")
# .claude/docs/.opencode/.agents entram como MERGE (nao espelho), mesmo conceito de update-engine.ps1
# (v1.65.0): soma o que o pacote traz, NUNCA apaga arquivo que so existe localmente (customizacao
# do operador, ex: Specialist gerado por squad-bridge). Buraco B/C (TASK-621): Copy-Engine antigo
# apagava a pasta inteira e recopiava do zero - agora so soma nestes diretorios.
$mergeDirs    = @(".claude","docs",".opencode",".agents")
$productFiles = @("README.md","CHANGELOG.md","VERSION","LICENSE","CREDITS.md","AGENTS.md","PRIMEIROS-PASSOS.md","CONTRIBUTING.md")
# Camada do operador, intocada: studio/  clients/  state.json  studio.yaml  alia.config.json  memory/
$protected = @("studio","clients","state.json","studio.yaml","alia.config.json","memory",".git")

# Fases do protocolo de progresso (contrato secao 3) - enum fixo, os 8 valores validos de "phase".
$eventPhases = @("download","extract","guard","backup","copy","smoke","rollback","done")

# ---------------------------------------------------------------------------
# Funcoes do miolo - testaveis isoladamente, sem baixar nada.
# ---------------------------------------------------------------------------

function Get-Package {
  # Baixa o zip do GitHub e extrai numa pasta temp. Retorna o caminho da pasta interna
  # (a raiz do pacote, ex: alia-flow-main/). Sobrescrita em teste para apontar a um pacote local.
  param(
    [Parameter(Mandatory)][string]$ZipUrl,
    [Parameter(Mandatory)][string]$TmpZip,
    [Parameter(Mandatory)][string]$TmpDir
  )
  try {
    Invoke-WebRequest -UseBasicParsing -Uri $ZipUrl -OutFile $TmpZip
  } catch {
    throw [System.Exception]::new("PHASE:DOWNLOAD|" + $_.Exception.Message)
  }
  try {
    Expand-Archive -Path $TmpZip -DestinationPath $TmpDir -Force
  } catch {
    throw [System.Exception]::new("PHASE:EXTRACT|" + $_.Exception.Message)
  }
  $inner = Get-ChildItem -Directory $TmpDir | Select-Object -First 1
  if (-not $inner) {
    throw [System.Exception]::new("PHASE:EXTRACT|pacote extraido nao contem pasta raiz")
  }
  return $inner.FullName
}

function Get-PackageVersion {
  param([Parameter(Mandatory)][string]$PackageDir)
  $p = Join-Path $PackageDir "VERSION"
  if (-not (Test-Path -LiteralPath $p)) { return "" }
  return ((Get-Content $p -ErrorAction SilentlyContinue) -join "").Trim()
}

function Get-CopySet {
  # Junta engineDirs + productFiles que realmente existem no pacote baixado.
  param(
    [Parameter(Mandatory)][string]$PackageDir,
    [Parameter(Mandatory)][string[]]$EngineDirs,
    [Parameter(Mandatory)][string[]]$ProductFiles
  )
  $items = @()
  foreach ($d in $EngineDirs) {
    if (Test-Path -LiteralPath (Join-Path $PackageDir $d)) { $items += $d }
  }
  foreach ($f in $ProductFiles) {
    if (Test-Path -LiteralPath (Join-Path $PackageDir $f)) { $items += $f }
  }
  return $items
}

function Assert-SafeCopySet {
  # Guarda de seguranca: aborta (throw) se o conjunto a copiar tocar a camada do operador.
  param(
    [Parameter(Mandatory)][string[]]$CopySet,
    [Parameter(Mandatory)][string[]]$Protected
  )
  $overlap = @($CopySet | Where-Object { $Protected -contains $_ })
  if ($overlap.Count -gt 0) {
    throw [System.Exception]::new("PHASE:GUARD|update tentaria tocar a camada do operador: " + ($overlap -join ", "))
  }
}

function Test-ValidAliaRoot {
  # Guarda de destino valido (furo 2 do contrato): confirma que $RootDir e uma instancia Alia de
  # verdade ANTES de aplicar qualquer copyset - VERSION + alia.config.json, ou engine\constitution.md.
  param([Parameter(Mandatory)][string]$RootDir)
  $hasVersionAndConfig = (Test-Path -LiteralPath (Join-Path $RootDir "VERSION")) -and
                          (Test-Path -LiteralPath (Join-Path $RootDir "alia.config.json"))
  $hasConstitution = Test-Path -LiteralPath (Join-Path $RootDir "engine\constitution.md")
  return ($hasVersionAndConfig -or $hasConstitution)
}

function Write-UpdateEvent {
  # Emite uma linha JSONL de progresso em $EventLogPath (contrato secao 3). Fail-soft: se a
  # escrita falhar por qualquer motivo, engole o erro e segue - emitir evento NUNCA pode
  # quebrar o fluxo de atualizacao. Sem $EventLogPath, e um no-op silencioso.
  param(
    [string]$EventLogPath,
    [Parameter(Mandatory)][string]$Phase,
    [Parameter(Mandatory)][int]$Pct,
    [Parameter(Mandatory)][string]$Message,
    [string]$Result,
    [object]$Detail
  )
  if (-not $EventLogPath) { return }
  try {
    $evt = [ordered]@{
      ts      = (Get-Date).ToUniversalTime().ToString("o")
      phase   = $Phase
      pct     = $Pct
      message = $Message
    }
    if ($Phase -eq "done") {
      $evt.result = $Result
      $evt.detail = $Detail
    }
    $line = ($evt | ConvertTo-Json -Depth 5 -Compress)
    Add-Content -LiteralPath $EventLogPath -Value $line -Encoding UTF8
  } catch {
    # fail-soft de proposito - evento perdido nunca derruba a atualizacao.
  }
}

function Backup-Engine {
  # Copia os itens do CopySet que ja existem em $DestDir para uma pasta de backup timestampada.
  param(
    [Parameter(Mandatory)][string]$DestDir,
    [Parameter(Mandatory)][string[]]$CopySet,
    [Parameter(Mandatory)][string]$Stamp
  )
  $backupDir = Join-Path $DestDir (".alia-backup-" + $Stamp)
  New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
  foreach ($name in $CopySet) {
    $src = Join-Path $DestDir $name
    if (Test-Path -LiteralPath $src) {
      Copy-Item -LiteralPath $src -Destination (Join-Path $backupDir $name) -Recurse -Force
    }
  }
  return $backupDir
}

function Get-MajorPart([string]$ver) {
  # So a parte MAJOR de MAJOR.MINOR.PATCH (buraco F, TASK-621). -1 quando nao reconhece o formato.
  if ($ver -match '^(\d+)\.') { return [int]$Matches[1] }
  return -1
}

function Get-MirrorDiff([string]$srcDir, [string]$dstDir) {
  # Portado de update-engine.ps1 (mesmo conceito, sem excludePrefixes - update-online nao tem
  # estado local dentro do motor). Devolve New/Changed/Removed (caminhos relativos) comparando
  # hash, nao mtime - so o que MUDOU de verdade entra no diff.
  $new = @(); $changed = @(); $removed = @()
  $srcFiles = @{}
  if (Test-Path -LiteralPath $srcDir) {
    foreach ($f in (Get-ChildItem -LiteralPath $srcDir -Recurse -File)) {
      $rel = $f.FullName.Substring($srcDir.Length).TrimStart('\')
      $srcFiles[$rel] = $f.FullName
    }
  }
  $dstFiles = @{}
  if (Test-Path -LiteralPath $dstDir) {
    foreach ($f in (Get-ChildItem -LiteralPath $dstDir -Recurse -File)) {
      $rel = $f.FullName.Substring($dstDir.Length).TrimStart('\')
      $dstFiles[$rel] = $f.FullName
    }
  }
  foreach ($rel in $srcFiles.Keys) {
    if (-not $dstFiles.ContainsKey($rel)) { $new += $rel }
    elseif ((Get-FileHash -LiteralPath $srcFiles[$rel] -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $dstFiles[$rel] -Algorithm SHA256).Hash) { $changed += $rel }
  }
  foreach ($rel in $dstFiles.Keys) {
    if (-not $srcFiles.ContainsKey($rel)) { $removed += $rel }
  }
  return @{ New = @($new | Sort-Object); Changed = @($changed | Sort-Object); Removed = @($removed | Sort-Object) }
}

function Get-EngineBaseline([string]$Path) {
  # Le o baseline PRISTINO da versao hoje instalada (escrito pelo proprio update-online.ps1 no
  # fim do update anterior - nao depende do MANIFEST.sha256 do pacote, que e opcional e nao cobre
  # todo arquivo). Sem baseline (1o update apos este mecanismo existir, ou instalacao nova): volta
  # vazio - a deteccao de edicao local fica indisponivel so nesse update, nunca inventa palpite.
  $map = @{}
  if (Test-Path -LiteralPath $Path) {
    foreach ($line in (Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue)) {
      $parts = $line -split '\|', 2
      if ($parts.Count -eq 2) { $map[$parts[0]] = $parts[1] }
    }
  }
  return $map
}

function Save-EngineBaseline([string]$DestDir, [string[]]$MirrorSet, [string]$Path) {
  # Grava o hash de CADA arquivo recem-aplicado - vira o baseline pristino da PROXIMA rodada.
  $lines = New-Object System.Collections.Generic.List[string]
  foreach ($name in $MirrorSet) {
    $full = Join-Path $DestDir $name
    if (Test-Path -LiteralPath $full -PathType Container) {
      foreach ($f in (Get-ChildItem -LiteralPath $full -Recurse -File)) {
        $rel = ($name + "/" + $f.FullName.Substring($full.Length).TrimStart('\')).Replace('\', '/')
        $lines.Add($rel + "|" + (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash)
      }
    } elseif (Test-Path -LiteralPath $full) {
      $lines.Add($name + "|" + (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash)
    }
  }
  [System.IO.File]::WriteAllLines($Path, $lines, (New-Object System.Text.UTF8Encoding($false)))
}

function Copy-Engine {
  # DIFF-ONLY (buraco B/C, TASK-621): so toca (cria/atualiza/remove) o arquivo que realmente
  # mudou, em vez de apagar a pasta inteira e recopiar do zero - mesmo conceito de
  # update-engine.ps1 (Get-MirrorDiff), portado aqui porque update-online.ps1 roda sozinho, sem
  # laboratorio ao lado, e nao pode dot-source o outro script. O backup de seguranca continua
  # sendo o item INTEIRO (Backup-Engine, acima) - so muda COMO a copia e aplicada.
  # $MirrorSet: motor puro (engine/scripts/skills/onboarding/optional-mcps + arquivos de topo) -
  #   espelha de verdade (New/Changed/Removed), igual update-engine.ps1 faz com engineDirs.
  # $MergeSet: .claude/docs/.opencode/.agents - SOMA (robocopy /E sem /MIR), nunca apaga arquivo
  #   que so existe localmente (customizacao do operador). Mesmo mecanismo de update-engine.ps1.
  param(
    [Parameter(Mandatory)][string]$PackageDir,
    [Parameter(Mandatory)][string]$DestDir,
    [Parameter(Mandatory)][string[]]$MirrorSet,
    [string[]]$MergeSet = @(),
    [hashtable]$Baseline = @{}
  )
  $localEdits = New-Object System.Collections.Generic.List[string]
  foreach ($name in $MirrorSet) {
    $src = Join-Path $PackageDir $name
    $dst = Join-Path $DestDir $name
    if (Test-Path -LiteralPath $src -PathType Container) {
      $diff = Get-MirrorDiff $src $dst
      foreach ($rel in $diff.New) {
        $to = Join-Path $dst $rel
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $to) | Out-Null
        Copy-Item -LiteralPath (Join-Path $src $rel) -Destination $to -Force
      }
      foreach ($rel in $diff.Changed) {
        $to = Join-Path $dst $rel
        $key = ($name + "/" + $rel).Replace('\', '/')
        # so acusa edicao local quando o baseline CONHECE o arquivo e o hash diverge - sem
        # baseline (1o update apos este mecanismo), sobrescreve como sempre, sem palpite.
        if ($Baseline.ContainsKey($key) -and ((Get-FileHash -LiteralPath $to -Algorithm SHA256).Hash -ne $Baseline[$key])) {
          Copy-Item -LiteralPath $to -Destination ($to + ".seu-backup") -Force
          $localEdits.Add($key)
        }
        Copy-Item -LiteralPath (Join-Path $src $rel) -Destination $to -Force
      }
      foreach ($rel in $diff.Removed) {
        $to = Join-Path $dst $rel
        if (Test-Path -LiteralPath $to) {
          Remove-Item -LiteralPath (Get-Item -LiteralPath $to -Force).FullName -Force
        }
      }
      if (Test-Path -LiteralPath $dst) {
        $empties = @(Get-ChildItem -LiteralPath $dst -Recurse -Directory | Sort-Object { $_.FullName.Length } -Descending)
        foreach ($dir in $empties) {
          if (@(Get-ChildItem -LiteralPath $dir.FullName -Force).Count -eq 0) { Remove-Item -LiteralPath $dir.FullName -Force }
        }
      }
    } elseif (Test-Path -LiteralPath $src) {
      # arquivo de topo (ex: README.md) - so troca se o conteudo mudou.
      if ((-not (Test-Path -LiteralPath $dst)) -or ((Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash)) {
        Copy-Item -LiteralPath $src -Destination $dst -Force
      }
    }
  }
  foreach ($name in $MergeSet) {
    $src = Join-Path $PackageDir $name
    $dst = Join-Path $DestDir $name
    if (Test-Path -LiteralPath $src) {
      robocopy $src $dst /E /NFL /NDL /NP /NS /NC /NJH /NJS | Out-Null
    }
  }
  return @($localEdits)
}

function Restore-Engine {
  # Rollback: remove de $DestDir os itens do CopySet (estado novo aplicado) e devolve os
  # itens originais a partir de $BackupDir.
  param(
    [Parameter(Mandatory)][string]$DestDir,
    [Parameter(Mandatory)][string]$BackupDir,
    [Parameter(Mandatory)][string[]]$CopySet
  )
  foreach ($name in $CopySet) {
    $target = Join-Path $DestDir $name
    if (Test-Path -LiteralPath $target) {
      # Rollback tem que ser a prova de falhas: resolve o caminho real (8.3 short-path quebra
      # Remove-Item -LiteralPath em PS 5.1) para o restore nunca falhar por causa do path.
      $targetFull = (Get-Item -LiteralPath $target -Force).FullName
      Remove-Item -LiteralPath $targetFull -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
  if ($BackupDir -and (Test-Path -LiteralPath $BackupDir)) {
    Get-ChildItem -Path $BackupDir -Force | ForEach-Object {
      Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $DestDir $_.Name) -Recurse -Force
    }
  }
}

# Se o script foi apenas "dot-sourced" para testar as funcoes acima, para aqui.
if ($env:ALIA_UPDATE_ONLINE_TEST_ONLY -eq "1") {
  return
}

# ---------------------------------------------------------------------------
# Fluxo real
# ---------------------------------------------------------------------------

$verInst = ((Get-Content (Join-Path $root "VERSION") -ErrorAction SilentlyContinue) -join "").Trim()

$tmpZip = Join-Path $env:TEMP ("alia-update-" + [System.Guid]::NewGuid().ToString("N") + ".zip")
$tmpDir = Join-Path $env:TEMP ("alia-update-x-" + [System.Guid]::NewGuid().ToString("N"))
$backupDir = $null
$copySet = @()
$applied = $false
$smokeGreen = $false
$rolledBack = $false
$exitCode = 0

function Emit-Result {
  # Monta o objeto de resultado (o mesmo que -Json ja imprime) e, se -EventLog foi passado,
  # emite a linha "done" do protocolo de progresso REUSANDO exatamente este objeto como detail.
  param([string]$fromVersion, [string]$toVersion, [string]$eventMessage = "", [string]$result = "")
  $resultObj = [PSCustomObject]@{
    fromVersion = $fromVersion
    toVersion   = $toVersion
    applied     = $applied
    changed     = $copySet
    smokeGreen  = $smokeGreen
    rolledBack  = $rolledBack
  }
  if ($Json) {
    $resultObj | ConvertTo-Json -Depth 5
  }
  if ($result) {
    Write-UpdateEvent -EventLogPath $EventLog -Phase "done" -Pct 100 -Message $eventMessage -Result $result -Detail $resultObj
  }
}

# Guarda de destino valido (furo 2): confirma que $root e uma instancia Alia de verdade ANTES
# de tocar em qualquer coisa. Roda mesmo em -Check/-DryRun (nada de rede ainda foi gasto).
if (-not (Test-ValidAliaRoot -RootDir $root)) {
  Write-Host ("[ABORTADO] " + $root + " nao parece uma instancia Alia (falta VERSION+alia.config.json ou engine\constitution.md).")
  Write-UpdateEvent -EventLogPath $EventLog -Phase "guard" -Pct 0 -Message "destino nao e instancia Alia" -Result "error" -Detail ([ordered]@{ root = $root })
  exit 1
}

try {
  Write-UpdateEvent -EventLogPath $EventLog -Phase "download" -Pct 10 -Message "baixando o motor mais recente"
  try {
    $pkgDir = Get-Package -ZipUrl $zipUrl -TmpZip $tmpZip -TmpDir $tmpDir
  } catch {
    $msg = $_.Exception.Message
    if ($msg -like "PHASE:DOWNLOAD|*") {
      Write-Host ("[ERRO] download falhou (rede/URL): " + $msg.Substring(15))
    } elseif ($msg -like "PHASE:EXTRACT|*") {
      Write-Host ("[ERRO] extracao falhou (zip corrompido?): " + $msg.Substring(14))
    } else {
      Write-Host ("[ERRO] " + $msg)
    }
    Emit-Result -fromVersion $verInst -toVersion "" -eventMessage "download/extracao falhou" -result "error"
    exit 1
  }

  Write-UpdateEvent -EventLogPath $EventLog -Phase "extract" -Pct 30 -Message "extraindo o pacote"

  $verPkg = Get-PackageVersion -PackageDir $pkgDir

  if ($verPkg -eq $verInst) {
    Write-Host ("Ja esta na versao " + $verInst + ". Nada a fazer.")
    Emit-Result -fromVersion $verInst -toVersion $verPkg -eventMessage "ja esta atualizado" -result "noop"
    exit 0
  }

  Write-UpdateEvent -EventLogPath $EventLog -Phase "guard" -Pct 40 -Message "conferindo integridade e guardas de seguranca"

  # Integridade (contrato secao 5 item 6): se o pacote baixado tem MANIFEST.sha256, confere
  # ANTES de aplicar o copyset. Sem manifesto no pacote, segue normal (nao inventa exigencia).
  # CONSERTO (code review adversarial, 31/08/2026 - mesma classe do bloqueador achado no
  # install.ps1): o verificador que vale e o que veio DENTRO do pacote baixado (mesma versao do
  # manifesto que ele confere), nao o da instalacao antiga - uma instalacao anterior a
  # verify-manifest.ps1 existir nem tem o arquivo, e `& $verifyScript` num caminho inexistente
  # derruba a atualizacao com erro cru em vez de degradar.
  $manifestPath = Join-Path $pkgDir "MANIFEST.sha256"
  if (Test-Path -LiteralPath $manifestPath) {
    $verifyScript = ""
    $verifyDoPacote = Join-Path $pkgDir "scripts\verify-manifest.ps1"
    if (Test-Path -LiteralPath $verifyDoPacote) {
      $verifyScript = $verifyDoPacote
    } elseif (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
      $localCandidato = Join-Path $PSScriptRoot "verify-manifest.ps1"
      if (Test-Path -LiteralPath $localCandidato) { $verifyScript = $localCandidato }
    }
    if ([string]::IsNullOrWhiteSpace($verifyScript)) {
      Write-Host "[AVISO] o pacote tem MANIFEST.sha256 mas nao trouxe scripts\verify-manifest.ps1 - integridade nao conferida agora (ver docs\INTEGRIDADE.md)."
    } else {
      & $verifyScript -Dir $pkgDir | Out-Null
      if ($LASTEXITCODE -ne 0) {
        Write-Host "[ABORTADO] integridade do pacote falhou (MANIFEST.sha256 nao bate) - nada tocado."
        Emit-Result -fromVersion $verInst -toVersion $verPkg -eventMessage "integridade falhou" -result "error"
        exit 1
      }
    }
  }

  $copySet = Get-CopySet -PackageDir $pkgDir -EngineDirs $engineDirs -ProductFiles $productFiles
  $mergeSet = Get-CopySet -PackageDir $pkgDir -EngineDirs $mergeDirs -ProductFiles @()
  $copySet = @($copySet + $mergeSet)

  try {
    Assert-SafeCopySet -CopySet $copySet -Protected $protected
  } catch {
    Write-Host ("[ABORTADO] " + $_.Exception.Message.Substring(12))
    Emit-Result -fromVersion $verInst -toVersion $verPkg -eventMessage "guarda de seguranca abortou" -result "error"
    exit 1
  }

  $majorInst = Get-MajorPart $verInst
  $majorPkg  = Get-MajorPart $verPkg
  $isMajorBump = ($majorInst -ge 0) -and ($majorPkg -gt $majorInst)
  if ($isMajorBump -and -not $isCheck -and -not $ConfirmMajor) {
    Write-Host ""
    Write-Host ("[ATENCAO] a versao " + $verPkg + " muda regras do motor (mudanca MAJOR: v" + $majorInst + " -> v" + $majorPkg + ").")
    Write-Host "          Isso pode exigir uma acao sua - veja a secao dessa versao maior no CHANGELOG.md antes de seguir."
    if (-not $Json -and -not $EventLog) {
      $respMajor = Read-Host "          Quer aplicar mesmo assim? (s/N)"
      if ($respMajor -notmatch '^(s|sim|y|yes)$') {
        Write-Host "[CANCELADO] nada foi alterado."
        Emit-Result -fromVersion $verInst -toVersion $verPkg -eventMessage "MAJOR: usuario nao confirmou" -result "noop"
        exit 0
      }
    } else {
      Write-Host "[PARADO] sem terminal para confirmar (-Json/-EventLog) - repita com -ConfirmMajor depois de revisar o CHANGELOG."
      Emit-Result -fromVersion $verInst -toVersion $verPkg -eventMessage "MAJOR requer confirmacao explicita" -result "needsConfirmation"
      exit 2
    }
  }

  Write-Host ("versao atual: " + $verInst + "  ->  nova versao: " + $verPkg)
  Write-Host ("pastas/arquivos de motor que seriam substituidos (" + $copySet.Count + "):")
  foreach ($c in $copySet) { Write-Host ("  - " + $c) }

  if ($isCheck) {
    Write-Host ""
    Write-Host "-Check: nada foi alterado."
    Emit-Result -fromVersion $verInst -toVersion $verPkg -eventMessage "-Check: nada foi alterado" -result "noop"
    exit 0
  }

  Write-UpdateEvent -EventLogPath $EventLog -Phase "backup" -Pct 55 -Message "salvando o motor atual"
  $stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
  $backupDir = Backup-Engine -DestDir $root -CopySet $copySet -Stamp $stamp
  Write-Host ("[OK] backup do motor atual salvo em: " + $backupDir)

  Write-UpdateEvent -EventLogPath $EventLog -Phase "copy" -Pct 75 -Message "copiando o motor novo"
  try {
    $mirrorSet = @($copySet | Where-Object { $mergeSet -notcontains $_ })
    $baselinePath = Join-Path $root ".alia-engine-baseline.sha256"
    $baseline = Get-EngineBaseline $baselinePath
    $localEdits = @(Copy-Engine -PackageDir $pkgDir -DestDir $root -MirrorSet $mirrorSet -MergeSet $mergeSet -Baseline $baseline)
    foreach ($ed in $localEdits) {
      Write-Host ("[SEU] " + $ed + " tinha edicao sua - a sua versao foi salva como " + $ed + ".seu-backup, e a versao nova foi aplicada.")
    }
    $applied = $true
  } catch {
    Write-Host ("[ERRO] copia falhou no meio: " + $_.Exception.Message)
    Write-UpdateEvent -EventLogPath $EventLog -Phase "rollback" -Pct 90 -Message "restaurando o motor anterior"
    Restore-Engine -DestDir $root -BackupDir $backupDir -CopySet $copySet
    $rolledBack = $true
    Write-Host "[ROLLBACK] motor anterior restaurado."
    Emit-Result -fromVersion $verInst -toVersion $verPkg -eventMessage "copia falhou, revertido" -result "rolledback"
    exit 1
  }

  Write-UpdateEvent -EventLogPath $EventLog -Phase "smoke" -Pct 85 -Message "rodando o smoke-test"
  $smokeScript = Join-Path $root "scripts\smoke-test.ps1"
  if (Test-Path -LiteralPath $smokeScript) {
    & $smokeScript | Out-Null
    $smokeGreen = ($LASTEXITCODE -eq 0)
  } else {
    $smokeGreen = $true
  }

  if (-not $smokeGreen) {
    Write-UpdateEvent -EventLogPath $EventLog -Phase "rollback" -Pct 90 -Message "smoke vermelho, restaurando o motor anterior"
    Restore-Engine -DestDir $root -BackupDir $backupDir -CopySet $copySet
    $rolledBack = $true
    $applied = $false
    Write-Host "[ROLLBACK] motor anterior restaurado."
    Emit-Result -fromVersion $verInst -toVersion $verPkg -eventMessage "smoke vermelho, revertido" -result "rolledback"
    exit 1
  }

  Save-EngineBaseline -DestDir $root -MirrorSet $mirrorSet -Path $baselinePath
  Write-Host ("[OK] Alia Flow atualizado para v" + $verPkg)
  Emit-Result -fromVersion $verInst -toVersion $verPkg -eventMessage "atualizado" -result "ok"
  exit 0
} finally {
  Remove-Item $tmpZip, $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
}
