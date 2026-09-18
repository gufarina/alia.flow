# Workflow - Command Chaining (um comando orquestra N skills)

> O padrao em que UM comando conduz uma sequencia de skills, e cada passo sugere o proximo - o
> mesmo encadeamento por fases do [Story Cycle](story-cycle.md) e do [QA Loop](qa-loop.md), aplicado
> a skills. O comando nao executa o trabalho cru: ele orquestra, e o stdout de cada passo aponta a
> proxima acao. Definicao executavel ao lado dos workflows irmaos.

---

## A tese

O engine ja encadeia FASES com handoff que sugere o proximo passo: o Story Cycle abre cada fase so
quando o gate da anterior fecha (story-cycle.md:18); o QA Loop liga veredito -> proxima acao
(qa-loop.md:11-18); o Squad Creator devolve handoff explicito `to: alia, next: loop-designer`
(squad-creator.yaml:91-94). O que faltava era esse mesmo padrao no nivel de SKILL: um comando que
orquestra N skills, cada passo declarando qual e o proximo.

Command Chaining materializa isso. As skills ja carregam `trigger` no frontmatter
(skills/loop-designer/SKILL.md:4) - o gancho por onde um comando as encadeia.

## As regras

- O comando ORQUESTRA, nao executa. Cada passo e uma skill (ou um modo de skill) que faz o trabalho;
  o comando so escolhe a rota e passa o handoff compactado adiante (Frugality Check passo 5,
  tools.md:37-39).
- Cada passo SUGERE o proximo. Ao terminar, um passo devolve um veredito ou artefato e aponta a acao
  seguinte - nunca um beco sem saida. E o mesmo "fase -> proximo passo" do Story Cycle.
- O proximo passo e SUGESTAO, nao salto automatico. O operador (ou a Alia) confirma antes de avancar,
  como o GO/NO-GO da fase Validate (story-cycle.md:14). Nenhum passo pula etapa.
- Fronteira intacta. O encadeamento respeita as exclusividades: quem publica e o DevOps
  (devops.yaml:7); o comando nao revive papeis aposentados (`status: retired`, loops.md ciclo de vida)
  nem importa plugins externos inteiros - so o padrao de encadeamento.

## Exemplo real do produto: o comando `*loops`

O comando `*loops` encadeia a skill [loop-designer](../../skills/loop-designer/SKILL.md) pelos seus
tres modos (sugerir -> criar -> revisar). CORTE (10/08/2026, mandato do CEO): nao ha mais passo de
"instalar mecanismo" - o Windows Task Scheduler e o runner que o alimentava (`install-loops.ps1`,
`run-loops.ps1`) foram removidos por completo (estado escondido na maquina, invisivel, nao viaja com
o produto). O unico loop agendado sobrevivente (`memory-curator`) ja tem mecanismo automatico sem
instalacao nenhuma: `scripts/smoke-test-studio.ps1` o chama toda vez que a prova roda.

| Passo | Skill / modo | Entrada | Saida | Sugere o proximo |
|-------|--------------|---------|-------|------------------|
| 1. sugerir | loop-designer (modo sugerir) | perfil do projeto (client.md, squad.yaml, state.json) | Plano de Loops + justificativa + custo somado | "Aprovar o Plano? -> passo 2 (criar)" |
| 2. criar | loop-designer (modo criar) | Plano aprovado | `clients/{id}/loops.yaml` gravado (UTF-8 sem BOM) | "loops.yaml pronto - memory-curator ja roda via smoke-test-studio.ps1; nada a instalar. Na data de review_on, voltar ao modo revisar" |

### O fluxo

```
*loops
  |
  |- [1] loop-designer:sugerir
  |       le o perfil, aplica R0..R6, monta o Plano de Loops
  |       -> sugere: "Plano pronto. Aprovar para criar? (passo 2)"
  |
  |- [2] loop-designer:criar            (so apos aprovacao do operador)
  |       grava clients/{id}/loops.yaml com review_on em cada loop
  |       -> sugere: "loops.yaml gravado. memory-curator ja roda sozinho via
  |                   smoke-test-studio.ps1 - nada a instalar. Na data de
  |                   review_on, voltar ao loop-designer:revisar"
```

O ciclo fecha em 2 passos, nao 3: apontando de volta para o modo `revisar` da propria skill quando
chega o `review_on` - o encadeamento e um anel, nao uma linha morta. Nenhum passo avanca sem o
veredito do anterior: o operador aprova o Plano antes de criar.

### Por que e frugal

A curadoria de memoria e o colapso de pipeline mais barato possivel (tools.md:43-51): em vez de um
agendador de SO separado (infraestrutura, estado escondido, custo de manutencao), ela anda de
carona no pipeline que ja roda sempre - `smoke-test-studio.ps1` chama `memory-curator.ps1 -Validade`
dentro da propria prova, sem passo extra nenhum. O passo 1 ramifica por julgamento (precisa de
aprovacao), entao fica como passo conversado; o passo 2 e deterministico, entao vira um comando. E a
regra do Frugality Check passo 4 (mecanico antes de julgamento) aplicada ao encadeamento inteiro.

## Cuidado: so o padrao, nao o plugin inteiro

O valor aqui e o PADRAO de encadeamento (comando -> skill -> skill -> mecanismo, cada passo sugerindo
o proximo), nao a importacao de fluxos de produto externos. Importar um plugin de PM inteiro pode
reviver papeis ja aposentados e furar a fronteira de provenance
([provenance.md](../governance/provenance.md)). Encadeie as skills do proprio produto; reuse a
TECNICA, nunca copie pacotes externos verbatim.

## Quando usar

| Situacao | Rota |
|----------|------|
| Sequencia fixa de skills do produto, cada uma sugerindo a proxima | Command Chaining (este doc) |
| Fluxo de Story da intencao ao Artifact | [Story Cycle](story-cycle.md) |
| Correcao iterativa apos Gate Fail | [QA Loop](qa-loop.md) |

## Segue

[Story Cycle](story-cycle.md) - [QA Loop](qa-loop.md) - [Loop Designer (skill)](../../skills/loop-designer/SKILL.md) -
[Ferramentas e Frugalidade](../tools.md) - [Provenance](../governance/provenance.md).
