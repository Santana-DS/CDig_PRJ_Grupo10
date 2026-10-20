// ============================================================================
// IDENTIFICACAO DA PLANTA TERMICA — AQUISICAO PRBS FINAL
//
// O arquivo CSV gerado por este firmware possui o contrato:
//   t,Uh,Uc,Tp_raw,Ta_raw,n_adc
// com uma linha por segundo. Tp_raw e Ta_raw sao medias da janela de 1 s;
// portanto, nao ha filtro digital com memoria que possa acrescentar dinamica.
//
// Condicionamento analogico: RC de 2,2 kohm / 470 uF no sinal Tp do LM35
// (frequencia de corte aproximada de 0,154 Hz). A sequencia e a mesma do
// arquivo prbs.m: b=9, j=4 e permanencia m=100 s por simbolo.
// ============================================================================

#include <Arduino.h>

// --- Hardware e aquisicao ---------------------------------------------------
const int pinTp = 36, pinTa = 34;
const int pinHeater = 25, pinCooler = 26;
const uint32_t ADC_PERIOD_MS = 100;
const uint32_t LOG_PERIOD_MS = 1000;
const uint8_t ADC_OVERSAMPLE = 32;
const uint16_t ADC_INTER_SAMPLE_US = 200;
const int TOTAL_AMOSTRAS_ID = 31500;
const uint8_t PWM_RES_BITS = 16;
const uint32_t PWM_FREQUENCY_HZ = 1000;
// --- Atuador e limites fisicos ----------------------------------------------
// Tres resistores de 150 ohm / 1/4 W em paralelo, alimentados em 12 V.
const float TENSAO_AQUECEDOR_V = 12.0f;
const float RESISTENCIA_AQUECEDOR_OHM = 150.0f;
// Equivale a PWM = 900 em 12 bits: 0,211 W/resistor (84% de 1/4 W).
const uint32_t PWM_MAX_SEGURO = 14400;
const float POTENCIA_LIMITE_POR_RESISTOR_W =
    (TENSAO_AQUECEDOR_V * TENSAO_AQUECEDOR_V / RESISTENCIA_AQUECEDOR_OHM) *
    ((float)PWM_MAX_SEGURO / 65535.0f);
const float TEMPERATURA_CORTE_C = 60.0f;
// Faixa final definida apos o ensaio anterior: 8260--13860 levou a operacao
// cerca de 1,5 C abaixo do PO. A faixa abaixo preserva a excursao util e usa
// o teto eletrico seguro no nivel alto. Equivale aproximadamente a 575--900
// em 12 bits; o maximo dissipa 0,211 W por resistor de 150 ohm.
const uint32_t UH_LOW = 9200;
const uint32_t UH_HIGH = 14400;

// --- Gerador PRBS ------------------------------------------------------------
// Equivalente ao ramo b=9 de prbs.m:
// y=x(b); x <- [xor(y,x(b-j)), x(1:b-1)], com j=4.
// O estado inicial e fixo para que a identificacao seja reproduzivel.
const uint8_t PRBS_BITS = 9;
const uint16_t PRBS_HOLD_AMOSTRAS = 100;
uint8_t estadoPrbs[PRBS_BITS] = {
  1, 0, 1, 1, 0, 0, 1, 0, 1
};
uint16_t holdRestante = PRBS_HOLD_AMOSTRAS;
uint8_t bitPrbsAtual = estadoPrbs[PRBS_BITS - 1];
uint32_t uhAtual = bitPrbsAtual ? UH_HIGH : UH_LOW;
int amostraId = 0;
uint32_t inicio = 0, ultimoAdc = 0, ultimoLog = 0;
float somaTpJanela = 0.0f, somaTaJanela = 0.0f;
uint16_t nAdc = 0;
bool corteTermico = false;
bool paradaManual = false;

float lerTemperaturaC(int pin) {
  // Reduz quantizacao e ruido aleatorio; nao substitui o filtro RC analogico.
  uint32_t somaMv = 0;
  for (uint8_t i = 0; i < ADC_OVERSAMPLE; ++i) {
    somaMv += analogReadMilliVolts(pin);
    delayMicroseconds(ADC_INTER_SAMPLE_US);
  }
  return (somaMv / (float)ADC_OVERSAMPLE) / 10.0f;
}
void avancarPrbsProfessor() {
  // Com indices C (0 a 8), x(b-j)=x(5) corresponde ao indice 4.
  const uint8_t realimentacao = estadoPrbs[PRBS_BITS - 1] ^ estadoPrbs[4];
  for (int i = PRBS_BITS - 1; i > 0; --i) {
    estadoPrbs[i] = estadoPrbs[i - 1];
  }
  estadoPrbs[0] = realimentacao;
  bitPrbsAtual = estadoPrbs[PRBS_BITS - 1];
  uhAtual = bitPrbsAtual ? UH_HIGH : UH_LOW;
}

void atualizarPrbs() {
  if (--holdRestante == 0) {
    avancarPrbsProfessor();
    holdRestante = PRBS_HOLD_AMOSTRAS;
  }
  // A proxima linha CSV descrevera o PWM aplicado durante o proximo segundo.
  ledcWrite(0, uhAtual);
}

void setup() {
  Serial.begin(115200);
  analogReadResolution(12);
  analogSetPinAttenuation(pinTp, ADC_0db);
  analogSetPinAttenuation(pinTa, ADC_0db);
  ledcSetup(0, PWM_FREQUENCY_HZ, PWM_RES_BITS);  ledcAttachPin(pinHeater, 0);
  ledcSetup(1, PWM_FREQUENCY_HZ, PWM_RES_BITS);  ledcAttachPin(pinCooler, 1);
  ledcWrite(1, 0);

  inicio = millis();
  ultimoAdc = inicio;
  ultimoLog = inicio;
  ledcWrite(0, uhAtual);
  Serial.println("START_DATA");
  Serial.println("t,Uh,Uc,Tp_raw,Ta_raw,n_adc");
}

void loop() {
  if (Serial.available() > 0) {
    String comando = Serial.readStringUntil('\n');
    comando.trim();
    if (comando == "STOP") {
      paradaManual = true;
      ledcWrite(0, 0);
      ledcWrite(1, 0);
      Serial.println("PARADA_MANUAL");
      Serial.println("END_DATA");
    }
  }
  if (paradaManual) {
    while (true) delay(1000);
  }

  const uint32_t agora = millis();
  if (agora - ultimoAdc >= ADC_PERIOD_MS) {
    ultimoAdc += ADC_PERIOD_MS;
    const float tpBruto = lerTemperaturaC(pinTp);
    const float taBruto = lerTemperaturaC(pinTa);
    somaTpJanela += tpBruto;
    somaTaJanela += taBruto;
    if (!corteTermico && tpBruto >= TEMPERATURA_CORTE_C) {
      corteTermico = true;
      ledcWrite(0, 0);
      ledcWrite(1, 0);
      Serial.printf("ALARME_CORTE_TERMICO,Tp_raw=%.3f\n", tpBruto);
    }
    nAdc++;
  }

  if (agora - ultimoLog >= LOG_PERIOD_MS && nAdc > 0) {
    ultimoLog += LOG_PERIOD_MS;
    if (corteTermico) {
      Serial.println("END_DATA");
      while (true) delay(1000);
    }
    if (amostraId >= TOTAL_AMOSTRAS_ID) {
      ledcWrite(0, 0);
      ledcWrite(1, 0);
      Serial.println("END_DATA");
      while (true) delay(1000);
    }

    // Media exclusiva da janela de aquisicao de 1 s. Nao ha estado entre
    // linhas; este processamento nao introduz polo nem atraso digital.
    const float tpJanela = somaTpJanela / nAdc;
    const float taJanela = somaTaJanela / nAdc;
    Serial.printf("%d,%lu,0,%.3f,%.3f,%u\n",
                  amostraId, uhAtual, tpJanela, taJanela, nAdc);
    somaTpJanela = 0.0f;
    somaTaJanela = 0.0f;
    nAdc = 0;
    amostraId++;
    atualizarPrbs();
  }
}
