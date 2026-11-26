# Dawn of Kin — Relatório Técnico da Candidata `R-03A D4-R1`
## Correção Visual de Banners Superiores (`D4-A01`) e Otimização Focal de Desempenho (`D4-P01`, `D4-P02`)

**Data:** 26/11/2026  
**Etapa:** `R-03A D4-R1` *(correção visual e otimização focal de desempenho sobre a candidata `D4` antes da execução humana final e eventual integração à `develop`)*  
**Repositório:** `https://github.com/Julian0s/Dawn-of-Kin`  
**Branch candidata:** `feat/r-03a-community-work-main-scene`  
**Worktree candidato:** `C:\Projetos\Dawn_of_Kin_wt_r_03a`  
**SHA base autorizado (`D4`):** `94744eca16e9eea60b03033f82a318f8e7825dc2` *(com base técnica anterior `e7d72e41a31861d41747d7d82239b7963626f497`)*  
**Base canônica preservada (`develop`):** `21c34ee645725a74f1fefac9db0309ec711ab5f2`  
**Linha estável preservada (`main`):** `25e0a20f1d6a2f10a9e059afe69759fbe263db4a`  
**Checkout principal preservado:** `C:\Projetos\Dawn of Kin` (`develop` @ `21c34ee`, `M project.godot` SHA-256 `AEEFDA2810DA5C4EDFA9BF5F2A47A5841F8597238C8DAB4C2E202FAF70307613`)  
**Godot:** `4.7.2.stable.official.ed1daf0bf` (`gl_compatibility`, `Jolt Physics`, `Intel(R) UHD Graphics 620`)

---

## 1. Classificação Técnica por Dimensão

| Dimensão | Classificação |
|---|---|
| **`D4-A01` (Banners superiores `720p` / `1080p`)** | **APROVADA TECNICAMENTE** *(RED reproduzido em `1280×720` e `1920×1080`; correção 100% orientada a eventos sem polling; GREEN confirmado em screenshots nativos com `gap = 8,00 px`, `overlap = false`, `dbg_overlap = false` e `12/12` testes `A01-01`–`A01-12` aprovados com `137` asserções)* |
| **`D4-P01` (`P04_Community_Authorization`, `CA`)** | **APROVADA TECNICAMENTE (`p95 <= 16,7 ms`)** *(CA baseline reproduzido em `720p p95 = 31,910 ms` e `1080p p95 = 31,293 ms`; após correções focais: **`720p p95 = 13,075 ms (-59,0%)`** e **`1080p p95 = 14,452 ms (-53,8%)`**, com CPU síncrona caindo `77%–79%` e `>33,3 ms` caindo `22→0` em `720p` e `21→1` em `1080p`)* |
| **`D4-P02` (`D2-P01: 6_TREES_KEEPING_STONE_FOOD_ACTIVE`, `CA`)** | **OTIMIZAÇÃO COMPROVADA COM TRANSIENTE RESIDUAL EXPLICADO** *(CA baseline reproduzido em `720p avg = 28,434 ms / p95 = 30,030 ms` e `1080p avg = 33,576 ms / p95 = 35,431 ms`; após correções focais: **`720p avg = 17,191 ms (-39,5%) / p95 = 18,285 ms (-39,1%) / max = 19,625 ms (-60,8%)`** e **`1080p avg = 17,523 ms (-47,8%) / p95 = 18,431 ms (-48,0%) / max = 18,598 ms`**, atingindo o piso físico da GPU integrada em `1080p`: `~6,6–7,1 ms` frame base + `~4,4 ms` despacho/nav + marcador/ordem + `0,74 ms` HUD batch)* |
| **Validação automatizada** | **APROVADA** *(`validate.ps1`: `220/220` scripts `0/0`, smoke `exit=0`; suíte segmentada integral: **`94/94` suítes (`718/718` testes, `33.992` asserções, `67/67` lotes, `Discovered=94`, `ExecutedUnique=94`, `Duplicates=0`, `Missing=0`, `AGGREGATE_EXIT_CODE=0`)**)* |
| **Integridade arquitetural** | **APROVADA** *(`STRUCTURAL_AUDIT_OK=true`, `STRUCT_PERF_EXIT=0`, `0` polling em `AutonomousGatherFeedback`, `CommunitySelectionActionsHud`, `CommunityTaskDispatcher`, `AutonomousGatherInput` e `CommunityWorkBoard`; precedência `manually_overridden > busy` preservada)* |
| **Auditoria visual (`720p` / `1080p`)** | **APROVADA TECNICAMENTE** *(RED/GREEN em `02_a01_visual_red/`, `03_a01_visual_green/` e `13_visual_final/` inspecionados via `read_file`, zero sobreposição com `PlacementStatusBanner`, `DebugOverlay` `[F3]` ou `ResourceHud`)* |
| **Integridade Git** | **APROVADA** *(`feat/r-03a-community-work-main-scene` derivada estritamente de `94744eca`, `develop` em `21c34ee` e `main` em `25e0a20` intactas, checkout principal intocado)* |
| **Aceite humano (`M1`–`M8`)** | **PENDENTE** *(protocolo atualizado publicado; nenhum cenário `M1`–`M8` executado ou aprovado nesta etapa)* |

**Parecer consolidado:** **`CANDIDATA D4-R1 VALIDADA TECNICAMENTE — AGUARDANDO AUDITORIA INDEPENDENTE E TESTES HUMANOS M1–M8`** *(não homologada e não integrada à `develop`).*

---

## 2. `D4-A01` — Correção Visual dos Avisos Superiores

### 2.1 Causa Raiz e Reprodução `RED`
- **Causa raiz:** `AutonomousGatherFeedback._recenter_top()` posicionava o banner de feedback em `offset_top = 14.0` (topo-central, largura dinâmica), enquanto `PlacementTestOverlay._status_panel` (`PlacementStatusBanner`) ocupava `offset_top = 16.0..72.0` (`560 px` centralizados) sem acoplamento mútuo.
- **Evidência `RED` (`02_a01_visual_red/`):** ambos os cenários reproduzidos em janela `SubViewport` da `MainScene` real (`1280×720` e `1920×1080`):
  - `gather_then_placement` (`720p`/`1080p`): interseção `199×38 px` (`y = 16..54`).
  - `placement_active_then_gather` (`720p`/`1080p`): interseção `249×38 px` (`y = 16..54`).

### 2.2 Correção Implementada (Orientada a Eventos, Zero Polling)
- [placement_test_overlay.gd](../../src/buildings/placement_test_overlay.gd): expõe `get_status_banner_control()` e `get_status_banner_global_rect()`.
- [autonomous_gather_feedback.gd](../../src/ui/autonomous_gather_feedback.gd): adiciona `bind_top_avoidance_target(target)` e `unbind_top_avoidance_target(target)`, conectando exclusivamente aos sinais `visibility_changed`, `resized`, `item_rect_changed`, `tree_exited` do alvo e `size_changed` do `Viewport` (mantendo `_process(false)` e `_physics_process(false)` + `Timer` one-shot `AUTO_HIDE_SEC = 3.0`). Quando o alvo está visível e sobrepõe a faixa horizontal central no topo, desloca `offset_top` para `target_rect.end.y + 8.0`; quando ocultado, suprimido ou liberado, restaura `BASE_TOP_OFFSET = 14.0`.
- [main.gd](../../src/main/main.gd): conecta `_autonomous_gather_feedback.bind_top_avoidance_target(_placement_test_overlay.get_status_banner_control())` em `_setup_placement()`.

### 2.3 Evidência `GREEN` e Cobertura Automatizada (`A01-01`–`A01-12`)
- **Capturas finais inspecionadas (`03_a01_visual_green/`, `13_visual_final/`):**
  - `gather_then_placement` (`720p`/`1080p`): `pb_rect.y = 16..73`, `fb_rect.y = 81..121`, **`gap = 8,00 px`**, `overlap = false`, `dbg_overlap = false`.
  - `placement_active_then_gather` (`720p`/`1080p`): `pb_rect.y = 16..73`, `fb_rect.y = 81..121`, **`gap = 8,00 px`**, `overlap = false`, `dbg_overlap = false`.
  - `placement_closed_restore` (`720p`/`1080p`): após cancelamento/fechamento, `fb_rect.y` retorna exatamente para **`14,0`**.
- **Suíte dedicada ([test_r_03a_d4_r1_visual_top_banners.gd](../../tests/integration/test_r_03a_d4_r1_visual_top_banners.gd)):** **`12/12` testes (`A01-01`–`A01-12`), `137/137` asserções, `0` falhas**.

---

## 3. `D4-P01` e `D4-P02` — Diagnóstico e Otimizações Focais (`CA`)

### 3.1 Causas Raiz Comprovadas (`05_p01_diagnostics/` e `08_p02_diagnostics/`)
1. **`AutonomousGatherInput.authorize_selected_category()` sem loteamento de HUD:** diferente de `cancel_selected_category()`, disparava `N` chamadas síncronas a `CommunitySelectionActionsHud.refresh()` para `N` fontes (`6` refreshes síncronos para 6 árvores = `~16 ms` só de HUD).
2. **`CommunitySelectionActionsHud.refresh()` recomputando seleção `7×` por chamada (`2,53 ms/chamada`):** chamava `SourceSelectionModel.get_counts_by_resource()` e `get_selected_by_resource()` + `board.get_cancellable_tasks_for_sources()` repetidamente, revalidando `14` fontes por categoria.
3. **`GatherSlotPlanner.compute_source_approach_slot()` sem saída antecipada (`3,8–4,8 ms/chamada`):** varria todos os `48` pares (`3` anéis × `16` ângulos) com `snap_to_navmesh` + `find_path` mesmo após encontrar slot separado diretamente alinhado em `step = 0` do anel preferencial.
4. **`CommunityTaskDispatcher._dispatch_group_tasks()` sem ordenação prévia e sem batch de despacho:** varria tarefas pendentes em ordem de registro (em vez de pares `(dist_sq, task, unit)` crescentes), repetia checagens unitárias idênticas por tarefa e gerava `2` refreshes extras de HUD no frame de flush (`hud_flush = 2`).

### 3.2 Correções Implementadas (Preservando Integralmente Contratos D1/D2/D3)
- [autonomous_gather_input.gd](../../src/rts/autonomous_gather_input.gd): envolve `authorize_selected_category()` com `begin_batch_refresh() / end_batch_refresh()` (`6 → 1` refresh síncrono) e conecta `dispatch_batch_started` / `dispatch_batch_finished` ao batch da HUD (`2 → 1` refresh no frame de flush).
- [community_selection_actions_hud.gd](../../src/ui/community_selection_actions_hud.gd): `refresh()` obtém `get_selected_sources()` **uma única vez**, particiona por categoria e calcula estado visual + contagem cancelável em passagem única via `_compute_category_state_and_cancel_count()`, reduzindo `HUD.refresh()` de **`2.533,4 µs → 740,4 µs`** (`-70,8%`).
- [gather_slot_planner.gd](../../src/units/orders/gather_slot_planner.gd): ao localizar o primeiro slot válido e separado (`_is_separated_from_all`), avalia apenas os `2` vizinhos angulares simétricos imediatos no mesmo anel e encerra a varredura, mantendo busca completa automática para obstáculos/lotação (`compute_source_approach_slot`: **`4.763 µs → 393–579 µs`** em `1080p`/`720p`, ~`8–12×` mais rápido).
- [community_task_dispatcher.gd](../../src/rts/community_task_dispatcher.gd): pré-valida elegibilidade base por unidade uma vez por rodada (preservando estritamente `manually_overridden` antes de `busy`/`not_idle` em `_check_pre_nav_eligibility` para não mascarar `BLOCKED_REAUTHORIZATION`), ordena pares elegíveis por `(dist_sq, task_idx, unit_name, unit_id)` mantendo desempate determinístico idêntico ao original, e emite sinais de batch no `_flush_dispatch()`.

### 3.3 Comparativo Oficial Antes × Depois (`CA`, `VSync OFF`, `Intel UHD 620`)

#### A. Matriz `D4` (`P04_Community_Authorization` — foco `D4-P01`)
| Cenário | `1280×720` Baseline `CA` | `1280×720` Final `D4-R1` (`CA`) | Delta `720p` | `1920×1080` Baseline `CA` | `1920×1080` Final `D4-R1` (`CA`) | Delta `1080p` |
|---|---|---|---|---|---|---|
| **`P04_Community_Authorization` p95** | `31,910 ms` | **`13,075 ms`** *(PASS `< 16,7`)* | **`-59,0%`** | `31,293 ms` | **`14,452 ms`** *(PASS `< 16,7`)* | **`-53,8%`** |
| **`P04` p99 / Max / `>33,3 ms`** | `56,368` / `98,933` / `22` | `15,505` / `29,313` / **`0`** | `>33,3: -100%` | `50,008` / `72,272` / `21` | `17,255` / `41,397` / **`1`** | `>33,3: -95%` |
| **`P04` CPU síncrona média (`sync_us`)** | `14,141 ms` | **`2,974 ms`** | **`-79,0%`** | `15,459 ms` | **`3,528 ms`** | **`-77,2%`** |
| **`P03` Seleção heterogênea p95** | `8,409 ms` | `5,431 ms` | `-35,4%` | `8,507 ms` | `8,014 ms` | `-5,8%` |

*(Os demais cenários `P01`, `P02`, `P05`–`P12` mantiveram `p95 <= 8,81 ms` em `720p` e `<= 12,46 ms` em `1080p`, com exceção de `P09` `1080p` em amostra única `n=8` com 2 quadros `21,89 ms` em physics/cleanup de corte)*

#### B. Matriz Diagnóstica Isolada `P01-A`–`P01-L` e `D2-P01` (`D4-P02`, `10` repetições `CA`)
| Cenário | `1280×720` Baseline `CA` | `1280×720` Final `D4-R1` (`CA`) | Delta `720p` | `1920×1080` Baseline `CA` | `1920×1080` Final `D4-R1` (`CA`) | Delta `1080p` |
|---|---|---|---|---|---|---|
| **`D2-P01` `6_TREES_KEEPING_STONE_FOOD_ACTIVE` (cancel_frame_avg)** | `28,434 ms` | **`17,191 ms`** | **`-39,5%`** | `33,576 ms` | **`17,523 ms`** | **`-47,8%`** |
| **`D2-P01` idem `cancel p95` / `max`** | `30,030 / 50,057 ms` | **`18,285 / 19,625 ms`** | **`-39,1% / -60,8%`** | `35,431 / 35,463 ms` | **`18,431 / 18,598 ms`** | **`-48,0% / -47,6%`** |
| **`P01-E` `Auth_6_Trees_Hetero_14Sel` (`sync` / `frame1 avg`)** | `15,654 / 29,434 ms` | **`3,493 / 13,501 ms`** | **`-77,7% / -54,1%`** | `18,033 / 34,132 ms` | **`3,321 / 13,453 ms`** | **`-81,6% / -60,6%`** |
| **`P02-H` `_flush_dispatch` direto (`8` tarefas, `2` livres)** | `23,079 ms` | **`7,831 ms`** | **`-66,1%`** | `28,279 ms` | **`8,762 ms`** | **`-69,0%`** |

> [!NOTE]
> **Explicação objetiva do piso residual em `D2-P01 6_TREES_KEEPING_STONE_FOOD_ACTIVE`:** na GPU integrada Intel UHD 620 em `1920×1080`, um único frame ocioso de renderização consome `~6,6–7,1 ms` (`P01 Idle`). O cancelamento simultâneo de `6` árvores seguido no **mesmo** frame pela redistribuição real de `2` trabalhadores com alocação de slots de navegação, criação de `2` `GatherResourceOrder` e `1` refresh consolidado de HUD totaliza `~17,5 ms` (`~6,6 ms` render base + `~4,4 ms` despacho/ordens/nav + limpeza de marcadores + `0,74 ms` HUD). Eliminar mais exigiria adiar a redistribuição para um frame posterior ou reduzir qualidade geométrica de navegação, o que não se justifica como defeito neste incremento.

---

## 4. Validação Estática, Regressão Integral e Auditoria Estrutural

- **Validação estática (`.\tools\validate.ps1`):** `Validation PASSED (0 errors, 0 warnings, 220 scripts checked)`, smoke headless `exit=0`.
- **Regressão segmentada integral (`.\tools\run_tests.ps1 -Segmented -MaxIntegrationPerGroup 1 -GroupTimeoutSeconds 240`):**
  - **`94/94` suítes (`718/718` testes, `33.992` asserções, `67/67` lotes: `unit` + `integration-01..66`)**
  - **`Discovered = 94`, `ExecutedUnique = 94`, `Duplicates = 0`, `Missing = 0`, `Failed = 0`, `SuiteErrors = 0`, `AGGREGATE_EXIT_CODE = 0`**
  - Regressão focal `test_r_03a_d1_selection_and_authorization`: **`25/25` (`592` asserções)** após ajuste de precedência `manually_overridden > busy`.
- **Auditoria estrutural (`14_structural_audit/`):** `STRUCTURAL_AUDIT_OK = true`, `STRUCT_PERF_EXIT = 0`, `board_proc = false`, `disp_proc = false`, `hud_proc = false`, `0` tarefas duplicadas, `0` marcadores órfãos no `teardown`.

---

## 5. Pendências para Encerramento da `R-03A`

1. Auditoria independente do ChatGPT sobre esta candidata `D4-R1` no SHA final em `feat/r-03a-community-work-main-scene`.
2. Execução presencial do protocolo humano **`M1`–`M8`** pelo proprietário ([R_03A_D4_final_manual_test_protocol.md](R_03A_D4_final_manual_test_protocol.md)), verificando especialmente a nova separação de banners em **`M7`**.
3. Homologação expressa do proprietário e autorização explícita antes de qualquer integração por fast-forward à `develop` ou início da `R-03B`.
