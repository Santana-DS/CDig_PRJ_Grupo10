function ensaio = simular_malha_discreta(cenario, compensarSenoide, usarAW)
%SIMULAR_MALHA_DISCRETA Simula a malha amostrada com atraso e saturação.
%   Cenários: seguimento, perturbacao e saturacao. Esta é uma simulação
%   numérica do modelo identificado, não uma validação física da bancada.

if nargin < 1, cenario = "seguimento"; end
if nargin < 2, compensarSenoide = true; end
if nargin < 3, usarAW = true; end
cenario = string(cenario);
assert(ismember(cenario, ["seguimento", "perturbacao", "saturacao"]), ...
    'Cenário desconhecido.');

pasta = fileparts(mfilename('fullpath'));
raizProjeto = fileparts(fileparts(fileparts(pasta)));
artefatos = fullfile(raizProjeto, 'resultados', 'artefatos');
sModelo = load(fullfile(artefatos, 'modelos_discretos.mat'), 'discreto');
sControle = load(fullfile(artefatos, 'controlador_discreto.mat'), ...
    'controle');
d = sModelo.discreto;
c = sControle.controle;
sPlanta = load(d.modeloOrigem, 'resultado');
sContinuo = load(d.projetoOrigem, 'projeto');
h = sPlanta.resultado.parametros;
u0 = sPlanta.resultado.u0;
y0 = sPlanta.resultado.y0;
Ts = d.Ts;

duracao = 1800;
if cenario == "seguimento", duracao = 700; end
if cenario == "saturacao", duracao = 900; end
t = (0:Ts:duracao)';
n = numel(t);
referencia = zeros(n, 1);
temperatura = zeros(n, 1);
perturbacao = zeros(n, 1);
uLivre = zeros(n, 1);
uAplicado = zeros(n, 1);
estimativaPerturbacao = zeros(n, 1);
inovacao = zeros(n, 1);

% Partida próxima ao equilíbrio de 50 °C, sem transitório artificial.
PO = 50;
q = (PO-y0)/h.Kp;
x = -(sContinuo.projeto.A \ sContinuo.projeto.B)*q;
xEstimado = [x; 0; 0];
xi = (q - c.Nb*(PO-y0) + c.F(1:2)*x + c.Kq*q)/c.Ki;

for k = 1:n
    [r, w] = sinais(cenario, t(k), d.Ts);
    y = y0 + d.Cd*x;
    erro = r-y;
    inovacao(k) = y-y0-d.Cod*xEstimado;

    % q é o comando anterior, já saturado. Prever a perturbação um passo
    % à frente compensa a latência do aquecedor quando o observador converge.
    wEstimado = xEstimado(3);
    wFuturo = d.Fd(1, :)*xEstimado(3:4);
    compensacao = 0;
    if compensarSenoide
        compensacao = c.Kq*wEstimado + wFuturo;
    end
    uLivre(k) = u0 + c.Nb*(r-y0) - c.F(1:2)*xEstimado(1:2) ...
        - c.Kq*q + c.Ki*xi - compensacao;
    uAplicado(k) = min(max(uLivre(k), d.atuador.minPWM16), ...
        d.atuador.maxPWM16);
    estimativaPerturbacao(k) = h.Kp*wEstimado;
    referencia(k) = r;
    temperatura(k) = y;
    perturbacao(k) = w;

    qProximo = uAplicado(k)-u0;
    xProximo = d.Ad*x + d.Bd*(q + w/h.Kp);
    xEstimadoProximo = d.Aod*xEstimado + d.Bod*q + ...
        d.Ld*inovacao(k);
    erroProximo = r-(y0+d.Cd*xProximo);  % Referência mantida no intervalo.
    if usarAW
        xi = atualizar_integrador_aw(xi, erroProximo, erro, ...
            uLivre(k), uAplicado(k), c.Ki, Ts, ...
            d.integrador.tempoRastreamentoInicial);
    else
        xi = xi + Ts/2*(erro + erroProximo);
    end
    x = xProximo;
    q = qProximo;
    xEstimado = xEstimadoProximo;
end

ensaio = struct('cenario', cenario, 'observadorAtivo', ...
    logical(compensarSenoide), 'antiWindupAtivo', logical(usarAW), ...
    't', t, 'referencia', referencia, 'temperatura', temperatura, ...
    'perturbacaoTermica', perturbacao, 'uLivre', uLivre, ...
    'uAplicado', uAplicado, 'estimativaPerturbacao', ...
    estimativaPerturbacao, 'inovacao', inovacao, ...
    'amostrasSaturadas', nnz(abs(uLivre-uAplicado) > 1e-9));
end

function [r, w] = sinais(cenario, t, Ts)
% w é a perturbação térmica equivalente, em graus Celsius.
r = 50; w = 0;
switch cenario
    case "seguimento"
        if t >= 200-Ts/2, r = 55; end
    case "perturbacao"
        if t >= 200-Ts/2, w = -10; end
        if t >= 700-Ts/2 && t < 1500-Ts/2
            w = -10 + 10*sin(2*pi*(t-700)/64);
        end
    case "saturacao"
        if t >= 200-Ts/2 && t < 500-Ts/2, r = 100; end
end
end
