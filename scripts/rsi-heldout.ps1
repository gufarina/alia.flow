<#
  rsi-heldout.ps1 - PECA 4 do motor de RSI: conjunto FIXO de assercoes deterministicas que
  representam decisoes JA TOMADAS pelo dono. Nenhuma proposta (PECA 1, rsi-apply.ps1) pode
  violar nenhuma delas - e o passo (e) do portao de APLICA.

  A lista NAO e inventada: cada assercao aponta pra uma linha de docs/CLAIMS.md (vetos/claims
  vigentes) ou de uma LEI ja registrada no law-ledger. Fonte de cada uma, no comentario acima
 do bloco. UTF-8 sem BOM.

  Uso:
    scripts/rsi-heldout.ps1 [-Root <caminho>]        - roda as assercoes contra Root (default: a
                                                        propria instancia). exit 0 = tudo intacto,
                                                        exit 1 = pelo menos uma violacao.
    scripts/rsi-heldout.ps1 -SelfTest                - PROVA PELO NEGATIVO: planta uma violacao de
                                                        cada assercao, uma de cada vez, numa copia
                                                        isolada, e confirma que SO aquela assercao
                                                        falha (as outras continuam limpas). Nao
                                                        toca a instancia real. exit 0 = todas as
                                                        assercoes pegam a propria violacao plantada.
#>
param(
  [string]$Root = "",
  [switch]$SelfTest
)
$ErrorActionPreference = "Stop"
$scriptRoot = $PSScriptRoot
$defaultRoot = Split-Path -Parent $scriptRoot
if ([string]::IsNullOrWhiteSpace($Root)) { $Root = $defaultRoot }
. (Join-Path $scriptRoot "_rsi-lib.ps1")

function Read-Text([string]$p) {
  if (-not (Test-Path -LiteralPath $p)) { return $null }
  return [System.IO.File]::ReadAllText($p)
}

# Iterador de code points de verdade (nao de char UTF-16): emoji fora do BMP (a maioria) vira
# par substituto em string .NET - regex \uXXXX simples nunca casa um par substituto corretamente.
function Get-CodePoints([string]$s) {
  $out = New-Object System.Collections.Generic.List[int]
  $i = 0
  while ($i -lt $s.Length) {
    if ([char]::IsHighSurrogate($s[$i]) -and ($i + 1) -lt $s.Length -and [char]::IsLowSurrogate($s[$i+1])) {
      $out.Add([char]::ConvertToUtf32($s[$i], $s[$i+1]))
      $i += 2
    } else {
      $out.Add([int]$s[$i])
      $i += 1
    }

  }

  return $out
}

function Test-HasEmoji([string]$s) {
  foreach ($cp in (Get-CodePoints $s)) {
    if ($cp -ge 0x1F300 -and $cp -le 0x1FAFF) { return $true }
    if ($cp -ge 0x2600 -and $cp -le 0x27BF) { return $true }
    if ($cp -ge 0x2B00 -and $cp -le 0x2BFF) { return $true }
    if ($cp -eq 0xFE0F) { return $true }
  }

  return $false
}

function Get-MachineFiles([string]$root) {
  # universo "arquivo de motor / arquivo de maquina": engine, scripts, skills - na instancia E na
  # oficina (clients/alia-flow-lab tem a mesma estrutura por LEI de espelhamento).
  $ext = @(".md", ".ps1", ".yaml", ".yml")
  $out = New-Object System.Collections.Generic.List[string]

  foreach ($sub in @("engine", "scripts")) {
    foreach ($base in @((Join-Path $root $sub), (Join-Path $root ("clients/alia-flow-lab/" + $sub)))) {
      if (-not (Test-Path -LiteralPath $base)) { continue }
      Get-ChildItem -LiteralPath $base -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $ext -contains $_.Extension.ToLower() } |
        ForEach-Object { $out.Add($_.FullName) }
    }

  }

  # skills/: a raiz mistura skill PROPRIA da Alia com skill de terceiro instalada pelo harness
  # (medido: 41 pastas na raiz vs 32 na oficina - "animate", "apple-design" etc nao sao nossas).
  # A oficina (clients/alia-flow-lab/skills) e a fonte limpa; so contam skills cujo NOME tambem
  # existe la. skills/loop-designer/** fica de fora por mandato explicito desta frente ("NAO
  # toque em ... skills/loop-designer/** - outra frente esta cortando os loops agora"; tem acento
  # pre-existente, char 237, e nao e nosso a consertar aqui).
  $labSkillsDir = Join-Path $root "clients/alia-flow-lab/skills"
  $ownNames = @()
  if (Test-Path -LiteralPath $labSkillsDir) {
    $ownNames = @(Get-ChildItem -LiteralPath $labSkillsDir -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
  }

  $ownNames = @($ownNames | Where-Object { $_ -ne "loop-designer" })
  foreach ($base in @((Join-Path $root "skills"), $labSkillsDir)) {
    if (-not (Test-Path -LiteralPath $base)) { continue }
    foreach ($name in $ownNames) {
      $dir = Join-Path $base $name
      if (-not (Test-Path -LiteralPath $dir)) { continue }
      Get-ChildItem -LiteralPath $dir -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $ext -contains $_.Extension.ToLower() } |
        ForEach-Object { $out.Add($_.FullName) }
    }

  }

  return $out.ToArray()
}

# ---------------------------------------------------------------------------
# As assercoes. Cada uma: id, fonte (onde a decisao foi registrada), Test (recebe $root, devolve
# $true = intacto/PASS, $false = violacao/FAIL) e Detail (para o relatorio).

# ---------------------------------------------------------------------------
function Get-Assertions {
  @(
    [PSCustomObject]@{
      Id     = "identidade-vetada-nao-reaparece"
      Fonte  = "docs/CLAIMS.md L44 (VETOS) + L60 GUARD: \bCOO\b - DERRUBADO pelo CEO 02/jul"
      Detail = "a persona da Alia nunca se descreve pelo cargo vetado (COO)"
      Test   = {
        param($root)
        $files = @(
          (Join-Path $root "engine/agents/persona.md"),
          (Join-Path $root "clients/alia-flow-lab/engine/agents/persona.md")
        )
        foreach ($f in $files) {
          $txt = Read-Text $f
          if ($null -ne $txt -and ($txt -match '\bCOO\b')) { return $false }  # veto (GUARD:), nunca uso vivo
        }

        return $true
      }

    },
    [PSCustomObject]@{
      Id     = "headline-vigente-presente"
      Fonte  = "docs/CLAIMS.md L36 (VIGENTE) - BRAND.md, secao CORRECAO DO CEO, 01/08/2026"
      Detail = "a headline vigente ('Voce nao e tecnico. E nao precisa ser.') nao some da fonte dela"
      Test   = {
        param($root)
        $f = Join-Path $root "clients/alia-flow-lab/docs/BRAND.md"
        $txt = Read-Text $f
        if ($null -eq $txt) { return $false }
        return ($txt -match [regex]::Escape("Voce nao e tecnico. E nao precisa ser."))
      }

    },
    [PSCustomObject]@{
      Id     = "sem-emoji-em-arquivo-de-motor"
      Fonte  = "LEI repetida em engine/governance/*.md ('Sem acentos, sem emojis') + CLAUDE.md raiz"
      Detail = "nenhum arquivo .md/.ps1/.yaml de engine/scripts/skills (instancia ou oficina) tem emoji"
      Test   = {
        param($root)
        foreach ($f in (Get-MachineFiles $root)) {
          $txt = Read-Text $f
          if ($null -eq $txt) { continue }
          if (Test-HasEmoji $txt) { return $false }
        }

        return $true
      }
    },
    [PSCustomObject]@{
      Id     = "sem-acento-em-arquivo-de-maquina"
      Fonte  = "AGENTS.md raiz: 'este arquivo (e o motor) e ASCII sem acento nem emoji'"
      Detail = "nenhum arquivo .md/.ps1/.yaml de engine/scripts/skills tem caractere fora de ASCII"
      Test   = {
        param($root)
        foreach ($f in (Get-MachineFiles $root)) {
          $txt = Read-Text $f
          if ($null -eq $txt) { continue }
          foreach ($ch in $txt.ToCharArray()) {
            if ([int]$ch -gt 127) { return $false }
          }
        }
        return $true
      }
    },
    [PSCustomObject]@{
      Id     = "lei-git-e-vitrine"
      Fonte  = "CLAUDE.md raiz, 'LEI - git e vitrine, nao gaveta' + engine/governance/public-surface.md"
      Detail = "a lei da superficie publica e o script que a mede continuam presentes"
      Test   = {
        param($root)
        $psm = Join-Path $root "engine/governance/public-surface.md"
        $cps = Join-Path $root "scripts/check-public-surface.ps1"
        $txt = Read-Text $psm
        if ($null -eq $txt) { return $false }
        if (-not (Test-Path -LiteralPath $cps)) { return $false }
        return ($txt -match [regex]::Escape("LEI da superficie publica"))
      }

    },
    [PSCustomObject]@{
      Id     = "lei-oficina-e-a-fonte-nao-e-repo-git"
      Fonte  = "CLAUDE.md raiz, 'A oficina NAO E repositorio git - nunca precisou'"
      Detail = "clients/alia-flow-lab/.git continua nao existindo (a oficina nunca vira repo)"
      Test   = {
        param($root)
        $g = Join-Path $root "clients/alia-flow-lab/.git"
        return (-not (Test-Path -LiteralPath $g))
      }

    }

  )
}

function Invoke-Assertions([string]$root) {
  $results = @()
  foreach ($a in (Get-Assertions)) {
    $ok = $false
    try { $ok = (& $a.Test $root) } catch { $ok = $false }
    $results += [PSCustomObject]@{ Id = $a.Id; Ok = $ok; Fonte = $a.Fonte; Detail = $a.Detail }
  }

  return $results
}

# ---------------------------------------------------------------------------
# Modo normal: roda contra -Root e reporta.

# ---------------------------------------------------------------------------
if (-not $SelfTest) {
  Write-Host "=== RSI Held-out (decisoes do dono, assercoes fixas) ==="
  Write-Host ("Root: " + $Root)
  Write-Host ""

  $results = Invoke-Assertions $Root
  $fail = 0
  foreach ($r in $results) {
    if ($r.Ok) {
      Write-Host ("[PASS] " + $r.Id)
    } else {
      Write-Host ("[FAIL] " + $r.Id + " - " + $r.Detail + " (fonte: " + $r.Fonte + ")")
      $fail++
    }

  }

  Write-Host ""

  if ($fail -eq 0) {
    Write-Host "HELD-OUT: PASS (nenhuma decisao do dono violada)"
    exit 0
  } else {
    Write-Host ("HELD-OUT: FAIL (" + $fail + " assercao(oes) violada(s))")
    exit 1
  }

}

# ---------------------------------------------------------------------------
# -SelfTest: prova pelo negativo. Planta 1 violacao por vez numa copia isolada (New-RsiLightCopy)
# e confirma que SO a assercao correspondente vira FAIL - as outras continuam PASS. Nunca toca
# a instancia real.

# ---------------------------------------------------------------------------
Write-Host "=== RSI Held-out - SELF-TEST (prova pelo negativo) ==="
Write-Host ("Instancia de referencia: " + $Root)
Write-Host ""

function Plant-Violation([string]$copyRoot, [string]$id) {
  switch ($id) {
    "identidade-vetada-nao-reaparece" {
      $f = Join-Path $copyRoot "engine/agents/persona.md"
      Add-Content -LiteralPath $f -Value "`r`nEla e a sua COO." -Encoding UTF8   # planta o cargo vetado (GUARD:) so pra prova negativa
    }

    "headline-vigente-presente" {
      $f = Join-Path $copyRoot "clients/alia-flow-lab/docs/BRAND.md"
      $txt = Read-Text $f
      $txt = $txt -replace [regex]::Escape("Voce nao e tecnico. E nao precisa ser."), "Voce e tecnico e precisa ser."
      [System.IO.File]::WriteAllText($f, $txt, (New-Object System.Text.UTF8Encoding($false)))
    }

    "sem-emoji-em-arquivo-de-motor" {
      $f = Join-Path $copyRoot "engine/rsi/rsi.md"
      Add-Content -LiteralPath $f -Value "`r`nplantado para self-test" -Encoding UTF8
      [System.IO.File]::AppendAllText($f, [char]::ConvertFromUtf32(0x1F525), (New-Object System.Text.UTF8Encoding($false)))
    }
    "lei-git-e-vitrine" {
      $f = Join-Path $copyRoot "scripts/check-public-surface.ps1"
      cmd /c del /F /Q "$f" 2>$null | Out-Null
    }

    "lei-oficina-e-a-fonte-nao-e-repo-git" {
      $g = Join-Path $copyRoot "clients/alia-flow-lab/.git"
      New-Item -ItemType Directory -Force -Path $g | Out-Null
    }
  }
}

$allowedCoFail = @{}

$allOk = $true
foreach ($a in (Get-Assertions)) {
  $copy = New-RsiLightCopy -Root $Root -Label "rsi-heldout-selftest"
  try {
    Plant-Violation -copyRoot $copy.Path -id $a.Id
    $results = Invoke-Assertions $copy.Path
    $thisOne = $results | Where-Object { $_.Id -eq $a.Id }
    $allowed = @()
    if ($allowedCoFail.ContainsKey($a.Id)) { $allowed = $allowedCoFail[$a.Id] }
    $others = $results | Where-Object { $_.Id -ne $a.Id -and ($allowed -notcontains $_.Id) }
    $othersOk = -not ($others | Where-Object { -not $_.Ok })
    if ((-not $thisOne.Ok) -and $othersOk) {
      Write-Host ("[PEGOU] " + $a.Id + " - violacao plantada foi detectada, as outras " + $others.Count + " assercoes continuam limpas")
    } else {
      $allOk = $false
      if ($thisOne.Ok) {
        Write-Host ("[CEGO]  " + $a.Id + " - violacao plantada NAO foi detectada")
      } else {
        $badOthers = ($others | Where-Object { -not $_.Ok } | ForEach-Object { $_.Id }) -join ", "
        Write-Host ("[RUIDO] " + $a.Id + " - pegou a violacao mas tambem derrubou outra(s): " + $badOthers)
      }

    }

  } finally {
    Remove-RsiLightCopy -Copy $copy
  }

}

Write-Host ""
if ($allOk) {
  Write-Host "SELF-TEST: PASS (cada assercao pega a propria violacao plantada, sem ruido)"
  exit 0
} else {
  Write-Host "SELF-TEST: FAIL (ver [CEGO]/[RUIDO] acima)"
  exit 1
}
