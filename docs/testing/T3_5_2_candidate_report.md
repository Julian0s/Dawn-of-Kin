# T3.5.2 — Relatório da candidata

Base: `56d8e97fc0bac0bd999fb4734b6eb12bdcd74ba9`; branch `feat/t3-5-2-building-inspector`. A candidata aguarda auditoria independente e testes manuais do proprietário.

## Implementação e contratos

`BuildingInspectorPanel` usa o sinal `construction_site_picked` e os sinais e getters de `ConstructionSite` e `SettlementInventory`. Exibe nome, estado, progresso, recursos por categoria, trabalhadores e limite de construtores. Mudanças são coalescidas por um temporizador de 0,2 s independente da escala de tempo; não há consulta econômica por quadro. Ao selecionar unidades, terreno vazio ou remover/concluir o canteiro, a inspeção é encerrada. O painel provisório continua disponível na classe para testes isolados, mas é ocultado na composição normal. A asserção da regressão T3.3 foi adaptada para verificar que a criação não abre um inspetor duplicado; uma verificação separada continua exercitando o painel provisório.

A ação de complemento aparece quando há déficit e abre confirmação explícita. O plano usa `get_complementable_missing_amounts()` e `can_authorize_manual_complement()`, informa saldo livre, proposta e saldo posterior. Só a confirmação cria `ManualComplementIntent.create_from_player_ui()` e chama `authorize_manual_complement(..., false)` após nova consulta. Há guarda de reentrada e vínculo ao canteiro inspecionado. Não há opção parcial nesta candidata. A reserva continua nas pilhas e o transporte permanece físico. Pedra bruta não deteriora temporalmente conforme DEC-11A.

O GDD e AGENTS registram estados históricos anteriores às integrações T3.4.5/T3.5.1; o [aceite T3.5.1](T3_5_1_closeout_ACCEPTANCE.md) e a autorização específica estabelecem o estado posterior. O GDD e a arquitetura não foram alterados. Cancelamento/reembolso D3, armazenamento protegido e persistência seguem fora do escopo.

## Evidências

Suíte específica `test_t3_5_2_building_inspector`: 3 testes, 64 asserções, sem falhas ou erros de suíte. A perda de reserva de madeira ocorre por `step_decay()` real; o teste verifica bloqueio sem saldo, autorização por botão, preservação de reserva de outra obra, ausência de alteração imediata de buffer/consumo/progresso, transporte físico e conclusão. Também cobre seleção, layout em dois SubViewports, F8, cliques, troca e remoção de canteiro durante confirmação, inclusive antes do próximo quadro, e painel provisório isolado. A lógica de intenção de uso único e as transações parciais do backend continuam cobertas pelas regressões T3.4. Não é oferecida ação parcial no HUD.

Regressões isoladas: T3.3 logística 11/11 testes e 225 asserções; T3.5.1 3/3 testes e 35 asserções. Uma tentativa anterior da regressão T3.3 falhou quando o painel abria automaticamente e interceptava a prévia; a abertura foi limitada à seleção do canteiro e a regressão passou em seguida.

`tools/validate.ps1`: 122 scripts validados e inicialização headless aprovada, zero erros e avisos. `tools/run_tests.ps1 -Segmented`: **41 suítes, 284/284 testes, 12.922 asserções**, zero falhas ou erros de suíte; `Discovered=41`, `ExecutedUnique=41`, `Duplicates=0`, `Missing=0`.

Inspeção gráfica da candidata final: pendente. Foi iniciada uma sessão gráfica, porém a tela estava ocupada por outra atividade e o painel não foi observado; a sessão também antecede os últimos ajustes e não valida o código final. Nenhuma aprovação visual ou manual é alegada. Ver [protocolo manual](T3_5_2_manual_test_protocol.md).

Código: `e32f0d51e801578c89cbbfe531f55d386ae9a472` (`src/ui/building_inspector_panel.gd`, UID, integração em `src/main/main.gd` e isolamento em `src/buildings/placement_test_overlay.gd`). Testes: `eae2b3ef8f8cad30c6557c8b1518b07db17d739d` (nova suíte, UID e adaptação da regressão T3.3). O commit documental é identificável pelo histórico Git; este documento não tenta registrar o próprio hash.
