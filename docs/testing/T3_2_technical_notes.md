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
| [world_navigation.gd](file:///C:/Projetos/Dawn_of_Kin_wt_t3_2_placement/src/navigation/world_navigation.gd) | `CandidateSession` (`map_rid`, `region_rid`, `prepare_ms`, `server_sync_ms`, `dispose()`, limpeza em `NOTIFICATION_PREDELETE`, consultas topológicas), `AsyncBakeToken`, cache estático de geometria (`_cached_static_vertices` / `_cached_static_indices` reaproveitados via `append_arrays()`), `invalidate_static_geometry_cache()`, `has_static_geometry_cache()`, `get_navigation_revision()` (`_navigation_revision` incrementado em `request_rebake()`, conclusões/falhas de sincronização e invalidação de cache), callback estático via `WeakRef` com cancelamento de tokens ativos em `_exit_tree()`, `create_candidate_session()` e `create_candidate_session_async()`. |
| [world_picker.gd](file:///C:/Projetos/Dawn_of_Kin_wt_t3_2_placement/src/rts/world_picker.gd) | Adicionados `pick_terrain_at_screen_pos()` e `pick_terrain_along_ray()` restritos a `CollisionLayers.MASK_TERRAIN` (`collide_with_bodies = true`, `collide_with_areas = false`). |
| [ground_resource_pile.gd](file:///C:/Projetos/Dawn_of_Kin_wt_t3_2_placement/src/economy/ground_resource_pile.gd) | Registrado grupo `GROUP_GROUND_PILES = &"ground_resource_piles"` em `_ready()` para consulta dentro do escopo da região. |
| [placement_validator.gd](file:///C:/Projetos/Dawn_of_Kin_wt_t3_2_placement/src/buildings/placement_validator.gd) | Validação espacial contínua sem grid (`validate_hover` leve + `validate_confirm` / `validate_confirm_async`), `ValidationContext.from_region()` isolado por subárvore/mundo `world_3d` (sem varredura global no `SceneTree`), `ValidationContext.refresh_dynamic_state()` + `_revalidate_confirm_preconditions()` no fechamento assíncrono (revalidando estado atual da região e revisão/malha da navegação principal, com código `REASON_NAVIGATION_STALE` e descarte obrigatório da `CandidateSession`), além de breakdown de tempos em `ValidationResult` (`main_thread_usec`, `candidate_prepare_ms`, `candidate_sync_ms`, `connectivity_query_ms`). |
| [placement_preview.gd](file:///C:/Projetos/Dawn_of_Kin_wt_t3_2_placement/src/buildings/placement_preview.gd) | Prévia 3D discreta, sem colisão e sem sombras (`BasePad`, `BodyVolume`, `RoofVolume`, 4 bordas), estados verde/vermelho foscos e pulso temporário de confirmação (`0,75 s`). |
| [placement_controller.gd](file:///C:/Projetos/Dawn_of_Kin_wt_t3_2_placement/src/buildings/placement_controller.gd) | Orquestração do modo de posicionamento (`start_placement`, `cancel_placement`, projeção cursor/câmera, confirmação assíncrona LMB com `use_async_confirm`, `is_confirm_pending()`, proteção de cancelamento em voo por geração/token, cancelamento RMB/`Esc`, atualização periódica de hover a cada `0,12 s` e sinais `storage_changed`/`navigation_ready` mesmo com cursor e câmera parados). |
| [placement_test_overlay.gd](file:///C:/Projetos/Dawn_of_Kin_wt_t3_2_placement/src/buildings/placement_test_overlay.gd) | UI mínima declaradamente temporária da T3.2 (`Abrigo 4×4 [F6]`, `Depósito 5×4 [F7]`, `Cancelar` + banner de estado), sem `Tab`/foco residual e com `MOUSE_FILTER_IGNORE` em todos os contêineres/textos. |
| [rts_input_controller.gd](file:///C:/Projetos/Dawn_of_Kin_wt_t3_2_placement/src/rts/rts_input_controller.gd) & [main.gd](file:///C:/Projetos/Dawn_of_Kin_wt_t3_2_placement/src/main/main.gd) | Roteamento exclusivo de LMB/RMB/`Esc` durante prévia ativa mantendo `InputEventMouseMotion` e controles da `RtsCameraRig` (`WASD`, setas, MMB, scroll, edge scroll) intactos; `main.gd` passa `_units_root` explícito ao `PlacementController`. |

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
- **Durante confirmação (`validate_confirm` / `validate_confirm_async`):**
  1. Coleta pontos âncora atualmente alcançáveis (acampamento, unidades fora da área, fontes de recurso alcançáveis, checkpoints de região e sondas de corredor adjacentes) **antes** do bake candidato.
  2. Cria uma `CandidateSession` isolada em `NavigationServer3D` (`map_create` + `region_create` separados, sem afetar a cena ou `WorldNavigation`), reaproveitando o cache estático da região (`_cached_static_vertices` / `_cached_static_indices` copiados via `append_arrays()` em vez de re-parsear todos os colisores estáticos a cada clique) e injetando a caixa candidata via `NavigationMeshSourceGeometryData3D.add_faces(PackedVector3Array, Transform3D)` (evita leituras de mesh na GPU/warnings observados com `add_mesh()` e erros observados na Godot 4.7.2 ao usar `set_indices()`/`.duplicate()`).
  3. No caminho padrão do controlador (`use_async_confirm = true`), o bake Recast roda em worker thread via `NavigationServer3D.bake_from_source_geometry_data_async()`, com token/geração cancelável com segurança caso o jogador pressione `Esc`/RMB antes da conclusão (`is_confirm_pending()`).
  4. Valida perímetro alcançável e preservação de conectividade após a erosão por `agent_radius = 0,5 m`.
  5. Libera explicitamente `region_rid` e `map_rid` (`session.dispose()`) antes de retornar, independentemente de aprovação, rejeição ou cancelamento em voo.

### Medição Real na Placa Integrada (`Intel(R) UHD Graphics 620`, `gl_compatibility`, `1920x1080`, `vsync = disabled`)

Medido com [t3_2_placement_benchmark.gd](file:///C:/Projetos/Dawn_of_Kin_wt_t3_2_placement/tests/perf/t3_2_placement_benchmark.gd) (sem `--fixed-fps`), comparando a implementação inicial (`ec4a61f`) com a revisão **T3.2-R1** (`warmup + 32` confirmações por modo):

- **Baseline T3.2 antes da T3.2-R1 (`ec4a61f`, síncrono sem cache):**
  - **Hover (`120` amostras):** `p50 = 0,846 ms`, média `0,958 ms`, `p95 = 2,116 ms`, máximo `2,605 ms`; frametime durante hover: `p50 = 8,562 ms`, `p95 = 12,865 ms`.
  - **Confirmação síncrona (`15` amostras no `TestMap` `64×64 m`):** `candidate_bake p50 = 80,803 ms` (`p95 = 116,406 ms`); validação completa `validate_confirm p50 = 92,090 ms`, média `93,758 ms`, `p95 = 134,714 ms`, máximo `134,714 ms`.
- **Após T3.2-R1 (cache estático `append_arrays()` + `bake_from_source_geometry_data_async()`):**
  - **Hover (`120` amostras):** `p50 = 0,323 ms`, média `0,383 ms`, `p95 = 0,767 ms`, máximo `0,971 ms`; frametime durante hover (`120` amostras): `p50 = 7,702 ms`, média `7,816 ms`, `p95 = 11,355 ms`, máximo `13,950 ms`.
  - **Confirmação assíncrona — impacto na thread principal (`32` confirmações, `static_cache_active = true`):** `p50 = 6,908 ms`, média `7,033 ms`, `p95 = 14,979 ms`, máximo `16,898 ms` (redução de ~88,9% no `p95` da thread principal).
  - **Frametime da janela durante as `32` confirmações assíncronas (`296` quadros):** `p50 = 7,250 ms`, média `7,647 ms`, `p95 = 11,110 ms`, máximo `24,510 ms` (**0 quadros `> 100 ms` e `> 30 ms`**).
  - **Breakdown assíncrono (`32` amostras):** `prepare` (`p50 = 1,461 ms`, `p95 = 2,998 ms`, `max = 3,900 ms`), `worker_bake` em thread separada (`p50 = 55,040 ms`, `p95 = 117,668 ms`, `max = 152,970 ms`), `rid_sync` (`p50 = 0,428 ms`, `p95 = 1,209 ms`, `max = 1,524 ms`), `connectivity_queries` (`p50 = 2,590 ms`, `p95 = 7,353 ms`, `max = 8,434 ms`). Tempo de parede até concluir o callback (`async_confirm_wall_ms`): `p50 = 64,572 ms`, média `66,818 ms`, `p95 = 133,061 ms`, máximo `173,726 ms`.
  - **Fallback síncrono com cache (`use_async_confirm = false`, `32` confirmações):** `sync_cached_confirm_total_ms p50 = 44,869 ms`, média `38,264 ms`, `p95 = 49,516 ms`, máximo `50,851 ms` (`prepare p95 = 1,509 ms`, `bake p95 = 42,433 ms`, `rid_sync p95 = 0,643 ms`, `connectivity_queries p95 = 3,083 ms`).

### Revisão T3.2-R1 — Atualização Dinâmica com Cursor Parado e Isolamento por Região

- **Prévia com cursor e câmera parados:** `PlacementController._process()` agora reavalia periodicamente (`DYNAMIC_HOVER_REFRESH_INTERVAL_SEC = 0,12 s`) além de marcar `_world_dirty` em sinais `GroundPileManager.storage_changed` e `WorldNavigation.navigation_ready`, garantindo transição imediata verde ↔ vermelho quando trabalhadores, pilhas físicas ou recursos mudam no mundo com o mouse imóvel.
- **Isolamento por região:** `ValidationContext.from_region()` eliminou chamadas globais a `SceneTree.get_nodes_in_group(...)`, descobrindo recursos, pilhas, depósitos, obstáculos, zonas reservadas e unidades apenas dentro da região/contexto ativo (`region_root`, suporte ao irmão `Units` sob `MainScene` quando na mesma `World3D` via `_matches_world()`), prevenindo vazamento entre regiões paralelas ou `SubViewport`s isolados.

### Revisão T3.2-R2 — Revalidação de Estado na Confirmação Assíncrona (TOCTOU)

- **Condição de corrida identificada:** entre o início do bake assíncrono (`_prepare_confirm_job`) e o retorno do worker thread (`_complete_confirm_with_session` / `_apply_confirm_outcome`), unidades, pilhas físicas, recursos, obstáculos ou a própria `WorldNavigation` podiam mudar de estado. Como `_complete_confirm_with_session()` não revalidava o snapshot atual da região nem a revisão da navegação, uma confirmação atrasada poderia aprovar uma posição já ocupada ou topologicamente obsoleta.
- **Correção implementada (contrato concentrado em `PlacementValidator`):**
  1. `WorldNavigation` mantém `_navigation_revision` explícito (`get_navigation_revision()`), incrementado em `request_rebake()`, conclusão/falha de sincronização e `invalidate_static_geometry_cache()` (sem afetar o preenchimento preguiçoso inicial do cache estático).
  2. `ValidationContext` guarda referências opcionais do escopo (`region_root`, `units_root`, `piles_root`, flags `has_explicit_units`/`has_explicit_sources`) e expõe `refresh_dynamic_state()` para re-coletar unidades, pilhas e recursos reais presentes na região no instante do callback.
  3. Ao finalizar `validate_confirm_async()`, `_revalidate_confirm_preconditions()` verifica, **sem** executar outro bake síncrono completo na thread principal: (a) disponibilidade e prontidão da `WorldNavigation`, (b) igualdade de `get_navigation_revision()`, referência `navigation_mesh`, `has_static_geometry_cache()` e `region_bounds` em relação ao início (`REASON_NAVIGATION_STALE` em caso de alteração), e (c) `_validate_spatial_base()` sobre o `ValidationContext` atualizado (footprint, limites, terreno 3×3 e cota, `CampStorageZone` D6, recursos naturais, obstáculos, pilhas e unidades atuais). Em qualquer falha, `session.dispose()` é garantido imediatamente e `PlacementController._apply_confirm_outcome()` emite `placement_rejected`, mantém a prévia ativa em vermelho e nunca emite `placement_confirmed`.
- **Testes adicionados (Cenários A–E determinísticos):**
  - [test_t3_2_placement_validation.gd](file:///C:/Projetos/Dawn_of_Kin_wt_t3_2_placement/tests/unit/test_t3_2_placement_validation.gd) (`test_07_async_confirm_revalidation_scenarios_a_b_c_e`): valida diretamente o contrato de `PlacementValidator.validate_confirm_async()` nos cenários C (estável), A (trabalhador entra na footprint antes do callback), B (pilha física aparece antes do callback) e E1/E2 (invalidação do cache estático e `request_rebake()` durante a operação).
  - [test_t3_2_placement_flow.gd](file:///C:/Projetos/Dawn_of_Kin_wt_t3_2_placement/tests/integration/test_t3_2_placement_flow.gd) (`test_05_async_confirm_race_conditions_scenarios_a_to_e`): valida ponta a ponta em `PlacementController` + `MainScene` os cenários A, B, E, D1/D2/D3 (cancelamento por RMB durante o bake sem reabrir prévia, troca de edifício `F6 -> F7`, guarda contra cliques duplicados e `queue_free()` do controlador em voo) e C (aprovação normal quando estável).
- **Medições atualizadas após T3.2-R2 (`Intel(R) UHD Graphics 620`, `gl_compatibility`, `1920x1080`, `vsync = disabled`, warmup + `32` confirmações):**
  - **Hover (`120` amostras):** `p50 = 0,770 ms`, média `0,947 ms`, `p95 = 2,123 ms`, máximo `3,014 ms`; frametime durante hover: `p50 = 8,355 ms`, `p95 = 13,767 ms`, máximo `22,587 ms`.
  - **Confirmação assíncrona na thread principal com revalidação completa (`32` confirmações, `static_cache_active = true`):** `p50 = 13,554 ms`, média `13,052 ms`, `p95 = 21,925 ms`, máximo `21,952 ms` (frente à T3.2-R1 `p50 = 6,908 ms`, `p95 = 14,979 ms` e muito abaixo do baseline síncrono `ec4a61f` `p50 = 92,090 ms`, `p95 = 134,714 ms`).
  - **Frametime da janela durante as `32` confirmações assíncronas (`473` quadros):** `p50 = 6,870 ms`, média `7,675 ms`, `p95 = 15,891 ms`, máximo `24,597 ms` (**0 quadros `> 30 ms` ou `> 100 ms`**).
  - **Breakdown assíncrono (`32` amostras):** `prepare` (`p50 = 1,803 ms`, `p95 = 2,704 ms`, `max = 3,164 ms`), `worker_bake` (`p50 = 89,990 ms`, `p95 = 163,010 ms`, `max = 180,844 ms`), `rid_sync` (`p50 = 0,832 ms`, `p95 = 1,614 ms`, `max = 1,643 ms`), `connectivity_queries` (`p50 = 4,255 ms`, `p95 = 8,864 ms`, `max = 9,477 ms`); tempo total de parede (`async_confirm_wall_ms`): `p50 = 106,404 ms`, média `108,317 ms`, `p95 = 185,980 ms`, máximo `192,434 ms`.
  - **Fallback síncrono com cache na mesma execução (`use_async_confirm = false`, `32` confirmações):** `sync_cached_confirm_total_ms p50 = 79,437 ms`, média `71,270 ms`, `p95 = 116,314 ms`, máximo `138,759 ms`.

**Limitações conhecidas registradas:**
1. No modo assíncrono padrão, há latência de parede de ~`106–186 ms` (`p50–p95` no estado térmico/energia medido; `~56–120 ms` observado anteriormente) até a resposta do worker thread; durante essa janela `is_confirm_pending()` bloqueia confirmações duplicadas, aceita cancelamento imediato por `Esc`/RMB ou troca de edifício e, se o mundo ou navegação mudar no intervalo, rejeita com segurança sem re-executar bake síncrono.
2. Caso um chamador opte explicitamente pelo modo síncrono (`validate_confirm()` ou `use_async_confirm = false`), ainda ocorre bake síncrono de ~`79–139 ms` (`~37–49 ms` em clock cheio) no `TestMap` (`64×64 m`).
3. A checagem de obsolescência da navegação depende das mutações de revisão expostas por `WorldNavigation` (`request_rebake()`, sincronização e invalidação de cache estático) e de comparações diretas sobre `navigation_mesh` e `region_bounds` — assumindo que ninguém edite o mapa de navegação ativo contornando a API de `WorldNavigation`.
4. Se mapas futuros crescerem muito além de `64×64 m` (T4/T5), continuará recomendável avaliar particionamento regional ou `filter_baking_aabb` para reduzir também o tempo de parede do worker thread.

---

## 4. Diferença Explícita entre T3.2 (Atual) e T3.3 (Futura)

- **Entregue na T3.2:** confirmação valida todas as restrições espaciais + NavMesh candidata e emite `placement_confirmed`, exibe pulso visual temporário e toast de texto, encerrando o modo de posicionamento **sem** efeito persistente no mundo ou na economia.
- **Reservado à T3.3+ (não implementado):** instanciação de `ConstructionSite`, gravação do edifício na `WorldNavigation` ativa, reserva/consumo de estoque no `SettlementInventory`, criação de ordem de construção e persistência em disco.
