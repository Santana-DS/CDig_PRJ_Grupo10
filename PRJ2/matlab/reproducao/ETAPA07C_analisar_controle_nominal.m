function resultado = ETAPA07C_analisar_controle_nominal(arquivo)
%ANALISAR_COLETA_PRJ2 Quantifica o ensaio físico completo do PRJ2.
%   Sem argumento, usa o CSV completo mais recente em dados/.

pasta = fileparts(mfilename('fullpath'));
raizProjeto = fileparts(fileparts(pasta));
pastaDados = fullfile(raizProjeto, 'dados');
pastaResultados = fullfile(raizProjeto, 'resultados', ...
    'controle_nominal');
if nargin < 1
    lista = dir(fullfile(pastaDados, 'ensaio_controle_nominal*.csv'));
    nomes = string({lista.name});
    lista = lista(~contains(nomes, "PARCIAL") & ~contains(nomes, "RESET"));
    assert(~isempty(lista), 'Nenhuma coleta completa foi encontrada.');
    [~, k] = max([lista.datenum]);
    arquivo = fullfile(lista(k).folder, lista(k).name);
end

T = readtable(arquivo);
esperadas = ["t", "R", "Y", "Ta", "U_livre", "Us", "W", "e", ...
    "xi", "x1hat", "x2hat", "e_sin", "inovacao"];
assert(all(ismember(esperadas, string(T.Properties.VariableNames))), ...
    'O CSV não possui todas as colunas esperadas.');
assert(height(T) >= 620 && T.t(end) >= 3590, 'A coleta não contém uma hora.');
if ~isfolder(pastaResultados)
    mkdir(pastaResultados);
end

transicoes = medirTransicoes(T);
patamares = medirPatamares(T);
eventosPerturbacao = medirEventosPerturbacao(T);
dt = diff(T.t);
resultado = struct( ...
    'arquivo', arquivo, 'amostras', height(T), ...
    'duracao_s', T.t(end)-T.t(1), ...
    'Ts_mediana_s', median(dt), 'Ts_min_s', min(dt), 'Ts_max_s', max(dt), ...
    'Y_min_C', min(T.Y), 'Y_max_C', max(T.Y), ...
    'Ta_inicial_C', mean(T.Ta(T.t < 60)), ...
    'Ta_final_C', mean(T.Ta(T.t >= T.t(end)-60)), ...
    'Us_min', min(T.Us), 'Us_max', max(T.Us), ...
    'amostras_saturadas', sum(T.Us <= 0 | T.Us >= 65535), ...
    'W_min', min(T.W), 'W_max', max(T.W), ...
    'diferenca_max_Ulivre_Us', max(abs(T.U_livre-T.Us)), ...
    'transicoes', transicoes, 'patamares', patamares, ...
    'eventosPerturbacao', eventosPerturbacao);

nomeBase = "ensaio_controle_nominal";
writetable(transicoes, fullfile(pastaResultados, nomeBase + "_transicoes.csv"));
writetable(patamares, fullfile(pastaResultados, nomeBase + "_patamares.csv"));
writetable(eventosPerturbacao, ...
    fullfile(pastaResultados, nomeBase + "_eventos_perturbacao.csv"));
save(fullfile(pastaResultados, nomeBase + "_metricas.mat"), 'resultado');
plotar(T, fullfile(pastaResultados, nomeBase + "_sinais.png"));

fprintf('Amostras: %d | duração: %.3f s | Ts mediano: %.3f s\n', ...
    resultado.amostras, resultado.duracao_s, resultado.Ts_mediana_s);
fprintf('Y: %.3f a %.3f °C | Us: %.0f a %.0f | saturadas: %d\n', ...
    resultado.Y_min_C, resultado.Y_max_C, resultado.Us_min, ...
    resultado.Us_max, resultado.amostras_saturadas);
disp(transicoes(:, {'tempo_s','regime','sentido','Tr10a90_s', ...
    'extremo_C','excursao_pct','erroFinal_C'}));
disp(patamares(:, {'janela','regime','referencia_C','bias_C', ...
    'rms_C','amplitude64s_C','inovacaoMedia_C'}));
disp(eventosPerturbacao);
end

function saida = medirTransicoes(T)
indices = find(diff(T.R) ~= 0) + 1;
n = numel(indices);
tempo_s = nan(n,1); regime = strings(n,1); sentido = strings(n,1);
Rinicial_C = nan(n,1); Rfinal_C = nan(n,1); Yantes_C = nan(n,1);
Tr10a90_s = nan(n,1); extremo_C = nan(n,1); excursao_pct = nan(n,1);
erroFinal_C = nan(n,1);

for j = 1:n
    k = indices(j);
    tempo_s(j) = T.t(k);
    Rinicial_C(j) = T.R(k-1);
    Rfinal_C(j) = T.R(k);
    Yantes_C(j) = mean(T.Y(max(1,k-10):k-1));
    sentido(j) = ternario(Rfinal_C(j) > Rinicial_C(j), "subida", "descida");
    regime(j) = classificar(T.t(k));
    if j < n, fim = indices(j+1)-1; else, fim = height(T); end
    % Não misture uma alteração posterior do cooler à resposta do degrau.
    limitesRegime = [1000 1800 3000];
    proximoLimite = limitesRegime(find(limitesRegime > T.t(k), 1));
    if ~isempty(proximoLimite)
        primeiroAposLimite = find(T.t >= proximoLimite, 1);
        fim = min(fim, primeiroAposLimite-1);
    end
    faixa = k:fim;
    progresso = (T.Y(faixa)-Yantes_C(j))/(Rfinal_C(j)-Yantes_C(j));
    t10 = cruzamento(T.t(faixa), progresso, 0.1);
    t90 = cruzamento(T.t(faixa), progresso, 0.9);
    if isfinite(t10) && isfinite(t90), Tr10a90_s(j) = t90-t10; end
    if sentido(j) == "subida"
        extremo_C(j) = max(T.Y(faixa));
        excursao_pct(j) = 100*(extremo_C(j)-Rfinal_C(j)) / ...
            abs(Rfinal_C(j)-Rinicial_C(j));
    else
        extremo_C(j) = min(T.Y(faixa));
        excursao_pct(j) = 100*(Rfinal_C(j)-extremo_C(j)) / ...
            abs(Rfinal_C(j)-Rinicial_C(j));
    end
    trechoFinal = faixa(T.t(faixa) >= T.t(faixa(end))-60);
    erroFinal_C(j) = mean(T.Y(trechoFinal)-T.R(trechoFinal));
end

saida = table(tempo_s, regime, sentido, Rinicial_C, Rfinal_C, Yantes_C, ...
    Tr10a90_s, extremo_C, excursao_pct, erroFinal_C);
end

function saida = medirPatamares(T)
def = {
    "300-390",   "sem_cooler", 300, 390;
    "650-790",   "sem_cooler", 650, 790;
    "900-990",   "sem_cooler", 900, 990;
    "1500-1590", "cooler_constante", 1500, 1590;
    "1700-1790", "cooler_constante", 1700, 1790;
    "1800-1990", "cooler_senoidal", 1800, 1990;
    "2150-2390", "cooler_senoidal", 2150, 2390;
    "2550-2790", "cooler_senoidal", 2550, 2790;
    "2900-2990", "cooler_senoidal", 2900, 2990;
    "3050-3190", "cooler_constante", 3050, 3190;
    "3450-3595", "cooler_constante", 3450, 3595};
n = size(def,1);
janela = strings(n,1); regime = strings(n,1);
referencia_C = nan(n,1); bias_C = nan(n,1); mae_C = nan(n,1);
rms_C = nan(n,1); desvio_C = nan(n,1); amplitude64s_C = nan(n,1);
UsMedio = nan(n,1); eSinMedio = nan(n,1); inovacaoMedia_C = nan(n,1);

for j = 1:n
    janela(j) = def{j,1}; regime(j) = def{j,2};
    faixa = T.t >= def{j,3} & T.t < def{j,4};
    erro = T.Y(faixa)-T.R(faixa);
    referencia_C(j) = mode(T.R(faixa));
    bias_C(j) = mean(erro); mae_C(j) = mean(abs(erro));
    rms_C(j) = sqrt(mean(erro.^2)); desvio_C(j) = std(erro);
    UsMedio(j) = mean(T.Us(faixa)); eSinMedio(j) = mean(T.e_sin(faixa));
    inovacaoMedia_C(j) = mean(T.inovacao(faixa));
    if regime(j) == "cooler_senoidal"
        w = 2*pi/64;
        X = [ones(sum(faixa),1), cos(w*T.t(faixa)), sin(w*T.t(faixa))];
        b = X\erro;
        amplitude64s_C(j) = hypot(b(2), b(3));
    end
end
saida = table(janela, regime, referencia_C, bias_C, mae_C, rms_C, ...
    desvio_C, amplitude64s_C, UsMedio, eSinMedio, inovacaoMedia_C);
end

function saida = medirEventosPerturbacao(T)
tempo_s = [1000; 1800; 3000];
evento = ["liga cooler constante"; "inicia cooler senoidal"; ...
    "retorna cooler constante"];
n = numel(tempo_s);
Yantes_C = nan(n,1); piorErro_C = nan(n,1); tempoPior_s = nan(n,1);
rms_C = nan(n,1); recuperacao1C_s = nan(n,1); recuperacao2C_s = nan(n,1);

for j = 1:n
    inicio = find(T.t >= tempo_s(j), 1);
    proximaR = find(T.t > T.t(inicio) & T.R ~= T.R(inicio), 1);
    if isempty(proximaR), fim = height(T); else, fim = proximaR-1; end
    antes = T.t >= tempo_s(j)-60 & T.t < tempo_s(j);
    faixa = inicio:fim;
    erro = T.Y(faixa)-T.R(faixa);
    Yantes_C(j) = mean(T.Y(antes));
    [~, kpior] = max(abs(erro));
    piorErro_C(j) = erro(kpior);
    tempoPior_s(j) = T.t(faixa(kpior))-tempo_s(j);
    rms_C(j) = sqrt(mean(erro.^2));
    recuperacao1C_s(j) = tempoRecuperacao(T.t(faixa), erro, tempo_s(j), 1);
    recuperacao2C_s(j) = tempoRecuperacao(T.t(faixa), erro, tempo_s(j), 2);
end
saida = table(tempo_s, evento, Yantes_C, piorErro_C, tempoPior_s, ...
    rms_C, recuperacao1C_s, recuperacao2C_s);
end

function tempo = tempoRecuperacao(t, erro, inicio, limite)
% Primeiro instante após o qual o erro permanece dentro da faixa.
ultimaViolacao = find(abs(erro) > limite, 1, 'last');
if isempty(ultimaViolacao)
    tempo = 0;
elseif ultimaViolacao == numel(erro)
    tempo = NaN;
else
    tempo = t(ultimaViolacao+1)-inicio;
end
end

function t = cruzamento(tempo, progresso, nivel)
k = find(progresso >= nivel, 1, 'first');
if isempty(k) || k == 1
    t = NaN;
else
    t = interp1(progresso(k-1:k), tempo(k-1:k), nivel);
end
end

function regime = classificar(t)
if t < 1000, regime = "sem_cooler";
elseif t < 1800, regime = "cooler_constante";
elseif t < 3000, regime = "cooler_senoidal";
else, regime = "cooler_constante";
end
end

function y = ternario(condicao, a, b)
if condicao, y = a; else, y = b; end
end

function plotar(T, arquivo)
f = figure('Visible', 'off', 'Position', [100 100 1300 900]);
tiledlayout(f, 4, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
ax1 = nexttile; stairs(T.t,T.R,'Color',[0.929 0.694 0.125]); hold on;
plot(T.t,T.Y,'Color',[0 0.447 0.741],'LineWidth',1.1); grid on;
ylabel('°C'); title('Referência e saída'); legend('R','Y');
ax2 = nexttile; plot(T.t,T.Y-T.R,'Color',[0.494 0.184 0.556]); grid on;
yline(0,'k:'); ylabel('Y-R (°C)'); title('Erro de seguimento');
ax3 = nexttile; plot(T.t,T.Us,'Color',[0.929 0.694 0.125]); hold on;
plot(T.t,T.e_sin,'Color',[0 0.447 0.741]); grid on;
ylabel('PWM16'); title('Controle e perturbação estimada'); legend('Us','e sin');
ax4 = nexttile; yyaxis left; plot(T.t,T.Ta,'Color',[0.466 0.674 0.188]);
ylabel('Ta (°C)'); yyaxis right; plot(T.t,T.W,'Color',[0.850 0.325 0.098]);
ylim([0 4095]); ylabel('W (PWM12)'); grid on; xlabel('Tempo (s)');
title('Ambiente e cooler');
linkaxes([ax1 ax2 ax3 ax4],'x'); xlim([0 3600]);
exportgraphics(f, arquivo, 'Resolution', 180); close(f);
end
