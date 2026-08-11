# _studio.ps1 - resolve a pasta de dados (o "studio") a partir do alia.config.json.
# O engine nunca crava "studio/": le o caminho do campo studio_dir na config.
#   studio_dir = "."       => os dados ficam na RAIZ da instalacao (ao lado do engine).
#   studio_dir = "studio"  => os dados ficam numa subpasta (padrao do produto / lab).
# Default "studio" quando a config nao existe ou nao traz o campo. Sem acentos, sem emojis.
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
