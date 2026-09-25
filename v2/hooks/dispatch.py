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

Nunca deixa excecao crua vazar: todo caminho de erro cai no except geral no
fim do arquivo, loga em activity.jsonl como "dispatch_error" e devolve uma
decisao segura (deny quando o evento e PreToolUse ou nao da pra saber; Stop
sempre libera - um hook quebrado nunca prende o operador).

So biblioteca padrao. UTF-8 explicito em toda leitura/escrita/print.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lib"))
import ledger  # noqa: E402
import paths  # noqa: E402


def _ledger_path() -> str:
    return paths.ledger_path()


def _project_dir() -> str:
    return os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd())


def _norm(p: str) -> str:
    return (p or "").replace("\\", "/")


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


def _infer_task_id(event: dict) -> str | None:
    tool_input = event.get("tool_input") or {}
    text = str(tool_input.get("prompt") or "") + " " + str(tool_input.get("description") or "")
    m = re.search(r"TASK-\d+", text)
    if m:
        return m.group(0)
    # ALIA_TASK_ID nunca era definido (achado da revisao independente, TASK-804): a fonte
    # real e o arquivo que `task.py open` grava por sessao (lib/paths.py).
    return paths.read_current_task(event.get("session_id"))


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
    re.compile(r"sk-[A-Za-z0-9]{20,}"),
    re.compile(r"AKIA[0-9A-Z]{16}"),
    re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
    re.compile(r"(?i)api[_-]?key\s*[:=]\s*['\"][A-Za-z0-9_\-]{16,}['\"]"),
]

PUBLISH_PATTERNS = re.compile(r"(?i)\b(git push|npm publish|package-release)\b")

# lista EXPLICITA do kernel (revisao independente: a checagem antiga procurava "/kernel/",
# uma pasta que nao existe - o kernel real e este punhado de arquivo + a pasta engine/).
KERNEL_FILES = ("agents.md", "claude.md", "contracts.md")

# gatilhos de redirecionamento que o Bash pode usar para escrever num arquivo (>, >>, tee,
# cp, mv, e os equivalentes de PowerShell Out-File/Set-Content).
# achado do CEO, 24/09/2026 (falso positivo no studio vivo): `2>&1` (duplicacao de descritor,
# nunca escreve arquivo) casava com o `>` generico e qualquer mencao de LEITURA ao kernel em
# outro trecho do mesmo comando (`cat AGENTS.md`, `grep ... AGENTS.md`) virava negacao. So o
# ALVO real de escrita conta agora - ver _extract_write_targets.
_FD_DUP_RE = re.compile(r"\d>&\d|>&\d")
_WRITE_OP_RE = re.compile(r"(?<![0-9])(>>|>)(?!&)")
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


def _extract_write_targets(command: str) -> list[str]:
    """So os tokens que sao de fato ALVO de escrita: destino de `>`/`>>` (nunca `2>&1`/`>&N`,
    duplicacao de descritor), `tee <alvo>`, ultimo argumento (ou `-Destination`/`-Path`) de
    cp/mv/rm/copy/move/Copy-Item/Move-Item/Remove-Item, `-Path`/`-FilePath` (ou 1o posicional) de
    Out-File/Set-Content/Add-Content/Clear-Content/Tee-Object, `-Path` de New-Item (so quando cria
    ARQUIVO: tem -Value ou nao e -ItemType Directory), 1o argumento de [IO.File]::Write* /
    [System.IO.File]::Write*, e o ultimo argumento nao-flag de `sed -i`. Leitura (cat, grep, python
    lendo o arquivo) nunca aparece aqui - so o ALVO real de escrita (TASK-824)."""
    alvos: list[str] = []
    sem_fd = _FD_DUP_RE.sub(" ", command)
    for m in _WRITE_OP_RE.finditer(sem_fd):
        resto = sem_fd[m.end():].lstrip().split()
        if resto:
            alvos.append(resto[0].strip("'\""))
    for m_iofile in _IOFILE_WRITE_RE.finditer(command):
        alvos.append(m_iofile.group(1).strip("'\""))
    for clausula in re.split(r"[;&|]+", command):
        c = clausula.strip()
        if not c:
            continue
        m_tee = re.match(r"tee\b\s+(?:-a\s+)?(\S+)", c, re.IGNORECASE)
        if m_tee:
            alvos.append(m_tee.group(1).strip("'\""))
            continue
        if _CP_RE.match(c):
            # so o DESTINO e alvo de escrita - -Path/-LiteralPath aqui e a origem, so leitura
            m_dest = re.search(r"-Destination\s+(\S+)", c, re.IGNORECASE)
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
            m_dest = re.search(r"-Destination\s+(\S+)", c, re.IGNORECASE)
            m_origem = re.search(r"-(?:Path|LiteralPath)\s+(\S+)", c, re.IGNORECASE)
            if m_dest:
                alvos.append(m_dest.group(1).strip("'\""))
            if m_origem:
                alvos.append(m_origem.group(1).strip("'\""))
            nao_flag = [p for p in c.split()[1:] if not p.startswith("-")]
            alvos.extend(p.strip("'\"") for p in nao_flag)
            continue
        if _RM_RE.match(c):
            # remover e destrutivo - todo -Path/-LiteralPath e todo posicional e alvo
            for m_path in re.finditer(r"-(?:Path|LiteralPath)\s+(\S+)", c, re.IGNORECASE):
                alvos.append(m_path.group(1).strip("'\""))
            nao_flag = [p for p in c.split()[1:] if not p.startswith("-")]
            alvos.extend(p.strip("'\"") for p in nao_flag)
            continue
        if _OUTFILE_SETCONTENT_RE.match(c):
            m_path = re.search(r"-(?:Path|FilePath)\s+(\S+)", c, re.IGNORECASE)
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
            m_path = re.search(r"-Path\s+(\S+)", c, re.IGNORECASE)
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
    p = "/" + _norm(path).lower().lstrip("/")
    return SOURCE_PATH_MARKER in p


def _is_kernel_path(path: str) -> bool:
    if _is_source_path(path):
        return False
    p = _norm(path).lower()
    if "/engine/" in p or p.endswith("/engine") or p == "engine":
        return True
    basename = p.rsplit("/", 1)[-1]
    return basename in KERNEL_FILES


def _bash_targets_kernel(command: str) -> bool:
    """Bash grava em engine/ ou num arquivo do kernel sem passar por Write/Edit (achado da
    revisao independente): confere so os ALVOS DE ESCRITA extraidos por
    _extract_write_targets - nunca menciona de leitura (cat, grep, python lendo o kernel)
    em outro trecho do mesmo comando."""
    return any(_is_kernel_path(alvo) for alvo in _extract_write_targets(command))


def _has_secret(text: str) -> bool:
    return any(p.search(text or "") for p in SECRET_PATTERNS)


def _is_client_write_without_delegation(event: dict, path: str) -> bool:
    p = _norm(path).lower()
    m = re.search(r"/clients/([a-z0-9\-]+)/", p)
    if not m:
        return False
    client_id = m.group(1)
    if NEGATION4_COORDINATION_EXEMPT in p:
        return False
    m_artifact = ARTIFACT_TASK_RE.search(p)
    if m_artifact and _artifact_marked_by_subagent(m_artifact.group(1).upper()):
        return False
    if event.get("_is_subagent"):
        # a propria sessao delegada (Agent/Task <id>-*) escrevendo no proprio
        # Client nunca e negada; a negacao e so sobre a SESSAO PRINCIPAL.
        return False
    session_id = event.get("session_id")
    return not ledger.session_has_agent_prefix(_ledger_path(), session_id, client_id + "-")


def _artifact_marked_by_subagent(task_id: str) -> bool:
    """True se ja existe um marcador `artifact_write` no ledger (gravado pelo proprio
    PostToolUse quando um sub-agente escreveu em artifacts/<task_id>/) para este task_id."""
    for ev in ledger.read_events(_ledger_path()):
        if ev.get("event") == "artifact_write" and ev.get("task_id") == task_id:
            return True
    return False


def handle_post_write_artifact_marker(event: dict) -> None:
    """PostToolUse de Write/Edit em artifacts/<task_id>/: grava o marcador que a 4a negacao
    consulta depois. So marca quando o PreToolUse ja deixou passar (PostToolUse so roda se o
    Write/Edit foi de fato executado)."""
    tool_input = event.get("tool_input") or {}
    path = _norm(tool_input.get("file_path", ""))
    m = ARTIFACT_TASK_RE.search(path.lower())
    if not m:
        return
    task_id = m.group(1).upper()
    ledger.append_event(_ledger_path(), {
        "event": "artifact_write",
        "session_id": event.get("session_id"),
        "agent_id": event.get("agent_id"),
        "task_id": task_id,
        "path": path,
    })


CHECK_MARKER_MAX_AGE_S = 30 * 60  # 30 minutos (mandato do CEO, 24/09/2026)


def _current_git_head(repo_dir: str) -> str | None:
    try:
        proc = subprocess.run(["git", "rev-parse", "HEAD"], cwd=repo_dir,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except OSError:
        return None
    if proc.returncode != 0:
        return None
    return proc.stdout.decode("utf-8", "replace").strip()


def _check_marker_valido() -> bool:
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
    head_gravado = dados.get("head")
    if head_gravado:
        repo_dir = os.path.dirname(os.path.dirname(marker))
        if _current_git_head(repo_dir) != head_gravado:
            return False
    return True


def handle_pretooluse_guard(event: dict) -> dict:
    tool_name = event.get("tool_name")
    tool_input = event.get("tool_input") or {}
    # sessao principal x sub-agente: PreToolUse/PostToolUse carregam agent_id
    # quando a chamada nasce dentro de um sub-agente (campo comum documentado
    # na doc oficial de hooks). Sem agent_id = sessao principal.
    event["_is_subagent"] = bool(event.get("agent_id"))

    if tool_name in ("Write", "Edit"):
        path = tool_input.get("file_path", "")
        content = str(tool_input.get("content") or tool_input.get("new_string") or "")
        if _is_kernel_path(path):
            return _deny("guard: escrita no kernel negada (AGENTS.md, CLAUDE.md, "
                         "CONTRACTS.md ou engine/)")
        if _has_secret(content) or _has_secret(path):
            return _deny("guard: segredo detectado no conteudo ou caminho")
        if _is_client_write_without_delegation(event, path):
            return _deny(
                "guard: Write/Edit em clients/<id>/ pela sessao principal sem "
                "Agent/Task <id>-* visto nesta sessao (herda delegation-gate L33/L45)"
            )
        return _no_decision()

    if tool_name in ("Bash", "PowerShell"):
        # PowerShell (TASK-824, achado do CEO 24/09/2026): o terminal nativo desta maquina
        # Windows passava sem nenhuma das 4 negacoes porque o guard so olhava "Bash". O campo
        # do evento e o mesmo (command), entao PowerShell recebe exatamente o mesmo tratamento.
        command = str(tool_input.get("command") or "")
        if _has_secret(command):
            return _deny("guard: segredo detectado no comando")
        if _bash_targets_kernel(command):
            return _deny("guard: Bash redireciona/copia para o kernel (AGENTS.md, "
                         "CLAUDE.md, CONTRACTS.md ou engine/) - negado")
        if PUBLISH_PATTERNS.search(command):
            if not _check_marker_valido():
                return _deny("guard: publicacao sem check (marcador de check ausente, "
                             "vencido ha mais de 30 min, ou HEAD divergente)")
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


def _load_state_for_stop() -> dict | None:
    """Le state.json so pra checar gate_verdict. Qualquer erro (arquivo
    ausente, JSON quebrado) devolve None - quem chama trata None como "nao da
    pra dizer" e a trava SEMPRE libera nesse caso (falha aberta)."""
    try:
        with open(paths.state_path(), "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, json.JSONDecodeError):
        return None
    return data if isinstance(data, dict) else None


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

    state = _load_state_for_stop()
    if state is None:
        return None
    tasks_by_id = {t.get("id"): t for t in state.get("tasks", []) if t.get("id")}
    task = tasks_by_id.get(task_id)
    if task is None or task.get("gate_verdict"):
        return None

    if seq is not None and ledger.delivery_already_notified(_ledger_path(), session_id, seq):
        return None
    if seq is not None:
        ledger.mark_delivery_notified(_ledger_path(), session_id, seq)
    return (f"{task_id} voltou sem veredito do Gate - rode o Gate ou feche com veredito "
            "antes de encerrar.")


def handle_stop(event: dict) -> dict:
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
                handle_pre_agent(event)
                _write_stdout(_no_decision())
                return 0
            if tool_name in ("Write", "Edit", "Bash", "PowerShell"):
                _write_stdout(handle_pretooluse_guard(event))
                return 0
            _write_stdout(_no_decision())
            return 0

        if hook == "PostToolUse":
            if tool_name in ("Agent", "Task"):
                handle_post_agent(event)
            if tool_name in ("Write", "Edit"):
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
