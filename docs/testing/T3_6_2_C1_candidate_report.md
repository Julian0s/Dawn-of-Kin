# T3.6.2-C1 — Candidata: preparação transacional do saque reservado e claim

**Base verificada:** `7349f71f472042edf62fa6c7a4e1b44bc7b0d4e5` (`feat/t3-6-2-provenance-transactions`).  
**`origin/main` de referência:** `25e0a20f1d6a2f10a9e059afe69759fbe263db4a`.  
**Referência arquitetural:** [T3.6-R2](https://github.com/Julian0s/Dawn-of-Kin/blob/69c13275a34a30564ac839ec920f83ef36590812/docs/architecture/T3_6_cancellation_architecture_R2_PROPOSAL.md) (commit `69c13275a34a30564ac839ec920f83ef36590812`).  
**GDD normativo:** `docs/Dawn_of_Kin_GDD.md` v1.2 (`wood` peso `2`, `stone` peso `3`, `food` peso `1`, `DEC-11A`, `DEC-11B`, `D2`, `D3`, `D9`, `DEC-18`).  
**Escopo:** implementação exclusiva da preparação pura, opt-in e sem efeitos colaterais (*dry run*) para saque reservado de pilha para mochila com proveniência da obra (`SITE_RESERVED`) e claim em trânsito, além de contadores de revisão anti-ABA e suíte adversarial de testes. **Nenhuma ativação global de proveniência, nenhuma alteração em `ConstructOrder`, nenhum commit transacional C2 e nenhum cancelamento D3.**

---

## 1. Contrato das APIs implementadas

### `ConstructionSite.prepare_reserved_withdrawal(...)`
```gdscript
func prepare_reserved_withdrawal(
    unit: Variant,
    pile_id: Variant,
    resource_id: Variant,
    requested_amount: Variant,
    operation_id: Variant,
    lot_id: Variant,
    options: Dictionary = {}
) -> Dictionary
```
- **Natureza:** opt-in, pura e rigorosamente sem efeitos colaterais (`dry_run_only = true`, `commit_supported = false`). Exige mochila com proveniência habilitada (`UnitCarryLoad.enable_provenance`).
- **Parâmetros e identificadores verificados:**
  - `site_id` e `_generation` (incrementado em `configure`, exigido `> 0`; validados contra `options.site_id` / `options.generation` quando fornecidos).
  - `reservation_id` do canteiro (validado contra `options.reservation_id`).
  - `pile_id`, `resource_id`, `requested_amount` inteiros estritamente positivos; peso unitário verificado consistentemente entre pilha, definição do canteiro, `options.unit_weight` e mochila.
  - `unit` (`Unit` válido e na árvore) e respectiva `UnitCarryLoad` (`options.unit_id` e `options.carry_load` se informados, além de unicidade contra conflito de identidade com outros trabalhadores/canteiros).
  - `operation_id` e `lot_id` (validados via `CarryProvenanceLedger._id`, verificados contra operações já registradas, `used_lots` e `options.prior_plan`).
- **Ordem cooperativa de guardas (R2):** adquire temporariamente `(1) site._is_preparing_or_transacting -> (2) GroundPileManager._is_preparing_withdrawal -> (3) carry_load._provenance_busy` (sem `await`) e libera estritamente na ordem inversa `(3) -> (2) -> (1)` antes de retornar. Qualquer reentrância prévia retorna `{"ok": false, "reason": "busy", "dependency": ...}`.
- **Retorno em rejeição:** `{"ok": false, "reason": "<motivo_explicito>", "dependency": "<participante_tecnico>"}` sem alterar nenhum estado.
- **Retorno em aprovação:** dicionário destacado com cópias independentes de:
  - Identidades (`operation_id`, `lot_id`, `site_instance_id`, `site_id`, `generation`, `reservation_id`, `region_id`, `pile_id`, `pile_instance_id`, `resource_id`, `unit_weight`, `requested_amount`, `unit_instance_id`, `unit_id`).
  - `revisions` (`site_revision`, `site_work_serial`, `inventory_revision`, `storage_revision`, `pile_ledger_revision`, `pile_revision`, `carry_load_revision`).
  - `lock_order` (`["site", "inventory_storage", "carry_load"]`).
  - `pile_plan` (projeção `before`/`after` da pilha física e do `PileReservationLedger` isolado).
  - `carry_plan` (projeção `before`/`after` de pesos, quantidades, novo lote `SITE_RESERVED` e histórico completo de `CarryProvenanceLedger`).
  - `claim_plan` (projeção `before`/`after` de `unit_transit_claim`, `pending_pickup`, `site_in_transit` e contabilidade `Q = S + T + B + C + M`).

### `ConstructionSite.validate_reserved_withdrawal_plan(plan, options = {}) -> Dictionary`
- Revalida estrutura do plano, identidade dos participantes (`site_instance_id`, `pile_instance_id`, `unit_instance_id`), ausência de contenção (`busy`), igualdade exata das 7 revisões em `plan.revisions` (detectando alterações silenciosas e cenários ABA mesmo quando os valores retornam ao estado anterior), reexecuta `prepare_reserved_withdrawal` com `expected_revisions = plan.revisions` e confirma `recomputed == plan` (rejeitando planos adulterados com `"tampered_or_stale_plan"`), sem qualquer mutação ou sinal.

### `GroundPileManager._prepare_reserved_pile_withdrawal(pile_id, reservation_id, resource_id, amount) -> Dictionary`
- Valida estado livre de mutação/notificação/lote, existência e validade da pilha, recurso e peso, integridade `total_reserved_on_pile <= pile.amount`, posse exclusiva da reserva pelo `reservation_id` informado (`reservation_belongs_to_other_site` vs `no_site_reservation_on_pile` conforme `DEC-11B`), saldo reservado e saldo físico suficientes, e simula `deduct_from_pile` sobre um `PileReservationLedger` temporário descartável, preservando saldo livre e reservas concorrentes na mesma pilha.

### Contadores de revisão anti-ABA adicionados
- [`GroundResourcePile`](../../src/economy/ground_resource_pile.gd): `get_transaction_revision()` incrementado em `configure_initial()` e `apply_state()`.
- [`PileReservationLedger`](../../src/economy/pile_reservation_ledger.gd): `get_transaction_revision()` incrementado em `clear()`, `allocate_on_pile()`, `deduct_from_pile()` (quando deduz `> 0`), `erase_pile()` e `restore_state()`.
- [`SettlementStorageSource`](../../src/economy/settlement_storage_source.gd): `get_transaction_revision()` incrementado em `_emit_storage_changed()` e `_emit_reservations_changed()`.
- [`GroundPileManager`](../../src/economy/ground_pile_manager.gd): `get_pile_ledger_revision()`, `get_resource_definition_pure()`, `_is_preparing_withdrawal` incluído em `is_locked()`, além de incrementos de `_transaction_revision` em `configure()`, `set_definitions()`, `set_camp_zone()`, `set_piles_root()`, `set_time_provider()`, `cleanup()`, `_remove_and_free_pile()`, `step_decay()` (inclusive quando apenas a exposição temporal da pilha avança sem perda inteira) e rollbacks de `_commit_reserve_entries` / `_commit_deposit_plan` / `_commit_withdraw_plan`.
- [`SettlementInventory`](../../src/economy/settlement_inventory.gd): `get_transaction_revision()` (incrementado em `set_storage_source` e encaminhamentos de sinal) e `is_transaction_busy()`.
- [`UnitCarryLoad`](../../src/economy/unit_carry_load.gd): `get_transaction_revision()`, `is_provenance_enabled()`, `get_provenance_unit_id()` e `is_transaction_busy()`.
- [`ConstructionSite`](../../src/buildings/construction_site.gd): `get_generation()`, `get_transaction_revision()`, `is_transaction_busy()`, `_is_preparing_or_transacting` (verificado também por `contribute_work()` e `authorize_manual_complement()`), e incrementos de `_transaction_revision` exclusivamente em mutações reais (nunca em leituras puras nem em `_prune_stale_state()` quando não há itens mortos).

---

## 2. Mapa dos mutadores, janelas reentrantes e efeitos indiretos

1. **Caminho jogável atual (`ConstructOrder._execute_pile_withdrawal`):**
   - Chama `SettlementInventory.withdraw_reserved_from_pile_to_carry_load` (`src/economy/settlement_inventory.gd#L216`) e **somente após seu retorno** chama `ConstructionSite.record_withdrawn_for_site` (`src/units/orders/construct_order.gd#L561`).
   - Dentro de `withdraw_reserved_from_pile_to_carry_load`: `_storage_source.end_batch(false)` (linha 269) dispara `GroundPileManager.reservations_changed` e `storage_changed` **antes** de `carry_load.end_batch(false)` (linha 270) e **antes** do registro de claim em trânsito na obra. Nesse intervalo, `ConstructionSite._on_inventory_reservations_changed()` já observa `reserved` reduzido com `in_transit` ainda zerado e pode reequilibrar papéis ou emitir `state_changed`.
   - Em seguida, `carry_load.end_batch(false)` dispara `load_changed`, podendo executar `ConstructionSite._on_unit_carry_load_changed()` (se a unidade já tiver listener ativo) igualmente **antes** de `record_withdrawn_for_site`.
   - `begin_batch()`/`end_batch()` em `SettlementStorageSource` e `UnitCarryLoad` apenas postergam/coalescem sinais; não oferecem atomicidade multicomponente nem rollback conjunto.
2. **Efeitos colaterais indiretos em getters existentes de `ConstructionSite`:**
   - `get_in_transit_amounts()`, `get_transit_claim_for_unit()`, `get_pending_pickup_amount()`, `get_total_pending_pickup_for_resource()`, `get_remaining_supply_to_claim()`, `get_worker_role()`, `get_unneeded_cargo_for_unit()`, `has_deliverable_transit_claim_for_unit()` e `has_active_peer_transport_for_site()` invocam `_prune_stale_state()`, podendo apagar entradas de `_pending_pickups`, `_transit_claims`, `_assigned_workers` e emitir `workers_changed` / `state_changed`.
   - `get_resource_definition()` persiste entradas no dicionário `_resource_defs` via `ResourceLoader`.
   - **Solução adotada na C1:** todas as consultas internas de `prepare_reserved_withdrawal` e `validate_reserved_withdrawal_plan` utilizam leitores puros dedicados (`_has_stale_participants_pure`, `_resolve_resource_definition_pure`, `_read_*_pure`, `_verify_unit_claims_reconciled_with_provenance_pure`), jamais invocando `_prune_stale_state()` ou gravando em `_resource_defs`.

---

## 3. Arquivos alterados e criados

| Arquivo | Tipo | Finalidade |
|---|---|---|
| [`src/buildings/construction_site.gd`](../../src/buildings/construction_site.gd) | Modificado | `_generation`, `_transaction_revision`, guarda cooperativa, leitores puros, `prepare_reserved_withdrawal()` e `validate_reserved_withdrawal_plan()`. |
| [`src/economy/ground_pile_manager.gd`](../../src/economy/ground_pile_manager.gd) | Modificado | `_is_preparing_withdrawal` em `is_locked()`, `get_pile_ledger_revision()`, `get_resource_definition_pure()`, revisões em mutadores e `_prepare_reserved_pile_withdrawal()`. |
| [`src/economy/ground_resource_pile.gd`](../../src/economy/ground_resource_pile.gd) | Modificado | `_transaction_revision` e `get_transaction_revision()` em `configure_initial()` e `apply_state()`. |
| [`src/economy/pile_reservation_ledger.gd`](../../src/economy/pile_reservation_ledger.gd) | Modificado | `_transaction_revision` e `get_transaction_revision()` em mutações e `restore_state()`. |
| [`src/economy/settlement_inventory.gd`](../../src/economy/settlement_inventory.gd) | Modificado | `_transaction_revision`, `get_transaction_revision()` e `is_transaction_busy()`. |
| [`src/economy/settlement_storage_source.gd`](../../src/economy/settlement_storage_source.gd) | Modificado | `_transaction_revision` e `get_transaction_revision()`. |
| [`src/economy/unit_carry_load.gd`](../../src/economy/unit_carry_load.gd) | Modificado | `get_transaction_revision()`, `is_provenance_enabled()`, `get_provenance_unit_id()` e `is_transaction_busy()`. |
| [`tests/integration/test_t3_6_2_c1_reserved_withdrawal_prep.gd`](../../tests/integration/test_t3_6_2_c1_reserved_withdrawal_prep.gd) (+ `.uid`) | Novo | Suíte de integração adversarial C1 cobrindo os 15 cenários exigidos. |
| [`docs/testing/T3_6_2_C1_candidate_report.md`](T3_6_2_C1_candidate_report.md) | Novo | Este relatório técnico da candidata C1. |

---

## 4. Invariantes garantidos e evidências de preparação sem efeitos

- **Conservação contábil e de lotes no plano:** todo plano aprovado garante `reserved_after == reserved_before - amount`, `in_transit_after == in_transit_before + amount`, `delivered_buffer`/`consumed`/`uncovered_missing` inalterados, `sum == required`, soma de lotes `SITE_RESERVED(site_id)` no ledger projetado igual a `after_transit_claim[resource_id]`, `after_amounts` reconciliado no `CarryProvenanceLedger` projetado e saldo livre da pilha intacto.
- **Regras de negócio preservadas:** respeito estrito a `DEC-11B` (reservas deterioradas não são complementadas automaticamente e pilhas livres pós-deterioração exigem `authorize_manual_complement` com `ManualComplementIntent`), separação entre reservas concorrentes de obras distintas, suporte a mochila mista (`FREE_GATHERED` + `SITE_RESERVED` de obra B + `SITE_RESERVED` de obra A) e rejeição de desvios (`unreconciled_cargo`, `unreconciled_site_claim`, `conflicting_site_claims`).
- **Ausência rigorosa de efeitos:** `SignalSpy` conectado a todos os sinais de `GroundPileManager`, `SettlementInventory`, `ConstructionSite` (todas as obras envolvidas) e `UnitCarryLoad` confirmou `events == []`, e `_snapshot_all(...)` comparou pilhas (quantidades, exposição, revisões, camadas visuais), `_ledger`, inventário, mochila (quantidades, pesos, snapshot transacional completo do ledger, revisão), claims, trabalhadores e revisões do canteiro antes e depois das preparações e validações.
- **Proteção ABA comprovada:** validada por `test_05` em 4 mutações ABA independentes (capacidade da mochila alterada e revertida; reserva liberada e complementada ao mesmo saldo; nó `GroundResourcePile` alterado e revertido; `claim_pickup` + `release_pickup_claim`), além de avanço silencioso de exposição via `step_decay()` sem perda física e detecção de payload adulterado.

---

## 5. Resultados completos de validação e testes

Executados diretamente em `C:\Projetos\Dawn_of_Kin_wt_t3_4_5` com Godot `4.7.2.stable.official.ed1daf0bf`:

| Verificação | Resultado observado |
|---|---|
| `.\tools\run_tests.ps1 -Filter test_t3_6_2_c1` | **5/5 testes aprovados, 221 asserções, 0 falhas, 0 erros de suíte** (`145,8 ms` Godot / `8.467,5 ms` total). |
| `.\tools\validate.ps1` | **APROVADO** — importação headless, `--check-only` em **129 scripts** e boot headless da cena principal com **0 erros e 0 avisos** (`exit 0`). |
| `.\tools\run_tests.ps1 -Segmented` | **46/46 suítes, 306/306 testes aprovados, 13.455 asserções, 0 falhas, 0 erros de suíte, 0 erros/avisos Godot** em 10 lotes disjuntos (`Discovered=46`, `ExecutedUnique=46`, `Duplicates=0`, `Missing=0`, `SumGodotElapsed=452.022,3 ms`, `TotalWallElapsed=465.905,6 ms`). |
| `git diff --check` | **Aprovado**, `0` erros de whitespace/formatação. |

Regressões T3.1–T3.6.2 preservadas integralmente na execução segmentada:
- `test_t3_1_reservations`: 17/17 (432 asserções)
- `test_t3_2_placement_validation`: 7/7 (134) / `test_t3_2_placement_flow`: 5/5 (111)
- `test_t3_3_construction_site`: 7/7 (164) / `test_t3_3_ux_display_and_workers`: 2/2 (9) / `test_t3_3_construction_logistics`: 11/11 (225) / `test_t3_3_ux_flow`: 3/3 (57)
- `test_t3_4_1_accounting_and_complement`: 8/8 (299) / `test_t3_4_2_deterministic_assembly`: 11/11 (829) / `test_t3_4_3_reactive_construction_orders`: 7/7 (426) / `test_t3_4_4_building_completion`: 9/9 (1.355) / `test_t3_4_5_navigation_bake`: 9/9 (2.305)
- `test_t3_5_1_construction_hud`: 3/3 (35) / `test_t3_5_2_building_inspector`: 3/3 (64)
- `test_t3_6_1_refund_math`: 5/5 (113) / `test_t3_6_2_a_provenance_ledger`: 4/4 (70) / `test_t3_6_2_b2_carry_binding`: 4/4 (53) / `test_t3_6_2_b3_2_source_transfer`: 4/4 (79)

Nenhum teste manual ou visual foi executado nesta etapa técnica de backend.

---

## 6. Limitações, dependências para C2 e riscos residuais

- **Preparação não é commit:** `prepare_reserved_withdrawal` e `validate_reserved_withdrawal_plan` não efetivam retirada física, mutação de mochila ou criação de claim (`commit_supported = false`). O caminho jogável em `ConstructOrder._execute_pile_withdrawal` permanece inalterado e sem proveniência.
- **Dependências técnicas necessárias para a execução atômica posterior (C2):**
  1. Método silencioso de dedução reservada/física em `GroundPileManager` vinculado exatamente ao `pile_plan`, capaz de restaurar snapshots de pilha/ledger (ou falhar antes de qualquer mutação irreversível) sem remover nós nem emitir sinais antes do commit global.
  2. Método silencioso em `ConstructionSite` para registrar o incremento do claim em trânsito, limpar `_pending_pickups` e vincular o listener de `UnitCarryLoad` sem emissão prematura de `state_changed`.
  3. Aplicação silenciosa já existente na mochila (`UnitCarryLoad._apply_prepared_provenance_add`) composta sob a mesma aquisição de guardas R2 `(1) site -> (2) storage -> (3) carry_load`, com revalidação integral de revisões/estado e liberação das guardas em ordem inversa antes de emitir coerentemente `storage_changed`, `reservations_changed`, `load_changed` e `site.state_changed`.
  4. Política explícita de idempotência para operações já cometidas em nível coordenado (recibo de saque reservado abrangendo pilha + mochila + claim, evitando duplo saque ou bloqueio indevido em replay).
  5. Eliminação de bypass caso um mesmo `UnitCarryLoad` com proveniência habilitada seja alvo de mutadores legados (`withdraw_reserved_from_pile_to_carry_load`, `accept_delivery_from_carry_load`, `deliver_from_carry_load`).
- **Riscos residuais e pontos não protegidos na C1:**
  - GDScript não impõe encapsulamento estrito em tempo de execução: mutação deliberada e direta em variáveis privadas (como `_amounts`, `_ledger`, `_transit_claims`, `_transaction_revision`) fora das APIs cooperativas continua fora do modelo de proteção.
  - Mutações em `InMemoryStorageSource` não são elegíveis a `prepare_reserved_withdrawal` (que rejeita explicitamente com `"unsupported_storage_source"` por exigir pilhas físicas gerenciadas por `GroundPileManager`).
  - `validate_reserved_withdrawal_plan()` re-valida todo o plano de forma pura, mas em um futuro executor atômico (C2) o período entre preparação externa e aquisição das guardas deverá ser seguido de revalidação sob as guardas mantidas antes de qualquer mutação.

**T3.6.2-C1 IMPLEMENTADA COMO CANDIDATA E VALIDADA EM TESTES AUTOMATIZADOS — AGUARDANDO AUDITORIA INDEPENDENTE. SEM MERGE, SEM TAG, SEM COMMIT C2 E SEM CANCELAMENTO D3.**
