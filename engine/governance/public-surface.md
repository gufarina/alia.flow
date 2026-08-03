# LEI da superficie publica - o que pode existir no git

> Mandato do CEO em 2026-08-01, depois de a Alia commitar landing pages no repo da oficina.
> Sem acentos, sem emojis. Esta lei vem ANTES de qualquer conveniencia de versionamento.

## A lei, em uma frase

**Git e vitrine, nao gaveta.** No git so existe o produto publico, limpo, do jeito que o
usuario final recebe. Tudo que e de desenvolvimento fica FORA do git - salvo em disco, dentro
da oficina, mas nunca versionado num repositorio que pode ser publicado.

## O que NUNCA entra no git

- Landing pages, candidatas de LP, estudos de arte, mockups, previews de design.
- PRD, roadmap, backlog, oportunidades (`opportunities/`), pareceres, auditorias.
- Registro de claims (`CLAIMS.md`), material de marca interno (`BRAND.md`), decisoes datadas.
- Memoria da Alia, `state.json`, tarefas, relatorios, `PRODUCT.md`, `DESIGN.md` de trabalho.
- Rascunhos (`_drafts/`, `_dev/`, `_candidatas/`, `research/`, `rsi-backlog/`).
- Qualquer coisa de cliente. Cliente nunca toca em repo publico.

## O que PODE entrar

Somente o que o usuario final baixa e usa: o motor, os scripts do produto, o instalador,
a licenca, o README publico, o CHANGELOG publico, o cliente de exemplo (`studio.example/`)
e a documentacao dirigida AO USUARIO (PRIMEIROS-PASSOS, CONTRIBUTING).

Regra de bolso: **se um estranho lendo aquilo aprende como a gente decide por dentro, nao vai.**

## Onde cada coisa mora

| Coisa | Onde fica | Versionado? |
|---|---|---|
| Produto publico | `Projetos/alia-flow` (repo com `origin`) | SIM - e o unico que publica |
| Oficina (motor em evolucao, LP, docs, PRD) | `studio-farina/clients/alia-flow-lab` | NAO - **sem git nenhum**, por lei |
| Operacao do studio (clientes, memoria, tarefas) | `studio-farina/` | NAO - nunca foi git |

A oficina **NAO E REPOSITORIO GIT** (removido em 01/08/2026; historico antigo arquivado em
`studio-farina/_backups/git-oficina-arquivado-2026-08-01`, caso alguem precise consultar).
Oficina nunca precisou de git. Se alguem rodar `git init` ali, esta violando esta lei.

## Como o trabalho de desenvolvimento e protegido, entao

Sem git, a protecao contra perda e o BACKUP, nao o commit:
`scripts/package-release.ps1` para o pacote publico, e copia datada em `_backups/` para a
oficina. O incidente de 24/jun (LP perdida num reorg) se resolve com backup, nao publicando.

## Antes de publicar, a conferencia obrigatoria

Rodar `scripts/check-public-surface.ps1` no repo publico. Ele reprova se qualquer arquivo
das categorias proibidas estiver rastreado. Reprovou, nao publica.
