function arquivos = gerar_modelo_expandido_prj2(arquivoModelo, destino)
%GERAR_MODELO_EXPANDIDO_PRJ2 Exporta uma vista expandida sem alterar o SLX.
%   Cria uma copia temporaria, expande os subsistemas do nivel superior e
%   exporta PNG e SVG. O modelo definitivo nunca e salvo nem modificado.

arguments
    arquivoModelo (1,1) string
    destino (1,1) string
end

assert(isfile(arquivoModelo), 'Modelo nao encontrado: %s', arquivoModelo);
if ~isfolder(destino), mkdir(destino); end

[~, nomeOriginal] = fileparts(arquivoModelo);
load_system(arquivoModelo);
limpaOriginal = onCleanup(@() fecharSeAberto(nomeOriginal));

pastaTemp = tempname;
mkdir(pastaTemp);
limpaTemp = onCleanup(@() removerTemporario(pastaTemp));
arquivoTemp = fullfile(pastaTemp, 'Prj2CDig_expandido_tmp.slx');
nomeTemp = 'Prj2CDig_expandido_tmp';
save_system(nomeOriginal, arquivoTemp);
close_system(nomeOriginal, 0);
clear limpaOriginal

load_system(arquivoTemp);
limpaModeloTemp = onCleanup(@() fecharSeAberto(nomeTemp));
subsistemas = find_system(nomeTemp, 'SearchDepth', 1, ...
    'BlockType', 'SubSystem');

% A lista e capturada antes da primeira expansao, pois cada operacao remove
% o bloco Subsystem correspondente do nivel superior.
for k = 1:numel(subsistemas)
    if getSimulinkBlockHandle(subsistemas{k}) ~= -1
        Simulink.BlockDiagram.expandSubsystem(subsistemas{k});
    end
end

set_param(nomeTemp, 'ScreenColor', 'white');
open_system(nomeTemp);
set_param(nomeTemp, 'ZoomFactor', 'FitSystem');
drawnow;

png = fullfile(destino, '13_modelo_expandido_PRJ2.png');
svg = fullfile(destino, '13_modelo_expandido_PRJ2.svg');
print(['-s' nomeTemp], '-dpng', '-r400', png);
print(['-s' nomeTemp], '-dsvg', '-painters', svg);

arquivos = struct('png', png, 'svg', svg, ...
    'subsistemasExpandidos', numel(subsistemas));
fprintf('Modelo expandido exportado | %d subsistemas | %s\n', ...
    numel(subsistemas), destino);
end

function fecharSeAberto(nome)
if bdIsLoaded(nome), close_system(nome, 0); end
end

function removerTemporario(pasta)
if isfolder(pasta), rmdir(pasta, 's'); end
end
