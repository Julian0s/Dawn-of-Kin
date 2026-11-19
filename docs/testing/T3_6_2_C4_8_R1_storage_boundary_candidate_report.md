# Dawn of Kin — Relatório Técnico da Candidata T3.6.2-C4.8-R1
## Auditoria corretiva da fronteira de armazenamento na criação de canteiros

- **Data:** 19/11/2026
- **Engine:** Godot 4.7.2 (`Godot_v4.7.2-stable_win64.exe`)
- **Escopo autorizado:** Correção complementar exclusiva da C4.8 (**Problema A:** fechamento dos mutadores públicos diretos de `InMemoryStorageSource` e lote herdados durante `SiteCreationScope`; **Problema B:** recusa fail-closed de implementações desconhecidas de `SettlementStorageSource` em `ConstructionManager.try_create_site_from_placement()`), sem iniciar `C4.9`, sem implementar `D3`/`P2`/`P4`/restante de `P6`, e sem alterações na `main`.
- **Parecer objetivo:** **CANDIDATA C4.8-R1 PRONTA PARA AUDITORIA** (`4/4` testes corretivos em GREEN com `194` asserções, `157/157` testes T3.6.2 e `454/454` testes segmentados em `63/63` suítes com `0` falhas e `0` erros/avisos; **P6 NÃO está integralmente concluída**).

---

## 1. Baseline Git

- **Repositório:** `Julian0s/Dawn-of-Kin`
- **Worktree:** `C:\Projetos\Dawn_of_Kin_wt_t3_4_5`
- **Branch:** `feat/t3-6-2-provenance-transactions`
- **HEAD inicial verificado:** `79ae274c070ef81e70b4e6108eaf99632a83160f` (`0` ahead / `0` behind `origin/feat/t3-6-2-provenance-transactions`, árvore limpa)
- **`main` de referência (intocada):** `25e0a20f1d6a2f10a9e059afe69759fbe263db4a`
- **Referência histórica R2:** `docs/architecture/T3_6_cancellation_architecture_R2_PROPOSAL.md` segue apenas no commit histórico divergente `69c13275a34a30564ac839ec920f83ef36590812` (não mesclada à branch atual, consultada apenas como referência junto a `AGENTS.md`, `docs/Dawn_of_Kin_GDD.md`, `docs/architecture/T3_architecture_PROPOSAL.md` e relatório C4.8).
- **Commits publicados desta candidata (anteriores a este relatório):**
  - `02df1ce2c221f8394487cf87c3bd85b79184c42f` — `fix(t3.6.2-c4.8-r1): lock InMemoryStorageSource mutators during SiteCreationScope and fail closed on unknown storage backends`
  - `42d3a6d9df98a355a522e0746c83ea388f00a259` — `test(t3.6.2-c4.8-r1): add adversarial and regression suite for direct storage mutators and unknown backends`

---

## 2. Análise dos mutadores diretos (`InMemoryStorageSource` e `SettlementInventory`)

No baseline `79ae274`, `ReservedWithdrawalCoordinator._acquire_site_creation_scope` marcava `inventory._is_delivering = true` (bloqueando `SettlementInventory.*`), mas apenas setava `_is_preparing_withdrawal = true` quando `storage_source is GroundPileManager`, deixando `InMemoryStorageSource` completamente exposto a chamadas diretas durante toda a janela da `SiteCreationScope` (e também `SettlementInventory.set_storage_source()` sem checar `_is_delivering` ou `InMemoryStorageSource`):

| Superfície auditada | Baseline `79ae274` | Exposição encontrada |
| --- | --- | --- |
| `InMemoryStorageSource.deposit` / `withdraw` | Sem guarda de transação | Alterava `_amounts` e emitia `storage_changed` em plena criação/rollback. |
| `InMemoryStorageSource.reserve_batch` | Sem guarda de transação | Permitia criar reservas concorrentes (`rogue_*`) antes do commit/rollback. |
| `InMemoryStorageSource.complement_reservation` | Sem guarda de transação | Permitia complementar reservas de obras irmãs durante criação/sinais. |
| `InMemoryStorageSource.release_batch` | Sem guarda de transação | Permitia apagar a reserva recém-alocada (antes da árvore ou pós-commit) ou reservas irmãs. |
| `InMemoryStorageSource.withdraw_reserved` | Sem guarda de transação | Permitia drenar recursos reservados recém-alocados ou de obras irmãs diretamente no backend. |
| `InMemoryStorageSource.record_intentional_decay` | Sem guarda de transação | Permitia reduzir saldos, perder reservas e emitir `reservation_lost_to_decay` sob escopo ativo. |
| Herdados de `SettlementStorageSource` (`begin_batch`, `end_batch`, `deposit_batch`, `withdraw_batch`, `withdraw_reserved_batch`) | Sem override de trava em `InMemoryStorageSource` | `begin_batch()`/operadores em lote alteravam `_batch_depth` (podendo suprimir/atrasar `_publish_site_reservation_committed`) e executavam mutações diretas em lote. |
| `SettlementInventory.set_storage_source` | Checava apenas `GroundPileManager._is_preparing_withdrawal` | Não verificava `_is_delivering` nem `InMemoryStorageSource` travado, permitindo troca de backend durante transação `InMemory`. |

Adicionalmente, caso um callback durante uma falha pré-commit (como `site_creator_override`) executasse uma mutação direta legítima em `InMemoryStorageSource` antes de retornar erro, `_restore_site_reservation_checkpoint_silent` restauraria o snapshot inicial e sobrescreveria essa alteração — condição eliminada ao impedir toda mutação pública direta enquanto a `SiteCreationScope` está ativa.

---

## 3. Reprodução RED

Executada a suíte corretiva `tests/integration/test_t3_6_2_c4_8_r1_storage_boundary.gd` contra o baseline `79ae274c070ef81e70b4e6108eaf99632a83160f` antes de qualquer alteração em `src/`:

- **Comando:** `.\tools\run_tests.ps1 -Filter test_t3_6_2_c4_8_r1_storage_boundary -TimeoutSeconds 45`
- **Exit code:** `1`
- **Resultado:** `Suites: 1 | Tests: 4 | Passed: 0 | Failed: 4 | SuiteErrors: 0 | Assertions: 177 | Elapsed: 6883.2 ms` (zero erros de script/fixture).

Achados concretos do RED:
1. **`test_01` (`54` falhas / `87` asserções):** nos callbacks `site_creator_override`, `child_entered_tree`, `reservations_changed` e `storage_changed`, chamadas diretas a `deposit`, `withdraw`, `reserve_batch`, `complement_reservation`, `withdraw_reserved` (antes de `release_batch`), `release_batch`, `record_intentional_decay`, `deposit_batch`, `withdraw_batch` e `begin_batch` executaram sem bloqueio; a própria reserva do canteiro novo foi apagada ainda dentro de `site_creator_override`, abortando a criação com `"site_instantiation_failed"`, deixando saldo final divergente (`reserved_wood=2`, `reserved_stone=1`, `available_wood=10`, `decayed=4`) e `46` emissões de sinal não autorizadas (`src_res`/`src_chg`). (No baseline, `forged_scope_ok` em `_apply_site_reservation_silent` já era bloqueado pelo `_owns_site_creation_scope` da C4.8).
2. **`test_02` (`30` falhas / `50` asserções):** durante falhas provocadas (`site_creator_override -> null` e `FailingConfigureSite`), chamadas diretas em `mem_source` (`deposit`, `withdraw`, `reserve_batch`, `complement_reservation`, `withdraw_reserved`, `withdraw_reserved_batch`, `release_batch`, `deposit_batch`, `withdraw_batch`, `begin_batch`, `record_intentional_decay`) executaram durante os dois ciclos de rollback, emitindo `76` sinais intermediários (`inv_chg`, `src_chg`, `inv_res`, `src_res`) e elevando revisões (`src`: `5 -> 43`; `inv`: `1 -> 15`).
3. **`test_03` (`14` falhas / `20` asserções):** `CustomUnsupportedStorageSource` (subclasse arbitrária de `SettlementStorageSource`) foi aceita pelo fallback em vez de recusar fail-closed: retornou `ok = true`, executou `begin_batch_calls = 1`, `end_batch_calls = 1`, `reserve_batch_calls = 1`, criou o canteiro, avançou `_next_site_seq` (`1 -> 2`), alterou revisões e emitiu `5` sinais (`inv_chg`, `src_chg`, `inv_res`, `src_res`, `site_created`).
4. **`test_04` (`1` falha / `20` asserções):** controle de regressão (`GroundPileManager`, isolamento multi-regional no mesmo `World3D` e conclusão `P6-A`) passou integralmente nos `19` pontos pré-existentes desde o baseline, falhando exclusivamente em `mem_src.has_method("is_locked")` (ainda inexistente no baseline).

---

## 4. Solução aplicada (Problema A)

1. **`src/economy/in_memory_storage_source.gd` (`+56 / -9`):**
   - Adicionado `var _is_preparing_withdrawal: bool = false` (sem setter público) e `func is_locked() -> bool`, retornando `_is_preparing_withdrawal or ReservedWithdrawalCoordinator._has_active_site_creation_for_storage(null, self)`.
   - Guardados todos os mutadores públicos e controles de lote com `if is_locked():`:
     - `begin_batch()`, `end_batch(discard_dirty)` (no-op sob trava, espelhando `GroundPileManager`);
     - `deposit`, `deposit_batch`, `withdraw`, `withdraw_batch`, `can_reserve_batch`, `reserve_batch`, `can_complement_reservation`, `complement_reservation`, `release_batch`, `withdraw_reserved`, `withdraw_reserved_batch` (retornando `false`);
     - `record_intentional_decay` (retornando `0`).
   - `_apply_site_reservation_silent` usa `super.can_reserve_batch(...)` sob validação estrita de posse (`_owns_site_creation_scope(scope)`, `scope.storage_source == self`, `_is_preparing_withdrawal`, `not is_batch_active()`, `not scope._reservation_applied`), marcando `scope._reservation_applied = true`.
   - `_publish_site_reservation_committed` exige `scope._reservation_applied and not scope._published`, marca `scope._published = true` e dispara `_dispatch_reservations_changed()` / `_dispatch_storage_changed()` enquanto `is_locked()` continua `true` (protegendo também observadores desses sinais).
2. **`src/economy/reserved_withdrawal_coordinator.gd` (`+16 / -0`):**
   - Adicionados `_reservation_applied: bool = false` e `_published: bool = false` em `SiteCreationScope` (uso único do escopo em criação/publicação).
   - `_owns_site_creation_scope(scope)` exige `(scope.storage_source as InMemoryStorageSource)._is_preparing_withdrawal == true` quando `storage_source is InMemoryStorageSource`.
   - `_acquire_site_creation_scope` valida `mem_storage.is_locked() or mem_storage.is_batch_active()`, seta `mem_storage._is_preparing_withdrawal = true`, e `_release_site_creation_scope` libera `mem_storage._is_preparing_withdrawal = false` em todos os caminhos de sucesso ou falha.
3. **`src/economy/ground_pile_manager.gd` (`+5 / -1`):**
   - Simetria de uso único via `scope._reservation_applied` e `scope._published` em `_apply_prepared_site_reservation_silent` e `_publish_site_reservation_committed`.
4. **`src/economy/settlement_inventory.gd` (`+8 / -2`):**
   - `is_transaction_busy()` passou a reconhecer `InMemoryStorageSource.is_locked()`; `set_storage_source()` bloqueia troca de fonte quando `_is_delivering` está ativo ou quando `_is_coordinator_storage` detecta `GroundPileManager._is_preparing_withdrawal` ou `InMemoryStorageSource.is_locked()`.

---

## 5. Tratamento de backends desconhecidos (Problema B)

Auditoria do contrato real de `SettlementStorageSource` (`src/economy/settlement_storage_source.gd`):
- Na classe-base, `reserve_batch()`, `complement_reservation()`, `release_batch()`, `withdraw_reserved()` retornam `false`, `_create_rollback_snapshot()` retorna `null` e `_restore_rollback_snapshot()` é no-op.
- Mesmo que uma subclasse implemente `reserve_batch`/`release_batch`, `begin_batch()`/`end_batch()` não garantem rollback atômico de falhas parciais, restauração de revisões, supressão de sinais intermediários fora do batch nem trava contra mutadores diretos durante a criação.

Correção fail-closed aplicada:
- **`ReservedWithdrawalCoordinator._acquire_site_creation_scope`:** logo após validar `storage_source != null`, se `not (storage_source is GroundPileManager) and not (storage_source is InMemoryStorageSource)`, retorna `{"ok": false, "busy": false, "reason": "unsupported_storage_source"}` antes de adquirir qualquer guarda, criar `SiteCreationScope` ou mutar `RegionalAuthority`.
- **`ConstructionManager.try_create_site_from_placement` (`+8 / -18`):** removido inteiramente o ramo `reserved_via_fallback`; rejeições por `"unsupported_storage_source"` retornam `_reject("unsupported_storage_source", "Armazenamento não suportado para criação transacional de canteiro.", definition, world_position)` antes de alocar IDs, consumir `_next_site_seq` ou instanciar `ConstructionSite` (mantendo também ramo `else:` fail-closed defensivo no bloco de reserva).

---

## 6. Preservação do rollback e isolamento de sinais

- Durante sucesso:
  - Reserva silenciosa -> criação/configuração/entrada do nó -> commit (`_sites.append`, sinal `state_changed`, revisão do inventário) -> `_publish_site_reservation_committed` (`reservations_changed`, `storage_changed`/`inventory_changed`) -> `site_created` -> `_finish_site_creation_guards(scope)`.
  - Observadores em todos os 5 pontos (`site_creator_override`, `child_entered_tree`, `reservations_changed`, `storage_changed`, `site_created`) encontram todas as mutações diretas em `InMemoryStorageSource` e `SettlementInventory` bloqueadas, evitando loops de sinal ou adulteração de reserva.
  - Após o retorno, `is_locked() == false` e o acesso direto a `InMemoryStorageSource` volta a funcionar integralmente.
- Durante falha (`override -> null`, `FailingConfigureSite`, pós-árvore):
  - Como toda mutação direta é barrada enquanto `SiteCreationScope` está ativa, o rollback restaura o snapshot inicial sem nunca sobrescrever mutação externa ocorrida durante a transação, mantendo `0` sinais intermediários, `0` reservas órfãs, revisões intactas e todas as travas liberadas.

---

## 7. Testes GREEN (`test_t3_6_2_c4_8_r1_storage_boundary.gd`)

Execução da suíte corretiva após a edição final:
- **Comando:** `.\tools\run_tests.ps1 -Filter test_t3_6_2 -TimeoutSeconds 240` (suíte `test_t3_6_2_c4_8_r1_storage_boundary.gd` executada dentro do conjunto pós-edição final) e `.\tools\run_tests.ps1 -Segmented -GroupTimeoutSeconds 240`:
  - `test_01_direct_in_memory_mutators_blocked_across_all_5_creation_callbacks`: **PASS** (`104` asserções)
  - `test_02_in_memory_failure_rollback_blocks_direct_tamper_and_emits_zero_signals`: **PASS** (`50` asserções)
  - `test_03_unknown_storage_source_fails_closed_before_any_mutation`: **PASS** (`20` asserções)
  - `test_04_regression_ground_pile_multiregion_and_p6a_completion_intact`: **PASS** (`20` asserções)
  - **Total da suíte:** `tests=4 | passed=4 | failed=0 | assertions=194` (`elapsed_ms=136.7` no filtro T3.6.2; `202.0` no lote segmentado).

---

## 8. Regressão completa após edição final

| Comando | Exit | Resultado observado |
| --- | --- | --- |
| `git diff --check` | `0` | Zero problemas de formatação/espaço em branco. |
| `.\tools\validate.ps1` | `0` | **`Validation PASSED (0 errors, 0 warnings, 157 scripts checked)`**. |
| `.\tools\run_tests.ps1 -Filter test_t3_6_2 -TimeoutSeconds 240` | `0` | **`Suites: 20 \| Tests: 157 \| Passed: 157 \| Failed: 0 \| SuiteErrors: 0 \| Assertions: 10570 \| Elapsed: 110730.3 ms`** (inclui `c4_8_r1`: `4/4 PASS, 194 assertions`; `c4_8`: `5/5 PASS, 220 assertions`; `c4_7`: `4/4 PASS, 151 assertions`). |
| `.\tools\run_tests.ps1 -Segmented -GroupTimeoutSeconds 240` | `0` | **`Batches: 15`** (`unit` + `integration-01`..`14`), **`Suites: 63 \| Tests: 454 \| Passed: 454 \| Failed: 0 \| SuiteErrors: 0 \| Assertions: 25356 \| SumGodotElapsed: 610784,3 ms \| TotalWallElapsed: 633302,1 ms`**, **`Coverage Check: Discovered=63 \| ExecutedUnique=63 \| Duplicates=0 \| Missing=0`**, `0` erros/avisos Godot. |

Destaques de regressão verificados dentro da execução segmentada final:
- `test_t2_economy.gd`: `17/17 PASS, 210 assertions`
- `test_t3_1_reservations.gd`: `17/17 PASS, 432 assertions`
- `test_t3_3_construction_site.gd`: `7/7 PASS, 164 assertions`
- `test_t3_4_4_building_completion.gd`: `9/9 PASS, 1355 assertions`
- `test_t3_4_5_navigation_bake.gd`: `9/9 PASS, 2305 assertions`

---

## 9. Riscos restantes

- **Escopo restante de P6 (P6 ainda NÃO concluída integralmente):** continuam pendentes para incrementos futuros de P6 a integração regional completa de `ConstructionSite.contribute_work` e `ConstructionSite.authorize_manual_complement`, bem como o fechamento de bypasses públicos remanescentes fora dos coordenadores (`UnitCarryLoad.add_with_provenance`, `ResourceSource.extract`, mutadores diretos de armazenamento/estoque fora da criação de canteiros em modo proveniência).
- **Risco residual herdado da C4.7:** `ConstructionManager._execute_site_completion()` não verifica explicitamente o retorno booleano de `_commit_completed_building_under_guard()` (inalterado fora do escopo desta corretiva).
- **Observação de subclasse de `InMemoryStorageSource`:** subclasses de teste de `InMemoryStorageSource` herdando o comportamento padrão continuam protegidas por `is_locked()`; se alguma subclasse externa sobrescrever um mutador público sem chamar `super` nem consultar `is_locked()`, ela depende de obedecer ao contrato `is_locked()` da superclasse (não existe framework genérico nesta etapa, conforme restrição §5).
- **Cobertura exclusivamente headless:** validação integralmente automatizada (`157` scripts + `63/63` suítes); sem alteração visual e sem ativação de `use_provenance_transactions` no RTS normal.

---

## 10. Parecer técnico

**CANDIDATA C4.8-R1 PRONTA PARA AUDITORIA.**

- Os dois apontamentos da auditoria da C4.8 (**Problema A:** mutadores diretos de `InMemoryStorageSource` e troca via `set_storage_source`; **Problema B:** fallback inseguro para `SettlementStorageSource` desconhecido) foram reproduzidos em RED (`4/4` falhas, `177` asserções sem erros de script), corrigidos cirurgicamente (`02df1ce`) e validados com `454/454` testes aprovados em `63/63` suítes (`25.356` asserções, `0` erros/avisos).
- **P6 permanece parcialmente aberta** (`P6-A` + `P6-B1` endurecida), **sem** alterações na `main`, **sem** criação de tags, **sem** homologação da T3.6.2 e **sem** avanço para `C4.9`, aguardando nova auditoria independente do ChatGPT.
