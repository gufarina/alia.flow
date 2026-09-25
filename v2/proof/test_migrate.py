# -*- coding: utf-8 -*-
"""Prova de v2/bin/migrate.py (D1, achado do Gate do NEXUS: nao havia prova automatica desta
classe - foi exatamente isso que deixou o estudio preso no CHANGELOG 1.83.0). apply numa copia
TEMPORARIA leva VERSION, CHANGELOG.md e o matcher do PreToolUse com PowerShell para o alvo; undo
devolve os hashes ORIGINAIS dos tres (nunca so apaga ou reescreve por cima). Nunca toca a fonte
real (v2/) nem qualquer instancia de verdade - so fixture sintetica em pasta temporaria.

Prova pelo negativo na PROPRIA prova (secao final): uma copia de migrate.py com o bloco que
copia CHANGELOG.md removido tem que fazer o check de copia FALHAR - senao esta prova nao tem
dente nenhum contra a mesma regressao que ela existe para pegar.

Uso: python test_migrate.py
"""
from __future__ import annotations

import atexit
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
V2 = os.path.dirname(HERE)
MIGRATE_PY = os.path.join(V2, "bin", "migrate.py")


def _sandbox_tempdir(prefix: str) -> str:
    """Sandbox de teste SEMPRE fora de v2/ (pasta temporaria do sistema), nunca dentro do
    motor. Removida no fim do processo mesmo se o teste falhar no meio (atexit)."""
    d = tempfile.mkdtemp(prefix=prefix)
    atexit.register(shutil.rmtree, d, ignore_errors=True)
    return d


FAILS: list[str] = []


def check(name: str, cond: bool, detail: str = "") -> None:
    status = "PASS" if cond else "FAIL"
    print(f"[{status}] {name} {detail}")
    if not cond:
        FAILS.append(name)


def sha256(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        h.update(fh.read())
    return h.hexdigest()


def _montar_fonte(raiz: str) -> str:
    """Monta uma fonte MINIMA e SINTETICA (<raiz>/VERSION, <raiz>/CHANGELOG.md,
    <raiz>/v2/AGENTS.md) - nunca a fonte real do motor, para a prova nao depender do conteudo
    mutavel de v2/ de verdade. Devolve o caminho de <raiz>/v2 (o --source do CLI)."""
    source = os.path.join(raiz, "v2")
    os.makedirs(source, exist_ok=True)
    with open(os.path.join(raiz, "VERSION"), "w", encoding="utf-8") as fh:
        fh.write("9.9.9-teste-migrate\n")
    with open(os.path.join(raiz, "CHANGELOG.md"), "w", encoding="utf-8") as fh:
        fh.write("# Changelog fixture\n\n## [9.9.9-teste-migrate] - 2026-01-01\n- entrada\n")
    with open(os.path.join(source, "AGENTS.md"), "w", encoding="utf-8") as fh:
        fh.write("kernel v2 fixture\n")
    return source


def _run(migrate_script: str, args: list[str]) -> tuple[int, str]:
    proc = subprocess.run([sys.executable, migrate_script, *args],
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    out = proc.stdout.decode("utf-8", "replace") + proc.stderr.decode("utf-8", "replace")
    return proc.returncode, out


# ---------------------------------------------------------------------------
print("=== migrate.py apply: VERSION, CHANGELOG.md e o matcher PowerShell chegam no alvo ===")
_raiz1 = _sandbox_tempdir("alia-v2-test-migrate-apply-")
_fonte1 = _montar_fonte(os.path.join(_raiz1, "fonte"))
_alvo1 = os.path.join(_raiz1, "alvo")

rc, out = _run(MIGRATE_PY, ["apply", "--source", _fonte1, "--target", _alvo1])
check("apply sai 0", rc == 0, out[-500:] if rc != 0 else "")

_version_alvo = os.path.join(_alvo1, "VERSION")
_changelog_alvo = os.path.join(_alvo1, "CHANGELOG.md")
_settings_alvo = os.path.join(_alvo1, ".claude", "settings.json")

check("apply copia VERSION para a raiz do alvo", os.path.isfile(_version_alvo))
if os.path.isfile(_version_alvo):
    check("VERSION do alvo bate hash com a fonte",
          sha256(_version_alvo) == sha256(os.path.join(os.path.dirname(_fonte1), "VERSION")))

check("apply copia CHANGELOG.md para a raiz do alvo", os.path.isfile(_changelog_alvo))
if os.path.isfile(_changelog_alvo):
    check("CHANGELOG.md do alvo bate hash com a fonte",
          sha256(_changelog_alvo) == sha256(os.path.join(os.path.dirname(_fonte1), "CHANGELOG.md")))

check(".claude/settings.json gravado no alvo", os.path.isfile(_settings_alvo))
if os.path.isfile(_settings_alvo):
    with open(_settings_alvo, "r", encoding="utf-8") as fh:
        _settings = json.load(fh)
    _matcher_pre = _settings.get("hooks", {}).get("PreToolUse", [{}])[0].get("matcher", "")
    check("matcher do PreToolUse do apply inclui PowerShell",
          "PowerShell" in _matcher_pre.split("|"), _matcher_pre)

# ---------------------------------------------------------------------------
print("\n=== migrate.py undo: devolve os hashes ORIGINAIS de VERSION, CHANGELOG.md e AGENTS.md ===")
# alvo com dado PREVIO de verdade (sobrescrito pelo apply), para o undo ter o que restaurar -
# nunca so remover um arquivo criado do zero.
_raiz2 = _sandbox_tempdir("alia-v2-test-migrate-undo-")
_fonte2 = _montar_fonte(os.path.join(_raiz2, "fonte"))
_alvo2 = os.path.join(_raiz2, "alvo")
os.makedirs(_alvo2, exist_ok=True)
with open(os.path.join(_alvo2, "VERSION"), "w", encoding="utf-8") as fh:
    fh.write("0.0.1-original\n")
with open(os.path.join(_alvo2, "CHANGELOG.md"), "w", encoding="utf-8") as fh:
    fh.write("# Changelog original\n")
with open(os.path.join(_alvo2, "AGENTS.md"), "w", encoding="utf-8") as fh:
    fh.write("AGENTS original\n")
_hash_version_pre = sha256(os.path.join(_alvo2, "VERSION"))
_hash_changelog_pre = sha256(os.path.join(_alvo2, "CHANGELOG.md"))
_hash_agents_pre = sha256(os.path.join(_alvo2, "AGENTS.md"))

rc2, out2 = _run(MIGRATE_PY, ["apply", "--source", _fonte2, "--target", _alvo2])
check("apply (sobre alvo com dado previo) sai 0", rc2 == 0, out2[-500:] if rc2 != 0 else "")
check("apply sobrescreveu VERSION (hash mudou)",
      sha256(os.path.join(_alvo2, "VERSION")) != _hash_version_pre)
check("apply sobrescreveu CHANGELOG.md (hash mudou)",
      sha256(os.path.join(_alvo2, "CHANGELOG.md")) != _hash_changelog_pre)
check("apply sobrescreveu AGENTS.md (hash mudou)",
      sha256(os.path.join(_alvo2, "AGENTS.md")) != _hash_agents_pre)

rc3, out3 = _run(MIGRATE_PY, ["undo", "--target", _alvo2])
check("undo sai 0", rc3 == 0, out3[-500:] if rc3 != 0 else "")
check("undo devolve o hash ORIGINAL de VERSION",
      sha256(os.path.join(_alvo2, "VERSION")) == _hash_version_pre)
check("undo devolve o hash ORIGINAL de CHANGELOG.md",
      sha256(os.path.join(_alvo2, "CHANGELOG.md")) == _hash_changelog_pre)
check("undo devolve o hash ORIGINAL de AGENTS.md",
      sha256(os.path.join(_alvo2, "AGENTS.md")) == _hash_agents_pre)

# ---------------------------------------------------------------------------
print("\n=== prova pelo negativo: tirar CHANGELOG.md da lista de copia FAZ o check acima FALHAR ===")
# copia o FONTE de migrate.py para um arquivo temporario e apaga so o bloco que copia
# CHANGELOG.md - nunca toca o migrate.py real. Se o bloco sumir por regressao futura, o mesmo
# check usado acima tem que acusar a ausencia.
with open(MIGRATE_PY, "r", encoding="utf-8") as fh:
    _fonte_migrate = fh.read()
_inicio = _fonte_migrate.index("    changelog_src = os.path.join")
_fim = _fonte_migrate.index("\n\n", _inicio) + 1
_bloco_changelog = _fonte_migrate[_inicio:_fim]
check("achou o bloco de copia do CHANGELOG.md no fonte de migrate.py (pre-condicao da prova negativa)",
      "CHANGELOG.md" in _bloco_changelog, _bloco_changelog[:80])
_migrate_quebrado_txt = _fonte_migrate.replace(_bloco_changelog, "")

_raiz3 = _sandbox_tempdir("alia-v2-test-migrate-negativo-")
_migrate_quebrado = os.path.join(_raiz3, "migrate_sem_changelog.py")
with open(_migrate_quebrado, "w", encoding="utf-8") as fh:
    fh.write(_migrate_quebrado_txt)

_fonte3 = _montar_fonte(os.path.join(_raiz3, "fonte"))
_alvo3 = os.path.join(_raiz3, "alvo")
rc4, out4 = _run(_migrate_quebrado, ["apply", "--source", _fonte3, "--target", _alvo3])
check("apply da copia quebrada (sem bloco de CHANGELOG) ainda sai 0 (nao trava, so nao copia)",
      rc4 == 0, out4[-300:])
check("prova negativa: SEM o bloco de copia, CHANGELOG.md NAO chega no alvo (o check positivo cairia em FAIL)",
      not os.path.isfile(os.path.join(_alvo3, "CHANGELOG.md")))

print("\n=== restaurado: migrate.py REAL (nunca tocado) continua copiando CHANGELOG.md ===")
_alvo4 = os.path.join(_raiz3, "alvo-restaurado")
rc5, out5 = _run(MIGRATE_PY, ["apply", "--source", _fonte3, "--target", _alvo4])
check("apply do migrate.py real sai 0", rc5 == 0, out5[-300:] if rc5 != 0 else "")
check("apply do migrate.py real (restaurado) volta a copiar CHANGELOG.md",
      os.path.isfile(os.path.join(_alvo4, "CHANGELOG.md")))

print("\n=== resultado ===")
if FAILS:
    print(f"FALHOU: {len(FAILS)} prova(s): {FAILS}")
    sys.exit(1)
print("TODAS AS PROVAS PASSARAM")
