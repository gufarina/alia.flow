# Capability Ledger - a promessa tem dono, prova e validade

> Registro da L57 (o marcador formal esta na secao "A LEI", abaixo), declarada em 09/09/2026
> (TASK-511). Nasceu de um defeito real: a auditoria de capacidade
> (`docs/CAPACIDADE-REAL.md`) foi medida em 10/08/2026 na v1.46.0, o motor andou 43 versoes ate a
> v1.71.1, e NADA no sistema avisou que aquela medicao tinha envelhecido. A coordenadora leu os
> selos velhos e os afirmou ao Operator como estado de hoje. A casa tinha catraca para grafo,
> acervo, linhagem, leis e harness - e nenhuma para a PROPRIA PROMESSA.

## Os 5 porques (o incidente, medido)

O Operator perguntou se o produto e bom. A coordenadora respondeu citando "dez capacidades
declaradas mas nao provadas" como estado de hoje. Era leitura de um retrato de um mes atras.

1. **Por que a coordenadora afirmou selos vencidos como estado de hoje?**
   Porque leu `docs/CAPACIDADE-REAL.md` e contou os selos, sem re-rodar um unico comando de prova.

2. **Por que ela nao re-rodou?**
   Porque o documento tem cara de fonte curada da casa, e a lei manda ler a fonte curada antes de
   afirmar. Ela cumpriu a lei e errou assim mesmo: a lei mandava LER a fonte, nunca mandava
   conferir se a fonte ainda VALE.

3. **Por que a fonte envelheceu um mes sem ninguem notar?**
   Porque nenhum script no motor a consulta para validar. [MEDIDO 09/09/2026] `smoke-test.ps1` e
   `smoke-test-studio.ps1` nao citam o arquivo nenhuma vez; o unico script que o menciona
   (`check-public-surface.ps1`) o trata como arquivo que nao pode VAZAR, nunca como fonte a
   revalidar. Entre a medicao (10/08, v1.46.0) e o incidente (09/09, v1.71.1) passaram 43 versoes.

4. **Por que nao existia esse mecanismo, se a casa tem catraca para quase tudo?**
   Porque toda catraca foi construida para o MECANISMO ("o motor funciona?") e nenhuma para a
   PROMESSA ("o que dizemos que entregamos ainda e verdade?"). Grafo, acervo, linhagem, leis,
   harness e ciclo de vida da Task tem sensor. Capacidade prometida nao tinha dono nem gate.

5. **Por que as duas auditorias do mesmo dia nao pegaram?**
   Porque as duas miraram custo e desempenho do harness, que era o escopo pedido, e a coordenadora
   tratou o escopo do pedido como limite da propria responsabilidade. Auditoria que nao cruza com a
   fonte que declara capacidade audita o motor, nunca o produto.

**CAUSA RAIZ:** a casa media se o motor funciona e nunca mediu se a promessa continua verdadeira.
Sem dono, sem validade e sem gate, o retrato de capacidade envelhece em silencio e vira afirmacao
falsa na boca de quem le - inclusive na da propria coordenadora.

**O CONSERTO E ESTE DOCUMENTO** (a lei), mais `scripts/capability-check.ps1` (a maquina) e o check
no smoke (o sensor). Mesmo par atuador/sensor que resolveu o ciclo de vida da Task na L56: mecanismo
sozinho depende de alguem lembrar de rodar, e foi assim que a divida nasceu.

## A LEI

> LEI (capacidade tem validade): nenhuma capacidade do produto pode ser AFIRMADA - em peca
> publica, em resposta ao Operator, em PRD ou em release - com selo mais velho que o teto de
> validade. Selo vencido nao e fonte: e historico. Quem afirma, re-mede antes.

Tres regras que sustentam a lei:

1. **Toda capacidade tem COMANDO DE PROVA executavel.** Prosa nao e selo. Se ninguem consegue
   escrever o comando que prova a capacidade, ela nao e FUNCIONA - e SO CONTRATO, e o registro
   diz isso na cara.
2. **Todo selo tem DATA e VERSAO.** O selo pertence a uma versao do motor. Motor novo, selo a
   reconferir.
3. **A validade e conferida por maquina, nao por memoria.** `scripts/capability-check.ps1` re-roda
   as provas; o smoke reprova quando o registro vence. Sem isso, a divida volta a envelhecer calada.

## Os quatro selos (nao existe quinto)

| Selo | O que significa | O que autoriza |
|---|---|---|
| **FUNCIONA** | Ha comando determinístico que prova, e ele passou na medicao mais recente. | Pode virar claim publico (via `docs/CLAIMS.md`) e pode ser afirmado ao Operator. |
| **FUNCIONA PARCIAL** | O mecanismo existe mas cobre uma fatia menor do que o nome sugere. A fatia exata fica escrita no registro. | Pode ser afirmado SO com a fatia junto, nunca liso. |
| **SO CONTRATO** | Declarado em prosa (doc, yaml, persona) sem maquina que force ou confira. | Uso interno (PRD, roadmap). NUNCA vira claim publico nem afirmacao de capacidade. |
| **NAO EXISTE** | Nao ha mecanismo. | Nada. Se o material publico promete isso, o claim se corta ou a feature se constroi. |

Regra dura de vocabulario: "existe mas nao provado" NAO e selo. Ou ha prova e e FUNCIONA, ou nao ha
e e SO CONTRATO. O selo ambiguo foi o que permitiu a divida dormir um mes.

## Validade

- **Teto padrao: 14 dias** OU **mudanca de MINOR do motor**, o que vier primeiro. O motor muda rapido
  demais para um teto maior: entre a medicao antiga e o dia do incidente passaram 43 versoes.
- Vencido = o registro inteiro esta vencido. Nao existe "so essa linha ainda vale".
- Re-medir e barato quando as provas sao comandos: `scripts/capability-check.ps1` roda tudo.

## A ordem de trabalho (aprendida na propria 1.72.0)

O gate REPROVOU a primeira tentativa desta release: as 42 linhas foram carimbadas com `1.71.1` e,
minutos depois, o bump levou a `VERSION` para `1.72.0`. Como o teto inclui "mudanca de MINOR", o
proprio bump invalidou o registro que a release acabou de medir. A lei funcionou; a ORDEM estava
errada.

Ordem correta, sempre:

1. Medir as capacidades (re-rodando os comandos de prova).
2. Bumpar `VERSION` e escrever o CHANGELOG.
3. **Recarimbar o registro com a versao NOVA** - a medicao e a mesma, o carimbo e que acompanha.
4. Rodar `capability-check.ps1` (espera exit 0) e so entao o smoke e o gate de release.

Quem pular o passo 3 leva FAIL do proprio sensor, e isso e o desenho certo: melhor reprovar a
release do que publicar um registro que aponta para uma versao que ja nao existe.

## O que o smoke cobra (o sensor)

O smoke do studio le este registro e REPROVA quando:

1. O registro esta vencido (idade acima do teto, ou versao do motor diferente da medicao).
2. Alguma capacidade citada em `docs/CLAIMS.md` como claim publico nao esta FUNCIONA hoje.
3. Alguma linha do registro nao tem comando de prova (capacidade sem como provar entrou escondida).

## Onde mora o quê

- `docs/CAPACIDADE-REAL.md` - o REGISTRO: uma linha por capacidade, com selo, data, versao,
  comando de prova e a lacuna que falta fechar.
- `scripts/capability-check.ps1` - a MAQUINA: roda as provas, imprime o selo do dia, compara com o
  registro e acusa divergencia e vencimento.
- `docs/CLAIMS.md` - o filtro do que e PUBLICO. Ja dependia do registro; agora a dependencia e
  conferida por maquina em vez de confianca.

## O que esta lei NAO faz

Ela nao julga se a capacidade e boa nem se vale a pena. Ela so garante que, quando a casa afirma
algo, a afirmacao tem prova com data. Decidir construir, cortar o claim ou conviver com a lacuna
continua sendo do Operator.
