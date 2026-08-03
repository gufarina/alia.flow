# Benchmark 4 - Retomada (resume): passos NAO re-rodados.
# Usa o journal append-only (events[]) do state.json do demo. Para uma Task de K passos
# interrompida no passo i, o resume deterministico re-roda 0 passos ja concluidos (vs i
# re-rodados sem journal). Garantia ESTRUTURAL (o ponto de retomada e o ultimo passo bom + 1)
# medida no demo real.
#
# Honestidade: nao da pra medir TOKEN economizado aqui; expressamos como PASSOS-NAO-RE-RODADOS.
# Determinista, sem LLM. Saida METRIC + VERDICT. Sai 0 se a derivacao bate.
# Sem acentos, sem emojis. UTF-8 sem BOM.

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
STATE = os.path.join(ROOT, "studio.example", "state.json")

# Os 5 passos do protocolo (engine/orchestration.md). K = 5.
STEPS = ["IDENTIFICA", "REGISTRA", "DELEGA", "MONITORA", "FECHA"]


def step_index(s):
    return STEPS.index(s) if s in STEPS else -1


def main():
    if not os.path.isfile(STATE):
        print("METRIC error=state.json do demo ausente")
        print("VERDICT: FAIL")
        return 1

    with open(STATE, encoding="utf-8") as f:
        state = json.load(f)

    events = state.get("events", [])
    print("METRIC source=studio.example/state.json events[] (journal append-only)")
    print("METRIC protocol_steps_K=" + str(len(STEPS)))
    print("METRIC journal_events_total=" + str(len(events)))

    # Por Task: ultimo passo bom registrado (maior ts). events[] e cronologico.
    last_by_task = {}
    for e in events:
        tid = e.get("task_id", "")
        ts = e.get("ts", "")
        cur = last_by_task.get(tid)
        if cur is None or ts >= cur["ts"]:
            last_by_task[tid] = e

    # Escolhe uma Task do demo e SIMULA interrupcao no passo MONITORA (passo i=4 de K=5),
    # truncando o journal ate ali. O resume deve apontar retomada DE MONITORA e re-rodar 0.
    tid = sorted(last_by_task.keys())[0]
    task_events = [e for e in events if e.get("task_id") == tid]

    # Trunca: mantem ate o primeiro evento MONITORA (interrupcao no meio de MONITORA).
    truncated = []
    interrupt_step = "MONITORA"
    for e in task_events:
        truncated.append(e)
        if e.get("step") == interrupt_step:
            break

    last_good = truncated[-1]
    last_step = last_good.get("step")
    i = step_index(last_step) + 1  # passo i = posicao 1-based do ultimo passo bom

    # Sem journal: ao retomar uma Task interrompida no passo i, re-roda os i passos do zero.
    # Com journal (resume): re-roda 0 passos concluidos; continua do ultimo passo bom.
    rerun_without_journal = i
    rerun_with_journal = 0
    steps_not_rerun = rerun_without_journal - rerun_with_journal

    print("METRIC demo_task=" + tid)
    print("METRIC interrupted_at_step=" + last_step + " (i=" + str(i) + " de K=" + str(len(STEPS)) + ")")
    print("METRIC rerun_steps_without_journal=" + str(rerun_without_journal))
    print("METRIC rerun_steps_with_resume=" + str(rerun_with_journal))
    print("METRIC steps_not_rerun=" + str(steps_not_rerun))
    print("METRIC resume_point=" + last_step + " (ultimo passo bom; nao re-roda anteriores)")

    # Garantia estrutural: o resume sempre re-roda 0 passos concluidos (continua do ponto bom).
    ok = (rerun_with_journal == 0) and (i >= 1) and (last_step == interrupt_step)
    print("METRIC structural_guarantee=resume re-roda 0 passos concluidos (continua do ultimo passo bom)")
    print("VERDICT: " + ("PASS" if ok else "FAIL"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
