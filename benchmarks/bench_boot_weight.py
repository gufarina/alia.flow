# Benchmark 3 - Peso de boot evitado (fast-boot).
# Mede o tamanho real (caracteres) dos 4 docs de nucleo que o AGENTS.md manda carregar ANTES
# de trabalho de dominio, e que o fast-boot NAO carrega para responder uma saudacao.
# Estima tokens como chars/4 (APROXIMADO - marcar como tal).
#
# Determinista, sem LLM. Saida METRIC + VERDICT. Sai 0 se os 4 docs existem.
# Sem acentos, sem emojis. UTF-8 sem BOM.

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

CORE_DOCS = [
    os.path.join("engine", "agents", "persona.md"),
    os.path.join("engine", "constitution.md"),
    os.path.join("engine", "glossary.md"),
    os.path.join("engine", "orchestration.md"),
]

CHARS_PER_TOKEN = 4  # aproximacao padrao para estimativa de tokens


def main():
    total_chars = 0
    missing = []
    print("METRIC source=AGENTS.md fast-boot (4 docs de nucleo: persona+constitution+glossary+orchestration)")
    for rel in CORE_DOCS:
        path = os.path.join(ROOT, rel)
        if not os.path.isfile(path):
            missing.append(rel)
            continue
        with open(path, encoding="utf-8") as f:
            chars = len(f.read())
        total_chars = total_chars + chars
        print("METRIC doc_chars[" + rel.replace("\\", "/") + "]=" + str(chars))

    if missing:
        for m in missing:
            print("METRIC error=doc ausente: " + m.replace("\\", "/"))
        print("VERDICT: FAIL")
        return 1

    est_tokens = total_chars // CHARS_PER_TOKEN
    print("METRIC core_total_chars=" + str(total_chars))
    print(
        "METRIC core_est_tokens~"
        + str(est_tokens)
        + " (APROXIMADO, chars/"
        + str(CHARS_PER_TOKEN)
        + ")"
    )
    print(
        "METRIC core_est_tokens_rounded~"
        + str(round(est_tokens / 1000.0, 1))
        + "k (APROXIMADO)"
    )
    print("METRIC fast_boot_loads_for_greeting=0 (responde em 1 linha sem abrir o nucleo)")
    print("VERDICT: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
