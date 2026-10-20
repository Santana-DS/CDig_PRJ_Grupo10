// PRJ2 - controle digital do processo termico.
// Implementa o controlador, o anti-windup e os observadores validados
// no modelo Prj2CDig_discreto_PRJ2.slx.

#include <Arduino.h>
#include <math.h>

namespace prj2 {

// Hardware e temporizacao.
constexpr uint8_t kPinTp = 36;
constexpr uint8_t kPinTa = 34;
constexpr uint8_t kPinAquecedor = 25;
constexpr uint8_t kPinCooler = 26;
constexpr uint8_t kCanalAquecedor = 0;
constexpr uint8_t kCanalCooler = 2;
constexpr uint16_t kConversoesAdc = 128;
constexpr uint32_t kTsMs = 5715;
constexpr uint32_t kDuracaoMs = 3600000;
constexpr uint32_t kTimeoutComunicacaoMs = 15000;
constexpr double kTemperaturaCorteC = 62.0;

// Parametros do controlador refinado.
constexpr double kY0 = 50.50282999999999;
constexpr double kU0 = 9688.13559322;
constexpr double kNb = 1615.01542842;
constexpr double kKi = 55.87486056;
constexpr double kK1 = 2.42292827;
constexpr double kK2 = 37.30035107;
constexpr double kKq = 0.45467056;
constexpr double kTustin = 2.8575;  // Ts/2.
constexpr double kKaw = 0.01789714;
constexpr double kCseno1 = 1.30135744;
constexpr double kCseno2 = 5.41983902;
constexpr double kPwm16Max = 65535.0;
constexpr double kGTermicoPwm16 = 455.85236927;
constexpr double kAd1 = 0.97680948204771745;
constexpr double kAd2 = 0.83799947890809312;
constexpr double kBd1 = 0.012391015895003424;
constexpr double kBd2 = 0.011491559879183539;

// Observador aumentado: [x1, x2, s1, s2].
constexpr double kA[4][4] = {
    {0.87148850627135255, -2.3349292179027987, 0.012391015895003424, 0},
    {-0.021460368525439675, 0.36223061019376079, 0.011491559879183539, 0},
    {0.54700065839072487, 12.12681339185988, 0.84668688848431295, 5.4198390207695537},
    {0.098868116531183062, 2.1918715840409377, -0.052237956106038111, 0.84668688848431295}};
constexpr double kBq[4] = {0.012391015895003424, 0.011491559879183539, 0, 0};
constexpr double kBy[4] = {101.15520303030875, 20.611544085060167,
                            -525.365078032665, -94.957574473786678};
constexpr double kCy[2] = {0.0010411819918428509, 0.023082640812882287};

struct Estado {
  double z[4];
  double xiAnterior;
  double erroAnterior;
  double referenciaAnterior;
  double awAnterior;
  double qAtrasado;
};

struct Saida {
  double erro;
  double xi;
  double uLivre;
  double us;
  double eSeno;
  double inovacao;
  double x1;
  double x2;
};

Estado estado;
bool coletando = false;
bool estadoInicializado = false;
uint32_t inicioMs = 0;
uint32_t proximaAmostraMs = 0;
uint32_t ultimaComunicacaoMs = 0;
uint16_t indice = 0;

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

double referencia(uint16_t amostra) {
  // Alternancia 45/55 graus C a cada 70 amostras (400,05 s).
  return ((amostra / 70U) % 2U == 0U) ? 45.0 : 55.0;
}

uint16_t comandoCooler(double tempoS) {
  if (tempoS < 1000.0) return 0;
  if (tempoS < 1800.0 || tempoS >= 3000.0) return 3211;
  const double seno = sin(2.0 * PI * (tempoS - 1800.0) / 64.0);
  return static_cast<uint16_t>(limitar(3051.0 + 803.0 * seno, 2248.0, 3854.0));
}

void inicializarEstados(double y, double r) {
  // Equilibrio coerente com a temperatura real no inicio do ensaio.
  const double entradaEquivalente = (y - kY0) * kGTermicoPwm16;
  estado.z[0] = kBd1 * entradaEquivalente / (1.0 - kAd1);
  estado.z[1] = kBd2 * entradaEquivalente / (1.0 - kAd2);
  estado.z[2] = 0;
  estado.z[3] = 0;
  estado.erroAnterior = r - y;
  estado.referenciaAnterior = r;
  estado.awAnterior = 0;
  estado.qAtrasado = -kU0;
  estado.xiAnterior = (estado.qAtrasado - kNb * (r - kY0) +
      kK1 * estado.z[0] + kK2 * estado.z[1] +
      kKq * estado.qAtrasado) / kKi;
}

Saida calcularControle(double r, double y) {
  const double x1 = estado.z[0];
  const double x2 = estado.z[1];
  const double erro = r - y;
  const double erroIntegral = estado.referenciaAnterior - y;
  const double xi = estado.xiAnterior +
      kTustin * (estado.erroAnterior + erroIntegral) + estado.awAnterior;
  const double eSeno = kCseno1 * estado.z[2] + kCseno2 * estado.z[3];
  const double yEstimado = kCy[0] * estado.z[0] + kCy[1] * estado.z[1];
  const double uLivre = kU0 + kNb * (r - kY0) + kKi * xi -
      kK1 * estado.z[0] - kK2 * estado.z[1] -
      kKq * estado.qAtrasado - eSeno;
  const double us = limitar(uLivre, 0.0, kPwm16Max);

  double zSeguinte[4] = {};
  for (uint8_t i = 0; i < 4; ++i) {
    zSeguinte[i] = kBq[i] * estado.qAtrasado + kBy[i] * (y - kY0);
    for (uint8_t j = 0; j < 4; ++j) {
      zSeguinte[i] += kA[i][j] * estado.z[j];
    }
  }
  for (uint8_t i = 0; i < 4; ++i) estado.z[i] = zSeguinte[i];
  estado.xiAnterior = xi;
  estado.erroAnterior = erro;
  estado.referenciaAnterior = r;
  estado.awAnterior = kKaw * (us - uLivre);
  estado.qAtrasado = us - kU0;

  return {erro, xi, uLivre, us, eSeno, y - kY0 - yEstimado, x1, x2};
}

void encerrar(const char* motivo) {
  coletando = false;
  desligarAtuadores();
  Serial.println(motivo);
  Serial.println("END_DATA");
}

void iniciar() {
  desligarAtuadores();
  indice = 0;
  estadoInicializado = false;
  inicioMs = millis();
  proximaAmostraMs = inicioMs;
  ultimaComunicacaoMs = inicioMs;
  coletando = true;
  Serial.println("START_DATA");
  Serial.println("CONFIG,PRJ2,CONTROLE_DISCRETO,Ts=5.715,Tcorte=62.0");
  Serial.println("t,R,Y,Ta,U_livre,Us,W,e,xi,x1hat,x2hat,e_sin,inovacao");
}

}  // namespace prj2

void setup() {
  using namespace prj2;
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
  Serial.println("READY: PRJ2_CONTROLE_DISCRETO");
}

void loop() {
  using namespace prj2;

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

  const double tempoS = (agoraMs - inicioMs) / 1000.0;
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

  const double r = referencia(indice);
  if (!estadoInicializado) {
    inicializarEstados(y, r);
    estadoInicializado = true;
  }
  const uint16_t w = comandoCooler(tempoS);
  const Saida s = calcularControle(r, y);
  ledcWrite(kCanalAquecedor, static_cast<uint32_t>(s.us));
  ledcWrite(kCanalCooler, w);

  Serial.printf("%.3f,%.4f,%.4f,%.4f,%.4f,%.0f,%u,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f\n",
      tempoS, r, y, ta, s.uLivre, s.us, w, s.erro, s.xi,
      s.x1, s.x2, s.eSeno, s.inovacao);
  ++indice;
  proximaAmostraMs += kTsMs;
}
