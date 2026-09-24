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
from datetime import datetime, timezone
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


def _clean_env(extra: dict | None = None) -> dict:
    """Ambiente LIMPO pro subprocesso de teste: nunca herda CLAUDE_PROJECT_DIR nem ALIA_* do
    host (achado do CEO, 24/09/2026 - check.py rodando com CLAUDE_PROJECT_DIR apontado pro
    studio vivo dava FAIL aqui, porque o dispatch.py filho enxergava dado real do studio em vez
    do sandbox de teste). `extra` sobrescreve por cima - so a variavel que o proprio teste pede."""
    env = {k: v for k, v in os.environ.items()
           if k != "CLAUDE_PROJECT_DIR" and not k.startswith("ALIA_")}
    if extra:
        env.update(extra)
    return env


def run_dispatch(event: dict | str, env_extra: dict | None = None) -> tuple[dict, float, int]:
    assert os.path.abspath(LEDGER) != REAL_STUDIO_LEDGER, "NUNCA gravar no ledger real do studio"
    env = _clean_env({"ALIA_LEDGER_PATH": LEDGER, **(env_extra or {})})
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

# 1c) TASK-811 (achado do CEO, 24/09/2026): a protecao do kernel vale para a INSTANCIA, nunca
# para a FONTE (a oficina, clients/alia-flow-lab/) - senao o kernel nao pode mais evoluir pelo
# caminho da lei (fonte -> migrate.py -> instancia). Prova nos DOIS sentidos.
# registra delegacao (4a negacao e ortogonal a esta prova - alia-flow-lab-warden visto na
# sessao satisfaz o delegation-gate, senao a escrita cairia numa negacao DIFERENTE)
run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "Agent", "session_id": "s2",
              "tool_use_id": "tu-src1", "tool_input": {"subagent_type": "alia-flow-lab-warden",
              "prompt": "conserta o guard do kernel"}})
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "Write", "session_id": "s2",
                           "tool_input": {"file_path": "C:/studio-farina/clients/alia-flow-lab/v2/AGENTS.md", "content": "x"}})
check("positivo: escrita na FONTE (clients/alia-flow-lab/v2/AGENTS.md) NAO e negada", out == {}, str(out))
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "Write", "session_id": "s2",
                           "tool_input": {"file_path": "clients/alia-flow-lab/engine/constitution.md", "content": "x"}})
check("positivo: escrita em clients/alia-flow-lab/engine/ (fonte) NAO e negada", out == {}, str(out))
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "Bash", "session_id": "s2",
                           "tool_input": {"command": "echo x >> clients/alia-flow-lab/v2/CLAUDE.md"}})
check("positivo: Bash >> na FONTE (clients/alia-flow-lab/v2/CLAUDE.md) NAO e negado", out == {}, str(out))
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "Write", "session_id": "s2",
                           "tool_input": {"file_path": "C:/studio-farina/v2/AGENTS.md", "content": "x"}})
check("nega escrita no kernel da INSTANCIA (raiz do studio/v2/AGENTS.md) - a protecao continua viva",
      out["hookSpecificOutput"]["permissionDecision"] == "deny", str(out))
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "Write", "session_id": "s2",
                           "tool_input": {"file_path": "C:/studio-farina/engine/constitution.md", "content": "x"}})
check("nega escrita no engine/ da INSTANCIA - a protecao continua viva",
      out["hookSpecificOutput"]["permissionDecision"] == "deny", str(out))

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

# 3) publicacao sem check (TASK-810: marcador vive em caminho FIXO sob CLAUDE_PROJECT_DIR,
# nunca em variavel ALIA_CHECK_MARKER_PATH - ninguem setava essa variavel no studio vivo e
# TODO git push nascia negado para sempre; achado do CEO, 24/09/2026)
_pub_root = _sandbox_tempdir("alia-v2-run-proofs-pub-")
# pasta PROPRIA (nunca dentro de SANDBOX): o teste de HEAD divergente cria um repo git de
# verdade aqui embaixo, e o Windows deixa objetos do git read-only - um rmtree NO MEIO do
# script (fresh_sandbox(), chamado pelos testes seguintes) derrubava o processo inteiro com
# PermissionError. Isolado, a limpeza fica so no atexit (ignore_errors=True, best-effort).
_marker = os.path.join(_pub_root, ".alia", "check-ok.json")
if os.path.exists(_marker):
    os.remove(_marker)
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "Bash", "session_id": "s2",
                           "tool_input": {"command": "git push origin main"}},
                          env_extra={"CLAUDE_PROJECT_DIR": _pub_root})
check("nega publicacao sem marcador de check", out["hookSpecificOutput"]["permissionDecision"] == "deny", str(out))

os.makedirs(os.path.dirname(_marker), exist_ok=True)
with open(_marker, "w", encoding="utf-8") as fh:
    json.dump({"ts": datetime.now(timezone.utc).isoformat(), "head": None}, fh)
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "Bash", "session_id": "s2",
                           "tool_input": {"command": "git push origin main"}},
                          env_extra={"CLAUDE_PROJECT_DIR": _pub_root})
check("positivo: publicacao com marcador fresco (sem HEAD gravado) passa", out == {}, str(out))

# prova negativa: marcador VENCIDO (mtime > 30 min) volta a negar
_velho = time.time() - (31 * 60)
os.utime(_marker, (_velho, _velho))
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "Bash", "session_id": "s2",
                           "tool_input": {"command": "git push origin main"}},
                          env_extra={"CLAUDE_PROJECT_DIR": _pub_root})
check("nega publicacao com marcador vencido (> 30 min)", out["hookSpecificOutput"]["permissionDecision"] == "deny", str(out))

# prova negativa: marcador fresco mas HEAD gravado diverge do HEAD atual do repo alvo
_git_ok = subprocess.run(["git", "init", "-q"], cwd=_pub_root).returncode == 0
if _git_ok:
    subprocess.run(["git", "config", "user.email", "test@test.local"], cwd=_pub_root)
    subprocess.run(["git", "config", "user.name", "test"], cwd=_pub_root)
    with open(os.path.join(_pub_root, "f.txt"), "w", encoding="utf-8") as fh:
        fh.write("x")
    subprocess.run(["git", "add", "f.txt"], cwd=_pub_root)
    subprocess.run(["git", "commit", "-q", "-m", "x"], cwd=_pub_root)
    _head_real = subprocess.run(["git", "rev-parse", "HEAD"], cwd=_pub_root,
                                 stdout=subprocess.PIPE).stdout.decode().strip()
    with open(_marker, "w", encoding="utf-8") as fh:
        json.dump({"ts": datetime.now(timezone.utc).isoformat(), "head": "0" * 40}, fh)
    out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "Bash", "session_id": "s2",
                               "tool_input": {"command": "git push origin main"}},
                              env_extra={"CLAUDE_PROJECT_DIR": _pub_root})
    check("nega publicacao com HEAD gravado divergente do HEAD atual", out["hookSpecificOutput"]["permissionDecision"] == "deny", str(out))
    with open(_marker, "w", encoding="utf-8") as fh:
        json.dump({"ts": datetime.now(timezone.utc).isoformat(), "head": _head_real}, fh)
    out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "Bash", "session_id": "s2",
                               "tool_input": {"command": "git push origin main"}},
                              env_extra={"CLAUDE_PROJECT_DIR": _pub_root})
    check("positivo: publicacao com HEAD gravado igual ao HEAD atual passa", out == {}, str(out))
else:
    print("[INFO] git indisponivel neste ambiente - prova de HEAD divergente pulada (marcador+idade ja provados acima)")

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

# ---------------------------------------------------------------------------
print("\n=== Stop: aviso de entrega sem veredito (TASK-812/2.0.1, additionalContext + indice) ===")
LEDGER = fresh_sandbox()
STATE_STOP = os.path.join(SANDBOX, "state_stop.json")
with open(STATE_STOP, "w", encoding="utf-8") as fh:
    json.dump({"tasks": [
        {"id": "TASK-812", "status": "open", "client": "alia-flow-lab"},
        {"id": "TASK-811", "status": "open", "client": "acme-saas"},
        {"id": "TASK-813", "status": "review", "client": "alia-flow-lab", "gate_verdict": "FAIL"},
    ]}, fh)


def run_stop(event_extra: dict, env_extra: dict | None = None) -> tuple[dict, float, int]:
    env = {"ALIA_STATE_PATH": STATE_STOP}
    if env_extra:
        env.update(env_extra)
    ev = {"hook_event_name": "Stop", "transcript_path": "/x.jsonl"}
    ev.update(event_extra)
    return run_dispatch(ev, env_extra=env)


def entrega_concluida(session_id: str, tu_id: str, agent_id: str, prompt: str) -> None:
    """Simula uma entrega de Specialist voltando (PostToolUse Agent status=completed) -
    o gatilho novo do aviso de Stop, nao mais so 'sessao tocou' (pre_agent)."""
    pre = {"hook_event_name": "PreToolUse", "tool_name": "Agent", "session_id": session_id,
           "tool_use_id": tu_id, "tool_input": {"subagent_type": "alia-flow-lab-warden", "prompt": prompt}}
    post = {"hook_event_name": "PostToolUse", "tool_name": "Agent", "session_id": session_id, "tool_use_id": tu_id,
            "tool_input": pre["tool_input"],
            "tool_response": {"status": "completed", "agentId": f"agent-{tu_id}", "totalTokens": 100,
                               "totalDurationMs": 50, "totalToolUseCount": 1,
                               "usage": {"input_tokens": 80, "output_tokens": 20}}}
    run_dispatch(pre)
    run_dispatch(post)


# 1) positivo: sessao sem entrega nenhuma -> passa, sem saida, dentro do alvo de tempo
out, dt, rc = run_stop({"session_id": "s-end-none"})
check("Stop passa (sem saida) quando a sessao nao teve entrega nenhuma", out == {}, str(out))
check("Stop responde abaixo de 300 ms", dt < 300, f"{dt:.1f} ms")

# 2) negativo: entrega de Specialist voltou citando TASK-812, que segue sem gate_verdict ->
# additionalContext (NUNCA decision:block - nao pode aparecer como erro pro Operator)
entrega_concluida("s-end1", "tu-e1", "agent-e1", "TASK-812 implementa a trava de fim")
out, dt, rc = run_stop({"session_id": "s-end1"})
ctx = out.get("hookSpecificOutput", {}).get("additionalContext", "")
check("Stop avisa via additionalContext (nunca decision:block) quando a entrega segue sem gate_verdict",
      "decision" not in out and "TASK-812" in ctx, str(out))
check("motivo cita so TASK-812, nunca TASK-811 (a sessao nao tocou TASK-811)",
      "TASK-811" not in ctx, str(out))

# prova negativa central (o erro mais provavel, citado no brief): TASK-811 esta open no
# state.json mas esta sessao nunca teve entrega nenhuma - nao pode avisar por causa dela
out_outra, _, _ = run_stop({"session_id": "s-end-nunca-tocou-nada"})
check("prova negativa: sessao sem entrega nenhuma nao avisa so pq TASK-811/812 estao open",
      out_outra == {}, str(out_outra))

# 3) uma vez por entrega: o MESMO post_agent (seq) nao avisa de novo, mesmo sem stop_hook_active
out_repete, _, _ = run_stop({"session_id": "s-end1"})
check("prova negativa: a MESMA entrega nao avisa 2 vezes (uma vez por entrega)",
      out_repete == {}, str(out_repete))

# 3b) uma NOVA entrega da MESMA Task ainda sem veredito volta a avisar (entrega nova, seq novo)
entrega_concluida("s-end1", "tu-e1b", "agent-e1b", "TASK-812 2a rodada, ainda sem gate")
out_nova, _, _ = run_stop({"session_id": "s-end1"})
check("positivo: uma NOVA entrega da mesma Task ainda sem veredito avisa de novo",
      "TASK-812" in out_nova.get("hookSpecificOutput", {}).get("additionalContext", ""), str(out_nova))

# 4) stop_hook_active=true nunca dispara o aviso (anti-laco - so a chamada seguinte do host)
entrega_concluida("s-end-loop", "tu-eloop", "agent-eloop", "TASK-812 outra sessao")
out_loop, _, _ = run_stop({"session_id": "s-end-loop", "stop_hook_active": True})
check("stop_hook_active=true nunca dispara o aviso", out_loop == {}, str(out_loop))

# 5) nada em voo: background_tasks nao vazio segura o aviso (algo ainda rodando)
entrega_concluida("s-end-bg", "tu-ebg", "agent-ebg", "TASK-812 com trabalho em voo")
out_bg, _, _ = run_stop({"session_id": "s-end-bg", "background_tasks": [{"id": "bg1"}]})
check("background_tasks nao vazio segura o aviso (nada em voo e pre-requisito)", out_bg == {}, str(out_bg))
out_bg_livre, _, _ = run_stop({"session_id": "s-end-bg"})
check("mesma sessao, sem background_tasks, avisa normalmente",
      "TASK-812" in out_bg_livre.get("hookSpecificOutput", {}).get("additionalContext", ""), str(out_bg_livre))

# 6) positivo: Task com gate_verdict ja registrado (mesmo status != done, ex.: review/FAIL)
# nao avisa - "sem gate_verdict" e o criterio, nunca o status
entrega_concluida("s-end2", "tu-e2", "agent-e2", "TASK-813 corrige o achado do Gate")
out_verdito, _, _ = run_stop({"session_id": "s-end2"})
check("Task com gate_verdict ja registrado (review/FAIL) nao dispara aviso", out_verdito == {}, str(out_verdito))

# 7) interruptor de emergencia: variavel de ambiente
entrega_concluida("s-end-off1", "tu-eoff1", "agent-eoff1", "TASK-812 com trava desligada")
out_env_off, _, _ = run_stop({"session_id": "s-end-off1"}, env_extra={"ALIA_END_LOCK_OFF": "1"})
check("ALIA_END_LOCK_OFF=1 desliga o aviso mesmo com Task sem veredito", out_env_off == {}, str(out_env_off))

# 7b) interruptor de emergencia: arquivo .claude/end-lock.off (mesmo padrao do graph-gate.off)
_lock_root = _sandbox_tempdir("alia-v2-run-proofs-lock-")
os.makedirs(os.path.join(_lock_root, ".claude"), exist_ok=True)
with open(os.path.join(_lock_root, ".claude", "end-lock.off"), "w", encoding="utf-8") as fh:
    fh.write("off")
entrega_concluida("s-end-off2", "tu-eoff2", "agent-eoff2", "TASK-812 com arquivo de desligamento")
out_file_off, _, _ = run_stop({"session_id": "s-end-off2"}, env_extra={"CLAUDE_PROJECT_DIR": _lock_root})
check("arquivo .claude/end-lock.off desliga o aviso", out_file_off == {}, str(out_file_off))

# 8) falha aberta: state.json quebrado ou ausente nunca prende o operador
_state_quebrado = os.path.join(SANDBOX, "state_quebrado.json")
with open(_state_quebrado, "w", encoding="utf-8") as fh:
    fh.write("{ isso nao fecha")
entrega_concluida("s-end-bad1", "tu-ebad1", "agent-ebad1", "TASK-812 com state quebrado")
out_json_bad, _, rc_json_bad = run_stop({"session_id": "s-end-bad1"}, env_extra={"ALIA_STATE_PATH": _state_quebrado})
check("state.json quebrado: Stop nunca avisa nem derruba (falha aberta), rc=0",
      out_json_bad == {} and rc_json_bad == 0, f"{out_json_bad} rc={rc_json_bad}")

entrega_concluida("s-end-bad2", "tu-ebad2", "agent-ebad2", "TASK-812 sem state.json")
out_no_state, _, rc_no_state = run_stop(
    {"session_id": "s-end-bad2"}, env_extra={"ALIA_STATE_PATH": os.path.join(SANDBOX, "nao-existe.json")})
check("state.json ausente: Stop nunca avisa nem derruba (falha aberta)",
      out_no_state == {} and rc_no_state == 0, str(out_no_state))

# 9) performance: indice (.idx.json) nunca varre o ledger inteiro - prova com 50 mil linhas
_perf_dir = _sandbox_tempdir("alia-v2-run-proofs-perf-")
_perf_ledger = os.path.join(_perf_dir, "activity.jsonl")
with open(_perf_ledger, "w", encoding="utf-8") as fh:
    for i in range(50_000):
        fh.write(json.dumps({"v": 1, "ts": i, "event": "post_agent", "session_id": f"s-fill-{i % 500}",
                              "agent_id": f"agent-fill-{i}", "task_id": f"TASK-FILL-{i}",
                              "tokens_total": 10}) + "\n")
sys.path.insert(0, os.path.join(V2, "lib"))
import ledger as _ledger_mod  # noqa: E402
_t0_idx = time.perf_counter()
_ledger_mod.session_last_post_agent(_perf_ledger, "s-fill-1")  # constroi o indice 1x (custo pago aqui)
_dt_build_ms = (time.perf_counter() - _t0_idx) * 1000

_perf_state = os.path.join(_perf_dir, "state.json")
with open(_perf_state, "w", encoding="utf-8") as fh:
    json.dump({"tasks": [{"id": "TASK-90001", "status": "open"}]}, fh)
run_dispatch({"hook_event_name": "PostToolUse", "tool_name": "Agent", "session_id": "s-perf",
              "tool_use_id": "tu-perf", "tool_input": {"prompt": "TASK-90001 entrega"},
              "tool_response": {"status": "completed", "agentId": "agent-perf", "totalTokens": 10,
                                 "totalDurationMs": 5, "totalToolUseCount": 1,
                                 "usage": {"input_tokens": 8, "output_tokens": 2}}},
             env_extra={"ALIA_LEDGER_PATH": _perf_ledger})
out_perf, dt_perf, _ = run_dispatch({"hook_event_name": "Stop", "session_id": "s-perf",
                                      "transcript_path": "/x.jsonl"},
                                     env_extra={"ALIA_LEDGER_PATH": _perf_ledger, "ALIA_STATE_PATH": _perf_state})
check("Stop com ledger de 50 mil linhas (indice ja construido) responde abaixo de 300 ms",
      dt_perf < 300, f"{dt_perf:.1f} ms (indice construido em {_dt_build_ms:.1f} ms)")
check("Stop com 50 mil linhas ainda acha a entrega certa (TASK-PERF-1)",
      "TASK-90001" in out_perf.get("hookSpecificOutput", {}).get("additionalContext", ""), str(out_perf))

# ---------------------------------------------------------------------------
print("\n=== Stop: guarda de idioma (TASK-813, mandato do CEO 24/09/2026) ===")


def _transcript_com_resposta(texto: str) -> str:
    caminho = os.path.join(SANDBOX, f"transcript_lang_{abs(hash(texto))}.jsonl")
    with open(caminho, "w", encoding="utf-8") as fh:
        fh.write(json.dumps({"type": "assistant", "message": {"content": [
            {"type": "text", "text": texto}]}}) + "\n")
    return caminho


TEXTO_INGLES = (
    "I checked the repository and the tests are passing now. This was caused by a missing "
    "environment variable that blocked the deploy. I would recommend merging this change "
    "today because it fixes the blocker for the release, and there is no risk to the rest "
    "of the system."
)
TEXTO_PORTUGUES_COM_TERMOS_TECNICOS = (
    "Rodei o check.py e o commit ficou verde no repositorio. O problema era uma variavel de "
    "ambiente que faltava no dispatch.py e travava o push. Recomendo fazer o merge hoje "
    "porque isso resolve o bloqueio do release sem risco para o resto do sistema."
)

_transcript_en = _transcript_com_resposta(TEXTO_INGLES)
out_en, dt_en, rc_en = run_stop({"session_id": "s-lang-en", "transcript_path": _transcript_en},
                                 env_extra={"ALIA_END_LOCK_OFF": "1"})
check("bloqueia resposta predominantemente em ingles",
      out_en.get("decision") == "block" and "ingles" in out_en.get("reason", "").lower(), str(out_en))
# "custo alvo abaixo de 100 ms" e do ALGORITMO da guarda (ler transcript + contar stopword),
# nao do spawn do processo python.exe - esse custo fixo (~90-115 ms neste host, medido acima
# em "I1(c) mediana") e o mesmo pra QUALQUER chamada do dispatch.py, guarda nenhuma controla
# isso. Mede as 2 coisas separadas: o algoritmo em processo (sem subprocess) e o round-trip
# completo (mesmo teto de 300 ms usado pro resto do Stop neste arquivo).
sys.path.insert(0, os.path.join(V2, "hooks"))
import dispatch as _dispatch_mod  # noqa: E402
_t0_algo = time.perf_counter()
_dispatch_mod._resposta_predominante_em_ingles(TEXTO_INGLES)
_dt_algo_ms = (time.perf_counter() - _t0_algo) * 1000
check("algoritmo da guarda de idioma (sem spawn de processo) abaixo de 100 ms (alvo do contrato)",
      _dt_algo_ms < 100, f"{_dt_algo_ms:.2f} ms")
check("round-trip completo (spawn + guarda) abaixo de 300 ms (mesmo teto do resto do Stop)",
      dt_en < 300, f"{dt_en:.1f} ms")

_transcript_pt = _transcript_com_resposta(TEXTO_PORTUGUES_COM_TERMOS_TECNICOS)
out_pt, dt_pt, rc_pt = run_stop({"session_id": "s-lang-pt", "transcript_path": _transcript_pt},
                                 env_extra={"ALIA_END_LOCK_OFF": "1"})
check("prova negativa: portugues com termos tecnicos em ingles (check.py, commit, push, "
      "dispatch.py, merge, release) NAO e barrado", out_pt == {}, str(out_pt))

print("\n=== resultado ===")
if FAILS:
    print(f"FALHOU: {len(FAILS)} prova(s): {FAILS}")
    sys.exit(1)
print("TODAS AS PROVAS PASSARAM")
