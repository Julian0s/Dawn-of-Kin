# DAWN OF KIN — T3.6.2-C4.9-R1
## Relatório Técnico da Candidata: Correção de Bypasses Internos nos Helpers de Reserva e Complementação

**Data:** 2026-11-19  
**Repositório:** `Julian0s/Dawn-of-Kin`  
**Branch:** `feat/t3-6-2-provenance-transactions`  
**Baseline inicial verificada:** `4df535b736b15ca3757034fe209e918acfc4d155`  
**`main` preservada (intocada):** `25e0a20f1d6a2f10a9e059afe69759fbe263db4a`  
**Status:** Implementado, validado automaticamente e submetido à auditoria independente (`P6` ainda **NÃO** declarada integralmente concluída).

---

## 1. Diagnóstico e Escopo

Esta correção complementar (`T3.6.2-C4.9-R1`) fecha exclusivamente os pontos de entrada internos adicionados na `C4.9` em `InMemoryStorageSource` e `GroundPileManager` que delegavam a validação de posse de escopo (`SiteCreationScope` / `ManualComplementScope`) apenas aos wrappers externos:

- Em `InMemoryStorageSource`:
  - `_apply_complement_reservation_internal()` não recebia `ManualComplementScope` nem validava `is_locked()`.
  - `_can_complement_reservation_unlocked()` ignorava `is_locked()` mesmo quando invocado fora de um `ManualComplementScope` autorizado.
- Em `GroundPileManager`:
  - `_prepare_reserve_plan_under_guard_internal()` e `_apply_prepared_entries_silent_internal()` checavam apenas flags locais (`_is_preparing_withdrawal`, `_is_mutating`, `_is_notifying`), sem validar a posse de `SiteCreationScope` ou `ManualComplementScope`.
  - `_restore_silent_checkpoint_internal()` restaurava snapshot de `_ledger` e revisões sem validar escopo, estado aplicado ou não publicação.
  - `_publish_silent_reservation_events()` emitia `reservations_changed` e `storage_changed` sem validar escopo nem transição única `_published`.

---

## 2. Reprodução RED na Baseline (`4df535b`) — Antes de Editar `src/`

A suíte adversarial [`tests/integration/test_t3_6_2_c4_9_r1_internal_helper_boundary.gd`](../../tests/integration/test_t3_6_2_c4_9_r1_internal_helper_boundary.gd) foi executada sobre a baseline inalterada `4df535b` (`1/4` aprovado, `3/4` falhos, `117` asserções, `0` `SuiteErrors`), reproduzindo todos os achados em execução:

1. **`test_01_in_memory_internal_helpers_blocked_outside_and_inside_transactions` (`13` falhas em `40` asserções):**
   - Fora de transação, `src._apply_complement_reservation_internal(site_b.reservation_id, {&"wood": 2})` elevou silenciosamente a reserva de `site_b` (`2 -> 4`) e reduziu o saldo livre (`14 -> 12`) sem emitir sinais;
   - Durante `SiteCreationScope` (`site_creator_override`), `_apply_complement_reservation_internal` voltou a alterar `site_b` (`4 -> 6`) e `_can_complement_reservation_unlocked` retornou `true` enquanto o armazenamento estava travado;
   - Durante `ManualComplementScope` (`reservations_changed`, `storage_changed`, `inventory_changed`), chamadas diretas a `_apply_complement_reservation_internal` elevaram a reserva de `site_b` sem autorização (`6 -> 12`, zerando o déficit de `site_b`).
2. **`test_02_ground_pile_apply_and_prepare_helpers_blocked_without_authorized_scope` (`6` falhas em `30` asserções):**
   - Durante `SiteCreationScope` (`site_creator_override`, onde `_is_preparing_withdrawal == true` e `_is_notifying == false`), `_prepare_reserve_plan_under_guard_internal` e `_apply_prepared_entries_silent_internal` executaram sem escopo e criaram a reserva não autorizada `&"rogue_site_res"`;
   - Durante `ManualComplementScope` no callback `state_changed` (com `_is_notifying == false`), `_apply_prepared_entries_silent_internal` alocou `2` unidades de madeira para `site_b` (`2 -> 4`).
3. **`test_03_restore_checkpoint_and_publish_events_blocked_without_authorized_scope` (`14` falhas em `25` asserções):**
   - `_restore_silent_checkpoint_internal(stale_ckpt)` apagou o `_ledger` e reverteu `get_transaction_revision()` fora de transação, dentro de `SiteCreationScope` e dentro dos callbacks de `ManualComplementScope` (revertendo a complementação recém-aplicada de `4 -> 0`);
   - `_publish_silent_reservation_events()` disparou sinais espúrios `reservations_changed` e `storage_changed` fora de transação (incrementando revisões de `inventory` e `site_a`), durante `site_creator_override` e reentrantemente dentro de `reservations_changed` / `storage_changed` (`3` emissões em vez de `1`).

---

## 3. Correções Implementadas

### 3.1 `src/economy/in_memory_storage_source.gd`
- `_can_complement_reservation_unlocked(reservation_id, extra_amounts, scope = null)`:
  - quando `scope != null`, exige `scope is ManualComplementScope`, `ReservedWithdrawalCoordinator._owns_manual_complement_scope(scope)` e `scope.storage_source == self`;
  - quando `scope == null` (caminho legado), exige `not is_locked()`.
- `_apply_complement_reservation_internal(reservation_id, extra_amounts, scope = null)`:
  - exige `scope is ManualComplementScope` válido e ativo (`_owns_manual_complement_scope(mc_scope)`), `mc_scope.storage_source == self`, `not mc_scope._complement_applied`, `not mc_scope._published`, `not is_batch_active()` e `_is_preparing_withdrawal`;
  - `complement_reservation()` público legado preserva seu funcionamento quando `not is_locked()`, executando validação, snapshot/rollback local e publicação em lote sem expor helper mutável desprotegido.
- `_restore_site_reservation_checkpoint_silent` e `_restore_manual_complement_checkpoint_silent`: passam a exigir que a reserva/complementação tenha sido aplicada (`_reservation_applied` / `_complement_applied`) e ainda não publicada (`not _published`), limpando a flag aplicada após o rollback.

### 3.2 `src/economy/ground_pile_manager.gd`
- Adicionado `_is_authorized_guard_scope(scope, expect_complement, require_applied, require_unpublished)` validando tipo exato do escopo, posse ativa em `ReservedWithdrawalCoordinator` (`_owns_site_creation_scope` ou `_owns_manual_complement_scope`), correspondência `scope.storage == self`, estado aplicado e estado não publicado.
- `_prepare_reserve_plan_under_guard_internal(reservation_id, amounts, allow_existing, scope = null)`: exige `_is_authorized_guard_scope(scope, allow_existing, false, true)`.
- `_apply_prepared_entries_silent_internal(reservation_id, entries, scope = null, expect_complement = false)`: exige `_is_authorized_guard_scope(scope, expect_complement, false, true)` e ausência de aplicação prévia no escopo, marcando `_reservation_applied = true` / `_complement_applied = true` apenas ao concluir com sucesso.
- `_restore_silent_checkpoint_internal(checkpoint, scope = null, expect_complement = false)`: exige `_is_authorized_guard_scope(scope, expect_complement, true, true)` e limpa a flag aplicada após restaurar.
- `_publish_silent_reservation_events(scope = null, expect_complement = false)`: exige `_is_authorized_guard_scope(scope, expect_complement, true, true)`, marca `_published = true` antes de despachar os sinais e impede emissões órfãs ou duplicadas.

---

## 4. Validação GREEN e Regressão Completa

1. **`.\tools\run_tests.ps1 -Filter test_t3_6_2_c4_9_r1_internal_helper_boundary -TimeoutSeconds 45`:** `1` suíte, `4/4` testes aprovados, `0` falhas, `0` `SuiteErrors`, `117` asserções, código `0` e `0` vazamentos.
2. **`git diff --check`:** código `0`.
3. **`.\tools\validate.ps1`:** `Validation PASSED (0 errors, 0 warnings, 159 scripts checked)`.
4. **`.\tools\run_tests.ps1 -Filter test_t3_6_2 -TimeoutSeconds 240`:** `22` suítes, `166/166` testes aprovados, `0` falhas, `0` `SuiteErrors`, `10.865` asserções.
5. **`.\tools\run_tests.ps1 -Segmented -GroupTimeoutSeconds 240`:**
   - `16` lotes (`unit` + `integration-01`..`integration-15`) — **TODOS APROVADOS** (incluindo `test_t3_4_1_accounting_and_complement`, `test_t3_6_2_c4_7_construction_completion_authority`, `test_t3_6_2_c4_8_site_creation_authority`, `test_t3_6_2_c4_8_r1_storage_boundary`, `test_t3_6_2_c4_9_manual_complement_authority` e `test_t3_6_2_c4_9_r1_internal_helper_boundary`);
   - **Cobertura:** `Discovered=65 | ExecutedUnique=65 | Duplicates=0 | Missing=0`;
   - **Totais:** `65` suítes, `463/463` testes aprovados, `0` falhas, `0` `SuiteErrors`, `25.652` asserções, `0` erros/avisos da Godot.

---

## 5. Commits Produzidos

- **Produção (`SHA1`):** `fe18c344409733d5b018fc4d08269da8aeb485d3` — `fix(t3.6.2-c4.9-r1): require scope ownership on internal storage helpers`
- **Testes (`SHA2`):** `7a4d67d3f53ba81d876ad4953cb19b830e1e34ad` — `test(t3.6.2-c4.9-r1): verify internal helper authorization boundaries`

---

## 6. Riscos Residuais e Limites de Escopo (`P6` ainda parcial)

- Nenhum helper interno de reserva silenciosa, restauração de snapshot ou publicação pós-commit em `InMemoryStorageSource` ou `GroundPileManager` permanece invocável sem a posse verificada do escopo ativo correspondente (`SiteCreationScope` ou `ManualComplementScope`).
- Permanecem fora do escopo desta etapa (não implementados): fronteira regional completa de `ConstructionSite.contribute_work`, fechamento de mutadores públicos remanescentes fora dos coordenadores (`UnitCarryLoad.add_with_provenance`, `ResourceSource.extract`, mutadores diretos de armazenamento fora de transações protegidas em modo proveniência), `D3` (cancelamento/custódia), `P2`, `P4`, ativação global de proveniência e `C4.10`.
