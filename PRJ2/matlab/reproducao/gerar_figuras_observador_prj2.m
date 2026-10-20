function metricas = gerar_figuras_observador_prj2(destino)
%GERAR_FIGURAS_OBSERVADOR_PRJ2 Gera evidencias com e sem compensacao.

pasta = fileparts(mfilename('fullpath'));
raizProjeto = fileparts(fileparts(pasta));
if nargin < 1
    destino = fullfile(raizProjeto, 'resultados', 'figuras_observador');
end
if ~isfolder(destino), mkdir(destino); end

arquivoModelo = fullfile(raizProjeto, 'simulink', 'Prj2CDig_discreto_PRJ2.slx');
assert(isfile(arquivoModelo), 'Modelo não encontrado: %s', arquivoModelo);
[~, modelo] = fileparts(arquivoModelo);
load_system(arquivoModelo);
limpeza = onCleanup(@() close_system(modelo, 0));

desligado = executar(modelo, '0');
ligado = executar(modelo, '1');

cores = struct('r', [0 0 0], 'y', [0.85 0.10 0.10], ...
    'ta', [0.93 0.55 0.05], 'w', [0.20 0.65 0.20], ...
    'u', [0 0.45 0.74], 'e', [0.20 0.65 0.20]);
plotarCenario(desligado, cores, 'Observador senoidal desativado', ...
    fullfile(destino, '02_sim_observador_desligado.png'));
plotarCenario(ligado, cores, 'Observador senoidal ativado', ...
    fullfile(destino, '03_sim_observador_ligado.png'));

% Exclui as vizinhanças dos degraus de referência: a métrica abaixo mede
% rejeição senoidal em regime, enquanto as figuras preservam todo o ensaio.
janela = (ligado.t >= 2200 & ligado.t < 2390) | ...
    (ligado.t >= 2600 & ligado.t < 2790);
rmsOff = rms(desligado.y(janela)-desligado.r(janela));
rmsOn = rms(ligado.y(janela)-ligado.r(janela));
metricas = table(rmsOff, rmsOn, 100*(1-rmsOn/rmsOff), ...
    'VariableNames', {'RMS_sem_observador_C', 'RMS_com_observador_C', ...
    'Reducao_RMS_pct'});
writetable(metricas, fullfile(destino, 'metricas_observador.csv'));

f = figure('Visible', 'off', 'Color', 'w', 'Units', 'inches', ...
    'Position', [0.2 0.2 7.08 3.80]);
tiledlayout(f, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
nexttile;
plot(desligado.t, desligado.y-desligado.r, 'Color', [0.55 0.35 0.75], ...
    'LineWidth', 1.25); hold on;
plot(ligado.t, ligado.y-ligado.r, 'Color', cores.y, 'LineWidth', 1.65);
yline(0, 'k:', 'LineWidth', 0.8); grid on; xlim([1800 3050]);
ylabel('Y-R (°C)');
legend('Sem observador', 'Com observador', 'Location', 'best', ...
    'NumColumns', 2);
nexttile;
stairs(ligado.t, ligado.u, 'Color', cores.u, 'LineWidth', 1.4); hold on;
plot(ligado.t, ligado.e, 'Color', cores.e, 'LineWidth', 1.4);
grid on; xlim([1800 3050]); xlabel('Tempo (s)'); ylabel('PWM16');
legend('U_s', 'e_{sin} estimado', 'Location', 'best', 'NumColumns', 2);
set(findall(f, '-property', 'FontSize'), 'FontSize', 8.5);
exportgraphics(f, fullfile(destino, '04_sim_comparacao_observador.png'), ...
    'Resolution', 600);
close(f);

% Vista superior do diagrama adotado, útil como figura de arquitetura.
open_system(modelo);
set_param(modelo, 'ZoomFactor', 'FitSystem');
print(['-s' modelo], '-dpng', '-r180', ...
    fullfile(destino, '01_modelo_discreto_simulink.png'));

fprintf('Figuras do observador concluídas | RMS %.4f -> %.4f °C\n', ...
    rmsOff, rmsOn);
end

function sinais = executar(modelo, chave)
entrada = Simulink.SimulationInput(modelo);
entrada = entrada.setBlockParameter( ...
    [modelo '/Observadores/Observador_on_off'], 'sw', chave);
entrada = entrada.setModelParameter('StopTime', '3600');
saida = sim(entrada);
[sinais.t, sinais.r] = serie(saida, 'R_log');
[~, sinais.y] = serie(saida, 'Y_log');
[~, sinais.ta] = serie(saida, 'Ta_log');
[~, sinais.w] = serie(saida, 'W_log');
[~, sinais.u] = serie(saida, 'U_log');
[~, sinais.e] = serie(saida, 'Esin_log');
end

function [t, x] = serie(saida, nome)
sinal = saida.get(nome);
t = double(sinal.Time(:));
x = double(sinal.Data(:));
end

function plotarCenario(s, c, titulo, arquivo)
f = figure('Visible', 'off', 'Color', 'w', 'Position', [80 80 1400 800]);
tiledlayout(f, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
nexttile;
stairs(s.t, s.u, 'Color', c.u, 'LineWidth', 2); hold on;
plot(s.t, s.e, 'Color', c.e, 'LineWidth', 2);
grid on; xlim([0 3600]); ylabel('PWM16');
legend('U_s', 'e_{sin}', 'Location', 'best'); title(titulo);
nexttile;
hTa = plot(s.t, s.ta, 'Color', c.ta, 'LineWidth', 2); hold on;
hW = stairs(s.t, s.w, 'Color', c.w, 'LineWidth', 2);
hR = stairs(s.t, s.r, ':', 'Color', c.r, 'LineWidth', 1);
hY = plot(s.t, s.y, 'Color', c.y, 'LineWidth', 2);
grid on; xlim([0 3600]); xlabel('Tempo (s)'); ylabel('Temperatura / W');
legend([hTa(1); hW(1); hR(1); hY(1)], ...
    {'Ta', 'W', 'R', 'Y'}, 'Location', 'best');
exportgraphics(f, arquivo, 'Resolution', 220);
close(f);
end
