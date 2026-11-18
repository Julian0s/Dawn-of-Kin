# T3.6.2-B1 — Snapshot transacional do ledger

Base da candidata `2a9e1606618a1d5d8ab5d5b2b877bbf00d195833`, branch `feat/t3-6-2-provenance-transactions`. A alteração local preexistente na suíte foi inspecionada, novamente executada (3/3 testes, 49 asserções) e preservada no commit `26e0209596807108c002c9aa5c6082e38c6bece5`.

## Contrato

`snapshot()` continua retornando somente lotes. `snapshot_transaction_state()` retorna cópias profundas de lotes, operações e IDs usados. `restore_transaction_state(state)` valida formato e reexecuta as operações na ordem registrada em instância temporária; exige igualdade das três estruturas reconstruídas e somente então substitui o estado, com cópias independentes. Estado inválido é recusado integralmente. A reconstrução exige tempo e memória proporcionais ao histórico (e o custo dos métodos usados); não é otimizada para uso por quadro.

A restauração serve exclusivamente a trabalho interno não comprometido: não desfaz transações já observadas por outros sistemas e não constitui rollback de pilhas, mochila ou canteiro. Nenhum fluxo de gameplay foi conectado.

Os testes verificam lotes múltiplos, histórico e IDs consumidos, retorno ao estado anterior, idempotência e conflito, isolamento de cópias, invariantes, snapshots malformados e inexistência de restauração parcial. Implementação e testes no commit `a3bc67de1b79a1881a495eed9d9efe95fe66dbcb`.

## Validação

- Suíte específica final: 4/4 testes, 70 asserções, nenhuma falha.
- `tools/validate.ps1`: 126 scripts, zero erros e avisos; inicialização headless aprovada.
- `tools/run_tests.ps1 -Segmented`: 43 suítes, 293/293 testes, 13.100 asserções, zero falhas ou erros de suíte; 43 descobertas e executadas uma vez, nenhuma duplicação ou omissão.
- `git diff --check`: aprovado.

Permanecem pendentes integração com `UnitCarryLoad` e `ResourceSource`, coordenação e rollback entre componentes, saque reservado/claim e descarga física. Nenhuma coleta com proveniência ativa, cancelamento ou alteração de gameplay foi implementada. T3.6.2-B permanece aberta. O commit deste relatório está no histórico da branch.
