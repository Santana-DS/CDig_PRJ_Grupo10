%% ETAPA 06 - SIMULACAO ZOH E ANTI-WINDUP
% O diagrama usa 10 bits internamente. A planta e o PI discreto em 16 bits
% sao convertidos pela mesma escala, preservando o produto C(z)G(z).

clear; clc; close all;

pasta = fileparts(mfilename('fullpath'));
raizProjeto = fileparts(fileparts(pasta));
arquivoModelo = fullfile(raizProjeto, 'resultados', 'artefatos', ...
    'modelo_final_P2DZ_V2.mat');
assert(isfile(arquivoModelo), 'Execute antes a Etapa01_Identificacao_P2DZ_Final.m.');
load(arquivoModelo, 'modeloP2DZ', 'ta');
h = get(modeloP2DZ);

% Condicoes de operacao e taxa de amostragem do projeto discreto.
Ta = mean(ta);
W = 0;
Ts = h.Td/2;
PO = 50;
Sat = 1024;
w0 = 0.09817477042468;
AmpW0 = 0.02*0.981/0.654;

% Planta na escala de 10 bits do diagrama do professor.
escalaPWM = 65535/1023;
Kp = h.Kp*escalaPWM;
Tp1 = h.Tp1;
Tp2 = h.Tp2;
Tz = h.Tz;
Td = h.Td;

% Realizacao modal empregada pelo processo termico do professor.
Ct = 0.0002;
Ka = 1;
Kw = 4;
Kt = 9.1657;
Kp2 = 1/(Kt*Ct*Tp1);
Am = (Tz-Tp1)/(Tp2-Tp1);
Bm = 1-Am;

% PI discreto final: C(z)=1700(z-0.922)/(z-1).
% A escolha preserva a acao integral e deixa margem para Mp e Tp.
Kd = 1700;
zd = 0.922;
KP = Kd/escalaPWM;
KI = Kd*(1-zd)/(Ts*escalaPWM);

open_system(fullfile(raizProjeto, 'simulink', 'Prj1CDig_ZOH.slx'));
