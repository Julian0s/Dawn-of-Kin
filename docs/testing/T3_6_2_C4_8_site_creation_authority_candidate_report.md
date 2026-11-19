# Dawn of Kin — Relatório Técnico da Candidata T3.6.2-C4.8
## P6-B1 — Criação de canteiros sob fronteira econômica regional

- **Data:** 19/11/2026
- **Engine:** Godot 4.7.2 (`Godot_v4.7.2-stable_win64.exe`)
- **Escopo autorizado:** Exclusivamente **P6-B1** — proteger `ConstructionManager.try_create_site_from_placement()` e a reserva inicial de materiais sob a fronteira econômica regional `(World3D, region_id)`, impedindo reservas órfãs, sinais intermediários, reentrância de observadores e corrupção por falhas parciais, sem ativar proveniência globalmente nem implementar o restante de `P6`, `P2`, `P4`, `D-INT-01/02/03` ou cancelamento `D3`.
- **Parecer objetivo:** **CANDIDATA C4.8 PRONTA PARA AUDITORIA** (reprodução `RED` confirmada em `5/5` testes no baseline `cf18bd0`; correções validadas em `5/5` testes focados, `153/153` testes T3.6.2 e `450/450` testes segmentados em `62/62` suítes com `0` falhas e `0` erros/avisos; **P6 NÃO está integralmente concluída** e **não** é declarada homologação formal da T3.6.2).

---

## 1. Baseline Git e commits publicados

- **Repositório:** `Julian0s/Dawn-of-Kin`
- **Worktree:** `C:\Projetos\Dawn_of_Kin_wt_t3_4_5`
- **Branch:** `feat/t3-6-2-provenance-transactions`
- **HEAD inicial verificado:** `cf18bd09c97ca27c3c476c3f4ab716de3a10ae8c` (`0` ahead / `0` behind `origin/feat/t3-6-2-provenance-transactions`, árvore limpa)
- **`main` de referência (intocada):** `25e0a20f1d6a2f10a9e059afe69759fbe263db4a`
- **Commits publicados desta candidata (anteriores a este relatório):**
  - `bb5ec66bcd6eec7a260491d6ed981bffccf09c40` — `feat(t3.6.2): protect construction site creation with regional boundary (P6-B1)` (`src/buildings/construction_manager.gd`, `src/economy/ground_pile_manager.gd`, `src/economy/in_memory_storage_source.gd`, `src/economy/reserved_withdrawal_coordinator.gd`, `src/economy/selective_camp_delivery_coordinator.gd`, `src/economy/selective_site_delivery_coordinator.gd`)
  - `0d1072fc0784c06a508e6dfdc597d26b66e54d55` — `test(t3.6.2-c4.8): add focused integration suite for site creation regional boundary (P6-B1)` (`tests/integration/test_t3_6_2_c4_8_site_creation_authority.gd` e `.uid`)

---

## 2. Divergência documental R2 registrada

Verificação direta em `docs/architecture/` na HEAD atual (`cf18bd09c97ca27c3c476c3f4ab716de3a10ae8c`):

- Os arquivos presentes em `docs/architecture/` na branch atual continuam sendo **exclusivamente**:
  - `docs/architecture/T1_architecture.md`
  - `docs/architecture/T2_architecture_DRAFT.md`
  - `docs/architecture/T3_architecture_PROPOSAL.md`
- A especificação `docs/architecture/T3_6_cancellation_architecture_R2_PROPOSAL.md` não está integrada à branch atual e existe apenas no commit histórico divergente `69c13275a34a30564ac839ec920f83ef36590812` (`merge-base` em `fb31887e9ee6671d81a6797ea0d921c6d8b7a979`).
- Ela foi consultada apenas como referência histórica confrontada com `AGENTS.md`, `docs/Dawn_of_Kin_GDD.md`, `docs/architecture/T3_architecture_PROPOSAL.md`, relatórios `C4.1`/`C4.5`–`C4.7` e o código real, sem ser incorporada à árvore nem declarada automaticamente aprovada.

---

## 3. Diagnóstico do baseline e evidência RED

Antes de qualquer alteração em `src/`, foi executada a suíte adversarial `tests/integration/test_t3_6_2_c4_8_site_creation_authority.gd` contra o baseline `cf18bd09c97ca27c3c476c3f4ab716de3a10ae8c`:

- **Comando RED:** `.\tools\run_tests.ps1 -Filter test_t3_6_2_c4_8_site_creation_authority`
- **Exit code:** `1`
- **Resultado:** `Suites: 1 | Tests: 5 | Passed: 0 | Failed: 5 | SuiteErrors: 0 | Assertions: 218 | Elapsed: 10660.1 ms`

### O que já possuía proteção suficiente no baseline (preservado intacto)

- Validações puras de entrada (`invalid_sites_root`, `invalid_inventory`, `invalid_definition`, `invalid_position`, `invalid_costs`).
- Verificação espacial pré-criação contra edifícios concluídos (`building_overlap`), canteiros já registrados (`site_overlap`) e área reservada do acampamento (`camp_overlap`).
- Rejeição atômica de `insufficient_resources` quando o estoque livre estava ocioso e insuficiente (sem reserva parcial).
- Independência entre regiões com `GroundPileManager`/`SettlementInventory` separados fora de conflitos de trava ou de autoridade compartilhada.

### Defeitos reais reproduzidos no baseline (RED)

1. **`test_01` (`9` falhas):**
   - `reserve_batch` disparava `storage.reservations_changed`, `inventory.reservations_changed` e `inventory.inventory_changed` **antes** de existir ou estar configurado o `ConstructionSite`; observadores viam uma reserva ativa sem canteiro associado.
   - Em `InMemoryStorageSource`, um observador conectado a `reservations_changed` conseguia chamar `inventory.release_batch(...)` durante o próprio sinal e apagar a reserva recém-criada (`reserved == 0` para obra ativa), além de falhas de `configure()` emitirem `2` sinais intermediários de reserva/liberação.
2. **`test_02` (`5` falhas):**
   - Durante transações ativas de `SelectiveCampDeliveryCoordinator`, `ReservedWithdrawalCoordinator` e conclusão `P6-A` (`complete_site_transaction`), `try_create_site_from_placement` não consultava a fronteira regional nem travas de conclusão/estoque: `can_reserve_batch` retornava `false` porque `storage.is_locked() == true`, fazendo `ConstructionManager` reportar falsamente `"insufficient_resources"` (e emitir `site_creation_rejected("insufficient_resources", ...)`) em vez de `"busy"`.
3. **`test_03` (`32` falhas):**
   - Durante `site_creator_override`, `reservations_changed` já havia sido emitido; `is_region_transaction_active_readonly` era `false`; `inspect_domain_for_worker_removal_readonly` não reportava `"regional_transaction_active"`; chamadas reentrantes de `try_create_site_from_placement` (dupla criação), `inventory.release_batch` / `withdraw_reserved` / `complement_reservation`, `storage.release_batch` / `withdraw_reserved` e `ReservedWithdrawalCoordinator.execute_reserved_withdrawal` **executaram com sucesso** durante a criação da obra (deletando a reserva da nova obra e saqueando madeira de obra irmã).
   - Durante `_sites_root.child_entered_tree`, o nó recém-inserido ainda não tinha executado `configure()` (`is_valid() == false`, `site_id == &""`, `reservation_id == &""`).
   - Dentro de `site_created`, reentrâncias econômicas e de criação não eram bloqueadas pela fronteira transacional.
4. **`test_04` (`7` falhas):**
   - Quatro falhas consecutivas após reserva (`override -> null`, `FailingConfigureSite`, `InvalidInTreeSite` e override hostil retornando `peer_site`) emitiram **32 sinais intermediários** (`inv_res`, `storage_res`, `inv_chg`, `storage_chg`) e causaram deriva nas revisões de `inventory` (`5 -> 21`), `storage` (`7 -> 23`) e `ledger` (`2 -> 18`).
   - Ainda mais grave: quando `site_creator_override` retornava um `ConstructionSite` já existente (`peer_site`), o rollback chamava `site.free()` **destruindo o canteiro irmão vivo (`peer_site`)**.
5. **`test_05` (`5` falhas):**
   - Durante transação ativa na Região A, `cm_a` reportou `"insufficient_resources"` em vez de `"busy"`.
   - Um `ConstructionManager` configurado com `region_id` conflitante (`&"rogue_region_c48"`) compartilhando o `GroundPileManager` já vinculado à `RegionalAuthority` da Região A (`&"default"`) **conseguiu criar canteiro e reservar estoque** em vez de ser recusado com `"ambiguous_domain"`.

---

## 4. Contrato de admissão regional

Em `src/economy/reserved_withdrawal_coordinator.gd`:

- Adicionada a capacidade interna `SiteCreationScope` (`world`, `region_id`, `manager`, `inventory`, `storage_source`, `storage`, `camp_zone`, `sites`, `new_site`, `authority`).
- Adicionado o campo `active_site_creation: SiteCreationScope` em `RegionalAuthority` e o registro ativo interno `static var _active_site_creation_scopes: Array[SiteCreationScope] = []`.
- **Sem materialização espúria de `RegionalAuthority` em modo legado/pré-proveniência:**
  - Se já existe `RegionalAuthority` para `(world, region_id)` em `world.get_meta(DOMAIN_META)`, `_acquire_site_creation_scope(manager)` valida correspondência exata com `storage` e obras vivas do domínio, recusa `"ambiguous_domain"` em qualquer divergência ou `"busy"` se `authority` estiver executando (`is_executing`, `active_delivery`, `active_camp_delivery`, `active_completion` ou `active_site_creation`), e vincula `authority.is_executing = true` + `authority.active_site_creation = scope`.
  - Se ainda **não** existe `RegionalAuthority` para `(world, region_id)`, `_acquire_site_creation_scope(manager)` ainda recusa `"ambiguous_domain"` caso `storage` já esteja vinculado a outra `(world, region)` ou a outra `RegionalAuthority`, recusa `"busy"` se houver qualquer criação/transação ativa no domínio ou no mesmo `inventory`/`storage_source`, e adquire o escopo via `_active_site_creation_scopes` + travas cooperativas **sem** criar `RegionalAuthority` em `world.get_meta(DOMAIN_META)`. Isso preserva integralmente os contratos das suítes `T3.3`, `C3.1`, `C3.3`, `C4.3` e `C4.6` (que exigem ausência de `DOMAIN_META` antes de transações opt-in de proveniência).
- Atualizados todos os pontos de consulta/admissão regional para enxergar `active_site_creation` e `_active_site_creation_scopes`:
  - `is_region_transaction_active_readonly(world, region_id)`
  - `inspect_domain_for_worker_removal_readonly(world, region_id, storage, camp_zone)` (verificando `_active_site_creation_scopes` inclusive quando `world.has_meta(DOMAIN_META)` é `false`)
  - `release_regional_domain(...)`
  - `_owns_delivery_scope`, `_owns_camp_delivery_scope`, `_owns_completion_scope`, `_acquire_completion_scope`
  - Pré-checagens antes de `_resolve_authority` / `_resolve_camp_authority` em `ReservedWithdrawalCoordinator._execute_core`, `SelectiveSiteDeliveryCoordinator` e `SelectiveCampDeliveryCoordinator` (impedindo que chamadas reentrantes ocupadas durante criação materializem `RegionalAuthority`).

---

## 5. Participantes e ordem de guardas

Ordem fixa de aquisição em `ConstructionManager.try_create_site_from_placement` + `ReservedWithdrawalCoordinator._acquire_site_creation_scope`:

1. Validações puras de entrada e sobreposição espacial (`invalid_*`, `building_overlap`, `site_overlap`, `camp_overlap`) — executadas antes de qualquer guarda ou mutação, preservando `building_overlap` durante `site_completed` (`test_t3_4_4_building_completion.gd:186`).
2. Checagem local `_creation_in_progress or _completion_in_progress` (`"busy"`).
3. Aquisição regional `_acquire_site_creation_scope(self)`:
   1. `authority.is_executing = true` e `authority.active_site_creation = scope` (se `authority != null`)
   2. `_active_site_creation_scopes.append(scope)`
   3. `peer._is_preparing_or_transacting = true` para todas as obras vivas no domínio ou compartilhando `inventory`/`storage_source` (ordenadas determinísticamente por `site_id`, `instance_id`)
   4. `inventory._is_delivering = true`
   5. `storage._is_preparing_withdrawal = true` (quando `GroundPileManager`)
   6. `camp_zone._coordinator_transaction_locked = true` (quando válido)
4. `manager._creation_in_progress = true`.
5. Após `site.configure(...)` off-tree e **antes** de `_sites_root.add_child(site)`: `site._is_preparing_or_transacting = true` e `scope.new_site = site`.

**Liberação (em ordem inversa, garantida em todos os caminhos de sucesso e falha, sem `await`):**
1. `camp_zone._coordinator_transaction_locked = false`
2. `storage._is_preparing_withdrawal = false`
3. `inventory._is_delivering = false`
4. `scope.new_site._is_preparing_or_transacting = false`
5. `peer._is_preparing_or_transacting = false` (ordem inversa)
6. `_active_site_creation_scopes.erase(scope)`
7. `authority.active_site_creation = null` e `authority.is_executing = false` (se `authority != null`)
8. `manager._creation_in_progress = false`

---

## 6. Ponto de commit e publicação coerente de sinais

Em vez de usar `begin_batch/end_batch` para mascarar falhas ou emitir `reserve_batch` antes da criação do nó:

1. **Preparação e reserva silenciosa sob posse de `SiteCreationScope`:**
   - Em `GroundPileManager`: `_prepare_site_reservation_under_guard(...)` valida plano determinístico de pilhas sem mutação; `_apply_prepared_site_reservation_silent(...)` grava checkpoint exato (`_ledger.snapshot_state()`, `_ledger._transaction_revision`, `_transaction_revision`), aloca no ledger sob `_is_mutating = true` e incrementa `_transaction_revision += 1` **sem emitir nenhum sinal**.
   - Em `InMemoryStorageSource`: `_apply_site_reservation_silent(...)` grava checkpoint (`_create_rollback_snapshot()`, `_transaction_revision`), grava a reserva e incrementa `_transaction_revision += 1` **sem emitir nenhum sinal**.
   - Todos esses helpers verificam `ReservedWithdrawalCoordinator._owns_site_creation_scope(scope)` (impedindo uso fora da transação autorizada).
2. **Instanciação, configuração off-tree e entrada na árvore:**
   - Verifica posse exclusiva do nó (`owns_site = is_instance_valid(site) and site.get_parent() == null and not _sites.has(site) and not site.is_valid()`).
   - Posiciona `site.position = _world_to_sites_local(world_position)` e executa `site.configure(...)` **antes** de `_sites_root.add_child(site)`, evitando que `child_entered_tree` jamais observe um canteiro parcialmente configurado ou sem corpo de colisão.
   - Aplica `site._is_preparing_or_transacting = true`, anexa em `_sites_root.add_child(site)` e revalida integralmente pós-árvore (`is_inside_tree`, `get_parent() == _sites_root`, `get_world_3d() == expected_world`, `is_valid()`, `site_id`, `reservation_id`, `region_id`, `definition`, `get_inventory()`, `SiteState.ACTIVE`, ausência de overlap e correspondência exata `_inventory.get_reservation_amounts(new_res_id) == costs`).
3. **Ponto de commit irreversível:**
   - `_sites.append(site)`
   - `site.state_changed.connect(_on_site_state_changed)`
   - Incremento único de `_inventory._transaction_revision += 1` (para `GroundPileManager`, cujo eco em `SettlementInventory` não duplica revisão sob `_is_delivering && _is_preparing_withdrawal`).
4. **Publicação pós-commit sob fronteira ativa (alinhada a `DEC-T3.6-SIGNALS-01`):**
   - Com `site._suppress_coordinator_signal_echo = true` durante `_publish_site_reservation_committed(scope)` (evitando bump espúrio de revisão no próprio canteiro recém-criado), dispara `reservations_changed` e `storage_changed`/`inventory_changed` quando tanto a reserva quanto o `ConstructionSite` válido já estão registrados em `_sites`.
   - Emite `site_created.emit(site)` ainda sob a fronteira regional (bloqueando reentrância dentro do callback) e imediatamente em seguida executa `_finish_site_creation_guards(scope)`, liberando todas as travas antes do retorno de `try_create_site_from_placement`.

---

## 7. Tratamento de rollback

Em qualquer falha antes do ponto de commit (estoque insuficiente, falha de reserva, `site_creator_override` retornando `null`/tipo inválido/canteiro já existente, falha em `site.configure()`, ou falha na revalidação pós-árvore):

- **Reserva:** restaurada silenciosamente via `_restore_site_reservation_checkpoint_silent(checkpoint, scope)` (restaurando snapshot exato do `PileReservationLedger` + `_ledger._transaction_revision` + `_transaction_revision` ou snapshot do `InMemoryStorageSource`), com **zero sinais intermediários**, **zero reservas órfãs** e **zero deriva de revisão** em estoque, armazenamento, ledger e canteiros irmãos.
- **Sequência de IDs:** `_next_site_seq` é restaurado para `saved_next_site_seq`.
- **Nó:** somente se `owns_site` for verdadeiro (nunca sobre um `ConstructionSite` pré-existente/registrado), desvincula inventário (`site._unbind_inventory()`), remove de `_sites_root` se inserido e libera via `site.free()`.
- **Guardas e rejeição:** `_finish_site_creation_guards(scope)` libera todas as travas **antes** de `_reject(...)` emitir `site_creation_rejected`.

---

## 8. Compatibilidade legada e interação com P6-A (§7)

- **Preservação funcional:** posicionamento livre sem grid, `PlacementValidator`, proteção de `CampStorageZone`, reservas físicas reais, `InMemoryStorageSource`, complementação manual `DEC-11B`, exclusão de reservas de outras obras, transporte físico obrigatório e contratos públicos de `site_created` / `site_creation_rejected` foram integralmente preservados (comprovado sem edição em nenhuma suíte legada `T1`–`T3.6.2`).
- **Integração com P6-A (`ConstructionManager._execute_site_completion`):**
  - `_execute_site_completion` passou a checar também `_creation_in_progress` (com reagendamento não penalizante via `_schedule_busy_completion_retry` quando disparado da fila diferida), e `try_create_site_from_placement` recusa com `"busy"` durante conclusão ativa em pontos livres mantendo `"building_overlap"` sobre o footprint concluído durante `site_completed`.
- **Avaliação da observação da auditoria C4.7 (§7):**
  - Avaliado o ponto levantado pelo ChatGPT (`ConstructionManager._execute_site_completion()` não verificar explicitamente o retorno booleano de `_commit_completed_building_under_guard()`).
  - **Resultado da avaliação:** P6-B1 **não** introduz nenhuma interação conflitante com esse caminho — quando uma conclusão está ativa, toda criação concorrente é barrada antes de adquirir escopo ou mutar qualquer participante; e quando uma criação está ativa, nenhuma conclusão consegue passar por `_valid_completion_site` ou `_acquire_completion_scope`, nunca atingindo `_commit_completed_building_under_guard()`.
  - Conforme §7, P6-A **não** foi refatorada nesta etapa e o ponto fica registrado como risco residual na §11 abaixo.

---

## 9. Arquivos modificados e escopo preservado

| Arquivo | Status (`--numstat`) | Resumo |
| --- | --- | --- |
| `src/economy/reserved_withdrawal_coordinator.gd` | Modificado (`+260 / -6`) | `SiteCreationScope`, `RegionalAuthority.active_site_creation`, `_active_site_creation_scopes`, aquisição/posse/liberação de escopo de criação, integração em consultas somente leitura, remoção de trabalhador, liberação regional, P6-A e guarda pré-resolução em `_execute_core`. |
| `src/buildings/construction_manager.gd` | Modificado (`+162 / -19`) | Fronteira regional transacional em `try_create_site_from_placement`, reserva silenciosa + checkpoint/rollback sem sinais intermediários, configuração off-tree pré-`add_child`, revalidação pós-árvore, posse exclusiva `owns_site`, publicação coerente pós-commit e exclusão mútua `_creation_in_progress` com `_execute_site_completion`. |
| `src/economy/ground_pile_manager.gd` | Modificado (`+81 / -0`) | Helpers internos sob posse de `SiteCreationScope`: `_prepare_site_reservation_under_guard`, `_apply_prepared_site_reservation_silent`, `_restore_site_reservation_checkpoint_silent`, `_publish_site_reservation_committed`. |
| `src/economy/in_memory_storage_source.gd` | Modificado (`+49 / -0`) | Helpers internos equivalentes sob posse de `SiteCreationScope` para compatibilidade legada com rollback silencioso e publicação pós-commit. |
| `src/economy/selective_site_delivery_coordinator.gd` | Modificado (`+2 / -0`) | Recusa `"busy"` antes de `_resolve_authority` quando há criação ativa no domínio/storage. |
| `src/economy/selective_camp_delivery_coordinator.gd` | Modificado (`+2 / -0`) | Recusa `"busy"` antes de `_resolve_camp_authority` quando há criação ativa no domínio/storage. |
| `tests/integration/test_t3_6_2_c4_8_site_creation_authority.gd` (+ `.uid`) | Novo (`+883` + `.uid`) | Suíte adversarial focada (`5` testes, `220` asserções em GREEN) cobrindo todos os 13 requisitos da §8. |
| `docs/testing/T3_6_2_C4_8_site_creation_authority_candidate_report.md` | Novo | Este relatório técnico. |

**Explicitamente intocados:** `src/buildings/construction_site.gd`, `src/economy/settlement_inventory.gd`, `src/main/main.gd`, `src/rts/command_controller.gd`, `src/units/orders/construct_order.gd`, todas as suítes de testes existentes e a branch `main`.

---

## 10. Evidências de validação (RED, GREEN e regressão completa)

| Comando | Exit | Resultado observado |
| --- | --- | --- |
| `.\tools\run_tests.ps1 -Filter test_t3_6_2_c4_8_site_creation_authority` (baseline `cf18bd0`, **RED**) | `1` | `Suites: 1 \| Tests: 5 \| Passed: 0 \| Failed: 5 \| SuiteErrors: 0 \| Assertions: 218 \| Elapsed: 10660.1 ms`. |
| `.\tools\run_tests.ps1 -Filter test_t3_6_2_c4_8_site_creation_authority` (**GREEN** focado) | `0` | `Suites: 1 \| Tests: 5 \| Passed: 5 \| Failed: 0 \| SuiteErrors: 0 \| Assertions: 220 \| Elapsed: 11507.7 ms`. |
| `git diff --check` | `0` | Sem erros de espaço em branco ou formatação de patch. |
| `.\tools\validate.ps1` | `0` | **`Validation PASSED (0 errors, 0 warnings, 156 scripts checked)`**. |
| `.\tools\run_tests.ps1 -Filter test_t3_6_2 -TimeoutSeconds 240` (**GREEN T3.6.2**) | `0` | `Suites: 19 \| Tests: 153 \| Passed: 153 \| Failed: 0 \| SuiteErrors: 0 \| Assertions: 10376 \| Elapsed: 101899.0 ms` (`c4_8`: `5/5 PASS, 220 assertions, 535.6 ms`; `c4_7`: `4/4 PASS, 151 assertions`). |
| `.\tools\run_tests.ps1 -Segmented -GroupTimeoutSeconds 240` (**GREEN global**) | `0` | **`Batches: 15`** (`unit` + `integration-01`..`14`), **`Suites: 62 \| Tests: 450 \| Passed: 450 \| Failed: 0 \| SuiteErrors: 0 \| Assertions: 25153 \| SumGodotElapsed: 590754,5 ms \| TotalWallElapsed: 613506,2 ms`**, **`Coverage Check: Discovered=62 \| ExecutedUnique=62 \| Duplicates=0 \| Missing=0`**, `0` erros/avisos Godot. |

Suítes-chave verificadas sem regressão dentro da execução segmentada final:
- `test_t3_2_placement_flow.gd`: `5/5 PASS, 111 assertions, 3916.2 ms`
- `test_t3_3_construction_site.gd`: `7/7 PASS, 164 assertions, 83.2 ms`
- `test_t3_4_4_building_completion.gd`: `9/9 PASS, 1355 assertions, 25463.8 ms`
- `test_t3_4_5_navigation_bake.gd`: `9/9 PASS, 2305 assertions, 37192.6 ms`
- `test_t3_5_1_construction_hud.gd`: `3/3 PASS, 35 assertions, 719.0 ms`
- `test_t3_5_2_building_inspector.gd`: `3/3 PASS, 64 assertions, 11854.2 ms`

---

## 11. Problemas residuais e confirmação sobre escopo P6

- **P6 NÃO foi integralmente concluída nesta candidata:** a C4.8 fecha exclusivamente **P6-B1** (criação de canteiros e reserva inicial sob fronteira econômica regional). Permanecem pendentes para etapas posteriores de `P6`:
  - Fronteiras regionais completas de `ConstructionSite.contribute_work` e `ConstructionSite.authorize_manual_complement`.
  - Restrição/fechamento de superfícies públicas de bypass fora dos coordenadores (`UnitCarryLoad.add_with_provenance`, `ResourceSource.extract`, mutadores diretos de `SettlementInventory` / `GroundPileManager` em modo proveniência).
- **Risco residual herdado da auditoria C4.7 (§7):** `ConstructionManager._execute_site_completion()` não checa explicitamente o retorno booleano de `_commit_completed_building_under_guard()`; confirmado sem conflito com P6-B1 e preservado sem refatoração de P6-A nesta etapa.
- **Fallback para `SettlementStorageSource` customizado de terceiros:** `GroundPileManager` e `InMemoryStorageSource` utilizam snapshot/rollback silencioso dedicado; caso algum teste futuro introduza uma subclasse arbitrária de `SettlementStorageSource` sem esses helpers, o fallback atual usa `begin_batch()`/`release_batch()`/`end_batch(true)` sob as travas regionais.
- **Pendências fora de escopo preservadas:** `P2`, `P4`, `D-INT-01`/`D-INT-02`/`D-INT-03`, ativação global de `use_provenance_transactions`, cancelamento/custódia `D3` e `SaveManager` `T3.8`.
- **Cobertura headless:** validação integralmente automatizada (`156` scripts + `62/62` suítes); não houve alteração visual nem teste manual adicional.

---

## 12. Parecer técnico

**CANDIDATA C4.8 PRONTA PARA AUDITORIA.**

- Escopo **P6-B1** implementado com alterações cirúrgicas (`bb5ec66`) e validado por suíte adversarial dedicada (`0d1072f`), com reprodução RED inequívoca no baseline `cf18bd0`, zero regressões nos `450/450` testes segmentados (`62/62` suítes, `25.153` asserções) e `156` scripts validados sem erros nem avisos.
- **P6 permanece parcialmente aberta** (somente `P6-A` e `P6-B1` concluídas), **sem** homologação formal da T3.6.2, **sem** merge em `main`, **sem** tag e **sem** avanço automático para `C4.9`, aguardando auditoria independente do ChatGPT.
