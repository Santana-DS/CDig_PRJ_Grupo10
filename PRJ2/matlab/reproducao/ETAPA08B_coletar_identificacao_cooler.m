function arquivo = ETAPA08B_coletar_identificacao_cooler
%COLETAR_IDENTIFICACAO_COOLER_PRJ2 Registra o ensaio complementar de 3 h.
% O Run inicia automaticamente. RESET da ESP32 limpa o gráfico e reinicia.

porta = "COM3";
colunas = ["t", "fase", "R", "Y", "Ta", "U_base", "du", "Us", "W"];
pasta = fileparts(mfilename('fullpath'));
raizProjeto = fileparts(fileparts(pasta));
pastaDados = fullfile(raizProjeto, 'dados');
if ~isfolder(pastaDados), mkdir(pastaDados); end

fig = criarFigura;
sp = serialport(porta, 115200, 'Timeout', 8);
configureTerminator(sp, "LF");
limpeza = onCleanup(@() pararSeguro(sp));
pause(0.5);

configuracao = iniciarFirmware(sp, colunas, true);
[arquivo, parcial] = nomesArquivos(pastaDados);
[dados, n, checkpoint] = reiniciar(fig, configuracao, colunas);
heartbeat = tic;
motivoFim = "";

try
    while isvalid(fig)
        if toc(heartbeat) >= 4
            writeline(sp, "HEARTBEAT");
            heartbeat = tic;
        end
        if sp.NumBytesAvailable == 0
            pause(0.03); drawnow limitrate; continue
        end
        linha = strtrim(string(readline(sp)));

        if linha == "READY: PRJ2_IDENTIFICACAO_COOLER"
            if n > 0
                salvar(dados(1:n,:), colunas, ...
                    replace(parcial, "_PARCIAL.csv", "_RESET.csv"));
            end
            configuracao = iniciarFirmware(sp, colunas, false);
            [arquivo, parcial] = nomesArquivos(pastaDados);
            [dados, n, checkpoint] = reiniciar(fig, configuracao, colunas);
            heartbeat = tic;
            continue
        end
        if linha == "END_DATA", break; end
        if startsWith(linha, "BASE_PWM,")
            fprintf('%s\n', linha); continue
        end
        if any(startsWith(linha, ["FIM_", "ALARME_", "PARADA_"]))
            motivoFim = linha; fprintf('%s\n', linha); continue
        end

        valores = str2double(split(linha, ','));
        if numel(valores) ~= numel(colunas) || any(isnan(valores))
            fprintf('[serial] %s\n', linha); continue
        end
        n = n + 1;
        dados(n,:) = valores(:).';
        atualizarFigura(fig, valores);

        if n-checkpoint >= 10
            salvar(dados(1:n,:), colunas, parcial);
            checkpoint = n;
            fprintf(['Amostra %d | t=%.1f s | fase=%d | Y=%.2f °C | ' ...
                'Ubase=%.0f | du=%+.0f\n'], n, valores(1), valores(2), ...
                valores(4), valores(6), valores(7));
        end
    end
catch erro
    if n > 0, salvar(dados(1:n,:), colunas, parcial); end
    rethrow(erro)
end

assert(n > 0, 'Nenhuma amostra válida foi recebida.');
salvar(dados(1:n,:), colunas, arquivo);
if isfile(parcial), delete(parcial); end
if motivoFim == "", motivoFim = "JANELA_FECHADA"; end
if isvalid(fig), fig.Name = "Identificação finalizada: " + motivoFim; end
fprintf('\nColeta finalizada: %d amostras; %.1f s.\nArquivo: %s\n', ...
    n, dados(n,1), arquivo);
end

function configuracao = iniciarFirmware(sp, colunas, pararAntes)
if pararAntes
    writeline(sp, "STOP"); pause(0.2); flush(sp);
end
writeline(sp, "START");
inicio = tic;
while toc(inicio) < 120
    if sp.NumBytesAvailable == 0, pause(0.03); continue; end
    linha = strtrim(string(readline(sp)));
    if linha == "READY: PRJ2_IDENTIFICACAO_COOLER"
        writeline(sp, "START");
    elseif linha == "START_DATA"
        configuracao = aguardarPrefixo(sp, ...
            "CONFIG,PRJ2,IDENTIFICACAO_COOLER,", 8);
        cabecalho = aguardarPrefixo(sp, "t,fase,R,Y,Ta,", 8);
        assert(cabecalho == strjoin(colunas, ','), ...
            'Cabeçalho serial inesperado: %s', cabecalho);
        return
    end
end
error('A ESP32 não iniciou a identificação em 120 s.');
end

function [arquivo, parcial] = nomesArquivos(pasta)
instante = string(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
arquivo = fullfile(pasta, ...
    "identificacao_planta_com_cooler_" + instante + ".csv");
parcial = fullfile(pasta, ...
    "identificacao_planta_com_cooler_" + instante + "_PARCIAL.csv");
end

function [dados, n, checkpoint] = reiniciar(fig, configuracao, colunas)
dados = nan(2200, numel(colunas)); n = 0; checkpoint = 0;
h = getappdata(fig, 'linhas'); nomes = fieldnames(h);
for k = 1:numel(nomes), clearpoints(h.(nomes{k})); end
eixos = getappdata(fig, 'eixos'); xlim(eixos(1), [0 60]);
fig.Name = "Identificação com cooler - coleta em andamento";
fprintf('%s\nColeta iniciada em t=0.\n\n', configuracao);
end

function fig = criarFigura
fig = figure('Name', 'Identificação com cooler', 'NumberTitle', 'off');
t = tiledlayout(fig, 3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
title(t, 'Identificação complementar da planta com cooler constante');
ax1 = nexttile(t); hold(ax1, 'on'); grid(ax1, 'on');
h.R = animatedline(ax1, 'DisplayName', 'R', 'Color', [0.929 0.694 0.125]);
h.Y = animatedline(ax1, 'DisplayName', 'Y', 'Color', [0 0.447 0.741], ...
    'LineWidth', 1.5); ylabel(ax1, '°C'); title(ax1, 'Referência e saída');
legend(ax1, 'Location', 'best');
ax2 = nexttile(t); grid(ax2, 'on'); yyaxis(ax2, 'left');
h.Ta = animatedline(ax2, 'DisplayName', 'Ta', ...
    'Color', [0.466 0.674 0.188], 'LineWidth', 1.2);
ylabel(ax2, 'Ta (°C)'); yyaxis(ax2, 'right');
h.W = animatedline(ax2, 'DisplayName', 'W', ...
    'Color', [0.850 0.325 0.098], 'LineWidth', 1.2);
ylim(ax2, [0 4095]); ylabel(ax2, 'W (PWM12)'); title(ax2, 'Ambiente e cooler');
legend(ax2, [h.Ta h.W], {'Ta','W'}, 'Location', 'best');
ax3 = nexttile(t); hold(ax3, 'on'); grid(ax3, 'on');
h.Us = animatedline(ax3, 'DisplayName', 'Us', ...
    'Color', [0.929 0.694 0.125], 'LineWidth', 1.4);
h.Ubase = animatedline(ax3, 'DisplayName', 'U base', ...
    'Color', [0 0.447 0.741], 'LineWidth', 1.1);
ylabel(ax3, 'PWM16'); xlabel(ax3, 'Tempo (s)');
title(ax3, 'Excitação aplicada'); legend(ax3, 'Location', 'best');
linkaxes([ax1 ax2 ax3], 'x');
setappdata(fig, 'linhas', h); setappdata(fig, 'eixos', [ax1 ax2 ax3]);
end

function atualizarFigura(fig, v)
h = getappdata(fig, 'linhas');
addpoints(h.R, v(1), v(3)); addpoints(h.Y, v(1), v(4));
addpoints(h.Ta, v(1), v(5)); addpoints(h.Ubase, v(1), v(6));
addpoints(h.Us, v(1), v(8)); addpoints(h.W, v(1), v(9));
eixos = getappdata(fig, 'eixos');
limite = max(60, 60*ceil((v(1)+1)/60)); xlim(eixos(1), [0 limite]);
if v(2) == 0
    fase = "acomodação";
elseif v(2) == 1
    fase = "média do equilíbrio";
else
    fase = "PRBS";
end
fig.Name = "Identificação com cooler - " + fase;
drawnow limitrate;
end

function linha = aguardarPrefixo(sp, prefixo, timeoutS)
inicio = tic;
while toc(inicio) < timeoutS
    if sp.NumBytesAvailable == 0, pause(0.03); continue; end
    linha = strtrim(string(readline(sp)));
    if startsWith(linha, prefixo), return; end
end
error('Tempo esgotado aguardando "%s".', prefixo);
end

function salvar(dados, colunas, arquivo)
writetable(array2table(dados, 'VariableNames', colunas), arquivo);
end

function pararSeguro(sp)
try
    writeline(sp, "STOP"); pause(0.1);
catch
    % A porta pode já ter sido desconectada.
end
end
