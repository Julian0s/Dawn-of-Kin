# DAWN OF KIN — T3.6.2-C4.9 / P6-B2
## Relatório Técnico da Candidata: Integridade Regional da Complementação Manual de Materiais

**Data:** 2026-11-19  
**Repositório:** `Julian0s/Dawn-of-Kin`  
**Branch:** `feat/t3-6-2-provenance-transactions`  
**Baseline inicial verificada:** `30a17c3d7bba8be94ece336863e55a5e89541495`  
**`main` preservada (intocada):** `25e0a20f1d6a2f10a9e059afe69759fbe263db4a`  
**Status:** Implementado, validado automaticamente e submetido à auditoria independente antes de qualquer avanço para etapas posteriores (`P6` ainda **NÃO** declarada integralmente concluída).

---

## 1. Escopo e Conformidade Normativa

Este incremento executou exclusivamente **T3.6.2-C4.9 / P6-B2**: auditoria e proteção regional de `ConstructionSite.authorize_manual_complement()` e de sua reserva econômica sob a fronteira `(World3D, region_id)` e armazenamento associado (`GroundPileManager` / `InMemoryStorageSource`).

Regras e decisões preservadas integralmente:
- **`DEC-11B`:** complementação de reserva deteriorada/liberada exige autorização explícita via `ManualComplementIntent` single-use, saldo livre real e transporte físico subsequente (`delivered_buffer` e `consumed` inalterados pelo ato de complementar); nenhuma realocação automática silenciosa.
- **Compatibilidade legada:** fluxos sem proveniência e testes unitários/de integração que não materializam `RegionalAuthority` continuam executando sem criação espúria de metadados `DOMAIN_META` no `World3D`.
- **Exclusões respeitadas:** nenhuma implementação de `ConstructionSite.contribute_work` regional, fechamento global de `P6`, cancelamento D3, custódia, `P2`, `P4`, `JobSystem`, ativação global de proveniência ou merge em `main`.

---

## 2. Defeitos Reproduzidos na Baseline (`30a17c3`) — Evidência RED

Antes de editar qualquer arquivo de produção em `src/`, a suíte adversarial [`tests/integration/test_t3_6_2_c4_9_manual_complement_authority.gd`](../../tests/integration/test_t3_6_2_c4_9_manual_complement_authority.gd) foi executada sobre `30a17c3` (`0/5` testes aprovados, `5` falhos, `174` asserções, `0` `SuiteErrors`), reproduzindo os desvios reais:

1. **Ausência de serialização regional em `authorize_manual_complement()`:** não consultava `RegionalAuthority`, escopos regionais ativos, `_work_transaction_in_progress`, bloqueio de `CampStorageZone`, `storage.is_batch_active()`, nem canteiros irmãos no mesmo domínio `(World3D, region_id)`.
2. **Reentrância durante sinais e exposição de mutadores diretos:** durante os callbacks pós-commit (`reservations_changed`, `storage_changed`, `inventory_changed`, `state_changed`), `is_region_transaction_active_readonly` retornava `false`, `inspect_domain_for_worker_removal_readonly` retornava `ok = true`, canteiros irmãos permaneciam com `is_transaction_busy() == false`, e em `InMemoryStorageSource` (`is_locked() == false`) chamadas reentrantes a `deposit`, `withdraw`, `complement_reservation`, `release_batch`, `record_intentional_decay`, `authorize_manual_complement` em canteiro irmão e `try_create_site_from_placement` executavam e corrompiam saldos.
3. **Ausência de fail-closed em backends desconhecidos e domínios ambíguos:** implementações desconhecidas de `SettlementStorageSource` tinham `can_complement_reservation` e `complement_reservation` invocadas normalmente; vínculos divergentes (`_withdrawal_world`/`_withdrawal_region`) também não falhavam fechado com `"ambiguous_domain"`.
4. **Deriva espúria de `_transaction_revision`:** `ConstructionSite.authorize_manual_complement` incrementava `_transaction_revision += 1` logo após `intent.consumed = true`, causando drift de revisão em tentativas recusadas (`insufficient_free_stock`, conflitos) e em no-op (`nothing_missing`).

---

## 3. Alterações Implementadas

### 3.1 `src/economy/reserved_withdrawal_coordinator.gd`
- Adicionada `ManualComplementScope`, `RegionalAuthority.active_manual_complement`, `RegionalAuthority.has_active_operation()` e lista estática `_active_manual_complement_scopes`.
- Implementado `_inspect_manual_complement_preconditions_readonly(site)` (compartilhado por `can_authorize_manual_complement` e `_acquire_manual_complement_scope`, sem efeitos colaterais nem materialização de `RegionalAuthority`):
  - valida thread principal, estado ativo do canteiro, `(World3D, SceneTree, region_id)` e suporte explícito de backend (`GroundPileManager` ou `InMemoryStorageSource`, falhando fechado com `"unsupported_storage_source"` caso contrário);
  - coleta deterministicamente canteiros do domínio ou que compartilhem inventário/armazenamento, impondo correspondência de `World3D` e armazenamento (e, quando `authority != null`, correspondência estrita de domínio e `_matches_economic_domain`), além de checar `_piles_root`, `_withdrawal_world`/`_withdrawal_region` e ausência de `RegionalAuthority` conflitante;
  - verifica concorrência em `site`, canteiros irmãos, `inventory`, `storage_source`, `camp_zone`, `RegionalAuthority` e escopos ativos (`SiteCreationScope`, `ManualComplementScope`).
- Implementados `_acquire_manual_complement_scope`, `_owns_manual_complement_scope`, `_release_manual_complement_scope`, `_has_active_manual_complement_in_domain` e `_has_active_manual_complement_for_storage`.
- Integrada exclusão mútua simétrica em `_owns_delivery_scope`, `_owns_camp_delivery_scope`, `_owns_completion_scope`, `_acquire_completion_scope`, `_owns_site_creation_scope`, `_acquire_site_creation_scope`, `is_region_transaction_active_readonly`, `inspect_domain_for_worker_removal_readonly`, `release_regional_domain` e `_execute_core`.

### 3.2 `src/economy/selective_site_delivery_coordinator.gd` e `src/economy/selective_camp_delivery_coordinator.gd`
- Atualizadas as guardas de entrada de `_execute` para recusar com `"busy"` quando houver `ManualComplementScope` ativo no domínio `(World3D, region_id)` ou para o mesmo `(inventory, storage)`.

### 3.3 `src/economy/ground_pile_manager.gd`
- Extraídos helpers internos compartilhados (`_prepare_reserve_plan_under_guard_internal`, `_apply_prepared_entries_silent_internal`, `_restore_silent_checkpoint_internal`, `_publish_silent_reservation_events`) para evitar duplicação entre `SiteCreationScope` e `ManualComplementScope`.
- Adicionados `_prepare_manual_complement_under_guard` (`allow_existing = true`), `_apply_prepared_manual_complement_silent`, `_restore_manual_complement_checkpoint_silent` e `_publish_manual_complement_committed`.

### 3.4 `src/economy/in_memory_storage_source.gd`
- Atualizado `is_locked()` para incluir `ReservedWithdrawalCoordinator._has_active_manual_complement_for_storage(null, self)`.
- Extraídos `_can_complement_reservation_unlocked` e `_apply_complement_reservation_internal`, reutilizados por `can_complement_reservation`, `complement_reservation` e pelos novos métodos de guarda `_prepare_manual_complement_under_guard`, `_apply_manual_complement_silent`, `_restore_manual_complement_checkpoint_silent` e `_publish_manual_complement_committed`.

### 3.5 `src/buildings/construction_site.gd`
- `can_authorize_manual_complement`: consulta `_inspect_manual_complement_preconditions_readonly(self)` antes de `_plan_manual_complement_internal(..., null)`.
- `authorize_manual_complement`:
  - preserva rejeição de ticket inválido (`"unauthorized_or_missing_intent"`, sem consumir ticket de outro canteiro) e consumo single-use imediato após validação estrutural (incluindo `_is_complementing` / `_is_preparing_or_transacting` / `_work_transaction_in_progress` / `busy` / estoque insuficiente);
  - elimina qualquer incremento de `_transaction_revision` em falhas, bloqueios ou `nothing_missing`;
  - adquire `ManualComplementScope`, planeja e aplica a reserva silenciosamente com checkpoint e validação pós-mutação (`verify_accounting_invariant()` + `_owns_manual_complement_scope(scope)`), executando rollback silencioso em falha, incrementando `_transaction_revision` de canteiro e inventário apenas no commit confirmado e publicando sinais com todas as travas regionais ainda ativas antes de liberar via `_finish_manual_complement_guards`.

---

## 4. Validação Automática Executada (Após o Último Edit)

1. **`git diff --check`:** encerrado com código `0` (sem erros de formatação/conflito).
2. **`.\tools\validate.ps1`:** `Validation PASSED (0 errors, 0 warnings, 158 scripts checked)`.
3. **`.\tools\run_tests.ps1 -Filter test_t3_6_2 -TimeoutSeconds 240`:** `21` suítes, `162/162` testes aprovados, `0` falhas, `0` `SuiteErrors`, `10.748` asserções.
4. **`.\tools\run_tests.ps1 -Segmented -GroupTimeoutSeconds 240`:**
   - `16` lotes (`unit` + `integration-01`..`integration-15`) — **TODOS APROVADOS**;
   - **Cobertura:** `Discovered=64 | ExecutedUnique=64 | Duplicates=0 | Missing=0`;
   - **Totais:** `64` suítes, `459/459` testes aprovados, `0` falhas, `0` `SuiteErrors`, `25.515` asserções, `0` erros/avisos da engine Godot.

---

## 5. Commits Produzidos

- **Produção:** `0d5a72c0bcd2f7111f8bd5b08519e7433b1ba65f` — `fix(t3.6.2-c4.9): serialize manual complement under regional authority`
- **Teste adversarial/regressão:** `f547088c363f4ff810484e92c1b5a79a1fd9865c` — `test(t3.6.2-c4.9): verify manual complement authority and reentrancy`

---

## 6. Limites Conhecidos e Pendências Reais (`P6` ainda parcial)

- A validação executada nesta candidata foi inteiramente automatizada headless (`validate.ps1`, `-Filter test_t3_6_2` e `-Segmented`); inspeção visual interativa no editor não foi reexecutada neste incremento (nenhum fluxo visual de HUD/cena foi alterado, e `BuildingInspectorPanel` apenas consome `can_authorize_manual_complement` / `authorize_manual_complement`).
- **Pendências explícitas de `P6` fora do escopo da C4.9 (NÃO implementadas):**
  - Fronteira regional completa de `ConstructionSite.contribute_work`;
  - Fechamento de mutadores públicos remanescentes fora dos coordenadores (`UnitCarryLoad.add_with_provenance`, `ResourceSource.extract`, mutadores diretos de armazenamento/inventário fora de `SiteCreationScope` / `ManualComplementScope` em modo proveniência);
  - Etapas posteriores (`D3` cancelamento/custódia, `P2`, `P4`, ativação global de proveniência).
