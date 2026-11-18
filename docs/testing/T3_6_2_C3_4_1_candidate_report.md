# Dawn of Kin — Relatório Técnico da Candidata T3.6.2-C3.4.1
## Preparação pura e validação da descarga seletiva no acampamento

**Status da candidata:** **T3.6.2-C3.4.1 — Publicada para auditoria independente** (não homologada; C3.4 **não** concluída; commit econômico de descarga seletiva **intencionalmente ausente** nesta etapa).

---

## Classificação de estado (separação obrigatória)

| Categoria | Itens concretos |
| --- | --- |
| **Implementado** | `SelectiveCampDeliveryPlanner` (`src/economy/selective_camp_delivery_planner.gd`) com `prepare_selective_camp_delivery(...)` e `validate_selective_camp_delivery_plan(...)`; auxiliar puro somente-leitura `ReservedWithdrawalCoordinator.inspect_camp_domain_for_preparation(...)` (`src/economy/reserved_withdrawal_coordinator.gd`). |
| **Testado automaticamente** | Suíte adversarial `tests/integration/test_t3_6_2_c3_4_1_selective_camp_delivery_prep.gd` (21 funções de teste cobrindo os 53 cenários dos Grupos A–E + isolamento regional/mundo/busy/conflito, 2.668 asserções); filtros T3.6.2 (`c3_4_1`, `c3_3`, `c3_2`, `c3_1`, `c2`, `test_t3_6_2`); validação Godot (`validate.ps1`, 140 scripts, 0 erros, 0 avisos); regressão segmentada completa (`run_tests.ps1 -Segmented`: 51 suítes, 372/372 testes, 17.682 asserções, 0 falhas/erros/vazamentos). |
| **Não testado manualmente** | Nenhum teste visual/manual em cena jogável foi executado — esta etapa é estritamente preparação pura em memória (`dry_run_only = true`, `commit_supported = false`, `physical_delivery_authorized = false`) sem alteração de ordens, UI ou fluxo jogável. |
| **Planejado** | T3.6.2-C3.4.2 (coordenador transacional de commit atômico de descarga seletiva no acampamento + restauração atômica de reserva física e autorização de proximidade); integração opt-in posterior em `DeliverToCampOrder` / `ConstructOrder`. |
| **Bloqueado** | Devolução de lotes `SITE_RESERVED` pertencentes a obras em estados não ativos (`COMPLETED`, `COMPLETING`, `COMPLETION_FAILED_RETRYABLE`, `COMPLETION_BLOCKED_ERROR`) — bloqueada explicitamente com `"d3_cancellation_not_implemented"` até implementação da custódia D3 (`CANCEL_TRANSIT`, `CANCEL_BUFFER`, `CANCEL_INCORPORATED`). |
| **Pendente de decisão** | `DEC-T3.6-SIGNALS-01` (política de guarda vs. liberação antes da publicação de sinais em transações econômicas; mantida inalterada na C2-R1 e C3.2 e sem publicação de sinais na C3.4.1); aprovação formal das decisões abertas da proposta T3.6-R2; eventual contador de revisão monotônico dedicado em `CampStorageZone`. |

---

## 1. SHA-base

- **SHA-base obrigatório verificado antes de editar:** `8a7851f699db13bc0cc714e005e09f5b5bc75319` (`feat/t3-6-2-provenance-transactions` local e `origin/feat/t3-6-2-provenance-transactions` idênticos, árvore limpa).
- **Referência da `main` verificada:** `25e0a20f1d6a2f10a9e059afe69759fbe263db4a` (inalterada).
- **Engine verificada:** Godot `4.7.2.stable.official.ed1daf0bf`.
- **Commits desta candidata (sobre `8a7851f699db13bc0cc714e005e09f5b5bc75319`):**
  - Implementação (`feat`): `36f12efcfc401b2b1ac79e59df11ea67c1559be1`
  - Testes adversariais (`test`): `a28e2697df2b5dcec6eba0fbf66a76bb04379d97`
  - Documentação (`docs`): commit seguinte contendo este relatório.

## 2. Branch e worktree utilizados

- **Repositório:** `Julian0s/Dawn-of-Kin`
- **Branch:** `feat/t3-6-2-provenance-transactions`
- **Worktree:** `C:\Projetos\Dawn_of_Kin_wt_t3_4_5`
- O worktree principal `C:\Projetos\Dawn of Kin` não foi modificado.

## 3. Documentação consultada

- `AGENTS.md`
- `docs/Dawn_of_Kin_GDD.md` (v1.2)
- `docs/architecture/T3_architecture_PROPOSAL.md`
- Proposta arquitetural T3.6-R2 consultada diretamente no objeto Git original `69c13275a34a30564ac839ec920f83ef36590812:docs/architecture/T3_6_cancellation_architecture_R2_PROPOSAL.md` (sem criar cópia substituta na branch candidata; continua sendo proposta com decisões pendentes).
- `docs/testing/T3_6_2_C2_R1_candidate_report.md`
- `docs/testing/T3_6_2_C3_1_candidate_report.md`
- `docs/testing/T3_6_2_C3_2_candidate_report.md`
- `docs/testing/T3_6_2_C3_3_candidate_report.md`
- Código-fonte inspecionado integralmente: `carry_provenance_ledger.gd`, `unit_carry_load.gd`, `ground_pile_manager.gd`, `ground_resource_pile.gd`, `pile_reservation_ledger.gd`, `settlement_inventory.gd`, `settlement_storage_source.gd`, `in_memory_storage_source.gd`, `camp_storage_zone.gd`, `reserved_withdrawal_coordinator.gd`, `selective_site_delivery_planner.gd`, `selective_site_delivery_coordinator.gd`, `deliver_to_camp_order.gd`, `gather_slot_planner.gd`, `construction_transfer_session.gd`, `construct_order.gd`, `construction_site.gd`, `world_navigation.gd`, `selective_site_delivery_fixture.gd`.

## 4. Contratos normativos aplicáveis

- **Proveniência vigente (`CarryProvenanceLedger`):** apenas `FREE_GATHERED` e `SITE_RESERVED`; nenhuma categoria futura de cancelamento D3 foi criada.
- **Isolamento legado (`SettlementInventory` / `UnitCarryLoad`):** mochilas sem proveniência permanecem intocadas e rejeitadas pelo novo planejador (`"provenance_disabled"`); `SettlementInventory.deliver_from_carry_load()` não foi alterado.
- **Armazenamento físico (`GroundPileManager` + `CampStorageZone` + `PileReservationLedger`):** reutilização fiel das regras determinísticas de ordenação de pilhas por `pile_id` ascendente, `max_pile_amount`, `get_candidate_slots()`, `validate_pile_position()`, `_compute_merged_state()` (`WEIGHTED_AVERAGE` / `KEEP_OLDEST`), afastamento `min_pile_clearance` e validação de `WorldNavigation`.
- **Autoridade regional compartilhada (`ReservedWithdrawalCoordinator`):** preservação da mesma tabela `world.get_meta(&"_reserved_withdrawal_domains")` da C2-R1 e C3.2, sem criar segunda contabilidade global, sem criar `RegionalAuthority`, sem registrar recibos e sem consumir `construction_transfer_serial`.
- **Contabilidade de obra (`ConstructionSite` / `SelectiveSiteDeliveryPlanner._read_accounting`):** invariante `required == reserved + transit + buffer + consumed + missing` preservado sem alterar buffer, material incorporado, progresso, déficit descoberto ou claims de outras unidades/obras.

## 5. Divergências identificadas

1. **Inspeção de domínio regional sem `ConstructionSite` obrigatório:** `ReservedWithdrawalCoordinator.inspect_domain_for_preparation(site, storage, operation_id)` exige um `ConstructionSite` como ponto de entrada, enquanto uma descarga no acampamento pode ocorrer com zero canteiros em cena (somente lotes `FREE_GATHERED`). **Resolução:** adicionado o auxiliar irmão estritamente somente-leitura `ReservedWithdrawalCoordinator.inspect_camp_domain_for_preparation(world, region_id, inventory, storage, operation_id, tree)`, que valida `RegionalAuthority`, vínculo de `storage._withdrawal_world`/`_withdrawal_region`, `_piles_root` e todos os `ConstructionSite`s vivos sem criar autoridade nem gravar metadata.
2. **Ausência de contador de revisão em `CampStorageZone`:** `CampStorageZone` não possui `_transaction_revision` próprio. **Resolução:** o planejador captura em `revisions.camp_config` o retrato completo de configuração (`zone_id`, `anchor`, `half_extents`, `slot_spacing`, `min_pile_clearance`, `max_pile_amount`, `decay_multiplier`, `max_nav_snap_distance`, `merge_exposure_policy`, `piles_root_global_pos`, `nav_instance_id`, `nav_ready`, `nav_revision`, `has_custom_validator`) e recalcula toda a projeção de slots em `validate_selective_camp_delivery_plan(...)`. Um caso puramente ABA em campos exportados de `CampStorageZone` que voltem ao valor exato anterior sem mudança em `storage`/`piles`/`nav` permanece documentado como limitação na Seção 18.
3. **Projeção física destacada vs. `GroundPileManager._build_deposit_plan`:** `_build_deposit_plan` retorna referências diretas a nós `GroundResourcePile` e não projeta reservas por origem nem identificadores virtuais de pilhas novas. **Resolução:** `SelectiveCampDeliveryPlanner` espelha fielmente os critérios de `_build_deposit_plan` (incluindo `_compute_merged_state`, `get_candidate_slots`, `validate_pile_position` e `_world_to_piles_local`) emitindo apenas structs de dados destacados e IDs virtuais (`&"virtual_pile:0"`, `&"virtual_pile:1"`, ...) sem consumir `storage._next_pile_id`.
4. **Getters com efeitos colaterais em `ConstructionSite`:** métodos públicos como `get_in_transit_amounts()`, `get_transit_claim_for_unit()`, `get_missing_amounts()` e `get_resource_definition()` executam `_prune_stale_state()` ou mutam `_resource_defs`. **Resolução:** nenhum desses métodos é chamado; o planejador utiliza exclusivamente leitores comprovadamente puros (`_read_transit_claim_for_unit_pure`, `_resolve_resource_definition_pure`, `SelectiveSiteDeliveryPlanner._read_accounting`, `get_required_amounts`, `get_delivered_buffer_amounts`, `get_consumed_amounts`, `get_site_state`, `get_generation`, `get_transaction_revision`, `is_valid`, `is_transaction_busy`).
5. **Política de sinais (`DEC-T3.6-SIGNALS-01`):** permanece pendente entre C2-R1/C3.2 e a proposta R2. A C3.4.1 não emite sinais e não modifica o comportamento de guarda da C2-R1 nem da C3.2.

## 6. Arquitetura do planejador

`SelectiveCampDeliveryPlanner` (`class_name SelectiveCampDeliveryPlanner extends RefCounted`) organiza o planejamento em etapas puras e fechadas em falha (fail-closed):

1. **Verificação de thread e entrada:** main thread, `operation_id`, `region_id`, parse estrito e canonização de `requested_lots`.
2. **Validação dos participantes e isolamento de mundo/região:** `Unit`, `World3D`, `SettlementInventory`, `GroundPileManager`, `CampStorageZone`, `_piles_root`, `WorldNavigation` (se vinculada), `UnitCarryLoad` com proveniência habilitada, guardas `busy` e `ReservedWithdrawalCoordinator.inspect_camp_domain_for_preparation(...)`.
3. **Varredura pura de `ConstructionSite`s e identidade de unidade:** particiona canteiros por domínio `(world, region)` vs. outra região/outro mundo, detecta `site_id` ou `reservation_id` duplicados, rejeita canteiros ocupados e conflitos de identidade de unidade (`ConstructionSite._unit_conflicts_with_target`).
4. **Integridade da mochila e do ledger:** reconstrói `CarryProvenanceLedger` destacado via `restore_transaction_state`, valida agregado, ausência de conflito de `operation_id`, pertencimento de todos os lotes a `cargo.unit_id` e consistência exata de pesos com `storage.get_resource_definition_pure` e `load.get_current_weight()`.
5. **Auditoria de integridade do armazenamento físico:** ordena pilhas por `pile_id`, valida `pile.is_valid()`, `World3D`, pesos, `pile_reserved <= pile.amount` e ausência de entradas órfãs ou divergentes em `storage._ledger`.
6. **Classificação de proveniência por lote e resolução de seleção determinística.**
7. **Simulação isolada de débitos no ledger clonado** com IDs sintéticos não colidentes (`c3.4.1:<len>:<op>:<idx>`) e revalidação de agregado e peso residual.
8. **Projeção física de mesclagens/criações e restauração de reservas** com verificação explícita de conservação por pilha, por obra e no acampamento global.

## 7. APIs e formatos de resultado

### Assinaturas públicas
- `SelectiveCampDeliveryPlanner.prepare_selective_camp_delivery(inventory: SettlementInventory, camp_zone: CampStorageZone, unit: Unit, region_id: Variant, operation_id: Variant, requested_lots: Variant = []) -> Dictionary`
- `SelectiveCampDeliveryPlanner.validate_selective_camp_delivery_plan(inventory: SettlementInventory, camp_zone: CampStorageZone, unit: Unit, region_id: Variant, plan: Variant) -> Dictionary`

### Campos obrigatórios presentes em todos os resultados de preparação (sucesso e falha)
- `ok`: `bool`
- `reason`: `String` (`""` em sucesso; código estável em falha)
- `dependency`: `String`
- `dry_run_only`: sempre `true`
- `commit_supported`: sempre `false`
- `physical_delivery_authorized`: sempre `false`
- `validation_scope`: `"accounting_and_storage_projection_only"`
- `operation_id`: `StringName`
- `identity`: `Dictionary` (`world`, `region_id`, `inventory`, `storage`, `camp_zone`, `camp_zone_id`, `piles_root`, `unit`, `unit_id`, `load`, `sites`)
- `requested_lots`: `Array[Dictionary]` normalizado e ordenado por `String(lot_id)`
- `selected_lots`: `Array[Dictionary]` com `lot_id`, `unit_id`, `resource_id`, `origin`, `site_id`, `generation`, `reservation_id`, `unit_weight`, `original_quantity`, `selected_quantity`, `residual_quantity`, `destination_class`, `debit_operation_id`, `physical_targets`
- `deliverable_amounts`: `Dictionary` (`{resource_id: int}`, chaves ordenadas)
- `destination_classes`: `{"by_lot": ..., "by_class": ...}`
- `before` / `after`: `cargo`, `weight`, `capacity`, `camp_physical_amounts`, `camp_reserved_amounts`, `camp_free_amounts`, `sites`
- `deposit_projection`: `merges`, `creates`, `total_added_by_resource`, `merge_count`, `create_count`, `requires_atomic_commit`
- `reservation_projection`: `requires_atomic_deposit_and_reservation`, `preserved_existing_pile_reservations`, `restorations`, `by_site`
- `blocked_lots`: `Array[Dictionary]` (lotes não elegíveis ou exigindo seleção explícita)
- `revisions`: `load`, `inventory`, `storage`, `pile_ledger`, `next_pile_id`, `piles`, `sites`, `camp_config`, `ledger_operation_count`, `ledger_used_lot_count`

### Códigos de erro estáveis implementados
`wrong_thread`, `invalid_operation`, `invalid_region`, `invalid_request`, `duplicate_lot_request`, `invalid_unit`, `invalid_domain`, `invalid_inventory`, `unsupported_storage_source`, `invalid_camp_zone`, `invalid_piles_root`, `world_mismatch`, `region_mismatch`, `ambiguous_domain`, `provenance_disabled`, `busy`, `operation_conflict`, `ambiguous_unit_identity`, `invalid_ledger`, `unreconciled_cargo`, `resource_or_weight_mismatch`, `weight_overflow`, `amount_overflow`, `conflicting_site_claims`, `unknown_reserved_site`, `invalid_site`, `d3_cancellation_not_implemented`, `generation_mismatch`, `carry_load_mismatch`, `insufficient_transit_claim`, `unreconciled_site_claim`, `accounting_invariant_violated`, `invalid_transit_claim`, `resource_not_required`, `lot_not_found`, `requested_amount_exceeds_lot`, `no_eligible_free_lots`, `lot_debit_conflict`, `unreconciled_projection`, `no_valid_camp_slot`, `navigation_not_ready`, `reservation_restoration_unavailable`, `invalid_plan`, `identity_mismatch`, `stale_revision`, `tampered_or_stale_plan`.

## 8. Classificação de proveniência

- **`FREE_GATHERED`:** elegível para `DEST_CAMP_FREE_STOCK` (`&"camp_free_stock"`), projetando incremento físico e livre iguais no acampamento (`camp_physical_after = camp_physical_before + q`, `camp_free_after = camp_free_before + q`, `carried_after = carried_before - q`).
- **`SITE_RESERVED` (obra ativa no mesmo mundo e região):** exige seleção explícita; valida existência do canteiro, `is_valid()`, `SiteState.ACTIVE`, `generation`, `reservation_id` não duplicado, claim de trânsito da unidade reconciliado exatamente com a soma dos lotes daquela obra para o recurso, definição de recurso/peso e invariante contábil completo (`SelectiveSiteDeliveryPlanner._read_accounting`). Classificado em `DEST_SITE_RESERVED_RESTORATION` (`&"site_reserved_restoration"`), projetando `transit_after = transit_before - q` e `reserved_after = reserved_before + q` sem alterar `buffer`, `consumed`, `required` ou `missing`.
- **`SITE_RESERVED` (outra obra):** lotes são endereçados individualmente por `lot_id`; uma solicitação para obra A nunca consome nem transborda para lotes da obra B, mesmo sendo do mesmo recurso.
- **`SITE_RESERVED` (obra concluída / em conclusão / falha de conclusão / bloqueada):** bloqueado explicitamente com `"d3_cancellation_not_implemented"` e nunca reclassificado para `FREE_GATHERED`.
- **`SITE_RESERVED` (obra inexistente / inválida / outra região / outro mundo):** bloqueado com `"unknown_reserved_site"`, `"invalid_site"`, `"region_mismatch"` ou `"world_mismatch"`; nunca reclassificado para `FREE_GATHERED`.

## 9. Regras de seleção

- Solicitação explícita exige `Array` de `Dictionary` com exatamente 2 chaves (`"lot_id"`, `"amount"`), `lot_id` válido, `amount` inteiro `> 0`, sem duplicatas (inclusive alias `String` vs `StringName`) e sem campos extras forjados pelo chamador.
- Todos os atributos (`unit_id`, `resource_id`, `origin`, `site_id`, `generation`, `unit_weight`) são obtidos exclusivamente do ledger vigente.
- **Semântica conservadora para solicitação vazia (`[]`):** seleciona **apenas** lotes `FREE_GATHERED` elegíveis; lotes `SITE_RESERVED` permanecem intocados em `after.cargo` e são reportados em `blocked_lots` (`"explicit_selection_required"` se obra ativa elegível, ou seu motivo de bloqueio específico). Se não houver nenhum lote `FREE_GATHERED`, retorna falha `"no_eligible_free_lots"` com `blocked_lots` preenchido.
- **Ordenação determinística:** `requested_lots` ordenado por `String(lot_id)`; `selected_lots` e `blocked_lots` ordenados por `(String(resource_id), String(lot_id))`; dicionários de saída ordenados alfabeticamente, independentemente da ordem de inserção ou de chamada.

## 10. Projeções físicas de depósito

- **Mesclagem (`deposit_projection.merges`):** percorre pilhas existentes do recurso em ordem crescente de `pile_id`, respeitando `camp_zone.max_pile_amount` (0 = ilimitado, limitado por `MAX_INT`), preservando todas as reservas preexistentes e calculando exposição final por `storage._compute_merged_state(pile, add_amount)` (`WEIGHTED_AVERAGE` ou `KEEP_OLDEST`).
- **Criação (`deposit_projection.creates`):** aloca novos blocos sequencialmente via `camp_zone.get_candidate_slots()` e `camp_zone.validate_pile_position(slot, occupied)`, acumulando cada `resolved_world` em `occupied` para que múltiplas criações no mesmo plano respeitem `min_pile_clearance`, limites da zona e `WorldNavigation`.
- **Identificadores virtuais:** criações recebem `&"virtual_pile:0"`, `&"virtual_pile:1"`, ...; `storage._next_pile_id` nunca é consumido.
- **Limitações físicas:** rejeita `"invalid_camp_zone"`, `"unsupported_storage_source"`, `"invalid_piles_root"`, `"no_valid_camp_slot"`, `"navigation_not_ready"`, `"amount_overflow"` e `"world_mismatch"`. `physical_delivery_authorized` permanece sempre `false`.

## 11. Projeções de reservas

- Cada fatia de lote `SITE_RESERVED` é mapeada deterministicamente sobre um alvo físico concreto (`&"existing_pile"` com `pile_id` + `pile_instance_id`, ou `&"virtual_pile"` com `virtual_pile_id` e `ledger_mode = &"bind_created_pile_id_on_commit"`).
- `reservation_projection.requires_atomic_deposit_and_reservation` é marcado `true` sempre que há restaurações — deixando explícito que a C3.4.1 **não** simula atomicidade com `deposit_batch()` + `reserve_batch()` separados.
- Reservas preexistentes de outras obras em pilhas mescladas são verificadas e expostas em `preserved_existing_pile_reservations` e `after_reservations`.
- Qualquer anomalia de lastro físico (`pile_reserved > pile.amount`, entrada órfã ou recurso divergente em `storage._ledger`, `reservation_id` duplicado entre duas obras ou inconsistência de conservação) falha fechada com `"reservation_restoration_unavailable"`.

## 12. Isolamento regional

- Consulta a mesma autoridade regional `world.get_meta(&"_reserved_withdrawal_domains")` via `ReservedWithdrawalCoordinator.inspect_camp_domain_for_preparation(...)`.
- Valida `World3D` único entre `unit`, `camp_zone`, `storage._piles_root`, `WorldNavigation` (se presente), pilhas e canteiros do domínio.
- Rejeita conflito de região (`"region_mismatch"`), mundo divergente (`"world_mismatch"`), autoridade apontando para outro storage ou conflito de inventário entre canteiros (`"ambiguous_domain"`), execução em andamento (`"busy"`) e reutilização de `operation_id` já presente nos recibos regionais ou no histórico do ledger da mochila (`"operation_conflict"`).

## 13. Revisões e anti-ABA

- O plano registra revisões monotônicas e identidades em `revisions`: `load`, `inventory`, `storage`, `pile_ledger`, `next_pile_id`, mapa completo `piles` (`instance_id`, `revision`, `resource_id`, `amount`, `position`, `world_pos`, `elapsed`, `accum`, `reserved`), mapa `sites` (`instance_id`, `generation`, `state`, `revision`, `work_serial`), `camp_config` (incluindo `nav_instance_id`, `nav_ready`, `nav_revision`, `has_custom_validator`) e contadores do ledger (`ledger_operation_count`, `ledger_used_lot_count`).
- `validate_selective_camp_delivery_plan(...)` valida a forma estrita do plano, recalcula independentemente a preparação a partir do estado vivo e compara `identity`, `revisions` e o plano completo via `_strict_equal(...)` (verificando `typeof(a) == typeof(b)`, barrando coerções `int -> float` ou `String -> StringName`).
- Casos ABA cobertos e rejeitados: mochila perde e recupera igual total, lote substituído por outro de igual quantidade, pilha removida e recriada no mesmo slot com igual quantidade, reserva criada e liberada voltando a zero, slot invalidado após preparação, mudança de geração de obra e alteração de configuração do depósito.

## 14. Demonstração de pureza

- Nenhum participante recebe mutação durante `prepare_selective_camp_delivery` (sucesso ou falha) ou `validate_selective_camp_delivery_plan` (válido, obsoleto ou adulterado).
- Verificado automaticamente em `test_group_e_full_observational_purity_and_repeatability_on_prepare_and_validate` (cenários 41–53) por snapshot completo comparando antes e depois:
  - Mochila (`cargo` + `load_revision` + `capacity`), ledger (`lots`, `operations`, `used_lots`), pilhas (`instance_id`, `amount`, `elapsed`, `accum`, `revision`), `storage._next_pile_id`, `storage._ledger.snapshot_state()`, `storage_revision`, `inventory_revision`, `pile_ledger_revision`, estado/claims/buffers/workers/revisões de todos os canteiros, ausência de criação de `RegionalAuthority` (quando inexistente) e preservação exata de `receipts` e `construction_transfer_serial` (quando existente), 0 sinais emitidos em todos os participantes, contagens idênticas de conexões de listeners e contagem idêntica de nós na árvore de cena.
  - Chamadas repetidas retornam resultados estritamente iguais via `_strict_equal`.

## 15. Cenários adversariais

Suíte `tests/integration/test_t3_6_2_c3_4_1_selective_camp_delivery_prep.gd` — **21 funções de teste, 2.668 asserções**, cobrindo integralmente os 53 cenários exigidos + isolamento regional/mundo/busy/conflito:

- **Grupo A — Seleção (Cenários 1–10):** `test_group_a_single_free_lot_full_and_partial` (1, 2), `test_group_a_two_free_lots_same_resource_and_multi_resource` (3, 4), `test_group_a_empty_request_conservative_free_only_policy` (5), `test_group_a_invalid_requests_missing_excessive_nonpositive_duplicate_and_extra_fields` (6, 7, 8, 9), `test_group_a_deterministic_ordering_independent_of_request_and_insertion_order` (10).
- **Grupo B — Proveniência (Cenários 11–20):** `test_group_b_free_and_reserved_wood_coexistence_and_combined_selection` (11), `test_group_b_two_sites_same_resource_explicit_site_a_preserves_site_b` (12, 13, 14), `test_group_b_generation_mismatch_and_insufficient_claim_and_invalid_site` (15, 16, 17), `test_group_b_d3_cancellation_blocked_never_reclassified_to_free` (18), `test_group_b_corrupted_ledger_and_unreconciled_aggregate_rejected` (19, 20).
- **Grupo C — Armazenamento (Cenários 21–30):** `test_group_c_merge_existing_pile_and_exposure_policy` (21), `test_group_c_projected_new_pile_max_capacity_split_and_multiple_creates` (22, 23, 24), `test_group_c_no_valid_slot_nav_not_ready_invalid_camp_and_unsupported_storage` (25, 26, 27), `test_group_c_preserves_existing_reservations_and_projects_virtual_pile_reservation` (28, 29), `test_group_c_rejects_unprovable_reservation_physical_link` (30).
- **Grupo D — Revisões (Cenários 31–40):** `test_group_d_immediate_validity_and_backpack_lot_and_added_resource_invalidation` (31, 32, 33, 38), `test_group_d_reservation_pile_slot_and_site_generation_invalidation` (34, 35, 36, 37), `test_group_d_aba_protection_for_backpack_pile_reservation_and_camp_config` (39), `test_group_d_tampered_plan_rejection_including_flags_amounts_and_int_to_float` (40).
- **Grupo E — Pureza e Isolamento (Cenários 41–53 + extras):** `test_group_e_full_observational_purity_and_repeatability_on_prepare_and_validate` (41–53), `test_group_e_regional_world_isolation_busy_guards_and_operation_conflict`.

**Nota sobre acesso a estado privado nos testes:** a suíte acessa campos privados (`_provenance`, `_amounts`, `_generation`, `_site_state`, `_transit_claims`, `_ledger._by_pile`, `_is_mutating`, `_is_preparing_or_transacting`, `_next_pile_id`, `RegionalAuthority.is_executing`/`receipts`/`construction_transfer_serial`) exclusivamente em cenários adversariais de corrupção, injeção de estado ocupado, verificação de pureza e simulação controlada de débito pós-preparação (`_debit_free_lot_for_test`), pois a API pública impede intencionalmente construir estados corrompidos e a C3.4.1 não expõe commit/débito público de lotes livres.

## 16. Resultados da regressão

Todos os comandos abaixo foram executados após a última edição de código em `C:\Projetos\Dawn_of_Kin_wt_t3_4_5` com Godot `4.7.2.stable.official.ed1daf0bf`:

| Comando | Exit | Suítes | Testes | Asserções | Observações |
| --- | --- | --- | --- | --- | --- |
| `.\tools\run_tests.ps1 -Filter test_t3_6_2_c3_4_1` | 0 | 1 | 21/21 | 2.668 | 0 falhas, 0 erros |
| `.\tools\run_tests.ps1 -Filter test_t3_6_2_c3_3` | 0 | 1 | 10/10 | 328 | 0 falhas, 0 erros |
| `.\tools\run_tests.ps1 -Filter test_t3_6_2_c3_2` | 0 | 1 | 8/8 | 360 | 0 falhas, 0 erros |
| `.\tools\run_tests.ps1 -Filter test_t3_6_2_c3_1` | 0 | 1 | 6/6 | 161 | 0 falhas, 0 erros |
| `.\tools\run_tests.ps1 -Filter test_t3_6_2_c2` | 0 | 1 | 16/16 | 651 | 0 falhas, 0 erros |
| `.\tools\run_tests.ps1 -Filter test_t3_6_2` | 0 | 9 | 83/83 | 4.652 | 0 falhas, 0 erros |
| `.\tools\validate.ps1` | 0 | — | — | — | **140 scripts validados**, 0 erros, 0 avisos |
| `.\tools\run_tests.ps1 -Segmented` | 0 | 51 | 372/372 | 17.682 | 11/11 lotes PASS; `Discovered=51`, `ExecutedUnique=51`, `Duplicates=0`, `Missing=0`; 0 erros/avisos/vazamentos |
| `git diff --check` | 0 | — | — | — | 0 problemas de whitespace/patch |

Comparação com a baseline C3.3 (`351/351` testes, `50` suítes, `15.016` asserções, `138` scripts): aumento líquido para **372/372 testes (+21)**, **51 suítes (+1)**, **17.682 asserções (+2.666)** e **140 scripts validados (+2)**, sem perda de nenhum teste anterior.

## 17. Arquivos modificados

- **Modificado:**
  - `src/economy/reserved_withdrawal_coordinator.gd` (+72 linhas: `inspect_camp_domain_for_preparation` e `_inspect_camp_economic_domain`, estritamente somente-leitura).
- **Criados:**
  - `src/economy/selective_camp_delivery_planner.gd` (e `.uid` gerado pelo Godot 4.7.2).
  - `tests/integration/test_t3_6_2_c3_4_1_selective_camp_delivery_prep.gd` (e `.uid` gerado pelo Godot 4.7.2).
  - `docs/testing/T3_6_2_C3_4_1_candidate_report.md`.

Nenhum arquivo de ordens (`deliver_to_camp_order.gd`, `construct_order.gd`), inventário legado (`settlement_inventory.gd`), GDD, HUD, persistência ou C2-R1/C3.2 (além do auxiliar puro de leitura no coordenador) foi alterado.

## 18. Limitações

1. **Sem commit econômico ou entrega física real:** `dry_run_only = true`, `commit_supported = false`, `physical_delivery_authorized = false` por definição de escopo.
2. **Sem verificação de proximidade física:** a preparação não exige que a unidade esteja no slot de descarga do acampamento; essa autorização caberá exclusivamente ao commit futuro (C3.4.2).
3. **Sem contador monotônico em `CampStorageZone`:** se propriedades exportadas de `CampStorageZone` forem alteradas e revertidas exatamente ao mesmo valor entre `prepare` e `validate` sem alterar pilhas, storage ou navegação, o retrato `camp_config` coincidirá (ABA puro de configuração estática de zona).
4. **Custom validator stateful sem revisão:** se um `_custom_position_validator` externo mudar o slot escolhido, `validate` rejeita (`"tampered_or_stale_plan"`), mas se mudar internamente sem alterar os slots escolhidos nem `has_custom_validator`, não existe revisão observável no `Callable`.
5. **Custódia D3 ausente:** devolução de lotes `SITE_RESERVED` de obras não ativas permanece intencionalmente bloqueada (`"d3_cancellation_not_implemented"`).

## 19. Dependências da C3.4.2

Para implementar o commit atômico de descarga seletiva no acampamento, a C3.4.2 precisará:
1. Coordenador transacional sob a mesma `RegionalAuthority` (compartilhando recibos, exclusão mútua e seriais regionais), com checkpoint/rollback silencioso abrangendo mochila (`UnitCarryLoad`), pilhas físicas (`GroundPileManager`), reservas (`PileReservationLedger`) e claims de trânsito (`ConstructionSite`).
2. Primitiva interna silenciosa no `GroundPileManager` que execute mesclagem + criação física de pilhas + vinculação atômica das reservas projetadas aos `pile_id` reais recém-atribuídos (`bind_created_pile_id_on_commit`) em um único limite atômico — nunca por chamadas separadas `deposit_batch()` + `reserve_batch()`.
3. Primitiva interna de débito seletivo de lotes `FREE_GATHERED` e `SITE_RESERVED` em `UnitCarryLoad` sob guarda de transação.
4. Verificação de proximidade física e autorização de ordem antes de efetivar o commit.
5. Reavaliação prévia da decisão pendente `DEC-T3.6-SIGNALS-01` antes de publicar sinais pós-commit.

## 20. Decisões ainda pendentes

- **`DEC-T3.6-SIGNALS-01` (Pendente):** definir se as transações econômicas da T3.6 mantêm guardas durante a publicação de sinais (como na C2-R1 e C3.2) ou liberam antes da publicação (conforme recomendação da proposta T3.6-R2). A C3.4.1 não alterou C2-R1/C3.2 e não emite sinais.
- **Proposta T3.6-R2 (`69c13275a34a30564ac839ec920f83ef36590812`):** segue como proposta arquitetural com decisões pendentes, incluindo custódia D3 (`CANCEL_TRANSIT`, `CANCEL_BUFFER`, `CANCEL_INCORPORATED`) e governança de cancelamento.
- **Revisão monotônica em `CampStorageZone` (Opcional futuro):** avaliar na C3.4.2 se `CampStorageZone` deve expor um contador de revisão próprio para eliminar até mesmo ABA puro em propriedades de configuração.
