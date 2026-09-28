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

print("\n=== bateria: flow/slice.py (TASK-812 item B, fatiar tarefa grande) ===")
rc, out, dt = run_script(os.path.join(V2, "flow", "test_slice.py"))
check("test_slice.py sai verde", rc == 0, f"{dt*1000:.0f} ms")
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

print("\n=== bateria: bin/gate.py (TASK-838, ponteiro verificavel em funciona/goal-backward) ===")
rc, out, dt = run_script(os.path.join(HERE, "test_gate.py"))
check("test_gate.py sai verde", rc == 0, f"{dt*1000:.0f} ms")
if rc != 0:
    print(out[-3000:])

print("\n=== bateria: bin/migrate.py (D1, achado do Gate do NEXUS: apply/undo sem prova automatica) ===")
rc, out, dt = run_script(os.path.join(HERE, "test_migrate.py"))
check("test_migrate.py sai verde", rc == 0, f"{dt*1000:.0f} ms")
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
      _saida.get("squads_dir", "") == os.path.join(_studio_fake, ".claude", "squads"), str(_saida))

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

_leak_c_fake = identity_guard.find_identity_leak("o caminho e C:\\Users\\fulano\\projeto", start=_id_fixture_dir)
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


_ID_SCAN_EXT = (".py", ".ps1", ".md", ".json", ".yaml", ".yml", ".txt", ".bat")
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
      _div_sem_data == {"valida": None, "vencida": None}, str(_div_sem_data))

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
check("(g) SessionStart startup com tudo OK devolve {} (sem Client velho)", _out_h == {}, str(_out_h))

# (g) o ramo resume tambem avisa (sessao retomada e a mesma porta de entrada)
_proc_g_resume = subprocess.run([sys.executable, os.path.join(V2, "hooks", "dispatch.py")],
                                 input=json.dumps({"hook_event_name": "SessionStart", "source": "resume",
                                                   "session_id": "s-fresc-g2"}).encode("utf-8"),
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=_env_g)
_ctx_g_resume = json.loads(_proc_g_resume.stdout.decode("utf-8") or "{}").get("hookSpecificOutput", {}).get("additionalContext", "")
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
_b_ok = _brief_fr(_fr_h_ok, "acme")
check("(k) brief de Client OK nao leva o campo conhecimento",
      _b_ok.get("ok") is True and "conhecimento" not in _b_ok, str(_b_ok)[:200])
_b_quebrado = _brief_fr(_fr_root(), "fantasma")
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
_repo_dir = os.path.dirname(os.path.dirname(_marker_path))
_head = None
try:
    _proc_head = subprocess.run(["git", "rev-parse", "HEAD"], cwd=_repo_dir,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if _proc_head.returncode == 0:
        _head = _proc_head.stdout.decode("utf-8", "replace").strip()
except OSError:
    _head = None
os.makedirs(os.path.dirname(_marker_path), exist_ok=True)
with open(_marker_path, "w", encoding="utf-8") as _fh:
    json.dump({"ts": _dt.datetime.now(_dt.timezone.utc).isoformat(), "head": _head}, _fh)
print(f"[MEDIDO] marcador de check verde gravado: {_marker_path} (head={_head})")

print("TODAS AS PROVAS PASSARAM")
