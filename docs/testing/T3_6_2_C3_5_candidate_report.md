# Dawn of Kin — Relatório Técnico da Candidata T3.6.2-C3.5
## Integração opt-in da coleta com proveniência ao ciclo real dos trabalhadores

**Status da candidata:** **T3.6.2-C3.5 — Candidata publicada para auditoria independente.** *(Sem ativação global de proveniência; sem homologação automática; sem merge na `main`; sem criação de tags; sem início de etapas futuras.)*

### Classificação normativa e de verificação

| Marcador | Classificação aplicada |
| --- | --- |
| **DECIDIDO** | GDD v1.2 (D2, D3, D9, DEC-11A/B, DEC-18/19), economia física e cadência de extração/peso da T2, reserva de slots em `ResourceSource`, transações opt-in B3.2 (`transfer_to_carry_load_with_provenance`) e descarga seletiva C3.4.2/C3.4.3 (`DeliverToCampOrder` + `SelectiveCampDeliveryCoordinator`). |
| **IMPLEMENTADO** | Alocação regional compartilhada de IDs de coleta (`ReservedWithdrawalCoordinator._allocate_gather_operation_ids`), proteção pós-commit e leitor puro de recibo em `ResourceSource` (`_coordinator_transaction_locked` durante sinais pós-commit, checagem ampliada em `is_transaction_busy() or _coordinator_transaction_locked`, e `get_provenance_receipt`), sessão transacional congelada `GatherTransferSession`, integração opt-in isolada em `GatherResourceOrder` (`use_provenance_transactions`, `region_id`) e atalhos removíveis `Ctrl+8`/`Ctrl+9` no harness manual `t3_6_2_c3_4_3_manual_harness.gd`. |
| **TESTADO AUTOMATICAMENTE** | Suíte adversarial `test_t3_6_2_c3_5_gather_order_integration.gd` (**6/6 testes, 964 asserções**, cobrindo os 60 cenários A–F em cena real `MainScene`/`TestMap` com NavMesh); regressão completa `test_t3_6_2` (**12 suítes, 113/113, 9.203 asserções**); filtros T2 dedicados (`worker_cycle`, `natural_source_states`, `pace_and_load`, `playable_economy`, `resource_sources`, `worker_transfer`, `camp_piles`); `validate.ps1` (**148 scripts**, 0 erros, 0 avisos); regressão segmentada global (`54` suítes, **402/402 testes, 22.234 asserções**, `Discovered=54`, `ExecutedUnique=54`, `Duplicates=0`, `Missing=0`, 0 erros/avisos/vazamentos). |
| **NÃO TESTADO MANUALMENTE** | Permanecem **PENDENTES** os **6 itens manuais (M1–M6)** da C3.4.3 em [T3_6_2_C3_4_3_manual_test_protocol.md](T3_6_2_C3_4_3_manual_test_protocol.md) e os **4 itens complementares (M7–M10)** da C3.5 em [T3_6_2_C3_5_manual_test_protocol.md](T3_6_2_C3_5_manual_test_protocol.md). Nenhuma validação visual interativa em janela real foi realizada pelo agente. |
| **PROPOSTA** | Documento arquitetural `T3.6-R2` (`69c13275a34a30564ac839ec920f83ef36590812:docs/architecture/T3_6_cancellation_architecture_R2_PROPOSAL.md`) consultado estritamente como referência técnica sem conversão em regra normativa. |
| **ABERTO** | `DEC-T3.6-SIGNALS-01` (política definitiva de guardas em publicação de sinais), política futura de migração de mochilas legadas e persistência em disco T3.8. |
| **BLOQUEADO** | Ativação global de proveniência em `CommandController` / RTS padrão, cancelamento D3, custódia/reembolso de obras, remoção definitiva DEC-09, novas profissões, novos controles permanentes de HUD e etapas posteriores à C3.5. |

---

## 1. SHA-base, branch, worktree e referências verificadas

- **SHA-base obrigatório verificado antes de editar:** `4e898980cd9bdafd038cdd044ce07439764c52d8` (`feat/t3-6-2-provenance-transactions` local e `origin/feat/t3-6-2-provenance-transactions` coincidentes, árvore limpa).
- **Main de referência:** `25e0a20f1d6a2f10a9e059afe69759fbe263db4a` (inalterada).
- **Tags preservadas:** `t1-complete`, `t2-complete`, `t3-3-complete` (intactas).
- **Worktree:** `C:\Projetos\Dawn_of_Kin_wt_t3_4_5` (`C:\Projetos\Dawn of Kin` não modificado).
- **Branch publicada:** `feat/t3-6-2-provenance-transactions` (`Julian0s/Dawn-of-Kin`).
- **Engine:** Godot `4.7.2.stable.official.ed1daf0bf`.

---

## 2. Matriz de riscos (auditoria pré-implementação)

| Risco identificado | Invariante protegida | Mitigação implementada | Teste correspondente |
| --- | --- | --- | --- |
| Quebra de compatibilidade T2 ou conversão silenciosa entre mochilas | Mochilas legadas não migram; RTS padrão fica em legado | Parâmetro opt-in `p_use_provenance_transactions = false`; admissão fail-closed (`REASON_PROVENANCE_REQUIRED` / `REASON_PROVENANCE_OPT_IN_REQUIRED`); `CommandController` intocado | Grupo A (Cenários 1–6) + bateria T2 completa |
| Mutação de capacidade, `begin_batch()` ou cancelamento/substituição da ordem dentro de `load_changed`, `amount_changed` ou `depleted` | Observadores pós-commit da B3.2 não alteram capacidade nem quebram o ciclo no mesmo stack; pré-commit ABA da B3.2 continua testável | Em `ResourceSource.transfer_to_carry_load_with_provenance`, `_coordinator_transaction_locked` passa a ser mantido **estritamente** durante a emissão pós-commit de sinais (`_emit_load_changed`, `amount_changed`, `depleted`), sem bloquear `_before_provenance_transfer_commit()` da B3.2; entrada checa `carry_load.is_transaction_busy() or carry_load._coordinator_transaction_locked`; `GatherResourceOrder.is_provenance_transfer_executing()` bloqueia reentrância | Grupo E (45–47) + `test_t3_6_2_b3_2` |
| Loop infinito de entrega quando carga residual `SITE_RESERVED` ocupa a mochila | Lotes `SITE_RESERVED` nunca são descartados, convertidos em livre ou re-tentados em ciclo sem progresso | `_has_eligible_free_lots(carry_load)` verifica presença de lotes `FREE_GATHERED > 0` antes de iniciar entrega; após retorno seletivo conservador, `can_fit_one(def) == false` encerra com `REASON_INSUFFICIENT_CARRY_CAPACITY` | Grupo C (21–28) |
| Duplicação de extração em `busy`, resultado incerto, replay após esgotamento ou troca de ordem | Mesmo intento usa o mesmo `(operation_id, lot_id, requested_amount)`; replay retorna `extracted = 0` | `GatherTransferSession` congela identidade de 15 campos e IDs regionais da `RegionalAuthority`; retenta até `MAX_BUSY_RETRIES = 4` (`0,25 s`); em resposta incerta consulta `source.get_provenance_receipt(op)` e realiza replay idempotente; `total_extracted_units` e `extraction_cycles_completed` só avançam se `not replayed and extracted > 0` | Grupo D (29–38) |
| Extração remota, slot abandonado ou crédito antecipado antes da chegada ao acampamento | Sem estoque no acampamento antes da entrega física; zero slots órfãos após saída | Verificação `_is_unit_in_working_range` antes de cada extração e falha explícita `"out_of_gather_range"` em deslocamento durante `busy`; entrega via `DeliverToCampOrder` seletivo na NavMesh; `_release_source_reservation()` em todas as saídas | Grupo B (7–19) + Grupo D (`37b`) + Grupo E (39–50) |
| Estado econômico intermediário visível em sinais ou colisão de recibos com construção | Nenhuma fonte paralela de verdade e nenhum estado parcial em notificações | Recibos de extração permanecem em `ResourceSource._provenance_receipts` sem poluir `RegionalAuthority.receipts`, usando o contador compartilhado `authority.construction_transfer_serial`; commit da B3.2 e C3.4.2 atomicamente antes dos sinais | Grupo B (10) + Grupo F (51–60) |

---

## 3. Arquitetura implementada e contratos preservados

1. **Alocação regional unificada sem autoridade paralela (`src/economy/reserved_withdrawal_coordinator.gd`):**
   - Adicionado `_allocate_gather_operation_ids(inventory, camp_zone, source, unit, region_id, order_identity, cycle_index)`.
   - Reutiliza a mesma `RegionalAuthority` resolvida via `_resolve_camp_authority(...)` e o mesmo contador monotônico `authority.construction_transfer_serial`, sem exigir `ConstructionSite` e sem misturar recibos de coleta dentro de `authority.receipts`.
   - Emite pares prefixados `gather:<world>:<serial>:<region>:<source_inst>:<source_id>:<unit_inst>:<load_inst>:<order_id>:<cycle>` e `lot:gather:...`, validando colisões em `authority.receipts`, `authority.committed_lots`, `load._provenance._operations/_used_lots` e `source._provenance_receipts`.
2. **Endurecimento transacional e leitura de recibo em `ResourceSource` (`src/economy/resource_source.gd`):**
   - A guarda de entrada de `transfer_to_carry_load_with_provenance` passa a verificar `_is_transferring or carry_load == null or carry_load.is_transaction_busy() or carry_load._coordinator_transaction_locked`, permitindo que `begin_batch()`, aplicação ativa ou trava de coordenador retornem `"busy"` sem consumir seriais ou alterar recibos.
   - Mantém `carry_load._coordinator_transaction_locked = true` durante a publicação pós-commit (`carry_load._emit_load_changed()`, `amount_changed`, `depleted`), impedindo que observadores alterem capacidade, entrem em `begin_batch()` ou cancelem/substituam ordens via `Unit`, mantendo intacto o gancho pré-commit `_before_provenance_transfer_commit()` da B3.2.
   - Expõe `get_provenance_receipt(operation_id)` como consulta pura somente-leitura (retornando cópia com `carry_load_instance_id` inteiro, sem vazar referências internas).
3. **Sessão congelada de coleta (`src/units/orders/gather_transfer_session.gd`):**
   - `class_name GatherTransferSession extends RefCounted`, espelhando o padrão da C3.4.3 (`CampDeliveryTransferSession`).
   - Congela identidade de 15 campos (`world`, `region_id`, `inventory`, `storage`, `camp_zone`, `zone_id`, `source`, `source_id`, `resource_id`, `unit_weight`, `unit`, `load`, `provenance_unit_id`, `order_id`, `cycle_index`), `requested_amount`, `operation_id` e `lot_id`.
   - Executa transferência exclusivamente via `ResourceSource.transfer_to_carry_load_with_provenance(...)` por meio de `_invoke_source_transfer(source, carry_load)` (indireção virtual sem callbacks mutáveis de teste em produção).
4. **Integração opt-in em `GatherResourceOrder` (`src/units/orders/gather_resource_order.gd`):**
   - Assinatura retrocompatível: `_init(..., p_use_provenance_transactions: bool = false, p_region_id: StringName = &"")`.
   - Caminho legado preservado integralmente; modo opt-in orquestra `GatherTransferSession` na fase `GATHERING` e instancia `DeliverToCampOrder(camp_zone, inventory, true, region_id, [])` na fase `DELIVERING_TO_CAMP`.
   - `CommandController` (`src/rts/command_controller.gd`), `ConstructOrder` (`src/units/orders/construct_order.gd`), `Unit`, HUDs e cenas permanentes não sofreram alterações.

---

## 4. Alterações na ordem de coleta, identidade, replay e segurança de sinais

### Alterações em `GatherResourceOrder`
- **Admissão restrita em `start()` e `physics_update()`:** em modo legado (`false`), recusa mochilas com proveniência usando `REASON_PROVENANCE_OPT_IN_REQUIRED`; em modo opt-in (`true`), recusa mochilas legadas usando `REASON_PROVENANCE_REQUIRED` e valida integridade do ledger (`validate_provenance()`), igualdade de `World3D`, `region_id` e compatibilidade `storage.get_camp_zone() == camp_zone` antes de adquirir slot ou alterar estado.
- **Ciclo preservado sem etapas artificiais:** mantém `APPROACHING_SOURCE` → `GATHERING` (com `_preparing_cycle` e `gather_interval_sec`) → `_awaiting_felling_before_delivery` (quando aplicável em árvores) → `DELIVERING_TO_CAMP` → novo `APPROACHING_SOURCE`.
- **Contabilização:** `total_extracted_units` e `extraction_cycles_completed` são incrementados exclusivamente quando `not last_extraction_replayed and last_extracted_units > 0`; `_delivered_trips` soma `_deliver_order.trips_completed` (também `0` em replay).
- **Navegação:** falha imediatamente com `REASON_NAVIGATION_NOT_READY` quando `!is_navigation_ready()` sem bake ativo; quando há sincronização/rebake ativo (`_is_syncing` ou `_active_rebake_token != null` ou `pending_building_nav_sync`), pausa via sinais (`_wait_for_navigation()`) sem creditar estoque e retoma em `navigation_ready`.

### Identidade dos intentos e proteção de replay
- **Identidade de 15 campos** verificada antes da alocação e antes de cada retentativa em `GatherTransferSession._execute_locked()`. Alterações entre tentativas (ex.: mutação de `source_id`, troca de unidade/mochila/canteiro/acampamento) encerram com `"transaction_identity_changed"`.
- **`busy` e limites:** respostas `"busy"` não alocam novo ID, preservam `operation_id`, `lot_id` e `requested_amount`, aguardam `RETRY_INTERVAL_SEC = 0.25` e encerram em `MAX_BUSY_RETRIES = 4` com `"busy_retry_exhausted"`.
- **Resultado incerto:** retornos sem campo booleano `"ok"` marcam `_outcome_uncertain = true`, **nunca** consomem novo serial, consultam `source.get_provenance_receipt(_operation_id)` e, encontrando recibo correspondente aos participantes e lote, executam replay idempotente (`replayed = true, extracted = 0`). Sem recibo (inclusive se a fonte tiver sido removida/destruída), encerram com `"unknown_transaction_outcome"`.
- **Fonte esgotada com recibo válido:** `ResourceSource.transfer_to_carry_load_with_provenance` verifica `_provenance_receipts.has(op)` antes de `is_available()`, e `GatherTransferSession._build_live_identity` exige nó válido na árvore com definição íntegra sem exigir `_remaining_amount > 0`, permitindo reconhecer recibos mesmo após esgotamento no último golpe.

### Segurança de callbacks e sinais (auditoria B3.2 / C3.5)
Auditados todos os pontos internos durante `transfer_to_carry_load_with_provenance`:
1. **`_before_provenance_transfer_commit()`:** executa **antes** do commit enquanto `_is_transferring = true` e `carry_load._provenance_busy = true`; default é retorno puro `true` (hook exclusivo de teste da B3.2 para aborto e mutação ABA pré-commit sem bloqueio de capacidade).
2. **`_trigger_tree_felling_if_needed(became_depleted)`:** executa somente **após** atualizar `_remaining_amount` e registrar `_provenance_receipts[op]`; no esgotamento direto passa a `TreeVisualState.FALLEN` sem tween, e na primeira extração parcial inicia `_felling_tween` (`FELLING → FALLEN`) apenas visual, enquanto `GatherResourceOrder` aguarda `_awaiting_felling_before_delivery` antes de caminhar para entrega sem reextrair nem duplicar estoque.
3. **`_sync_visuals()` e `_trigger_gather_feedback()`:** puramente visuais sobre `AvailableVisual`, `DepletedVisual`, `Fruits` e `DiscoverabilityBadge`, após commit.
4. **`load_changed`, `amount_changed`, `depleted`:** disparados somente **após** saldo da fonte, mochila, ledger e recibo estarem integralmente consistentes e com `_is_transferring = true`, `_provenance_busy = true` e `carry_load._coordinator_transaction_locked = true`.
   - Observadores não conseguem iniciar `transfer_to_carry_load_with_provenance` (`"busy"`), `transfer_to_carry_load` (`0`), `set_base_capacity` (`false`), `begin_batch()` (bloqueado), `add_with_provenance` (`"unavailable"`), `take_all` (`{}`), `Unit.cancel_current_order()`/`issue_order()` (bloqueado por `_is_reserved_withdrawal_locked`), nem `GatherResourceOrder.cancel()`/`physics_update()` (`is_provenance_transfer_executing()` adia replanejamento com `_replan_requested = true`).
   - **`DEC-T3.6-SIGNALS-01` permanece aberta.**

---

## 5. Carga mista, cancelamento, falhas e conservação física

- **Carga mista e anti-loop:** quando a mochila mistura lotes livres (`wood`, `stone`, `food`) e lotes `SITE_RESERVED` (Obra A e Obra B), `_can_start_delivery_with_current_cargo()` e `DeliverToCampOrder` seletivo conservador (`requested_lots = []`) descarregam exclusivamente `FREE_GATHERED`. Ao término da entrega, se `not carry_load.can_fit_one(source_def)` devido à carga residual reservada, a ordem encerra imediatamente com `REASON_INSUFFICIENT_CARRY_CAPACITY` sem voltar ao acampamento, mantendo claims, reservas e lotes das Obras A e B inalterados.
- **Cancelamento em todas as fases:**
  - Antes da extração (aproximação, preparação, `RETRY_SCHEDULED`): nenhuma extração futura ocorre porque `cancel_intent(source, _unit)` marca `_cancelled = true` (`"order_cancelled"`) e `_release_source_reservation()` devolve o slot.
  - Durante queda de árvore, transporte (`DELIVERING_TO_CAMP`) ou retentativa de descarga: lotes já comprometidos permanecem com seu `lot_id` e peso na mochila; nenhum recurso entra no acampamento; sessão de entrega é bloqueada permanentemente.
  - Remoção controlada de trabalhador via `TemporaryTestWorkersController`: com carga na mochila (`FREE_GATHERED`), `can_remove_temporary_workers()` recusa com `"cargo_in_backpack"`; com mochila vazia segurando slot na fonte, `remove_temporary_workers_safely()` aciona `_exit_tree()` / `cancel_current_order()` e libera o slot sem órfãos.
- **Falhas de entrega no acampamento:** se `SelectiveCampDeliveryCoordinator` recusar (ex.: `unsafe_pile_creator_override`, `no_valid_camp_slot`), `GatherResourceOrder` falha com a razão real e preserva integralmente todos os lotes `FREE_GATHERED` e `SITE_RESERVED`.
- **Conservação física:** verificada quadro a quadro e dentro dos observadores dos 8 sinais (`load_changed`, `amount_changed`, `depleted`, `storage_changed`, `inventory_changed`), comprovando `remaining_source + carried_free + camp_free == constante`, lastro integral das reservas nas pilhas, igualdade de claims vs lotes `SITE_RESERVED` e liberação de todas as guardas em sucesso e erro.

---

## 6. Mapeamento dos 60 cenários adversariais (`test_t3_6_2_c3_5_gather_order_integration.gd`)

| Grupo | Cenários cobertos | Função de teste | Resultado / Asserções |
| --- | --- | --- | --- |
| **Grupo A — Compatibilidade** | 1–6 (coleta/entrega legada, default off, recusa cruzada legado↔proveniência, `CommandController` legado) | `test_group_a_compatibility_opt_in_default_off_and_strict_isolation` | **PASS** (56 asserções) |
| **Grupo B — Ciclo real** | 7–20 (alcance físico, slot 1-worker, preparação, lote `FREE_GATHERED` + autoridade compartilhada sem poluir `authority.receipts`, fonte/mochila exatas, peso/desaceleração + pedra 90%, zero crédito antecipado, entrega seletiva, multi-viagem, queda de árvore + esgotamento no último corte + arbusto/pedra) | `test_group_b_real_cycle_slots_weights_felling_and_depletion` | **PASS** (417 asserções) |
| **Grupo C — Carga mista** | 21–28 (madeira/pedra/alimento livres + Obras A e B reservadas, descarga só livre, claims/buffers intactos, capacidade residual, zero loop com carga inelegível inicial ou residual pós-descarga, falha conservadora mantendo carga) | `test_group_c_mixed_cargo_selective_delivery_and_anti_loop` | **PASS** (151 asserções) |
| **Grupo D — Idempotência** | 29–38 (1º commit, replay, operação repetida / commit externo durante `busy` sem duplicar ciclo/total, conflitos de lote/quantidade/fonte/unidade, `busy` retry preservando IDs + `MAX_BUSY_RETRIES = 4`, resultado incerto com e sem commit real, replay em fonte esgotada, mudança de identidade, deslocamento em retry `out_of_gather_range`, substituição de ordem) | `test_group_d_idempotency_busy_retries_uncertain_outcome_depleted_replay_and_conflicts` | **PASS** (114 asserções) |
| **Grupo E — Falhas e reentrância** | 39–50 (cancelamento pré-coleta/preparação/retry, cancelamento em queda da árvore/transporte/pré-descarga, fonte removida inclusive em resultado incerto, remoção controlada via `TemporaryTestWorkersController`, navegação indisponível + espera/retomada de sync, reentrância em `amount_changed`, `depleted`, `load_changed`, falha na descarga mantendo carga, zero slots abandonados, bloqueio de execução pós-cancelamento) | `test_group_e_cancellations_removals_navigation_callbacks_and_guards` | **PASS** (140 asserções) |
| **Grupo F — Conservação** | 51–60 (conservação extração/descarga por quadro e em observadores, zero lotes/reservas órfãos, recibos únicos sem duplicação, pesos conciliados, Obras A/B intocadas, zero recurso fictício em replay, zero estado intermediário em sinais, todas as guardas liberadas) | `test_group_f_conservation_invariants_observer_atomicity_and_guard_cleanup` | **PASS** (86 asserções) |

---

## 7. Resultados completos das regressões (§12)

Todas as execuções ocorreram no worktree `C:\Projetos\Dawn_of_Kin_wt_t3_4_5` sobre a versão final do código, com saída completa `0 erros`, `0 avisos` e `0 vazamentos`:

| Comando executado | Exit | Suítes | Testes | Asserções | Status |
| --- | --- | --- | --- | --- | --- |
| `.\tools\run_tests.ps1 -Filter test_t3_6_2_c3_5` | 0 | 1 | 6/6 | 964 | PASS |
| `.\tools\run_tests.ps1 -Filter test_t3_6_2_b3_2` | 0 | 1 | 4/4 | 79 | PASS |
| `.\tools\run_tests.ps1 -Filter test_t3_6_2_c3_4_3` | 0 | 1 | 8/8 | 1.187 | PASS |
| `.\tools\run_tests.ps1 -Filter test_t3_6_2_c3_4_2` | 0 | 1 | 11/11 | 1.841 | PASS |
| `.\tools\run_tests.ps1 -Filter test_t3_6_2_c3_4_1` | 0 | 1 | 26/26 | 3.227 | PASS |
| `.\tools\run_tests.ps1 -Filter test_t3_6_2_c3_3` | 0 | 1 | 10/10 | 328 | PASS |
| `.\tools\run_tests.ps1 -Filter test_t3_6_2` | 0 | 12 | 113/113 | 9.203 | PASS |
| `.\tools\run_tests.ps1 -Filter test_t2_worker_cycle` | 0 | 1 | 8/8 | 2.660 | PASS |
| `.\tools\run_tests.ps1 -Filter test_t2_natural_source_states` | 0 | 2 | 8/8 | 194 | PASS |
| `.\tools\run_tests.ps1 -Filter test_t2_pace_and_load` | 0 | 2 | 18/18 | 509 | PASS |
| `.\tools\run_tests.ps1 -Filter test_t2_playable_economy` | 0 | 1 | 8/8 | 351 | PASS |
| `.\tools\run_tests.ps1 -Filter test_t2_resource_sources` | 0 | 1 | 6/6 | 95 | PASS |
| `.\tools\run_tests.ps1 -Filter test_t2_worker_transfer` | 0 | 1 | 5/5 | 53 | PASS |
| `.\tools\run_tests.ps1 -Filter test_t2_camp_piles` | 0 | 2 | 10/10 | 153 | PASS |
| `.\tools\validate.ps1` | 0 | — | — | — | PASS (**148 scripts**, import headless + startup `main.tscn`) |
| `.\tools\run_tests.ps1 -Segmented` | 0 | 54 | 402/402 | 22.234 | PASS (12/12 lotes; `Discovered=54`, `ExecutedUnique=54`, `Duplicates=0`, `Missing=0`; 0 erros/avisos/vazamentos) |
| `git diff --check` | 0 | — | — | — | PASS |

*(Nota de transparência: na execução segmentada completa em 12 lotes, `test_t2_worker_cycle::test_03` registrou `140` asserções contra `142` na execução filtrada isolada — totalizando `2.658` vs `2.660` na suíte — variação natural de contagem de quadros dentro do laço de caminhada real, com 100% dos testes aprovados e zero falhas.)*

---

## 8. Autorrevisão adversarial (§13 — 16 questões respondidas com evidência)

1. **Quais métodos aparentemente seguros foram reutilizados?**
   `ResourceSource.transfer_to_carry_load_with_provenance(...)` (B3.2), `DeliverToCampOrder` em modo seletivo + `CampDeliveryTransferSession` (C3.4.3), `ReservedWithdrawalCoordinator._resolve_camp_authority(...)`, `UnitMovement` (`begin_move_to`, `stop_movement`, `face_towards`), `GatherSlotPlanner` (`collect_other_unit_positions`, `compute_source_approach_slot`) e `Unit.cancel_current_order()` / `issue_order()`.
2. **Quais efeitos indiretos eles executam?**
   - `ResourceSource.transfer_to_carry_load_with_provenance` invoca `_before_provenance_transfer_commit()`, inicia `_felling_tween` (`_trigger_tree_felling_if_needed`), altera nós visuais/frutos (`_sync_visuals`), cria tween de impacto (`_trigger_gather_feedback`), emite `load_changed` (que aciona `UnitMovement._recompute_target_speed`), `amount_changed` e `depleted`.
   - `DeliverToCampOrder.start` inicia caminhada (e faz preflight puro sem criar `RegionalAuthority`), e ao chegar no slot chama `SelectiveCampDeliveryCoordinator`, alterando pilhas, `GroundPileManager`, `SettlementInventory`, HUD e `load_changed`.
   - `_resolve_camp_authority` grava metadata `DOMAIN_META` no `World3D` e vincula `storage._withdrawal_world`/`storage._withdrawal_region` na primeira operação real.
   - `_wait_for_navigation` para movimento (`IDLE`), podendo provocar falso cancelamento caso `_update_approaching` tratasse `IDLE` como cancelamento sem distinguir pausa reativa.
3. **Existem callbacks externos durante estados parciais?**
   Não para estado econômico: em `transfer_to_carry_load_with_provenance`, `_apply_prepared_provenance_add`, `_remaining_amount`, `_transaction_revision` e `_provenance_receipts[op]` já estão integralmente comprometidos antes de qualquer sinal (`load_changed`, `amount_changed`, `depleted`), como comprovado pelos observadores no Grupo F (`59`) sem estados parciais. O único hook pré-commit (`_before_provenance_transfer_commit`) é protegido por revisão e aborta antes de qualquer mutação (retestado por `test_t3_6_2_b3_2`).
4. **Algum sinal pode provocar reentrada?**
   Sem proteção extra, `load_changed`, `amount_changed` e `depleted` permitiriam `set_base_capacity`, `begin_batch`, `Unit.cancel_current_order()` ou `physics_update` no mesmo stack. **Risco crítico encontrado e corrigido antes da publicação:** em `src/economy/resource_source.gd`, `carry_load._coordinator_transaction_locked = true` passou a envolver exclusivamente os sinais pós-commit (`_emit_load_changed`, `amount_changed`, `depleted`), a entrada de `transfer_to_carry_load_with_provenance` passou a recusar `is_transaction_busy() or _coordinator_transaction_locked` com `"busy"`, e `GatherResourceOrder.is_provenance_transfer_executing()` bloqueia `cancel()` e adia `physics_update()` (`_replan_requested = true`). Evidência: `test_group_e_cancellations_removals_navigation_callbacks_and_guards` (Cenários 45–47).
5. **Existe caminho capaz de duplicar uma extração?**
   Não nos fluxos auditados: (a) cada ciclo aloca um único serial monotônico em `RegionalAuthority.construction_transfer_serial`; (b) retentativas `busy` reutilizam exatamente os mesmos `(operation_id, lot_id, requested_amount)`; (c) `ResourceSource._provenance_receipts` retorna `replayed = true, extracted = 0` para repetição idêntica e `"operation_conflict"` para divergência; (d) `GatherResourceOrder` só incrementa `total_extracted_units` e `extraction_cycles_completed` se `not last_extraction_replayed and last_extracted_units > 0`; (e) em árvores em queda, `_awaiting_felling_before_delivery` apenas aguarda `is_felling()` encerrar sem reexecutar extração. Evidência: Grupos B (20), D (29–38) e F (58).
6. **Existe caminho capaz de perder um lote após cancelamento?**
   Não via fluxos de ordem: `GatherResourceOrder.cancel`, `_finish_failed` e `_finish_cancelled` jamais chamam `take_all()`, `remove_units()` nem descartam lotes do `CarryProvenanceLedger`; o cancelamento na entrega ou antes da descarga preserva tanto `FREE_GATHERED` quanto `SITE_RESERVED` e seus claims. Evidência: Grupo C (26–28) e Grupo E (40, 41, 48).
7. **Existe estado que provoca loop infinito?**
   **Sim, identificado na auditoria prévia:** se a mochila contivesse apenas lotes `SITE_RESERVED` (ou lotes residuais após uma entrega seletiva conservadora deixando `not carry_load.can_fit_one(source_def)`), o código legado entraria em loop tentando descarregar sem esvaziar. **Corrigido em `GatherResourceOrder`:** `_can_start_delivery_with_current_cargo` exige `_has_eligible_free_lots(carry_load)` no modo opt-in, e `_handle_deliver_finished` falha explicitamente com `REASON_INSUFFICIENT_CARRY_CAPACITY` se `not carry_load.can_fit_one(source_def)` após a entrega seletiva. Também removida a reaproximação automática em `out_of_gather_range` pós-sessão aberta, evitando perseguição infinita. Evidência: Grupo C (21–28) e Grupo D (`37b`).
8. **Algum trabalhador pode abandonar uma reserva de slot?**
   Toda criação de reserva (`_acquire_source_reservation`) é acompanhada por `_release_source_reservation()` em `_start_delivering`, `cancel`, `_finish_succeeded`, `_finish_failed` e `_finish_cancelled`, além de `Unit._exit_tree()` acionar `exiting_order.cancel(...)` (e `ResourceSource._prune_invalid_workers()` limpar IDs inválidos como salvaguarda). Validado por `_assert_all_guards_clear` ao fim de todos os grupos A–F e explicitamente no Cenário 43 com `TemporaryTestWorkersController`.
9. **Um recibo pode ser usado por outra fonte ou unidade?**
   Não: `ResourceSource._provenance_receipts` pertence à instância específica de cada fonte e valida `old.load.get_ref() == carry_load`, `old.source == source_id`, `old.lot`, `old.requested`, `old.resource` e `old.weight`; além disso, `GatherTransferSession` compara `_identity` de 15 campos (incluindo instâncias de fonte, unidade, mochila, mundo e região) e verifica `_receipt_matches_session` na reconciliação de resultado incerto. Evidência: Grupo D (Cenário 32).
10. **Uma ordem encerrada pode afetar a próxima ordem?**
    Não: `GatherTransferSession` marca `SUCCEEDED`/`FAILED`/`CANCELLED` (`is_closed() == true`) de modo terminal (`intent_already_closed` / `order_cancelled`); `_active_gather_session` e `_deliver_order` são encerrados e limpos antes de concluir; sinais de navegação são sempre desconectados em `_disconnect_navigation_signals()`, e `GatherResourceOrder.is_provenance_transfer_executing()` exige `status == Status.RUNNING`. A próxima ordem aloca novo serial regional e novas instâncias de sessão. Evidência: Grupos D (38) e E (39b, 41, 50).
11. **Um resultado `busy` altera indevidamente o intento?**
    Não: quando `execute_or_retry` recebe `"busy"`, `_operation_id`, `_lot_id`, `_requested_amount` e `_identity` são preservados intactos em `GatherTransferSession`; apenas `_busy_retries` e `_retry_remaining = 0.25` avançam até `MAX_BUSY_RETRIES = 4` (`busy_retry_exhausted`). Evidência: Grupo D (33, 34).
12. **Existe falha de navegação que credita estoque?**
    Não: `GatherResourceOrder` nunca chama depósito direto no inventário; crédito ao acampamento só ocorre após chegada física no `CampStorageZone` dentro de `DeliverToCampOrder` + `SelectiveCampDeliveryCoordinator`. Quando a navegação falha (`REASON_NAVIGATION_NOT_READY`) ou aguarda rebake (`_is_syncing`), o movimento é interrompido e o estoque do acampamento permanece inalterado. Evidência: Grupo B (15) e Grupo E (44).
13. **O comportamento legado sofreu alteração?**
    Não: `_use_provenance_transactions` inicia `false` por padrão; `CommandController` não foi modificado; todos os 7 filtros T2 de coleta/movimento/fontes/árvores/arbustos/transporte/pilhas (`test_t2_worker_cycle`, `test_t2_natural_source_states`, `test_t2_pace_and_load`, `test_t2_playable_economy`, `test_t2_resource_sources`, `test_t2_worker_transfer`, `test_t2_camp_piles`) e o Grupo A aprovaram 100% sem alterações de contrato.
14. **Os testes verificam efeitos reais ou apenas retornos?**
    Verificam efeitos concretos em cena real (`MainScene`/`TestMap` com `NavigationRegion3D`): posições físicas dos trabalhadores, número de slots ativos em `ResourceSource`, contagens reais em `source.get_remaining_amount()`, `UnitCarryLoad` (`amounts`, `weights`, `provenance_snapshot().ledger`), pilhas físicas em `GroundPileManager`, `SettlementInventory`, claims em `ConstructionSite`, velocidade efetiva de `UnitMovement`, animação `FELLING`/`FALLEN`/frutos e invariantes de observação nos 8 sinais econômicos.
15. **Existem riscos não cobertos pelos testes?**
    Sim (explícitos como riscos residuais): (a) comportamento sob latência/interação real de mouse/teclado em janela gráfica contínua (testes são headless determinísticos com `Engine.time_scale = 3.0`); (b) destruição arbitrária externa de `UnitCarryLoad` por referência solta fora do fluxo de `Unit`/`TemporaryTestWorkersController` enquanto mantém lotes; (c) concorrência de persistência/save-load (`T3.8` não implementada).
16. **Quais limitações permanecem?**
    Ver Seção 9.

---

## 9. Pendências manuais e limitações residuais

- **Pendências de validação manual:**
  - Permanecem **6 itens pendentes (M1–M6)** da C3.4.3 em [T3_6_2_C3_4_3_manual_test_protocol.md](T3_6_2_C3_4_3_manual_test_protocol.md).
  - Permanecem **4 itens pendentes (M7–M10)** da C3.5 em [T3_6_2_C3_5_manual_test_protocol.md](T3_6_2_C3_5_manual_test_protocol.md), testáveis de modo isolado e sem alteração no HUD permanente por meio de [t3_6_2_c3_4_3_manual_harness.gd](../../tests/visual/t3_6_2_c3_4_3_manual_harness.gd) (`Ctrl+1` a `Ctrl+9`).
- **Limitações arquiteturais e de ciclo de vida registradas:**
  - Modo opt-in desligado por padrão no RTS normal (`CommandController`) até etapa de integração global posterior.
  - Migração de mochilas legadas, reembolso/custódia D3 e remoção definitiva DEC-09 permanecem fora de escopo e bloqueados.
  - Se uma `ResourceSource` for destruída/removida da árvore no exato instante de um resultado transacional incerto antes da leitura do recibo, não é possível reconciliar seu recibo histórico — o sistema recusa com `"unknown_transaction_outcome"` sem inventar extração bem-sucedida (Cenário 42b).
  - Recibos e contadores `RegionalAuthority` permanecem em memória vinculados ao ciclo de vida de `World3D` (T3.8 pendente).
  - `DEC-T3.6-SIGNALS-01` segue aberta.

---

## 10. Arquivos modificados e criados

- **Modificados (`src/`):**
  - `src/economy/resource_source.gd` (`+27/-1`)
  - `src/economy/reserved_withdrawal_coordinator.gd` (`+91`)
  - `src/units/orders/gather_resource_order.gd` (`+406/-14`)
- **Criados (`src/`):**
  - `src/units/orders/gather_transfer_session.gd` (`+431`, + `.uid`)
- **Modificados / Criados (`tests/`):**
  - `tests/integration/test_t3_6_2_c3_5_gather_order_integration.gd` (`+1.252`, + `.uid`)
  - `tests/visual/t3_6_2_c3_4_3_manual_harness.gd` (`+51`, extensão removível para `Ctrl+8`/`Ctrl+9` e telemetria)
- **Criados (`docs/`):**
  - `docs/testing/T3_6_2_C3_5_manual_test_protocol.md` (`+115`)
  - `docs/testing/T3_6_2_C3_5_candidate_report.md` (este relatório)

---

## 11. Commits publicados (`feat/t3-6-2-provenance-transactions`)

- **SHA-base:** `4e898980cd9bdafd038cdd044ce07439764c52d8`
- **Commit 1 (`feat`):** `3a22a7fb5a9e452a514ac8767219b8b8232f8278` — `feat(t3.6.2-c3.5): integrate opt-in provenance gathering into GatherResourceOrder`
- **Commit 2 (`test`):** `3522b19c78d4955ff30274a44c01151c0c7768ed` — `test(t3.6.2-c3.5): add adversarial integration suite and manual harness shortcuts`
- **Commit 3 (`docs`):** commit subsequente contendo [T3_6_2_C3_5_manual_test_protocol.md](T3_6_2_C3_5_manual_test_protocol.md) e este relatório [T3_6_2_C3_5_candidate_report.md](T3_6_2_C3_5_candidate_report.md).
