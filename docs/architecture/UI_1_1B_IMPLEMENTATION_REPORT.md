# DAWN OF KIN — UI-1.1B: RELATÓRIO TÉCNICO DE IMPLEMENTAÇÃO
## Interação Poligonal, Pausa Segura, Proteção da Câmera e Roteador Progressivo de Esc — Identidade D2.2 ("Marcos de Pedra e Eclipse")

> **Status:** `CANDIDATA PRONTA PARA AUDITORIA INDEPENDENTE E HOMOLOGAÇÃO DO PROPRIETÁRIO` — Subincremento **`UI-1.1B`** implementado sobre a fundação homologada **`UI-1.1A R2`** (`a02aa97`), validado estaticamente (`199` scripts GDScript, `0` erros, `0` avisos), aprovado integralmente na regressão segmentada completa (**`81/81` suítes, `579/579` testes, `28.329` asserções, `0` falhas, `0` erros de suíte, `0` timeouts, código de saída `0`**) e validado visualmente ao vivo na **Godot 4.7.2** (`Intel(R) UHD Graphics 620`, `OpenGL 3.3 Compatibility`) em `1280×720` e `1920×1080`.  
> **Escopo estritamente respeitado:** Somente **`UI-1.1B`** foi implementada. `UI-1.2`, `UI-1.3`, `UI-1.4`, `UI-1.5` e demais etapas futuras **NÃO foram iniciadas**. Nenhum merge ou tag foi criado. `use_d2_2_hud = false` permanece inalterado como padrão de produção em `src/main/main.tscn`.  
> **Branch Candidata:** `feat/ui-1-1b-d2-interaction-pause` (worktree isolado `C:\Projetos\Dawn_of_Kin_wt_ui_1_1b`).  
> **Base Homologada (`UI-1.1A R2`):** `feat/ui-1-1a-d2-visual-foundation` @ `a02aa97bb4358ccf0b78c9f35deab766bc21ff6e`.  
> **SHA Técnico da Implementação (código + testes + evidências VCG):** `577116347c69d252a0512a03a13176fd4e94476f`.

---

## 1. Referências Normativas e Paridade de Assets

- **Plano Técnico Aprovado:** `planning/ui-1-0-r1-integration-plan` @ `7dbfeb148f68f353bad71e1363db01eae7c41018` (`docs/architecture/UI_1_0_R1_INTEGRATION_PLAN.md`).
- **Design System Homologado:** `design/ui-0-r2-3-2-closeout` @ `cdd9f2f4308a05d822c8f7c72f57c0a07756f0a6` ([DAWN_OF_KIN_VISUAL_DESIGN_SYSTEM.md](../design/DAWN_OF_KIN_VISUAL_DESIGN_SYSTEM.md)).
- **Referência Visual Aprovada D2.2:** `design/ui-0-r2-2-d2-visual-fidelity` @ `1ab8ffb78c269f3a659712491de91ab1f317e919`.
- **Fundação UI-1.1A Homologada:** `feat/ui-1-1a-d2-visual-foundation` @ `a02aa97bb4358ccf0b78c9f35deab766bc21ff6e` ([UI_1_1A_IMPLEMENTATION_REPORT.md](UI_1_1A_IMPLEMENTATION_REPORT.md)).
- **Integridade dos 9 Assets D2.2:** Paridade SHA-256 bit-a-bit reconfirmada entre `docs/design/ui-0-r2-2/assets/*` e `res://assets/ui/d2/*` (`9/9` idênticos, zero alteração visual ou de atlas).

---

## 2. Arquivos Criados e Modificados

### 2.1 Novos Arquivos de Produção (`src/ui/d2/`)
- [`src/ui/d2/components/d2_polygonal_slab.gd`](../../src/ui/d2/components/d2_polygonal_slab.gd) — Superfície mineral poligonal (`extends TextureRect`) com `_has_point()` via `Geometry2D.is_point_in_polygon()`, compensação de `shadow_pad = 10 px`, recálculo em `NOTIFICATION_RESIZED`, `MOUSE_FILTER_STOP`, `mouse_force_pass_scroll_events = false`, `FOCUS_NONE` e `accept_event()` explícito para botões/scroll do mouse.
- [`src/ui/d2/components/d2_slab_button.gd`](../../src/ui/d2/components/d2_slab_button.gd) — Botão nativo Godot (`extends BaseButton`) com suporte a silhueta poligonal opcional e controles D2.2 da placa superior (`||` e `1×`), `FOCUS_NONE`, `mouse_force_pass_scroll_events = false`, consumo de clique direito/meio/scroll via `accept_event()`, e estados visuais canônicos (`normal`, `hover`, `pressed`, `active`, `external_pause_indicator`, `disabled`).
- [`src/ui/d2/d2_simulation_pause_controller.gd`](../../src/ui/d2/d2_simulation_pause_controller.gd) — Autoridade de pausa segura da UI (`PROCESS_MODE_ALWAYS`, zero polling), pilha idempotente de motivos da UI (`&"hud_pause"`), observador síncrono pausável (`_TreePauseObserver` via `NOTIFICATION_PAUSED`/`NOTIFICATION_UNPAUSED`), contrato cooperativo explícito de leases em `SceneTree` (`dok_pause_authorities`) e guarda contra remoção destrutiva de pausas externas.
- [`src/ui/d2/d2_ui_escape_router.gd`](../../src/ui/d2/d2_ui_escape_router.gd) — Roteador progressivo de `Esc` ordenado por prioridade (`10`..`90`), instanciado em modo estritamente **pass-through** (`0` handlers ativos na `UI-1.1B`).

### 2.2 Arquivos de Produção Modificados (Cirúrgicos)
- [`src/ui/d2/d2_tokens.gd`](../../src/ui/d2/d2_tokens.gd) — Adicionados polígonos canônicos D2.2 (`POLYGON_RESOURCE_ROCK`, `POLYGON_TOP_PLAQUE`, etc.) e tokens cromáticos dos controles de tempo (`COLOR_TIME_BTN_*`) extraídos do showcase aprovado D2.2.
- [`src/camera/rts_camera_rig.gd`](../../src/camera/rts_camera_rig.gd) — Adicionados `set_input_locked(locked: bool)` / `is_input_locked()`, limpeza de estado transitório (`_pan_velocity_xz`, `_is_dragging`, `_pending_drag_pixels`) ao travar/destravar, rastreamento de `_last_mouse_pos` em `_input()` (eliminando posição obsoleta sobre controles `MOUSE_FILTER_STOP`) e verificação `_is_pointer_over_blocking_gui(viewport)` via `viewport.gui_get_hovered_control()` no Edge Pan, mantendo WASD livre fora de pausa e 100% dos testes legados de câmera intactos.
- [`src/ui/d2/components/d2_resource_rocks_view.gd`](../../src/ui/d2/components/d2_resource_rocks_view.gd) — Migração dos 3 blocos de recurso para `D2PolygonalSlab` (`POLYGON_RESOURCE_ROCK`, `pad = 10 px`), mantendo `process_mode = PROCESS_MODE_PAUSABLE` e ícones/rótulos/container em `MOUSE_FILTER_IGNORE`.
- [`src/ui/d2/components/d2_top_plaque_view.gd`](../../src/ui/d2/components/d2_top_plaque_view.gd) — `process_mode = PROCESS_MODE_ALWAYS`, fundo `D2PolygonalSlab` (`POLYGON_TOP_PLAQUE`, `pad = 10 px`), ativação real apenas dos botões `||` e `1×` via `D2SlabButton` ligados a `D2SimulationPauseController`, honestidade visual em pausa externa (`1×` desabilitado), e preservação estrita de `2×`, `4×` e `· ☰ MENU` como inertes/desabilitados (`MOUSE_FILTER_IGNORE`, zero `BaseButton`, zero callbacks).
- [`src/ui/d2/d2_hud_root.gd`](../../src/ui/d2/d2_hud_root.gd) — Composição de `D2SimulationPauseController` e `D2UiEscapeRouter` (pass-through), `process_mode = PROCESS_MODE_ALWAYS` no compositor transparente raiz (veja §4.3), `configure()` retrocompatível com `camera_rig` e `economy_clock` opcionais, e `unbind()` idempotente.
- [`src/main/main.gd`](../../src/main/main.gd) — Em `_setup_d2_hud()` (executado exclusivamente quando `use_d2_2_hud == true`), repassa `_camera_rig` e `_economy_clock` para `_d2_hud_root.configure(...)`. Modo legado (`use_d2_2_hud = false`) 100% intocado.

### 2.3 Testes Criados e Atualizados
- **Novas suítes `UI-1.1B`:**
  - [`tests/unit/test_ui_1_1b_polygon_and_pause.gd`](../../tests/unit/test_ui_1_1b_polygon_and_pause.gd) (`4` testes, `131` asserções).
  - [`tests/integration/test_ui_1_1b_hitboxes_and_pause.gd`](../../tests/integration/test_ui_1_1b_hitboxes_and_pause.gd) (`5` testes, `127` asserções, executando sob `use_provenance_economy = true`).
- **Atualização pontual de 2 asserções transitórias de `UI-1.1A` (sem excluir testes):**
  - [`tests/unit/test_ui_1_1a_foundation.gd`](../../tests/unit/test_ui_1_1a_foundation.gd): atualizada a asserção de botões na placa superior para verificar o contrato evoluído da `UI-1.1B` (exatamente 2 botões ativos `||`/`1×` e `has_inert_unimplemented_controls() == true` para `2×`/`4×`/`MENU`).
  - [`tests/integration/test_ui_1_1a_visual_data.gd`](../../tests/integration/test_ui_1_1a_visual_data.gd): substituída a verificação genérica de todos os controles em `MOUSE_FILTER_IGNORE` pelo contrato estrito `_assert_ui_1_1b_mouse_filter_contract()` (somente `D2PolygonalSlab` e `D2SlabButton` usam `MOUSE_FILTER_STOP` + `mouse_force_pass_scroll_events = false` + `FOCUS_NONE`; todos os containers, ícones, rótulos e slots inertes permanecem `MOUSE_FILTER_IGNORE`).

---

## 3. Implementação A — Hitboxes Poligonais (`D2PolygonalSlab` e `D2SlabButton`)

- **Auditoria Pixel-a-Pixel do Atlas:** Antes da implementação, os vértices canônicos do Design System foram confrontados contra o canal alpha real de `assets/ui/d2/d2_2_faithful_atlas.png` + `atlas_manifest.json` (`shadow_pad = 10 px`):
  - `resource_rock` (`84×42`, região `104×62`): `[(6,0), (84,3), (79,42), (0,38)] + (10,10)` — todos os vértices incidem exatamente sobre o filete dourado kintsugi (`alpha ≈ 153–200`), enquanto o pad de sombra `(0..9)` e os chanfros externos `(11,11)` permanecem transparentes (`alpha = 0–12`).
  - `top_plaque` (`196×110`, região `216×130`): `[(0,4), (98,0), (196,4), (190,110), (6,106)] + (10,10)` — vértices da cumeeira e laterais chanfradas coincidem exatamente com o filete dourado (`alpha ≈ 150–208`).
- **Comportamento real na Godot 4.7.2:**
  - `Control._has_point(point)` executa `Geometry2D.is_point_in_polygon(point, _scaled_polygon)` e recalcula `_scaled_polygon` em `NOTIFICATION_RESIZED` e `set_scaled_size()`.
  - `_gui_input(event)` invoca `accept_event()` explicitamente em eventos `InputEventMouseButton` (esquerdo, direito, meio e scroll wheel em `D2PolygonalSlab`; botão direito, meio, scroll ou estado desabilitado em `D2SlabButton`), impedindo qualquer vazamento para `_unhandled_input()` (`RtsInputController`, `CommandController`, `RtsCameraRig`).
  - Os vãos entre as 3 pedras escalonadas (mesmo onde os retângulos delimitadores do `shadow_pad` de 10 px se sobrepõem) retornam `_has_point() == false` em ambas as pedras adjacentes, deixando cliques chegarem livremente ao terreno 3D.

---

## 4. Implementação B — Arquitetura e Propriedade dos Estados de Pausa

### 4.1 Auditoria Completa de Autoridades de Pausa no Repositório
Auditoria executada em `src/**/*.gd` e `tests/**/*.gd`:
- **`SceneTree.paused`:** Nenhum script de produção em `src/` escrevia `SceneTree.paused` antes da `UI-1.1B`. Leitores existentes: `EconomyClockController.is_paused()` (`tree_paused or clock_paused`) e o mecanismo nativo `PROCESS_MODE_PAUSABLE` da Godot (unidades, navegação, construção, `RtsInputController`, `PlacementController`, `EconomyClockController` e `DecayTickTimer`).
- **`EconomyClockController.set_paused()` / `SimulatedWorldTimeProvider.set_paused()`:** Utilizados apenas em testes unitários/isolados; `D2SimulationPauseController` **nunca** chama `EconomyClockController.set_paused()`, evitando duplo estado divergente.
- **`Engine.time_scale`:** Nunca modificado por código de produção em `src/`; `D2SimulationPauseController` nunca altera `Engine.time_scale`.

### 4.2 Política Explícita de Propriedade e Contrato Cooperativo
Para atender integralmente a salvaguarda de preservação de pausas externas (evitando o erro de gravar/restaurar `get_tree().paused = not _reasons.is_empty()` indiscriminadamente), `D2SimulationPauseController` adota:
1. **Pilha idempotente de motivos da UI (`_reasons`):** Na `UI-1.1B`, apenas `REASON_HUD_PAUSE (&"hud_pause")` é conectado aos botões da placa; múltiplos motivos da UI podem coexistir sem perda de pausa prematura.
2. **Contrato Cooperativo de Leases em `SceneTree` (`dok_pause_authorities`):** API estática (`acquire_tree_pause_lease`, `release_tree_pause_lease`, `has_other_pause_leases`, `get_active_pause_leases`) que permite a futuras autoridades cooperativas e múltiplas instâncias compartilhar `SceneTree.paused` com segurança em qualquer ordem de liberação.
3. **Detecção e Proteção de Pausa Externa Não Gerenciada:** Se `SceneTree.paused == true` sem lease cooperativo prévio (ex.: depurador, harness ou subsistema externo gravando `get_tree().paused = true` diretamente), `_observed_unmanaged_external_pause = true` e `_owns_tree_pause = false`.
4. **Regra Estrita de `unpause` Seguro:** `D2SimulationPauseController` somente executa `tree.paused = false` quando **todas** as condições são simultaneamente verdadeiras: `_reasons.is_empty()`, `_owns_tree_pause == true`, `not _observed_unmanaged_external_pause` e `not has_other_pause_leases(tree, _owner_id)`. Caso contrário, **nunca** executa `unpause` destrutivo (nem via `1×`, nem via `unbind()`, nem em `_exit_tree()`).
5. **Observador Zero-Polling:** Filho interno `_TreePauseObserver` (`PROCESS_MODE_PAUSABLE`, `set_process(false)`) reage sincronamente a `NOTIFICATION_PAUSED` / `NOTIFICATION_UNPAUSED` para atualizar a trava da câmera e a placa superior sem polling por frame.

### 4.3 Achado Técnico Real Durante Testes de Integração (Travessia de Cliques Durante Pausa)
Nos primeiros testes de clique real (`vp.push_input()`) no botão `1×` com `SceneTree.paused == true`, descobriu-se que a Godot 4 verifica `Control::can_process()` **de cima para baixo** em `Viewport::_gui_find_control_at_pos()`. Como `D2HudRoot` herdava `PAUSABLE` de `UiLayer`/`Main`, o `Viewport` interrompia a busca antes de alcançar `D2TopPlaqueView` (`PROCESS_MODE_ALWAYS`).
- **Solução cirúrgica:** `D2HudRoot.process_mode = Node.PROCESS_MODE_ALWAYS` (mantendo `set_process(false)`, `set_physics_process(false)` e `MOUSE_FILTER_IGNORE`), `D2TopPlaqueView.process_mode = Node.PROCESS_MODE_ALWAYS`, e **`D2ResourceRocksView.process_mode = Node.PROCESS_MODE_PAUSABLE`**, preservando `UiLayer` e todas as HUDs legadas (`ResourceHud`, `ConstructionHud`, `BuildingInspectorPanel`) estritamente pausáveis.
- Adicionalmente, adicionou-se cache seguro `_cached_tree` / `_get_scene_tree()` em `D2SimulationPauseController` para eliminar erros `Parameter "data.tree" is null` quando `MainScene._exit_tree()` invoca `unbind()` após os filhos saírem da árvore.

---

## 5. Implementação C — Proteção Cirúrgica da Câmera (`RtsCameraRig`)

Em [`src/camera/rts_camera_rig.gd`](../../src/camera/rts_camera_rig.gd):
- **`set_input_locked(locked: bool)` / `is_input_locked()`:** Ao travar, zera `_pan_velocity_xz`, cancela `_is_dragging`, descarta `_pending_drag_pixels`, fixa `_target_distance = _current_distance` e impede qualquer deslocamento/zoom em `_unhandled_input()` e `step_camera()`. Ao destravar, reinicia `_last_tick_usec = Time.get_ticks_usec()` para garantir retomada suave sem salto brusco.
- **Correção da posição obsoleta do mouse (`_last_mouse_pos`):** O rastreamento de `InputEventMouseMotion` foi promovido para `_input(event)` (executado antes do consumo pela GUI), eliminando a retenção de coordenadas antigas de borda quando o ponteiro entra sobre uma pedra `MOUSE_FILTER_STOP`.
- **Edge Pan seletivo:** `_collect_pan_direction()` consulta `_is_pointer_over_blocking_gui(viewport)` via `viewport.gui_get_hovered_control()`, bloqueando Edge Pan exclusivamente quando o ponteiro repousa sobre uma superfície sólida visível da HUD e preservando Edge Pan nas bordas livres da janela e nas margens transparentes. WASD permanece plenamente funcional quando a câmera não está travada.
- **Retrocompatibilidade:** `tests/integration/test_camera_rig.gd` (`8/8`, incluindo `test_06` que testa câmera destravada sob pausa externa e `test_08` de Edge Pan) e `tests/unit/test_camera_math.gd` (`7/7`) passaram sem qualquer modificação.

---

## 6. Implementação D — Roteador Progressivo de `Esc` (`D2UiEscapeRouter`)

Em [`src/ui/d2/d2_ui_escape_router.gd`](../../src/ui/d2/d2_ui_escape_router.gd):
- Instanciado sob `D2HudRoot` em modo estritamente **pass-through** (`0` handlers ativos na `UI-1.1B`, `process_mode = PROCESS_MODE_ALWAYS`).
- Não chama `set_input_as_handled()` sem handler ativo, preservando integralmente:
  1. `ConstructionHud._input()` (fecha catálogo legado sem limpar seleção).
  2. `PlacementController.handle_unhandled_input()` (cancela posicionamento sem limpar seleção).
  3. `RtsInputController._unhandled_input()` (cancela drag ativo ou limpa seleção sem cancelamento duplo).
- Sob pausa ativa via `||`, pressionar `Esc` **não** abre menu fictício nem despausa indevidamente; a retomada permanece no botão `1×`.
- API pronta (`register_handler`, `unregister_handler`, prioridades `10/20/30/40/50/90`) para os incrementos futuros (`UI-1.3`, `UI-1.4`, `UI-1.5`).

---

## 7. Evidências de Testes Automatizados, Validação Estática e Regressão Integral

### 7.1 Validação Estática (`.\tools\validate.ps1`)
- **Resultado:** **`PASSED` — `0` erros, `0` avisos de tipagem estrita, `199` scripts GDScript verificados (`--check-only`), importação headless e boot de `main.tscn` aprovados.**

### 7.2 Suítes Focadas `UI-1.1B`, `UI-1.1A` e Câmera
- `tests/unit/test_ui_1_1b_polygon_and_pause.gd`: **4/4 aprovados (`131` asserções)** — geometria poligonal, padding, resize `1,00 ↔ 1,22`, todos os 6 cenários de propriedade/cooperação de pausa, honestidade visual de pausa externa na placa e contrato do roteador `Esc`.
- `tests/integration/test_ui_1_1b_hitboxes_and_pause.gd`: **5/5 aprovados (`127` asserções)** — executando sob economia real de produção **`use_provenance_economy = true`**:
  - `test_01_surface_hitboxes_clicks_scroll_edge_pan_and_resize` (`24` asserções): cliques LMB/RMB sobre pedras sólidas, passagem por sombra/chanfro/vão entre pedras, bloqueio de scroll na HUD vs mapa livre, bloqueio de Edge Pan na pedra vs borda livre, WASD funcional e resize `720p → 1080p → 720p`.
  - `test_02_real_pause_buttons_camera_lock_and_economy_clock` (`38` asserções): cliques reais (`vp.push_input`) repetidos em `||` e `1×` (inclusive clique real em `1×` com `SceneTree.paused == true`), trava absoluta da câmera (WASD, Edge Pan, Wheel, MMB Drag = `0,0`), congelamento de `EconomyClockController` e zero vazamento de clique direito/scroll nos botões.
  - `test_03_pause_during_gathering_transport_and_construction_with_provenance` (`38` asserções): pausa e retomada reais durante **coleta física/transporte de madeira** e durante **montagem ativa de `ConstructionSite`** sob `use_provenance_economy = true`, comprovando congelamento absoluto durante pausa, continuação íntegra após `1×`, **conservação exata de materiais** (`wood - 4`, `stone - 2`, `reserved == 0`, proveniência válida) e `preflight_economic_teardown()` + `request_controlled_teardown()` aprovados (`ok == true`).
  - `test_04_external_pause_preservation_scene_exit_and_reentry` (`8` asserções): preservação integral de pausa externa (incluindo `1×` desabilitado e saída de cena sob pausa externa) + reentrada limpa sem vazamento de estado.
  - `test_05_escape_router_passthrough_and_legacy_mode_intact` (`19` asserções): pass-through de `Esc` (catálogo, posicionamento, drag, seleção, pausa sem menu fictício) e modo legado `main.tscn` (`use_d2_2_hud = false`) 100% intacto.
- `tests/unit/test_ui_1_1a_foundation.gd` (`4/4`, `109` asserções) e `tests/integration/test_ui_1_1a_visual_data.gd` (`4/4`, `112` asserções): **100% aprovados**.
- `tests/unit/test_camera_math.gd` (`7/7`, `36` asserções) e `tests/integration/test_camera_rig.gd` (`8/8`, `277` asserções): **100% aprovados**.

### 7.3 Regressão Integral Completa (`.\tools\run_tests.ps1 -Segmented -MaxIntegrationPerGroup 1`)
Executada sem processos concorrentes e sem modificar o runner `tools/run_tests.ps1`:

| Métrica | Valor Medido |
|---|---|
| **Comando** | `.\tools\run_tests.ps1 -Segmented -MaxIntegrationPerGroup 1` |
| **Código de Saída (`$LASTEXITCODE`)** | **`0`** |
| **Lotes Disjuntos Concluídos** | **`58 / 58`** (`PASS unit` [24 suítes] + `PASS integration-01`..`57` [1 suíte/lote]) |
| **Suítes Descobertas e Executadas** | **`81 / 81`** (`+2` novas suítes UI-1.1B sobre as 79 da UI-1.1A) |
| **Testes Executados e Aprovados** | **`579 / 579`** (`+9` novos testes sobre os 570 da UI-1.1A) |
| **Falhas (`Failed`)** | **`0`** |
| **Erros de Suíte (`SuiteErrors`)** | **`0`** |
| **Timeouts** | **`0`** |
| **Avisos de Tipagem Estrita** | **`0`** |
| **Total de Asserções** | **`28.329`** |
| **Verificação de Cobertura (`Coverage Check`)** | `Discovered=81 \| ExecutedUnique=81 \| Duplicates=0 \| Missing=0` |
| **Tempo Acumulado Godot (`SumGodotElapsed`)** | `981.940,4 ms` (~`16,37 min`) |
| **Tempo Real de Parede (`TotalWallElapsed`)** | `1.032.517,7 ms` (~`17,21 min`) |

---

## 8. Validação Visual Real (VCG — Godot 4.7.2) e Protocolo de Teste Manual Interativo

### 8.1 Capturas Reais Publicadas (`Intel(R) UHD Graphics 620`, `OpenGL 3.3 Compatibility`)

| Evidência | Arquivo | Observação VCG |
|---|---|---|
| **UI-1.1B Canônica — `1280×720`** | [`G_ui_1_1b_sandbox_1280x720.png`](../design/ui-1-1b/G_ui_1_1b_sandbox_1280x720.png) | Escala `1,22×` limpa, zero clipping, `1×` ativo dourado, zero contornos QA. |
| **UI-1.1B Canônica — `1920×1080`** | [`G_ui_1_1b_sandbox_1920x1080.png`](../design/ui-1-1b/G_ui_1_1b_sandbox_1920x1080.png) | Escala `1,00×` fiel à D2.2, `DebugOverlay [F3]` deslocado abaixo das pedras. |
| **UI-1.1B Pausada (`||` ativo) — `1920×1080`** | [`G_ui_1_1b_paused_1920x1080.png`](../design/ui-1-1b/G_ui_1_1b_paused_1920x1080.png) | `||` iluminado em ouro kintsugi, `1×` pronto para retomar, `2×`/`4×`/`MENU` desabilitados. |
| **Recorte Placa Normal (`1080p`)** | [`G_ui_1_1b_plaque_running_1080p.png`](../design/ui-1-1b/G_ui_1_1b_plaque_running_1080p.png) | Estado normal com `1×` ativo e `● EXPOSTO` real. |
| **Recorte Placa Pausada (`1080p`)** | [`G_ui_1_1b_plaque_paused_1080p.png`](../design/ui-1-1b/G_ui_1_1b_plaque_paused_1080p.png) | Estado pausado real com `||` ativo. |
| **Comparação Canto Superior Esquerdo (D2.2 × UI-1.1B × QA)** | [`C_ui_1_1b_compare_top_left.png`](../design/ui-1-1b/C_ui_1_1b_compare_top_left.png) | Paridade visual exata das 3 pedras + contorno ciano acompanhando chanfros e vãos. |
| **Comparação Canto Superior Direito (D2.2 × Normal × Pausado × QA)** | [`C_ui_1_1b_compare_top_right.png`](../design/ui-1-1b/C_ui_1_1b_compare_top_right.png) | Cumeeira poligonal de 5 vértices + hitboxes verdes exatas em `||` e `1×`. |
| **QA Hitboxes Separado — `1920×1080`** | [`QA_ui_1_1b_hitboxes_overlay_1920x1080.png`](../design/ui-1-1b/QA_ui_1_1b_hitboxes_overlay_1920x1080.png) | Contornos desenhados exclusivamente pelo script externo de QA (ausentes no jogo real). |
| **QA Hitboxes Separado — `1280×720`** | [`QA_ui_1_1b_hitboxes_overlay_1280x720.png`](../design/ui-1-1b/QA_ui_1_1b_hitboxes_overlay_1280x720.png) | Alinhamento poligonal exato em escala `1,22×`. |
| **Modo Legado Intacto (`main.tscn`, `1280×720`)** | [`G_ui_1_1b_legacy_intact_1280x720.png`](../design/ui-1-1b/G_ui_1_1b_legacy_intact_1280x720.png) | HUD legada 100% preservada com `use_d2_2_hud = false`. |

- **Resultado do VCG:** **`APROVADO`** — Identidade D2.2 integralmente preservada (materiais, tipografia, proporções, espaçamentos e contraste WCAG), zero contornos de debug no jogo real, e alinhamento sub-pixel dos polígonos nas capturas de QA tanto em `720p` quanto em `1080p`.

### 8.2 Distinção de Status e Protocolo de Teste Manual pelo Proprietário
- **Testado automaticamente (eventos reais `vp.push_input` + economia real `use_provenance_economy = true`):** Todos os 10 cenários de superfície, 12 cenários de pausa/conservação e 7 cenários de `Esc`/legado (§7.2).
- **Testado visualmente ao vivo na Godot 4.7.2 (GPU real `gl_compatibility`):** Todas as capturas em `1280×720` e `1920×1080` (§8.1).
- **Teste manual interativo humano (pendente de execução pelo proprietário no editor/executável):** Para conferência interativa direta em `tests/visual/ui_1_d2_2_sandbox.tscn`:
  1. Selecionar um fundador e clicar com botão esquerdo e direito sobre as pedras sólidas (confirmar zero desseleção e zero ordem de movimento).
  2. Clicar no vão transparente entre as pedras e nos cantos chanfrados (confirmar passagem normal ao mundo 3D).
  3. Rolar a roda do mouse sobre pedra/placa (sem zoom) e sobre o gramado (zoom normal).
  4. Mover o cursor até a borda livre da janela (Edge Pan ativo) e sobre as pedras/placa (Edge Pan bloqueado; WASD normal).
  5. Ordenar coleta ou construção, clicar em `||` (simulação e câmera travam), tentar mover a câmera (imóvel), pressionar `Esc` (nenhum menu fictício abre), e clicar em `1×` (coleta/construção retoma sem perda de recursos).
  6. Abrir `Construir`, pressionar `Esc` (fecha catálogo), selecionar maquete, pressionar `Esc` (cancela posicionamento), selecionar unidade, pressionar `Esc` (limpa seleção).

---

## 9. Riscos, Limitações Residuais e Integridade dos Worktrees

- **Limitação arquitetural honesta de `SceneTree.paused` (Godot 4):** Caso um código externo futuro escreva `get_tree().paused = true` diretamente **enquanto** a HUD já mantém a árvore pausada, sem utilizar o contrato cooperativo `D2SimulationPauseController.acquire_tree_pause_lease()`, o booleano global único da Godot não oferece sinalização de escrita redundante. **Mitigação estabelecida:** qualquer subsistema futuro que pause a simulação deve utilizar a API cooperativa `acquire_tree_pause_lease` / `release_tree_pause_lease`. Pausas externas anteriores à HUD (gerenciadas ou não gerenciadas) já são 100% protegidas.
- **Limitações esperadas desta etapa:** `2×`, `4×`, `☰ MENU`, Estelas dos Fundadores (`UI-1.2`), Laje de Maquetes (`UI-1.3`), Monólito de Canteiro (`UI-1.4`) e Monólito de Menu/Pausa com preflight de saída (`UI-1.5`) permanecem fora do escopo da `UI-1.1B`.
- **Estado dos Worktrees e Branches:**
  - `C:\Projetos\Dawn_of_Kin_wt_ui_1_1b` (`feat/ui-1-1b-d2-interaction-pause`): branch candidata limpa e isolada, derivada de `a02aa97bb4358ccf0b78c9f35deab766bc21ff6e`.
  - `C:\Projetos\Dawn_of_Kin_wt_ui_1_1a` (`feat/ui-1-1a-d2-visual-foundation` @ `a02aa97`): 100% intocado.
  - `C:\Projetos\Dawn of Kin` (`review/t2-closeout-candidate`), `main`, GDD, Design System homologado e demais worktrees protegidos: 100% intocados.

---

## 10. Parada Obrigatória

A implementação **UI-1.1B** é submetida formalmente como **proposta candidata**, aguardando auditoria independente do ChatGPT e deliberação/homologação expressa do proprietário.

- **Merge:** não realizado.
- **Tag:** não criada.
- **Cutover (`use_d2_2_hud`):** permanece `false` em `src/main/main.tscn`.
- **UI-1.2 e etapas futuras:** não iniciadas.
