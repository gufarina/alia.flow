<#
  _rsi-lib.ps1 - biblioteca compartilhada do motor de RSI (PECA 1 e PECA 4).
  Dot-source apenas (nao roda sozinho). Fornece:
    New-RsiLightCopy $root  -> copia de trabalho ISOLADA da instancia, barata (poucos MB) mas
      funcionalmente completa: as pastas pequenas e evolutiveis (engine, scripts, skills, memory,
      docs, studio, arquivos da raiz) sao copiadas de verdade - editar ali NUNCA toca o vivo. A
      oficina (clients/alia-flow-lab, ~23MB) tambem e copiada de verdade, porque e onde o motor
      nasce. O resto (outros Clients, _backups, research, dotdirs de ferramenta) e gigante (3GB+)
      e nao muda com a proposta - vira JUNCTION (link de pasta NTFS, sem copiar bytes), pra que
      smoke-test-studio.ps1 rodando na copia ainda enxergue os dados reais dos outros clientes.
    Remove-RsiLightCopy $copy -> desfaz a copia (remove as junctions primeiro, sem recursao pra
      dentro delas, so depois apaga o resto). UTF-8 sem BOM.
#>

function New-RsiLightCopy {
  param([Parameter(Mandatory=$true)][string]$Root, [string]$Label = "rsi")
  $stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
  $copyRoot = Join-Path $env:TEMP ($Label + "-" + $stamp + "-" + [Guid]::NewGuid().ToString("N").Substring(0,8))
  New-Item -ItemType Directory -Force -Path $copyRoot | Out-Null

  $copyDirs = @("engine", "scripts", "skills", "memory", "docs", "studio")
  $junctions = New-Object System.Collections.Generic.List[string]

  Get-ChildItem -LiteralPath $Root -Force | ForEach-Object {
    $item = $_
    $dest = Join-Path $copyRoot $item.Name

    if ($item.PSIsContainer) {
      if ($item.Name -eq "clients") {
        $destClients = Join-Path $copyRoot "clients"
        New-Item -ItemType Directory -Force -Path $destClients | Out-Null
        Get-ChildItem -LiteralPath $item.FullName -Force | ForEach-Object {
          $c = $_
          $cDest = Join-Path $destClients $c.Name
          if ($c.Name -eq "alia-flow-lab") {
            # a oficina: copia de verdade (fonte do motor, pode ser alvo de proposta).
            robocopy $c.FullName $cDest /E /NFL /NDL /NJH /NJS /NC /NS /NP | Out-Null
          } else {
            New-Item -ItemType Junction -Path $cDest -Target $c.FullName | Out-Null
            $junctions.Add($cDest)
          }
        }
      }
      elseif ($copyDirs -contains $item.Name) {
        robocopy $item.FullName $dest /E /NFL /NDL /NJH /NJS /NC /NS /NP | Out-Null
      }
      else {
        # pasta pesada/irrelevante para o teste (backups, research, dotdirs de ferramenta...).
        New-Item -ItemType Junction -Path $dest -Target $item.FullName | Out-Null
        $junctions.Add($dest)
      }
    }
    else {
      Copy-Item -LiteralPath $item.FullName -Destination $dest -Force
    }
  }

  return [PSCustomObject]@{
    Path      = $copyRoot
    Junctions = $junctions.ToArray()
  }
}

function Remove-RsiLightCopy {
  param([Parameter(Mandatory=$true)]$Copy)
  foreach ($j in $Copy.Junctions) {
    if (Test-Path -LiteralPath $j) {
      # remove SO o ponto de juncao (nao o alvo real): cmd /c rmdir sem /S nao recursa pro alvo.
      cmd /c rmdir /Q "$j" 2>$null | Out-Null
    }
  }
  if (Test-Path -LiteralPath $Copy.Path) {
    # cmd /c rmdir /S apaga o que sobrou (arquivos copiados de verdade - seguro, sem junction
    # sobrevivente pra recursar). Evita o bug de Remove-Item -Recurse com caminho de 8.3 truncado.
    cmd /c rmdir /S /Q "$($Copy.Path)" 2>$null | Out-Null
  }
}
