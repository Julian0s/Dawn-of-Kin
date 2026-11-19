# Dawn of Kin — Relatório Técnico da Candidata T3.6.2-C4.7
## P6-A — Fronteira transacional regional da conclusão de construções

- **Data:** 19/11/2026
- **Engine:** Godot 4.7.2 (`Godot_v4.7.2-stable_win64.exe`)
- **Escopo autorizado:** Exclusivamente **P6-A** — proteger a conclusão de canteiros (`ConstructionManager` / `ConstructionSite`) contra execução concorrente ou reentrante de transações na mesma autoridade econômica `(World3D, region_id)` e contra inconsistências de posicionamento/estado durante callbacks de conclusão, sem ativar proveniência no fluxo RTS normal nem implementar o restante de `P6`, `P2`, `P4`, `D-INT-01/02/03` ou cancelamento `D3`.
- **Parecer objetivo:** **CANDIDATA C4.7 PRONTA PARA AUDITORIA** (reprodução `RED` confirmada em `4/4` testes no baseline `d31f6be`; correções validadas em `4/4` testes focados, `148/148` testes T3.6.2 e `445/445` testes segmentados em `61/61` suítes com `0` falhas e `0` erros/avisos; **não** declarada homologação formal do proprietário).

---

## 1. Baseline Git e commits publicados

- **Repositório:** `Julian0s/Dawn-of-Kin`
- **Worktree:** `C:\Projetos\Dawn_of_Kin_wt_t3_4_5`
- **Branch:** `feat/t3-6-2-provenance-transactions`
- **HEAD inicial verificado:** `d31f6be2ff3e3de01c6548da84a0b252542a952e` (`0` ahead / `0` behind `origin/feat/t3-6-2-provenance-transactions`, árvore limpa)
- **`main` de referência (intocada):** `25e0a20f1d6a2f10a9e059afe69759fbe263db4a`
- **Commits publicados desta candidata (anteriores a este relatório):**
  - `6abb4383aef013d7bf62a4e515e8f4c135c6f64c` — `feat(t3.6.2): protect construction site completion with regional authority (P6-A)` (`src/buildings/construction_manager.gd`, `src/buildings/construction_site.gd`, `src/economy/reserved_withdrawal_coordinator.gd`)
  - `aa546b14da21dc8b569a2a4e0e8bde93540cacb7` — `test(t3.6.2-c4.7): add focused integration suite for construction completion regional authority (P6-A)` (`tests/integration/test_t3_6_2_c4_7_construction_completion_authority.gd` e `.uid`)

---

## 2. Divergência documental R2 registrada

Verificação direta em `docs/architecture/` na HEAD atual (`d31f6be2ff3e3de01c6548da84a0b252542a952e`):

- Os arquivos presentes em `docs/architecture/` na branch atual são **exclusivamente**:
  - `docs/architecture/T1_architecture.md`
  - `docs/architecture/T2_architecture_DRAFT.md`
  - `docs/architecture/T3_architecture_PROPOSAL.md`
- Nem `docs/architecture/T3_6_cancellation_architecture_PROPOSAL.md` nem `docs/architecture/T3_6_cancellation_architecture_R2_PROPOSAL.md` existem em `docs/architecture/` na HEAD atual da branch `feat/t3-6-2-provenance-transactions`.
- O documento `docs/architecture/T3_6_cancellation_architecture_R2_PROPOSAL.md` reside no commit histórico `69c13275a34a30564ac839ec920f83ef36590812`, com ancestral comum `git merge-base HEAD 69c13275a34a30564ac839ec920f83ef36590812` igual a `fb31887e9ee6671d81a6797ea0d921c6d8b7a979` (histórico não mesclado à branch atual).
- O conteúdo desse commit histórico foi inspecionado via `git show` apenas como referência arquitetural (especialmente a §4 "Conclusão concorrente"), confrontado com `AGENTS.md`, `docs/architecture/T3_architecture_PROPOSAL.md` e o código-fonte vigente, sem presumir integração desse arquivo à branch e sem incorporá-lo fora do escopo autorizado.

---

## 3. Causa raiz do gap P6-A e evidência RED

Antes de qualquer alteração em `src/`, a suíte `tests/integration/test_t3_6_2_c4_7_construction_completion_authority.gd` foi executada contra o baseline `d31f6be2ff3e3de01c6548da84a0b252542a952e`:

- **Comando RED:** `.\tools\run_tests.ps1 -Filter test_t3_6_2_c4_7_construction_completion_authority`
- **Exit code:** `1`
- **Resultado:** `Suites: 1 | Tests: 4 | Passed: 0 | Failed: 4 | SuiteErrors: 0 | Assertions: 140 | Elapsed: 12106.6 ms`

### Defeitos reproduzidos no baseline

1. **Conclusão ignorando autoridade regional ativa (`test_01`):** `ConstructionManager.complete_site_transaction` e `_complete_queued_site` checavam apenas `_completion_in_progress` e `not site._is_preparing_or_transacting`. Se outra transação estivesse ativa na mesma `(World3D, region_id)` (por exemplo, entrega de acampamento de um trabalhador enquanto outro canteiro já estava `COMPLETING`), a conclusão era disparada no meio da transação ativa e ainda disparava `site_completed` / `_finish_succeeded()`. Além disso, o disparo diferido via `_on_site_state_changed` não possuía reagendamento para `busy` transitório sem contabilizar erro.
2. **Reentrância e bypass durante callbacks de conclusão (`test_02`):** durante `building_creator_override`, `child_entered_tree` (antes de a edificação estar devidamente posicionada), `building_blocker_added` e `site_completed`, a `RegionalAuthority` permanecia livre (`is_executing == false`, `active_completion == null`), `storage`, `inventory` e canteiros irmãos não estavam travados, e era possível disparar transações econômicas (`execute_reserved_withdrawal`, entregas seletivas), chamadas diretas a `site.commit_completed_building(...)` / `site.record_completion_failure(...)` ou segunda conclusão concorrente sobre `ConstructionSite`.
3. **Obras irmãs no domínio e isolamento entre regiões (`test_03`):** canteiros irmãos ativos (`_is_preparing_or_transacting == true`) no mesmo domínio não bloqueavam a conclusão, e `retry_failed_site_completion` não consultava `is_region_transaction_active_readonly`.
4. **Posicionamento na árvore, preservação de contador de falhas em `busy` e limpeza pós-falha (`test_04`):** `building` entrava em `_buildings_root.add_child(building)` antes de receber `transform`, expondo nó não posicionado em `child_entered_tree`; quando `building` falhava na validação após entrar na árvore, a revalidação de identidade/geração/conflito de edificação era limitada e `_apply_completed_building` só desconectava `_unbind_inventory()` / `_clear_all_transit_listeners()` após `site_completed.emit()`.

---

## 4. Arquitetura P6-A adotada e contratos regionais

Em `src/economy/reserved_withdrawal_coordinator.gd`:

- Adicionada a capacidade interna `CompletionScope` (`world`, `region_id`, `manager`, `site`, `inventory`, `sites`, `authority`).
- Adicionado o campo `active_completion: CompletionScope` em `RegionalAuthority`.
- Atualizadas todas as inspeções de atividade/domínio para considerar `authority.active_completion != null`:
  - `is_region_transaction_active_readonly(world, region_id)`
  - `inspect_domain_for_worker_removal_readonly(...)`
  - `release_regional_domain(...)`
  - `_owns_delivery_scope(...)` e `_owns_camp_delivery_scope(...)` (exigem `authority.active_completion == null`)
- Criados os helpers internos estáticos:
  - `_acquire_completion_scope(manager: ConstructionManager, site: ConstructionSite) -> Dictionary`:
    - Valida thread principal, validade de `manager` e `site` na árvore, `world`, `region_id == manager.get_region_id()`, `inventory == manager.get_inventory()` e `not inventory.is_transaction_busy()`.
    - Coleta todas as obras conhecidas do domínio via `site._collect_known_other_sites_pure()` + `site`, ordenadas determinísticamente, recusando com `{"ok": false, "busy": true, "reason": "busy"}` se qualquer obra estiver com `is_transaction_busy()`.
    - Quando `inventory.get_storage_source() is GroundPileManager`: verifica `_matches_economic_domain(site, world, storage, authority)`, atividade da `RegionalAuthority` (`is_executing`, `active_delivery`, `active_camp_delivery`, `active_completion`), travas de `storage` (`is_locked()`, `is_batch_active()`) e `camp_zone.is_transaction_locked()`; vincula ou reutiliza `authority`, marca `authority.is_executing = true`, `authority.active_completion = scope`, `s._is_preparing_or_transacting = true` em todas as obras do domínio, `inventory._is_delivering = true` e `storage._is_preparing_withdrawal = true`.
    - Quando `storage_source` não é `GroundPileManager` (ex.: `InMemoryStorageSource` das suítes legadas `T3.4.4`/`T3.4.5`): ainda consulta `is_region_transaction_active_readonly(world, region)` para impedir conclusão durante transação ativa de região já vinculada ao mundo, aplicando as travas cooperativas em `domain_sites` e `inventory` sem materializar `RegionalAuthority` artificial.
  - `_owns_completion_scope(scope: CompletionScope) -> bool`: verifica posse ativa da `CompletionScope` sobre `world`, `region_id`, `manager`, `site`, `inventory`, `sites` e (quando aplicável) `RegionalAuthority` + `storage`.
  - `_release_completion_scope(scope: CompletionScope) -> void`: libera na ordem inversa `storage._is_preparing_withdrawal`, `inventory._is_delivering`, `s._is_preparing_or_transacting`, `authority.active_completion` e `authority.is_executing`.

---

## 5. Ordem de guardas, ponto de commit e ciclo de vida do nó em `ConstructionManager`

Em `src/buildings/construction_manager.gd`, `complete_site_transaction` e `_complete_queued_site` convergem para `_execute_site_completion(site, building_instance, from_queued_dispatch)`:

1. **Pré-checagem leve:** se `_completion_in_progress` ou `not _valid_completion_site(site)` (`not site.is_transaction_busy()` e `site.is_completion_ready()`), retorna `false`; quando `from_queued_dispatch == true` e a obra segue em `COMPLETING` por bloqueio transitório (`_completion_in_progress` ou `site.is_transaction_busy()`), agenda retentativa curta sem erro (`BUSY_COMPLETION_RETRY_SEC = 0.05`).
2. **Conflito e snapshot de identidade:** verifica `site.get_site_state() == SiteState.COMPLETING` e `_has_conflicting_completed_building(site)` (`_has_building_id(site.site_id)` ou `has_building_overlapping_rect(...)`), capturando `expected_site_id`, `expected_generation`, `expected_world` e `expected_region`.
3. **Aquisição regional:** chama `ReservedWithdrawalCoordinator._acquire_completion_scope(self, site)`. Em falha `"busy"`, retorna `false` (com retentativa curta apenas se `from_queued_dispatch == true`, sem incrementar `_completion_retry_count`). Em erro estrutural não-`busy`, chama `site.record_completion_failure(...)` + `_schedule_retry(site)`.
4. **Validação de raiz e instanciação:** valida `_buildings_root` (na árvore, mesmo `World3D` e meta `&"region_id" == expected_region`). Instancia via `building_instance` ou `building_creator_override` / `BuildingInstance.new()`, verificando posse exclusiva (`owns_created`) e `_validate_site_ready_for_completion_under_guard(...)`.
5. **Posicionamento pré-árvore e checagem pós-árvore:**
   - Configura `building.transform = _world_to_buildings_local_transform(site.global_transform)` **antes** de `_buildings_root.add_child(building)`, garantindo que ouvintes de `child_entered_tree` observem a edificação já posicionada.
   - Após `_buildings_root.add_child(building)`, reafirma `building.global_transform = site.global_transform` e revalida `_validate_site_ready_for_completion_under_guard(...)`, `building.is_valid()`, `building_id`, `definition`, `region_id`, `get_world_3d()`, `get_footprint_rect()` e `incorporated_materials`.
   - Em qualquer invalidade ou mutação concorrente de identidade/geração/estado, remove e libera apenas o nó recém-criado (nunca uma edificação já registrada), registra falha via `site._record_completion_failure_under_guard(...)`, agenda `_schedule_retry(site)` e libera guardas.
6. **Commit e liberação antes de `remove_child(site)` (causa e correção de regressão observada em `test_t3_6_2_c3_3_order_integration.gd`):**
   - Na sequência: limpa timers de retry do canteiro (`_clear_completion_timers_for_site`), anexa `building` a `_completed_buildings`, notifica `_world_navigation.notify_building_geometry_changed(building)`, comita em `site._commit_completed_building_under_guard(building, scope)` (que dispara `site_completed`), e remove `site` de `_sites`.
   - `_finish_completion_guards(scope)` é executado **logo após `_sites.erase(site)` e antes de `_sites_root.remove_child(site)`**. Durante o diagnóstico desta candidata, constatou-se que liberar a guarda apenas após `remove_child(site)` fazia `site._exit_tree()` (com `_site_state == COMPLETED`) emitir `state_changed(self)` enquanto `site._is_preparing_or_transacting` ainda era `true`, levando observadores de transação econômica (como `test_solo_physically_transports_wood_and_stone_then_completes_building`) a interpretar um sinal de remoção pós-conclusão como se houvesse transferência ativa após a ordem já ter finalizado. Com `_finish_completion_guards(scope)` antes de `remove_child(site)`, todos os callbacks de construção (`building_creator_override`, `child_entered_tree`, `building_blocker_added`, `site_completed`) ocorrem sob proteção regional plena, enquanto `site._exit_tree()` observa corretamente a transação já encerrada e `site` já fora de `_sites`.

---

## 6. Proteção de bypasses em `ConstructionSite`

Em `src/buildings/construction_site.gd`:

- `record_completion_failure(reason)` e `commit_completed_building(building)` continuam recusando chamadas externas sempre que `_is_preparing_or_transacting == true`.
- O caminho autorizado interno passa por `_record_completion_failure_under_guard(reason, completion_scope)` e `_commit_completed_building_under_guard(building, completion_scope)`, ambos validando `completion_scope.site == self` e `ReservedWithdrawalCoordinator._owns_completion_scope(completion_scope)` antes de aplicar `_apply_completion_failure` ou `_apply_completed_building`.
- Em `_apply_completed_building(building)`, `_unbind_inventory()` e `_clear_all_transit_listeners()` passaram a executar **antes** de `site_completed.emit(self, building)` para evitar que ouvintes do término da obra ainda encontrem listeners econômicos ligados à obra já concluída.

---

## 7. Reentrância e callbacks observáveis

Validado em `test_01` e `test_02` de `test_t3_6_2_c4_7_construction_completion_authority.gd`:

- Reentrâncias disparadas dentro de `building_creator_override`, `child_entered_tree`, `building_blocker_added` e `site_completed` não conseguem:
  - executar `complete_site_transaction(...)` duplicado nem gerar segunda `BuildingInstance`;
  - executar `execute_reserved_withdrawal(...)` (`"busy"`), `SelectiveSiteDeliveryCoordinator` (`"busy"`), `SelectiveCampDeliveryCoordinator` (`"busy"`) ou `GatherTransferSession` na mesma região;
  - chamar `site.commit_completed_building(...)` ou `site.record_completion_failure(...)` manualmente sobre a obra em conclusão;
  - remover trabalhador temporário via `inspect_domain_for_worker_removal_readonly(...)` (reporta `"regional_transaction_active"`).
- Contratos legados durante `site_completed` preservados integralmente (`test_t3_4_4_building_completion`): durante o callback `site_completed`, `cm.get_sites().has(site)` e `cm.get_completed_buildings().has(building)` são `true`, `building.is_valid()` é `true` e nova alocação no mesmo footprint falha com `"building_overlap"`.

---

## 8. Retentativas em `busy` vs falhas reais

- **Contenção transitória (`busy`):**
  - Se `complete_site_transaction(site)` é chamado diretamente com região ou obra irmã ocupada, retorna `false` sem alterar `_site_state` e sem incrementar `_completion_retry_count`.
  - Se o disparo veio da fila reativa (`_complete_queued_site`, `from_queued_dispatch == true`), `_schedule_busy_completion_retry(site)` agenda retentativa em `0.05 s` (`_busy_completion_timers`) sem incrementar `_completion_retry_count` nem transicionar para `COMPLETION_FAILED_RETRYABLE`; liberada a transação concorrente, a obra conclui automaticamente.
- **Falhas reais de conclusão:**
  - Falha na criação/validação de edificação ou `_buildings_root` inválido transiciona normalmente para `COMPLETION_FAILED_RETRYABLE` / `COMPLETION_BLOCKED_ERROR` e agenda `_schedule_retry(site)`.
  - `_on_completion_retry_timeout` e `retry_failed_site_completion(site)` agora também verificam `ReservedWithdrawalCoordinator.is_region_transaction_active_readonly(site.get_world_3d(), site.region_id)` antes de retomar `COMPLETING`.
  - `_exit_tree()` de `ConstructionManager` limpa `_retry_timers`, `_busy_completion_timers` e `_navigation_retry_timer`.

---

## 9. Isolamento regional e multi-domínio

- Validado em `test_03` (`test_t3_6_2_c4_7_construction_completion_authority.gd`):
  - No mesmo `World3D`, duas regiões distintas (`default` e `reg_b_c47`) mantêm `RegionalAuthority`, `GroundPileManager`, `SettlementInventory` e `ConstructionManager` independentes: enquanto a região `reg_b_c47` está bloqueada em transação ativa na sua `RegionalAuthority`, a região `default` conclui sua obra normalmente (`1` `BuildingInstance` em `default`, `0` em `reg_b_c47`).
  - Quando a transação em `default` bloqueia a conclusão de `site_a` via obra irmã ocupada (`peer._is_preparing_or_transacting == true`) ou via `RegionalAuthority` ativa, `site_a` permanece em `COMPLETING` intacto até a liberação, enquanto `reg_b_c47` continua operacional.

---

## 10. Conservação econômica

Validada em `test_01`–`test_04` da C4.7 e em toda a suíte T3.6.2 (`148/148`):

- Quando a conclusão é recusada por `"busy"` ou por falha de instanciação/validação de edificação, nenhum recurso reservado no estoque, no `GroundPileManager`, nas mochilas (`CarryProvenanceLedger`) ou no `buffer` / `consumed` do canteiro é duplicado, perdido ou debitado novamente.
- Quando a conclusão comita após a liberação da região, os materiais incorporados na `BuildingInstance` (`incorporated_materials`) correspondem exatamente aos consumidos pelo canteiro (`get_consumed_amounts()`), e os saldos residuais do `SettlementInventory` / `GroundPileManager` permanecem consistentes.

---

## 11. Arquivos afetados e escopo preservado

| Arquivo | Status | Resumo |
| --- | --- | --- |
| `src/economy/reserved_withdrawal_coordinator.gd` | Modificado (`+150 / -6`) | `CompletionScope`, `RegionalAuthority.active_completion`, aquisição/posse/liberação de escopo de conclusão e visibilidade em helpers somente leitura e de remoção/liberação regional. |
| `src/buildings/construction_manager.gd` | Modificado (`+171 / -17`) | Fronteira transacional regional em `_execute_site_completion`, posicionamento pré-árvore, revalidação de identidade/geração/conflito, retry não penalizante para `busy` em despacho diferido, checagem regional em `retry_failed_site_completion` e limpeza de timers. |
| `src/buildings/construction_site.gd` | Modificado (`+34 / -3`) | Guardas `_record_completion_failure_under_guard` e `_commit_completed_building_under_guard`, unbind antes de `site_completed.emit` e preservação do bloqueio de bypass público sob `_is_preparing_or_transacting`. |
| `tests/integration/test_t3_6_2_c4_7_construction_completion_authority.gd` (+ `.uid`) | Novo (`+613` código + `.uid`) | 4 testes focados (`151` asserções) cobrindo contenção regional, reentrância em todos os callbacks de conclusão, obras irmãs, isolamento entre regiões no mesmo `World3D`, preservação de retry count, rollback sem perda e regressão de navegação/footprint. |
| `docs/testing/T3_6_2_C4_7_construction_completion_authority_candidate_report.md` | Novo | Este relatório técnico. |

**Explicitamente intocados:** `src/main/main.gd`, `src/rts/command_controller.gd`, `src/economy/resource_source.gd`, `src/economy/unit_carry_load.gd`, `src/units/orders/construct_order.gd`, `src/units/orders/gather_transfer_session.gd`, e a branch `main`.

---

## 12. Evidências de validação executadas após a edição final

| Verificação | Resultado observado |
| --- | --- |
| `.\tools\run_tests.ps1 -Filter test_t3_6_2_c4_7_construction_completion_authority` (baseline `d31f6be`, **RED**) | **Exit 1.** `Suites: 1 \| Tests: 4 \| Passed: 0 \| Failed: 4 \| SuiteErrors: 0 \| Assertions: 140 \| Elapsed: 12106.6 ms`. |
| `git diff --check` | **Exit 0.** Zero problemas de espaço em branco/patch. |
| `.\tools\validate.ps1` | **Exit 0.** **`Validation PASSED (0 errors, 0 warnings, 155 scripts checked)`**. |
| `.\tools\run_tests.ps1 -Filter test_t3_6_2 -TimeoutSeconds 240` (**GREEN T3.6.2**) | **Exit 0.** `Suites: 18 \| Tests: 148 \| Passed: 148 \| Failed: 0 \| SuiteErrors: 0 \| Assertions: 10147 \| Elapsed: 105755.8 ms` (inclui `test_t3_6_2_c4_7_construction_completion_authority`: `4/4 PASS, 151 assertions`, e `test_t3_6_2_c3_3_order_integration`: `10/10 PASS, 328 assertions`). |
| `.\tools\run_tests.ps1 -Segmented -GroupTimeoutSeconds 240` (**GREEN global**) | **Exit 0.** **`Batches: 15`** (`unit` + `integration-01`..`14`), **`Suites: 61 \| Tests: 445 \| Passed: 445 \| Failed: 0 \| SuiteErrors: 0 \| Assertions: 24934 \| SumGodotElapsed: 604139,5 ms \| TotalWallElapsed: 630917,5 ms`**, **`Coverage Check: Discovered=61 \| ExecutedUnique=61 \| Duplicates=0 \| Missing=0`** (inclui `test_t3_4_4_building_completion`: `9/9 PASS, 1355 assertions` e `test_t3_4_5_navigation_bake`: `9/9 PASS, 2305 assertions`), com `0` erros/avisos Godot. |

---

## 13. Limites restantes fora do escopo C4.7

- **Restante de P6 (planejado para `P6-B` / etapas seguintes):** outras superfícies mutadoras públicas fora da fronteira de conclusão de construções (ex.: revisões diretas de criação/desregistro em `ConstructionSite` ou integrações futuras de cancelamento `D3` e `T3.6.3`) não fazem parte deste incremento `P6-A`.
- **Pendências fora de escopo preservadas:** `P2` (integração de despacho/região/diagnósticos no `CommandController` e overlay), `P4` (migrador atômico de cargas legadas), `DEC-T3.6-SIGNALS-01` (`D-INT-02`), decisões `D-INT-01` e `D-INT-03`, ativação global de `use_provenance_transactions` e todo o fluxo de cancelamento/recuperação/custódia `D3`.
- **Cobertura exclusivamente automatizada headless nesta etapa:** nenhuma alteração visual foi feita nem a proveniência foi habilitada no fluxo normal de jogo; não houve execução manual/visual adicional.

---

## 14. Parecer objetivo sobre a candidata

**CANDIDATA C4.7 PRONTA PARA AUDITORIA.**

- Escopo **P6-A** entregue e isolado nos 3 arquivos de produção esperados (`6abb438`) e na suíte dedicada (`aa546b1`), com reprodução RED inequívoca no baseline, validação de `155` scripts sem avisos e `445/445` testes aprovados em `61/61` suítes (`24.934` asserções).
- **Não** é declarada homologação formal pelo proprietário; nenhum merge em `main`, criação de tag ou avanço para `P6-B` / `C4.8` foi realizado, aguardando auditoria técnica independente.
