%% ETAPA 04 - DISCRETIZACAO ZOH
% Discretizacao do modelo P2DZ validado, com Ts=Td/2 conforme o roteiro.

clear; clc; close all;

pasta = fileparts(mfilename('fullpath'));
raizProjeto = fileparts(fileparts(pasta));
artefatos = fullfile(raizProjeto, 'resultados', 'artefatos');
arquivoModelo = fullfile(artefatos, 'modelo_final_P2DZ_V2.mat');
assert(isfile(arquivoModelo), 'Execute antes a Etapa01_Identificacao_P2DZ_Final.m.');
load(arquivoModelo, 'modeloP2DZ');
h = get(modeloP2DZ);
s = tf('s');
Ts = h.Td/2;

G_s = h.Kp*(1 + h.Tz*s) / ((1 + h.Tp1*s)*(1 + h.Tp2*s));
G_s.InputDelay = h.Td;
G_z = c2d(G_s, Ts, 'zoh');
G_s
G_z

% Sobreposicao com marcadores ampliados para leitura clara do plano-z.
polosZ = pole(G_z);
zerosZ = zero(G_z);
figure('Name', 'Mapa polo-zero da planta ZOH', 'Color', 'w');
pzmap(G_z); grid on; hold on;
hPolos = plot(real(polosZ), imag(polosZ), 'x', ...
    'Color', [0.85 0.10 0.10], 'MarkerSize', 14, 'LineWidth', 2.5);
hZeros = plot(real(zerosZ), imag(zerosZ), 'o', ...
    'Color', [0.00 0.35 0.80], 'MarkerSize', 11, 'LineWidth', 2.2);
legend([hPolos hZeros], {'Polos', 'Zeros'}, 'Location', 'southwest');
title('Mapa polo-zero da planta discretizada por ZOH');

save(fullfile(artefatos, 'planta_ZOH_P2DZ_V2.mat'), 'G_s', 'G_z', 'Ts', 'h');
fprintf('Ts = Td/2 = %.4f s. Planta ZOH salva em planta_ZOH_P2DZ_V2.mat.\n', Ts);
