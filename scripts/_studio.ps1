# Resolve-ArtifactItems (TASK-787, remediacao - achado da coordenadora): FONTE UNICA de resolucao
# de prova de Artifact, usada por register-task.ps1 (o registro) E gate-check.ps1 (o portao).
# Causa raiz do defeito medido (opportunities/bancada-portas/remedicao.py, 15 provas): cada script
# tinha a PROPRIA logica de resolver caminho relativo, e quando uma regra mudava (relativo a pasta
# que CONTEM o studio, onde moram os repositorios irmaos), so um dos dois aprendia. Daqui em
# diante, nenhum dos dois pode ter logica propria de resolucao - so este ponto.
# Formato canonico: itens separados por ";"; cada item e URL http(s) OU caminho de ARQUIVO OU
# PASTA (absoluto, relativo a raiz do studio, ou relativo a pasta que CONTEM o studio). Prova por
# TIPO (achado da coordenadora - "pasta" nao e "arquivo"): arquivo existe e tem tamanho > 0; pasta
# existe e NAO esta vazia; url e "url" (nao verificavel por caminho, quem chama decide o que fazer
# com isso - hoje vira SKIP/aceite, nunca FAIL). Barra final na pasta NUNCA muda o resultado.
# Devolve array de objetos: @{ item; isUrl; tipo("arquivo"|"pasta"|"url"|""); resolvedPath; found; exists }.
# "found" = achou ALGO no caminho (arquivo ou pasta, mesmo vazio). "exists" = found E valido pro
# TIPO (arquivo com conteudo, pasta com conteudo) - e o booleano final que register-task.ps1 usa;
# gate-check.ps1 usa found+exists pra distinguir "nao existe" de "existe mas vazio".
function Resolve-ArtifactItems {
  param([string]$ArtifactStr, [string]$StudioRootPath)
  $out = New-Object System.Collections.Generic.List[object]
  # CONSERTO (achado da coordenadora): a raiz chegava as vezes RELATIVA (".", ".\", etc, quando o
  # chamador roda da propria raiz do studio) - Split-Path -Parent "." devolve vazio, entao o ramo
  # do repositorio IRMAO nunca rodava (a derivacao do pai precisa de caminho ABSOLUTO). Absolutiza
  # ANTES de qualquer derivacao - unica linha nova, resolve "." e "./" contra o cwd de quem chamou.
  if (-not [string]::IsNullOrWhiteSpace($StudioRootPath)) {
    # NUNCA [System.IO.Path]::GetFullPath aqui: ele resolve contra Environment.CurrentDirectory,
    # que NAO acompanha Push-Location/Set-Location do PowerShell (o defeito medido pela
    # coordenadora: "." e "./" ficavam FAIL rodando de dentro do studio via Push-Location, so o
    # caminho ABSOLUTO passava). GetUnresolvedProviderPathFromPSPath resolve contra o cwd REAL do
    # PowerShell (o provider path), a mesma nocao de "onde estou" que Get-Location usa.
    try { $StudioRootPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($StudioRootPath) } catch { }
  }
  if ([string]::IsNullOrWhiteSpace($ArtifactStr)) { return $out.ToArray() }
  $items = @($ArtifactStr -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
  foreach ($it in $items) {
    if ($it -match '^(?i)https?://') {
      $out.Add([PSCustomObject]@{ item = $it; isUrl = $true; tipo = "url"; resolvedPath = ""; found = $true; exists = $true })
      continue
    }
    # barra final (pasta "com barra") nunca pode mudar o resultado - apara antes de testar.
    $itTrim = $it.TrimEnd('\', '/')
    if ([string]::IsNullOrWhiteSpace($itTrim)) { $itTrim = $it }
    $resolved = ""
    $found = $false
    try {
      if ([System.IO.Path]::IsPathRooted($itTrim) -and (Test-Path -LiteralPath $itTrim)) { $resolved = $itTrim; $found = $true }
    } catch { }
    if (-not $found -and -not [string]::IsNullOrWhiteSpace($StudioRootPath)) {
      try {
        $tryStudio = Join-Path $StudioRootPath $itTrim
        if (Test-Path -LiteralPath $tryStudio) { $resolved = $tryStudio; $found = $true }
      } catch { }
    }
    if (-not $found -and -not [string]::IsNullOrWhiteSpace($StudioRootPath)) {
      try {
        $siblingRoot = Split-Path -Parent $StudioRootPath
        if (-not [string]::IsNullOrWhiteSpace($siblingRoot)) {
          $trySibling = Join-Path $siblingRoot $itTrim
          if (Test-Path -LiteralPath $trySibling) { $resolved = $trySibling; $found = $true }
        }
      } catch { }
    }
    $tipo = ""
    $validExists = $false
    if ($found) {
      $isContainer = $false
      try { $isContainer = (Get-Item -LiteralPath $resolved -Force).PSIsContainer } catch { }
      if ($isContainer) {
        $tipo = "pasta"
        $childCount = 0
        try { $childCount = @(Get-ChildItem -LiteralPath $resolved -Force -ErrorAction SilentlyContinue).Count } catch { }
        $validExists = $childCount -gt 0
      } else {
        $tipo = "arquivo"
        $sz = 0
        try { $sz = (Get-Item -LiteralPath $resolved -Force).Length } catch { }
        $validExists = $sz -gt 0
      }
    } else {
      $resolved = if (-not [string]::IsNullOrWhiteSpace($StudioRootPath)) { Join-Path $StudioRootPath $itTrim } else { $itTrim }
    }
    $out.Add([PSCustomObject]@{ item = $it; isUrl = $false; tipo = $tipo; resolvedPath = $resolved; found = $found; exists = $validExists })
  }
  return $out.ToArray()
}

# _studio.ps1 - resolve a pasta de dados (o "studio") a partir do alia.config.json.
# O engine nunca crava "studio/": le o caminho do campo studio_dir na config.
#   studio_dir = "."       => os dados ficam na RAIZ da instalacao (ao lado do engine).
#   studio_dir = "studio"  => os dados ficam numa subpasta (padrao do produto / lab).
# Default "studio" quando a config nao existe ou nao traz o campo.
function Get-StudioRoot {
  param([Parameter(Mandatory = $true)][string]$Root)
  $studioDir = "studio"
  $cfgPath = Join-Path $Root "alia.config.json"
  if (Test-Path -LiteralPath $cfgPath) {
    try {
      $cfg = [System.IO.File]::ReadAllText($cfgPath) | ConvertFrom-Json
      $val = "$($cfg.studio_dir)".Trim()
      if ($val -ne "") { $studioDir = $val }
    } catch {}
  }
  if ($studioDir -eq "." -or $studioDir -eq "./" -or $studioDir -eq ".\") { return $Root }
  return (Join-Path $Root $studioDir)
}

# --- Estado do Client (OPP-77) ----------------------------------------------------------------
# Um Client nao e so "existe/nao existe": ele tem ESTADO no registro (state.json, clients[].state).
#   ativo      operacao viva. Cobra tudo (squad, mapa de conhecimento, Tasks com linhagem).
#   pontual    ideia tocada uma vez / experimento. NAO cobra squad nem mapa; aparece como informacao.
#   arquivado  encerrado. Sai das cobrancas e do painel do dia a dia; historico e Tasks intactos.
# COMPATIBILIDADE (regra dura): Client SEM estado declarado = ativo. Nenhuma migracao e forcada e
# nenhum registro antigo quebra. Valor desconhecido tambem cai em ativo - na duvida, COBRA (quem
# valida o valor no ato da escrita e o scripts/client-state.ps1; o smoke reprova valor invalido).
$ALIA_CLIENT_STATES = @("ativo", "pontual", "arquivado")

function Get-ClientStates {
  param([Parameter(Mandatory = $true)][string]$StateFile)
  $map = @{}
  if (-not (Test-Path -LiteralPath $StateFile)) { return $map }
  $st = $null
  try { $st = [System.IO.File]::ReadAllText($StateFile) | ConvertFrom-Json } catch { return $map }
  if ($null -eq $st) { return $map }
  if (-not (($st.PSObject.Properties.Name) -contains 'clients')) { return $map }
  foreach ($c in @($st.clients)) {
    $id = "$($c.id)"
    if ($id -eq "") { continue }
    $s = ""
    if (($c.PSObject.Properties.Name) -contains 'state') { $s = "$($c.state)".Trim().ToLower() }
    if ($ALIA_CLIENT_STATES -notcontains $s) { $s = "ativo" }
    $map[$id] = $s
  }
  return $map
}

function Get-ClientStateOf {
  param($Map, [string]$Id)
  if (($null -ne $Map) -and ($Map.Count -gt 0) -and ($Map.ContainsKey($Id))) { return $Map[$Id] }
  return "ativo"
}

# --- Custo automatico do transcript (TASK-569) -----------------------------------------------
# Le usage (input_tokens + cache_creation_input_tokens + cache_read_input_tokens + output_tokens)
# de mensagens "message.usage", deduplicando por message.id, e conta blocos "type":"tool_use" em
# message.content. Prefere subagents/agent-*.jsonl (sessao com sub-agentes); sem sub-agentes,
# mede o transcript principal <session>.jsonl. Fonte unica reusada por register-task.ps1 (e por
# quem mais precisar) - cost-sensor.ps1/cost-per-artifact.ps1 usam proxy de MB, nao usage, entao
# nao havia parser de usage pra extrair antes deste ponto.
function Measure-TranscriptFile {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.HashSet[string]]$SeenIds,
    [Parameter(Mandatory = $true)][ref]$TokensSum,
    [Parameter(Mandatory = $true)][ref]$ToolUseCount
  )
  if (-not (Test-Path -LiteralPath $Path)) { return }
  $lines = [System.IO.File]::ReadAllLines($Path)
  foreach ($line in $lines) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $obj = $null
    try { $obj = $line | ConvertFrom-Json } catch { continue }
    $msg = $obj.message
    if ($null -eq $msg) { continue }
    $mid = "$($msg.id)"
    if ($null -ne $msg.usage) {
      if ($mid -eq "" -or -not $SeenIds.Contains($mid)) {
        if ($mid -ne "") { [void]$SeenIds.Add($mid) }
        $u = $msg.usage
        $t = 0
        if ($u.input_tokens) { $t += [int]$u.input_tokens }
        if ($u.cache_creation_input_tokens) { $t += [int]$u.cache_creation_input_tokens }
        if ($u.cache_read_input_tokens) { $t += [int]$u.cache_read_input_tokens }
        if ($u.output_tokens) { $t += [int]$u.output_tokens }
        $TokensSum.Value += $t
      }
    }
    if ($msg.content) {
      foreach ($blk in @($msg.content)) {
        if ("$($blk.type)" -eq "tool_use") { $ToolUseCount.Value++ }
      }
    }
  }
}

function Get-TranscriptUsage {
  param(
    [string]$ProjectsDir = "",
    [string]$Slug = "",
    [string]$SessionId = ""
  )
  $result = [pscustomobject]@{ tokens = 0; tool_uses = 0; source = "indisponivel" }
  if ([string]::IsNullOrWhiteSpace($SessionId)) { return $result }
  if ([string]::IsNullOrWhiteSpace($ProjectsDir)) { $ProjectsDir = Join-Path $env:USERPROFILE ".claude/projects" }
  if ([string]::IsNullOrWhiteSpace($Slug)) { $Slug = ($PWD.Path -replace '[^a-zA-Z0-9]', '-') }
  $sessDir = Join-Path $ProjectsDir $Slug
  $subDir = Join-Path $sessDir (Join-Path $SessionId "subagents")
  $seen = New-Object System.Collections.Generic.HashSet[string]
  $tokensSum = 0
  $toolCount = 0
  $found = $false
  if (Test-Path -LiteralPath $subDir) {
    $subFiles = Get-ChildItem -LiteralPath $subDir -Filter "agent-*.jsonl" -File -ErrorAction SilentlyContinue
    if (@($subFiles).Count -gt 0) {
      $found = $true
      foreach ($f in $subFiles) {
        Measure-TranscriptFile -Path $f.FullName -SeenIds $seen -TokensSum ([ref]$tokensSum) -ToolUseCount ([ref]$toolCount)
      }
    }
  }
  if (-not $found) {
    $mainFile = Join-Path $sessDir ($SessionId + ".jsonl")
    if (Test-Path -LiteralPath $mainFile) {
      $found = $true
      Measure-TranscriptFile -Path $mainFile -SeenIds $seen -TokensSum ([ref]$tokensSum) -ToolUseCount ([ref]$toolCount)
    }
  }
  if ($found) {
    $result.tokens = $tokensSum
    $result.tool_uses = $toolCount
    $result.source = "auto-transcript"
  }
  return $result
}
