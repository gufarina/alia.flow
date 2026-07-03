@echo off
REM Atualizar o motor Alia Flow desta instancia a partir do laboratorio.
REM Atualiza so o motor; nunca toca seus clientes, estado e configuracao.
cd /d "%~dp0"
powershell -ExecutionPolicy Bypass -File "%~dp0scripts\update-engine.ps1"
echo.
pause
