function resultados = ETAPA05_validar_controle_discreto()
%VALIDAR_CONTROLADOR_DISCRETO Compara seguimento, senoide e saturação.
%   As métricas são do modelo nominal sem ruído nem incerteza paramétrica.
pasta = fileparts(mfilename('fullpath'));
raizProjeto = fileparts(fileparts(pasta));
funcoes = fullfile(pasta, 'apoio');
artefatos = fullfile(raizProjeto, 'resultados', 'artefatos');
s = load(fullfile(artefatos, 'controlador_discreto.mat'), ...
    'controle');
c = s.controle;
caminhoAnterior = path;
restaurar = onCleanup(@() path(caminhoAnterior));
addpath(funcoes);

seguimento = simular_malha_discreta("seguimento", true, true);
senoideOn = simular_malha_discreta("perturbacao", true, true);
senoideOff = simular_malha_discreta("perturbacao", false, true);
awOn = simular_malha_discreta("saturacao", true, true);
awOff = simular_malha_discreta("saturacao", true, false);

janelaSenoide = senoideOn.t >= 1100 & senoideOn.t < 1450;
rmsOn = rms(senoideOn.temperatura(janelaSenoide)-50);
rmsOff = rms(senoideOff.temperatura(janelaSenoide)-50);
janelaRetorno = awOn.t >= 500;
minimoAW = min(awOn.temperatura(janelaRetorno));
minimoSemAW = min(awOff.temperatura(janelaRetorno));

assert(abs(seguimento.temperatura(end)-55) < 0.01, ...
    'Erro residual no seguimento nominal.');
assert(seguimento.amostrasSaturadas == 0, ...
    'Degrau nominal saturou o atuador.');
assert(abs(c.TrInterpolado-c.TrAlvo) < 1, ...
    'Tempo de subida nominal distante do alvo.');
assert(c.stepInfoNominal.Overshoot < 0.1, ...
    'Sobressinal nominal fora da meta.');
assert(rmsOn < 0.1*rmsOff, ...
    'Compensação senoidal não reduziu suficientemente a oscilação.');
assert(awOn.amostrasSaturadas < awOff.amostrasSaturadas && ...
    minimoAW > minimoSemAW, ...
    'Anti-windup não melhorou a recuperação após saturação.');

resultados = struct( ...
    'seguimento', seguimento, 'senoideOn', senoideOn, ...
    'senoideOff', senoideOff, 'awOn', awOn, 'awOff', awOff, ...
    'TrInterpolado', c.TrInterpolado, ...
    'sobressinalNominal', c.stepInfoNominal.Overshoot, ...
    'rmsSenoideOn', rmsOn, 'rmsSenoideOff', rmsOff, ...
    'minimoComAW', minimoAW, 'minimoSemAW', minimoSemAW);
destino = fullfile(artefatos, 'simulacao_discreta.mat');
save(destino, 'resultados');
fprintf('Tr interpolado: %.3f s | Mp nominal: %.3f%%\n', ...
    resultados.TrInterpolado, resultados.sobressinalNominal);
fprintf('RMS senoidal: %.4f °C (on), %.4f °C (off)\n', rmsOn, rmsOff);
fprintf('Mínimo após estresse: %.3f °C (AW), %.3f °C (sem AW)\n', ...
    minimoAW, minimoSemAW);
fprintf('Arquivo gerado: %s\n', destino);
end
