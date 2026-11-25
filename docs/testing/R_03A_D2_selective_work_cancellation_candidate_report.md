# R-03A D2 — Cancelamento Seletivo de Trabalhos Comunitários por Fonte e Categoria (`D2-A` / `D2-B`)

- **Data:** 25/11/2026
- **Incremento:** **`R-03A D2`**
- **Status real:** **`IMPLEMENTADO`** · **`VALIDADO TECNICAMENTE`** · **`AUDITORIA INDEPENDENTE PENDENTE`** · **`RETESTE HUMANO PENDENTE (`HD2-01`–`HD2-10`)`** · **`D2 NÃO HOMOLOGADA`** · **`R-03A NÃO HOMOLOGADA`** · **`NÃO INTEGRADO À DEVELOP`** · **`D3`–`D4` / `R-03B` BLOQUEADOS**
- **Base homologada imediata:** `9964a063893971cd0473afc567627d0da0c4493e` (**`R-03A D1` definitivamente homologada pelo proprietário** após 5/5 cenários do reteste humano `RH-R3-01`–`RH-R3-05` aprovados sem ressalvas; `H-F01` e `H-F02` encerrados no escopo retestado)
- **Ancestralidade linear:** `21c34ee` (`develop`) → `f77e99e` (`R1.1`) → `a39f3b5` (`D0`) → `a56af98` (`D1`) → `9f5b307` (`D1 R1`) → `5824c3e` (`D1 R2`) → `9964a06` (`D1 R3 Corretiva` — **`D1 HOMOLOGADA`**) → **`R-03A D2`**
- **Branch candidata:** `feat/r-03a-community-work-main-scene`
- **Worktree utilizado:** `C:\Projetos\Dawn_of_Kin_wt_r_03a`
- **Flags preservadas em `src/main/main.tscn`:** `use_provenance_economy = true`, `automatic_cancellation_recovery = true`, `use_d2_2_hud = false`.
- **Arquivo externo de evidências:** `C:\Projetos\Backups\Dawn_of_Kin_Archive_Local\evidencias\R-03A\D2\`

---

## 1. Autorização expressa e decisões aprovadas (`D2-A` / `D2-B`)

Após a homologação definitiva da `R-03A D1` (`9964a06`), o proprietário autorizou exclusivamente **`R-03A D2 — Cancelamento seletivo de trabalhos comunitários`** sob duas decisões canônicas:

1. **`D2-A` (Interface):** selo mineral **`×`** posicionado **acima de cada categoria** da `CommunitySelectionActionsHud` (Alternativa D da prancha forense D2), sem botão global de "cancelar tudo", preservando intactas as lajes D1 R2 (`97×54` externo / `85×42` pedra sólida), com deslocamento horizontal/vertical `0 px` e atlas D2.2 intocado.
2. **`D2-B` (Carga transportada):** preservar integralmente a carga já extraída pelo trabalhador e concluir **uma única entrega legítima ao acampamento** (`DeliverToCampOrder` seletivo com proveniência), com **zero retorno** à fonte cancelada, sem mutação direta fora das autoridades econômicas.
3. **Granularidade estrita:** `(fontes selecionadas ∩ categoria acionada ∩ domínio regional válido ∩ tarefas ativas)`, cobrindo `PENDING_WORKERS`, `IN_PROGRESS` e `BLOCKED_REAUTHORIZATION`, sem jamais expandir por `group_id` ou globalmente.

Expressamente **fora de escopo / bloqueados:** `D3` (corte progressivo de árvores/`CHOPPING`/`D0-A03`/`D0-A04`), `D4`, `R-03B`, `R-03D`/`D-11`, botão global de cancelar tudo, `C-01`/`C-02` ampliada/`C-04`–`C-06` e alterações em `project.godot`, atlas D2.2, `ico_work_*.png`, `tree_source.tscn`, `rts_input_controller.gd`, câmera, picking, edge scrolling, GDD v1.3 ou Design System.

---

## 2. Alterações de produção aplicadas (7 arquivos em `src/`)

1. **`src/rts/work_task.gd`:** adicionada constante `REASON_PLAYER_CANCELLED = "player_cancelled_community_work"`.
2. **`src/rts/community_work_board.gd`:** adicionado `get_cancellable_tasks_for_sources(sources, resource_id)` — filtra estritamente `(sources ∩ resource_id ∩ is_source_in_region_domain ∩ task.is_active() ∩ task.region_id == _region_id)`, deduplicando por `instance_id` sem jamais expandir por `group_id`.
3. **`src/units/orders/gather_resource_order.gd`:**
   - Adicionada constante `REASON_COMMUNITY_WORK_CANCELLED = "community_work_cancelled"`, flags `_stop_after_delivery` e `_community_cancel_requested`, getters públicos e `request_community_cancel(movement)`.
   - **Mid-transfer (`is_provenance_transfer_executing() == true`):** difere com `deferred_during_transfer` sem abortar commit; intercepta imediatamente no retorno de `_execute_active_gather_session()`, antes de qualquer 2º ciclo ou espera de retry (`RETRY_SCHEDULED`), aplicando `_apply_deferred_community_cancel()`.
   - **Já em `DELIVERING_TO_CAMP`:** mantém a entrega atual (`finish_current_delivery`) e encerra com `SUCCEEDED` em `_handle_deliver_finished()` (`if _stop_after_delivery or not _is_source_usable(): _finish_succeeded()`), sem readquirir vaga nem retornar à fonte.
   - **Em `APPROACHING_SOURCE`/`GATHERING` com carga `FREE_GATHERED` elegível:** cancela intenção pendente (`cancel_intent`), libera vaga da fonte, interrompe movimento e transita diretamente para `_start_delivering()` com `_stop_after_delivery = true` (`transitioned_to_final_delivery`).
   - **Sem carga livre elegível (mochila vazia ou somente lotes `SITE_RESERVED`/`CANCEL_*`):** retorna `cancel_immediately` para cancelamento imediato via `Unit.cancel_current_order()`, parando o movimento em `_finish_cancelled()`.
4. **`src/units/orders/deliver_to_camp_order.gd` (`+4` linhas — correção defensiva descoberta por `O14`):** adicionada guarda de validade de `camp_zone` (`camp_zone == null or not is_instance_valid(camp_zone) or not camp_zone.is_inside_tree() or camp_zone.is_queued_for_deletion()`) no início de `_start_selective_walk()`, impedindo `SCRIPT ERROR` ao tentar replanejar entrega após remoção do `CampStorageZone` durante a entrega final (`O14`).
5. **`src/rts/community_task_dispatcher.gd`:**
   - Adicionado `cancel_tasks_for_sources(sources, resource_id, reason)` com snapshot imutável pré-mutação, contador de reentrância `_cancelling_batch_depth` (suprimindo `_flush_dispatch` durante o lote e coalescendo um único `request_dispatch()` ao término), fechamento **board-first** (`WorkTask.State.CANCELLED`), reconciliação cooperativa validando exatamente `unit.get_current_order() == snap_order and unit.get_order_revision() == snap_rev` (preservando 100% das ordens pessoais) e rejeição explícita de domínio inválido (`region_mismatch`).
   - Blindagem de reentrância em `_try_dispatch_unit_to_task()` (`E11` / correção do `RED-05`): verifica `if not task.is_active()` após `command_units_to_gather()`, impedindo ressurreição da tarefa para `IN_PROGRESS` e desfazendo cooperativamente a ordem órfã recém-criada.
6. **`src/rts/autonomous_gather_input.gd`:** conexão/desconexão de `CommunitySelectionActionsHud.category_cancel_requested`, método público `cancel_selected_category(resource_id)` (preservando a seleção atual e permitindo cancelamento administrativo de tarefas já registradas no domínio válido mesmo com admissão econômica bloqueada, §11.4 / `E08`) e feedback discreto em português.
7. **`src/ui/community_selection_actions_hud.gd`:**
   - Novo sinal `category_cancel_requested(resource_id)` e subclasse interna `_PolygonalCancelSealButton` (octógono chanfrado em basalto vulcânico D2.2, `34×22` para `×` ou `44×22` para parcial `×N`, vão transparente pass-through de `6 px` acima da pedra sólida da laje, `SEAL_HEADROOM_Y = 26.0`, deslocamento `0 px` nas lajes, hit-testing poligonal `Geometry2D.is_point_in_polygon`, `ACTION_MODE_BUTTON_RELEASE`, bloqueio anti-click-through de RMB/MMB/scroll na pedra sólida, tooltips contextuais em português, otimização contra re-tematização redundante).
   - Mantém `has_stop_button() == false` (compatibilidade D1 + ausência de botão global cancelar-tudo) e adiciona `get_category_cancel_button`, `is_category_cancel_visible`, `get_category_cancel_count` e `get_category_cancel_text`.

---

## 3. Evidências `RED → GREEN` e cobertura rastreável (`S01`–`S14`, `O01`–`O14`, `E01`–`E16`, `U01`–`U20`)

### 3.1 Provas `RED` genuínas sobre a base intocada `9964a06` (`02_red\red_d2_results.txt`)
Executadas sobre `9964a06` antes de qualquer alteração em `src/` (`Exit=0, HasErr=False, HasWarn=False`):
- **`RED-01`:** fechar tarefa no board deixava `GatherResourceOrder` ativa (`extracted_after_board_close=4`, `30→26`).
- **`RED-02`:** após `DELIVERING_TO_CAMP`, a ordem readquiria vaga (`has_reservation=true`) e retornava à fonte (`phase=0`).
- **`RED-03`:** `cancel()` durante `is_provenance_transfer_executing() == true` era no-op silencioso (`still_active_10f_later=true`).
- **`RED-04`:** inexistiam `cancel_selected_category` / `cancel_tasks_for_sources`, e override no trabalhador reatribuía tarefa a outro trabalhador (`reassigned_to_other=true`).
- **`RED-05`:** fechamento reentrante durante `_try_dispatch_unit_to_task()` ressuscitava a tarefa para `IN_PROGRESS` (`resurrected=true`, `orphan_order_active=true`).
- **`RED-06`:** `CommunitySelectionActionsHud` não possuía sinal nem API de selo de cancelamento por categoria.

### 3.2 Nova suíte `tests/integration/test_r_03a_d2_selective_work_cancellation.gd` (`8/8 PASS`, `330` asserções)
| Teste | Requisitos Cobertos | Asserções | Status |
|---|---|---:|---|
| `test_d2_s01_s06_category_subset_mixed_and_group_isolation` | `S01`–`S06` | `39` | **`PASS`** |
| `test_d2_s07_s14_states_markers_selection_reauth_and_idempotency` | `S07`–`S14` | `32` | **`PASS`** |
| `test_d2_o01_o06_worker_phases_and_single_final_delivery` | `O01`–`O06` | `47` | **`PASS`** |
| `test_d2_o07_o14_personal_orders_reassignment_removals_and_delivery_failures` | `O07`–`O14` | `30` | **`PASS`** |
| `test_d2_e01_e05_provenance_mid_transfer_busy_retry_replay_and_delivery_tx` | `E01`–`E05` | `34` | **`PASS`** |
| `test_d2_e06_e10_conservation_blocked_economy_reserved_lots_and_construct_coexistence` | `E06`–`E10` | `28` | **`PASS`** |
| `test_d2_e11_e16_reentrancy_rapid_reauth_group_fifo_and_domain_guards` | `E11`–`E16` | `26` | **`PASS`** |
| `test_d2_u01_u20_hud_cancel_seal_geometry_real_input_and_layouts` (`720p` + `1080p`) | `U01`–`U20` | `94` | **`PASS`** |

---

## 4. Validação integral, focais, janela nativa (`[SYNTHETIC]`), visual, desempenho e smokes

- **Suítes focais (`16/16 PASS`, `FOCAL_FAIL=0`):** `test_source_selection_model` (`4/4`, `52`), `test_picking_selection` (`9/9`, `70`), `test_box_selection` (`7/7`, `58`), `test_commands` (`5/5`, `72`), `test_rux_1_autonomous_gather` (`7/7`, `87`), `test_rux_2a_auto_resources` (`10/10`, `166`), `test_rux_2b_multi_source_selection` (`14/14`, `116`), `test_r_03a_community_work_main_scene` (`28/28`, `962`), `test_r_03a_d1_selection_and_authorization` (`25/25`, `592`), `test_r_03a_d2_selective_work_cancellation` (`8/8`, `330`), `test_t2_worker_cycle` (`8/8`, `2.659`), `test_t3_6_2_c3_4_3_order_integration` (`9/9`, `1.207`), `test_t3_6_2_c3_5_gather_order_integration` (`6/6`, `955`), `test_t3_6_2_c4_10_work_regional_authority` (`3/3`, `179`), `test_t3_6_2_c4_12_rts_provenance` (`5/5`, `119`) e `test_t3_6_3_b1_4_recovery_dispatch` (`16/16`, `178`).
- **Campanha em janela nativa (`[SYNTHETIC]`, não substitui reteste humano):** `1280×720` (`10/10 PASS`, `FAILED=0`) e `1920×1080` (`10/10 PASS`, `FAILED=0`) — cenários `N01`–`N10` aprovados sem erros/avisos.
- **Evidências visuais (`09_evidencias_visuais/`):** capturas `V01`–`V10` (tela cheia + crop HUD) em `1280×720` e `1920×1080`, mais prancha comparativa `prancha_comparativa_D1_homologada_vs_D2_candidata_1920x1080.png`, inspecionadas visualmente (selos `×` e `×2` legíveis, alinhamento mineral D2.2, zero sobreposição, zero deslocamento das lajes).
- **Benchmark focal (`1920×1080`, Intel UHD Graphics 620, `gl_compatibility`, VSync OFF — `D4` permanece `ABERTO`):**
  - `P1_idle_baseline`: `avg=7,394 ms | p50=7,477 ms | p95=9,175 ms`
  - `P2_selected_no_seals`: `avg=7,245 ms | p50=7,297 ms | p95=9,044 ms`
  - `P3_3cats_authorized_with_seals`: `avg=7,317 ms | p50=7,402 ms | p95=9,341 ms` (`<= 16,7 ms`)
  - `P6_hover_seal_steady`: `avg=9,013 ms | p50=8,999 ms | p95=13,310 ms` (`<= 16,7 ms`)
  - `P7_post_cancel_clean`: `avg=6,842 ms | p50=6,726 ms | p95=8,669 ms` (`<= 16,7 ms`)
  - `ZERO_POLLING_VERIFY`: `hud_process=false | hud_physics=false | dispatcher_process=false | dispatcher_physics=false`
  - *Nota transparente de pico sintético:* `P4_batch_cancel_3cats_cpu` (estresse artificial cancelando todas as 14 fontes simultaneamente nas 3 categorias no mesmo quadro) registrou `avg=30,008 ms` (`~2,1 ms/tarefa`, devido ao `HUD.refresh()` síncrono emitido a cada `task_closed`), refletido em `P5_repeated_auth_cancel_frames` (`p50=6,506 ms`, `p95=24,099 ms` em alternância a cada 10 quadros). O fechamento formal de desempenho pertence à etapa **`D4` (`ABERTO`)**.
- **Validação estática (`.\tools\validate.ps1`):** `PASSED` (`0` erros, `0` avisos, **`214` scripts verificados**, `DOCS_DESIGN_IMPORT_COUNT=0`, boot headless limpo).
- **Regressão segmentada integral (`.\tools\run_tests.ps1 -Segmented -MaxIntegrationPerGroup 1`):**
  - **`89/89` suítes** (`Discovered=89 | ExecutedUnique=89 | Duplicates=0 | Missing=0`), **`657/657` testes**, **`30.936` asserções**, **`63/63` lotes**, `0` falhas, `0` erros de suíte (`SEGMENTED_EXIT=0`).
  - **Delta exato vs base homologada `D1` (`9964a06`: `88` suítes / `649` testes / `30.589` asserções / `213` scripts / `62` lotes):** `+1` suíte (`test_r_03a_d2_selective_work_cancellation.gd`), `+8` testes, `+1` script, `+1` lote de integração, `+347` asserções líquidas (`+330` deliberadas da D2 + `+17` variação física natural em suítes de movimentação).
- **Smokes e arquivos protegidos:** `run_game.ps1 -QuitAfter 60 -FailOnWarnings` aprovado em `1280×720` (`EXIT=0`) e `1920×1080` (`EXIT=0`); `PROTECTED_FILES_CHECKED=8 | PROTECTED_HASH_DIFF_COUNT=0`.

---

## 5. Próximos passos bloqueados até auditoria e homologação

1. Auditoria técnica independente do ChatGPT sobre o commit publicado em `origin/feat/r-03a-community-work-main-scene`.
2. Execução pelo proprietário do roteiro humano **`HD2-01`–`HD2-10`** (`15_reteste_humano\ROTEIRO_RETESTE_HUMANO_R03A_D2.md`) em `1280×720` e `1920×1080`.
3. `D3`, `D4`, integração na `develop` e etapas `R-03B`–`T3.9` permanecem estritamente **`BLOQUEADO`** até decisão expressa do proprietário.
