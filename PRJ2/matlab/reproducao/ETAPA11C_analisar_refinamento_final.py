import pandas as pd
import matplotlib.pyplot as plt
from pathlib import Path

PASTA = Path(__file__).resolve().parent
RAIZ_PROJETO = PASTA.parent.parent
BASE = RAIZ_PROJETO / "dados" / "ensaio_controle_escalonado.csv"
NOVO = RAIZ_PROJETO / "dados" / "ensaio_controle_refinado.csv"
PASTA_SAIDA = RAIZ_PROJETO / "resultados" / "refinamento_final"
PASTA_SAIDA.mkdir(parents=True, exist_ok=True)
SAIDA = PASTA_SAIDA / "comparacao_refinamento.png"


def segmento_valido(caminho):
    dados = pd.read_csv(caminho)
    return dados[dados["segmento"] == dados["segmento"].max()].copy()


base = segmento_valido(BASE)
novo = segmento_valido(NOVO)
janela_base = base[(base["t"] >= 1750) & (base["t"] <= 3250)]
janela_nova = novo[(novo["t"] >= 1750) & (novo["t"] <= 3250)]

fig, eixos = plt.subplots(3, 1, figsize=(14, 9), sharex=True)

eixos[0].plot(janela_nova["t"], janela_nova["R"], "k--", label="R")
eixos[0].plot(janela_base["t"], janela_base["Y"], label="Y anterior")
eixos[0].plot(janela_nova["t"], janela_nova["Y"], label="Y refinado")
eixos[0].set_ylabel("Temperatura (°C)")
eixos[0].legend(ncol=3)

eixos[1].plot(janela_base["t"], janela_base["Y"] - janela_base["R"],
              label="Erro anterior")
eixos[1].plot(janela_nova["t"], janela_nova["Y"] - janela_nova["R"],
              label="Erro refinado")
eixos[1].axhline(0, color="black", linewidth=0.8)
eixos[1].set_ylabel("Y − R (°C)")
eixos[1].legend(ncol=2)

eixos[2].plot(janela_base["t"], janela_base["W"], label="W anterior")
eixos[2].plot(janela_nova["t"], janela_nova["W"], label="W refinado")
eixos[2].set_ylabel("PWM12")
eixos[2].set_xlabel("Tempo (s)")
eixos[2].legend(ncol=2)

for eixo in eixos:
    eixo.grid(True, alpha=0.3)
    for instante in (1800, 2000, 2400, 2800, 3000, 3200):
        eixo.axvline(instante, color="gray", linewidth=0.7, alpha=0.35)

fig.suptitle("Comparação experimental durante a perturbação senoidal")
fig.tight_layout()
fig.savefig(SAIDA, dpi=180)
