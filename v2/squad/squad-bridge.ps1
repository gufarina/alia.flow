# squad-bridge.ps1 - PONTEIRO para bridge.ps1 (mesma pasta). Copia unica do gerador: nao edite a logica aqui.
& (Join-Path $PSScriptRoot 'bridge.ps1') @args
exit $LASTEXITCODE
