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


---

# Revisão R1 — Correções pós-auditoria independente

**Status da revisão:** **T3.6.2-C3.4.1-R1 — Correção publicada para auditoria independente** (não homologada; C3.4 **não** concluída; C3.4.2 fora do escopo).

## R1.1 SHA-base da correção

- **SHA-base auditado (local e remoto verificados antes da edição):** `d6218c928337de5a86032127d1d2f223eaf9a942`
- **Branch / Worktree:** `feat/t3-6-2-provenance-transactions` em `C:\Projetos\Dawn_of_Kin_wt_t3_4_5`
- **Referência da `main`:** `25e0a20f1d6a2f10a9e059afe69759fbe263db4a` (inalterada)
- **Engine:** Godot `4.7.2.stable.official.ed1daf0bf`

## R1.2 Problemas identificados na auditoria independente

1. **Callback externo não confiável durante preparação pura (falha principal):** `SelectiveCampDeliveryPlanner._project_camp_deposit_and_reservations_pure(...)` invocava `CampStorageZone.validate_pile_position(...)`, que executa `camp_zone._custom_position_validator.call(resolved_pos)` quando configurado. Um `Callable` arbitrário não oferece garantia de pureza observacional e poderia mutar pilhas, reservas, posições, revisões, nós da cena ou estado externo durante uma API declarada estritamente somente-leitura.
2. **Lacuna na inspeção da coleção física interna `storage._piles` (falha secundária):** `SelectiveCampDeliveryPlanner._inspect_storage_state_pure(...)` consultava `storage.get_piles()`, que filtra silenciosamente referências inválidas (`if is_instance_valid(pile)`). Assim, entradas nulas ou liberadas presentes na coleção interna `_piles` não eram detectadas como inconsistência de integridade.
3. **Divergência aparente de 2 asserções no relatório anterior:** `15.016 (C3.3) + 2.668 (C3.4.1) = 17.684`, enquanto a execução segmentada totalizou `17.682` (`-2`), exigindo investigação e comprovação objetiva.

## R1.3 Análise de causa raiz

- **Causa raiz #1 (Callback):** `CampStorageZone.validate_pile_position(...)` serve também ao fluxo normal de gameplay/depósito, onde validadores personalizados são permitidos. Ao chamar `validate_pile_position(...)` sem barreira prévia para `_custom_position_validator`, o planejador puro herdava a execução de um callback externo não verificável.
- **Causa raiz #2 (`_piles`):** `GroundPileManager.get_piles()` foi projetado como leitor defensivo de conveniência para o jogo, ignorando elementos inválidos em `_piles`. Para um planejador fail-closed, essa filtragem mascarava corrupção estrutural na coleção interna de pilhas.
- **Causa raiz #3 (Auditoria focada de pureza de leitura):** revisadas todas as chamadas efetuadas durante `prepare_selective_camp_delivery` e `validate_selective_camp_delivery_plan` em `CampStorageZone`, `WorldNavigation` (`is_navigation_ready`, `get_navigation_revision`, `snap_to_navmesh`, `is_position_reachable` → `find_path` → `get_pending_route_reason` / `query_path_on_map`), `GroundPileManager` (sem invocar `get_piles()` nem `pile_creator_override`), `SettlementInventory`, `ConstructionSite` (somente leitores `_pure` + `SelectiveSiteDeliveryPlanner._read_accounting`), `UnitCarryLoad` e `ReservedWithdrawalCoordinator.inspect_camp_domain_for_preparation`. Nenhuma outra chamada executa callbacks externos, poda automática, mutação de cache, incremento de revisão, emissão de sinal ou alocação persistente. Como polimento mínimo, `nav._navigation_revision` foi substituído pelo getter público puro `nav.get_navigation_revision()`.

## R1.4 Caminhos de código afetados

- `src/economy/selective_camp_delivery_planner.gd`:
  - `prepare_selective_camp_delivery(...)`
  - `_has_untrusted_custom_position_validator(camp_zone)` (novo auxiliar privado)
  - `_inspect_storage_state_pure(...)`
  - `_project_camp_deposit_and_reservations_pure(...)`
- `tests/integration/test_t3_6_2_c3_4_1_selective_camp_delivery_prep.gd`
- `CampStorageZone.validate_pile_position(...)` e `GroundPileManager` **não** foram modificados (preservando integralmente o comportamento existente do gameplay).

## R1.5 Correção aplicada

1. **Barreira contra callback externo não confiável (`"unsafe_custom_position_validator"`):**
   - Adicionado `_has_untrusted_custom_position_validator(camp_zone)` verificando `validator.is_valid() or not validator.is_null()`.
   - Rejeição conservadora antecipada em `prepare_selective_camp_delivery(...)` (antes de qualquer projeção, abrangendo tanto criação virtual quanto mesclagem e também revalidação em `validate_selective_camp_delivery_plan(...)` quando um callback é instalado posteriormente) e verificação defensiva adicional imediatamente antes de `camp_zone.validate_pile_position(...)` em `_project_camp_deposit_and_reservations_pure(...)`.
   - O callback nunca é executado; nenhum parâmetro `trust_callback` ou contorno silencioso foi introduzido.
2. **Inspeção bruta da coleção interna `storage._piles` (`"invalid_physical_pile_collection"`):**
   - `_inspect_storage_state_pure(...)` percorre diretamente `storage._piles` sem podar, remover ou alterar qualquer elemento, validando: `storage._next_pile_id > 0`, elemento não nulo, `is_instance_valid`, tipo `GroundResourcePile`, `not is_queued_for_deletion()`, `is_valid()`, `is_inside_tree()`, `get_parent() == storage._piles_root`, `0 < pile_id < storage._next_pile_id`, `_storage_owner.get_ref() == storage`, ausência de instâncias duplicadas e ausência de `pile_id` duplicado.
   - Entradas órfãs ou divergentes em `storage._ledger` continuam falhando fechadas com `"reservation_restoration_unavailable"`.

## R1.6 Contratos preservados

Mantidos integralmente todos os contratos da C3.4.1: `FREE_GATHERED`, `SITE_RESERVED`, seleção explícita e padrão conservador (`[]` apenas livre), isolamento entre obras distintas, descarga parcial, conservação física e contábil, mesclagem com política de exposição, criações virtuais (`&"virtual_pile:N"`), restauração projetada de reservas, proteção anti-ABA, validação de `operation_id`, isolamento regional e de `World3D`, verificação de pesos, rejeição de planos adulterados, ausência de commit e flags obrigatórias (`dry_run_only = true`, `commit_supported = false`, `physical_delivery_authorized = false`).

## R1.7 Testes novos e adaptações

Em `tests/integration/test_t3_6_2_c3_4_1_selective_camp_delivery_prep.gd` (+5 funções de teste; 21 → **26 testes**, 2.668 → **3.227 asserções**):

- `test_r1_untrusted_callback_storage_mutation_refused_without_execution` (§4.1): callback que alteraria pilha e depositaria madeira é recusado antes da execução (caminhos de criação virtual e mesclagem), com contador `0`, snapshot completo idêntico e `0` sinais.
- `test_r1_untrusted_callback_pile_creation_refused_without_execution` (§4.2): callback que criaria pilha via `try_create_pile_at` nunca executa; `_next_pile_id`, `_piles.size()` e contagem de nós permanecem intactos.
- `test_r1_untrusted_callback_reservation_mutation_refused_without_execution` (§4.3): callback que liberaria/criaria reservas nunca executa; reservas de obra, claims e revisões permanecem intactos.
- `test_r1_untrusted_callback_self_state_and_post_prepare_validation` (§4.4, §4.5, §4.6): callback com efeito em contador externo nunca executa; planos válidos preparados sem callback (mesclagem e criação virtual) passam a ser recusados em `validate_selective_camp_delivery_plan(...)` assim que um callback é anexado, sem executá-lo; confirmação direta de que `CampStorageZone.validate_pile_position(...)` permanece inalterado para o gameplay e executaria o callback se chamado diretamente; ao remover o callback (`Callable()`), preparação e validação voltam a operar normalmente.
- `test_r1_physical_pile_collection_integrity_and_no_implicit_cleanup` (§5.2): verifica coleção íntegra, referência liberada (`free()`) em `_piles` (comprovadamente invisível a `get_piles()`), entrada `null`, referência duplicada, duas pilhas com mesmo `pile_id`, `pile_id >= _next_pile_id`, `pile_id == 0`, entrada órfã no ledger e confirmação explícita de que `_piles` não sofre poda/limpeza automática.
- Adaptação dos cenários 25a e 36 (§4.7) para não dependerem mais de `_custom_position_validator`: falta genuína de slot via redução de `zone_bounds_half_extents` (25a) e invalidação real de slot via ocupação física por nova pilha (36a) e encolhimento de limites (36b), preservando cobertura integral de cada condição de forma independente.

## R1.8 Resultados das regressões (pós-R1, Godot `4.7.2.stable.official.ed1daf0bf`)

| Comando | Exit | Suítes | Testes | Asserções | Observações |
| --- | --- | --- | --- | --- | --- |
| `.\tools\run_tests.ps1 -Filter test_t3_6_2_c3_4_1` | 0 | 1 | 26/26 | 3.227 | 0 falhas, 0 erros (+5 testes, +559 asserções) |
| `.\tools\run_tests.ps1 -Filter test_t3_6_2_c3_3` | 0 | 1 | 10/10 | 328 | 0 falhas, 0 erros |
| `.\tools\run_tests.ps1 -Filter test_t3_6_2_c3_2` | 0 | 1 | 8/8 | 360 | 0 falhas, 0 erros |
| `.\tools\run_tests.ps1 -Filter test_t3_6_2_c3_1` | 0 | 1 | 6/6 | 161 | 0 falhas, 0 erros |
| `.\tools\run_tests.ps1 -Filter test_t3_6_2_c2` | 0 | 1 | 16/16 | 651 | 0 falhas, 0 erros |
| `.\tools\run_tests.ps1 -Filter test_t3_6_2` | 0 | 9 | 88/88 | 5.211 | 0 falhas, 0 erros (`1.984 + 3.227 = 5.211` exato) |
| `.\tools\validate.ps1` | 0 | — | — | — | **140 scripts validados**, 0 erros, 0 avisos |
| `.\tools\run_tests.ps1 -Segmented` | 0 | 51 | 377/377 | 18.242 | 11/11 lotes PASS; `Discovered=51`, `ExecutedUnique=51`, `Duplicates=0`, `Missing=0`; 0 erros/avisos/vazamentos |
| `git diff --check` | 0 | — | — | — | Limpo |

## R1.9 Explicação da diferença entre contagens de asserções

A investigação comparativa suíte-a-suíte entre as execuções segmentadas comprovou objetivamente que:

1. A suíte `test_t3_6_2_c3_4_1_selective_camp_delivery_prep.gd` tem contagem **100% determinística** e idêntica entre execução isolada e segmentada (`2.668` na candidata inicial; `3.227` na R1).
2. Todas as 9 suítes do filtro `test_t3_6_2` têm soma **exata** em relação à baseline C3.3 (`1.984 + 2.668 = 4.652` na candidata inicial; `1.984 + 3.227 = 5.211` na R1; variação zero).
3. A diferença de `-2` observada na candidata inicial (`17.682` vs. `15.016 + 2.668 = 17.684`) e a diferença de `+1` observada entre C3.4.1 e C3.4.1-R1 (`18.242` vs. `17.682 + 559 = 18.241`) originam-se exclusivamente de **suítes de integração T2 preexistentes** que executam asserções dentro de laços `while ... await wait_physics_frames(1)` cujo número de iterações varia em `±1–2` frames conforme o escalonamento de frames do host:
   - Diff real observado por suíte entre os dois logs segmentados (sem nenhuma alteração em código ou testes T2):
     - `tests/integration/test_t2_natural_source_states.gd`: `102 → 101` (`-1`), onde a linha 134 executa `assert_true(solid.global_transform.is_equal_approx(solid_tf_before))` a cada physics frame enquanto a animação de queda (dirigida por `_process(delta)`) permanece em `is_felling()`.
     - `tests/integration/test_t2_worker_cycle.gd`: `2.657 → 2.659` (`+2`), onde as linhas 644, 667 e 751 executam `assert_true(source.get_active_worker_count() <= ...)` a cada physics frame dentro de laços de espera de transição de estado.
   - Resultado líquido entre C3.4.1 e C3.4.1-R1: `-1 + 2 = +1`, explicando integralmente `17.682 + 559 + 1 = 18.242` sem qualquer omissão, duplicata ou instabilidade nas suítes T3.6.2.

## R1.10 Limitações restantes

- Ausência intencional de commit econômico e de autorização de proximidade física (`commit_supported = false`, `physical_delivery_authorized = false` — escopo da futura C3.4.2).
- Validadores personalizados em `CampStorageZone` são recusados de forma conservadora (`"unsafe_custom_position_validator"`) até que exista um contrato específico, verificável e aprovado de pureza para validadores de posição (fora do escopo desta revisão).
- `CampStorageZone` continua sem contador de revisão monotônico próprio (ABA puro de propriedades exportadas revertidas ao valor exato anterior sem mudança em pilhas/storage/nav permanece documentado como limitação conhecida).
- Lotes `SITE_RESERVED` de obras não ativas continuam bloqueados com `"d3_cancellation_not_implemented"` até implementação da custódia D3.
- `DEC-T3.6-SIGNALS-01` permanece pendente (C2-R1 e C3.2 inalteradas; C3.4.1-R1 não emite sinais).

## R1.11 Arquivos modificados na R1

- `src/economy/selective_camp_delivery_planner.gd` (+40/-6 linhas)
- `tests/integration/test_t3_6_2_c3_4_1_selective_camp_delivery_prep.gd` (+313/-14 linhas)
- `docs/testing/T3_6_2_C3_4_1_candidate_report.md` (acréscimo desta seção R1, preservando integralmente o histórico original)

## R1.12 SHAs publicados (branch `feat/t3-6-2-provenance-transactions`)

- **Base auditada:** `d6218c928337de5a86032127d1d2f223eaf9a942`
- **Commit R1 (`fix`):** `a39e1867ebd44cccb90db82d95f8b394082a02e5` — `fix(t3.6.2-c3.4.1-r1): reject untrusted custom position validator and inspect raw _piles`
- **Commit R1 (`test`):** `71d7ea342e7e523285e048f4d3f2292dbeaeb811` — `test(t3.6.2-c3.4.1-r1): add adversarial callback purity and raw pile collection tests`
- **Commit R1 (`docs`):** commit seguinte contendo esta seção do relatório.
