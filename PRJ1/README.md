# PRJ1 - Identificação e controle PI discreto

## Fluxo principal

Execute em `matlab/projeto`, nesta ordem:

1. `Etapa01_Identificacao_P2DZ_V1.m` e
   `Etapa01_Identificacao_P2DZ_V2.m`;
2. `Etapa02_Projeto_PI_Continuo_LGR_P2DZ.m`;
3. `Etapa03_Simulacao_Continua_AW.m`;
4. `Etapa04_Discretizacao_ZOH.m`;
5. `Etapa05_Projeto_PI_Discreto_ZOH.m`;
6. `Etapa06_Simulacao_ZOH_AW.m`.

Os arquivos intermediários são gerados em `resultados/artefatos`. Os scripts
usam os CSVs em `dados` e os modelos em `simulink`, sempre por caminhos
relativos.

O atalho `reproduzir_PRJ1.m` executa a sequência completa. Como as etapas de
projeto abrem o `sisotool` e os modelos Simulink, use-o no MATLAB Desktop.

## Reprodução experimental

- `matlab/reproducao/Etapa00_Coletor_PRBS.py`: coleta da identificação;
- `Etapa08_Monitoramento_Malha_Fechada.m`: acompanhamento em tempo real;
- `Etapa09_Analise_Malha_Fechada_AW.m`: métricas e figuras com/sem
  anti-windup.

Os projetos PlatformIO estão em `firmware/identificacao_prbs` e
`firmware/controle_final`. Compile cada pasta diretamente no PlatformIO.
