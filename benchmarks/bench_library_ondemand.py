# Benchmark 5 (opcional) - Razao de frugalidade: nucleo enxuto vs biblioteca sob demanda.
# O fast-boot carrega SO os 4 docs de nucleo. O resto do motor (engine/*.md) e biblioteca
# sob demanda (engine/MAP.md indexa). Medimos quanto da prosa do motor NAO entra na cabeca
# por padrao. Determinista, sem LLM.
#
# Saida METRIC + VERDICT. Sem acentos, sem emojis. UTF-8 sem BOM.

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
ENGINE = os.path.join(ROOT, "engine")

CORE_DOCS = [
    os.path.join("engine", "agents", "persona.md"),
    os.path.join("engine", "constitution.md"),
    os.path.join("engine", "glossary.md"),
    os.path.join("engine", "orchestration.md"),
]


def chars_of(path):
    with open(path, encoding="utf-8") as f:
        return len(f.read())


def main():
    core_chars = 0
    for rel in CORE_DOCS:
        p = os.path.join(ROOT, rel)
        if not os.path.isfile(p):
            print("METRIC error=core doc ausente: " + rel)
            print("VERDICT: FAIL")
            return 1
        core_chars += chars_of(p)

    total_chars = 0
    md_count = 0
    for dirpath, _dirs, files in os.walk(ENGINE):
        for fn in files:
            if fn.endswith(".md"):
                md_count += 1
                total_chars += chars_of(os.path.join(dirpath, fn))

    ondemand_chars = total_chars - core_chars
    ondemand_pct = round(100.0 * ondemand_chars / total_chars) if total_chars else 0
    core_pct = round(100.0 * core_chars / total_chars) if total_chars else 0

    print("METRIC source=engine/*.md (nucleo fast-boot vs biblioteca sob demanda)")
    print("METRIC engine_md_files=" + str(md_count))
    print("METRIC core_chars=" + str(core_chars))
    print("METRIC engine_total_chars=" + str(total_chars))
    print("METRIC ondemand_chars=" + str(ondemand_chars))
    print("METRIC core_pct_of_engine=" + str(core_pct) + "%")
    print("METRIC ondemand_pct_of_engine=" + str(ondemand_pct) + "% (fica fora do boot)")
    print("VERDICT: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
