---
target: v2/lib/task_model.py
what: Correcao dita pelo CEO vira criterio verificavel: close exige --licao (L90) e a reincidencia e medida por rsi_reincidencia.py (L86). Trava ja aplicada na oficina.
why: CEO repete a mesma correcao ("ja disse") em 13 sessoes porque a correcao ficava em prosa; a regra textual nao funcionou.
motivated_by: patterns-2026-09-18.md | atrito:correcao-repetida - 13 sessao(oes) distinta(s)
promoted_on: 2026-10-01
status: aplicado-na-oficina (L90 licao no close; L91 prazo; medido por L86)
---

# Candidato correcao-repetida-vira-criterio - staged em 2026-10-01

> Criado por scripts/rsi-promote-pattern.ps1 apos SIM do operador sobre o padrao abaixo.
> Faltam proposed/ e test.ps1 (quem escreve a mudanca de verdade preenche) antes de
> este candidato poder rodar por scripts/rsi-apply.ps1 -Candidate correcao-repetida-vira-criterio.

## Padrao que originou

- relatorio: patterns-2026-09-18.md
- bucket: atrito:correcao-repetida - 13 sessao(oes) distinta(s)

## Como reverter

Nada foi promovido ainda (status: staged) - reverter e so apagar esta pasta:
engine/rsi/_candidates/correcao-repetida-vira-criterio
Se um dia isto for promovido por rsi-apply.ps1, o rollback vira -Rollback correcao-repetida-vira-criterio (registrado em engine/rsi/_archive/LINEAGE.md).
