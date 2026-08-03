# Benchmarks deterministicos do Alia Flow

Scripts re-rodaveis, sem LLM, sem rede. Cada um imprime linhas `METRIC ...` com o numero
REAL e um `VERDICT: PASS/FAIL` (exit 0/1). Sao a prova por tras das promessas de performance
do produto. Regra do CEO: so vira promessa o que um benchmark sustenta.

## Como re-rodar

Esta pasta vai dentro do pacote publico: da para rodar tudo na sua propria maquina, sem rede e
sem chave de API. Da raiz do produto (a pasta que tem `engine/`, `scripts/` e `VERSION`):

```
python benchmarks/run-all.py
```

Ou um por vez:

```
python benchmarks/bench_knowledge_lift.py     # Lift de conhecimento (ablacao, REUSA T14)
python benchmarks/bench_zero_token_checks.py  # Verificacoes a custo zero de token (smoke)
python benchmarks/bench_boot_weight.py        # Peso de boot evitado (fast-boot)
python benchmarks/bench_resume_steps.py       # Passos nao re-rodados na retomada
python benchmarks/bench_library_ondemand.py   # Razao nucleo vs biblioteca sob demanda
```

Requisitos: Python 3 e PowerShell (so o bench de smoke chama `scripts/smoke-test.ps1`).

## O que cada bench mede

> Os numeros abaixo sao a ultima medicao [MEDIDO 2026-08-02, v1.39.0], nao uma promessa: eles
> mudam quando o produto muda. O que vale e a saida que o script imprime na SUA maquina - se
> divergir daqui, a sua saida e que esta certa e este arquivo e que esta velho.

1. **bench_knowledge_lift** - NAO reinventa: re-roda `score.py` de T14
   (`studio.example/clients/acme-saas/tests/knowledge-ablation/`) e reporta cobertura de
   termos da linguagem ubiqua no braco cego (sem segundo cerebro) vs informado (com segundo
   cerebro), o ganho e o limiar. Numero real: 0 -> 5 termos (de 5), ganho 5, limiar 3.

2. **bench_zero_token_checks** - roda o smoke inteiro e captura `Checks: N PASS`. Todas as
   checagens sao deterministicas (sem chamar modelo). Confirma as 4 Frugal Skills como
   scripts `.ps1` (exit 0/1). Ultima medicao: **152 PASS, 0 FAIL, ALL GREEN**. Este numero
   SOBE a cada versao (99 na v1.15, 135 na v1.37.1, 152 na v1.39.0), porque cada regra nova
   entra com a verificacao que a prova - por isso a copy publica usa piso ("mais de 150") e o
   numero exato so sai daqui.

3. **bench_boot_weight** - soma os caracteres dos 4 docs de nucleo que o fast-boot NAO abre
   para responder uma saudacao, e estima tokens como chars/4 (APROXIMADO). Ultima medicao:
   43898 chars (~11.0k tokens aprox).

4. **bench_resume_steps** - usa o journal `events[]` do `state.json` do demo. Trunca a Task
   no passo MONITORA (i=4 de K=5) e mostra que o resume re-roda 0 passos concluidos (vs 4
   sem journal). Garantia ESTRUTURAL; expressa em passos-nao-re-rodados (nao em tokens).

5. **bench_library_ondemand** - razao do nucleo (4 docs) sobre toda a prosa do motor
   (`engine/*.md`). Ultima medicao: nucleo = 17% do motor (43898 de 262826 caracteres, 54
   documentos); 83% fica fora do boot (sob demanda).

## Confianca (rotulo em cada metrica)

- SOLIDO    - numero medido por script re-rodavel, com teste-fonte (ex.: ablacao T14, smoke).
- DIRECIONAL - numero real, mas com estimativa embutida (ex.: tokens ~ chars/4) ou derivado
              de um demo unico (resume).
- NAO-SUPORTADO - nao ha benchmark; nao pode virar promessa (ex.: "% de reducao de codigo").
