# Dawn of Kin — Relatório Técnico da Candidata T3.6.2-C3.4.3
## Integração opt-in da descarga seletiva às ordens de trabalhadores

**Status da candidata:** **T3.6.2-C3.4.3 — Candidata publicada para auditoria independente e validação manual aplicável.** *(Não homologada; sem ativação global de proveniência; sem merge na `main`; sem tags; sem início de C3.4.4 ou etapas posteriores.)*

### Classificação normativa e de verificação

| Marcador | Classificação aplicada |
| --- | --- |
| **DECIDIDO** | GDD v1.2 (D2, D3, D9, DEC-11A/B, DEC-18/19), economia física no `CampStorageZone` (T2), reservas sem realocação automática (T3.1), transporte e construção progressiva (T3.3–T3.5), transações opt-in C2-R1/C3.1/C3.2/C3.3/C3.4.1-R1/C3.4.2. |
| **IMPLEMENTADO** | Correção pré-integração da C3.4.2 (§2.1: guarda de finalização visual pós-`add_child` em `GroundPileManager` + bloqueio transacional em `CampStorageZone`); alocação regional de `operation_id` sem canteiro em `ReservedWithdrawalCoordinator`; sessão congelada `CampDeliveryTransferSession`; modo seletivo opt-in em `DeliverToCampOrder`; integração opt-in com proteção anti-loop em `ConstructOrder`; harness manual isolado e removível em `tests/visual/t3_6_2_c3_4_3_manual_harness.gd`. |
| **TESTADO AUTOMATICAMENTE** | Suíte adversarial `test_t3_6_2_c3_4_3_order_integration.gd` (8 testes cobrindo os 60 cenários A–F + extras em cena real com deslocamento NavMesh, 1.187 asserções); novo teste §2.1 em `test_t3_6_2_c3_4_2` (`11/11`, 1.841 asserções); todos os filtros T3.6.2 (`11` suítes, `107/107`, 8.239 asserções); `validate.ps1` (`146` scripts, 0 erros, 0 avisos); regressão segmentada integral (`53` suítes, `396/396` testes, `21.275` asserções, 0 erros/avisos/vazamentos). |
| **NÃO TESTADO MANUALMENTE** | Nenhum dos 6 itens (M1–M6) do protocolo [T3_6_2_C3_4_3_manual_test_protocol.md](T3_6_2_C3_4_3_manual_test_protocol.md) foi executado visual/interativamente pelo agente; validação manual pendente de execução pelo proprietário. |
| **PROPOSTA** | Arquitetura T3.6-R2 (`69c13275a34a30564ac839ec920f83ef36590812:docs/architecture/T3_6_cancellation_architecture_R2_PROPOSAL.md`) — preservada estritamente como referência arquitetural, sem promoção a norma. |
| **ABERTO** | `DEC-T3.6-SIGNALS-01` (política definitiva de guardas durante publicação de sinais), política definitiva de migração de mochilas legadas e persistência T3.8. |
| **BLOQUEADO** | Devolução de lotes `SITE_RESERVED` de obras não ativas (`d3_cancellation_not_implemented`), custódia/reembolso D3, ativação global de proveniência, T3.6.3 e T3.6.4. |

---

## 1. SHA-base

- **SHA-base obrigatório verificado antes de editar:** `6d46cea1376b7a573871e09b3d5738edfcf1d67a` (`feat/t3-6-2-provenance-transactions` local e `origin/feat/t3-6-2-provenance-transactions` coincidentes, árvore limpa).
- **Referência da `main` verificada:** `25e0a20f1d6a2f10a9e059afe69759fbe263db4a` (inalterada).
- **Engine verificada:** Godot `4.7.2.stable.official.ed1daf0bf`.

## 2. Branch e worktree

- **Repositório:** `Julian0s/Dawn-of-Kin`
- **Branch:** `feat/t3-6-2-provenance-transactions`
- **Worktree:** `C:\Projetos\Dawn_of_Kin_wt_t3_4_5` (`C:\Projetos\Dawn of Kin` não modificado).

## 3. Contratos consultados e auditoria prévia da C3.4.2 (§2.1)

Foram consultados `AGENTS.md`, `docs/Dawn_of_Kin_GDD.md` (v1.2 — D2, D3, D9, DEC-11A/B, DEC-18/19), `69c13275a34a30564ac839ec920f83ef36590812:docs/architecture/T3_6_cancellation_architecture_R2_PROPOSAL.md` (preservando status de proposta) e os relatórios de C2-R1, C3.2, C3.3, C3.4.1-R1 e C3.4.2, além da inspeção direta de todas as ordens, movimento, planejamento de slots e coordenadores econômicos.

### Achado reproduzido na revisão adicional da C3.4.2 (§2.1) e correção aplicada

Antes da integração em gameplay, foi executado um teste empírico em Godot `4.7.2` exercitando todos os quatro cenários de observador `SceneTree.node_added` na fronteira pós-commit de criação de múltiplas pilhas:

1. **Falha crítica reproduzida na base `6d46cea`:** em `GroundPileManager._finalize_camp_delivery_after_commit_silent(...)` (linha 1519), um observador de `SceneTree.node_added` que executava `remove_child(new_pile); new_pile.free()` na pilha #1 provocava `SCRIPT ERROR: Invalid call. Nonexistent function '_finalize_detached_visuals_after_commit' in base 'previously freed'` e abortava o laço, deixando a pilha #2 permanentemente destacada (`get_parent() == null`). Além disso, `new_pile` entrava na árvore com `is_in_group(GROUP_GROUND_PILES) == false`, e `CampStorageZone` não bloqueava mutações de configuração durante `node_added`, permitindo que um observador alterasse `zone_id` mid-publication e quebrasse a identidade de replay.
2. **Descoberta adicional em Godot 4.7.2 C++:** pré-anexar filhos visuais (`VisualRoot` + 4 `MeshInstance3D`) antes de `_piles_root.add_child(new_pile)` provoca violação de acesso em C++ (`Node::_propagate_enter_tree`) se um observador liberar o nó durante `node_added`. Portanto, cada pilha recém-criada **deve** entrar em `_piles_root` sem filhos (já marcada em `GROUP_GROUND_PILES`), sendo revalidada (`is_instance_valid`, `not is_queued_for_deletion()`, `is_inside_tree()`, `get_parent() == _piles_root`) antes de `_finalize_detached_visuals_after_commit(_visual_cache)`.
3. **Distinção entre alterações pós-commit legítimas e violações de integridade:**
   - **Durante `node_added` (guardas cooperativos ativos sob `DEC-T3.6-SIGNALS-01`):** reentrância transacional (`"busy"`), mutadores da API de armazenamento (`withdraw`/`cleanup` bloqueados) e mutações de `CampStorageZone` (`_coordinator_transaction_locked = true`) são bloqueados cooperativamente; após o retorno do coordenador, alterações de configuração em `CampStorageZone` (com avanço de `_config_revision`) e retiradas via API do `GroundPileManager`/`SettlementInventory` funcionam legitimamente.
   - **Remoção bruta via árvore (`remove_child` / `queue_free` / `free`):** constitui violação externa da integridade do armazenamento (contorna `GroundPileManager`), não gera mais erro/crash nem aborta pilhas subsequentes, e é detectada fail-closed na operação seguinte por `SelectiveCampDeliveryPlanner` como `"invalid_physical_pile_collection"`.
4. **Rastreabilidade:** correção isolada nos commits `cabcb6cb71af55aefe93a13ea69f51871ad6275d` (`fix(t3.6.2-c3.4.2)`) e `b1798085fe4999df8148dabf669a8de17e13f08b` (`test(t3.6.2-c3.4.2)`), antes da integração C3.4.3.

## 4. Matriz de riscos

| Risco | Mitigação implementada | Evidência de teste |
| --- | --- | --- |
| Quebra do modo legado / conversão silenciosa | `DeliverToCampOrder` e `ConstructOrder` mantêm legado como padrão; admissão fail-closed (`provenance_required` / `provenance_opt_in_required`); `CommandController` e `GatherResourceOrder` inalterados | Grupo A (Cenários 1–6) + regressão T2/T3.3–T3.5 |
| Teletransporte ou crédito antes da chegada | Caminhada real na NavMesh em `DeliverToCampOrder`; commit adiado de `start()` para `physics_update` somente após chegada e `check_physical_authorization_participants` | Grupo B (7–9) + Grupo C (18) + Grupo F (55) |
| Descarte total da mochila / conversão de reserva em livre | Proibição de `deliver_from_carry_load()` no modo seletivo; seleção por `lot_id` preservando lotes não selecionados; restauração estrita para a obra de origem | Grupo B (10–14) + Grupo C (20–23) |
| Loop infinito com carga residual inelegível | Classificação por lote concreto em `CampDeliveryTransferSession.inspect_cargo_for_construction_site` + guarda `_last_camp_return_load_revision` + checagem de progresso legítimo antes de reiniciar retorno | Grupo C (23, 24) + `lost_link` |
| Promoção indevida a `BUILDER` (D9) com carga residual | Checagem pré-promoção em `site.is_fully_supplied()` e `try_promote_solo_to_builder` exige mochila vazia ou retorno completo possível antes de promover | Grupo C (`d3_order`, equipe D9 com 3+1 trabalhadores) |
| Duplicação em `busy` / resultado incerto / cancelamento tardio | `CampDeliveryTransferSession` congela `operation_id`, identidade (10 campos) e `requested_lots`; `MAX_BUSY_RETRIES = 4`, `0,25 s`; consulta recibo e faz replay em resultado incerto; `cancel_intent` bloqueia commits futuros e reconhece recibos já comprometidos | Grupo D (27–30) + Grupo E (41–50) |
| Reentrância durante sinais econômicos | `DeliverToCampOrder.is_selective_transfer_executing()` (restrito a `status == RUNNING`) + `ConstructOrder._defer_transfer_replan()` impedem novo commit, subordem recursiva, autocancelamento e dupla contagem | Grupo E (47–49 + reentrância em subordem de `ConstructOrder`) |
| Navegação indisponível / slot invalidado / unidade deslocada | Espera reativa para rebake ativo (`pending_building_nav_sync`/`_is_syncing`), falha imediata quando nav indisponível sem rebake, monitoramento de `_last_camp_config_revision`, revalidação física antes de cada tentativa e retry | Grupo D (31–40) |

## 5. Arquitetura da integração

- **`src/economy/reserved_withdrawal_coordinator.gd`:** adicionado `_allocate_camp_delivery_operation_id(...)` reutilizando a mesma `RegionalAuthority` e o mesmo contador monotônico `construction_transfer_serial` sem depender de `ConstructionSite`.
- **`src/economy/selective_camp_delivery_coordinator.gd` + `src/economy/selective_camp_delivery_tx_helpers.gd`:** adicionado `get_receipt_in_domain(world, region_id, operation_id)` (consulta pura por domínio) e extraído `check_physical_authorization_participants(...)` como fonte única da verificação de proximidade e acesso físico.
- **`src/units/orders/camp_delivery_transfer_session.gd` (`class_name CampDeliveryTransferSession`):** sessão dedicada congelando intento, identidade, seleção normalizada de lotes, retentativas `busy`, reconciliação de resultado incerto, cancelamento definitivo, preflight puro (`probe_preflight`) e classificação por proveniência para obras (`inspect_cargo_for_construction_site`).
- **`src/units/orders/deliver_to_camp_order.gd`:** dois modos explicitamente separados (legado padrão vs. seletivo opt-in).
- **`src/units/orders/construct_order.gd`:** substitui o bloqueio fixo `selective_camp_delivery_required` da C3.3 pelo retorno seletivo real baseado em proveniência, mantendo política padrão conservadora (`return_other_site_reserved = false`) e opção explícita (`return_other_site_reserved = true`) para restauração de lotes de outra obra ativa.

## 6. Comportamento legado preservado

- `DeliverToCampOrder.new(camp_zone, inventory)` mantém `use_selective_provenance = false`, movimento até slot alcançável, descarga via `SettlementInventory.deliver_from_carry_load()`, integração intacta com `GatherResourceOrder`, sem criar `RegionalAuthority` e sem habilitar proveniência.
- `ConstructOrder.new(site, camp_zone, force_transporter)` mantém `p_use_provenance_transactions = false`.
- `CommandController` (entrada RTS) continua emitindo `GatherResourceOrder` e `ConstructOrder` no modo legado por padrão.
- Mochila legada nunca é convertida automaticamente; modo legado em mochila com proveniência falha fechado (`provenance_opt_in_required`).

## 7. Comportamento opt-in

- `DeliverToCampOrder.new(camp_zone, inventory, true, region_id, requested_lots)`:
  1. Exige mochila com proveniência habilitada (`provenance_required` caso contrário).
  2. Congela identidade e seleção normalizada em `CampDeliveryTransferSession` e executa preflight puro (permitindo caminhada quando `busy` e rejeitando pedidos inválidos/inelegíveis/callbacks inseguros imediatamente).
  3. Planeja slot navegável em `CampStorageZone` e caminha fisicamente em `Unit.State.TRANSPORTING` sem creditar recursos durante o trajeto.
  4. Na chegada física, valida proximidade/acesso físico e executa `SelectiveCampDeliveryCoordinator` via sessão congelada.
  5. Registra `last_delivered`, `last_delivered_units`, `last_receipt`, `last_created_pile_ids`, `last_replayed` e incrementa `trips_completed` exclusivamente em commits efetivos (`not replayed and delivered_now > 0`).
  6. Permite sucesso em descarga parcial com preservação dos lotes residuais. Nunca chama `SettlementInventory.deliver_from_carry_load()`.

## 8. Seleção de lotes

- **Padrão conservador (`requested_lots = []`):** seleciona somente lotes `FREE_GATHERED` elegíveis; sem lotes livres elegíveis retorna `"no_eligible_free_lots"` sem caminhar.
- **Seleção explícita (`[{"lot_id": ..., "amount": ...}]`):** valida `lot_id`, quantidade inteira positiva, `site_id`, geração, claim em trânsito, obra ativa e lastro da reserva de destino via planejador/coordenador.
- **Carga residual:** após descarga parcial válida, lotes restantes conservam exatamente `lot_id`, origem, quantidades e pesos no ledger, sem reiniciar descarga sobre lotes comprometidos ou inelegíveis.

## 9. Identidade dos intentos

`CampDeliveryTransferSession` congela: `operation_id` (prefixo `camp_delivery:<world>:<serial>:<region>:<zone_inst>:<zone_id>:<unit_inst>:<load_inst>:<order_id>` alocado na `RegionalAuthority` compartilhada sem exigir `ConstructionSite`), identidade completa de 10 campos (`world`, `region_id`, `inventory`, `storage`, `camp_zone`, `camp_zone.zone_id`, `unit`, `load`, `provenance_unit_id`, `order_id`), `requested_lots` normalizado, `state`, `is_executing`, `_busy_retries`, `_retry_remaining` e `_final_result`. Qualquer divergência de identidade durante retentativa falha com `"transaction_identity_changed"`.

## 10. Retentativas e replay

- **`busy`:** preserva exatamente `_operation_id` e `_requested_lots` originais; retenta em `RETRY_INTERVAL_SEC = 0.25` até `MAX_BUSY_RETRIES = 4` (compatível com C3.3), sem disparar a cada frame; ao esgotar retorna `"busy_retry_exhausted"`.
- **Revalidação pré-retentativa:** verifica identidade, prontidão de navegação e proximidade física antes de cada tentativa.
- **Replay:** outro coordenador comprometendo o intento congelado durante `busy` é reconhecido como `ok = true, replayed = true, delivered_now = 0` sem duplicar recursos nem incrementar `trips_completed`.
- **Resultado incerto (§6.3):** resposta sem campo `ok: bool` consulta `get_receipt` / `get_receipt_in_domain` para o mesmo `_operation_id`; se houver recibo válido, executa replay idempotente sem gerar novo ID; se não houver, encerra com `"unknown_transaction_outcome"` preservando a mochila.

## 11. Autorização física

Reutiliza `SelectiveCampDeliveryTxHelpers.check_physical_authorization_participants(...)`: unidade viva no mesmo `World3D`, `WorldNavigation` pronta e compatível com `CampStorageZone` e `UnitMovement`, slot em limites via `GatherSlotPlanner.compute_camp_dropoff_slot(...)`, distância horizontal `<= 0,35 m`, `|Δy| <= 0,85 m`, linha física livre sem parede (`BuildSlotPlanner.has_clear_physical_access`), recusa de `_custom_position_validator` e `pile_creator_override`. Monitora `camp_zone.get_config_revision()` e `nav.get_navigation_revision()` durante a caminhada; deslocamento da unidade fora da posição autorizada falha imediatamente com `"out_of_camp_dropoff_range"`.

## 12. Cancelamento de ordens

- Durante deslocamento ou espera `busy` antes do commit: para movimento, desconecta sinais de navegação, preserva carga/lotes/claims e chama `cancel_intent(...)`, fechando permanentemente a sessão (`"order_cancelled"` bloqueia qualquer tentativa futura).
- Substituição manual (ex.: `MoveOrder`): cancela com `REASON_REPLACED` e libera a unidade para cumprir a ordem manual sem perda de carga.
- Cancelamento após commit já realizado externamente no mesmo `operation_id`: `cancel_intent(...)` reconhece o recibo comprometido em `last_receipt` / `last_delivered` (`last_replayed = true`, `trips_completed = 0`) sem desfazer nem duplicar o resultado.

## 13. Integração com `ConstructOrder`

- Substitui o bloqueio fixo `REASON_SELECTIVE_CAMP_DELIVERY_REQUIRED` por inspeção concreta de proveniência (`CampDeliveryTransferSession.inspect_cargo_for_construction_site`), nunca usando quantidades agregadas para autorizar devolução.
- **Política conservadora padrão (`return_other_site_reserved = false`):** devolve automaticamente lotes `FREE_GATHERED` via subordem `DeliverToCampOrder` seletiva; preserva lotes `SITE_RESERVED` de outras obras ativas (falhando com `selective_camp_delivery_required` somente se a carga residual impedir progresso legítimo, preservando integralmente todos os testes da C3.3).
- **Seleção explícita de outra obra ativa (`return_other_site_reserved = true`):** permite restaurar fisicamente lotes `SITE_RESERVED` de outra obra ativa para a reserva da própria obra (jamais convertendo em estoque livre nem transferindo para a obra atual), mantendo lotes D3 bloqueados (`d3_cancellation_not_implemented`).
- Após descarga, reavalia papel D9, necessidade de suprimento e elegibilidade a `BUILDER`, sem promover trabalhador com carga residual incompatível e preservando limites de transportadores/construtores. `camp_return_trips_completed` contabiliza retornos reais ao acampamento separadamente de `trips_completed` (entregas ao canteiro).

## 14. Proteção contra loops

Múltiplas barreiras impedem o ciclo `iniciar retorno → descarga parcial → mochila não vazia → iniciar retorno`:
1. Classificação concreta por `lot_id` exclui da nova solicitação qualquer lote já não elegível (`Site B` sob política conservadora, obra não ativa / D3, geração divergente, claim inconsistente, erro fatal de acampamento).
2. Mochila não vazia **não** aciona retorno isoladamente: se `returnable_requests` estiver vazio e ainda houver capacidade para suprir a obra atual como `TRANSPORTER`/`SOLO_SUPPLIER`, a ordem prossegue normalmente no suprimento da obra atual.
3. Se não houver progresso legítimo possível (ex.: mochila cheia de carga não devolvível ou papel `BUILDER`/promoção exigindo mochila vazia), encerra imediatamente com diagnóstico explícito (`selective_camp_delivery_required`, `d3_cancellation_not_implemented`, `generation_mismatch`, `no_valid_camp_slot`, etc.), sem descartar material.
4. `_last_camp_return_load_revision` bloqueia reentrada no mesmo revision de mochila em cenários de replay com `delivered_now == 0`.

## 15. Conservação econômica

Validada a cada notificação e ao final de cada ciclo misto no Grupo F (Cenários 51–60):
- `camp_physical + sum(carried) + sum(site_buffer + site_consumed) == total_inicial` por recurso.
- Toda reserva tem lastro físico (`pile_reserved <= pile.amount`) e zero entradas órfãs no `PileReservationLedger`.
- Todo claim de trânsito corresponde exatamente à soma dos lotes `SITE_RESERVED` no ledger da mochila.
- Zero pilhas órfãs na coleção bruta `storage._piles`; pesos e quantidades residuais conferem com `CarryProvenanceLedger`.
- Obra B permanece intocada por operações da Obra A; todo `SUCCEEDED` corresponde a commit verificado por recibo.

## 16. Notificações e reentrância

`DEC-T3.6-SIGNALS-01` permanece **aberto** (a política provisória da C2-R1/C3.2/C3.4.2 que mantém guardas durante publicação pós-commit não foi alterada). Durante os 6 sinais econômicos (`load_changed`, `storage_changed`, `inventory_changed`, `storage.reservations_changed`, `inventory.reservations_changed`, `site.state_changed`):
- `DeliverToCampOrder.is_selective_transfer_executing()` (restrito a `status == RUNNING`) e `ConstructOrder._defer_transfer_replan()` adiam replanejamentos e bloqueiam `physics_update`, `cancel` e criação recursiva de subordem/transação no mesmo stack.
- A reavaliação da `ConstructOrder` após sucesso da subordem ocorre no próximo tick físico (`_replan_requested = true`), após liberação integral dos guardas.

## 17. Resultados dos testes (Godot `4.7.2.stable.official.ed1daf0bf`)

### Comandos obrigatórios (§12)

| Comando | Exit | Suítes | Testes | Asserções | Status |
| --- | --- | --- | --- | --- | --- |
| `.\tools\run_tests.ps1 -Filter test_t3_6_2_c3_4_3` | 0 | 1 | 8/8 | 1.187 | PASS (60 cenários A–F + extras, caminhada real) |
| `.\tools\run_tests.ps1 -Filter test_t3_6_2_c3_4_2` | 0 | 1 | 11/11 | 1.841 | PASS (+1 teste §2.1 `node_added`, +64 asserções) |
| `.\tools\run_tests.ps1 -Filter test_t3_6_2_c3_4_1` | 0 | 1 | 26/26 | 3.227 | PASS (inalterada) |
| `.\tools\run_tests.ps1 -Filter test_t3_6_2_c3_3` | 0 | 1 | 10/10 | 328 | PASS (inalterada) |
| `.\tools\run_tests.ps1 -Filter test_t3_6_2_c3_2` | 0 | 1 | 8/8 | 360 | PASS (inalterada) |
| `.\tools\run_tests.ps1 -Filter test_t3_6_2_c2` | 0 | 1 | 16/16 | 651 | PASS (inalterada) |
| `.\tools\run_tests.ps1 -Filter test_t3_6_2` | 0 | 11 | 107/107 | 8.239 | PASS (`6.988 + 64 + 1.187 = 8.239` exato) |
| `.\tools\validate.ps1` | 0 | — | — | — | PASS (**146 scripts**, 0 erros, 0 avisos) |
| `.\tools\run_tests.ps1 -Segmented` | 0 | 53 | 396/396 | 21.275 | PASS (12/12 lotes; `Discovered=53`, `ExecutedUnique=53`, `Duplicates=0`, `Missing=0`; 0 erros/avisos/vazamentos) |
| `git diff --check` | 0 | — | — | — | Limpo |

### Suítes legadas diretamente relacionadas (verificadas na execução segmentada)

- **Coleta, transporte e descarga:** `test_t2_worker_cycle` (`8/8`, 2.662), `test_t2_pace_and_load` (`13/13`, 452), `test_t2_playable_economy` (`8/8`, 351), `test_t2_camp_piles` (`9/9`, 144), `test_t2_camp_piles_nav` (`1/1`, 9), `test_t2_worker_transfer` (`5/5`, 53).
- **Construção e papéis D9:** `test_t3_3_construction_logistics` (`11/11`, 225), `test_t3_3_construction_site` (`7/7`, 164), `test_t3_3_ux_flow` (`3/3`, 57), `test_t3_4_3_reactive_construction_orders` (`7/7`, 426), `test_t3_4_4_building_completion` (`9/9`, 1.355), `test_t3_5_1_construction_hud` (`3/3`, 35), `test_t3_5_2_building_inspector` (`3/3`, 64).
- **Navegação, cancelamento de ordens e seleção contextual RTS:** `test_navigation` (`8/8`, 292), `test_t3_4_5_navigation_bake` (`9/9`, 2.305), `test_unit_movement` (`8/8`, 318), `test_commands` (`5/5`, 72), `test_picking_selection` (`9/9`, 70), `test_box_selection` (`7/7`, 58), `test_selection_manager` (`7/7`, 71).

## 18. Autorrevisão adversarial (§11)

1. **Bug real detectado na própria C3.4.2 antes da integração (§2.1):** `remove_child + free()` em `node_added` causava `SCRIPT ERROR` em `ground_pile_manager.gd:1519` e abandonava a pilha #2 destacada; corrigido com revalidação pós-`add_child` (mantendo a pilha sem filhos durante `add_child` para evitar crash em C++ `_propagate_enter_tree`) + `_coordinator_transaction_locked` em `CampStorageZone`.
2. **Bug real detectado na própria C3.4.3 durante o teste adversarial do Grupo E:** `DeliverToCampOrder.is_selective_transfer_executing()` inicialmente consultava `load._coordinator_transaction_locked` sem verificar `status == Status.RUNNING`, fazendo uma ordem já concluída retornar `true` quando uma ordem posterior travava a mesma mochila. Corrigido exigindo `status == Status.RUNNING`.
3. **Efeitos colaterais ocultos auditados:** `CampDeliveryTransferSession.inspect_cargo_for_construction_site` utiliza apenas leitores puros (`_read_transit_claim_for_unit_pure`, `provenance_snapshot`, `SelectiveCampDeliveryPlanner.prepare_selective_camp_delivery` com `probe_op` sem criar autoridade nem consumir serial).
4. **Riscos residuais honestos:** (a) remoção bruta de `GroundResourcePile` via `free()`/`remove_child()` por código externo continua sendo bypass fora de transação suportada (agora sem crash e detectada fail-closed na operação seguinte); (b) se uma unidade for removida arbitrariamente da árvore (`free()`) enquanto carrega lotes, o tratamento definitivo depende da política de destruição externa da T3.6-R2; (c) testes automatizados headless não provam ergonomia visual/interativa em janela real.

## 19. Limitações

- Modo opt-in não ativado globalmente nem exposto em botões permanentes de HUD (por restrição de escopo §15).
- Lotes `SITE_RESERVED` de obras não ativas permanecem bloqueados por D3 (`d3_cancellation_not_implemented`).
- `DEC-T3.6-SIGNALS-01` segue pendente.
- Recibos vivem em memória pelo ciclo de vida do `World3D` (sem persistência T3.8).
- Validação manual interativa em cena jogável ainda não executada pelo proprietário.

## 20. Testes manuais pendentes

Todos os 6 itens (`M1`–`M6`) do protocolo [docs/testing/T3_6_2_C3_4_3_manual_test_protocol.md](T3_6_2_C3_4_3_manual_test_protocol.md) encontram-se **PENDENTES DE VALIDAÇÃO PELO PROPRIETÁRIO**, executáveis com o harness isolado e removível [tests/visual/t3_6_2_c3_4_3_manual_harness.gd](../../tests/visual/t3_6_2_c3_4_3_manual_harness.gd). Nenhuma aprovação manual é presumida pela aprovação dos testes automatizados headless.

## 21. Arquivos alterados

- **Modificados (correção §2.1 C3.4.2 + suporte C3.4.3):**
  - `src/economy/camp_storage_zone.gd` (`+23`)
  - `src/economy/ground_pile_manager.gd` (`+21/-3`)
  - `src/economy/ground_resource_pile.gd` (`+4/-1`)
  - `src/economy/reserved_withdrawal_coordinator.gd` (`+73`)
  - `src/economy/selective_camp_delivery_coordinator.gd` (`+16`)
  - `src/economy/selective_camp_delivery_planner.gd` (`+1/-1`)
  - `src/economy/selective_camp_delivery_tx_helpers.gd` (`+22/-7`)
  - `src/units/orders/deliver_to_camp_order.gd` (`+403/-11`)
  - `src/units/orders/construct_order.gd` (`+167/-7`)
  - `tests/integration/test_t3_6_2_c3_4_2_selective_camp_delivery_commit.gd` (`+152`)
- **Criados:**
  - `src/units/orders/camp_delivery_transfer_session.gd` (`+543`, + `.uid`)
  - `tests/integration/test_t3_6_2_c3_4_3_order_integration.gd` (`+1266`, + `.uid`)
  - `tests/visual/t3_6_2_c3_4_3_manual_harness.gd` (`+270`, + `.uid`)
  - `docs/testing/T3_6_2_C3_4_3_manual_test_protocol.md`
  - `docs/testing/T3_6_2_C3_4_3_candidate_report.md`

## 22. SHAs publicados (`feat/t3-6-2-provenance-transactions`)

- **SHA-base:** `6d46cea1376b7a573871e09b3d5738edfcf1d67a`
- **Commit 1 (`fix` C3.4.2 §2.1):** `cabcb6cb71af55aefe93a13ea69f51871ad6275d` — `fix(t3.6.2-c3.4.2): guard post-commit node_added visual finalization and camp zone lock`
- **Commit 2 (`test` C3.4.2 §2.1):** `b1798085fe4999df8148dabf669a8de17e13f08b` — `test(t3.6.2-c3.4.2): verify post-commit node_added observer lifecycle boundaries`
- **Commit 3 (`feat` C3.4.3):** `e1763d71ec3037e2740fb185f32bb730001740d6` — `feat(t3.6.2-c3.4.3): integrate opt-in selective camp delivery into worker orders`
- **Commit 4 (`test` C3.4.3):** `bff76161cdd51a40c9fe1065cd5ca8aa84ff1581` — `test(t3.6.2-c3.4.3): add adversarial order integration suite and removable manual harness`
- **Commit 5 (`docs` C3.4.3):** commit seguinte contendo este relatório e o protocolo manual.
