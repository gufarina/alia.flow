# -*- coding: utf-8 -*-
"""Prova do portao de pastas (TASK-870): v2/lib/layout.py + o gancho no dispatch.py.

Tudo em sandbox de tempdir (nunca toca o estudio real). Cada regra tem um MUTANTE: a mesma pergunta com a
regra desligada tem de dar o resultado contrario, senao o teste nao prova nada (prova pelo negativo).
Cobre tambem as pendencias 2.1.4 do grafo_gate (/scratchpad/ com barra, linha JSON nao-dict).
Uso: python test_layout.py  (sai 1 se algo falhar)
"""
from __future__ import annotations

import copy
import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
V2 = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(V2, "hooks"))
sys.path.insert(0, os.path.join(V2, "lib"))
import layout  # noqa: E402

FAILS: list[str] = []
os.environ.pop("ALIA_LAYOUT_GATE_OFF", None)  # o check.py liga este interruptor para as provas LEGADAS; aqui o portao e o alvo


def check(nome: str, cond: bool, detalhe: str = "") -> None:
    print(f"[{'PASS' if cond else 'FAIL'}] {nome} {detalhe}")
    if not cond:
        FAILS.append(nome)


def touch(p: str, txt: str = "x\n") -> None:
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(txt)


ST = tempfile.mkdtemp(prefix="alia-layout-")
ST = os.path.realpath(ST)
try:
    for f in ("state.json", "README.md", "clients/zeta/client.md", "clients/zeta/artifacts/proj-2026-10-01/a.md",
              "clients/alia-flow-lab/README.md", "clients/codigo/package.json", "docs/existente-com-legado.md",
              "legado-solto.txt", "Nome Velho.txt"):
        touch(os.path.join(ST, f))

    def v(rel: str, st: str = ST):
        return layout.violacao_de_caminho(os.path.join(st, rel), st)

    def regra(rel: str) -> str:
        r = v(rel)
        return r["regra"] if r else ""

    print("=== estudio: caminho NOVO ===")
    check("R1: arquivo solto novo na raiz bloqueia e diz onde mora", regra("teste solto.txt") == "R1" and "studio/" in v("teste solto.txt")["msg"])
    check("R1: .ps1 novo na raiz manda para scripts/", "scripts/" in (v("novo-script.ps1") or {}).get("msg", ""))
    check("R2: pasta de topo nova fora do manifesto bloqueia", regra("pasta-inventada/a.md") == "R2")
    check("R11: pasta coringa (tmp/misc/novo) bloqueia mesmo dentro de pasta permitida", regra("docs/misc/a.md") == "R11" and regra("docs/tmp-x/a.md") == "R11")
    check("R3: espaco e acento em nome novo bloqueiam", regra("docs/Relatório final.txt") == "R3" and regra("docs/a b.txt") == "R3")
    check("R3: .md pode ter maiuscula (PROXIMA-SESSAO.md); outra extensao nao", regra("docs/PROXIMA-SESSAO.md") == "" and regra("docs/Foto.PNG") == "R3")
    check("R9: fonte unica (CLAIMS.md) fora da oficina bloqueia", regra("docs/CLAIMS.md") == "R9")
    check("caminho que cabe no manifesto passa", regra("docs/2026-10-01-tema/nota.md") == "" and regra("studio/x.json") == "" and regra("out/r.html") == "")

    print("=== existente, infra e fora do estudio nunca bloqueiam ===")
    check("arquivo EXISTENTE fora do manifesto nunca bloqueia (legado-solto.txt, Nome Velho.txt)", regra("legado-solto.txt") == "" and regra("Nome Velho.txt") == "")
    check("infra nao bloqueia (memory/, _backups/, .claude/, node_modules, scratchpad)",
          all(regra(p) == "" for p in ("memory/Nota Nova.md", "_backups/x y/z.zip", ".claude/qualquer coisa.json",
                                       "docs/node_modules/Pacote X/i.js", "docs/scratchpad/Rascunho Meu.txt")))
    check("caminho fora do estudio nao e da conta do portao", layout.violacao_de_caminho(os.path.join(tempfile.gettempdir(), "fora aqui.txt"), ST) is None)

    print("=== Client e oficina (regras proprias) ===")
    check("C1: arquivo solto novo na raiz do Client bloqueia", regra("clients/zeta/notas.md") == "C1")
    check("C1: client.md/loops.yaml na raiz passam", regra("clients/zeta/loops.yaml") == "")
    check("C5: artifact solto direto em artifacts/ bloqueia", regra("clients/zeta/artifacts/solto.md") == "C5")
    check("C5: pasta de projeto sem data bloqueia e sugere slug-AAAA-MM-DD", regra("clients/zeta/artifacts/landing/a.md") == "C5" and "landing-20" in v("clients/zeta/artifacts/landing/a.md")["msg"])
    check("C5: slug-AAAA-MM-DD, coordination e TASK-N (entrega delegada) passam", regra("clients/zeta/artifacts/lp-2026-10-02/a.md") == "" and regra("clients/zeta/artifacts/coordination/a.json") == "" and regra("clients/zeta/artifacts/TASK-9/e.md") == "")
    check("C6: _backups dentro do Client bloqueia (vai para _backups/ do estudio)", regra("clients/zeta/_backups/x.zip") == "C6")
    check("C10: pasta misc/tmp dentro do Client bloqueia", regra("clients/zeta/docs/misc/a.md") == "C10")
    check("Client com codigo-fonte dentro (package.json) e opaco", regra("clients/codigo/src/Main.TSX") == "")
    check("oficina tem regras proprias: pasta de topo inventada bloqueia, artifacts e docs passam",
          regra("clients/alia-flow-lab/_dev2/a.md") == "R2" and regra("clients/alia-flow-lab/docs/CLAIMS.md") == "" and regra("clients/alia-flow-lab/release/Qualquer Coisa.X") == "")
    check("id de Client novo fora de kebab-case bloqueia", regra("clients/NovoCliente/client.md") == "R3")

    print("=== negativo: mutante (regra desligada) NAO bloqueia = o teste distingue ===")
    orig = layout._M
    mut = copy.deepcopy(layout.manifesto())
    mut["perfis"]["estudio"]["raiz_arquivos"].append("teste solto.txt")
    mut["perfis"]["estudio"]["raiz_pastas"].append("pasta-inventada")
    mut["nome_ok"] = "^.*$"
    mut["coringa"] = "^$nunca"
    mut["perfis"]["client"]["raiz_arquivos"].append("notas.md")
    layout._M = mut
    check("mutante: R1 desligada deixa passar", regra("teste solto.txt") == "")
    check("mutante: R2 desligada deixa passar", regra("pasta-inventada/a.md") == "")
    check("mutante: R3 desligada deixa passar", regra("docs/a b.txt") == "")
    check("mutante: R11 desligada deixa passar", regra("docs/misc/a.md") == "")
    check("mutante: C1 desligada deixa passar", regra("clients/zeta/notas.md") == "")
    layout._M = orig
    check("restaurado o manifesto real, volta a bloquear", regra("teste solto.txt") == "R1")

    print("=== gancho no dispatch (PreToolUse), processo real ===")
    DISP = os.path.join(V2, "hooks", "dispatch.py")

    def hook(tool: str, ti: dict, extra_env: dict | None = None, cwd: str = ST) -> dict:
        env = {k: x for k, x in os.environ.items() if not k.startswith(("ALIA_", "CLAUDE_"))}
        env.update({"CLAUDE_PROJECT_DIR": ST, "ALIA_LEDGER_PATH": os.path.join(ST, "ledger.jsonl"),
                    "ALIA_DELEGATION_WALL_OFF": "1", "ALIA_SPINE_OFF": "1"})
        env.update(extra_env or {})
        ev = {"hook_event_name": "PreToolUse", "tool_name": tool, "tool_input": ti, "cwd": cwd, "session_id": "t"}
        p = subprocess.run([sys.executable, DISP], input=json.dumps(ev).encode("utf-8"), stdout=subprocess.PIPE,
                           stderr=subprocess.PIPE, env=env)
        try:
            return json.loads(p.stdout.decode("utf-8", "replace") or "{}")
        except json.JSONDecodeError:
            return {"_erro": p.stdout.decode("utf-8", "replace") + p.stderr.decode("utf-8", "replace")}

    def negado(r: dict) -> bool:
        return (r.get("hookSpecificOutput") or {}).get("permissionDecision") == "deny"

    novo = os.path.join(ST, "teste solto.txt")
    r = hook("Write", {"file_path": novo, "content": "x"})
    check("Write em caminho novo fora do manifesto: DENY com o destino", negado(r) and "layout [R1]" in json.dumps(r), str(r)[:160])
    check("Edit/MultiEdit idem", negado(hook("MultiEdit", {"file_path": novo, "edits": []})) and negado(hook("Edit", {"file_path": novo, "new_string": "x"})))
    check("Write em arquivo EXISTENTE fora do manifesto: passa", not negado(hook("Write", {"file_path": os.path.join(ST, "legado-solto.txt"), "content": "x"})))
    check("Write dentro do manifesto: passa", not negado(hook("Write", {"file_path": os.path.join(ST, "docs", "ok.md"), "content": "x"})))
    check("Bash com redirecionamento para caminho novo: DENY", negado(hook("Bash", {"command": f'echo oi > "{novo}"'})))
    check("Bash para caminho valido: passa", not negado(hook("Bash", {"command": f'echo oi > "{os.path.join(ST, "docs", "ok.txt")}"'})))
    check("Bash que so le (cat) nao bloqueia", not negado(hook("Bash", {"command": f'cat "{novo}"'})))
    check("interruptor ALIA_LAYOUT_GATE_OFF=1 desliga so o bloqueio", not negado(hook("Write", {"file_path": novo, "content": "x"}, {"ALIA_LAYOUT_GATE_OFF": "1"})))
    touch(os.path.join(ST, ".claude", "layout-gate.off"), "1")
    check("arquivo .claude/layout-gate.off tambem desliga", not negado(hook("Write", {"file_path": novo, "content": "x"})))
    os.remove(os.path.join(ST, ".claude", "layout-gate.off"))

    print("=== falha aberta registrada ===")
    import dispatch  # noqa: E402
    os.environ["CLAUDE_PROJECT_DIR"] = ST
    os.environ["ALIA_LEDGER_PATH"] = os.path.join(ST, "ledger2.jsonl")
    orig_fn = layout.violacao_de_caminho

    def explode(*a, **k):
        raise RuntimeError("manifesto corrompido de proposito")
    layout.violacao_de_caminho = explode
    saida = dispatch._layout_deny({"tool_name": "Write", "tool_input": {"file_path": novo}, "cwd": ST})
    layout.violacao_de_caminho = orig_fn
    led = open(os.path.join(ST, "ledger2.jsonl"), encoding="utf-8").read() if os.path.exists(os.path.join(ST, "ledger2.jsonl")) else ""
    check("erro no portao: libera (falha aberta) e grava layout_excecao no ledger", saida is None and "layout_excecao" in led)

    print("=== catraca: baseline so encolhe; sweep so lista ===")
    OF = os.path.join(ST, "clients", "alia-flow-lab")
    touch(os.path.join(OF, "legado-solto.txt"))
    antes = sorted(os.path.relpath(os.path.join(d, f), OF) for d, _, fs in os.walk(OF) for f in fs)
    linhas = layout.sweep(OF, "oficina")
    depois = sorted(os.path.relpath(os.path.join(d, f), OF) for d, _, fs in os.walk(OF) for f in fs)
    check("sweep lista o legado e NAO move nem apaga nada", any("legado-solto.txt" in l for l in linhas) and antes == depois)
    check("check sem baseline: rc 2 (nao se aplica)", layout.main(["--check", "--perfil", "oficina", "--root", OF]) == 2)
    check("freeze cria a baseline", layout.main(["--freeze", "--perfil", "oficina", "--root", OF]) == 0)
    check("check com a baseline: verde", layout.main(["--check", "--perfil", "oficina", "--root", OF]) == 0)
    touch(os.path.join(OF, "novo-vazamento.txt"))
    check("item NOVO no legado: check reprova (catraca cresceu)", layout.main(["--check", "--perfil", "oficina", "--root", OF]) == 1)
    check("freeze RECUSA crescer a baseline", layout.main(["--freeze", "--perfil", "oficina", "--root", OF]) == 1)
    os.remove(os.path.join(OF, "novo-vazamento.txt"))
    os.remove(os.path.join(OF, "legado-solto.txt"))
    check("legado removido: check verde e freeze ENCOLHE a baseline",
          layout.main(["--check", "--perfil", "oficina", "--root", OF]) == 0 and layout.main(["--freeze", "--perfil", "oficina", "--root", OF]) == 0
          and "legado-solto" not in open(layout.baseline_path(OF), encoding="utf-8").read())
    sw_estudio = layout.sweep(ST, "estudio")
    check("sweep do estudio cobre o legado do Client e nao entra na oficina", any(l.endswith("legado-solto.txt") for l in sw_estudio)
          and not any("alia-flow-lab" in l for l in sw_estudio))

    print("=== pendencias 2.1.4: grafo_gate ===")
    import grafo_gate  # noqa: E402
    check("/scratchpad/ com barra: pasta scratchpad e infra, 'scratchpad-app' (codigo) nao",
          grafo_gate._infra("/x/proj/scratchpad/a.md") and not grafo_gate._infra("/x/proj/scratchpad-app/src/a.py"))
    tr = os.path.join(ST, "transcript.jsonl")
    with open(tr, "w", encoding="utf-8") as fh:
        fh.write('[{"type": "tool_use"}]\n{"type":"tool_use"}\n')  # 1a linha: JSON valido que e lista, nao objeto
    try:
        ok = grafo_gate._lido_no_transcript(tr, os.path.join(ST, "GRAPH_REPORT.md"), "clients/zeta") is False
    except Exception as exc:  # noqa: BLE001
        ok = False
        print("  excecao:", exc)
    check("transcript com linha JSON nao-dict (lista, numero, string) nao quebra a leitura", ok)
finally:
    shutil.rmtree(ST, ignore_errors=True)

if FAILS:
    print(f"FALHOU: {len(FAILS)} prova(s): {FAILS}")
    sys.exit(1)
print("test_layout: TODAS AS PROVAS PASSARAM")
