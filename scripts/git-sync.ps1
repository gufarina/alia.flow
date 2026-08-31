<#
  git-sync.ps1 - Commit + push SEM o usuario ter git instalado (OPP-72).
  Salva/versiona uma pasta (por padrao o studio do operador) num repositorio do GitHub usando SO a
  API HTTPS do GitHub (Invoke-RestMethod, ja vem no Windows) - nenhum git.exe, nenhuma dependencia.

  Por que assim: o publico do Alia Flow nao e tecnico e pode nao ter git. "Fazer backup / versionar o
  meu trabalho na nuvem" tem que ser um botao, nao um tutorial de git. A API Git Data do GitHub faz
  um commit atomico de varios arquivos (blobs -> tree -> commit -> move o branch) so com um token.

  Autenticacao (uma vez): um token do GitHub (fine-grained, permissao Contents: Read and write no
  repo alvo). Vem por -Token, ou pela variavel de ambiente ALIA_GH_TOKEN, ou por
  %LOCALAPPDATA%\Alia\gh-token.txt (o launcher guarda ali). Nunca e impresso nem commitado.

  Uso:
    powershell -ExecutionPolicy Bypass -File scripts/git-sync.ps1 -Repo "usuario/meu-backup" `
      [-Path <pasta>] [-Branch main] [-Message "..."] [-Token <tk>] [-DryRun]

  -DryRun: valida entradas e LISTA o que seria enviado, sem chamar a API (prova segura sem token).
  Sem acentos, sem emojis. UTF-8 sem BOM. exit 0 sucesso, 1 erro (com motivo claro).
#>
param(
  [Parameter(Mandatory=$true)][string]$Repo,          # "owner/repo"
  [string]$Path = "",                                  # pasta a versionar (default: studio da instancia)
  [string]$Branch = "main",
  [string]$Message = "",
  [string]$Token = "",
  [int]$MaxFiles = 2000,
  [switch]$DryRun
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

# --- Pasta alvo: default = studio do operador (studio_dir do alia.config.json), senao a raiz ---
# Valida o ARGUMENTO (-Repo) antes de tocar em pasta: input malformado se rejeita antes de
# qualquer efeito de ambiente (a pasta studio existe na instancia mas nao no pacote publico -
# validar pasta primeiro dava mensagem errada conforme o contexto).
if ($Repo -notmatch '^[^/]+/[^/]+$') { Write-Host "[ERRO] -Repo deve ser 'owner/repo'."; exit 1 }
if ([string]::IsNullOrWhiteSpace($Path)) {
  $sd = "studio"
  $cfg = Join-Path $root "alia.config.json"
  if (Test-Path $cfg) { try { $sd = (Get-Content $cfg -Raw | ConvertFrom-Json).studio_dir } catch {} }
  if ($sd -eq "." -or [string]::IsNullOrWhiteSpace($sd)) { $Path = $root } else { $Path = Join-Path $root $sd }
}
if (-not (Test-Path -LiteralPath $Path)) { Write-Host ("[ERRO] pasta nao encontrada: " + $Path); exit 1 }
# CONSERTO (code review adversarial, 31/08/2026 - VAZAMENTO DE CAMINHO REAL, MEDIDO): o caminho
# de cada arquivo dentro do commit era calculado por `$_.FullName.Substring($Path.Length)`. Com
# -Path relativo (ex.: "." ou "..\pasta"), $Path.Length NAO corresponde ao prefixo do FullName
# absoluto que o Get-ChildItem devolve - o corte cai no meio do caminho ABSOLUTO e o que vai pro
# repositorio publico e ":\Users\<usuario>\Projetos\..." (medido em -DryRun). Ou seja: o nome de
# usuario do Windows do operador viajava pra dentro de um repo publico, e os caminhos do commit
# saiam quebrados. Resolver o alvo pra caminho COMPLETO uma unica vez conserta os dois males, e
# esta e a mesma classe de vazamento que o guard de caminho absoluto do package-release.ps1 ja
# reprova no pacote - aqui ninguem estava olhando.
$Path = (Resolve-Path -LiteralPath $Path).ProviderPath.TrimEnd('\', '/')
if ([string]::IsNullOrWhiteSpace($Message)) { $Message = "Alia: backup do studio" }

# --- Coleta de arquivos (ignora lixo/segredo; nunca envia o token nem .git) ---
$ignore = @('\.git[\\/]', 'node_modules[\\/]', 'gh-token\.txt$', '\.env$')
$all = Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
  $rel = $_.FullName.Substring($Path.Length).TrimStart('\','/')
  $skip = $false; foreach ($pat in $ignore) { if ($rel -match $pat) { $skip = $true; break } }
  -not $skip
}
if ($all.Count -gt $MaxFiles) { Write-Host ("[ERRO] " + $all.Count + " arquivos > teto " + $MaxFiles + " (use -MaxFiles ou aponte uma pasta menor)."); exit 1 }

Write-Host ("=== git-sync (sem git) -> " + $Repo + " [" + $Branch + "] ===")
Write-Host ("pasta:    " + $Path)
Write-Host ("arquivos: " + $all.Count)
Write-Host ("mensagem: " + $Message)

if ($DryRun) {
  Write-Host "modo: DRY-RUN (nada enviado). Amostra do que iria:"
  $all | Select-Object -First 12 | ForEach-Object { Write-Host ("  + " + $_.FullName.Substring($Path.Length).TrimStart('\','/')) }
  if ($all.Count -gt 12) { Write-Host ("  ... e mais " + ($all.Count - 12)) }
  Write-Host "[DRY-RUN OK] entradas validas. Com -Token (ou ALIA_GH_TOKEN), isto faria 1 commit atomico via API."
  exit 0
}

# --- Token (uma vez) ---
if ([string]::IsNullOrWhiteSpace($Token)) { $Token = $env:ALIA_GH_TOKEN }
if ([string]::IsNullOrWhiteSpace($Token)) {
  $tf = Join-Path $env:LOCALAPPDATA "Alia\gh-token.txt"
  if (Test-Path $tf) { $Token = (Get-Content $tf -Raw).Trim() }
}
if ([string]::IsNullOrWhiteSpace($Token)) {
  Write-Host "[ERRO] sem token do GitHub. Passe -Token, defina ALIA_GH_TOKEN, ou salve em %LOCALAPPDATA%\Alia\gh-token.txt."
  Write-Host "       Crie um fine-grained token com Contents: Read and write no repo alvo."
  exit 1
}

$api = "https://api.github.com"
$headers = @{ Authorization = ("Bearer " + $Token); "User-Agent" = "alia-flow"; Accept = "application/vnd.github+json" }
function Gh($method, $url, $body) {
  $args = @{ Method = $method; Uri = ($api + $url); Headers = $headers }
  if ($null -ne $body) { $args.Body = ($body | ConvertTo-Json -Depth 6 -Compress); $args.ContentType = "application/json" }
  return Invoke-RestMethod @args
}

try {
  # 1) branch atual (ou cria do default se nao existir)
  $baseSha = $null; $baseTree = $null
  try {
    $ref = Gh GET ("/repos/$Repo/git/ref/heads/$Branch") $null
    $baseSha = $ref.object.sha
    $baseCommit = Gh GET ("/repos/$Repo/git/commits/$baseSha") $null
    $baseTree = $baseCommit.tree.sha
  } catch {
    Write-Host ("  branch '" + $Branch + "' novo (primeiro commit)")
  }

  # 2) blob por arquivo (base64)
  Write-Host "enviando arquivos (blobs)..."
  $tree = @()
  foreach ($f in $all) {
    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
    $b64 = [System.Convert]::ToBase64String($bytes)
    $blob = Gh POST ("/repos/$Repo/git/blobs") @{ content = $b64; encoding = "base64" }
    $rel = ($f.FullName.Substring($Path.Length).TrimStart('\','/')) -replace '\\','/'
    $tree += @{ path = $rel; mode = "100644"; type = "blob"; sha = $blob.sha }
  }

  # 3) tree -> 4) commit -> 5) move o branch
  $treeBody = @{ tree = $tree }
  if ($baseTree) { $treeBody.base_tree = $baseTree }
  $newTree = Gh POST ("/repos/$Repo/git/trees") $treeBody
  $commitBody = @{ message = $Message; tree = $newTree.sha }
  if ($baseSha) { $commitBody.parents = @($baseSha) }
  $newCommit = Gh POST ("/repos/$Repo/git/commits") $commitBody

  if ($baseSha) {
    Gh PATCH ("/repos/$Repo/git/refs/heads/$Branch") @{ sha = $newCommit.sha; force = $false } | Out-Null
  } else {
    Gh POST ("/repos/$Repo/git/refs") @{ ref = ("refs/heads/" + $Branch); sha = $newCommit.sha } | Out-Null
  }

  Write-Host ("[OK] commit " + $newCommit.sha.Substring(0,7) + " enviado para " + $Repo + " (" + $Branch + "). Seu trabalho esta salvo na nuvem.")
  exit 0
} catch {
  Write-Host ("[ERRO] falha ao sincronizar: " + $_.Exception.Message)
  Write-Host "       Confira o token (Contents: Read and write) e o nome do repo."
  exit 1
}
