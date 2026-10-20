# PRJ2 - Controle discreto com rejeição de perturbações

## Fluxo principal

Adicione `matlab/projeto` ao caminho do MATLAB e execute:

```matlab
ETAPA01_identificar_planta_nominal;
ETAPA02_projetar_controle_continuo(false);
ETAPA03_discretizar_modelos_zoh;
ETAPA04_projetar_controle_discreto(false);
ETAPA05_identificar_planta_com_cooler;
ETAPA06_projetar_controle_escalonado;
```

Os artefatos intermediários são gravados em `resultados/artefatos`. As demais
saídas ficam em subpastas temáticas de `resultados`.

## Material complementar reprodutível

Esta pasta é opcional para a avaliação. O projeto solicitado está integralmente
apresentado em `matlab/projeto`; os arquivos abaixo apenas permitem auditar os
ensaios e regenerar resultados do relatório.

`matlab/reproducao` contém:

- validação numérica e no Simulink;
- análise de sensibilidade paramétrica;
- coletores e análises dos ensaios nominal, ventilado e refinado;
- comparação multimodelo e transferência sem tranco;
- geração das figuras finais.

Esses scripts não são etapas adicionais do roteiro: são a trilha de validação
que sustenta as decisões apresentadas no relatório.

## Firmware

- `firmware/final`: implementação definitiva;
- `firmware/historico`: três marcos experimentais preservados para documentar
  a evolução do controlador.

Cada subpasta é um projeto PlatformIO independente e pode ser compilada sem
renomear arquivos.
