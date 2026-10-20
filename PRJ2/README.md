# PRJ2 - Controle discreto com rejeição de perturbações

**[Relatório](https://raw.githubusercontent.com/Santana-DS/CDig_PRJ_Grupo10/main/PRJ2/relatorio/CDig_Relatorio_Grupo10_PRJ2.pdf) · [Vídeo - inserir URL](https://www.youtube.com/)**

## Resultado em destaque

O ensaio final de uma hora mostra a referência e a saída, a temperatura
ambiente, o PWM do cooler, o comando aplicado e a contribuição do observador
senoidal. O controle escalonado suavizou a resposta sob ventilação e preservou
o seguimento nos regimes nominal e perturbado.

![Ensaio final com perturbações constante e senoidal](resultados/figuras/11_ensaio_final_1h.png)

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
