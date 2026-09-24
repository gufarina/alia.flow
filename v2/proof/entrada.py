# -*- coding: utf-8 -*-
"""I10 - mede os tokens (bytes/4) que chegam antes do trabalho comecar, separando MOTOR
(o que o engine controla) de PLATAFORMA (o que o Claude Code injeta por fora, fora do
alcance de qualquer modulo - fronteira declarada no contrato do modulo 7/context,
v2/CONTRACTS.md). Compara 1.84 (studio hoje) com 2.0 (v2). So biblioteca padrao.

Uso: python entrada.py
Todo numero sai com o path medido, para reproduzir com Get-Item/wc -c.
"""
from __future__ import annotations

import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))          # .../v2/proof
V2 = os.path.dirname(HERE)                                  # .../v2
CLIENT = os.path.dirname(V2)                                 # .../clients/alia-flow-lab
ROOT = os.path.dirname(os.path.dirname(CLIENT))              # .../studio-farina
HOME = os.path.expanduser("~")
AGENTS_DIR = os.path.join(ROOT, ".claude", "agents")


def size(path: str) -> int:
    return os.path.getsize(path) if os.path.isfile(path) else 0


def tok(b: int) -> float:
    return round(b / 4, 1)


def lista_agentes_bytes() -> tuple[int, int]:
    """Proxy do que o host injeta pra rotear pela descricao (arquitetura, secao 3 DELEGA):
    soma bytes de 'nome: descricao' de cada agente invocavel. Nao e o texto exato que o
    host monta (formatacao propria dele), mas usa o mesmo dado fonte (frontmatter)."""
    total = 0
    n = 0
    if not os.path.isdir(AGENTS_DIR):
        return 0, 0
    pat_name = re.compile(r"^name:\s*(.+)$", re.M)
    pat_desc = re.compile(r"^description:\s*(.+)$", re.M)
    for fname in sorted(os.listdir(AGENTS_DIR)):
        if not fname.endswith(".md"):
            continue
        path = os.path.join(AGENTS_DIR, fname)
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            head = fh.read(3000)
        m_name = pat_name.search(head)
        m_desc = pat_desc.search(head)
        nome = m_name.group(1).strip() if m_name else fname
        desc = m_desc.group(1).strip() if m_desc else ""
        linha = f"- {nome}: {desc}\n"
        total += len(linha.encode("utf-8"))
        n += 1
    return total, n


def main() -> None:
    # plataforma: fora do motor, identica nas duas versoes (contrato modulo 7: "sobre
    # esses o motor so mede e recomenda ao Operator, nunca edita").
    global_claude = os.path.join(HOME, ".claude", "CLAUDE.md")
    memory_md = os.environ.get(
        "ALIA_MEMORY_PATH",
        os.path.join(HOME, ".claude", "projects", "C--Users-Lite-OS-Projetos-studio-farina",
                     "memory", "MEMORY.md"),
    )
    b_global = size(global_claude)
    b_memory = size(memory_md)
    b_agentes, n_agentes = lista_agentes_bytes()
    plataforma_total = b_global + b_memory + b_agentes

    # motor 1.84: CLAUDE.md do projeto (plataforma tecnica, injeta @AGENTS.md, conta uma
    # vez so pois e identico nas 2 versoes) + AGENTS.md e CLAUDE.md do Client + regra do mapa.
    proj_claude = os.path.join(ROOT, "CLAUDE.md")
    client_claude = os.path.join(CLIENT, "CLAUDE.md")
    client_agents = os.path.join(CLIENT, "AGENTS.md")
    mapa_regra = os.path.join(ROOT, ".claude", "rules", "graphify-integration.md")
    b_proj = size(proj_claude)
    b_client_claude = size(client_claude)
    b_client_agents = size(client_agents)
    b_mapa = size(mapa_regra)
    motor_184 = b_proj + b_client_claude + b_client_agents + b_mapa

    # motor 2.0: kernel estatico (v2/AGENTS.md) substitui AGENTS.md+CLAUDE.md do Client;
    # a regra do mapa vira skill sob demanda (modulo 2, "pergunta -> 1 linha por doc"),
    # 0 bytes no boot por design, nao por arquivo ausente.
    v2_agents = os.path.join(V2, "AGENTS.md")
    b_v2_agents = size(v2_agents)
    motor_20 = b_proj + b_v2_agents

    print("=== plataforma (fora do motor, identica nas 2 versoes) ===")
    print(f"[MEDIDO] {global_claude} = {b_global} bytes (~{tok(b_global)} tok)")
    print(f"[MEDIDO] {memory_md} = {b_memory} bytes (~{tok(b_memory)} tok)")
    print(f"[MEDIDO] lista de agentes ({n_agentes} arquivos, {AGENTS_DIR}) = {b_agentes} bytes "
          f"(~{tok(b_agentes)} tok) [proxy: nome+description do frontmatter]")
    print(f"[MEDIDO] subtotal plataforma = {plataforma_total} bytes (~{tok(plataforma_total)} tok)")

    print("\n=== motor 1.84 ===")
    print(f"[MEDIDO] {proj_claude} = {b_proj} bytes")
    print(f"[MEDIDO] {client_claude} = {b_client_claude} bytes")
    print(f"[MEDIDO] {client_agents} = {b_client_agents} bytes")
    print(f"[MEDIDO] {mapa_regra} = {b_mapa} bytes")
    print(f"[MEDIDO] subtotal motor 1.84 = {motor_184} bytes (~{tok(motor_184)} tok)")

    print("\n=== motor 2.0 ===")
    print(f"[MEDIDO] {proj_claude} = {b_proj} bytes (arquivo de plataforma, identico nas 2 versoes)")
    print(f"[MEDIDO] {v2_agents} = {b_v2_agents} bytes")
    print("[INFERIDO] regra do mapa = 0 bytes no boot (modulo 2 vira skill sob demanda, nunca injecao automatica)")
    print(f"[MEDIDO] subtotal motor 2.0 = {motor_20} bytes (~{tok(motor_20)} tok)")

    print("\n=== comparacao ===")
    if motor_184:
        corte = motor_184 - motor_20
        pct = (1 - motor_20 / motor_184) * 100
        print(f"[MEDIDO] motor: 1.84 = {motor_184} bytes vs 2.0 = {motor_20} bytes, "
              f"corte de {corte} bytes ({pct:.1f}% menor)")
    total_184 = motor_184 + plataforma_total
    total_20 = motor_20 + plataforma_total
    print(f"[MEDIDO] total (motor+plataforma): 1.84 = {total_184} bytes (~{tok(total_184)} tok) "
          f"vs 2.0 = {total_20} bytes (~{tok(total_20)} tok)")
    if total_184:
        print(f"[MEDIDO] plataforma sozinha = {plataforma_total} bytes (~{tok(plataforma_total)} tok) "
              f"= {plataforma_total/total_184*100:.1f}% do total 1.84 e "
              f"{plataforma_total/total_20*100:.1f}% do total 2.0 - fora do alcance de qualquer modulo do motor")


if __name__ == "__main__":
    main()
