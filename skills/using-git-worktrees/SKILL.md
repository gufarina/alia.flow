---
name: using-git-worktrees
description: Disciplina de git worktrees para varios especialistas ou squads trabalharem em paralelo sem se atropelar. Cada frente de trabalho vive num worktree e numa branch isolados, sobre o mesmo repositorio, e so integra quando esta verde - sem misturar mudancas no meio do caminho. Use quando duas ou mais Tasks tocam o mesmo repo ao mesmo tempo, quando um experimento precisa de um espaco descartavel sem sujar o trabalho principal, ou quando um squad quer rodar frentes concorrentes sem conflito de arquivos.
trigger: /using-git-worktrees
provenance: nucleo
---

# Using Git Worktrees

Capacidade de isolamento de trabalho paralelo. Um worktree e um diretorio de trabalho
extra ligado ao mesmo repositorio: cada um aponta para a sua propria branch, com os
proprios arquivos no disco, compartilhando um unico historico. Frentes concorrentes
deixam de disputar os mesmos arquivos.

Padroes de git do produto: `engine/engineering.md` (conventional commits, atomicos).
Regra de fronteira: `git push` e exclusivo do DevOps (engineering.md, secao Git).

Sem acentos, sem emojis em qualquer arquivo gerado (regra do CEO).

## Quando usar

- Duas ou mais Tasks tocam o mesmo repositorio ao mesmo tempo e nao podem esperar uma
  pela outra.
- Um especialista precisa de um espaco descartavel para um experimento ou um spike sem
  arriscar o trabalho principal.
- Um squad quer paralelizar frentes (ex: feature, fix urgente, refactor) sem que um
  `git stash` ou troca de branch jogue fora o contexto de outra frente.

Quando NAO usar: tarefa unica e sequencial no repo cabe na branch corrente; abrir
worktree para isso so cria diretorio orfao para limpar depois.

## O procedimento

### 1. Criar um worktree por frente

Para cada frente de trabalho, crie um worktree com uma branch propria, fora da arvore do
repo principal (irmao, nao filho - evita que o repo principal enxergue o worktree como
conteudo seu):

```
git worktree add ../<repo>-<frente> -b frente/<descricao-curta>
```

- O caminho (`../<repo>-<frente>`) e o diretorio novo no disco.
- `-b frente/<descricao-curta>` cria a branch isolada ja apontada por esse worktree.
- Nome de branch por convencao: prefixo da frente + descricao em kebab-case, sem acento
  (ex: `frente/copy-landing`, `frente/fix-checkout`). Um nome por Task.

Se a branch ja existe, omita `-b`:

```
git worktree add ../<repo>-<frente> frente/<descricao-curta>
```

### 2. Isolar - trabalhar so dentro do worktree da frente

- Cada especialista entra no diretorio do seu worktree e trabalha SO ali. Os arquivos
  daquela frente nao aparecem no worktree dos outros: zero conflito de edicao concorrente.
- Commits sao atomicos e com referencia da Task, no padrao de `engine/engineering.md`. O
  commit fica na branch daquele worktree - nao vaza para as outras frentes.
- Nunca edite a mesma branch a partir de dois worktrees: o git bloqueia isso de proposito.
  Uma branch, um worktree, uma frente.
- Conferir o mapa a qualquer momento:

```
git worktree list
```

### 3. Integrar - so quando a frente esta verde

Integrar e juntar a frente de volta ao tronco depois de pronta e verificada (criterio de
aceite cumprido, Quality Gate passado). A ordem reduz conflito:

1. Atualize a branch da frente com o tronco mais recente ANTES de integrar (merge ou
   rebase do tronco para dentro da frente, conforme a politica do repo). Resolver conflito
   acontece aqui, dentro da frente, sem travar as outras.
2. Com a frente verde e atualizada, leve-a ao tronco (merge da branch da frente no tronco)
   no worktree do tronco.
3. Repita por frente. Integrar uma de cada vez mantem cada conflito pequeno e rastreavel.

Fronteira dura: este procedimento orquestra git LOCAL (criar branch, commitar, integrar).
Publicar para o remoto - `git push` - continua EXCLUSIVO do DevOps (engineering.md, secao
Git). A frente integrada e entregue ao DevOps para publicar; o especialista nao da push.

### 4. Limpar - nao deixar worktree orfao

Frente integrada e worktree usado nao ficam por inercia (mesmo principio do ciclo de vida
dos loops: nada eterno sem motivo):

```
git worktree remove ../<repo>-<frente>
git branch -d frente/<descricao-curta>
```

- `worktree remove` apaga o diretorio de trabalho extra do disco.
- `branch -d` remove a branch ja integrada (use `-d`, que recusa apagar branch nao
  integrada - protege trabalho nao mesclado).
- Se um worktree foi removido manualmente do disco por fora, rode `git worktree prune`
  para o git esquecer a referencia morta.

## Invariante

- Uma frente = um worktree = uma branch = uma Task. Sem cruzamento.
- Integrar so com a frente verde; conflito se resolve dentro da frente, antes de tocar o
  tronco.
- `git push` nunca sai daqui: e do DevOps. Este procedimento para no merge local.
- Worktree e branch integrados sao limpos, nunca abandonados.
- Toda escrita de arquivo nas frentes: UTF-8 sem BOM, sem acentos, sem emojis.
