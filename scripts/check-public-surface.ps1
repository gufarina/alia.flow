# check-public-surface.ps1 - a trava da LEI da superficie publica
# Reprova se arquivo de desenvolvimento estiver presente na superficie publica.
# Lei: engine/governance/public-surface.md (mandato do CEO, 01/08/2026)
# Uso:  .\check-public-surface.ps1 [-Repo <caminho>]
#
# CONSERTO (auditoria forense, defeito 5): a oficina (clients/alia-flow-lab) NAO E repositorio git
# por LEI - "sai exit 0 sem inspecionar nada quando a pasta nao e git" fazia a condicao de falha
# ser IMPOSSIVEL nos dois unicos lugares onde este script se aplica de verdade (a propria oficina,
# e o estagio de propagacao clients/alia-flow-lab/release/alia-flow que tambem nao e git). Agora o
# script inspeciona por CAMINHO/CONTEUDO em disco quando nao ha git (sem "tudo certo" as cegas);
# so sai com erro se nao conseguir nem enumerar arquivos (pasta inexistente).
[CmdletBinding()]
param([string]$Repo = ".", [string[]]$OnlyPaths = @())

$ErrorActionPreference = "Stop"
$fail = 0
$warn = 0

function Bad($msg)  { Write-Host "[FAIL] $msg" -ForegroundColor Red;    $script:fail++ }
function Ok($msg)   { Write-Host "[PASS] $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "[WARN] $msg" -ForegroundColor Yellow; $script:warn++ }

# Le os Clients REAIS do operador (10/08/2026, achado de vazamento de identidade). A lista NUNCA
# e cravada aqui - cada operador tem clientes diferentes, e este script e do produto (ship pra
# qualquer instalacao). Sobe a arvore de pastas a partir de ONDE ESTE SCRIPT VIVE (nao de -Repo,
# que e so o alvo da varredura) procurando alia.config.json; le studio_dir e o state.json de la.
# Continua subindo ate o topo: se houver mais de um alia.config.json na ascendencia (ex.: a
# oficina clients/alia-flow-lab tem o seu proprio, dogfood, ANINHADO dentro da instancia real
# studio-farina), o ANCESTRAL MAIS EXTERNO com Clients de verdade vence - e o que representa a
# operacao real do operador, nao o dogfood interno do motor. Sem alia.config.json/state.json em
# nenhum ancestral (instalacao limpa, isolada) -> lista vazia, o check de identidade e pulado.
# Retorna [pscustomobject]@{ Ids = <lista de Client id>; StudioName = <nome do studio> }. O
# StudioName (campo "studio" do MESMO alia.config.json que resolveu os Ids) serve pro chamador
# distinguir "nome do proprio estudio" (self-reference, sempre legitima em README/CHANGELOG/
# engine) de "nome de Client" que por acaso compartilhe uma das palavras do nome do estudio -
# sem cravar nenhuma palavra de operador especifico aqui, o nome do estudio vem 100% do config.
function Find-OperatorClientIds {
    $dir = Split-Path -Parent $PSCommandPath
    if ([string]::IsNullOrWhiteSpace($dir)) { $dir = $PSScriptRoot }
    $ids = @()
    $studioName = ""
    for ($i = 0; $i -lt 12 -and $dir; $i++) {
        $cfgPath = Join-Path $dir "alia.config.json"
        if (Test-Path -LiteralPath $cfgPath) {
            try {
                $cfg = Get-Content -LiteralPath $cfgPath -Raw | ConvertFrom-Json
                $sdir = "$($cfg.studio_dir)"
                if ([string]::IsNullOrWhiteSpace($sdir)) { $sdir = "." }
                $statePath = Join-Path (Join-Path $dir $sdir) "state.json"
                if (Test-Path -LiteralPath $statePath) {
                    $st = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
                    # "alia-flow"/"alia-flow-lab" nunca conta como Client a proteger: e o proprio
                    # PRODUTO (a oficina se dogfooda como Client dela mesma) - o nome dele aparece
                    # de proposito em toda superficie publica (README, CHANGELOG, engine/...) e nao
                    # e identidade de cliente nenhuma. Sem esta exclusao o check reprova o pacote
                    # inteiro (medido: 399 "vazamentos" falsos numa primeira versao deste check).
                    $found = @($st.clients | ForEach-Object {
                        if ($_ -is [string]) { $_ } elseif ($_.id) { "$($_.id)" }
                    } | Where-Object { $_ -and $_ -notmatch '^alia-flow(-lab)?$' })
                    if ($found.Count -gt 0) { $ids = $found; $studioName = "$($cfg.studio)" }
                }
            } catch { }
        }
        $parent = Split-Path -Parent $dir
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $dir) { break }
        $dir = $parent
    }
    return [pscustomobject]@{ Ids = $ids; StudioName = $studioName }
}

Push-Location $Repo
try {
    $inside = ""
    try { $inside = (& git rev-parse --is-inside-work-tree 2>&1 | Out-String).Trim() } catch { $inside = "" }
    $ehGit = ($inside -eq "true")

    $repoRaiz = (Get-Location).Path
    $arquivos = @()
    if ($ehGit) {
        $repoRaiz = (& git rev-parse --show-toplevel).Trim()
        Write-Host ""
        Write-Host "=== Superficie publica (git): $repoRaiz ===" -ForegroundColor Cyan
        Write-Host ""
        $arquivos = & git ls-files
    } else {
        if (-not (Test-Path -LiteralPath $repoRaiz)) {
            Write-Host "[FAIL] Pasta nao existe: $repoRaiz - nao consigo conferir a superficie publica." -ForegroundColor Red
            exit 1
        }
        Write-Host ""
        Write-Host "=== Superficie publica (sem git, varredura em disco): $repoRaiz ===" -ForegroundColor Cyan
        Write-Host ""
        $sep = [IO.Path]::DirectorySeparatorChar
        $todos = Get-ChildItem -LiteralPath $repoRaiz -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' -and $_.FullName -notmatch '[\\/]node_modules[\\/]' }
        $arquivos = @($todos | ForEach-Object { $_.FullName.Substring($repoRaiz.Length).TrimStart('\','/').Replace('\','/') })
        if ($arquivos.Count -eq 0) {
            Write-Host "[FAIL] Nao consegui enumerar nenhum arquivo em $repoRaiz - nao consigo conferir a superficie publica." -ForegroundColor Red
            exit 1
        }
    }

    # CONSERTO (TASK-285, ultima volta): -OnlyPaths restringe a varredura a um subconjunto de
    # arquivos (prefixos relativos), pensado para rodar CEDO - dentro do smoke da OFICINA, contra
    # os proprios arquivos vivos (CHANGELOG.md, release-reviews/), antes de qualquer empacotamento.
    # Sem isto o unico jeito de flagar vazamento de identidade era escanear o pacote JA GERADO
    # (release/alia-flow) ou o repo git publico - tarde demais pra pegar no ATO de escrever o
    # CHANGELOG, e escanear a oficina INTEIRA sem filtro da 300+ falso-positivo (doc interno,
    # squad/, opportunities/, release-reviews historico - todos citam Client real legitimamente).
    if ($OnlyPaths.Count -gt 0) {
        $arquivos = @($arquivos | Where-Object {
            $rel = $_
            [bool]($OnlyPaths | Where-Object { $rel -eq $_ -or $rel.StartsWith($_ + '/') })
        })
        Write-Host ("[INFO] Escopo restrito a -OnlyPaths (" + ($OnlyPaths -join ", ") + "): " + $arquivos.Count + " arquivo(s) na varredura")
    }

    # ---- (1) categorias proibidas no git ----
    # padrao -> motivo. studio.example/ e o cliente de EXEMPLO que ship: fica de fora do veto.
    # Lista ampliada em 10/08/2026 (mandato do CEO: doc de produto e "exclusiva nossa, jamais
    # vazando") para cobrir TUDO que engine/governance/public-surface.md enumera + o achado da
    # auditoria de superficie do mesmo dia. Cada veto novo tem o motivo do porque e interno.
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
        @{ p = '(^|/)memory/(?!.*examples)'; m = 'memoria da Alia' },
        @{ p = '(^|/)\.claude/agents/';      m = 'agente de especialista de cliente (squad-bridge) vazado para a superficie publica' },
        # --- ampliacao 10/08/2026 ---
        @{ p = '(^|/)docs/CAPACIDADE-REAL\.md$'; m = 'numero interno de capacidade (nao aprovado para peca publica)' },
        @{ p = '(^|/)docs/RELEASE-STATUS\.md$';  m = 'relatorio de drift oficina/staging/publico, cita caminho da maquina do dono' },
        @{ p = '(?i)(^|/)PRD(\.md)?(/|$)';       m = 'PRD (documento de produto interno)' },
        @{ p = '(?i)(^|/)roadmap';               m = 'roadmap interno (qualquer arquivo/pasta com "roadmap" no caminho)' },
        @{ p = '(^|/)preview/';                  m = 'preview de peca/design ainda nao aprovada' },
        @{ p = '(^|/)landing/';                  m = 'landing page (qualquer landing/, nao so brand/landing/)' },
        @{ p = '(^|/)brand/';                    m = 'IP de marca/sistema visual do dono (qualquer brand/, nao so docs/BRAND.md)' },
        @{ p = '(^|/)clients/';                  m = 'material de cliente (Cliente-Projeto-Tarefa) - cliente nunca toca em repo publico' },
        # scripts amarrados A INSTANCIA/OFICINA, nao ao motor (defesa em profundidade - a protecao
        # de primeira linha e o allowlist de scripts/ em package-release.ps1; este veto pega o caso
        # de o arquivo ja estar rastreado no git publico de antes, ou de alguem commitar direto).
        @{ p = '(^|/)scripts/smoke-test-studio\.ps1$'; m = 'smoke DA INSTANCIA Studio Farina, nao do motor (o smoke do motor e scripts/smoke-test.ps1)' },
        @{ p = '(^|/)scripts/migrate-to-studio\.ps1$'; m = 'migracao unica do sistema legado do dono (caminhos da maquina dele)' },
        @{ p = '(^|/)scripts/extract-secrets\.ps1$';   m = 'migracao unica do sistema legado do dono (segredos)' }
    )

    $vazou = @()
    foreach ($v in $vetos) {
        $hits = $arquivos | Where-Object {
            $_ -match $v.p -and $_ -notmatch '^studio\.example/'
        }
        foreach ($h in $hits) { $vazou += [pscustomobject]@{ arq = $h; motivo = $v.m } }
    }

    if ($vazou.Count -eq 0) {
        Ok ("Nenhum arquivo de desenvolvimento " + $(if ($ehGit) { "rastreado" } else { "presente em disco" }) + " (" + $arquivos.Count + " arquivo(s) conferido(s))")
    } else {
        foreach ($x in ($vazou | Sort-Object arq -Unique)) {
            Bad ("vazou: " + $x.arq + "  (" + $x.motivo + ")")
        }
    }

    # ---- (1.5) vazamento de IDENTIDADE de cliente real do operador (10/08/2026) ----
    # Diferente do veto (1) acima (que reprova CAMINHO): aqui o alvo e CONTEUDO - nome de Client
    # real citado como exemplo/fixture/incidente dentro de um arquivo que ship. O operador vende
    # para clientes que nao podem aparecer no produto que outra pessoa instala.
    $opClient = Find-OperatorClientIds
    $opClientIds = @($opClient.Ids)
    if ($opClientIds.Count -gt 0) {
        $idPattern = ($opClientIds | ForEach-Object { [regex]::Escape($_) }) -join '|'
        # \b sozinho conta HIFEN como fronteira de palavra (falso positivo medido 10/08/2026: o
        # nome REAL de um servidor MCP em .mcp.json/squad-bridge.ps1 tem o padrao
        # "<ferramenta>-<id-de-Client>", e \b<id>\b casava dentro dele - so um pedaco de outro
        # identificador, nao a identidade do Client). Fronteira de IDENTIDADE nao pode ser hifen
        # nem underscore: exige lookaround negativo pros dois (\w cobre letra/digito/underscore; o
        # hifen entra a parte). Isto ainda pega a mencao ISOLADA ao Client em prosa/caminho
        # (ex.: "clients/<id>/", "-Client <id>", "o cliente <id>" - espaco/barra/pontuacao
        # continuam fronteira valida) - so exclui o caso em que o id e PEDACO de um identificador
        # maior colado por hifen/underscore.
        $idRegex = New-Object System.Text.RegularExpressions.Regex ('(?i)(?<![\w-])(?:' + $idPattern + ')(?![\w-])')
        # O nome do PROPRIO studio (campo "studio" do alia.config.json) pode compartilhar uma
        # palavra com um Client real por coincidencia. A citacao do proprio nome do studio e
        # legitima em qualquer lugar da superficie; so a mencao ISOLADA a um Client e vazamento.
        # Tira a frase do nome do studio do texto ANTES de procurar Client, sem cravar nenhuma
        # palavra de operador especifico aqui (o nome do studio vem 100% do config lido acima).
        $selfRegex = $null
        if (-not [string]::IsNullOrWhiteSpace($opClient.StudioName)) {
            $selfPat = [regex]::Escape($opClient.StudioName) -replace '\\ ', '[\s-]+'
            $selfRegex = New-Object System.Text.RegularExpressions.Regex ('(?i)' + $selfPat)
        }
        $textExt = @(".ps1",".py",".md",".json",".yaml",".yml",".html",".js",".ts",".bat",".txt")
        $scanFiles = $arquivos | Where-Object {
            ($textExt -contains [IO.Path]::GetExtension($_)) -and
            ($_ -notmatch '(^|/)graphify-out/cache/') -and
            ($_ -notmatch '^studio\.example/')
        }
        $idLeaks = @()
        foreach ($rel in $scanFiles) {
            $full = Join-Path $repoRaiz ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
            if (-not (Test-Path -LiteralPath $full)) { continue }
            $conteudo = Get-Content -LiteralPath $full -Raw -ErrorAction SilentlyContinue
            if ([string]::IsNullOrEmpty($conteudo)) { continue }
            if ($selfRegex) { $conteudo = $selfRegex.Replace($conteudo, ' ') }
            $m = $idRegex.Match($conteudo)
            if ($m.Success) { $idLeaks += [pscustomobject]@{ arq = $rel; nome = $m.Value } }
        }
        if ($idLeaks.Count -eq 0) {
            Ok ("Nenhuma identidade de Client real do operador (" + $opClientIds.Count + " no registro) na superficie")
        } else {
            foreach ($x in ($idLeaks | Sort-Object arq -Unique)) {
                Bad ("identidade de cliente vazou: " + $x.arq + "  (nome real: " + $x.nome + ")")
            }
        }
    } else {
        Write-Host "[INFO] Sem state.json de operador com Clients reais em nenhum ancestral - check de identidade de cliente pulado (instalacao limpa)."
    }

    # ---- (2) a oficina nao pode ter remoto (so faz sentido em repo git) ----
    if ($ehGit) {
        $ehOficina = $repoRaiz -match 'alia-flow-lab'
        $remotos = @(& git remote)
        if ($ehOficina) {
            if ($remotos.Count -eq 0) { Ok "Oficina sem remoto (nao publica, por lei)" }
            else { Bad ("Oficina TEM remoto (" + ($remotos -join ", ") + ") - remova: git remote remove <nome>") }
        } else {
            if ($remotos.Count -gt 0) { Ok ("Repo publico com remoto: " + ($remotos -join ", ")) }
            else { Warn "Repo publico sem remoto configurado" }
        }
    } else {
        Write-Host "[INFO] Sem git: checks de remoto e .gitignore nao se aplicam (a inspecao de conteudo acima e a que vale aqui)."
    }

    # ---- (3) o .gitignore cobre as categorias? (so faz sentido em repo git) ----
    if ($ehGit) {
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
