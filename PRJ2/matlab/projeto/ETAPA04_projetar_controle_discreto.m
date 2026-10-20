function controle = ETAPA04_projetar_controle_discreto(abrirModelo)
%PROJETAR_CONTROLADOR_DISCRETO Aloca polos com integrador e atraso explícito.
%   O canal integral é trapezoidal (Tustin). Os ganhos contínuos servem
%   apenas de referência: a realimentação é recalculada para a planta ZOH.
%   Ao final, abre o modelo Simulink discreto adotado no projeto.

if nargin < 1
    abrirModelo = true;
end

pasta = fileparts(mfilename('fullpath'));
raizProjeto = fileparts(fileparts(pasta));
apoio = fullfile(raizProjeto, 'resultados', 'artefatos');
fonte = fullfile(apoio, 'modelos_discretos.mat');
assert(isfile(fonte), 'Execute ETAPA03_discretizar_modelos_zoh antes.');
s = load(fonte, 'discreto');
d = s.discreto;
Ad = d.Ad; Bd = d.Bd; C = d.Cd; Ts = d.Ts;

% Estados [x1; x2; q; xi], sendo q[k] o PWM aplicado no passo anterior.
% xi[k+1] = xi[k] + Ts/2*(e[k] + e[k+1]); r é constante no intervalo.
Ai = [Ad, Bd, zeros(2, 1); ...
      zeros(1, 2), 0, 0; ...
      -Ts/2*C*(eye(2)+Ad), -Ts/2*C*Bd, 1];
Bi = [0; 0; 1; 0];
Er = [0; 0; 0; Ts];
Ci = [C, 0, 0];
assert(rank(ctrb(Ai, Bi)) == 4, ...
    'Planta aumentada com atraso e integral não controlável.');

zeroPlanta = tzero(ss(Ad, Bd, C, 0, Ts));
assert(isscalar(zeroPlanta) && isreal(zeroPlanta) && ...
    zeroPlanta > 0 && zeroPlanta < 1, ...
    'Zero discreto da planta fora da faixa esperada.');

% Alvo interno de 19 s compensa a amostragem e atende Tr <= 20 s.
TrAlvo = 19;
pResposta = -log(9)/TrAlvo;
zResposta = exp(pResposta*Ts);
zCancelado = exp((pResposta/3)*Ts);
zAtraso = exp((4*pResposta)*Ts);
polos = [zeroPlanta, zResposta, zCancelado, zAtraso];
F = place(Ai, Bi, polos);
Acl = Ai - Bi*F;
Ki = -F(4);
assert(Ki > 0, 'O ganho integral calculado deve ser positivo.');

% Nb cancela o resíduo do polo zCancelado na resposta à referência.
% O autovetor esquerdo desse modo fornece a condição l'*(Bi*Nb+Er)=0.
[V, D] = eig(Acl');
[~, indice] = min(abs(diag(D) - zCancelado));
l = V(:, indice);
Nb = real(-(l'*Er)/(l'*Bi));
assert(isfinite(Nb) && Nb > 0, 'Pré-filtro Nb inválido.');

Tref = ss(Acl, Bi*Nb + Er, Ci, 0, Ts);
info = stepinfo(Tref, 'RiseTimeLimits', [0.1, 0.9]);
[resposta, tempo] = step(Tref, 0:Ts:12*TrAlvo);
t10 = cruzamento(tempo, resposta, 0.1);
t90 = cruzamento(tempo, resposta, 0.9);
TrInterpolado = t90 - t10;
assert(abs(dcgain(Tref) - 1) < 1e-6, ...
    'A ação integral não preservou o ganho unitário em regime.');
assert(all(abs(eig(Acl)) < 1), 'Malha discreta nominal instável.');

modeloSimulink = fullfile(raizProjeto, 'simulink', 'Prj2CDig_discreto_PRJ2.slx');
controle = struct( ...
    'Ai', Ai, 'Bi', Bi, 'Er', Er, 'Ci', Ci, ...
    'F', F, 'K', F(1:2), 'Kq', F(3), 'Ki', Ki, 'Nb', Nb, ...
    'polos', polos, 'zeroPlanta', zeroPlanta, ...
    'TrAlvo', TrAlvo, 'TrInterpolado', TrInterpolado, ...
    'stepInfoNominal', info, 'Tref', Tref, ...
    'modeloOrigem', fonte, 'modeloSimulink', modeloSimulink);
destino = fullfile(apoio, 'controlador_discreto.mat');
save(destino, 'controle');
if abrirModelo
    assert(isfile(modeloSimulink), ...
        'Modelo discreto não encontrado: %s', modeloSimulink);
    open_system(modeloSimulink);
end
fprintf(['Etapa 4 concluída | Tr %.3f s | Mp %.3f%% | ' ...
    'Ki %.6g | Nb %.6g\n'], ...
    TrInterpolado, info.Overshoot, Ki, Nb);
end

function tNivel = cruzamento(t, y, nivel)
% Interpola apenas a leitura da métrica; a simulação permanece amostrada.
i = find(y >= nivel, 1, 'first');
assert(~isempty(i) && i > 1, 'Resposta não cruzou o nível esperado.');
tNivel = t(i-1) + (nivel-y(i-1)) * ...
    (t(i)-t(i-1))/(y(i)-y(i-1));
end
