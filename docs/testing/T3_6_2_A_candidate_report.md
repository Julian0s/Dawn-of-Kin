# T3.6.2-A — Candidata: ledger isolado de proveniência

Base `25e0a20f1d6a2f10a9e059afe69759fbe263db4a`; branch `feat/t3-6-2-provenance-transactions`. Referência [T3.6-R2](https://github.com/Julian0s/Dawn-of-Kin/blob/69c13275a34a30564ac839ec920f83ef36590812/docs/architecture/T3_6_cancellation_architecture_R2_PROPOSAL.md). Não há integração operacional de lotes neste incremento.

## Inventário de mutadores e chamadores

- `UnitCarryLoad.add_units`, `remove_units`, `take_all`, `restore_load_snapshot`: alteram ou restauram quantidades/pesos agregados.
- `ResourceSource.transfer_to_carry_load`: extrai e adiciona à mochila; chamada por `GatherResourceOrder`.
- `SettlementInventory.withdraw_reserved_from_pile_to_carry_load`: adiciona à mochila e retira reserva/pilha; chamada por `ConstructOrder._execute_pile_withdrawal`, que registra o claim depois.
- `ConstructionSite.accept_delivery_from_carry_load`: remove da mochila, atualiza buffer e claims; chamada por `ConstructOrder`.
- `SettlementInventory.deliver_from_carry_load`: usa `take_all`, deposita e restaura mochila em falha; chamada por `DeliverToCampOrder`.
- `ConstructionSite.record_withdrawn_for_site`: registra claim, sem alterar fisicamente a mochila. `selection_manager.add_units` manipula seleção RTS, não materiais.

## Contrato

`CarryProvenanceLedger` é `RefCounted`, com `register_lot(op, lot)`, `query(unit, resource, origin, site)`, `split_lot(op, lot_id, child_id, amount)`, `withdraw(op, lot_id, amount)`, `snapshot()` e `validate_aggregate(unit, aggregate)`. Lotes possuem IDs fornecidos, trabalhador, recurso, quantidade inteira positiva, origem `FREE_GATHERED` ou `SITE_RESERVED`, obra quando aplicável e geração. IDs de lote não são reutilizados durante a vida do ledger. Cada operação bem-sucedida registra seu ID e conteúdo; repetição igual retorna `replayed`, conteúdo diferente é recusado. Valores inválidos falham antes da mutação. Soma por unidade e recurso é verificada contra overflow; snapshots e consultas retornam cópias independentes. Retirada seleciona um único lote por ID; não é uma descarga física.

A validação compara a soma de lotes à mochila agregada fornecida, devolvendo diagnóstico de divergência sem alterar ou atribuir origem. Os testes provam conservação na divisão e seleção de lotes no ledger isolado; não demonstram identidade com uma mochila real. O chamador futuro precisa fornecer IDs estáveis e integrar atomicamente o ledger a todas as mutações físicas.

## Resultados

- Suíte específica: 2/2 testes, 33 asserções, sem falhas.
- `tools/validate.ps1`: 126 scripts, zero erros ou avisos, inicialização headless aprovada.
- `tools/run_tests.ps1 -Segmented`: 43/43 suítes, 291/291 testes, 13.069 asserções, zero falhas/erros de suíte; 43 descobertas e executadas sem omissões ou duplicatas.
- `git diff --check`: verificado antes da publicação.

## Limitações

Sem uso operacional do ledger em `src` existente; nenhum fluxo de gameplay alterado. A janela entre saque e claim, integração com mochilas e claims, rollback entre componentes, descarga física seletiva, custódia e cancelamento continuam pendentes. O ledger é apenas memória: não implementa persistência nem garante por si só atomicidade entre objetos. IDs de operações são mantidos durante a vida da instância; o armazenamento cresce com as operações. Nenhum teste visual foi realizado.

Commits técnicos: `fcfd4ff` implementação, `13fda09` testes, `b0acf1f` ajuste de espaço. O commit deste relatório consta no histórico Git. A T3.6.2 completa não está concluída.
