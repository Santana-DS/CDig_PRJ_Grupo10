%% ETAPA 09 - ANALISE EXPERIMENTAL: PI DISCRETO COM E SEM ANTI-WINDUP
% Processa os dois ensaios do controlador C(z)=1700(z-0.922)/(z-1).
% Produz figuras individuais, comparacao direta e uma tabela de metricas.
% O ISE e calculado com o erro registrado pela ESP32, usando integracao
% trapezoidal sobre a janela prescrita pelo roteiro.

clearvars; clc; close all;

%% Configuracao do ensaio e destinos
pastaScript = fileparts(mfilename("fullpath"));
pastaProjeto = fileparts(fileparts(pastaScript));
pastaDados = fullfile(pastaProjeto, "dados");
pastaFiguras = fullfile(pastaProjeto, "resultados", "figuras");
idControlador = "p2dz_k1700_z922";
janelaISE = [2100 3000];
colunasNecessarias = {'t', 'R', 'Y', 'U', 'U_s', 'W', 'Ta', 'e'};

arquivoComAW = fullfile(pastaDados, "ensaio_" + idControlador + "_com_aw.csv");
arquivoSemAW = fullfile(pastaDados, "ensaio_" + idControlador + "_sem_aw.csv");
if ~isfolder(pastaFiguras), mkdir(pastaFiguras); end

% A coleta fisica nao deve ser comparada com arquivos de sintonias antigas.
dadosComAW = carregarEnsaio(arquivoComAW, colunasNecessarias);
dadosSemAW = carregarEnsaio(arquivoSemAW, colunasNecessarias);

%% Metricas numericas
metricasComAW = calcularMetricas(dadosComAW, "Com AW", janelaISE);
metricasSemAW = calcularMetricas(dadosSemAW, "Sem AW", janelaISE);
resumo = [metricasComAW; metricasSemAW];
writetable(resumo, fullfile(pastaFiguras, "09_METRICAS.csv"));
disp(resumo);

fprintf("\nISE [%d,%d] s: com AW = %.2f C^2.s | sem AW = %.2f C^2.s\n", ...
    janelaISE(1), janelaISE(2), metricasComAW.ISE_Janela, metricasSemAW.ISE_Janela);

%% Figuras individuais
plotarEnsaio(dadosComAW, "Com anti-windup", ...
    fullfile(pastaFiguras, "09.COM_AW.png"));
plotarEnsaio(dadosSemAW, "Sem anti-windup", ...
    fullfile(pastaFiguras, "09.SEM_AW.png"));

%% Comparacoes: visao global e primeiro degrau positivo
plotarComparacao(dadosComAW, dadosSemAW, metricasComAW, metricasSemAW, ...
    janelaISE, [0 3600], fullfile(pastaFiguras, "09_COMPARACAO_n.png"));
plotarComparacao(dadosComAW, dadosSemAW, metricasComAW, metricasSemAW, ...
    janelaISE, [350 1000], fullfile(pastaFiguras, "09_COMPARACAO_ZOOM_n.png"));

%% Funcoes locais
function dados = carregarEnsaio(arquivo, colunas)
    if ~isfile(arquivo)
        error("Arquivo nao encontrado: %s", arquivo);
    end
    dados = readtable(arquivo);
    if ~all(ismember(colunas, dados.Properties.VariableNames))
        error("Formato invalido em %s. Colunas esperadas: %s", ...
            arquivo, strjoin(colunas, ", "));
    end
    valores = dados{:, colunas};
    if height(dados) < 2 || ~isnumeric(valores) || any(~isfinite(valores(:)))
        error("Dados ausentes ou nao numericos em %s.", arquivo);
    end
    if any(diff(dados.t) <= 0)
        error("O vetor de tempo deve ser estritamente crescente em %s.", arquivo);
    end
end
function metricas = calcularMetricas(dados, modo, janelaISE)
    mascaraISE = dados.t >= janelaISE(1) & dados.t <= janelaISE(2);
    if nnz(mascaraISE) < 2
        error("O ensaio nao contem amostras suficientes na janela ISE.");
    end

    % Primeiro degrau positivo de referencia: 45 para 55 C, em torno de 400 s.
    indiceSubida = find(diff(dados.R) > 0, 1, "first") + 1;
    [mp, tp] = metricasPrimeiroDegrau(dados, indiceSubida);
    diferencaSaturacao = abs(dados.U - dados.U_s);

    metricas = table(string(modo), height(dados), dados.t(end), ...
        median(diff(dados.t)), trapz(dados.t, dados.e.^2), ...
        trapz(dados.t, abs(dados.e)), trapz(dados.t(mascaraISE), ...
        dados.e(mascaraISE).^2), max(dados.Y), min(dados.Y), mp, tp, ...
        nnz(diferencaSaturacao > 1e-6), ...
        'VariableNames', {'Modo', 'Amostras', 'Duracao_s', 'TsMedio_s', ...
        'ISE_Total', 'IAE_Total', 'ISE_Janela', 'Ymax_C', 'Ymin_C', ...
        'Mp1_pct', 'Tp1_s', 'AmostrasSaturadas'});
end

function [mp, tp] = metricasPrimeiroDegrau(dados, indiceSubida)
    mp = NaN; tp = NaN;
    if isempty(indiceSubida) || indiceSubida <= 1
        return;
    end
    tDegrau = dados.t(indiceSubida);
    rInicial = dados.R(indiceSubida - 1);
    rFinal = dados.R(indiceSubida);
    if rFinal <= rInicial
        return;
    end

    % A proxima mudanca de referencia delimita a resposta ao degrau.
    indiceFim = find(dados.t > tDegrau & abs(dados.R - rFinal) > 1e-9, ...
        1, "first");
    if isempty(indiceFim), indiceFim = height(dados); end
    janela = indiceSubida:indiceFim-1;
    [yPico, indiceLocal] = max(dados.Y(janela));
    mp = 100 * (yPico - rFinal) / (rFinal - rInicial);
    tp = dados.t(janela(indiceLocal)) - tDegrau;
end

function plotarEnsaio(dados, descricao, arquivoFigura)
    figura = figure("Color", "w", "Position", [80 80 1100 820]);
    layout = tiledlayout(figura, 3, 1, "TileSpacing", "compact", "Padding", "compact");
    tempoFinal = min(3600, dados.t(end));

    nexttile(layout); hold on;
    plot(dados.t, dados.R, "Color", [0 0.20 0.80], "LineWidth", 1.5, ...
        "DisplayName", "Referencia R");
    plot(dados.t, dados.Y, "Color", [0 0.55 0], "LineWidth", 1.3, ...
        "DisplayName", "Temperatura Y");
    grid on; xlim([0 tempoFinal]); ylabel("Temperatura (C)");
    title("Resposta em malha fechada - " + descricao); legend("Location", "best");

    nexttile(layout); hold on;
    plot(dados.t, dados.U, "Color", [0.85 0 0], "LineWidth", 1.0, ...
        "DisplayName", "U calculado");
    plot(dados.t, dados.U_s, "Color", [0.93 0.55 0.05], "LineWidth", 1.3, ...
        "DisplayName", "U aplicado");
    yline(0, "k--", "Limite inferior", "HandleVisibility", "off");
    grid on; xlim([0 tempoFinal]); ylabel("PWM do aquecedor (16 bits)");
    title("Acao de controle e saturacao"); legend("Location", "best");
    ylim(limitesComMargem([dados.U; dados.U_s]));

    nexttile(layout); hold on;
    yyaxis left
    plot(dados.t, dados.W, "Color", [0.49 0.18 0.56], "LineWidth", 1.1);
    ylabel("PWM do cooler (12 bits)");
    yyaxis right
    plot(dados.t, dados.Ta, "Color", [0.1 0.60 0.60], "LineWidth", 1.0);
    ylabel("Temperatura ambiente (C)");
    grid on; xlim([0 tempoFinal]); xlabel("Tempo (s)");
    title("Perturbacao e temperatura ambiente");

    exportgraphics(figura, arquivoFigura, "Resolution", 240);
end

function plotarComparacao(comAW, semAW, metCom, metSem, janelaISE, janelaPlot, arquivoFigura)
    [t, r, yCom, ySem] = alinharEnsaios(comAW, semAW);
    mascara = t >= janelaPlot(1) & t <= janelaPlot(2);
    t = t(mascara); r = r(mascara); yCom = yCom(mascara); ySem = ySem(mascara);

    figura = figure("Color", "w", "Position", [100 100 1100 490]); hold on;
    plot(t, r, "k:", "LineWidth", 1.7, "DisplayName", "Referencia");
    plot(t, yCom, "Color", [0 0.20 0.90], "LineWidth", 1.35, ...
        "DisplayName", "Com AW");
    plot(t, ySem, "Color", [0.90 0.05 0.05], "LineWidth", 1.25, ...
        "DisplayName", "Sem AW");
    if janelaPlot(1) <= janelaISE(1) && janelaPlot(2) >= janelaISE(2)
        xline(janelaISE(1), "k--", "HandleVisibility", "off");
        xline(janelaISE(2), "k--", "HandleVisibility", "off");
        tituloISE = sprintf(" | ISE [%d,%d] s: AW %.1f | sem AW %.1f C^2.s", ...
            janelaISE(1), janelaISE(2), metCom.ISE_Janela, metSem.ISE_Janela);
    else
        tituloISE = "";
    end
    grid on; xlim(janelaPlot); xlabel("Tempo (s)"); ylabel("Temperatura (C)");
    title("Comparacao da resposta em malha fechada" + tituloISE);
    legend("Location", "best");
    exportgraphics(figura, arquivoFigura, "Resolution", 240);
end


function [t, r, yCom, ySem] = alinharEnsaios(comAW, semAW)
    inicio = max(comAW.t(1), semAW.t(1));
    fim = min(comAW.t(end), semAW.t(end));
    t = unique([comAW.t(comAW.t >= inicio & comAW.t <= fim); ...
                semAW.t(semAW.t >= inicio & semAW.t <= fim)]);
    r = interp1(comAW.t, comAW.R, t, "previous");
    yCom = interp1(comAW.t, comAW.Y, t, "linear");
    ySem = interp1(semAW.t, semAW.Y, t, "linear");
end

function limites = limitesComMargem(valores)
    valores = valores(isfinite(valores));
    minimo = min(valores); maximo = max(valores);
    margem = max(0.08 * (maximo - minimo), 500);
    limites = [minimo - margem, maximo + margem];
end
