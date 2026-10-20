# Controle Digital de Processo Térmico - Grupo 10

Repositório dos projetos PRJ1 e PRJ2 da disciplina ENE0167 - Controle
Digital. O material reúne projeto de controle, firmware da ESP32, modelos
Simulink, dados experimentais e resultados congelados.

## Organização

- `PRJ1/`: identificação P2DZ, projeto PI contínuo/discreto e anti-windup.
- `PRJ2/`: observadores, análise de sensibilidade, identificação sob
  convecção forçada e controle discreto escalonado.
- Em cada projeto, `matlab/projeto` contém a entrega principal e deve ser o
  ponto de partida da avaliação.
- `matlab/reproducao` é um anexo técnico opcional, com coleta, verificações e
  geração de figuras. Ele não acrescenta etapas ao roteiro nem substitui os
  fundamentos apresentados em `matlab/projeto`.
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

## Relatórios

- [Relatório do PRJ1](PRJ1/relatorio/CDig_Relatorio_Grupo10_PRJ1.pdf?raw=1)
- [Relatório do PRJ2](PRJ2/relatorio/CDig_Relatorio_Grupo10_PRJ2.pdf?raw=1)

Os links usam a visualização bruta para contornar eventuais falhas do
pré-visualizador de PDF do GitHub.
