function reproduzir_PRJ1()
%REPRODUZIR_PRJ1 Executa o fluxo principal com caminhos relativos.
%   As etapas legadas sao scripts e iniciam com CLEAR. Cada uma e executada
%   explicitamente no workspace base para que a ultima parametrizacao fique
%   disponivel aos modelos Simulink depois que esta funcao terminar.

raiz = fileparts(mfilename('fullpath'));
projeto = fullfile(raiz, 'matlab', 'projeto');
etapas = {
    'Etapa01_Identificacao_P2DZ_V1.m'
    'Etapa01_Identificacao_P2DZ_V2.m'
    'Etapa02_Projeto_PI_Continuo_LGR_P2DZ.m'
    'Etapa03_Simulacao_Continua_AW.m'
    'Etapa04_Discretizacao_ZOH.m'
    'Etapa05_Projeto_PI_Discreto_ZOH.m'
    'Etapa06_Simulacao_ZOH_AW.m'
    };

for k = 1:numel(etapas)
    arquivo = fullfile(projeto, etapas{k});
    assert(isfile(arquivo), 'Etapa ausente: %s', arquivo);
    fprintf('[PRJ1 %d/%d] %s\n', k, numel(etapas), etapas{k});
    comando = sprintf("run('%s')", strrep(arquivo, "'", "''"));
    evalin('base', comando);
end

fprintf('PRJ1 reproduzido. Variaveis finais disponiveis no workspace base.\n');
end
