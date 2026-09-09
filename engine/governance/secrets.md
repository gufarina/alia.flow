# Segredos com auditoria - a lei do cofre

> Mandato do CEO em 2026-09-08, depois de um VERCEL_TOKEN ter sido colado na CONVERSA (o operador
> pediu para colar no `.env`; ele colou no chat por engano). A Alia pediu para gerar outro token e
> revogar o vazado; o operador respondeu, com razao: "se eu pegar outro voce vai dar a mesma
> resposta, nao tem logica" - o canal continua sendo o mesmo chat, pedir rotacao so repete a
> exposicao - e fechou: "SEJA RESPONSAVEL E GUARDE ESSA MERDA COM AUDITORIA". O defeito era do
> motor: nao havia lugar seguro pra um segredo entrar, nem registro de quem usou o que e quando.
> UTF-8 sem BOM.

## A lei, em uma frase

> LEI: segredo tem UMA porta (`scripts/secret.ps1`), o VALOR mora SO no cofre
> (`{studio}/.secrets/vault.json`), e toda acao sobre ele fica registrada num ledger que NUNCA
> guarda o valor (`{studio}/secrets-ledger.jsonl`). O normal e USAR sem VER.

## As duas pecas, papeis diferentes (nunca confundir)

| Peca | O que guarda | Quem le | Onde mora |
|---|---|---|---|
| Cofre | O VALOR do segredo | So `scripts/secret.ps1` | `{studio}/.secrets/vault.json` |
| Ledger | Nome, escopo, acao, quem, pra que, IMPRESSAO DIGITAL (sha256 truncado) - nunca o valor | Qualquer agente (e a prova) | `{studio}/secrets-ledger.jsonl` (append-only) |

## Os verbos (todos em `scripts/secret.ps1`)

- `-Set` grava. O valor NUNCA vem por argumento de linha de comando (vaza em historico de shell,
  log de hook, transcript) - so por STDIN (pipe) ou por `-File <caminho>` que o script LE E APAGA.
  Nao ha parametro `-Value` neste script, de proposito: tentar passar um da erro do proprio
  PowerShell (parametro nao existe), prova pelo negativo sem precisar de logica extra.
- `-Use` e o verbo PRINCIPAL: roda um comando FILHO com o segredo injetado numa variavel de
  ambiente, sem nunca imprimir o valor. O agente publica sem jamais ver o token.
- `-List` mostra nome, escopo, quando entrou, ultimo uso e a impressao digital. Nunca o valor.
- `-Revoke` tira do cofre (o ledger mantem o historico).
- `-Get` e o caminho EXCEPCIONAL: exige `-IAcceptExposure` E `-Reason` juntos, ou recusa sem tocar
  o ledger (recusa nao e risco, nao precisa virar linha). Quando de fato expoe, grava `risky:true`
  no ledger - ruidoso de proposito, nunca silencioso.
- `-MarkLeaked` registra um vazamento conhecido (ex.: colado no chat por engano) SEM mexer no
  cofre - ver a doutrina abaixo.

## A doutrina do vazamento (vale para o motor inteiro, nao so este script)

Nunca mais pedir ao operador para gerar e colar um segredo novo pelo MESMO canal que ja o expos.
Se um segredo vazou pelo chat: (a) registra o vazamento no ledger (`secret.ps1 -MarkLeaked`),
(b) usa o que tem para nao travar o trabalho, (c) oferece UMA vez o caminho seguro de
substituicao (`-Set` via stdin/`-File`, nunca de novo pelo chat), (d) nunca repete a cobranca.
Cobrar rotacao sem oferecer canal melhor empurra o custo do defeito do motor para o operador -
foi exatamente o erro que motivou este documento.

## O guarda (duas camadas, uma no ATO e uma no GATE)

1. **No ATO** (`scripts/secret-write-guard.ps1`, hook de `PreToolUse`, matcher
   `Edit|Write|NotebookEdit`): se o CONTEUDO que esta prestes a ser gravado contem o valor literal
   de um segredo que ja esta no cofre, a escrita e RECUSADA antes de acontecer
   (`permissionDecision:deny`), citando nome e fingerprint - nunca o valor. Exclui o proprio cofre
   e o proprio ledger (e la que o valor deve morar). Segredo com menos de 8 caracteres nunca entra
   na comparacao (ruido: string curta bate por acaso).
2. **No GATE** (`scripts/check-public-surface.ps1`, secao "(1.7) segredo do cofre vazado em
   arquivo"): antes de publicar, varre toda a superficie (arquivo versionado, artifact de cliente,
   `state.json`, memoria - tudo que ja entra na varredura existente) atras do valor EXATO de cada
   segredo do cofre. Diferente da cacada de credencial generica (secao 1.6, que procura FORMATO -
   `sk-ant-...`, `nvapi-...` etc, sem saber se e real): esta secao sabe o valor de verdade, zero
   falso positivo e zero falso negativo pra qualquer segredo que passou pelo cofre.

Os dois nunca imprimem o valor - so nome, escopo e fingerprint (mesma disciplina do ledger).

## Onde NAO decide

Este documento nao substitui `engine/governance/public-surface.md` (a lei mais ampla de git-e-
vitrine) nem a cacada de credencial generica (secao 1.6 do mesmo script, L42 do law-ledger) - e
uma CAMADA A MAIS, especifica de segredo conhecido pelo cofre, reusando a mesma varredura de
arquivos que ja existia (reuse-first).

## Segue
[MAP](../MAP.md) - [law-ledger](law-ledger.md) - [public-surface](public-surface.md) -
[persistence-catalog](persistence-catalog.md).
