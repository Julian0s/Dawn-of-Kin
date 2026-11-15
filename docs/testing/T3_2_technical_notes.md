# Notas Técnicas — T3.2 (Validação Espacial, Área Reservada e Prévia sem Grid)

**Branch:** `feature/t3-2-placement`<br>
**Base:** `main` (`ceb3f7194a750e66dbf73ebb0b0a7460d51eb87f`)<br>
**Engine / Renderer:** Godot `4.7.2.stable` / `gl_compatibility`<br>
**Status:** Implementado e validado automaticamente na T3.2; aguardando testes manuais e aceite do proprietário (T3.3+ não iniciada).

---

## 1. Arquitetura Implementada

| Módulo | Responsabilidade |
|---|---|
| [building_definition.gd](file:///C:/Projetos/Dawn_of_Kin_wt_t3_2_placement/src/buildings/building_definition.gd) | Recurso de definição (`definition_id`, `display_name`, `footprint_size`, `visual_height`, `costs`, `build_work_required_sec`, `max_builders`, `storage_capacities`) e cálculos de retângulo/AABB e offsets de perímetro. Na T3.2, custos, tempos, construtores e capacidades atuam exclusivamente como metadados. |
| `data/buildings/shelter_basic.tres` | `shelter_basic` (`"Abrigo Básico"`), `4,0 × 4,0 m`, altura visual `3,0 m`, metadados provisórios `wood=12, stone=6`, `30,0 s`, `max_builders=2`. |
| `data/buildings/storage_depot.tres` | `storage_depot` (`"Depósito Rústico"`), `5,0 × 4,0 m`, altura visual `2,8 m`, metadados provisórios `wood=18, stone=10`, `45,0 s`, `max_builders=2`, `wood=50, stone=50, food=30`. |
| [collision_layers.gd](file:///C:/Projetos/Dawn_of_Kin_wt_t3_2_placement/src/core/collision_layers.gd) | Adicionada `MASK_NAV_STATIC = MASK_TERRAIN \| MASK_OBSTACLES \| MASK_BUILDINGS` para que a malha navegável da região ignore `ResourceSource` sem depender de hacks de camada. |
| [world_navigation.gd](file:///C:/Projetos/Dawn_of_Kin_wt_t3_2_placement/src/navigation/world_navigation.gd) | Adicionada `CandidateSession` (`map_rid`, `region_rid`, `dispose()`, limpeza defensiva em `NOTIFICATION_PREDELETE`, `snap_to_navmesh`, `find_path`, `is_position_reachable`, `get_bake_metrics`), `get_map_bounds()`, `query_path_on_map()` e `create_candidate_session(candidate_boxes)`. |
| [world_picker.gd](file:///C:/Projetos/Dawn_of_Kin_wt_t3_2_placement/src/rts/world_picker.gd) | Adicionados `pick_terrain_at_screen_pos()` e `pick_terrain_along_ray()` restritos a `CollisionLayers.MASK_TERRAIN` (`collide_with_bodies = true`, `collide_with_areas = false`). |
| [ground_resource_pile.gd](file:///C:/Projetos/Dawn_of_Kin_wt_t3_2_placement/src/economy/ground_resource_pile.gd) | Registrado grupo `GROUP_GROUND_PILES = &"ground_resource_piles"` em `_ready()` para detecção uniforme de pilhas físicas dentro ou fora de `CampStorageZone`. |
| [placement_validator.gd](file:///C:/Projetos/Dawn_of_Kin_wt_t3_2_placement/src/buildings/placement_validator.gd) | Validação espacial contínua sem grid (`validate_hover` leve + `validate_confirm` com `CandidateSession`), reutilizando shapes e queries pré-alocados. |
| [placement_preview.gd](file:///C:/Projetos/Dawn_of_Kin_wt_t3_2_placement/src/buildings/placement_preview.gd) | Prévia 3D discreta, sem colisão e sem sombras (`BasePad`, `BodyVolume`, `RoofVolume`, 4 bordas), estados verde/vermelho foscos e pulso temporário de confirmação (`0,75 s`). |
| [placement_controller.gd](file:///C:/Projetos/Dawn_of_Kin_wt_t3_2_placement/src/buildings/placement_controller.gd) | Orquestração do modo de posicionamento (`start_placement`, `cancel_placement`, projeção cursor/câmera, confirmação LMB, cancelamento RMB/Esc). |
| [placement_test_overlay.gd](file:///C:/Projetos/Dawn_of_Kin_wt_t3_2_placement/src/buildings/placement_test_overlay.gd) | UI mínima declaradamente temporária da T3.2 (`Abrigo 4×4 [F6]`, `Depósito 5×4 [F7]`, `Cancelar` + banner de estado), sem `Tab`/foco residual e com `MOUSE_FILTER_IGNORE` em todos os contêineres/textos. |
| [rts_input_controller.gd](file:///C:/Projetos/Dawn_of_Kin_wt_t3_2_placement/src/rts/rts_input_controller.gd) & [main.gd](file:///C:/Projetos/Dawn_of_Kin_wt_t3_2_placement/src/main/main.gd) | Roteamento exclusivo de LMB/RMB/`Esc` durante prévia ativa mantendo `InputEventMouseMotion` e controles da `RtsCameraRig` (`WASD`, setas, MMB, scroll, edge scroll) intactos. |

---

## 2. Parâmetros Espaciais Provisórios (`PlacementValidator`)

Calibrados na T3.2 para Godot `4.7.2` + `TestMap` (`agent_radius = 0,5 m`):

- `MAX_TERRAIN_SLOPE_DEG = 10.0` — declive máximo permitido nos 9 pontos (grade 3×3) amostrados sobre a área da pegada.
- `MAX_TERRAIN_HEIGHT_DELTA_M = 0.35` — variação máxima de elevação entre os 9 pontos do terreno sob a pegada.
- `CENTER_NAV_SNAP_MAX_XZ_M = 0.75`, `CENTER_NAV_SNAP_MAX_Y_M = 0.65` — tolerância de aderência do centro à malha navegável ativa.
- `PERIMETER_ACCESS_OFFSET_M = 0.85` — afastamento externo para pontos de acesso de trabalho ao redor do perímetro.
- `MIN_ACCESSIBLE_PERIMETER_POINTS = 2` — mínimo de pontos alcançáveis no perímetro de montagem.
- `CORRIDOR_PROBE_OFFSET_M = 1.35` — sondas externas de passagem testadas antes e depois do bake candidato para evitar bloqueio de corredores/acessos.
- `PILE_FOOTPRINT_RADIUS_M = 0.55` — raio de ocupação considerado para cada `GroundResourcePile`.
- `CampStorageZone` (D6): verificação dinâmica pelo `get_anchor_position()` e `zone_bounds_half_extents` reais da instância ativa na região (funciona também quando `camp_storage_zone == null`). Motivo emitido: `"Posição inválida: área reservada para pilhas do acampamento."`.

Ordem de checagem espacial em `_validate_spatial_base`: entradas finitas e nav pronta → limites da região → amostragem 3×3 do terreno → zona reservada do acampamento (D6) → recursos naturais → obstáculos/construções → pilhas físicas → unidades → compatibilidade central na NavMesh ativa. Checar recursos e obstáculos antes da distância de snap à NavMesh garante diagnóstico específico mesmo sobre o "buraco" erodido ao redor de árvores/muros.

---

## 3. NavMesh Candidata Isolada vs. Hover em Tempo Real

- **Durante hover (`validate_hover`):** executa apenas física 3D + consultas baratas na `WorldNavigation` ativa, encerrando a verificação de perímetro assim que atinge `MIN_ACCESSIBLE_PERIMETER_POINTS` (2). **Não** executa rebake nem modifica a navegação ativa.
- **Durante confirmação (`validate_confirm`):**
  1. Coleta pontos âncora atualmente alcançáveis (acampamento, unidades fora da área, fontes de recurso alcançáveis, checkpoints de região e sondas de corredor adjacentes) **antes** do bake candidato.
  2. Cria uma `CandidateSession` isolada em `NavigationServer3D` (`map_create` + `region_create` síncronos, sem afetar a cena ou `WorldNavigation`), parseando a geometria estática e injetando a caixa candidata via `NavigationMeshSourceGeometryData3D.add_faces(PackedVector3Array, Transform3D)` (evita leituras de mesh na GPU/warnings observados com `add_mesh()`).
  3. Valida perímetro alcançável e preservação de conectividade após a erosão por `agent_radius = 0,5 m`.
  4. Libera explicitamente `region_rid` e `map_rid` (`session.dispose()`) antes de retornar, independentemente de aprovação ou rejeição.

### Medição Real na Placa Integrada (`Intel UHD Graphics 620`, `gl_compatibility`, `1920x1080`, `vsync = disabled`)

Medido com [t3_2_placement_benchmark.gd](file:///C:/Projetos/Dawn_of_Kin_wt_t3_2_placement/tests/perf/t3_2_placement_benchmark.gd) (sem `--fixed-fps`):
- **Hover (`120` amostras em posições válidas e inválidas):** `p50 = 0,846 ms`, média `0,958 ms`, `p95 = 2,116 ms`, máximo `2,605 ms`; frametime da janela durante hover contínuo: `p50 = 8,562 ms`, `p95 = 12,865 ms`.
- **Confirmação com bake candidato isolado (`15` amostras no `TestMap` `64×64 m`, `cell_size = 0,25`):** `candidate_bake p50 = 80,803 ms` (média `81,097 ms`, `p95 = 116,406 ms`); validação completa `validate_confirm p50 = 92,090 ms` (média `93,758 ms`, `p95 = 134,714 ms`, máximo `134,714 ms`).

**Limitação conhecida registrada:** como o bake candidato síncrono cobre toda a `TestMap` (`64×64 m`), há uma pausa pontual de ~87–135 ms apenas no clique de confirmação em hardware integrado. Se mapas futuros crescerem muito além de `64×64 m` (T4/T5), será recomendável avaliar particionamento regional/local ou recorte por `filter_baking_aabb` antes de escalar o tamanho da região.

---

## 4. Diferença Explícita entre T3.2 (Atual) e T3.3 (Futura)

- **Entregue na T3.2:** confirmação valida todas as restrições espaciais + NavMesh candidata e emite `placement_confirmed`, exibe pulso visual temporário e toast de texto, encerrando o modo de posicionamento **sem** efeito persistente no mundo ou na economia.
- **Reservado à T3.3+ (não implementado):** instanciação de `ConstructionSite`, gravação do edifício na `WorldNavigation` ativa, reserva/consumo de estoque no `SettlementInventory`, criação de ordem de construção e persistência em disco.
