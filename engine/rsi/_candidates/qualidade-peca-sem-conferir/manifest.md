---
target: v2/lib/task_model.py
what: Peca entregue sem conferir contra o que o CEO ja disse (referencia, exemplo real, ordem da narrativa): licao obrigatoria no close (L90) forca nomear o que foi conferido; reincidencia medida por L86 (fraca 16 + reprovada 13).
why: Memorias gateway-qualidade-antes-de-entregar e peca-visual-so-vai-ao-ceo-depois-de-confere existem e o padrao reincide: texto nao funciona, entra trava executavel.
motivated_by: patterns-2026-09-22.md | atrito:qualidade-fraca - 16 sessao(oes) distinta(s)
promoted_on: 2026-10-01
status: aplicado-na-oficina (L90 licao no close; L91 prazo; medido por L86)
---

# Candidato qualidade-peca-sem-conferir - staged em 2026-10-01

> Criado por scripts/rsi-promote-pattern.ps1 apos SIM do operador sobre o padrao abaixo.
> Faltam proposed/ e test.ps1 (quem escreve a mudanca de verdade preenche) antes de
> este candidato poder rodar por scripts/rsi-apply.ps1 -Candidate qualidade-peca-sem-conferir.

## Padrao que originou

- relatorio: patterns-2026-09-22.md
- bucket: atrito:qualidade-fraca - 16 sessao(oes) distinta(s)

## Como reverter

Nada foi promovido ainda (status: staged) - reverter e so apagar esta pasta:
engine/rsi/_candidates/qualidade-peca-sem-conferir
Se um dia isto for promovido por rsi-apply.ps1, o rollback vira -Rollback qualidade-peca-sem-conferir (registrado em engine/rsi/_archive/LINEAGE.md).
