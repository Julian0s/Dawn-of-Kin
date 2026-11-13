# Dawn of Kin — Arquitetura da T1 (Fundação RTS)

Documento de referência arquitetural do marco **T1 — Fundação RTS** (`Godot 4.7.2`, `gl_compatibility`, `Jolt Physics`, GDScript tipado, sem autoloads globais).

---

## 1. Princípios Estruturais

- **Separação de responsabilidades:** Nenhum "god script"; entrada, seleção, planejamento de grupo, comandos, câmera, navegação, movimento e ordens vivem em classes focadas.
- **Composição por nós e `RefCounted`:**
  - Sistemas de geometria pura e estado lógico (`CameraMath`, `SelectionBoxMath`, `GroupMovePlanner`, `WorldPicker`, `PickResult`, `UnitOrder`, `MoveOrder`) são `RefCounted` testáveis isoladamente.
  - Controladores de cena (`RtsCameraRig`, `SelectionManager`, `RtsInputController`, `CommandController`, `WorldNavigation`, `Unit`, `UnitMovement`) operam sobre sinais e dependências explícitas injetadas por [main.gd](file:///c:/Projetos/Dawn%20of%20Kin/src/main/main.gd).
- **Camadas de física centralizadas:** Definidas em [collision_layers.gd](file:///c:/Projetos/Dawn%20of%20Kin/src/core/collision_layers.gd):
  - `LAYER_TERRAIN` (`1`), `LAYER_OBSTACLES` (`2`), `LAYER_UNITS` (`3`), `LAYER_SELECTION` (`4`), além de camadas reservadas para T2 (`LAYER_RESOURCES`) e T3 (`LAYER_BUILDINGS`).
- **Ações de entrada centralizadas:** Mapeadas em [input_actions.gd](file:///c:/Projetos/Dawn%20of%20Kin/src/core/input_actions.gd) (`select`, `command`, `selection_modifier`, `clear_selection`, `camera_pan_*`, `camera_drag`, `camera_zoom_*`, `toggle_debug_overlay`).

---

## 2. Composição da Cena Principal (`src/main/main.tscn`)

[main.gd](file:///c:/Projetos/Dawn%20of%20Kin/src/main/main.gd) instancia e conecta:
- `TestMap` (`levels/test_map/test_map.tscn`) e seu nó `WorldNavigation` (com `DirectionalLight3D` em modo ortogonal `SHADOW_ORTHOGONAL`, `directional_shadow_max_distance = 75.0`, atlas `2048x2048` em `project.godot` e `Ground.cast_shadow = OFF` para otimização de fill-rate mantendo sombras nas demais geometrias)
- `RtsCameraRig` (`src/camera/rts_camera_rig.tscn`)
- Os dois protagonistas iniciais (`LeaderA` e `LeaderB`) com `CharacterDefinition` distintas (`data/characters/leader_a.tres`, `leader_b.tres`)
- `SelectionManager` (`src/rts/selection_manager.gd`)
- `CommandController` (`src/rts/command_controller.gd`)
- `DestinationMarker` (`src/rts/destination_marker.gd`)
- `RtsInputController` (`src/rts/rts_input_controller.gd`)
- `SelectionBoxOverlay` (`src/ui/selection_box_overlay.gd`) e `DebugOverlay` (`src/ui/debug_overlay.gd`)

---

## 3. Subsistemas da T1

### 3.1 Câmera Isométrica RTS
- **Arquivos:** [rts_camera_rig.gd](file:///c:/Projetos/Dawn%20of%20Kin/src/camera/rts_camera_rig.gd), [camera_math.gd](file:///c:/Projetos/Dawn%20of%20Kin/src/camera/camera_math.gd)
- **Responsabilidades:**
  - Hierarquia `FocusPivot` → `YawPivot` (`-45°`) → `PitchPivot` (`-48°`) → `Camera3D` em projeção perspectiva (`FOV 42°`).
  - Pan por teclado (WASD/Setas), arraste com botão do meio e Edge Scrolling (margem base de `6 px` físicos ajustada por DPI/viewport).
  - Zoom suave exponencial entre limites configurados, com velocidade de pan proporcional à distância de zoom e uso de `delta` real de processo (independente de `Engine.time_scale` e FPS).
  - Contenção estrita do ponto focal dentro de `map_bounds` do `TestMap`.

### 3.2 Picking e Seleção (Individual e por Caixa)
- **Arquivos:** [world_picker.gd](file:///c:/Projetos/Dawn%20of%20Kin/src/rts/world_picker.gd), [pick_result.gd](file:///c:/Projetos/Dawn%20of%20Kin/src/rts/pick_result.gd), [selection_manager.gd](file:///c:/Projetos/Dawn%20of%20Kin/src/rts/selection_manager.gd), [selection_box_math.gd](file:///c:/Projetos/Dawn%20of%20Kin/src/rts/selection_box_math.gd), [rts_input_controller.gd](file:///c:/Projetos/Dawn%20of%20Kin/src/rts/rts_input_controller.gd), [selection_indicator.gd](file:///c:/Projetos/Dawn%20of%20Kin/src/units/selection_indicator.gd), [selection_box_overlay.gd](file:///c:/Projetos/Dawn%20of%20Kin/src/ui/selection_box_overlay.gd)
- **Responsabilidades:**
  - `WorldPicker` converte coordenadas de tela em `PickResult` (`UNIT`, `GROUND`, `OBSTACLE`, `NONE`) via raycasts físicos respeitando oclusão por terreno/obstáculos.
  - `RtsInputController` diferencia clique vs arraste usando limiar escalado por DPI (`SelectionManager.get_drag_threshold_px()`), coordena hover independente da seleção, seleção por caixa (em 4 direções com `Shift` aditivo), e cancelamento via `Esc` ou perda de foco.
  - `SelectionManager` mantém lista deduplicada de unidades selecionadas e limpa referências ao saírem da árvore (`tree_exited`).

### 3.3 Navegação e Mapa de Testes
- **Arquivos:** [world_navigation.gd](file:///c:/Projetos/Dawn%20of%20Kin/src/navigation/world_navigation.gd), [test_map.gd](file:///c:/Projetos/Dawn%20of%20Kin/levels/test_map/test_map.gd)
- **Responsabilidades:**
  - `WorldNavigation` (`NavigationRegion3D`) faz bake da `NavigationMesh` a partir dos colisores em `LAYER_TERRAIN` e `LAYER_OBSTACLES`, aguarda sincronização assíncrona com o `NavigationServer3D` e emite `navigation_ready`.
  - Expõe `find_path(...)`, `is_position_reachable(...)` e `resolve_reachable_target(...)` diferenciando caminhos válidos (`OK`), alvos desconectados/bloqueados (`PARTIAL_UNREACHABLE`, ex.: interior do `ClosedEnclosure`) e consultas inválidas.

### 3.4 Planejamento de Grupo, Comandos e Ordens
- **Arquivos:** [command_controller.gd](file:///c:/Projetos/Dawn%20of%20Kin/src/rts/command_controller.gd), [group_move_planner.gd](file:///c:/Projetos/Dawn%20of%20Kin/src/rts/group_move_planner.gd), [destination_marker.gd](file:///c:/Projetos/Dawn%20of%20Kin/src/rts/destination_marker.gd), [unit_order.gd](file:///c:/Projetos/Dawn%20of%20Kin/src/units/orders/unit_order.gd), [move_order.gd](file:///c:/Projetos/Dawn%20of%20Kin/src/units/orders/move_order.gd)
- **Responsabilidades:**
  - `CommandController` recebe clique direito contextual (`PickResult`), coleta posições ocupadas/reservadas pelas unidades não comandadas (`_collect_occupied_positions`) e delega o cálculo de alvos ao `GroupMovePlanner`.
  - `GroupMovePlanner` gera slots concêntricos não sobrepostos filtrados por alcance/snap na navmesh, evita cruzamento na atribuição (`assign_slots_minimum_distance`) e desvia ordens individuais sobre slots ocupados/reservados marcando `adjusted_for_occupancy = true`, preservando o contrato de inalcançabilidade (`requested_target_reachable = false`) para áreas desconectadas.
  - `Unit` executa uma ordem ativa por vez (`UnitOrder` / `MoveOrder`) com ciclo `PENDING → RUNNING → SUCCEEDED / FAILED / CANCELLED`, emitindo `order_finished`.

### 3.5 Movimento e Evasão Dinâmica (RVO)
- **Arquivos:** [unit.gd](file:///c:/Projetos/Dawn%20of%20Kin/src/units/unit.gd), [unit_movement.gd](file:///c:/Projetos/Dawn%20of%20Kin/src/units/unit_movement.gd)
- **Responsabilidades:**
  - `UnitMovement` (`CharacterBody3D` + `NavigationAgent3D`) controla aceleração, rotação suave no plano XZ, gravidade, recuperação de bloqueio dinâmico (`STUCK_WINDOW_SEC = 1.5 s`, `MAX_REPATH_ATTEMPTS = 1`) e um único `move_and_slide()` por frame de física.
  - RVO 2D (`use_3d_avoidance = false`, `radius = 0.5 m`, `neighbor_distance = 3.5 m`, `max_neighbors = 8`, `time_horizon_agents = 0.8 s`) via sinal `velocity_computed`:
    - Unidades em movimento usam prioridade `0.5`; unidades em `IDLE` usam prioridade `1.0` com velocidade solicitada `Vector3.ZERO` para permanecerem imóveis enquanto unidades ativas desviam.
    - `_clamp_avoidance_to_navmesh` impede que desvios laterais empurrem a unidade para fora das bordas de rampas ou platôs.
