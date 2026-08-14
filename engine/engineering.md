# Alia - Padroes de Engenharia

> Como o codigo nasce no Alia Flow. Na era da IA que gera muito, o gargalo nao e velocidade - e
> entropia. Estes padroes sao limitadores de velocidade que forcam incrementos testaveis e mantem
> a codebase navegavel.

---

## Disciplina (os 4 principios)

1. **Pensar antes de codar** - declarar suposicoes e tradeoffs. Se ha mais de uma interpretacao,
   apresente-as; nao escolha em silencio. Se ambiguo, faca UMA pergunta cirurgica.
2. **Simplicidade primeiro** - o codigo minimo que resolve o Job; nada especulativo. Sem abstracao
   pra uso unico, sem flexibilidade que ninguem pediu. 200 linhas que cabem em 50, reescreva.
3. **Mudancas cirurgicas** - toque so o que a Task exige. Nao refatore o que nao esta quebrado, nao
   "melhore" codigo adjacente, siga o estilo existente. Cada linha mudada rastreia ao pedido.
4. **Goal-driven** - criterios de sucesso verificaveis antes de comecar; loop ate verificar.

> O teste de cada mudanca: toda linha alterada traca direto ao pedido do Operator. O que nao traca,
> sai do diff.

## Escada da simplicidade

Operacionaliza o principio 2. Antes de escrever codigo, suba a escada na ordem e PARE no primeiro
degrau que ja resolve - so desce pro proximo quando o de cima nao serve:

1. Isso precisa existir? (YAGNI - corta o especulativo)
2. Resolve com a biblioteca padrao?
3. Com recurso nativo da linguagem/plataforma?
4. Com uma dependencia ja instalada?
5. Da pra ser uma linha?
6. So entao: o minimo de codigo proprio.

Regra de corte: nenhuma abstracao que nao foi pedida; deletar antes de adicionar.

Quando a simplificacao for DELIBERADA, marque com um comentario `frugal-debito:` declarando o teto
da escolha e o caminho de upgrade. Ex.: `// frugal-debito: lista linear; teto ~1k itens; trocar por
indice se crescer`. Assim a simplificacao fica visivel e revisavel - parece uma decisao, nao um
buraco.

> Escada e convencao adaptadas do skill ponytail (Dietrich Gebert, MIT) - ver CREDITS; o marcador de
> comentario chama-se `frugal-debito:` no nosso motor (nao `ponytail:`). Versao generalizada para
> qualquer Artifact (nao so codigo): [artifact-ladder.md](features/artifact-ladder.md). O motor ja
> vivia o principio (REUSE>ADAPT>CREATE, modulos profundos, criterio 5 do Gate); isto so o torna
> operacional, sem peso novo.

## IDS - Desenvolvimento Incremental

**REUSE > ADAPT > CREATE.** Antes de criar, consulte o registro do que ja existe. A regra do
encaixe (fit) decide a rota:

| Rota | Fit | O que fazer |
|------|-----|-------------|
| **Reuse** | >= 90% | Usar direto, sem copia. |
| **Adapt** | 60-89% | Estender com mudanca <= 30%, sem quebrar consumidores, documentar a adaptacao. |
| **Create** | < 60% | Justificar (nada serviu) e registrar o novo pra proxima Task reusar. |

> Criar sem checar o registro e o anti-pattern mais caro: duplica logica, multiplica bug e cega a
> proxima reutilizacao. Create e a ultima opcao, nao a primeira.

O "registro" do Reuse tem endereco por squad: a pasta `knowledge/examples/` (examples padrao-ouro).
Consulte-a ANTES de criar - convencao em [Examples-driven](features/examples-driven.md).

## Modulos profundos, nao rasos

Interface estreita, complexidade interna alta (Ousterhout). Um modulo profundo expoe pouco e
encapsula muito; um raso expoe muito e so delega. Indicador de profundidade: <= 5 exports publicos,
regra de negocio encapsulada, teste na interface (nao nos internals). Modulo novo com mais de 5
exports publicos exige justificativa - senao e sinal de "God Service" e reprova no Gate.

## Git

Conventional commits (`feat:`, `fix:`, `docs:`, `refactor:`...), atomicos, cada um com referencia da
Task. Commit de teste antes do commit de implementacao quando houver TDD. `git push` e **exclusivo
do DevOps**.

## Erros

`try/catch` com contexto claro; nunca engolir erro em silencio. Falha vira evidencia (log, mensagem,
proximo passo), nao desaparece. Sem tratamento de erro pra cenario impossivel - isso e ruido.

## Gates de engenharia

Toda entrega de codigo passa pelos Gates antes de virar Artifact. Sao a forma operacional do
Quality Gate da Constituicao aplicada ao codigo: simplicidade, mudanca cirurgica, IDS respeitado,
modulo profundo, erro tratado, evidencia presente. O que reprova volta pro autor, nao pro Operator.

## Segue

[Constituicao](constitution.md) - os Principios. [Persona](agents/persona.md) - a voz.
[Arquitetura](../docs/architecture/ARCHITECTURE.md) - o desenho do sistema.
