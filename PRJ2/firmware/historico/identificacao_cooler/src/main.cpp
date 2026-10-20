// PRJ2 - identificacao complementar da planta com cooler constante.
// Fase 0: regula 50 C; fase 1: estima o PWM de equilibrio;
// fase 2: aplica PRBS pequena em malha aberta ao redor desse equilibrio.

#include <Arduino.h>
#include <math.h>

namespace id_cooler {

constexpr uint8_t kPinTp = 36;
constexpr uint8_t kPinTa = 34;
constexpr uint8_t kPinAquecedor = 25;
constexpr uint8_t kPinCooler = 26;
constexpr uint8_t kCanalAquecedor = 0;
constexpr uint8_t kCanalCooler = 2;
constexpr uint16_t kConversoesAdc = 128;
constexpr uint32_t kTsMs = 5715;
constexpr uint32_t kDuracaoMs = 10800000;
constexpr uint32_t kInicioMediaMs = 1200000;
constexpr uint32_t kInicioPrbsMs = 1800000;
constexpr uint32_t kTimeoutComunicacaoMs = 15000;
constexpr double kReferenciaC = 50.0;
constexpr double kTemperaturaCorteC = 60.0;
constexpr uint16_t kPwmCooler = 3211;
constexpr double kAmplitudePrbs = 2500.0;
constexpr uint8_t kAmostrasPorBit = 2;
constexpr double kPwm16Max = 65535.0;

// Mesma sintonia refinada usada no ensaio principal; atua só na acomodação.
constexpr double kY0 = 50.50282999999999;
constexpr double kU0 = 9688.13559322;
constexpr double kNb = 1615.01542842;
constexpr double kKi = 55.87486056;
constexpr double kK1 = 2.42292827;
constexpr double kK2 = 37.30035107;
constexpr double kKq = 0.45467056;
constexpr double kTustin = 2.8575;
constexpr double kKaw = 0.01789714;
constexpr double kCseno1 = 1.30135744;
constexpr double kCseno2 = 5.41983902;
constexpr double kGTermicoPwm16 = 455.85236927;
constexpr double kAd1 = 0.97680948204771745;
constexpr double kAd2 = 0.83799947890809312;
constexpr double kBd1 = 0.012391015895003424;
constexpr double kBd2 = 0.011491559879183539;
constexpr double kA[4][4] = {
    {0.87148850627135255, -2.3349292179027987, 0.012391015895003424, 0},
    {-0.021460368525439675, 0.36223061019376079, 0.011491559879183539, 0},
    {0.54700065839072487, 12.12681339185988, 0.84668688848431295,
     5.4198390207695537},
    {0.098868116531183062, 2.1918715840409377, -0.052237956106038111,
     0.84668688848431295}};
constexpr double kBq[4] = {0.012391015895003424, 0.011491559879183539,
                            0, 0};
constexpr double kBy[4] = {101.15520303030875, 20.611544085060167,
                            -525.365078032665, -94.957574473786678};

struct EstadoControle {
  double z[4];
  double xiAnterior;
  double erroAnterior;
  double referenciaAnterior;
  double awAnterior;
  double qAtrasado;
};

EstadoControle controle;
bool coletando = false;
bool controleInicializado = false;
bool basePronta = false;
uint32_t inicioMs = 0;
uint32_t proximaAmostraMs = 0;
uint32_t ultimaComunicacaoMs = 0;
double somaPwm = 0;
uint16_t contagemPwm = 0;
double pwmBase = 0;
uint16_t amostraPrbs = 0;
int8_t sinalPrbs = 1;
uint8_t lfsr = 0x5A;  // Estado não nulo de uma sequência máxima de 7 bits.

double limitar(double valor, double minimo, double maximo) {
  return fmin(fmax(valor, minimo), maximo);
}

void desligarAtuadores() {
  ledcWrite(kCanalAquecedor, 0);
  ledcWrite(kCanalCooler, 0);
}

double lerTemperatura(uint8_t pino) {
  double somaMv = 0;
  for (uint16_t i = 0; i < kConversoesAdc; ++i) {
    somaMv += analogReadMilliVolts(pino);
    delayMicroseconds(1000);
  }
  return somaMv / (10.0 * kConversoesAdc);  // LM35: 10 mV/grau C.
}

void inicializarControle(double y) {
  const double entradaEquivalente = (y - kY0) * kGTermicoPwm16;
  controle.z[0] = kBd1 * entradaEquivalente / (1.0 - kAd1);
  controle.z[1] = kBd2 * entradaEquivalente / (1.0 - kAd2);
  controle.z[2] = 0;
  controle.z[3] = 0;
  controle.erroAnterior = kReferenciaC - y;
  controle.referenciaAnterior = kReferenciaC;
  controle.awAnterior = 0;
  controle.qAtrasado = -kU0;
  controle.xiAnterior = (controle.qAtrasado -
      kNb * (kReferenciaC - kY0) + kK1 * controle.z[0] +
      kK2 * controle.z[1] + kKq * controle.qAtrasado) / kKi;
}

double calcularControle(double y) {
  const double erro = kReferenciaC - y;
  const double erroIntegral = controle.referenciaAnterior - y;
  const double xi = controle.xiAnterior +
      kTustin * (controle.erroAnterior + erroIntegral) + controle.awAnterior;
  const double eSeno = kCseno1 * controle.z[2] + kCseno2 * controle.z[3];
  const double uLivre = kU0 + kNb * (kReferenciaC - kY0) + kKi * xi -
      kK1 * controle.z[0] - kK2 * controle.z[1] -
      kKq * controle.qAtrasado - eSeno;
  const double us = limitar(uLivre, 0.0, kPwm16Max);

  double zSeguinte[4] = {};
  for (uint8_t i = 0; i < 4; ++i) {
    zSeguinte[i] = kBq[i] * controle.qAtrasado + kBy[i] * (y - kY0);
    for (uint8_t j = 0; j < 4; ++j) {
      zSeguinte[i] += kA[i][j] * controle.z[j];
    }
  }
  for (uint8_t i = 0; i < 4; ++i) controle.z[i] = zSeguinte[i];
  controle.xiAnterior = xi;
  controle.erroAnterior = erro;
  controle.referenciaAnterior = kReferenciaC;
  controle.awAnterior = kKaw * (us - uLivre);
  controle.qAtrasado = us - kU0;
  return us;
}

int8_t proximoSinalPrbs() {
  // Polinômio x^7 + x^6 + 1: período de 127 bits para estado não nulo.
  const uint8_t realimentacao = ((lfsr >> 6) ^ (lfsr >> 5)) & 0x01;
  lfsr = static_cast<uint8_t>(((lfsr << 1) | realimentacao) & 0x7F);
  return (lfsr & 0x01) ? 1 : -1;
}

void encerrar(const char* motivo) {
  coletando = false;
  desligarAtuadores();
  Serial.println(motivo);
  Serial.println("END_DATA");
}

void iniciar() {
  desligarAtuadores();
  controleInicializado = false;
  basePronta = false;
  somaPwm = 0;
  contagemPwm = 0;
  pwmBase = 0;
  amostraPrbs = 0;
  sinalPrbs = 1;
  lfsr = 0x5A;
  inicioMs = millis();
  proximaAmostraMs = inicioMs;
  ultimaComunicacaoMs = inicioMs;
  coletando = true;
  Serial.println("START_DATA");
  Serial.println("CONFIG,PRJ2,IDENTIFICACAO_COOLER,Ts=5.715,W=3211,R=50,PRBS=2500,T=10800");
  Serial.println("t,fase,R,Y,Ta,U_base,du,Us,W");
}

}  // namespace id_cooler

void setup() {
  using namespace id_cooler;
  digitalWrite(kPinAquecedor, LOW);
  digitalWrite(kPinCooler, LOW);
  pinMode(kPinAquecedor, OUTPUT);
  pinMode(kPinCooler, OUTPUT);
  Serial.begin(115200);
  Serial.setTimeout(100);

  const uint32_t fa = ledcSetup(kCanalAquecedor, 1000, 16);
  const uint32_t fc = ledcSetup(kCanalCooler, 5000, 12);
  if (fa == 0 || fc == 0) {
    Serial.println("ALARME_CONFIG_PWM");
    return;
  }
  ledcAttachPin(kPinAquecedor, kCanalAquecedor);
  ledcAttachPin(kPinCooler, kCanalCooler);
  desligarAtuadores();
  analogReadResolution(12);
  analogSetPinAttenuation(kPinTp, ADC_0db);
  analogSetPinAttenuation(kPinTa, ADC_0db);
  Serial.println("READY: PRJ2_IDENTIFICACAO_COOLER");
}

void loop() {
  using namespace id_cooler;

  if (!coletando) desligarAtuadores();
  if (Serial.available() > 0) {
    String comando = Serial.readStringUntil('\n');
    comando.trim();
    if (comando == "START" && !coletando) iniciar();
    else if (comando == "STOP" && coletando) encerrar("PARADA_MANUAL");
    else if (comando == "HEARTBEAT" && coletando) ultimaComunicacaoMs = millis();
  }
  if (!coletando) return;

  const uint32_t agoraMs = millis();
  if (agoraMs - ultimaComunicacaoMs > kTimeoutComunicacaoMs) {
    encerrar("ALARME_COMUNICACAO");
    return;
  }
  if (agoraMs - inicioMs >= kDuracaoMs) {
    encerrar("FIM_NORMAL");
    return;
  }
  if (static_cast<int32_t>(agoraMs - proximaAmostraMs) < 0) return;

  const uint32_t decorridoMs = agoraMs - inicioMs;
  const double tempoS = decorridoMs / 1000.0;
  const double y = lerTemperatura(kPinTp);
  const double ta = lerTemperatura(kPinTa);
  if (!isfinite(y) || !isfinite(ta) || y < -10 || y > 100 ||
      ta < -10 || ta > 100) {
    encerrar("ALARME_SENSOR");
    return;
  }
  if (y >= kTemperaturaCorteC) {
    encerrar("ALARME_TEMPERATURA_PROCESSO");
    return;
  }

  if (!controleInicializado) {
    inicializarControle(y);
    controleInicializado = true;
  }

  uint8_t fase = 0;
  double du = 0;
  double us = 0;
  if (decorridoMs < kInicioPrbsMs) {
    fase = (decorridoMs < kInicioMediaMs) ? 0 : 1;
    us = calcularControle(y);
    if (decorridoMs >= kInicioMediaMs) {
      somaPwm += us;
      ++contagemPwm;
      pwmBase = somaPwm / contagemPwm;
    }
  } else {
    fase = 2;
    if (!basePronta) {
      if (contagemPwm < 40 || pwmBase < 5000 || pwmBase > 50000) {
        encerrar("ALARME_PWM_BASE");
        return;
      }
      basePronta = true;
      Serial.printf("BASE_PWM,%.1f,%u\n", pwmBase, contagemPwm);
    }
    if (amostraPrbs % kAmostrasPorBit == 0) sinalPrbs = proximoSinalPrbs();
    du = sinalPrbs * kAmplitudePrbs;
    us = limitar(pwmBase + du, 0.0, kPwm16Max);
    ++amostraPrbs;
  }

  ledcWrite(kCanalCooler, kPwmCooler);
  ledcWrite(kCanalAquecedor, static_cast<uint32_t>(lround(us)));
  Serial.printf("%.3f,%u,%.1f,%.4f,%.4f,%.1f,%.1f,%.0f,%u\n",
      tempoS, fase, kReferenciaC, y, ta, pwmBase, du, us, kPwmCooler);
  proximaAmostraMs += kTsMs;
}
