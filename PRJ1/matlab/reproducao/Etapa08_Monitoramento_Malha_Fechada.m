%% ETAPA 08 - MONITORAMENTO EM TEMPO REAL DA MALHA FECHADA
% Recebe a telemetria do PI P2DZ C(z)=1700(z-0.922)/(z-1), apresenta o
% ensaio ao vivo e grava o CSV ao receber END_DATA. U e U_s sao PWM de 16
% bits do aquecedor; W e PWM de 12 bits do cooler a 5 kHz.

clearvars; clc; close all;

%% Configuracao
portaSerial = "COM3";
baudRate = 115200;
pastaScript = fileparts(mfilename("fullpath"));
pastaProjeto = fileparts(fileparts(pastaScript));
pastaDados = fullfile(pastaProjeto, "dados");
idControlador = "p2dz_k1700_z922";
pwmMaximo = 65535;
modoEnsaio = "";
arquivoSaida = "";
arquivoParcial = "";
amostrasPorCheckpoint = 30;  % Copia recuperavel a cada ~86 s.
nomesColunas = ["t", "R", "Y", "U", "U_s", "W", "Ta", "e"];

if ~isfolder(pastaDados)
    mkdir(pastaDados);
end

%% Porta serial
serial = serialport(portaSerial, baudRate);
configureTerminator(serial, "LF");
serial.Timeout = 1;
pause(1);
flush(serial);
writeline(serial, "START");
disp("Comando START enviado; aguardando telemetria da ESP32.");

%% Janela de acompanhamento
figura = figure("Name", "Malha fechada", ...
    "NumberTitle", "off", "Color", "w", "Position", [80 80 1000 760]);
layout = tiledlayout(figura, 3, 1, "TileSpacing", "compact");

nexttile(layout, 1);
linhaR = animatedline("Color", [0 0.25 0.8], "LineWidth", 1.5, ...
    "DisplayName", "Referencia R");
linhaY = animatedline("Color", [0 0.5 0], "LineWidth", 1.5, ...
    "DisplayName", "Temperatura Y");
ylabel("Temperatura (C)"); grid on; legend("Location", "best");
title("Resposta em malha fechada");

nexttile(layout, 2);
linhaU = animatedline("Color", [0.85 0 0], "LineWidth", 1.0, ...
    "DisplayName", "U calculado");
linhaUs = animatedline("Color", [0.93 0.69 0.13], "LineWidth", 1.5, ...
    "DisplayName", "U aplicado");
yline(pwmMaximo, "k--", "Saturacao nominal", "HandleVisibility", "off");
ylabel("PWM do aquecedor (16 bits)"); grid on; legend("Location", "best");
title("Acao de controle e saturacao");

nexttile(layout, 3);
yyaxis left
linhaW = animatedline("Color", [0.49 0.18 0.56], "LineWidth", 1.2, ...
    "DisplayName", "W (cooler)");
ylabel("PWM do cooler (12 bits)");
yyaxis right
linhaTa = animatedline("Color", [0.1 0.6 0.6], "LineWidth", 1.0, ...
    "DisplayName", "Ta");
ylabel("Temperatura ambiente (C)");
xlabel("Tempo do ensaio (s)"); grid on;
title("Perturbacao e temperatura ambiente");

%% Recepcao da telemetria
dados = zeros(0, numel(nomesColunas));
coletando = false;
disp("Aguardando START_DATA da ESP32.");

while isvalid(figura)
    if serial.NumBytesAvailable == 0
        drawnow limitrate;
        pause(0.05);
        continue;
    end

    linha = strtrim(readline(serial));
    if startsWith(linha, "ALARME_CONFIG_PWM")
        clear serial
        error("Falha na configuracao PWM da ESP32: %s", linha);
    end
    % A ESP32 retorna ao estado seguro apos RESET. Reenvia START sem
    % reabrir a COM3; a coleta e os graficos sao reiniciados em START_DATA.
    if startsWith(linha, "READY:")
        coletando = false;
        writeline(serial, "START");
        disp("ESP32 reiniciada; comando START reenviado.");
        continue;
    end
    if linha == "START_DATA"
        coletando = true;
        dados = zeros(0, numel(nomesColunas));
        clearpoints(linhaR); clearpoints(linhaY);
        clearpoints(linhaU); clearpoints(linhaUs);
        clearpoints(linhaW); clearpoints(linhaTa);
        continue;
    end
    if startsWith(linha, "CONFIG,AW=")
        if contains(linha, "AW=1")
            modoEnsaio = "com_aw";
        else
            modoEnsaio = "sem_aw";
        end
        arquivoSaida = fullfile(pastaDados, ...
            "ensaio_" + idControlador + "_" + modoEnsaio + ".csv");
        arquivoParcial = fullfile(pastaDados, ...
            "ensaio_" + idControlador + "_" + modoEnsaio + ".partial.csv");
        figura.Name = "Malha fechada - " + idControlador + " - " + modoEnsaio;
        fprintf("Coleta configurada: %s\n", arquivoSaida);
        continue;
    end
    if linha == "END_DATA"
        break;
    end

    valores = str2double(split(linha, ","));
    if coletando && numel(valores) == numel(nomesColunas) && all(isfinite(valores))
        t = valores(1);
        addpoints(linhaR, t, valores(2));
        addpoints(linhaY, t, valores(3));
        addpoints(linhaU, t, valores(4));
        addpoints(linhaUs, t, valores(5));
        addpoints(linhaW, t, valores(6));
        addpoints(linhaTa, t, valores(7));
        dados(end + 1, :) = valores.'; %#ok<SAGROW>
        % Em um ensaio de uma hora, uma falha de interface nao deve descartar
        % os dados ja obtidos. O arquivo final so e escrito em END_DATA.
        if strlength(arquivoParcial) > 0 && ...
                mod(size(dados, 1), amostrasPorCheckpoint) == 0
            writetable(array2table(dados, "VariableNames", nomesColunas), arquivoParcial);
        end
        drawnow limitrate;
    end
end

% Ao encerrar por END_DATA ou pelo fechamento da figura, remove o comando
% de aquecimento antes de salvar os dados.
if isvalid(serial)
    writeline(serial, "STOP");
end

%% Persistencia
if isempty(dados)
    warning("Nenhuma linha de telemetria foi registrada.");
elseif strlength(arquivoSaida) == 0
    error("O firmware nao informou a configuracao anti-windup.");
else
    writetable(array2table(dados, "VariableNames", nomesColunas), arquivoSaida);
    if isfile(arquivoParcial)
        delete(arquivoParcial);
    end
    fprintf("CSV salvo: %s\n", arquivoSaida);
end
