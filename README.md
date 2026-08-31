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

**Verificacoes automaticas que nao gastam nenhum token de modelo** (262 na versao atual; o
numero exato aparece no fim do smoke) cobrem o motor inteiro: formato do que e entregue, a
conferencia de qualidade, o mapa de conhecimento, a integridade do nucleo, e mais. Nenhuma chama
IA; qualquer pessoa com acesso ao codigo pode rodar de novo e conferir.

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

A identidade e as regras da Alia vivem em `AGENTS.md`, um arquivo de texto aberto - sem trava de
nenhum fornecedor. No Claude Code, o `CLAUDE.md` aponta pra esse arquivo e a Alia assume sozinha;
em outros programas que leem `AGENTS.md` (Codex, OpenCode e outros), o mesmo arquivo e lido
direto.

Hoje essas regras (escolher o especialista certo, passar pelo Quality Gate, lembrar do seu
contexto) funcionam porque a Alia as segue, nao porque existe uma trava tecnica que a impeca de
pular uma etapa - a unica excecao e a escrita no nucleo do sistema, que uma protecao especifica
(`apply-safe-output`) bloqueia de verdade.

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
