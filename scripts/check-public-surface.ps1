# check-public-surface.ps1 - a trava da LEI da superficie publica
# Reprova se arquivo de desenvolvimento estiver rastreado num repo git.
# Lei: engine/governance/public-surface.md (mandato do CEO, 01/08/2026)
# Uso:  .\check-public-surface.ps1 [-Repo <caminho>]
[CmdletBinding()]
param([string]$Repo = ".")

$ErrorActionPreference = "Stop"
$fail = 0
$warn = 0

function Bad($msg)  { Write-Host "[FAIL] $msg" -ForegroundColor Red;    $script:fail++ }
function Ok($msg)   { Write-Host "[PASS] $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "[WARN] $msg" -ForegroundColor Yellow; $script:warn++ }

Push-Location $Repo
try {
    $inside = ""
    try { $inside = (& git rev-parse --is-inside-work-tree 2>&1 | Out-String).Trim() } catch { $inside = "" }
    if ($inside -ne "true") {
        Write-Host "Nao e repositorio git: $Repo - nada a conferir (correto para a oficina)."
        exit 0
    }

    $repoRaiz = (& git rev-parse --show-toplevel).Trim()
    Write-Host ""
    Write-Host "=== Superficie publica: $repoRaiz ===" -ForegroundColor Cyan
    Write-Host ""

    $arquivos = & git ls-files

    # ---- (1) categorias proibidas no git ----
    # padrao -> motivo. studio.example/ e o cliente de EXEMPLO que ship: fica de fora do veto.
    $vetos = @(
        @{ p = '(^|/)brand/landing/';        m = 'landing page / arte de marca' },
        @{ p = '(^|/)docs/CLAIMS\.md$';      m = 'registro interno de claims' },
        @{ p = '(^|/)docs/BRAND\.md$';       m = 'marca interna' },
        @{ p = '(^|/)docs/product/';         m = 'PRD / roadmap / produto interno' },
        @{ p = '(^|/)docs/business/';        m = 'material de negocio' },
        @{ p = '(^|/)opportunities/';        m = 'backlog de oportunidades' },
        @{ p = '(^|/)research/';             m = 'pesquisa interna' },
        @{ p = '(^|/)_drafts/';              m = 'rascunho' },
        @{ p = '(^|/)_dev/';                 m = 'material de desenvolvimento' },
        @{ p = '(^|/)_candidatas/';          m = 'candidata de design' },
        @{ p = '(^|/)_backups/';             m = 'backup' },
        @{ p = '^PRODUCT\.md$';              m = 'contexto de produto (ferramenta de design)' },
        @{ p = '^DESIGN-.*\.md$';            m = 'sistema visual de trabalho' },
        @{ p = '^state\.json$';              m = 'estado operacional do studio' },
        @{ p = '^mission-control\.html$';    m = 'painel interno' },
        @{ p = '(^|/)memory/(?!.*examples)'; m = 'memoria da Alia' }
    )

    $vazou = @()
    foreach ($v in $vetos) {
        $hits = $arquivos | Where-Object {
            $_ -match $v.p -and $_ -notmatch '^studio\.example/'
        }
        foreach ($h in $hits) { $vazou += [pscustomobject]@{ arq = $h; motivo = $v.m } }
    }

    if ($vazou.Count -eq 0) {
        Ok "Nenhum arquivo de desenvolvimento rastreado"
    } else {
        foreach ($x in ($vazou | Sort-Object arq -Unique)) {
            Bad ("vazou: " + $x.arq + "  (" + $x.motivo + ")")
        }
    }

    # ---- (2) a oficina nao pode ter remoto ----
    $ehOficina = $repoRaiz -match 'alia-flow-lab'
    $remotos = @(& git remote)
    if ($ehOficina) {
        if ($remotos.Count -eq 0) { Ok "Oficina sem remoto (nao publica, por lei)" }
        else { Bad ("Oficina TEM remoto (" + ($remotos -join ", ") + ") - remova: git remote remove <nome>") }
    } else {
        if ($remotos.Count -gt 0) { Ok ("Repo publico com remoto: " + ($remotos -join ", ")) }
        else { Warn "Repo publico sem remoto configurado" }
    }

    # ---- (3) o .gitignore cobre as categorias? ----
    $gi = Join-Path $repoRaiz ".gitignore"
    if (Test-Path $gi) {
        $txt = Get-Content $gi -Raw
        foreach ($alvo in @("brand/landing", "opportunities", "docs/product")) {
            if ($txt -notmatch [regex]::Escape($alvo)) { Warn ".gitignore nao cobre: $alvo" }
        }
        if ($warn -eq 0) { Ok ".gitignore cobre as categorias principais" }
    } else {
        Warn "sem .gitignore"
    }

    Write-Host ""
    if ($fail -gt 0) {
        Write-Host "REPROVADO: $fail violacao(oes) da LEI da superficie publica." -ForegroundColor Red
        Write-Host "Ver engine/governance/public-surface.md" -ForegroundColor Red
        exit 1
    }
    Write-Host "SUPERFICIE LIMPA ($warn aviso(s))" -ForegroundColor Green
    exit 0
}
finally { Pop-Location }
