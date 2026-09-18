@echo off
REM Alia Flow - abrir a pagina de boas-vindas com 1 clique.
REM De dois cliques neste arquivo. Ele abre a apresentacao no seu navegador.
REM Nao precisa de Python nem de nada instalado: e so um arquivo aberto no navegador.
REM Quem te configura de verdade e a Alia, na conversa.

cd /d "%~dp0"
start "" "onboarding\index.html"
