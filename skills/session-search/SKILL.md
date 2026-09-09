---
name: session-search
description: Busca crua por palavra nas sessoes passadas do projeto via FTS5. Indexa os transcripts JSONL do Claude Code num SQLite local e responde consultas com trecho, janela de contexto e bookends da sessao. Use quando precisa lembrar onde algo foi literalmente dito/feito numa sessao anterior (uma frase, um nome de arquivo, um comando, uma decisao por palavra) - o complemento cru do grafo. Trigger: buscar na sessao, recall de transcript, "onde a gente falou de X", "em que sessao decidimos Y".
trigger: /session-search <termo>
provenance: nucleo
---

# Session Search

Recall cru por texto sobre os transcripts das sessoes passadas. Indexa cada evento
de usuario e assistente num indice FTS5 (SQLite local) e devolve, para cada acerto,
um trecho + a janela de eventos ao redor + os bookends da sessao para situar.

Mecanismo: `scripts/session-search.py` (stdlib pura: sqlite3, json, glob, argparse;
sem pip). E uma Frugal Skill - o trabalho mecanico de indexar e buscar custa zero
token de modelo. O agente so entra para interpretar os acertos.

## Diferenca para o grafo (leia antes de usar)

Sao recalls complementares, nao concorrentes:

- O GRAFO (`squad/knowledge/graphify-out/`) e recall de CONCEITO: nos e relacoes,
  "o que se liga a que". Responde "quais temas/entidades se relacionam com X".
- Esta BUSCA e recall CRU por palavra: o texto literal do transcript. Responde
  "onde a gente DISSE/FEZ X, palavra por palavra".

Regra de escolha: para navegar ideias e ligacoes, grafo. Para achar a frase, o
comando, o nome de arquivo ou a decisao exata que apareceu numa sessao, esta busca.
O Frugality Check manda consultar o grafo antes de varredura cega; esta busca NAO e
varredura cega de arquivos - e consulta a um indice ja construido dos transcripts,
o recall de texto que o grafo nao cobre.

## Como usar (sempre nesta ordem)

### 1. Indexar primeiro

```
python scripts/session-search.py index
```

- Le todos os `*.jsonl` do diretorio de transcripts, extrai o texto de cada evento
  de usuario e assistente (texto, thinking, nome de tool_use, e tool_result em
  texto), ignora ruido binario (imagens, payload opaco).
- Grava numa tabela FTS5 em `memory/_index/sessions.db` (cria a pasta).
- E idempotente: re-indexar limpa e regrava com id estavel (`arquivo:linha`), nunca
  duplica. Rode de novo sempre que houver sessoes novas.
- Imprime quantos arquivos e quantos eventos indexou.

Configuravel:
- `--transcripts <dir>` aponta para outro diretorio de JSONL.
- `--db <caminho>` muda o caminho do indice (default `memory/_index/sessions.db`).

### 2. Buscar (modo DISCOVERY)

```
python scripts/session-search.py search "loops"
```

Para cada acerto, o modo discovery imprime:

- o TRECHO (snippet do FTS5, com o termo destacado entre colchetes);
- a JANELA DE CONTEXTO: os eventos de `-5` a `+5` ao redor do acerto, dentro da
  mesma sessao, com o evento do acerto marcado por `>>`;
- os BOOKENDS: o primeiro e o ultimo evento daquela sessao, para situar o acerto
  no arco da conversa.

Cada evento aparece como `#<id> [papel] texto...`, onde `<id>` e a ordem global
estavel do evento - e o que voce usa para rolar.

Opcoes:
- `--limit <n>` controla quantos acertos (default 5).
- O `<termo>` aceita sintaxe FTS5 (ex: `"loops"`, `"deep research"`,
  `"loops OR memoria"`, `"loop*"`).

### 3. Rolar mais contexto (modo SCROLL)

Quando a janela de `+-5` nao basta, role mais contexto ao redor de um acerto pelo
seu id:

```
python scripts/session-search.py search --scroll 142
```

- Abre uma janela mais larga (raio 10 por padrao) ao redor do evento `#142`,
  sempre dentro da mesma sessao.
- `--radius <n>` ajusta o tamanho da janela para ver ainda mais (ou menos).

## Metadados guardados

Cada evento no indice carrega: id estavel (`arquivo:linha`), arquivo de origem,
ordem global (`seq`), numero da linha, papel (user/assistant) e o texto. Isso
sustenta a janela de contexto, os bookends e o scroll.

## Fronteira e provenance

- O indice (`memory/_index/sessions.db`) e DADO DO OPERADOR: fica fora do git
  (`.gitignore`), igual ao restante de `memory/`. O conteudo cru das sessoes pode
  ter acentos/non-ASCII, mas vive so no DB - nunca no codigo nem na skill.
- Esta capacidade so LE transcripts e ESCREVE no indice local. Nao toca nucleo,
  nao toca a memoria real do operador, nao deleta nada.
- Codigo e skill: UTF-8 sem BOM, ASCII puro, sem emojis.

## Invariante

- Indexar e idempotente: re-rodar nunca duplica (id estavel `arquivo:linha`).
- Discovery = trecho + janela `+-5` + bookends. Scroll = janela mais larga por id.
- Recall cru por palavra; o grafo cobre conceito/relacao. Use o certo para a pergunta.
- O indice e dado do operador (gitignored); o codigo e a skill ficam ASCII.
