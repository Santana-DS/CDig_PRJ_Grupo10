function resultado = ETAPA06_analisar_sensibilidade()
%ETAPA06_ANALISAR_SENSIBILIDADE Avalia o modelo final sob incertezas.
%   Até ±10% em Kp e nos dois tempos de polo são cenários de estresse, não
%   intervalos de confiança da identificação. O observador fica nominal.
%   Nenhum .slx é modificado: todas as variações usam SimulationInput.

pasta = fileparts(mfilename('fullpath'));
raizProjeto = fileparts(fileparts(pasta));
apoio = fullfile(raizProjeto, 'resultados', 'artefatos');
s = load(fullfile(apoio, 'planta_p2dz.mat'), 'resultado');
h = s.resultado.parametros;
[estimativa, desvioPadrao] = getpvec(s.resultado.modelo);
s = load(fullfile(apoio, 'modelos_discretos.mat'), 'discreto');
Ts = s.discreto.Ts;
modelo = 'Prj2CDig_discreto_PRJ2';
load_system(fullfile(raizProjeto, 'simulink', [modelo '.slx']));
limpeza = onCleanup(@() close_system(modelo, 0));

escala = [0.9 0.95 0.99 1 1.01 1.05 1.1];
niveis = numel(escala);
Tr = nan(niveis, niveis);
Mp = nan(niveis, niveis);
erroRegime = nan(niveis, niveis);
for i = 1:niveis
    for j = 1:niveis
        planta = perturbarPlanta(h, Ts, escala(i), escala(j));
        saida = sim(degrau(modelo, planta));
        [Tr(i,j), Mp(i,j), erroRegime(i,j)] = medirDegrau(saida);
    end
end

% Frequência real de W difere da frequência fixa usada pelo observador.
% A janela de RMS exclui o transitório de ativação do seno em 1800 s.
fatoresFrequencia = [0.9 0.95 1 1.05 1.1];
rmsSeno = nan(numel(fatoresFrequencia), 1);
for i = 1:numel(fatoresFrequencia)
    saida = sim(senoide(modelo, 2*pi/64*fatoresFrequencia(i)));
    [t, y] = serie(saida, 'Y_log');
    janela = t >= 2200 & t < 2990;
    rmsSeno(i) = sqrt(mean((y(janela)-50).^2));
end

% A frequência correta não depende da amplitude, até que atuador ou
% modelo deixem de ser lineares. Aqui W é térmico equivalente, não PWM.
amplitudes = [10 20 30];
rmsAmplitude = nan(numel(amplitudes), 1);
pwmMaximo = nan(numel(amplitudes), 1);
for i = 1:numel(amplitudes)
    saida = sim(senoide(modelo, 2*pi/64, amplitudes(i)));
    [t, y] = serie(saida, 'Y_log');
    [~, u] = serie(saida, 'U_log');
    janela = t >= 2200 & t < 2990;
    rmsAmplitude(i) = sqrt(mean((y(janela)-50).^2));
    pwmMaximo(i) = max(u);
end

resultado = struct('modelo', modelo, 'Ts', Ts, ...
    'escalaKp', escala, 'escalaTp1Tp2', escala, ...
    'Tr10a90_s', Tr, 'Mp_pct', Mp, 'erroRegime_C', erroRegime, ...
    'fatorFrequencia', fatoresFrequencia, 'rmsSeno_C', rmsSeno, ...
    'amplitudeW_C', amplitudes, 'rmsAmplitude_C', rmsAmplitude, ...
    'pwmMaxAmplitude', pwmMaximo, ...
    'desvioPadraoFormal_pct', 100*desvioPadrao./abs(estimativa), ...
    'nota', ['Variacoes deterministicas, nao intervalos de confianca; ' ...
    'planta e frequencia variam, observador/controlador permanecem nominais.']);
destino = fullfile(raizProjeto, 'resultados', 'sensibilidade');
if ~isfolder(destino), mkdir(destino); end
save(fullfile(destino, 'sensibilidade_prj2.mat'), 'resultado');
plotar(resultado, fullfile(destino, 'sensibilidade_prj2.png'));

fprintf('%s: Tr nominal %.3f s; faixa %.3f..%.3f s; ', ...
    modelo, Tr(4,4), min(Tr, [], 'all'), max(Tr, [], 'all'));
fprintf('Mp max %.3f%%; RMS seno ±5%% %.3f/%.3f C\n', ...
    max(Mp, [], 'all'), rmsSeno(2), rmsSeno(4));
fprintf('RMS com amplitude W=10/20/30 C: %s C\n', ...
    mat2str(rmsAmplitude', 5));
end

function p = perturbarPlanta(h, Ts, fatorKp, fatorTempo)
% Reconstrói o P2DZ antes da ZOH; Tz e Ts continuam identificados.
T1 = h.Tp1*fatorTempo;
T2 = h.Tp2*fatorTempo;
Kp = h.Kp*fatorKp;
modal1 = (h.Tz-T1)/(T2-T1);
A = diag([-1/T1 -1/T2]);
B = Kp*[1; 1];
C = [modal1/T1 (1-modal1)/T2];
discreto = c2d(ss(A, B, C, 0), Ts, 'zoh');
p = struct('A', discreto.A, 'B', discreto.B, 'C', discreto.C);
end

function entrada = degrau(modelo, p)
entrada = Simulink.SimulationInput(modelo);
base = [modelo '/Cenario_1h/'];
entrada = entrada.setBlockParameter([base 'R_base'], 'Value', '50');
pulso = [base 'R_pulsos'];
entrada = entrada.setBlockParameter(pulso, 'Amplitude', '5');
entrada = entrada.setBlockParameter(pulso, 'Period', '1000');
entrada = entrada.setBlockParameter(pulso, 'PulseWidth', '800');
entrada = entrada.setBlockParameter(pulso, 'PhaseDelay', '140');
entrada = entrada.setBlockParameter([base 'W_DC'], 'FinalValue', '0');
planta = [modelo '/Processo_Termico/Planta_ZOH'];
entrada = entrada.setBlockParameter(planta, 'A', mat2str(p.A, 17));
entrada = entrada.setBlockParameter(planta, 'B', mat2str(p.B, 17));
entrada = entrada.setBlockParameter(planta, 'C', mat2str(p.C, 17));
entrada = entrada.setBlockParameter( ...
    [modelo '/Observadores/Observador_on_off'], 'sw', '1');
entrada = entrada.setModelParameter('StopTime', '1600');
end

function entrada = senoide(modelo, frequencia, amplitude)
if nargin < 3, amplitude = 20; end
entrada = Simulink.SimulationInput(modelo);
base = [modelo '/Cenario_1h/'];
entrada = entrada.setBlockParameter([base 'R_base'], 'Value', '50');
entrada = entrada.setBlockParameter([base 'R_pulsos'], 'Amplitude', '0');
entrada = entrada.setBlockParameter([base 'W_seno'], ...
    'Frequency', num2str(frequencia, 17));
entrada = entrada.setBlockParameter([base 'W_seno'], ...
    'Amplitude', num2str(amplitude, 17));
entrada = entrada.setBlockParameter( ...
    [modelo '/Observadores/Observador_on_off'], 'sw', '1');
entrada = entrada.setModelParameter('StopTime', '3600');
end

function [Tr, Mp, erro] = medirDegrau(saida)
[t, r] = serie(saida, 'R_log');
[~, y] = serie(saida, 'Y_log');
k = find(diff(r) > 0, 1, 'first') + 1;
assert(~isempty(k), 'Degrau ausente.');
t0 = t(k);
y0 = mean(y(t >= t0-50 & t < t0));
yf = mean(y(t >= 1500));
assert(yf > y0 && all(isfinite(y)), 'Resposta inválida.');
janela = t >= t0;
tt = t(janela); yy = y(janela);
Tr = cruzamento(tt, yy, y0+0.9*(yf-y0)) - ...
    cruzamento(tt, yy, y0+0.1*(yf-y0));
Mp = max(0, max(yy)-yf)/(yf-y0)*100;
erro = yf-55;
end

function instante = cruzamento(t, y, limiar)
k = find(y >= limiar, 1, 'first');
assert(~isempty(k) && k > 1, 'Limiar não cruzado.');
instante = interp1(y(k-1:k), t(k-1:k), limiar);
end

function [t, y] = serie(saida, nome)
sinal = saida.get(nome);
t = double(sinal.Time(:));
y = double(sinal.Data(:));
end

function plotar(dados, arquivo)
f = figure('Visible', 'off', 'Color', 'w', 'Position', [100 100 1100 430]);
tiledlayout(f, 1, 3, 'TileSpacing', 'compact');
limites = [min(dados.Tr10a90_s, [], 'all') ...
    max(dados.Tr10a90_s, [], 'all')];
nexttile; imagesc(dados.escalaTp1Tp2, dados.escalaKp, ...
    dados.Tr10a90_s); axis xy; clim(limites); colorbar;
xlabel('Fator dos tempos'); ylabel('Fator de Kp'); title('Tr final (s)');
nexttile; imagesc(dados.escalaTp1Tp2, dados.escalaKp, ...
    dados.Mp_pct); axis xy; colorbar;
xlabel('Fator dos tempos'); ylabel('Fator de Kp');
title('Sobressinal final (%)');
nexttile;
plot(100*(dados.fatorFrequencia-1), dados.rmsSeno_C, ...
    'o-', 'LineWidth', 1.4); grid on;
xlabel('Desvio da frequencia do cooler (%)');
ylabel('RMS de Y-R (graus C)'); title('Sensibilidade a frequencia');
exportgraphics(f, arquivo, 'Resolution', 170);
close(f);
end
