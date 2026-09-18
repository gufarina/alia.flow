@echo off
REM Atualizar o motor Alia Flow. Atualiza so o motor; nunca toca seus clientes, estado e config.
cd /d "%~dp0"
if exist "%~dp0clients\alia-flow-lab" (
  REM Instalacao de desenvolvimento/instancia: puxa do laboratorio local.
  powershell -ExecutionPolicy Bypass -File "%~dp0scripts\update-engine.ps1"
) else (
  REM Instalacao publica: baixa a versao nova do GitHub, com backup e rollback automaticos.
  powershell -ExecutionPolicy Bypass -File "%~dp0scripts\update-online.ps1"
)
echo.
pause
