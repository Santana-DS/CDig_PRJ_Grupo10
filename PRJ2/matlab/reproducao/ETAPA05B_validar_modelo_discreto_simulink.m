function resultado = ETAPA05B_validar_modelo_discreto_simulink(arquivoModelo)
%ETAPA05B_VALIDAR_MODELO_DISCRETO_SIMULINK Mede a malha no SLX final.
%   Os cenários são aplicados por SimulationInput: o arquivo .slx não muda.
%   O degrau de 100 graus C é somente estresse numérico de saturação.
%   Informe outro nome de modelo para comparar uma cópia refinada.

pasta = fileparts(mfilename('fullpath'));
raizProjeto = fileparts(fileparts(pasta));
if nargin < 1
    arquivoModelo = fullfile(raizProjeto, 'simulink', ...
        'Prj2CDig_discreto_PRJ2.slx');
end
assert(isfile(arquivoModelo), 'Modelo não encontrado: %s', arquivoModelo);
[~, modelo] = fileparts(arquivoModelo);
assert(isvarname(modelo), 'Nome de modelo inválido.');
load_system(arquivoModelo);
fechar = onCleanup(@() close_system(modelo, 0));

% Degrau isolado, sem W: permite medir Tr(10--90%) e Mp sem a mistura de
% perturbações e trocas periódicas de referência do cenário de 1 hora.
degrau = configurar(modelo, 50, 5, 900, 0, '1', 700);
degrau = sim(degrau);
[t, r] = serie(degrau, 'R_log');
[~, y] = serie(degrau, 'Y_log');
indice = find(diff(r) > 0, 1, 'first') + 1;
assert(~isempty(indice), 'Degrau de referência não encontrado.');
t0 = t(indice);
yInicial = mean(y(t >= t0-50 & t < t0));
yFinal = mean(y(t >= 600));
janela = t >= t0 & t < 600;
td = t(janela); yd = y(janela);
tr = cruzamento(td, yd, yInicial + 0.9*(yFinal-yInicial)) - ...
    cruzamento(td, yd, yInicial + 0.1*(yFinal-yInicial));
mp = 100*max(0, max(yd)-yFinal)/(yFinal-yInicial);

% Rejeição senoidal após acomodação; mesma planta e mesmo W, alterando
% apenas a chave do observador. R permanece em 50 graus C.
ligado = sim(configurar(modelo, 50, 0, 900, -20, '1', 3600));
desligado = sim(configurar(modelo, 50, 0, 900, -20, '0', 3600));
[ts, ysLigado] = serie(ligado, 'Y_log');
[~, ysDesligado] = serie(desligado, 'Y_log');
faixa = ts >= 2200 & ts < 2990;
rmsLigado = sqrt(mean((ysLigado(faixa)-50).^2));
rmsDesligado = sqrt(mean((ysDesligado(faixa)-50).^2));
patamar = ts >= 1600 & ts < 1780;
erroConstante = max(abs(ysLigado(patamar)-50));

% Estresse puramente simulado: referência 50 -> 100 -> 50 graus C.
% K_AW=0 desativa só a correção anti-windup, para comparação causal.
comAW = sim(configurar(modelo, 50, 50, 53, 0, '1', 900));
semAW = configurar(modelo, 50, 50, 53, 0, '1', 900);
semAW = semAW.setVariable('K_AW', 0, 'Workspace', modelo);
semAW = sim(semAW);
[ta, ra] = serie(comAW, 'R_log');
[~, yaCom] = serie(comAW, 'Y_log');
[~, yaSem] = serie(semAW, 'Y_log');
[~, uaCom] = serie(comAW, 'U_log');
retorno = find(diff(ra) < 0, 1, 'first') + 1;
assert(~isempty(retorno), 'Retorno de referência não encontrado.');
recuperacao = ta >= ta(retorno) & ta <= ta(retorno)+350;

resultado = struct( ...
    'modelo', modelo, 'Ts', median(diff(t)), ...
    'degrau', struct('tempo', t0, 'yInicial', yInicial, ...
        'yFinal', yFinal, 'Tr10a90_s', tr, 'Mp_pct', mp), ...
    'senoide', struct('janela_s', [2200 2990], ...
        'rmsLigado_C', rmsLigado, 'rmsDesligado_C', rmsDesligado, ...
        'reducao_pct', 100*(1-rmsLigado/rmsDesligado), ...
        'erroMaximoPatamarConstante_C', erroConstante), ...
    'saturacao', struct('retorno_s', ta(retorno), ...
        'minComAW_C', min(yaCom(recuperacao)), ...
        'minSemAW_C', min(yaSem(recuperacao)), ...
        'pwmMaximo', max(uaCom)));

destino = fullfile(raizProjeto, 'resultados', ...
    'validacao_simulink');
if ~isfolder(destino), mkdir(destino); end
prefixo = ['verificacao_' modelo];
save(fullfile(destino, [prefixo '.mat']), 'resultado');
figura(t, r, y, ts, ysLigado, ysDesligado, ta, ra, yaCom, yaSem, ...
    fullfile(destino, [prefixo '.png']));
fprintf('Tr 10-90%% = %.3f s; Mp = %.3f%%; Y final = %.4f C\n', ...
    tr, mp, yFinal);
fprintf('Senoide RMS: %.4f C ligada, %.4f C desligada (redução %.2f%%)\n', ...
    rmsLigado, rmsDesligado, resultado.senoide.reducao_pct);
fprintf('Erro maximo com W constante apos acomodacao: %.5f C\n', ...
    erroConstante);
fprintf('Saturacao: Y min retorno %.3f C com AW, %.3f C sem AW\n', ...
    resultado.saturacao.minComAW_C, resultado.saturacao.minSemAW_C);
end

function entrada = configurar(modelo, base, amplitude, largura, wDC, chave, fim)
% Mantém a configuração aprovada no arquivo; só muda o cenário deste run.
entrada = Simulink.SimulationInput(modelo);
cenario = [modelo '/Cenario_1h/'];
entrada = entrada.setBlockParameter([cenario 'R_base'], 'Value', num2str(base));
pulso = [cenario 'R_pulsos'];
entrada = entrada.setBlockParameter(pulso, 'Amplitude', num2str(amplitude));
entrada = entrada.setBlockParameter(pulso, 'Period', '1000');
entrada = entrada.setBlockParameter(pulso, 'PulseWidth', num2str(largura));
entrada = entrada.setBlockParameter(pulso, 'PhaseDelay', '35');
entrada = entrada.setBlockParameter([cenario 'W_DC'], ...
    'FinalValue', num2str(wDC));
entrada = entrada.setBlockParameter([modelo '/Observadores/Observador_on_off'], ...
    'sw', chave);
entrada = entrada.setModelParameter('StopTime', num2str(fim));
end

function [t, x] = serie(simulacao, nome)
sinal = simulacao.get(nome);
t = double(sinal.Time(:));
x = double(sinal.Data(:));
assert(numel(t) == numel(x), 'Sinal %s não é escalar.', nome);
end

function instante = cruzamento(t, y, limiar)
k = find(y >= limiar, 1, 'first');
assert(~isempty(k) && k > 1, 'Cruzamento de limiar ausente.');
instante = interp1(y(k-1:k), t(k-1:k), limiar);
end

function figura(t, r, y, ts, yon, yoff, ta, ra, yaw, ysem, arquivo)
f = figure('Visible', 'off', 'Color', 'w', 'Position', [100 100 1050 800]);
tiledlayout(f, 3, 1, 'TileSpacing', 'compact');
nexttile; stairs(t, r, 'k--'); hold on; plot(t, y, 'b', 'LineWidth', 1.4);
xlim([175 350]); ylim([49 56]); grid on;
ylabel('Temperatura (graus C)'); title('Degrau nominal de referencia');
legend('R', 'Y', 'Location', 'southeast');
nexttile; plot(ts, yon, 'b', 'LineWidth', 1.4); hold on;
plot(ts, yoff, 'r'); yline(50, 'k--'); xlim([2200 2600]); grid on;
ylabel('Temperatura (graus C)'); title('Perturbacao senoidal isolada');
legend('Compensacao ligada', 'Desligada', 'R', 'Location', 'southeast');
nexttile; plot(ta, yaw, 'b', 'LineWidth', 1.4); hold on;
plot(ta, ysem, 'r'); stairs(ta, ra, 'k--'); xlim([450 850]); grid on;
xlabel('Tempo (s)'); ylabel('Temperatura (graus C)');
title('Estresse numerico de saturacao (nao aplicar na bancada)');
legend('Com anti-windup', 'Sem anti-windup', 'R', 'Location', 'northeast');
exportgraphics(f, arquivo, 'Resolution', 170);
close(f);
end
