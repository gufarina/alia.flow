"""layout.py - portao de pastas (TASK-870). Uma logica, tres pontos de chamada.

  1. PreToolUse (Write/Edit/MultiEdit/Bash), via hooks/dispatch.py: `violacao_de_caminho` bloqueia SO
     caminho NOVO fora do manifesto (layout-manifesto.json) e diz onde deveria morar. Arquivo que ja
     existe nunca bloqueia. Falha aberta: erro aqui nunca trava o operador (o dispatch registra o
     evento `layout_excecao` no ledger).
  2. Smoke e proof/check.py: `--check` varre a arvore e compara com `<raiz>/studio/layout-baseline.txt`
     (catraca: o legado so encolhe; item novo reprova).
  3. `--sweep` so LISTA. `--freeze` grava a baseline (so cria ou encolhe). Este modulo NUNCA move nem apaga.

Perfis: `estudio` (raiz do estudio), `client` (clients/<id>/), `oficina` (clients/alia-flow-lab/, regras
proprias). Infra (memory/, _backups/, .claude/, node_modules, scratchpad ...) nunca entra. Sem pasta
coringa isenta: so o que o manifesto declara `opacas` (saida gerada) ou Client com codigo-fonte dentro.

Interruptor de emergencia (desliga so o bloqueio): ALIA_LAYOUT_GATE_OFF=1 ou `.claude/layout-gate.off`.
Uso: python layout.py --sweep|--check|--freeze [--perfil estudio|oficina|client] [--root DIR]
So biblioteca padrao.
"""
from __future__ import annotations

import datetime
import json
import os
import re
import sys
import unicodedata

HERE = os.path.dirname(os.path.abspath(__file__))
_M: dict | None = None


def manifesto() -> dict:
    global _M
    if _M is None:
        with open(os.path.join(HERE, "layout-manifesto.json"), "r", encoding="utf-8") as fh:
            _M = json.load(fh)
    return _M


def _n(p: str) -> str:
    p = (p or "").replace("\\", "/")
    m = re.match(r"^/([a-zA-Z])/", p)  # git-bash: /c/<pasta> vira C:/<pasta>
    return (m.group(1).upper() + ":/" + p[3:]) if m else p


def _real(p: str) -> str:
    """realpath do ancestral que existe + o resto (resolve nome 8.3 e maiuscula de drive)."""
    d, resto = os.path.abspath(p), []
    while not os.path.lexists(d):
        pai = os.path.dirname(d)
        if pai == d:
            break
        resto.append(os.path.basename(d))
        d = pai
    try:
        base = os.path.realpath(d)
    except (OSError, ValueError):
        base = d
    return os.path.join(base, *reversed(resto)) if resto else base


def desligado(studio: str) -> bool:
    return os.environ.get("ALIA_LAYOUT_GATE_OFF") == "1" or os.path.exists(os.path.join(studio, ".claude", "layout-gate.off"))


def _slug(nome: str) -> str:
    s = unicodedata.normalize("NFKD", nome).encode("ascii", "ignore").decode("ascii").lower()
    return re.sub(r"-+", "-", re.sub(r"[^a-z0-9._]+", "-", s)).strip("-") or "item"


def _tipo(nome: str) -> str:
    ext = os.path.splitext(nome)[1].lower()
    if ext in (".ps1", ".py", ".sh", ".bat", ".js", ".mjs"):
        return "script"
    if ext in (".md", ".pdf"):
        return "doc"
    if ext in (".html", ".png", ".jpg", ".jpeg", ".webm", ".log", ".svg", ".gif"):
        return "saida"
    if ext in (".json", ".jsonl", ".yaml", ".yml", ".csv", ".txt"):
        return "dado"
    return "outro"


def _isento(perfil: str, rel: list[str], raiz_abs: str) -> bool:
    M = manifesto()
    low = [s.lower() for s in rel]
    if any(s in M["infra_qualquer"] for s in low):
        return True
    if perfil == "client":
        return any(os.path.isfile(os.path.join(raiz_abs, f)) for f in M["client_com_codigo_se_tem"])
    if low[0] in [x.lower() for x in M["infra_topo"]]:
        return True
    return low[0] in [x.lower() for x in M["perfis"][perfil].get("opacas", [])]


def _v(regra: str, rel: list[str], i: int, onde: str, pref: str) -> dict:
    caminho = pref + "/".join(rel[: i + 1])
    return {"regra": regra, "caminho": caminho,
            "msg": (f"layout [{regra}]: '{caminho}' e caminho NOVO fora do manifesto de pastas. Deveria morar em: {onde}. "
                    "Pensar antes de criar (skills/file-organization). Interruptor de emergencia: "
                    "ALIA_LAYOUT_GATE_OFF=1 ou .claude/layout-gate.off.")}


def _segmento(perfil: str, rel: list[str], i: int, e_dir: bool, pref: str = "") -> dict | None:
    M = manifesto()
    pf = M["perfis"][perfil]
    seg = rel[i]
    low = seg.lower()
    dest = M["destinos"]
    if i == 0:
        lista = [x.lower() for x in (pf["raiz_pastas"] if e_dir else pf["raiz_arquivos"])]
        if low not in lista:
            if perfil == "client":
                if low == "_backups":
                    return _v("C6", rel, i, "_backups/<id>-AAAA-MM-DD-motivo/ do estudio (backup nunca mora dentro do Client)", pref)
                return _v("C1", rel, i, "a raiz do Client so tem " + ", ".join(pf["raiz_arquivos"]) + " e as pastas "
                          + ", ".join(pf["raiz_pastas"]) + "; outro material: " + dest["outro"], pref)
            if e_dir:
                return _v("R2", rel, i, "uma pasta de topo existente (" + ", ".join(x for x in pf["raiz_pastas"] if not x.startswith("."))
                          + "); trabalho datado numa subpasta AAAA-MM-DD-tema/ de docs/, dado de Client em clients/<id>/", pref)
            return _v("R1", rel, i, dest[_tipo(seg)], pref)
    if e_dir and re.search(M["coringa"], low):
        return _v("C10" if perfil == "client" else "R11", rel, i, "pasta com nome do ASSUNTO (nada de tmp/misc/novo/final/copy/recovered)", pref)
    if perfil in ("client", "oficina") and i == 1 and rel[0].lower() == "artifacts":
        hoje = datetime.date.today().isoformat()
        if not e_dir:
            return _v("C5", rel, i, f"artifacts/<projeto>-{hoje}/{seg} (artifact solto direto em artifacts/ e vazamento)", pref)
        if not (re.match(M["artifacts_projeto"], seg) or re.match(M["artifacts_task"], seg)) and low not in M["artifacts_reservadas"]:
            return _v("C5", rel, i, f"artifacts/{_slug(seg)}-{hoje}/ (pasta de projeto = slug-AAAA-MM-DD)", pref)
    if not e_dir and perfil != "oficina" and seg in M["fonte_unica"]["nomes"]:
        return _v("R9", rel, i, M["fonte_unica"]["onde"] + seg + " (fonte unica viva; aqui so link)", pref)
    task_dir = e_dir and i == 1 and rel[0].lower() == "artifacts" and re.match(M["artifacts_task"], seg)
    ok = re.match(M["nome_ok"], seg) or task_dir or (not e_dir and (re.match(M["nome_md_ok"], seg) or seg in M["nome_excecoes"]))
    if not ok:
        return _v("R3", rel, i, f"'{_slug(seg)}' (kebab-case ASCII, sem espaco nem acento; .md pode ter maiuscula)", pref)
    return None


def violacao_de_caminho(caminho: str, studio: str) -> dict | None:
    """None = livre (existe, infra, fora do estudio ou dentro do manifesto). Dict = {regra, caminho, msg}."""
    caminho = _n(caminho.strip().strip("'\""))
    if not caminho or not os.path.isabs(caminho) or os.path.lexists(caminho):
        return None
    ap, st = _n(_real(caminho)), _n(_real(studio)).rstrip("/")
    if not (ap.lower() + "/").startswith(st.lower() + "/"):
        return None
    partes = ap[len(st):].strip("/").split("/")
    pref = ""
    if partes[0].lower() == "clients" and len(partes) >= 2:
        raiz = f"{st}/clients/{partes[1]}"
        if not os.path.isdir(raiz) and not re.match(manifesto()["nome_ok"], partes[1]):
            return _v("R3", partes, 1, f"clients/{_slug(partes[1])}/ (id de Client em kebab-case ASCII)", "")
        perfil = "oficina" if partes[1].lower() == "alia-flow-lab" else "client"
        rel, pref = partes[2:], f"clients/{partes[1]}/"
    else:
        perfil, rel, raiz = "estudio", partes, st
    if not rel or _isento(perfil, rel, raiz):
        return None
    novo = 0
    while novo < len(rel) and os.path.lexists(os.path.join(raiz, *rel[: novo + 1])):
        novo += 1
    for i in range(novo, len(rel)):
        v = _segmento(perfil, rel, i, i < len(rel) - 1, pref)
        if v:
            return v
    return None


# ---------------------------------------------------------------------------
# Varredura (so lista)
# ---------------------------------------------------------------------------

def _andar(raiz: str, perfil: str, base: str, saida: list[str], pular_clients: bool = False) -> None:
    pilha: list[tuple[str, list[str]]] = [(raiz, [])]
    while pilha:
        d, rel = pilha.pop()
        try:
            entradas = sorted(os.scandir(d), key=lambda e: e.name)
        except OSError:
            continue
        for e in entradas:
            r = rel + [e.name]
            e_dir = e.is_dir(follow_symlinks=False)
            if _isento(perfil, r, raiz) or (pular_clients and len(r) == 1 and e.name.lower() == "clients"):
                continue
            v = _segmento(perfil, r, len(r) - 1, e_dir, base)
            if v:
                saida.append(f"{v['regra']} {v['caminho']}")  # violou: lista e nao desce (o legado entra como 1 item)
            elif e_dir:
                pilha.append((e.path, r))


def sweep(raiz: str, perfil: str = "estudio") -> list[str]:
    raiz = os.path.abspath(raiz)
    out: list[str] = []
    _andar(raiz, perfil, "", out, pular_clients=(perfil == "estudio"))
    cdir = os.path.join(raiz, "clients")
    if perfil == "estudio" and os.path.isdir(cdir):
        for c in sorted(os.scandir(cdir), key=lambda x: x.name):
            if not c.is_dir() or c.name.lower() == "alia-flow-lab":  # a oficina tem baseline propria
                continue
            if not re.match(manifesto()["nome_ok"], c.name):
                out.append(f"R3 clients/{c.name}")
                continue
            _andar(c.path, "client", f"clients/{c.name}/", out)
    return sorted(set(out))


def baseline_path(raiz: str) -> str:
    return os.path.join(os.path.abspath(raiz), "studio", "layout-baseline.txt")


def _chaves(linhas: list[str]) -> dict[str, str]:
    return {l.split(" ", 1)[1]: l.split(" ", 1)[0] for l in linhas if " " in l}


def ler_baseline(raiz: str) -> dict[str, str] | None:
    try:
        with open(baseline_path(raiz), "r", encoding="utf-8") as fh:
            return _chaves([l.rstrip("\n") for l in fh if l.strip() and not l.startswith("#")])
    except OSError:
        return None


def comparar(raiz: str, perfil: str) -> dict:
    base = ler_baseline(raiz)
    agora = _chaves(sweep(raiz, perfil))
    if base is None:
        return {"ok": False, "sem_baseline": True, "agora": len(agora), "novos": []}
    novos = sorted(k for k in agora if k not in base)
    return {"ok": not novos, "sem_baseline": False, "baseline": len(base), "agora": len(agora), "novos": novos,
            "encolheu": len([k for k in base if k not in agora])}


def congelar(raiz: str, perfil: str) -> tuple[bool, str]:
    linhas = sweep(raiz, perfil)
    base = ler_baseline(raiz)
    if base is not None:
        novos = [l for l in linhas if l.split(" ", 1)[1] not in base]
        if novos:
            return False, f"recusado: a baseline so encolhe; {len(novos)} item(ns) novo(s): " + "; ".join(novos[:5])
    p = baseline_path(raiz)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(f"# layout-baseline perfil={perfil}: legado tolerado, SO ENCOLHE (python v2/lib/layout.py --freeze). Formato: REGRA caminho\n")
        fh.write("\n".join(linhas) + ("\n" if linhas else ""))
    return True, f"baseline gravada: {len(linhas)} item(ns) em {p}"


def main(argv: list[str]) -> int:
    def arg(nome: str, padrao: str) -> str:
        return argv[argv.index(nome) + 1] if nome in argv[:-1] else padrao
    perfil = arg("--perfil", "estudio")
    raiz = arg("--root", "")
    if not raiz:
        sys.path.insert(0, HERE)
        import paths
        raiz = paths.studio_root()
    if perfil not in ("estudio", "oficina", "client"):
        print("perfil invalido")
        return 2
    if "--freeze" in argv:
        ok, msg = congelar(raiz, perfil)
        print(msg)
        return 0 if ok else 1
    if "--check" in argv:
        r = comparar(raiz, perfil)
        if r["sem_baseline"]:
            print(f"layout --check [{perfil}]: sem baseline em {baseline_path(raiz)} ({r['agora']} item(ns) no legado). Rode --freeze.")
            return 2
        print(f"layout --check [{perfil}]: baseline {r['baseline']}, agora {r['agora']}, encolheu {r['encolheu']}, novos {len(r['novos'])}")
        for k in r["novos"][:20]:
            print("  NOVO fora do manifesto: " + k)
        return 0 if r["ok"] else 1
    linhas = sweep(raiz, perfil)  # --sweep (padrao): so lista
    print("\n".join(linhas))
    print(f"# {len(linhas)} item(ns) fora do manifesto (nada foi movido nem apagado)", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
