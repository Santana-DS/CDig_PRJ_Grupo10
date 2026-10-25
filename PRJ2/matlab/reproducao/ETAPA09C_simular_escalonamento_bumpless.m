function resultado = ETAPA09C_simular_escalonamento_bumpless
%SIMULAR_ESCALONAMENTO_BUMPLESS_PRJ2 Valida a troca entre controladores.
% Compara chaveamento ingenuo e transferencia com rastreamento integral.
% As plantas sao mantidas nos extremos identificados; a transicao fisica
% entre elas nao e inventada, pois nao ha dados para identifica-la.

pasta=fileparts(mfilename('fullpath'));
raizProjeto=fileparts(fileparts(pasta));
apoio=fullfile(raizProjeto,'resultados','artefatos');
saida=fullfile(raizProjeto,'resultados','escalonamento_bumpless');
if ~isfolder(saida),mkdir(saida);end

S=load(fullfile(apoio,'modelos_discretos.mat'),'discreto');d=S.discreto;
S=load(fullfile(apoio,'controlador_discreto.mat'),'controle');cn=S.controle;
S=load(fullfile(apoio,'planta_p2dz.mat'),'resultado');nom=S.resultado;
S=load(fullfile(raizProjeto,'resultados','controlador_cooler', ...
    'controlador_p1d_cooler.mat'),'projeto');cp=S.projeto.controle;

ctlNom=normalizarNominal(cn,d,nom.u0,nom.y0);
ctlCool=normalizarCooler(cp);
uEqNom=nom.u0+(50-nom.y0)/nom.parametros.Kp;
Pnom=struct('nome',"P2DZ sem cooler",'A',d.Ad,'B',d.Bd,'C',d.Cd,'uEq',uEqNom);
Pc=struct('nome',"P1D com cooler",'A',ssdataA(cp),'B',ssdataB(cp), ...
    'C',ssdataC(cp),'uEq',cp.u0);

casos={ ...
    struct('nome',"ligar antes do proximo degrau",'planta',Pc,'a0',0,'a1',1,'tDegrau',180), ...
    struct('nome',"ligar durante transiente",'planta',Pc,'a0',0,'a1',1,'tDegrau',80), ...
    struct('nome',"desligar antes do proximo degrau",'planta',Pnom,'a0',1,'a1',0,'tDegrau',180)};
estrategias=["ingenua","rastreada instantanea","rastreada 2Ts", ...
    "rastreada 20s","rastreada 60s"];
rampas=[0 0 2*d.Ts 20 60];
rastrear=[false true true true true];
ensaios=cell(numel(casos),numel(estrategias));
metricas=table('Size',[numel(casos)*numel(estrategias) 9], ...
    'VariableTypes',["string","string",repmat("double",1,7)], ...
    'VariableNames',{'Caso','Estrategia','Rampa_s','SaltoMaxPWM','DesvioMax_C', ...
    'Tr10a90_s','Mp_pct','PwmMin','PwmMax'});

linha=0;
for c=1:numel(casos)
    for e=1:numel(estrategias)
        linha=linha+1;
        ens=simular(casos{c},rampas(e),rastrear(e),ctlNom,ctlCool,d.Ts);
        m=medir(ens,casos{c}.tDegrau);
        ensaios{c,e}=ens;
        metricas(linha,:)={casos{c}.nome,estrategias(e),rampas(e),m.saltoPWM, ...
            m.desvio,m.Tr,m.Mp,min(ens.u),max(ens.u)};
    end
end

resultado=struct('descricao',['Validacao da logica de transferencia; ' ...
    'nao modela a mudanca fisica intermediaria da planta.'], ...
    'Ts',d.Ts,'rampas_s',rampas,'casos',{casos}, ...
    'estrategias',estrategias,'ensaios',{ensaios},'metricas',metricas);
save(fullfile(saida,'escalonamento_bumpless_resultado.mat'),'resultado');
writetable(metricas,fullfile(saida,'metricas_escalonamento.csv'));
plotar(resultado,saida);
disp(metricas);fprintf('Resultados: %s\n',saida);
end

function c=normalizarNominal(x,d,u0,y0)
c=struct('nome',"nominal",'Kx',x.F(1:2),'Kq',x.F(3), ...
    'Ki',x.Ki,'Nb',x.Nb,'Aod',d.Aod,'Bod',d.Bod,'Cod',d.Cod, ...
    'Ld',d.Ld,'Fd',d.Fd,'nx',2,'u0',u0,'y0',y0);
end

function c=normalizarCooler(x)
c=struct('nome',"cooler",'Kx',x.Kx,'Kq',x.Kq,'Ki',x.Ki,'Nb',x.Nb, ...
    'Aod',x.Aod,'Bod',x.Bod,'Cod',x.Cod,'Ld',x.Ld,'Fd',x.Fd, ...
    'nx',1,'u0',x.u0,'y0',x.y0);
end

function A=ssdataA(c)
G=c2d(ss(tf(c.Kp,[c.Tp1 1])),c.Ts,'zoh');A=G.A;
end
function B=ssdataB(c)
G=c2d(ss(tf(c.Kp,[c.Tp1 1])),c.Ts,'zoh');B=G.B;
end
function C=ssdataC(c)
G=c2d(ss(tf(c.Kp,[c.Tp1 1])),c.Ts,'zoh');C=G.C;
end

function ens=simular(caso,rampa,rastrear,cn,cp,Ts)
t=(0:Ts:500)';n=numel(t);r=50+5*(t>=caso.tDegrau-Ts/2);
alpha=zeros(n,1);
for k=1:n
    if rampa==0
        s=double(t(k)>=100-Ts/2);
    else
        s=min(max((t(k)-100)/rampa,0),1);
    end
    alpha(k)=caso.a0+(caso.a1-caso.a0)*s;
end

P=caso.planta;x=zeros(size(P.A,1),1);qP=0;
sn=inicializar(cn,P.uEq,50);sp=inicializar(cp,P.uEq,50);
y=zeros(n,1);u=y;un=y;up=y;
for k=1:n
    y(k)=50+P.C*x;erro=r(k)-y(k);
    [un(k),inovN]=saidaControle(sn,cn,y(k),r(k));
    [up(k),inovP]=saidaControle(sp,cp,y(k),r(k));
    uLivre=(1-alpha(k))*un(k)+alpha(k)*up(k);
    u(k)=min(max(uLivre,0),65535);
    xNovo=P.A*x+P.B*qP;
    if k<n
        yNovo=50+P.C*xNovo;erroNovo=r(k)-yNovo;
        sn=avancar(sn,cn,inovN,u(k),un(k),erro,erroNovo,Ts,rastrear,alpha(k)<0.5);
        sp=avancar(sp,cp,inovP,u(k),up(k),erro,erroNovo,Ts,rastrear,alpha(k)>=0.5);
    end
    x=xNovo;qP=u(k)-P.uEq;
end
ens=struct('t',t,'r',r,'y',y,'u',u,'uNom',un,'uCool',up,'alpha',alpha);
end

function s=inicializar(c,uEq,y)
s.q=uEq-c.u0;
s.xh=(eye(size(c.Aod))-c.Aod+c.Ld*c.Cod)\ ...
    (c.Bod*s.q+c.Ld*(y-c.y0));
comp=c.Kq*s.xh(c.nx+1)+c.Fd(1,:)*s.xh(c.nx+1:c.nx+2);
s.xi=(uEq-c.u0-c.Nb*(y-c.y0)+c.Kx*s.xh(1:c.nx)+ ...
    c.Kq*s.q+comp)/c.Ki;
end

function [u,inov]=saidaControle(s,c,y,r)
inov=y-c.y0-c.Cod*s.xh;
comp=c.Kq*s.xh(c.nx+1)+c.Fd(1,:)*s.xh(c.nx+1:c.nx+2);
u=c.u0+c.Nb*(r-c.y0)-c.Kx*s.xh(1:c.nx)-c.Kq*s.q+c.Ki*s.xi-comp;
end

function s=avancar(s,c,inov,uAplicado,uProprio,e,eNovo,Ts,rastrear,ativo)
s.xh=c.Aod*s.xh+c.Bod*s.q+c.Ld*inov;
if rastrear
    correcao=(uAplicado-uProprio)/c.Ki;
elseif ativo
    correcao=(uAplicado-uProprio)/c.Ki;
else
    % Estrategia ingenua: controlador inativo fica congelado.
    return
end
s.xi=s.xi+Ts/2*(e+eNovo)+correcao;
s.q=uAplicado-c.u0;
end

function m=medir(e,tDegrau)
janela=e.t>=95 & e.t<=170;
m.saltoPWM=max(abs(diff(e.u(janela))));
m.desvio=max(abs(e.y(janela)-e.r(janela)));
j=e.t>=tDegrau;tt=e.t(j);yy=e.y(j);
t10=cruzamento(tt,yy,50.5);t90=cruzamento(tt,yy,54.5);
m.Tr=t90-t10;m.Mp=max(0,(max(yy)-55)/5*100);
end

function tc=cruzamento(t,y,nivel)
k=find(y>=nivel,1,'first');
if isempty(k)||k==1,tc=Inf;else,tc=interp1(y(k-1:k),t(k-1:k),nivel);end
end

function plotar(r,saida)
f=figure('Visible','off','Color','w','Position',[50 50 2200 1150]);
tiledlayout(numel(r.casos),numel(r.estrategias),'TileSpacing','compact','Padding','compact');
for c=1:numel(r.casos)
    for e=1:numel(r.estrategias)
        x=r.ensaios{c,e};nexttile;yyaxis left;
        plot(x.t,x.r,'k--');hold on;plot(x.t,x.y,'LineWidth',1.4);
        ylabel('Temperatura (°C)');yyaxis right;plot(x.t,x.alpha,'LineWidth',1.2);
        ylim([-0.05 1.05]);ylabel('alpha cooler');grid on;
        title(r.casos{c}.nome+" - "+r.estrategias(e));xlabel('Tempo (s)');
    end
end
exportgraphics(f,fullfile(saida,'temperaturas_escalonamento.png'),'Resolution',180);close(f);

f=figure('Visible','off','Color','w','Position',[100 50 1450 1000]);
tiledlayout(numel(r.casos),1,'TileSpacing','compact','Padding','compact');
for c=1:numel(r.casos)
    nexttile;hold on;grid on;
    for e=1:numel(r.estrategias)
        x=r.ensaios{c,e};plot(x.t,x.u,'LineWidth',1.2,'DisplayName',r.estrategias(e));
    end
    title(r.casos{c}.nome);ylabel('PWM16');legend('Location','best');
    if c==numel(r.casos),xlabel('Tempo (s)');end
end
exportgraphics(f,fullfile(saida,'comando_escalonamento.png'),'Resolution',180);close(f);
end
