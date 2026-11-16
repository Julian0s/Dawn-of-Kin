# Dawn of Kin — Notas Técnicas da Etapa T3.3 (Canteiro de Obra e Suprimento Físico)

- **Etapa:** T3.3 — Canteiro de Obra e Suprimento Físico (Transporte)
- **Branch de Implementação:** `feature/t3-3-construction-logistics`
- **Base:** `origin/main` (`931ad196346251e3f24a3ea5db6facb3641233bc`, T3.1 e T3.2 integradas)
- **Engine / Renderer:** Godot `4.7.2.stable`, `gl_compatibility`
- **Estado:** T3.3 implementada (`R1`, `R2`, `UX`); **adendo consolidado em 16/11/2026:** **10/10 testes manuais aprovados pelo proprietário** ([T3_3_manual_test_protocol.md](T3_3_manual_test_protocol.md)); **homologação formal pendente, sem integração à `main` e T3.4 não iniciada** (ver [T3_3_closeout_CANDIDATE.md](T3_3_closeout_CANDIDATE.md)). *Nota: as seções 3–7 abaixo preservam os registros históricos de cada rodada.*

---

## 1. Escopo Entregue vs. Fronteiras Estritas (T3.4–T3.8)

### Implementado na T3.3
- Criação transacional de canteiro (`ConstructionSite`) imediatamente após confirmação válida do posicionamento, com reserva atômica (`reserve_batch`) no estoque físico do assentamento e rollback garantido (`release_batch`) em caso de falha pós-reserva.
- Retirada física direcionada à pilha específica (`pile_id`) visitada pelo trabalhador, respeitando o identificador de reserva do canteiro e a capacidade/peso da mochila (`UnitCarryLoad`), com desaceleração proporcional de movimento sob carga.
- Transporte físico, descarregamento no perímetro do canteiro para o buffer de obra (`delivered_buffer`), atualização viva da contabilidade (`required`, `reserved_in_piles`, `in_transit`, `delivered_buffer`, `missing`) e proteção contra duplo saque ou overflow de entrega.
- Tratamento conforme política aprovada (**Alternativa B — Perda Direta**) quando pilhas reservadas sofrem deterioração (`reservation_lost_to_decay`): não há realocação automática nem fabricação de recursos; o déficit passa a constar como faltante (`missing`).
- Organização de trabalhadores segundo **D9** (máximo de construtores simultâneos `max_builders = 2`): 1 trabalhador atua como `SOLO_SUPPLIER`; 2 trabalhadores atuam como 1 `TRANSPORTER` + 1 `BUILDER` em espera no perímetro; 3 trabalhadores atuam como 1 `TRANSPORTER` + 2 `BUILDER`; 4º trabalhador excedente é rejeitado pelo canteiro (`REASON_NO_WORKER_SLOT`), e se o transportador sair enquanto ainda houver suprimento pendente, um construtor é promovido automaticamente a `TRANSPORTER`.
- Planejamento de slots e isolamento por `World3D` (`BuildSlotPlanner`), incluindo verificação de conectividade da origem do trabalhador com a malha navegável (`_is_unit_connected_to_path`).
- Picking RTS de canteiro (`PickResult.Kind.CONSTRUCTION_SITE` via `CollisionLayers.MASK_BUILDINGS`), designação por clique direito ou pelo painel provisório (`TemporarySitePanel` em `PlacementTestOverlay`), e bloqueio de sobreposição contra canteiros existentes em `PlacementValidator`.

### Explicitamente fora de escopo (não implementado nesta etapa)
- **T3.4:** Consumo do buffer entregue em progresso de montagem, transmutação para edifício concluído, `BuildSlotPlanner` de construção ativa e rebake na `WorldNavigation` ativa após conclusão.
- **T3.5:** Catálogo definitivo e inspetor final de construções.
- **T3.6:** Cancelamento de canteiro e reembolso/restituição de buffer.
- **T3.7:** Armazenamento em depósito físico construído.
- **T3.8:** Persistência/save-load.

---

## 2. Arquitetura e Contratos dos Módulos

### 2.1 Economia e Saque Físico Direcionado
- `src/economy/ground_pile_manager.gd`:
  - `get_pile_world_position(pile)`: calcula a posição global real da pilha no mundo.
  - `get_reserved_pile_entries(reservation_id, resource_id, reference_pos)`: lista as pilhas que ainda mantêm unidades reservadas para o `reservation_id`, ordenadas por distância até `reference_pos`.
  - `withdraw_reserved_from_pile(pile_id, reservation_id, resource_id, amount)`: debita estritamente a `pile_id` específica visitada pelo trabalhador e confirma via `_commit_withdraw_plan(...)` com snapshot/rollback atômico.
- `src/economy/settlement_inventory.gd`:
  - `get_reserved_pile_entries(...)`: delega a consulta ao backend de armazenamento quando disponível.
  - `withdraw_reserved_from_pile_to_carry_load(pile_id, reservation_id, resource_def, requested_amount, carry_load) -> int`: guarda contra reentrância (`_is_delivering`), valida espaço livre via `carry_load.get_max_additional_units(resource_def)` e `carry_load.add_units(...)`, e restaura snapshot da mochila em caso de falha na retirada física da pilha.

### 2.2 Núcleo de Canteiros e Planejamento Espacial
- `src/buildings/construction_site.gd` (`ConstructionSite`):
  - Node3D modular em grupo `construction_sites`, com colisor `SiteBody` (`StaticBody3D`) apenas na camada `CollisionLayers.MASK_BUILDINGS` (não entra na máscara `MASK_WORLD_SOLID` de movimento das unidades nem dispara rebake ativo da T3.4) e malha discreta `FoundationVisual` com `CAST_SHADOW_OFF`.
  - Contabilidade por recurso: `_required_amounts`, `_delivered_buffer`, `_pending_pickups` (reivindicações de coleta em andamento por trabalhador/pilha), `_transit_claims` (carga já retirada da pilha com destino ao canteiro), `_assigned_workers` e papéis D9 (`WorkerRole.UNASSIGNED`, `SOLO_SUPPLIER`, `TRANSPORTER`, `BUILDER`).
  - `accept_delivery_from_carry_load(...)`: aceita unidades da mochila limitadas pelo déficit restante de entrega (`get_remaining_need_for_dropoff`), evitando overflow ou dupla contagem em múltiplas chamadas, e emite `supply_completed` apenas quando todos os custos atingem 100% no buffer (sem iniciar montagem).
  - Conexão ao sinal `reservation_lost_to_decay` do `SettlementInventory`: emite `reservation_lost` / `state_changed` sem realocar outras pilhas.
- `src/buildings/build_slot_planner.gd` (`BuildSlotPlanner`):
  - `collect_other_unit_positions(...)`: varredura isolada por `World3D` (`units` no mesmo `world_3d`).
  - `find_best_pickup_candidate(...)`: escolhe recurso faltante ainda não reivindicado (`claimable_for_site`), dentro do espaço de carga da unidade, na pilha reservada alcançável mais próxima.
  - `compute_pile_approach_slot(...)` e `compute_site_perimeter_slot(...)`: calculam posições no navmesh respeitando tolerância de alcance, separação mínima entre trabalhadores e validação de conectividade da posição inicial do trabalhador (`_is_unit_connected_to_path`, que rejeita casos fora do navmesh ou isolados atrás de paredes de `CollisionLayers.MASK_OBSTACLES`).
- `src/buildings/construction_manager.gd` (`ConstructionManager`):
  - `try_create_site_from_placement(definition, world_position)`: rejeita sobreposição com canteiros existentes, sobreposição com a `CampStorageZone` (D6) e falta de estoque livre; executa `reserve_batch(...)` com `reservation_id` monotônico; instancia `ConstructionSite` (permitindo `site_creator_override` em testes determinísticos) e executa `release_batch(...)` se qualquer etapa pós-reserva falhar.

### 2.3 Ordem de Construção, Controle RTS e UI Provisória
- `src/units/orders/construct_order.gd` (`ConstructOrder extends UnitOrder`):
  - Fases: `RETURNING_UNNEEDED_CARGO`, `MOVING_TO_PILE`, `MOVING_TO_SITE_DROPOFF`, `MOVING_TO_BUILDER_SLOT`, `BUILDER_STANDBY`.
  - Carga incompatível na mochila é devolvida com segurança ao acampamento via `DeliverToCampOrder` (sem apagar nem desperdiçar recursos).
  - Interrupção da ordem preserva os recursos físicos na mochila (`UnitCarryLoad`) e atualiza reivindicações/papéis D9 no canteiro.
  - Replanejamento automático quando `WorldNavigation.get_navigation_revision()` muda durante o trajeto ou quando a pilha alvo é exaurida/perdida por deterioração no meio do caminho.
- Integração RTS e UI:
  - `src/rts/pick_result.gd` e `src/rts/world_picker.gd`: tipo `PickResult.Kind.CONSTRUCTION_SITE` e consulta em `CollisionLayers.MASK_BUILDINGS`.
  - `src/rts/rts_input_controller.gd` e `src/rts/command_controller.gd`: clique esquerdo seleciona/inspeciona canteiro; clique direito (ou `command_units_to_site`) designa trabalhadores selecionados ao canteiro (inclusive com `force_transporter` opcional para concorrência forçada em teste).
  - `src/buildings/placement_validator.gd`: `ValidationContext.construction_sites` impede posicionamento sobre canteiros existentes e considera caixas candidatas.
  - `src/buildings/placement_test_overlay.gd` e `src/main/main.gd`: instancia `_construction_sites_root` sob `MainScene` (preservando contagem de filhos de `TestMap`), conecta `placement_confirmed` -> `ConstructionManager`, e adiciona o painel temporário `TemporarySitePanel` (controles não interativos mantidos em `MOUSE_FILTER_IGNORE`, com botões `Designar selecionados` e `Fechar`).

---

## 3. Verificações Automatizadas Executadas

Todas as execuções ocorreram na worktree `C:\Projetos\Dawn_of_Kin_wt_t3_3_construction` após a edição final do código e testes:

| Verificação | Comando | Resultado Observado |
|---|---|---|
| Validação de scripts e cena principal | `.\tools\validate.ps1` | **PASSOU** — `0 errors, 0 warnings, 103 scripts checked` |
| Testes unitários específicos T3.3 | `.\tools\run_tests.ps1 -Filter "t3_3"` | `test_t3_3_construction_site.gd`: **5/5 aprovados**, **112 asserções** |
| Testes de integração específicos T3.3 | `.\tools\run_tests.ps1 -Filter "t3_3"` | `test_t3_3_construction_logistics.gd`: **6/6 aprovados**, **121 asserções** |
| Regressão global segmentada (T1–T3.3) | `.\tools\run_tests.ps1 -Segmented` | **7/7 batches PASS**, **32/32 suítes** (`Discovered=32`, `ExecutedUnique=32`, `Duplicates=0`, `Missing=0`), **222/222 testes aprovados**, **7.382 asserções**, **0 falhas**, **0 erros de suíte** (`SumGodotElapsed: 294068,7 ms`, `TotalWallElapsed: 306205,0 ms`) |

---

## 4. Benchmark Real no Hardware Disponível (`tests/perf/t3_3_logistics_benchmark.gd`)

- **Hardware:** `Intel(R) UHD Graphics 620`, Godot `4.7.2.stable`, renderer `gl_compatibility`, sem `--fixed-fps`.
- **Condição de energia medida no momento da execução:** bateria DC (`Win32_Battery.BatteryStatus = 1`, carga `74,79`), plano do Windows `Equilibrado` (`381b4222-f694-41f0-9685-ff5bb260df2e`).
- **Cenário medido:** `MainScene + TestMap`, 4 trabalhadores ativos divididos entre 2 canteiros (`Abrigo Básico` e `Depósito Rústico`) com `TemporarySitePanel` aberto, 2 criações de canteiro e janela de 360 quadros de renderização ativa.

| Resolução | Criação de Canteiro (`site_creation_ms`, n=2) | FPS Médio (`active_logistics_frame_ms`) | Média (`mean_ms`) | `p50_ms` | `p95_ms` | `max_ms` | Quadros `> 100 ms` |
|---|---|---|---|---|---|---|---|
| `1920×1080` | `mean 6,072 ms` (`p50 4,302 ms`, `max 7,842 ms`) | `117,8 FPS` | `8,489 ms` | `8,187 ms` | `13,08 ms` | `20,672 ms` | `0` |
| `1280×720` | `mean 4,807 ms` (`p50 4,476 ms`, `max 5,138 ms`) | `200,9 FPS` | `4,978 ms` | `4,721 ms` | `6,683 ms` | `12,348 ms` | `0` |

> **Observação de medição:** Na execução a `1920×1080` (~3,06 s de parede nos 360 quadros), o primeiro canteiro já havia recebido `10` unidades de madeira no buffer; em `1280×720` (~1,79 s de parede a `200,9 FPS`), os trabalhadores ainda estavam na primeira pernada de transporte quando os 360 quadros encerraram. Ambos os perfis registraram **0 quadros acima de 100 ms** e `p95` abaixo de `16,67 ms` mesmo em bateria DC.

---

## 5. Limitações Conhecidas e Itens Não Verificados
- **Testes manuais e visuais:** O protocolo `docs/testing/T3_3_manual_test_protocol.md` ainda **não foi executado** manualmente pelo proprietário (todos os itens permanecem marcados como `NÃO TESTADO`).
- **Benchmark em tomada CA:** O benchmark `t3_3_logistics_benchmark.gd` foi medido apenas sob bateria DC; execução opcional em tomada CA pode ser feita seguindo o mesmo script se necessário para comparação.
- **UI provisória:** `PlacementTestOverlay` / `TemporarySitePanel` é uma interface temporária de apoio à T3.3 e será substituída pelo catálogo/inspetor definitivos na T3.5.

---

## 6. Revisão T3.3-R1 — Integridade da Entrega, Alcance Físico e Coordenação Pós-Interrupção

### 6.1 Correções Técnicas Aplicadas
1. **Integridade do buffer do canteiro (`src/buildings/construction_site.gd`):**
   - `accept_delivery_from_carry_load(unit, carry_load)` agora exige `unit` válido e limita o aceite por recurso a `mini(claimed, mini(need, mini(carried, invariant_cap)))` usando `_transit_claims` atribuídos especificamente àquele trabalhador e àquela obra.
   - Carga não atribuída ou pertencente a outro canteiro permanece intacta em `UnitCarryLoad`, sem reduzir reivindicações de outras obras; interrupção e reemissão para a mesma obra preservam o claim em trânsito da unidade.
   - `record_withdrawn_for_site()` limita o registro em trânsito à folga `required - delivered - reserved - in_transit`, preservando o invariante `reserved + in_transit + delivered_buffer <= required`.
2. **Bloqueio de retirada/entrega através de paredes (`src/buildings/build_slot_planner.gd`, `src/units/orders/construct_order.gd`):**
   - Introduzido `BuildSlotPlanner.has_clear_physical_access()` via raycast físico 3D (`CollisionLayers.MASK_WORLD_SOLID`, `hit_from_inside = true` a `REACH_PROBE_HEIGHT = 0.55`).
   - `is_unit_in_pile_reach()` e `is_unit_in_site_dropoff_range()` (com fallback para `site.get_world_3d()` quando inserido na árvore) exigem acesso físico desobstruído além de distância XZ e tolerância vertical.
   - `compute_pile_approach_slot()` e `compute_site_perimeter_slot()` filtram candidatos com acesso físico livre e priorizam por menor distância navegável real (`_path_length`) para contornar obstáculos parciais sem alterar a NavMesh ativa.
   - `ConstructOrder` revalida o alcance físico com `_get_world_3d()` no instante exato da retirada da pilha e da entrega no perímetro, recorrendo a helpers não recursivos `_retry_pile_approach_or_fail()` e `_retry_site_dropoff_or_fail()`.
3. **Espera por colega interrompido e isolamento do `BUILDER` (`src/buildings/construction_site.gd`, `src/units/orders/construct_order.gd`):**
   - Causa raiz confirmada: antes da R1, a verificação usava `get_in_transit_amount() > 0` (que inclui reivindicações órfãs de trabalhadores já cancelados/interrompidos), enviando o novo transportador a `_start_moving_to_builder_slot()` enquanto ainda mantinha papel `SOLO_SUPPLIER`/`TRANSPORTER`, gerando replanejamento contínuo por frame em `_update_builder_standby`.
   - Adicionado `ConstructionSite.has_active_peer_transport_for_site(exclude_unit)` (considera apenas trabalhadores com ordem ativa `SOLO_SUPPLIER`/`TRANSPORTER` e `_pending_pickups` ou `_transit_claims` válidos) e estado dedicado `ConstructOrder.Phase.WAITING_FOR_PEER_SUPPLY` dirigido pelos sinais `state_changed` e `workers_changed`. Trabalhadores em `BUILDER_STANDBY` não consomem nem transferem sua `UnitCarryLoad` pré-existente.
4. **Correção documental no protocolo manual (`docs/testing/T3_3_manual_test_protocol.md`):**
   - Corrigido o custo citado do `Depósito Rústico` de `16 Madeira, 10 Pedra` para `18 Madeira, 10 Pedra`, em conformidade com `data/buildings/storage_depot.tres`.

### 6.2 Validação Pós-R1
- `.\tools\validate.ps1`: **APROVADA** (`0 errors, 0 warnings, 103 scripts checked`).
- `.\tools\run_tests.ps1 -Segmented`: **227/227 testes aprovados em 32 suítes** (`0 failures, 0 suite errors, 7.488 asserções`), incluindo:
  - `tests/unit/test_t3_3_construction_site.gd`: **7/7 testes** (`164` asserções) — cobrindo entrega sem claim, carga mista, isolamento entre obras, idempotência, reemissão, invariante contábil e `has_active_peer_transport_for_site`.
  - `tests/integration/test_t3_3_construction_logistics.gd`: **9/9 testes** (`174` asserções) — cobrindo parede fechada ao redor de pilhas/canteiro, parede parcial com desvio, terreno aberto, substituição após colega interrompido e integridade da mochila do `BUILDER`.

### 6.3 Benchmark `t3_3_logistics_benchmark.gd` — Antes vs. Depois da R1 (Bateria DC)
- **Hardware / Ambiente:** `Intel(R) UHD Graphics 620`, renderer `gl_compatibility`, plano `Equilibrado`, bateria DC (`BatteryStatus=1`), sem `--fixed-fps`.
- **Pré-R1 (`9774035`, carga 74%):**
  - `1920×1080`: `site_creation_ms` média `6,072 ms` (`p95 = 7,842 ms`), `active_logistics_frame_ms` média `8,489 ms` (`117,80 FPS`, `p50 = 8,187 ms`, `p95 = 13,080 ms`, `max = 20,672 ms`, `0` quadros `> 100 ms`).
  - `1280×720`: `site_creation_ms` média `4,807 ms` (`p95 = 5,138 ms`), `active_logistics_frame_ms` média `4,978 ms` (`200,90 FPS`, `p50 = 4,721 ms`, `p95 = 6,683 ms`, `max = 12,348 ms`, `0` quadros `> 100 ms`).
- **Pós-R1 (`feature/t3-3-construction-logistics`, carga 49%):**
  - `1920×1080`: `site_creation_ms` média `6,468 ms` (`p95 = 6,797 ms`), `active_logistics_frame_ms` média `9,639 ms` (`103,75 FPS`, `p50 = 9,318 ms`, `p95 = 15,290 ms`, `max = 26,181 ms`, `0` quadros `> 100 ms`).
  - `1280×720`: `site_creation_ms` média `5,912 ms` (`p95 = 6,847 ms`), `active_logistics_frame_ms` média `7,469 ms` (`133,88 FPS`, `p50 = 7,086 ms`, `p95 = 11,893 ms`, `max = 23,116 ms`, `0` quadros `> 100 ms`).
- **Interpretação:** Mesmo sob bateria DC (49% de carga), os quadros ativos permanecem abaixo de `16,67 ms` no `p95` em ambas as resoluções (`103,75 FPS` em `1080p` e `133,88 FPS` em `720p`, `0` engasgos `> 100 ms`), demonstrando que as verificações físicas espaciais por evento não introduziram custo significativo por frame. Os testes manuais em `docs/testing/T3_3_manual_test_protocol.md` continuam `NÃO TESTADO` aguardando execução pelo proprietário.

---

## 7. Revisão T3.3-R2 — Reprodução Visual, Diagnóstico e Correção de Navegação no Platô / Rampa

### 7.1 Sintoma e Causas Raiz Confirmadas
Durante os testes manuais da T3.3-R1, o item **B2** reprovou quando um canteiro foi criado no platô próximo à rampa do `TestMap`: um trabalhador ficou preso na face lateral da rampa, houve entrega parcial e o suprimento não foi concluído. A reprodução visual renderizada ([T3_3_R2_plateau_navigation_diagnostic.md](T3_3_R2_plateau_navigation_diagnostic.md), via `tests/visual/t3_3_r2_plateau_repro.gd` em `1280×720` e `1920×1080` com `--rendering-driver opengl3 --debug-navigation --debug-collisions`) comprovou:
1. A NavMesh conectava diretamente o chão plano às faces inclinadas laterais da `Ramp` em `z = -12.0` e `z = -16.0`, gerando trajetos que colidiam com a parede lateral física (`9` hits no Cenário D e `62`/`58` hits no Cenário E `pre_fix`, com falha `site_unreachable`).
2. `BuildSlotPlanner.HEIGHT_TOLERANCE` (`2.5` m) e a ausência de checagem de cota do terreno físico permitiam candidatos mal validados em bordas com desnível sem verificação de degrau horizontal baixo.
3. `ConstructOrder` falhava imediatamente ao receber `UnitMovement.MoveState.FAILED_STUCK` na aproximação a slots de perímetro sem tentar slots alternativos disponíveis, e `UnitMovement` não restringia discrepância vertical ao avançar waypoints entre níveis.

### 7.2 Correções Técnicas Aplicadas
1. **`src/navigation/world_navigation.gd`:** Adicionado `_append_sloped_terrain_side_curbs(source_root, source_data)` reutilizando `_build_box_faces` em `request_rebake()` e `_prepare_candidate_build_inputs()` logo após `parse_source_geometry_data`. Aplica barreiras virtuais finas de `0.40 m` apenas durante o bake nas faces laterais de corpos `CollisionLayers.MASK_TERRAIN` inclinados (`5°..45°`, `up_axis.y in [0.707, 0.996]`), mantendo abertos o pé inferior e a saída superior da rampa.
2. **`src/buildings/build_slot_planner.gd`:** Reduzida `HEIGHT_TOLERANCE` para `0.85`, adicionada `NAV_SURFACE_Y_TOLERANCE = 0.75`, `_sample_terrain_ground_y(world_pos, world_3d)` e detecção de degrau horizontal baixo (`minf + 0.35`) em `has_clear_physical_access()`, validando `snap_to_navmesh` e `resolved_target` contra o terreno físico em `compute_pile_approach_slot()` e `compute_site_perimeter_slot()`.
3. **`src/units/orders/construct_order.gd` e `src/units/unit_movement.gd`:** Em `ConstructOrder`, adicionado `_retry_perimeter_slot_move(movement, target_state)` para tentar slots de perímetro alternativos em `MoveState.FAILED_STUCK` até `MAX_APPROACH_RETRIES` (preservando falha imediata para `FAILED_INVALID`) em `_update_moving_to_site_dropoff`, `_update_moving_to_builder_slot` e `_update_waiting_for_peer_supply`. Em `UnitMovement`, adicionada `WAYPOINT_VERTICAL_TOLERANCE_Y = 0.65` em `_resolve_steer_point()` e `_refresh_active_path()`, mantendo `AVOIDANCE_NAVMESH_CLAMP_TOLERANCE_Y = 0.75` (necessário porque `DEFAULT_CELL_HEIGHT = 0.25` posiciona a NavMesh do chão plano em `y = 0.500`).

### 7.3 Verificações Visuais, Automatizadas e Benchmark Pós-R2
- **Reprodução visual renderizada (`tests/visual/t3_3_r2_plateau_repro.gd`, `--mode=post_fix --scenario=all`):** **5/5 cenários aprovados (A–E)** em `1280×720` e `1920×1080`, com **0 colisões laterais na rampa** em todos os cenários (`pre_fix` registrava `9` no Cenário D e `62`/`58` no Cenário E com `site_unreachable`).
- **Validação de scripts e cena:** `.\tools\validate.ps1` -> **PASSOU** (`0 errors, 0 warnings, 104 scripts checked`).
- **Testes T3.3:** `.\tools\run_tests.ps1 -Filter "t3_3"` -> **18/18 aprovados** (`369` asserções: `11/11` em `test_t3_3_construction_logistics.gd` incluindo `test_09_r2_plateau_ramp_detour_and_elevated_slot_filtering` e `test_10_r2_plateau_two_worker_roles_promotion_and_full_supply`, e `7/7` em `test_t3_3_construction_site.gd`).
- **Regressão global segmentada:** `.\tools\run_tests.ps1 -Segmented` -> **7/7 batches PASS, 32/32 suítes (`Discovered=32, ExecutedUnique=32, Duplicates=0, Missing=0`), 229/229 testes aprovados, 7.518 asserções, 0 falhas, 0 erros de suíte** (`SumGodotElapsed: 275479,8 ms`, `TotalWallElapsed: 280419,0 ms`).
- **Benchmark renderizado pós-R2 (`tests/perf/t3_3_logistics_benchmark.gd`, tomada CA `BatteryStatus=2`, plano `Equilibrado`, `Intel(R) UHD Graphics 620`, `opengl3`):**
  - `1920×1080`: `site_creation_ms` média `2,552 ms` (`p95 = 2,901 ms`), `active_logistics_frame_ms` média `7,931 ms` (`126,08 FPS`, `p50 = 7,053 ms`, `p95 = 14,080 ms`, `max = 93,201 ms`, `0` quadros `> 100 ms`).
  - `1280×720`: `site_creation_ms` média `4,000 ms` (`p95 = 4,893 ms`), `active_logistics_frame_ms` média `3,911 ms` (`255,68 FPS`, `p50 = 3,680 ms`, `p95 = 5,476 ms`, `max = 7,710 ms`, `0` quadros `> 100 ms`).
- **Pendência manual:** B2 aguarda reteste manual pelo proprietário após R2; itens C1–D2 seguem pendentes (`T3.3` não homologada).
