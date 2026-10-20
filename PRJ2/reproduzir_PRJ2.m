%% REPRODUZIR PRJ2
% Executa o fluxo principal usando somente caminhos relativos ao repositorio.

raiz = fileparts(mfilename('fullpath'));
projeto = fullfile(raiz, 'matlab', 'projeto');
caminhoAnterior = path;
restaurar = onCleanup(@() path(caminhoAnterior));
addpath(projeto);

ETAPA01_identificar_planta_nominal();
ETAPA02_projetar_controle_continuo(false);
ETAPA03_discretizar_modelos_zoh();
ETAPA04_projetar_controle_discreto(false);
ETAPA05_identificar_planta_com_cooler();
ETAPA06_projetar_controle_escalonado();
