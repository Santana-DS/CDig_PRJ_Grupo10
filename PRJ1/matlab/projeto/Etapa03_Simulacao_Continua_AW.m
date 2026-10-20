%% ETAPA 03 - SIMULACAO CONTINUA E ANTI-WINDUP
% A planta e o PI em 16 bits sao convertidos para o PWM de 10 bits do modelo.

clear; clc; close all;

pasta = fileparts(mfilename('fullpath'));
raizProjeto = fileparts(fileparts(pasta));
arquivoModelo = fullfile(raizProjeto, 'resultados', 'artefatos', ...
    'modelo_final_P2DZ_V2.mat');
assert(isfile(arquivoModelo), 'Execute antes a Etapa01_Identificacao_P2DZ_Final.m.');
load(arquivoModelo, 'modeloP2DZ', 'ta');
h = get(modeloP2DZ);
% Condicoes de operacao e sinais definidos no roteiro.
Ta = mean(ta);
W = 0;
Ts = 1;
PO = 50;
Sat = 1024;
w0 = 0.09817477042468;
AmpW0 = 0.02*0.981/0.654;
% Conversao entre PWM bruto de 16 bits e a escala de 10 bits do diagrama.
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
% PI continuo C(s)=1900+47.5/s convertido para a escala de 10 bits.
KP = 1900/escalaPWM;
KI = 47.5/escalaPWM;
open_system(fullfile(raizProjeto, 'simulink', 'Prj1CDig.slx'));
