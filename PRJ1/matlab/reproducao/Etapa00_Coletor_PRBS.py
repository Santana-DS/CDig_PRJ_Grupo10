"""Coletor serial da identificacao PRBS V2 da planta termica.

O firmware correspondente e ``src/main.cpp``. Este programa grava somente
linhas de dados no CSV, preserva o cabecalho do protocolo e envia ``STOP`` ao
ESP32 quando a coleta e interrompida por Ctrl+C.

Ensaio conforme o roteiro: N=31500, Ti=1 s e PRBS b=9, j=4, m=100 s.
O CSV final so e publicado depois de validada uma coleta completa.
"""

from pathlib import Path
import ctypes
import math
import time
import serial

PORTA = "COM3"
BAUD = 115200
PASTA = Path(__file__).resolve().parent
RAIZ_PROJETO = PASTA.parent.parent
SAIDA = RAIZ_PROJETO / "dados" / "ensaio_prbs_v2_b9_m100_u7000_12200.csv"
PARCIAL = SAIDA.with_suffix(".partial.csv")
COLUNAS = "t,Uh,Uc,Tp_raw,Ta_raw,n_adc"
N_AMOSTRAS = 31500
N_ADC_ESPERADO = 10
NIVEIS_PWM = {7000, 12200}

ES_CONTINUOUS = 0x80000000
ES_SYSTEM_REQUIRED = 0x00000001


def validar_linha(linha: str, indice_esperado: int) -> None:
    """Valida uma linha do contrato CSV antes de persistir o dado bruto."""
    campos = linha.split(",")
    if len(campos) != 6:
        raise ValueError(f"CSV invalido: esperadas 6 colunas, obtidas {len(campos)}.")
    try:
        t, uh, uc, tp, ta, n_adc = [float(campo) for campo in campos]
    except ValueError:
        raise ValueError("CSV invalido: campo nao numerico.") from None
    if not all(math.isfinite(valor) for valor in (t, uh, uc, tp, ta, n_adc)):
        raise ValueError("CSV invalido: valor nao finito.")
    if int(t) != indice_esperado or t != int(t):
        raise ValueError(f"Tempo invalido: recebido {t}, esperado {indice_esperado}.")
    if int(uh) not in NIVEIS_PWM or uh != int(uh):
        raise ValueError(f"PWM PRBS invalido: {uh}.")
    if uc != 0:
        raise ValueError(f"Cooler deveria estar desligado na identificacao: Uc={uc}.")
    if int(n_adc) != N_ADC_ESPERADO or n_adc != int(n_adc):
        raise ValueError(f"n_adc invalido: {n_adc}, esperado {N_ADC_ESPERADO}.")


def manter_sistema_ativo(ativo: bool) -> None:
    """Inibe ou libera suspensao do Windows sem alterar a configuracao global."""
    estado = ES_CONTINUOUS | ES_SYSTEM_REQUIRED if ativo else ES_CONTINUOUS
    if ctypes.windll.kernel32.SetThreadExecutionState(estado) == 0:
        print("[AVISO] Windows nao confirmou a inibicao de suspensao.")


def main() -> None:
    """Registra e valida a coleta entre START_DATA e END_DATA."""
    if SAIDA.exists():
        raise FileExistsError(
            f"Arquivo final ja existe e nao sera sobrescrito: {SAIDA.resolve()}"
        )
    if PARCIAL.exists():
        linhas_parciais = PARCIAL.read_text(encoding="utf-8", errors="ignore").splitlines()
        if len(linhas_parciais) <= 1:
            PARCIAL.unlink()
        else:
            raise FileExistsError(
                "Arquivo parcial com dados existente; analise ou remova antes "
                f"de reiniciar: {PARCIAL.resolve()}"
            )

    coleta_valida = False
    manter_sistema_ativo(True)
    try:
        SAIDA.parent.mkdir(parents=True, exist_ok=True)
        with serial.Serial(PORTA, BAUD, timeout=1) as ser, PARCIAL.open(
            "w", encoding="utf-8", newline=""
        ) as arquivo:
            coletando = False
            n_linhas = 0
            falha_firmware = ""
            limite_inicio = time.monotonic() + 20
            ultima_linha = time.monotonic()
            fim_coleta = False
            print("[INFO] Aguardando START_DATA da ESP32...")
            try:
                while not fim_coleta:
                    bruto = ser.readline()
                    if not bruto:
                        agora = time.monotonic()
                        if not coletando and agora > limite_inicio:
                            raise RuntimeError("START_DATA nao recebido em 20 s.")
                        if coletando and agora - ultima_linha > 5:
                            raise RuntimeError("Telemetria interrompida por mais de 5 s.")
                        continue

                    linha = bruto.decode("utf-8", errors="ignore").strip()
                    if not linha:
                        continue
                    if linha == "START_DATA":
                        if coletando:
                            raise RuntimeError("START_DATA duplicado.")
                        coletando = True
                        arquivo.write(COLUNAS + "\n")
                        arquivo.flush()
                        ultima_linha = time.monotonic()
                        print(f"[INFO] Coleta iniciada: {SAIDA.resolve()}")
                        continue
                    if linha == COLUNAS:
                        ultima_linha = time.monotonic()
                        continue
                    if linha.startswith("ALARME_CORTE_TERMICO") or linha == "PARADA_MANUAL":
                        falha_firmware = linha
                        print(f"[ERRO] Firmware interrompeu a coleta: {linha}")
                        continue
                    if linha == "END_DATA":
                        if not coletando:
                            raise RuntimeError("END_DATA recebido antes de START_DATA.")
                        if falha_firmware:
                            raise RuntimeError(f"Coleta interrompida: {falha_firmware}")
                        fim_coleta = True
                        continue
                    if coletando and linha:
                        validar_linha(linha, n_linhas)
                        arquivo.write(linha + "\n")
                        n_linhas += 1
                        ultima_linha = time.monotonic()
            except KeyboardInterrupt:
                ser.write(b"STOP\n")
                ser.flush()
                raise RuntimeError("Coleta interrompida pelo operador; STOP enviado ao ESP32.") from None

            if n_linhas != N_AMOSTRAS:
                raise RuntimeError(
                    f"Coleta incompleta: {n_linhas} linhas; esperadas {N_AMOSTRAS}."
                )
            arquivo.flush()
            coleta_valida = True
    except (OSError, RuntimeError, ValueError, serial.SerialException) as erro:
        print(f"[ERRO] CSV final nao foi publicado: {erro}")
    finally:
        if coleta_valida:
            PARCIAL.replace(SAIDA)
            print(f"[INFO] Coleta validada e salva: {SAIDA.resolve()}")
        manter_sistema_ativo(False)
        print("[INFO] Inibicao de suspensao liberada.")


if __name__ == "__main__":
    main()
