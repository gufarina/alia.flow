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
tres modos (sugerir -> criar -> revisar), e fecha ligando ao mecanismo `scripts/install-loops.ps1`.
Cada passo aponta o proximo:

| Passo | Skill / modo | Entrada | Saida | Sugere o proximo |
|-------|--------------|---------|-------|------------------|
| 1. sugerir | loop-designer (modo sugerir) | perfil do projeto (client.md, squad.yaml, state.json) | Plano de Loops + justificativa + custo somado | "Aprovar o Plano? -> passo 2 (criar)" |
| 2. criar | loop-designer (modo criar) | Plano aprovado | `clients/{id}/loops.yaml` gravado (UTF-8 sem BOM) | "loops.yaml pronto -> passo 3 (instalar mecanismo)" |
| 3. instalar | scripts/install-loops.ps1 | loops.yaml | tarefas agendadas (dry-run por padrao; -Install para valer) | "dry-run OK? -> rodar com -Install; depois agendar revisao" |

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
  |       -> sugere: "loops.yaml gravado. Instalar os agendados? (passo 3)"
  |
  |- [3] scripts/install-loops.ps1 -Client {id}
          le o loops.yaml e cria as tarefas (DRY-RUN por padrao)
          -> sugere: "dry-run conferido. Rodar -Install para valer;
                      na data de review_on, voltar ao loop-designer:revisar"
```

O passo 3 fecha o ciclo apontando de volta para o modo `revisar` da propria skill quando chega o
`review_on` - o encadeamento e um anel, nao uma linha morta. Nenhum passo avanca sem o veredito do
anterior: o operador aprova o Plano antes de criar, e confere o dry-run antes do `-Install`.

### Por que e frugal

O passo 3 e um colapso de pipeline em CLI (tools.md:43-51): em vez de N chamadas tagarelas para
agendar cada tarefa, `install-loops.ps1` le o yaml e gera a config num passo, e o unico custo de
contexto e o stdout. Os passos 1 e 2 ramificam por julgamento (precisam de aprovacao), entao ficam
como passos conversados; o passo 3 e deterministico, entao vira um comando. E a regra do Frugality
Check passo 4 (mecanico antes de julgamento) aplicada ao encadeamento inteiro.

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
