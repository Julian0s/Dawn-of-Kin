# R-03A D1 R2 — Relatório Técnico da Candidata (Ressalvas Humanas `H-F01` e Fidelidade Visual D2.2 `H-V01`/`H-V02`/`H-V03`)

- **Data:** 25/11/2026
- **Incremento:** **`R-03A D1 R2`** — Revisão focal das ressalvas humanas de `H1`–`H7` sobre `R-03A D1 R1`
- **Status real:** **`IMPLEMENTADO`** · **`VALIDADO TECNICAMENTE`** · **`PUBLICADO EM BRANCH CANDIDATA`** · **`AUDITORIA INDEPENDENTE PENDENTE`** · **`RETESTE HUMANO FOCAL PENDENTE`** · **`R-03A NÃO HOMOLOGADA`** · **`NÃO INTEGRADO À DEVELOP`** · **`D2 NÃO AUTORIZADA`** · **`R-03B BLOQUEADA`**
- **Base imediata auditada:** `9f5b307d139bcec4e885d5ca90b6bed0899dda31` (`R-03A D1 R1`, aceita tecnicamente)
- **Ancestralidade linear:** `21c34ee` (`develop` / `R-02B.5`) → `f77e99e` (`R-03A R1.1`) → `a39f3b5` (`R-03A D0`) → `a56af98` (`R-03A D1`) → `9f5b307` (`R-03A D1 R1`) → **`R-03A D1 R2`**
- **Branch candidata:** `feat/r-03a-community-work-main-scene`
- **Worktree único utilizado:** `C:\Projetos\Dawn_of_Kin_wt_r_03a`
- **Relatórios preservados integralmente:** [R-03A original](R_03A_community_work_main_scene_candidate_report.md), [R-03A R1](R_03A_R1_community_work_main_scene_candidate_report.md), [R-03A R1.1](R_03A_R1_1_focal_evidence_candidate_report.md), [R-03A D0](../architecture/R_03A_D0_community_work_experience_revision_PLAN.md), [R-03A D1](R_03A_D1_source_selection_and_authorization_candidate_report.md) e [R-03A D1 R1](R_03A_D1_R1_focal_correction_candidate_report.md).

---

## 1. Registro fiel dos testes humanos focais `H1`–`H7` (sobre `D1 R1`) e decisões aprovadas

Todos os sete cenários focais foram aprovados funcionalmente pelo proprietário, com ressalvas específicas de interação (`H-F01`) e fidelidade visual (`H-V01`, `H-V02`, `H-V03`), mantendo-se `R-03A` **NÃO HOMOLOGADA** até reteste humano e conclusão de `D2`–`D4`:

| Cenário | Resultado humano (`D1 R1`) | Observações registradas |
|---|---|---|
| `H1` — Seleção individual | Aprovado | Desmarcação intermitente ao clicar no terreno (`H-F01`) |
| `H2` — Seleção heterogênea | Aprovado | Mesma ocorrência (`H-F01`) |
| `H3` — Shift + arraste | Aprovado | Mesma ocorrência (`H-F01`) |
| `H4` — Autorização pela HUD | Aprovado | Nenhuma |
| `H5` — Qualidade visual | Aprovado com ressalvas | Fidelidade mineral D2.2 (`H-V01`–`H-V03`) e ausência de parada (`H-P01`, prevista para `D2`) |
| `H6` — Controles RTS | Aprovado | Nenhuma |
| `H7` — Trabalho e fluidez | Aprovado | Nenhuma |

**Aspectos visuais avaliados como satisfatórios (preservados):**
1. Posicionamento central inferior da barra contextual.
2. Tamanho perceptível dos ícones (`22×22 px`).
3. Legibilidade das contagens numéricas.
4. Fluidez da interação.

**Aspectos visuais a melhorar (tratados nesta R2):**
1. Aparência dos ícones (`H-V02`).
2. Consistência mineral com a HUD D2.2 escolhida ("visual pedra", `H-V01`).
3. Distinção visual no mundo entre fontes selecionadas e fontes com trabalho autorizado (`H-V03`).

**Decisões expressas aprovadas pelo proprietário:**
- **`V1`:** reproduzir a materialidade de pedra D2.2 utilizando as referências e assets homologados, preservando ícones e contagens minimalistas (sem títulos permanentes, descrições longas ou botão `Parar`).
- **`V2`:** substituir os dois anéis concêntricos por **um anel discreto de seleção** e **um pequeno símbolo correspondente à atividade autorizada** (machado, picareta, colheita).
- **`H-P01` (`D0-A02`):** limitação prevista de cancelamento definitivo preservada integralmente para `D2` (não antecipada nesta R2).

---

## 2. Diagnóstico forense e correção de `H-F01` (desmarcação intermitente no terreno)

### 2.1 Investigação instrumental na `MainScene` real (`9f5b307`)
Foram executados dois roteiros instrumentais sobre a base não modificada `9f5b307` em `1920×1080` e `1280×720` (`evidencias\R-03A\D1\R2\diagnostico_hf01\diag_hf01_forensic.txt` e `diag_hf01_edge_cases.txt`):

- **Causa-raiz comprovada (100% reproduzível):**
  - `RtsInputController.BASE_DRAG_THRESHOLD_PX` é `6,0 px` (a 96 DPI).
  - Quando o jogador executa um clique esquerdo rápido sem `Shift` sobre terreno livre e o ponteiro desliza `> 6,0 px` entre pressionamento e soltura (micro-arraste natural de `6,5–15 px`, ou pequeno arraste vazio no chão), `RtsInputController._unhandled_input()` roteia o evento para `_handle_box_selection(start_pos, end_pos, shift_held = false)`.
  - Em `AutonomousGatherInput._handle_box_selection()` (`src/rts/autonomous_gather_input.gd`), o ramo `DragMode.UNIT_BOX_RTS` chamava apenas `super._handle_box_selection(...)` — que limpava `SelectionManager` quando `0` unidades estavam na caixa, **mas nunca limpava `_selection_model`**.
  - Consequência exata do relato humano: cliques sobre terreno livre com deslocamento `<= 6,0 px` desmarcavam normalmente; cliques sobre terreno livre com deslocamento `>= 6,5 px` mantinham todas as fontes selecionadas e a HUD visível, obrigando a repetir cliques até acertar um clique com drift `<= 6,0 px`.
- **Hipóteses investigadas e descartadas com evidência:**
  - *Overlays transparentes em `UiLayer` bloqueando cliques:* descartada (apenas `BuildButton` e `ActionsPanel`/`Authorize_*` visíveis têm `mouse_filter != IGNORE`; `0/60` pontos de terreno livre bloqueados na varredura de grade).
  - *Estado residual de `_left_pressed` ou `_drag_mode` ao cruzar a HUD:* descartada (`EDGE 1`/`EDGE 2` retornaram `_left_pressed = false` e `_is_drag_gesture = false`).
  - *Erro do `WorldPicker` sobre terreno livre:* descartada (`ground_non_clear = 0` em toda a varredura).
  - *Double-click ou deslocamento de câmera durante clique:* descartadas (`AUDIT 9`, `EDGE 7` limparam normalmente).
  - *Atraso visual ou indicadores órfãos em `SourceSelectionModel`:* descartada (remoção é síncrona ao sinal `selection_changed`).
- **Fronteiras preservadas (`§5.5`):** cliques diretos sobre obstáculos (`PickResult.Kind.OBSTACLE`), unidades (`UNIT`, coexistência com painel de habitantes), canteiros (`CONSTRUCTION_SITE`) ou fontes esgotadas/indisponíveis continuam diferenciados de terreno livre; colisores de fontes (`InteractionArea`) e `BASE_DRAG_THRESHOLD_PX` (`6,0 px`) não foram alterados.

### 2.2 Evidência RED/GREEN e correção mínima aplicada
- **RED (base `9f5b307` sem alteração de produção):** suíte `test_r_03a_d1_selection_and_authorization.gd` com os 3 novos testes `test_r2_hf01_01..03` falhou com `3` testes / `27` asserções comportamentais reprovadas especificamente em cliques sobre terreno livre com drift natural `> 6,0 px` (`evidencias\R-03A\D1\R2\red_green\hf01_red_before.txt`, `exit=1`).
- **Correção mínima (`src/rts/autonomous_gather_input.gd`):** no ramo `UNIT_BOX_RTS` de `_handle_box_selection()`, após `super._handle_box_selection(start_pos, end_pos, unit_shift)`, se `not unit_shift and not shift_held` e `_selection_manager.is_empty()` e tanto `pick_at_screen_pos(start_pos)` quanto `pick_at_screen_pos(end_pos)` forem terreno livre (`is_ground() or is_none()`), chamar `_selection_model.clear()`.
- **GREEN:** repetição exata sobre a correção aprovada (`18/18` na verificação pura em `hf01_green_after.txt`, `20/20` e `443` asserções após inclusão dos testes de `H-V01`/`H-V03`).

---

## 3. Restauração da materialidade D2.2 (`H-V01`), ícones (`H-V02`) e marcadores de mundo (`H-V03`)

### 3.1 Referências homologadas inspecionadas diretamente
- `docs/design/DAWN_OF_KIN_VISUAL_DESIGN_SYSTEM.md` (Seções 1–4, `resource_rock` e `slab_cmd_basalt`).
- `assets/ui/d2/d2_2_faithful_atlas.png` + `assets/ui/d2/atlas_manifest.json` (verificados intocados por `git diff` e SHA-256).
- `docs/design/ui-0-r2-2/G_godot_D2_2_hud_1920x1080.png`, `detail_crops/C_tl_resources.png`, `detail_crops/C_br_commands.png` e `docs/design/ui-1-3/C_ui_1_3_compare_action_slabs.png`.
- Componentes de produção `UI-1`: `D2AtlasLibrary`, `D2Tokens`, `D2ThemeFactory`, `D2PolygonalSlab`, `D2SlabButton`, `D2ActionSlabsView` e `D2ResourceRocksView`.

### 3.2 `H-V01` — Materialidade mineral na `CommunitySelectionActionsHud`
- **Assets e componentes reutilizados:**
  - Região **`slab_cmd_basalt`** (`166×92 px`, conteúdo `146×72 px`, `shadow_pad = 10 px`, polígono `D2Tokens.POLYGON_SLAB_CMD_BASALT`) carregada de `d2_2_faithful_atlas.png` via `D2AtlasLibrary`, aplicada em escala isotrópica uniforme `0,583×` (`97×54 px` externo / `85×42 px` rocha sólida — downsampling nítido sem distorção).
  - **`D2PolygonalSlab`** para cada laje de comando presente (`[Machado N]`, `[Picareta N]`, `[Colheita N]`), eliminando os retângulos genéricos `StyleBoxFlat` da D1 e mantendo ritmo orgânico D2.2 (`SLAB_STAGGER_Y = [0, 3, 1] px`) ancorado no centro inferior (`BOTTOM_OFFSET_PX = 16 px`).
  - **`D2ThemeFactory`** (`Palatino Linotype` / `Georgia` bold `16 px` em `#F4EFE4`) para as contagens.
  - Botão poligonal interno (`_PolygonalCommandButton extends Button`) com `_has_point()` sobre `Geometry2D.is_point_in_polygon()` e `_gui_input()` consumindo LMB/RMB/MMB/scroll na rocha sólida, deixando margens transparentes de sombra e vãos entre pedras `MOUSE_FILTER_IGNORE`.
- **Cinco estados discretos sobre a pedra (sem pintar a rocha inteira nem depender apenas de cor):**
  - `available`: basalto nativo + filete dourado do atlas; hover realça `#F5D996` (`1,5 px`) + leve brilho.
  - `partial`: filete `#DFBC72` (`1,6 px`) + traço duplo inferior gravado em ouro.
  - `authorized`: filete `#A5C98B` (`1,75 px`, 9,78:1 AAA) + marca gravada `✓` no canto superior direito + contagem `#A5C98B`.
  - `blocked_reauthorization`: filete `#EAB464` (`1,75 px`, 9,68:1 AAA) + marca gravada `!` no canto superior direito + contagem `#EAB464`.
  - `economy_blocked`: véu escuro contido (`alpha 0,44`), filete terracota `#C66A58` (`1,35 px`), marca `×`, ícone atenuado, contagem `COLOR_DISABLED_TEXT` e `disabled = true`.
- **Flags preservadas:** `use_d2_2_hud = false`, `use_provenance_economy = true`, `automatic_cancellation_recovery = true`; sem botão `Parar`.

### 3.3 `H-V02` — Refinamento dos 3 ícones independentes (`48×48 px`)
- `assets/ui/d2/icons/ico_work_chop.png` — machado lenhador gravado em ouro kintsugi (`#DFBC72` / `#F5D996`) com corpo rebaixado `#2A241C` (harmonia direta com `ico_wood`).
- `assets/ui/d2/icons/ico_work_mine.png` — picareta arqueada de pontas duplas em ardósia-marfim (`#D8E0E6` / `#30343A`) com cabo e colar em ouro `#DFBC72` (harmonia direta com `ico_stone`).
- `assets/ui/d2/icons/ico_work_harvest.png` — foice curva de colheita em ouro `#DFBC72` / `#F5D996` emoldurando fruto âmbar `#E6A854` com haste sálvia `#92B874` (harmonia direta com `ico_food`).
- Atlas `d2_2_faithful_atlas.png` e `atlas_manifest.json` **100% intocados**; prancha comparativa arquivada em `evidencias\R-03A\D1\R2\visual\prancha_icones_d2_2_vs_d1_vs_r2.png`.

### 3.4 `H-V03` (`V2`) — Anel único de seleção + símbolo discreto de atividade autorizada
- **Seleção (`SourceSelectionRing_<sid>`):** único anel discreto ao redor da base (`0,86`–`0,98`, material compartilhado `SELECTION_RING_COLOR`).
- **Trabalho autorizado (`AutoGatherWorkMarker_<task_id>`):** substitui integralmente o antigo anel interno `AutoGatherTaskRing_<task_id>` por um `Sprite3D` puramente visual (`BILLBOARD_ENABLED`, `cast_shadow = OFF`, `no_depth_test = false`, **zero `CollisionObject3D`/`Area3D`**, **zero `_process`**).
  - Usa cache compartilhado de no máximo 6 `ImageTexture` (`64×64 px`, 3 categorias × `{active, blocked}`): pequeno selo octogonal chanfrado de basalto escuro (`#141618`) com borda `#DFBC72` emoldurando o ícone refinado da atividade (`Machado` / `Picareta` / `Colheita`); em `BLOCKED_REAUTHORIZATION`, a borda alterna por sinal (`Board.task_updated`) para âmbar `#EAB464` com ícone suavemente atenuado e marca `!` âmbar.
  - Alturas calibradas por inspeção direta em GPU (evitando oclusão pela copa e colisão com `DiscoverabilityBadge`): madeira `y = 4,40 m`, pedra `y = 1,72 m`, alimento `y = 1,38 m` (`pixel_size = 0,0110`).
  - Persiste em `PENDING_WORKERS` e `IN_PROGRESS`; removido automaticamente em `task_closed` (esgotamento, conclusão, falha, remoção da fonte) e em `teardown_community_work()`.

---

## 4. Resultados da validação técnica, visual e de desempenho

### 4.1 Testes focais (`13/13` suítes — `118/118` testes, `2.756` asserções, `0` falhas)
- `test_r_03a_d1_selection_and_authorization.gd`: `20/20` (`443` asserções) — inclui `H-F01` (`01`–`03`), `H-V01` (`materiality_polygons_and_states`), `H-V03` (4 estados + ciclo de vida completo + `WorldPicker` + reinstanciação) e preservação de `T01-A`/`T01-B`.
- `test_r_03a_community_work_main_scene.gd`: `28/28` (`962` asserções, reconciliado helper `_count_highlight_children` para `AutoGatherWorkMarker_`).
- `test_source_selection_model.gd`: `4/4` (`52`); `test_box_selection.gd`: `7/7` (`58`); `test_picking_selection.gd`: `9/9` (`70`).
- `test_rux_1_autonomous_gather.gd`: `7/7` (`87`); `test_rux_2a_auto_resources.gd`: `10/10` (`166`); `test_rux_2b_multi_source_selection.gd`: `14/14` (`116`, helper `_count_highlight_children` reconciliado).
- `test_ui_1_1a_foundation.gd`: `4/4` (`109`); `test_ui_1_1a_visual_data.gd`: `4/4` (`240`); `test_ui_1_3_construction_flow.gd`: `3/3` (`155`).
- `test_t3_6_2_c4_10_work_regional_authority.gd`: `3/3` (`179`); `test_t3_6_2_c4_12_rts_provenance.gd`: `5/5` (`119`).

### 4.2 Validação estática, smokes e regressão integral segmentada
- **`.\tools\validate.ps1`:** `PASSED` — `0` erros, `0` avisos, `213` scripts validados, boot headless limpo, `DOCS_DESIGN_IMPORT_COUNT=0`.
- **Smokes reais (`.\tools\run_game.ps1 -FailOnWarnings`):** `1280×720` (`exit=0`) e `1920×1080` (`exit=0`).
- **Regressão integral segmentada (`.\tools\run_tests.ps1 -Segmented -MaxIntegrationPerGroup 1`):**
  - **`62/62` lotes**, **`88/88` suítes** (`Discovered=88 | ExecutedUnique=88 | Duplicates=0 | Missing=0`), **`644/644` testes**, **`30.447` asserções**, **`0` falhas**, **`0` SuiteErrors**, `exit=0`.
  - **Delta perante D1 R1 (`88` suítes / `639` testes / `30.285` asserções / `213` scripts / `62` lotes):** `+5` testes focais R2 (`test_r2_hf01_01..03`, `test_r2_hv01_*`, `test_r2_hv03_*`) e `+162` asserções líquidas (mesmas `88` suítes, `213` scripts e `62` lotes).

### 4.3 Validação visual real em GPU (`1280×720` e `1920×1080`)
- Capturados e inspecionados diretamente 8 cenários representativos cobrindo todos os 10 estados de `§13.1` em `1280×720` e `1920×1080` (`16` capturas reais na Intel UHD Graphics 620) + 2 pranchas comparativas em `evidencias\R-03A\D1\R2\visual\`:
  - `prancha_icones_d2_2_vs_d1_vs_r2.png`
  - `prancha_comparativa_d1_vs_r2.png`
  - Capturas `01_none_selected` até `08_blocked_reauth_and_construction` (`1280x720` e `1920x1080`).
- A primeira inspeção real em GPU identificou oclusão parcial do marcador de madeira pela copa superior em `y = 3,22 m`; após recalibração para `y = 4,40 m` (e alimento `y = 1,38 m`), a reinspeção confirmou clareza total dos 4 estados, materialidade mineral autêntica e zero sobreposição em `720p` e `1080p`.

### 4.4 Desempenho proporcional (`Intel(R) UHD Graphics 620`, `1920×1080`, `gl_compatibility`, `--disable-vsync`)
- Polling verificado: `HUD._process=false`, `HUD._physics=false`, `Board._process=false`, `Dispatcher._process=false`.
- **Resultados medidos (`evidencias\R-03A\D1\R2\desempenho\perf_r03a_d1_r2_1080p.txt`):**
  - `Idle (steady 180f)`: `avg = 7,985 ms` | `p50 = 7,799 ms` | **`p95 = 10,129 ms`** | `max = 13,045 ms` (ref. D1 steady: `8,556 ms`).
  - `Multi/Heterogêneo + HUD basalto 3 cat. (COLD 60f)`: `avg = 8,149 ms` | **`p95 = 11,112 ms`** | `max = 43,870 ms`.
  - `Multi/Heterogêneo + HUD basalto 3 cat. (STEADY 180f)`: `avg = 8,404 ms` | **`p95 = 10,349 ms`** | `max = 13,537 ms` (ref. D1 steady: `9,112 ms`).
  - `Marcadores de trabalho ativos (COLD 60f)`: `avg = 9,436 ms` | **`p95 = 11,314 ms`** | `max = 110,101 ms` (pico único de geração inicial das texturas em cache + primeiro draw `Sprite3D`).
  - `Trabalho ativo + marcadores + zoom (22/36/58) + hover + box drag (STEADY 180f)`: `avg = 8,107 ms` | **`p95 = 14,263 ms`** | `max = 26,268 ms` (ref. D1 steady: `11,578 ms`).
- Referência histórica a frio da D1 preservada (`pico = 72,630 ms`, `p95 = 22,710 ms`, atribuição à compilação inicial registrada apenas como hipótese). Todos os cenários em regime permanente e a frio mantiveram `p95 <= 16,7 ms`. Avaliação final consolidada reservada à `D4`.

---

## 5. Limitações conhecidas e pendências

- **Aceite humano e visual pendentes:** a aprovação técnica e inspeção do agente **não** substituem a auditoria independente do ChatGPT nem o reteste humano focal do proprietário (especialmente para confirmar a percepção prática de `H-F01` e a aprovação estética de `V1`/`V2`).
- **`H-P01` (`D0-A02` → `D2`):** cancelamento comunitário definitivo (botão `Parar`) permanece intencionalmente fora da R2.
- **`D0-A03` e `D0-A04` → `D3`:** corte progressivo até derrubada de árvores e conservação econômica associada permanecem fora da R2.
- **`D4`:** campanha consolidada final (`M1`–`M8` completos e benchmark final CA/DC) permanece reservada.
- **`R01` (T4):** isolamento de fonte externa não etiquetada no mesmo `World3D` segue limitação documentada reservada à `T4`.
- **`use_d2_2_hud = false`:** preservado até `R-05B` (`D-ERR-1 B`).
