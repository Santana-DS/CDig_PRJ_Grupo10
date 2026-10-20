function resultado = ETAPA01_identificar_planta_nominal()
%IDENTIFICAR_PLANTA Estima o modelo P2DZ a partir do ensaio local.
%   Descarta 2000 amostras e estima Kp, Tp1,
%   Tp2 e Td com Tz = 190 s. Reserva os últimos 20% para validação.
%   Saída: apoio/planta_p2dz.mat, com modelo, dados e metadados.

pasta = fileparts(mfilename('fullpath'));
raizProjeto = fileparts(fileparts(pasta));
apoio = fullfile(raizProjeto, 'resultados', 'artefatos');
if ~isfolder(apoio), mkdir(apoio); end
csv = fullfile(raizProjeto, 'dados', 'identificacao_planta_nominal.csv');
assert(isfile(csv), 'CSV de identificação não encontrado: %s', csv);

amostras = readtable(csv);
campos = {'t', 'Uh', 'Tp_raw', 'Ta_raw'};
assert(all(ismember(campos, amostras.Properties.VariableNames)), ...
    'CSV sem as colunas necessárias.');
assert(height(amostras) == 31500, 'Esperadas 31500 amostras PRBS.');
assert(all(abs(diff(amostras.t) - 1) < 1e-9), ...
    'A identificação exige amostragem uniforme de 1 s.');

transitorio = 2000;
u = double(amostras.Uh(transitorio + 1:end));
y = double(amostras.Tp_raw(transitorio + 1:end));
ta = double(amostras.Ta_raw(transitorio + 1:end));
assert(all(isfinite([u; y; ta])), 'Há amostras não finitas.');

nTreino = floor(0.8 * numel(u));
u0 = mean(u(1:nTreino));
y0 = mean(y(1:nTreino));
uInc = u - u0;
yInc = y - y0;

treino = iddata(yInc(1:nTreino), uInc(1:nTreino), 1);
validacao = iddata(yInc(nTreino + 1:end), uInc(nTreino + 1:end), 1);

% O zero foi selecionado por perfil de validação. Sem fixá-lo,
% a otimização pode degenerar para o caso particular P2D (Tz próximo de 0).
modelo = idproc('P2DZ');
modelo.Kp = 0.00219;
modelo.Tp1 = 244;
modelo.Tp2 = 32;
modelo.Tz = 190;
modelo.Td = 5.7;
modelo.Structure.Tz.Free = false;
modelo = procest(treino, modelo);

[~, fit] = compare(validacao, modelo);
p = get(modelo);
resultado = struct( ...
    'modelo', modelo, 'parametros', p, 'fit', fit, ...
    'treino', treino, 'validacao', validacao, ...
    'u0', u0, 'y0', y0, 'taMedia', mean(ta), ...
    'TsIdentificacao', 1, 'transitorio', transitorio, ...
    'csvOrigem', csv);

destino = fullfile(apoio, 'planta_p2dz.mat');
save(destino, 'resultado');
fprintf(['Etapa 1 concluída | FIT %.2f%% | Kp %.7g | ', ...
    'Tp1 %.2f s | Tp2 %.2f s | Tz %.0f s | Td %.3f s\n'], ...
    fit, p.Kp, p.Tp1, p.Tp2, p.Tz, p.Td);
end
