"""identity_guard.py - deteccao de identidade real do operador em arquivo publicavel do motor
(TASK-841/842, WARDEN). Cinco porques do vazamento barrado no push da 2.0.3: nada separava
"evidencia para justificar" (privada) de "conteudo do codigo" (publico); a unica trava rodava na
ULTIMA porta (check-public-surface.ps1, pre-push); v2/proof/check.py, que roda a cada mudanca, nao
conferia identidade.

Achado da coordenacao (rodada 2, medido em git grep no produto publicado): o nome do estudio e o
usuario da maquina JA estavam publicos desde antes da 2.0.3 - o check-public-surface.ps1 trata o
nome do estudio como autorreferencia legitima (correto para ELE, que so cacada Client id), mas
este guard novo NUNCA pode repetir esse relaxamento: nome de estudio aqui e SEMPRE vazamento.

Este modulo e a fonte UNICA da regra de identidade para as duas travas (guard na ESCRITA em
hooks/dispatch.py, prova a cada rodada em proof/check.py). Espelha
scripts/check-public-surface.ps1 (Find-OperatorClientIds + secao "(1.5)") - MESMA fonte de dado
(alia.config.json -> studio_dir -> state.json clients, excluindo alia-flow/alia-flow-lab) e MESMA
tecnica de casamento (fronteira de identidade sem hifen/underscore). Nao inventa regra nova pro
Client id; AMPLIA a cobertura pro nome do estudio e pro usuario da maquina, que o script original
nunca precisou cobrir (ele so protege caminho/credencial/Client, nao autorreferencia de estudio).

Tres coisas nunca podem aparecer em arquivo publicavel do motor:
(a) id de Client real do operador (vem do state.json do operador, nunca cravado aqui).
(b) nome do estudio do operador, em qualquer forma: campo "studio" do alia.config.json E o nome
    da pasta raiz do estudio (a pasta que CONTEM o alia.config.json quando studio_dir="."), sem
    diferenca de caixa e com espaco/hifen/underscore intercambiaveis entre as palavras. NUNCA e
    autorreferencia legitima aqui (diferente do check-public-surface.ps1, que so precisa disso
    pra nao confundir Client id com o nome do proprio estudio).
(c) usuario da maquina do operador, em toda forma observada na pratica: caminho nativo com
    espaco, com barra normal, com hifen (forma de slug que o Claude Code usa em
    .claude/projects/, "C--Users-<nome>-..."), com %20, sem espaco algum, e o nome curto 8.3
    (formato "USUARI~1") - todas derivadas em tempo de execucao (os.path.expanduser("~") e a API
    do Windows), nunca cravadas aqui.

Sem state.json acessivel em nenhum ancestral (produto publico ja distribuido, por exemplo): (a) e
(b) ficam vazias e so (c) roda - fail-soft, nunca quebra a sessao por falta de dado do operador.

COBERTURA DO GUARD NA ESCRITA (achado do revisor LATTICE, R2) - declarada aqui de proposito, nunca
so em prosa solta: Write/Edit confere SEMPRE (conteudo + caminho). Bash/PowerShell confere SO
quando ha ALVO PUBLICAVEL entre os alvos de escrita extraidos E o comando carrega TEXTO INLINE
reconhecivel (heredoc, echo/printf/Write-Output/Set-Content/Add-Content/Out-File) - download,
copia de arquivo binario ou redirecionamento de arquivo ja existente no disco ficam FORA do guard
na escrita (o comando nao carrega o conteudo, so o caminho). Essa fatia da superficie e coberta
pela varredura PERIODICA de proof/check.py (que le o arquivo depois de escrito), nunca pelo guard
em tempo real. Ver hooks/dispatch.py (`_bash_carries_inline_content`) e CONTRACTS.md, linha do
modulo "guard".
"""
from __future__ import annotations

import json
import os
import re

_ENGINE_EXCLUDE_RE = re.compile(r"^alia-flow(-lab)?$", re.IGNORECASE)


def find_operator_client_ids(start: str | None = None) -> tuple[list[str], list[str]]:
    """Sobe a arvore de pastas a partir de `start` (default: onde este arquivo mora em disco -
    mesma estrategia de check-public-surface.ps1, que sobe a partir de $PSCommandPath, nunca do
    cwd/alvo da varredura) procurando alia.config.json -> studio_dir -> state.json. Continua ate
    o topo (max 12 niveis): cada acerto SOBRESCREVE sem early-return, entao o ancestral MAIS
    EXTERNO com Clients de verdade vence - o mesmo comportamento do script original. Retorna
    (ids_de_client, nomes_do_estudio) - o segundo e uma LISTA porque o estudio tem duas formas
    legitimas de nome: o campo "studio" do config E o nome da pasta raiz do estudio (podem
    divergir, ex. campo "Estudio Exemplo" vs pasta "estudio-exemplo"). Sem config/state em nenhum
    ancestral: ([], [])."""
    d = os.path.abspath(start or os.path.dirname(os.path.abspath(__file__)))
    ids: list[str] = []
    studio_names: list[str] = []
    for _ in range(12):
        cfg_path = os.path.join(d, "alia.config.json")
        if os.path.isfile(cfg_path):
            try:
                with open(cfg_path, "r", encoding="utf-8") as fh:
                    cfg = json.load(fh)
                sdir = str(cfg.get("studio_dir") or ".").strip() or "."
                studio_dir_abs = os.path.normpath(os.path.join(d, sdir))
                state_path = os.path.join(studio_dir_abs, "state.json")
                if os.path.isfile(state_path):
                    with open(state_path, "r", encoding="utf-8") as fh:
                        state = json.load(fh)
                    found = []
                    for c in (state.get("clients") or []):
                        cid = None
                        if isinstance(c, str):
                            cid = c
                        elif isinstance(c, dict) and c.get("id"):
                            cid = str(c["id"])
                        if cid and not _ENGINE_EXCLUDE_RE.match(cid):
                            found.append(cid)
                    if found:
                        ids = found
                        nomes = []
                        campo_studio = str(cfg.get("studio") or "").strip()
                        if campo_studio:
                            nomes.append(campo_studio)
                        pasta_studio = os.path.basename(studio_dir_abs.rstrip("\\/"))
                        if pasta_studio and pasta_studio.lower() not in (n.lower() for n in nomes):
                            nomes.append(pasta_studio)
                        studio_names = nomes
            except (OSError, json.JSONDecodeError, AttributeError, TypeError):
                pass
        parent = os.path.dirname(d)
        if not parent or parent == d:
            break
        d = parent
    return ids, studio_names


def _boundary_regex(alternatives: list[str]) -> re.Pattern | None:
    """Mesma fronteira de identidade do script original: nao basta \\b (que conta hifen como
    fronteira e casaria um id real colado dentro de outro identificador maior por hifen, ex.
    um servidor "ferramenta-<id>" no .mcp.json). Fronteira valida e espaco/barra/pontuacao;
    hifen e underscore colados NUNCA contam."""
    alternatives = [a for a in alternatives if a]
    if not alternatives:
        return None
    alt = "|".join(re.escape(a) for a in alternatives)
    return re.compile(r"(?i)(?<![\w-])(?:" + alt + r")(?![\w-])")


def _studio_names_regex(studio_names: list[str]) -> re.Pattern | None:
    """Um nome de estudio pode aparecer com espaco, hifen OU underscore entre as palavras
    ("Estudio Exemplo", "estudio-exemplo", "estudio_exemplo") - todas as tres formas contam como
    vazamento, nunca autorreferencia legitima."""
    padroes = []
    for nome in studio_names:
        tokens = re.split(r"[\s_-]+", nome.strip())
        tokens = [t for t in tokens if t]
        if tokens:
            padroes.append(r"[\s_-]+".join(re.escape(t) for t in tokens))
    if not padroes:
        return None
    return re.compile(r"(?i)(?<![\w-])(?:" + "|".join(padroes) + r")(?![\w-])")


def _short_username() -> str | None:
    """Nome curto 8.3 do Windows (ex. "USUARI~1") derivado da API do proprio SO - nunca
    cravado/adivinhado (a regra de truncamento 8.3 nao e trivial de reproduzir a mao). Fail-soft:
    fora do Windows, ou sem a API disponivel, devolve None (nao quebra a checagem, so essa forma
    fica de fora)."""
    if os.name != "nt":
        return None
    try:
        import ctypes
        home = os.path.expanduser("~")
        buf = ctypes.create_unicode_buffer(260)
        n = ctypes.windll.kernel32.GetShortPathNameW(home, buf, 260)  # type: ignore[attr-defined]
        if n == 0:
            return None
        return os.path.basename(buf.value.rstrip("\\/"))
    except Exception:
        return None


def operator_identity_needles(start: str | None = None) -> tuple[list[str], list[str], list[str]]:
    """Resolve as 3 categorias de uma vez: (ids_de_client, nomes_do_estudio, formas_do_caminho).
    `formas_do_caminho` cobre o caminho nativo, barra normal, o USUARIO isolado (que e o que
    realmente varia de forma: com espaco, com hifen - a forma que o Claude Code usa em
    .claude/projects/, "C--Users-<nome>-...", com %20, sem espaco, e o nome curto 8.3)."""
    ids, studio_names = find_operator_client_ids(start)
    home = os.path.expanduser("~")
    home_fwd = home.replace("\\", "/")
    usuario = os.path.basename(home.rstrip("\\/"))
    formas = [home, home_fwd]
    if usuario:
        formas.append(usuario)
        formas.append(re.sub(r"[\s_]+", "-", usuario))  # forma de slug (Claude Code)
        formas.append(usuario.replace(" ", "%20"))
        formas.append(usuario.replace(" ", ""))
    curto = _short_username()
    if curto:
        formas.append(curto)
    # so formas com pelo menos 4 caracteres uteis (cerca de ruido, mesmo padrao do vault-leak)
    formas = sorted({f for f in formas if f and len(f) >= 4}, key=len, reverse=True)
    return ids, studio_names, formas


def find_identity_leak_with(text: str, ids: list[str], studio_names: list[str],
                             home_forms: list[str] | None = None) -> str | None:
    """Mesma regra de find_identity_leak, mas recebe ids/studio_names/home_forms JA resolvidos -
    usado por quem varre muitos textos (proof/check.py) para nao reabrir alia.config.json/
    state.json nem recalcular o nome curto 8.3 a cada linha."""
    if not text:
        return None
    if ids:
        id_re = _boundary_regex(ids)
        m = id_re.search(text) if id_re else None
        if m:
            return f"id de Client real do operador ({m.group(0)})"
    studio_re = _studio_names_regex(studio_names)
    m2 = studio_re.search(text) if studio_re else None
    if m2:
        return f"nome do estudio do operador ({m2.group(0)})"
    if home_forms is None:
        _, _, home_forms = operator_identity_needles()
    text_lower = text.lower()
    for candidate in home_forms:
        if candidate.lower() in text_lower:
            return f"caminho/usuario real da maquina do operador ({candidate})"
    return None


def find_identity_leak(text: str, start: str | None = None) -> str | None:
    """Devolve o motivo (string) do PRIMEIRO achado de identidade real no texto, ou None se
    limpo. Ordem: (a) id de Client, (b) nome do estudio, (c) usuario/caminho da maquina - a
    primeira que bater decide a mensagem. Resolve tudo do zero a cada chamada (uso do guard, 1
    Write/Edit por vez) - para varrer muitos textos de uma vez, use find_identity_leak_with."""
    ids, studio_names, home_forms = operator_identity_needles(start)
    return find_identity_leak_with(text, ids, studio_names, home_forms)


# ---------------------------------------------------------------------------
# Classificacao de alvo publicavel (o que e "arquivo do motor que ship")
# ---------------------------------------------------------------------------
# ALLOWLIST, nao denylist - mesmo criterio de scripts/package-release.ps1 (reuse-first: espelha
# $shipDirs/$shipFiles/$scriptsAllow/$docsAllow de la, nao inventa uma segunda lista). Denylist
# falha aberto (pasta privada nova nasce publicavel por omissao); allowlist falha fechado (pasta
# nova so entra quando alguem decide ship-la em package-release.ps1 E aqui).

_SHIP_DIRS = {"engine", "skills", "onboarding", "optional-mcps", "studio.example",
              ".github", ".claude", ".opencode", ".agents", "v2"}
_SHIP_DIR_EXCLUDE_SUBDIRS = {"_retired", "_dev", "_drafts", "release", "node_modules"}
_SHIP_FILES = {
    "agents.md", "claude.md", "readme.md", "primeiros-passos.md", "contributing.md",
    "changelog.md", "version", "license", "credits.md", "alia.config.json", "opencode.json",
    "iniciar-alia.bat", "atualizar-alia.bat", "reverter-alia.bat", ".gitattributes",
    ".gitignore", "manifest.sha256",
}
# scripts/<nome> - mesma allowlist ($scriptsAllow) de scripts/package-release.ps1.
_SCRIPTS_ALLOW = {
    "_studio.ps1", "_manifest-exclude.ps1", "alinhamento-gate.ps1", "budget-check.ps1",
    "check-public-surface.ps1", "client-state.ps1", "cost-per-artifact.ps1", "cost-sensor.ps1",
    "ddd-drift.ps1", "debt-scan.ps1", "delegation-gate.ps1", "delegation-guard.ps1",
    "desperdicio.ps1", "detect-harness.ps1", "docs-check.ps1", "doctor.ps1",
    "evolution-scan.ps1", "git-sync.ps1", "gate-check.ps1", "graph-check.ps1",
    "graph-usage-sensor.ps1", "graph-usage.ps1", "guard-core.ps1", "health-check.ps1",
    "import-project.ps1", "install.ps1", "kb-index.ps1", "law-ledger-check.ps1",
    "lineage-graph.ps1", "make-manifest.ps1", "memory-curator.ps1", "mission-control.ps1",
    "package-release.ps1", "promote-memory.ps1", "publish-gate.ps1", "reflect-check.ps1",
    "register-task.ps1", "response-guard.ps1", "rsi-patterns.ps1", "semantic-lint.ps1",
    "session-reflection.ps1", "session-search.py", "smoke-test.ps1", "squad-bridge.ps1",
    "squad-report.ps1", "stale-tasks.ps1", "task-context.ps1", "task-sweep.ps1",
    "update-engine.ps1", "update-online.ps1", "validate-workflow.ps1", "verify-manifest.ps1",
    "secret.ps1", "secret-write-guard.ps1", "pre-tool-use.ps1", "session-start.ps1",
    "session-baton.ps1", "session-baton-guard.ps1", "harness-baseline.ps1",
    "ensure-graphify.ps1", "rsi-apply.ps1", "rsi-heldout.ps1", "_rsi-lib.ps1",
    "sync-harness-adapters.ps1", "rsi-promote-pattern.ps1", "capability-check.ps1",
    "read-shunt-guard.ps1", "budget-gate.ps1", "release-gate.ps1", "leitor-gate.ps1",
    "revert-alia.ps1", "install-release-hooks.ps1",
}
_DOCS_ALLOW = {"readme.md", "compatibilidade.md", "integridade.md"}
# engine/<...> excluido mesmo dentro de _SHIP_DIRS - mesmo $xf de package-release.ps1: edges.json
# e DERIVED (regenerado por kb-index.ps1 a cada rodada, empacotar seria foto congelada podre);
# capability-ledger.md/secrets.md sao diario de bancada, nenhum script da allowlist le em runtime.
_ENGINE_FILE_EXCLUDE = {"governance/edges.json", "governance/capability-ledger.md", "governance/secrets.md"}

_OFICINA_MARKER = "/clients/alia-flow-lab/"


def _classify_oficina_relative(rel: str) -> bool:
    """True quando `rel` (caminho relativo a clients/alia-flow-lab/, ja em minusculo/barra
    normal) e publicavel pela mesma allowlist de package-release.ps1."""
    if rel == "studio.example" or rel.startswith("studio.example/"):
        return True
    parts = [p for p in rel.split("/") if p]
    if not parts:
        return False
    top = parts[0]
    if top == "v2":
        # v2/ inteiro ships (motor 2.0), exceto sandbox/cache de teste - nunca identidade real,
        # ja coberto pela prova de "guarda: nenhum _sandbox* sobrevive" em proof/check.py.
        return not any(p.startswith("_sandbox") or p == "__pycache__" for p in parts[1:])
    if top in _SHIP_DIRS:
        if any(p in _SHIP_DIR_EXCLUDE_SUBDIRS for p in parts[1:-1]):
            return False
        if top == ".claude" and len(parts) > 1 and parts[1] == "agents":
            return False
        if top == "engine" and "/".join(parts[1:]) in _ENGINE_FILE_EXCLUDE:
            return False
        return True
    if top == "scripts":
        if len(parts) == 2 and parts[1] in _SCRIPTS_ALLOW:
            return True
        if len(parts) >= 2 and parts[1] == "fixtures":
            return True
        return False
    if top == "docs":
        return len(parts) == 2 and parts[1] in _DOCS_ALLOW
    if len(parts) == 1 and top in _SHIP_FILES:
        return True
    return False


def _find_product_root(path: str) -> str | None:
    """Sobe a arvore a partir do arquivo alvo procurando VERSION + v2/ + MANIFEST.sha256 juntos
    (marcador do repositorio do PRODUTO publicado, sem alia.config.json de dogfood aninhado)."""
    d = os.path.dirname(os.path.abspath(path))
    for _ in range(15):
        if (os.path.isfile(os.path.join(d, "VERSION")) and
                os.path.isdir(os.path.join(d, "v2")) and
                os.path.isfile(os.path.join(d, "MANIFEST.sha256"))):
            return d
        parent = os.path.dirname(d)
        if not parent or parent == d:
            break
        d = parent
    return None


def _find_instance_v2_root(path: str) -> str | None:
    """Sobe a arvore procurando VERSION + v2/(pasta) juntos, SEM exigir MANIFEST.sha256 (marcador
    mais frouxo que _find_product_root: cobre uma INSTANCIA INSTALADA do operador - update local
    pode nao regravar MANIFEST.sha256). So serve pra decidir se um path DENTRO de v2/ e
    protegido; a RAIZ da instancia (alia.config.json, state.json) NUNCA e classificada por isto -
    e dado privado do operador por definicao (AGENTS.md, Fronteira), nao arquivo publicavel."""
    d = os.path.dirname(os.path.abspath(path))
    for _ in range(15):
        if os.path.isfile(os.path.join(d, "VERSION")) and os.path.isdir(os.path.join(d, "v2")):
            return d
        parent = os.path.dirname(d)
        if not parent or parent == d:
            break
        d = parent
    return None


def classify_target(path: str) -> str | None:
    """'oficina' quando o alvo mora em clients/alia-flow-lab/... E esta na ALLOWLIST que
    package-release.ps1 de fato empacota; 'product' quando o alvo mora sob a raiz de um repo do
    PRODUTO ja publicado (VERSION + v2/ + MANIFEST.sha256 - la dentro, tudo e publicavel por
    definicao, so exclui .git); 'instance' quando o alvo mora DENTRO de v2/ de uma INSTANCIA
    instalada (VERSION + v2/, sem MANIFEST.sha256) - so v2/ e protegido ali, nunca a raiz da
    instancia (dado privado do operador); None quando o alvo nao e publicavel (guard nao trava)."""
    norm = ("/" + path.replace("\\", "/").lstrip("/")).lower()
    idx = norm.find(_OFICINA_MARKER)
    if idx != -1:
        rel = norm[idx + len(_OFICINA_MARKER):]
        return "oficina" if _classify_oficina_relative(rel) else None
    root = _find_product_root(path)
    if root:
        rel = os.path.relpath(os.path.abspath(path), root).replace("\\", "/").lower()
        if rel.split("/")[0] == ".git":
            return None
        return "product"
    inst_root = _find_instance_v2_root(path)
    if inst_root:
        rel = os.path.relpath(os.path.abspath(path), inst_root).replace("\\", "/").lower()
        parts = rel.split("/")
        if parts[0] == "v2" and not any(p.startswith("_sandbox") or p == "__pycache__" for p in parts[1:]):
            return "instance"
    return None
