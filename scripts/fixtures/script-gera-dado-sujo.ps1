# Fixture do guard de scripts (achado H5). NAO e script de producao: nao roda em lugar nenhum,
# nao esta no escopo varrido pelo guard (que olha so scripts/*.ps1, sem recursao) e so e lido
# pela prova do proprio guard no smoke-test.ps1.
#
# Serve para provar as duas metades de uma vez: que o guard PEGA o script que GRAVA o cargo
# derrubado em dado gerado, e que ele NAO acusa a linha que apenas registra a decisao.

$identidade = [ordered]@{ name = "Alia"; role = "COO + Framework Governor" }   # USO VIVO - o guard TEM que pegar esta linha
$identidade | ConvertTo-Json | Set-Content (Join-Path $PSScriptRoot 'saida-fixture.json') -Encoding UTF8

# REGISTRO (o guard TEM que ignorar esta linha): "COO" foi DERRUBADO pelo CEO em 02/jul.
