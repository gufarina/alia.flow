---
name: leitura-em-massa
description: Delega a leitura INTEIRA de um arquivo grande (acima do teto do hook) a um sub-agente em modelo barato, que devolve so um resumo em bullets citando linha. Use para ENTENDER um arquivo grande, nunca para editar.
trigger: '"[LEITOR]", arquivo grande, mais de 350 linhas, resumo de arquivo, ler varios arquivos, bulk-reader'
provenance: 'TASK-559, artigo do Spotify "Portal by Spotify cut my Claude Code token usage by 90%" (https://engineering.atspotify.com/2026/9/portal-by-spotify-cut-my-claude-code-token-usage-by-90)'
---

# Leitor em massa - resumo em modelo barato para arquivo grande

> O sub-agente do proprio host faz o papel do Portal do artigo do Spotify: le o arquivo inteiro
> num modelo barato e devolve so bullets ao modelo caro. Nao existe wrapper CLI - `claude -p`
> aninhado e recusado pelo host, entao a "Portal" aqui e o sub-agente nativo.

## Por que existe

[MEDIDO 14/09/2026, 30 dias de transcricoes do studio] Read = 16.751 chamadas e 92,9 MB (53% de
todo byte devolvido por ferramenta). 909 leituras inteiras de arquivo > 350 linhas somam 29,7 MB,
mais 148 cat/Get-Content grandes = 3,1 MB: leituras grandes sao 18,7% dos bytes de ferramenta e
18,4% do volume reenviado turno a turno. Prova em 4 cenarios reais (Explore + haiku, so bullets):
53 KB -> 2,8 KB; 59 KB -> 3,0 KB; 38 KB -> 1,9 KB; 255 KB -> 1,7 KB; media 96% a menos no contexto
do modelo caro.

## Entender ou editar? (a decisao)

| Preciso de... | Rota |
|---|---|
| Entender o arquivo (visao geral, onde fica X) | leitor em massa (este documento) |
| Editar, ou pegar um trecho exato | fatia: Read com offset/limit, ou Grep pelo header/simbolo |
| Raciocinio, arquitetura, seguranca | nunca delega - fica com o modelo principal |

Acima de 150 linhas e so para entender -> leitor, mesmo abaixo do teto do hook (350): o hook e
freio de emergencia, nao a regra.

[LIDO, artigo do Spotify] O modelo barato, num resumo, deixou passar um bug de thread-safety - por
isso a terceira linha nunca delega: o resumo informa a decisao, nao substitui o julgamento.

## O molde

Um arquivo:

```
Agent(subagent_type="Explore", model="haiku", prompt="""
Leia o arquivo {caminho} INTEIRO com Read em fatias de 1000 linhas (offset/limit) ate o fim do
arquivo - nunca peca Read sem offset/limit, o hook nega tambem dentro deste sub-agente. Nao leia
nenhum outro arquivo. Pergunta: {pergunta}

Contrato de saida (obrigatorio): so bullets, sem saudacao, sem prosa, sem preambulo, sem
conclusao. Maximo 30 linhas. Cada bullet cita o numero de linha (L120:). Se algo nao estiver
no arquivo, escreva 'nao consta'.
""")
```

Varios arquivos: uma chamada so, liste todos os caminhos e a pergunta comum no mesmo prompt -
nunca uma chamada por arquivo.

## Dentro de um especialista

Specialist PODE acionar o leitor, sob cerca do motor: so Explore em Haiku, so o molde desta
skill, no maximo 3 leituras por Task, prompt curto (ate 2.500 caracteres), nunca em segundo
plano. Qualquer outra delegacao dentro do sub-agente e bloqueada pelo motor (`[LEITOR-CERCA]`).
Acima do teto de 3, volta a fatiar por header/simbolo (Grep pelo titulo da secao, depois Read
com offset/limit).

Justificativa: o leitor e barato (Haiku), sem escrita e sem ferramenta de delegar, entao nao ha
fan-out possivel; o teto de 3 limita o custo a cerca de 150 mil tokens de modelo barato por
especialista no pior caso.

## Custo e latencia

[MEDIDO] 45 a 68 mil tokens do modelo barato por chamada (pedagio fixo de contexto do sub-agente,
~25 mil, mais o arquivo) e 20 a 41 s de latencia. Regra: abaixo do teto (350 linhas), fatiar e mais
barato que delegar; so acima do teto o leitor em massa poupa o modelo caro. Mesmo assim, 150
linhas so para entender ja custam cerca de 2 mil tokens do modelo caro, e esse custo volta a cada
turno (mediana de 99 turnos por sessao principal) - por isso o leitor vale antes do teto do hook.

## Desligar e ajustar o teto

`ALIA_READ_SHUNT_OFF=1` ou o arquivo `.claude/read-shunt.off` desligam o hook. O teto de linhas vem
de `ALIA_SHUNT_MIN_LINES` (padrao 350, ver `engine/reading-strategy.yaml`).
