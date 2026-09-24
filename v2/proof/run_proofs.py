# -*- coding: utf-8 -*-
"""Bateria de prova do I1/I4, roda sem rede. So biblioteca padrao.

Uso: python run_proofs.py
Imprime cada prova com [MEDIDO] e o resultado. Sai com codigo != 0 se alguma
prova falhar (permite plugar num CI depois).
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
DISPATCH = os.path.join(V2, "hooks", "dispatch.py")
def _sandbox_tempdir(prefix: str) -> str:
    """Sandbox de teste SEMPRE fora de v2/ (pasta temporaria do sistema), nunca dentro do
    motor - a origem do vazamento medido pelo CEO (state.json real copiado para dentro de
    v2/proof/_sandbox_task e pego pelo check-public-surface.ps1). Removida no fim do processo
    mesmo se o teste falhar no meio (atexit, nao so no caminho feliz)."""
    d = tempfile.mkdtemp(prefix=prefix)
    atexit.register(shutil.rmtree, d, ignore_errors=True)
    return d
SANDBOX = _sandbox_tempdir("alia-v2-run-proofs-")

FAILS = []


def _fake_secret(prefix: str, body: str) -> str:
    """Monta uma credencial de fixture em tempo de execucao - nunca um literal contiguo no
    fonte que bata o padrao de deteccao de segredo do check-public-surface.ps1 (a prova pelo
    negativo do guard de segredo precisa do FORMATO, nao de um segredo de verdade)."""
    return prefix + body


def check(name: str, cond: bool, detail: str = "") -> None:
    status = "PASS" if cond else "FAIL"
    print(f"[{status}] {name} {detail}")
    if not cond:
        FAILS.append(name)


def fresh_sandbox() -> str:
    if os.path.exists(SANDBOX):
        shutil.rmtree(SANDBOX)
    os.makedirs(SANDBOX)
    return os.path.join(SANDBOX, "activity.jsonl")


REAL_STUDIO_LEDGER = os.path.abspath(os.path.join(V2, "..", "studio", "activity.jsonl"))


def run_dispatch(event: dict | str, env_extra: dict | None = None) -> tuple[dict, float, int]:
    assert os.path.abspath(LEDGER) != REAL_STUDIO_LEDGER, "NUNCA gravar no ledger real do studio"
    env = dict(os.environ)
    env["ALIA_LEDGER_PATH"] = LEDGER
    if env_extra:
        env.update(env_extra)
    payload = event if isinstance(event, str) else json.dumps(event, ensure_ascii=False)
    t0 = time.perf_counter()
    proc = subprocess.run(
        [sys.executable, DISPATCH],
        input=payload.encode("utf-8"),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
    )
    dt_ms = (time.perf_counter() - t0) * 1000
    out = {}
    if proc.stdout:
        try:
            out = json.loads(proc.stdout.decode("utf-8"))
        except json.JSONDecodeError:
            out = {"_raw_stdout": proc.stdout.decode("utf-8", "replace")}
    return out, dt_ms, proc.returncode


def read_ledger() -> list[dict]:
    if not os.path.exists(LEDGER):
        return []
    with open(LEDGER, "r", encoding="utf-8") as fh:
        return [json.loads(l) for l in fh if l.strip()]


# ---------------------------------------------------------------------------
LEDGER = fresh_sandbox()
print("=== I1(d) prova negativa: evento malformado ===")
out, dt, rc = run_dispatch("{ isso nao e json valido")
check("malformado nao derruba (rc=0)", rc == 0, f"rc={rc}")
check("malformado devolve deny", out.get("hookSpecificOutput", {}).get("permissionDecision") == "deny", str(out))
ev = read_ledger()
check("malformado registrado no ledger", any(e.get("event") == "dispatch_error" for e in ev), str(ev))

LEDGER = fresh_sandbox()
out, dt, rc = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "Write",
                             "session_id": "s1", "tool_input": {"file_path": "/x/y.txt", "content": "ok"}})
check("evento sem campo obrigatorio dentro do schema (session sem client) segue vivo", rc == 0, f"rc={rc}")

# ---------------------------------------------------------------------------
print("\n=== I1(d) prova negativa: 2 Tasks mesma sessao nao colapsam custo ===")
LEDGER = fresh_sandbox()
pre1 = {"hook_event_name": "PreToolUse", "tool_name": "Agent", "session_id": "s1",
        "tool_use_id": "tu1", "tool_input": {"subagent_type": "Explore", "prompt": "TASK-101 explore a"}}
post1 = {"hook_event_name": "PostToolUse", "tool_name": "Agent", "session_id": "s1", "tool_use_id": "tu1",
         "tool_input": pre1["tool_input"],
         "tool_response": {"status": "completed", "agentId": "agent-AAA", "totalTokens": 1000,
                            "totalDurationMs": 500, "totalToolUseCount": 3,
                            "usage": {"input_tokens": 800, "output_tokens": 200}}}
pre2 = {"hook_event_name": "PreToolUse", "tool_name": "Agent", "session_id": "s1",
        "tool_use_id": "tu2", "tool_input": {"subagent_type": "Explore", "prompt": "TASK-102 explore b"}}
post2 = {"hook_event_name": "PostToolUse", "tool_name": "Agent", "session_id": "s1", "tool_use_id": "tu2",
         "tool_input": pre2["tool_input"],
         "tool_response": {"status": "completed", "agentId": "agent-BBB", "totalTokens": 4000,
                            "totalDurationMs": 900, "totalToolUseCount": 5,
                            "usage": {"input_tokens": 3500, "output_tokens": 500}}}
for e in (pre1, post1, pre2, post2):
    run_dispatch(e)
rows = [e for e in read_ledger() if e.get("event") == "post_agent"]
check("2 Tasks geram 2 linhas de custo", len(rows) == 2, f"{len(rows)} linhas")
toks = sorted(r.get("tokens_total") for r in rows)
check("custos diferentes, nao colapsados", toks == [1000, 4000], str(toks))

print("\n=== I1(d) prova negativa: PostToolUse duplicado no mesmo agent_id nao duplica custo ===")
run_dispatch(post1)  # reenvia o mesmo PostToolUse (agent-AAA) de novo
rows2 = [e for e in read_ledger() if e.get("event") == "post_agent" and e.get("agent_id") == "agent-AAA"]
dup = [e for e in read_ledger() if e.get("event") == "post_agent_duplicate_ignored"]
check("agent-AAA ainda tem so 1 linha de custo", len(rows2) == 1, f"{len(rows2)} linhas")
check("duplicata fica registrada como ignorada", len(dup) == 1, str(dup))

# ---------------------------------------------------------------------------
print("\n=== I1 fechamento: SubagentStop com transcript real (soma por id de mensagem) ===")
REAL_TRANSCRIPT = os.path.abspath(os.path.join(
    os.path.expanduser("~"), ".claude", "projects",
    "C--Users-Lite-OS-Projetos-studio-farina",
    "33e36edc-6cdd-4a07-a6d6-7111798e9160", "subagents",
    "agent-a98c3476ac6663981.jsonl"))
if os.path.exists(REAL_TRANSCRIPT):
    LEDGER = fresh_sandbox()
    stop_event = {"hook_event_name": "SubagentStop", "session_id": "s-real",
                  "agent_id": "agent-real-a98c3476", "agent_type": "alia-flow-lab-canon",
                  "agent_transcript_path": REAL_TRANSCRIPT}
    out, _, rc = run_dispatch(stop_event)
    check("SubagentStop com transcript real nao derruba (rc=0)", rc == 0, f"rc={rc}")
    rows = [e for e in read_ledger() if e.get("event") == "post_agent" and e.get("agent_id") == "agent-real-a98c3476"]
    check("gravou exatamente 1 linha de custo", len(rows) == 1, f"{len(rows)} linhas")
    row = rows[0] if rows else {}
    usage = row.get("usage") or {}
    check("tool_calls = 5 (5 toolu_ id distintos, nao message.id)", row.get("tool_calls") == 5, str(row.get("tool_calls")))
    check("input_tokens = 10 (soma dedupe por message.id)", usage.get("input_tokens") == 10, str(usage.get("input_tokens")))
    check("output_tokens = 25704 (MAIOR valor por message.id, nao soma de streaming)", usage.get("output_tokens") == 25704, str(usage.get("output_tokens")))
    check("cache_creation_input_tokens = 100119", usage.get("cache_creation_input_tokens") == 100119, str(usage.get("cache_creation_input_tokens")))
    check("cache_read_input_tokens = 233369", usage.get("cache_read_input_tokens") == 233369, str(usage.get("cache_read_input_tokens")))
    check("source = transcript_planB", row.get("source") == "transcript_planB", str(row.get("source")))
else:
    check("transcript real existe (pre-condicao do teste)", False, REAL_TRANSCRIPT)

# ---------------------------------------------------------------------------
print("\n=== I1(c) mediana de 20 execucoes, frio e quente ===")
pyc_dirs = [os.path.join(V2, "hooks", "__pycache__"), os.path.join(V2, "lib", "__pycache__")]
for d in pyc_dirs:
    if os.path.exists(d):
        shutil.rmtree(d)
LEDGER = fresh_sandbox()
sample_event = {"hook_event_name": "PreToolUse", "tool_name": "Write", "session_id": "s-perf",
                 "tool_input": {"file_path": "/tmp/perf.txt", "content": "ok"}}

cold_times = []
for i in range(3):
    for d in pyc_dirs:
        if os.path.exists(d):
            shutil.rmtree(d)
    _, dt, rc = run_dispatch(sample_event)
    cold_times.append(dt)

warm_times = []
for i in range(20):
    _, dt, rc = run_dispatch(sample_event)
    warm_times.append(dt)

print(f"[MEDIDO] frio (pycache limpo a cada rodada, n=3): {[round(t,1) for t in cold_times]} ms, mediana={statistics.median(cold_times):.1f} ms")
print(f"[MEDIDO] quente (pycache presente, n=20): {[round(t,1) for t in warm_times]} ms")
med_warm = statistics.median(warm_times)
print(f"[MEDIDO] mediana quente = {med_warm:.1f} ms")
check("mediana quente abaixo de 150 ms (meta da secao 1)", med_warm < 150, f"{med_warm:.1f} ms")

# ---------------------------------------------------------------------------
print("\n=== I1 fechamento (revisao independente): payload legitimo nunca devolve 'allow' ===")
LEDGER = fresh_sandbox()
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "Write", "session_id": "s-legit",
                           "tool_input": {"file_path": "C:/studio/docs/README.md", "content": "texto comum"}})
check("payload legitimo devolve {} (nenhum permissionDecision, o host decide sozinho)", out == {}, str(out))
check("prova negativa: 'allow' nunca aparece na saida (o defeito critico do laudo)",
      "hookSpecificOutput" not in out, str(out))

print("\n=== I4 guard: as 4 negacoes ===")
LEDGER = fresh_sandbox()

# 1) kernel (lista explicita: AGENTS.md, CLAUDE.md, CONTRACTS.md, engine/)
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "Write", "session_id": "s2",
                           "tool_input": {"file_path": "C:/studio/engine/constitution.md", "content": "x"}})
check("nega escrita em engine/", out["hookSpecificOutput"]["permissionDecision"] == "deny", str(out))
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "Write", "session_id": "s2",
                           "tool_input": {"file_path": "C:/studio/v2/AGENTS.md", "content": "x"}})
check("nega escrita em AGENTS.md (kernel de verdade, nao mais /kernel/ fictício)", out["hookSpecificOutput"]["permissionDecision"] == "deny", str(out))
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "Write", "session_id": "s2",
                           "tool_input": {"file_path": "C:/studio/v2/CLAUDE.md", "content": "x"}})
check("nega escrita em CLAUDE.md", out["hookSpecificOutput"]["permissionDecision"] == "deny", str(out))
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "Edit", "session_id": "s2",
                           "tool_input": {"file_path": "C:/studio/v2/CONTRACTS.md", "new_string": "x"}})
check("nega Edit em CONTRACTS.md", out["hookSpecificOutput"]["permissionDecision"] == "deny", str(out))
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "Write", "session_id": "s2",
                           "tool_input": {"file_path": "C:/studio/docs/README.md", "content": "x"}})
check("positivo: kernel NAO acusa arquivo comum", out == {}, str(out))

# 1b) Bash: redirecionamento/copia para o kernel tambem e negado, nao so Write/Edit
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "Bash", "session_id": "s2",
                           "tool_input": {"command": "echo malicioso >> v2/AGENTS.md"}})
check("nega Bash com >> para AGENTS.md (kernel via redirecionamento)", out["hookSpecificOutput"]["permissionDecision"] == "deny", str(out))
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "Bash", "session_id": "s2",
                           "tool_input": {"command": "cp /tmp/fake.md v2/engine/constitution.md"}})
check("nega Bash cp para dentro de engine/", out["hookSpecificOutput"]["permissionDecision"] == "deny", str(out))
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "Bash", "session_id": "s2",
                           "tool_input": {"command": "Set-Content -Path v2/CONTRACTS.md -Value x"}})
check("nega Bash Set-Content para CONTRACTS.md (equivalente PowerShell)", out["hookSpecificOutput"]["permissionDecision"] == "deny", str(out))
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "Bash", "session_id": "s2",
                           "tool_input": {"command": "echo ola >> docs/README.md"}})
check("positivo: Bash com >> para arquivo comum NAO acusa kernel", out == {}, str(out))
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "Bash", "session_id": "s2",
                           "tool_input": {"command": "cat v2/AGENTS.md"}})
check("positivo: Bash so LENDO AGENTS.md (sem gatilho de redirecionamento) NAO acusa", out == {}, str(out))

# 2) segredo
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "Write", "session_id": "s2",
                           "tool_input": {"file_path": "C:/studio/docs/notes.md", "content": "AKIA1234567890ABCDEF"}})
check("nega segredo (AWS key) no conteudo", out["hookSpecificOutput"]["permissionDecision"] == "deny", str(out))
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "Bash", "session_id": "s2",
                           "tool_input": {"command": "echo " + _fake_secret("sk-", "ABCDEFGHIJKLMNOPQRSTUVWX")}})
check("nega segredo (sk-...) no comando bash", out["hookSpecificOutput"]["permissionDecision"] == "deny", str(out))
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "Write", "session_id": "s2",
                           "tool_input": {"file_path": "C:/studio/docs/notes.md", "content": "texto comum sem segredo"}})
check("positivo: segredo NAO acusa texto comum", out == {}, str(out))

# 3) publicacao sem check
marker = os.path.join(SANDBOX, "check-passed.marker")
if os.path.exists(marker):
    os.remove(marker)
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "Bash", "session_id": "s2",
                           "tool_input": {"command": "git push origin main"}},
                          env_extra={"ALIA_CHECK_MARKER_PATH": marker})
check("nega publicacao sem check", out["hookSpecificOutput"]["permissionDecision"] == "deny", str(out))
with open(marker, "w", encoding="utf-8") as fh:
    fh.write("ok")
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "Bash", "session_id": "s2",
                           "tool_input": {"command": "git push origin main"}},
                          env_extra={"ALIA_CHECK_MARKER_PATH": marker})
check("positivo: publicacao com check presente passa", out == {}, str(out))

# 4) Write/Edit em clients/<id>/ pela sessao principal sem Agent <id>-* visto
LEDGER = fresh_sandbox()
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "Write", "session_id": "s3",
                           "tool_input": {"file_path": "C:/studio/clients/acme/squad/knowledge/x.md", "content": "y"}})
check("nega Write em clients/acme/ sem delegacao vista na sessao", out["hookSpecificOutput"]["permissionDecision"] == "deny", str(out))

# registra que a sessao viu um Agent acme-dev (delegacao legitima)
run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "Agent", "session_id": "s3",
              "tool_use_id": "tu9", "tool_input": {"subagent_type": "acme-dev", "prompt": "faz algo"}})
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "Write", "session_id": "s3",
                           "tool_input": {"file_path": "C:/studio/clients/acme/squad/knowledge/x.md", "content": "y"}})
check("positivo: apos Agent acme-dev visto, Write em clients/acme/ passa", out == {}, str(out))

# condicao 3 do Gate, corrigida: artifacts/coordination/ continua isento (laudo do Gateway),
# mas artifacts/<task>/ SO isenta quando o proprio PostToolUse ja marcou no ledger que um
# SUB-AGENTE escreveu la (nao mais /artifacts/ inteiro isento por padrao).
LEDGER = fresh_sandbox()
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "Write", "session_id": "s4",
                           "tool_input": {"file_path": "C:/studio/clients/acme/artifacts/coordination/laudo.md", "content": "y"}})
check("nao acusa laudo em artifacts/coordination/ mesmo sem Agent visto (falso alarme do response-guard morre aqui)",
      out == {}, str(out))

out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "Write", "session_id": "s4",
                           "tool_input": {"file_path": "C:/studio/clients/acme/artifacts/TASK-801/laudo.md", "content": "y"}})
check("prova negativa: artifacts/TASK-801/ SEM marcador no ledger ainda e negado (a isencao de /artifacts/ inteiro acabou)",
      out["hookSpecificOutput"]["permissionDecision"] == "deny", str(out))

# um sub-agente delegado (agent_id presente) escreve de verdade em artifacts/TASK-801/: o
# PreToolUse passa (dentro do sub-agente nunca e negado) e o PostToolUse grava o marcador.
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "Write", "session_id": "s4",
                           "agent_id": "agent-SUB1", "agent_type": "acme-dev",
                           "tool_input": {"file_path": "C:/studio/clients/acme/artifacts/TASK-801/laudo.md", "content": "y"}})
check("Write de dentro do sub-agente em artifacts/TASK-801/ passa (agent_id presente)", out == {}, str(out))
run_dispatch({"hook_event_name": "PostToolUse", "tool_name": "Write", "session_id": "s4",
              "agent_id": "agent-SUB1",
              "tool_input": {"file_path": "C:/studio/clients/acme/artifacts/TASK-801/laudo.md", "content": "y"}})
marcados = [e for e in read_ledger() if e.get("event") == "artifact_write" and e.get("task_id") == "TASK-801"]
check("PostToolUse gravou o marcador artifact_write para TASK-801", len(marcados) == 1, str(marcados))

# agora a SESSAO PRINCIPAL (sem agent_id, sem Agent acme-* visto) escreve no MESMO
# artifacts/TASK-801/: o marcador ja existe, entao isenta.
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "Write", "session_id": "s4",
                           "tool_input": {"file_path": "C:/studio/clients/acme/artifacts/TASK-801/resumo.md", "content": "y"}})
check("positivo: apos o marcador existir para TASK-801, sessao principal grava em artifacts/TASK-801/ sem negacao",
      out == {}, str(out))

# outro task_id, sem marcador proprio, continua negado (a isencao e por task_id, nao geral)
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "Write", "session_id": "s4",
                           "tool_input": {"file_path": "C:/studio/clients/acme/artifacts/TASK-802/laudo.md", "content": "y"}})
check("prova negativa: TASK-802 sem marcador proprio continua negado (isencao nao vaza entre Tasks)",
      out["hookSpecificOutput"]["permissionDecision"] == "deny", str(out))

# escrita dentro do proprio sub-agente delegado (agent_id presente) nunca e negada
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "Write", "session_id": "s4",
                           "agent_id": "agent-ZZZ", "agent_type": "acme-dev",
                           "tool_input": {"file_path": "C:/studio/clients/acme/squad/knowledge/x.md", "content": "y"}})
check("Write feito de DENTRO do sub-agente (agent_id presente) nunca e negado pela 4a negacao",
      out == {}, str(out))

print("\n=== resultado ===")
if FAILS:
    print(f"FALHOU: {len(FAILS)} prova(s): {FAILS}")
    sys.exit(1)
print("TODAS AS PROVAS PASSARAM")
