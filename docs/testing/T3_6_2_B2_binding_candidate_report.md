# T3.6.2-B2 — Associação inicial opcional à mochila

Base `230c25d27eef13e69aec0476569a0023330da77b`; branch `feat/t3-6-2-provenance-transactions`. Este incremento é parcial e não conclui a B2.

## Implementação

`UnitCarryLoad.enable_provenance(unit_id)` só aceita mochila vazia e cria um ledger novo exclusivo, sem receber nem compartilhar ledger externo. `provenance_snapshot()` retorna cópias de quantidades, pesos e estado transacional completo; `validate_provenance()` compara os lotes com as quantidades físicas. `add_with_provenance(operation_id, lot_id, resource_id, unit_weight, amount, origin, site_id, generation)` prepara um ledger candidato independente a partir de snapshot completo, valida operação, capacidade, peso, limites e balanço, e então publica os dois estados antes do sinal. Uma falha na preparação não altera nenhum dos dois estados, incluindo histórico e IDs. Repetição idêntica é no-op; conflito é recusado. Uma guarda recusa adição reentrante enquanto o sinal imediato é emitido. O ledger pertence à mochila e não é retornado pela API; nomes internos em GDScript são convenção e acesso deliberado a campos internos não constitui fronteira de segurança.

No modo ativo, `add_resource`/`add_units` retornam falso, `remove_units` retorna zero, `take_all` retorna vazio e `restore_load_snapshot` não altera estado. No modo desativado mantêm comportamento anterior. Não há ativação automática em cenas ou unidades. A etapa não implementa remoção seletiva, desativação, integração com ResourceSource ou rollback econômico entre objetos. Snapshot é somente diagnóstico; não é API de restauração externa. O custo de reconstruir histórico cresce com o número de operações; não foi medido benchmark.

## Verificação

Suíte específica `tools/run_tests.ps1 -Filter t3_6_2_b2_carry_binding`: 3/3 testes, 35 asserções, sem falhas. Abrange obras A/B, recursos diferentes, capacidade, peso, repetição e conflito, bloqueio legado, estados anteriores/posteriores, independência e reentrância. Falha de capacidade ocorre após preparação do ledger candidato e deixa snapshot físico e de histórico inalterado. A primeira execução apresentou vazamento causado pelo ciclo de referência do callback do teste; desconectar o callback corrigiu o problema, e a execução posterior passou sem erros ou avisos.

`tools/validate.ps1`: 127 scripts, zero erros ou avisos. `tools/run_tests.ps1 -Segmented`: 44 suítes, 296/296 testes, 13.136 asserções; zero falhas ou erros de suíte; 44 descobertas e executadas uma vez, sem duplicações ou omissões. `git diff --check` aprovado.

Nenhuma coleta, saque, depósito, obra ou cancelamento foi integrado ao modo opcional. Não houve teste visual ou alteração pretendida da experiência jogável. A infraestrutura requer auditoria antes de futura integração operacional.

Commits técnicos: `5020222db5999f10b39f3c6c53ffa693ba6a13c2` e `3c7aa29900a1d1491d66ca7c6a6729ce8ccd435f`. O commit deste relatório consta no histórico da branch.
