# Bastao - o artefato de passagem entre estacoes

> Feature do motor. O bastao e o handoff compacto (<=500 tokens) que carrega uma Task de um
> agente/estacao para o proximo, sem despejar a conversa inteira. Detalha o que forja.md ja
> resume na secao "O bastao (o fio entre as estacoes)" - nao contradiz, aprofunda. Sem acentos,
> sem emojis. UTF-8 sem BOM.

---

## O problema que resolve

Sem um formato fixo de passagem, cada handoff vira improviso: um agente despeja o transcript
inteiro no proximo (estoura contexto, mistura responsabilidade) ou resume mal e a Task perde
decisao ja tomada (o proximo reprocessa do zero, ou pior, contradiz o que ja foi decidido). O
bastao fecha essa lacuna com um CONTRATO fixo e pequeno: cabe em qualquer janela de contexto,
carrega so o que o proximo precisa para agir, e nunca precisa ser lido duas vezes (flag
`consumed`).

Frugalidade em forma de artefato: o handoff compactado ja e lei em
[Delegacao = isolamento de contexto](../orchestration.md#delegacao--isolamento-de-contexto-doutrina)
("Artefato + resumo, nunca o transcript cru") e em [tools.md](../tools.md) ("compactar o
handoff"). O bastao e ESSA lei com campos e teto exatos.

## O CONTRATO do bastao

Todo bastao tem exatamente estes campos, cada um com teto duro. Total: **<=500 tokens**.

| Campo | Conteudo | Teto |
|-------|----------|------|
| `de` | Quem passa (estacao/agente/papel de origem) | 1 linha |
| `para` | Quem recebe (estacao/agente/papel de destino) | 1 linha |
| `task_id` | O id da Task no `studio/state.json` | 1 linha |
| `decisoes` | Decisoes ja tomadas que o proximo NAO deve reabrir | max 5 itens |
| `arquivos_tocados` | Paths dos arquivos que esta estacao criou/editou | max 10 itens |
| `bloqueios` | Impedimentos ainda abertos que o proximo precisa saber | max 3 itens |
| `proximo_passo` | O que o proximo deve fazer, direto ao ponto | max 2 frases |
| `consumed` | Flag booleana - vira `true` assim que o destino le e age | bool |

O molde estruturado (pronto para um agente preencher) vive em
[bastao-template.yaml](bastao-template.yaml).

## A regra: perfil + bastao, nunca a conversa inteira

Quem ENTRA numa Task recebe **so duas coisas**: o proprio perfil (persona, Domain Pack, Expert
Mind - o que ja o define) e o bastao da estacao anterior. Nunca o transcript, nunca o raciocinio
bruto de quem passou a bola. Isso e a mesma regra do
[cap de profundidade de delegacao](../orchestration.md#delegacao--isolamento-de-contexto-doutrina):
o contexto do agente anterior fica com ele; sobe/desce so o que decide o proximo passo.

Reprocessar o bruto e o erro que o bastao existe para evitar - estoura contexto e convida o
proximo agente a refazer julgamento que ja foi feito (e ja esta em `decisoes`).

## A cadeia e a sugestao de proximo comando

Cada estacao/agente, ao fechar sua parte, DECLARA no bastao qual e a proxima estacao (`para`).
Isso forma a **cadeia**: FUNDIR passa a MOLDAR, MOLDAR passa a PROVAR (ou a TEMPERAR se falhar),
PROVAR passa a GUARDAR - a sequencia das 5 estacoes da Forja e a cadeia canonica, mas o bastao
tambem serve handoffs fora da Forja (gateway -> especialista, especialista -> QA).

Ao entregar, o coordenador nao so passa o bastao - ele **sugere o proximo comando** para quem
entra ("Sugestao: rode `*implementa` na Task TASK-123"). Isso ancora nos passos MONITORA e FECHA
do [protocolo de 5 passos](../orchestration.md#o-protocolo-5-passos):

- **MONITORA**: o coordenador le o `proximo_passo` do bastao recebido e usa isso para cobrar
  progresso - ele sabe o que esperar sem reler a Task inteira.
- **FECHA**: ao fechar sua parte, quem entrega preenche o bastao (inclusive `proximo_passo`) ANTES
  do Artifact ser dado como pronto - o bastao e parte do fechamento, nao um anexo opcional depois.

## Como casa com a Forja e o Advisor Pattern

- **Forja (5 estacoes)**: o bastao E o fio entre FUNDIR -> MOLDAR -> TEMPERAR -> PROVAR -> GUARDAR
  descrito em [forja.md](forja.md). Cada estacao fecha com um bastao para a proxima; TEMPERAR
  anexa o registro de tentativa ao bastao quando escala.
- **Advisor Pattern**: o bastao e o conselho do [advisor-pattern.md](advisor-pattern.md) resolvem
  problemas diferentes. O bastao passa a Task ADIANTE (handoff, a Task muda de dono); o advisor
  aconselha o MESMO executor no meio da Task (a Task nao muda de dono, nao para). Nunca confundir
  um pedido de conselho com um bastao incompleto.

## Regras duras

1. **Teto de 500 tokens e duro, nao alvo.** Bastao que estoura o teto e sintoma de Task mal
   quebrada (mais de um dominio, decisao demais) - quebrar em sub-Tasks, cada uma com seu bastao,
   em vez de alongar o campo.
2. **`consumed` evita reprocessamento.** Assim que o destino le e age sobre o bastao, marca
   `consumed: true`. Um bastao com `consumed: true` nao e reaberto nem reinterpretado por outro
   agente - se a Task voltar a essa estacao, nasce um bastao novo.
3. **Bastao nao substitui o Gate.** O bastao transporta contexto operacional (decisoes, arquivos,
   bloqueios); ele nao e evidencia de qualidade. O [Quality Gate](../governance/quality-gate.md)
   continua sendo o unico juiz do Artifact, independente do que o bastao diz.
4. **Decisoes listadas no bastao nao se reabrem sem motivo.** Se o proximo agente discorda de uma
   decisao ja tomada, isso e escalacao (mesma regra das 3 abordagens de
   [orchestration.md](../orchestration.md#causa-raiz-antes-de-escalar)), nao uma sobrescrita
   silenciosa.
5. **Sem Client/Task = sem bastao.** O bastao carrega `task_id`; sem Task registrada
   (IDENTIFICA + REGISTRA ja feitos) nao ha bastao valido para passar.

## Segue
[Orquestracao](../orchestration.md) - [Forja](forja.md) - [Advisor Pattern](advisor-pattern.md) -
[Quality Gate](../governance/quality-gate.md) - [Template do bastao](bastao-template.yaml)
