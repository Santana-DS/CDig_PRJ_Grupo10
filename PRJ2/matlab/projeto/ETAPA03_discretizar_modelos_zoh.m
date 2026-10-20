function discreto = ETAPA03_discretizar_modelos_zoh()
%DISCRETIZAR_MODELOS Prepara a planta e o observador para Ts = Td.
%   O aquecedor possui uma amostra de atraso. A perturbação térmica é
%   modelada na entrada da planta, após esse atraso. O controlador discreto
%   será sintonizado em etapa própria; os ganhos contínuos não são reutilizados.

pasta = fileparts(mfilename('fullpath'));
raizProjeto = fileparts(fileparts(pasta));
apoio = fullfile(raizProjeto, 'resultados', 'artefatos');
fontePlanta = fullfile(apoio, 'planta_p2dz.mat');
fonteProjeto = fullfile(apoio, 'projeto_continuo.mat');
assert(isfile(fontePlanta) && isfile(fonteProjeto), ...
    'Execute o pipeline inicial antes da discretização.');

sPlanta = load(fontePlanta, 'resultado');
sProjeto = load(fonteProjeto, 'projeto');
h = sPlanta.resultado.parametros;
continuo = sProjeto.projeto;
Ts = h.Td;
assert(Ts > 3 && Ts < 8, 'Td fora da faixa especificada no roteiro.');

% Retentor de ordem zero: u[k] permanece constante durante cada amostra.
planta = c2d(ss(continuo.A, continuo.B, continuo.C, 0), Ts, 'zoh');
Ad = planta.A; Bd = planta.B; Cd = planta.C;

% q[k] = u[k-1]. O comando calculado em k só alcança a planta em k+1.
% Estado aumentado [x1; x2; q], sem aproximação de Padé para o atraso.
Aat = [Ad, Bd; zeros(1, 3)];
Bat = [0; 0; 1];
Cat = [Cd, 0];
Gat = ss(Aat, Bat, Cat, 0, Ts);
assert(rank(ctrb(Aat, Bat)) == 3, ...
    'Planta com atraso não controlável.');

% Oscilador amostrado exatamente: seus polos devem ficar no círculo unitário.
Fd = expm(continuo.As * Ts);
assert(max(abs(abs(eig(Fd)) - 1)) < 1e-10, ...
    'A discretização alterou a frequência do oscilador.');

% Observador preditor para x e para uma perturbação senoidal equivalente
% à entrada do aquecedor. O estado q (PWM já aplicado) é conhecido.
Aod = [Ad, Bd * continuo.Cs; zeros(2, 2), Fd];
Bod = [Bd; 0; 0];
Cod = [Cd, 0, 0];
assert(rank(obsv(Aod, Cod)) == 4, ...
    'Observador senoidal discreto não observável.');
polosObservador = exp(continuo.polosObservador * Ts);
Ld = place(Aod', Cod', polosObservador)';
assert(max(abs(sort(eig(Aod - Ld*Cod)) - ...
    sort(polosObservador(:)))) < 1e-7, ...
    'Polos do observador discreto diferentes dos especificados.');

% O canal integral por Tustin usa a média dos erros atual e anterior.
% O termo de back-calculation será aplicado ao PWM efetivamente saturado.
integrador = struct('metodo', 'Tustin', 'pesoErro', Ts/2, ...
    'tempoRastreamentoInicial', Ts);
atuador = struct('minPWM16', 0, 'maxPWM16', 65535);

discreto = struct( ...
    'Ts', Ts, 'Td', h.Td, 'Ad', Ad, 'Bd', Bd, 'Cd', Cd, ...
    'Aat', Aat, 'Bat', Bat, 'Cat', Cat, 'Gat', Gat, ...
    'Fd', Fd, 'Aod', Aod, 'Bod', Bod, 'Cod', Cod, ...
    'Ld', Ld, 'polosObservador', polosObservador, ...
    'integrador', integrador, 'atuador', atuador, ...
    'modeloOrigem', fontePlanta, 'projetoOrigem', fonteProjeto);

destino = fullfile(apoio, 'modelos_discretos.mat');
save(destino, 'discreto');
fprintf('Etapa 3 concluída | Ts %.3f s | atraso 1 amostra | polos %s\n', ...
    Ts, mat2str(polosObservador, 4));
end
