# DAWN OF KIN — RELATÓRIO TÉCNICO CANDIDATO T3.4.1

**Etapa:** `T3.4.1` — Contabilidade Separada, Complementação Manual (`DEC-11B`), Intenção Tipada (`ManualComplementIntent`) e Estados do Canteiro<br>
**Status:** **CANDIDATA PARA AUDITORIA INDEPENDENTE — NÃO HOMOLOGADA / SEM MERGE**<br>
**Branch:** `feat/t3-4-1-accounting-reservations`<br>
**Worktree Isolado:** `C:\Projetos\Dawn_of_Kin_wt_t3_4_1`<br>
**Base Oficial (`origin/main`):** `518aec6da477c6105b60844a106cb7322246b53a`<br>
**Arquitetura Referência Aprovada (`T3.4-R2.3`):** commit `da20244f4320f0ae5e03236553f5c0e3f57f3a6f` (registro de aprovação `39cdaac674d78111efd300b70b8f2f3909e347f9` em `planning/t3-4-architecture-r2`)<br>
**Último Marco Homologado:** `t3-3-complete` (`c7947c9630c102a9d77603cac0bae68678247c95`)<br>
**Engine Validada:** Godot `4.7.2.stable.official.ed1daf0bf` (`--headless`)<br>
**Data:** 16 de novembro de 2026

---

## 1. Escopo Implementado na T3.4.1 vs. Etapas Bloqueadas

### Implementado exclusivamente na T3.4.1
1. **Contabilidade separada em [`ConstructionSite`](../../src/buildings/construction_site.gd) (`§3.2`):**
   - Adicionado `_consumed_materials: Dictionary` inicializado com `0` para todo recurso exigido em `configure()` (sem consumo progressivo nesta etapa).
   - Adaptados os `8` contratos da matriz `§3.2`: `get_consumed_amount()`, `get_total_received_amount()`, `get_remaining_need_for_dropoff()`, `get_missing_amount()`, `is_fully_supplied()`, `get_remaining_supply_to_claim()`, `record_withdrawn_for_site()` e `accept_delivery_from_carry_load()`, além de getters complementares (`get_consumed_amounts()`, `get_total_received_amounts()`, `get_accounting_breakdown()`, `verify_accounting_invariant()`).
   - Preservado o comportamento `T3.3-R1` de `_transit_claims` em interrupções de trabalhadores (sem apagar ou reduzir carga atribuída em trânsito quando a ordem é interrompida).
2. **Backend transacional de complementação `DEC-11B`:**
   - Contrato base em [`SettlementStorageSource`](../../src/economy/settlement_storage_source.gd): `can_complement_reservation()` e `complement_reservation()`.
   - Implementação em [`InMemoryStorageSource`](../../src/economy/in_memory_storage_source.gd) com snapshot/rollback, permissão para `reservation_id` existente (inclusive com saldo anterior reduzido a `0`) e preservação de `_reservation_order`.
   - Implementação em [`GroundPileManager`](../../src/economy/ground_pile_manager.gd) via helper compartilhado `_build_reserve_plan_internal(reservation_id, amounts, allow_existing)` e `_commit_reserve_entries()` com snapshot/rollback em `_ledger`, mantendo `reserve_batch()` bloqueado para IDs já existentes e impedindo qualquer toque em reservas de outras obras.
   - Fachada delegada em [`SettlementInventory`](../../src/economy/settlement_inventory.gd).
3. **Intenção tipada e API manual em `ConstructionSite` (`R2-01 §3`):**
   - Novo script [`ManualComplementIntent`](../../src/buildings/manual_complement_intent.gd) (`OriginKind.PLAYER_UI` e `OriginKind.TEST_HARNESS`), atuando estritamente como mecanismo arquitetural de rastreabilidade de origem, uso único e proteção contra disparo acidental.
   - Rejeição estrutural de `null`, reuso (`consumed == true`), alvo incompatível, criação manual fora de fábrica, UI `Control` fora da árvore (`PLAYER_UI`), e emissores proibidos (`SettlementStorageSource`, `SettlementInventory`, `EconomyClockController`, `UnitOrder` e derivados, `ConstructionSite`, `ConstructionManager`).
   - Em `authorize_manual_complement(intent, requested_amounts = {}, allow_partial = false)` (sem default em `intent`): consumo imediato (`intent.consumed = true`) logo após validação estrutural — **inclusive quando a operação falha por `insufficient_free_stock`, reentrância ou pré-condição** — mais guarda `_is_complementing` contra reentrância em sinais (`"reentrant_complement_blocked"`), `get_complementable_missing_amounts()` e `can_authorize_manual_complement()`.
4. **Estrutura formal de estados em `ConstructionSite` (`R2-02 §1`):**
   - Introduzidos os enums `SiteState` (`UNCONFIGURED`, `ACTIVE`, `COMPLETING`, `COMPLETION_FAILED_RETRYABLE`, `COMPLETION_BLOCKED_ERROR`, `COMPLETED`) e `AssemblySubstate` (`NONE`, `WAITING_ASSEMBLY`, `ASSEMBLING`, `PAUSED_STARVED`, `PAUSED_NO_WORKERS`), getters (`get_site_state()`, `get_assembly_substate()`, `is_active()`), inicialização `UNCONFIGURED/NONE -> ACTIVE/WAITING_ASSEMBLY` em `configure()`, e inclusão aditiva em `get_status_snapshot()`.

### Estritamente fora do escopo (permanece planejado/bloqueado)
- **T3.4.2:** `contribute_work()`, aritmética determinística em microssegundos e ocupação real de slot atribuído (`BuildSlotPlanner`).
- **T3.4.3:** `ConstructOrder.Phase.WAITING_FOR_MATERIALS`, retomada por sinais, promoções `D9`/`DEC-18` e montagem ativa.
- **T3.4.4:** `BuildingInstance`, `complete_site_transaction()` e proteção contínua contra sobreposição em edifícios concluídos.
- **T3.4.5:** Inclusão regional `N1` e barreira transitória `_pending_building_blockers` em `WorldNavigation`/`UnitMovement`/`CommandController`, além de benchmark `T34-PERF-01`.
- **T3.5–T3.9:** UI definitiva (`BuildingInspectorPanel`), reembolso `D3`, Depósito Rústico funcional e persistência `SaveManager`. Nenhuma UI provisória ou botão de jogador foi criado na `T3.4.1`.

---

## 2. Preservação da Invariante Contábil

Para todo recurso exigido $R$ em um canteiro ativo:

$$\text{required}(R) = \text{reserved}(R) + \text{in\_transit}(R) + \text{delivered\_buffer}(R) + \text{consumed}(R) + \text{uncovered\_missing}(R)$$

- Todas as `5` parcelas pertencem a $\mathbb{Z}_{\ge 0}$: `_consumed_materials[R] >= 0`, `_delivered_buffer[R] >= 0`, `get_reserved_in_piles_amount(R) >= 0`, `get_in_transit_amount(R) >= 0` (com `_clamp_unit_transit_claim()` mantendo cada claim $\le$ saldo real da mochila) e `get_missing_amount(R) = maxi(0, required - total_received - reserved - in_transit)`.
- `record_withdrawn_for_site()` limita qualquer adição a `accounting_headroom = maxi(0, required - total_received - reserved - in_transit)`.
- `accept_delivery_from_carry_load()` limita cada entrega a `mini(claimed, mini(need, mini(carried, invariant_cap)))`, onde `invariant_cap = maxi(0, required - total_received - reserved - other_in_transit)`.
- Logo, $\text{reserved} + \text{in\_transit} + \text{delivered\_buffer} + \text{consumed} \le \text{required}$ vale em todo estado válido, garantindo que a soma das `5` parcelas seja sempre exatamente igual a `required`, sem duplicação ou saldo negativo mesmo após decaimento (`step_decay()`), interrupção de transporte ou complementação manual (`DEC-11B`).

---

## 3. Arquivos Modificados e Criados

- Modificados (`src/`):
  - [`src/economy/settlement_storage_source.gd`](../../src/economy/settlement_storage_source.gd)
  - [`src/economy/in_memory_storage_source.gd`](../../src/economy/in_memory_storage_source.gd)
  - [`src/economy/ground_pile_manager.gd`](../../src/economy/ground_pile_manager.gd)
  - [`src/economy/settlement_inventory.gd`](../../src/economy/settlement_inventory.gd)
  - [`src/buildings/construction_site.gd`](../../src/buildings/construction_site.gd)
- Criados (`src/`, `tests/`, `docs/`):
  - [`src/buildings/manual_complement_intent.gd`](../../src/buildings/manual_complement_intent.gd) *(+ `.gd.uid`)*
  - [`tests/unit/test_t3_4_1_accounting_and_complement.gd`](../../tests/unit/test_t3_4_1_accounting_and_complement.gd) *(+ `.gd.uid`)*
  - [`docs/testing/T3_4_1_candidate_report.md`](T3_4_1_candidate_report.md) *(este relatório)*

---

## 4. Registro das Duas Condições Vinculantes de Teste

1. **Condição 1 — `T34-AUT-01` ([`test_01_t34_aut_01_authorized_complement_after_decay_cond_1`](../../tests/unit/test_t3_4_1_accounting_and_complement.gd)):**
   - Usando `Abrigo Básico` real (`12` madeiras, `6` pedras) e os parâmetros reais de [`decay_wood_provisional.tres`](../../data/resources/decay_wood_provisional.tres) (`420 s` carência, `120 s` por unidade), o fixture reserva integralmente as **`6` pedras** antes da autorização com lote vazio `{}`, impedindo que déficit de pedra interfira na reposição das `4` madeiras perdidas (`+1200.0 s`, perda `10 w` na Pilha 1, criação da Pilha 2 livre pós-decay sem auto-reserva via `try_create_pile_at()`). O teste também valida explicitamente o caminho alternativo `{&"wood": 4}` quando há déficit separado de pedra.
2. **Condição 2 — `T34-AUT-03` ([`test_04_t34_aut_03_multi_site_shared_pile_decay_cond_2`](../../tests/unit/test_t3_4_1_accounting_and_complement.gd)):**
   - Utiliza explicitamente `BuildingDefinition` exclusivo de teste com requisito de **`5` madeiras** por obra (`test_5wood_a` e `test_5wood_b`, sem alterar [`shelter_basic.tres`](../../data/buildings/shelter_basic.tres) nem o `GDD v1.2`). Pilha 1 (`10 w`, `elapsed = 420.0 s`) e Pilha 2 (`4 w` livres, `elapsed = 0.0 s`) são criadas via `try_create_pile_at()`, sofrendo avanço simultâneo de `+480.0 s` em `step_decay()`: Pilha 1 perde `4 w` (reduzindo apenas Obra B de `5 -> 1 w`, preservando Obra A em `5/5 w`), Pilha 2 perde `0 w` (`accum = 60.0 s < 120.0 s`), e o complemento manual atende somente a Obra B.

---

## 5. Resultados Reais de Validação e Testes Executados

Todos os comandos abaixo foram executados no worktree isolado `C:\Projetos\Dawn_of_Kin_wt_t3_4_1` após a edição final de código e testes:

1. **Validação Godot (`.\tools\validate.ps1`):**
   - `--headless --import`, `--check-only` em **`111` scripts** e `--quit-after 3` na cena principal.
   - Resultado: **`Validation PASSED (0 errors, 0 warnings, 111 scripts checked)`** (`exit code 0`).
2. **Novos testes da T3.4.1 (`res://tests/unit/test_t3_4_1_accounting_and_complement.gd`):**
   - **`8/8` aprovados**, **`299` asserções**, `0` falhas, `0` erros/avisos:
     - Cobertura inicial (`6` testes, `212` asserções): `T34-AUT-01`, `T34-AUT-01B`, `T34-AUT-02`, `T34-AUT-03`, `T34-AUT-04`, contratos `SiteState`/`AssemblySubstate` e `8` getters.
     - **Auditoria complementar (`2` testes adicionais, zero alterações em código de produção):**
       - `test_07_zeroed_wood_reservation_in_ground_pile_manager_and_manual_recreation` (**`36` asserções**): valida com `GroundPileManager` real o decaimento total (`12 -> 0 w`), desaparecimento completo da reserva no `PileReservationLedger` (`has_reservation == false`), ausência de realocação automática ao criar nova pilha (`15 w` livres) e recriação integral da reserva sob o mesmo `reservation_id` via `ManualComplementIntent`.
       - `test_08_multi_resource_atomicity_wood_ok_stone_short_and_retry` (**`51` asserções**): valida atomicidade multirrecurso (`allow_partial = false`) com madeira suficiente (`5 >= 4`) e pedra insuficiente (`2 < 3`), confirmando `ok = false` (`insufficient_free_stock`), zero reserva adicional, saldos físicos e reserva de outra obra intactos, invariante preservada, consumo do ticket na falha (`intent_fail.consumed == true`) e sucesso integral após disponibilizar pedra e enviar novo ticket (`{&"wood": 4, &"stone": 3}`).
3. **Regressões T3.1–T3.3 e Suíte Segmentada Completa (`.\tools\run_tests.ps1 -Segmented`):**
   - `test_t3_1_reservations.gd`: **`17/17`** (`432` asserções).
   - `test_t3_2_placement_validation.gd`: **`7/7`** (`134` asserções).
   - `test_t3_2_placement_flow.gd`: **`5/5`** (`111` asserções).
   - `test_t3_3_construction_site.gd`: **`7/7`** (`164` asserções).
   - `test_t3_3_ux_display_and_workers.gd`: **`2/2`** (`9` asserções).
   - `test_t3_3_construction_logistics.gd`: **`11/11`** (`205` asserções).
   - `test_t3_3_ux_flow.gd`: **`3/3`** (`55` asserções).
   - **Totais da suíte segmentada completa (`7` lotes isolados):** **`35/35` suítes**, **`242/242` testes aprovados**, **`0` falhas**, **`0` erros de suíte**, **`7.882` asserções**, `Discovered=35 | ExecutedUnique=35 | Duplicates=0 | Missing=0` (`exit code 0`).
   - **Reconciliação exata das asserções entre a execução anterior (`240` testes / `7.798` asserções) e a atual (`242` testes / `7.882` asserções, $\Delta = +84$):**
     - `test_t3_4_1_accounting_and_complement.gd`: **`+87`** (`212 -> 299`, pelos `2` novos testes: `test_07` = `36` e `test_08` = `51`).
     - [`test_t2_natural_source_states.gd`](../../tests/integration/test_t2_natural_source_states.gd): **`+1`** (`103 -> 104`, em `test_03_concurrent_workers_single_felling_and_cancel_before_vs_after_extract`: `34 -> 35`, pois o loop `while` executa `assert_eq(total_w, initial_1)` por quadro de física até concluir, variando em `+1` quadro de simulação).
     - [`test_t2_worker_cycle.gd`](../../tests/integration/test_t2_worker_cycle.gd): **`-4`** (`2660 -> 2656`, em `test_03_solid_obstacle_approach_clearance_and_two_concurrent_workers_no_deadlock`: `142 -> 138`, pois o loop `while` executa `2` asserções de distância por trabalhador em `Unit.State.WORKING` por quadro de física, variando em `-2` worker-frames em `WORKING`).
     - Demais `32` suítes (incluindo todas as `7` suítes `T3.1–T3.3` e todas as `17` unitárias anteriores): **`0`** de variação (`delta = 0`).
     - Soma exata: `87 + 1 - 4 = +84` (`7.798 + 84 = 7.882`). Zero erro de transcrição e zero falha.
4. **Não verificado / fora do escopo:** testes visuais/UI interativos do botão manual (não aplicável nesta etapa porque `BuildingInspectorPanel` pertence à `T3.5`).

---

## 6. Problemas Encontrados e Corrigidos Durante a Implementação

- No primeiro rascunho de [`test_t3_4_1_accounting_and_complement.gd`](../../tests/unit/test_t3_4_1_accounting_and_complement.gd), o helper `_make_test_building_def` usou erroneamente `construction_time_sec` em vez da propriedade real `build_work_required_sec` de [`BuildingDefinition`](../../src/buildings/building_definition.gd), e `test_06` tentou carregar `12` madeiras (peso `24`) em uma única viagem com capacidade máxima `20` de `LeaderA` (`10` madeiras/viagem). Ambos os desvios foram corrigidos no arquivo de teste (`2` viagens de entrega para madeira em `test_06`), mantendo as regras reais de peso e definição de edifícios sem alterações no código de produção.

---

## 7. Pendências Técnicas e de Governança Reais

- Auditoria independente do ChatGPT e revisão/aceite do proprietário sobre este candidato `T3.4.1` na branch `feat/t3-4-1-accounting-reservations`.
- Autorização expressa futura antes de iniciar a implementação de **`T3.4.2`** (`contribute_work`, microssegundos e ocupação de slot) ou etapas subsequentes (`T3.4.3–T3.4.5`).
