<#
  ensure-graphify.ps1 - garante o motor de mapa de conhecimento (graphify) disponivel nesta
  maquina, sem NUNCA expor Python/pip/uv/pacote/nome de comando ao operador. Mandato do CEO
  (10/08/2026): o graphify deixa de ser "turbo opcional" e vira REQUISITO da instalacao - o mapa
  e o que torna a operacao barata e estavel (varrer as cegas gasta muito mais token do que
  consultar um mapa pronto). O operador e leigo, nunca programou - quem chama este script
  (scripts/install.ps1 e/ou skills/setup-alia) repassa a UNICA frase pronta que ele imprime,
  nunca inventa a propria nem cita o mecanismo.

  VERSAO FIXA DO PACOTE (conserto 11/08/2026 - antes instalava "o que vier", sem trava nenhuma).
  $GraphifyyPinnedVersion abaixo e a UNICA linha que muda quando a casa decidir atualizar - medida
  nesta maquina com "python -m pip show graphifyy" no dia do conserto (Version: 0.4.23). Instalar
  sempre a mesma versao conhecida-boa evita que uma release nova do pacote (fora do controle da
  casa) quebre silenciosamente uma maquina nova. Se a versao fixa sumiu do indice (nunca aconteceu
  ainda, mas pacote de terceiro pode remover release) o script DEGRADA para a mais recente
  disponivel, MAS avisa (rota "uv-latest-fallback" / "pip-latest-fallback" no -StatusPath) -
  degradar avisando e melhor que falhar em silencio; nunca deixa de tentar instalar por causa da
  trava de versao.

  ORDEM DE TENTATIVA (fail-soft - NUNCA trava o primeiro contato, so PREPARA):
    (a) ja disponivel?     -> "python -m graphify --help" funciona -> nao faz nada (nao reinstala
                               so pra bater a versao fixa - maquina que ja funciona fica quieta).
    (b) uv disponivel?     -> rota PREFERIDA: uv garante o interpretador sozinho (uv python
                               install) e instala o pacote FIXO nele (uv pip install --python
                               ...==$GraphifyyPinnedVersion); versao fixa falhou -> tenta de novo
                               sem pin (mais recente) e avisa no -StatusPath.
    (c) so python (sem uv)?-> instala pelo pip do proprio python (rota antiga, ainda funciona),
                               mesma logica de pin com fallback avisado.
    (d) nada disponivel?   -> baixa o uv (binario unico, sem dependencia) e volta ao passo (b).
    (e) tudo falhou        -> registra o estado em -StatusPath, imprime UMA frase de leigo
                               explicando o que ficou faltando, e SEGUE (nunca bloqueia o resto).

  CONTRATO: sempre exit 0. Todo o corpo roda dentro de um unico try/catch - erro interno vira
  passo (e), nunca trava quem chamou. Console so recebe a frase de leigo no caminho de falha
  total; sucesso (a-d) e silencioso de proposito (mesmo padrao da memoria nativa: "liga e pronto,
  sem anunciar"). Estado detalhado (rota usada, motivo) fica SO em -StatusPath (JSON), nunca no
  console - quem chama pode ler o arquivo se precisar de detalhe, o operador nunca ve o JSON. UTF-8 sem BOM.
#>
param(
  [string]$StatusPath = "",
  [string]$UvInstallUrl = "https://astral.sh/uv/install.ps1"
)

# Versao conhecida-boa do pacote graphifyy - troque SO esta linha quando a casa decidir atualizar.
# Medida nesta maquina em 11/08/2026 via "python -m pip show graphifyy".
$GraphifyyPinnedVersion = "0.4.23"

$root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($StatusPath)) {
  $StatusPath = Join-Path (Join-Path $root "studio") "graphify-setup-status.json"
}

function Write-GraphifyStatus([bool]$Ready, [string]$Route, [string]$Reason) {
  try {
    $dir = Split-Path -Parent $StatusPath
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -LiteralPath $dir)) {
      New-Item -ItemType Directory -Force -Path $dir -ErrorAction SilentlyContinue | Out-Null
    }
    $obj = [ordered]@{
      ready  = $Ready
      route  = $Route
      reason = $Reason
      ts     = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    }
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($StatusPath, ($obj | ConvertTo-Json -Compress), $utf8NoBom)
  } catch { }
}

# Invocacao de executavel nativo via Start-Process (nao o operador "&"): medido nesta mesma
# sessao que, numa maquina com ambiente minimo/restrito (o caso real de quem nunca configurou
# nada), o operador "&" pode devolver saida vazia e LASTEXITCODE vazio SEM erro nenhum - Start-
# Process com redirecionamento de stdout/stderr para arquivo e o jeito que realmente funciona
# nesse cenario (prova pelo negativo rodada em ambiente isolado antes deste conserto entrar).
function Invoke-Native([string]$FilePath, [string[]]$ArgList) {
  # Argumentos viram UMA string com aspas manuais (nao o array direto): medido que -ArgumentList
  # com array nao cota de forma confiavel elementos com espaco (ex: caminho embaixo de
  # "%USERPROFILE% com espaco no nome") no PowerShell 5.1 - o espaco corta o argumento ao meio e quebra o
  # comando (prova pelo negativo rodada em ambiente isolado antes deste conserto entrar).
  $argStr = ($ArgList | ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' }) -join ' '
  $outFile = [System.IO.Path]::GetTempFileName()
  $errFile = [System.IO.Path]::GetTempFileName()
  try {
    $p = Start-Process -FilePath $FilePath -ArgumentList $argStr -NoNewWindow -Wait -PassThru `
         -RedirectStandardOutput $outFile -RedirectStandardError $errFile -ErrorAction Stop
    $stdout = ""
    try { $stdout = (Get-Content -LiteralPath $outFile -Raw -ErrorAction SilentlyContinue) } catch { }
    return [pscustomobject]@{ ExitCode = $p.ExitCode; StdOut = $stdout }
  } catch {
    return [pscustomobject]@{ ExitCode = 1; StdOut = "" }
  } finally {
    Remove-Item -LiteralPath $outFile, $errFile -Force -ErrorAction SilentlyContinue
  }
}

function Test-GraphifyReady {
  $r = Invoke-Native "python" @("-m", "graphify", "--help")
  return ($r.ExitCode -eq 0)
}

# Rota (b)/(d): dado um uv.exe (ja no PATH ou recem-baixado), garante um Python + o pacote nele,
# e deixa a pasta desse interpretador (e a pasta de shims do uv) visiveis para ESTE processo -
# uma sessao NOVA ja enxerga isso pelo PATH persistente que o proprio instalador do uv grava.
$script:UsedFallbackVersion = $false

function Install-ViaUv([string]$Uv) {
  # --break-system-packages: python gerenciado pelo uv se recusa a instalar pacote direto nele
  # sem essa flag (protecao PEP 668) - medido nesta sessao (erro "externally managed").
  [void] (Invoke-Native $Uv @("python", "install", "3.12", "--default"))
  $found = Invoke-Native $Uv @("python", "find", "3.12")
  $py312 = ""
  if ($found.ExitCode -eq 0) { $py312 = ($found.StdOut -split "`r?`n" | Where-Object { $_ -ne "" } | Select-Object -First 1) }
  if (-not [string]::IsNullOrWhiteSpace($py312) -and (Test-Path -LiteralPath $py312)) {
    $pinnedSpec = "graphifyy==" + $GraphifyyPinnedVersion
    # Ate 2 tentativas COM a versao fixa: medido nesta sessao que a criacao de pasta de um pacote
    # (tree-sitter-*) pode falhar por instantes com "ja existe" (antivirus/indexador prendendo o
    # arquivo por um momento) - erro transitorio, some numa segunda tentativa. Nunca repete mais
    # que isso (erro e sinal, nao parede - regra da casa em engine/tools.md).
    $pipResult = $null
    for ($i = 0; $i -lt 2; $i++) {
      $pipResult = Invoke-Native $Uv @("pip", "install", "--python", $py312, "--break-system-packages", "-q", $pinnedSpec)
      if ($pipResult.ExitCode -eq 0) { break }
      Start-Sleep -Milliseconds 500
    }
    # Versao fixa falhou (ex: sumiu do indice) -> degrada para a mais recente, MAS avisa no status.
    if ($pipResult.ExitCode -ne 0) {
      $pipResult = Invoke-Native $Uv @("pip", "install", "--python", $py312, "--break-system-packages", "-q", "graphifyy")
      if ($pipResult.ExitCode -eq 0) { $script:UsedFallbackVersion = $true }
    }
    $pyDir = Split-Path -Parent $py312
    if (Test-Path -LiteralPath $pyDir) { $env:PATH = $pyDir + [System.IO.Path]::PathSeparator + $env:PATH }
  }
  $localBin = Join-Path $env:USERPROFILE ".local\bin"
  if (Test-Path -LiteralPath $localBin) { $env:PATH = $localBin + [System.IO.Path]::PathSeparator + $env:PATH }
}

try {
  # (a) ja disponivel - nao faz nada, sem anunciar (mesmo padrao da memoria nativa).
  if (Test-GraphifyReady) {
    Write-GraphifyStatus $true "already" "ja disponivel nesta maquina"
    exit 0
  }

  $uvCmd = Get-Command uv -ErrorAction SilentlyContinue
  $uvExe = if ($uvCmd) { $uvCmd.Source } else { $null }

  # (b) uv ja disponivel - rota preferida.
  if ($uvExe) {
    Install-ViaUv $uvExe
    if (Test-GraphifyReady) {
      $rota = if ($script:UsedFallbackVersion) { "python + graphify garantidos via uv (versao fixa " + $GraphifyyPinnedVersion + " indisponivel, caiu para a mais recente)" } else { "python + graphify " + $GraphifyyPinnedVersion + " garantidos via uv" }
      Write-GraphifyStatus $true "uv" $rota
      exit 0
    }
  }

  # (c) so python, sem uv - instala pelo pip do proprio python (rota antiga), mesma trava de
  # versao fixa com fallback avisado.
  $pyCmd = Get-Command python -ErrorAction SilentlyContinue
  if ($pyCmd) {
    $pipPinned = Invoke-Native "python" @("-m", "pip", "install", "--user", "-q", ("graphifyy==" + $GraphifyyPinnedVersion))
    $usouFallbackPip = $false
    if ($pipPinned.ExitCode -ne 0) {
      [void] (Invoke-Native "python" @("-m", "pip", "install", "--user", "-q", "graphifyy"))
      $usouFallbackPip = $true
    }
    if (Test-GraphifyReady) {
      $rota = if ($usouFallbackPip) { "instalado no python ja existente (versao fixa " + $GraphifyyPinnedVersion + " indisponivel, caiu para a mais recente)" } else { "instalado no python ja existente (versao " + $GraphifyyPinnedVersion + ")" }
      Write-GraphifyStatus $true "pip" $rota
      exit 0
    }
  }

  # (d) nada disponivel - baixa o uv (binario unico, sem dependencia) e volta ao passo (b).
  if (-not $uvExe) {
    try {
      $installScript = Invoke-RestMethod -Uri $UvInstallUrl -TimeoutSec 20 -UseBasicParsing
      Invoke-Expression $installScript *> $null
    } catch { }
    $uvCmd2 = Get-Command uv -ErrorAction SilentlyContinue
    $uvExe2 = $null
    if ($uvCmd2) { $uvExe2 = $uvCmd2.Source }
    else {
      $cand = Join-Path $env:USERPROFILE ".local\bin\uv.exe"
      if (Test-Path -LiteralPath $cand) { $uvExe2 = $cand }
    }
    if ($uvExe2) {
      Install-ViaUv $uvExe2
      if (Test-GraphifyReady) {
        $rota = if ($script:UsedFallbackVersion) { "uv instalado agora, python + graphify atras dele (versao fixa " + $GraphifyyPinnedVersion + " indisponivel, caiu para a mais recente)" } else { "uv instalado agora, python + graphify " + $GraphifyyPinnedVersion + " atras dele" }
        Write-GraphifyStatus $true "uv-bootstrap" $rota
        exit 0
      }
    }
  }

  # (e) tudo falhou - NUNCA trava o operador; registra e explica em uma frase de leigo.
  Write-GraphifyStatus $false "none" "sem forma de preparar o mapa nesta maquina agora"
  Write-Host "Nao consegui preparar o mapa de conhecimento agora - vou continuar te ajudando normalmente, so que revirando os arquivos do seu projeto na mao (mais lento e mais caro); posso tentar de novo mais tarde."
  exit 0
} catch {
  try { Write-GraphifyStatus $false "erro" ("erro interno: " + $_.Exception.Message) } catch { }
  exit 0
}
