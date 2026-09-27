# -*- coding: utf-8 -*-
"""Prova de v2/bin/gate.py (TASK-838): o ponteiro verificavel exigido nos criterios `funciona`
e `goal-backward` quando vem em PASS. Padrao copiado do jkudish/jev-mcp (MIT): "o pedido e a
afirmacao nao sao prova; so a evidencia e". So o PRIMEIRO CORTE (formato do ponteiro, sem
modelo) - a conferencia semantica de que a evidencia sustenta o criterio fica para prova futura.

A medida de justificativa (validador NOVO contra os pareceres historicos reais citados nos
eventos `gate_check` de activity.jsonl) foi reportada ao operador fora deste arquivo - caminho
de scratchpad de sessao e identidade do estudio nunca viram literal no motor publico. Esta prova
reproduz o MESMO padrao medido (evidencia so em frase, sem ponteiro) com fixture sintetica, para
a regressao continuar coberta sem depender de caminho de disco de sessao nenhuma.

Uso: python test_gate.py
"""
from __future__ import annotations

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
V2 = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(V2, "bin"))
sys.path.insert(0, os.path.join(V2, "lib"))
import gate  # noqa: E402

FAILS: list[str] = []


def check(name: str, cond: bool, detail: str = "") -> None:
    status = "PASS" if cond else "FAIL"
    print(f"[{status}] {name} {detail}")
    if not cond:
        FAILS.append(name)


def _parecer_base(funciona_linha: str, goal_backward_linha: str, veredito: str = "PASS") -> str:
    return (
        f"funciona: PASS\n{funciona_linha}\n"
        "aderente-ddd: PASS\nevidencia: revisado contra o DDD do modulo\n"
        "frugal: PASS\nevidencia: sem custo extra de rede\n"
        "rastreavel: PASS\nevidencia: TASK-838 no titulo do commit\n"
        "simplicidade: PASS\nevidencia: menor diff possivel\n"
        "fundamentada: PASS\nevidencia: aderente ao contrato do modulo\n"
        f"{goal_backward_linha}\n"
        f"veredito: {veredito}\n"
    )


# ---------------------------------------------------------------------------
print("=== positivo: comando entre crases conta como ponteiro verificavel ===")
parecer_comando = _parecer_base(
    "evidencia: rodei `python gate.py --task TASK-1 --parecer x.md` e saiu ok",
    "goal-backward: PASS\nevidencia: rodei `python -m pytest test_gate.py` e bateu o objetivo",
)
r = gate.validar_parecer(parecer_comando)
check("nenhum problema quando funciona/goal-backward citam comando entre crases",
      r["problemas"] == [], str(r["problemas"]))

# ---------------------------------------------------------------------------
print("\n=== positivo: caminho de arquivo que EXISTE no disco conta como ponteiro ===")
_gate_py_rel = os.path.relpath(os.path.join(V2, "bin", "gate.py"), HERE).replace("\\", "/")
parecer_caminho = _parecer_base(
    f"evidencia: a funcao nova esta em {_gate_py_rel}:71 conforme pedido",
    f"goal-backward: PASS\nevidencia: objetivo cumprido, ver {_gate_py_rel}",
)
r = gate.validar_parecer(parecer_caminho, parecer_path=os.path.join(HERE, "parecer_fixture.md"))
check("nenhum problema quando o caminho citado (com sufixo :linha) existe no disco",
      r["problemas"] == [], str(r["problemas"]))

# ---------------------------------------------------------------------------
print("\n=== negativo: funciona em PASS so com frase (sem comando, sem caminho que existe) ===")
parecer_frase = _parecer_base(
    "evidencia: testei e funcionou direitinho, ficou tudo certo",
    "goal-backward: PASS\nevidencia: rastreavel a TASK-838 no titulo do commit",
)
r = gate.validar_parecer(parecer_frase)
check("criterio 'funciona' em PASS sem ponteiro vira problema",
      any("funciona" in p and "aponte arquivo" in p for p in r["problemas"]), str(r["problemas"]))

# ---------------------------------------------------------------------------
print("\n=== negativo: goal-backward em PASS so com frase ===")
parecer_frase_gb = _parecer_base(
    "evidencia: rodei `python gate.py --task TASK-1 --parecer x.md`",
    "goal-backward: PASS\nevidencia: o objetivo era X e esta no GitHub, conferido",
)
r = gate.validar_parecer(parecer_frase_gb)
check("criterio 'goal-backward' em PASS sem ponteiro vira problema",
      any("goal-backward" in p and "aponte arquivo" in p for p in r["problemas"]), str(r["problemas"]))

# ---------------------------------------------------------------------------
print("\n=== negativo: caminho citado que NAO existe no disco nao conta como ponteiro ===")
parecer_caminho_falso = _parecer_base(
    "evidencia: implementado em v2/bin/arquivo-que-nao-existe-de-jeito-nenhum.py:10",
    "goal-backward: PASS\nevidencia: rastreavel a TASK-838 no titulo do commit",
)
r = gate.validar_parecer(parecer_caminho_falso)
check("caminho que nao existe no disco NAO conta como ponteiro (funciona ainda reprova)",
      any("funciona" in p and "aponte arquivo" in p for p in r["problemas"]), str(r["problemas"]))

# ---------------------------------------------------------------------------
print("\n=== CONCERN e FAIL nunca exigem ponteiro (so PASS exige) ===")
parecer_concern = (
    "funciona: CONCERN\nevidencia: acho que funciona mas nao tive tempo de rodar\n"
    "aderente-ddd: PASS\nevidencia: revisado contra o DDD do modulo\n"
    "frugal: PASS\nevidencia: sem custo extra de rede\n"
    "rastreavel: PASS\nevidencia: TASK-838 no titulo do commit\n"
    "simplicidade: PASS\nevidencia: menor diff possivel\n"
    "fundamentada: PASS\nevidencia: aderente ao contrato do modulo\n"
    "goal-backward: FAIL\nevidencia: nao bateu o objetivo, por impressao\n"
    "veredito: FAIL\n"
)
r = gate.validar_parecer(parecer_concern)
check("funciona em CONCERN e goal-backward em FAIL sem ponteiro NAO geram o problema de ponteiro",
      not any("aponte arquivo" in p for p in r["problemas"]), str(r["problemas"]))

# ---------------------------------------------------------------------------
print("\n=== prova pelo negativo na propria prova: sem o bloco novo, o parecer-so-frase passaria ===")
# reproduz o comportamento ANTIGO (antes do TASK-838): validar so ate a linha de evidencia
# existir, sem checar ponteiro - usado para provar que o FAIL acima e do bloco novo, nao de
# outra regra que ja existia.
import re as _re  # noqa: E402


def _validar_sem_ponteiro(texto: str) -> list[str]:
    problemas: list[str] = []
    linhas = texto.splitlines()
    for rotulo in gate.TODOS_CRITERIOS:
        idx, valor = gate._linha_rotulo(rotulo, linhas)
        if idx is None:
            problemas.append(f"criterio '{rotulo}' ausente")
            continue
        evidencia = gate._evidencia_logo_apos(idx, linhas)
        if not evidencia:
            problemas.append(f"criterio '{rotulo}' sem evidencia")
    return problemas


problemas_antigos = _validar_sem_ponteiro(parecer_frase)
check("prova negativa: SEM o bloco de ponteiro, o mesmo parecer-so-frase passaria batido",
      problemas_antigos == [], str(problemas_antigos))

# ---------------------------------------------------------------------------
# Justificativa (TASK-838): rodei este mesmo validador contra os pareceres historicos reais
# citados no campo parecer_path dos eventos gate_check de activity.jsonl (medida reportada ao
# operador fora deste arquivo - caminho de scratchpad de sessao e identidade do estudio, nunca
# viram literal no motor publico). O resultado medido: 9 pareceres historicos unicos, os 9
# recusados nos dois criterios por falta de ponteiro. A prova PERMANENTE abaixo reproduz o
# MESMO padrao (evidencia so em frase, sem comando nem caminho) com uma fixture sintetica, para
# a regressao continuar coberta sem depender de caminho de disco de sessao nenhuma.
print("\n=== prova de regressao: padrao historico (evidencia so em frase) continua recusado ===")
parecer_estilo_historico = _parecer_base(
    "evidencia: o objetivo era garantir esse comportamento e ele esta implementado, conferido",
    "goal-backward: PASS\nevidencia: a entrega bateu o objetivo pedido, esta no repositorio",
)
r = gate.validar_parecer(parecer_estilo_historico)
check("parecer no estilo historico (so frase, sem ponteiro) e recusado nos 2 criterios",
      sum(1 for p in r["problemas"] if "aponte arquivo" in p) == 2, str(r["problemas"]))

print("\n=== resultado ===")
if FAILS:
    print(f"FALHOU: {len(FAILS)} prova(s): {FAILS}")
    sys.exit(1)
print("TODAS AS PROVAS PASSARAM")
