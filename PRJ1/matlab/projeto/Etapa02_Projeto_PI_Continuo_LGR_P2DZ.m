%% ETAPA 02 - PROJETO DO PI CONTINUO PELO LGR
% Sintonia final: C(s)=1900(s+0,025)/s = 1900 + 47,5/s.

clear; clc; close all;

pasta = fileparts(mfilename('fullpath'));
raizProjeto = fileparts(fileparts(pasta));
arquivoModelo = fullfile(raizProjeto, 'resultados', 'artefatos', ...
    'modelo_final_P2DZ_V2.mat');
assert(isfile(arquivoModelo), 'Execute antes a Etapa01_Identificacao_P2DZ_Final.m.');
load(arquivoModelo, 'modeloP2DZ');
p = get(modeloP2DZ);
s = tf('s');

G = p.Kp*(1+p.Tz*s)*exp(-p.Td*s) / ...
    ((1+p.Tp1*s)*(1+p.Tp2*s));

% Especificacoes: Mp <= 15 %% e Tp <= 30 s.
Mp = 0.15;
Tp = 30;
zeta = -log(Mp)/sqrt(pi^2 + log(Mp)^2);
wn = pi/(Tp*sqrt(1-zeta^2));
poloDominante = -zeta*wn + 1i*wn*sqrt(1-zeta^2); %#ok<NASGU>

KP = 1900;
KI = 47.5;
C = KP*(s+KI/KP)/s;

if usejava('desktop')
    sisotool(G, C);
else
    % Em execucao automatica, o atraso e aproximado apenas para exibir o LGR.
    % O modelo P2DZ original permanece inalterado nas etapas seguintes.
    Gp = pade(G, 1);
    f = figure('Visible', 'off');
    rlocus(C*Gp); grid on;
    close(f);
end
