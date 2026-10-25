function resultado = ETAPA09B_comparar_controladores
%COMPARAR_CONTROLADOR_MULTIMODELO_PRJ2 Testa uma sintonia nos dois extremos.
% A planta e o observador do controlador permanecem nominais. A planta real
% simulada alterna entre o P2DZ sem cooler e o P1D identificado com W=3211.
% Nenhum SLX, firmware ou parametro oficial e modificado.

pasta = fileparts(mfilename('fullpath'));
raizProjeto = fileparts(fileparts(pasta));
apoio = fullfile(raizProjeto, 'resultados', 'artefatos');
saida = fullfile(raizProjeto,'resultados','comparacao_multimodelo');
if ~isfolder(saida), mkdir(saida); end

S = load(fullfile(apoio,'modelos_discretos.mat'),'discreto'); d = S.discreto;
S = load(fullfile(apoio,'controlador_discreto.mat'),'controle'); base = S.controle;
S = load(fullfile(apoio,'planta_p2dz.mat'),'resultado'); nominal = S.resultado;
S = load(fullfile(raizProjeto,'resultados','identificacao_cooler', ...
    'identificacao_cooler_resultado.mat'),'resultado'); idCooler = S.resultado;

Ts = d.Ts;
pCool = get(idCooler.modeloSelecionado);
assert(idCooler.nomeSelecionado == "P1D", 'Esperado modelo P1D selecionado.');
Gcool = ss(tf(pCool.Kp,[pCool.Tp1 1]));
Gcoold = c2d(Gcool,Ts,'zoh');

plantas = {
    struct('nome',"P2DZ nominal, W=0",'A',d.Ad,'B',d.Bd,'C',d.Cd, ...
        'uEq',nominal.u0+(50-nominal.y0)/nominal.parametros.Kp), ...
    struct('nome',"P1D identificado, W=3211",'A',Gcoold.A, ...
        'B',Gcoold.B,'C',Gcoold.C,'uEq',idCooler.u0)};

% Inclui o refinamento atual (19 s) e alternativas mais lentas/rapidas.
alvos = [15 19 22 25 30 40 50 60 80];
linhas = numel(alvos)*numel(plantas);
metricas = table('Size',[linhas 11], ...
    'VariableTypes',["double","string",repmat("double",1,9)], ...
    'VariableNames',{'AlvoInterno_s','Planta','Tr10a90_s','Mp_pct', ...
    'Ts2pct_s','ErroFinal_C','IAE_Cs','PwmMin','PwmMax', ...
    'FracaoSaturada','Estavel'});
ensaios = cell(numel(alvos),numel(plantas));

linha = 0;
for a = 1:numel(alvos)
    c = sintonizar(base,Ts,alvos(a));
    for p = 1:numel(plantas)
        linha = linha+1;
        e = simular(d,c,plantas{p},nominal.u0,nominal.y0,Ts);
        m = medir(e);
        metricas(linha,:) = {alvos(a),plantas{p}.nome,m.Tr,m.Mp, ...
            m.Ts2,m.erroFinal,m.IAE,min(e.u),max(e.u), ...
            mean(e.u<=0 | e.u>=65535),double(m.estavel)};
        ensaios{a,p} = e;
    end
end

% Uma sintonia robusta deve permanecer estavel nos dois extremos. Entre as
% candidatas sem saturacao e com erro final pequeno, minimiza-se primeiro o
% pior sobressinal e depois a pior diferenca de Tr em relacao a 20 s.
resumo = table('Size',[numel(alvos) 8], ...
    'VariableTypes',repmat("double",1,8), ...
    'VariableNames',{'AlvoInterno_s','PiorTr_s','PiorMp_pct', ...
    'PiorTs2pct_s','PiorErroFinal_C','PiorIAE_Cs', ...
    'MaiorFracaoSaturada','ConformeRoteiroNosDois'});
for a=1:numel(alvos)
    q = metricas(metricas.AlvoInterno_s==alvos(a),:);
    resumo{a,:} = [alvos(a),max(q.Tr10a90_s),max(q.Mp_pct), ...
        max(q.Ts2pct_s),max(abs(q.ErroFinal_C)),max(q.IAE_Cs), ...
        max(q.FracaoSaturada),double(all(q.Estavel) && ...
        max(abs(q.ErroFinal_C))<0.05 && max(q.FracaoSaturada)==0 && ...
        max(q.Tr10a90_s)<=22 && max(q.Mp_pct)<=1)];
end

existeSintoniaConforme = any(resumo.ConformeRoteiroNosDois==1);
alvoAtual = 19;

resultado = struct('Ts',Ts,'plantas',{plantas},'alvosInternos_s',alvos, ...
    'metricas',metricas,'resumo',resumo,'ensaios',{ensaios}, ...
    'existeSintoniaUnicaConforme',existeSintoniaConforme, ...
    'alvoAtual_s',alvoAtual,'controleAtual',sintonizar(base,Ts,alvoAtual), ...
    'observacao',['Selecao exploratoria; nao altera controlador oficial. ' ...
    'A planta intermediaria depende de W e ainda nao foi identificada.']);

save(fullfile(saida,'comparacao_multimodelo_resultado.mat'),'resultado');
writetable(metricas,fullfile(saida,'metricas_multimodelo.csv'));
writetable(resumo,fullfile(saida,'resumo_sintonias.csv'));
plotar(resultado,saida);

fprintf('\nResumo por sintonia:\n'); disp(resumo);
if existeSintoniaConforme
    fprintf('Ha sintonia unica conforme nos dois modelos.\n');
else
    fprintf(['Nenhuma sintonia unica desta familia atende simultaneamente ' ...
        'Tr e Mp nos dois modelos. Manter 19 s como oficial.\n']);
end
fprintf('Resultados: %s\n',saida);
end

function c = sintonizar(base,Ts,alvo)
c = base;
p = -log(9)/alvo;
polos = [base.zeroPlanta,exp(p*Ts),exp(p*Ts/3),exp(4*p*Ts)];
F = place(base.Ai,base.Bi,polos);
Acl = base.Ai-base.Bi*F;
[V,D] = eig(Acl');
[~,i] = min(abs(diag(D)-polos(3)));
l = V(:,i);
Nb = real(-(l'*base.Er)/(l'*base.Bi));
assert(-F(4)>0 && Nb>0 && all(abs(eig(Acl))<1),'Sintonia invalida.');
c.F=F; c.K=F(1:2); c.Kq=F(3); c.Ki=-F(4); c.Nb=Nb;
end

function e = simular(d,c,p,u0,y0,Ts)
t=(0:Ts:800)'; n=numel(t); r=50+5*(t>=200-Ts/2);
x=zeros(size(p.A,1),1); qPlanta=0;
q=p.uEq-u0;
% Estado estacionario do observador nominal para Y=R=50 e PWM de equilibrio.
xh=(eye(size(d.Aod))-d.Aod+d.Ld*d.Cod)\(d.Bod*q+d.Ld*(50-y0));
comp=c.Kq*xh(3)+d.Fd(1,:)*xh(3:4);
xi=(p.uEq-u0-c.Nb*(50-y0)+c.F(1:2)*xh(1:2)+c.Kq*q+comp)/c.Ki;

y=zeros(n,1);u=zeros(n,1);uLivre=zeros(n,1);
for k=1:n
    y(k)=50+p.C*x;
    erro=r(k)-y(k);
    inovacao=y(k)-y0-d.Cod*xh;
    comp=c.Kq*xh(3)+d.Fd(1,:)*xh(3:4);
    uLivre(k)=u0+c.Nb*(r(k)-y0)-c.F(1:2)*xh(1:2) ...
        -c.Kq*q+c.Ki*xi-comp;
    u(k)=min(max(uLivre(k),0),65535);
    xNovo=p.A*x+p.B*qPlanta;
    qNovo=u(k)-u0;
    xhNovo=d.Aod*xh+d.Bod*q+d.Ld*inovacao;
    if k<n
        yProximo=50+p.C*xNovo;
        erroProximo=r(k)-yProximo;
        xi=xi+Ts/2*(erro+erroProximo)+(u(k)-uLivre(k))/c.Ki;
    end
    x=xNovo; xh=xhNovo; q=qNovo; qPlanta=u(k)-p.uEq;
end
e=struct('t',t,'r',r,'y',y,'u',u,'uLivre',uLivre);
end

function m = medir(e)
jan=e.t>=200; tt=e.t(jan); yy=e.y(jan); erro=e.r(jan)-yy;
t10=cruzamento(tt,yy,50.5); t90=cruzamento(tt,yy,54.5);
m.Tr=t90-t10;
m.Mp=max(0,(max(yy)-55)/5*100);
dentro=abs(yy-55)<=0.1;
k=find(cummin(flip(dentro))==1,1,'last');
if isempty(k), m.Ts2=Inf; else, m.Ts2=tt(numel(tt)-k+1)-200; end
m.erroFinal=mean(erro(end-min(9,numel(erro)-1):end));
m.IAE=trapz(tt,abs(erro));
m.estavel=all(isfinite(yy)) && max(abs(yy))<100;
end

function tc = cruzamento(t,y,nivel)
k=find(y>=nivel,1,'first');
if isempty(k) || k==1, tc=Inf; return; end
tc=interp1(y(k-1:k),t(k-1:k),nivel);
end

function plotar(r,saida)
f=figure('Visible','off','Color','w','Position',[100 100 1450 850]);
tiledlayout(2,1,'TileSpacing','compact','Padding','compact');
for p=1:2
    nexttile; hold on; grid on;
    for a=1:numel(r.alvosInternos_s)
        e=r.ensaios{a,p};
        plot(e.t,e.y,'DisplayName',sprintf('alvo %.0f s',r.alvosInternos_s(a)));
    end
    plot(e.t,e.r,'k--','LineWidth',1.5,'DisplayName','R');
    title(r.plantas{p}.nome); ylabel('Y (°C)');
    if p==2, xlabel('Tempo (s)'); end
    legend('Location','eastoutside');
end
exportgraphics(f,fullfile(saida,'respostas_multimodelo.png'),'Resolution',180);
close(f);

f=figure('Visible','off','Color','w','Position',[100 100 1200 650]);
plot(r.resumo.AlvoInterno_s,r.resumo.PiorTr_s,'o-','LineWidth',1.3);hold on;
plot(r.resumo.AlvoInterno_s,r.resumo.PiorMp_pct,'s-','LineWidth',1.3);
xline(r.alvoAtual_s,'--k','sintonia atual');grid on;
xlabel('Alvo interno da sintonia nominal (s)');
legend('Pior Tr (s)','Pior Mp (%)','Location','best');
title('Compromisso nos dois modelos extremos');
exportgraphics(f,fullfile(saida,'compromisso_multimodelo.png'),'Resolution',180);
close(f);
end
