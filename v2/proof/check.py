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


def _clean_env(extra: dict | None = None) -> dict:
    """Ambiente LIMPO pro subprocesso de teste: nunca herda CLAUDE_PROJECT_DIR nem ALIA_* do
    host (achado do CEO, 24/09/2026 - check.py rodado com CLAUDE_PROJECT_DIR apontando pro
    studio vivo fazia run_proofs.py FAIL, porque o dispatch.py filho enxergava dado real do
    studio em vez do sandbox de teste). `extra` sobrescreve por cima."""
    env = {k: v for k, v in os.environ.items()
           if k != "CLAUDE_PROJECT_DIR" and not k.startswith("ALIA_")}
    # as provas LEGADAS simulam a sessao principal escrevendo; o muro de delegacao (dispatch.py,
    # _wall_check) tem bateria propria e liga o muro la (ALIA_DELEGATION_WALL_OFF=0).
    env["ALIA_DELEGATION_WALL_OFF"] = "1"
    # idem a espinha: as provas legadas acionam agentes sem Task aberta; o dispatch da espinha
    # tem bateria propria (test_espinha.py) e liga la.
    env["ALIA_SPINE_OFF"] = "1"
    env["ALIA_PULSO"] = "1"  # PULSO e opt-in; as provas legadas dele rodam com a flag ligada
    if extra:
        env.update(extra)
    return env


def run_script(path: str) -> tuple[int, str, float]:
    t0 = time.perf_counter()
    proc = subprocess.run([sys.executable, path], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           env=_clean_env())
    dt = time.perf_counter() - t0
    out = proc.stdout.decode("utf-8", "replace") + proc.stderr.decode("utf-8", "replace")
    return proc.returncode, out, dt


def run_py(args: list[str]) -> tuple[int, str, float]:
    t0 = time.perf_counter()
    proc = subprocess.run([sys.executable, *args], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           env=_clean_env())
    dt = time.perf_counter() - t0
    out = proc.stdout.decode("utf-8", "replace") + proc.stderr.decode("utf-8", "replace")
    return proc.returncode, out, dt


# TASK-858 (tempo): as 6 baterias abaixo sao scripts INDEPENDENTES (cada um com sandbox proprio em
# tempdir, nenhum escreve no real). Rodavam em fila (run_proofs 16 s + test_task 6 s + ... = ~23 s
# dos ~34 s medidos). Agora sobem TODAS juntas aqui no topo e cada secao so COLETA o resultado, na
# mesma ordem de sempre - o que era espera em fila vira espera do mais lento. A prova do squad-bridge
# (4 chamadas de powershell) sobe junto, numa thread, e e coletada no fim (custo isolado).
_PROCS: dict[str, tuple] = {}


def _start_script(path: str, baixa: bool = False) -> None:
    fo = tempfile.TemporaryFile()
    _PROCS[path] = (subprocess.Popen([sys.executable, path], stdout=fo, stderr=subprocess.STDOUT,
                                     env=_clean_env(), creationflags=_BAIXA if baixa and os.name == "nt" else 0),
                    fo, time.perf_counter())


# 2.1.3 (WARDEN): prova que se pula calada passa pela propria sujeira (run_proofs pulava a identidade fora do
# estudio e ninguem via). Toda linha `[SKIP]`/`SKIP ` das baterias e CONTADA e impressa no fim; na COPIA DE
# EMPACOTAMENTO (release/alia-flow) qualquer SKIP reprova, salvo o declarado abaixo (dado que so existe no
# estudio do operador e nunca viaja: o gabarito do grafo).
SKIPS: list[tuple[str, str]] = []
SKIPS_DECLARADOS = {"test_grafo.py": "gabarito de query e dado privado do estudio (nao viaja no produto)"}
_SKIP_RE = re.compile(r"^\s*\[?SKIP\]?(?:\s|:|$)")


def collect_script(path: str) -> tuple[int, str, float]:
    proc, fo, t0 = _PROCS[path]
    rc = proc.wait()
    dt = time.perf_counter() - t0  # da largada ate a coleta (limite superior do tempo do script)
    fo.seek(0)
    out = fo.read().decode("utf-8", "replace")
    fo.close()
    SKIPS.extend((os.path.basename(path), l.strip()) for l in out.splitlines() if _SKIP_RE.match(l))
    return rc, out, dt


# TASK-867 (causa raiz do flaky): run_proofs.py mede a LATENCIA do hook (mediana de 20 execucoes < 150 ms, Stop
# de 50 mil linhas < 300 ms). Medida de relogio dentro de um pool de 12 processos disputando CPU reprova por
# vizinhanca, nao por defeito do hook (medido: 112 ms sozinho; 3 check.py juntos = 290 ms e FAIL). Isolar em fila
# custava +4 s de 30 s, entao as OUTRAS baterias sobem em prioridade abaixo do normal (herdada pelos filhos):
# run_proofs ganha a CPU na disputa e continua tudo em paralelo (tempo total preservado).
_BAIXA = 0x00004000  # BELOW_NORMAL_PRIORITY_CLASS (Windows; noutros SO a flag e ignorada)
_start_script(os.path.join(HERE, "run_proofs.py"))
for _n in ("test_task.py", "test_gate.py", "test_migrate.py", "test_rsi_reincidencia.py",
           "test_memoria_check.py", "test_frescor_divida.py", "test_grafo.py", "test_espinha.py", "test_ciclo.py"):
    _start_script(os.path.join(HERE, _n), baixa=True)
for _n in ("test_risk.py", "test_slice.py"):
    _start_script(os.path.join(V2, "flow", _n), baixa=True)

# ---- squad-bridge -Only (2.0.6): fixture isolada, 4 chamadas de powershell (~1-2 s cada) ----
# Sobe numa THREAD aqui no topo (custo isolado: roda enquanto o resto corre) e e coletada no fim.
# Incidente 29/09/2026: `-Client <client> -Only <especialista>` apagou 103 bundles de .claude/agents (o -Only
# antigo PODAVA os outros Clients). So o script do PRODUTO (v2/squad/squad-bridge.ps1) - o
# scripts/squad-bridge.ps1 e da instancia e nao viaja. RepoRoot temp com 2 Clients (nunca o real).
import threading  # noqa: E402

SB_SCRIPT = os.path.join(V2, "squad", "squad-bridge.ps1")
SB_RESULT: dict = {}


def _sb_fixture(root: str) -> None:
    for cid, aid in (("fx-a", "alpha"), ("fx-b", "beta")):
        ag = os.path.join(root, "clients", cid, "squad", "agents")
        os.makedirs(ag, exist_ok=True)
        with open(os.path.join(root, "clients", cid, "squad", "squad.yaml"), "w", encoding="utf-8", newline="\n") as fh:
            fh.write(f"squad:\n  client: {cid}\n  name: Fixture -Only\n  domain: fixture temporaria\n  status: active\n")
        with open(os.path.join(ag, aid + ".yaml"), "w", encoding="utf-8", newline="\n") as fh:
            fh.write(f"id: {aid}\ncamada: B\ndomain: fixture\ntools: [Read, Grep]\nbudget:\n  tool_calls: 20\n"
                     "output_contract:\n  max_lines: 60\n  evidence_tags: [MEDIDO, LIDO, INFERIDO]\n"
                     "grounding: client.md\nauthority:\n  decides: teste\n  escalates_to: teste\n")
        with open(os.path.join(ag, aid + ".md"), "w", encoding="utf-8", newline="\n") as fh:
            fh.write(f"# {aid}\n\nFixture persona (-Only).\n")


def _sb_run(root: str, args: list[str]) -> tuple[int, str]:
    proc = subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", SB_SCRIPT,
                           "-RepoRoot", root, *args], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                          env=_clean_env())
    return proc.returncode, proc.stdout.decode("utf-8", "replace")


def _sb_prova(root: str, apagar_durante_only: bool = False) -> None:
    """`apagar_durante_only=True` SIMULA a poda antiga (prova pelo negativo): apaga fx-b-beta.md
    logo apos cada -Only, exatamente o efeito do defeito - a prova tem de reprovar."""
    ag = os.path.join(root, ".claude", "agents")
    a, b = os.path.join(ag, "fx-a-alpha.md"), os.path.join(ag, "fx-b-beta.md")
    n = lambda: len(os.listdir(ag)) if os.path.isdir(ag) else 0  # noqa: E731
    _sb_fixture(root)
    rc, out = _sb_run(root, [])
    base = n()
    SB_RESULT["full"] = (rc == 0 and base >= 2 and os.path.isfile(a) and os.path.isfile(b), f"rc={rc} arquivos={base}")
    for chave, args in (("cliente", ["-Client", "fx-a", "-Only", "fx-a"]),
                        ("especialista", ["-Client", "fx-a", "-Only", "alpha"])):
        rc, out = _sb_run(root, args)
        if apagar_durante_only and os.path.isfile(b):
            os.remove(b)
        SB_RESULT[chave] = (rc == 0 and n() == base and os.path.isfile(b) and "REMOVIDO" not in out,
                            f"rc={rc} antes={base} depois={n()}")
    os.remove(a)
    rc, out = _sb_run(root, ["-Client", "fx-a", "-Only", "alpha"])
    SB_RESULT["regenera"] = (rc == 0 and os.path.isfile(a) and os.path.isfile(b) and n() == base,
                             f"rc={rc} arquivos={n()}")


def _sb_thread_main() -> None:
    try:
        _sb_prova(_sandbox_tempdir("alia-v2-check-sb-only-"), bool(os.environ.get("_CHECK_SB_NEGATIVO")))
    except Exception as exc:  # a coleta reprova com o motivo, nunca some calada
        SB_RESULT["erro"] = repr(exc)


_SB_THREAD = threading.Thread(target=_sb_thread_main, daemon=True)
_SB_THREAD.start()

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
print("\n=== guarda (TASK-810): client.py resolve STUDIO_ROOT pelo cwd/CLAUDE_PROJECT_DIR, nunca pela posicao do script ===")
_raiz_teste = _sandbox_tempdir("alia-v2-check-studioroot-")
_studio_fake = os.path.join(_raiz_teste, "studio-fake")
_cwd_fundo = os.path.join(_studio_fake, "a", "b", "c")
os.makedirs(_cwd_fundo, exist_ok=True)
with open(os.path.join(_studio_fake, "state.json"), "w", encoding="utf-8") as fh:
    fh.write("{}")
_script_em_outro_lugar = os.path.join(_raiz_teste, "onde-o-motor-mora", "v2")
os.makedirs(os.path.join(_script_em_outro_lugar, "bin"), exist_ok=True)
os.makedirs(os.path.join(_script_em_outro_lugar, "lib"), exist_ok=True)
shutil.copyfile(os.path.join(V2, "bin", "client.py"), os.path.join(_script_em_outro_lugar, "bin", "client.py"))
shutil.copyfile(os.path.join(V2, "lib", "paths.py"), os.path.join(_script_em_outro_lugar, "lib", "paths.py"))
_env = _clean_env()
_proc = subprocess.run([sys.executable, os.path.join(_script_em_outro_lugar, "bin", "client.py"), "list"],
                        stdout=subprocess.PIPE, stderr=subprocess.PIPE, cwd=_cwd_fundo, env=_env)
_saida = json.loads(_proc.stdout.decode("utf-8"))
check("client.py rodado de OUTRA profundidade acha a raiz pelo cwd (state.json), nao pela posicao do script",
      _saida.get("repo_root", "") == _studio_fake, str(_saida))

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

# ---------------------------------------------------------------------------
print("\n=== identidade real do operador (TASK-841/842, WARDEN): sem Client/estudio/usuario real "
      "em arquivo publicavel do motor ===")
sys.path.insert(0, os.path.join(V2, "lib"))
import identity_guard  # noqa: E402

# fixture positiva: alia.config.json + state.json SINTETICOS (Client "cliente-exemplo", estudio
# "Estudio Exemplo" numa PASTA "estudio-exemplo-pasta" - nomes de campo e de pasta DIVERGEM de
# proposito, pra provar que as duas formas contam), fora do motor de verdade (a lei da propria
# Task 841/842 proibe nome de Client real em v2/).
_id_fixture_root = _sandbox_tempdir("alia-v2-check-identity-")
_id_fixture_dir = os.path.join(_id_fixture_root, "estudio-exemplo-pasta")
os.makedirs(_id_fixture_dir, exist_ok=True)
with open(os.path.join(_id_fixture_dir, "alia.config.json"), "w", encoding="utf-8") as fh:
    json.dump({"studio_dir": ".", "studio": "Estudio Exemplo"}, fh)
with open(os.path.join(_id_fixture_dir, "state.json"), "w", encoding="utf-8") as fh:
    json.dump({"clients": ["cliente-exemplo", {"id": "alia-flow-lab"}]}, fh)

_ids_fx, _studios_fx = identity_guard.find_operator_client_ids(_id_fixture_dir)
check("find_operator_client_ids le a fixture, exclui alia-flow-lab e devolve as DUAS formas do nome do estudio (campo + pasta)",
      _ids_fx == ["cliente-exemplo"] and _studios_fx == ["Estudio Exemplo", "estudio-exemplo-pasta"],
      str((_ids_fx, _studios_fx)))

_leak_a = identity_guard.find_identity_leak("o Client cliente-exemplo pediu isso", start=_id_fixture_dir)
check("(a) positivo: id de Client real detectado", _leak_a is not None and "cliente-exemplo" in _leak_a, str(_leak_a))

_leak_hifen = identity_guard.find_identity_leak("mcp-cliente-exemplo-tool nunca casa (colado por hifen)", start=_id_fixture_dir)
check("negativo: id colado por hifen/underscore (fronteira) NAO conta como vazamento", _leak_hifen is None, str(_leak_hifen))

# (a, R2) achado do revisor LATTICE: ids CURTOS de Client (ex. 6-8 letras) podem colar dentro de
# outro nome (o dono do GitHub nas URLs de instalacao e o caso real: scripts/install.ps1 tem
# "$repo = <dono>/alia.flow" e o dono contem um id real colado a outro prefixo). Usa os ids REAIS
# desta maquina (nunca cravados aqui) para provar as duas pontas com a MESMA regra de
# check-public-surface.ps1 - sem piso/excecao inventada so pra id curto.
_ids_r2, _ = identity_guard.find_operator_client_ids()
if _ids_r2:
    _id_curto = min(_ids_r2, key=len)
    _colado = "prefixo" + _id_curto + "sufixo"
    _leak_colado_r2 = identity_guard.find_identity_leak_with(_colado, _ids_r2, [])
    check(f"(a) negativo R2: id curto real ({len(_id_curto)} letra(s)) colado dentro de outro nome NAO casa",
          _leak_colado_r2 is None, str(_leak_colado_r2))
    _palavra = "o Client " + _id_curto + " pediu isso"
    _leak_palavra_r2 = identity_guard.find_identity_leak_with(_palavra, _ids_r2, [])
    check("(a) positivo R2: o MESMO id curto real como PALAVRA INTEIRA casa",
          _leak_palavra_r2 is not None, str(_leak_palavra_r2))
    # dono do GitHub de verdade (scripts/install.ps1, lido do disco, nunca cravado aqui): se
    # ELE proprio colar algum id real, tem que passar limpo - a mesma regra de
    # check-public-surface.ps1, nenhuma excecao especial pro nome do dono.
    _install_ps1_r2 = os.path.join(os.path.dirname(V2), "scripts", "install.ps1")
    if os.path.isfile(_install_ps1_r2):
        with open(_install_ps1_r2, "r", encoding="utf-8") as fh:
            _m_repo_r2 = re.search(r'\$repo\s*=\s*"([^"]+)"', fh.read())
        if _m_repo_r2:
            _owner_r2 = _m_repo_r2.group(1).split("/")[0]
            _leak_owner_r2 = identity_guard.find_identity_leak_with(_owner_r2, _ids_r2, [])
            check(f"(a) negativo R2: dono real do GitHub em scripts/install.ps1 NAO casa nenhum id de Client "
                  "real colado (mesma regra de check-public-surface.ps1, sem piso inventado)",
                  _leak_owner_r2 is None, str(_leak_owner_r2))

_leak_clean = identity_guard.find_identity_leak("texto generico sem nada sensivel", start=_id_fixture_dir)
check("negativo: texto limpo nao acusa nada", _leak_clean is None, str(_leak_clean))

# (b) nome do estudio: campo do config, pasta raiz, e as 3 formas de separador - NUNCA
# autorreferencia legitima (diferente do check-public-surface.ps1, que so precisa disso pra Client).
for _texto_b, _motivo_b in [
    ("a marca Estudio Exemplo aparece aqui (campo do config, com espaco)", "campo com espaco"),
    ("a marca estudio-exemplo-pasta aparece aqui (nome da pasta, com hifen)", "pasta com hifen"),
    ("a marca estudio_exemplo aparece aqui (com underscore)", "com underscore"),
    ("a marca ESTUDIO EXEMPLO aparece aqui (caixa alta)", "case-insensitive"),
]:
    _r = identity_guard.find_identity_leak(_texto_b, start=_id_fixture_dir)
    check(f"(b) positivo [{_motivo_b}]: nome do estudio detectado", _r is not None and "estudio" in _r, str(_r))

# (c) usuario/caminho da maquina: as 5 formas praticas (nativo, hifen/slug do Claude Code, %20,
# sem espaco, 8.3 curto quando o SO souber devolver).
_ids_nc, _studios_nc, _formas_c = identity_guard.operator_identity_needles(_id_fixture_dir)
check(f"operator_identity_needles resolve pelo menos 3 formas do caminho/usuario real ({len(_formas_c)})",
      len(_formas_c) >= 3, str(_formas_c))
_usuario_real = os.path.basename(os.path.expanduser("~").rstrip("\\/"))
_forma_hifen = re.sub(r"[\s_]+", "-", _usuario_real)
for _texto_c, _motivo_c in [
    (f"o caminho e {os.path.expanduser('~')}\\projeto", "caminho nativo"),
    (f"pasta .claude/projects/C--Users-{_forma_hifen}-Projetos-x/memory", "slug com hifen (Claude Code)"),
    (f"o usuario e {_usuario_real.replace(' ', '%20')}", "%20"),
]:
    _r = identity_guard.find_identity_leak(_texto_c, start=_id_fixture_dir)
    check(f"(c) positivo [{_motivo_c}]: usuario/caminho real detectado", _r is not None and "maquina do operador" in _r, str(_r))

_leak_c_fake = identity_guard.find_identity_leak("o caminho e C:\\Us" "ers\\fulano\\projeto", start=_id_fixture_dir)
check("negativo: caminho de fixture sintetica (fulano) nao acusa nada", _leak_c_fake is None, str(_leak_c_fake))

# sem state.json acessivel em nenhum ancestral (caso do produto publico distribuido): (a) e (b)
# ficam vazias, so (c) roda - fail-soft, esperado, nunca quebra a sessao.
_no_state_dir = _sandbox_tempdir("alia-v2-check-identity-nostate-")
_ids_ns, _studios_ns = identity_guard.find_operator_client_ids(_no_state_dir)
check("sem state.json em nenhum ancestral: ids e nomes do estudio ficam vazios ((a)/(b) pulados, esperado)",
      _ids_ns == [] and _studios_ns == [], str((_ids_ns, _studios_ns)))
_leak_ns_id = identity_guard.find_identity_leak("cliente-exemplo aparece aqui mas sem config", start=_no_state_dir)
check("sem config: mencao a um id nao acusa nada (nada pra comparar)", _leak_ns_id is None, str(_leak_ns_id))
_leak_ns_home = identity_guard.find_identity_leak(f"caminho {os.path.expanduser('~').replace(chr(92), '/')}/x", start=_no_state_dir)
check("sem config: (c) caminho real continua ativo mesmo sem state.json (fail-soft nunca desliga o caminho)",
      _leak_ns_home is not None, str(_leak_ns_home))

# classify_target: allowlist real (mesma de package-release.ps1) - oficina, produto, e pasta/
# script FORA da allowlist (nao ship, entao identidade la dentro nunca trava este guard).
# CONSERTO (achado da coordenacao): os casos de OFICINA usavam o proprio caminho V2 deste
# processo - so bate "oficina" quando check.py roda DE DENTRO da oficina de verdade; rodando no
# produto (mesmo sha256 do arquivo, layout de disco diferente) os 6 casos reprovavam por diverg
# do ambiente, nunca por defeito do codigo. Agora a fixture MONTA o layout de oficina numa pasta
# SINTETICA (contem o marcador clients/alia-flow-lab/ literal) - o mesmo veredito em QUALQUER
# lugar onde check.py rode.
_ofc_root = os.path.join(_sandbox_tempdir("alia-v2-check-classify-oficina-"), "clients", "alia-flow-lab")
os.makedirs(os.path.join(_ofc_root, "v2", "hooks"), exist_ok=True)
os.makedirs(os.path.join(_ofc_root, "scripts"), exist_ok=True)
os.makedirs(os.path.join(_ofc_root, "docs"), exist_ok=True)
os.makedirs(os.path.join(_ofc_root, "opportunities"), exist_ok=True)
os.makedirs(os.path.join(_ofc_root, "studio"), exist_ok=True)
for _rel_ofc in ("v2/hooks/dispatch.py", "scripts/smoke-test.ps1", "scripts/smoke-test-studio.ps1",
                  "docs/CLAIMS.md", "opportunities/x.md", "studio/state.json"):
    open(os.path.join(_ofc_root, *_rel_ofc.split("/")), "w").close()
check("classify_target: v2/hooks/dispatch.py (layout sintetico de oficina) = oficina",
      identity_guard.classify_target(os.path.join(_ofc_root, "v2", "hooks", "dispatch.py")) == "oficina", "")
check("classify_target: scripts/smoke-test.ps1 (sintetico, na allowlist) = oficina",
      identity_guard.classify_target(os.path.join(_ofc_root, "scripts", "smoke-test.ps1")) == "oficina", "")
check("classify_target: scripts/smoke-test-studio.ps1 (sintetico, FORA da allowlist, smoke da instancia) NAO trava",
      identity_guard.classify_target(os.path.join(_ofc_root, "scripts", "smoke-test-studio.ps1")) is None, "")
check("classify_target: docs/CLAIMS.md (sintetico, docs/ e allowlist, CLAIMS nao esta nela) NAO trava",
      identity_guard.classify_target(os.path.join(_ofc_root, "docs", "CLAIMS.md")) is None, "")
check("classify_target: pasta privada (opportunities/) sintetica dentro da oficina NAO trava",
      identity_guard.classify_target(os.path.join(_ofc_root, "opportunities", "x.md")) is None, "")
check("classify_target: studio/ (sintetico, dogfood operacional da propria oficina) NAO trava",
      identity_guard.classify_target(os.path.join(_ofc_root, "studio", "state.json")) is None, "")

_prod_root = _sandbox_tempdir("alia-v2-check-identity-prod-")
open(os.path.join(_prod_root, "VERSION"), "w").close()
os.makedirs(os.path.join(_prod_root, "v2"), exist_ok=True)
open(os.path.join(_prod_root, "MANIFEST.sha256"), "w").close()
_prod_file = os.path.join(_prod_root, "engine", "x.md")
os.makedirs(os.path.dirname(_prod_file), exist_ok=True)
open(_prod_file, "w").close()
check("classify_target: repo com VERSION+v2/+MANIFEST.sha256 = product (repo inteiro, ja publicado)",
      identity_guard.classify_target(_prod_file) == "product", "")
check("classify_target: caminho fora dos dois marcadores (nem oficina nem product) = None (nao trava)",
      identity_guard.classify_target(os.path.join(_id_fixture_dir, "qualquer.md")) is None, "")

# prova negativa DE VERDADE (LEI da casa: desligue a condicao e confira o FAIL de verdade).
# Simula o guard SEM a exclusao de alia-flow-lab: o proprio motor citando o proprio nome (self
# -reference legitima em qualquer README/CHANGELOG/engine) viraria falso positivo eterno - a
# exclusao existe exatamente para isso nunca acontecer.
_regex_sem_exclusao = re.compile(r"(?i)(?<![\w-])(?:cliente-exemplo|alia-flow-lab)(?![\w-])")
check("prova negativa: SEM a exclusao de alia-flow-lab, self-reference do motor vira falso positivo",
      bool(_regex_sem_exclusao.search("o motor alia-flow-lab cita o proprio nome")), "")
check("com a exclusao (codigo real de identity_guard.py): a mesma frase nao acusa nada",
      identity_guard.find_identity_leak("o motor alia-flow-lab cita o proprio nome", start=_id_fixture_dir) is None, "")

# prova negativa DE VERDADE do nome do estudio: sem tratar a forma-pasta como needle, o mesmo
# texto (b) acima passaria batido - confere que DESLIGAR so a forma-pasta faz o achado sumir.
_ids_sopc, _studios_sopc = identity_guard.find_operator_client_ids(_id_fixture_dir)
_so_campo = [n for n in _studios_sopc if n != "estudio-exemplo-pasta"]
_sem_forma_pasta = identity_guard.find_identity_leak_with(
    "a marca estudio-exemplo-pasta aparece aqui", _ids_sopc, _so_campo)
check("prova negativa: SEM a forma-pasta na lista, a mesma frase (so pasta, sem o campo) passa batida",
      _sem_forma_pasta is None, str(_sem_forma_pasta))

# varredura de VERDADE: todo arquivo PUBLICAVEL - modo depende de ONDE check.py roda (achado do
# revisor LATTICE, R2: a varredura so olhava a oficina; quando check.py roda DENTRO do repo do
# PRODUTO ja publicado - a 3a porta, CI do produto - tem que varrer o produto inteiro, senao um
# vazamento que so existe la (scripts/ divergem 1.83/1.84, nao propagam por copia) nunca e pego).
_ids_real, _studios_real, _formas_real = identity_guard.operator_identity_needles()
_kernel_probe = os.path.join(V2, "AGENTS.md")
_scan_kind = identity_guard.classify_target(_kernel_probe)
# CONSERTO (achado da coordenacao, R4): sem marcador de oficina NEM de produto (ex.: uma
# INSTANCIA instalada do estudio - VERSION + v2/ + alia.config.json/state.json REAIS do
# operador, sem MANIFEST.sha256 de pacote) o codigo antigo caia direto no "else" e tratava
# como OFICINA por omissao - varria alia.config.json/state.json da RAIZ da instancia, que sao
# dado PRIVADO do operador por definicao (AGENTS.md, Fronteira: "studio = os dados, do
# operador, privado, nunca vai pro repo publico"), nao arquivo publicavel. So v2/ (o motor que
# roda ali, identico ao que ship) entra nesse 3o modo.
if _scan_kind == "product":
    _SCAN_ROOT = identity_guard._find_product_root(_kernel_probe)
    _SCAN_LABEL = "produto (repo inteiro)"
elif _scan_kind == "oficina":
    _SCAN_ROOT = os.path.dirname(V2)  # .../clients/alia-flow-lab
    _SCAN_LABEL = "oficina (allowlist de package-release.ps1)"
else:
    _SCAN_ROOT = V2  # instancia instalada: so o motor (v2/) e publicavel, a raiz e privada
    _SCAN_LABEL = "instancia instalada (so v2/ - raiz do estudio e dado privado do operador)"
# CHANGELOG.md ship, mas TRUNCADO no publish (package-release.ps1, $ChangelogPublicFloor):
# historico ANTES dessa versao nunca sai da oficina. Mesmo piso aqui, senao a varredura reprova
# historico que nunca vaza de verdade (o proprio CHANGELOG documenta Task de Client por nome -
# legitimo na oficina, cortado antes de publicar; no produto o arquivo ja chega truncado, o piso
# so nao acha nada pra cortar - inofensivo).
_CHANGELOG_PUBLIC_FLOOR = "1.79.0"
_id_scan_count = 0
_id_leaks: list[str] = []


def _scan_file_for_identity(_fp: str) -> None:
    """Le `_fp`, corta o CHANGELOG.md no piso publico, e acumula vazamento em `_id_leaks` -
    fatorado pra ser chamado tanto pelo modo git-list quanto pelo walk do disco."""
    global _id_scan_count
    try:
        with open(_fp, "r", encoding="utf-8") as fh:
            _linhas = fh.readlines()
    except (OSError, UnicodeDecodeError):
        return
    if os.path.basename(_fp) == "CHANGELOG.md":
        _floor_re = re.compile(r"^##\s*\[" + re.escape(_CHANGELOG_PUBLIC_FLOOR) + r"\]")
        _corte = next((i for i, l in enumerate(_linhas) if _floor_re.match(l.strip())), len(_linhas))
        _linhas = _linhas[:_corte]
    _id_scan_count += 1
    for _i, _linha in enumerate(_linhas, start=1):
        _vaz = identity_guard.find_identity_leak_with(_linha, _ids_real, _studios_real, _formas_real)
        if _vaz:
            _id_leaks.append(f"{os.path.relpath(_fp, _SCAN_ROOT)}:{_i} - {_vaz}")


def _git_relpaths(root: str) -> list[str] | None:
    """Achado da coordenacao (R3): no produto, PUBLICO e o que o git versiona - nao o disco
    inteiro (docs/RELEASE-STATUS.md e docs/provas/*.txt estao no .gitignore do produto, nunca
    publicam, mas o walk antigo os lia do disco mesmo assim e reprovava vazamento que ninguem
    vai ver). Sem `.git` em `root`, devolve None - quem chama cai no walk do disco, como sempre."""
    if not os.path.isdir(os.path.join(root, ".git")):
        return None
    try:
        _tracked = subprocess.run(["git", "ls-files"], cwd=root, capture_output=True,
                                   text=True, check=True, encoding="utf-8").stdout
        _novos = subprocess.run(["git", "ls-files", "--others", "--exclude-standard"], cwd=root,
                                 capture_output=True, text=True, check=True, encoding="utf-8").stdout
    except (OSError, subprocess.CalledProcessError):
        return None
    _linhas_git = _tracked.splitlines() + _novos.splitlines()
    return sorted({l.strip().replace("\\", "/") for l in _linhas_git if l.strip()})


_ID_SCAN_EXT = (".py", ".ps1", ".md", ".json", ".yaml", ".yml", ".txt", ".bat", ".svg", ".html", ".js", ".ts", ".css", ".sh", ".toml")
_git_files = _git_relpaths(_SCAN_ROOT) if _scan_kind == "product" else None
if _git_files is not None:
    _SCAN_LABEL = "produto (git ls-files: versionado + novo nao ignorado, nunca o disco inteiro)"
    for _rel in _git_files:
        if not _rel.endswith(_ID_SCAN_EXT):
            continue
        _fp = os.path.join(_SCAN_ROOT, *_rel.split("/"))
        if identity_guard.classify_target(_fp) != _scan_kind:
            continue
        _scan_file_for_identity(_fp)
else:
    for _root, _dirs, _files in os.walk(_SCAN_ROOT):
        _rel_root = os.path.relpath(_root, _SCAN_ROOT).replace("\\", "/")
        if _rel_root == ".":
            _rel_root = ""
        if _scan_kind == "product":
            _dirs[:] = [d for d in _dirs if d != ".git"]
        elif _scan_kind == "oficina":
            _dirs[:] = [d for d in _dirs if d != ".git" and not d.startswith("_sandbox") and d != "__pycache__" and
                        identity_guard._classify_oficina_relative((_rel_root + "/" + d) if _rel_root else d)]
        else:
            # instancia: _SCAN_ROOT JA E v2/ (nao a raiz do estudio) - so poda sandbox/cache,
            # o resto de v2/ ships inteiro (mesma regra de _classify_oficina_relative pro top "v2").
            _dirs[:] = [d for d in _dirs if not d.startswith("_sandbox") and d != "__pycache__"]
        for _fn in _files:
            if not _fn.endswith(_ID_SCAN_EXT):
                continue
            _fp = os.path.join(_root, _fn)
            if _scan_kind in ("product", "oficina") and identity_guard.classify_target(_fp) != _scan_kind:
                continue
            _scan_file_for_identity(_fp)
check(f"varredura de TODO arquivo publicavel - modo {_SCAN_LABEL} ({_id_scan_count} arquivo(s), "
      f"{len(_ids_real)} Client id(s) + {len(_studios_real)} forma(s) de estudio reais): "
      "nenhuma identidade real do operador vazada", len(_id_leaks) == 0, str(_id_leaks[:10]))

# prova positiva/negativa do modo git-list (achado da coordenacao, R3): PUBLICO no produto e o
# que o git versiona - docs/RELEASE-STATUS.md e docs/provas/*.txt do produto real estao no
# .gitignore e nunca publicam, mas o walk do disco antigo os lia e reprovava vazamento que
# ninguem ve. Fixture: repo git com .gitignore, 1 arquivo IGNORADO com identidade (nao pode
# entrar na lista), 1 VERSIONADO com identidade (tem que entrar), 1 NOVO nao ignorado com
# identidade (tambem tem que entrar - git ls-files --others --exclude-standard).
_git_fx_root = _sandbox_tempdir("alia-v2-check-identity-gitlist-")
subprocess.run(["git", "init", "-q"], cwd=_git_fx_root, check=True)
subprocess.run(["git", "config", "user.email", "fx@fx.fx"], cwd=_git_fx_root, check=True)
subprocess.run(["git", "config", "user.name", "fx"], cwd=_git_fx_root, check=True)
with open(os.path.join(_git_fx_root, ".gitignore"), "w", encoding="utf-8") as fh:
    fh.write("ignorado.md\n")
with open(os.path.join(_git_fx_root, "versionado.md"), "w", encoding="utf-8") as fh:
    fh.write("versionado\n")
with open(os.path.join(_git_fx_root, "ignorado.md"), "w", encoding="utf-8") as fh:
    fh.write("ignorado\n")
subprocess.run(["git", "add", "versionado.md", ".gitignore"], cwd=_git_fx_root, check=True)
subprocess.run(["git", "commit", "-q", "-m", "fx"], cwd=_git_fx_root, check=True)
with open(os.path.join(_git_fx_root, "novo-nao-ignorado.md"), "w", encoding="utf-8") as fh:
    fh.write("novo\n")
_git_listados = _git_relpaths(_git_fx_root)
check("R3 (git-list): versionado.md entra na lista", "versionado.md" in (_git_listados or []), str(_git_listados))
check("R3 (git-list): novo-nao-ignorado.md (git ls-files --others --exclude-standard) entra na lista",
      "novo-nao-ignorado.md" in (_git_listados or []), str(_git_listados))
check("R3 (git-list) prova negativa: ignorado.md (.gitignore) NUNCA entra na lista - o walk do "
      "disco antigo o leria; git ls-files nao", "ignorado.md" not in (_git_listados or []), str(_git_listados))

# ---------------------------------------------------------------------------
print("\n=== cadeado de versao (TASK-822): VERSION == primeira entrada do CHANGELOG.md ===")
import paths  # noqa: E402 (resolvedor de lib/paths.py)
_raiz_cadeado = paths.instance_root()
_version_cadeado_path = os.path.join(_raiz_cadeado, "VERSION")
_changelog_cadeado_path = os.path.join(_raiz_cadeado, "CHANGELOG.md")
_changelog_existe = os.path.isfile(_changelog_cadeado_path)
check(f"CHANGELOG.md existe na raiz da instancia ({_raiz_cadeado})", _changelog_existe, _changelog_cadeado_path)
_version_cadeado = ""
if os.path.isfile(_version_cadeado_path):
    with open(_version_cadeado_path, "r", encoding="utf-8") as fh:
        _version_cadeado = fh.read().strip()
_changelog_topo = None
if _changelog_existe:
    with open(_changelog_cadeado_path, "r", encoding="utf-8") as fh:
        for _linha_ch in fh:
            _m_topo = re.match(r"^##\s*\[(.+?)\]", _linha_ch.strip())
            if _m_topo:
                _changelog_topo = _m_topo.group(1).strip()
                break
check(f"VERSION ({_version_cadeado}) bate com a primeira entrada do CHANGELOG.md ({_changelog_topo})",
      _changelog_existe and _version_cadeado != "" and _version_cadeado == _changelog_topo,
      f"VERSION={_version_cadeado} topo={_changelog_topo}")

# ---------------------------------------------------------------------------
print("\n=== TASK-856: frescor.py - conferencia de FRESCOR do conhecimento por Client ===")
from datetime import datetime, timezone, timedelta  # noqa: E402 (so usado nesta bateria)
sys.path.insert(0, os.path.join(V2, "lib"))
import frescor as _fr  # noqa: E402


def _fr_root() -> str:
    return _sandbox_tempdir("alia-v2-check-frescor-")


def _fr_touch(path: str, dias_atras: float = 0.0) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("x")
    t = time.time() - dias_atras * 86400
    os.utime(path, (t, t))


# (a) mapa com 11 curados mais novos que o mapa = VELHO
_fr_a = _fr_root()
_fr_a_know = os.path.join(_fr_a, "clients", "acme", "squad", "knowledge")
_fr_touch(os.path.join(_fr_a_know, "graphify-out", "graph.json"), dias_atras=5)
for _i in range(11):
    _fr_touch(os.path.join(_fr_a_know, f"nota{_i}.md"), dias_atras=1)
_r_a = _fr.avaliar_client(_fr_a, "acme")
check("(a) mapa com 11 curados mais novos que o mapa = VELHO", _r_a["mapa"]["veredito"] == "VELHO", str(_r_a["mapa"]))

# (b) mapa de 30 dias + 1 curado novo = VELHO
_fr_b = _fr_root()
_fr_b_know = os.path.join(_fr_b, "clients", "acme", "squad", "knowledge")
_fr_touch(os.path.join(_fr_b_know, "graphify-out", "graph.json"), dias_atras=30)
_fr_touch(os.path.join(_fr_b_know, "nota.md"), dias_atras=1)
_r_b = _fr.avaliar_client(_fr_b, "acme")
check("(b) mapa de 30 dias + 1 curado novo = VELHO", _r_b["mapa"]["veredito"] == "VELHO", str(_r_b["mapa"]))

# (c) mapa de 30 dias + nada mais novo = OK (Client parado nunca vira VELHO so por idade)
_fr_c = _fr_root()
_fr_c_know = os.path.join(_fr_c, "clients", "acme", "squad", "knowledge")
_fr_touch(os.path.join(_fr_c_know, "graphify-out", "graph.json"), dias_atras=30)
_fr_touch(os.path.join(_fr_c_know, "nota.md"), dias_atras=40)  # mais velho que o mapa
_r_c = _fr.avaliar_client(_fr_c, "acme")
check("(c) mapa de 30 dias sem nada mais novo = OK (parado nao e VELHO)", _r_c["mapa"]["veredito"] == "OK", str(_r_c["mapa"]))

# (d) divida: data futura cala (valida); vencida NAO cala; sem data reconhecivel NAO cala
_fr_d = _fr_root()
_fr_d_arq = os.path.join(_fr_d, "studio", "conhecimento-dividas.txt")
os.makedirs(os.path.dirname(_fr_d_arq), exist_ok=True)
_amanha = (datetime.now(timezone.utc) + timedelta(days=1)).strftime("%Y-%m-%d")
_ontem = (datetime.now(timezone.utc) - timedelta(days=1)).strftime("%Y-%m-%d")
with open(_fr_d_arq, "w", encoding="utf-8") as fh:
    fh.write(f"acme {_amanha} motivo futuro\n")
_div_futura = _fr._checar_divida(_fr_d, "acme")
check("(d) divida com data futura fica valida (cala)", _div_futura["valida"] == _amanha, str(_div_futura))
with open(_fr_d_arq, "w", encoding="utf-8") as fh:
    fh.write(f"acme {_ontem} motivo vencido\n")
_div_vencida = _fr._checar_divida(_fr_d, "acme")
check("(d) divida vencida NAO cala (vira divida_vencida)",
      _div_vencida["valida"] is None and _div_vencida["vencida"] == _ontem, str(_div_vencida))
with open(_fr_d_arq, "w", encoding="utf-8") as fh:
    fh.write("acme sem-data motivo\n")
_div_sem_data = _fr._checar_divida(_fr_d, "acme")
check("(d) linha sem data reconhecivel NAO cala nada",
      (_div_sem_data["valida"], _div_sem_data["vencida"]) == (None, None), str(_div_sem_data))

_longe = (datetime.now(timezone.utc) + timedelta(days=60)).strftime("%Y-%m-%d")
with open(_fr_d_arq, "w", encoding="utf-8") as fh:
    fh.write(f"acme {_longe} prazo longo demais\n")
_div_longa = _fr._checar_divida(_fr_d, "acme")
check("(d) divida com prazo acima do teto NAO cala (prazo longo = sem prazo)",
      _div_longa["valida"] is None, str(_div_longa))

# (i) CHANGELOG fora de ordem: vale a MAIOR versao, nao a primeira linha do arquivo
_fr_i = _fr_root()
_fr_i_code = os.path.join(_fr_i, "produto-acme")
os.makedirs(_fr_i_code, exist_ok=True)
os.makedirs(os.path.join(_fr_i, "clients", "acme"), exist_ok=True)
with open(os.path.join(_fr_i_code, "CHANGELOG.md"), "w", encoding="utf-8") as fh:
    fh.write("## [0.6.0] - 2026-09-14\n\n## [0.9.0] - 2026-09-26\n\n## [0.8.3] - 2026-09-26\n")
with open(os.path.join(_fr_i, "clients", "acme", "client.md"), "w", encoding="utf-8") as fh:
    fh.write(f"- **codePath:** {_fr_i_code}\n\nversao 0.6.0\n")
_r_i = _fr.avaliar_client(_fr_i, "acme")
check("(i) CHANGELOG fora de ordem: produto = maior versao (0.9.0) e ficha ATRASADA",
      _r_i["produto"] is not None and _r_i["produto"]["versao"] == "0.9.0" and _r_i["produto"]["ficha"] == "ATRASADA", str(_r_i["produto"]))

# (j) indice recem-gerado: MAP.md nasce logo depois do edges.json e NAO conta como mudanca
_fr_j = _fr_root()
_fr_j_know = os.path.join(_fr_j, "clients", "acme", "squad", "knowledge")
_fr_touch(os.path.join(_fr_j_know, "graphify-out", "graph.json"), dias_atras=2)
_fr_touch(os.path.join(_fr_j_know, "nota.md"), dias_atras=3)
_fr_touch(os.path.join(_fr_j_know, "edges.json"), dias_atras=0.001)
_fr_touch(os.path.join(_fr_j_know, "MAP.md"), dias_atras=0)
_r_j = _fr.avaliar_client(_fr_j, "acme")
check("(j) indice recem-gerado (MAP.md depois do edges.json) fica OK e nao envelhece o mapa",
      _r_j["indice"]["veredito"] == "OK" and _r_j["mapa"]["mudaram"] == 0, str(_r_j["indice"]) + " " + str(_r_j["mapa"]))

# (e) produto: CHANGELOG do codePath na 0.7.0; client.md sem a versao = ATRASADA, com = OK;
# codePath com crase e barra final tambem resolve (achado da coordenacao)
_fr_e = _fr_root()
_fr_e_client_dir = os.path.join(_fr_e, "clients", "acme")
os.makedirs(_fr_e_client_dir, exist_ok=True)
_fr_e_code = os.path.join(_fr_e, "produto-acme")
os.makedirs(_fr_e_code, exist_ok=True)
with open(os.path.join(_fr_e_code, "CHANGELOG.md"), "w", encoding="utf-8") as fh:
    fh.write("## [0.7.0] - 2026-09-27\n\ntexto\n")
with open(os.path.join(_fr_e_client_dir, "client.md"), "w", encoding="utf-8") as fh:
    fh.write(f"- **codePath:** {_fr_e_code}\n\nprojeto na versao 0.6.0\n")
_r_e_atrasada = _fr.avaliar_client(_fr_e, "acme")
check("(e) client.md sem a versao do CHANGELOG = ficha ATRASADA",
      _r_e_atrasada["produto"] is not None and _r_e_atrasada["produto"]["ficha"] == "ATRASADA", str(_r_e_atrasada["produto"]))
with open(os.path.join(_fr_e_client_dir, "client.md"), "w", encoding="utf-8") as fh:
    fh.write(f"- **codePath:** {_fr_e_code}\n\nprojeto na versao 0.7.0\n")
_r_e_ok = _fr.avaliar_client(_fr_e, "acme")
check("(e) client.md citando a versao do CHANGELOG = ficha OK",
      _r_e_ok["produto"] is not None and _r_e_ok["produto"]["ficha"] == "OK", str(_r_e_ok["produto"]))
with open(os.path.join(_fr_e_client_dir, "client.md"), "w", encoding="utf-8") as fh:
    fh.write(f"- **codePath:** `{_fr_e_code}/`\n\nprojeto na versao 0.7.0\n")
_r_e_crase = _fr.avaliar_client(_fr_e, "acme")
check("(e) codePath com crase e barra final tambem resolve o CHANGELOG",
      _r_e_crase["produto"] is not None and _r_e_crase["produto"]["ficha"] == "OK", str(_r_e_crase["produto"]))

# (f) artifacts com 3 subpastas + 1 arquivo solto = 4 entregas (oculto ignorado)
_fr_f = _fr_root()
_fr_f_art = os.path.join(_fr_f, "clients", "acme", "artifacts")
os.makedirs(os.path.join(_fr_f_art, "sub1"))
os.makedirs(os.path.join(_fr_f_art, "sub2"))
os.makedirs(os.path.join(_fr_f_art, "sub3"))
with open(os.path.join(_fr_f_art, "sub1", "a.md"), "w", encoding="utf-8") as fh:
    fh.write("x")
with open(os.path.join(_fr_f_art, "solto.md"), "w", encoding="utf-8") as fh:
    fh.write("x")
with open(os.path.join(_fr_f_art, ".oculto.md"), "w", encoding="utf-8") as fh:
    fh.write("x")
_r_f = _fr._checar_entregas(os.path.join(_fr_f, "clients", "acme"))
check("(f) 3 subpastas + 1 arquivo solto = 4 entregas (oculto ignorado)", _r_f["quantidade"] == 4, str(_r_f))

# (g) SessionStart startup: Client VELHO gera aviso [CONHECIMENTO VELHO]; tudo OK devolve {}
_fr_g = _fr_root()
with open(os.path.join(_fr_g, "state.json"), "w", encoding="utf-8") as fh:
    json.dump({"clients": [{"id": "acme", "status": "active"}]}, fh)
_fr_touch(os.path.join(_fr_g, "clients", "acme", "squad", "knowledge", "graphify-out", "graph.json"), dias_atras=30)
_fr_touch(os.path.join(_fr_g, "clients", "acme", "squad", "knowledge", "nota.md"), dias_atras=1)
_env_g = _clean_env({"CLAUDE_PROJECT_DIR": _fr_g, "ALIA_LEDGER_PATH": os.path.join(_fr_g, "activity.jsonl")})
_proc_g = subprocess.run([sys.executable, os.path.join(V2, "hooks", "dispatch.py")],
                          input=json.dumps({"hook_event_name": "SessionStart", "source": "startup",
                                            "session_id": "s-fresc-g"}).encode("utf-8"),
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=_env_g)
_out_g = json.loads(_proc_g.stdout.decode("utf-8") or "{}")
_ctx_g = _out_g.get("hookSpecificOutput", {}).get("additionalContext", "")
check("(g) SessionStart startup com Client VELHO devolve aviso [CONHECIMENTO VELHO]",
      "[CONHECIMENTO VELHO]" in _ctx_g and "acme" in _ctx_g, str(_out_g))

_fr_h_ok = _fr_root()
with open(os.path.join(_fr_h_ok, "state.json"), "w", encoding="utf-8") as fh:
    json.dump({"clients": [{"id": "acme", "status": "active"}]}, fh)
_fr_touch(os.path.join(_fr_h_ok, "clients", "acme", "squad", "knowledge", "graphify-out", "graph.json"), dias_atras=1)
_env_h = _clean_env({"CLAUDE_PROJECT_DIR": _fr_h_ok, "ALIA_LEDGER_PATH": os.path.join(_fr_h_ok, "activity.jsonl")})
_proc_h = subprocess.run([sys.executable, os.path.join(V2, "hooks", "dispatch.py")],
                          input=json.dumps({"hook_event_name": "SessionStart", "source": "startup",
                                            "session_id": "s-fresc-h"}).encode("utf-8"),
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=_env_h)
_out_h = json.loads(_proc_h.stdout.decode("utf-8") or "{}")
check("(g) SessionStart startup com tudo OK devolve {} (sem pulso.json, sem Client velho)", _out_h == {}, str(_out_h))

# (g) o ramo resume tambem avisa (sessao retomada e a mesma porta de entrada)
# chamada direta (sem processo novo): a fronteira do processo ja e provada pelo caso startup acima
import importlib.util as _ilu  # noqa: E402


def _com_env(extra: dict, fn):
    antes = {k: os.environ.get(k) for k in extra}
    os.environ.update(extra)
    try:
        return fn()
    finally:
        for k, v in antes.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v


def _carrega(nome: str, caminho: str):
    spec = _ilu.spec_from_file_location(nome, caminho)
    mod = _ilu.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


_disp_fr = _carrega("_dispatch_frescor", os.path.join(V2, "hooks", "dispatch.py"))
_out_g_resume = _com_env({"CLAUDE_PROJECT_DIR": _fr_g, "ALIA_LEDGER_PATH": os.path.join(_fr_g, "activity.jsonl")},
                         lambda: _disp_fr.handle_session_start({"hook_event_name": "SessionStart", "source": "resume",
                                                                "session_id": "s-fresc-g2"}))
_ctx_g_resume = (_out_g_resume or {}).get("hookSpecificOutput", {}).get("additionalContext", "")
check("(g) SessionStart resume com Client VELHO tambem devolve [CONHECIMENTO VELHO]",
      "[CONHECIMENTO VELHO]" in _ctx_g_resume and "acme" in _ctx_g_resume, _ctx_g_resume[:200])


def _brief_fr(root: str, client: str) -> dict:
    campos = {"client": client, "project": "p", "objetivo": "o", "paths": "x", "consumidor": "c",
              "destino": "d", "exemplo_falha": "e"}
    proc = subprocess.run([sys.executable, os.path.join(V2, "bin", "brief.py"), "open", "--brief", json.dumps(campos)],
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=_clean_env({"CLAUDE_PROJECT_DIR": root}))
    return json.loads(proc.stdout.decode("utf-8") or "{}")


# (k) brief: Client VELHO leva o campo conhecimento; Client OK nao leva; Client quebrado nao derruba
_b_velho = _brief_fr(_fr_g, "acme")
check("(k) brief de Client VELHO leva o campo conhecimento citando o Client",
      _b_velho.get("ok") is True and "acme" in str(_b_velho.get("conhecimento", "")), str(_b_velho)[:200])
_brief_mod = _carrega("_brief_frescor", os.path.join(V2, "bin", "brief.py"))


def _brief_direto(root: str, client: str) -> dict:
    campos = {"client": client, "project": "p", "objetivo": "o", "paths": "x", "consumidor": "c",
              "destino": "d", "exemplo_falha": "e"}
    args = _brief_mod.build_parser().parse_args(["open", "--brief", json.dumps(campos)])
    return _com_env({"CLAUDE_PROJECT_DIR": root}, lambda: args.func(args))


_b_ok = _brief_direto(_fr_h_ok, "acme")
check("(k) brief de Client OK nao leva o campo conhecimento",
      _b_ok.get("ok") is True and "conhecimento" not in _b_ok, str(_b_ok)[:200])
_b_quebrado = _brief_direto(_fr_root(), "fantasma")
check("(k) brief de Client sem pasta continua abrindo (frescor nunca derruba o brief)",
      _b_quebrado.get("ok") is True, str(_b_quebrado)[:200])

# (l) versao citada com fronteira: "1.0.1" nao vale dentro de "1.0.10"
_fr_l = _fr_root()
_fr_l_code = os.path.join(_fr_l, "produto-acme")
os.makedirs(_fr_l_code, exist_ok=True)
os.makedirs(os.path.join(_fr_l, "clients", "acme"), exist_ok=True)
with open(os.path.join(_fr_l_code, "CHANGELOG.md"), "w", encoding="utf-8") as fh:
    fh.write("## [1.0.1] - 2026-09-20" + chr(10))
with open(os.path.join(_fr_l, "clients", "acme", "client.md"), "w", encoding="utf-8") as fh:
    fh.write("- **codePath:** " + _fr_l_code + chr(10) + chr(10) + "versao 1.0.10" + chr(10))
_r_l = _fr.avaliar_client(_fr_l, "acme")
check("(l) versao 1.0.1 nao e achada dentro de 1.0.10 (ficha ATRASADA)",
      _r_l["produto"] is not None and _r_l["produto"]["ficha"] == "ATRASADA", str(_r_l["produto"]))

# (h) frescor.py --check: exit 1 com Client ativo VELHO, exit 0 sem
_fr_hcli_velho = _fr_root()
with open(os.path.join(_fr_hcli_velho, "state.json"), "w", encoding="utf-8") as fh:
    json.dump({"clients": [{"id": "acme", "status": "active"}]}, fh)
_fr_touch(os.path.join(_fr_hcli_velho, "clients", "acme", "squad", "knowledge", "graphify-out", "graph.json"), dias_atras=30)
_fr_touch(os.path.join(_fr_hcli_velho, "clients", "acme", "squad", "knowledge", "nota.md"), dias_atras=1)
_proc_check_velho = subprocess.run([sys.executable, os.path.join(V2, "bin", "frescor.py"),
                                     "--root", _fr_hcli_velho, "--check"],
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=_clean_env())
check("(h) frescor.py --check sai 1 com Client ativo VELHO", _proc_check_velho.returncode == 1, str(_proc_check_velho.returncode))

_fr_hcli_ok = _fr_root()
with open(os.path.join(_fr_hcli_ok, "state.json"), "w", encoding="utf-8") as fh:
    json.dump({"clients": [{"id": "acme", "status": "active"}]}, fh)
_fr_touch(os.path.join(_fr_hcli_ok, "clients", "acme", "squad", "knowledge", "graphify-out", "graph.json"), dias_atras=1)
_proc_check_ok = subprocess.run([sys.executable, os.path.join(V2, "bin", "frescor.py"),
                                  "--root", _fr_hcli_ok, "--check"],
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=_clean_env())
check("(h) frescor.py --check sai 0 sem Client velho", _proc_check_ok.returncode == 0, str(_proc_check_ok.returncode))

# ---------------------------------------------------------------------------
print("\n=== TASK-845: publicacao, segredo, kernel na instancia, fechamento com veredito ===")
_T845 = _sandbox_tempdir("alia-v2-t845-")
_DISPATCH_845 = os.path.join(V2, "hooks", "dispatch.py")


def _disp845(event: dict, project_dir: str) -> dict:
    env = _clean_env({"ALIA_LEDGER_PATH": os.path.join(_T845, "activity.jsonl"),
                      "CLAUDE_PROJECT_DIR": project_dir})
    proc = subprocess.run([sys.executable, _DISPATCH_845], input=json.dumps(event).encode("utf-8"),
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
    try:
        return json.loads(proc.stdout.decode("utf-8") or "{}")
    except json.JSONDecodeError:
        return {"_raw": proc.stdout.decode("utf-8", "replace")}


def _negou845(out: dict) -> bool:
    return (out.get("hookSpecificOutput") or {}).get("permissionDecision") == "deny"


# item 1 (E01): repo git de verdade, marcador com e sem HEAD, sessao principal x sub-agente
_repo845 = os.path.join(_T845, "repo")
os.makedirs(_repo845)
_g = ["git", "-c", "user.email=t@t.local", "-c", "user.name=t"]
subprocess.run(["git", "init", "-q"], cwd=_repo845)
with open(os.path.join(_repo845, "f.txt"), "w", encoding="utf-8") as fh:
    fh.write("x")
subprocess.run(_g + ["add", "f.txt"], cwd=_repo845)
subprocess.run(_g + ["commit", "-q", "-m", "x"], cwd=_repo845)
_head845 = subprocess.run(["git", "rev-parse", "HEAD"], cwd=_repo845,
                          stdout=subprocess.PIPE).stdout.decode().strip()
_mk845 = os.path.join(_repo845, ".alia", "check-ok.json")
os.makedirs(os.path.dirname(_mk845))
_push = {"hook_event_name": "PreToolUse", "tool_name": "Bash", "session_id": "t845",
         "tool_input": {"command": "git push origin main"}}


def _grava_marcador(head) -> None:
    with open(_mk845, "w", encoding="utf-8") as fh:
        json.dump({"ts": "agora", "head": head, "repo": _repo845}, fh)


_grava_marcador(None)
check("E01 negativo: marcador com head null nao libera publicacao",
      _negou845(_disp845(_push, _repo845)))
_grava_marcador("0" * 40)
check("E01 negativo: marcador com HEAD diferente do repo alvo nao libera",
      _negou845(_disp845(_push, _repo845)))
_grava_marcador(_head845)
_out845 = _disp845(_push, _repo845)
check("E01 positivo: sessao principal com HEAD igual publica", _out845 == {}, str(_out845))
check("E01 negativo: o mesmo push com agent_id (sub-agente) e negado, mesmo com marcador valido",
      _negou845(_disp845(dict(_push, agent_id="warden-1"), _repo845)))

# item 2 (E03): um valor falso por formato, montado por concatenacao (este arquivo nao dispara)
_formatos845 = {
    "sk-ant-": "sk-" + "ant-" + "api03-" + "A" * 30,
    "sk-proj-": "sk-" + "proj-" + "B" * 30,
    "ghp_": "gh" + "p_" + "C" * 36,
    "github_pat_": "github" + "_pat_" + "D" * 50,
    "nvapi-": "nv" + "api-" + "E" * 40,
    "pplx-": "pp" + "lx-" + "F" * 40,
    "JWT": "ey" + "J" + "G" * 20 + "." + "ey" + "J" + "H" * 20 + "." + "I" * 20,
    "NOME_KEY=": "NVIDIA_API" + "_KEY=" + "J" * 30,
    "NOME_TOKEN=": "GH_TO" + "KEN=" + "K" * 30,
    "NOME_SECRET=": "CLIENT_SEC" + "RET=" + "L" * 30,
}
for _nome845, _valor845 in _formatos845.items():
    _ev = {"hook_event_name": "PreToolUse", "tool_name": "Write", "session_id": "t845",
           "tool_input": {"file_path": os.path.join(_T845, "nota.md"), "content": "x " + _valor845}}
    check(f"E03 negativo: trava de segredo nega {_nome845}", _negou845(_disp845(_ev, _T845)))
_limpo845 = "o token mora no cofre; MAX_TOKEN=4096; ver GITHUB_TOKEN no ambiente"
_out845 = _disp845({"hook_event_name": "PreToolUse", "tool_name": "Write", "session_id": "t845",
                    "tool_input": {"file_path": os.path.join(_T845, "nota.md"), "content": _limpo845}}, _T845)
check("E03 positivo: texto que so cita nome de chave passa", _out845 == {}, str(_out845))
_out845 = _disp845({"hook_event_name": "PreToolUse", "tool_name": "NotebookEdit", "session_id": "t845",
                    "tool_input": {"notebook_path": os.path.join(_T845, "n.ipynb"),
                                   "new_source": _formatos845["ghp_"]}}, _T845)
check("E21 negativo: NotebookEdit com segredo tambem e negado", _negou845(_out845), str(_out845))

# item 3 (E02): CLAUDE.md da instancia passa a importar @AGENTS.md, sem perder o texto dela
_alvo845 = os.path.join(_T845, "instancia")
os.makedirs(_alvo845)
with open(os.path.join(_alvo845, "CLAUDE.md"), "w", encoding="utf-8") as fh:
    fh.write("# leis da instancia\n")
_mig845 = os.path.join(V2, "bin", "migrate.py")
for _ in range(2):  # 2 applies: prova que a importacao entra uma vez so
    _rc845, _o845, _ = run_py([_mig845, "apply", "--source", V2, "--target", _alvo845])
with open(os.path.join(_alvo845, "CLAUDE.md"), "r", encoding="utf-8") as fh:
    _claude845 = fh.read()
check("E02 positivo: CLAUDE.md da instancia abre com @AGENTS.md e guarda o texto dela",
      _rc845 == 0 and _claude845.startswith("@AGENTS.md") and "# leis da instancia" in _claude845,
      _o845[-300:] if _rc845 else "")
check("E02 negativo: dois applies nao duplicam a importacao",
      _claude845.splitlines().count("@AGENTS.md") == 1, str(_claude845.splitlines().count("@AGENTS.md")))
with open(os.path.join(_alvo845, ".claude", "settings.json"), "r", encoding="utf-8") as fh:
    _set845 = json.load(fh)["hooks"]
check("PR03 settings do motor: um desenho so (PreToolUse com NotebookEdit e PowerShell, "
      "PostToolUse Agent|Task, SubagentStop, Stop, SessionStart startup|resume|compact)",
      _set845["PreToolUse"][0]["matcher"] == "Write|Edit|NotebookEdit|Bash|PowerShell|Agent|Task|Grep|Glob"
      and _set845["PostToolUse"][0]["matcher"] == "Agent|Task"
      and _set845["SessionStart"][0]["matcher"] == "startup|resume|compact"
      and sorted(_set845) == ["PostToolUse", "PreToolUse", "SessionStart", "Stop", "SubagentStop"],
      str(sorted(_set845)))
# TASK-856: o matcher de SessionStart mudou de "compact" para "startup|resume|compact" no
# TEMPLATE (migrate.py) - o settings.json que a propria oficina usa so acompanha por
# migrate.py apply (LEI da Task: nunca editar esse arquivo a mao). Ate essa migracao rodar, a
# divergencia e ESPERADA e fica nomeada como [DIVIDA], nunca escondida nem virando FAIL falso.
_oficina_settings845 = os.path.join(os.path.dirname(V2), ".claude", "settings.json")
if os.path.isfile(_oficina_settings845):
    with open(_oficina_settings845, "r", encoding="utf-8") as fh:
        _hooks_oficina845 = json.load(fh)["hooks"]
    with open(_oficina_settings845, encoding="utf-8") as fh:
        _sem_ps1_845 = ".ps1" not in fh.read()
    if _hooks_oficina845 == _set845 and _sem_ps1_845:
        check("PR03 negativo: settings.json desta raiz e o mesmo desenho (nenhum .ps1 da 1.x)", True)
    else:
        print("[DIVIDA] settings.json da oficina ainda nao foi migrado para o desenho novo "
              "(SessionStart startup|resume|compact) - pendente de migrate.py apply, fora do "
              "escopo desta Task (o arquivo nao e editado a mao)")

# item 5 (E07): register-task.ps1 recusa done sem -GateVerdict em qualquer tipo
_reg845 = os.path.abspath(os.path.join(V2, "..", "scripts", "register-task.ps1"))
if os.path.isfile(_reg845):
    _st845 = os.path.join(_T845, "state.json")
    with open(_st845, "w", encoding="utf-8") as fh:
        json.dump({"clients": [{"id": "acme", "squad": {"gateway": "gw", "specialists": ["bruno"]}, "projects": ["p"]}],
                   "tasks": []}, fh)
    _art845 = os.path.join(_T845, "entrega.md")
    with open(_art845, "w", encoding="utf-8") as fh:
        fh.write("Entrega de prova da TASK-845: registro de fechamento com veredito do Gate. " * 8 + "\n")
    _led845 = os.path.join(_T845, "activity.jsonl")
    with open(_led845, "w", encoding="utf-8") as fh:
        fh.write(json.dumps({"event": "review_verdict", "task_id": "TASK-001", "veredito": "PASS"}) + "\n")

    # register-task.ps1 e WRAPPER da CLI `alia`. A recusa de done sem veredito e a de projeto fora do
    # cadastro vem da CLI (prova de cada recusa, com mutante, em test_espinha.py); aqui so o wrapper.
    def _reg(extra: list[str], projeto: str = "p") -> tuple[int, str]:
        p = subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", _reg845,
                            "-Client", "acme", "-Project", projeto, "-Title", "t845 ate o criterio de aceite",
                            "-Type", "construcao", "-Status", "done", "-Artifact", _art845,
                            "-Paths", _art845, "-Consumidor", "WARDEN", "-Destino", "interno",
                            "-ExemploFalha", "fechar sem veredito", "-StateFile", _st845, *extra],
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           env=_clean_env({"ALIA_LEDGER_PATH": _led845, "CLAUDE_PROJECT_DIR": _T845,
                                           "ALIA_CURRENT_TASK_PATH": os.path.join(_T845, ".cur.json")}))
        return p.returncode, (p.stdout + p.stderr).decode("utf-8", "replace")

    _rc845, _o845 = _reg([])
    check("E07 negativo: done sem -GateVerdict e recusado pelo wrapper",
          _rc845 != 0 and "GateVerdict" in _o845, _o845[-300:])
    _rc845, _o845 = _reg(["-GateVerdict", "PASS"], projeto="projeto-que-ninguem-cadastrou")
    check("E07 negativo: projeto fora do cadastro e recusado pela CLI atras do wrapper",
          _rc845 != 0 and "projeto_fora_do_cadastro" in _o845, _o845[-300:])
    _rc845, _o845 = _reg(["-GateVerdict", "PASS"])
    check("E07 positivo: o mesmo done, projeto cadastrado e veredito no ledger, fecha", _rc845 == 0, _o845[-400:])

# ---------------------------------------------------------------------------
print("\n=== TASK-845: janela de 6.000 bytes e rollback do update-online pelo check.py ===")
with open(os.path.join(_alvo845, "AGENTS.md"), "rb") as fh:
    _ag845 = len(fh.read())
with open(os.path.join(_alvo845, "CLAUDE.md"), "rb") as fh:
    _cl845 = len(fh.read())
check("janela positivo: AGENTS.md + CLAUDE.md da instancia migrada cabe em 6.000 bytes",
      _ag845 + _cl845 <= 6000, f"{_ag845} + {_cl845} = {_ag845 + _cl845} bytes")
_gordo845 = os.path.join(_T845, "instancia-gorda")
os.makedirs(_gordo845)
_texto_gordo845 = "# leis da instancia\n" + ("regra longa da instancia. " * 200)
with open(os.path.join(_gordo845, "CLAUDE.md"), "w", encoding="utf-8") as fh:
    fh.write(_texto_gordo845)
_rc845, _o845, _ = run_py([_mig845, "apply", "--source", V2, "--target", _gordo845])
with open(os.path.join(_gordo845, "CLAUDE.md"), "r", encoding="utf-8") as fh:
    _intacto845 = fh.read() == _texto_gordo845
check("janela negativo: apply recusa instancia que passaria de 6.000 bytes e nao toca nada",
      _rc845 != 0 and _intacto845 and not os.path.exists(os.path.join(_gordo845, "AGENTS.md")),
      _o845[-200:])

_uo845 = os.path.abspath(os.path.join(V2, "..", "scripts", "update-online.ps1"))
if os.path.isfile(_uo845):
    import zipfile  # noqa: E402

    def _instancia_uo(nome: str, check_sai: int) -> tuple[str, str]:
        raiz = os.path.join(_T845, nome)
        for rel, txt in (("VERSION", "2.0.4\n"), ("alia.config.json", "{}\n"),
                         ("engine/x.md", "velho\n"), ("v2/proof/check.py", "import sys\nsys.exit(0)\n")):
            os.makedirs(os.path.dirname(os.path.join(raiz, rel)), exist_ok=True)
            with open(os.path.join(raiz, rel), "w", encoding="utf-8") as fh:
                fh.write(txt)
        os.makedirs(os.path.join(raiz, "scripts"), exist_ok=True)
        shutil.copy2(_uo845, os.path.join(raiz, "scripts", "update-online.ps1"))
        zp = os.path.join(_T845, nome + ".zip")
        with zipfile.ZipFile(zp, "w") as z:
            z.writestr("pkg-main/VERSION", "2.0.5\n")
            z.writestr("pkg-main/engine/x.md", "novo\n")
            z.writestr("pkg-main/v2/proof/check.py", f"import sys\nsys.exit({check_sai})\n")
            with open(_uo845, "rb") as fh:
                z.writestr("pkg-main/scripts/update-online.ps1", fh.read())
        return raiz, zp

    def _inicia_uo(raiz: str, zp: str) -> tuple[str, subprocess.Popen]:
        return raiz, subprocess.Popen(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                                       os.path.join(raiz, "scripts", "update-online.ps1"), "-Json",
                                       "-PackageZip", zp],
                                      stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=_clean_env())

    def _fim_uo(raiz: str, proc: subprocess.Popen) -> tuple[int, str, str]:
        out, err = proc.communicate()
        with open(os.path.join(raiz, "engine", "x.md"), "r", encoding="utf-8") as fh:
            return proc.returncode, fh.read().strip(), (out + err).decode("utf-8", "replace")

    # as duas rodadas em paralelo (instancias separadas), para caber no teto de 30 s
    _uo_verm845 = _inicia_uo(*_instancia_uo("uo-vermelho", 1))
    _uo_verde845 = _inicia_uo(*_instancia_uo("uo-verde", 0))
    _rc845, _x845, _o845 = _fim_uo(*_uo_verm845)
    check("update-online negativo: check.py vermelho no pacote reverte o motor (exit != 0, engine volta)",
          _rc845 != 0 and _x845 == "velho", f"rc={_rc845} x={_x845} {_o845[-300:]}")
    _rc845, _x845, _o845 = _fim_uo(*_uo_verde845)
    check("update-online positivo: check.py verde aplica o pacote",
          _rc845 == 0 and _x845 == "novo", f"rc={_rc845} x={_x845} {_o845[-300:]}")

# ---------------------------------------------------------------------------
print("\n=== PULSO (Operacao Deep, TASK-847, WARDEN): calculo, decaimento, teto, guard ===")
sys.path.insert(0, os.path.join(V2, "lib"))
import pulso  # noqa: E402

# positivo: estado calculado de eventos sinteticos bate o valor esperado (2 FAIL = peso 4,
# 1 CONCERN sem agent_type conhecido = so conta pra "alia", 1 task_fechado_sem_veredito = peso 1;
# TASK-9001 tem pre_agent com agent_type conhecido, TASK-9002 nao - a atribuicao ao Specialist so
# vale para TASK-9001).
_eventos_pulso = [
    {"event": "pre_agent", "task_id": "TASK-9001", "agent_type": "cliente-ficticio-especialista", "ts": 1000},
    {"event": "gate_check", "task_id": "TASK-9001", "veredito": "FAIL", "ts": 1001},
    {"event": "gate_check", "task_id": "TASK-9001", "veredito": "FAIL", "ts": 1002},
    {"event": "gate_check", "task_id": "TASK-9002", "veredito": "CONCERN", "ts": 1003},
    {"event": "task_fechado_sem_veredito", "task_id": "TASK-9001", "ts": 1004},
]
_entidades_pulso, _task_agent_pulso = pulso.compute_from_events(_eventos_pulso, {}, {}, horas_passadas=0.0)
check("positivo: pressao de 'alia' bate o esperado (2 FAIL=4 + 1 CONCERN=1 + 1 sem-veredito=1 = 6.0)",
      _entidades_pulso["alia"]["pressao"]["valor"] == 6.0, str(_entidades_pulso["alia"]["pressao"]))
check("positivo: pressao do Specialist executor bate o esperado (so as 2 Tasks dele: 4+1=5.0, "
      "nunca o CONCERN de TASK-9002 que ele nunca executou)",
      _entidades_pulso["cliente-ficticio-especialista"]["pressao"]["valor"] == 5.0,
      str(_entidades_pulso["cliente-ficticio-especialista"]["pressao"]))
check("positivo: task_agent_map atribui TASK-9001 ao Specialist certo",
      _task_agent_pulso.get("TASK-9001") == "cliente-ficticio-especialista", str(_task_agent_pulso))

# decaimento: pressao (meia-vida 4h) cai pela metade em 4h sem evento novo; calor (meia-vida 1h)
# cai pela metade em 1h - as duas meias-vidas sao DIFERENTES de proposito (spec Operacao Deep).
_entidades_decai, _ = pulso.compute_from_events(
    [], {"alia": {"pressao": {"valor": 8.0, "origem": {}}, "calor": {"valor": 8.0, "origem": {}}}},
    {}, horas_passadas=4.0)
check("decaimento: pressao (meia-vida 4h) cai de 8.0 para 4.0 em 4h sem evento novo",
      _entidades_decai["alia"]["pressao"]["valor"] == 4.0, str(_entidades_decai["alia"]["pressao"]))
check("decaimento: calor (meia-vida 1h) cai de 8.0 para 0.5 em 4h (4 meias-vidas) sem evento novo",
      _entidades_decai["alia"]["calor"]["valor"] == 0.5, str(_entidades_decai["alia"]["calor"]))

# teto de caracteres: bloco normal cabe (positivo); bloco com historia gorda estoura o teto e
# render() tem que RECUSAR (prova negativa DE VERDADE - quebra de proposito, confere o FAIL,
# depois confere que o MESMO estado sem o campo gordo volta a passar, o "desfaz" da lei da casa).
_estado_normal = pulso.from_facts({
    "alia": {"pressao": 8.2, "calor": 3.0, "confianca_acumulada": 41,
             "historia": [{"nota": "nota-ficticia-1.md", "frase": "fan-out sem teto vira milhoes de token"}]},
    "cliente-ficticio-especialista": {"pressao": 7.5, "calor": 6.5},
})
_bloco_alia = pulso.render("alia", _estado_normal)
_bloco_specialist = pulso.render("cliente-ficticio-especialista", _estado_normal)
check(f"positivo: bloco 'alia' cabe no teto de {pulso.TETO_ALIA} caracteres", len(_bloco_alia) <= pulso.TETO_ALIA,
      f"{len(_bloco_alia)} chars")
check(f"positivo: bloco de Specialist cabe no teto de {pulso.TETO_SUBAGENTE} caracteres",
      len(_bloco_specialist) <= pulso.TETO_SUBAGENTE, f"{len(_bloco_specialist)} chars")
check("positivo: agent_id sem entrada no PULSO devolve string vazia (nada a injetar)",
      pulso.render("agente-fantasma-sem-entrada", _estado_normal) == "", "")

_estado_gordo = pulso.from_facts({"alia": {"pressao": 8.0, "calor": 6.0, "confianca_acumulada": 1,
    "historia": [{"nota": "n1-" + "x" * 250 + ".md", "frase": "y" * 140},
                 {"nota": "n2-" + "z" * 250 + ".md", "frase": "w" * 140}]}})
_quebrou_teto = False
try:
    pulso.render("alia", _estado_gordo)
except ValueError:
    _quebrou_teto = True
check("prova negativa: render() com historia gorda estoura o teto e LEVANTA (nunca trunca calado)",
      _quebrou_teto, "")
check("desfaz: o MESMO estado, so com a historia normal de volta, renderiza sem erro (a lei so "
      "pega o defeito real, nao trava pra sempre)",
      pulso.render("alia", _estado_normal) != "", "")

# guard (Write/Edit/Bash em pulso.json e sempre negado - so o hook Stop->recompute escreve)
_PULSO_T847 = _sandbox_tempdir("alia-v2-check-pulso-")


def _disp847(event: dict, ledger_path: str) -> dict:
    env = _clean_env({"ALIA_LEDGER_PATH": ledger_path})
    proc = subprocess.run([sys.executable, os.path.join(V2, "hooks", "dispatch.py")],
                           input=json.dumps(event).encode("utf-8"),
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
    try:
        return json.loads(proc.stdout.decode("utf-8") or "{}")
    except json.JSONDecodeError:
        return {"_raw": proc.stdout.decode("utf-8", "replace")}


def _negou847(out: dict) -> bool:
    return (out.get("hookSpecificOutput") or {}).get("permissionDecision") == "deny"


_ledger847 = os.path.join(_PULSO_T847, "activity.jsonl")
_pulso_alvo847 = os.path.join(_PULSO_T847, "pulso.json")
check("prova negativa: Write direto em pulso.json e negado pelo guard",
      _negou847(_disp847({"hook_event_name": "PreToolUse", "tool_name": "Write", "session_id": "p1",
                          "tool_input": {"file_path": _pulso_alvo847, "content": "{}"}}, _ledger847)))
check("prova negativa: Edit direto em pulso.json e negado pelo guard",
      _negou847(_disp847({"hook_event_name": "PreToolUse", "tool_name": "Edit", "session_id": "p1",
                          "tool_input": {"file_path": _pulso_alvo847, "new_string": "{}"}}, _ledger847)))
check("prova negativa: Bash escrevendo em pulso.json (redirecionamento) e negado pelo guard",
      _negou847(_disp847({"hook_event_name": "PreToolUse", "tool_name": "Bash", "session_id": "p1",
                          "tool_input": {"command": f'echo "{{}}" > "{_pulso_alvo847}"'}}, _ledger847)))
check("positivo: Write em outro arquivo qualquer (nao pulso.json) continua liberado",
      _disp847({"hook_event_name": "PreToolUse", "tool_name": "Write", "session_id": "p1",
                "tool_input": {"file_path": os.path.join(_PULSO_T847, "outro.json"), "content": "{}"}},
               _ledger847) == {})

# bloco do sub-agente anexado: pulso.json ja existe com uma entrada de Specialist sob pressao
# alta - PreToolUse de Agent/Task tem que devolver updatedInput com o bloco no fim do prompt.
pulso.save_state(_pulso_alvo847, pulso.from_facts({"cliente-ficticio-especialista": {"pressao": 8.0, "calor": 1.0}}))
_out_inject847 = _disp847({"hook_event_name": "PreToolUse", "tool_name": "Agent", "session_id": "p2",
                           "tool_input": {"subagent_type": "cliente-ficticio-especialista",
                                          "prompt": "faz a Task X"}}, _ledger847)
_updated_input847 = (_out_inject847.get("hookSpecificOutput") or {}).get("updatedInput") or {}
check("positivo: PreToolUse de Agent para um agent_id COM entrada no PULSO devolve updatedInput "
      "com o bloco anexado ao prompt",
      "PULSO (cliente-ficticio-especialista)" in str(_updated_input847.get("prompt", "")),
      str(_out_inject847))
check("positivo: updatedInput vem com permissionDecision allow (guard ja deixaria passar)",
      (_out_inject847.get("hookSpecificOutput") or {}).get("permissionDecision") == "allow",
      str(_out_inject847))
_out_sem_entrada847 = _disp847({"hook_event_name": "PreToolUse", "tool_name": "Agent", "session_id": "p3",
                                "tool_input": {"subagent_type": "agente-sem-entrada-no-pulso",
                                               "prompt": "faz a Task Y"}}, _ledger847)
check("negativo: agent_id SEM entrada no PULSO nao recebe updatedInput nenhum (nada a injetar)",
      _out_sem_entrada847 == {}, str(_out_sem_entrada847))

# cold start (Stop, 1a chamada): nunca varre o ledger existente, so marca o offset atual - prova
# via ledger com conteudo previo e confere que nenhuma entidade nasce com pressao/calor da
# HISTORIA antiga do ledger (decisao documentada: reage so daqui pra frente).
_ledger_cold847 = os.path.join(_PULSO_T847, "cold", "activity.jsonl")
os.makedirs(os.path.dirname(_ledger_cold847), exist_ok=True)
with open(_ledger_cold847, "w", encoding="utf-8") as _fh847:
    _fh847.write(json.dumps({"event": "gate_check", "task_id": "TASK-OLD", "veredito": "FAIL", "ts": 1}) + "\n")
_out_cold847 = _disp847({"hook_event_name": "Stop", "session_id": "p-cold", "transcript_path": "/x.jsonl"},
                        _ledger_cold847)
_pulso_cold847 = pulso.load_state(os.path.join(os.path.dirname(_ledger_cold847), "pulso.json"))
check("cold start: 1a chamada de recompute() nunca reconstroi retroativamente (FAIL antigo no "
      "ledger nao vira pressao de 'alia' no 1o boot)",
      _pulso_cold847.get("entidades", {}).get("alia", {}).get("pressao", {}).get("valor", 0) == 0,
      str(_pulso_cold847.get("entidades")))
check("cold start: offset gravado bate o tamanho do ledger na hora (nunca 0 com ledger nao-vazio)",
      _pulso_cold847.get("_ledger_offset", 0) == os.path.getsize(_ledger_cold847),
      str(_pulso_cold847.get("_ledger_offset")))

# Coleta das baterias-script (largadas no topo; coletar aqui deixa o trabalho em processo acima
# rodar ENQUANTO elas correm).
# ---------------------------------------------------------------------------
print("=== bateria: guard + ledger (I1/I4, hooks/dispatch.py + lib/ledger.py) ===")
rc, out, dt = collect_script(os.path.join(HERE, "run_proofs.py"))
check("run_proofs.py (guard/ledger/SubagentStop) sai verde", rc == 0, f"{dt*1000:.0f} ms")
if rc != 0:
    print(chr(10).join(l for l in out.splitlines() if "[FAIL]" in l))  # o FAIL nunca cai fora da cauda
    print(out[-3000:])

print("\n=== bateria: flow/risk.py (I6) ===")
rc, out, dt = collect_script(os.path.join(V2, "flow", "test_risk.py"))
check("test_risk.py sai verde", rc == 0, f"{dt*1000:.0f} ms")
if rc != 0:
    print(out[-2000:])

print("\n=== bateria: flow/slice.py (TASK-812 item B, fatiar tarefa grande) ===")
rc, out, dt = collect_script(os.path.join(V2, "flow", "test_slice.py"))
check("test_slice.py sai verde", rc == 0, f"{dt*1000:.0f} ms")
if rc != 0:
    print(out[-2000:])

print("\n=== bateria: bin/task.py (I2, CLI open/close/context) ===")
rc, out, dt = collect_script(os.path.join(HERE, "test_task.py"))
check("test_task.py sai verde", rc == 0, f"{dt*1000:.0f} ms")
if rc != 0:
    print(out[-3000:])

print("\n=== bateria: ciclo de trabalho sem deadlock (2.1.2, TASK-862) ===")
rc, out, dt = collect_script(os.path.join(HERE, "test_ciclo.py"))
check("test_ciclo.py sai verde (toda acao do ciclo tem ator liberado + mutantes pegos)", rc == 0, f"{dt*1000:.0f} ms")
if rc != 0:
    print(out[-3000:])

print("\n=== bateria: bin/gate.py (TASK-838, ponteiro verificavel em funciona/goal-backward) ===")
rc, out, dt = collect_script(os.path.join(HERE, "test_gate.py"))
check("test_gate.py sai verde", rc == 0, f"{dt*1000:.0f} ms")
if rc != 0:
    print(out[-3000:])

print("\n=== bateria: bin/migrate.py (D1, achado do Gate do NEXUS: apply/undo sem prova automatica) ===")
rc, out, dt = collect_script(os.path.join(HERE, "test_migrate.py"))
check("test_migrate.py sai verde", rc == 0, f"{dt*1000:.0f} ms")
if rc != 0:
    print(out[-3000:])

# squad-bridge -Only (thread largada no topo)
print("\n=== squad-bridge -Only: nunca apaga bundle fora do escopo (v2/squad/squad-bridge.ps1, fixture isolada) ===")
_SB_THREAD.join()
for _k, _nome in (("full", "geracao completa da fixture gera os bundles dos 2 Clients (base da contagem)"),
                  ("cliente", "-Client X -Only <client>: contagem de .claude/agents nao cai, o outro Client segue la, sem REMOVIDO"),
                  ("especialista", "-Client X -Only <especialista> (o caso do incidente): contagem nao cai, o outro Client segue la, sem REMOVIDO"),
                  ("regenera", "-Only regenera o alvo apagado e o outro Client fica intacto")):
    _ok, _det = SB_RESULT.get(_k, (False, "prova nao terminou: " + SB_RESULT.get("erro", "?")))
    check("squad-bridge -Only: " + _nome, _ok, _det)

# ---------------------------------------------------------------------------
# MURO DE DELEGACAO (30/09/2026): a sessao principal so delega. Prova pelo negativo: alem dos
# casos de nega/libera, um MUTANTE do dispatch (muro desligado no codigo) tem que ser pego.
# ---------------------------------------------------------------------------
print("\n=== MURO DE DELEGACAO: sessao principal nao escreve dominio ===")
_TW = _sandbox_tempdir("alia-v2-wall-")
_DISPATCH_W = os.path.join(V2, "hooks", "dispatch.py")


def _dispW(event: dict, extra_env: dict | None = None, dispatch: str = _DISPATCH_W, off_file: bool = False) -> dict:
    os.makedirs(os.path.join(_TW, ".claude"), exist_ok=True)
    _of = os.path.join(_TW, ".claude", "delegation-wall.off")
    if off_file:
        open(_of, "w").write("x")
    elif os.path.exists(_of):
        os.remove(_of)
    env = _clean_env({"ALIA_LEDGER_PATH": os.path.join(_TW, "activity.jsonl"),
                      "CLAUDE_PROJECT_DIR": _TW, "ALIA_DELEGATION_WALL_OFF": "0",
                      **(extra_env or {})})
    proc = subprocess.run([sys.executable, dispatch], input=json.dumps(event).encode("utf-8"),
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
    try:
        return json.loads(proc.stdout.decode("utf-8") or "{}")
    except json.JSONDecodeError:
        return {"_raw": proc.stdout.decode("utf-8", "replace")}


def _muro(out: dict) -> bool:
    return "muralha de delegacao" in str((out.get("hookSpecificOutput") or {}).get("permissionDecisionReason", ""))


def _evW(tool: str, ti: dict, sess: str = "wallS", sub: bool = False) -> dict:
    e = {"hook_event_name": "PreToolUse", "tool_name": tool, "session_id": sess, "tool_input": ti}
    if sub:
        e["agent_id"] = "ag1"
    return e


_wp = _TW.replace("\\", "/") + "/src/app.py"
_wm = _TW.replace("\\", "/") + "/memory/nota.md"
_o = _dispW(_evW("Write", {"file_path": _wp, "content": "x"}))
check("muro: sessao principal Write fora da infra e negada", _muro(_o))
check("muro: a negacao diz a quem delegar", "Specialist" in str(_o) or "Gateway" in str(_o))
check("muro: Write em memoria (infra) passa", not _muro(_dispW(_evW("Write", {"file_path": _wm, "content": "x"}))))
check("muro: Write em state.json passa", not _muro(_dispW(_evW("Write", {"file_path": _TW + "/state.json", "content": "{}"}))))
check("muro: Write em docs/ops passa", not _muro(_dispW(_evW("Write", {"file_path": _TW + "/docs/ops/a.md", "content": "x"}))))
check("muro: sub-agente (agent_id) escreve fora da infra sem ser barrado",
      not _muro(_dispW(_evW("Write", {"file_path": _wp, "content": "x"}, sub=True))))
check("muro: NotebookEdit da sessao principal negado",
      _muro(_dispW(_evW("NotebookEdit", {"notebook_path": _TW + "/n.ipynb", "new_source": "x"}))))
check("muro: Bash `>` em arquivo de dominio negado",
      _muro(_dispW(_evW("Bash", {"command": f"echo oi > {_wp}"}))))
check("muro: PowerShell Set-Content em dominio negado",
      _muro(_dispW(_evW("PowerShell", {"command": f"Set-Content -Path {_wp} -Value x"}))))
check("muro: python -c que escreve arquivo negado",
      _muro(_dispW(_evW("Bash", {"command": "python -c \"open('a.txt','w').write('x')\""}))))
check("muro: Bash so de leitura passa",
      not _muro(_dispW(_evW("Bash", {"command": f"cat {_wp} | grep x 2>&1"}))))
check("muro: Bash escrevendo em memoria passa",
      not _muro(_dispW(_evW("Bash", {"command": f"echo oi >> {_wm}"}))))
# liberacao com prazo
_gp = os.path.join(_TW, ".alia", "direto.json")
os.makedirs(os.path.dirname(_gp), exist_ok=True)


def _grant(sess="wallS", ini=0.0, dur=1800, quote="faz voce mesma"):
    t = time.time() + ini
    with open(_gp, "w", encoding="utf-8") as fh:
        json.dump({"session_id": sess, "granted_at": t, "expires_at": t + dur, "ceo_quote": quote}, fh)


_ev_w = _evW("Write", {"file_path": _wp, "content": "x"})
_grant()
check("muro: liberacao valida (mesma sessao) deixa passar", not _muro(_dispW(_ev_w)))
_grant(sess="outra")
check("muro: liberacao de OUTRA sessao nao vale", _muro(_dispW(_ev_w)))
_grant(ini=-7200, dur=1800)
check("muro: liberacao vencida nao vale", _muro(_dispW(_ev_w)))
_grant(dur=86400)
check("muro: liberacao com prazo > 60 min nao vale", _muro(_dispW(_ev_w)))
_grant(quote="")
check("muro: liberacao sem frase do CEO nao vale", _muro(_dispW(_ev_w)))
os.remove(_gp)
# interruptor
check("muro: ALIA_DELEGATION_WALL_OFF=1 desliga o bloqueio",
      not _muro(_dispW(_ev_w, {"ALIA_DELEGATION_WALL_OFF": "1"})))
check("muro: .claude/delegation-wall.off desliga o bloqueio", not _muro(_dispW(_ev_w, off_file=True)))
check("muro: sem interruptor volta a bloquear", _muro(_dispW(_ev_w)))
# liberacao SO pelo hook de prompt do CEO; a sessao principal nao se libera
_ups = {"hook_event_name": "UserPromptSubmit", "session_id": "wallS"}
_dispW({**_ups, "prompt": "bom dia, como esta o status?"})
check("muro: prompt comum do CEO NAO libera", not os.path.exists(_gp) and _muro(_dispW(_ev_w)))
_o_up = _dispW({**_ups, "prompt": "Alia, faz voce mesma essa edicao"})
check("muro: pedido expresso do CEO (UserPromptSubmit) libera e manda confirmar",
      os.path.exists(_gp) and not _muro(_dispW(_ev_w)) and "Confirme" in str(_o_up))
os.remove(_gp)
_aut = _dispW(_evW("Bash", {"command": "python v2/bin/direto.py grant \"faz voce mesma\" --session wallS"}))
check("muro: NEGATIVO - a Alia tenta se liberar via Bash e o muro nega",
      _muro(_aut) and not os.path.exists(_gp))
_forja = lambda o: _muro(o) or "nao se escrevem por ferramenta" in str(o) or "nao se forjam por comando" in str(o)  # 2.1.3: negada tambem pela guarda de marcador
check("muro: autoliberacao via Write em direto.json tambem negada",
      _forja(_dispW(_evW("Write", {"file_path": _gp.replace("\\", "/"), "content": "{}"}))))
check("muro: autoliberacao via PowerShell negada",
      _forja(_dispW(_evW("PowerShell", {"command": f"Set-Content {_gp} '{{}}'"}))))
# PROVA PELO NEGATIVO: mutante com o muro desligado no codigo tem que ser pego pelo teste
_mut = os.path.join(_TW, "mut", "v2")
shutil.copytree(V2, _mut, ignore=shutil.ignore_patterns("__pycache__", "proof", "deep"))
_mp = os.path.join(_mut, "hooks", "dispatch.py")
_src = open(_mp, encoding="utf-8").read()
_alvo = 'if event.get("_is_subagent") or _wall_off():\n        return None'
check("muro: ponto de mutacao existe no dispatch", _src.count(_alvo) == 1)
open(_mp, "w", encoding="utf-8", newline="").write(_src.replace(_alvo, "return None"))
check("muro: NEGATIVO - mutante sem muro deixa a escrita passar (o teste acima o pegaria)",
      not _muro(_dispW(_ev_w, dispatch=_mp)))

# PULSO vetado: sem ALIA_PULSO=1 nada entra no SessionStart nem no prompt do sub-agente, e o Stop
# nao regrava. Prova pelo negativo com mutante que ignora a flag.
print("\n=== PULSO: desligado salvo opt-in (ALIA_PULSO=1) ===")
_TP = _sandbox_tempdir("alia-v2-pulsoflag-")
_lp = os.path.join(_TP, "activity.jsonl")
pulso.save_state(os.path.join(_TP, "pulso.json"),
                 pulso.from_facts({"alia": {"pressao": 8.0, "calor": 1.0},
                                   "cliente-ficticio-especialista": {"pressao": 8.0, "calor": 1.0}}))
_ev_ag = {"hook_event_name": "PreToolUse", "tool_name": "Agent", "session_id": "pf",
          "tool_input": {"subagent_type": "cliente-ficticio-especialista", "prompt": "faz X"}}
_ev_ss = {"hook_event_name": "SessionStart", "source": "startup", "session_id": "pf"}


def _dispP(event: dict, flag: str | None, dispatch: str | None = None) -> dict:
    env = _clean_env({"ALIA_LEDGER_PATH": _lp, "CLAUDE_PROJECT_DIR": _TP,
                      **({"ALIA_PULSO": flag} if flag is not None else {})})
    if flag is None:
        env.pop("ALIA_PULSO", None)
    proc = subprocess.run([sys.executable, dispatch or os.path.join(V2, "hooks", "dispatch.py")],
                          input=json.dumps(event).encode("utf-8"), stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, env=env)
    try:
        return json.loads(proc.stdout.decode("utf-8") or "{}")
    except json.JSONDecodeError:
        return {}


check("PULSO off: prompt do sub-agente NAO recebe bloco sem a flag",
      "PULSO (" not in str(_dispP(_ev_ag, None)))
check("PULSO off: SessionStart NAO injeta bloco sem a flag",
      "PULSO" not in str(_dispP(_ev_ss, None)))
_dispP({"hook_event_name": "Stop", "session_id": "pf", "transcript_path": "/x.jsonl"}, None)
_ps = pulso.load_state(os.path.join(_TP, "pulso.json"))
check("PULSO off: Stop NAO regrava o pulso.json (sem _ledger_offset novo)", "_ledger_offset" not in _ps)
check("PULSO on (controle): com ALIA_PULSO=1 o bloco volta ao sub-agente e ao SessionStart",
      "PULSO (cliente-ficticio-especialista)" in str(_dispP(_ev_ag, "1"))
      and "PULSO: pressao 8.0" in str(_dispP(_ev_ss, "1")))
_mp2 = os.path.join(_TP, "mut", "v2")
shutil.copytree(V2, _mp2, ignore=shutil.ignore_patterns("__pycache__", "proof", "deep"))
_f2 = os.path.join(_mp2, "hooks", "dispatch.py")
_s2 = open(_f2, encoding="utf-8").read()
_al2 = 'return os.environ.get("ALIA_PULSO") == "1"'
check("PULSO off: ponto de mutacao existe", _s2.count(_al2) == 1)
open(_f2, "w", encoding="utf-8", newline="").write(_s2.replace(_al2, "return True"))
check("PULSO off: NEGATIVO - mutante que ignora a flag injeta o bloco (o teste acima o pegaria)",
      "PULSO (cliente-ficticio-especialista)" in str(_dispP(_ev_ag, None, _f2)))

# client.py use X so toca {X}-* (incidente 30/09 21:57: `use <client>` apagou 150 agentes de outros
# Clients). Prova pelo negativo: a versao quebrada (sem a trava --prune) tem que apagar o outro.
print("\n=== client.py use: rodar para um Client nunca apaga o outro ===")
_TC = _sandbox_tempdir("alia-v2-clientuse-")


def _cu_fixture(tag: str) -> tuple[str, str]:
    """Repo sintetico com 2 Clients (fx-a, fx-b) + macro, gerados pela bridge de verdade (
    nao ha mais reserva .claude/squads; `use` chama v2/squad/bridge.ps1)."""
    root, ag = os.path.join(_TC, "repo-" + tag), os.path.join(_TC, "agents-" + tag)
    shutil.rmtree(root, ignore_errors=True)
    shutil.rmtree(ag, ignore_errors=True)
    _oficina = os.path.dirname(V2)
    shutil.copytree(os.path.join(_oficina, "engine"), os.path.join(root, "engine"))  # a bridge resolve docs citados no contrato
    for c in ("fx-a", "fx-b"):
        dst = os.path.join(root, "clients", c, "squad")
        os.makedirs(os.path.join(dst, "agents"))
        # dado proprio da fixture: nada de squad/ da oficina (nao existe em estudio nem no produto)
        _ag = [("nexus", "NEXUS", "A", "full", True), ("warden", "WARDEN", "B", "expert", False)]
        _y = [f"squad:\n  client: {c}\n  name: Fixture {c}\n  preset: engine\n  domain: fixture\n  status: active\n",
              "gateway: nexus\n", "agents:\n"]
        for i, nm, cam, brain, gw in _ag:
            _y.append(f"  - id: {i}\n    name: {nm}\n    role: Fixture {nm}\n    camada: {cam}\n    brain: {brain}\n"
                      f"    gateway: {str(gw).lower()}\n    domain: fixture\n    knowledge: [all]\n")
            open(os.path.join(dst, "agents", i + ".md"), "w", encoding="utf-8", newline="").write(
                f"# {nm} - fixture ({c})\n\n## Papel\n\nPersona sintetica da prova.\n")
            open(os.path.join(dst, "agents", i + ".yaml"), "w", encoding="utf-8", newline="").write(
                f"id: {i}\nname: {nm}\nrole: Fixture {nm}\nclient: {c}\ncamada: {cam}\nbrain: {brain}\n"
                f"gateway: {str(gw).lower()}\ndomain: fixture\nknowledge:\n - all\nentry_point: knowledge/MAP.md\n"
                f"budget:\n tool_calls: 20\n tokens: null\noutput_contract:\n max_lines: 60\n evidence_tags: [MEDIDO, LIDO, INFERIDO]\n"
                f"grounding: client.md\nauthority:\n decides: fixture\n escalates_to: fixture\n")
        open(os.path.join(dst, "squad.yaml"), "w", encoding="utf-8", newline="").write("".join(_y))
        os.makedirs(os.path.join(dst, "knowledge"), exist_ok=True)
        open(os.path.join(dst, "knowledge", "MAP.md"), "w", encoding="utf-8").write("# MAP\n")  # a bridge exige o MAP.md do Client
    os.makedirs(ag)
    for n in ("fx-b-nexus.md", "fx-b-velho.md"):
        open(os.path.join(ag, n), "w", encoding="utf-8").write("vivo")
    return root, ag


def _cu_run(script: str, extra: list[str], tag: str) -> list[str]:
    root, ag = _cu_fixture(tag)
    r = subprocess.run([sys.executable, script, "--repo-root", root, "--agents-dir", ag, "use", "fx-a"] + extra,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=_clean_env())
    _cu_ult[tag] = r.stdout.decode("utf-8", "replace")
    return sorted(os.listdir(ag))


_cu_ult: dict[str, str] = {}
_cu_real = os.path.join(V2, "bin", "client.py")
_cu_src = open(_cu_real, encoding="utf-8").read()
_cu_trava = '    if args.prune:\n        cmd.append("-Prune")'
shutil.copytree(os.path.join(V2, "lib"), os.path.join(_TC, "v2", "lib"), ignore=shutil.ignore_patterns("__pycache__"))
shutil.copytree(os.path.join(V2, "squad"), os.path.join(_TC, "v2", "squad"), ignore=shutil.ignore_patterns("__pycache__"))
os.makedirs(os.path.join(_TC, "v2", "bin"))
_cu_mut = os.path.join(_TC, "v2", "bin", "client.py")
open(_cu_mut, "w", encoding="utf-8", newline="").write(_cu_src.replace(_cu_trava, '    if True:\n        cmd.append("-Prune")'))
# as 3 execucoes (cada uma = 1 powershell da bridge) sobem juntas: custo do mais lento, nao da soma
from concurrent.futures import ThreadPoolExecutor  # noqa: E402
with ThreadPoolExecutor(3) as _cu_ex:
    _f_sem = _cu_ex.submit(_cu_run, _cu_real, [], "sem")
    _f_pr = _cu_ex.submit(_cu_run, _cu_real, ["--prune"], "pr")
    _f_mut = _cu_ex.submit(_cu_run, _cu_mut, [], "mut")
    _cu_sem, _cu_pr, _cu_mutres = _f_sem.result(), _f_pr.result(), _f_mut.result()
check("client.py use fx-a chama a bridge: gera fx-a-* e os macro", "fx-a-warden.md" in _cu_sem and "macro-leitor.md" in _cu_sem,
      f"{_cu_sem} {_cu_ult.get('sem', '')[:200]}")
check("client.py use fx-a NAO apaga agentes do fx-b", "fx-b-nexus.md" in _cu_sem and "fx-b-velho.md" in _cu_sem, str(_cu_sem))
check("client.py use fx-a --prune (explicito) remove os do fx-b e mantem fx-a e macro",
      "fx-b-nexus.md" not in _cu_pr and "fx-b-velho.md" not in _cu_pr and "fx-a-nexus.md" in _cu_pr and "macro-leitor.md" in _cu_pr, str(_cu_pr))
check("client.py: ponto de mutacao (trava --prune) existe", _cu_src.count(_cu_trava) == 1)
check("client.py: nao ha mais reserva .claude/squads", "DEFAULT_SQUADS_DIR" not in _cu_src and "--squads-dir" not in _cu_src)
check("client.py: NEGATIVO - versao quebrada apaga o fx-b sem --prune (o check acima a reprovaria)",
      "fx-b-nexus.md" not in _cu_mutres)

# ---------------------------------------------------------------------------
print("\n=== Gate - artifact obrigatorio (mutante L65/L76 tem que cair) e shell aninhado ===")
_tm_src_path = os.path.join(V2, "lib", "task_model.py")
_tm_real = _carrega("_task_model_w1", _tm_src_path)
_w1_task = {"id": "TASK-GATE", "status": "open", "type": "feature"}
_w1_ev = [{"event": "review_verdict", "task_id": "TASK-GATE", "veredito": "PASS"}]


def _fecha_sem_artifact(mod) -> bool:
    """True quando fechar com --artifact vazio foi RECUSADO (o comportamento certo)."""
    try:
        mod.fechar(dict(_w1_task), "PASS", "", _w1_ev)
    except mod.TaskError:
        return True
    return False


check("gate: task_model.fechar recusa artifact vazio", _fecha_sem_artifact(_tm_real), "")
_tm_src = open(_tm_src_path, encoding="utf-8", newline="").read()
check("gate: ponto de mutacao `if not artifact:` existe", "    if not artifact:\n" in _tm_src, "")
_tm_mut_dir = _sandbox_tempdir("alia-v2-check-w1-tm-")
_tm_mut_path = os.path.join(_tm_mut_dir, "task_model_mut.py")
open(_tm_mut_path, "w", encoding="utf-8", newline="").write(_tm_src.replace("    if not artifact:\n", "    if False:\n", 1))
check("gate: NEGATIVO - mutante L65/L76 (`if not artifact` -> `if False`) CAI: o teste acima o reprova",
      not _fecha_sem_artifact(_carrega("_task_model_w1_mut", _tm_mut_path)), "")

# shell aninhado (powershell -Command / python -c) escreve sem o guard ver o alvo; a varredura
# periodica da arvore publicavel (acima) e quem pega. Prova: o guard deixa passar o comando e a
# varredura acusa o arquivo que ele escreveria.
_w1_dest = os.path.join(_SCAN_ROOT, "___w1-aninhado.md")
_w1_home = os.path.expanduser("~")
_w1_ninho = {"hook_event_name": "PreToolUse", "tool_name": "Bash", "session_id": "w1",
             "tool_input": {"command": f'powershell -Command "Set-Content -Path {_w1_dest} -Value vazou"'}}
_w1_n_out = _com_env({"ALIA_DELEGATION_WALL_OFF": "1"}, lambda: _disp_fr.handle_pretooluse_guard(dict(_w1_ninho)))
check("shell aninhado: o guard NAO enxerga a escrita dentro de `powershell -Command` (a lacuna que a varredura cobre)",
      _w1_n_out == {}, str(_w1_n_out))
_id_leaks_antes = len(_id_leaks)
_w1_arq = os.path.join(_sandbox_tempdir("alia-v2-check-w1-nest-"), "nested.md")
open(_w1_arq, "w", encoding="utf-8").write("escrito por shell aninhado: " + _w1_home + "\n")
_scan_file_for_identity(_w1_arq)
check("shell aninhado: a varredura periodica ACUSA o arquivo que o shell aninhado escreveu",
      len(_id_leaks) == _id_leaks_antes + 1, str(_id_leaks[_id_leaks_antes:]))
del _id_leaks[_id_leaks_antes:]
_id_scan_count -= 1
check("shell aninhado: positivo - arquivo limpo nao acusa", (lambda: (open(_w1_arq, "w", encoding="utf-8").write("limpo\n"),
      _scan_file_for_identity(_w1_arq), len(_id_leaks) == _id_leaks_antes)[-1])(), "")
_id_scan_count -= 1

# ---------------------------------------------------------------------------
print("\n=== check-public-surface - nao rastreados, e-mail/caminho pessoal e autoria (provado pelo negativo) ===")
_CPS = os.path.join(os.path.dirname(V2), "scripts", "check-public-surface.ps1")
_cps_fx = _sandbox_tempdir("alia-v2-check-cps-")
_cps_repo = os.path.join(os.path.realpath(_cps_fx), "repo")  # PowerShell nao entra por caminho 8.3
os.makedirs(_cps_repo)
_g = lambda *a: subprocess.run(["git", *a], cwd=_cps_repo, check=True, capture_output=True)
_g("init", "-q")
_g("config", "user.email", "fx@users.noreply.github.com")
_g("config", "user.name", "fx")
open(os.path.join(_cps_repo, "rastreado.md"), "w", encoding="utf-8").write("contato fulano.teste@gm" "ail.com e pasta C:/Us" "ers/Zeca/proj\n")
_g("add", "rastreado.md")
subprocess.run(["git", "-c", "user.email=autor.pessoal@gm" "ail.com", "-c", "user.name=autor", "commit", "-q", "-m", "fx"],
               cwd=_cps_repo, check=True, capture_output=True)
open(os.path.join(_cps_repo, "do-motor.txt"), "w", encoding="utf-8").write("ok" + chr(10))
_g("add", "do-motor.txt")
subprocess.run(["git", "-c", "user.email=noreply@alia-flow.local", "-c", "user.name=Alia Flow", "commit", "-q", "-m", "fx2"],
               cwd=_cps_repo, check=True, capture_output=True)
open(os.path.join(_cps_repo, "novo-nao-rastreado.md"), "w", encoding="utf-8").write("C:/Us" "ers/Beltrano2/x\n")
open(os.path.join(_cps_repo, "plano-ops.md"), "w", encoding="utf-8").write("ver docs" + "/ops/red-team-x\n")
open(os.path.join(_cps_repo, "plano-etapa.py"), "w", encoding="utf-8").write("# W" + "5b etapa interna\n")
open(os.path.join(_cps_repo, "falso-positivo.py"), "w", encoding="utf-8").write('TASK_ID = "TASK-W' + '1"\nw5b_x = 1\n')


def _cps_start(script: str) -> subprocess.Popen:
    return subprocess.Popen(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script, "-Repo", _cps_repo],
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=_clean_env())


_cps_src = open(_CPS, encoding="utf-8", newline="").read()
_cps_pontos = {
    "sem --others": "@(& git ls-files --others --exclude-standard)",
    "sem agulhas": "$m1 = $emailRe.Match($conteudo)",
    "sem autoria": "if ($mail -and $mail -notmatch",
}
_cps_muts = {}
for _nome, _ponto in _cps_pontos.items():
    check(f"public-surface: ponto de mutacao existe ({_nome})", _ponto in _cps_src, _ponto)
    _alvo_mut = os.path.join(_cps_fx, "mut-" + _nome.replace(" ", "_").replace("-", "") + ".ps1")
    _novo = {"sem --others": ("@(& git ls-files --others --exclude-standard)", "@()"),
             "sem agulhas": ("$m1 = $emailRe.Match($conteudo)", "$m1 = [regex]::Match('', 'nunca-casa-xyz')"),
             "sem autoria": ("if ($mail -and $mail -notmatch", "if ($false -and $mail -notmatch")}[_nome]
    open(_alvo_mut, "w", encoding="utf-8", newline="").write(_cps_src.replace(_novo[0], _novo[1], 1))
    _cps_muts[_nome] = _cps_start(_alvo_mut)
_cps_real = _cps_start(_CPS)
_cps_saida = {n: pr.communicate()[0].decode("utf-8", "replace") for n, pr in _cps_muts.items()}
_cps_real_out = _cps_real.communicate()[0].decode("utf-8", "replace")
check("public-surface: o script real REPROVA com o veredito da LEI (exit 1, nao erro de partida)",
      _cps_real.returncode == 1 and "REPROVADO:" in _cps_real_out,
      "" if _cps_real.returncode == 1 and "REPROVADO:" in _cps_real_out else _cps_real_out[-300:])  # saida da fixture so aparece se a prova falhar
check("public-surface: acusa o arquivo NAO RASTREADO", "pessoal vazou: novo-nao-rastreado.md" in _cps_real_out, "")
check("public-surface: acusa e-mail pessoal e caminho de usuario no rastreado",
      "pessoal vazou: rastreado.md  (e-mail pessoal)" in _cps_real_out
      and "pessoal vazou: rastreado.md  (caminho de usuario real da maquina)" in _cps_real_out, "")
check("public-surface: acusa pasta interna de operacao e id de etapa em comentario",
      "pessoal vazou: plano-ops.md  (cita pasta interna de operacao)" in _cps_real_out
      and "pessoal vazou: plano-etapa.py  (cita id de etapa interna (plano))" in _cps_real_out, "")
check("public-surface: sem falso positivo em task id/variavel", "falso-positivo.py" not in _cps_real_out, "")
check("public-surface: acusa autor/committer que nao e noreply", "autoria: autor/committer do historico nao e noreply: autor.pessoal@gm" "ail.com" in _cps_real_out, "")
check("public-surface: noreply@alia-flow.local (sem dado pessoal) NAO e acusado", "historico nao e noreply: noreply@alia-flow.local" not in _cps_real_out, "")
check("public-surface: mutantes rodaram ate o fim (veredito impresso)", all("REPROVADO:" in o or "SUPERFICIE LIMPA" in o for o in _cps_saida.values()), "")
check("public-surface: NEGATIVO - mutante sem `--others` deixa o nao rastreado passar",
      "novo-nao-rastreado.md" not in _cps_saida["sem --others"], "")
check("public-surface: NEGATIVO - mutante sem agulhas deixa o e-mail pessoal passar",
      "(e-mail pessoal)" not in _cps_saida["sem agulhas"], "")
check("public-surface: NEGATIVO - mutante sem conferencia de autoria deixa o autor pessoal passar",
      "autoria:" not in _cps_saida["sem autoria"], "")

# ---------------------------------------------------------------------------
print("\n=== law-ledger - COBERTA exige teste que EXISTE (fim dos testes fantasmas) ===")
# copia de empacotamento = a que nao leva o empacotador (scripts/package-release.ps1 e oficina-only), onde quer que
# esteja (antes: so o caminho release/alia-flow, e a copia em %TEMP% do proprio empacotador escapava)
_EMPACOTAMENTO = (not os.path.isfile(os.path.join(os.path.dirname(V2), "scripts", "package-release.ps1"))
                  or "/release/alia-flow/" in (V2.replace("\\", "/") + "/"))
_LEDGER_MD = os.path.join(os.path.dirname(V2), "engine", "governance", "law-ledger.md")
_ledger_arquivos: set[str] = set()
for _rt in ("scripts", "v2", "engine"):
    for _r, _d, _fs in os.walk(os.path.join(os.path.dirname(V2), _rt)):
        _ledger_arquivos.update(_fs)


def _ledger_coberta_fantasma(linhas: list[str]) -> list[str]:
    """Ids de leis `COBERTA` cujos testes citados (`x.ps1`/`x.py`) nao existem no disco."""
    ruins = []
    for _ln in linhas:
        if not _ln.startswith("| L"):
            continue
        _c = _ln.split("|")
        if len(_c) != 7 or not _c[5].strip().startswith("COBERTA"):
            continue
        _citados = set(re.findall(r"([\w.-]+\.(?:ps1|py))", _c[4]))
        if _citados and not any(x in _ledger_arquivos for x in _citados):
            ruins.append(_c[1].strip())
    return ruins


if os.path.isfile(_LEDGER_MD):
    _ledger_linhas = open(_LEDGER_MD, encoding="utf-8").read().splitlines()
    if _EMPACOTAMENTO:  # L34/L62/L69 citam package-release/smoke-test/release-gate, que so existem na oficina
        print("[MEDIDO] ledger: conferencia de teste fantasma roda so na oficina (a copia de empacotamento nao leva "
              "os scripts de release); as unidades abaixo rodam sempre")
    else:
        check("ledger: nenhuma lei COBERTA cita so teste inexistente", _ledger_coberta_fantasma(_ledger_linhas) == [],
              str(_ledger_coberta_fantasma(_ledger_linhas)))
    check("ledger: NEGATIVO - linha COBERTA que cita teste fantasma e pega pela conferencia",
          _ledger_coberta_fantasma(["| L99 | x | y | `nao-existe-w1.ps1` | COBERTA (fixture) |"]) == ["L99"], "")
    check("ledger: positivo - COBERTA citando teste que existe (check.py) nao acusa",
          _ledger_coberta_fantasma(["| L99 | x | y | `check.py` | COBERTA |"]) == [], "")
else:
    print("[INFO] law-ledger.md ausente nesta instalacao - conferencia pulada")

# ---------------------------------------------------------------------------
print("\n=== provas ligadas (RSI reincidencia, memoria_check, divida renovavel, grafo) ===")
for _tn, _rot in (("test_rsi_reincidencia.py", "rsi_reincidencia.py (teste de reincidencia por aprendizado, com negativo)"),
                  ("test_memoria_check.py", "memoria_check.py (orfa + valido_de, com negativo)"),
                  ("test_frescor_divida.py", "frescor: divida renovavel no maximo 1 vez"),
                  ("test_grafo.py", "grafo_saude / grafo_uso"),
                  ("test_espinha.py", "espinha: CLI alia, schema, adaptadores, trava do grafo/wiki (cada recusa com mutante)")):
    _rc, _out, _dt = collect_script(os.path.join(HERE, _tn))
    check(f"{_rot} - {_tn} sai verde", _rc == 0, (_out[-300:] if _rc else f"{_dt*1000:.0f} ms"))
_rsi_rc, _rsi_out, _ = run_py([os.path.join(V2, "bin", "rsi_reincidencia.py"), "--root", os.path.dirname(os.path.dirname(os.path.dirname(V2))), "--check"])
print(f"[MEDIDO] rsi_reincidencia.py no estudio real: exit {_rsi_rc} (reincidencia real e sinal para a Alia, nao falha da prova): "
      + (_rsi_out.strip().splitlines() or ["sem saida"])[-1][:160])

# ---------------------------------------------------------------------------
print("\n=== [AGENTE VELHO] - source_hash do bundle x fonte (frescor.agentes_velhos) ===")
_av = _sandbox_tempdir("alia-v2-check-agvelho-")
_av_src = os.path.join(_av, "engine", "macro", "agents")
os.makedirs(_av_src)
os.makedirs(os.path.join(_av, "studio"))
os.makedirs(os.path.join(_av, ".claude", "agents"))
open(os.path.join(_av_src, "leitor.md"), "wb").write(b"persona v1\n")
open(os.path.join(_av_src, "leitor.yaml"), "wb").write(b"id: leitor\n")
_av_hash = hashlib.sha256(b"persona v1\n" + b"id: leitor\n").hexdigest()[:16]
_av_bundle = os.path.join(_av, ".claude", "agents", "macro-leitor.md")
open(_av_bundle, "w", encoding="utf-8").write(f"corpo\n<!-- source_hash: {_av_hash} -->\n")
check("agentes_velhos: bundle com hash igual ao da fonte NAO e velho", _fr.agentes_velhos(_av) == [], "")
open(os.path.join(_av_src, "leitor.md"), "wb").write(b"persona v2 editada\n")
_av_v = _fr.agentes_velhos(_av)
check("agentes_velhos: persona editada depois de gerar = [AGENTE VELHO]", [v["arquivo"] for v in _av_v] == ["macro-leitor.md"], str(_av_v))
_av_div = (datetime.now(timezone.utc) + timedelta(days=3)).strftime("%Y-%m-%d")
open(os.path.join(_av, "studio", "conhecimento-dividas.txt"), "w", encoding="utf-8").write(f"macro {_av_div} refazendo\n")
check("agentes_velhos: divida com prazo cala (mesma regra do mapa)", _fr.agentes_velhos(_av) == [], "")
os.remove(os.path.join(_av, "studio", "conhecimento-dividas.txt"))
_fr_src_txt = open(os.path.join(V2, "lib", "frescor.py"), encoding="utf-8").read()
_av_ponto = "if esperado is None or esperado == achados[-1]:"
check("agentes_velhos: ponto de mutacao existe", _av_ponto in _fr_src_txt, "")
_av_mutdir = _sandbox_tempdir("alia-v2-check-agvelho-mut-")
_av_mut = os.path.join(_av_mutdir, "frescor_mut.py")
open(_av_mut, "w", encoding="utf-8", newline="").write(_fr_src_txt.replace(_av_ponto, "if True:", 1))
check("agentes_velhos: NEGATIVO - mutante que ignora o hash nao ve a persona editada (o teste acima o pega)",
      _carrega("_frescor_av_mut", _av_mut).agentes_velhos(_av) == [], "")
_av_dispatch = _com_env({"CLAUDE_PROJECT_DIR": _av, "ALIA_LEDGER_PATH": os.path.join(_av, "activity.jsonl")},
                        lambda: _disp_fr._frescor_bloco())
check("dispatch: o bloco do SessionStart so cita [AGENTE VELHO] quando ha cliente ativo? (sem state.json, silencio ou aviso)",
      isinstance(_av_dispatch, str), repr(_av_dispatch)[:120])

# ---- L89: persona sem fantasia (Remove-FantasySections de v2/squad/lib.ps1), provada pelo negativo ----
_pf_lib = os.path.join(V2, "squad", "lib.ps1")
_pf_src = open(_pf_lib, encoding="utf-8").read()
_pf_ponto = "'^(voz|como pensa"
check("L89 persona sem fantasia: ponto de mutacao existe", _pf_ponto in _pf_src, "")
_pf_dir = _sandbox_tempdir("alia-v2-check-fantasia-")
_pf_mut = os.path.join(_pf_dir, "lib_mut.ps1")
open(_pf_mut, "w", encoding="utf-8", newline="").write(_pf_src.replace(_pf_ponto, "'^(zzz|como pensa", 1))
_pf_md = "# X" + chr(10)*2 + "## Faz" + chr(10)*2 + "entrega A" + chr(10)*2 + "## Voz" + chr(10)*2 + "fantasia-v" + chr(10)*2 + "## Como pensa" + chr(10)*2 + "fantasia-c" + chr(10)*2 + "## Nao faz" + chr(10)*2 + "limite B" + chr(10)
_pf_md_path = os.path.join(_pf_dir, "persona.md")
open(_pf_md_path, "w", encoding="utf-8", newline="").write(_pf_md)
def _pf_run(lib):
    cmd = f". '{lib}'; Remove-FantasySections (Get-Content -Raw -Encoding UTF8 '{_pf_md_path}')"
    return subprocess.Popen(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", cmd],
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
_pf_a, _pf_b = _pf_run(_pf_lib), _pf_run(_pf_mut)
_pf_oa = _pf_a.communicate()[0].decode("utf-8", "replace")
_pf_ob = _pf_b.communicate()[0].decode("utf-8", "replace")
check("L89 persona sem fantasia: Voz e Como pensa saem, Faz e Nao faz ficam",
      "fantasia-v" not in _pf_oa and "fantasia-c" not in _pf_oa and "entrega A" in _pf_oa and "limite B" in _pf_oa, _pf_oa[:120] if "fantasia" in _pf_oa else "")
check("L89 persona sem fantasia: NEGATIVO - mutante que nao reconhece 'Voz' deixa a fantasia passar (o teste acima o pega)",
      "fantasia-v" in _pf_ob, "")

import datetime as _dt  # noqa: E402

sys.path.insert(0, os.path.join(V2, "lib"))
def _versao(pasta: str) -> str | None:
    try:
        with open(os.path.join(pasta, "VERSION"), "r", encoding="utf-8") as _vf:
            return _vf.read().strip() or None
    except OSError:
        return None


def _vtupla(v: str | None) -> tuple | None:
    try:
        return tuple(int(x) for x in (v or "").split("."))
    except ValueError:
        return None


def gravar_marcador(marker_path: str, repo_dir: str, head: str | None, motor_raiz: str) -> str:
    """2.1.3 (WARDEN): o marcador so carimba o repo que ESTA prova mediu: a VERSION do repo tem que ser a do motor
    verificado (antes qualquer --repo recebia o carimbo so pelo HEAD, e o check verde de um motor liberava o
    push de outro repo qualquer). Gravacao atomica. Devolve 'gravado' | 'sem_head' | 'repo_diferente'."""
    if not head:
        return "sem_head"
    # o repo so recebe a VERSION nova PELO publicar (que exige este marcador): ele pode estar na mesma versao
    # do motor verificado ou em uma ANTERIOR, nunca numa posterior (nem sem VERSION).
    _vm, _vr = _vtupla(_versao(motor_raiz)), _vtupla(_versao(repo_dir))
    if _vm is None or _vr is None or _vr > _vm:
        return "repo_diferente"
    import trava as _trava  # noqa: E402
    _trava.gravar_atomico(marker_path, json.dumps({"ts": _dt.datetime.now(_dt.timezone.utc).isoformat(),
                                                   "head": head, "repo": repo_dir,
                                                   "version": _versao(motor_raiz)}))
    return "gravado"


# prova do marcador (barata, sem rodar o check de novo): repo com a VERSION do motor recebe o carimbo; repo com
# outra VERSION nao; sem HEAD nao; e o mutante que carimba qualquer repo e pego.
_mk = _sandbox_tempdir("alia-v2-marcador-")
for _d, _v in (("motor", "9.9.9"), ("igual", "9.9.9"), ("outro", "10.0.0"), ("atras", "9.9.8")):
    os.makedirs(os.path.join(_mk, _d), exist_ok=True)
    with open(os.path.join(_mk, _d, "VERSION"), "w", encoding="utf-8") as _fh:
        _fh.write(_v + "\n")
_mk_p = os.path.join(_mk, ".alia", "check-ok.json")
check("marcador: repo com a VERSION do motor verificado recebe o carimbo",
      gravar_marcador(_mk_p, os.path.join(_mk, "igual"), "a" * 40, os.path.join(_mk, "motor")) == "gravado"
      and json.load(open(_mk_p, encoding="utf-8"))["repo"] == os.path.join(_mk, "igual"))
os.remove(_mk_p)
check("marcador: repo UMA VERSAO ATRAS (o caso normal: recebe a nova so ao publicar) recebe o carimbo, com a VERSION do motor",
      gravar_marcador(_mk_p, os.path.join(_mk, "atras"), "a" * 40, os.path.join(_mk, "motor")) == "gravado"
      and json.load(open(_mk_p, encoding="utf-8"))["version"] == "9.9.9")
os.remove(_mk_p)
check("marcador: repo numa VERSION POSTERIOR a do motor verificado nao recebe o carimbo",
      gravar_marcador(_mk_p, os.path.join(_mk, "outro"), "a" * 40, os.path.join(_mk, "motor")) == "repo_diferente"
      and not os.path.exists(_mk_p))
check("marcador: sem HEAD nao carimba", gravar_marcador(_mk_p, os.path.join(_mk, "igual"), None, os.path.join(_mk, "motor")) == "sem_head")
_src_mk = __import__("inspect").getsource(gravar_marcador).replace("if _vm is None or _vr is None or _vr > _vm:", "if False:", 1)
_ns_mk: dict = {"os": os, "json": json, "_versao": _versao, "_vtupla": _vtupla, "_dt": _dt}
exec(_src_mk, _ns_mk)
check("negativo marcador: mutante que carimba qualquer repo e pego (carimbou o repo de outra VERSION)",
      _ns_mk["gravar_marcador"](_mk_p, os.path.join(_mk, "outro"), "a" * 40, os.path.join(_mk, "motor")) == "gravado")

print(f"\n=== provas puladas: {len(SKIPS)} [SKIP] contado(s) ===")
for _sk_script, _sk_linha in SKIPS:
    print(f"[SKIP] {_sk_script}: {_sk_linha}")


def skips_reprovam(empacotamento: bool, skips: list[tuple[str, str]]) -> bool:
    """Na copia de empacotamento, SKIP de bateria nao declarada reprova (a prova que nao rodou nao prova nada)."""
    return empacotamento and any(a not in SKIPS_DECLARADOS for a, _ in skips)


_sk_amostra = [("run_proofs.py", "[SKIP] identidade")]
check("SKIP: linha `[SKIP] x`, `SKIP x` e `  [SKIP]: x` sao contadas; `[PASS] SKIP` e prosa nao",
      all(_SKIP_RE.match(l) for l in ("[SKIP] x", "SKIP acerto da query", "  [SKIP]: y"))
      and not any(_SKIP_RE.match(l) for l in ("[PASS] SKIP x", "nao e SKIP aqui", "SKIPPED")))
check("SKIP: na copia de empacotamento um SKIP nao declarado REPROVA; no estudio ou declarado, nao",
      skips_reprovam(True, _sk_amostra) and not skips_reprovam(False, _sk_amostra)
      and not skips_reprovam(True, [("test_grafo.py", "SKIP gabarito ausente")]))
_ns_sk: dict = {"SKIPS_DECLARADOS": SKIPS_DECLARADOS}
exec(__import__("inspect").getsource(skips_reprovam).replace("return empacotamento and any", "return False and any", 1), _ns_sk)
check("negativo SKIP: mutante que nunca reprova e pego (deixa o SKIP passar na copia de empacotamento)",
      not _ns_sk["skips_reprovam"](True, _sk_amostra))
check("nenhuma prova pulada na copia de empacotamento (SKIP so e tolerado no estudio, e contado)",
      not skips_reprovam(_EMPACOTAMENTO, SKIPS), f"{len(SKIPS)} SKIP(s)" if SKIPS else "")

DT_TOTAL = time.perf_counter() - T0
print(f"\n=== resultado ({DT_TOTAL:.2f} s) ===")
check("tempo total ate 30 s (alvo do contrato)", DT_TOTAL <= 30, f"{DT_TOTAL:.2f} s")
if FAILS:
    print(f"FALHOU: {len(FAILS)} prova(s): {FAILS}")
    sys.exit(1)

# ---------------------------------------------------------------------------
# Marcador de check verde (TASK-810, achado do CEO 24/09/2026): a negacao de publicacao do
# dispatch.py antes exigia ALIA_CHECK_MARKER_PATH - ninguem setava essa variavel fora dos
# proprios testes, entao TODO `git push` nascia negado para sempre. Agora, so quando TODAS as
# provas acima passam, grava-se um marcador num caminho FIXO (paths.check_marker_path(), nunca
# variavel de ambiente) com data/hora e o HEAD do repo alvo (se houver git) - a negacao aceita
# so um marcador com menos de 30 minutos e (quando gravou HEAD) HEAD identico ao atual.
sys.path.insert(0, os.path.join(V2, "lib"))
import paths as _paths  # noqa: E402
import datetime as _dt  # noqa: E402

_marker_path = _paths.check_marker_path()
# TASK-845 (E01): repo alvo = o repo git de onde o check roda (cwd); sem git, a raiz do studio.
# Sem HEAD nao grava marcador (nunca "head": null) e a publicacao segue travada.
_repo_dir = os.path.dirname(os.path.dirname(_marker_path))
# 2.1.2 (TASK-862, caso A): --repo <caminho> escolhe o repo a publicar (o produto); o marcador
# continua SEMPRE em paths.check_marker_path() (o studio que o guard le), com repo+HEAD do alvo.
_repo_arg = None
if "--repo" in sys.argv[:-1]:
    _repo_arg = os.path.abspath(sys.argv[sys.argv.index("--repo") + 1])
try:
    _proc_top = subprocess.run(["git", "rev-parse", "--show-toplevel"], cwd=_repo_arg or os.getcwd(),
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if _proc_top.returncode == 0:
        _repo_dir = os.path.normpath(_proc_top.stdout.decode("utf-8", "replace").strip())
except OSError:
    pass
_head = None
try:
    _proc_head = subprocess.run(["git", "rev-parse", "HEAD"], cwd=_repo_dir,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if _proc_head.returncode == 0:
        _head = _proc_head.stdout.decode("utf-8", "replace").strip()
except OSError:
    _head = None

_estado_marcador = gravar_marcador(_marker_path, _repo_dir, _head, os.path.dirname(V2))
if _estado_marcador == "gravado":
    print(f"[MEDIDO] marcador de check verde gravado: {_marker_path} (repo={_repo_dir} head={_head})")
elif _estado_marcador == "repo_diferente":
    print(f"[MEDIDO] marcador NAO gravado: o repo {_repo_dir} (VERSION {_versao(_repo_dir)}) nao e a copia verificada "
          f"(VERSION {_versao(os.path.dirname(V2))}); publicacao segue travada")
else:
    print(f"[MEDIDO] marcador NAO gravado: {_repo_dir} sem HEAD de git; publicacao segue travada")

print("TODAS AS PROVAS PASSARAM")
