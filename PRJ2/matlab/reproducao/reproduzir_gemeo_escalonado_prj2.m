function resultado = reproduzir_gemeo_escalonado_prj2
%REPRODUZIR_GEMEO_ESCALONADO_PRJ2 Reproduz o gemeo digital escalonado.
% O SLX ja contem todos os parametros no Model Workspace. Este script usa
% apenas o modelo final e a coleta experimental versionada no repositorio.

raizPrj2=fileparts(fileparts(fileparts(mfilename('fullpath'))));
modelo='Prj2CDig_escalonado_gemeo_v2';
arquivo=fullfile(raizPrj2,'simulink',[modelo '.slx']);
csv=fullfile(raizPrj2,'dados','ensaio_controle_refinado.csv');
assert(isfile(arquivo),'Modelo escalonado V2 nao encontrado em PRJ2/simulink.');
assert(isfile(csv),'Coleta final nao encontrada em PRJ2/dados.');

diretorioAnterior=pwd;
limpeza=onCleanup(@() cd(diretorioAnterior)); %#ok<NASGU>
cd(fullfile(raizPrj2,'simulink'));
load_system(arquivo);
out=sim(modelo);
d=readtable(csv,'VariableNamingRule','preserve');
g=findgroups(d.segmento); cont=splitapply(@numel,d.segmento,g);
[~,ig]=max(cont); d=d(g==ig,:); d=sortrows(d,'t');
yh=interp1(out.sim_Y.Time,out.sim_Y.Data,d.t,'linear','extrap');
uh=interp1(out.sim_Us.Time,out.sim_Us.Data,d.t,'linear','extrap');
erro=d.Y-yh;
fit=100*(1-norm(erro)/norm(d.Y-mean(d.Y)));
rmse=sqrt(mean(erro.^2)); erroMax=max(abs(erro));

limites=[0 400;400 800;800 1000;0 1000;1000 1800;1800 3000;3000 3600;0 3600];
rotulos=["0-400 s";"400-800 s";"800-1000 s";"0-1000 s"; ...
    "1000-1800 s";"1800-3000 s";"3000-3600 s";"total"];
fitTrecho=zeros(8,1); rmseTrecho=zeros(8,1); maxTrecho=zeros(8,1);
for i=1:8
    idx=d.t>=limites(i,1) & d.t<=limites(i,2); et=erro(idx); yt=d.Y(idx);
    fitTrecho(i)=100*(1-norm(et)/norm(yt-mean(yt)));
    rmseTrecho(i)=sqrt(mean(et.^2)); maxTrecho(i)=max(abs(et));
end
tabelaTrechos=table(rotulos,fitTrecho,rmseTrecho,maxTrecho, ...
    'VariableNames',{'trecho','FIT_pct','RMSE_C','erro_maximo_C'});

fig=figure('Name','Gemeo digital experimental V2 - PRJ2', ...
    'NumberTitle','off','Color','w','Position',[40 40 1500 900]);
tl=tiledlayout(fig,4,1,'TileSpacing','compact','Padding','compact');
title(tl,sprintf('Gêmeo digital V2 — FIT %.1f%%, RMSE %.3f °C',fit,rmse));
nexttile;
plot(d.t,d.R,'k--','LineWidth',1,'DisplayName','R'); hold on;
plot(d.t,d.Y,'Color',[.10 .35 .75],'LineWidth',2,'DisplayName','Y real');
plot(d.t,yh,'r-','LineWidth',1.5,'DisplayName','Y simulado');
grid on; xlim([0 3600]); ylabel('°C'); title('Referência e saída');
legend('Location','eastoutside');
nexttile;
plot(d.t,erro,'Color',[.5 0 .5],'LineWidth',1.3); yline(0,'k:');
grid on; xlim([0 3600]); ylabel('°C'); title('Resíduo: Y real - Y simulado');
nexttile;
plot(d.t,d.Us,'Color',[.10 .35 .75],'LineWidth',2,'DisplayName','Us real'); hold on;
plot(d.t,uh,'r-','LineWidth',1.3,'DisplayName','Us simulado');
grid on; xlim([0 3600]); ylabel('PWM16'); title('Ação de controle');
legend('Location','eastoutside');
nexttile;
plot(d.t,d.W,'Color',[.20 .60 .20],'LineWidth',2,'DisplayName','W'); hold on;
stairs(d.t,d.modo*3211,'k--','LineWidth',1,'DisplayName','modo × 3211');
grid on; xlim([0 3600]); xlabel('Tempo (s)'); ylabel('PWM12');
title('Perturbação e modo ativo'); legend('Location','eastoutside');

saidaFig=fullfile(raizPrj2,'resultados','figuras');
saidaMet=fullfile(raizPrj2,'resultados','metricas');
if ~isfolder(saidaFig), mkdir(saidaFig); end
if ~isfolder(saidaMet), mkdir(saidaMet); end
exportgraphics(fig,fullfile(saidaFig,'15_gemeo_escalonado_v2.png'), ...
    'Resolution',180);
fprintf('Gemeo V2 | FIT %.2f%% | RMSE %.3f °C | erro maximo %.3f °C.\n', ...
    fit,rmse,erroMax);
disp(tabelaTrechos);
resultado=struct('simulacao',out,'coleta',d,'yInterpolado',yh, ...
    'uInterpolado',uh,'erro',erro,'fit',fit,'rmse',rmse, ...
    'erroMaximo',erroMax,'trechos',tabelaTrechos,'figura',fig);
writetable(tabelaTrechos,fullfile(saidaMet,'metricas_gemeo_escalonado_v2.csv'));
end
