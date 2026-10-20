%% ETAPA 01 - IDENTIFICACAO FINAL P2DZ
% Identificacao PRBS com 80 %% dos dados para estimacao e 20 %% para validacao.
% O perfil P2DZ preliminar selecionou Tz=190 s; o zero e mantido fixo nesta
% etapa para evitar sua degeneracao numerica para o caso particular P2D.

clear; clc; close all;

pasta = fileparts(mfilename('fullpath'));
raizProjeto = fileparts(fileparts(pasta));
artefatos = fullfile(raizProjeto, 'resultados', 'artefatos');
if ~isfolder(artefatos), mkdir(artefatos); end
tabela = readtable(fullfile(raizProjeto, 'dados', ...
    'ensaio_prbs_v2_b9_m100_u7000_12200.csv'));

transitorio = 2000;
dados = tabela(transitorio+1:end, :);
u = double(dados.Uh(:));
y = double(dados.Tp_raw(:));
ta = double(dados.Ta_raw(:));
Ts = 1;

nTreino = floor(0.80*numel(u));
it = 1:nTreino;
iv = nTreino+1:numel(u);
u0 = mean(u(it));
y0 = mean(y(it));
uid = u-u0;
yid = y-y0;

data = iddata(yid(it), uid(it), Ts);
datav = iddata(yid(iv), uid(iv), Ts);

% P2DZ selecionado por validacao: Tz=190 s. Os demais parametros sao
% reestimados diretamente por procest em cada execucao.
modeloP2DZ = idproc('P2DZ');
modeloP2DZ.Kp = 0.00219;
modeloP2DZ.Tp1 = 244;
modeloP2DZ.Tp2 = 32;
modeloP2DZ.Tz = 190;
modeloP2DZ.Td = 5.7;
modeloP2DZ.Structure.Tz.Free = false;
modeloP2DZ = procest(data, modeloP2DZ);

figure('Name', 'Validacao P2DZ');
[~, fitnessValidacao] = compare(datav, modeloP2DZ);
compare(datav, modeloP2DZ); grid on;
title(sprintf('Validacao independente P2DZ - FIT %.1f%%', fitnessValidacao));

p = get(modeloP2DZ);
fprintf('FIT = %.1f%% | Kp = %.9g | Tp1 = %.4f s | Tp2 = %.4f s | ', ...
    fitnessValidacao, p.Kp, p.Tp1, p.Tp2);
fprintf('Tz = %.4f s | Td = %.4f s\n', p.Tz, p.Td);

save(fullfile(artefatos, 'modelo_final_P2DZ_V2.mat'), 'modeloP2DZ', ...
    'data', 'datav', 'fitnessValidacao', 'u0', 'y0', 'u', 'y', 'ta', ...
    'Ts', 'transitorio');
