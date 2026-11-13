# Plano de Implementação da T2 — Trabalho e Recursos (Transporte Físico)

> **RASCUNHO — NÃO APROVADO**
> Este plano técnico detalhado foi reorganizado integralmente após a aprovação da decisão **D2-1 (Opção B — Transporte físico até o acampamento)** e suas regras de peso, capacidade individual (`0%–100%`) e armazenamento por categoria. Baseia-se em `docs/Dawn_of_Kin_GDD_v1.0.md`, `docs/architecture/T2_architecture_DRAFT.md` e no código real da T1 (`2808799` / `t1-complete`).
> Nenhuma etapa foi iniciada nem autorizada para execução.

---

## 1. Premissas, Regra Fundamental e Guardrails

1. **Regra fundamental da T2 (`GDD §5` — DECIDIDO):** Nenhum recurso pode entrar instantaneamente no `SettlementInventory` durante a coleta. Toda extração vai primeiro para a carga individual (`UnitCarryLoad`) respeitando peso unitário e capacidade máxima (`0%–100%`), e só entra no estoque coletivo após entrega física em um `StoragePoint` compatível.
2. **Conservação matemática estrita:** Em qualquer ciclo normal, parcial, concorrente, interrompido ou falho, deve valer `delta(ResourceNode) + delta(UnitCarryLoad) + delta(SettlementInventory) == 0`, sem criação nem destruição silenciosa de unidades.
3. **Regressão obrigatória da T1:** Os 90 testes aprovados e 1.607 asserções existentes (`tools/run_tests.ps1`), além de zero erros/avisos sob `tools/validate.ps1`, precisam continuar 100% verdes em **cada** incremento.
4. **Orçamento Intel UHD 620 (`KNOWN_ISSUES.md`):** Preservar margem estreita medida na T1.10 (`p95 = 16,586 ms` em 1920×1080) evitando polling em `_process` e evitando rebake de NavMesh em runtime.
5. **Convenções do projeto:** Código, cenas, nós, identificadores e comentários em **inglês**; documentação e protocolos em **português**; tipagem estrita sem avisos (`project.godot`).

---

## 2. Decisões em Aberto (Não Bloqueantes para Iniciar T2.0, Abertas a Ajuste)

Com **D2-1 (Transporte físico)** aprovada, permanecem **ABERTOS** apenas parâmetros de balanceamento e preferências opcionais que não alteram o desenho dos contratos principais:

| ID | Questão em Aberto | Alternativas | Trade-off | Recomendação Técnica | Momento de Uso |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **D2-2** | **Comportamento após entregar carga de uma fonte que se esgotou** | **A)** Concluir ordem em `IDLE`<br>**B)** Buscar automaticamente outra fonte próxima do mesmo tipo | **A:** Previsível e mínimo; zero risco de passeio indesejado pelo mapa.<br>**B:** Mais cômodo, porém introduz escolha heurística de alvo fora de T2 | **Opção A** na base da T2 (`auto_retarget = false`), mantendo gancho limpo para `JobSystem` futuro | `T2.3` |
| **D2-3** | **Finitude dos nós vs regeneração temporizada** | **A)** Nós finitos na T2 (toco/cascalho/arbusto seco)<br>**B)** Regeneração após `N` segundos | **A:** Comprova esgotamento, carga parcial e zero timers de mundo.<br>**B:** Mantém fontes disponíveis indefinidamente | **Opção A** por padrão (`regenerates = false` configurável em `.tres`) | `T2.1` |
| **D2-4** | **Valores iniciais de peso, capacidade, ciclo e rendimento** | Sugestão inicial: `comida peso=1`, `madeira peso=2`, `pedra peso=4`; `capacidade base=20`; ciclos `2,0–2,5 s`; `max_workers=2` | Carga de `20` cabendo `20` comidas, `10` madeiras ou `5` pedras dá retorno visível em ~2–4 viagens sem lentidão | Manter **totalmente parametrizado em `.tres`** (`ResourceDefinition` e `CharacterDefinition`) para calibragem livre | `T2.0` |
| **D2-5** | **Comportamento quando depósitos futuros tiverem teto local cheio (`T3+`)** | **A)** Na T2 pontos iniciais não têm teto bloqueante (`has_local_capacity=false`)<br>**B)** Impor teto já no acampamento inicial T2 | **A:** Foca T2 na prova de coleta/peso/transporte sem punir antes de haver construção (`T3`) | **Opção A** na T2, já com suporte de `has_local_capacity` e descarga parcial no contrato de `StoragePoint` para a T3 | `T2.1` / `T2.3` |

---

## 3. Sequência Reorganizada por Dependências Reais (`T2.0` → `T2.6`)

Não há incrementos "remendados" ou condicionais: carga com peso, pontos de armazenamento por categoria e transporte físico fazem parte da espinha dorsal desde `T2.0`.

```text
T2.0 (ResourceDefinition c/ peso + CharacterDefinition c/ capacidade + UnitCarryLoad + SettlementInventory)
  │
  ├───────────────────────────────┐
  ▼                               ▼
T2.1 (ResourceNode +              T2.2 (PickResult.RESOURCE & STORAGE +
      StoragePoint rústicos +           WorldPicker c/ filtro anti-auto-oclusão)
      StorageRegistry + TestMap)  │
  │                               │
  └───────────────┬───────────────┘
                  ▼
T2.3 (Unit.State WORKING & TRANSPORTING + DeliverOrder + GatherOrder completa)
                  │
                  ▼
T2.4 (CommandController despacho coleta/entrega manual + concorrência + RtsInputController)
                  │
                  ▼
T2.5 (SettlementResourceHud + UnitCarryStatusHud 0%-100% + feedback visual mínimo)
                  │
                  ▼
T2.6 (Regressão 90 testes T1 + suíte T2 + estresse RVO transporte + benchmark UHD 620 + protocolo manual)
```

---

## 4. Incrementos Detalhados de Execução

### Incremento T2.0 — Modelo Econômico: Pesos, Carga Individual e Estoque Compartilhado

- **Objetivo e comportamento observável:** Construir a base pura e exata de dados e transações da T2: recursos com peso unitário (`.tres`), capacidade configurável nos personagens, componente `UnitCarryLoad` com cálculo exato de peso ocupado e porcentagem (`0%` a `100%`), suporte a múltiplas categorias na carga, gancho de modificadores futuros de capacidade e `SettlementInventory` com transações atômicas não negativas. Sem alterações de gameplay ou cena jogável ainda além de registrar `SettlementInventory` na cena principal.
- **Arquivos/componentes:**
  - *Novos:*
    - `src/economy/resource_definition.gd` (+ `.uid`)
    - `src/economy/settlement_inventory.gd` (+ `.uid`)
    - `src/units/unit_carry_load.gd` (+ `.uid`)
    - `data/resources/wood_tree.tres`, `data/resources/stone_rock.tres`, `data/resources/food_berry_bush.tres`
    - `tests/unit/test_resource_definition.gd` (+ `.uid`)
    - `tests/unit/test_unit_carry_load.gd` (+ `.uid`)
    - `tests/unit/test_settlement_inventory.gd` (+ `.uid`)
  - *Modificados:*
    - `src/units/character_definition.gd` (`@export var base_carry_capacity: int = 20`)
    - `data/characters/leader_a.tres`, `data/characters/leader_b.tres` (valor explícito `base_carry_capacity = 20`)
    - `src/main/main.gd`, `src/main/main.tscn` (composição explícita de `SettlementInventory` sem autoload)
- **Interfaces e dados:**
  - `ResourceDefinition`: `resource_id`, `display_name`, `unit_weight: int`, `initial_amount: int`, `yield_per_cycle: int`, `cycle_duration_sec: float`, `standoff_radius_m: float`, `interact_tolerance_m: float`, `max_concurrent_workers: int`, `regenerates: bool`, `regrow_delay_sec: float`, `is_valid()`.
  - `UnitCarryLoad`: `configure()`, `set_capacity_modifier()`, `remove_capacity_modifier()`, `get_effective_capacity()`, `get_used_weight()`, `get_free_weight()`, `get_fill_percent()` (`0.0..100.0`), `can_fit_one()`, `get_max_addable_units()`, `should_return_to_storage()`, `add_resource()`, `remove_resource()`, sinal `load_changed`.
  - `SettlementInventory`: `add_resource()`, `get_amount()`, `has_enough()`, `try_consume()`, `get_snapshot()`, `apply_snapshot()`, sinais `resource_changed`, `inventory_reset`.
- **Dependências e riscos:** Nenhuma dependência da T2. **Risco:** Erros de arredondamento ou excesso de capacidade em cargas parciais; mitigado usando quantidades e pesos inteiros exatos e pré-checagem estrita em `add_resource` / `get_max_addable_units`.
- **Critérios de aceite:**
  - `UnitCarryLoad` nunca ultrapassa `100%` nem aceita frações; `get_fill_percent()` reflete exatamente `0%–100%`.
  - Modificadores aumentam/diminuem capacidade sem perder itens já carregados; múltiplas categorias coexistem pelo peso somado.
  - `SettlementInventory` garante atomicidade em `try_consume`, rejeita negativos e preserva snapshots.
- **Testes e regressão:** Suíte unitária cobrindo limites exatos (`8/10` com item peso `4` -> não cabe mais 1), lotes parciais, múltiplas categorias, modificadores e conservação; `tools/validate.ps1` + todos os 90 testes T1 passam.
- **Reversibilidade:** Isolada em módulos de dados/economia.
- **Modelo de IA recomendado:** **`Gemini 4 Hydrogen Medium`** (domínio puro, determinístico, sem física/NavMesh).

---

### Incremento T2.1 — Fontes (`ResourceNode`) e Pontos Rústicos de Armazenamento (`StoragePoint`, `StorageRegistry`)

- **Objetivo e comportamento observável:** Implementar no mundo as fontes coletáveis (`ResourceNode` para árvores, rochas e novos arbustos `BerryBushPlaceholder`) e a infraestrutura mínima rústica do acampamento inicial (`StoragePoint`: `CampWoodPile`, `CampStoneCairn`, `CampFoodCache`, orquestrados por `StorageRegistry`), posicionada em área aberta compatível com todos os caminhos dos testes T1.
- **Arquivos/componentes:**
  - *Novos:*
    - `src/world/resource_node.gd` (+ `.uid`)
    - `src/world/storage_point.gd` (+ `.uid`)
    - `src/economy/storage_registry.gd` (+ `.uid`)
    - `assets/placeholder/berry_bush_placeholder.tscn`
    - `assets/placeholder/storage_wood_pile.tscn`, `storage_stone_cairn.tscn`, `storage_food_cache.tscn` (cenas simples compartilhando `StoragePoint` script e poucos materiais em `assets/placeholder/`)
    - `assets/placeholder/mat_bush_placeholder.tres`, `mat_berry_placeholder.tres`, `mat_crate_placeholder.tres` (conforme necessário)
    - `tests/integration/test_resource_node.gd` (+ `.uid`)
    - `tests/integration/test_storage_point.gd` (+ `.uid`)
  - *Modificados:*
    - `assets/placeholder/tree_placeholder.tscn`, `assets/placeholder/rock_placeholder.tscn` (`ResourcePickArea` em `MASK_RESOURCES` + visual esgotado + script `ResourceNode` preservando `StaticBody3D` em `MASK_OBSTACLES`)
    - `levels/test_map/test_map.tscn`, `levels/test_map/test_map.gd` (adição de `Resources` com arbustos e `CampStorage` com os 3 depósitos especializados em área livre fora dos corredores da T1)
    - `src/main/main.gd`, `src/main/main.tscn` (registro de `StorageRegistry` conectado ao `TestMap`)
- **Interfaces e dados:**
  - `ResourceNode`: `extract_amount()`, `reserve_worker_slot()`, `release_worker_slot()`, `is_harvestable()`, `get_max_interact_distance_xz()`, estado `DEPLETED` mantendo `StaticBody3D` sem rebake.
  - `StoragePoint`: `accepted_categories`, `is_active`, `priority`, `has_local_capacity`, `local_capacity`, `can_accept_category()`, `deposit_from_carry_load()`, `StoragePickArea` em `MASK_BUILDINGS`.
  - `StorageRegistry`: `find_best_storage_for(resource_id, from_pos, world_nav)`.
- **Dependências e riscos:** Depende de `T2.0`. **Riscos críticos:** (1) quebrar `test_test_map.gd` (`Obstacles` precisa manter `>10` `StaticBody3D` em `MASK_OBSTACLES`), mitigado mantendo árvores/rochas sob `Obstacles` e novos depósitos/arbustos em containers próprios (`Resources`, `CampStorage`); (2) bloquear trajetos dos testes `test_commands.gd` ao redor de `(0,0,-2.5)..(0,0,5)`, mitigado posicionando `CampStorage` em área limpa ao sul (`z ~ +8,5`).
- **Critérios de aceite:** Fontes e depósitos respeitam camadas físicas, NavMesh bake contorna tudo limpo, `StorageRegistry` encontra o depósito compatível alcançável por categoria e `deposit_from_carry_load` transfere itens preservando conservação absoluta.
- **Testes e regressão:** Testes de integração de `ResourceNode`, `StoragePoint`/`StorageRegistry` (descarga parcial, categoria incompatível rejeitada, depósito desativado/inacessível) + execução obrigatória dos 90 testes T1.
- **Reversibilidade:** Reversível preservando obstáculos originais e isolando `CampStorage`/`Resources`.
- **Modelo de IA recomendado:** **`Gemini 4 Hydrogen Medium`** (estrutura bem especificada; atenção cuidadosa ao posicionamento em `test_map.tscn`).

---

### Incremento T2.2 — Picking Contextual de Recursos e Depósitos (`PickResult`, `WorldPicker`)

- **Objetivo e comportamento observável:** Estender o sistema de picking para reconhecer fontes coletáveis (`PickResult.Kind.RESOURCE`) e pontos de armazenamento (`PickResult.Kind.STORAGE`) via `MASK_RESOURCES` e `MASK_BUILDINGS`, respeitando oclusão por muros/terreno/unidades sem jamais sofrer auto-oclusão pelo próprio colisor sólido do recurso ou do depósito.
- **Arquivos/componentes:**
  - *Modificados:*
    - `src/rts/pick_result.gd` (`Kind.RESOURCE`, `Kind.STORAGE`, `resource_node`, `storage_point`, `from_resource()`, `from_storage()`, `is_resource()`, `is_storage()`)
    - `src/rts/world_picker.gd` (queries em `MASK_RESOURCES` e `MASK_BUILDINGS`, `_resolve_resource_from_collider`, `_resolve_storage_from_collider`, filtro anti-auto-oclusão, ordenação por distância câmera → hit)
  - *Novos:*
    - `tests/unit/test_pick_result.gd` (+ `.uid`)
    - `tests/integration/test_picking_t2.gd` (+ `.uid`)
- **Interfaces e dados:** API retrocompatível de `WorldPicker` e `PickResult`.
- **Dependências e riscos:** Depende de `T2.1`. **Risco:** Auto-oclusão em árvore/rocha/pilha ou regressão no picking de `UNIT`, `OBSTACLE` (`WallWest`) e `GROUND`.
- **Critérios de aceite:** Árvore/rocha/arbusto → `Kind.RESOURCE`; pilha/cesta de armazenamento → `Kind.STORAGE`; atrás de `WallWest` → `Kind.OBSTACLE`; fonte esgotada deixa de retornar `Kind.RESOURCE`; unidade à frente vence sobre recurso/depósito atrás.
- **Testes e regressão:** Testes unitários e integração com câmera isométrica em zoom min/default/max e cenários ocluídos + regressão completa T1 (`test_picking_selection.gd`, `test_box_selection.gd`, `test_commands.gd`).
- **Reversibilidade:** Isolada em `PickResult` e `WorldPicker`.
- **Modelo de IA recomendado:** **`Gemini 4 Hydrogen Medium`**.

---

### Incremento T2.3 — Carga na Unidade, Estados `WORKING`/`TRANSPORTING`, `DeliverOrder` e `GatherOrder`

- **Objetivo e comportamento observável:** Integrar `UnitCarryLoad` à `Unit`, introduzir os estados `WORKING` e `TRANSPORTING`, adicionar `UnitMovement.face_position()`, criar `DeliverOrder` (entrega física pura) e `GatherOrder` completa (ir à fonte → extrair respeitando peso/capacidade e lote parcial → transportar ao depósito compatível → descarregar no `SettlementInventory` → encadear outro depósito se carga mista → repetir se fonte ainda válida). **Comprova diretamente que o estoque coletivo só aumenta no ato do descarregamento.**
- **Arquivos/componentes:**
  - *Modificados:*
    - `src/units/unit.gd` (`State.WORKING`, `State.TRANSPORTING`, composição `_carry_load: UnitCarryLoad`, sinal `carry_load_changed`, getter `get_carry_load()`, sincronização de estado da ordem)
    - `src/units/unit_movement.gd` (`face_position(world_pos, delta)`)
    - `src/units/orders/unit_order.gd` (`get_requested_unit_state()`, constantes `REASON_INVALID_RESOURCE`, `REASON_RESOURCE_DEPLETED`, `REASON_NO_WORKER_SLOT`, `REASON_NO_STORAGE`, `REASON_STORAGE_UNREACHABLE`, `REASON_STORAGE_FULL`)
  - *Novos:*
    - `src/units/orders/storage_delivery_helper.gd` (+ `.uid`, lógica compartilhada de seleção e descarga em depósitos evitando duplicação entre `DeliverOrder` e `GatherOrder`)
    - `src/units/orders/deliver_order.gd` (+ `.uid`)
    - `src/units/orders/gather_order.gd` (+ `.uid`)
    - `tests/integration/test_gather_and_transport.gd` (+ `.uid`)
- **Interfaces e dados:** `Unit.get_carry_load()`, `DeliverOrder.new(storage_point, storage_registry, settlement_inventory)`, `GatherOrder.new(resource_node, slot_position, storage_registry, settlement_inventory, auto_repeat := true)`.
- **Dependências e riscos:** Depende de `T2.0` e `T2.1`. **Risco alto:** Máquina de estados assíncrona com física real (RVO durante retorno, preservação da carga ao cancelar/substituir em trânsito, depósito cercado falhando sem perda nem duplicação, extração parcial ao esgotar ou atingir `100%`, invalidação da fonte mid-order).
- **Critérios de aceite:**
  - Durante `APPROACHING` e `HARVESTING`, `SettlementInventory` permanece **inalterado** (`0`), enquanto `UnitCarryLoad` cresce de `0%` até o gatilho de retorno.
  - Quando a carga atinge `100%`, ou `free_weight < unit_weight` (ex.: `80%` na pedra), ou a fonte esgota com carga parcial (`> 0`), a unidade entra em `TRANSPORTING`, vai até o `StoragePoint` compatível e só então `SettlementInventory` incrementa pelo valor exato descarregado.
  - Cancelar por `MoveOrder` no meio do transporte mantém a carga intacta dentro da unidade (`0` perda, `0` crédito prematuro).
  - Cargas mistas (ex.: madeira + comida) encadeiam descarga no depósito de comida e depois no de madeira automaticamente.
  - Depósito inacessível falha explicitamente mantendo carga preservada na unidade.
- **Testes e regressão:** Testes de integração com física Jolt e NavMesh real cobrindo conservação exata, carga máxima/limite parcial, fonte esgotada com carga parcial, cancelamento em `TRANSPORTING`, fonte removida durante coleta, múltiplas categorias na mesma carga, depósito inacessível e todos os 90 testes T1.
- **Reversibilidade:** `MoveOrder` intacta; ordens T2 totalmente modulares.
- **Modelo de IA recomendado:** **`Gemini 4 Hydrogen High`** (complexidade central da máquina de estados, conservação garantida e física/RVO reais).

---

### Incremento T2.4 — Despacho Contextual por Clique Direito, Concorrência e Entrega Manual

- **Objetivo e comportamento observável:** Conectar `PickResult.Kind.RESOURCE` e `PickResult.Kind.STORAGE` ao `CommandController` e `RtsInputController`: clique direito em recurso despacha 1 ou mais unidades com alocação de slots sem sobreposição; clique direito em depósito compatível despacha `DeliverOrder` manual caso unidades selecionadas tenham carga acumulada; prevenção de empilhamento entre trabalhadores em `MOVING`, `WORKING` e `TRANSPORTING`; clique rápido 20 Hz seguro sem vazamento de slots nem de recursos.
- **Arquivos/componentes:**
  - *Modificados:*
    - `src/rts/command_controller.gd` (injeção de `StorageRegistry` e `SettlementInventory` opcional em `configure()`, despacho de `GatherOrder` e `DeliverOrder`, `_collect_occupied_positions` estendido para `WORKING` e `TRANSPORTING`)
    - `src/rts/rts_input_controller.gd` (hover sutil opcional em recurso/depósito quando seleção ativa; clique esquerdo e drag box T1 intactos)
    - `src/main/main.gd` (ligação completa de `StorageRegistry` e `SettlementInventory` no `CommandController`)
  - *Novos:*
    - `tests/integration/test_gather_commands_and_concurrency.gd` (+ `.uid`)
- **Interfaces e dados:** `CommandController.configure(selection_manager, world_nav, destination_marker, settlement_inventory = null, storage_registry = null)` (retrocompatível com chamadas antigas).
- **Dependências e riscos:** Depende de `T2.2` e `T2.3`. **Risco alto:** Contenção de múltiplos trabalhadores tanto ao redor da fonte quanto chegando juntos ao mesmo depósito, 3º trabalhador em nó com `max_concurrent_workers = 2`, esgotamento simultâneo por 2 trabalhadores e spam de cliques 20 Hz alternando fonte ↔ depósito ↔ solo.
- **Critérios de aceite:**
  - 2 unidades comandadas na mesma árvore coletam simultaneamente em slots separados (`>= 2*radius + clearance`), voltam fisicamente ao `CampWoodPile`, descarregam sem se bloquear e `total_collected_from_tree == settlement_wood + sum(unit_carry_wood)`.
  - Interromper uma unidade em transporte clicando no chão preserva sua carga; clicar depois no `CampWoodPile` faz entregar via `DeliverOrder`.
  - Spam 20 Hz entre árvore, arbusto, depósito e solo não vaza slots nem duplica recursos.
- **Testes e regressão:** Testes simulando `InputEventMouseButton` reais no `MainScene` completo (coleta individual, grupo em árvore/rocha/arbusto, contenção 3º trabalhador, entrega manual interrompida, spam 20 Hz, fonte dentro de `ClosedEnclosure`) + regressão dos 90 testes T1.
- **Reversibilidade:** Contida no despacho de `RESOURCE` / `STORAGE` de `CommandController`.
- **Modelo de IA recomendado:** **`Gemini 4 Hydrogen High`** (concorrência multi-unidade, alocação espacial e interações reais de mouse + RVO).

---

### Incremento T2.5 — HUD do Estoque, Indicador de Carga `0%–100%` e Feedback Visual

- **Objetivo e comportamento observável:** Expor ao jogador de forma clara e não bloqueante: (1) o estoque coletivo (`Madeira | Pedra | Comida`), visivelmente congelado durante a coleta e atualizado apenas na entrega; (2) o estado e a **porcentagem ocupada (`0%–100%`)** + resumo da carga carregada da unidade selecionada; e (3) feedback visual mínimo discreto no mundo (estado esgotado da fonte, hover sutil, identificação visual clara entre `WoodPile`/`StoneCairn`/`FoodCache` e unidade carregando/trabalhando).
- **Arquivos/componentes:**
  - *Novos:*
    - `src/ui/settlement_resource_hud.gd` (+ `.uid`) e `src/ui/settlement_resource_hud.tscn`
    - `src/ui/unit_carry_hud.gd` (+ `.uid`) e `src/ui/unit_carry_hud.tscn` (painel discreto inferior/canto orientado exclusivamente por sinais `selection_changed`, `carry_load_changed` e `state_changed`)
    - `tests/integration/test_t2_hud.gd` (+ `.uid`)
  - *Modificados:*
    - `src/main/main.tscn`, `src/main/main.gd` (ligação dos dois HUDs em `UiLayer`, ambos com `mouse_filter = MOUSE_FILTER_IGNORE` em toda a hierarquia)
- **Interfaces e dados:** API orientada exclusivamente a sinais (`set_process(false)` em ambos os HUDs).
- **Dependências e riscos:** Depende de `T2.0`, `T2.3` e `T2.4`. **Risco:** Algum `Control` interno capturar eventos de mouse e quebrar edge scroll / picking da T1, ou adicionar overhead de renderização desnecessário.
- **Critérios de aceite:**
  - `UnitCarryHud` mostra `0%` → aumento gradual por ciclo → `100%` (ou limite de espaço) → volta a `0%` na descarga; exatamente quando volta a `0%`, `SettlementResourceHud` soma os recursos.
  - Nenhum controle do HUD intercepta cliques (`MOUSE_FILTER_IGNORE` validado em teste).
- **Testes e regressão:** Teste de integração validando atualização síncrona via sinais durante ciclo real de coleta e descarga, além de não bloqueio de input + regressão total.
- **Reversibilidade:** Desconectável no `UiLayer` sem alterar lógica econômica nem de ordens.
- **Modelo de IA recomendado:** **`Gemini 4 Hydrogen Medium`**.

---

### Incremento T2.6 — Regressão Total, Estresse de Transporte na Intel UHD 620 e Protocolo Manual

- **Objetivo e comportamento observável:** Validar tecnicamente toda a T2 com zero erros/avisos, executar cenário visual reproduzível de ciclo completo (coleta + transporte ida/volta + descarga + esgotamento), medir impacto real do tráfego de transporte RVO em 1920×1080 na Intel UHD 620 comparando com o baseline da T1.10 (`p95 = 16,586 ms`), consolidar `docs/architecture/T2_architecture.md` e entregar protocolo manual para aceitação do jogador.
- **Arquivos/componentes:**
  - *Novos:*
    - `tests/visual/scenario_t2_gather_transport.gd` (+ `.uid`)
    - `docs/testing/T2_manual_test_protocol.md`
    - `docs/architecture/T2_architecture.md`
  - *Modificados (se medido algo novo ou ajustes mínimos sem mascarar falhas):*
    - Atualização pontual de `docs/KNOWN_ISSUES.md` se houver métricas novas e revisão do `README.md` quando autorizado.
- **Dependências e riscos:** Depende de `T2.0` a `T2.5`. **Risco principal:** O aumento do tráfego ativo RVO ida-e-volta e as malhas dos depósitos/arbustos ultrapassarem os `16,7 ms` p95 em 1080p na UHD 620 — exige medição real via `tools/perf.ps1` e eventual ajuste leve de sombras/segmentos caso necessário.
- **Critérios de aceite:**
  - `tools/validate.ps1`: 0 erros, 0 avisos.
  - `tools/run_tests.ps1`: 100% dos 90 testes (1.607 asserções) da T1 + toda suíte da T2 aprovados sem skips.
  - `tools/perf.ps1`: métricas medidas em 1920×1080 na Intel UHD 620 dentro do orçamento.
  - Protocolo manual aprovado pelo usuário antes de encerrar ou commitar.
- **Reversibilidade:** Documentação e cenários não alteram gameplay.
- **Modelo de IA recomendado:** **`Gemini 4 Hydrogen Medium`** (escalar para `High` apenas se o benchmark apontar gargalo técnico para otimizar).

---

## 5. Resumo Comparativo de Modelos Recomendados

| Incremento | Foco | Risco Técnico | Modelo Recomendado |
| :--- | :--- | :--- | :--- |
| **T2.0** | `ResourceDefinition` (peso) + `UnitCarryLoad` (0%–100%) + `SettlementInventory` | Baixo | `Gemini 4 Hydrogen Medium` |
| **T2.1** | `ResourceNode` + `BerryBush` + 3 `StoragePoint` rústicos + `StorageRegistry` | Médio (compat. `TestMap`) | `Gemini 4 Hydrogen Medium` |
| **T2.2** | `PickResult` (`RESOURCE`/`STORAGE`) + `WorldPicker` anti-auto-oclusão | Médio | `Gemini 4 Hydrogen Medium` |
| **T2.3** | `WORKING`/`TRANSPORTING` + `DeliverOrder` + `GatherOrder` + conservação | Alto (state machine + física) | `Gemini 4 Hydrogen High` |
| **T2.4** | `CommandController` (coleta/entrega manual), concorrência e spam 20 Hz | Alto (RVO + slots + concorrência) | `Gemini 4 Hydrogen High` |
| **T2.5** | `SettlementResourceHud` + `UnitCarryHud` (0%–100%) reativos | Baixo | `Gemini 4 Hydrogen Medium` |
| **T2.6** | Regressão T1+T2, benchmark Intel UHD 620 e protocolo manual | Médio (margem 1080p) | `Gemini 4 Hydrogen Medium` |

---

## 6. Critérios Globais de Aceite da T2 (`AC-T2` Atualizados)

- **AC-T2-01 (Não-instantaneidade estrita):** Durante todo o deslocamento de ida e durante a coleta na fonte, o `SettlementInventory` e o HUD coletivo **não** aumentam; os materiais entram apenas na carga individual da unidade.
- **AC-T2-02 (Peso, capacidade e limite 0%–100%):** A ocupação individual varia de `0%` a `100%` com base no peso por material; nunca ultrapassa `100%`; quando não há espaço para mais 1 unidade coletável (ex.: `80%` com resto menor que o peso do recurso), o trabalhador retorna ao acampamento para descarregar.
- **AC-T2-03 (Entrega por categoria e conservação):** Madeira vai ao ponto de madeira, pedra ao de pedra e comida ao de comida; somente após descarregar no depósito válido o estoque compartilhado aumenta pelo valor exato descarregado e a carga volta a `0%`. Vale conservação exata (`extraído == carregado + entregue`).
- **AC-T2-04 (Carga parcial e esgotamento):** Quando uma fonte se esgota antes de completar `100%` de carga, a unidade carrega o saldo extraído até o depósito compatível, descarrega tudo sem perda e finaliza limpamente sem tentar extrair além do limite da jazida.
- **AC-T2-05 (Carga mista e entrega manual):** Redirecionar uma unidade com carga parcial para outra fonte preserva os materiais anteriores dentro da capacidade total e descarrega cada categoria no seu respectivo depósito; clicar com direito em um depósito com unidade carregada permite descarga manual imediata (`DeliverOrder`).
- **AC-T2-06 (Cancelamento e falha de depósito sem perda):** Cancelar no meio do transporte ou encontrar depósito inacessível nunca duplica nem apaga a carga carregada pelo trabalhador; falhas reportam razão explícita sem travamento.
- **AC-T2-07 (Concorrência, contenção e 20 Hz):** Dois trabalhadores coletam na mesma árvore em slots separados e entregam ao depósito sem interpenetração RVO; cliques rápidos 20 Hz entre fontes/depósitos/solo não vazam slots nem corrompem quantidades.
- **AC-T2-08 (Picking, oclusão e controles T1):** Recursos e depósitos respeitam oclusão por muros/terreno/unidades sem auto-oclusão; clique esquerdo, caixa de seleção e câmera funcionam exatamente como na T1.
- **AC-T2-09 (Regressão T1 e qualidade estrita):** `tools/validate.ps1` com zero erros/avisos e 100% dos 90 testes / 1.607 asserções da T1 + toda suíte da T2 aprovados em `tools/run_tests.ps1`.
- **AC-T2-10 (Intel UHD 620 e protocolo manual):** Benchmark em 1920×1080 medido dentro do orçamento operacional e protocolo manual `T2_manual_test_protocol.md` aprovado pelo usuário.
