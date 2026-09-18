@echo off
REM Reverter o motor Alia Flow para o ultimo backup automatico. So mexe no motor; nunca toca
REM seus clientes, estado e config (mesma lista protegida do atualizar-alia.bat).
cd /d "%~dp0"
powershell -ExecutionPolicy Bypass -File "%~dp0scripts\revert-alia.ps1"
echo.
pause
