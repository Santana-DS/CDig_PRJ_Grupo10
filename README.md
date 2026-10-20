# Controle Digital de Processo Térmico - Grupo 10

Repositório dos projetos PRJ1 e PRJ2 da disciplina ENE0167 - Controle
Digital. O material reúne projeto de controle, firmware da ESP32, modelos
Simulink, dados experimentais e resultados congelados.

## Organização

- `PRJ1/`: identificação P2DZ, projeto PI contínuo/discreto e anti-windup.
- `PRJ2/`: observadores, análise de sensibilidade, identificação sob
  convecção forçada e controle discreto escalonado.
- Em cada projeto, `matlab/projeto` contém o fluxo didático principal.
- `matlab/reproducao` contém coleta, verificações complementares e geração de
  figuras. Esses arquivos documentam a engenharia sem poluir o fluxo avaliado.
- `dados` e `resultados` preservam as coletas e saídas necessárias para
  reproduzir as análises sem repetir os ensaios físicos.

## Requisitos

- MATLAB R2024b ou posterior;
- Simulink;
- Control System Toolbox;
- System Identification Toolbox;
- Python 3.11+ com `pandas`, `matplotlib` e `pyserial` para os utilitários em
  Python;
- PlatformIO com plataforma `espressif32` para compilar os firmwares.

Todos os caminhos são resolvidos relativamente ao repositório. Após um
`git clone`, não é necessário editar nomes de usuário ou diretórios locais.
A porta serial está configurada como `COM3` nos coletores e pode ser alterada
no início do respectivo arquivo quando a enumeração do sistema for diferente.

Consulte os README de cada projeto para a ordem de execução.
