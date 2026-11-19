# Dawn of Kin — Relatório Técnico da Candidata T3.6.2-C4.5
## Integridade de identidade econômica e capacidade das unidades — P3

- **Data:** 19/11/2026
- **Engine:** Godot 4.7.2 (`Godot_v4.7.2-stable_win64.exe`)
- **Escopo autorizado:** Exclusivamente investigação, reprodução e correção das lacunas **P3** (**P3-A** identidade econômica de unidades no domínio; **P3-B** coerência de capacidade entre `Unit.definition` e `UnitCarryLoad`), sem ativação global de proveniência no fluxo RTS normal.
- **Parecer objetivo:** **CANDIDATA C4.5 PRONTA PARA AUDITORIA** (reprodução `RED` confirmada no baseline `e53e953`, correções mínimas validadas em `5/5` testes focados, `139/139` testes T3.6.2 e `436/436` testes segmentados com `0` erros/avisos; **não** declarada homologação formal do proprietário).

---

## 1. Baseline e arquivos examinados

- **Repositório:** `Julian0s/Dawn-of-Kin`
- **Worktree:** `C:\Projetos\Dawn_of_Kin_wt_t3_4_5`
- **Branch:** `feat/t3-6-2-provenance-transactions`
- **HEAD inicial verificado:** `e53e95361645c41156d1c3864c7006ae06d9523f` (`0` ahead / `0` behind `origin/feat/t3-6-2-provenance-transactions`, árvore limpa)
- **`main` de referência (intocada):** `25e0a20f1d6a2f10a9e059afe69759fbe263db4a`
- **Commits publicados desta candidata (anteriores a este relatório):**
  - `ea8ab8b1dc2d650828a59c2c118600629e356e71` — `fix(t3.6.2-c4.5): enforce domain-wide economic unit identity (P3-A) and atomic Unit.definition capacity coherence (P3-B)`
  - `2a3311382ecd54ee7e6959d5211191005a7c7f81` — `test(t3.6.2-c4.5): add focused integration suite for unit identity and capacity coherence (P3)`

### Documentos e código-fonte confrontados

- Governança e especificação: `AGENTS.md`, `docs/Dawn_of_Kin_GDD.md` (v1.2), `docs/architecture/T3_6_cancellation_architecture_R2_PROPOSAL.md`, `docs/testing/T3_6_2_C4_1_readiness_inspection_report.md`, `docs/testing/T3_6_2_C4_2_lifecycle_worker_removal_candidate_report.md`, `docs/testing/T3_6_2_C4_3_construction_transfer_session_candidate_report.md`, `docs/testing/T3_6_2_C4_4_rts_order_acceptance_candidate_report.md`.
- Código de produção inspecionado:
  - `src/units/unit.gd`
  - `src/units/character_definition.gd`
  - `src/economy/unit_carry_load.gd`
  - `src/economy/carry_provenance_ledger.gd`
  - `src/main/main.gd`
  - `src/units/temporary_test_workers_controller.gd`
  - `src/buildings/construction_site.gd`
  - `src/economy/selective_camp_delivery_planner.gd`
  - `src/economy/selective_camp_delivery_coordinator.gd`
  - `src/economy/reserved_withdrawal_coordinator.gd`
  - `src/economy/selective_site_delivery_coordinator.gd`
  - `src/economy/resource_source.gd`
  - `src/units/orders/gather_resource_order.gd`
  - `src/units/orders/gather_transfer_session.gd`
- Suítes de identidade/domínio confrontadas: `test_t3_6_2_b3_2_source_transfer.gd`, `test_t3_6_2_c1_reserved_withdrawal_prep.gd`, `test_t3_6_2_c2_reserved_withdrawal_transaction.gd`, `test_t3_6_2_c3_2_selective_delivery_transaction.gd`, `test_t3_6_2_c3_3_camp_delivery_transaction.gd`, `test_t3_6_2_c3_4_gather_provenance_transaction.gd`, `test_t3_6_2_c4_2_lifecycle_worker_removal.gd`, `test_t3_6_2_c4_3_construction_transfer_session.gd`.

---

## 2. Falhas P3 realmente reproduzidas

Antes de qualquer alteração em `src/`, foi criada a suíte focada `tests/integration/test_t3_6_2_c4_5_unit_identity_capacity.gd` (5 testes, 105 asserções) e executada contra o baseline `e53e95361645c41156d1c3864c7006ae06d9523f`:

- **Comando:** `.\tools\run_tests.ps1 -Filter test_t3_6_2_c4_5_unit_identity_capacity`
- **Exit code:** `1`
- **Resultado:** `Suites: 1 | Tests: 5 | Passed: 1 | Failed: 4 | SuiteErrors: 0 | Assertions: 105 | Elapsed: 6564.2 ms`

Falhas reproduzidas no baseline:

1. **`test_01_p3a_duplicate_provenance_unit_id_without_sites_rejected_across_all_paths`** (`17` falhas):
   - Duas unidades vivas (`u1` e `u2`) no mesmo `World3D` com `provenance_unit_id = &"shared_id"` e **nenhum** canteiro (ou com `u2` fora de canteiros).
   - `GatherTransferSession.execute_extract(...)`, `GatherResourceOrder.start(...)` (opt-in), `SelectiveCampDeliveryPlanner.plan(...)`, `SelectiveCampDeliveryCoordinator.execute(...)`, `ReservedWithdrawalCoordinator.execute(...)` e `ConstructionSite.prepare_selective_delivery_plan(...)` aceitaram indevidamente `u1` porque não existia verificação de domínio abrangendo todas as unidades vivas fora de `ConstructionSite`.
2. **`test_02_p3a_ambiguous_region_duplicate_fails_closed_while_proven_distinct_regions_coexist`** (`3` falhas):
   - Uma unidade solta no mesmo `World3D` com o mesmo `provenance_unit_id`, porém **sem** região comprovada, não bloqueou a operação de `u_reg_a` na região `region_a` em coleta, planejamento/entrega ao acampamento e saque reservado.
3. **`test_03_p3a_shared_unit_carry_load_without_sites_rejected`** (`7` falhas):
   - Duas unidades vivas com `provenance_unit_id` distinto ou mesmo com o mesmo `UnitCarryLoad` compartilhado (sem canteiros) foram aceitas por `SelectiveCampDeliveryPlanner.plan`, `GatherTransferSession.execute_extract` e `ResourceSource.transfer_to_carry_load_with_provenance`.
4. **`test_04_p3b_definition_change_blocked_under_real_transaction_lock_and_negative_capacity`** (`4` falhas):
   - Durante trava transacional real (`load_changed` pós-commit de `SelectiveCampDeliveryCoordinator`, com `_coordinator_transaction_locked == true` e `_is_reserved_withdrawal_locked() == true`), `unit.definition = alt_def`, `unit.apply_definition(alt_def)` e `unit.definition = null` alteraram `unit.definition`, a velocidade de movimento (`_movement._move_speed`) e o visual, enquanto `UnitCarryLoad.set_base_capacity()` retornou `false` silenciosamente e manteve `base_capacity = 20`.
   - Com capacidade base negativa (`base_carry_capacity = -5`), `unit.apply_definition(bad_def)` também substituiu `unit.definition` e sincronizou movimento/visual mesmo com `set_base_capacity(-5)` rejeitado.
5. **`test_05_control_normal_unlocked_definition_change_overload_modifiers_and_legacy_flow`** (`PASS`, `20` asserções): controle positivo confirmado desde o baseline.

---

## 3. Correções implementadas

| Arquivo | Escopo | Resumo da alteração |
| --- | --- | --- |
| `src/economy/reserved_withdrawal_coordinator.gd` | P3-A | Implementação de `validate_unit_identity_in_domain_readonly(world, region_id, unit, load, tree)` e `_collect_unit_proven_regions_readonly(...)`, integrados antes da criação/resolução de `RegionalAuthority` (e após checagem `busy` somente leitura) em `_allocate_construction_transfer_ids`, `_allocate_camp_delivery_operation_id` e `_allocate_gather_operation_ids`. |
| `src/buildings/construction_site.gd` | P3-A | `_has_conflicting_unit_identity_pure(...)` passou a consultar `ReservedWithdrawalCoordinator.validate_unit_identity_in_domain_readonly(...)`, cobrindo tanto saque reservado quanto planejamento/entrega seletiva à obra mesmo quando a unidade conflitante não está registrada em nenhum `ConstructionSite`. |
| `src/economy/selective_camp_delivery_planner.gd` | P3-A | Validação de identidade econômica no domínio via `validate_unit_identity_in_domain_readonly(...)` durante `plan(...)`, protegendo o planejador, o coordenador de entrega ao acampamento e `CampDeliveryTransferSession`. |
| `src/units/orders/gather_transfer_session.gd` | P3-A | Validação de identidade econômica no domínio em `_build_live_identity(...)` antes de qualquer extração com proveniência. |
| `src/units/orders/gather_resource_order.gd` | P3-A | Validação preventiva em `start()` (apenas no caminho opt-in com proveniência) antes de reservar slot de trabalhador na fonte de recurso. |
| `src/economy/resource_source.gd` | P3-A | Em `transfer_to_carry_load_with_provenance(...)`, rejeição com `"ambiguous_unit_identity"` se mais de uma `Unit` viva em `GROUP_SELECTABLE_UNITS` compartilhar a mesma instância de `UnitCarryLoad` (mantendo testes unitários com `UnitCarryLoad.new()` avulso). |
| `src/units/temporary_test_workers_controller.gd` | P3-A | Remoção segura passou a delegar a validação de identidade ao mesmo validador read-only de domínio quando `resolved_region` é conhecida, além de rejeitar explicitamente `UnitCarryLoad` compartilhado no fallback sem região resolvida. |
| `src/units/unit.gd` | P3-B | Adicionado `_is_definition_mutation_locked() -> bool`. Setter inline de `@export var definition` agora bloqueia mutação sob trava transacional ou quando `UnitCarryLoad.set_base_capacity(value.base_carry_capacity)` retorna `false` **antes** de atribuir `definition = value` ou invocar `_sync_definition()`. `apply_definition(def)` delega diretamente para `definition = def` (preservando assinatura `void` e removendo chamada duplicada a `_sync_definition()`). `_sync_definition()` repete a guarda atômica antes de sincronizar `_movement` e visuais. |
| `tests/integration/test_t3_6_2_c1_reserved_withdrawal_prep.gd` | Ajuste de higiene em teste existente | Adicionadas 2 linhas (`host.remove_child(u_dup); u_dup.free()`) logo após a linha 635 (`site._pending_pickups.erase(...)`) em `test_04_...`, espelhando o `u_stale.free()` já existente na linha 684. Sem esse descarte, `u_dup` (`&"small_unit"`) permanecia viva em `host` após seu subteste, fazendo a proteção P3-A corretamente rejeitar `u1` (`&"small_unit"`) no subteste seguinte (`claim_not_eligible`). |
| `tests/integration/test_t3_6_2_c4_5_unit_identity_capacity.gd` (+ `.uid`) | P3-A + P3-B | Nova suíte de integração com 5 testes (`105` asserções) cobrindo P3-A, P3-B, isolamento entre regiões distintas, falhas em modo fechado e preservação do fluxo normal/legado. |

Arquivos **deliberadamente não modificados**:

- `src/economy/unit_carry_load.gd`: preservado intacto. Sua guarda `if _coordinator_transaction_locked: return false` em `set_base_capacity()` mantém compatibilidade com o teste ABA `test_t3_6_2_b3_2_source_transfer.gd::test_failures_and_stale_revision_leave_materials_unchanged` (que invoca `set_base_capacity()` durante `_provenance_busy == true` fora de `_coordinator_transaction_locked`), enquanto `Unit` bloqueia mutação de `definition` em qualquer trava de transação/proveniência.
- `src/main/main.gd` e `src/rts/command_controller.gd`: intocados; o fluxo RTS padrão permanece em modo legado (proveniência desligada por padrão).

---

## 4. Contratos de identidade econômica e domínio

`ReservedWithdrawalCoordinator.validate_unit_identity_in_domain_readonly(world, region_id, unit, load, tree) -> Dictionary`:

1. **Puro e somente leitura:** nunca cria nem altera `RegionalAuthority`, nunca registra recibos, nunca avança `next_serial` e nunca altera metadados de `World3D`, unidades ou mochilas.
2. **Thread e validade estrutural:** exige main thread (`"wrong_thread"`), `world`/`region_id`/`tree` válidos (`"invalid_domain"`), `unit` viva em árvore (`"invalid_unit"`), `load` válida com `is_provenance_enabled() == true` e `provenance_unit_id` não vazio/válido (`"provenance_disabled"` / `"ambiguous_unit_identity"`), além de `unit.get_world_3d() == world` e `unit.get_carry_load() == load`.
3. **Sem confusão com `character_id` ou nome visual:** duas unidades com o mesmo `character_id` (ex.: mesma `CharacterDefinition`) e `provenance_unit_id` distintos convivem normalmente; a verificação usa exclusivamente `provenance_unit_id` e identidade de instância `UnitCarryLoad`.
4. **Conflito de mochila compartilhada (`UnitCarryLoad`):** rejeita com `"ambiguous_unit_identity"` se qualquer outra `Unit` viva em `GROUP_SELECTABLE_UNITS` (em qualquer mundo da árvore), qualquer participante de `ConstructionSite` no mesmo `World3D`, ou qualquer recibo comprometido em `RegionalAuthority` de `(world, region_id)` com `provenance_unit_id` diferente referenciar a mesma instância de `UnitCarryLoad`.
5. **Conflito de `provenance_unit_id` no domínio:**
   - Se a unidade-alvo possui metadado explícito `region_id` divergente de `region_id`, falha fechado (`"ambiguous_unit_identity"`).
   - Para cada outra unidade viva `other_u` no mesmo `World3D` (em `GROUP_SELECTABLE_UNITS` ou em `ConstructionSite`s do `World3D`) que tenha proveniência ativa e o mesmo `provenance_unit_id`:
     - Apura exclusivamente associações regionais **comprovadas** de `other_u` via `_collect_unit_proven_regions_readonly(...)`, usando apenas 4 fontes objetivas:
       1. Metadado explícito `other_u.get_meta(&"region_id")` (se válido);
       2. Participação ativa em `ConstructionSite` do `World3D` (`has_transit_claim_for_unit`, `_pending_pickups`, `_pending_deliveries`, `_active_builders`);
       3. Ordem econômica ativa em `other_u.get_current_order()` (`GatherResourceOrder` com `provenance_enabled` e `region_id` resolvido, ou `ConstructOrder` com `site.region_id`);
       4. Recibo já comprometido em `RegionalAuthority.receipts` no `World3D` contendo `other_load` com `other_prov_id`.
     - **Nunca** infere região por proximidade física, nome de nó ou `character_id`.
     - Se `other_u` tiver exatamente **1** região comprovada válida **estritamente diferente** de `region_id` (sem região inválida/conflitante), a convivência inter-regional é permitida.
     - Em **qualquer outro caso** (região igual a `region_id`, múltiplas regiões, região inválida, ou **nenhuma** região comprovada — unidade solta/ambígua no mesmo `World3D`), falha fechado com `{"ok": false, "reason": "ambiguous_unit_identity", "dependency": "unit"}`.
6. **Sem autoloads, sem persistência:** todo o estado continua limitado à sessão e ao escopo explícito da cena/domínio.

---

## 5. Proteção de capacidade e definição

Em `src/units/unit.gd`:

- `_is_definition_mutation_locked() -> bool` retorna `true` quando `_is_reserved_withdrawal_locked()` é `true` **ou** `_carry_load != null` e qualquer uma das travas `_coordinator_transaction_locked`, `_provenance_busy` ou `_provenance_applying` está ativa.
- Setter inline de `@export var definition`:
  1. Se `_is_definition_mutation_locked()`: retorna imediatamente sem alterar `definition`, `_carry_load`, `_movement` ou visuais.
  2. Se `value == null` (e destravado): permite atribuir `definition = null` normalmente.
  3. Se `_carry_load != null` e `not _carry_load.set_base_capacity(value.base_carry_capacity)`: retorna imediatamente **antes** de atribuir `definition = value` e **antes** de chamar `_sync_definition()`.
  4. Somente após o aceite de `set_base_capacity()` atribui `definition = value` e, se `is_node_ready()`, chama `_sync_definition()`.
- `apply_definition(def: CharacterDefinition) -> void`: mantém assinatura `void` e delega integralmente a `definition = def` (eliminando a duplicação anterior de `_sync_definition()`).
- `_sync_definition()`: guarda adicional para retornar cedo se `definition == null`, `_is_definition_mutation_locked()` ou `not _carry_load.set_base_capacity(definition.base_carry_capacity)` antes de atualizar `_movement` e visuais.
- **Preservações validadas:** modificadores aditivos/multiplicativos (`add_capacity_modifier` / `remove_capacity_modifier`), redução de capacidade abaixo da carga atual (sobrecarga intencional sem destruir carga existente nem quebrar o ledger de proveniência), bloqueios transacionais existentes e fluxo legado destravado permanecem intactos.

---

## 6. Testes RED/GREEN e regressão

### Fase RED (baseline `e53e95361645c41156d1c3864c7006ae06d9523f`, antes das correções em `src/`)

| Comando | Resultado |
| --- | --- |
| `.\tools\run_tests.ps1 -Filter test_t3_6_2_c4_5_unit_identity_capacity` | **Exit 1 (RED confirmado).** `1` suíte, `5` testes (`1` pass controle / `4` fail P3-A e P3-B), `105` asserções, `0` erros de suíte. |

### Fase GREEN e regressão completa (pós-correção)

| Comando | Resultado |
| --- | --- |
| `.\tools\run_tests.ps1 -Filter test_t3_6_2_c4_5_unit_identity_capacity` | **Exit 0.** `1` suíte, **`5/5 PASS`**, **`105` asserções**, `0` falhas, `0` erros/avisos. |
| `.\tools\run_tests.ps1 -Filter test_t3_6_2 -TimeoutSeconds 240` | **Exit 0.** `16` suítes (`b3_2`, `c1`, `c2`, `c3_1`–`c3_5`, `c4_2`–`c4_5`, `a`, `b2`), **`139/139 PASS`**, **`9.807` asserções**, `0` falhas, `0` erros/avisos. |
| `git diff --check` | **Exit 0.** (Sem problemas de whitespace/patch.) |
| `.\tools\validate.ps1` | **Exit 0.** **`Validation PASSED (0 errors, 0 warnings, 153 scripts checked)`**. |
| `.\tools\run_tests.ps1 -Segmented -GroupTimeoutSeconds 240` | **Exit 0.** **`14/14` lotes PASS** (`unit` + `integration-01`..`13`), **`59/59` suítes** (`Discovered=59 \| ExecutedUnique=59 \| Duplicates=0 \| Missing=0`), **`436/436 PASS`**, **`24.585` asserções**, `0` falhas, `0` erros de suíte, `0` erros/avisos Godot (`SumGodotElapsed: 540800,3 ms \| TotalWallElapsed: 550158,7 ms`). |

---

## 7. Evidências de conservação econômica

Verificado diretamente em `test_t3_6_2_c4_5_unit_identity_capacity.gd` e nas 16 suítes T3.6.2:

- **Rejeição em coleta (`GatherTransferSession`, `GatherResourceOrder`, `ResourceSource`):** quando a identidade é rejeitada por duplicidade, ambiguidade regional ou `UnitCarryLoad` compartilhado, a fonte mantém `remaining` inalterado, `get_active_worker_count() == 0` (sem vazamento de slot), a mochila mantém `total_units == 0`, `validate_provenance() == true` e nenhuma `RegionalAuthority` é criada nem tem `next_serial` avançado.
- **Rejeição em entrega ao acampamento (`SelectiveCampDeliveryPlanner`, `SelectiveCampDeliveryCoordinator`):** estoque do acampamento (`ResourceInventory`), pilha de solo (`GroundPileManager`), carga da unidade e ledger permanecem bit-a-bit idênticos; nenhum recibo ou serial é gravado.
- **Rejeição em canteiro (`ConstructionSite`, `ReservedWithdrawalCoordinator`):** claims de trânsito, `pending_pickups`, reservas de canteiro, pilha e carga da unidade não sofrem mutação; nenhum recibo ou serial é emitido.
- **Rejeição de `Unit.definition` / `apply_definition` sob trava ou capacidade inválida (P3-B):** durante `load_changed` pós-commit de `SelectiveCampDeliveryCoordinator`, `unit.definition`, `_movement._move_speed`, `base_capacity`, `effective_capacity`, peso carregado, estoque do acampamento e `validate_provenance()` permanecem completamente consistentes antes, durante e após a transação.

---

## 8. Requisitos P3 atendidos e pendências remanescentes

### Atendidos na C4.5

- **P3-A (integridade de identidade econômica em runtime):** validação uniforme e somente leitura cobrindo todas as unidades vivas no domínio (inclusive fora de `ConstructionSite`), detecção de `UnitCarryLoad` compartilhado, rejeição de IDs vazios/inválidos, falha fechada em associação regional ambígua, sem heurísticas de proximidade/nome/`character_id`, sem autoloads/persistência e sem mutações de inspeção.
- **P3-B (coerência atômica entre `Unit.definition` e `UnitCarryLoad`):** proteção contra divergência sob trava transacional real e capacidade negativa, preservando modificadores, sobrecarga, assinatura pública e modo legado.

### Pendências remanescentes (explicitamente fora do escopo C4.5)

- **Atribuição automática de `provenance_unit_id` único nas unidades de produção (`MainScene` / spawners):** propositalmente adiada para a etapa de integração/ativação controlada (`P2` / `D-INT-03`), pois `MainScene` deve permanecer em modo legado (proveniência desligada por padrão) na C4.5. Quando a proveniência for ativada no fluxo real, cada unidade precisará receber um `provenance_unit_id` único no domínio (sem reusar `character_id` compartilhado entre múltiplos trabalhadores).
- **Itens de prontidão ainda pendentes da C4.1:** `P2` (fluxo de ordens/HUD/feedback), `P4`, `P6`, `D-INT-01`, `D-INT-02`, `D-INT-03` e `DEC-T3.6-SIGNALS-01`.
- **Verificação visual/manual no editor:** não houve alteração visual ou ativação de proveniência em `MainScene`; a validação desta candidata é integralmente automatizada headless (`validate.ps1` + `436/436` testes segmentados).

---

## 9. Compatibilidade das regiões distintas e modo legado

- **Regiões distintas no mesmo `World3D`:** validado explicitamente em `test_t3_6_2_c4_5_unit_identity_capacity.gd::test_02` e preservado integralmente nas suítes pré-existentes `test_t3_6_2_c2_reserved_withdrawal_transaction.gd::test_r1_regions_worlds_and_domain_lifetime`, `test_t3_6_2_c3_2_selective_delivery_transaction.gd::test_operation_ids_are_isolated_across_regions_and_worlds` e `test_t3_6_2_c4_3_construction_transfer_session.gd::test_receipt_queries_are_typed_readonly_and_region_specific`. Duas unidades com o mesmo `provenance_unit_id` em regiões comprovadamente distintas operam de forma isolada sem interferência.
- **Mesmo `character_id` com `provenance_unit_id` distinto:** validado em `test_01` e `test_05` — unidades compartilhando a mesma `CharacterDefinition` operam normalmente desde que possuam `provenance_unit_id` e `UnitCarryLoad` distintos.
- **Modo legado:** `MainScene` e `CommandController` não foram modificados; todos os testes T1, T2, T3.2–T3.5 e `test_05` (coleta/entrega/remoção em modo legado e troca normal de `CharacterDefinition` destravada) passaram integralmente.

---

## 10. Parecer objetivo da candidata

**CANDIDATA C4.5 PRONTA PARA AUDITORIA.**

- Escopo estritamente respeitado (somente **P3-A** e **P3-B**; `main` intocada; proveniência desligada por padrão no fluxo RTS normal).
- Falhas P3-A e P3-B reproduzidas em RED no baseline `e53e953` e eliminadas em GREEN com conservação econômica comprovada.
- Validação técnica limpa (`validate.ps1`: `153` scripts, `0` erros/avisos; regressão segmentada: `14/14` lotes, `59/59` suítes, `436/436` testes, `24.585` asserções, `0` falhas/erros/avisos).
- Aguardando auditoria técnica independente do ChatGPT e autorização expressa antes de qualquer avanço para etapas posteriores (`C4.6`, ativação global ou merge).
