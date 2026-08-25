![Alia Flow](docs/assets/banner.svg)

# Alia Flow

*O arnes de operador que voce roda dentro do seu proprio coding agent: nao entrega o primeiro
rascunho, entrega o que passou pela conferencia.*

---

`MIT` - `versao atual em` [`VERSION`](VERSION) - `Windows (PowerShell 5.1+); Mac/Linux ainda nao validados` - `verificacoes deterministicas, sem chamar IA (numeros abaixo)`

---

**Verificacao deterministica sem agente, rastreabilidade obrigatoria de tarefa a entrega, e um
freio na porta de saida com prova real em log.** Sem benchmark de performance fabricado. Ver
[Numeros](#numeros).

---

## Antes / depois

O mesmo pedido, dois caminhos.

**"Escreva a copy da landing do Painel Pulse."**

| | Chat generico | Alia Flow |
|---|---|---|
| Registro | Nenhum. A conversa some quando a aba fecha. | Vira uma Task amarrada a um cliente e um projeto antes de comecar (`register-task.ps1`). |
| Contexto | So o que voce colar na hora. | O especialista carrega o segundo cerebro do cliente (glossario, exemplos, Expert Mind) antes de escrever. |
| Saida | O primeiro texto que o modelo gerar. | Passa pelo Quality Gate (5 criterios + veredito) antes de sair; o que nao passa volta para refino. |
| Memoria | Nenhuma. Amanha comeca do zero. | Vira nota de memoria que a proxima Task do mesmo cliente reaproveita. |

Nao e metrica de performance, e diferenca de PROCESSO - e da para conferir em disco: o exemplo
real inteiro (Task, Artifact, Gate, memoria) esta em
[`studio.example/clients/acme-saas/artifacts/ART-001-landing-copy.md`](studio.example/clients/acme-saas/artifacts/ART-001-landing-copy.md)
e no gate correspondente,
[`ART-001.gate.md`](studio.example/clients/acme-saas/artifacts/gates/ART-001.gate.md).

---

## Numeros

Tres numeros, cada um com a prova ao lado - nenhum e projecao.

### Verificacoes deterministicas

![Verificacoes deterministicas](docs/assets/chart-verificacoes.svg)

**Verificacoes deterministicas que rodam a custo zero de token de modelo** (243 na versao atual;
o numero exato aparece no fim do smoke) cobrem o motor completo da oficina - formato de artefato,
Quality Gate, grafo de conhecimento, guards de veto, allow-list, integridade do nucleo e mais.
Nenhuma chama IA; todas re-rodaveis por qualquer pessoa com acesso ao codigo.

```sh
git clone https://github.com/gufarina/alia.flow.git alia-flow
cd alia-flow
powershell -ExecutionPolicy Bypass -File scripts/smoke-test.ps1
#   -> uma linha por check, "Checks: X PASS, Y FAIL" no fim.
```

### Demonstracao de memoria (ilustrativa, nao prova)

![Demonstracao de memoria](docs/assets/chart-memoria.svg)

Cobertura dos termos do cliente: **0 de 5 (0%)** sem o segundo cerebro carregado, **5 de 5
(100%)** com ele carregado. Honestidade sobre o que isto e: as duas respostas
(`out-blind.md` e `out-informed.md`) foram escritas a mao para ilustrar o padrao esperado, nao
geradas por um agente respondendo de verdade duas vezes. O scorer conta, de forma deterministica,
se as 5 palavras-chave aparecem no texto - isso prova que o SCORER funciona, nao que a memoria
muda a saida de um agente real. O scorer e
`studio.example/clients/acme-saas/tests/knowledge-ablation/score.py`; a prova completa esta em
[`studio.example/clients/acme-saas/tests/knowledge-ablation/README.md`](studio.example/clients/acme-saas/tests/knowledge-ablation/README.md).

### Freio de saida

![Freio de saida](docs/assets/chart-freio.svg)

Em **121 turnos** observados na operacao real, o freio de saida (`response-guard.ps1`) bloqueou
**1 vez** por falta de delegacao e **7 vezes** por afirmacao sem fonte citada - cada bloqueio com
hora e motivo em log. Amostra pequena, citada com o numero, nunca como cobertura total.

---

## Como funciona

A Alia recebe um pedido em linguagem comum e gira um ciclo antes de devolver qualquer coisa:

1. **Produz** - escolhe o especialista certo do squad e o faz carregar o segundo cerebro do
   dominio antes do primeiro resultado.
2. **Avalia** - o resultado passa pelo Quality Gate (Funciona, DDD, Frugal, Rastreavel, Atrito).
   Nada sai cru.
3. **Refina** - o que nao passou volta para correcao e nova avaliacao, ate aprovar.
4. **Aprende** - o resultado vira memoria do cliente; a proxima volta comeca melhor que a de hoje.

A identidade e o protocolo vivem em `AGENTS.md` - arquivos abertos (`.md`, `.ps1`, `.yaml`), sem
config travada de fornecedor. No Claude Code, `CLAUDE.md` importa esse `AGENTS.md` (a
documentacao oficial confirma: Claude Code le `CLAUDE.md`, nao `AGENTS.md` direto); nos demais
agentes que leem `AGENTS.md` (Codex, OpenCode, Aider, outros), o boot e o proprio arquivo, lido
direto. Roteamento por capacidade, o Quality Gate e a memoria com validade sao contrato que a
Alia segue, descrito em arquivos que ela carrega no boot - nao regra travada em runtime, com uma
excecao mecanica: a porta de escrita segura (`apply-safe-output`) bloqueia de fato automacao
escrevendo no nucleo.

---

## Instalacao

Pre-requisito: um coding agent instalado. A Alia mora dentro dele, nao roda sozinha.

> Repositorio em beta fechado hoje - a linha de instalacao abaixo passa a responder quando a
> visibilidade abrir, sem data prometida. Sistema operacional: so Windows (PowerShell 5.1+) foi
> provado; Mac/Linux ainda nao validados (OPP-22).

**[Claude Code](https://claude.com/claude-code)** - fluxo completo validado ponta a ponta:

```sh
iwr -useb https://raw.githubusercontent.com/gufarina/alia.flow/main/scripts/install.ps1 | iex
```

Abra a pasta no Claude Code. O `CLAUDE.md` importa o `AGENTS.md` e a Alia assume sozinha; se nao
acontecer, rode `/alia`.

**[Codex](https://github.com/openai/codex)** - parcial:

```sh
iwr -useb https://raw.githubusercontent.com/gufarina/alia.flow/main/scripts/install.ps1 | iex
```

Le o `AGENTS.md` direto e assume a persona. Delegacao portavel entre coordenador e especialista
ainda nao validada aqui (OPP-42).

**[OpenCode](https://opencode.ai)** - parcial:

```sh
iwr -useb https://raw.githubusercontent.com/gufarina/alia.flow/main/scripts/install.ps1 | iex
```

Mesma base do Codex: le `AGENTS.md`, assume a persona, mesma ressalva de delegacao portavel.

**Outro agente que leia `AGENTS.md`** - basico, sem garantia de sub-agentes isolados nem hooks de
lifecycle.

Detalhe completo do que funciona e do que degrada por agente:
[docs/COMPATIBILIDADE.md](docs/COMPATIBILIDADE.md).

---

## Comandos

| Comando | O que faz |
|---|---|
| `powershell -ExecutionPolicy Bypass -File scripts/install.ps1` | Instala numa pasta vazia: baixa, descompacta, transacional (backup + rollback se falhar no meio). |
| `powershell -ExecutionPolicy Bypass -File scripts/update-online.ps1 -Check` | Confere se ha versao nova do motor, sem aplicar nada. |
| `powershell -ExecutionPolicy Bypass -File scripts/update-online.ps1` | Atualiza o motor sem tocar nos dados do operador (studio, clients, memory); backup antes, rollback automatico se o smoke ficar vermelho depois. |
| `powershell -ExecutionPolicy Bypass -File scripts/smoke-test.ps1` | Roda o trilho completo de verificacoes deterministicas (o numero da secao Numeros). |
| `powershell -ExecutionPolicy Bypass -File scripts/doctor.ps1` | Diagnostico read-only da instalacao (estrutura, versao vs changelog, config, trilho). `-Json` para saida de maquina. |
| `powershell -ExecutionPolicy Bypass -File scripts/verify-manifest.ps1 -Dir .` | Confere o `MANIFEST.sha256` do pacote baixado, arquivo por arquivo (integridade, nao autenticidade - ver [docs/INTEGRIDADE.md](docs/INTEGRIDADE.md)). |
| `powershell -ExecutionPolicy Bypass -File scripts/git-sync.ps1 -Repo usuario/repo -DryRun` | Versiona o seu studio num repositorio GitHub sem precisar de git instalado (so um token). Tire o `-DryRun` para enviar de verdade. |
| `powershell -ExecutionPolicy Bypass -File scripts/mission-control.ps1` | Gera o painel HTML estatico com o estado das Tasks (quem pediu, o que saiu, veredito do Gate). |
| `python benchmarks/run-all.py` | Roda os 5 benchmarks deterministicos (sem rede, sem chave de API) que sustentam as promessas de performance estrutural do produto. |

---

## Perguntas frequentes

**Por que mais um framework de agente?**
Nao e um framework de agente. E o arnes em volta do modelo: memoria entre tarefas, escolha da
mao certa por trabalho, e um loop de qualidade que confere e refina antes de o resultado sair.
Todo engenheiro acaba montando o seu, ad hoc - este e o que ja vem pronto e auditado por teste.

**O repositorio esta aberto para clonar agora?**
Nao. Esta em beta fechado hoje; a URL de instalacao publica responde 404 nesta data. A linha de
instalacao deste README passa a funcionar quando a visibilidade abrir, sem data prometida.

**Funciona no Mac ou Linux?**
Ainda nao foi validado. O trilho de verificacao (CI incluso) roda hoje so em Windows com
PowerShell 5.1+. Suporte a Mac/Linux e evolucao declarada (OPP-22), sem data.

**Preciso saber programar para usar?**
Nao para operar: voce pede em portugues comum, dentro do seu coding agent. Mas voce precisa ter
um coding agent instalado primeiro - o Alia Flow mora dentro dele, nao roda sozinho.

**A demonstracao de memoria prova que a memoria muda a saida de um agente real?**
Nao. As duas respostas foram escritas a mao para ilustrar o raciocinio esperado; o scorer conta
palavras-chave de forma deterministica, o que prova que o MEDIDOR funciona, nao que um agente
real produz output diferente com e sem memoria. Rodar esse experimento de verdade e passo futuro
declarado, nao numero anunciado.

**Existe benchmark de performance (tokens, velocidade, custo)?**
Nao fabricamos um. O que existe e verificavel: verificacao deterministica sem IA, rastreabilidade
obrigatoria e o freio de saida com amostra real - ver [Numeros](#numeros).

**O roteamento por especialista e o Quality Gate sao trava do sistema, ou so contrato que a Alia segue?**
Contrato descrito em arquivos abertos carregados no boot. O sistema nao impede fisicamente um
desvio, com uma excecao mecanica: a porta de escrita segura (`apply-safe-output`) bloqueia de
fato automacao escrevendo no nucleo. O resto se sustenta pelos gates versionados e pelas
verificacoes do smoke, nao por trava de runtime.

**A allow-list de ferramentas por agente e aplicada de verdade?**
Esta declarada em todo agente executor, mas o enforcement em runtime ainda nao existe hoje - e
contrato lido, nao trava.

**A delegacao funciona igual em qualquer coding agent?**
So no Claude Code o fluxo completo (boot, delegacao com isolamento de contexto, Quality Gate)
esta validado ponta a ponta. Codex e OpenCode leem o `AGENTS.md` e assumem a persona, mas a
delegacao portavel entre coordenador e especialista ainda nao esta validada la (OPP-42).

**O ciclo Task -> Artifact -> Gate -> memoria funciona so no exemplo, ou em qualquer cliente meu?**
O ciclo completo, ponta a ponta, hoje so foi provado com o cliente de demonstracao `acme-saas`
(dentro de `studio.example/`), como vitrine do fluxo. Escala multi-cliente nao faz parte do que
esta provado.

---

## Licenca e creditos

[MIT](LICENSE) (c) The Alia Flow Authors.

O Alia Flow se apoia em frameworks, metodos e mestres que vieram antes - **aiox**,
**BMAD-METHOD**, Domain-Driven Design, **ponytail** (Dietrich Gebert, MIT) e outros. Os Expert
Minds carregam a metodologia publica de mestres reais de cada campo (Ogilvy, Kent Beck, Brad
Frost, Eugene Schwartz, Sean Ellis) - credito a eles pelo metodo, a implementacao e nossa.
Creditos e fontes completos em [CREDITS.md](CREDITS.md). Como contribuir:
[CONTRIBUTING.md](CONTRIBUTING.md).

---

*Voce diz o resultado. A Alia roda o loop. O gargalo deixa de ser voce.*
