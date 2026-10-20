function reproduzir_PRJ1
%REPRODUZIR_PRJ1 Executa o fluxo principal com caminhos relativos.

raiz = fileparts(mfilename('fullpath'));
addpath(fullfile(raiz, 'matlab', 'projeto'));

Etapa01_Identificacao_P2DZ_V1;
Etapa01_Identificacao_P2DZ_V2;
Etapa02_Projeto_PI_Continuo_LGR_P2DZ;
Etapa03_Simulacao_Continua_AW;
Etapa04_Discretizacao_ZOH;
Etapa05_Projeto_PI_Discreto_ZOH;
Etapa06_Simulacao_ZOH_AW;
end
