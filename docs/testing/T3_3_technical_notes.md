# Dawn of Kin — Notas Técnicas da Etapa T3.3 (Canteiro de Obra e Suprimento Físico)

- **Etapa:** T3.3 — Canteiro de Obra e Suprimento Físico (Transporte)
- **Branch de Implementação:** `feature/t3-3-construction-logistics`
- **Base:** `origin/main` (`931ad196346251e3f24a3ea5db6facb3641233bc`, T3.1 e T3.2 integradas)
- **Engine / Renderer:** Godot `4.7.2.stable`, `gl_compatibility`
- **Estado:** Implementada e validada automaticamente; aguardando validação visual/manual e aprovação formal do proprietário (`T3.4+` permanecem bloqueadas).

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
