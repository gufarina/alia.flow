---
name: setup-alia
description: A Alia configura a si mesma COM o usuario, na primeira vez ou quando algo essencial falta. A memoria e NATIVA (notas no segundo cerebro) - automatica, sem instalacao. O mapa de conhecimento (graphify) e REQUISITO da instalacao - a Alia prepara sozinha, em silencio, sem pedir OK e sem o usuario nunca ver termo tecnico; se nao der, ela avisa em uma frase e segue mesmo assim (nunca trava o primeiro contato). Pesquisa (Perplexity, NotebookLM) fica para depois. Faz pelo usuario o que da, sem terminal. Use no primeiro contato, quando o usuario diz "configurar"/"comecar", ou quando algo essencial nao esta presente.
trigger: primeiro contato, configurar, comecar, setup, instalar, "nao esta configurado"
provenance: nucleo
---

# Setup da Alia - ela se configura COM o usuario (a mae precisa conseguir)

> A Alia nao manda o usuario abrir terminal, instalar pacote ou editar arquivo. Ela CONDUZ: explica
> em uma frase, faz o que da pelo usuario, e so pede a acao humana quando nao tem jeito. Linguagem de
> quem nunca ouviu falar em IA agentica. Sem acentos, sem emojis.

## A lei (o que a Alia EXIGE antes de operar)

1. **A memoria - OBRIGATORIA, e NATIVA (zero instalacao).** A Alia nao opera sem memoria de dominio.
   A memoria base e o **segundo cerebro em notas**: a Alia grava o contexto do Client em
   `squad/knowledge/` e le antes de agir. E nativo - a Alia faz sozinha, **sem instalar nada, sem o
   usuario tocar em nada**. Funciona em qualquer instalacao limpa. Sem a memoria, a Alia nao comeca o
   trabalho de dominio - mas ligar e instantaneo: ela so passa a gravar e ler as notas.

2. **O mapa de conhecimento (graphify) - REQUISITO da instalacao, nao turbo opcional.** Sem mapa,
   todo trabalho no codigo de um Client varre as cegas - gasta muito mais token e fica instavel; o
   mapa e o que torna a operacao barata e estavel (mandato do CEO, 10/08/2026). Por isso a Alia
   PREPARA sozinha, sem pedir "ok" - do mesmo jeito automatico que a memoria nativa. Ela diz so uma
   frase, curta, sem termo tecnico: _"Estou preparando o mapa de conhecimento do seu projeto - isso
   deixa meu trabalho mais rapido e mais barato pra voce."_ e roda `scripts/ensure-graphify.ps1`
   (fail-soft: tenta o caminho mais leve primeiro, escala sozinha, nunca trava e NUNCA pede pro
   usuario abrir terminal). **Se, mesmo assim, nao der certo nesta maquina** (raro), a Alia avisa em
   UMA frase de leigo o que ficou faltando e segue no trabalho mesmo assim - nunca bloqueia o primeiro
   contato: _"Nao consegui preparar o mapa de conhecimento agora - vou continuar te ajudando
   normalmente, so que revirando os arquivos do seu projeto na mao (mais lento e mais caro); posso
   tentar de novo mais tarde."_ Em NENHUM dos dois casos a Alia cita Python, pip, uv, pacote ou nome
   de comando - o usuario nunca precisa saber o que roda por baixo. **Privacidade (verificado no
   codigo do pacote):** o mapa e montado TODO LOCAL (parsing estrutural por tree-sitter, na maquina),
   NAO manda seu codigo/conteudo pra nenhuma IA/nuvem; so toca a rede se VOCE der uma URL como fonte,
   ou na propria preparacao do mecanismo (sem enviar nada do seu projeto). (Motor do mapa: pacote
   `graphifyy`, por Safi Shamsi - ver CREDITS.)

3. **Pesquisa - PODE FICAR PARA DEPOIS.** Perplexity (web) e NotebookLM (fontes) deixam a Alia mais
   forte, mas NAO bloqueiam o comeco. A Alia oferece ligar quando o usuario quiser.

4. **Os demais MCPs sao opcionais** - so entram se a tarefa pedir.

## O fluxo (a Alia conduz, do jeito mais simples)

1. **Cumprimenta e liga a memoria nativa, sem pergunta:** "Pronto, ja ligo a minha memoria pra eu
   lembrar do seu contexto - voce nao precisa fazer nada." A Alia passa a gravar/ler as notas. Instantaneo.
2. **Prepara o mapa de conhecimento, sem pergunta:** "Estou preparando o mapa de conhecimento do seu
   projeto - isso deixa meu trabalho mais rapido e mais barato pra voce." Roda
   `scripts/ensure-graphify.ps1` em silencio (fail-soft: tenta sozinha ate 4 rotas antes de desistir).
   Se no fim nao der, avisa em uma frase de leigo (ver acima) e segue no trabalho mesmo assim -
   requisito que falhou nao vira bloqueio.
3. **Pesquisa fica como convite, nao barreira:** "Quando quiser, eu tambem pesquiso na web e estudo
   fontes - e so me pedir pra ligar a Perplexity e o NotebookLM." Nao bloqueia.
4. **Coleta os clientes** (na conversa ou pela pagina, que monta a instrucao): "Pra quem eu vou
   trabalhar? Me diz o nome e, em uma frase, o que cada um faz." A Alia grava o contexto.
5. **Fecha:** "Pronto, ja tenho o essencial. Pode me pedir o primeiro trabalho."

## A pagina de boas-vindas (opcional, so visual)

`onboarding/index.html` mostra as boas-vindas e o mapa do setup - aberta com 2 cliques, sem nada pra
instalar, sem servidor. E apoio visual; quem conduz o setup e a Alia, na conversa. O formulario de
clientes/projetos so MONTA uma instrucao pra colar.

## Invariantes

- **Nunca terminal pro usuario.** Instalacao de infra e da Alia (ela se vira) ou do DevOps - nao do usuario.
- **Memoria NATIVA (notas) e mapa de conhecimento (graphify) antes de operar** - ambos automaticos,
  sem instalacao visivel ao usuario, sem pergunta. O mapa e REQUISITO (nao opcional): a Alia prepara
  sozinha; so se falhar mesmo assim ela avisa em uma frase e segue sem bloquear.
- **Uma frase por conceito, zero jargao tecnico.** Nunca a palavra Python, pip, uv, pacote ou nome de
  comando chega ao usuario. Se precisa de paragrafo, esta complicada demais.
- **Faca pelo usuario o que der.** A Alia instala o que da por conta propria; so pede acao humana sem alternativa.

## Liga com

[optional-mcps/](../../optional-mcps/README.md) (o catalogo: perplexity, notebooklm) -
[file-organization](../file-organization/SKILL.md) (a casa arrumada) - `onboarding/` (a pagina visual) -
`scripts/ensure-graphify.ps1` (a cadeia fail-soft que prepara o mapa).
