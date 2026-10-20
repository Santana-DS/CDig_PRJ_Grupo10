// ============================================================================
// ETAPA 07 - LEI DE CONTROLE PI DISCRETO ZOH
//
// Projeto discreto: C(z)=1700(z-0,922)/(z-1), Ts=Td/2=2,8575 s.
// Forma incremental em PWM bruto de 16 bits:
//   u[k] = u[k-1] + 1700 e[k] - 1567,4 e[k-1].
//
// Altere somente ANTI_WINDUP_ATIVO para comparar os dois ensaios.
// A telemetria segue o contrato: t,R,Y,U,U_s,W,Ta,e.
// ============================================================================

#include <Arduino.h>

// --- Selecao do ensaio -------------------------------------------------------
constexpr bool ANTI_WINDUP_ATIVO = true;

// --- Hardware e leitura ------------------------------------------------------
constexpr int PIN_TP = 36;
constexpr int PIN_TA = 34;
constexpr int PIN_AQUECEDOR = 25;
constexpr int PIN_COOLER = 26;
// O canal 2 usa outro temporizador e isola o PWM do cooler do aquecedor.
constexpr uint8_t CANAL_AQUECEDOR = 0;
constexpr uint8_t CANAL_COOLER = 2;
// Media restrita a cada leitura: atenua ruido sem introduzir memoria digital.
constexpr uint8_t ADC_OVERSAMPLE = 128;
constexpr uint16_t ADC_INTER_SAMPLE_US = 1000;

// --- Controlador PI ZOH ------------------------------------------------------
// 2858 ms e a aproximacao inteira de 2,8575 s no agendador do ESP32.
constexpr uint32_t TS_CONTROLE_MS = 2858;
constexpr float PI_B0 = 1700.0f;
constexpr float PI_B1 = -1567.4f;

// --- Atuadores e roteiro -----------------------------------------------------
constexpr uint8_t PWM_AQUECEDOR_BITS = 16;
constexpr uint32_t PWM_AQUECEDOR_FREQUENCY_HZ = 1000;
constexpr uint8_t PWM_COOLER_BITS = 12;
constexpr uint32_t PWM_COOLER_FREQUENCY_HZ = 5000;
constexpr uint32_t PWM_AQUECEDOR_MAX = 65535;
constexpr uint32_t DURACAO_ENSAIO_S = 3600;
constexpr float REFERENCIA_BAIXA_C = 45.0f;
constexpr float REFERENCIA_ALTA_C = 55.0f;

// Histerese medida do cooler: partida 2408 e parada 1445 em 12 bits.
constexpr uint32_t COOLER_OPERACIONAL_MIN = 2248;
constexpr uint32_t COOLER_OPERACIONAL_MAX = 3854;
constexpr uint32_t COOLER_NOMINAL = 3211;
constexpr uint32_t COOLER_SENOIDE_CENTRO = 3051;
constexpr uint32_t COOLER_AMPLITUDE = 803;
constexpr float PERIODO_SENOIDE_S = 64.0f;

uint32_t inicioEnsaioMs = 0;
uint32_t ultimoControleMs = 0;
bool ensaioAtivo = false;
bool finalizado = false;
bool pwmConfigurado = false;
float erroAnterior = 0.0f;
float estadoInternoU = 0.0f;

float limitar(float valor, float minimo, float maximo) {
  return min(max(valor, minimo), maximo);
}

float lerTemperaturaC(int pino) {
  uint32_t somaMv = 0;
  for (uint8_t i = 0; i < ADC_OVERSAMPLE; ++i) {
    somaMv += analogReadMilliVolts(pino);
    delayMicroseconds(ADC_INTER_SAMPLE_US);
  }
  return (somaMv / static_cast<float>(ADC_OVERSAMPLE)) / 10.0f;
}

float referenciaDoEnsaio(float tEnsaioS) {
  const uint32_t bloco = static_cast<uint32_t>(tEnsaioS / 400.0f);
  return (bloco % 2U == 0U) ? REFERENCIA_BAIXA_C : REFERENCIA_ALTA_C;
}

uint32_t perturbacaoDoEnsaio(float tEnsaioS) {
  if (tEnsaioS < 1000.0f) return 0;
  if (tEnsaioS < 1800.0f) return COOLER_NOMINAL;
  if (tEnsaioS < 3000.0f) {
    const float senoide = sinf(2.0f * PI * (tEnsaioS - 1800.0f) /
                               PERIODO_SENOIDE_S);
    return static_cast<uint32_t>(limitar(
        COOLER_SENOIDE_CENTRO + COOLER_AMPLITUDE * senoide,
        static_cast<float>(COOLER_OPERACIONAL_MIN),
        static_cast<float>(COOLER_OPERACIONAL_MAX)));
  }
  return COOLER_NOMINAL;
}

void desligarAtuadores() {
  ledcWrite(CANAL_AQUECEDOR, 0);
  ledcWrite(CANAL_COOLER, 0);
}

void finalizarEnsaio(const char* motivo) {
  if (finalizado) return;
  desligarAtuadores();
  Serial.println(motivo);
  Serial.println("END_DATA");
  finalizado = true;
}

void atualizarControle(uint32_t agoraMs);

void iniciarEnsaio() {
  desligarAtuadores();
  estadoInternoU = 0.0f;
  erroAnterior = 0.0f;
  inicioEnsaioMs = millis();
  ultimoControleMs = inicioEnsaioMs;
  ensaioAtivo = true;
  Serial.println("START_DATA");
  Serial.printf("CONFIG,AW=%d,Ts=%.3f,Kd=%.1f,zd=%.3f\n",
                ANTI_WINDUP_ATIVO ? 1 : 0, TS_CONTROLE_MS / 1000.0f,
                PI_B0, -PI_B1 / PI_B0);
  Serial.println("t,R,Y,U,U_s,W,Ta,e");
  // A amostra inicial pertence a t=0; as proximas ocorrem a cada Ts.
  atualizarControle(inicioEnsaioMs);
}

void atualizarControle(uint32_t agoraMs) {
  const float tEnsaioS = (agoraMs - inicioEnsaioMs) / 1000.0f;
  if (tEnsaioS >= DURACAO_ENSAIO_S) {
    finalizarEnsaio("FIM_NORMAL");
    return;
  }

  const float referencia = referenciaDoEnsaio(tEnsaioS);
  const uint32_t pwmCooler = perturbacaoDoEnsaio(tEnsaioS);
  const float temperaturaProcesso = lerTemperaturaC(PIN_TP);
  const float temperaturaAmbiente = lerTemperaturaC(PIN_TA);
  const float erro = referencia - temperaturaProcesso;

  const float uCalculado = estadoInternoU + PI_B0 * erro +
                            PI_B1 * erroAnterior;
  const float uSaturado = limitar(uCalculado, 0.0f,
                                  static_cast<float>(PWM_AQUECEDOR_MAX));

  // Com AW, o estado acompanha a saida saturada; sem AW, acumula U calculado.
  estadoInternoU = ANTI_WINDUP_ATIVO ? uSaturado : uCalculado;
  erroAnterior = erro;
  ledcWrite(CANAL_AQUECEDOR, static_cast<uint32_t>(uSaturado));
  ledcWrite(CANAL_COOLER, pwmCooler);

  Serial.printf("%.3f,%.3f,%.3f,%.3f,%.3f,%lu,%.3f,%.3f\n",
                tEnsaioS, referencia, temperaturaProcesso, uCalculado,
                uSaturado, pwmCooler, temperaturaAmbiente, erro);
}

void setup() {
  Serial.begin(115200);
  analogReadResolution(12);
  analogSetPinAttenuation(PIN_TP, ADC_0db);
  analogSetPinAttenuation(PIN_TA, ADC_0db);

  const uint32_t frequenciaAquecedor = ledcSetup(
      CANAL_AQUECEDOR, PWM_AQUECEDOR_FREQUENCY_HZ, PWM_AQUECEDOR_BITS);
  const uint32_t frequenciaCooler = ledcSetup(
      CANAL_COOLER, PWM_COOLER_FREQUENCY_HZ, PWM_COOLER_BITS);
  if (frequenciaAquecedor == 0 || frequenciaCooler == 0) {
    desligarAtuadores();
    Serial.printf("ALARME_CONFIG_PWM,aquecedor=%lu,cooler=%lu\n",
                  frequenciaAquecedor, frequenciaCooler);
    return;
  }

  ledcAttachPin(PIN_AQUECEDOR, CANAL_AQUECEDOR);
  ledcAttachPin(PIN_COOLER, CANAL_COOLER);
  desligarAtuadores();
  pwmConfigurado = true;
  Serial.println("READY: atuadores desligados; monitoramento envia START.");
}

void loop() {
  if (!pwmConfigurado) {
    delay(20);
    return;
  }

  if (Serial.available() > 0) {
    String comando = Serial.readStringUntil('\n');
    comando.trim();
    if (comando == "START" && !ensaioAtivo && !finalizado) {
      iniciarEnsaio();
    } else if (comando == "STOP") {
      finalizarEnsaio("PARADA_MANUAL");
    }
  }
  if (!ensaioAtivo || finalizado) {
    delay(20);
    return;
  }

  const uint32_t agoraMs = millis();
  if (agoraMs - ultimoControleMs >= TS_CONTROLE_MS) {
    ultimoControleMs += TS_CONTROLE_MS;
    atualizarControle(agoraMs);
  }
}
