function metricas = ETAPA08_plotar_resultados_finais()
%ETAPA08_PLOTAR_RESULTADOS_FINAIS Gera as figuras essenciais do PRJ2.
%   Mostra o ensaio refinado de 1 h e compara o erro sob perturbacao
%   senoidal antes e depois do refinamento. Nenhum dado e alterado.

pasta = fileparts(mfilename('fullpath'));
raizProjeto = fileparts(fileparts(pasta));
dados = fullfile(raizProjeto, 'dados');
refinado = ultimoSegmento(readtable(fullfile(dados, ...
    'ensaio_controle_refinado.csv')));
anterior = ultimoSegmento(readtable(fullfile(dados, ...
    'ensaio_controle_escalonado.csv')));

destino = fullfile(raizProjeto, 'resultados', ...
    'figuras_entrega');
if ~isfolder(destino), mkdir(destino); end

preto = [0 0 0]; vermelho = [0.85 0.10 0.10];
laranja = [0.93 0.55 0.05]; verde = [0.20 0.65 0.20];
azul = [0 0.45 0.74];
eSinAtivo = (1-refinado.modo).*refinado.e_sin_nom + ...
    refinado.modo.*refinado.e_sin_cool;

f = figure('Color', 'w', 'Position', [100 80 1400 850]);
tiledlayout(f, 3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
nexttile; stairs(refinado.t, refinado.R, ':', 'Color', preto, ...
    'LineWidth', 1); hold on;
plot(refinado.t, refinado.Y, 'Color', vermelho, 'LineWidth', 2);
grid on; xlim([0 3600]); ylabel('Temperatura (°C)');
legend('R', 'Y', 'Location', 'best');
title('Ensaio final do controle discreto escalonado');
nexttile; yyaxis left;
plot(refinado.t, refinado.Ta, 'Color', laranja, 'LineWidth', 2);
ylabel('Ta (°C)'); yyaxis right;
stairs(refinado.t, refinado.W, 'Color', verde, 'LineWidth', 2);
ylabel('W (PWM12)'); grid on; xlim([0 3600]);
axAmbiente = gca;
axAmbiente.YAxis(1).Color = laranja;
axAmbiente.YAxis(2).Color = verde;
legend('Ta', 'W', 'Location', 'best');
nexttile; stairs(refinado.t, refinado.Us, 'Color', azul, ...
    'LineWidth', 2); hold on;
plot(refinado.t, eSinAtivo, 'Color', verde, 'LineWidth', 2);
grid on; xlim([0 3600]); ylabel('PWM16'); xlabel('Tempo (s)');
legend('U_s', 'e_{sin} ativo', 'Location', 'best');
exportgraphics(f, fullfile(destino, 'ensaio_final.png'), 'Resolution', 200);

janelaRef = refinado.t >= 2000 & refinado.t < 3000;
janelaAnt = anterior.t >= 2000 & anterior.t < 3000;
erroRef = refinado.Y - refinado.R;
erroAnt = anterior.Y - anterior.R;
metricas = table( ...
    [sqrt(mean(erroAnt(janelaAnt).^2)); sqrt(mean(erroRef(janelaRef).^2))], ...
    [max(abs(erroAnt(janelaAnt))); max(abs(erroRef(janelaRef)))], ...
    'VariableNames', {'RMSE_C', 'ErroMaximoAbsoluto_C'}, ...
    'RowNames', {'AntesDoRefinamento', 'SolucaoFinal'});

f2 = figure('Color', 'w', 'Position', [150 120 1200 520]);
plot(anterior.t, erroAnt, 'Color', [0.55 0.35 0.75]); hold on;
plot(refinado.t, erroRef, 'Color', azul, 'LineWidth', 2);
yline(0, 'k:'); xlim([0 3600]); grid on;
xlabel('Tempo (s)'); ylabel('Y - R (°C)');
title('Evolucao experimental sob perturbacao senoidal');
legend('Antes do refinamento', 'Solucao final', 'Location', 'best');
exportgraphics(f2, fullfile(destino, 'comparacao_refinamento.png'), ...
    'Resolution', 200);
writetable(metricas, fullfile(destino, 'metricas_refinamento.csv'), ...
    'WriteRowNames', true);
fprintf(['Etapa 8 concluída | RMSE senoidal %.3f -> %.3f °C | ' ...
    'figuras em %s\n'], metricas.RMSE_C(1), metricas.RMSE_C(2), destino);
end

function T = ultimoSegmento(T)
% Ignora tentativas anteriores eventualmente preservadas no mesmo CSV.
if ismember('segmento', T.Properties.VariableNames)
    T = T(T.segmento == max(T.segmento), :);
end
end
