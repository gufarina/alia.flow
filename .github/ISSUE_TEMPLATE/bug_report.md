---
name: Reportar bug
about: Algo do Alia Flow nao funciona como esperado
title: "[bug] "
labels: bug
---

## O que aconteceu

Descreva o comportamento observado e o que voce esperava.

## Como reproduzir

Passos para reproduzir. Se possivel, o comando exato.

## Ambiente

- Sistema operacional:
- Coding agent (Claude Code / Codex / OpenCode / outro):
- Versao do Alia Flow (conteudo do arquivo `VERSION`):

## Saida do trilho

Cole a saida de:

```sh
powershell -ExecutionPolicy Bypass -File scripts/smoke-test.ps1
```

O trilho e a fonte de verdade - se ele fica vermelho, cole a(s) linha(s) `[FAIL]`.
