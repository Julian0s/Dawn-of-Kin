# R-03A D3.1 — Máquina de estados e barreira econômica das árvores

**Base homologada:** `7c53187eebe82ab2e1bc8c5add3661d7d769aed7`
**Branch candidata:** `feat/r-03a-community-work-main-scene`
**Estado:** incremento intermediário validado isoladamente e submetido à auditoria independente.

## Decisões aplicadas

- **D0-A03.** A derrubada torna-se irreversível ao ingressar em `FELLING`. O saldo integral só fica disponível para recolhimento em `FALLEN`.
- **D0-A04.** A decisão sobre balanço regional por recurso permanece vinculante. A validação desta entrega cobre deltas locais da fonte e das mochilas, peso, capacidade, lotes e recibos. A prova regional completa é um incremento posterior.
- **Parâmetros provisórios.** Corte individual em 2,5 s de simulação, rendimento combinado em 1,5× e queda em 0,50 s. Os três permanecem configuráveis.
- **Interrupção.** A retirada temporária congela o corte quando sai o último cortador. O cancelamento definitivo pré-queda zera o progresso se nenhum participante independente continuar. A queda confirmada prossegue sem trabalhador.
- **D1 e D2.** As ordens, a seleção, o cancelamento seletivo e o limite de uma atribuição por tarefa conservam os arquivos homologados. A exceção D2-T02 vale somente para o registro histórico.

## Contrato técnico

`ResourceSource` resolve `STANDING → CHOPPING → FELLING → FALLEN → DEPLETED`. A fonte mantém o relógio pausável, ligado apenas quando há participantes registrados ou queda em curso. A prioridade de física é 1 durante a atividade. Assim, as ordens com prioridade padrão atualizam sua elegibilidade antes de a fonte calcular o progresso.

`begin_tree_cut(unit, order, revision, authorization)` registra a participação quando a unidade tem vaga, está em alcance no mesmo mundo, possui a ordem corrente em execução e apresenta revisão correspondente. A ordem chama a interface depois da preparação. O identificador de autorização é um objeto opaco fornecido pelo responsável pela ordem ou tarefa. O mesmo objeto acompanha uma autorização vigente e um novo objeto identifica a reautorização. A fonte verifica a participação e guarda revogações locais enquanto o identificador existir. O quadro comunitário segue como autoridade da autorização no jogo.

`end_tree_cut(unit, order, revision, authorization)` retira a participação que coincide com a identidade registrada. Liberar a vaga também retira a participação correspondente. `cancel_tree_cut_authorization(authorization)` revoga o identificador, inclusive quando a ordem já saiu ou ainda não entrou. Identificadores obsoletos e registros duplicados não avançam o corte. Na saída da árvore, a fonte descarta participações e revoga as autorizações conhecidas. O corte pré-queda é encerrado e a queda já comprometida só volta a avançar se a mesma fonte retornar à árvore de cenas.

No tick, a fonte observa cancelamentos já aplicados, remove participantes inválidos e amostra o conjunto restante. Avança o relógio uma vez à taxa de 1× ou 1,5× e instala a transição antes da representação e dos sinais. A queda inicia com tempo próprio no tick seguinte. Chamadas reentrantes não avançam o relógio. A publicação de mudanças de fase respeita a ordem dos commits, inclusive quando um observador recolhe a última unidade ao receber `FALLEN`. O Tween é avançado pela fonte e pode ser recriado a partir do progresso. O estado econômico também avança sem nós visuais.

A condição central de nova extração mantém `is_available()` disponível para seleção e trabalho. Nas quatro APIs econômicas, madeira nova só é liberada em `FALLEN`. A transferência com proveniência reconhece primeiro o recibo compatível, revalida a condição ao comprometer um novo lote e preserva o replay após esgotamento. O caminho legado aceita `requested_amount = -1`, conforme o contrato anterior. O saldo e `DEPLETED` já estão consolidados quando os observadores recebem as notificações de carga e esgotamento. Pedra e alimento usam o mesmo comportamento econômico anterior.

## Validação executada

| Registro | Resultado | Código | Tempo do processo |
|---|---|---:|---:|
| `01_red` | Base sem D3.1. 1/11 passou, 10 falharam, 43 asserções. A madeira saiu antes da queda e a API ainda não existia. | 1 | 13,1 s |
| `02_green` | 11/11 testes passaram, 207 asserções no total. O executor rejeitou 84 erros de nós ausentes na fixture de `Unit`. | 1 | 12,8 s |
| `03_green` | O executor rejeitou a suíte por argumento de mensagem colocado no parâmetro de tolerância de `assert_near()`. A fixture foi corrigida. | 1 | 24,8 s |
| `04_green` | 11/11, 221 asserções, após correção da fixture. | 0 | 28,5 s |
| `05_validate` | 216 scripts, 0 erros e 0 avisos. Validação iniciada antes da última revisão de reentrância. | 0 | 1326,7 s |
| `06_green_final` | 12/12, 227 asserções, 0 erros e 0 avisos. A suíte completa inclui publicação ordenada durante depleção reentrante. | 0 | 29,8 s |
| `07_validate_final` | 216 scripts, importação e inicialização da MainScene em headless, 0 erros e 0 avisos. | 0 | 1354,7 s |
| `08_provenance_regression` | Filtro histórico da proveniência. 4/4, 70 asserções, 0 erros e 0 avisos. | 0 | 31,0 s |
| `09_pile_regression` | Filtro histórico de pilhas. 10/10 em 2 suítes, 153 asserções, 0 erros e 0 avisos. | 0 | 31,4 s |

A suíte focal verifica os cinco estados, as quatro APIs nas três fases pré-queda, cancelamentos em ambas as fronteiras, retomada após congelamento, ordens e autorizações obsoletas, duas ordens em ordens distintas de registro, pausa e Tween interrompido, ausência de nós visuais, teardown e callbacks reentrantes. Ela também verifica esgotamento, `-1` legado, carga e estoque preexistentes, peso misto, disputa pelo saldo final, rollback, revalidação no commit e replay após esgotamento.

Os registros externos preservam stdout, stderr, duração e código do PowerShell filho capturado imediatamente e propagado pelo processo de captura. O executor existente reúne a saída da Godot no stdout do PowerShell. Evidências em `C:\Projetos\Backups\Dawn_of_Kin_Archive_Local\evidencias\R-03A\D3\D3.1`.

## Pendências e classificação dos testes históricos

| Classe | Testes e dependências |
|---|---|
| Atualização do contrato substituído | `test_t2_natural_source_states` unitário e de integração, `test_m1_m10_independent_headless` e `test_t3_6_2_c3_5_gather_order_integration` contêm expectativas de queda iniciada por extração ou de carga durante a queda. A integração posterior deve trocar essas expectativas por saldo intacto até `FALLEN` e conservar assertivas de queda única, toco, picking, peso, viagens e conservação. |
| Adaptação futura de fixture | `test_t2_resource_sources`, `test_t2_worker_transfer`, `test_source_selection_model`, picking e velocidade T2, `test_t3_6_2_b3_2_source_transfer` e fixtures de reserva, entrega seletiva, identidade regional ou recuperação que semeiam madeira usando fonte em pé. Precondicionar árvores de teste ao estado caído quando o objetivo da fixture é semear carga ou esgotar uma fonte. Preservar os cenários de replay, reentrada, capacidades, isolamento e rollback. |
| Regressão de integração pendente | `GatherResourceOrder` e `GatherTransferSession` ainda percorrem o ciclo anterior. O fluxo de madeira da MainScene e dos sandboxes UX/RUX precisa chamar as interfaces novas. Testes de viagem, autorização e cancelamento D1/D2 que dependem dessa coleta precisam da integração ou da adaptação de fixture indicada. Os 13 aceites humanos anteriores seguem como evidências das respectivas revisões. |
| Asserções preservadas | Pedra, alimento, reservas, custódias, autoridade regional, recuperação, construção legada P-REC-1, D1/D2 e os demais casos históricos mantêm o texto original. O estado de compatibilidade integral será medido quando a integração de ordens estiver autorizada. |

A validação da MainScene nesta entrega é uma inicialização headless. A D3.1 entrega a fonte e seu contrato isolado. A coleta de árvore em pé pela MainScene fica bloqueada pela barreira até que o fluxo de ordem passe a demonstrar corte e queda. A regressão integral, a prova regional, os testes humanos e a homologação definitiva da D3 e de D0-A03/D0-A04 seguem como marcos distintos.

## Proteções

A referência de `develop` é `21c34ee645725a74f1fefac9db0309ec711ab5f2` e a de `main` é `25e0a20f1d6a2f10a9e059afe69759fbe263db4a`. Git e hashes de integridade constam nas evidências externas. O arquivo `project.godot` do checkout principal conserva o SHA-256 `AEEFDA2810DA5C4EDFA9BF5F2A47A5841F8597238C8DAB4C2E202FAF70307613`.
