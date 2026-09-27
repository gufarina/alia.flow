# -*- coding: utf-8 -*-
"""Prova de v2/bin/gate.py (TASK-838): o ponteiro verificavel exigido nos criterios `funciona`
e `goal-backward` quando vem em PASS. Padrao copiado do jkudish/jev-mcp (MIT): "o pedido e a
afirmacao nao sao prova; so a evidencia e". So o PRIMEIRO CORTE (formato do ponteiro, sem
modelo) - a conferencia semantica de que a evidencia sustenta o criterio fica para prova futura.

Tambem roda o validador NOVO sobre os 8 pareceres historicos citados nos eventos `gate_check`
de activity.jsonl (a medida de justificativa da mudanca) e imprime [MEDIDO] com o resultado -
nunca falha o check.py por isso (pareceres historicos nasceram sob o contrato ANTIGO, sem
ponteiro; reprovar agora e o EFEITO ESPERADO da mudanca, nao uma regressao).

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
print("\n=== medida de justificativa: validador NOVO sobre os 8 pareceres historicos "
      "(campo parecer_path dos eventos gate_check em activity.jsonl) ===")
PARECERES_HISTORICOS = [
    r"C:\Users\LITEOS~1\AppData\Local\Temp\claude\C--Users-Lite-OS-Projetos-studio-farina"
    r"\20c80adf-be0f-4d63-9ae0-7a380fb85732\scratchpad\pareceres\TASK-822.md",
    r"C:\Users\LITEOS~1\AppData\Local\Temp\claude\C--Users-Lite-OS-Projetos-studio-farina"
    r"\20c80adf-be0f-4d63-9ae0-7a380fb85732\scratchpad\pareceres\TASK-823.md",
    r"C:\Users\LITEOS~1\AppData\Local\Temp\claude\C--Users-Lite-OS-Projetos-studio-farina"
    r"\20c80adf-be0f-4d63-9ae0-7a380fb85732\scratchpad\pareceres\TASK-824.md",
    r"C:\Users\LITEOS~1\AppData\Local\Temp\claude\C--Users-Lite-OS-Projetos-studio-farina"
    r"\20c80adf-be0f-4d63-9ae0-7a380fb85732\scratchpad\pareceres\TASK-825.md",
    r"C:\Users\LITEOS~1\AppData\Local\Temp\claude\C--Users-Lite-OS-Projetos-studio-farina"
    r"\20c80adf-be0f-4d63-9ae0-7a380fb85732\scratchpad\pareceres\TASK-826.md",
    r"C:\Users\LITEOS~1\AppData\Local\Temp\claude\C--Users-Lite-OS-Projetos-studio-farina"
    r"\20c80adf-be0f-4d63-9ae0-7a380fb85732\scratchpad\pareceres\TASK-827.md",
    r"C:\Users\LITEOS~1\AppData\Local\Temp\claude\C--Users-Lite-OS-Projetos-studio-farina"
    r"\20c80adf-be0f-4d63-9ae0-7a380fb85732\scratchpad\pareceres\changelog-2.0.1.md",
    r"C:\Users\LITEOS~1\AppData\Local\Temp\claude\C--Users-Lite-OS-Projetos-studio-farina"
    r"\28f69224-8c56-416d-9210-4198a9256af9\scratchpad\parecer-TASK-837.md",
    r"C:\Users\LITEOS~1\AppData\Local\Temp\claude\C--Users-Lite-OS-Projetos-studio-farina"
    r"\a6f1190f-ffaf-4e36-a859-bb0492d7bc4d\scratchpad\jev\parecer-TASK-830.md",
]
_recusados = 0
_faltando = 0
for _p in PARECERES_HISTORICOS:
    if not os.path.isfile(_p):
        _faltando += 1
        print(f"[LIDO] parecer historico nao encontrado no disco (scratchpad de sessao expirou): {_p}")
        continue
    with open(_p, "r", encoding="utf-8", errors="replace") as _fh:
        _texto = _fh.read()
    _r = gate.validar_parecer(_texto, parecer_path=_p)
    _so_ponteiro = [pr for pr in _r["problemas"] if "aponte arquivo" in pr]
    if _so_ponteiro:
        _recusados += 1
        print(f"[MEDIDO] recusado por ponteiro: {os.path.basename(_p)} -> {_so_ponteiro}")
    else:
        print(f"[MEDIDO] aceito (com ponteiro valido ou criterio nao PASS): {os.path.basename(_p)}")
print(f"[MEDIDO] total: {len(PARECERES_HISTORICOS)} pareceres historicos, "
      f"{_recusados} recusados por falta de ponteiro, {_faltando} nao encontrados no disco")

print("\n=== resultado ===")
if FAILS:
    print(f"FALHOU: {len(FAILS)} prova(s): {FAILS}")
    sys.exit(1)
print("TODAS AS PROVAS PASSARAM")
