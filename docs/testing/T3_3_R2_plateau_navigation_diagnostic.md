# Diagnóstico Visual e Correção T3.3-R2 — Navegação no Platô, Lateral da Rampa e Continuidade de Abastecimento

- **Branch:** `feature/t3-3-construction-logistics`
- **Base (`origin/main`):** `931ad196346251e3f24a3ea5db6facb3641233bc`
- **Worktree:** `C:\Projetos\Dawn_of_Kin_wt_t3_3_construction`
- **Engine / Renderer:** Godot `4.7.2.stable` (`gl_compatibility` / `--rendering-driver opengl3`)
- **Hardware Medido:** `Intel(R) UHD Graphics 620`
- **Status Atual (adendo histórico R2):** Na ocasião da rodada R2, os **10/10 testes manuais** (incluindo o reteste de **B2** e os itens **C1–D2**) vieram a ser aprovados pelo proprietário em 16/11/2026 ([T3_3_manual_test_protocol.md](T3_3_manual_test_protocol.md)).

> **Adendo de Status Posterior (16/11/2026):** Posteriormente ao diagnóstico R2 e ao fechamento manual acima, a etapa **T3.3** foi **formalmente homologada pelo proprietário** ([T3_3_closeout_ACCEPTANCE.md](T3_3_closeout_ACCEPTANCE.md)), **integrada à `main` no commit `3c6fc0bd36fc3828af5a89662fb23cfb60d37865`** e marcada com a **tag anotada `t3-3-complete`**. A etapa **T3.4** permanece planejada e estritamente **bloqueada / não autorizada** (aguardando `T3.4-ARCHITECTURE-R2` e decisão expressa do proprietário). *O registro técnico e as medições originais da rodada R2 abaixo permanecem preservados integralmente.*

---

## 1. Sintoma Reportado pelo Proprietário (Teste Manual B2 — T3.3-R1)

Durante a execução manual do item **B2** do protocolo [T3_3_manual_test_protocol.md](T3_3_manual_test_protocol.md):
1. Um canteiro (`Abrigo Básico`) foi posicionado propositalmente na região elevada do platô próximo à rampa do `TestMap`.
2. Ao enviar um líder/trabalhador ao canteiro, o personagem ficou preso na lateral da rampa em vez de contornar pela base e subir pela entrada da rampa.
3. Ocorreu uma entrega parcial, mas o suprimento completo não foi concluído e os trabalhadores não deram continuidade esperada às atividades.

---

## 2. Reprodução Visual Automatizada (`tests/visual/t3_3_r2_plateau_repro.gd`)

Para reproduzir e isolar o defeito sem dependência exclusiva de execução headless, foi criado o runner visual renderizado [`tests/visual/t3_3_r2_plateau_repro.gd`](../../tests/visual/t3_3_r2_plateau_repro.gd), executado com janela real (`--rendering-driver opengl3 --debug-navigation --debug-collisions`) em **`1280×720`** e **`1920×1080`**, gerando telemetria JSONL frame a frame, resumos JSON e capturas de tela em `docs/testing/evidence/t3_3_r2_plateau/`:

- **Cenário A (`ground`):** Canteiro no chão plano de controle.
- **Cenário B (`plateau_center`):** Canteiro no centro do platô elevado com 1 líder suprindo completamente `12 Madeira` e `6 Pedra`.
- **Cenário C (`plateau_ramp_edge`):** Canteiro próximo à borda superior da rampa no platô com 1 líder.
- **Cenário D (`forced_lateral_approach`):** Trabalhador posicionado no chão plano ao lado da face lateral da rampa (`(9.5, 0.0, -9.8)`), forçando consulta de rota e deslocamento até canteiro próximo à borda superior da rampa.
- **Cenário E (`two_workers_plateau`):** 2 líderes (`LeaderA` + `LeaderB`) com interrupção do transportador após a primeira entrega parcial e promoção D9 para continuidade do suprimento no platô.

### 2.1 Causas Raiz Comprovadas na Captura `pre_fix`

A inspeção conjunta de `pre_fix_summary_1280x720.json`, `pre_fix_summary_1920x1080.json`, logs JSONL e capturas PNG confirmou três falhas acopladas:

1. **Ponte indevida de NavMesh cruzando a lateral inclinada da rampa (`src/navigation/world_navigation.gd`):**
   - O `NavigationMesh` (`DEFAULT_CELL_HEIGHT = 0.25`) conectava polígonos do chão plano diretamente à face inclinada lateral da `Ramp` ao longo de `z = -12.0` e `z = -16.0`.
   - No Cenário D `pre_fix`, `direct_nav_path` atravessava a parede lateral em `x = 6.5` (`[[9.5,0.5,-9.8], [6.5,0.5,-11.5], [6.75,0.75,-12.5], ...]`), registrando `path_crosses_lateral_wall: true`, `path_min_x: 6.5`, `unit_min_x_detour: 6.577` e **9 colisões laterais na `Ramp`** em ambas as resoluções.
   - No Cenário E `pre_fix`, após `LeaderA` cumprir a entrega inicial e ser interrompido, `LeaderB` promovido entrou em rota cruzando a lateral da rampa próximo a `(6.375, 0.33, -12.0)` mirando `[12.286, 2.286, -12.5]`, acumulando **62 colisões laterais na `Ramp`** (`1280×720`) / **58 colisões** (`1920×1080`), disparando `FAILED_STUCK` e abortando a ordem com `site_unreachable` após entrega incompleta (`stone: 6, wood: 10`).

2. **Tolerância vertical permissiva e ausência de verificação de piso/desnível nos slots de perímetro (`src/buildings/build_slot_planner.gd`):**
   - `HEIGHT_TOLERANCE` estava em `2.5` m, próximo ao desnível do platô, sem validar a cota do terreno físico (`CollisionLayers.MASK_TERRAIN`) para os pontos projetados em `snap_to_navmesh` e `resolved_target` nem detectar degraus baixos na verificação horizontal de `has_clear_physical_access()`.

3. **Falha imediata em `FAILED_STUCK` sem tentativa de slot alternativo (`src/units/orders/construct_order.gd`) e tolerância vertical de waypoint (`src/units/unit_movement.gd`):**
   - Quando `UnitMovement` emitia `MoveState.FAILED_STUCK` ao aproximar-se de um slot de perímetro ou entrega em borda elevada, `ConstructOrder` falhava imediatamente com `site_unreachable` sem tentar outro slot livre do perímetro.
   - Adicionalmente, `UnitMovement._resolve_steer_point()` e `_refresh_active_path()` não limitavam a discrepância vertical ao avançar waypoints em rampas/desníveis. *(Nota técnica: ao investigar tolerâncias verticais em `UnitMovement`, comprovou-se por falha imediata em `test_rvo_separation.gd` que `AVOIDANCE_NAVMESH_CLAMP_TOLERANCE_Y` deve permanecer em `0.75`, pois o `DEFAULT_CELL_HEIGHT = 0.25` do Recast posiciona a NavMesh do chão plano `Ground` (`y = 0.0`) em `y = 0.500`, resultando em diferença vertical de `0.499 m > 0.45 m` que rejeitaria pontos válidos de desvio RVO em terreno plano.)*

---

## 3. Correções Implementadas (Estritamente Escopadas à T3.3-R2)

1. **Barreira de bake apenas nas laterais de geometrias de terreno inclinadas (`src/navigation/world_navigation.gd`):**
   - Adicionado `_append_sloped_terrain_side_curbs(source_root, source_data)` reutilizando `_build_box_faces`, invocado em `request_rebake()` e `_prepare_candidate_build_inputs()` logo após `parse_source_geometry_data` e antes de `_store_static_geometry_cache`.
   - Para corpos estáticos em `CollisionLayers.MASK_TERRAIN` com `BoxShape3D` inclinados entre `5°` e `45°` (`up_axis.y in [0.707, 0.996]`), o bake adiciona meios-fios virtuais finos (`0.40 m`, menor que `2 * DEFAULT_AGENT_RADIUS`) apenas nas duas faces laterais da rampa (`u_start = 0.05`, `u_end = horiz_len - 0.15`), sem criar colisores físicos nem bloquear o pé da rampa ou a saída superior no platô.

2. **Validação vertical e de desnível nos slots físicos (`src/buildings/build_slot_planner.gd`):**
   - `HEIGHT_TOLERANCE` reduzida de `2.5` para `0.85`; adicionada `NAV_SURFACE_Y_TOLERANCE = 0.75` e `_sample_terrain_ground_y(world_pos, world_3d)` via raycast em `CollisionLayers.MASK_TERRAIN`.
   - `has_clear_physical_access()` passa a exigir `absf(from_pos.y - to_pos.y) <= HEIGHT_TOLERANCE` e executa raycast horizontal baixo a `minf + 0.35` quando `absf(from_pos.y - to_pos.y) > 0.20` para barrar acesso através de degraus/encostas verticais.
   - `compute_pile_approach_slot()` e `compute_site_perimeter_slot()` validam a cota da superfície navegável (`snap_to_navmesh` e `resolved_target`) contra o piso físico quando há terreno sob a posição, preservando fallback para cenários sintéticos isolados sem terreno sob o slot.

3. **Tentativa de slots alternativos de perímetro em `FAILED_STUCK` e alinhamento vertical de waypoint (`src/units/orders/construct_order.gd`, `src/units/unit_movement.gd`):**
   - Em `ConstructOrder`, adicionado `_retry_perimeter_slot_move(movement, target_state)` e atualizado o tratamento de `_update_moving_to_site_dropoff`, `_update_moving_to_builder_slot` e `_update_waiting_for_peer_supply`: diante de `UnitMovement.MoveState.FAILED_STUCK`, a ordem reavalia o papel/standby e tenta outro slot de perímetro disponível até `MAX_APPROACH_RETRIES`, mantendo falha imediata apenas em `MoveState.FAILED_INVALID`.
   - Em `UnitMovement`, adicionada `WAYPOINT_VERTICAL_TOLERANCE_Y = 0.65` em `_resolve_steer_point()` e `_refresh_active_path()`, mantendo `AVOIDANCE_NAVMESH_CLAMP_TOLERANCE_Y = 0.75`.

---

## 4. Comparativo `pre_fix` vs. `post_fix` em Execução Real Renderizada

Todos os cenários foram executados em janelas reais (`--rendering-driver opengl3 --debug-navigation --debug-collisions`) na GPU `Intel(R) UHD Graphics 620`, com **0 erros e 0 avisos** no `post_fix`:

| Cenário | Métrica | `pre_fix` (`1280×720`) | `pre_fix` (`1920×1080`) | `post_fix` (`1280×720`) | `post_fix` (`1920×1080`) |
|---|---|---|---|---|---|
| **A — Controle no chão plano** | Status / Entregue / Hits laterais `Ramp` | `PASS` / `12M, 6P` / `0` (`189` quadros) | `PASS` / `12M, 6P` / `0` (`189` quadros) | `PASS` / `12M, 6P` / `0` (`190` quadros) | `PASS` / `12M, 6P` / `0` (`189` quadros) |
| **B — Centro do platô (1 líder)** | Status / Entregue / Hits laterais `Ramp` | `PASS` / `12M, 6P` / `11` (`1873` quadros) | `PASS` / `12M, 6P` / `11` (`1872` quadros) | `PASS` / `12M, 6P` / `0` (`1929` quadros) | `PASS` / `12M, 6P` / `0` (`1929` quadros) |
| **C — Borda da rampa no platô (1 líder)** | Status / Entregue / Hits laterais `Ramp` | `PASS` / `12M, 6P` / `11` (`1606` quadros) | `PASS` / `12M, 6P` / `11` (`1595` quadros) | `PASS` / `12M, 6P` / `0` (`1659` quadros) | `PASS` / `12M, 6P` / `0` (`1655` quadros) |
| **D — Aproximação lateral forçada** | Status / Cruzamento lateral / `min_x` rota & unidade / Hits `Ramp` / Entregue | **`FAIL`** / `true` / `6.5` & `6.577` / `9` / `12M, 6P` | **`FAIL`** / `true` / `6.5` & `6.577` / `9` / `12M, 6P` | **`PASS`** / `false` / `4.5` & `4.583` / **`0`** / `12M, 6P` | **`PASS`** / `false` / `4.5` & `4.583` / **`0`** / `12M, 6P` |
| **E — 2 trabalhadores + interrupção/promoção D9** | Status / Entregue / Hits `Ramp` / Falhas / D9+standby+promoção | **`FAIL`** / `10M, 6P` / **`62`** / `site_unreachable` / `true, true, true` (`1772` quadros) | **`FAIL`** / `10M, 6P` / **`58`** / `site_unreachable` / `true, true, true` (`1745` quadros) | **`PASS`** / `12M, 6P` / **`0`** / `[]` / `true, true, true` (`1765` quadros) | **`PASS`** / `12M, 6P` / **`0`** / `[]` / `true, true, true` (`1763` quadros) |

### Evidências e Capturas Inspecionadas

- **Resumos JSON:**
  - [pre_fix_summary_1280x720.json](evidence/t3_3_r2_plateau/pre_fix_summary_1280x720.json) / [pre_fix_summary_1920x1080.json](evidence/t3_3_r2_plateau/pre_fix_summary_1920x1080.json)
  - [post_fix_summary_1280x720.json](evidence/t3_3_r2_plateau/post_fix_summary_1280x720.json) / [post_fix_summary_1920x1080.json](evidence/t3_3_r2_plateau/post_fix_summary_1920x1080.json)
- **Telemetria JSONL:**
  - [pre_fix_telemetry.jsonl](evidence/t3_3_r2_plateau/pre_fix_telemetry.jsonl) / [pre_fix_telemetry_1920x1080.jsonl](evidence/t3_3_r2_plateau/pre_fix_telemetry_1920x1080.jsonl)
  - [post_fix_telemetry.jsonl](evidence/t3_3_r2_plateau/post_fix_telemetry.jsonl) / [post_fix_telemetry_1920x1080.jsonl](evidence/t3_3_r2_plateau/post_fix_telemetry_1920x1080.jsonl)
- **Capturas de tela representativas (`1280×720` e `1920×1080`):**
  - Falha `pre_fix` na lateral da rampa: [`1280x720/pre_fix/09_pre_fix_failure_state.png`](evidence/t3_3_r2_plateau/1280x720/pre_fix/09_pre_fix_failure_state.png), [`1920x1080/pre_fix/09_pre_fix_failure_state.png`](evidence/t3_3_r2_plateau/1920x1080/pre_fix/09_pre_fix_failure_state.png), [`1280x720/pre_fix/scenario_E_final.png`](evidence/t3_3_r2_plateau/1280x720/pre_fix/scenario_E_final.png), [`1920x1080/pre_fix/scenario_E_final.png`](evidence/t3_3_r2_plateau/1920x1080/pre_fix/scenario_E_final.png)
  - Contorno pelo pé da rampa e suprimento concluído `post_fix`: [`1280x720/post_fix/scenario_D_detour.png`](evidence/t3_3_r2_plateau/1280x720/post_fix/scenario_D_detour.png), [`1920x1080/post_fix/scenario_D_detour.png`](evidence/t3_3_r2_plateau/1920x1080/post_fix/scenario_D_detour.png), [`1280x720/post_fix/09_post_fix_completed_standby.png`](evidence/t3_3_r2_plateau/1280x720/post_fix/09_post_fix_completed_standby.png), [`1920x1080/post_fix/09_post_fix_completed_standby.png`](evidence/t3_3_r2_plateau/1920x1080/post_fix/09_post_fix_completed_standby.png)

---

## 5. Regressão Automatizada e Benchmark Pós-T3.3-R2

Foram adicionados dois testes permanentes em [`tests/integration/test_t3_3_construction_logistics.gd`](../../tests/integration/test_t3_3_construction_logistics.gd):
- `test_09_r2_plateau_ramp_detour_and_elevated_slot_filtering` (18 asserções)
- `test_10_r2_plateau_two_worker_roles_promotion_and_full_supply` (13 asserções)

### 5.1 Validação Executada Após a Edição Final

| Verificação | Comando | Resultado Observado |
|---|---|---|
| Validação de projeto e scripts | `.\tools\validate.ps1` | **PASSOU** — `0 errors, 0 warnings, 104 scripts checked` |
| Suíte RVO isolada (após ajuste final em `unit_movement.gd`) | `.\tools\run_tests.ps1 -Filter "test_rvo_separation"` | **7/7 testes aprovados**, `129` asserções (`48905.1 ms`) |
| Testes filtrados da T3.3 | `.\tools\run_tests.ps1 -Filter "t3_3"` | **2/2 suítes, 18/18 testes aprovados, 369 asserções** (`40293.9 ms`): `test_t3_3_construction_logistics.gd` (**11/11**, `205` asserções) + `test_t3_3_construction_site.gd` (**7/7**, `164` asserções) |
| Bateria completa segmentada (T1–T3.3) | `.\tools\run_tests.ps1 -Segmented` | **7/7 batches PASS, 32/32 suítes (`Discovered=32, ExecutedUnique=32, Duplicates=0, Missing=0`), 229/229 testes aprovados, 7.518 asserções, 0 falhas, 0 erros de suíte** (`SumGodotElapsed: 275479,8 ms`, `TotalWallElapsed: 280419,0 ms`) |
| Higiene de diff | `git diff --check` | Limpo (`exit 0`, sem erros de espaço em branco) |

### 5.2 Benchmark Renderizado (`tests/perf/t3_3_logistics_benchmark.gd`) Pós-R2

- **Hardware / Energia:** `Intel(R) UHD Graphics 620`, OpenGL `3.3.0 Compatibility`, plano `Equilibrado` (`381b4222-f694-41f0-9685-ff5bb260df2e`), **tomada CA (`BatteryStatus = 2`, carga `87% / 95%`)**, `--rendering-driver opengl3`, `samples = 360` quadros de logística ativa (`4` trabalhadores, `2` canteiros com `TemporarySitePanel` aberto).

| Resolução | `site_creation_ms` (`n=2`) | `avg_fps` (`active_logistics_frame_ms`) | `mean_ms` | `p50_ms` | `p95_ms` | `max_ms` | `frames_gt_100ms` | Console |
|---|---|---|---|---|---|---|---|---|
| `1920×1080` | `mean 2,552 ms` (`p50 2,202`, `p95 2,901`, `max 2,901`) | `126,08 FPS` | `7,931 ms` | `7,053 ms` | `14,080 ms` | `93,201 ms` | `0` | `EXIT=0 ERR=False WARN=False` |
| `1280×720` | `mean 4,000 ms` (`p50 3,107`, `p95 4,893`, `max 4,893`) | `255,68 FPS` | `3,911 ms` | `3,680 ms` | `5,476 ms` | `7,710 ms` | `0` | `EXIT=0 ERR=False WARN=False` |

---

## 6. Limites Conhecidos e Próximo Passo Manual *(Registro Histórico da Rodada R2)*

- Na ocasião da publicação deste diagnóstico R2, o item **B2** aguardava reteste manual e os itens **C1–D2** estavam pendentes. Posteriormente (16/11/2026), **todos os 10/10 itens manuais foram aprovados** e a **T3.3 foi formalmente homologada na `main` (`3c6fc0b`, tag `t3-3-complete`)** conforme adendo no topo e [T3_3_closeout_ACCEPTANCE.md](T3_3_closeout_ACCEPTANCE.md); **nenhuma funcionalidade de `T3.4+` foi implementada**.
