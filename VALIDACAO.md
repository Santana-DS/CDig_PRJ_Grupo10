# Validação do repositório

Verificações realizadas antes da publicação:

- ausência de caminhos absolutos nos arquivos distribuídos;
- execução das identificações e da discretização do PRJ1 a partir da cópia
  isolada do repositório;
- execução das etapas 1 a 4 do PRJ2 a partir da raiz do repositório;
- conclusão numérica da identificação nominal com FIT de 93,78%;
- localização correta dos CSVs, artefatos e modelos Simulink;
- compilação dos firmwares finais do PRJ1 e PRJ2;
- compilação dos três firmwares históricos preservados do PRJ2;
- auditoria de caches e arquivos temporários pelo `.gitignore`.

Os fluxos que abrem `sisotool`, Simulink ou figuras devem ser executados em
uma sessão MATLAB Desktop com o serviço gráfico disponível. Os resultados
congelados permanecem em `resultados/figuras` para consulta sem nova
execução.
