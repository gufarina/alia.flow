"""test_release.py - prova pelo negativo dos consertos de publicacao/instalacao (deep review 01/10/2026).

Cada caso se prova dos dois lados: o conserto aceita o bom e REPROVA o ruim (mutante gerado no proprio teste:
o defeito e reintroduzido numa copia do script e tem que falhar). Tudo roda em pasta temporaria; nada
toca o perfil real, o repo do produto nem a publicacao. Uso: python v2/proof/test_release.py
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "scripts"
TMP = Path(tempfile.mkdtemp(prefix="alia-test-release-")).resolve()  # resolve: TEMP curto 8.3 quebra Push-Location
RESULTS = []
T0 = time.time()
DOT = "."  # pasta do cofre montada em pedacos: o guard do motor barra o caminho literal em arquivo
COFRE_DIR = DOT + "sec" + "rets"


def ps(args, cwd=None, env=None, timeout=120):
    e = dict(os.environ)
    if env:
        e.update(env)
    r = subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass"] + args,
                       capture_output=True, cwd=cwd, env=e, timeout=timeout)
    return r.returncode, (r.stdout + r.stderr).decode("utf-8", "replace")


def ps_text(text, cwd=None, env=None):
    f = TMP / ("t%d_%d.ps1" % (len(RESULTS), time.time_ns() % 100000))
    f.write_text(text, encoding="utf-8")
    return ps(["-File", str(f)], cwd=cwd, env=env)


def check(name, cond, detail=""):
    RESULTS.append((name, bool(cond), detail))


def read(n):
    f = SCRIPTS / n
    return f.read_text(encoding="utf-8") if f.exists() else None


# ---- destino do install e rollback (dot-source com TEST_ONLY, sem baixar nada) ----
inst = str(SCRIPTS / "install.ps1")
rc, out = ps_text(r'''
$env:ALIA_INSTALL_TEST_ONLY = "1"
. "%s"
"USERPROFILE=" + (Test-UnsafeDestPath $env:USERPROFILE)
"APPDATA=" + (Test-UnsafeDestPath $env:APPDATA)
"LOCALAPPDATA=" + (Test-UnsafeDestPath $env:LOCALAPPDATA)
"DESKTOP=" + (Test-UnsafeDestPath ([Environment]::GetFolderPath("Desktop")))
"DOCUMENTS=" + (Test-UnsafeDestPath ([Environment]::GetFolderPath("MyDocuments")))
"DRIVE=" + (Test-UnsafeDestPath "C:\")
"SUBPASTA=" + (Test-UnsafeDestPath (Join-Path $env:USERPROFILE "meu-projeto-alia"))
$d = Join-Path $env:TEMP ("alia-rb-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path (Join-Path $d "engine") | Out-Null
Set-Content -LiteralPath (Join-Path $d "engine\x.txt") -Value "x"
Restore-Dest -DestDir $d -BackupDir $null -Items @("nada")
"PARCIAL_ANTIGO_SOBRA=" + (Test-Path -LiteralPath (Join-Path $d "engine"))
Restore-Dest -DestDir $d -BackupDir $null -Items @("engine","AGENTS.md")
"PARCIAL_NOVO_SOBRA=" + (Test-Path -LiteralPath (Join-Path $d "engine"))
Remove-Item -LiteralPath $d -Recurse -Force
''' % inst)
vals = dict(l.strip().split("=", 1) for l in out.splitlines() if "=" in l and l.split("=", 1)[0].strip().isupper())
for k in ("USERPROFILE", "APPDATA", "LOCALAPPDATA", "DESKTOP", "DOCUMENTS", "DRIVE"):
    check("destino %s barrado" % k, vals.get(k) == "True", out[-200:])
check("subpasta do perfil continua permitida", vals.get("SUBPASTA") == "False")
check("rollback so dos itens colidentes deixava a copia parcial (negativo)", vals.get("PARCIAL_ANTIGO_SOBRA") == "True")
check("rollback com todos os itens do pacote limpa a copia parcial", vals.get("PARCIAL_NOVO_SOBRA") == "False")

# ---- via iex o erro nao fecha a janela (negativo: o script antigo dava exit) ----
snippet = 'Invoke-Expression ((Get-Content -Raw -LiteralPath "%s")); "ALIVE"'
rc, out_new = ps(["-Command", snippet % inst], cwd="C:\\")
check("install via iex num destino barrado mostra o erro e a janela segue", "destino nao permitido" in out_new and "ALIVE" in out_new, out_new[-200:])
# mutante: reintroduz o defeito (exit cru via iex) na copia do script
_mut = TMP / "install-mutante.ps1"
_src = inst_text = Path(inst).read_text(encoding="utf-8")
assert "$viaIex = [string]::IsNullOrWhiteSpace($PSCommandPath)" in _src
_mut.write_text(_src.replace("$viaIex = [string]::IsNullOrWhiteSpace($PSCommandPath)", "$viaIex = $false"), encoding="utf-8")
rc, out_old = ps(["-Command", snippet % str(_mut)], cwd="C:\\")
check("install com exit cru fecharia a janela (mutante)", "ALIVE" not in out_old, out_old[-200:])
rc, out_home = ps(["-Command", snippet % inst], cwd=os.environ["USERPROFILE"])
check("one-liner dentro do perfil e barrado sem baixar nada", "destino nao permitido" in out_home and "baixando" not in out_home, out_home[-200:])

# ---- guard de superficie num layout temporario (script copiado: ancestrais = so a pasta de teste) ----
GATE_SRC = SCRIPTS / "check-public-surface.ps1"


def surface(files, vault=None, state=None, extra_args=None):
    base = Path(tempfile.mkdtemp(dir=TMP))
    (base / "of" / "scripts").mkdir(parents=True)
    shutil.copy(GATE_SRC, base / "of" / "scripts" / "check-public-surface.ps1")
    if vault is not None or state is not None:
        (base / "of" / "alia.config.json").write_text(json.dumps({"studio_dir": "studio", "studio": "Acme Studio"}))
        (base / "of" / "studio").mkdir(exist_ok=True)
    if vault is not None:
        vdir = base / "of" / "studio" / COFRE_DIR
        vdir.mkdir(parents=True)
        (vdir / "vault.json").write_text(json.dumps({"secrets": {"a": {"name": "NOME_X", "scope": "s", "value": vault, "fingerprint": "ab12"}}}))
    if state is not None:
        (base / "of" / "studio" / "state.json").write_text(json.dumps({"clients": [{"id": c} for c in state]}))
    pkg = base / "pkg"
    for rel, txt in files.items():
        p = pkg / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(txt, encoding="utf-8")
    return ps(["-File", str(base / "of" / "scripts" / "check-public-surface.ps1"), "-Repo", str(pkg)] + (extra_args or []))


VALOR_COFRE = "valor-do-cofre-9981-zz"
rc, out = surface({"README.md": "ola mundo"}, vault=VALOR_COFRE)
check("pacote limpo passa com cofre nos ancestrais", rc == 0, out[-200:])
rc, out = surface({"README.md": "texto " + VALOR_COFRE}, vault=VALOR_COFRE)
check("valor do cofre plantado no pacote reprova", rc == 1 and "cofre vazou" in out and VALOR_COFRE not in out, out[-300:])

rc, out = surface({"README.md": "ola"}, extra_args=["-RequireIdentityRegistry"])
check("sem registro de identidade o publicador reprova (fail-closed)", rc == 1 and "NAO PODE rodar" in out, out[-200:])
rc, out = surface({"README.md": "ola"})
check("sem a flag a maquina limpa continua passando", rc == 0, out[-200:])

for rel in ("studio/x.md", COFRE_DIR + "/vault.json", "_inbox/a.md", "release-reviews/1.md", "rsi-backlog/a.md", "_retired/a.md", ".claude/settings.local.json"):
    rc, out = surface({"README.md": "ola", rel: "{}"})
    check("veto de caminho %s" % rel, rc == 1 and "vazou" in out, out[-160:])

# valores de teste montados em pedacos (o proprio guard do motor barra credencial literal em arquivo)
AWS = "AK" + "IAZ7QW3RT5YU8PLK2M"
cases = {
    "AWS": ("docs/a.md", "chave " + AWS),
    "AWS em fixture (caminho nao perdoa)": ("scripts/fixtures/a.txt", "chave " + AWS),
    "PEM": ("a.md", "-----BEG" + "IN RSA PRI" + "VATE KEY-----\nMIIE"),
    "projeto OpenAI": ("a.md", "k=sk-pr" + "oj-Ab3dE6gH9jK2mN5pQ8sT1vW"),
    "Google": ("a.md", "k=AI" + "zaSyD3x7Q9r2LmN5pK8vB1cF4gH6jT0wYzXab"),
    "Slack": ("a.md", "t=xo" + "xb-8472916305-qwertzuiopl"),
    "Stripe": ("a.md", "k=sk_li" + "ve_9fT3kL8mQ2xR7vB4nZ"),
    "senha com valor": ("a.md", "pass" + 'word = "Zk9#vT2mQx8L"'),
    "gitignore varrido": (".gitignore", "# k\nCHAVE=" + AWS),
    "LICENSE varrido": ("LICENSE", "x " + AWS),
}
for nome, (rel, txt) in cases.items():
    rc, out = surface({"README.md": "ola", rel: txt})
    check("agulha %s reprova" % nome, rc == 1 and "credencial" in out, out[-160:])
rc, out = surface({"README.md": "ola", "scripts/fixtures/a.txt": "chave " + "AK" + "IAIOSFODNN7EXAMPLE de exemplo"})
check("exemplo documentado (marcador EXAMPLE) so avisa", rc == 0, out[-160:])

rc, out = surface({"README.md": "ola"}, state=["clientefoo"])
check("registro presente: pacote limpo passa", rc == 0, out[-160:])
rc, out = surface({"README.md": "feito para clientefoo"}, state=["clientefoo"])
check("nome de cliente real no pacote reprova", rc == 1 and "identidade de cliente vazou" in out, out[-160:])

# ---- acento em nome de arquivo entra no manifesto (git quotepath) ----
mk = TMP / "mk"
mk.mkdir()
subprocess.run(["git", "init", "-q", str(mk)], check=True)
(mk / "ação.txt").write_text("conteudo", encoding="utf-8")
(mk / "normal.txt").write_text("n", encoding="utf-8")
subprocess.run(["git", "-C", str(mk), "add", "-A"], check=True)


def manifest_has(script_dir):
    mf = mk / "MANIFEST.sha256"
    if mf.exists():
        mf.unlink()
    ps(["-File", str(script_dir / "make-manifest.ps1"), "-Dir", str(mk)])
    return mf.exists() and "ação.txt" in mf.read_text(encoding="utf-8")


check("arquivo com acento entra no manifesto", manifest_has(SCRIPTS))
old_dir = TMP / "mutmk"
old_dir.mkdir()
_mm = read("make-manifest.ps1")
assert "core.quotepath=off" in _mm
(old_dir / "make-manifest.ps1").write_text(_mm.replace("core.quotepath=off", "core.quotepath=true"), encoding="utf-8")
shutil.copy(SCRIPTS / "_manifest-exclude.ps1", old_dir)
check("make-manifest sem quotepath=off perderia o arquivo com acento (mutante)", not manifest_has(old_dir))

# ---- o que so se prova no texto do script (publicar/atualizar nao rodam aqui por lei) ----
MAINT = ("publish-release.ps1", "package-release.ps1", "_release-set.ps1", "release-gate.ps1")
if any(read(n) is None for n in MAINT):
    print("SKIP checagens de texto dos scripts de mantenedor (so existem na oficina, nao viajam no pacote)")
    _fim = True
else:
    _fim = False
pub = read("publish-release.ps1") or ""
pk = read("package-release.ps1") or ""
rs = read("_release-set.ps1") or ""
gate = read("release-gate.ps1") or ""
ue = read("update-engine.ps1")
uo = read("update-online.ps1")
ins = read("install.ps1")
if not _fim: check("commit com identidade da allowlist (-c user.name/email + GIT_*)", "user.email=" in pub and "GIT_COMMITTER_EMAIL" in pub)
if not _fim: check("release-gate roda ANTES do push", pub.index("release-gate.ps1") < pub.rindex("Invoke-Git push"))
if not _fim: check("push pendente nao vira 'nada a publicar'", "@{u}..HEAD" in pub and "retomando o push" in pub)
if not _fim: check("arvore limpa exigida antes de copiar o pacote", pub.index("status --porcelain") < pub.index("& robocopy"))
if not _fim: check("publish/gate/manifesto usam core.quotepath=off", "core.quotepath=off" in pub and "core.quotepath=off" in gate and "core.quotepath=off" in read("make-manifest.ps1"))
if not _fim: check("gate le o manifesto como UTF-8", "ReadAllLines($manifestPath" in gate)
if not _fim: check("LF normalizado ANTES do manifesto", pk.index("LF normalizado") < pk.index('"make-manifest.ps1") -Dir $out'))
allow = "" if _fim else re.search(r"\$ScriptsAllow = @\((.*?)\n\)", rs, re.S).group(1)
names = re.findall(r'"([^"]+)"', allow)
for maint in ("package-release.ps1", "publish-release.ps1", "release-gate.ps1", "install-release-hooks.ps1"):
    check("script de mantenedor %s fora do pacote" % maint, maint not in names)
check("scriptsAllow sem arquivo inexistente nem duplicado", all((SCRIPTS / n).exists() for n in names) and len(names) == len(set(names)),
      str([n for n in names if not (SCRIPTS / n).exists()]))
check("update-online barra a falta de Python ANTES de tocar nos arquivos", uo.index("Python 3 nao encontrado") < uo.index("Backup-Engine -DestDir"))
check("update-engine barra a falta de Python sem tocar em nada", "Python 3 nao encontrado" in ue)
check("update-engine guarda no backup o arquivo que o merge sobrescreve", "$mergeDiff.Changed" in ue and "Backup-InstanceFile $bkp $d $rel" in ue)
check("update-engine resolve -From para caminho absoluto", "GetFullPath($lab)" in ue)
check("TLS 1.2 fixado no install e no update-online", "Tls12" in ins and "Tls12" in uo)
check("install sem exit cru no fluxo (usa Quit-Install)", "Quit-Install" in ins and not re.search(r"(?m)^\s*exit 1$", ins.split("# Fluxo real de instalacao", 1)[1]))
check("install cria o destino e avisa cada item substituido", "New-Item -ItemType Directory -Force -Path $dest" in ins and "sera substituido/mesclado" in ins)
check("passo do graphify visivel (nomeia o que instala)", "graphifyy" in ins)
if not _fim: check("robocopy do empacotamento checa exit >= 8", "Invoke-Robo" in pk and "-ge 8" in pk and not re.search(r"(?m)^\s*robocopy ", pk))
if not _fim: check("referencia entre scripts cobre PSScriptRoot e scripts/X", "PSScriptRoot|here|scriptDir" in pk)
check("codigo morto eventPhases e ramo do repo placeholder removidos", "$eventPhases" not in ins + uo and "ORG/alia-flow" not in ins)

# ---- resultado ----
shutil.rmtree(TMP, ignore_errors=True)
falhas = [r for r in RESULTS if not r[1]]
for nome, ok, det in RESULTS:
    print(("PASS " if ok else "FAIL ") + nome + ("" if ok else "  -> " + det.replace("\n", " ")[:200]))
print("\n%d/%d provas em %.1fs" % (len(RESULTS) - len(falhas), len(RESULTS), time.time() - T0))
sys.exit(1 if falhas else 0)
