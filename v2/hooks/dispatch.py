#!/usr/bin/env python3
"""Despachante unico do motor 2.0 (modulo 8, guard; modulo 4, ledger).

Le UM evento de hook do Claude Code pelo stdin (JSON) e faz 3 coisas, nunca
mais que isso:

1. Ledger (PreToolUse/PostToolUse/SubagentStop de Agent e Task): grava em
   activity.jsonl quem executou e, se o payload trouxer uso, o custo.
2. Guard (PreToolUse de Write, Edit, Bash, Agent, Task): as 4 negacoes do
   modulo 8. So PreToolUse decide; os outros eventos so alimentam o ledger.
3. Trava de fim (Stop, TASK-812): se ESTA sessao tocou uma Task (evidencia no
   ledger - session_id e task_id gravados juntos por um evento real - nunca o
   campo "session" do state.json, quase sempre vazio) que segue sem
   gate_verdict, bloqueia o Stop 1 vez citando o id da Task. stop_hook_active
   nunca bloqueia de novo (anti-laco): deixa parar e grava "encerrou_sem_gate"
   no ledger, a divida visivel. Desliga com ALIA_END_LOCK_OFF=1 ou o arquivo
   .claude/end-lock.off (mesmo padrao do graph-gate.off).
4. Recuperacao pos-compactacao (SessionStart matcher "compact", TASK-839): devolve
   additionalContext curto apontando o transcript_path da sessao (o .jsonl continua com a
   conversa inteira antes da fronteira de compactacao) e grava "compact_recovery" no ledger.
   Qualquer outro source, ou SessionStart sem transcript_path, devolve {} (fail-soft).

Nunca deixa excecao crua vazar: todo caminho de erro cai no except geral no
fim do arquivo, loga em activity.jsonl como "dispatch_error" e devolve uma
decisao segura (deny quando o evento e PreToolUse ou nao da pra saber; Stop
sempre libera - um hook quebrado nunca prende o operador).

So biblioteca padrao. UTF-8 explicito em toda leitura/escrita/print.
"""
from __future__ import annotations

import json
import os
import posixpath
import re
import shlex
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lib"))
import identity_guard  # noqa: E402
import ledger  # noqa: E402
import paths  # noqa: E402
import trava  # noqa: E402
# pulso (Operacao Deep, TASK-847) importado SO dentro de quem usa (handle_pretooluse_pulso_inject,
# handle_stop, handle_session_start) - import tardio, nunca no topo: a maioria dos eventos
# despachados (Write/Edit/Bash negados ou nao, PostToolUse, SubagentStop) nunca precisa de PULSO,
# e cada subprocesso novo de dispatch.py paga o custo de importar do zero (nao ha cache entre
# processos) - medido, custava alguns segundos a mais na bateria inteira de proof/run_proofs.py.


def _ledger_path() -> str:
    return paths.ledger_path()


def _project_dir() -> str:
    return paths.studio_root()  # 2.1.3: mesma regra do resto (antes divergia sem CLAUDE_PROJECT_DIR)


def _nome_longo(p: str) -> str:
    """Caminho 8.3 (`ALIA-F~1`) vira o nome longo (so Windows, so quando ha `~`): o guard casa pelo
    NOME das pastas, e o nome curto escapava de clients/<id>/ e da fonte do motor."""
    if os.name != "nt" or "~" not in p:
        return p
    try:
        import ctypes
        buf = ctypes.create_unicode_buffer(1024)
        cand, sufixo = p, ""
        for _ in range(12):
            n = ctypes.windll.kernel32.GetLongPathNameW(cand.replace("/", "\\"), buf, 1024)  # type: ignore[attr-defined]
            if 0 < n < 1024:
                return buf.value.replace("\\", "/") + sufixo
            cand, resto = posixpath.split(cand)
            if not cand or not resto:
                break
            sufixo = "/" + resto + sufixo
    except Exception:
        pass
    return p


def _norm(p: str) -> str:
    """Barra normal + `..`/`.` resolvidos (2.1.3: `clients/x/../../engine/a.md` escapava do kernel, da
    muralha e da isencao de artifacts) + nome longo no Windows."""
    p = (p or "").replace("\\", "/")
    if not p:
        return p
    return posixpath.normpath(_nome_longo(p))


def _com_cwd(p: str, cwd: str | None) -> str:
    """Caminho relativo de Bash/PowerShell vira absoluto contra o cwd do evento (quando ha): a fonte do
    motor so e reconhecida pelo caminho inteiro. Sem cwd, o relativo segue relativo (e o guard o trata)."""
    q = (p or "").strip().strip("'\"")
    n = q.replace("\\", "/")
    if not q or not cwd or n.startswith(("/", "~", "$")) or re.match(r"^[A-Za-z]:", n):
        return p
    return cwd.replace("\\", "/").rstrip("/") + "/" + n


# ---------------------------------------------------------------------------
# Ledger (parte 4)
# ---------------------------------------------------------------------------

def handle_pre_agent(event: dict) -> None:
    tool_input = event.get("tool_input") or {}
    ledger.append_event(_ledger_path(), {
        "event": "pre_agent",
        "session_id": event.get("session_id"),
        "tool_use_id": event.get("tool_use_id"),
        "tool_name": event.get("tool_name"),
        "agent_type": tool_input.get("subagent_type"),
        "task_id": _infer_task_id(event),
        "prompt_chars": len(str(tool_input.get("prompt") or "")),
    })


SUBAGENT_CAP = 20  # teto de Agent/Task por sessao - o 21o e negado


def _subagent_cap_check(event: dict) -> dict | None:
    """Conta Agent/Task por sessao num sidecar do ledger (O(1), nunca le o activity.jsonl).
    Devolve a negacao quando a sessao ja gastou o teto; senao incrementa e devolve None.
    Sem session_id nao ha como contar: libera (falha aberta, so este teto)."""
    sid = event.get("session_id")
    if not sid:
        return None
    path = _ledger_path() + ".subagentes.json"
    # 2.1.3: ler-contar-gravar sob lock + escrita atomica. Antes, dois Agent em paralelo perdiam uma
    # contagem e um JSON lido pela metade zerava o teto da sessao (falha aberta).
    with trava.trava(path):
        try:
            with open(path, "r", encoding="utf-8") as fh:
                cont = json.load(fh)
            if not isinstance(cont, dict):
                cont = {}
        except (OSError, json.JSONDecodeError):
            cont = {}
        n = int(cont.get(sid, 0))
        if n >= SUBAGENT_CAP:
            return _deny(f"guard: teto de {SUBAGENT_CAP} subagentes por sessao atingido ({n} ja acionados). "
                         "Feche esta sessao e abra outra, ou trabalhe sem delegar mais.")
        cont[sid] = n + 1
        try:
            trava.gravar_atomico(path, json.dumps(cont))
        except OSError:
            pass
    return None


def _infer_task_id(event: dict) -> str | None:
    tool_input = event.get("tool_input") or {}
    text = str(tool_input.get("prompt") or "") + " " + str(tool_input.get("description") or "")
    m = re.search(r"TASK-\d+", text)
    if m:
        return m.group(0)
    # ALIA_TASK_ID nunca era definido (achado da revisao independente, TASK-804): a fonte
    # real e o arquivo que `task.py open` grava por sessao (lib/paths.py).
    return paths.read_current_task(event.get("session_id"))


# ---------------------------------------------------------------------------
# PULSO (Operacao Deep, TASK-847): PreToolUse de Agent/Task anexa o bloco do sub-agente ao fim
# do prompt via updatedInput. permissionDecision "allow" e seguro aqui porque handle_pre_agent
# (chamado antes desta funcao) nunca nega Agent/Task hoje - so registra no ledger; "allow" so
# formaliza o que o guard ja deixaria passar, nunca afrouxa negacao nenhuma.
# ---------------------------------------------------------------------------

def _pulso_on() -> bool:
    """PULSO (TASK-847) foi vetado pela seguranca: desligado, salvo opt-in ALIA_PULSO=1. Sem a
    flag nada e injetado (sub-agente, SessionStart) nem regravado (Stop)."""
    return os.environ.get("ALIA_PULSO") == "1"


def handle_pretooluse_pulso_inject(event: dict) -> dict:
    if not _pulso_on():
        return _no_decision()
    tool_input = event.get("tool_input") or {}
    agent_id = tool_input.get("subagent_type")
    if not agent_id:
        return _no_decision()
    try:
        import pulso  # noqa: E402 (import tardio - ver comentario no topo do arquivo)
        state = pulso.load_state(paths.pulso_path())
        bloco = pulso.render(agent_id, state)
    except Exception:
        return _no_decision()  # PULSO nunca bloqueia nem quebra a delegacao
    if not bloco:
        return _no_decision()  # agente sem entrada no PULSO = nada injetado
    prompt_original = str(tool_input.get("prompt") or "")
    novo_input = dict(tool_input)
    novo_input["prompt"] = f"{prompt_original}\n\n{bloco}" if prompt_original else bloco
    return {"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "allow",
        "updatedInput": novo_input,
    }}


_USAGE_FIELDS = ("input_tokens", "output_tokens", "cache_creation_input_tokens", "cache_read_input_tokens")


def _sum_usage_from_transcript(transcript_path: str) -> dict | None:
    """Plano B (secao 4): le SO os campos de uso do transcript do sub-agente,
    nunca o conteudo, e soma por turno. Custo O(linhas do transcript daquele
    sub-agente), nao da conversa inteira.

    O transcript grava a MESMA mensagem varias vezes durante o streaming
    (cada linha e um content-block novo do mesmo turno, com `usage` repetido
    e crescente ate o valor final). Somar toda linha conta a mesma mensagem
    2 a 3x e infla o total (medido: 17.010 contra 677.514 antes do conserto).
    Correcao: agrupa por `message.id` e fica so com o MAIOR valor de cada
    campo de uso por id (a leitura final do streaming), depois soma entre
    ids distintos. Linha sem id nunca e deduplicada com outra (chave unica
    por linha), para nao perder uso de verdade por falta de id.

    `tool_calls` conta blocos `tool_use` por `id` de bloco (`toolu_...`),
    nao por `message.id`: turnos com mais de 1 tool_use no mesmo `message.id`
    aparecem em linhas separadas do transcript, cada uma com so o bloco novo.
    """
    if not transcript_path or not os.path.exists(transcript_path):
        return None
    per_message: dict[str, dict[str, int]] = {}
    tool_use_ids: set[str] = set()
    found = False
    line_no = 0
    with open(transcript_path, "r", encoding="utf-8") as fh:
        for raw in fh:
            line_no += 1
            raw = raw.strip()
            if not raw:
                continue
            try:
                rec = json.loads(raw)
            except json.JSONDecodeError:
                continue
            msg = rec.get("message") if isinstance(rec, dict) else None
            if not isinstance(msg, dict):
                continue
            content = msg.get("content")
            if isinstance(content, list):
                for b in content:
                    if isinstance(b, dict) and b.get("type") == "tool_use":
                        tool_id = b.get("id")
                        if tool_id:
                            tool_use_ids.add(tool_id)
            usage = msg.get("usage")
            if not isinstance(usage, dict):
                continue
            found = True
            mid = msg.get("id") or f"_no_id_line_{line_no}"
            slot = per_message.setdefault(mid, {})
            for k in _USAGE_FIELDS:
                v = int(usage.get(k) or 0)
                if v > slot.get(k, 0):
                    slot[k] = v
    if not found:
        return None
    totals = {k: 0 for k in _USAGE_FIELDS}
    for slot in per_message.values():
        for k in _USAGE_FIELDS:
            totals[k] += slot.get(k, 0)
    totals["tool_calls"] = len(tool_use_ids)
    return totals


def handle_post_agent(event: dict) -> None:
    tool_response = event.get("tool_response") or {}
    agent_id = tool_response.get("agentId")
    status = tool_response.get("status")

    if agent_id and ledger.cost_already_recorded(_ledger_path(), agent_id):
        # prova negativa: 2o PostToolUse para o mesmo agent_id nunca duplica custo.
        ledger.append_event(_ledger_path(), {
            "event": "post_agent_duplicate_ignored",
            "session_id": event.get("session_id"),
            "agent_id": agent_id,
        })
        return

    row = {
        "event": "post_agent",
        "session_id": event.get("session_id"),
        "tool_use_id": event.get("tool_use_id"),
        "agent_id": agent_id,
        "agent_type": (event.get("tool_input") or {}).get("subagent_type"),
        "task_id": _infer_task_id(event),
        "status": status,
    }

    if status == "completed":
        row["source"] = "payload"
        row["tokens_total"] = tool_response.get("totalTokens")
        row["duration_ms"] = tool_response.get("totalDurationMs")
        row["tool_calls"] = tool_response.get("totalToolUseCount")
        row["usage"] = tool_response.get("usage")
    else:
        # plano B: status != completed (ex.: async_launched) nao traz uso no
        # payload de PostToolUse; tenta o transcript do proprio sub-agente se
        # algum SubagentStop ja tiver deixado o caminho no ambiente/ledger.
        row["source"] = "pending_background"

    ledger.append_event(_ledger_path(), row)


def handle_subagent_stop(event: dict) -> None:
    agent_id = event.get("agent_id")
    if not agent_id or ledger.cost_already_recorded(_ledger_path(), agent_id):
        return
    usage = _sum_usage_from_transcript(event.get("agent_transcript_path"))
    if usage is None:
        return
    ledger.append_event(_ledger_path(), {
        "event": "post_agent",
        "session_id": event.get("session_id"),
        "agent_id": agent_id,
        "agent_type": event.get("agent_type"),
        "task_id": paths.read_current_task(event.get("session_id")),
        "status": "completed_background",
        "source": "transcript_planB",
        "tokens_total": sum(v for k, v in usage.items() if k != "tool_calls"),
        "tool_calls": usage.get("tool_calls"),
        "usage": {k: v for k, v in usage.items() if k != "tool_calls"},
    })


# ---------------------------------------------------------------------------
# Guard (parte 8) - so PreToolUse decide
# ---------------------------------------------------------------------------

# Sem negacao, o dispatch NUNCA devolve decisao (revisao independente, TASK-804): um
# "allow" explicito pula as perguntas de permissao do proprio host quando o Claude Code
# roda fora do bypass. Dict vazio = "este hook nao tem opiniao", o host decide sozinho.
def _no_decision() -> dict:
    return {}


def _deny(reason: str) -> dict:
    return {"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": reason,
    }}


SECRET_PATTERNS = [
    # 2.1.3: `sk-` so conta no comeco de palavra (antes casava `task-<20 letras>`, `disk-...`).
    re.compile(r"(?<![A-Za-z0-9_\-])sk-[A-Za-z0-9]{20,}"),
    # TASK-845 (E03): formatos que passavam pela trava (medido 27/09 com valor falso).
    re.compile(r"(?<![A-Za-z0-9_\-])sk-(?:ant|proj)-[A-Za-z0-9_\-]{20,}"),
    re.compile(r"gh[pousr]_[A-Za-z0-9]{30,}"),
    re.compile(r"github_pat_[A-Za-z0-9_]{40,}"),
    re.compile(r"nvapi-[A-Za-z0-9_\-]{30,}"),
    re.compile(r"pplx-[A-Za-z0-9]{30,}"),
    re.compile(r"eyJ[A-Za-z0-9_\-]{10,}\.eyJ[A-Za-z0-9_\-]{10,}"),
    re.compile(r"\b[A-Z0-9_]*(?:KEY|TOKEN|SECRET)\s*[:=]\s*['\"]?[A-Za-z0-9_\-]{20,}"),
    # 2.1.3: minuscula/mista (`token = "..."`, `"client_secret": "..."`) so com o valor ENTRE ASPAS (sem
    # aspas, `cache_key = nome_de_variavel_comprido` e codigo, nao segredo); e cabecalho `Bearer <valor>`.
    re.compile(r"(?i)\b\w*(?:key|token|secret|passw(?:or)?d)\w*['\"]?\s*[:=]\s*['\"][A-Za-z0-9_\-/+=.]{20,}['\"]"),
    re.compile(r"(?i)\bbearer\s+[A-Za-z0-9_\-.=]{20,}"),
    re.compile(r"AKIA[0-9A-Z]{16}"),
    re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
    re.compile(r"(?i)api[_-]?key\s*[:=]\s*['\"][A-Za-z0-9_\-]{16,}['\"]"),
]

_SPLIT_CLAUSULAS_RE = re.compile(r"[;&|\n\r]+")
_PREFIXOS_COMANDO = {"sudo", "env", "command", "time", "nohup", "exec", "call", "start", "&", ".", "builtin"}
_SHELLS = {"bash", "sh", "zsh", "pwsh", "powershell", "cmd"}
_INTERPRETES = {"python", "python3", "py", "node", "pwsh", "powershell", "bash", "sh", "zsh"}
_PUBLICADORES = {"package-release", "publish-release"}


def _tokens(clausula: str) -> list[str]:
    try:
        toks = shlex.split(clausula, posix=False)
    except ValueError:
        toks = clausula.split()
    return [t.strip("'\"") for t in toks]


def _base_cmd(tok: str) -> str:
    b = _norm(tok).rsplit("/", 1)[-1].lower()
    return b[:-4] if b.endswith(".exe") else b


def _stem(tok: str) -> str:
    return os.path.splitext(_base_cmd(tok))[0]


def _cmd_tokens(clausula: str) -> list[str]:
    """Tokens da clausula a partir da POSICAO DE COMANDO (pula `VAR=x`, sudo/env/call/& ...)."""
    toks = _tokens(clausula)
    while toks and (re.match(r"^\w+=", toks[0]) or _base_cmd(toks[0]) in _PREFIXOS_COMANDO):
        toks = toks[1:]
    return toks


def _clausula_publica(clausula: str, nivel: int = 0) -> bool:
    """True quando a clausula, NA POSICAO DE COMANDO, publica: `git [-C x ...] push`, `gh release`,
    `npm|pnpm|yarn|bun publish`, ou o script package-release/publish-release (direto ou via
    interpretador). Nome citado/editado/lido (cat, Edit, echo) nunca conta (2.1.3, P1-8 e P2-10)."""
    toks = _cmd_tokens(clausula)
    if not toks:
        return False
    cmd, args = _base_cmd(toks[0]), toks[1:]
    if _stem(toks[0]) in _PUBLICADORES:
        return True
    if cmd == "git":
        k = 0
        while k < len(args):
            a = args[k]
            if a in ("-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path") and k + 1 < len(args):
                k += 2
            elif a.startswith("-"):
                k += 1
            else:
                return a.lower() == "push"
        return False
    sub = [a for a in args if not a.startswith("-")]
    if cmd == "gh":
        return bool(sub) and sub[0].lower() == "release"
    if cmd in ("npm", "pnpm", "yarn", "bun", "cargo"):
        return bool(sub) and sub[0].lower() == "publish"
    if cmd == "twine":
        return bool(sub) and sub[0].lower() == "upload"
    if cmd in _INTERPRETES:
        for k, a in enumerate(args):  # `-c`/`-Command`: a string e um comando (recursao curta)
            if a.lower() in ("-c", "-command", "/c"):
                return nivel < 2 and _comando_publica(" ".join(args[k + 1:]), nivel + 1)
        for k, a in enumerate(args):  # o script que o interpretador roda: o de -File, ou o 1o com extensao de script
            if a.lower() in ("-file", "-f") and k + 1 < len(args):
                return _stem(args[k + 1]) in _PUBLICADORES
            if a.lower().endswith(_SCRIPT_EXT):
                return _stem(a) in _PUBLICADORES
    return False


def _comando_publica(command: str, nivel: int = 0) -> bool:
    return any(_clausula_publica(c, nivel) for c in _SPLIT_CLAUSULAS_RE.split(_sem_corpo_heredoc(command)))


def _repo_do_push(command: str, cwd: str) -> str | None:
    """Pasta onde o `git push` do comando roda: `git -C <dir>`, `cd <dir> &&`, senao o cwd do evento."""
    destino = cwd or ""
    for c in _SPLIT_CLAUSULAS_RE.split(_sem_corpo_heredoc(command)):
        toks = _cmd_tokens(c)
        if toks and _base_cmd(toks[0]) in ("cd", "set-location", "pushd") and len(toks) > 1:
            destino = _com_cwd(toks[-1], destino)
        elif toks and _base_cmd(toks[0]) == "git" and "-C" in toks and toks.index("-C") + 1 < len(toks):
            destino = _com_cwd(toks[toks.index("-C") + 1], destino)
            break
    return destino or None
# 2.1.2 (TASK-862): comandos regidos SO por L70 + marcador de check valido, fora da muralha L80
# (a sessao principal e a unica que publica/propaga; barrar a escrita dela ai deixava zero ator).
# update-engine nao exige marcador: so sai da muralha. A passagem vale SO para o comando INTEIRO
# `powershell|pwsh [-NoProfile] [-ExecutionPolicy X] -File <...>publish-release|update-engine.ps1
# [args]`: sem -Command/-c, sem encadeamento nem redirecionamento, so esses dois scripts.
# 2.1.3 (P1-5): `[ \t]` no lugar de `\s` (a linha nova e separador de comando, nao espaco), fullmatch,
# e o script so vale dentro de uma pasta `scripts/` (antes: qualquer pasta, ate /tmp/x/update-engine.ps1).
_WALL_PASS_RE = re.compile(
    r"""(?ix)[ \t]*(?:powershell|pwsh)(?:\.exe)?(?:[ \t]+-NoProfile)?(?:[ \t]+-ExecutionPolicy[ \t]+\w+)?
    [ \t]+-File[ \t]+(?P<q>["']?)(?:[^"'\s;&|<>`$()]*[\\/])?scripts[\\/](?:publish-release|update-engine)\.ps1(?P=q)
    (?:[ \t]+[\w.:\\/\-"']+)*[ \t]*""")
_WALL_PASS_BAD_ARG_RE = re.compile(r"(?i)\s-(?:c|command|e|ec|encodedcommand)(?:\s|$)")

# lista EXPLICITA do kernel (revisao independente: a checagem antiga procurava "/kernel/",
# uma pasta que nao existe - o kernel real e este punhado de arquivo + a pasta engine/).
KERNEL_FILES = ("agents.md", "claude.md", "contracts.md")

# gatilhos de redirecionamento que o Bash pode usar para escrever num arquivo (>, >>, tee,
# cp, mv, e os equivalentes de PowerShell Out-File/Set-Content).
# achado do CEO, 24/09/2026 (falso positivo no studio vivo): `2>&1` (duplicacao de descritor,
# nunca escreve arquivo) casava com o `>` generico e qualquer mencao de LEITURA ao kernel em
# outro trecho do mesmo comando (`cat AGENTS.md`, `grep ... AGENTS.md`) virava negacao. So o
# ALVO real de escrita conta agora - ver _extract_write_targets.
# TASK-824 (conserto, regressao apontada pelo Gate do NEXUS): cp/mv/rm nao podem compartilhar a
# mesma extracao de alvo - cada familia tem semantica diferente de qual argumento e ESCRITA. cp
# so escreve no DESTINO (-Destination ou ultimo posicional); -Path/-LiteralPath ali e a ORIGEM
# (leitura), nunca alvo. mv apaga a origem ao mover, entao origem E destino sao alvo de escrita.
# rm/del/erase/remove-item sao os mais amplos: TODO -Path/-LiteralPath e TODO posicional e alvo,
# porque cada caminho citado e apagado. rd/rmdir ficam de fora de proposito (a lei protege
# ARQUIVO do kernel, nunca pasta).
_CP_RE = re.compile(r"^(cp|copy|copy-item)\b", re.IGNORECASE)
_MV_RE = re.compile(r"^(mv|move|move-item)\b", re.IGNORECASE)
_RM_RE = re.compile(r"^(rm|del|erase|remove-item)\b", re.IGNORECASE)
_OUTFILE_SETCONTENT_RE = re.compile(r"^(out-file|set-content|add-content|clear-content|tee-object)\b", re.IGNORECASE)
_NEWITEM_RE = re.compile(r"^new-item\b", re.IGNORECASE)
_IOFILE_WRITE_RE = re.compile(r"\[(?:system\.)?io\.file\]::write\w*\s*\(\s*['\"]([^'\"]+)['\"]", re.IGNORECASE)
_SED_INPLACE_RE = re.compile(r"^sed\b", re.IGNORECASE)
# alvo entre aspas (com espaco dentro - achado do NEXUS, Gate: caminho real do usuario quase
# sempre tem espaco, ex. "<unidade>:\Users\Nome Completo\...", e (\S+) ou .split() ingenuo cortava no
# espaco, deixando so o pedaco ATE o espaco como "alvo" - a identidade nunca era vista dentro da
# parte cortada fora, e o alvo incompleto raramente batia numa pasta publicavel de verdade).
_QUOTED_OR_TOKEN = r'''(?:"[^"]*"|'[^']*'|\S+)'''


def _first_token(text: str) -> str:
    """Primeiro token de `text`, respeitando aspas simples/duplas (o conteudo entre aspas pode
    ter espaco) - mesma regra usada pelas capturas `-Destination`/`-Path`/`-FilePath` abaixo."""
    text = text.lstrip()
    if not text:
        return ""
    if text[0] in "'\"":
        aspa = text[0]
        fim = text.find(aspa, 1)
        if fim != -1:
            return text[1:fim]
        return text[1:]
    return text.split(None, 1)[0]


def _sem_corpo_heredoc(command: str) -> str:
    """Tira o corpo de heredoc (so a 1a linha, com o redirecionamento, fica)."""
    return _HEREDOC_BODY_RE.sub(lambda m: m.group(0).split(chr(10), 1)[0], command)


def _redirect_targets(texto: str) -> list[str]:
    """Alvos de `>`, `>>`, `N>`, `&>`, `>|`, `>&arq` FORA de aspas. Nao contam: `2>&1`/`>&N` (duplicacao
    de descritor), setas `->`/`=>`, `>(...)` e `>` dentro de aspas (HTML em echo, `a -> b`). Aspa que
    nunca fecha (apostrofo solto: `echo don't > f`) e tratada como literal e o resto e varrido de novo."""
    alvos: list[str] = []
    aspa, pos_aspa, i, n = "", -1, 0, len(texto)
    while i < n:
        ch = texto[i]
        if aspa:
            if ch == aspa:
                aspa = ""
        elif ch in "'\"":
            aspa, pos_aspa = ch, i
        elif ch == ">" and not (i and texto[i - 1] in "-="):
            j = i + 1
            if j < n and texto[j] == ">":
                j += 1
            if j < n and texto[j] == "|":
                j += 1
            if j < n and texto[j] == "(":
                i = j
                continue
            if j < n and texto[j] == "&":
                k = j + 1
                if k < n and (texto[k].isdigit() or texto[k] == "-"):
                    i = k + 1
                    continue
                j = k
            alvo = _first_token(texto[j:])
            if alvo:
                alvos.append(alvo.strip("'\""))
            i = j
            continue
        i += 1
    if aspa:
        alvos.extend(_redirect_targets(texto[pos_aspa + 1:]))
    return alvos


def _extract_write_targets(command: str) -> list[str]:
    """So os tokens que sao de fato ALVO de escrita: destino de `>`/`>>` (nunca `2>&1`/`>&N`,
    duplicacao de descritor), `tee <alvo>`, ultimo argumento (ou `-Destination`/`-Path`) de
    cp/mv/rm/copy/move/Copy-Item/Move-Item/Remove-Item, `-Path`/`-FilePath` (ou 1o posicional) de
    Out-File/Set-Content/Add-Content/Clear-Content/Tee-Object, `-Path` de New-Item (so quando cria
    ARQUIVO: tem -Value ou nao e -ItemType Directory), 1o argumento de [IO.File]::Write* /
    [System.IO.File]::Write*, e o ultimo argumento nao-flag de `sed -i`. Leitura (cat, grep, python
    lendo o arquivo) nunca aparece aqui - so o ALVO real de escrita (TASK-824)."""
    command = _sem_corpo_heredoc(command)  # o corpo do heredoc e TEXTO, nao comando (P2-9)
    alvos: list[str] = _redirect_targets(command)
    for m_iofile in _IOFILE_WRITE_RE.finditer(command):
        alvos.append(m_iofile.group(1).strip("'\""))
    for clausula in _SPLIT_CLAUSULAS_RE.split(command):  # inclui linha nova (P1-1)
        c = clausula.strip()
        if not c:
            continue
        m_tee = re.match(rf"tee\b\s+(?:-a\s+)?({_QUOTED_OR_TOKEN})", c, re.IGNORECASE)
        if m_tee:
            alvos.append(m_tee.group(1).strip("'\""))
            continue
        if _CP_RE.match(c):
            # so o DESTINO e alvo de escrita - -Path/-LiteralPath aqui e a origem, so leitura
            m_dest = re.search(rf"-Destination\s+({_QUOTED_OR_TOKEN})", c, re.IGNORECASE)
            if m_dest:
                alvos.append(m_dest.group(1).strip("'\""))
            else:
                nao_flag = [p for p in c.split()[1:] if not p.startswith("-")]
                if nao_flag:
                    alvos.append(nao_flag[-1].strip("'\""))
            continue
        if _MV_RE.match(c):
            # mover apaga a origem - origem e destino contam como alvo de escrita.
            # TASK-824 (conserto): todo argumento que nao e flag conta SEMPRE como alvo (origem
            # ou destino, os dois sao escrita), somado aos valores de -Destination/-Path -
            # forma mista (um posicional + uma flag) tambem precisa marcar o posicional.
            m_dest = re.search(rf"-Destination\s+({_QUOTED_OR_TOKEN})", c, re.IGNORECASE)
            m_origem = re.search(rf"-(?:Path|LiteralPath)\s+({_QUOTED_OR_TOKEN})", c, re.IGNORECASE)
            if m_dest:
                alvos.append(m_dest.group(1).strip("'\""))
            if m_origem:
                alvos.append(m_origem.group(1).strip("'\""))
            nao_flag = [p for p in c.split()[1:] if not p.startswith("-")]
            alvos.extend(p.strip("'\"") for p in nao_flag)
            continue
        if _RM_RE.match(c):
            # remover e destrutivo - todo -Path/-LiteralPath e todo posicional e alvo
            for m_path in re.finditer(rf"-(?:Path|LiteralPath)\s+({_QUOTED_OR_TOKEN})", c, re.IGNORECASE):
                alvos.append(m_path.group(1).strip("'\""))
            nao_flag = [p for p in c.split()[1:] if not p.startswith("-")]
            alvos.extend(p.strip("'\"") for p in nao_flag)
            continue
        if _OUTFILE_SETCONTENT_RE.match(c):
            m_path = re.search(rf"-(?:Path|FilePath)\s+({_QUOTED_OR_TOKEN})", c, re.IGNORECASE)
            if m_path:
                alvos.append(m_path.group(1).strip("'\""))
            else:
                nao_flag = [p for p in c.split()[1:] if not p.startswith("-")]
                if nao_flag:
                    alvos.append(nao_flag[0].strip("'\""))
            continue
        if _NEWITEM_RE.match(c):
            m_itemtype = re.search(r"-ItemType\s+(\S+)", c, re.IGNORECASE)
            tem_valor = re.search(r"-Value\s+", c, re.IGNORECASE) is not None
            e_diretorio = bool(m_itemtype) and m_itemtype.group(1).strip("'\"").lower() in ("directory", "dir")
            if e_diretorio and not tem_valor:
                continue  # cria pasta vazia - nunca escreve dentro de um arquivo do kernel
            m_path = re.search(rf"-Path\s+({_QUOTED_OR_TOKEN})", c, re.IGNORECASE)
            if m_path:
                alvos.append(m_path.group(1).strip("'\""))
            else:
                nao_flag = [p for p in c.split()[1:] if not p.startswith("-")]
                if nao_flag:
                    alvos.append(nao_flag[0].strip("'\""))
            continue
        if _SED_INPLACE_RE.match(c):
            partes = c.split()
            tem_inplace = any(p.startswith("-i") for p in partes[1:])
            if tem_inplace:
                nao_flag = [p for p in partes[1:] if not p.startswith("-")]
                if nao_flag:
                    alvos.append(nao_flag[-1].strip("'\""))
    return alvos

# so artifacts/<task_id>/ isenta a 4a negacao, e so quando o proprio PostToolUse ja marcou
# no ledger que um sub-agente escreveu naquele task_id (nao mais /artifacts/ inteiro).
ARTIFACT_TASK_RE = re.compile(r"/artifacts/(TASK-\d+)/", re.IGNORECASE)
NEGATION4_COORDINATION_EXEMPT = "/artifacts/coordination/"


# achado do CEO, 24/09/2026: a FONTE do motor (a oficina, clients/alia-flow-lab/) nunca e o
# kernel PROTEGIDO - e exatamente onde a lei manda o kernel EVOLUIR (fonte -> migrate.py ->
# instancia). Proteger a fonte pelo mesmo nome de arquivo do kernel da instancia travava a
# propria evolucao do motor pelo caminho certo (so sobrava editar direto na instancia, o
# atalho que a lei proibe). A protecao vale para o kernel da INSTANCIA (raiz do studio, v2/ da
# instancia, engine/ da instancia) - nunca para a fonte.
SOURCE_PATH_MARKER = "/clients/alia-flow-lab/"


def _is_source_path(path: str) -> bool:
    p = "/" + _norm(path.strip().strip("'\"")).lower().lstrip("/")
    return SOURCE_PATH_MARKER in p


# PULSO (Operacao Deep, TASK-847): so o proprio hook (Stop -> pulso.recompute) escreve o
# arquivo; Write/Edit/Bash/PowerShell da sessao contra pulso.json e sempre negado. Basename puro
# (mesmo estilo de KERNEL_FILES) - o nome e distintivo o bastante para nao colidir com outro
# arquivo legitimo.
def _is_pulso_write_target(path: str) -> bool:
    basename = _norm(path).lower().rsplit("/", 1)[-1]
    return basename == "pulso.json"


def _is_kernel_path(path: str) -> bool:
    if _is_source_path(path):
        return False
    p = _norm(path.strip().strip("'\"")).lower()
    pn = "/" + p.lstrip("/")  # 2.1.3 (P1-2): `engine/x.md` relativo tambem e kernel
    if "/engine/" in pn or pn.endswith("/engine"):
        return True
    basename = p.rsplit("/", 1)[-1]
    if basename in KERNEL_FILES:
        return True
    # config do host e scripts de skill sao gravaveis pelo
    # agente e rodam como hook - mexer neles e mexer na propria trava.
    if basename.startswith("settings") and basename.endswith(".json") and pn.rsplit("/", 2)[-2] == ".claude":
        return True
    if "/.claude/skills/" in pn and "/scripts/" in pn.split("/.claude/skills/", 1)[1]:
        return True
    return False


def _bash_targets_kernel(command: str, cwd: str | None = None) -> bool:
    """Bash grava em engine/ ou num arquivo do kernel sem passar por Write/Edit (achado da
    revisao independente): confere so os ALVOS DE ESCRITA extraidos por
    _extract_write_targets - nunca menciona de leitura (cat, grep, python lendo o kernel)
    em outro trecho do mesmo comando."""
    return any(_is_kernel_path(_com_cwd(alvo, cwd)) for alvo in _extract_write_targets(command))


_HEREDOC_RE = re.compile(r"<<-?\s*['\"]?\w+")
_INLINE_WRITE_CMD_RE = re.compile(r"(?i)^(echo|printf|write-output|write-out|set-content|add-content|out-file)\b")


def _bash_carries_inline_content(command: str) -> bool:
    """True quando o comando carrega TEXTO INLINE (nao so um caminho de origem/destino): heredoc
    (`<<EOF`), ou clausula que comeca com echo/printf/Write-Output/Set-Content/Add-Content/
    Out-File. Escopo deliberadamente estreito (achado do revisor LATTICE, R2): so cobre o caso em
    que o CONTEUDO viaja dentro do proprio comando; download/copia de arquivo binario ou ja
    existente no disco fica fora - a prova periodica de proof/check.py cobre a superficie depois."""
    if _HEREDOC_RE.search(command):
        return True
    for clausula in _SPLIT_CLAUSULAS_RE.split(command):
        if _INLINE_WRITE_CMD_RE.match(clausula.strip()):
            return True
    return False


_HEREDOC_BODY_RE = re.compile(r"<<-?\s*['\"]?(\w+)['\"]?[^\n]*\n(.*?)(?:\n\s*\1\b|\Z)", re.DOTALL)
_SETCONTENT_FAMILY_RE = re.compile(r"(?i)^(set-content|add-content|out-file)\b")
_CLAUSULA_SPLIT_RE = re.compile(r"(?<![0-9&])[;&]+|\n|(?<!\|)\|(?!\|)")


def _ate_redirecionamento(texto: str) -> str:
    """Corta `texto` no primeiro `>`/`>>` fora de aspas (o que vem depois e o ALVO, nao conteudo)."""
    aspa = ""
    for i, ch in enumerate(texto):
        if aspa:
            if ch == aspa:
                aspa = ""
        elif ch in "'\"":
            aspa = ch
        elif ch == ">" and not (i > 0 and texto[i - 1] == "&") and texto[i + 1:i + 2] != "&":
            return texto[:i]
    return texto


def _inline_content_text(command: str) -> str:
    """So o TEXTO ESCRITO pelo comando: corpo de heredoc, argumento
    de echo/printf/Write-Output (ate o redirecionamento), `-Value` de Set-Content/Add-Content/
    Out-File e o que vem por pipe para eles. O resto (`cd <estudio> &&`, caminhos de origem/destino)
    nunca entra - o caminho do estudio num `cd` e legitimo, so o conteudo que vai pro arquivo vaza."""
    partes: list[str] = [m.group(2) for m in _HEREDOC_BODY_RE.finditer(command)]
    resto = _HEREDOC_BODY_RE.sub(lambda m: m.group(0).split("\n", 1)[0], command)
    clausulas = [c.strip() for c in _CLAUSULA_SPLIT_RE.split(resto)]
    for i, c in enumerate(clausulas):
        if not c:
            continue
        m_cmd = _INLINE_WRITE_CMD_RE.match(c)
        if m_cmd:
            corpo = c[m_cmd.end():]
            if _SETCONTENT_FAMILY_RE.match(c):
                m_val = re.search(r"(?i)-Value\s+(.*)$", corpo)
                corpo = m_val.group(1) if m_val else ""
            partes.append(_ate_redirecionamento(corpo))
            continue
        prox = clausulas[i + 1] if i + 1 < len(clausulas) else ""
        if prox and (_SETCONTENT_FAMILY_RE.match(prox) or re.match(r"(?i)^tee\b", prox)):
            partes.append(_ate_redirecionamento(c))
    return "\n".join(partes)


_TASK_CLOSE_RE = re.compile(r"(?i)\btask\.py\b.*?\bclose\b")
_REGISTER_DONE_RE = re.compile(r"(?i)\bregister-task\.ps1\b.*?-Status\s+['\"]?done\b")
_ARTIFACT_ARG_RE = re.compile(rf"(?i)(?:--artifact|-Artifact)[\s=]+({_QUOTED_OR_TOKEN})")


def _artifacts_que_nao_existem(command: str, event: dict) -> list[str]:
    """fechar Task exige artifact que EXISTA. Itens
    separados por `;`; `http(s)://` e o prefixo `ext:` (repo externo, declarado) valem sem disco.
    Resolve contra o cwd do evento e a raiz do projeto. So olha `task.py close` e
    `register-task.ps1 -Status done` - abrir/atualizar Task nunca e barrado."""
    if not (_TASK_CLOSE_RE.search(command) or _REGISTER_DONE_RE.search(command)):
        return []
    m = _ARTIFACT_ARG_RE.search(command)
    if not m:
        return []  # sem --artifact o proprio task.py recusa (L65/L76); aqui so o que cita e nao existe
    bases = [b for b in (event.get("cwd"), _project_dir(), os.getcwd()) if b]
    faltam: list[str] = []
    for item in m.group(1).strip("'\"").split(";"):
        item = item.strip()
        if not item or item.lower().startswith(("http://", "https://", "ext:")):
            continue
        if not any(os.path.exists(item if os.path.isabs(item) else os.path.join(b, item)) for b in bases):
            faltam.append(item)
    return faltam


def _has_secret(text: str) -> bool:
    return any(p.search(text or "") for p in SECRET_PATTERNS)


def _is_client_write_without_delegation(event: dict, path: str) -> bool:
    p = "/" + _norm(path.strip().strip("'\"")).lower().lstrip("/")
    m = re.search(r"/clients/([a-z0-9\-]+)/", p)
    if not m:
        return False
    client_id = m.group(1)
    if NEGATION4_COORDINATION_EXEMPT in p:
        return False
    m_artifact = ARTIFACT_TASK_RE.search(p)
    if m_artifact and _artifact_marked_by_subagent(m_artifact.group(1).upper(), client_id):
        return False
    if event.get("_is_subagent"):
        # a propria sessao delegada (Agent/Task <id>-*) escrevendo no proprio
        # Client nunca e negada; a negacao e so sobre a SESSAO PRINCIPAL.
        return False
    session_id = event.get("session_id")
    # 2.1.3 (P0-6): a liberacao expressa do CEO (direto.json) tambem destrava ESTA guarda; sem isso o
    # CEO liberava a sessao principal na muralha e a guarda 4 seguia negando: acao sem ator.
    if _direct_grant_valid(session_id):
        return False
    return not ledger.session_has_agent_prefix(_ledger_path(), session_id, client_id + "-")


def _artifact_marked_by_subagent(task_id: str, client_id: str | None = None) -> bool:
    """True se ja existe um marcador `artifact_write` no ledger (gravado pelo proprio
    PostToolUse quando um sub-agente escreveu em artifacts/<task_id>/) para este task_id. Marcador com
    Client gravado so vale para esse Client (2.1.3); o antigo, sem Client, segue valendo."""
    for ev in ledger.read_events(_ledger_path()):
        if ev.get("event") == "artifact_write" and ev.get("task_id") == task_id:
            if client_id and ev.get("client") and ev.get("client") != client_id:
                continue
            return True
    return False


def handle_post_write_artifact_marker(event: dict) -> None:
    """PostToolUse de Write/Edit em artifacts/<task_id>/: grava o marcador que a 4a negacao
    consulta depois. So marca quando o PreToolUse ja deixou passar (PostToolUse so roda se o
    Write/Edit foi de fato executado)."""
    if not event.get("agent_id"):
        return  # 2.1.3: so a escrita de SUB-AGENTE marca; a da sessao principal nunca se auto-isenta
    tool_input = event.get("tool_input") or {}
    path = _norm(tool_input.get("file_path", ""))
    m = ARTIFACT_TASK_RE.search(path.lower())
    if not m:
        return
    task_id = m.group(1).upper()
    m_cli = re.search(r"/clients/([a-z0-9\-]+)/", "/" + path.lower().lstrip("/"))
    ledger.append_event(_ledger_path(), {
        "event": "artifact_write",
        "session_id": event.get("session_id"),
        "agent_id": event.get("agent_id"),
        "task_id": task_id,
        "client": m_cli.group(1) if m_cli else None,
        "path": path,
    })


CHECK_MARKER_MAX_AGE_S = 30 * 60  # 30 minutos (mandato do CEO, 24/09/2026)


def _current_git_head(repo_dir: str) -> str | None:
    import subprocess  # tardio: so a trava de publicacao usa; no topo custava ~10-80 ms em TODO spawn
    try:
        proc = subprocess.run(["git", "rev-parse", "HEAD"], cwd=repo_dir,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except OSError:
        return None
    if proc.returncode != 0:
        return None
    return proc.stdout.decode("utf-8", "replace").strip()


def _git_toplevel(pasta: str) -> str | None:
    import subprocess  # tardio (ver _current_git_head)
    try:
        proc = subprocess.run(["git", "rev-parse", "--show-toplevel"], cwd=pasta,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except (OSError, NotADirectoryError):
        return None
    return proc.stdout.decode("utf-8", "replace").strip() or None if proc.returncode == 0 else None


def _mesmo_caminho(a: str, b: str) -> bool:
    return os.path.normcase(os.path.realpath(a)) == os.path.normcase(os.path.realpath(b))


def _usa_git(command: str) -> bool:
    for c in _SPLIT_CLAUSULAS_RE.split(_sem_corpo_heredoc(command)):
        t = _cmd_tokens(c)
        if t and _base_cmd(t[0]) == "git":
            return True
    return False


def _check_marker_valido(command: str = "", cwd: str | None = None) -> bool:
    """[MEDIDO, achado do CEO 24/09/2026] A negacao antiga exigia ALIA_CHECK_MARKER_PATH -
    ninguem setava essa variavel de ambiente fora dos proprios testes, entao TODO `git push` a
    partir do studio vivo nascia negado para sempre. Agora o marcador vive num caminho FIXO
    (paths.check_marker_path(), gravado por proof/check.py quando fecha verde) e libera a
    publicacao so se: (1) o arquivo existe, (2) tem menos de 30 minutos, e (3) quando o
    marcador registrou um HEAD de git, o HEAD atual do repo bate com o HEAD gravado (prova de
    que o check verde foi contra O QUE VAI SER publicado, nao contra um commit velho)."""
    marker = paths.check_marker_path()
    if not os.path.exists(marker):
        return False
    try:
        idade_s = time.time() - os.path.getmtime(marker)
    except OSError:
        return False
    if idade_s > CHECK_MARKER_MAX_AGE_S or idade_s < 0:
        return False
    try:
        with open(marker, "r", encoding="utf-8") as fh:
            dados = json.load(fh)
    except (OSError, json.JSONDecodeError):
        return False
    # TASK-845 (E01): marcador sem HEAD nao libera nada; o HEAD gravado tem que bater com o
    # HEAD atual do repo alvo (campo "repo" do marcador, ou a raiz do studio quando ausente).
    head_gravado = dados.get("head")
    if not head_gravado:
        return False
    repo_dir = dados.get("repo") or os.path.dirname(os.path.dirname(marker))
    if _current_git_head(repo_dir) != head_gravado:
        return False
    # 2.1.3: o repo nunca pode estar numa VERSION POSTERIOR a que o check verde mediu (anterior e o caso normal:
    # ele so recebe a nova pelo proprio publicar, que confere o VERSION commitado depois).
    ver_marc = dados.get("version")
    if ver_marc:
        try:
            with open(os.path.join(repo_dir, "VERSION"), "r", encoding="utf-8") as fv:
                ver_repo = fv.read().strip()
            if tuple(int(x) for x in ver_repo.split(".")) > tuple(int(x) for x in str(ver_marc).split(".")):
                return False
        except (OSError, ValueError):
            return False
    # 2.1.3 (P1-7): o check verde vale para o repo que ELE mediu. `git push` de OUTRO repo (cd/-C/cwd)
    # nunca passa por um marcador que foi gravado para o produto.
    if command and _usa_git(command):
        alvo = _repo_do_push(command, cwd or _project_dir())
        topo = _git_toplevel(alvo) if alvo and os.path.isdir(alvo) else None
        if topo and not _mesmo_caminho(topo, repo_dir):
            return False
    return True


# ---------------------------------------------------------------------------
# MURO DE DELEGACAO (mandato do CEO, 30/09/2026) - a Alia na SESSAO PRINCIPAL so delega.
# Distincao: PreToolUse carrega agent_id so quando a chamada nasce num sub-agente; sem agent_id
# = sessao principal. Ai Write/Edit/NotebookEdit e Bash/PowerShell de escrita so passam em infra
# liberada (memoria, docs/ops, state.json, task corrente, briefs) ou com a LIBERACAO do CEO.
# Liberacao: <studio>/.alia/direto.json {session_id, granted_at, expires_at, ceo_quote}, nasce SO
# do hook UserPromptSubmit (handle_user_prompt_submit) quando a mensagem do CEO traz o pedido
# expresso; grava evento direct_grant no ledger; vale 1 sessao e no maximo 60 min. A sessao
# principal nunca a cria: qualquer comando dela que cite direto.json e negado pelo proprio muro. Interruptor: ALIA_DELEGATION_WALL_OFF=1 ou
# .claude/delegation-wall.off (padrao end-lock.off/graph-gate.off; desliga so o bloqueio).
# ---------------------------------------------------------------------------

WALL_ALLOW_FRAGMENTS = ("/memory/", "/docs/ops/", "/briefs/", "/artifacts/coordination/")
WALL_DIRECT_MAX_S = 60 * 60
_WALL_NULL_SINKS = ("/dev/null", "nul", "$null")
_WALL_INTERP_RE = re.compile(r"(?i)\b(python3?|py|node|pwsh|powershell)(\.exe)?\b[^\n]*"
                             r"(\s-c\b|\s-e\b|\s-command\b|<<|\s-\s*<)")
# 2.1.3 (P1-4): powershell -EncodedCommand/-enc/-ec esconde o script em base64 (nada de token de escrita
# visivel): vale como script inline que escreve. `-ExecutionPolicy` NAO casa (o `x` quebra o -e\w*).
_WALL_ENCODED_RE = re.compile(r"(?i)\b(?:pwsh|powershell)(?:\.exe)?\b[^\n]*?\s-e(?:c|n\w*)?(?=\s|$)")
_SCRIPT_EXT = (".py", ".js", ".mjs", ".cjs", ".ps1", ".sh")
_SCRIPT_ALLOW_RE = re.compile(r"(?:^|/)(?:v2/(?:bin|proof|flow)|scripts|\.claude/skills/[^/]+/scripts)/")


def _wall_script_fora_da_allowlist(command: str, cwd: str | None) -> bool:
    """`python x.py`/`node x.js`/`pwsh -File x.ps1`/`bash x.sh` rodando script FORA da allowlist (v2/bin,
    v2/proof, v2/flow, scripts/, skills/*/scripts/, e a infra liberada): o arquivo pode escrever o que
    quiser e o texto do comando nao mostra (P1-4). `python -m`/`-c` ficam com a regra inline."""
    for c in _SPLIT_CLAUSULAS_RE.split(_sem_corpo_heredoc(command)):
        toks = _cmd_tokens(c)
        if not toks or _base_cmd(toks[0]) not in _INTERPRETES:
            continue
        script = None
        for a in toks[1:]:
            low = a.lower()
            if low in ("-c", "-command", "-m", "-e"):
                break
            if a.startswith("-"):
                continue
            if low.endswith(_SCRIPT_EXT):
                script = a
                break
        if script is None:
            continue
        alvo = "/" + _norm(_com_cwd(script, cwd)).lower().lstrip("/")
        if not (_SCRIPT_ALLOW_RE.search(alvo) or _wall_path_allowed(_com_cwd(script, cwd))):
            return True
    return False
_WALL_WRITE_TOKENS_RE = re.compile(r"(?i)(open\s*\([^)]*['\"][wa]|write_text|write_bytes|writefile|"
                                   r"fs\.\w*write|set-content|add-content|out-file|\.write\()")


def _wall_off() -> bool:
    if os.environ.get("ALIA_DELEGATION_WALL_OFF") == "1":
        return True
    return os.path.exists(os.path.join(_project_dir(), ".claude", "delegation-wall.off"))


def _direct_grant_path() -> str:
    return os.path.join(paths.studio_root(), ".alia", "direto.json")


def _direct_grant_valid(session_id: str | None) -> bool:
    try:
        with open(_direct_grant_path(), "r", encoding="utf-8") as fh:
            g = json.load(fh)
        # 2.1.3: o arquivo guarda UMA liberacao por sessao em "grants" (duas sessoes nao se sobrescrevem);
        # o formato antigo (liberacao solta no topo) segue valendo.
        g = ((g.get("grants") or {}).get(session_id) if session_id else None) or g
        now = time.time()
        return (bool(session_id) and g.get("session_id") == session_id
                and len(str(g.get("ceo_quote") or "").strip()) >= 5
                and now < float(g["expires_at"])
                and float(g["expires_at"]) - float(g["granted_at"]) <= WALL_DIRECT_MAX_S)
    except (OSError, ValueError, KeyError, TypeError):
        return False


def _wall_path_allowed(path: str) -> bool:
    p = "/" + _norm(path.strip().strip("'\"")).lower().lstrip("/")
    if p.lstrip("/") in tuple(x.lstrip("/") for x in _WALL_NULL_SINKS):  # /dev/null e NUL nunca sao alvo de escrita
        return True
    if any(a in p for a in WALL_ALLOW_FRAGMENTS):
        return True
    base = p.rsplit("/", 1)[-1]
    return base in ("state.json", os.path.basename(paths.current_task_path()).lower())


def _wall_target_hint(path: str) -> str:
    m = re.search(r"/clients/([a-z0-9\-]+)/", _norm(path).lower())
    if m and m.group(1) == "alia-flow-lab":
        return "o motor: acione alia-flow-lab-nexus (Gateway), que roteia ao Specialist dono (WARDEN hooks/prova, GAUGE contexto, CANON leis...)"
    if m:
        return f"acione o Gateway do Client {m.group(1)} (agente {m.group(1)}-*), que roteia ao Specialist dono"
    return "acione o Specialist dono do dominio via Agent/Task (Gateway do Client em caso de duvida)"


def _wall_check(event: dict) -> dict | None:
    """Devolve _deny(...) quando a SESSAO PRINCIPAL tenta escrever fora da infra liberada."""
    if event.get("_is_subagent") or _wall_off():
        return None
    tool = event.get("tool_name")
    ti = event.get("tool_input") or {}
    if tool in ("Bash", "PowerShell") and re.search(r"(?i)direto\.json|direto\.py", str(ti.get("command") or "")):
        return _deny("muralha de delegacao: a sessao principal nao cria a propria liberacao - so o "
                     "pedido expresso do CEO na mensagem dele (hook de prompt) libera.")
    cwd = event.get("cwd")
    if tool in ("Write", "Edit", "NotebookEdit", "MultiEdit"):
        alvos = [ti.get("file_path") or ti.get("notebook_path") or ""]
        inline = False
    else:
        cmd = str(ti.get("command") or "")
        alvos = [_com_cwd(a, cwd) for a in _extract_write_targets(cmd)]
        # passagem: o proprio comando de publicar/propagar, sem encadear nada, nao e "script inline
        # que escreve arquivo" (invocado via -Command). Alvo de escrita explicito segue valendo.
        passa = bool(_WALL_PASS_RE.fullmatch(cmd.strip()) and not _WALL_PASS_BAD_ARG_RE.search(cmd))
        inline = not passa and bool(
            (_WALL_INTERP_RE.search(cmd) and _WALL_WRITE_TOKENS_RE.search(cmd))
            or _WALL_ENCODED_RE.search(cmd) or _wall_script_fora_da_allowlist(cmd, cwd))
    fora = [a for a in alvos if not _wall_path_allowed(a)]
    if not fora and not inline:
        return None
    if _direct_grant_valid(event.get("session_id")):
        return None
    alvo = fora[0] if fora else "(script inline que escreve arquivo)"
    return _deny(
        f"muralha de delegacao: a sessao principal so delega - escrita em {alvo} negada. "
        f"Quem faz: {_wall_target_hint(alvo)}. Se o CEO pediu EXPRESSAMENTE que voce faca e voce "
        "confirmou, o CEO precisa pedir isso na mensagem dele (o hook de prompt libera, vale esta "
        "sessao, max 60 min) - voce nao se libera sozinha.")


_DIRECT_ASK_RE = re.compile(
    r"(?i)(fa[cz]a|faz|executa|execute|resolve|resolva|mexe|mexa)\s+(voce|vc)\s+mesm[ao]"
    r"|(pode|quero que)\s+(voce|vc)\s+(mesm[ao]\s+)?(faz|fazer|execute|executar|mexer)"
    r"|(?:^|[.!?\n]\s*)sem\s+delegar"  # 2.1.3: "ela fez sem delegar" e queixa, nao pedido
    r"|(?<!ela )(?<!ele )(?<!alia )(?<!voce )(?<!vc )\b(?:faz|faca|execute|executa|resolve|resolva|mexe|mexa|rode|roda|edite|edita|escreva|escreve)\b[^.!?\n]{0,40}\bsem\s+delegar"
    r"|\b(?:quero|pode|precisa|preciso)\b[^.!?\n]{0,30}\bsem\s+delegar"
    r"|nao\s+delegue|libera(r)?\s+(a\s+)?alia\s+(pra|para)\s+(fazer|executar)")


_HARNESS_PROMPT_MARKERS = ("<task-notification>", "[system notification", "<system-reminder>")


def handle_user_prompt_submit(event: dict) -> dict:
    """Unica origem da liberacao do muro: o prompt do CEO traz o pedido expresso. Devolve contexto
    mandando a Alia CONFIRMAR ao CEO que vai executar direto."""
    import unicodedata
    prompt = str(event.get("prompt") or "")
    # 2.1.2 (TASK-862, caso C): notificacao do harness (tarefa em segundo plano) nao e mensagem do
    # CEO, e frase entre aspas/crase/citacao (>) e citacao, nao pedido. O regex abaixo nao mudou.
    if any(m in prompt.lower() for m in _HARNESS_PROMPT_MARKERS):
        return {}
    pedido = re.sub(r'(?m)"[^"\n]*"|“[^”]*”|`[^`]*`|^\s*>.*$', " ", prompt)
    norm = unicodedata.normalize("NFKD", pedido).encode("ascii", "ignore").decode("ascii")
    sid = event.get("session_id")
    if not sid or not _DIRECT_ASK_RE.search(norm):
        return {}
    agora = time.time()
    grant = {"session_id": sid, "granted_at": agora, "expires_at": agora + WALL_DIRECT_MAX_S,
             "ceo_quote": prompt.strip()[:300]}
    gp = _direct_grant_path()
    with trava.trava(gp):
        try:
            with open(gp, "r", encoding="utf-8") as fh:
                atual = json.load(fh)
            grants = dict((atual.get("grants") or {}) if isinstance(atual, dict) else {})
        except (OSError, json.JSONDecodeError):
            grants = {}
        grants = {k: v for k, v in grants.items() if isinstance(v, dict) and float(v.get("expires_at") or 0) > agora}
        grants[sid] = grant
        trava.gravar_atomico(gp, json.dumps({**grant, "grants": grants}, ensure_ascii=False))
    ledger.append_event(_ledger_path(), {"event": "direct_grant", "session_id": sid,
                                         "ceo_quote": grant["ceo_quote"], "expires_at": grant["expires_at"]})
    return {"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext":
            "[MURALHA] O CEO pediu para voce executar direto. Confirme a ele numa frase que vai "
            "executar sozinha; a liberacao vale esta sessao por ate 60 min."}}


_MARCADORES_PROPRIOS = ("direto.json", "check-ok.json")


def _e_marcador_proprio(path: str) -> bool:
    return _norm((path or "").strip().strip("'\"")).lower().rsplit("/", 1)[-1] in _MARCADORES_PROPRIOS


def _comando_forja_marcador(command: str, cwd: str | None) -> bool:
    """2.1.3 (P1-7): .alia/check-ok.json e .alia/direto.json (a liberacao do CEO e o check verde) so nascem
    do proprio check.py e do hook de prompt. NINGUEM os forja por Bash/PowerShell, sub-agente inclusive:
    alvo de escrita com esse nome, ou o nome junto de gravacao inline. So LER nao e barrado."""
    if not re.search(r"(?i)(?:direto|check-ok)\.json", command):
        return False
    if any(_e_marcador_proprio(a) for a in _extract_write_targets(command)):
        return True
    return bool(_WALL_WRITE_TOKENS_RE.search(command) or re.search(r"(?i)\bsed\b[^\n]*\s-i", command))


def _layout_deny(event: dict) -> dict | None:
    """Portao de pastas (TASK-870, v2/lib/layout.py): bloqueia SO caminho NOVO fora do manifesto, com a
    mensagem de onde ele deveria morar. Existente nunca bloqueia. Falha ABERTA: erro aqui vira o evento
    `layout_excecao` no ledger e a escrita segue."""
    try:
        import layout  # tardio: so quem escreve paga
        studio = paths.studio_root()
        if layout.desligado(studio):
            return None
        ti = event.get("tool_input") or {}
        cwd = event.get("cwd")
        if event.get("tool_name") in ("Bash", "PowerShell"):
            alvos = [_com_cwd(a, cwd) for a in _extract_write_targets(str(ti.get("command") or ""))]
        else:
            alvos = [_com_cwd(str(ti.get("file_path") or ti.get("notebook_path") or ""), cwd)]
        for a in alvos:
            a = a.strip().strip("'\"")
            if not a or re.search(r"[$*?%`]|^~", a):  # variavel, glob ou ~: nao resolve com seguranca
                continue
            v = layout.violacao_de_caminho(a, studio)
            if v:
                return _deny(v["msg"])
    except Exception as exc:  # noqa: BLE001 - fail-open registrado
        try:
            ledger.append_event(_ledger_path(), {"event": "layout_excecao", "error": str(exc)[:300],
                                                 "tool": event.get("tool_name")})
        except Exception:
            pass
    return None


def handle_pretooluse_guard(event: dict) -> dict:
    tool_name = event.get("tool_name")
    tool_input = event.get("tool_input") or {}
    cwd = event.get("cwd")
    # sessao principal x sub-agente: PreToolUse/PostToolUse carregam agent_id
    # quando a chamada nasce dentro de um sub-agente (campo comum documentado
    # na doc oficial de hooks). Sem agent_id = sessao principal.
    event["_is_subagent"] = bool(event.get("agent_id"))
    if tool_name in ("Write", "Edit", "NotebookEdit", "MultiEdit"):
        _fp = tool_input.get("file_path") or tool_input.get("notebook_path") or ""
        if _e_marcador_proprio(_fp):
            return _deny("guard: .alia/check-ok.json e .alia/direto.json nao se escrevem por ferramenta - "
                         "so o check.py (marcador) e o pedido expresso do CEO (liberacao) os criam")
    elif tool_name in ("Bash", "PowerShell"):
        if _comando_forja_marcador(str(tool_input.get("command") or ""), cwd):
            return _deny("guard: .alia/check-ok.json e .alia/direto.json nao se forjam por comando - "
                         "so o check.py (marcador) e o pedido expresso do CEO (liberacao) os criam")
    if tool_name in ("Write", "Edit", "NotebookEdit", "MultiEdit", "Bash", "PowerShell"):
        _negado_muralha = _wall_check(event)
        if _negado_muralha:
            return _negado_muralha

    if tool_name in ("Write", "Edit", "NotebookEdit", "MultiEdit"):
        path = tool_input.get("file_path") or tool_input.get("notebook_path") or ""
        content = str(tool_input.get("content") or tool_input.get("new_string")
                      or tool_input.get("new_source") or "")
        # MultiEdit (2.1.3): o texto novo de CADA edicao entra na varredura de segredo e identidade.
        for edit_extra in (tool_input.get("edits") or []):
            if isinstance(edit_extra, dict):
                content += "\n" + str(edit_extra.get("new_string") or "")
        if _is_kernel_path(path):
            return _deny("guard: escrita no kernel negada (AGENTS.md, CLAUDE.md, "
                         "CONTRACTS.md ou engine/)")
        if _is_pulso_write_target(path):
            return _deny("guard: escrita direta em pulso.json negada - so o hook "
                         "(Stop -> pulso.recompute) regrava o PULSO")
        if _has_secret(content) or _has_secret(path):
            return _deny("guard: segredo detectado no conteudo ou caminho")
        # TASK-841/842 (WARDEN): trava na ESCRITA - arquivo publicavel do motor (oficina
        # clients/alia-flow-lab/... ou repo do produto) nunca leva id de Client real, nome do
        # estudio do operador, ou caminho real da maquina do operador. Ver v2/lib/identity_guard.py.
        # CONSERTO (Gate do NEXUS, medido): o `path` NUNCA entra na varredura - todo caminho REAL
        # publicavel contem a pasta do usuario e/ou do estudio por construcao (e onde o arquivo
        # mora em disco), entao escanear o path derrubava QUALQUER escrita legitima com conteudo
        # limpo. O caminho so decide SE o alvo e publicavel (classify_target); a identidade so e
        # julgada pelo CONTEUDO que vai DENTRO do arquivo.
        alvo_publicavel = identity_guard.classify_target(_nome_longo(path.replace("\\", "/")) if path else path)
        if alvo_publicavel:
            vazamento = identity_guard.find_identity_leak(content)
            if vazamento:
                return _deny(
                    f"guard: identidade real vazando em arquivo publicavel do motor ({alvo_publicavel}) - "
                    f"{vazamento}. Use um nome generico; a evidencia real fica na pasta privada "
                    "(opportunities/)."
                )
        if _is_client_write_without_delegation(event, path):
            return _deny(
                "guard: Write/Edit em clients/<id>/ pela sessao principal sem "
                "Agent/Task <id>-* visto nesta sessao (herda delegation-gate L33/L45)"
            )
        return _layout_deny(event) or _no_decision()

    if tool_name in ("Bash", "PowerShell"):
        # PowerShell (TASK-824, achado do CEO 24/09/2026): o terminal nativo desta maquina
        # Windows passava sem nenhuma das 4 negacoes porque o guard so olhava "Bash". O campo
        # do evento e o mesmo (command), entao PowerShell recebe exatamente o mesmo tratamento.
        command = str(tool_input.get("command") or "")
        if _has_secret(command):
            return _deny("guard: segredo detectado no comando")
        _faltam_artifact = _artifacts_que_nao_existem(command, event)
        if _faltam_artifact:
            return _deny("guard: fechar Task exige artifact que EXISTA em disco - nao resolve: "
                         + "; ".join(_faltam_artifact) + " (repo externo: prefixo ext:)")
        if _bash_targets_kernel(command, cwd):
            return _deny("guard: Bash redireciona/copia para o kernel (AGENTS.md, "
                         "CLAUDE.md, CONTRACTS.md ou engine/) - negado")
        if any(_is_pulso_write_target(alvo) for alvo in _extract_write_targets(command)):
            return _deny("guard: Bash/PowerShell escrevendo em pulso.json negado - "
                         "so o hook (Stop -> pulso.recompute) regrava o PULSO")
        # TASK-841/842 (R2, achado do revisor LATTICE): Bash/PowerShell tambem escreve arquivo
        # sem passar por Write/Edit (heredoc, echo/Set-Content com texto inline). So confere
        # identidade quando ha ALVO PUBLICAVEL entre os alvos de escrita extraidos E o comando
        # carrega conteudo inline reconhecivel - cobertura deliberadamente PARCIAL (download,
        # copia binaria, redirecionamento de arquivo ja existente ficam de fora daqui); o resto
        # da superficie e coberto pela varredura periodica em proof/check.py, nunca so aqui. Ver
        # v2/lib/identity_guard.py (docstring) e v2/CONTRACTS.md.
        # CONSERTO (Gate do NEXUS, medido): o texto do ALVO (caminho) e removido do comando ANTES
        # de varrer - mesmo motivo do bloco Write/Edit acima, o caminho publicavel sempre contem
        # pasta do usuario/estudio por construcao; so o texto INLINE (heredoc/echo) e julgado.
        _alvos_escrita = [_com_cwd(a, cwd) for a in _extract_write_targets(command)]
        _alvos_publicaveis = [a for a in _alvos_escrita if identity_guard.classify_target(_nome_longo(a.replace("\\", "/")))]
        if _alvos_publicaveis and _bash_carries_inline_content(command):
            _texto_sem_alvo = _inline_content_text(command)
            for _alvo_pub in _alvos_publicaveis:
                for _forma_alvo in (_alvo_pub, f'"{_alvo_pub}"', f"'{_alvo_pub}'"):
                    _texto_sem_alvo = _texto_sem_alvo.replace(_forma_alvo, " ")
            _vazamento_bash = identity_guard.find_identity_leak(_texto_sem_alvo)
            if _vazamento_bash:
                _kind_bash = identity_guard.classify_target(_alvos_publicaveis[0])
                return _deny(
                    f"guard: identidade real vazando em comando que escreve arquivo publicavel do "
                    f"motor ({_kind_bash}) - {_vazamento_bash}. Use um nome generico; a evidencia "
                    "real fica na pasta privada (opportunities/)."
                )
        _negado_layout = _layout_deny(event)
        if _negado_layout:
            return _negado_layout
        if _comando_publica(command):
            if event["_is_subagent"]:
                return _deny("guard: especialista nunca publica (L70) - publicacao so pela "
                             "sessao principal, depois do check verde")
            if not _check_marker_valido(command, cwd):
                return _deny("guard: publicacao sem check (marcador de check ausente, "
                             "vencido ha mais de 30 min, ou HEAD divergente). Rode da raiz do "
                             "studio: python v2/proof/check.py --repo <caminho do repo a publicar> "
                             "(grava " + paths.check_marker_path() + " com o HEAD desse repo) e "
                             "repita o comando em ate 30 min, sem novo commit no repo.")
        return _no_decision()

    return _no_decision()


# ---------------------------------------------------------------------------
# Trava de fim (Stop, TASK-812) - bloqueia 1x quando a sessao tocou uma Task
# que segue sem gate_verdict. Evidencia SEMPRE do ledger (session_id e task_id
# gravados juntos por um evento real desta sessao), nunca do campo "session"
# do Task no state.json - Tasks nascidas por register-task.ps1 quase sempre
# tem esse campo vazio, e confiar nele bloquearia a sessao errada por causa de
# uma Task aberta que ela nunca tocou.
# ---------------------------------------------------------------------------

def _end_lock_off() -> bool:
    if os.environ.get("ALIA_END_LOCK_OFF") == "1":
        return True
    return os.path.exists(os.path.join(_project_dir(), ".claude", "end-lock.off"))


# ---------------------------------------------------------------------------
# Guarda de idioma (Stop, TASK-813, mandato do CEO 24/09/2026): a resposta final ao Operator
# tem que ser em portugues do Brasil - regra escrita no kernel nao segurou (a coordenadora
# respondeu em ingles varias vezes). Sem modelo: conta palavra de ligacao (stopword) EN contra
# PT na ULTIMA mensagem do assistente do transcript, ignorando bloco de codigo e
# caminho/URL (ambos citam token em ingles de forma legitima). Sinal fraco (poucas stopwords
# reconhecidas) falha ABERTO - nunca bloqueia por falta de dado.
# ---------------------------------------------------------------------------

_EN_STOPWORDS = {
    "the", "is", "are", "was", "were", "and", "but", "with", "this", "that",
    "these", "those", "have", "has", "had", "will", "would", "should", "could",
    "your", "not", "can", "for", "there", "here", "what", "when", "which",
    "about", "into", "than", "then", "them", "their", "been", "being", "does",
}
_PT_STOPWORDS = {
    "o", "a", "os", "as", "e", "ou", "mas", "com", "isso", "isto", "essa", "esse",
    "essas", "esses", "aquela", "aquele", "tem", "tinha", "vai", "voce", "seu",
    "sua", "eu", "nos", "eles", "elas", "nao", "pode", "para", "em", "no", "na",
    "ser", "se", "entao", "faz", "aqui", "ate", "que", "por", "uma", "um", "dos",
    "das", "ja", "so", "mais", "tambem", "sem", "foi", "sao", "como",
}
_CODE_BLOCK_RE = re.compile(r"```.*?```", re.DOTALL)
_PATH_OR_URL_RE = re.compile(r"(https?://\S+|(?:[A-Za-z]:)?[./\\][\w./\\-]*\w)")


def _texto_sem_codigo_e_caminho(texto: str) -> str:
    texto = _CODE_BLOCK_RE.sub(" ", texto)
    texto = _PATH_OR_URL_RE.sub(" ", texto)
    return texto


def _ultima_mensagem_assistente(transcript_path: str) -> str | None:
    if not transcript_path or not os.path.exists(transcript_path):
        return None
    ultima = None
    try:
        with open(transcript_path, "r", encoding="utf-8") as fh:
            for raw in fh:
                raw = raw.strip()
                if not raw:
                    continue
                try:
                    rec = json.loads(raw)
                except json.JSONDecodeError:
                    continue
                if rec.get("type") != "assistant":
                    continue
                msg = rec.get("message")
                if not isinstance(msg, dict):
                    continue
                content = msg.get("content")
                texto = ""
                if isinstance(content, str):
                    texto = content
                elif isinstance(content, list):
                    partes = [b.get("text", "") for b in content
                              if isinstance(b, dict) and b.get("type") == "text"]
                    texto = "\n".join(partes)
                if texto.strip():
                    ultima = texto
    except OSError:
        return None
    return ultima


def _resposta_predominante_em_ingles(texto: str) -> bool:
    limpo = _texto_sem_codigo_e_caminho(texto).lower()
    palavras = re.findall(r"[a-zà-ú]+", limpo)
    en = sum(1 for w in palavras if w in _EN_STOPWORDS)
    pt = sum(1 for w in palavras if w in _PT_STOPWORDS)
    if en + pt < 3:
        return False  # sinal fraco demais - falha aberto, nunca bloqueia por falta de dado
    return en > pt


# ---------------------------------------------------------------------------
# Aviso de entrega sem veredito (Stop, TASK-812/2.0.1, redesenhado apos objecoes do Canon/
# Gauge): NUNCA bloqueia (usa additionalContext, nao decision:block - nao aparece como erro
# pro Operator) e NUNCA varre o ledger inteiro (so o indice .idx.json, O(1), via
# ledger.session_last_post_agent). Dispara so quando: (a) nada em voo em background_tasks,
# (b) uma entrega de Specialist (post_agent) voltou NESTA sessao, (c) a Task dessa entrega
# segue sem gate_verdict, (d) esta entrega especifica ainda nao foi avisada (uma vez por
# entrega, nunca repete pro mesmo post_agent). Nunca olha Task de outra sessao/conversa - so
# a ULTIMA entrega desta sessao entra na conta.
# ---------------------------------------------------------------------------

def _aviso_entrega_sem_veredito(event: dict) -> str | None:
    if event.get("background_tasks"):
        return None  # algo ainda em voo - Stop nao interrompe antes de terminar
    session_id = event.get("session_id")
    if not session_id:
        return None
    entrega = ledger.session_last_post_agent(_ledger_path(), session_id)
    if not entrega or not entrega.get("task_id"):
        return None
    task_id = entrega["task_id"]
    seq = entrega.get("seq")

    # o estado nao e lido aqui - a espinha (`alia task pending`) diz se a Task segue sem veredito.
    # Qualquer falha (sem state.json, erro interno) devolve None: a trava de fim libera (falha aberta).
    codigo, res = _alia(["task", "pending", "--id", task_id, "--sem-divida"])
    if codigo != 0 or task_id not in (res.get("pendentes") or []):
        return None

    if seq is not None and ledger.delivery_already_notified(_ledger_path(), session_id, seq):
        return None
    if seq is not None:
        ledger.mark_delivery_notified(_ledger_path(), session_id, seq)
    # Operacao Deep (TASK-847): antes disso so existia o aviso de texto abaixo (additionalContext,
    # efemero). Agora tambem vira evento proprio no ledger - insumo de "pressao" do PULSO
    # (pulso.py, EVENTO_TASK_SEM_VEREDITO), tanto para "alia" quanto para o agent_type executor.
    import pulso  # noqa: E402 (import tardio - ver comentario no topo do arquivo)
    ledger.append_event(_ledger_path(), {
        "event": pulso.EVENTO_TASK_SEM_VEREDITO,
        "session_id": session_id,
        "task_id": task_id,
    })
    return (f"{task_id} voltou sem veredito do Gate - rode o Gate ou feche com veredito "
            "antes de encerrar.")


def handle_stop(event: dict) -> dict:
    # PULSO (Operacao Deep, TASK-847): recalcula e regrava a CADA Stop, sempre, independente de
    # qualquer interruptor de trava - so grava, nunca decide nada aqui. Envolvido em try/except:
    # um PULSO quebrado nunca prende o operador (mesmo espirito do resto deste dispatch).
    try:
        if _pulso_on():
            import pulso  # noqa: E402 (import tardio - ver comentario no topo do arquivo)
            pulso.recompute(_ledger_path(), paths.pulso_path())
    except Exception:
        pass

    # guarda de idioma (TASK-813) e independente do interruptor ALIA_END_LOCK_OFF/end-lock.off
    # - aquele interruptor e so da trava de fim (TASK-812, gate_verdict), um kill-switch
    # separado, nunca desliga a exigencia de portugues por engano.
    stop_hook_active = bool(event.get("stop_hook_active"))
    if not stop_hook_active:
        ultima = _ultima_mensagem_assistente(event.get("transcript_path"))
        if ultima and _resposta_predominante_em_ingles(ultima):
            return {"decision": "block",
                     "reason": "Resposta em ingles: reescreva em portugues do Brasil"}

    if _end_lock_off():
        return {}
    if stop_hook_active:
        # anti-laco: a 2a chamada do host (depois de um bloqueio de idioma) sempre deixa
        # parar - nunca dispara o aviso de entrega de novo na mesma volta.
        return {}

    aviso = _aviso_entrega_sem_veredito(event)
    if aviso:
        return {"hookSpecificOutput": {"hookEventName": "Stop", "additionalContext": aviso}}
    return {}


# ---------------------------------------------------------------------------
# Recuperacao pos-compactacao (SessionStart, TASK-839): a conversa compactada some do resumo,
# mas o .jsonl da sessao continua com o texto integral ANTES da fronteira (achado medido: 2.582
# linhas antes de subtype compact_boundary num transcript real). O contrato do host dispara
# SessionStart com matcher "compact" so apos /compact manual ou automatico - so ai vale avisar.
# Teto de 700 caracteres (nosso, mais apertado que o teto do host de 10.000), sempre PT-BR.
# ---------------------------------------------------------------------------

CONTEXTO_COMPACT_MAX_CHARS = 700


def _frescor_bloco() -> str:
    """Aviso de conhecimento velho no startup/resume (TASK-856): o sensor 1.x
    (graph-usage-sensor.ps1) morreu e L26/L67 apontavam para codigo que a 2.0 nunca chamava - um
    Client real ficou 45 dias com mapa velho sem aviso nenhum. Erro = sem aviso (fail-soft, nunca
    prende a sessao), mas grava no ledger como o resto deste despachante."""
    try:
        import frescor  # noqa: E402 (import tardio - mesmo padrao do pulso, ver topo do arquivo)
        root = paths.studio_root()
        velhos = []
        for cid in frescor.clientes_ativos(root):
            resultado = frescor.avaliar_client(root, cid)
            if resultado["veredito"] == "VELHO":
                velhos.append(resultado)
        blocos = []
        if velhos:
            linhas = [frescor.linha_humana(r) for r in velhos[:8]]
            blocos.append("\n".join(["[CONHECIMENTO VELHO]"] + linhas + [
                "Antes de trabalhar nesse Client, leia a fonte (client.md, artifacts/, CHANGELOG do "
                "codigo), nao o mapa. Refazer: /graphify clients/<id>/squad/knowledge e "
                "scripts/kb-index.ps1."
            ]))
        agentes = frescor.agentes_velhos(root)
        if agentes:
            por_client: dict[str, list[str]] = {}
            for a in agentes:
                por_client.setdefault(a["client"], []).append(a["agente"])
            linhas_a = [f"{c}: {len(n)} agente(s) gerado(s) atras da persona ({', '.join(n[:4])})"
                        for c, n in sorted(por_client.items())[:8]]
            blocos.append("\n".join(["[AGENTE VELHO]"] + linhas_a + [
                "A persona mudou depois de gerar o agente. Refazer: python v2/bin/client.py use <id>."]))
        return "\n\n".join(blocos)
    except Exception as exc:
        try:
            ledger.append_event(_ledger_path(), {"event": "frescor_error", "error": str(exc)[:300]})
        except Exception:
            pass
        return ""


def handle_session_start(event: dict) -> dict:
    # PULSO (Operacao Deep, TASK-847): startup/resume injeta o bloco "alia" (o unico source que
    # o dispatch tratava ate aqui era "compact", branch abaixo - nunca mexido). Sem pulso.json
    # ainda (Alia nova, ou PULSO nunca rodou) render() devolve "" e nada e injetado.
    if event.get("source") in ("startup", "resume"):
        try:
            if not _pulso_on():
                raise RuntimeError("PULSO desligado")
            import pulso  # noqa: E402 (import tardio - ver comentario no topo do arquivo)
            estado = pulso.load_state(paths.pulso_path())
            bloco = pulso.render("alia", estado)
        except Exception:
            bloco = ""
        bloco_frescor = _frescor_bloco()  # TASK-856: aviso de conhecimento velho, combinado com o PULSO
        partes = [b for b in (bloco, bloco_frescor, _espinha_abre_sessao(event)) if b]
        if not partes:
            return {}
        return {"hookSpecificOutput": {"hookEventName": "SessionStart",
                                        "additionalContext": "\n\n".join(partes)}}

    if event.get("source") != "compact":
        return {}
    transcript_path = event.get("transcript_path")
    if not transcript_path:
        return {}
    session_id = event.get("session_id")
    task_id = paths.read_current_task(session_id)
    sufixo_task = f" Task corrente desta sessao: {task_id}." if task_id else ""
    contexto = (
        "Conversa compactada. O texto integral anterior a compactação continua em "
        f"{transcript_path}. Antes de afirmar fato exato da parte compactada (caminho, "
        "número, decisão, pedido original do operador), busque nesse arquivo com Grep em vez "
        f"de confiar só no resumo.{sufixo_task}"
    )
    if len(contexto) > CONTEXTO_COMPACT_MAX_CHARS:
        contexto = contexto[:CONTEXTO_COMPACT_MAX_CHARS]
    ledger.append_event(_ledger_path(), {
        "event": "compact_recovery",
        "session_id": session_id,
        "transcript_path": transcript_path,
        "task_id": task_id,
    })
    return {"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": contexto}}


# ---------------------------------------------------------------------------
# ADAPTADOR da espinha Cliente>Projeto>Tarefa (Claude Code). Zero regra de dominio aqui: o
# evento do host vira chamada `alia` (bin/alia.py, em processo) e o que ela recusa vira deny.
# Declaracao (matriz em adapters/matriz.json): BLOQUEIA PreToolUse Agent|Task (task dispatch) e
# PreToolUse Grep|Glob (graph check); SO AVISA SessionStart (open) e Stop (task pending).
# Falha aberta so quando a espinha nao existe nesta instancia (sem state.json) ou quebrou por dentro.
# ---------------------------------------------------------------------------

_ESPINHA_SEM_VOTO = ("state_ausente", "erro_interno", "uso_invalido")


def _alia(argv: list[str]) -> tuple[int, dict]:
    try:
        sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "bin"))
        import alia  # noqa: E402 (import tardio: so quem fala com a espinha paga o custo)
        return alia.run(argv)
    except Exception as exc:  # noqa: BLE001 - fronteira: adaptador nunca derruba o hook
        return 1, {"ok": False, "regra": "erro_interno", "error": str(exc)}


def _negacao_da_espinha(codigo: int, res: dict, sessao: str = "") -> dict | None:
    if codigo == 0:
        return None
    if res.get("regra") in _ESPINHA_SEM_VOTO:
        try:  # falha aberta deixa rastro no ledger (C8): o `task pending` avisa o host sem trava
            import espinha  # noqa: E402
            espinha.registrar_falha_aberta("claude", str(res.get("regra")), sessao)
        except Exception:
            pass
        return None
    return _deny(f"espinha: {res.get('error')} [{res.get('regra')}]")


def _espinha_dispatch(event: dict) -> dict | None:
    tool_input = event.get("tool_input") or {}
    agente, sessao = tool_input.get("subagent_type"), event.get("session_id")
    if not agente or not sessao:
        return None
    return _negacao_da_espinha(*_alia(["task", "dispatch", "--specialist", str(agente), "--session", str(sessao)]), str(sessao))


def _espinha_grafo(event: dict) -> dict | None:
    tool_input = event.get("tool_input") or {}
    if not event.get("session_id"):
        return None
    import grafo_gate  # tardio: so o Grep|Glob paga
    alvo = grafo_gate.alvo_da_varredura(str(tool_input.get("path") or ""), str(tool_input.get("pattern") or "") if event.get("tool_name") == "Glob" else "")
    codigo, res = _alia(["graph", "check", "--session", str(event["session_id"]), "--tool", str(event.get("tool_name")),
                         "--path", alvo, "--cwd", str(event.get("cwd") or ""),
                         "--host", "claude", "--transcript", str(event.get("transcript_path") or "")])
    negacao = _negacao_da_espinha(codigo, res, str(event["session_id"]))
    if negacao:
        return negacao
    if res.get("aviso"):
        return {"hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext": res["aviso"]}}
    return None


def _espinha_abre_sessao(event: dict) -> str:
    """SessionStart startup|resume: `alia open` grava session_opened. So AVISA, e so quando ha o que fazer
    (Tasks abertas com projeto fora do cadastro): tudo em dia = silencio (o contrato do SessionStart)."""
    codigo, res = _alia(["open", "--session", str(event.get("session_id") or "")])
    fora = (res.get("divida") or {}).get("abertas_com_projeto_fora_do_cadastro", 0)
    if codigo != 0 or not fora:
        return ""
    return (f"[ESPINHA] {fora} Tasks abertas com projeto fora do cadastro: cadastre com "
            "`python v2/bin/alia.py project add --client <id> --from-tasks` (ou --id <projeto>).")


# ---------------------------------------------------------------------------
# Roteamento principal
# ---------------------------------------------------------------------------

def _write_stdout(obj: dict) -> None:
    sys.stdout.write(json.dumps(obj, ensure_ascii=False))
    sys.stdout.flush()


def main() -> int:
    raw = sys.stdin.buffer.read().decode("utf-8", errors="replace")
    try:
        event = json.loads(raw)
        if not isinstance(event, dict) or "hook_event_name" not in event:
            raise ValueError("malformed_event: missing hook_event_name")
    except Exception as exc:  # noqa: BLE001 - fronteira: nunca deixa crua
        try:
            ledger.append_event(_ledger_path(), {
                "event": "dispatch_error",
                "error": str(exc)[:300],
                "raw_len": len(raw),
            })
        except Exception:
            pass
        _write_stdout(_deny(f"guard: evento malformado ({exc})"))
        return 0

    try:
        hook = event.get("hook_event_name")
        tool_name = event.get("tool_name")

        if hook == "PreToolUse":
            if tool_name in ("Agent", "Task"):
                _negado_teto = _subagent_cap_check(event)
                if _negado_teto:
                    _write_stdout(_negado_teto)
                    return 0
                _negado_espinha = _espinha_dispatch(event)
                if _negado_espinha:
                    _write_stdout(_negado_espinha)
                    return 0
                handle_pre_agent(event)
                _write_stdout(handle_pretooluse_pulso_inject(event))
                return 0
            if tool_name in ("Grep", "Glob"):
                _write_stdout(_espinha_grafo(event) or _no_decision())
                return 0
            if tool_name in ("Write", "Edit", "NotebookEdit", "MultiEdit", "Bash", "PowerShell"):
                _write_stdout(handle_pretooluse_guard(event))
                return 0
            _write_stdout(_no_decision())
            return 0

        if hook == "UserPromptSubmit":
            _write_stdout(handle_user_prompt_submit(event))
            return 0

        if hook == "PostToolUse":
            if tool_name in ("Agent", "Task"):
                handle_post_agent(event)
            if tool_name in ("Write", "Edit", "MultiEdit"):
                handle_post_write_artifact_marker(event)
            _write_stdout({})
            return 0

        if hook == "SubagentStop":
            handle_subagent_stop(event)
            _write_stdout({})
            return 0

        if hook == "Stop":
            _write_stdout(handle_stop(event))
            return 0

        if hook == "SessionStart":
            _write_stdout(handle_session_start(event))
            return 0

        _write_stdout({})
        return 0
    except Exception as exc:  # noqa: BLE001 - fronteira: nunca deixa crua
        try:
            ledger.append_event(_ledger_path(), {
                "event": "dispatch_error",
                "error": str(exc)[:300],
                "hook_event_name": event.get("hook_event_name"),
            })
        except Exception:
            pass
        if event.get("hook_event_name") == "PreToolUse":
            _write_stdout(_deny(f"guard: erro interno ({exc})"))
        else:
            _write_stdout({})
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
