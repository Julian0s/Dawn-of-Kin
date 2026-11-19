# Dawn of Kin — Relatório Técnico da Candidata T3.6.2-C3.4.2
## Commit atômico da descarga seletiva no acampamento

**Status da candidata:** **T3.6.2-C3.4.2 — Candidata publicada para auditoria independente** (não homologada; C3.4.3 **não** iniciada; sem integração com `DeliverToCampOrder`, `ConstructOrder` ou coleta T2).

### Classificação normativa e de verificação

| Marcador | Classificação aplicada |
| --- | --- |
| **DECIDIDO** | GDD v1.2 (D2, D9, DEC-11A/B, DEC-18/19), economia em pilha física no `CampStorageZone` (T2), reservas por pilha sem reancoragem automática (T3.1/DEC-11B), proveniência `FREE_GATHERED`/`SITE_RESERVED` em modo opt-in (C2-R1, C3.1, C3.2, C3.3, C3.4.1-R1). |
| **IMPLEMENTADO** | Coordenador transacional explícito `SelectiveCampDeliveryCoordinator`, helpers privados `selective_camp_delivery_tx_helpers.gd`, criação destacada pós-commit em `GroundResourcePile`/`GroundPileManager`, escopo/recibo `selective_camp_delivery` na `RegionalAuthority`, revalidação sob escopo em `SelectiveCampDeliveryPlanner` e contador monotônico `_config_revision` em `CampStorageZone`. |
| **TESTADO AUTOMATICAMENTE** | Suíte adversarial `test_t3_6_2_c3_4_2_selective_camp_delivery_commit.gd` (10 testes cobrindo os 70 cenários A–F + conservação global + ABA + `node_added`, 1.777 asserções); todos os filtros T3.6.2 (`98/98`, 6.988 asserções); `validate.ps1` (143 scripts, 0 erros, 0 avisos); regressão segmentada completa (`52` suítes, `387/387` testes, `20.020` asserções, 0 erros/avisos/vazamentos). |
| **NÃO TESTADO MANUALMENTE** | Nenhum teste visual/manual jogável executado — a C3.4.2 é exposta exclusivamente via API transacional explícita e não altera ordens ou interface do jogo. |
| **PROPOSTA** | Arquitetura T3.6-R2 (`69c13275a34a30564ac839ec920f83ef36590812:docs/architecture/T3_6_cancellation_architecture_R2_PROPOSAL.md`) — mantida estritamente como referência arquitetural, sem promoção unilateral a norma. |
| **ABERTO** | `DEC-T3.6-SIGNALS-01` (política definitiva de guardas durante publicação de sinais), contrato futuro de validadores personalizados comprovadamente puros, política definitiva de migração de mochilas legadas e persistência T3.8. |
| **BLOQUEADO** | Devolução de lotes `SITE_RESERVED` de obras não ativas (`d3_cancellation_not_implemented` até custódia D3); integração de ordens de unidade (escopo C3.4.3); T3.6.3 e T3.6.4. |

---

## 1. SHA-base

- **SHA-base obrigatório verificado antes de editar:** `d54750c11d9141cf427ba507febb4894d02f21a2` (`feat/t3-6-2-provenance-transactions` local e remoto coincidentes, árvore limpa).
- **Referência da `main` verificada:** `25e0a20f1d6a2f10a9e059afe69759fbe263db4a` (inalterada).
- **Engine verificada:** Godot `4.7.2.stable.official.ed1daf0bf`.

## 2. Branch e worktree

- **Repositório:** `Julian0s/Dawn-of-Kin`
- **Branch:** `feat/t3-6-2-provenance-transactions`
- **Worktree:** `C:\Projetos\Dawn_of_Kin_wt_t3_4_5` (`C:\Projetos\Dawn of Kin` não modificado).

## 3. Documentação consultada

- `AGENTS.md`, `docs/Dawn_of_Kin_GDD.md` (v1.2), `docs/architecture/T3_architecture_PROPOSAL.md`
- `69c13275a34a30564ac839ec920f83ef36590812:docs/architecture/T3_6_cancellation_architecture_R2_PROPOSAL.md` (proposta, não norma aprovada)
- `docs/testing/T3_6_2_C2_R1_candidate_report.md`, `T3_6_2_C3_1_candidate_report.md`, `T3_6_2_C3_2_candidate_report.md`, `T3_6_2_C3_3_candidate_report.md`, `T3_6_2_C3_4_1_candidate_report.md` (incluindo R1)
- Código-fonte auditado diretamente: `selective_camp_delivery_planner.gd`, `reserved_withdrawal_coordinator.gd`, `selective_site_delivery_coordinator.gd`, `selective_site_delivery_planner.gd`, `unit_carry_load.gd`, `carry_provenance_ledger.gd`, `ground_pile_manager.gd`, `ground_resource_pile.gd`, `pile_reservation_ledger.gd`, `settlement_inventory.gd`, `settlement_storage_source.gd`, `camp_storage_zone.gd`, `construction_site.gd`, `gather_slot_planner.gd`, `build_slot_planner.gd`, `deliver_to_camp_order.gd`, `unit_movement.gd`, `world_navigation.gd`, `selective_site_delivery_fixture.gd`.

## 4. Divergências detectadas na auditoria prévia

1. **Setters travados em `GroundResourcePile` sob `_is_preparing_withdrawal`:** `GroundResourcePile` bloqueia setters (`pile_id`, `definition`, `resource_id`, `amount`, `configure_initial`, `apply_state`) quando `_storage_owner._is_preparing_withdrawal == true`. **Resolução:** mesclagens usam `_apply_state_without_visual(...)` (mesmo padrão da C2-R1) e novas pilhas são inicializadas destacadas via `_configure_initial_detached_for_commit(...)` antes de vincular `_storage_owner`, sendo anexadas a `_piles_root` e sincronizadas visualmente somente após a gravação definitiva do recibo.
2. **Efeitos de ciclo de vida de nós (`_enter_tree` / `_ready` / `node_added`):** inserir novas pilhas em `_piles_root` antes das invariantes finais exporia estado parcial a observadores de `SceneTree.node_added` ou `GROUP_GROUND_PILES`. **Resolução:** pilhas novas permanecem 100% destacadas da árvore durante todos os estágios falháveis; em rollback pré-commit são liberadas com `free()` sem nenhum evento de cena; em commit bem-sucedido só entram na árvore depois que o recibo regional e as revisões finais já foram registrados.
3. **`pile_creator_override` em `GroundPileManager`:** `GroundPileManager._instantiate_pile` executaria `pile_creator_override.call(...)`, um callback arbitrário externo. **Resolução:** tanto o coordenador quanto `_apply_camp_delivery_create_detached_silent(...)` recusam qualquer `pile_creator_override` configurado (`"unsafe_pile_creator_override"`) antes de qualquer mutação, preservando o comportamento legado fora da nova API.
4. **ABA puro em `CampStorageZone` (identificado na C3.4.1-R1 e §14.1):** propriedades exportadas e transform local/global de `CampStorageZone` não possuíam contador monotônico; uma mudança síncrona `A → B → A` em `position` também não dispara `NOTIFICATION_TRANSFORM_CHANGED` isoladamente porque Godot coalescia o bit dirty global. **Resolução:** adicionado `_config_revision: int` + `get_config_revision()` em `CampStorageZone`, incrementado em setters de configuração geométrica/capacidade/navegação e em ambos `NOTIFICATION_LOCAL_TRANSFORM_CHANGED` (síncrono) e `NOTIFICATION_TRANSFORM_CHANGED`, capturado em `revisions.camp_config.config_revision`. (Ver limitação residual documentada na Seção 22 sobre toggling puro `null → fn → null` de `_custom_position_validator`.)
5. **Revalidação sob guardas próprias (§6.1):** a API pública `prepare_selective_camp_delivery(...)` rejeita participantes ocupados. **Resolução:** adicionado `_prepare_under_camp_delivery_scope(scope, operation_id, requested_lots)` validado estritamente por `ReservedWithdrawalCoordinator._owns_camp_delivery_scope(scope)` (sem parâmetro `ignore_busy`).

## 5. Matriz de riscos pré-implementação

| Risco | Prevenção implementada | Teste verificador |
| --- | --- | --- |
| Debitar lote incorreto | Seleção por `lot_id` + débito individual em `CarryProvenanceLedger` destacado; proibição de `take_all()` | Grupos A e B (`test_group_a_*`, `test_group_b_*`) |
| Remover material sem criar depósito | Checkpoint completo + rollback silencioso em 15 fronteiras pré-commit | Grupo C (`test_group_c_all_pre_commit_fault_boundaries_*`) |
| Criar depósito sem debitar mochila | Aplicação na ordem débito → mesclagem → criação destacada → reserva → claim + verificação de invariantes finais antes do recibo | Grupo C + `verify_final_invariants` |
| Restaurar reserva em pilha inexistente / ID virtual | Resolução explícita `virtual_pile:N → real_pile_id > 0` antes de `_ledger.allocate_on_pile`; validação `pile_reserved <= pile.amount` | Grupo B (`test_group_b_mixed_*`) + Grupo C |
| Reservar material de outra obra / corromper obra B | Lotes vinculados a `site_id`/`generation`/`reservation_id`; baselines de todas as obras pares conferidos em `verify_final_invariants` | Grupo B (`test_group_b_reserved_delivery_site_a_*`) |
| Criar pilha física e falhar em seguida | Pilhas novas ficam destacadas da árvore até pós-recibo; rollback chama `free()`, restaura `_piles` e `_next_pile_id`, 0 eventos `node_added` | Grupo C (`after_pile_create`, `during_pile_create`, `before_receipt_commit`) |
| Falhar durante mesclagem ou combinação mesclagem + criação | Checkpoint `merge_states` + `created_piles` desfeitos juntos em `_restore_camp_delivery_checkpoint_silent` | Grupo C (`after_pile_merge`, `test_group_c_combined_*`) |
| Falhar durante vinculação de reserva | Snapshot integral de `PileReservationLedger` restaurado com avanço monotônico de revisão | Grupo C (`during_reservation_restore`, `after_reservation_restore`) |
| Repetir operação já comprometida / conflito cross-C2/C3.2 | Recibo regional `selective_camp_delivery` na mesma `RegionalAuthority` + verificação de WeakRefs, identidade, `requested_lots` e SHA-256 `plan_digest` | Grupo D (`test_group_d_idempotency_*`) |
| Alterar estado durante preparação / plano obsoleto / ABA | Revalidação integral sob escopo + `_strict_equal` + revisões monotônicas em mochila, storage, pilhas, ledger, sites e `CampStorageZone._config_revision` | Grupo E (`test_group_e_unsafe_*`) |
| Executar callback externo antes do commit | Recusa prévia de `_custom_position_validator` (`unsafe_custom_position_validator`) e `pile_creator_override` (`unsafe_pile_creator_override`) antes de alocar autoridade ou mutar estado | Grupo E (Cenários 57, 58) |
| Sinais reentrantes / estado intermediário | Publicação somente pós-recibo sob guardas cooperativos mantidos; `_suppress_coordinator_signal_echo` em sites; `node_added` só após recibo | Grupo F (`test_group_f_concurrency_*`) |
| Descarga remota / parede / navegação indisponível | Autorização física obrigatória com `WorldNavigation` pronta + `GatherSlotPlanner.compute_camp_dropoff_slot` + `CAMP_DROPOFF_REACH_TOLERANCE_XZ` (`0.35 m`) + `BuildSlotPlanner.has_clear_physical_access` | Grupo E (`test_group_e_physical_authorization_*`) |

## 6. Arquitetura efetivamente construída

Separada em módulos pequenos e focados sem criar segunda autoridade econômica:

- **`src/economy/selective_camp_delivery_coordinator.gd` (`class_name SelectiveCampDeliveryCoordinator`):** orquestração da API pública (`execute_selective_camp_delivery`, `commit_prepared_selective_camp_delivery`, `get_receipt`), aquisição/liberação de guardas, execução dos estágios silenciosos com hooks de falha, gravação de recibo, publicação de notificações e replay idempotente.
- **`src/economy/selective_camp_delivery_tx_helpers.gd` (privado, sem `class_name`):** autorização física (`check_physical_authorization`), preparação dos débitos definitivos no ledger (`prepare_commit_debits`), captura de checkpoints (`capture_checkpoints`), verificação de invariantes finais e conservação global (`verify_final_invariants`), rollback completo (`restore_silent`) e validação estrita de recibo (`validate_camp_receipt`).
- **`src/economy/reserved_withdrawal_coordinator.gd`:** extensão mínima da `RegionalAuthority` compartilhada (`RECEIPT_CAMP_DELIVERY`, `CampDeliveryScope`, `_owns_camp_delivery_scope`, `_resolve_camp_authority` e validação de tipo em `_read_receipt`).
- **`src/economy/ground_pile_manager.gd` + `src/economy/ground_resource_pile.gd`:** primitivas internas silenciosas sob guarda `_is_preparing_withdrawal` para checkpoint, mesclagem sem visual, criação destacada, restauração de reserva, rollback completo e finalização pós-commit (anexo em `_piles_root` + reconstrução/sincronização visual).
- **`src/economy/selective_camp_delivery_planner.gd` + `src/economy/camp_storage_zone.gd`:** `_prepare_under_camp_delivery_scope(...)` e `_config_revision` monotônico em `CampStorageZone`.

## 7. Escopo da autoridade regional

Compartilha integralmente `world.get_meta(&"_reserved_withdrawal_domains")[region_id]` (`ReservedWithdrawalCoordinator.RegionalAuthority`) com C2-R1 e C3.2:
- Um único flag `authority.is_executing` exclui mutuamente C2-R1, C3.2 e C3.4.2 no par `(World3D, region_id)`.
- `authority.active_camp_delivery` e `authority.active_delivery` são mutuamente exclusivos em `_owns_delivery_scope` e `_owns_camp_delivery_scope`.
- A tabela `authority.receipts` unifica os tipos `reserved_withdrawal`, `selective_site_delivery` e `selective_camp_delivery`, impedindo reutilização cruzada de `operation_id` entre os três coordenadores.
- Chamadas rejeitadas por callback inseguro (`_custom_position_validator` / `pile_creator_override`) ou mochila legada (`provenance_disabled`) falham antes de criar uma nova `RegionalAuthority` caso ainda não exista nenhuma no mundo.

## 8. Contratos do coordenador

- `execute_selective_camp_delivery(inventory: SettlementInventory, camp_zone: CampStorageZone, unit: Unit, region_id: Variant, operation_id: Variant, requested_lots: Variant = []) -> Dictionary`
- `commit_prepared_selective_camp_delivery(inventory: SettlementInventory, camp_zone: CampStorageZone, unit: Unit, region_id: Variant, plan: Variant) -> Dictionary`
- `get_receipt(operation_id: Variant) -> Dictionary`
- **Retorno de sucesso:** `{"ok": true, "reason": "", "dependency": "", "replayed": bool, "delivered_now": int, "delivered_amounts": Dictionary, "created_pile_ids": Array[int], "receipt": Dictionary}` (`delivered_now == 0` em replay).
- **Retorno de falha:** `{"ok": false, "reason": String, "dependency": String, "replayed": false, "delivered_now": 0, "delivered_amounts": {}, "created_pile_ids": [], "receipt": {}}`.

## 9. Guardas e ordem de aquisição

Ordem fixa compatível com C2-R1 e C3.2:
1. `authority.is_executing = true` + `authority.active_camp_delivery = scope`
2. Todos os `ConstructionSite`s vivos em `(world, region_id)`, ordenados por `(String(site_id), get_instance_id())`: `site._is_preparing_or_transacting = true`
3. `inventory._is_delivering = true`
4. `storage._is_preparing_withdrawal = true`
5. `load._provenance_busy = true`
6. `load._coordinator_transaction_locked = true`

Liberação sempre em ordem estritamente inversa (`_release`), sem qualquer `await` durante o bloqueio.

## 10. Autorização física

Executada sob guardas em `TxHelpers.check_physical_authorization(scope)` (e reexecutada caso `_fault_at` esteja conectado após `before_carry_debit`):
- Valida `unit` vivo na árvore, `global_position` finita, mesmo `World3D`, mesma `load`; `camp_zone` válido na árvore e vinculado a `storage`; `_piles_root` válido no mesmo `World3D`; ausência de `_custom_position_validator` e `pile_creator_override`.
- Exige `WorldNavigation` real vinculada a `camp_zone`, viva no mesmo `World3D`, compatível com `unit.get_movement().get_world_navigation()` (se definida) e com `is_navigation_ready() == true` (caso contrário: `"navigation_not_ready"` ou `"navigation_mismatch"`).
- Calcula o slot de entrega alcançável via `GatherSlotPlanner.compute_camp_dropoff_slot(unit_pos, camp_zone, nav, [])` e exige: slot dentro dos limites da zona, distância horizontal `<= CAMP_DROPOFF_REACH_TOLERANCE_XZ` (`UnitMovement.ARRIVAL_TOLERANCE_XZ + 0.10 = 0.35 m`), `|Δy| <= BuildSlotPlanner.HEIGHT_TOLERANCE` (`0.85 m`) e linha física livre via `BuildSlotPlanner.has_clear_physical_access(unit_pos, slot_pos, world)`.
- Não exige instância de `DeliverToCampOrder`.

## 11. Implementação do débito seletivo

- `TxHelpers.prepare_commit_debits(authority, fresh)` reconstrói um `CarryProvenanceLedger` destacado a partir de `plan.before.cargo.ledger` e debita cada entrada de `plan.selected_lots` com ID único `c3.4.2:<len>:<op>:<idx>` verificado contra `candidate._operations`, `authority.receipts` e `op`.
- Verifica igualdade exata dos lotes residuais, `_used_lots` e `validate_aggregate`.
- Na etapa silenciosa, instala o ledger debitado, as quantidades residuais e os pesos residuais preservando integralmente lotes não selecionados (livres ou de outras obras). Nunca chama `take_all()`.

## 12. Aplicação física nas pilhas

- **Mesclagens:** `storage._apply_camp_delivery_merge_silent(...)` aplica `_apply_state_without_visual(...)` respeitando `pile_id`, instância, exposição (`WEIGHTED_AVERAGE` / `KEEP_OLDEST`), `max_pile_amount` e reservas anteriores.
- **Criações:** `storage._apply_camp_delivery_create_detached_silent(...)` aloca `real_pile_id = _next_pile_id`, incrementa `_next_pile_id`, configura `GroundResourcePile` destacado via `_configure_initial_detached_for_commit(...)` e registra em `_piles` e `checkpoint.created_piles` sem anexar à árvore.
- **Finalização pós-commit:** somente após gravação definitiva do recibo, `_finalize_camp_delivery_after_commit_silent(...)` sincroniza visuais das pilhas mescladas e anexa cada pilha criada a `_piles_root` com `_finalize_detached_visuals_after_commit(_visual_cache)`.

## 13. Restauração de reservas

- Cada entrada de `plan.reservation_projection.restorations` resolve o `target_pile_id` físico real (`pile_id` existente ou mapeado de `virtual_pile:N` recém-criado). Nenhum ID virtual jamais entra no `PileReservationLedger`.
- `storage._apply_camp_delivery_reservation_restore_silent(...)` verifica `pile.resource_id == resource_id` e `current_reserved + amount <= pile.amount` antes de chamar `_ledger.allocate_on_pile(...)`.
- Em seguida, o claim em trânsito da unidade em cada obra envolvida é reduzido exatamente para `plan.after.sites[sid].claim` (mantendo o listener `load_changed` conectado durante todos os estágios falháveis e desconectando-o somente no limite irreversível do commit quando o claim daquela obra chega a vazio).

## 14. Checkpoints

`TxHelpers.capture_checkpoints(...)` captura antes da primeira mutação:
- **Mochila:** referência original de `load._provenance`, `_amounts`, `_unit_weights` + snapshot do `debited_ledger`.
- **Armazenamento:** cópia de `_piles`, estado exato (`amount`, `elapsed`, `accum`) de cada pilha alvo de mesclagem, `storage._ledger.snapshot_state()`, `_next_pile_id`, revisão e listas `merged_piles`/`created_piles`.
- **Obras envolvidas:** `claim` original com `callback`, `buffer`, `consumed`, `_work_progress_usec`, `site_state`, `assembly_substate`, `_was_fully_supplied`.
- **Obras pares (não envolvidas):** baselines de `buffer`, `consumed`, `claim`, `revision`, `reservations`, `progress`, `site_state` para validação de não-interferência em `verify_final_invariants`.

## 15. Rollback

- Falha em `before_carry_debit` ou na reautorização física antes da primeira mutação retorna imediatamente sem alterar revisões nem estado econômico.
- Qualquer falha nos estágios pós-primeira mutação (`after_ledger_debit` até `before_receipt_commit`) executa `TxHelpers.restore_silent(scope, checkpoint)`:
  - Restaura `site._transit_claims[uid]` de cada obra mutada e incrementa `site._transaction_revision += 1` (listeners preservados intactos).
  - Chama `storage._restore_camp_delivery_checkpoint_silent(...)`: restaura `_ledger` (incrementando revisão do ledger), restaura `_piles`, restaura `_next_pile_id`, libera com `free()` toda pilha destacada criada, restaura estado de cada pilha mesclada (incrementando revisão da pilha) e incrementa `storage._transaction_revision += 1`.
  - Restaura `load._provenance`, `load._amounts`, `load._unit_weights` e incrementa `load._transaction_revision += 1`.
- Nenhum recibo é gravado, nenhum sinal é emitido, nenhum nó órfão permanece, `_next_pile_id` não é desperdiçado e todas as revisões permanecem monotônicas (sem mascarar ABA).

## 16. Recibos e idempotência

- Recibo gravado em `authority.receipts[op]` sob `kind = &"selective_camp_delivery"` com `operation_id`, `identity`, `requested_lots`, `selected_lots`, `delivered_amounts`, `created_pile_ids`, `restored_reservations`, `plan_digest` (SHA-256 de `var_to_bytes(plan)`) + WeakRefs para `camp_zone`, `unit`, `load`, `inventory`, `storage`.
- Primeira execução válida: aplica uma vez, retorna `replayed = false`, `delivered_now > 0`.
- Repetição com mesmo `operation_id` e mesmo intento (no mesmo coordenador ou em nova instância `SelectiveCampDeliveryCoordinator`): retorna `ok = true`, `replayed = true`, `delivered_now = 0`, mesmo recibo, `0` mutações e `0` sinais.
- Repetição com mesmo `operation_id` e intento divergente (seleção, unidade, digest de plano adulterado, ou conflito com recibo C2-R1 / C3.2): recusa com `"operation_conflict"`.
- Repetição com mesmo `operation_id` e outra região sobre o mesmo storage: recusa com `"region_mismatch"`.

## 17. Política provisória de sinais (`DEC-T3.6-SIGNALS-01`)

**`DEC-T3.6-SIGNALS-01` permanece pendente.** Como solução provisória de compatibilidade estrita com C2-R1 e C3.2 nesta candidata, `_publish(...)` emite notificações somente **após** o commit definitivo (revisões avançadas, recibo gravado e pilhas criadas anexadas) e **com os guardas cooperativos ainda mantidos**, suprimindo eco interno de `ConstructionSite` via `_suppress_coordinator_signal_echo`:
1. `storage._dispatch_reservations_changed()` (quando houve restauração de reserva; propaga `inventory.reservations_changed`)
2. `storage._dispatch_storage_changed()` (propaga `inventory.inventory_changed`)
3. `load.load_changed.emit()`
4. `site.state_changed.emit(site)` (em ordem determinística de `site_id` para cada obra envolvida)

Qualquer reentrada durante esses sinais (ou durante `node_added` pós-commit) observa o estado final comprometido + recibo e é recusada com `"busy"` / `false`. Essa escolha é explicitamente provisória e não encerra `DEC-T3.6-SIGNALS-01`.

## 18. Testes adversariais

Suíte `tests/integration/test_t3_6_2_c3_4_2_selective_camp_delivery_commit.gd` — **10 funções de teste, 1.777 asserções**, com `WorldNavigation` real assada em `SubViewport` isolado:
- **Grupo A (Cenários 1–10):** `test_group_a_free_delivery_full_partial_multi_resource_two_lots_and_conservative_default`, `test_group_a_free_delivery_new_pile_and_multiple_new_piles_and_commit_prepared`.
- **Grupo B (Cenários 11–24):** `test_group_b_reserved_delivery_site_a_atomic_restoration_and_site_b_preservation` (com `buffer > 0`, `consumed > 0` e `progress > 0` reais produzidos por um `BUILDER`), `test_group_b_mixed_free_and_reserved_partial_and_virtual_pile_and_d3_blocked`.
- **Grupo C (Cenários 25–40):** `test_group_c_all_pre_commit_fault_boundaries_roll_back_cleanly` (todos os 15 estágios de falha pré-commit + 0 eventos `node_added` + 0 sinais + 0 recibos + revisões monotônicas + guardas liberados), `test_group_c_combined_merge_create_multi_site_rollback_and_post_abort_retry`.
- **Grupo D (Cenários 41–50):** `test_group_d_idempotency_replay_cross_coordinator_and_all_conflict_cases`.
- **Grupo E (Cenários 51–62):** `test_group_e_physical_authorization_range_nav_zone_capacity_and_wall_blocker` (inclui parede sólida entre unidade e slot), `test_group_e_unsafe_callbacks_removed_pile_tampered_stale_and_world_region_isolation` (inclui ABA em `CampStorageZone.max_pile_amount` e `CampStorageZone.position`).
- **Grupo F (Cenários 63–70):** `test_group_f_concurrency_reentrancy_in_all_signals_and_guard_release` (inclui sonda `node_added` pós-commit e reentradas em todos os 6 sinais).

## 19. Resultados da regressão (Godot `4.7.2.stable.official.ed1daf0bf`)

| Comando | Exit | Suítes | Testes | Asserções | Observações |
| --- | --- | --- | --- | --- | --- |
| `.\tools\run_tests.ps1 -Filter test_t3_6_2_c3_4_2` | 0 | 1 | 10/10 | 1.777 | 0 falhas, 0 erros |
| `.\tools\run_tests.ps1 -Filter test_t3_6_2_c3_4_1` | 0 | 1 | 26/26 | 3.227 | 0 falhas, 0 erros (inalterada) |
| `.\tools\run_tests.ps1 -Filter test_t3_6_2_c3_3` | 0 | 1 | 10/10 | 328 | 0 falhas, 0 erros |
| `.\tools\run_tests.ps1 -Filter test_t3_6_2_c3_2` | 0 | 1 | 8/8 | 360 | 0 falhas, 0 erros |
| `.\tools\run_tests.ps1 -Filter test_t3_6_2_c3_1` | 0 | 1 | 6/6 | 161 | 0 falhas, 0 erros |
| `.\tools\run_tests.ps1 -Filter test_t3_6_2_c2` | 0 | 1 | 16/16 | 651 | 0 falhas, 0 erros |
| `.\tools\run_tests.ps1 -Filter test_t3_6_2` | 0 | 10 | 98/98 | 6.988 | 0 falhas, 0 erros (`5.211 + 1.777 = 6.988` exato) |
| `.\tools\validate.ps1` | 0 | — | — | — | **143 scripts validados**, 0 erros, 0 avisos |
| `.\tools\run_tests.ps1 -Segmented` | 0 | 52 | 387/387 | 20.020 | 12/12 lotes PASS; `Discovered=52`, `ExecutedUnique=52`, `Duplicates=0`, `Missing=0`; 0 erros/avisos/vazamentos |
| `git diff --check` | 0 | — | — | — | Limpo |

Verificação estática de chamadas em `src/**/*.gd`: zero chamadas de produção em `DeliverToCampOrder`, `ConstructOrder` ou qualquer sistema de gameplay.

## 20. Evidências de conservação

- Validada tanto dentro do próprio commit (`TxHelpers.verify_final_invariants`, pré-recibo) quanto na suíte adversarial (`_assert_global_conservation` após cada commit e cada rollback):
  - `camp_physical_after + carried_after == camp_physical_before + carried_before` por recurso.
  - `required == reserved + transit + buffer + consumed + missing` em toda obra ativa (envolvida ou par).
  - Em devolução reservada: `Δtransit = -q`, `Δreserved = +q`, `Δbuffer = Δconsumed = Δprogress = Δmissing = 0`, obra B intocada.
  - Em devolução livre: `Δcamp_free = +q`, `Δcarried_free = -q`, reservas existentes preservadas.
  - Em toda pilha: `pile_reserved <= pile.amount` e zero entradas órfãs ou virtuais em `PileReservationLedger`.

## 21. Autorrevisão técnica obrigatória (§17)

1. **Existe algum método chamado que execute outro método com efeitos colaterais?** Na fase de preparação/autorização, `CampStorageZone.validate_pile_position` só é alcançável após barreira que recusa `_custom_position_validator`; `GatherSlotPlanner.compute_camp_dropoff_slot` usa apenas leituras puras de `CampStorageZone` e `WorldNavigation.find_path`/`snap_to_navmesh`; `BuildSlotPlanner.has_clear_physical_access` usa apenas raycasts físicos. Na fase de aplicação, apenas mutadores internos silenciosos sob guarda executam efeitos.
2. **Alguma função aparentemente de leitura altera estado?** Auditadas todas as chamadas em `CampStorageZone`, `WorldNavigation`, `GroundPileManager`, `SettlementInventory`, `ConstructionSite` e `UnitCarryLoad`: nenhum getter com poda (`get_in_transit_amounts`, `get_transit_claim_for_unit`, `get_missing_amounts`, `get_resource_definition`) ou filtragem oculta (`get_piles()` em `_inspect_storage_state_pure`) é usado no caminho crítico.
3. **Algum callback externo pode executar durante estado parcial?** Não. `_custom_position_validator` e `pile_creator_override` são recusados antes da alocação de autoridade e novamente sob guardas; `_fault_at` é exclusivo de testes e recebe apenas o nome `String` do estágio; `node_added` e todos os sinais só disparam após o commit definitivo e gravação do recibo.
4. **O ciclo de vida dos nós pode emitir notificações antes do commit?** Não. Novas pilhas são construídas destacadas (`get_parent() == null`, fora da árvore) até depois de `verify_final_invariants` e gravação de `authority.receipts[op]`. Verificado dinamicamente por conexão em `SceneTree.node_added` nos Grupos C (`0` eventos em todos os 15 estágios de abort) e F (`1` evento somente com recibo e estado já comprometidos).
5. **É possível debitar a mochila e falhar na pilha sem restauração completa?** Não em falhas tratadas na thread principal: `after_ledger_debit`, `after_carry_debit`, `before_pile_merge`, `after_pile_merge`, `before_pile_create`, `during_pile_create` e `after_pile_create` passam todos por `TxHelpers.restore_silent`, testado com comparação integral de snapshots.
6. **É possível criar pilha e falhar na reserva?** Sim, e o rollback desfaz integralmente a pilha destacada (`free()`), restaura `_piles`, `_next_pile_id`, mesclagens, `_ledger`, mochila e claims — provado em `before_reservation_restore`, `during_reservation_restore`, `after_reservation_restore` e `test_group_c_combined_*`.
7. **É possível duplicar material após replay?** Não. `authority.receipts[op]` é checado antes de qualquer mutação, vincula WeakRefs, `identity`, `requested_lots` e SHA-256 `plan_digest`, e retorna `replayed = true, delivered_now = 0` sem mutações nem sinais (provado no Grupo D inclusive com segundo coordenador).
8. **É possível restaurar reserva da obra errada?** Não. Cada lote `SITE_RESERVED` carrega `site_id` e `generation` do ledger da mochila, validados contra `ConstructionSite` vivo no mesmo mundo/região, claim reconciliado e `reservation_id` único; `verify_final_invariants` confere ainda que todas as obras pares permaneceram intactas (Grupo B).
9. **Algum objeto inválido é ocultado por getter filtrado?** Não na preparação/validação/invariantes: `_inspect_storage_state_pure` e `verify_final_invariants` iteram diretamente a coleção bruta `storage._piles`.
10. **Algum mutador legado consegue ignorar os guardas?** Mutadores econômicos de `SettlementInventory`, `GroundPileManager`, `GroundResourcePile`, `UnitCarryLoad` e `ConstructionSite` respeitam os guardas cooperativos (`_is_delivering`, `_is_preparing_withdrawal`, `_provenance_busy`, `_coordinator_transaction_locked`, `_is_preparing_or_transacting`). **Ressalva honesta:** `CampStorageZone` não possui guarda transacional durante a publicação pós-commit de sinais; entretanto, qualquer alteração ali feita por um listener ocorreria já após o commit irreversível e incrementaria `_config_revision` para planos futuros.
11. **Algum listener ou sinal é perdido no rollback?** Não. Listeners `load_changed` dos claims de obra só são desconectados após todas as invariantes finais e após `before_receipt_commit`; o Grupo C verifica `load_connections` idêntico após rollback em todos os 15 estágios.
12. **Alguma revisão pode voltar ao valor anterior e mascarar ABA?** Não para mochila, storage, pilhas, ledger de reservas, inventário, sites e `CampStorageZone._config_revision` (todas avançam monotonicamente). **Ressalva honesta:** alternar `_custom_position_validator` de `Callable() → fn → Callable()` sem mudar geometria/capacidade/navegação não incrementa `_config_revision` (intencionalmente preservando a semântica validada na C3.4.1-R1 §4.6, já que `fn` jamais é executada).
13. **Alguma falha deixa um ID consumido ou nó órfão?** Não. `_restore_camp_delivery_checkpoint_silent` restaura `_next_pile_id` e chama `free()` em todas as pilhas destacadas criadas; o Grupo C comprova `next_pile_id`, `raw_piles_count`, `pile_root_children` e `nodes` idênticos e zero vazamentos no encerramento Godot.
14. **Existe algum cenário não coberto pelos testes?** Sim — declarados explicitamente: (a) destruição forçada do processo/cena durante execução fora da thread principal; (b) movimentação autônoma real via `DeliverToCampOrder` / `ConstructOrder` (escopo C3.4.3); (c) validação manual visual em cena jogável; (d) sessões longas com milhares de recibos/operações (sem benchmark de retenção em memória).
15. **A implementação exige decisão normativa ainda não aprovada?** Não altera nenhuma norma aprovada e mantém `DEC-T3.6-SIGNALS-01` aberto com a política provisória compatível com C2-R1 e C3.2; D3 permanece bloqueado.
16. **Algum componente novo introduziu complexidade desnecessária?** Não: apenas 2 arquivos novos enxutos (`selective_camp_delivery_coordinator.gd` e `selective_camp_delivery_tx_helpers.gd`) espelhando fielmente a arquitetura da C3.2 (`SelectiveSiteDeliveryCoordinator`), sem segunda autoridade nem camada genérica especulativa.
17. **Os resultados de testes comprovam as garantias anunciadas ou apenas o retorno de sucesso?** Comprovam as garantias estruturais: verificam snapshots completos de mochila/ledger/pilhas/reservas/claims/nós/conexões/revisões, conservação global de matéria, ausência de `node_added` pré-commit, bloqueio real de mutadores concorrentes dentro de todos os 6 sinais, bloqueio físico por parede sólida e execução de todos os 15 estágios de rollback.

## 22. Limitações

- Sem integração com `DeliverToCampOrder`, `ConstructOrder` ou coleta T2 (escopo da C3.4.3).
- Sem validação manual/visual em cena jogável (testes automatizados headless em Godot 4.7.2).
- `DEC-T3.6-SIGNALS-01` permanece pendente (política provisória mantém guardas durante publicação de sinais).
- Validadores personalizados (`_custom_position_validator`) e `pile_creator_override` são recusados conservadoramente até que exista contrato verificável de pureza.
- Toggling `Callable() → fn → Callable()` em `_custom_position_validator` sem mudança de geometria/capacidade/navegação não incrementa `CampStorageZone._config_revision`.
- Lotes `SITE_RESERVED` de obras não ativas seguem bloqueados por dependência D3 (`d3_cancellation_not_implemented`).
- Recibos permanecem em memória pelo ciclo de vida do `World3D` (sem persistência T3.8).

## 23. Pendências para C3.4.3

1. Integrar `SelectiveCampDeliveryCoordinator` em modo opt-in ao fluxo de `DeliverToCampOrder` e ao retorno seletivo de `ConstructOrder` (substituindo o encerramento `selective_camp_delivery_required` da C3.3 quando apropriado).
2. Alocar `operation_id` determinístico na `RegionalAuthority` para descargas iniciadas por ordens (análogo a `_allocate_construction_transfer_ids`), com retentativa segura em `busy` e replay idempotente.
3. Reavaliar `DEC-T3.6-SIGNALS-01` antes de expandir reações de ordens a sinais pós-commit.

## 24. Arquivos alterados

- **Modificados:**
  - `src/economy/camp_storage_zone.gd` (`+50/-8`: `_config_revision` monotônico em setters + notificações de transform)
  - `src/economy/ground_resource_pile.gd` (`+28`: `_configure_initial_detached_for_commit` e `_finalize_detached_visuals_after_commit`)
  - `src/economy/ground_pile_manager.gd` (`+193`: helpers internos silenciosos de checkpoint, merge, criação destacada, restauração de reserva, rollback e finalização pós-commit)
  - `src/economy/reserved_withdrawal_coordinator.gd` (`+83/-4`: `RECEIPT_CAMP_DELIVERY`, `CampDeliveryScope`, `active_camp_delivery`, `_owns_camp_delivery_scope`, `_resolve_camp_authority`, suporte em `_read_receipt`)
  - `src/economy/selective_camp_delivery_planner.gd` (`+66/-17`: `_prepare_under_camp_delivery_scope` e `config_revision` em `revisions.camp_config`)
- **Criados:**
  - `src/economy/selective_camp_delivery_tx_helpers.gd` (`+422`, + `.uid`)
  - `src/economy/selective_camp_delivery_coordinator.gd` (`+553`, + `.uid`)
  - `tests/integration/test_t3_6_2_c3_4_2_selective_camp_delivery_commit.gd` (`+1066`, + `.uid`)
  - `docs/testing/T3_6_2_C3_4_2_candidate_report.md`

## 25. Commits e SHA final (`feat/t3-6-2-provenance-transactions`)

- **SHA-base:** `d54750c11d9141cf427ba507febb4894d02f21a2`
- **Commit 1 (`feat`):** `ff64bc4ea164ef79a11039e9c36901797901b171` — `feat(t3.6.2-c3.4.2): add atomic selective camp delivery coordinator and detached pile commit`
- **Commit 2 (`test`):** `c251340739bae3eec68ee50f2e90232db5b96255` — `test(t3.6.2-c3.4.2): add adversarial commit, rollback, replay, and reentrancy integration suite`
- **Commit 3 (`docs`):** commit seguinte contendo este relatório.
