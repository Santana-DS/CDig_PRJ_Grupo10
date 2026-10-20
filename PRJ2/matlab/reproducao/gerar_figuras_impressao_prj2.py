"""Gera as figuras experimentais do PRJ2 no tamanho físico do relatório.

Os PDFs são vetoriais e devem ser preferidos no LaTeX. Os PNGs a 600 dpi
servem para inspeção, apresentação e compatibilidade.
"""

from pathlib import Path
import argparse

import matplotlib as mpl
import matplotlib.pyplot as plt
import pandas as pd


LARGURA_DUPLA = 7.08  # polegadas; largura útil aproximada do IFAC em A4
PRETO = "#000000"
VERMELHO = "#d62728"
LARANJA = "#ed8b00"
VERDE = "#2ca02c"
AZUL = "#0072bd"
AZUL_ANTERIOR = "#4c78a8"


def ultimo_segmento(caminho: Path) -> pd.DataFrame:
    dados = pd.read_csv(caminho)
    if "segmento" in dados.columns:
        dados = dados.loc[dados["segmento"] == dados["segmento"].max()]
    return dados.copy()


def configurar_estilo() -> None:
    mpl.rcParams.update(
        {
            "font.family": "serif",
            "font.size": 8.5,
            "axes.labelsize": 8.5,
            "xtick.labelsize": 7.5,
            "ytick.labelsize": 7.5,
            "legend.fontsize": 7.5,
            "axes.linewidth": 0.7,
            "grid.linewidth": 0.45,
            "grid.alpha": 0.25,
            "lines.solid_capstyle": "round",
            "pdf.fonttype": 42,
            "ps.fonttype": 42,
        }
    )


def acabamento(eixo, limite_x=(0, 3600)) -> None:
    eixo.set_xlim(*limite_x)
    eixo.grid(True)
    eixo.tick_params(direction="in", length=3, width=0.6)
    for lado in eixo.spines.values():
        lado.set_linewidth(0.7)


def salvar(figura, destino: Path, nome: str) -> None:
    figura.savefig(destino / f"{nome}.pdf", bbox_inches="tight")
    figura.savefig(destino / f"{nome}.png", dpi=600, bbox_inches="tight")
    plt.close(figura)


def figura_comparacao(anterior: pd.DataFrame, final: pd.DataFrame, destino: Path) -> None:
    anterior = anterior.loc[anterior["t"].between(1750, 3250)]
    final = final.loc[final["t"].between(1750, 3250)]

    fig, eixos = plt.subplots(
        2, 1, figsize=(LARGURA_DUPLA, 3.80), sharex=True,
        gridspec_kw={"hspace": 0.12},
    )

    eixos[0].step(
        final["t"], final["R"], where="post", color=PRETO,
        linestyle=":", linewidth=1.15, label=r"$R$",
    )
    eixos[0].plot(
        anterior["t"], anterior["Y"], color=AZUL_ANTERIOR,
        linewidth=1.25, label=r"$Y$ anterior",
    )
    eixos[0].plot(
        final["t"], final["Y"], color=VERMELHO,
        linewidth=1.65, label=r"$Y$ refinado",
    )
    eixos[0].set_ylabel("Temperatura (°C)")
    eixos[0].legend(loc="upper right", ncol=3, frameon=True)
    eixos[0].text(0.01, 0.90, "(a)", transform=eixos[0].transAxes)

    eixos[1].plot(
        anterior["t"], anterior["Y"] - anterior["R"],
        color=AZUL_ANTERIOR, linewidth=1.25, label="Anterior",
    )
    eixos[1].plot(
        final["t"], final["Y"] - final["R"],
        color=VERMELHO, linewidth=1.65, label="Refinado",
    )
    eixos[1].axhline(0, color=PRETO, linestyle=":", linewidth=0.8)
    eixos[1].set_ylabel(r"Erro $Y-R$ (°C)")
    eixos[1].set_xlabel("Tempo (s)")
    eixos[1].legend(loc="lower right", ncol=2, frameon=True)
    eixos[1].text(0.01, 0.90, "(b)", transform=eixos[1].transAxes)

    for eixo in eixos:
        acabamento(eixo, (1750, 3250))
        for instante in (1800, 2000, 2400, 2800, 3000, 3200):
            eixo.axvline(instante, color="0.55", linewidth=0.45, alpha=0.35)

    fig.subplots_adjust(left=0.095, right=0.99, bottom=0.12, top=0.985)
    salvar(fig, destino, "10_comparacao_refinamento_experimental")


def figura_final_completa(final: pd.DataFrame, destino: Path) -> None:
    e_sin = (1 - final["modo"]) * final["e_sin_nom"] + final["modo"] * final["e_sin_cool"]
    fig, eixos = plt.subplots(
        3, 1, figsize=(LARGURA_DUPLA, 5.25), sharex=True,
        gridspec_kw={"hspace": 0.12},
    )

    eixos[0].step(
        final["t"], final["R"], where="post", color=PRETO,
        linestyle=":", linewidth=1.1, label=r"$R$",
    )
    eixos[0].plot(final["t"], final["Y"], color=VERMELHO, linewidth=1.6, label=r"$Y$")
    eixos[0].set_ylabel("Temperatura (°C)")
    eixos[0].legend(loc="lower right", ncol=2)

    eixo_ta = eixos[1]
    eixo_w = eixo_ta.twinx()
    linha_ta = eixo_ta.plot(final["t"], final["Ta"], color=LARANJA, linewidth=1.1, label=r"$T_a$")[0]
    linha_w = eixo_w.step(final["t"], final["W"], where="post", color=VERDE, linewidth=1.25, label=r"$W$")[0]
    eixo_ta.set_ylabel(r"$T_a$ (°C)", color=LARANJA)
    eixo_w.set_ylabel(r"$W$ (PWM12)", color=VERDE)
    eixo_ta.tick_params(axis="y", colors=LARANJA)
    eixo_w.tick_params(axis="y", colors=VERDE, direction="in", length=3, width=0.6)
    eixo_ta.legend([linha_ta, linha_w], [r"$T_a$", r"$W$"], loc="lower center", ncol=2)

    eixos[2].step(final["t"], final["Us"], where="post", color=AZUL, linewidth=1.3, label=r"$U_s$")
    eixos[2].plot(final["t"], e_sin, color=VERDE, linewidth=1.25, label=r"$e_{sin}$ ativo")
    eixos[2].set_ylabel("PWM16")
    eixos[2].set_xlabel("Tempo (s)")
    eixos[2].legend(loc="upper right", ncol=2)

    for eixo in eixos:
        acabamento(eixo)
    eixo_w.set_xlim(0, 3600)
    eixo_w.grid(False)

    fig.subplots_adjust(left=0.09, right=0.91, bottom=0.09, top=0.99)
    salvar(fig, destino, "11_ensaio_final_1h")


def figura_ry(final: pd.DataFrame, destino: Path) -> None:
    fig, eixo = plt.subplots(figsize=(LARGURA_DUPLA, 2.35))
    eixo.step(
        final["t"], final["R"], where="post", color=PRETO,
        linestyle=":", linewidth=1.2, label=r"$R$",
    )
    eixo.plot(final["t"], final["Y"], color=VERMELHO, linewidth=1.85, label=r"$Y$")
    eixo.set_ylim(24, 60.5)
    eixo.set_ylabel("Temperatura (°C)")
    eixo.set_xlabel("Tempo (s)")
    eixo.legend(loc="lower right", ncol=2, frameon=True)
    acabamento(eixo)
    fig.subplots_adjust(left=0.085, right=0.995, bottom=0.20, top=0.985)
    salvar(fig, destino, "12_ensaio_final_RY_coluna_dupla")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dados", type=Path, required=True)
    parser.add_argument("--destino", type=Path, required=True)
    args = parser.parse_args()

    args.destino.mkdir(parents=True, exist_ok=True)
    configurar_estilo()
    anterior = ultimo_segmento(args.dados / "ensaio_controle_escalonado.csv")
    final = ultimo_segmento(args.dados / "ensaio_controle_refinado.csv")

    figura_comparacao(anterior, final, args.destino)
    figura_final_completa(final, args.destino)
    figura_ry(final, args.destino)
    print(f"Figuras para impressão gravadas em: {args.destino}")


if __name__ == "__main__":
    main()
