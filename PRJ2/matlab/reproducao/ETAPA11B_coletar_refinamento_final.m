function arquivo = ETAPA11B_coletar_refinamento_final
%COLETAR_REFINAMENTO_PRJ2 Compara fase e ponderacao de referencia.

porta = "COM3";
baud = 115200;
nomes = ["t","R","Y","Ta","W","modo","beta","U_nom","U_cool", ...
    "U_livre","Us","e_sin_nom","e_sin_cool","inov_nom","inov_cool"];
pastaScript = fileparts(mfilename('fullpath'));
raizProjeto = fileparts(fileparts(pastaScript));
pasta = fullfile(raizProjeto, 'dados');
if ~isfolder(pasta), mkdir(pasta); end
instante = string(datetime('now','Format','yyyyMMdd_HHmmss'));
arquivo = fullfile(pasta,"ensaio_controle_refinado_"+instante+".csv");
logSerial = fullfile(pasta,"log_controle_refinado_"+instante+".txt");

fid = fopen(arquivo,'w');
assert(fid>0,'Nao foi possivel criar o arquivo de coleta.');
fprintf(fid,'segmento,%s\n',strjoin(nomes,','));
fclose(fid);
fidLog = fopen(logSerial,'w');
assert(fidLog>0,'Nao foi possivel criar o log serial.');
fclose(fidLog);

[fig,h,ax] = criarGraficos;
sp = serialport(porta,baud,'Timeout',2);
configureTerminator(sp,"LF");
limpeza = onCleanup(@() finalizar(sp));
pause(1);
% Reinicia o cronometro somente depois que a porta ja esta pronta.
writeline(sp,"STOP"); pause(0.2); flush(sp); writeline(sp,"START");

% 1 h / 5,715 s resulta em cerca de 630 amostras; reserva com margem.
dados = nan(800,numel(nomes));
n = 0; segmento = 1; graficoAtivo = true;
tentativaTempoZero = 0;
heartbeat = tic; repeticaoStart = tic;
fprintf('Coletor final ativo em %s. Arquivo: %s\n',porta,arquivo);

while isgraphics(fig)
    if toc(heartbeat)>=4
        writeline(sp,"HEARTBEAT"); heartbeat=tic;
    end
    if n==0 && toc(repeticaoStart)>=2
        writeline(sp,"START"); repeticaoStart=tic;
    end
    if sp.NumBytesAvailable==0
        pause(0.03); drawnow limitrate; continue
    end

    linha = strtrim(string(readline(sp)));
    anexarTexto(logSerial,linha);

    if linha=="READY: PRJ2_CONTROLE_ESCALONADO"
        if n>0, segmento=segmento+1; end
        n=0; dados(:)=NaN; limparGraficos(h,ax);
        tentativaTempoZero=0;
        writeline(sp,"START"); repeticaoStart=tic;
        fprintf('RESET detectado; iniciando segmento %d.\n',segmento);
        continue
    end
    if linha=="START_DATA" || startsWith(linha,"CONFIG,") || ...
            startsWith(linha,"t,R,Y,Ta,")
        fprintf('%s\n',linha); continue
    end
    if linha=="END_DATA", break; end
    if any(startsWith(linha,["FIM_","ALARME_","PARADA_"]))
        fprintf('%s\n',linha); continue
    end

    v = str2double(split(linha,','));
    if numel(v)~=numel(nomes) || any(~isfinite(v))
        fprintf('[serial] %s\n',linha); continue
    end

    % Se a amostra t=0 foi perdida durante a abertura da USB, reinicia uma
    % unica vez sem deslocar ou fabricar tempos no arquivo.
    if n==0 && v(1)>1 && tentativaTempoZero==0
        tentativaTempoZero=1;
        writeline(sp,"STOP"); pause(0.2); flush(sp); writeline(sp,"START");
        repeticaoStart=tic;
        fprintf('Sincronizando a primeira amostra com t = 0.\n');
        continue
    end

    n=n+1; dados(n,:)=v(:).';
    anexarAmostra(arquivo,segmento,v);  % Disco antes da interface grafica.

    if graficoAtivo
        try
            atualizarGraficos(h,ax,dados(1:n,:));
        catch erroGrafico
            graficoAtivo=false;
            anexarTexto(logSerial,"ERRO_GRAFICO: "+string(getReport(erroGrafico)));
            warning('PRJ2:GraficoDesativado','%s',erroGrafico.message);
        end
    end
    if n==1 || mod(n,10)==0
        fprintf('segmento=%d n=%d t=%.1f s Y=%.2f C Us=%.0f W=%.0f\n', ...
            segmento,n,v(1),v(3),v(11),v(5));
    end
end
fprintf('Coleta encerrada. Arquivo: %s\n',arquivo);
end

function [fig,h,ax] = criarGraficos
fig=figure('Name','PRJ2 - refinamento comparativo','NumberTitle','off');
t=tiledlayout(fig,4,1,'TileSpacing','compact','Padding','compact');
title(t,'Refinamento do controle discreto escalonado');

ax(1)=nexttile(t); hold(ax(1),'on'); grid(ax(1),'on');
h.R=plot(ax(1),NaN,NaN,'Color',[0.929 0.694 0.125],'DisplayName','R');
h.Y=plot(ax(1),NaN,NaN,'Color',[0 0.447 0.741],'LineWidth',1.5,'DisplayName','Y');
ylabel(ax(1),'Temperatura (C)'); title(ax(1),'Referencia e saida'); legend(ax(1));

ax(2)=nexttile(t); grid(ax(2),'on');
h.Ta=plot(ax(2),NaN,NaN,'Color',[0.466 0.674 0.188],'LineWidth',1.3,'DisplayName','Ta');
ylabel(ax(2),'Ta (C)'); title(ax(2),'Temperatura ambiente'); legend(ax(2));

ax(3)=nexttile(t); hold(ax(3),'on'); grid(ax(3),'on');
h.W=plot(ax(3),NaN,NaN,'Color',[0.850 0.325 0.098],'LineWidth',1.3,'DisplayName','W');
h.M=plot(ax(3),NaN,NaN,'k--','DisplayName','modo x 3211');
ylabel(ax(3),'PWM12'); title(ax(3),'Cooler e modo ativo'); legend(ax(3));

ax(4)=nexttile(t); hold(ax(4),'on'); grid(ax(4),'on');
h.Us=plot(ax(4),NaN,NaN,'Color',[0 0.447 0.741],'LineWidth',1.5,'DisplayName','Us');
h.Un=plot(ax(4),NaN,NaN,'Color',[0.494 0.184 0.556],'DisplayName','U nominal');
h.Uc=plot(ax(4),NaN,NaN,'Color',[0.850 0.325 0.098],'DisplayName','U cooler');
h.Es=plot(ax(4),NaN,NaN,'k:','DisplayName','e sin ativo');
ylabel(ax(4),'PWM16'); xlabel(ax(4),'Tempo (s)');
title(ax(4),'Controle e perturbacao estimada'); legend(ax(4));

linkaxes(ax,'x'); xlim(ax(1),[0 60]);
end

function atualizarGraficos(h,ax,d)
t=d(:,1); modo=d(:,6);
set(h.R,'XData',t,'YData',d(:,2)); set(h.Y,'XData',t,'YData',d(:,3));
set(h.Ta,'XData',t,'YData',d(:,4)); set(h.W,'XData',t,'YData',d(:,5));
set(h.M,'XData',t,'YData',3211*modo);
set(h.Un,'XData',t,'YData',d(:,8)); set(h.Uc,'XData',t,'YData',d(:,9));
set(h.Us,'XData',t,'YData',d(:,11));
eAtivo=d(:,12); eAtivo(modo==1)=d(modo==1,13);
set(h.Es,'XData',t,'YData',eAtivo);
xlim(ax(1),[0 max(60,60*ceil((t(end)+1)/60))]);
for k=1:numel(ax), ylim(ax(k),'auto'); end
drawnow limitrate;
end

function limparGraficos(h,ax)
campos=fieldnames(h);
for k=1:numel(campos), set(h.(campos{k}),'XData',NaN,'YData',NaN); end
xlim(ax(1),[0 60]); drawnow;
end

function anexarAmostra(arquivo,segmento,v)
fid=fopen(arquivo,'a');
assert(fid>0,'Nao foi possivel atualizar o CSV.');
fprintf(fid,'%d,',segmento);
fprintf(fid,'%.10g',v(1));
fprintf(fid,',%.10g',v(2:end));
fprintf(fid,'\n');
fclose(fid);
end

function anexarTexto(arquivo,texto)
fid=fopen(arquivo,'a');
assert(fid>0,'Nao foi possivel atualizar o log serial.');
fprintf(fid,'%s\n',texto);
fclose(fid);
end

function finalizar(sp)
try
    writeline(sp,"STOP");
catch
end
end
