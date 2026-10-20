function projeto = ETAPA02_projetar_controle_continuo(abrirModelo)
%PROJETAR_CONTINUO_INICIAL Projeto nominal em EE para o processo P2DZ.
%   Aloca os polos do controlador aumentado e do observador senoidal.
%   Esta etapa contínua segue o roteiro: ainda não inclui atraso, saturação
%   nem anti-windup. Esses efeitos serão tratados no projeto discreto.
%   Ao final, parametriza e abre o modelo contínuo fornecido pelo professor.

if nargin < 1
    abrirModelo = true;
end

pasta = fileparts(mfilename('fullpath'));
raizProjeto = fileparts(fileparts(pasta));
apoio = fullfile(raizProjeto, 'resultados', 'artefatos');
fonte = fullfile(apoio, 'planta_p2dz.mat');
assert(isfile(fonte), 'Execute ETAPA01_identificar_planta_nominal antes.');
s = load(fonte, 'resultado');
h = s.resultado.parametros;

% Realização modal usada no diagrama Prj2CDig do professor.
modal1 = (h.Tz - h.Tp1) / (h.Tp2 - h.Tp1);
modal2 = 1 - modal1;
A = diag([-1/h.Tp1, -1/h.Tp2]);
B = h.Kp * [1; 1];
C = [modal1/h.Tp1, modal2/h.Tp2];
assert(rank(ctrb(A, B)) == 2, 'Planta não controlável.');
assert(rank(obsv(A, C)) == 2, 'Planta não observável.');
assert(abs(dcgain(ss(A, B, C, 0)) - h.Kp) < 1e-10, ...
    'A realização modal não preserva o ganho identificado.');

% xi_dot = r - y; u = Nb*r - K*x + Ki*xi.
Aa = [A, zeros(2, 1); -C, 0];
Ba = [B; 0];
assert(rank(ctrb(Aa, Ba)) == 3, 'Planta com integrador não controlável.');

TrAlvo = 20;  % 10% a 90%, Grupo 10.
pResposta = -log(9) / TrAlvo;
pCancelado = pResposta / 3;
pZero = -1 / h.Tz;
Ka = place(Aa, Ba, [pCancelado, pZero, pResposta]);
K = Ka(1:2);
Ki = -Ka(3);
Nb = -Ki / pCancelado;

% A planta fornece o zero em pZero; Nb*r + Ki*xi fornece o zero em
% pCancelado. Assim, a transferência nominal r -> y fica de 1ª ordem.
Acl = [A - B*K, B*Ki; -C, 0];
Bcl = [B*Nb; 1];
Tref = ss(Acl, Bcl, [C, 0], 0);
info = stepinfo(Tref, 'RiseTimeLimits', [0.1, 0.9]);

% Oscilador: w = xs1, xs1_dot = xs2, xs2_dot = -w0^2*xs1.
% A perturbação entra pelo mesmo canal da entrada térmica equivalente.
w0 = 2*pi/64;
As = [0, 1; -w0^2, 0];
Cs = [1, 0];
Ao = [A, B*Cs; zeros(2, 2), As];
Bo = [B; 0; 0];
Co = [C, 0, 0];
assert(rank(obsv(Ao, Co)) == 4, 'Observador aumentado não observável.');
condObservabilidade = cond(obsv(Ao, Co));

% Polos distintos evitam a fragilidade numérica dos polos repetidos do
% exemplo didático. Esta semente moderada limita a amplificação de ruído;
% a escolha será refinada com atraso e ruído medido.
polosObservador = [-0.04, -0.05, -0.06, -0.07];
L = place(Ao', Co', polosObservador)';

% A amplitude abaixo é uma estimativa inicial de u no instante do degrau,
% antes de os estados responderem. O limite real será testado em simulação.
u0 = s.resultado.u0;
uInicialMais5 = u0 + 5*Nb;
uEq45 = u0 - 5/h.Kp;
uInicial45para55 = uEq45 + 10*Nb;
modeloSimulink = fullfile(raizProjeto, 'simulink', ...
    'Prj2CDig_continuo_professor.slx');

projeto = struct( ...
    'A', A, 'B', B, 'C', C, 'Aa', Aa, 'Ba', Ba, ...
    'Ao', Ao, 'Bo', Bo, 'Co', Co, 'As', As, 'Cs', Cs, ...
    'K', K, 'Ki', Ki, 'Nb', Nb, 'L', L, ...
    'polosControlador', [pCancelado, pZero, pResposta], ...
    'polosObservador', polosObservador, 'TrAlvo', TrAlvo, ...
    'stepInfoNominal', info, 'w0', w0, ...
    'condObservabilidade', condObservabilidade, 'modeloOrigem', fonte, ...
    'modeloSimulink', modeloSimulink, ...
    'uInicialMais5', uInicialMais5, ...
    'uInicial45para55', uInicial45para55);

destino = fullfile(apoio, 'projeto_continuo.mat');
save(destino, 'projeto');
if abrirModelo
    prepararModeloContinuo(projeto, s.resultado);
end
fprintf(['Etapa 2 concluída | Tr %.3f s | Mp %.3f%% | ' ...
    'Ki %.6g | Nb %.6g\n'], info.RiseTime, info.Overshoot, Ki, Nb);
end

function prepararModeloContinuo(projeto, identificacao)
% Converte PWM16 para a escala PWM10 usada no diagrama didático.
h = identificacao.parametros;
escala = 65535/1023;
Kp = h.Kp*escala;
Tp1 = h.Tp1; Tp2 = h.Tp2; Tz = h.Tz; Td = h.Td;
A = (Tz-Tp1)/(Tp2-Tp1);
B = 1-A;
K = projeto.K/escala;
Ki = projeto.Ki/escala;
Nb = projeto.Nb/escala;
w0 = projeto.w0;

Ap = diag([-1/Tp1, -1/Tp2]);
Bp = Kp*[1; 1];
Cp = [A/Tp1, B/Tp2];
As = [0, 1; -w0^2, 0];
Ao = [Ap, Bp*[1, 0]; zeros(2, 2), As];
L = place(Ao', [Cp, 0, 0]', projeto.polosObservador)';

Ta = identificacao.taMedia;
Tid = identificacao.TsIdentificacao;
PO = 50;
umin = 0; umax = 1023;
xs1i = 0; xs2i = 0; xii = 0;
x1i = 0; x2i = 0; x1ei = 0; x2ei = 0;
parametros = struct('Kp', Kp, 'Tp1', Tp1, 'Tp2', Tp2, 'Tz', Tz, ...
    'Td', Td, 'A', A, 'B', B, 'K', K, 'Ki', Ki, 'Nb', Nb, ...
    'L', L, 'w0', w0, 'Ta', Ta, 'Tid', Tid, 'PO', PO, ...
    'umin', umin, 'umax', umax, 'xs1i', xs1i, 'xs2i', xs2i, ...
    'xii', xii, 'x1i', x1i, 'x2i', x2i, 'x1ei', x1ei, 'x2ei', x2ei);
nomes = fieldnames(parametros);
for k = 1:numel(nomes)
    assignin('base', nomes{k}, parametros.(nomes{k}));
end
assert(isfile(projeto.modeloSimulink), ...
    'Modelo contínuo não encontrado: %s', projeto.modeloSimulink);
open_system(projeto.modeloSimulink);
end
