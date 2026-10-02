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
# TASK-870: com RUN_PROOFS_RELOGIO=adiado (o check.py liga no pool paralelo) as 3 medidas de LATENCIA nao rodam aqui:
# medida de relogio no meio de 12 processos reprova por vizinhanca. Elas moram em proof/relogio.py e rodam em SERIE.
RELOGIO_ADIADO = os.environ.get("RUN_PROOFS_RELOGIO") == "adiado"


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
    # idem a espinha: as provas legadas acionam agentes sem Task aberta; o dispatch da espinha
    # tem bateria propria (test_espinha.py) e liga la.
    env["ALIA_SPINE_OFF"] = "1"
    env["ALIA_PULSO"] = "1"  # PULSO e opt-in; as provas legadas dele rodam com a flag ligada
    if extra:
        env.update(extra)
    return env


_MODS: dict = {}


def _load_dispatch(dispatch: str):
    """Carrega o dispatch (real ou mutante) UMA vez, no mesmo processo (2.1.3: ~100 spawns de python eram
    os ~20 s do check.py; o teto e 30 s). O que MEDE latencia segue em subprocesso (`spawn=True`)."""
    import importlib.util
    mod = _MODS.get(dispatch)
    if mod is None:
        spec = importlib.util.spec_from_file_location("rp_dispatch%d" % len(_MODS), dispatch)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        _MODS[dispatch] = mod
    return mod


def _dispatch_inproc(payload: str, env: dict, dispatch: str) -> tuple[dict, int]:
    """Mesmo `main()` do hook real, com stdin/stdout/ambiente trocados so durante a chamada."""
    import io
    import types
    mod = _load_dispatch(dispatch)
    env_antes, in_antes, out_antes = dict(os.environ), sys.stdin, sys.stdout
    os.environ.clear()
    os.environ.update(env)
    sys.stdin = types.SimpleNamespace(buffer=io.BytesIO(payload.encode("utf-8")))
    sys.stdout = io.StringIO()
    try:
        try:
            rc = mod.main()
        except SystemExit as exc:
            rc = exc.code or 0
        texto = sys.stdout.getvalue()
    finally:
        sys.stdin, sys.stdout = in_antes, out_antes
        os.environ.clear()
        os.environ.update(env_antes)
    try:
        return (json.loads(texto) if texto else {}), rc
    except json.JSONDecodeError:
        return {"_raw_stdout": texto}, rc


def run_dispatch(event: dict | str, env_extra: dict | None = None,
                 dispatch: str | None = None, spawn: bool = False) -> tuple[dict, float, int]:
    assert os.path.abspath(LEDGER) != REAL_STUDIO_LEDGER, "NUNCA gravar no ledger real do studio"
    env = _clean_env({"ALIA_LEDGER_PATH": LEDGER, **(env_extra or {})})
    payload = event if isinstance(event, str) else json.dumps(event, ensure_ascii=False)
    t0 = time.perf_counter()
    if not spawn:
        out, rc = _dispatch_inproc(payload, env, dispatch or DISPATCH)
        return out, (time.perf_counter() - t0) * 1000, rc
    proc = subprocess.run(
        [sys.executable, dispatch or DISPATCH],
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


def _melhor_de(dt: float, repete, teto: float = 300.0) -> float:
    """TASK-858: latencia de UMA chamada (spawn do python ~100 ms + dispatch) oscila com a carga da
    maquina e do proprio check.py (baterias em paralelo). O teto NAO muda: so se a 1a medida estoura,
    repete ate 2x e vale a MENOR - defeito real (codigo lento) estoura nas 3; ruido de carga nao."""
    melhor = dt
    for _ in range(2):
        if melhor < teto:
            break
        melhor = min(melhor, repete())
    return melhor


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
# TASK-841/842 (WARDEN): caminho de projeto do Claude Code embute usuario + nome do studio do
# operador - identidade que nunca pode ficar cravada em v2/. Esta fixture so roda quando
# ALIA_REAL_TRANSCRIPT_FIXTURE aponta pra um arquivo local (uso manual, nunca comitado); sem a
# variavel o bloco e pulado (INFO, nao FAIL) - a soma por message.id ja tem cobertura sintetica
# em outros pontos deste arquivo (I1(a-d) acima).
REAL_TRANSCRIPT = os.environ.get("ALIA_REAL_TRANSCRIPT_FIXTURE", "")
if REAL_TRANSCRIPT and os.path.exists(REAL_TRANSCRIPT):
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
    print("[INFO] ALIA_REAL_TRANSCRIPT_FIXTURE nao definido - bloco de transcript real pulado (nao e FAIL)")

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
    _, dt, rc = run_dispatch(sample_event, spawn=True)
    cold_times.append(dt)

if RELOGIO_ADIADO:
    print("[INFO] mediana quente adiada: roda isolada em proof/relogio.py (serie, depois do pool)")
else:
    warm_times = []
    for i in range(20):
        _, dt, rc = run_dispatch(sample_event, spawn=True)
        warm_times.append(dt)

    print(f"[MEDIDO] frio (pycache limpo a cada rodada, n=3): {[round(t,1) for t in cold_times]} ms, mediana={statistics.median(cold_times):.1f} ms")
    print(f"[MEDIDO] quente (pycache presente, n=20): {[round(t,1) for t in warm_times]} ms")
    med_warm = statistics.median(warm_times)
    # TASK-858: so remede se estourou o teto (150 ms) - mesma regra do _melhor_de(); vale a MENOR mediana.
    for _ in range(2):
        if med_warm < 150:
            break
        med_warm = min(med_warm, statistics.median([run_dispatch(sample_event, spawn=True)[1] for _ in range(20)]))
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

# 1b-ps (TASK-824, achado do CEO 24/09/2026): a ferramenta PowerShell (terminal principal
# desta maquina Windows) passava sem nenhuma das 4 negacoes - o guard so olhava "Bash". O
# campo do evento e o mesmo (command), entao PowerShell recebe exatamente o mesmo tratamento.
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "PowerShell", "session_id": "s2",
                           "tool_input": {"command": "Set-Content -Path v2/AGENTS.md -Value x"}})
check("nega PowerShell Set-Content para AGENTS.md (kernel)", out["hookSpecificOutput"]["permissionDecision"] == "deny", str(out))
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "PowerShell", "session_id": "s2",
                           "tool_input": {"command": "Get-Content v2/AGENTS.md"}})
check("positivo: PowerShell so LENDO AGENTS.md (Get-Content, sem gatilho de escrita) NAO acusa", out == {}, str(out))

# 1b-verbos (TASK-824, conserto: _extract_write_targets so reconhecia parte dos comandos de
# escrita). Cada verbo novo com ALVO no kernel nega; leitura do kernel no mesmo comando com
# escrita fora do kernel passa (a mesma regra do 1b-bis, agora tambem para os verbos novos).
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "PowerShell", "session_id": "s2",
                           "tool_input": {"command": "Add-Content -Path v2/AGENTS.md -Value x"}})
check("nega PowerShell Add-Content para AGENTS.md (kernel)", out["hookSpecificOutput"]["permissionDecision"] == "deny", str(out))
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "PowerShell", "session_id": "s2",
                           "tool_input": {"command": "Clear-Content -Path v2/CLAUDE.md"}})
check("nega PowerShell Clear-Content para CLAUDE.md (kernel)", out["hookSpecificOutput"]["permissionDecision"] == "deny", str(out))
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "PowerShell", "session_id": "s2",
                           "tool_input": {"command": "New-Item -Path v2/CONTRACTS.md -Value x -Force"}})
check("nega PowerShell New-Item com -Value para CONTRACTS.md (kernel)", out["hookSpecificOutput"]["permissionDecision"] == "deny", str(out))
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "PowerShell", "session_id": "s2",
                           "tool_input": {"command": "New-Item -ItemType File -Path v2/AGENTS.md"}})
check("nega PowerShell New-Item -ItemType File para AGENTS.md (kernel)", out["hookSpecificOutput"]["permissionDecision"] == "deny", str(out))
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "PowerShell", "session_id": "s2",
                           "tool_input": {"command": "New-Item -ItemType Directory -Path v2/AGENTS.md"}})
check("positivo: New-Item -ItemType Directory sem -Value NAO acusa (cria pasta, nunca escreve em arquivo)", out == {}, str(out))
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "PowerShell", "session_id": "s2",
                           "tool_input": {"command": "Remove-Item -Path v2/AGENTS.md"}})
check("nega PowerShell Remove-Item para AGENTS.md (kernel)", out["hookSpecificOutput"]["permissionDecision"] == "deny", str(out))
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "PowerShell", "session_id": "s2",
                           "tool_input": {"command": "Get-Content v2/CLAUDE.md | Tee-Object -FilePath v2/CONTRACTS.md"}})
check("nega PowerShell Tee-Object para CONTRACTS.md (kernel), mesmo lendo CLAUDE.md no mesmo comando", out["hookSpecificOutput"]["permissionDecision"] == "deny", str(out))
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "PowerShell", "session_id": "s2",
                           "tool_input": {"command": "[IO.File]::WriteAllText('v2/AGENTS.md', 'x')"}})
check("nega PowerShell [IO.File]::WriteAllText para AGENTS.md (kernel)", out["hookSpecificOutput"]["permissionDecision"] == "deny", str(out))
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "PowerShell", "session_id": "s2",
                           "tool_input": {"command": "[System.IO.File]::WriteAllLines('v2/CLAUDE.md', 'x')"}})
check("nega PowerShell [System.IO.File]::WriteAllLines para CLAUDE.md (kernel)", out["hookSpecificOutput"]["permissionDecision"] == "deny", str(out))
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "Bash", "session_id": "s2",
                           "tool_input": {"command": "rm v2/AGENTS.md"}})
check("nega Bash rm para AGENTS.md (kernel)", out["hookSpecificOutput"]["permissionDecision"] == "deny", str(out))
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "Bash", "session_id": "s2",
                           "tool_input": {"command": "sed -i 's/a/b/' v2/AGENTS.md"}})
check("nega Bash sed -i para AGENTS.md (kernel)", out["hookSpecificOutput"]["permissionDecision"] == "deny", str(out))
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "Bash", "session_id": "s2",
                           "tool_input": {"command": "sed -n '1p' v2/AGENTS.md"}})
check("positivo: Bash sed sem -i (so leitura) NAO acusa", out == {}, str(out))
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "PowerShell", "session_id": "s2",
                           "tool_input": {"command": "Get-Content v2/AGENTS.md; Add-Content -Path docs/notes.md -Value x"}})
check("positivo: leitura do kernel (Get-Content) + Add-Content fora do kernel no mesmo comando NAO acusa", out == {}, str(out))
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "Bash", "session_id": "s2",
                           "tool_input": {"command": "cat v2/AGENTS.md && rm docs/scratch.txt"}})
check("positivo: leitura do kernel (cat) + rm fora do kernel no mesmo comando NAO acusa", out == {}, str(out))

# 1b-bis (achado do CEO, 24/09/2026, falso positivo no studio vivo): 2>&1 (duplicacao de
# descritor) e mencao de LEITURA ao kernel (cat, grep, python lendo) em outro trecho do
# MESMO comando nunca contam como escrita.
_cmd_leitura_real = ('cat VERSION; grep -c -i "fale sempre em portugu" AGENTS.md; '
                     'python v2/proof/check.py 2>&1 | tail -1')
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "Bash", "session_id": "s2",
                           "tool_input": {"command": _cmd_leitura_real}})
check("positivo: comando exato do falso positivo (leitura + 2>&1) NAO acusa", out == {}, str(out))
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "Bash", "session_id": "s2",
                           "tool_input": {"command": "echo x > AGENTS.md"}})
check("nega Bash com > (nao so >>) na INSTANCIA", out["hookSpecificOutput"]["permissionDecision"] == "deny", str(out))
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "Bash", "session_id": "s2",
                           "tool_input": {"command": "cp a AGENTS.md"}})
check("nega Bash cp a AGENTS.md (destino = ultimo argumento) na INSTANCIA",
      out["hookSpecificOutput"]["permissionDecision"] == "deny", str(out))

# 1b-cp-mv-rm (TASK-824, regressao do Gate do NEXUS): dispatch.py:282 buscava
# -(?:Destination|Path|LiteralPath) com re.search, que pega o PRIMEIRO que aparece no comando -
# misturava origem (leitura) com destino (escrita) de Copy-Item/Move-Item, e Move-Item/rm nao
# marcavam a origem como alvo. As provas abaixo isolam cada familia.
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "PowerShell", "session_id": "s2",
                           "tool_input": {"command": "Copy-Item -Path docs/a.md -Destination v2/AGENTS.md"}})
check("nega Copy-Item -Path docs -Destination kernel (destino no kernel)",
      out["hookSpecificOutput"]["permissionDecision"] == "deny", str(out))
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "PowerShell", "session_id": "s2",
                           "tool_input": {"command": "Copy-Item -Path v2/AGENTS.md -Destination docs/bak.md"}})
check("positivo: Copy-Item -Path kernel -Destination docs passa (-Path e origem, so leitura)",
      out == {}, str(out))
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "PowerShell", "session_id": "s2",
                           "tool_input": {"command": "Move-Item -Path v2/AGENTS.md -Destination docs/bak2.md"}})
check("nega Move-Item -Path kernel -Destination docs (mover apaga a origem, tambem e escrita)",
      out["hookSpecificOutput"]["permissionDecision"] == "deny", str(out))
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "Bash", "session_id": "s2",
                           "tool_input": {"command": "rm v2/AGENTS.md docs/x.txt"}})
check("nega rm kernel docs/x.txt (todo posicional e alvo, nao so o ultimo)",
      out["hookSpecificOutput"]["permissionDecision"] == "deny", str(out))
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "Bash", "session_id": "s2",
                           "tool_input": {"command": "cp docs/a.md v2/AGENTS.md"}})
check("nega cp docs/a.md v2/AGENTS.md (destino = ultimo posicional, no kernel)",
      out["hookSpecificOutput"]["permissionDecision"] == "deny", str(out))
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "Bash", "session_id": "s2",
                           "tool_input": {"command": "cp v2/AGENTS.md docs/b.md"}})
check("positivo: cp v2/AGENTS.md docs/b.md passa (origem no kernel e so leitura)",
      out == {}, str(out))

# 1b-mv-mista (TASK-824, Gate do NEXUS): "if not m_dest and not m_origem" so capturava o
# posicional quando NEM -Destination NEM -Path/-LiteralPath apareciam no comando - a forma
# MISTA (um posicional + uma flag) deixava o outro lado do mv sem marcar como alvo de escrita.
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "PowerShell", "session_id": "s2",
                           "tool_input": {"command": "Move-Item v2/AGENTS.md -Destination docs/bak.md"}})
check("nega Move-Item <kernel posicional> -Destination docs (forma mista 1, origem sem flag)",
      out["hookSpecificOutput"]["permissionDecision"] == "deny", str(out))
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "PowerShell", "session_id": "s2",
                           "tool_input": {"command": "Move-Item -Path docs/x.md v2/AGENTS.md"}})
check("nega Move-Item -Path docs <kernel posicional> (forma mista 2, destino sem flag)",
      out["hookSpecificOutput"]["permissionDecision"] == "deny", str(out))
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "PowerShell", "session_id": "s2",
                           "tool_input": {"command": "Move-Item docs/a.md -Destination docs/b.md"}})
check("positivo: Move-Item docs -Destination docs (nenhum lado no kernel) passa",
      out == {}, str(out))
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "Bash", "session_id": "s2",
                           "tool_input": {"command": "mv v2/AGENTS.md docs/bak.md"}})
check("nega Bash mv v2/AGENTS.md docs/bak.md (forma pura sem flag, origem no kernel)",
      out["hookSpecificOutput"]["permissionDecision"] == "deny", str(out))

# 1c) TASK-811 (achado do CEO, 24/09/2026): a protecao do kernel vale para a INSTANCIA, nunca
# para a FONTE (a oficina, clients/alia-flow-lab/) - senao o kernel nao pode mais evoluir pelo
# caminho da lei (fonte -> migrate.py -> instancia). Prova nos DOIS sentidos.
# registra delegacao (4a negacao e ortogonal a esta prova - alia-flow-lab-warden visto na
# sessao satisfaz o delegation-gate, senao a escrita cairia numa negacao DIFERENTE)
run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "Agent", "session_id": "s2",
              "tool_use_id": "tu-src1", "tool_input": {"subagent_type": "alia-flow-lab-warden",
              "prompt": "conserta o guard do kernel"}})
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "Write", "session_id": "s2",
                           "tool_input": {"file_path": "C:/instancia-exemplo/clients/alia-flow-lab/v2/AGENTS.md", "content": "x"}})
check("positivo: escrita na FONTE (clients/alia-flow-lab/v2/AGENTS.md) NAO e negada", out == {}, str(out))
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "Write", "session_id": "s2",
                           "tool_input": {"file_path": "clients/alia-flow-lab/engine/constitution.md", "content": "x"}})
check("positivo: escrita em clients/alia-flow-lab/engine/ (fonte) NAO e negada", out == {}, str(out))
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "Bash", "session_id": "s2",
                           "tool_input": {"command": "echo x >> clients/alia-flow-lab/v2/CLAUDE.md"}})
check("positivo: Bash >> na FONTE (clients/alia-flow-lab/v2/CLAUDE.md) NAO e negado", out == {}, str(out))
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "Write", "session_id": "s2",
                           "tool_input": {"file_path": "C:/instancia-exemplo/v2/AGENTS.md", "content": "x"}})
check("nega escrita no kernel da INSTANCIA (raiz do studio/v2/AGENTS.md) - a protecao continua viva",
      out["hookSpecificOutput"]["permissionDecision"] == "deny", str(out))
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "Write", "session_id": "s2",
                           "tool_input": {"file_path": "C:/instancia-exemplo/engine/constitution.md", "content": "x"}})
check("nega escrita no engine/ da INSTANCIA - a protecao continua viva",
      out["hookSpecificOutput"]["permissionDecision"] == "deny", str(out))

# 1d) TASK-841/842 (R2, Gate do NEXUS, medido): as provas acima SO usavam caminho SINTETICO
# ("C:/instancia-exemplo/..."), nunca o caminho REAL desta maquina - por isso nenhuma prova
# pegou o defeito real: identity_guard.find_identity_leak(path) tambem escaneava o CAMINHO, e
# todo caminho publicavel de verdade contem a pasta do usuario e/ou do estudio POR CONSTRUCAO (e
# onde o arquivo mora em disco) - qualquer escrita legitima com conteudo limpo virava negada.
# Esta bateria usa o CAMINHO REAL (V2 de verdade, dentro de clients/alia-flow-lab) e roda pelo
# DESPACHANTE INTEIRO via subprocess (run_dispatch), no formato exato do hook real.
sys.path.insert(0, os.path.join(V2, "lib"))
import identity_guard as _idg_r2  # noqa: E402


# 2.1.3 (WARDEN): a prova de identidade NAO depende mais de onde a copia mora nem de quem opera (antes:
# dentro de release/alia-flow o bloco nao rodava e nao dizia nada - prova que passa pela propria sujeira).
# Sandbox PROPRIO: arvore de produto falsa (VERSION + MANIFEST.sha256 + v2/) com alia.config.json e
# state.json FALSOS na raiz, e a copia de hooks/+lib/ DENTRO dela - o identity_guard dessa copia sobe a
# arvore e acha o Client e o estudio falsos. O dispatch roda em subprocesso (spawn): e o identity_guard
# DESSA arvore que tem que decidir. A prova roda sempre; nenhum caminho a pula.
IDG_ID, IDG_ESTUDIO = "cliente-ficticio", "Estudio Ficticio"


def _ident_sandbox(trocas: list[tuple[str, str]] | None = None) -> tuple[str, str, str]:
    raiz = _sandbox_tempdir("alia-v2-run-proofs-ident-")
    for nome, txt in (("VERSION", "0.0.0\n"), ("MANIFEST.sha256", ""),
                      ("alia.config.json", json.dumps({"studio": IDG_ESTUDIO, "studio_dir": "."})),
                      ("state.json", json.dumps({"clients": [{"id": IDG_ID}], "tasks": []}))):
        with open(os.path.join(raiz, nome), "w", encoding="utf-8", newline="") as fh:
            fh.write(txt)
    for sub in ("hooks", "lib"):
        shutil.copytree(os.path.join(V2, sub), os.path.join(raiz, "v2", sub), ignore=shutil.ignore_patterns("__pycache__"))
    alvo = os.path.join(raiz, "v2", "hooks", "dispatch.py")
    src = open(alvo, encoding="utf-8", newline="").read()
    for velho, novo in (trocas or []):
        assert velho in src, "ponto de mutacao sumiu: " + velho
        src = src.replace(velho, novo, 1)
    open(alvo, "w", encoding="utf-8", newline="").write(src)
    return alvo, os.path.join(raiz, "v2", "lib", "___r2-fixture.md"), os.path.join(raiz, "v2", "lib")


_IDG_D, _r2_target, _IDG_LIB = _ident_sandbox()  # caminho do alvo contem o nome da pasta do "estudio" falso
_idg_ids_r2, _idg_studios_r2 = _idg_r2.find_operator_client_ids(_IDG_LIB)
check("identidade: o sandbox falso e lido pelo identity_guard (Client e estudio falsos achados)",
      _idg_ids_r2 == [IDG_ID] and IDG_ESTUDIO in _idg_studios_r2, str((_idg_ids_r2, _idg_studios_r2)))


def _run_idg(ev: dict, dispatch: str = _IDG_D) -> dict:
    return run_dispatch(ev, dispatch=dispatch, spawn=True)[0]


out = _run_idg({"hook_event_name": "PreToolUse", "tool_name": "Write", "session_id": "s2",
                "tool_input": {"file_path": _r2_target, "content": "x = 1"}})
check("R2 positivo: Write com CONTEUDO LIMPO em caminho publicavel passa (o caminho, que contem o nome do "
      "estudio e o usuario, NUNCA e o motivo de negar)", out == {}, str(out))

out = _run_idg({"hook_event_name": "PreToolUse", "tool_name": "Write", "session_id": "s2",
                "tool_input": {"file_path": _r2_target, "content": "o Client " + IDG_ID + " pediu isso"}})
check("R2 positivo: Write com id de Client real no CONTEUDO nega",
      out.get("hookSpecificOutput", {}).get("permissionDecision") == "deny", str(out))

out = _run_idg({"hook_event_name": "PreToolUse", "tool_name": "Edit", "session_id": "s2",
                "tool_input": {"file_path": _r2_target, "new_string": "y = 2"}})
check("R2 positivo: Edit com CONTEUDO LIMPO em caminho publicavel passa", out == {}, str(out))

out = _run_idg({"hook_event_name": "PreToolUse", "tool_name": "Edit", "session_id": "s2",
                "tool_input": {"file_path": _r2_target, "new_string": "a marca " + IDG_ESTUDIO + " aparece aqui"}})
check("R2 positivo: Edit com nome do estudio real no CONTEUDO nega",
      out.get("hookSpecificOutput", {}).get("permissionDecision") == "deny", str(out))

# Bash: alvo com ESPACO entre aspas (a extracao de alvo cortava no espaco e a cobertura nunca se
# confirmava - achado do revisor LATTICE). Heredoc para o MESMO caminho, conteudo limpo x
# conteudo com identidade.
_r2_cmd_limpo = 'cat <<EOF > "' + _r2_target + '"\nconteudo limpo, nada sensivel\nEOF'
out = _run_idg({"hook_event_name": "PreToolUse", "tool_name": "Bash", "session_id": "s2",
                "tool_input": {"command": _r2_cmd_limpo}})
check("R2 positivo: Bash heredoc para alvo entre aspas, conteudo limpo, passa", out == {}, str(out))

_r2_cmd_id = 'cat <<EOF > "' + _r2_target + '"\no Client ' + IDG_ID + ' pediu isso\nEOF'
out = _run_idg({"hook_event_name": "PreToolUse", "tool_name": "Bash", "session_id": "s2",
                "tool_input": {"command": _r2_cmd_id}})
check("R2 positivo: Bash heredoc com id de Client real no CORPO nega",
      out.get("hookSpecificOutput", {}).get("permissionDecision") == "deny", str(out))

# prova negativa DE VERDADE (LEI da casa): volta o Write/Edit a escanear content OR path (linha
# antiga, medida real do defeito) e confere que o mesmo caso "positivo" acima vira FAIL.
_r2_leak_com_path_velho = _idg_r2.find_identity_leak("x = 1", _IDG_LIB) or _idg_r2.find_identity_leak(_r2_target, _IDG_LIB)
check("prova negativa: reintroduzindo 'or find_identity_leak(path)' (linha antiga), o MESMO "
      "conteudo limpo no MESMO caminho volta a acusar vazamento (reproduz o defeito medido "
      "pelo Gate do NEXUS)", _r2_leak_com_path_velho is not None, str(_r2_leak_com_path_velho))

# A trava de identidade varre SO o conteudo escrito, nunca o comando inteiro.
# Mutantes: copia de hooks/+lib/ num tempdir com UMA linha trocada; a prova tem que CAIR nele.
def _mutante_dispatch(nome: str, trocas: list[tuple[str, str]]) -> str:
    raiz = _sandbox_tempdir("alia-v2-run-proofs-mut-" + nome + "-")
    shutil.copytree(os.path.join(V2, "hooks"), os.path.join(raiz, "hooks"), ignore=shutil.ignore_patterns("__pycache__"))
    shutil.copytree(os.path.join(V2, "lib"), os.path.join(raiz, "lib"), ignore=shutil.ignore_patterns("__pycache__"))
    alvo = os.path.join(raiz, "hooks", "dispatch.py")
    src = open(alvo, encoding="utf-8", newline="").read()
    for velho, novo in trocas:
        assert velho in src, "ponto de mutacao sumiu: " + velho
        src = src.replace(velho, novo, 1)
    open(alvo, "w", encoding="utf-8", newline="").write(src)
    return alvo


def _negou(out: dict) -> bool:
    return out.get("hookSpecificOutput", {}).get("permissionDecision") == "deny"


_w1_home = os.path.expanduser("~")  # contem o usuario real em qualquer maquina
_w1_root = _w1_home  # caminho do cd: contem identidade, mas e caminho de cd, nunca conteudo escrito
_w1_cd = {"hook_event_name": "PreToolUse", "tool_name": "Bash", "session_id": "w1",
          "tool_input": {"command": f'cd "{_w1_root}" && echo ok > "{_r2_target}"'}}
_w1_eco = {"hook_event_name": "PreToolUse", "tool_name": "Bash", "session_id": "w1",
           "tool_input": {"command": f'echo {_w1_home} > "{_r2_target}"'}}
out = _run_idg(_w1_cd)
check("identidade: `cd <estudio> && echo ok > alvo` PASSA (o caminho do cd nao e conteudo)", out == {}, str(out))
out = _run_idg(_w1_eco)
check("identidade: `echo <caminho real do usuario> > alvo` NEGA (o conteudo escrito vaza)", _negou(out), str(out))
_w1_mut, _, _ = _ident_sandbox([("_texto_sem_alvo = _inline_content_text(command)", "_texto_sem_alvo = command")])
out = _run_idg(_w1_cd, dispatch=_w1_mut)
check("identidade: NEGATIVO - mutante que varre o comando inteiro nega o `cd <estudio>` (a prova acima o pega)",
      _negou(out), str(out))

# .claude/settings*.json e .claude/skills/**/scripts viram kernel (nao se escreve pela sessao).
_w1_cl = os.path.join(SANDBOX, "inst", ".claude")
for _rot, _caminho in (("settings.json", os.path.join(_w1_cl, "settings.json")),
                       ("settings.local.json", os.path.join(_w1_cl, "settings.local.json")),
                       ("skills/x/scripts/h.py", os.path.join(_w1_cl, "skills", "x", "scripts", "h.py"))):
    out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "Write", "session_id": "w1",
                               "tool_input": {"file_path": _caminho, "content": "x"}})
    check(f"kernel: Write em .claude/{_rot} NEGA", _negou(out), str(out))
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "Bash", "session_id": "w1",
                           "tool_input": {"command": f'echo x > "{os.path.join(_w1_cl, "settings.json")}"'}})
check("kernel: Bash `echo x > .claude/settings.json` NEGA", _negou(out), str(out))
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "Write", "session_id": "w1",
                           "tool_input": {"file_path": os.path.join(_w1_cl, "skills", "x", "SKILL.md"), "content": "x"}})
check("kernel: positivo - .claude/skills/x/SKILL.md (fora de scripts/) PASSA", out == {}, str(out))
_w1_mk = _mutante_dispatch("kern", [('pn.rsplit("/", 2)[-2] == ".claude"', "False"),
                                    ('"/.claude/skills/" in pn and', "False and")])
for _caminho in (os.path.join(_w1_cl, "settings.json"), os.path.join(_w1_cl, "skills", "x", "scripts", "h.py")):
    out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "Write", "session_id": "w1",
                               "tool_input": {"file_path": _caminho, "content": "x"}}, dispatch=_w1_mk)
    check("kernel: NEGATIVO - mutante sem a protecao deixa passar " + os.path.basename(_caminho), out == {}, str(out))

# Teto de 20 subagentes por sessao - o 21o Agent/Task e negado com mensagem.
fresh_sandbox()
_w1_ag = {"hook_event_name": "PreToolUse", "tool_name": "Agent", "session_id": "w1-teto",
          "tool_input": {"subagent_type": "x-y", "prompt": "p"}}
_w1_neg20 = [_negou(run_dispatch(_w1_ag)[0]) for _ in range(20)]
check("teto: os 20 primeiros Agent da sessao passam", not any(_w1_neg20), str(_w1_neg20))
out, _, _ = run_dispatch(_w1_ag)
check("teto: o 21o Agent da MESMA sessao e NEGADO com mensagem do teto",
      _negou(out) and "teto de 20 subagentes" in out["hookSpecificOutput"]["permissionDecisionReason"], str(out))
out, _, _ = run_dispatch({**_w1_ag, "session_id": "w1-outra"})
check("teto: positivo - outra sessao comeca do zero", not _negou(out), str(out))
fresh_sandbox()
_w1_mt = _mutante_dispatch("teto", [("SUBAGENT_CAP = 20", "SUBAGENT_CAP = 10 ** 9")])
_w1_mneg = [_negou(run_dispatch({**_w1_ag, "session_id": "w1-mt"}, dispatch=_w1_mt)[0]) for _ in range(21)]
check("teto: NEGATIVO - mutante sem teto deixa o 21o passar (a prova acima o pega)", not any(_w1_mneg), str(_w1_mneg))
fresh_sandbox()

# Gate: fechar Task exige artifact que EXISTA em disco (a lei L65/L76 era so `if not artifact`).
_w1_close = lambda art: {"hook_event_name": "PreToolUse", "tool_name": "Bash", "session_id": "w1",
                          "cwd": V2, "tool_input": {"command": f'python bin/task.py close --id TASK-1 --artifact "{art}" --veredito PASS'}}
out, _, _ = run_dispatch(_w1_close("nao-existe-w1.md"))
check("gate: `task.py close --artifact <inexistente>` NEGA citando o item",
      _negou(out) and "nao-existe-w1.md" in out["hookSpecificOutput"]["permissionDecisionReason"], str(out))
out, _, _ = run_dispatch(_w1_close("bin/task.py;ext:repo-externo/x.md"))
check("gate: positivo - artifact existente (relativo ao cwd) + item `ext:` PASSA", out == {}, str(out))
_w1_mg = _mutante_dispatch("gate", [("    if not (_TASK_CLOSE_RE.search(command) or _REGISTER_DONE_RE.search(command)):\n        return []",
                                     "    return []")])
out, _, _ = run_dispatch(_w1_close("nao-existe-w1.md"), dispatch=_w1_mg)
check("gate: NEGATIVO - mutante sem a checagem deixa fechar com artifact inexistente", out == {}, str(out))

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

# TASK-824: o mesmo "git push" via PowerShell (nao so Bash) tem que ser negado sem marcador.
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "PowerShell", "session_id": "s2",
                           "tool_input": {"command": "git push origin main"}},
                          env_extra={"CLAUDE_PROJECT_DIR": _pub_root})
check("nega publicacao via PowerShell sem marcador de check", out["hookSpecificOutput"]["permissionDecision"] == "deny", str(out))

os.makedirs(os.path.dirname(_marker), exist_ok=True)
with open(_marker, "w", encoding="utf-8") as fh:
    json.dump({"ts": datetime.now(timezone.utc).isoformat(), "head": None}, fh)
out, _, _ = run_dispatch({"hook_event_name": "PreToolUse", "tool_name": "Bash", "session_id": "s2",
                           "tool_input": {"command": "git push origin main"}},
                          env_extra={"CLAUDE_PROJECT_DIR": _pub_root})
check("nega publicacao com marcador fresco SEM HEAD gravado (TASK-845, E01)", out.get("hookSpecificOutput", {}).get("permissionDecision") == "deny", str(out))

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


def run_stop(event_extra: dict, env_extra: dict | None = None, spawn: bool = False) -> tuple[dict, float, int]:
    env = {"ALIA_STATE_PATH": STATE_STOP}
    if env_extra:
        env.update(env_extra)
    ev = {"hook_event_name": "Stop", "transcript_path": "/x.jsonl"}
    ev.update(event_extra)
    return run_dispatch(ev, env_extra=env, spawn=spawn)


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
out, dt, rc = run_stop({"session_id": "s-end-none"}, spawn=True)
check("Stop passa (sem saida) quando a sessao nao teve entrega nenhuma", out == {}, str(out))
if not RELOGIO_ADIADO:  # relogio isolado em proof/relogio.py
    dt = _melhor_de(dt, lambda: run_stop({"session_id": "s-end-none"}, spawn=True)[1])
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
                                     env_extra={"ALIA_LEDGER_PATH": _perf_ledger, "ALIA_STATE_PATH": _perf_state}, spawn=True)
_ev_perf = {"hook_event_name": "Stop", "session_id": "s-perf", "transcript_path": "/x.jsonl"}
_env_perf = {"ALIA_LEDGER_PATH": _perf_ledger, "ALIA_STATE_PATH": _perf_state}
if not RELOGIO_ADIADO:  # relogio isolado em proof/relogio.py
    dt_perf = _melhor_de(dt_perf, lambda: run_dispatch(_ev_perf, env_extra=_env_perf, spawn=True)[1])
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
                                 env_extra={"ALIA_END_LOCK_OFF": "1"}, spawn=True)
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
dt_en = _melhor_de(dt_en, lambda: run_stop({"session_id": "s-lang-en", "transcript_path": _transcript_en},
                                            env_extra={"ALIA_END_LOCK_OFF": "1"}, spawn=True)[1])
check("round-trip completo (spawn + guarda) abaixo de 300 ms (mesmo teto do resto do Stop)",
      dt_en < 300, f"{dt_en:.1f} ms")

_transcript_pt = _transcript_com_resposta(TEXTO_PORTUGUES_COM_TERMOS_TECNICOS)
out_pt, dt_pt, rc_pt = run_stop({"session_id": "s-lang-pt", "transcript_path": _transcript_pt},
                                 env_extra={"ALIA_END_LOCK_OFF": "1"})
check("prova negativa: portugues com termos tecnicos em ingles (check.py, commit, push, "
      "dispatch.py, merge, release) NAO e barrado", out_pt == {}, str(out_pt))

# ---------------------------------------------------------------------------
print("\n=== TASK-838 (C): read_current_task nunca cai no _last quando o session_id e conhecido ===")
sys.path.insert(0, os.path.join(V2, "lib"))
import paths as _paths_mod  # noqa: E402
import importlib as _importlib  # noqa: E402
_importlib.reload(_paths_mod)

_current_task_fixture = os.path.join(SANDBOX, "current-task-fixture.json")
os.environ["ALIA_CURRENT_TASK_PATH"] = _current_task_fixture
with open(_current_task_fixture, "w", encoding="utf-8", newline="\n") as fh:
    json.dump({"sessao-a": "TASK-FIXTURE-1", "_last": "TASK-FIXTURE-1"}, fh)

# positivo: sessao com entrada propria ganha a propria (nunca a de outra sessao)
check("sessao com entrada propria devolve a sua",
      _paths_mod.read_current_task("sessao-a") == "TASK-FIXTURE-1",
      str(_paths_mod.read_current_task("sessao-a")))

# negativo (a prova do achado real: agente de outra sessao gravado na Task aberta por outra
# conversa): sessao NOVA (sem entrada propria) tem que devolver None, NUNCA o "_last" de outra
# sessao.
check("prova negativa: sessao SEM entrada propria (mas com session_id conhecido) devolve None, "
      "nunca cai no _last de outra sessao",
      _paths_mod.read_current_task("sessao-b-nova") is None,
      str(_paths_mod.read_current_task("sessao-b-nova")))

# regressao (comportamento antigo intencional, preservado): SEM session_id (CLI fora do hook),
# cai no _last como sempre.
check("sem session_id (CLI fora do hook) continua caindo no _last",
      _paths_mod.read_current_task(None) == "TASK-FIXTURE-1",
      str(_paths_mod.read_current_task(None)))
del os.environ["ALIA_CURRENT_TASK_PATH"]

# ---------------------------------------------------------------------------
print("\n=== TASK-839 (B): SessionStart/compact devolve ponteiro de recuperacao ===")
LEDGER = fresh_sandbox()
_transcript_compact = os.path.join(SANDBOX, "transcript-compact-fixture.jsonl")
with open(_transcript_compact, "w", encoding="utf-8") as fh:
    fh.write('{"type": "user", "message": {"content": "oi"}}\n')

_current_task_compact = os.path.join(SANDBOX, "current-task-compact.json")
with open(_current_task_compact, "w", encoding="utf-8", newline="\n") as fh:
    json.dump({"s-compact-1": "TASK-839"}, fh)

out_compact, _, rc_compact = run_dispatch(
    {"hook_event_name": "SessionStart", "source": "compact", "session_id": "s-compact-1",
     "transcript_path": _transcript_compact},
    env_extra={"ALIA_CURRENT_TASK_PATH": _current_task_compact},
)
check("SessionStart/compact sai 0", rc_compact == 0, f"rc={rc_compact}")
_ctx_compact = out_compact.get("hookSpecificOutput", {}).get("additionalContext", "")
check("additionalContext cita o transcript_path (ponteiro de recuperacao)",
      _transcript_compact in _ctx_compact, _ctx_compact)
check("additionalContext cita a Task corrente desta sessao",
      "TASK-839" in _ctx_compact, _ctx_compact)
check("additionalContext ate 700 caracteres (teto proprio)", len(_ctx_compact) <= 700, str(len(_ctx_compact)))
_eventos_compact = read_ledger()
check("evento compact_recovery gravado no ledger",
      any(e.get("event") == "compact_recovery" and e.get("session_id") == "s-compact-1"
          for e in _eventos_compact), str(_eventos_compact))

# negativo (a): source diferente de "compact" (ex.: "startup"/"resume") nunca gera o CONTEXTO DE
# RECUPERACAO (o startup/resume tem o proprio ramo, PULSO + frescor - TASK-847/TASK-856; aqui so
# provamos que ele NUNCA cai no texto de recuperacao pos-compactacao). CLAUDE_PROJECT_DIR aponta
# pro SANDBOX (sem state.json/Clients) para o frescor nao subir a arvore e achar o studio real.
LEDGER = fresh_sandbox()
out_startup, _, rc_startup = run_dispatch(
    {"hook_event_name": "SessionStart", "source": "startup", "session_id": "s-compact-2",
     "transcript_path": _transcript_compact}, env_extra={"CLAUDE_PROJECT_DIR": SANDBOX})
check("prova negativa: SessionStart source=startup nunca cita o transcript_path de recuperacao",
      _transcript_compact not in json.dumps(out_startup), str(out_startup))
check("positivo: SessionStart source=startup sem PULSO/Client velho (sandbox vazio) devolve {}",
      out_startup == {}, str(out_startup))
check("nenhum compact_recovery gravado para source=startup", read_ledger() == [], str(read_ledger()))

# negativo (b): SessionStart/compact SEM transcript_path nunca gera contexto (nao ha o que apontar)
LEDGER = fresh_sandbox()
out_sem_transcript, _, rc_sem_transcript = run_dispatch(
    {"hook_event_name": "SessionStart", "source": "compact", "session_id": "s-compact-3"})
check("prova negativa: SessionStart/compact sem transcript_path devolve {}",
      out_sem_transcript == {}, str(out_sem_transcript))

print("\n=== resultado ===")
if FAILS:
    print(f"FALHOU: {len(FAILS)} prova(s): {FAILS}")
    sys.exit(1)
print("TODAS AS PROVAS PASSARAM")
