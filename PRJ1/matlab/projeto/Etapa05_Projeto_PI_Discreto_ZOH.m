%% ETAPA 05 - PROJETO DO PI DISCRETO PELO LGR
% O LGR parte da discretizacao Tustin do PI continuo da Etapa 02.

clear; clc; close all;

pasta = fileparts(mfilename('fullpath'));
raizProjeto = fileparts(fileparts(pasta));
arquivoPlanta = fullfile(raizProjeto, 'resultados', 'artefatos', ...
    'planta_ZOH_P2DZ_V2.mat');
assert(isfile(arquivoPlanta), 'Execute antes a Etapa04_Discretizacao_ZOH.m.');
load(arquivoPlanta, 'G_z', 'Ts');
s = tf('s');

% Semente Tustin do PI continuo, mantida como referencia de projeto.
% KPc = 1900;
% KIc = 47.5;
% CInicial = c2d(KPc*(s+KIc/KPc)/s, Ts, 'tustin');

% Sintonia final no LGR discreto. O zero proximo de 0.922 preserva a
% acao integral e evita a cauda de acomodacao observada para zero em 0.940.
Kd = 1700;
zd = 0.922;
C = tf(Kd*[1 -zd], [1 -1], Ts);

sisotool(G_z, C);
