function projeto = ETAPA06_projetar_controle_escalonado
%ETAPA06_PROJETAR_CONTROLE_ESCALONADO Projeta o controlador para W=3211.
% Replica a filosofia do controlador oficial: ZOH, atraso explicito de uma
% amostra, integrador Tustin, observador de perturbacao e anti-windup.
% Nao altera o firmware nem o controlador nominal.

pasta = fileparts(mfilename('fullpath'));
raizProjeto = fileparts(fileparts(pasta));
apoio = fullfile(raizProjeto, 'resultados', 'artefatos');
saida = fullfile(raizProjeto,'resultados','controlador_cooler');
if ~isfolder(saida), mkdir(saida); end

S=load(fullfile(raizProjeto,'resultados','identificacao_cooler', ...
    'identificacao_cooler_resultado.mat'),'resultado'); id=S.resultado;
S=load(fullfile(apoio,'modelos_discretos.mat'),'discreto'); d=S.discreto;
S=load(fullfile(apoio,'planta_p2dz.mat'),'resultado'); nom=S.resultado;
p=get(id.modeloSelecionado); Ts=d.Ts;
assert(id.nomeSelecionado=="P1D" && abs(p.Td-Ts)<1e-6, ...
    'Identificacao P1D esperada.');

Gd=c2d(ss(tf(p.Kp,[p.Tp1 1])),Ts,'zoh');
A=Gd.A; B=Gd.B; C=Gd.C;

% Estados aumentados [x; q; xi], com q igual ao PWM anterior.
Ai=[A B 0; 0 0 0; -Ts/2*C*(1+A) -Ts/2*C*B 1];
Bi=[0;1;0]; Er=[0;0;Ts]; Ci=[C 0 0];
assert(rank(ctrb(Ai,Bi))==3,'Sistema P1D aumentado nao controlavel.');

alvoInterno=19;
pr=-log(9)/alvoInterno;
zResposta=exp(pr*Ts); zCancelado=exp(pr*Ts/3); zAtraso=exp(4*pr*Ts);
polos=[zResposta zCancelado zAtraso];
F=place(Ai,Bi,polos); Ki=-F(3);
Acl=Ai-Bi*F;
[V,D]=eig(Acl'); [~,k]=min(abs(diag(D)-zCancelado)); l=V(:,k);
Nb=real(-(l'*Er)/(l'*Bi));
assert(Ki>0 && Nb>0 && all(abs(eig(Acl))<1),'Controlador P1D invalido.');

% Observador do estado termico e do oscilador senoidal equivalente.
Aod=[A B*[1 0]; zeros(2,1) d.Fd];
Bod=[B;0;0]; Cod=[C 0 0];
polosObs=sort(d.polosObservador(:));
polosObs=polosObs(1:3);  % tres polos mais rapidos do projeto aprovado
Ld=place(Aod',Cod',polosObs)';
assert(max(abs(sort(eig(Aod-Ld*Cod))-polosObs))<1e-7, ...
    'Polos do observador P1D incorretos.');

Tref=ss(Acl,Bi*Nb+Er,Ci,0,Ts);
[y,t]=step(Tref,0:Ts:300); y=squeeze(y);
Tr=cruzamento(t,y,0.9)-cruzamento(t,y,0.1);
Mp=max(0,(max(y)-1)*100);

controle=struct('Ai',Ai,'Bi',Bi,'Er',Er,'Ci',Ci,'F',F, ...
    'Kx',F(1),'Kq',F(2),'Ki',Ki,'Nb',Nb,'polos',polos, ...
    'Aod',Aod,'Bod',Bod,'Cod',Cod,'Ld',Ld, ...
    'polosObservador',polosObs,'Fd',d.Fd,'Ts',Ts, ...
    'u0',id.u0,'y0',50,'Kp',p.Kp,'Tp1',p.Tp1,'Td',p.Td);

ensaio=simular(controle,A,B,C,controle.u0);
metrica=medir(ensaio);
uEqNom=nom.u0+(50-nom.y0)/nom.parametros.Kp;
ensaioCruzado=simular(controle,d.Ad,d.Bd,d.Cd,uEqNom);
metricaCruzada=medir(ensaioCruzado);
projeto=struct('modeloIdentificado',id.modeloSelecionado, ...
    'controle',controle,'Tref',Tref,'TrLinear_s',Tr,'MpLinear_pct',Mp, ...
    'ensaioCasado',ensaio,'metricaCasada',metrica, ...
    'ensaioNoP2DZNominal',ensaioCruzado,'metricaNoP2DZNominal',metricaCruzada, ...
    'status','Exploratorio; nao aplicar sem validar a comutacao bumpless.');
save(fullfile(saida,'controlador_p1d_cooler.mat'),'projeto');
plotar(ensaio,ensaioCruzado,saida);

fprintf(['Etapa 6 concluída | Tr %.3f s | Mp %.3f%% | ' ...
    'Ki %.6g | Nb %.6g\n'], metrica.Tr, metrica.Mp, Ki, Nb);
end

function e=simular(c,A,B,C,uEq)
Ts=c.Ts;t=(0:Ts:500)';n=numel(t);r=50+5*(t>=100-Ts/2);
x=zeros(size(A,1),1);qPlanta=0;q=uEq-c.u0;
xh=(eye(3)-c.Aod+c.Ld*c.Cod)\(c.Bod*q+c.Ld*(50-c.y0));
comp=c.Kq*xh(2)+c.Fd(1,:)*xh(2:3);
xi=(uEq-c.u0-c.Nb*(50-c.y0)+c.Kx*xh(1)+c.Kq*q+comp)/c.Ki;
y=zeros(n,1);u=y;uLivre=y;
for k=1:n
    y(k)=50+C*x; erro=r(k)-y(k);
    inov=y(k)-c.y0-c.Cod*xh;
    comp=c.Kq*xh(2)+c.Fd(1,:)*xh(2:3);
    uLivre(k)=c.u0+c.Nb*(r(k)-c.y0)-c.Kx*xh(1)-c.Kq*q+ ...
        c.Ki*xi-comp;
    u(k)=min(max(uLivre(k),0),65535);
    xNovo=A*x+B*qPlanta;
    qNovo=u(k)-c.u0;
    xhNovo=c.Aod*xh+c.Bod*q+c.Ld*inov;
    if k<n
        yNovo=50+C*xNovo;
        xi=xi+Ts/2*(erro+r(k)-yNovo)+(u(k)-uLivre(k))/c.Ki;
    end
    x=xNovo;q=qNovo;qPlanta=u(k)-uEq;xh=xhNovo;
end
e=struct('t',t,'r',r,'y',y,'u',u,'uLivre',uLivre);
end

function m=medir(e)
j=e.t>=100;tt=e.t(j);yy=e.y(j);
m.Tr=cruzamento(tt,yy,50.5)-100;
t90=cruzamento(tt,yy,54.5);t10=cruzamento(tt,yy,50.5);
m.Tr=t90-t10;m.Mp=max(0,(max(yy)-55)/5*100);
m.erroFinal=55-mean(yy(end-9:end));
m.PwmMin=min(e.u);m.PwmMax=max(e.u);
end

function tc=cruzamento(t,y,nivel)
k=find(y>=nivel,1,'first');assert(~isempty(k)&&k>1,'Cruzamento ausente.');
tc=interp1(y(k-1:k),t(k-1:k),nivel);
end

function plotar(e,eCross,saida)
f=figure('Visible','off','Color','w','Position',[100 100 1250 750]);
tiledlayout(2,1,'TileSpacing','compact','Padding','compact');
nexttile;plot(e.t,e.r,'--','LineWidth',1.3);hold on;
plot(e.t,e.y,'LineWidth',1.5);plot(eCross.t,eCross.y,'LineWidth',1.3);
grid on;ylabel('Temperatura (°C)');legend('R','Y');
legend('R','P1D com cooler','P2DZ sem cooler','Location','best');
title('Controlador P1D aplicado aos dois modelos');
nexttile;plot(e.t,e.u,'LineWidth',1.3);hold on;plot(eCross.t,eCross.u,'LineWidth',1.3);
grid on;ylabel('PWM16');xlabel('Tempo (s)');legend('P1D com cooler','P2DZ sem cooler');
title('Comando do aquecedor');
exportgraphics(f,fullfile(saida,'resposta_controlador_p1d.png'),'Resolution',180);
close(f);
end
