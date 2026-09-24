#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""check.py - a conferencia rapida UNICA do motor 2.0 (modulo 9, proof, I9).

Contrato: CONTRACTS.md modulo 9 + e4-arquitetura-v2.md secao 7 (I9). Roda todas as
baterias dos outros modulos, mais a checagem cruzada do ledger (module 4) e 1 catraca
generica, e imprime PASS/FAIL com o tempo total. Alvo: ate 30s, mira 10s.

So biblioteca padrao. Nunca toca studio/ real, nunca .claude/agents real, nunca
state.json real (so LEITURA do real, para tirar copia/hash; toda escrita vai para
proof/_sandbox_check/).

Uso: python check.py
Sai com codigo 1 se qualquer prova falhar.
"""
from __future__ import annotations

import atexit
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
V2 = os.path.dirname(HERE)
REAL_STATE = os.path.abspath(os.path.join(V2, "..", "..", "..", "state.json"))
def _sandbox_tempdir(prefix: str) -> str:
    """Sandbox de teste SEMPRE fora de v2/ (pasta temporaria do sistema), nunca dentro do
    motor - a origem do vazamento medido pelo CEO (state.json real copiado para dentro de
    v2/proof/_sandbox_task e pego pelo check-public-surface.ps1). Removida no fim do processo
    mesmo se o teste falhar no meio (atexit, nao so no caminho feliz)."""
    d = tempfile.mkdtemp(prefix=prefix)
    atexit.register(shutil.rmtree, d, ignore_errors=True)
    return d
SANDBOX = _sandbox_tempdir("alia-v2-check-")

FAILS: list[str] = []
T0 = time.perf_counter()


def check(name: str, cond: bool, detail: str = "") -> None:
    status = "PASS" if cond else "FAIL"
    print(f"[{status}] {name} {detail}")
    if not cond:
        FAILS.append(name)


def run_script(path: str) -> tuple[int, str, float]:
    t0 = time.perf_counter()
    proc = subprocess.run([sys.executable, path], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    dt = time.perf_counter() - t0
    out = proc.stdout.decode("utf-8", "replace") + proc.stderr.decode("utf-8", "replace")
    return proc.returncode, out, dt


def run_py(args: list[str]) -> tuple[int, str, float]:
    t0 = time.perf_counter()
    proc = subprocess.run([sys.executable, *args], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    dt = time.perf_counter() - t0
    out = proc.stdout.decode("utf-8", "replace") + proc.stderr.decode("utf-8", "replace")
    return proc.returncode, out, dt


# ---------------------------------------------------------------------------
print("=== bateria: guard + ledger (I1/I4, hooks/dispatch.py + lib/ledger.py) ===")
rc, out, dt = run_script(os.path.join(HERE, "run_proofs.py"))
check("run_proofs.py (guard/ledger/SubagentStop) sai verde", rc == 0, f"{dt*1000:.0f} ms")
if rc != 0:
    print(out[-3000:])

print("\n=== bateria: flow/risk.py (I6) ===")
rc, out, dt = run_script(os.path.join(V2, "flow", "test_risk.py"))
check("test_risk.py sai verde", rc == 0, f"{dt*1000:.0f} ms")
if rc != 0:
    print(out[-2000:])

print("\n=== bateria: learn/ (I8, refletor/curador/promocao) ===")
rc, out, dt = run_script(os.path.join(HERE, "test_learn.py"))
check("test_learn.py sai verde", rc == 0, f"{dt*1000:.0f} ms")
if rc != 0:
    print(out[-2000:])

print("\n=== bateria: bin/task.py (I2, CLI open/close/context) ===")
rc, out, dt = run_script(os.path.join(HERE, "test_task.py"))
check("test_task.py sai verde", rc == 0, f"{dt*1000:.0f} ms")
if rc != 0:
    print(out[-3000:])

# ---------------------------------------------------------------------------
print("\n=== decide (I7): porta abstem sem Laya ===")
sys.path.insert(0, os.path.join(V2, "lib"))
import decide  # noqa: E402
t0 = time.perf_counter()
resposta = decide.decide("check-i9", {"pergunta": "isto e so uma prova"})
dt = (time.perf_counter() - t0) * 1000
check("decide() devolve None (abstem) - nenhuma prova depende dela responder", resposta is None, f"{dt:.1f} ms")

# ---------------------------------------------------------------------------
print("\n=== kernel (I3): v2/AGENTS.md ===")
AGENTS_MD = os.path.join(V2, "AGENTS.md")
with open(AGENTS_MD, "rb") as fh:
    bytes1 = fh.read()
with open(AGENTS_MD, "rb") as fh:
    bytes2 = fh.read()
hash1 = hashlib.sha256(bytes1).hexdigest()
hash2 = hashlib.sha256(bytes2).hexdigest()
check("2 leituras do kernel dao o mesmo hash", hash1 == hash2, f"{hash1[:12]}")
check("kernel ate 6.000 bytes (alvo do contrato)", len(bytes1) <= 6000, f"{len(bytes1)} bytes")
texto_kernel = bytes1.decode("utf-8")
padrao_data = re.compile(r"\d{1,2}[/.]\d{1,2}[/.]\d{2,4}|\d{4}-\d{2}-\d{2}|TASK-\d+|v2\.\d|20\d{2}")
achados_data = padrao_data.findall(texto_kernel)
check("kernel sem digito de data/versao/Task (arquivo estatico de verdade)", len(achados_data) == 0, str(achados_data))

# prova negativa: edicao a mao diverge o hash
texto_editado = texto_kernel + "\nlinha editada a mao\n"
hash_editado = hashlib.sha256(texto_editado.encode("utf-8")).hexdigest()
check("prova negativa: kernel editado a mao diverge do hash original", hash_editado != hash1, "")

# ---------------------------------------------------------------------------
print("\n=== LAW-MAP.md: nenhuma LEI sem destino ===")
LAW_MAP = os.path.join(V2, "LAW-MAP.md")
with open(LAW_MAP, "r", encoding="utf-8") as fh:
    linhas_lei = [l for l in fh if re.match(r"^\|\s*L\d+\s*\|", l)]
sem_destino = []
for linha in linhas_lei:
    cols = [c.strip() for c in linha.strip().strip("|").split("|")]
    if len(cols) < 3 or not cols[2]:
        sem_destino.append(linha.strip())
check(f"{len(linhas_lei)} LEIs no LAW-MAP.md, nenhuma sem destino", len(sem_destino) == 0, str(sem_destino[:3]))
check("LAW-MAP.md tem pelo menos 78 LEIs mapeadas (contagem do Canon, I0)", len(linhas_lei) >= 78, f"{len(linhas_lei)}")


def _linha_sem_destino_quebrada() -> str:
    return "| L99 | lei fake para prova pelo negativo |  | doutrina |\n"


achados_fake = [l for l in [_linha_sem_destino_quebrada()] if re.match(r"^\|\s*L\d+\s*\|", l) and
                len([c.strip() for c in l.strip().strip("|").split("|")]) >= 3 and
                not [c.strip() for c in l.strip().strip("|").split("|")][2]]
check("prova negativa: linha fake sem destino e detectada pela mesma regra", len(achados_fake) == 1, str(achados_fake))

# ---------------------------------------------------------------------------
print("\n=== checagem cruzada do ledger (modulo 4, I9) ===")


def cross_check(state: dict, events: list[dict]) -> list[str]:
    """Task done sem delegacao nem marca de ordem do Operator: FAIL.
    Evento apontando para Task inexistente: FAIL."""
    problemas = []
    task_ids = {t.get("id") for t in state.get("tasks", [])}
    delegadas = {ev.get("task_id") for ev in events
                 if ev.get("event") in ("pre_agent", "post_agent") and ev.get("task_id")}
    for t in state.get("tasks", []):
        if t.get("status") != "done":
            continue
        tem_delegacao = t.get("id") in delegadas
        tem_ordem_operator = bool(t.get("operator_order"))
        if not tem_delegacao and not tem_ordem_operator:
            problemas.append(f"Task {t.get('id')} done sem delegacao nem ordem do Operator")
    for ev in events:
        tid = ev.get("task_id")
        if tid and tid not in task_ids:
            problemas.append(f"evento {ev.get('event')} aponta para Task inexistente: {tid}")
    return problemas


# fixture positiva: tudo certo
state_ok = {"tasks": [
    {"id": "TASK-901", "status": "done"},
    {"id": "TASK-902", "status": "done", "operator_order": True},
    {"id": "TASK-903", "status": "open"},
]}
events_ok = [
    {"event": "pre_agent", "task_id": "TASK-901"},
    {"event": "post_agent", "task_id": "TASK-901"},
]
problemas_ok = cross_check(state_ok, events_ok)
check("positivo: Task done com delegacao + Task done com ordem do Operator, zero problema", problemas_ok == [], str(problemas_ok))

# fixture negativa (a): Task done sem delegacao nem ordem do Operator
state_bad_a = {"tasks": [{"id": "TASK-904", "status": "done"}]}
problemas_a = cross_check(state_bad_a, [])
check("negativo: Task done sem delegacao nem ordem do Operator da FAIL", len(problemas_a) == 1, str(problemas_a))

# fixture negativa (b): evento aponta Task inexistente
state_bad_b = {"tasks": [{"id": "TASK-905", "status": "done", "operator_order": True}]}
events_bad_b = [{"event": "pre_agent", "task_id": "TASK-QUE-NAO-EXISTE"}]
problemas_b = cross_check(state_bad_b, events_bad_b)
check("negativo: evento apontando Task inexistente da FAIL", any("inexistente" in p for p in problemas_b), str(problemas_b))

# a mesma checagem, agora sobre o state.json REAL (leitura) e o ledger de sandbox vazio -
# so mede quantas Tasks done ficariam sem cobertura hoje (nao e FAIL do check.py, e sinal
# para o Canon/Archive de divida existente, igual ao "SEM TESTE" do law-ledger.md).
if os.path.exists(REAL_STATE):
    with open(REAL_STATE, "r", encoding="utf-8") as fh:
        state_real = json.load(fh)
    problemas_reais = cross_check(state_real, [])
    sem_cobertura = sum(1 for p in problemas_reais if "sem delegacao" in p)
    print(f"[MEDIDO] state.json real: {sem_cobertura} Task(s) done sem delegacao/ordem do Operator "
          f"visivel no ledger vazio de sandbox (nao e defeito do check.py: o ledger real nao foi lido "
          f"aqui de proposito, para nunca depender de studio/activity.jsonl)")

# ---------------------------------------------------------------------------
print("\n=== bin/contexto.py + bin/passagem.py (TASK-804: economia de contexto da coordenadora) ===")
os.makedirs(SANDBOX, exist_ok=True)
BIN = os.path.join(V2, "bin")

# fixture: transcript com streaming fora de ordem - 2 linhas do MESMO message.id, a 2a com
# valor MENOR (delta parcial chegando por ultimo); dedup por id tem que pegar o MAIOR de
# cada campo, nunca somar as 2 linhas como 2 cobrancas distintas.
transcript_fixture = os.path.join(SANDBOX, "transcript_fixture.jsonl")
linhas_transcript = [
    {"type": "assistant", "timestamp": "2026-01-01T00:00:00.000Z", "message": {"id": "msg_1",
     "usage": {"input_tokens": 10, "output_tokens": 5, "cache_creation_input_tokens": 100, "cache_read_input_tokens": 200}}},
    {"type": "assistant", "timestamp": "2026-01-01T00:01:00.000Z", "message": {"id": "msg_2",
     "usage": {"input_tokens": 1, "output_tokens": 2, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 500}}},
    {"type": "assistant", "timestamp": "2026-01-01T00:01:00.500Z", "message": {"id": "msg_2",
     "usage": {"input_tokens": 1, "output_tokens": 1, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 50}}},
]
with open(transcript_fixture, "w", encoding="utf-8") as fh:
    for linha in linhas_transcript:
        fh.write(json.dumps(linha) + "\n")

rc, out, dt = run_py([os.path.join(BIN, "contexto.py"), transcript_fixture, "--teto", "100"])
check("contexto.py sai 0 na fixture", rc == 0, f"{dt*1000:.0f} ms")
json_linha = out.strip().splitlines()[-1] if out.strip() else "{}"
resultado_ctx = json.loads(json_linha) if json_linha.startswith("{") else {}
g = resultado_ctx.get("gasto_acumulado", {})
check("gasto acumulado dedup por message.id (msg_1 + msg_2, nunca 3 linhas)",
      g.get("input_tokens") == 11 and g.get("cache_read_input_tokens") == 700, str(g))
u = resultado_ctx.get("contexto_ultima_chamada", {})
check("contexto da ultima chamada usa o MAIOR valor de cada campo do msg_2 (nao a ultima linha)",
      u.get("contexto_tokens") == 501, str(u))
check("estourou_teto=True com teto 100 (501 > 100)", resultado_ctx.get("estourou_teto") is True, "")

# fixture: plano + state + ledger para passagem.py (nunca a conversa)
plano_fixture = os.path.join(SANDBOX, "plano_fixture.md")
with open(plano_fixture, "w", encoding="utf-8") as fh:
    fh.write("# Plano fixture\n\n## Proxima tarefa\nfazer x, y, z.\n\n## Pendentes\noutra coisa\n")
state_fixture = os.path.join(SANDBOX, "state_fixture.json")
with open(state_fixture, "w", encoding="utf-8") as fh:
    json.dump({"tasks": [
        {"id": "TASK-CHECK-1", "status": "open", "title": "aberta", "client": "c", "project": "p", "specialist": "s"},
        {"id": "TASK-CHECK-2", "status": "done", "title": "fechada", "client": "c", "project": "p", "specialist": "s"},
    ]}, fh)
ledger_fixture = os.path.join(SANDBOX, "ledger_fixture.jsonl")
with open(ledger_fixture, "w", encoding="utf-8") as fh:
    fh.write(json.dumps({"event": "post_agent", "task_id": "TASK-CHECK-1", "agent_id": "s"}) + "\n")
out_dir = os.path.join(SANDBOX, "passagem_out")

rc, out, dt = run_py([os.path.join(BIN, "passagem.py"), "--plano", plano_fixture, "--state", state_fixture,
                       "--ledger", ledger_fixture, "--titulo", "Check Fixture", "--out", out_dir])
check("passagem.py sai 0 na fixture", rc == 0, f"{dt*1000:.0f} ms")
resultado_pas = json.loads(out.strip().splitlines()[-1]) if rc == 0 else {}
gerado = resultado_pas.get("path", "")
check("passagem.py grava o arquivo em --out", os.path.isfile(gerado), gerado)
if os.path.isfile(gerado):
    with open(gerado, "r", encoding="utf-8") as fh:
        conteudo_passagem = fh.read()
    check("passagem tem a secao Proxima tarefa do plano (nao da conversa)",
          "fazer x, y, z." in conteudo_passagem, "")
    check("passagem lista TASK-CHECK-1 (aberta) e nao TASK-CHECK-2 (done)",
          "TASK-CHECK-1" in conteudo_passagem and "TASK-CHECK-2" not in conteudo_passagem, "")
    check("passagem ate 6.000 bytes (1 pagina, mesmo teto do kernel)",
          len(conteudo_passagem.encode("utf-8")) <= 6000, f"{len(conteudo_passagem.encode('utf-8'))} bytes")

# ---------------------------------------------------------------------------
print("\n=== catraca generica: nenhum arquivo do motor v2 usa travessao ===")
TRAVESSAO = chr(0x2014)  # em-dash, banido por lei da casa (chr() pra nunca ter o char no fonte)
ofensores = []
for root, dirs, files in os.walk(V2):
    dirs[:] = [d for d in dirs if not d.startswith("_sandbox") and d != "__pycache__"]
    for fn in files:
        if fn.endswith((".py", ".ps1", ".md")):
            fp = os.path.join(root, fn)
            try:
                with open(fp, "r", encoding="utf-8") as fh:
                    conteudo = fh.read()
            except UnicodeDecodeError:
                continue
            if TRAVESSAO in conteudo:
                ofensores.append(os.path.relpath(fp, V2))
check("nenhum arquivo do motor v2 usa travessao (regra da casa)", len(ofensores) == 0, str(ofensores[:5]))

# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
print("\n=== guarda: nenhum _sandbox* sobrevive dentro de v2/ ===")
# Causa raiz do vazamento medido pelo CEO (24/09): test_task.py recriava
# proof/_sandbox_task/ DENTRO de v2/ com uma COPIA do state.json real, e o
# check-public-surface.ps1 pegava a identidade de Client real ali dentro. As
# sandboxes agora nascem em tempfile.mkdtemp() (fora de v2/, limpo por atexit) -
# esta prova falha se qualquer _sandbox* reaparecer dentro do motor.
sandboxes_em_v2 = []
for root, dirs, _files in os.walk(V2):
    for d in list(dirs):
        if d.startswith("_sandbox"):
            sandboxes_em_v2.append(os.path.relpath(os.path.join(root, d), V2))
check("nenhum diretorio _sandbox* dentro de v2/ (sandbox de teste vive em tempfile, fora do motor)",
      len(sandboxes_em_v2) == 0, str(sandboxes_em_v2))

DT_TOTAL = time.perf_counter() - T0
print(f"\n=== resultado ({DT_TOTAL:.2f} s) ===")
check("tempo total ate 30 s (alvo do contrato)", DT_TOTAL <= 30, f"{DT_TOTAL:.2f} s")
if FAILS:
    print(f"FALHOU: {len(FAILS)} prova(s): {FAILS}")
    sys.exit(1)
print("TODAS AS PROVAS PASSARAM")
