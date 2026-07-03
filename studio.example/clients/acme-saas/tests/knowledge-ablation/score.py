# Scorer do teste de ablacao de conhecimento.
# Le out-blind.md e out-informed.md, conta termos-chave cobertos e decide PASS/FAIL.
# Sem acentos, sem emojis. Imprime "VERDICT: PASS" e sai 0 quando passa.

import sys

KEY_TERMS = ["Painel Pulse", "Cartao", "Ativacao", "Headline", "Chamada de acao"]
THRESHOLD = 3


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def covered(text, terms):
    found = set()
    low = text.lower()
    for t in terms:
        if t.lower() in low:
            found.add(t)
    return found


def main():
    blind = read("out-blind.md")
    informed = read("out-informed.md")

    blind_cov = covered(blind, KEY_TERMS)
    informed_cov = covered(informed, KEY_TERMS)

    gain = len(informed_cov) - len(blind_cov)

    print("Termos cobertos (blind): " + str(len(blind_cov)))
    print("Termos cobertos (informed): " + str(len(informed_cov)))
    print("Ganho do informed: " + str(gain) + " (threshold " + str(THRESHOLD) + ")")

    if gain >= THRESHOLD:
        print("VERDICT: PASS")
        return 0
    print("VERDICT: FAIL")
    return 1


if __name__ == "__main__":
    sys.exit(main())