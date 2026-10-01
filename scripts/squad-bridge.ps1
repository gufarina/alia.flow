# squad-bridge.ps1 - PONTEIRO. A ponte mora em UM lugar so: v2/squad/bridge.ps1 (nucleo) + v2/squad/targets/.
# Este arquivo existe so para o nome antigo continuar valendo; nao edite a logica aqui.
# Mudou de contrato: -Mode saiu (use -Target claude|opencode|pi|context-load); -MigrateContract saiu
# (o nucleo reprova campo ausente); -Reserve saiu (a reserva .claude/squads nao existe mais).
& (Join-Path $PSScriptRoot '..\v2\squad\bridge.ps1') @args
exit $LASTEXITCODE
