# T3.6.2-C2 — Candidata: coordenador transacional do saque reservado (`pilha -> mochila -> proveniencia -> claim`)

## 1. Contexto verificável

- **Repositório:** `Julian0s/Dawn-of-Kin`
- **Worktree:** `C:\Projetos\Dawn_of_Kin_wt_t3_4_5`
- **Branch candidata:** `feat/t3-6-2-provenance-transactions`
- **SHA-base obrigatório:** `4e890852d5faba242b8db9a9809f99e0ca5a291e` (relatório `T3.6.2-C1-R1`, sobre `ca71ec57ca6eeee6a5a47ba64388e6a43caf4421`)
- **`origin/main` de referência:** `25e0a20f1d6a2f10a9e059afe69759fbe263db4a`
- **Engine verificada:** Godot `4.7.2.stable.official.ed1daf0bf`
- **Referência arquitetural:** `T3.6-R2` ([`docs/architecture/T3_6_cancellation_architecture_R2_PROPOSAL.md`](../architecture/T3_6_cancellation_architecture_R2_PROPOSAL.md), commit `69c13275a34a30564ac839ec920f83ef36590812`, §§4–5)
- **Fonte normativa:** [`docs/Dawn_of_Kin_GDD.md`](../Dawn_of_Kin_GDD.md) v1.2 (`wood` peso `2`, `stone` peso `3`, `food` peso `1`, `DEC-11A`, `DEC-11B`, `D2`, `D9`, `DEC-18`)
- **Escopo:** implementação opt-in da primeira transação atômica de saque reservado (`ReservedWithdrawalCoordinator`), sem ativação global de proveniência e sem acoplamento ao caminho jogável (`ConstructOrder`).

---

## 2. Contrato completo das APIs implementadas

### `ReservedWithdrawalCoordinator` ([`src/economy/reserved_withdrawal_coordinator.gd`](../../src/economy/reserved_withdrawal_coordinator.gd))
- `execute_reserved_withdrawal(site: Variant, unit: Variant, pile_id: Variant, resource_id: Variant, requested_amount: Variant, operation_id: Variant, lot_id: Variant, options: Dictionary = {}) -> Dictionary`
  - Executa o saque reservado atômico de `requested_amount` unidades de `resource_id` na pilha `pile_id` (reservada para `site`) para a `UnitCarryLoad` com proveniência habilitada da `unit`, registrando o lote `SITE_RESERVED` (`site_id`, `generation`), atualizando o claim em trânsito na `site`, consumindo `_pending_pickups` elegível, gravando recibo por `operation_id` e publicando sinais coerentes.
  - Retorna em sucesso inédito: `{"ok": true, "reason": "", "dependency": "", "replayed": false, "withdrawn": req_amount, "committed_amount": req_amount, "receipt": <cópia_imutável>}`.
  - Retorna em replay idempotente: `{"ok": true, "reason": "", "dependency": "", "replayed": true, "withdrawn": 0, "committed_amount": N, "receipt": <cópia_imutável>}`.
  - Retorna em rejeição/abort: `{"ok": false, "reason": "<motivo>", "dependency": "<participante>", "replayed": false, "withdrawn": 0}`.
- `commit_prepared_withdrawal(site: Variant, unit: Variant, prepared_plan: Variant, options: Dictionary = {}) -> Dictionary`
  - Valida a forma estrutural de um plano C1-R1 (`ConstructionSite._validate_plan_shape_pure`), verifica identidade e revisões sob guarda (`_validate_plan_under_coordinator_guards`, incluindo `peer_claim_revisions`), verifica os requisitos físicos C2 e comita via `_execute_core`.
- `get_receipt(operation_id: Variant) -> Dictionary` / `has_receipt(operation_id: Variant) -> bool` / `is_busy() -> bool`
- Hook de teste: `var fault_injection_hook: Callable = Callable()` invocado nos 5 pontos determinísticos sem expor bypass em produção quando não configurado.

### Helpers internos silenciosos sob guarda nos participantes
- [`GroundPileManager`](../../src/economy/ground_pile_manager.gd):
  - `_capture_pile_withdrawal_checkpoint(pile_id: int) -> Dictionary`
  - `_apply_prepared_pile_withdrawal_silent(pile_plan: Dictionary, checkpoint: Dictionary) -> Dictionary`
  - `_restore_pile_withdrawal_checkpoint_silent(checkpoint: Dictionary) -> void`
  - `_finalize_exhausted_pile_after_commit_silent(pile: GroundResourcePile) -> bool`
- [`UnitCarryLoad`](../../src/economy/unit_carry_load.gd):
  - `_capture_provenance_checkpoint() -> Dictionary`
  - `_restore_provenance_checkpoint_silent(checkpoint: Dictionary) -> bool`
- [`ConstructionSite`](../../src/buildings/construction_site.gd):
  - `_prepare_reserved_withdrawal_under_coordinator_guards(...) -> Dictionary`
  - `_validate_prepare_preconditions_and_parse(...) -> Dictionary`
  - `_validate_plan_shape_pure(...) -> Dictionary`
  - `_validate_plan_under_coordinator_guards(...) -> Dictionary`
  - `_capture_claim_checkpoint(uid: int) -> Dictionary`
  - `_apply_prepared_claim_silent(unit, carry_load, resource_id, amount, claim_plan, checkpoint) -> bool`
  - `_restore_claim_checkpoint_silent(checkpoint: Dictionary) -> void`

---

## 3. Ordem de aquisição e liberação cooperativa de guardas

1. Antes de adquirir qualquer guarda: verificação de afinidade de thread (`_owner_thread_id == OS.get_thread_caller_id()`), `_is_executing == false`, verificação de idempotência/lote (`_receipts` / `_committed_lots`), checagem de não-ocupação (`site.is_transaction_busy()`, `inventory.is_transaction_busy()`, `storage_source.is_batch_active()`, `pile_manager.is_locked()`, `carry_load.is_transaction_busy()`, além de todos os `peer_sites` da mesma região e `World3D`), e parsing estrutural via `_validate_prepare_preconditions_and_parse`.
2. Aquisição síncrona na ordem fixa `R2`:
   1. `coordinator._is_executing = true` -> `site._is_preparing_or_transacting = true` -> `peer._is_preparing_or_transacting = true` (todos os canteiros pares na mesma região e `World3D`);
   2. `inventory._is_delivering = true` -> `pile_manager._is_preparing_withdrawal = true`;
   3. `carry_load._provenance_busy = true`.
3. Liberação única determinística (`_release_guards`) estritamente em ordem reversa `(3) carry_load -> (2) pile_manager / inventory -> (1) peers (reverso) -> site -> coordinator`, tanto em sucesso (logo após publicação coerente dos sinais) quanto em qualquer caminho de rejeição ou rollback.

---

## 4. Revalidação sob guarda antes do primeiro efeito colateral

Imediatamente após a aquisição das guardas e **antes** de qualquer mutação:
- Se fornecido `prepared_plan` (ou `prior_plan`), `_validate_plan_under_coordinator_guards` verifica:
  - Compatibilidade estrutural e correspondência com `site` e `unit`;
  - Igualdade exata das 7 revisões inteiras (`site_revision`, `site_work_serial`, `inventory_revision`, `storage_revision`, `pile_ledger_revision`, `pile_revision`, `carry_load_revision`);
  - Integridade, geração, presença na região/`World3D` e revisão viva de todas as obras registradas em `peer_claim_revisions` (rejeitando com `"stale_peer_site_revision"` em caso de divergência ou cenário ABA em obra par);
  - Recomposição integral sob guarda confirmando `recomputed == plan` (`"tampered_or_stale_plan"` em payload adulterado).
- Executa `_prepare_reserved_withdrawal_under_coordinator_guards` com `require_assigned_worker = true` obrigatório (qualquer tentativa de passar `options["require_assigned_worker"] = false` é rejeitada com `"physical_authorization_required"`), exigindo papel `TRANSPORTER` ou `SOLO_SUPPLIER` e `ConstructOrder` ativa vinculada ao canteiro e em execução atual na unidade.
- Valida a obrigatoriedade de `_pending_pickups[uid]` compatível (`unit`, `pile_id`, `resource_id` e `amount >= requested_amount`; caso ausente ou inferior, rejeita com `"claim_not_eligible"`).
- Valida o nó `GroundResourcePile` vivo, na árvore e no mesmo `World3D`, e executa o predicado físico real `BuildSlotPlanner.is_unit_in_pile_reach(typed_unit.global_position, pile_manager.get_pile_world_position(pile), ConstructionSite.DEFAULT_PILE_PICKUP_REACH, typed_site.get_world_3d())`, rejeitando com `"out_of_pile_reach"` se houver desnível, distância excessiva ou obstrução física.

---

## 5. Execução silenciosa e fronteira de commit irreversível

1. **Checkpoints pré-mutação:** captura snapshots isolados de pilha + `PileReservationLedger` (`_capture_pile_withdrawal_checkpoint`), mochila + `CarryProvenanceLedger` (`_capture_provenance_checkpoint`) e claims/pickups do canteiro (`_capture_claim_checkpoint`), além das baselines contábeis (`reserved_before`, `in_transit_before`, `buffer_before`, `consumed_before`, `missing_before`).
2. **Estágio A — Pilha e Reserva (silencioso):** `_apply_prepared_pile_withdrawal_silent` deduz do `PileReservationLedger` e reduz `pile.amount` via `apply_state` **sem emitir sinais** e **sem chamar `_remove_and_free_pile(pile)` mesmo quando `next_amount == 0`** (mantendo o nó recuperável em caso de abort posterior).
3. **Estágio B — Mochila e Proveniência (silencioso):** `UnitCarryLoad._apply_prepared_provenance_add(raw_add_plan)` com `_provenance_applying = true` registra o lote `SITE_RESERVED`, atualiza `_amounts`, `_unit_weights` e `_transaction_revision` sem emitir `load_changed`.
4. **Estágio C — Claim em Trânsito e Pending Pickup (silencioso):** `_apply_prepared_claim_silent` consome `_pending_pickups[uid]`, assegura o listener `_ensure_transit_listener(unit, carry_load)`, incrementa `_transit_claims[uid]["amounts"][resource_id]` e verifica o novo claim contra `claim_plan["after_transit_claim"]` sem emitir `state_changed`.
5. **Verificação de invariantes pós-mutação (`_verify_post_mutation_invariants`):** comprova `reserved_before + in_transit_before == reserved_after + in_transit_after`, imutabilidade de `delivered_buffer` / `consumed` / `uncovered_missing`, `site._verify_accounting_invariant_pure()`, `carry_load.validate_provenance()`, pesos/totais esperados, `_verify_unit_claims_reconciled_with_provenance_pure`, e saldo final de pilha e reservas na pilha.
6. **Fronteira irreversível de commit:** somente após a aprovação dos 5 estágios e de todas as invariantes finais ocorre:
   - Remoção e liberação física da pilha exaurida via `_finalize_exhausted_pile_after_commit_silent(pile)` (quando `pile.amount <= 0`);
   - Registro imutável do recibo em `_receipts[op_id]` e bloqueio definitivo do lote em `_committed_lots[lot_id] = op_id`;
   - Publicação coerente dos sinais e liberação reversa das guardas.

---

## 6. Pontos de rollback implementados e prova de restauração

| Ponto de falha injetada | Momento da falha | Componentes restaurados em ordem reversa | Sinais emitidos | Efeito em `_receipts` / `_committed_lots` |
|---|---|---|---|---|
| 1. `"before_pile_deduction"` | Antes da dedução física | Nenhum participante foi mutado | `[]` (zero) | Não gravado |
| 2. `"after_pile_deduction"` | Após dedução de pilha/reserva e antes da mochila | `GroundPileManager._restore_pile_withdrawal_checkpoint_silent` (restaura `PileReservationLedger` incluindo `_reservation_order` + `pile.apply_state`, incrementa revisões) | `[]` (zero) | Não gravado |
| 3. `"after_carry_add"` | Após escrita na mochila/proveniência e antes do claim | `UnitCarryLoad._restore_provenance_checkpoint_silent` -> `GroundPileManager._restore_pile_withdrawal_checkpoint_silent` | `[]` (zero) | Não gravado |
| 4. `"after_claim_update"` | Após atualizar `_pending_pickups`/`_transit_claims`, antes das invariantes finais | `ConstructionSite._restore_claim_checkpoint_silent` (restaura `_pending_pickups` e `_transit_claims`, e desconecta `load_changed` se a unidade não possuía claim prévio) -> `UnitCarryLoad` -> `GroundPileManager` | `[]` (zero) | Não gravado |
| 5. `"during_final_invariants"` | Na verificação final (hook ou corrupção real de invariante detectada pós-mutação) | Mesmo rollback integral nos 3 participantes; em caso de exaustão física (`amount == 0`), nó `GroundResourcePile` **permanece vivo, válido e na árvore**, restaurado ao saldo original | `[]` (zero) | Não gravado |

Em todas as reversões, as revisões (`_transaction_revision` e revisões do ledger de reservas) avançam monotonicamente para impedir cenários ABA, permitindo reexecução legítima posterior com os mesmos `operation_id` e `lot_id` (cenário 23).

---

## 7. Idempotência por `operation_id`, `duplicate_lot` e vínculo canônico do recibo

Cada recibo gravado em `_receipts[op_id]` vincula de forma imutável:
`operation_id`, `lot_id`, `site_instance_id`, `site_id`, `generation`, `reservation_id`, `region_id`, `world_instance_id`, `pile_id`, `pile_instance_id`, `resource_id`, `unit_weight`, `requested_amount`, `committed_amount`, `unit_instance_id`, `carry_load_instance_id`, `unit_id`.

- **Replay idempotente:** mesma `operation_id` já comitada com parâmetros e `prepared_plan` (quando informado) idênticos retorna `{"ok": true, "replayed": true, "withdrawn": 0, "committed_amount": N, "receipt": ...}` mesmo que a pilha original já tenha sido exaurida ou a unidade tenha se deslocado, sem qualquer mutação ou sinal.
- **Conflito (`"operation_conflict"`):** mesma `operation_id` com qualquer divergência em `lot_id`, `pile_id`, `resource_id`, `requested_amount`, `unit`, `site`, `unit_weight` ou restrições de `options` é recusada sem efeitos.
- **Proteção contra reuso de lote (`"duplicate_lot"`):** tentativa de usar um `lot_id` já comitado em `_committed_lots` (mesmo sob outra `operation_id` ou outra unidade) ou já presente em `CarryProvenanceLedger.used_lots` é recusada sem efeitos.

---

## 8. Publicação de sinais e proteção contra observação parcial e reentrância

- Todas as mutações de estado, finalização de pilha exaurida e gravação do recibo completam **antes** do primeiro sinal.
- Durante `pile_manager._emit_reservations_changed()`, `pile_manager._emit_storage_changed()`, `carry_load._emit_load_changed()` e `typed_site.state_changed.emit(typed_site)`:
  - `_suppress_coordinator_signal_echo = true` nas obras travadas impede eco prematuro/triplicado de `state_changed` via `_on_inventory_reservations_changed` e `_on_unit_carry_load_changed` e evita ruído de `state_changed` em obras pares não modificadas;
  - Todas as guardas (`coordinator._is_executing`, `site._is_preparing_or_transacting`, `inventory._is_delivering`, `pile_manager._is_preparing_withdrawal`, `carry_load._provenance_busy`) permanecem ativas enquanto os sinais rodam e são liberadas em ordem reversa somente ao término das notificações;
  - Observadores conectados aos 6 sinais (`manager.reservations_changed`, `inventory.reservations_changed`, `manager.storage_changed`, `inventory.inventory_changed`, `carry_load.load_changed`, `site.state_changed`) leem os exatos valores finais comitados e têm qualquer tentativa de reentrância recusada (`"busy"`, `false`, `0`, `{}`).

---

## 9. Isolamento do legado sem proveniência e bloqueio contra bypass

- **Quando `carry_load.is_provenance_enabled() == true` (ou transação/guarda ativa):**
  - `SettlementInventory.withdraw_reserved_from_pile_to_carry_load` e `deliver_from_carry_load` retornam imediatamente `0` e `{}` sem iniciar lotes nem alterar cargas/pilhas.
  - `ConstructionSite.record_withdrawn_for_site` e `accept_delivery_from_carry_load` retornam imediatamente sem acionar `_prune_stale_state()` e sem alterar `_pending_pickups`, `_transit_claims`, `_delivered_buffer` ou `_transaction_revision`.
  - `UnitCarryLoad.add_units`, `add_resource`, `remove_units`, `take_all` e `restore_load_snapshot` seguem bloqueados por `_provenance != null`.
  - Mutadores públicos de `ConstructionSite`, `GroundPileManager` e `SettlementInventory` respeitam `is_transaction_busy()` / `is_locked()`.
- **Quando `is_provenance_enabled() == false`:** o caminho legado (`ConstructOrder`, `withdraw_reserved_from_pile_to_carry_load`, `record_withdrawn_for_site`, `accept_delivery_from_carry_load`, `deliver_from_carry_load`, além da suíte B3.2 para mutações de capacidade em `_before_provenance_transfer_commit`) permanece 100% preservado.

---

## 10. Arquivos alterados e criados

| Arquivo | Tipo | Finalidade |
|---|---|---|
| [`src/economy/reserved_withdrawal_coordinator.gd`](../../src/economy/reserved_withdrawal_coordinator.gd) (+ `.uid`) | Novo | Coordenador transacional opt-in `ReservedWithdrawalCoordinator`, recibos idempotentes, pontos de injeção de falha e publicação coerente de sinais. |
| [`src/economy/ground_pile_manager.gd`](../../src/economy/ground_pile_manager.gd) | Modificado | Helpers silenciosos `_capture_pile_withdrawal_checkpoint`, `_apply_prepared_pile_withdrawal_silent`, `_restore_pile_withdrawal_checkpoint_silent` e remoção diferida `_finalize_exhausted_pile_after_commit_silent`. |
| [`src/economy/settlement_inventory.gd`](../../src/economy/settlement_inventory.gd) | Modificado | Guardas `is_transaction_busy()` em mutadores e bloqueio de `withdraw_reserved_from_pile_to_carry_load` / `deliver_from_carry_load` para cargas com proveniência habilitada. |
| [`src/economy/unit_carry_load.gd`](../../src/economy/unit_carry_load.gd) | Modificado | Helpers de checkpoint/restauração silenciosa `_capture_provenance_checkpoint` e `_restore_provenance_checkpoint_silent`. |
| [`src/buildings/construction_site.gd`](../../src/buildings/construction_site.gd) | Modificado | Guardas transacionais em mutadores, bloqueio legado em cargas com proveniência (`record_withdrawn_for_site`, `accept_delivery_from_carry_load`), supressão de eco `_suppress_coordinator_signal_echo`, revalidação sob guarda (`_validate_plan_under_coordinator_guards`, `_prepare_reserved_withdrawal_under_coordinator_guards`) e helpers silenciosos de claim/pickup. |
| [`tests/integration/test_t3_6_2_c1_reserved_withdrawal_prep.gd`](../../tests/integration/test_t3_6_2_c1_reserved_withdrawal_prep.gd) | Modificado | Substituição das 5 semeaduras diretas via `record_withdrawn_for_site` em cargas com proveniência (testes `test_03` e `test_09`) por helper local de fixture `_seed_site_transit_claim`. |
| [`tests/integration/test_t3_6_2_c2_reserved_withdrawal_transaction.gd`](../../tests/integration/test_t3_6_2_c2_reserved_withdrawal_transaction.gd) (+ `.uid`) | Novo | Suíte de integração adversarial C2 cobrindo integralmente os 30 cenários exigidos. |
| [`docs/testing/T3_6_2_C2_candidate_report.md`](T3_6_2_C2_candidate_report.md) | Novo | Este relatório técnico da candidata C2. |

---

## 11. Matriz dos 30 cenários testados e resultados

Suíte [`tests/integration/test_t3_6_2_c2_reserved_withdrawal_transaction.gd`](../../tests/integration/test_t3_6_2_c2_reserved_withdrawal_transaction.gd) (`10/10` funções de teste, **492 asserções, 0 falhas, 0 erros/avisos**):

| Cenários | Teste na suíte C2 | Asserções | Resultado |
|---|---|---|---|
| 1, 2, 3, 4 (parcial, esgotar reserva mantendo livre/outra obra, exaurir pilha no commit, mochila vazia) | `test_01_02_03_04_happy_paths_partial_site_exhaustion_pile_exhaustion_empty_load` | 50 | PASS |
| 5, 6, 7, 8 (mochila mista com `FREE_GATHERED` mesmo/outro recurso, acúmulo na mesma obra/geração, múltiplas obras ativas) | `test_05_06_07_08_mixed_carry_loads_free_and_multi_site_preservation` | 26 | PASS |
| 9, 10, 11, 12, 13, 14 (reserva/pilha insuficiente, reserva de outra obra, capacidade, `unit_weight`, alcance físico real inclusive deslocamento pós-prepare) | `test_09_10_11_12_13_14_precondition_rejections_zero_mutations_zero_signals` | 38 | PASS |
| 15, 16, 17, 18, 19, 23 (rollbacks nos pontos 1–5 inclusive com exaustão de pilha sem `free()` prematuro, corrupção de invariante e retry com mesmos IDs) | `test_15_16_17_18_19_23_fault_injection_rollbacks_and_retry_after_abort` | 215 | PASS |
| 20, 21, 22 (replay idempotente via execução direta e plano preparado, `operation_conflict` e `duplicate_lot`) | `test_20_21_22_idempotent_replay_operation_conflict_and_duplicate_lot` | 35 | PASS |
| 24, 25, 26 (invalidação concorrente e ABA de pilha/ledger, mochila/proveniência, obra e obra par `stale_peer_site_revision`) | `test_24_25_26_concurrent_invalidation_and_aba_detection` | 25 | PASS |
| 27 (reentrância bloqueada em todos os 6 sinais relevantes com visão final consistente entre observadores) | `test_27_reentrancy_in_all_signals_and_consistent_observer_view` | 59 | PASS |
| 28 (isolamento `World3D`, região/origem desconhecida, geração, papel `BUILDER`, ausência de `_pending_pickups`, tamper e thread) | `test_28_world_region_generation_worker_eligibility_and_tamper` | 20 | PASS |
| 29 (bloqueio total de todos os métodos legados sem proveniência em carga com proveniência ativa) | `test_29_legacy_bypass_methods_blocked_when_provenance_enabled` | 13 | PASS |
| 30 (regressão integral do fluxo legado sem proveniência) | `test_30_legacy_flow_without_provenance_remains_intact` | 11 | PASS |

---

## 12. Resultados completos de validação e testes

Executados em `C:\Projetos\Dawn_of_Kin_wt_t3_4_5` após a edição final de código e testes, com Godot `4.7.2.stable.official.ed1daf0bf`:

| Verificação | Resultado observado |
|---|---|
| `.\tools\run_tests.ps1 -Filter test_t3_6_2_c2` | **10/10 testes aprovados, 492 asserções, 0 falhas, 0 vazamentos ObjectDB, saída `0`** (`542,4 ms` Godot / `10.277,6 ms` total isolado; `161,3 ms` Godot dentro do lote `integration-08` em `-Segmented`). |
| `.\tools\run_tests.ps1 -Filter test_t3_6_2_c1` | **10/10 testes aprovados, 282 asserções, 0 falhas, saída `0`** (`192,8 ms` isolado; `154,4 ms` em `integration-08`). |
| `.\tools\run_tests.ps1 -Filter test_t3_6_2` | **5/5 suítes T3.6.2 (`a`, `b2`, `b3_2`, `c1`, `c2`), 32/32 testes aprovados, 976 asserções, 0 falhas, saída `0`** (`17.343,5 ms`). |
| `.\tools\validate.ps1` | **Validation PASSED (`0 errors`, `0 warnings`, `131 scripts checked`)** incluindo importação headless, `--check-only` e boot headless da cena principal (`exit 0`). |
| `.\tools\run_tests.ps1 -Segmented` | **10/10 lotes aprovados (`unit`, `integration-01`..`09`), 47/47 suítes, 321/321 testes aprovados, 14.011 asserções, 0 falhas, 0 erros de suíte** (`Discovered=47`, `ExecutedUnique=47`, `Duplicates=0`, `Missing=0`, `SumGodotElapsed=466.112,2 ms`, `TotalWallElapsed=484.822,8 ms`, `exit 0`). |
| `git diff --check` | **Aprovado (`exit 0`, sem erros de formatação ou whitespace).** |

Nenhum teste manual ou interativo em UI foi executado nesta etapa de backend transacional.

---

## 13. Confirmação explícita de não escopo (o que **não** foi implementado)

Em estrita conformidade com os limites da `T3.6.2-C2`, este incremento **não** implementa:
- Ativação global de proveniência nas mochilas do jogo;
- Conexão automática de `ReservedWithdrawalCoordinator` em `ConstructOrder._execute_pile_withdrawal()`;
- Entrega seletiva na obra por origem/lote;
- Depósito seletivo no acampamento;
- Cancelamento de obra (`D3`) ou estados de cancelamento (`REQUESTED`, `FREEZING`, `RETURNING`, `SETTLED`);
- Recuperação ou ressarcimento de materiais já incorporados (`consumed`);
- Depósitos físicos `T3.7`, save/load `T3.8` ou alterações de HUD;
- Merge em `main` ou criação de tags Git.

---

## 14. Limitações técnicas conhecidas e próximos passos previstos

- **Escopo estritamente em memória e por instância do coordenador:** os recibos `_receipts` e índices `_committed_lots` pertencem à instância de `ReservedWithdrawalCoordinator` (persistência entre execuções depende da futura camada `T3.8`).
- **Execução headless de backend:** testes headless validam exaustivamente toda a lógica, concorrência síncrona, sinais e rollback, mas não substituem futuros testes jogáveis no runtime completo quando `ConstructOrder` passar a consumir o coordenador.
- **Imutabilidade em GDScript:** assim como na `C1`, GDScript não impõe controle de acesso em tempo de execução contra mutação direta externa de atributos privados (`_amounts`, `_ledger`, `_transit_claims`, `_transaction_revision`).
- **Próximo passo previsto:** implementar a entrega seletiva na obra / retorno ao acampamento (`T3.6.2-C3+`) mantendo compatibilidade integral com `ReservedWithdrawalCoordinator` e conciliação `SITE_RESERVED` / `FREE_GATHERED`.

---

## 15. Commits criados na branch e publicação

Commits criados na branch `feat/t3-6-2-provenance-transactions` a partir do SHA-base `4e890852d5faba242b8db9a9809f99e0ca5a291e`:

1. `bfffe8ad15e8ba6a42754b2c00c991a4a8f50ad6` — `feat(t3.6.2-c2): add opt-in transactional coordinator for reserved pile withdrawal`
2. `05260ec55e9c8037d30dcfed3655079d654996fe` — `test(t3.6.2-c2): add 30-scenario adversarial suite for reserved withdrawal transaction`
3. Commit documental subsequente desta própria entrega (`docs(t3.6.2-c2): publish C2 technical candidate report`) contendo exclusivamente [`docs/testing/T3_6_2_C2_candidate_report.md`](T3_6_2_C2_candidate_report.md), seguido de publicação na branch remota `origin/feat/t3-6-2-provenance-transactions`.

**T3.6.2-C2 IMPLEMENTADA COMO CANDIDATA E VALIDADA AUTOMATIZADAMENTE — AGUARDANDO AUDITORIA INDEPENDENTE DO CHATGPT. SEM MERGE EM `main` E SEM TAG.**
