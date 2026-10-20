function resultado = ETAPA08C_analisar_identificacao_cooler
%ANALISAR_IDENTIFICACAO_COOLER_PRJ2 Identifica a planta sob conveccao forcada.
% Usa quatro periodos PRBS completos para estimacao e dois para validacao.
% Compara modelos de 1a, 2a e 3a ordem com a planta nominal.

pasta = fileparts(mfilename('fullpath'));
raizProjeto = fileparts(fileparts(pasta));
apoio = fullfile(raizProjeto, 'resultados', 'artefatos');
pastaSaida = fullfile(raizProjeto, 'resultados', ...
    'identificacao_cooler');
if ~isfolder(pastaSaida), mkdir(pastaSaida); end

csv = fullfile(raizProjeto, 'dados', 'identificacao_planta_com_cooler.csv');
assert(isfile(csv), 'Coleta nao encontrada: %s', csv);
T = readtable(csv);
campos = {'t','fase','R','Y','Ta','U_base','du','Us','W'};
assert(all(ismember(campos, T.Properties.VariableNames)), ...
    'CSV sem as colunas esperadas.');
assert(all(isfinite(T{:,campos}),'all'), 'A coleta contem valores nao finitos.');

Ts = median(diff(T.t));
erroTs = max(abs(diff(T.t)-Ts));
assert(abs(Ts-5.715) < 1e-3 && erroTs < 2e-3, ...
    'Amostragem incompatível com Ts=5,715 s.');
assert(all(T.W == 3211), 'O cooler nao permaneceu em W=3211.');
assert(max(T.Y) < 60, 'A coleta atingiu o limite termico.');

P = T(T.fase == 2,:);
periodo = 254;             % 127 bits, dois samples por bit
nEst = 4*periodo;
nVal = 2*periodo;
assert(height(P) >= nEst+nVal, 'Menos de seis periodos PRBS completos.');

% Um periodo maximal tem 64 niveis positivos e 63 negativos. A remocao
% destas medias evita que o pequeno desbalanceamento contamine os offsets.
uEst0 = mean(P.Us(1:nEst));
yEst0 = mean(P.Y(1:nEst));
uEst = P.Us(1:nEst)-uEst0;
yEst = P.Y(1:nEst)-yEst0;
uVal = P.Us(nEst+(1:nVal))-uEst0;
yVal = P.Y(nEst+(1:nVal))-yEst0;

zEst = iddata(yEst, uEst, Ts, 'Name', 'PRBS cooler - estimacao');
zVal = iddata(yVal, uVal, Ts, 'Name', 'PRBS cooler - validacao');

tipos = {'P1D','P2D','P2DZ','P3D','P3DZ'};
nomes = ["P1D","P2D","P2DZ","P3D","P3DZ"];
modelos = cell(size(tipos));
for k = 1:numel(tipos)
    inicial = idproc(tipos{k});
    inicial.Kp = 0.0022;
    inicial.Td = Ts;
    inicial.Structure.Kp.Minimum = 0;
    inicial.Structure.Td.Minimum = 0;
    inicial.Structure.Td.Maximum = 4*Ts;
    % O firmware atualiza o atuador e mede no mesmo periodo. A coleta nao
    % resolve atrasos subamostrais; por isso preservamos o atraso de uma
    % amostra ja identificado e usado em todo o projeto digital.
    inicial.Structure.Td.Free = false;
    if contains(tipos{k}, 'P1'), inicial.Tp1 = 120; end
    if contains(tipos{k}, 'P2')
        inicial.Tp1 = 240; inicial.Tp2 = 32;
    end
    if contains(tipos{k}, 'P3')
        inicial.Tp1 = 240; inicial.Tp2 = 32; inicial.Tp3 = 12;
    end
    if contains(tipos{k}, 'Z'), inicial.Tz = 190; end
    modelos{k} = procest(zEst, inicial);
end

% Planta nominal identificada sem cooler, para comparacao justa no mesmo
% conjunto de validacao e com os mesmos offsets incrementais.
origem = fullfile(apoio, 'planta_p2dz.mat');
S = load(origem, 'resultado');
modeloOriginal = S.resultado.modelo;
modelosTodos = [{modeloOriginal}, modelos];
nomesTodos = ["P2DZ original (sem cooler)", nomes];

n = numel(yVal);
metricas = table('Size',[numel(modelosTodos),15], ...
    'VariableTypes', ["string", repmat("double",1,14)], ...
    'VariableNames', {'Modelo','FitEstimacao_pct','FitValidacao_pct', ...
    'RMSEValidacao_C','MaxErroValidacao_C','AICValidacao', ...
    'BICValidacao','MaxAutocorrRes_L1a20','Kp','Tp1_s','Tp2_s', ...
    'Tp3_s','Tz_s','Td_s','NumeroParametros'});
predicoes = zeros(n, numel(modelosTodos));
residuos = zeros(n, numel(modelosTodos));

for k = 1:numel(modelosTodos)
    m = modelosTodos{k};
    [~, fitEst] = compare(zEst, m);
    [yh, fitVal] = compare(zVal, m);
    yp = yh.OutputData;
    e = yVal-yp;
    predicoes(:,k) = yp;
    residuos(:,k) = e;
    np = numel(getpvec(m));
    sse = sum(e.^2);
    p = get(m);
    metricas.Modelo(k) = nomesTodos(k);
    metricas.FitEstimacao_pct(k) = fitEst;
    metricas.FitValidacao_pct(k) = fitVal;
    metricas.RMSEValidacao_C(k) = sqrt(mean(e.^2));
    metricas.MaxErroValidacao_C(k) = max(abs(e));
    metricas.AICValidacao(k) = n*log(sse/n)+2*np;
    metricas.BICValidacao(k) = n*log(sse/n)+np*log(n);
    metricas.MaxAutocorrRes_L1a20(k) = maxAutocorr(e,20);
    metricas.Kp(k) = campo(p,'Kp');
    metricas.Tp1_s(k) = campo(p,'Tp1');
    metricas.Tp2_s(k) = campo(p,'Tp2');
    metricas.Tp3_s(k) = campo(p,'Tp3');
    metricas.Tz_s(k) = campo(p,'Tz');
    metricas.Td_s(k) = campo(p,'Td');
    metricas.NumeroParametros(k) = np;
end

% Decisao conservadora: entre os modelos de ate 2a ordem, escolher o mais
% simples que fique a menos de 2 pontos percentuais do melhor FIT. Assim,
% um segundo polo quase instantaneo nao e confundido com ordem fisica real.
% Uma 3a ordem so e aceita se aumentar o FIT em >=5 pontos e reduzir a
% correlacao residual. Isso evita trocar interpretabilidade por sobreajuste.
idxOrdem2 = find(ismember(metricas.Modelo,["P1D","P2D","P2DZ"]));
[~,j2] = max(metricas.FitValidacao_pct(idxOrdem2));
melhorFit2 = metricas.FitValidacao_pct(idxOrdem2(j2));
idxElegiveis = idxOrdem2(metricas.FitValidacao_pct(idxOrdem2) >= melhorFit2-2);
[~,jSimples] = min(metricas.NumeroParametros(idxElegiveis));
idxBase = idxElegiveis(jSimples);
idxOrdem3 = find(ismember(metricas.Modelo,["P3D","P3DZ"]));
[~,j3] = max(metricas.FitValidacao_pct(idxOrdem3));
idx3 = idxOrdem3(j3);
ganhoFit3 = metricas.FitValidacao_pct(idx3)-metricas.FitValidacao_pct(idxBase);
if ganhoFit3 >= 5 && metricas.MaxAutocorrRes_L1a20(idx3) < ...
        metricas.MaxAutocorrRes_L1a20(idxBase)
    idxSelecionado = idx3;
else
    idxSelecionado = idxBase;
end

% Estatisticas de repetibilidade por periodo completo.
ciclos = table('Size',[6,7], ...
    'VariableTypes', repmat("double",1,7), ...
    'VariableNames', {'Ciclo','tInicial_s','tFinal_s','Ymedia_C', ...
    'Ymin_C','Ymax_C','Tamedia_C'});
for c = 1:6
    q = P((c-1)*periodo+(1:periodo),:);
    ciclos{c,:} = [c q.t(1) q.t(end) mean(q.Y) min(q.Y) max(q.Y) mean(q.Ta)];
end

writetable(metricas, fullfile(pastaSaida,'metricas_modelos.csv'));
writetable(ciclos, fullfile(pastaSaida,'repetibilidade_ciclos.csv'));

modeloSelecionado = modelosTodos{idxSelecionado};
resultado = struct('csvOrigem',csv,'Ts',Ts,'erroMaxTs',erroTs, ...
    'u0',uEst0,'y0',yEst0,'periodoAmostras',periodo, ...
    'indicesEstimacao',1:nEst,'indicesValidacao',nEst+(1:nVal), ...
    'modelos',{modelosTodos},'nomesModelos',nomesTodos, ...
    'metricas',metricas,'ciclos',ciclos, ...
    'indiceSelecionado',idxSelecionado, ...
    'nomeSelecionado',nomesTodos(idxSelecionado), ...
    'modeloSelecionado',modeloSelecionado,'ganhoFitOrdem3',ganhoFit3);
save(fullfile(pastaSaida,'identificacao_cooler_resultado.mat'),'resultado');

gerarFiguras(T,P,nEst,nVal,yEst0,yVal,predicoes,residuos, ...
    nomesTodos,idxSelecionado,pastaSaida);

selecionado = metricas(idxSelecionado, :);
fprintf(['Identificação com cooler concluída | %s | FIT %.2f%% | ' ...
    'RMSE %.3f °C\n'], nomesTodos(idxSelecionado), ...
    selecionado.FitValidacao_pct, selecionado.RMSEValidacao_C);
end

function v = campo(s,nome)
if isfield(s,nome), v = s.(nome); else, v = NaN; end
end

function a = maxAutocorr(e,nLag)
e = e-mean(e); den = sum(e.^2); a = 0;
for lag = 1:nLag
    a = max(a,abs(sum(e(1:end-lag).*e(1+lag:end))/den));
end
end

function gerarFiguras(T,P,nEst,nVal,y0,yVal,pred,resid,nomes,idxSel,pasta)
f = figure('Visible','off','Color','w','Position',[100 100 1400 850]);
tiledlayout(3,1,'TileSpacing','compact','Padding','compact');
nexttile; plot(T.t,T.Y,'LineWidth',1.1); hold on; plot(T.t,T.R,'--');
yline(60,':r'); grid on; ylabel('Temperatura (°C)');
legend('Y','R','limite','Location','best'); title('Coleta completa');
nexttile; yyaxis left; plot(T.t,T.Ta); ylabel('Ta (°C)');
yyaxis right; plot(T.t,T.W); ylabel('W (PWM12)'); grid on;
title('Ambiente e cooler');
nexttile; stairs(T.t,T.Us,'LineWidth',1); hold on; plot(T.t,T.U_base,'--');
grid on; ylabel('PWM16'); xlabel('Tempo (s)'); legend('Us','U base');
title('Excitacao aplicada');
exportgraphics(f,fullfile(pastaSaida,'coleta_identificacao_cooler.png'),'Resolution',180);
close(f);

q = P(nEst+(1:nVal),:);
f = figure('Visible','off','Color','w','Position',[100 100 1400 750]);
plot(q.t-q.t(1),yVal+y0,'k','LineWidth',1.5,'DisplayName','medido'); hold on;
cores = lines(size(pred,2));
for k=1:size(pred,2)
    plot(q.t-q.t(1),pred(:,k)+y0,'Color',cores(k,:), ...
        'DisplayName',nomes(k));
end
grid on; xlabel('Tempo de validacao (s)'); ylabel('Y (°C)');
title('Validacao independente: dois periodos PRBS completos');
legend('Location','eastoutside');
exportgraphics(f,fullfile(pastaSaida,'comparacao_modelos_validacao.png'),'Resolution',180);
close(f);

e = resid(:,idxSel); e=e-mean(e); nLag=40; ac=zeros(nLag+1,1);
for lag=0:nLag
    ac(lag+1)=sum(e(1:end-lag).*e(1+lag:end))/sum(e.^2);
end
f=figure('Visible','off','Color','w','Position',[100 100 1100 650]);
stem(0:nLag,ac,'filled'); hold on; limite=1.96/sqrt(numel(e));
yline(limite,'--r'); yline(-limite,'--r'); grid on;
xlabel('Atraso (amostras)'); ylabel('Autocorrelacao');
title("Residuos de validacao - "+nomes(idxSel));
exportgraphics(f,fullfile(pastaSaida,'residuos_modelo_selecionado.png'),'Resolution',180);
close(f);
end
