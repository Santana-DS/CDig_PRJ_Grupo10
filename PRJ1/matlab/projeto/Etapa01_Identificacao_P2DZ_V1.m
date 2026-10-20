%% ETAPA 01 - IDENTIFICACAO FINAL P2DZ
% Identifica a dinamica termica pelo PRBS final. A entrada e o PWM bruto
% de 16 bits e a saida e a temperatura de processo em graus C.

clear; clc; close all;

pasta = fileparts(mfilename('fullpath'));
raizProjeto = fileparts(fileparts(pasta));
artefatos = fullfile(raizProjeto, 'resultados', 'artefatos');
if ~isfolder(artefatos), mkdir(artefatos); end
tabela = readtable(fullfile(raizProjeto, 'dados', ...
    'ensaio_prbs_final_b9_m100_pwm16.csv'));

% Descarte do transitorio inicial previsto no roteiro.
transitorio = 2000;
dados = tabela(transitorio+1:end, :);
u = double(dados.Uh(:));
y = double(dados.Tp_raw(:));
ta = double(dados.Ta_raw(:));
Ts = 1;

% Particao i=6: 80%% para estimacao e 20%% para validacao.
fracaoTreino = 0.80;
nTreino = floor(fracaoTreino*numel(u));
it = 1:nTreino;
iv = nTreino+1:numel(u);

% Os offsets sao calculados apenas no treino e preservados na validacao.
u0 = mean(u(it));
y0 = mean(y(it));
uid = u-u0;
yid = y-y0;

data = iddata(yid(it), uid(it), Ts, 'Name', 'Treino PRBS final');
datav = iddata(yid(iv), uid(iv), Ts, 'Name', 'Validacao PRBS final');
modeloP2DZ = procest(data, 'P2DZ');

figure('Name', 'Validacao independente P2DZ');
[~, fitnessValidacao] = compare(datav, modeloP2DZ);
compare(datav, modeloP2DZ);
grid on;
title(sprintf('Validacao independente P2DZ - FIT %.1f%%', fitnessValidacao));

% Resumo conciso para registrar os parametros efetivamente usados adiante.
p = get(modeloP2DZ);
fprintf('FIT = %.1f%% | Kp = %.9g | Tp1 = %.4f s | Tp2 = %.4f s | ', ...
    fitnessValidacao, p.Kp, p.Tp1, p.Tp2);
fprintf('Tz = %.4f s | Td = %.4f s\n', p.Tz, p.Td);

save(fullfile(artefatos, 'modelo_final_P2DZ_b9_m100.mat'), ...
    'modeloP2DZ', 'data', 'datav', 'fitnessValidacao', ...
    'u0', 'y0', 'u', 'y', 'ta', 'Ts', 'transitorio', 'fracaoTreino');
