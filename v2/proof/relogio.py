# -*- coding: utf-8 -*-
"""relogio.py - as medidas de LATENCIA do hook, isoladas (TASK-870, decisao do CEO).

Antes ficavam dentro do run_proofs.py, que roda no pool paralelo do check.py: medida de relogio disputando CPU
com 12 processos (e com a carga da maquina) reprovava por vizinhanca, nao por defeito do hook. Agora o pool
roda o run_proofs.py com RUN_PROOFS_RELOGIO=adiado (sem estas 3 medidas) e o check.py chama ESTE script em
SERIE, depois do pool. Metas inalteradas: mediana quente < 150 ms; Stop sem entrega < 300 ms; Stop com ledger
de 50 mil linhas < 300 ms. Regra do repete (TASK-858) igual: so remede se estourou o teto, vale a MENOR.

Uso: python relogio.py  (sai 1 se alguma meta estourar)
"""
from __future__ import annotations

import atexit
import json
import os
import shutil
import statistics
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
V2 = os.path.dirname(HERE)
DISPATCH = os.environ.get("RELOGIO_DISPATCH") or os.path.join(V2, "hooks", "dispatch.py")  # mutante da prova pelo negativo
SB = tempfile.mkdtemp(prefix="alia-v2-relogio-")
atexit.register(shutil.rmtree, SB, ignore_errors=True)
FAILS: list[str] = []


def check(nome: str, cond: bool, detalhe: str = "") -> None:
    print(f"[{'PASS' if cond else 'FAIL'}] {nome} {detalhe}")
    if not cond:
        FAILS.append(nome)


def roda(evento: dict, ledger: str, extra: dict | None = None) -> tuple[dict, float]:
    env = {k: v for k, v in os.environ.items() if k not in ("CLAUDE_PROJECT_DIR", "PYTHONNOUSERSITE") and not k.startswith("ALIA_")}  # hook real carrega o site do usuario
    env.update({"ALIA_DELEGATION_WALL_OFF": "1", "ALIA_SPINE_OFF": "1", "ALIA_PULSO": "1", "ALIA_LEDGER_PATH": ledger})
    env.update(extra or {})
    t0 = time.perf_counter()
    p = subprocess.run([sys.executable, DISPATCH], input=json.dumps(evento).encode("utf-8"),
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
    dt = (time.perf_counter() - t0) * 1000
    try:
        return json.loads(p.stdout.decode("utf-8", "replace") or "{}"), dt
    except json.JSONDecodeError:
        return {}, dt


LED = os.path.join(SB, "activity.jsonl")

# 1) mediana quente (mesmo evento e mesma regra do run_proofs)
ev = {"hook_event_name": "PreToolUse", "tool_name": "Write", "session_id": "s-perf",
      "tool_input": {"file_path": "/tmp/perf.txt", "content": "ok"}}
roda(ev, LED)  # aquece o pycache (1 basta: o pool ja o deixou quente)
med = statistics.median([roda(ev, LED)[1] for _ in range(20)])
for _ in range(2):
    if med < 150:
        break
    med = min(med, statistics.median([roda(ev, LED)[1] for _ in range(20)]))
print(f"[MEDIDO] mediana quente (isolada, em serie) = {med:.1f} ms")
check("mediana quente abaixo de 150 ms (meta da secao 1)", med < 150, f"{med:.1f} ms")

# 2) Stop de sessao sem entrega
st_sem = os.path.join(SB, "state_stop.json")
with open(st_sem, "w", encoding="utf-8") as fh:
    json.dump({"tasks": [{"id": "TASK-812", "status": "open", "client": "alia-flow-lab"}]}, fh)
ev_stop = {"hook_event_name": "Stop", "session_id": "s-end-none", "transcript_path": "/x.jsonl"}
dt = roda(ev_stop, LED, {"ALIA_STATE_PATH": st_sem})[1]
for _ in range(2):
    if dt < 300:
        break
    dt = min(dt, roda(ev_stop, LED, {"ALIA_STATE_PATH": st_sem})[1])
check("Stop responde abaixo de 300 ms", dt < 300, f"{dt:.1f} ms")

# 3) Stop com ledger de 50 mil linhas
sys.path.insert(0, os.path.join(V2, "lib"))
import ledger as _ledger  # noqa: E402
led50 = os.path.join(SB, "perf", "activity.jsonl")
os.makedirs(os.path.dirname(led50))
with open(led50, "w", encoding="utf-8") as fh:
    for i in range(50_000):
        fh.write(json.dumps({"v": 1, "ts": i, "event": "post_agent", "session_id": f"s-fill-{i % 500}",
                              "agent_id": f"agent-fill-{i}", "task_id": f"TASK-FILL-{i}", "tokens_total": 10}) + "\n")
t0 = time.perf_counter()
_ledger.session_last_post_agent(led50, "s-fill-1")  # constroi o indice 1x (custo pago aqui)
build = (time.perf_counter() - t0) * 1000
st50 = os.path.join(SB, "perf", "state.json")
with open(st50, "w", encoding="utf-8") as fh:
    json.dump({"tasks": [{"id": "TASK-90001", "status": "open"}]}, fh)
roda({"hook_event_name": "PostToolUse", "tool_name": "Agent", "session_id": "s-perf", "tool_use_id": "tu-perf",
      "tool_input": {"prompt": "TASK-90001 entrega"},
      "tool_response": {"status": "completed", "agentId": "agent-perf", "totalTokens": 10, "totalDurationMs": 5,
                        "totalToolUseCount": 1, "usage": {"input_tokens": 8, "output_tokens": 2}}}, led50)
ev50 = {"hook_event_name": "Stop", "session_id": "s-perf", "transcript_path": "/x.jsonl"}
out50, dt50 = roda(ev50, led50, {"ALIA_STATE_PATH": st50})
for _ in range(2):
    if dt50 < 300:
        break
    dt50 = min(dt50, roda(ev50, led50, {"ALIA_STATE_PATH": st50})[1])
check("Stop com ledger de 50 mil linhas (indice ja construido) responde abaixo de 300 ms", dt50 < 300,
      f"{dt50:.1f} ms (indice construido em {build:.1f} ms)")

if FAILS:
    print(f"FALHOU: {FAILS}")
    sys.exit(1)
print("relogio: TODAS AS MEDIDAS DENTRO DA META")
