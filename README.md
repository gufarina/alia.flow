# Alia Flow

**Um arnes de operador que voce roda no seu proprio agente - a Alia nao entrega a primeira saida do modelo, ela roda um loop ate o resultado passar.**

O modelo virou commodity. O valor nao esta na capacidade crua, e no arnes em volta dela: a memoria que carrega contexto entre tarefas, a mao certa escolhida por trabalho, a conducao do pedido a entrega, e o loop de qualidade que confere e refina antes de o resultado sair. Todo engenheiro acaba montando o seu, ad hoc. O Alia Flow e esse arnes ja pronto - e auditado por teste.

`MIT` - `vendor-neutral por construcao (boot via AGENTS.md)` - `verificacoes deterministicas (veja o smoke: ALL GREEN)` - `prova de ablacao de conhecimento` - versao atual em `VERSION`

> **Pre-requisito: um coding agent.** A Alia mora dentro de um agente de codigo - escolha um e instale antes:
> [Claude Code](https://claude.com/claude-code) - [Codex](https://github.com/openai/codex) - [OpenCode](https://opencode.ai).
> Depois, uma linha instala a Alia:
> `iwr -useb https://raw.githubusercontent.com/gufarina/alia.flow/main/scripts/install.ps1 | iex`

---

## Voce sempre quis usar IA. Agora e so dizer o que precisa.

Voce viu todo mundo usando e ficou com a impressao de que era pra quem entende de tecnologia. Voce ate tentou, e parou na mesma parede: parecia que primeiro era preciso aprender a operar uma engrenagem, achar as palavras certas, virar meio tecnico. Entao desistia e voltava a fazer na mao.

Aqui e diferente em dois pontos. Voce diz o resultado que precisa, em palavras comuns - como pediria a uma pessoa de confianca. E o que volta nao e o primeiro rascunho: e a versao que ja passou por uma conferencia e foi ajustada ate ficar boa. Nada para aprender, nada para configurar. A forca da IA, sem o manual.

> Esse e o produto que se monta sobre este arnes. O que vem abaixo e o motor, para quem vai ler o codigo.

---

## Por que isto existe (origem)

O cenario sempre foi solto. Varios frameworks agenticos, cada um puxando para um lado, e nenhum deles focado em gerar valor de verdade - em otimizar dentro de uma empresa ou de um workflow real. Eram pecas soltas, demos bonitas, nao um sistema que entrega resultado e responde por ele.

Eu queria a outra coisa: nao mais um framework de agentes, e sim o arnes em volta do modelo, focado em valor e em quem nao e tecnico - a pessoa que tem a visao mas nao deveria precisar virar engenheiro para usar IA. Entao fui montando o meu. Este e o Alia Flow.

## O que e

Uma **orquestradora** (a Alia) que roda um loop de qualidade. Ela recebe trabalho delegado em linguagem comum, registra a tarefa, e gira o ciclo antes de devolver:

- **Produz** - escolhe o especialista certo do squad e o faz carregar o segundo cerebro do dominio antes de produzir o primeiro resultado.
- **Avalia** - cobra o artefato e passa pelo Quality Gate. Nada sai cru.
- **Refina** - o que nao passou volta para correcao e nova avaliacao, ate aprovar.
- **Aprende** - o resultado de cada volta vira memoria do cliente; a proxima volta comeca melhor que a de hoje.

A tese central do produto e essa: qualidade nao e prometida, e loopada ate existir. A Alia nao mostra o primeiro esboco - so o que ja passou pela conferencia.

O boot acontece via `AGENTS.md` - sobre arquivos abertos (`.md`, `.ps1`, `.yaml`). Sem config travada de fornecedor, sem lock-in. Abriu a pasta no seu agente, virou a Alia. Vendor-neutral por **construcao**: o motor sao arquivos abertos lidos no boot, nao um plugin amarrado a um unico fornecedor.

## A prova: a memoria muda o resultado, e da pra medir

A afirmacao mais barata do mercado de IA e "memoria melhora o output". Quase ninguem prova. O Alia Flow prova por ablacao - mesmo briefing, mesma cadeia, a unica variavel e o acesso ao segundo cerebro:

- **Braco cego** (sem o segundo cerebro): cobertura dos termos do cliente **0 de 5 (0%)**.
- **Braco informado** (com o segundo cerebro carregado): cobertura **5 de 5 (100%)**.
- **Ganho: 5**, num limiar de aprovacao de **3**.

A pontuacao sai de um scorer Python deterministico (`tests/knowledge-ablation/score.py`), nao de um juiz LLM. E uma prova **causal**, nao uma narrativa: voce roda na sua maquina e ve o numero.

### Como provar voce mesmo

Sem instalador. Voce clona, roda o trilho e olha o verde.

```sh
git clone <repo> alia-flow
cd alia-flow

# O trilho: todas as verificacoes deterministicas, sem agente - inclui a ablacao.
powershell -ExecutionPolicy Bypass -File scripts/smoke-test.ps1
#   -> todos [PASS], "ALL GREEN", exit 0.
#   A ablacao (T14) roda o scorer Python contra o cliente demo; o material esta em
#   studio.example/clients/acme-saas/tests/knowledge-ablation/ (test.yaml, score.py,
#   out-blind.md vs out-informed.md, RESULT.md).
```

O smoke test roda em PowerShell, sem agente nenhum: confere a engine, a instancia de exemplo, os squads, o grafo, os artefatos, os gates, a memoria, a consistencia de estado e a ablacao - de uma vez. Verde quer dizer que o ciclo inteiro fecha com evidencia em disco, nao que "deveria funcionar".

Para ver o arnes operando, abra a pasta no seu agente (ele le o `AGENTS.md`) e delegue um trabalho contra o cliente de exemplo `acme-saas`.

## O que tem dentro

| Peca | O que e (honesto) |
|------|-------------------|
| **O loop de qualidade** | O motor. A Alia gira produz -> avalia -> refina -> aprende e so deixa sair o que passou. Os principios abaixo sao papeis dentro dessa volta. |
| **Roteamento por capacidade (produz)** | A Alia quebra o trabalho em unidades delegaveis e roteia cada uma pro especialista mais capaz - nao faz com as proprias maos. Contrato que ela segue no boot, nao regra travada em runtime. |
| **Segundo cerebro em camadas + grafo** | O knowledge de cada cliente, mais o Graphify: um grafo de conhecimento real que alimenta o recall. E o conhecimento que move a cobertura de 0/5 para 5/5 na ablacao. |
| **Quality Gate (avalia)** | Toda entrega passa por um juiz: Funciona, DDD, Frugal, Rastreavel e Atrito, mais o contrato de formato. Verdict Pass / Concerns / Fail com evidencia. Pass libera; Fail volta pro refino. |
| **Expert Minds** | Mestres reais carregados por dominio - Ogilvy, Kent Beck, Brad Frost, Eugene Schwartz, Sean Ellis. Cada especialista herda a metodologia do mestre do seu campo antes de produzir. Usados em entregas reais no demo. |
| **Ciclo E2E com evidencia** | Task -> Artifact -> verdict -> memory, completo e rastreavel em disco no cliente demo `acme-saas`. |

### Capacidades deterministicas a custo zero de token

Cada uma e um script que executa um contrato que antes era so prosa lida - sem chamar modelo:

- **validate-artifact** - confere o FORMATO do entregavel contra o contrato do seu tipo (copy, story, json, migration, component) antes de gastar julgamento caro. Format-before-content: a estrutura barata reprova antes do conteudo.
- **state-resume** - le o diario append-only de eventos da tarefa e aponta de onde retomar. Run multi-passo que morre no meio nao recomeca do zero - continua do ultimo passo bom.
- **apply-safe-output (porta de escrita segura)** - executa o `block_when` do manifesto: automacao nunca escreve direto no nucleo; muda o motor so o operador. Fail-closed na duvida.
- **sanitize-input** - neutraliza texto perigoso na borda (tags, mentions, URIs nao-HTTPS, control chars, limite de tamanho) antes do payload virar comando. Roda sob demanda, nunca no boot.

Essas, somadas aos guardrails de qualidade e aos checks de integridade, formam as **verificacoes deterministicas que rodam a custo zero de token de modelo** (99 na versao atual; o numero exato aparece no fim do smoke) - todas re-rodaveis pelo smoke test, nenhuma chama IA.

### Nota de honestidade para quem le o codigo

Roteamento por capacidade, o Quality Gate e a memoria tipada com validade sao **contrato que a Alia segue**, descrito em arquivos abertos que ela carrega no boot - nao regra travada em runtime. O sistema nao *impede* fisicamente um desvio (com a excecao da porta de escrita acima, que e mecanica). A prova de que o contrato vale esta na ablacao e nos gates versionados: resultado observavel, nao promessa.

## O que ainda NAO faz

A parte que costuma estar escondida nos READMEs. Aqui esta explicita, de proposito:

- **Delegacao portavel entre CLIs ainda em andamento.** O boot via `AGENTS.md` e vendor-neutral por construcao, e o fluxo esta validado no Claude Code. Rodar a delegacao plenamente no Codex / opencode e outros agentes esta no roadmap (OPP-42), nao garantido hoje.
- **Allow-list de tools so declarada.** A lista de ferramentas por persona esta declarada nos manifestos, mas o enforcement em runtime ainda nao existe - hoje e contrato, nao trava.
- **Descoberta-vira-task adiada.** A Alia ainda nao transforma uma descoberta sua em tarefa por conta propria; isso fica para depois.
- **Sem instalador de um clique pleno.** Existe `install.ps1`, mas o `alia init` que pergunta o nome do studio e configura tudo sozinho ainda nao esta completo.
- **Prova so com o demo.** O ciclo E2E e provado apenas com o cliente de exemplo `acme-saas`, como vitrine do fluxo. Escala multi-cliente nao e parte do que esta aberto.
- **Benchmark de loop-quality a construir.** A ablacao mede o lift do contexto (0/5 -> 5/5). O ganho do proprio loop - 1a volta vs pos-refino - ainda nao tem benchmark; e projecao a medir, nao numero anunciado.

Se algo acima virar verde, vira um teste no trilho antes de virar uma frase aqui.

## Licenca e creditos

[MIT](LICENSE) (c) Studio Farina.

O Alia Flow se apoia em frameworks, metodos e mestres que vieram antes - **aiox**, **BMAD-METHOD**, Domain-Driven Design, **ponytail** (Dietrich Gebert, MIT) e outros. Os Expert Minds carregam a metodologia publica de mestres reais de cada campo (Ogilvy, Kent Beck, Brad Frost, Eugene Schwartz, Sean Ellis) - credito a eles pelo metodo; a implementacao e nossa. Os creditos e fontes completos estao em [CREDITS.md](CREDITS.md).

---

*Voce diz o resultado. A Alia roda o loop. O gargalo deixa de ser voce.*
