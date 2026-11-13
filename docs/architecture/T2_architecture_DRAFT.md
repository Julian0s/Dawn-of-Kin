# Arquitetura Técnica da T2 — Trabalho e Recursos (Revisão D2-1: Transporte Físico)

> **RASCUNHO — NÃO APROVADO**
> Este documento é exclusivamente uma proposta técnica de planejamento para a fase **T2 — Trabalho e Recursos** de *Dawn of Kin*, revisada após a aprovação da decisão **D2-1 (Opção B — Transporte físico até o acampamento)** e suas regras associadas. Nenhuma implementação de código, cena, teste ou commit foi iniciada. A execução aguarda aprovação explícita do usuário, conforme `AGENTS.md`.

---

## 1. Contexto, Baseline Verificada e Limites de Escopo

### 1.1 Baseline real inspecionada
- **Workspace oficial:** `C:\Projetos\Dawn of Kin`
- **Branch e histórico Git:** `main`, commit de referência `2808799` (`docs(t1): record final manual acceptance`), tag anotada `t1-complete`, mantendo `docs/historico/` não rastreado.
- **Engine e ambiente:** Godot `4.7.2.stable.official.ed1daf0bf`, GDScript tipado com avisos rígidos habilitados em `project.godot` (`untyped_declaration`, `unsafe_property_access`, `unsafe_method_access`, `unsafe_cast`, `unsafe_call_argument`), renderizador `gl_compatibility` (OpenGL 3.3), física 3D `Jolt Physics`.
- **Hardware de referência e orçamento medido (`docs/KNOWN_ISSUES.md`):**
  - Intel UHD 620, 16 GB RAM: em `1920×1080` na T1.10 atingiu `94,24 FPS`, `p50 = 10,236 ms` e `p95 = 16,586 ms` (`0,114 ms` abaixo do teto de `16,7 ms`, alcançando `17,016 ms` em bateria no Run 3).
  - Custo RVO/física por unidade (`tests/perf/rvo_stress_test.gd`): `phys_avg_ms` sobe de `2,14 ms` (2 unidades) para `6,17 ms` (10), `9,24 ms` (25) e `14,56 ms` (50 unidades) — cerca de `0,26–0,30 ms` por unidade em movimento.
- **Suíte de regressão existente:** 13 suítes, 90 testes aprovados, 1.607 asserções e 49 scripts validados sem erros nem avisos (`tools/validate.ps1`, `tools/run_tests.ps1`).

### 1.2 Objetivo mínimo revisado da T2 (`Dawn_of_Kin_GDD_v1.0.md` §5 e §13)
Selecionar um ou mais habitantes/protagonistas (`LeaderA`, `LeaderB`), emitir ordem contextual com clique direito em uma fonte coletável (`madeira`, `pedra` ou `comida`), fazer o trabalhador ir até a fonte, coletar materiais respeitando peso por recurso e capacidade individual (`0%` a `100%`), retornar ao local de armazenamento compatível no acampamento quando atingir o limite (ou quando não couber mais nenhuma unidade, ou ao esgotar a fonte com carga parcial) e **somente ao descarregar fisicamente no depósito válido** creditar os recursos no `SettlementInventory`, preservando integralmente todos os sistemas RTS da T1.

### 1.3 Fora de escopo da T2
- Fome ou sede individuais nas unidades (**DECIDIDO** fora em `GDD §5`).
- Posicionamento livre pelo jogador e construção completa de edifícios/canteiros (`T3`).
- Profissões especializadas, fabricação, ferramentas, armas e árvores de tecnologia (`T3–T6`).
- Logística automática entre múltiplos assentamentos/regiões (`T4+`), save/load em disco (`T4` — apenas interfaces de snapshot prontas) e ciclo familiar/combate/NPCs externos (`T5–T8`).

---

## 2. Incompatibilidades e Restrições Reais do Código T1

1. **Contrato de camadas físicas em `TestMap/Obstacles` (`tests/integration/test_test_map.gd`, linhas 38–45):**
   `test_02` exige `> 10` nós `StaticBody3D` sob `TestMap/Obstacles` todos com `collision_layer == CollisionLayers.MASK_OBSTACLES` (`2`) e `collision_mask == 0`. Os corpos sólidos de árvores e rochas devem permanecer em `MASK_OBSTACLES` (inclusive para NavMesh bake), utilizando uma `Area3D` dedicada (`ResourcePickArea`) em `CollisionLayers.MASK_RESOURCES` (`6`) para picking, e uma `Area3D` dedicada (`StoragePickArea`) em `CollisionLayers.MASK_BUILDINGS` (`5`, já nomeada `"buildings"` em `project.godot`) nos pontos de armazenamento do acampamento.

2. **Corredores espaciais ocupados pelos testes da T1 (`tests/integration/test_commands.gd`):**
   Os testes da T1 enviam unidades por clique de tela para `(0, 0, 0)`, `(0, 0, -2.5)`, `(6.5, 0, 0.5)`, `(-4..4, 0, -1..5)` e pelo vão de `WallWithGap` (`x in [-2, 2], z = -6`).
   - **Restrição arquitetural obrigatória:** Os pontos rústicos de armazenamento do acampamento inicial **não podem** ser colocados no corredor central `(0, 0, -3..+5)` nem na frente da fenda em `z = -6`. Devem ser posicionados em área aberta livre (ex.: ao sul da posição inicial dos líderes, próximo a `z = +7,5..+9,5`, afastados do `ClosedEnclosure` em `(-16, 12)` e da `Rock05` em `(-2.5, 16)`), preservando 100% das trajetórias dos 90 testes T1.

3. **Auto-oclusão no `WorldPicker` (`src/rts/world_picker.gd`):**
   Tanto `ResourceNode` quanto `StoragePoint` combinam colisor sólido (`MASK_OBSTACLES`, para NavMesh e física) com `Area3D` de picking (`MASK_RESOURCES` / `MASK_BUILDINGS`). A checagem de oclusão deve ignorar hits de `solid_query` que pertençam à hierarquia da mesma entidade-alvo, bloqueando apenas quando outro corpo sólido (muro, terreno, outra rocha/árvore) estiver à frente.

4. **Máquina de estados de `Unit`, `UnitOrder` e `UnitMovement` (`src/units/`):**
   - `Unit.State` possui hoje apenas `IDLE` e `MOVING`. Precisa incorporar `WORKING` e `TRANSPORTING`, sincronizados pela ordem ativa sem quebrar `MoveOrder` nem `GatherOrder`/`MoveOrder` nos testes da T1.
   - `UnitMovement` só gira o corpo quando em deslocamento ativo (`applied_xz.length() > AVOIDANCE_MIN_ROTATION_SPEED`), precisando expor `face_position(world_pos, delta)` para trabalho e descarga voltados ao alvo.
   - `CommandController._collect_occupied_positions()` precisa considerar também trabalhadores em `WORKING` e em `TRANSPORTING` (pelo slot reservado ou posição atual) para evitar sobreposição em novas ordens.

---

## 3. Classificação Rigorosa Conforme o GDD Atualizado

| Item / Regra | Status no GDD | Reflexo Arquitetural na T2 |
| :--- | :--- | :--- |
| Transporte físico: estoque só aumenta após descarga em depósito válido | **DECIDIDO** (`§5`, `§13`) | `GatherOrder` extrai para `UnitCarryLoad`; apenas `StoragePoint` + descarga credita `SettlementInventory` |
| Capacidade individual de carga em cada habitante (inclui casal líder) | **DECIDIDO** (`§5`) | `UnitCarryLoad` em `Unit`, inicializada via `CharacterDefinition.base_carry_capacity` |
| Ocupação exibida em porcentagem (`0%` a `100%`) com base no peso total | **DECIDIDO** (`§5`) | `CarryLoad.get_fill_ratio()` / `get_fill_percent()` calculados por peso total / capacidade efetiva |
| Peso unitário específico por tipo de material | **DECIDIDO** (`§5`) | `ResourceDefinition.unit_weight` aplicado em toda verificação/adição de carga |
| Retorno ao acampamento em `100%` ou quando não cabe mais 1 unidade | **DECIDIDO** (`§5`) | Transição para `TRANSPORTING` sempre que `free_weight < def.unit_weight` |
| Locais apropriados por categoria (`madeira`, `pedra`, `comida`) + evolução | **DECIDIDO** (`§5`, `§6`) | `StoragePoint` com categorias aceitas e `StorageRegistry` compartilhado entre T2 e T3+ |
| Capacidade expansível futuramente (traços, profissão, itens, melhorias) | **DECIDIDO** (`§5`) | Interface de modificadores (`set_capacity_bonus` / `CarryCapacityModifier`) em `UnitCarryLoad` |
| Pontos rústicos iniciais no Nível 1 sem construção prévia da T3 | **PROPOSTA** (`§5`, `§6`) | `CampWoodPile`, `CampStoneCairn`, `CampFoodCache` no acampamento inicial |
| Carga multi-recurso na unidade e entrega de carga parcial ao esgotar fonte | **PROPOSTA** (`§5`) | `UnitCarryLoad` indexado por `resource_id`; entrega encadeada e descarga parcial segura |
| Valores numéricos de peso, capacidade, ciclo, rendimento e slots | **ABERTO** (`§5`) | Externalizados exclusivamente em `.tres` com defaults iniciais para validação |
| Comportamento se todos os depósitos estiverem cheios/bloqueados | **ABERTO** (`§5`) | Carga preservada na unidade; falha explícita sem perda nem duplicação (`T2` sem teto punitivo) |

---

## 4. Arquitetura da Capacidade de Carga e Conservação de Recursos

### 4.1 Lei de conservação e aritmética exata (sem arredondamento ou perda)
Para impedir bugs clássicos de ponto flutuante (`0.1 + 0.2`), lotes que ultrapassem `100%` ou frações perdidas:
1. **Quantidades sempre em inteiros:** `ResourceNode`, `UnitCarryLoad` e `SettlementInventory` armazenam quantidades exclusivamente como **inteiros não negativos** (`int >= 0`) por `resource_id: StringName`. Não existe fração de unidade de recurso.
2. **Pesos e capacidade em unidades inteiras de peso:** `ResourceDefinition.unit_weight: int` (`>= 1`, ex.: `peso 1` para `1 unit`, equivalente lógico a `0,1 kg` ou `1 u.p.`) e `CharacterDefinition.base_carry_capacity: int` (`>= 1`).
   - O peso total ocupado é exato: `used_weight = sum(qty * weight_of(id))`.
   - A porcentagem ocupada para interface é derivada deterministicamente desse valor:
     `fill_percent: float = clampf((float(used_weight) / float(effective_capacity)) * 100.0, 0.0, 100.0)`.
   - **Extensão futura:** se um dia for necessário granularidade decimal (ex.: `0,5 kg`), basta representar internamente em decigramas/centésimos inteiros na definição `.tres`.
3. **Extração limitada antes de tocar o nó (`pre-clamping`):**
   Ao concluir um ciclo de trabalho na fonte `node` de definição `def`:
   - `free_weight: int = carry_load.get_free_weight()`
   - `max_fit_units: int = free_weight / def.unit_weight` *(divisão inteira exata)*
   - Se `max_fit_units <= 0`: o trabalhador **não** extrai nada do nó e inicia imediatamente o retorno (`TRANSPORTING`).
   - `requested_extract: int = mini(def.yield_per_cycle, max_fit_units)`
   - `extracted: int = node.extract_amount(requested_extract)` *(que já faz `mini(requested_extract, remaining_amount)`)*
   - `accepted: int = carry_load.add_resource(def.resource_id, extracted, def.unit_weight)` *(garantidamente `accepted == extracted` porque a capacidade livre foi verificada antes da extração)*

Com esse contrato:
$$\Delta_{\text{ResourceNode}} + \Delta_{\text{UnitCarryLoad}} + \Delta_{\text{SettlementInventory}} = 0$$
em **todo** frame, incluindo lotes parciais por fim da jazida ou fim do espaço de carga!

### 4.2 Contratos da Carga Individual

#### A. Extensão de `CharacterDefinition` (`src/units/character_definition.gd`)
- `@export var base_carry_capacity: int = 20` (`> 0` obrigatório em `is_valid()`).

#### B. `UnitCarryLoad` (`src/units/unit_carry_load.gd`, `class_name UnitCarryLoad extends RefCounted` ou `Node` filho de `Unit`)
Sugere-se `RefCounted` composto diretamente dentro de `Unit` (zero overhead de nó extra na `SceneTree`, preservando nós por cena para a Intel UHD 620) com sinal emitido via `Unit` ou no próprio `UnitCarryLoad`:
- **Sinais:**
  - `load_changed(used_weight: int, max_capacity: int, fill_percent: float, items_snapshot: Dictionary)`
- **Estado privado:**
  - `_base_capacity: int`
  - `_capacity_modifiers: Dictionary` (`source_id: StringName -> delta: int`, pronto para traços, profissão, ferramentas ou melhorias futuras)
  - `_items: Dictionary` (`resource_id: StringName -> quantity: int`, mantendo apenas entradas `> 0`)
  - `_unit_weights: Dictionary` (`resource_id: StringName -> unit_weight: int`, armazenado junto para recalcular peso total instantaneamente sem depender de lookups externos ao descarregar ou calcular `fill_percent` se a capacidade mudar!)
- **API pública concreta:**
  - `configure(base_capacity: int) -> void`
  - `set_capacity_modifier(modifier_id: StringName, bonus_weight: int) -> void` / `remove_capacity_modifier(modifier_id: StringName) -> void` *(gancho limpo T3–T6; `effective_capacity = maxi(1, _base_capacity + sum_modifiers)`)*
  - `get_effective_capacity() -> int`
  - `get_used_weight() -> int`
  - `get_free_weight() -> int`
  - `get_fill_ratio() -> float` / `get_fill_percent() -> float` (`0.0` a `100.0`)
  - `can_fit_one(unit_weight: int) -> bool`
  - `get_max_addable_units(unit_weight: int) -> int`
  - `is_empty() -> bool` / `is_full() -> bool`
  - `should_return_to_storage(next_unit_weight: int) -> bool` (`return is_full() or not can_fit_one(next_unit_weight)`)
  - `get_amount(resource_id: StringName) -> int`
  - `get_carried_resource_ids() -> Array[StringName]`
  - `get_items_snapshot() -> Dictionary`
  - `add_resource(resource_id: StringName, quantity: int, unit_weight: int) -> int` *(rejeita quantidade/peso inválidos; nunca excede `effective_capacity`; retorna exatamente quanto coube e emite `load_changed`)*
  - `remove_resource(resource_id: StringName, quantity: int) -> int` *(remove `mini(quantity, current)` atomicamente e emite `load_changed`)*
  - `clear_all() -> Dictionary` *(somente para reset explícito / snapshot)*

> **Separação estrita:** `UnitCarryLoad` nunca referencia `SettlementInventory` nem escreve nele. Somente uma transação explícita de entrega (`StoragePoint` + `SettlementInventory`) move itens de `UnitCarryLoad` para o estoque compartilhado.

---

## 5. Sistema de Armazenamento Progressivo (T2 → T3+)

### 5.1 Comparação e alternativas para a infraestrutura inicial de descarregamento

> **DECISÃO DE DESIGN EM ABERTO:** As regras aprovadas pelo proprietário exigem separação por categorias (madeira, pedra, alimentos) e evolução progressiva dos depósitos. A forma concreta como esses pontos são apresentados no primeiro acampamento permanece uma decisão de produto em aberto, analisada abaixo:

| Critério | Alternativa 1: Ponto Inicial Único Compartilhado | Alternativa 2: Áreas Rústicas Especializadas *(Recomendada pela Engenharia)* |
| :--- | :--- | :--- |
| **Aderência à narrativa do casal** | Neutra: um único espaço delimitado de acampamento (ex.: fogueira/lona no chão) | **Alta:** demarcações naturais no chão (pilha de galhos, monte de pedras, cesto de vime), sem qualquer edifício construído |
| **Separação por categoria** | Parcial no espaço: um ponto central que recebe tudo ou exige selecionar categorias | **Total:** destinos físicos e visuais separados no terreno desde o primeiro dia |
| **Contenção e RVO no acampamento** | Alta: todos os trabalhadores convergem exatamente para as mesmas coordenadas | **Baixa:** distribui o fluxo de locomoção e descarregamento entre 3 pontos distintos |
| **Antecipação indevida da T3** | Zero | **Zero:** são demarcadores rústicos de solo; depósitos construídos com obras continuam exclusivos da T3 |
| **Continuidade técnica para a T3** | Exige refatorar a navegação de entrega quando surgirem depósitos dedicados | **Direta:** depósitos construíveis da T3 herdam a mesma classe `StoragePoint` e o `StorageRegistry` |

**Recomendação técnica:** Adotar a **Alternativa 2 (Áreas Rústicas Especializadas)**, implementando **uma única classe modular `StoragePoint`** instanciada em três demarcações rústicas do acampamento inicial (`CampWoodPile` para madeira, `CampStoneCairn` para pedra e `CampFoodCache` para comida). Essa escolha preserva a narrativa de sobrevivência inicial (não há infraestrutura pré-existente nem obras da T3), respeita a separação por categorias e evita retrabalho ao introduzir os depósitos construíveis no futuro.

### 5.2 Contratos de Armazenamento

#### A. `StoragePoint` (`src/world/storage_point.gd`, `class_name StoragePoint extends Node3D`)
- **Grupo:** `GROUP_STORAGE_POINTS = &"storage_points"`.
- **Composição de cena:**
  - `SolidBody` (`StaticBody3D` em `CollisionLayers.MASK_OBSTACLES`, `collision_mask = 0`) → mantém NavMesh assada ao redor da pilha/cesta e evita caminhar por dentro do depósito.
  - `StoragePickArea` (`Area3D` em `CollisionLayers.MASK_BUILDINGS`, `monitorable = true`) → permite clique direito contextual de entrega manual (`PickResult.Kind.STORAGE`) e hover sem bloquear raycast sólido.
  - `VisualRoot` → malha placeholder rústica leve e de baixo custo (troncos empilhados, monte de pedras, cestos/caixote de provisões) reutilizando materiais existentes/compartilhados.
- **Propriedades configuráveis:**
  - `@export var storage_id: StringName`
  - `@export var display_name: String`
  - `@export var accepted_categories: Array[StringName] = []` *(ex.: `[&"wood"]` na T2; permite múltiplas categorias ou `"*"` em futuros armazéns gerais da T3+)*
  - `@export var dropoff_radius_m: float = 1.4` / `interact_tolerance_m: float = 0.6`
  - `@export var is_active: bool = true` *(desligável se construção em obra na T3)*
  - `@export var priority: int = 0` *(desempate futuro entre depósitos rústicos vs armazéns evoluídos)*
  - `@export var has_local_capacity: bool = false` / `local_capacity: int = 0` *(inativo na T2 por padrão — mantém estoque coletivo como autoridade; preparado para evolução T3 com depósito cheio/ampliação sem refatorar API!)*
- **Sinais:**
  - `delivery_received(storage_point: StoragePoint, resource_id: StringName, amount: int)`
  - `availability_changed(storage_point: StoragePoint)`
- **API pública concreta:**
  - `can_accept_category(resource_id: StringName) -> bool`
  - `get_accepted_categories() -> Array[StringName]`
  - `get_remaining_storage_space(resource_id: StringName) -> int` *(retorna `INF`/sentinel `-1` indicando ilimitado na T2 quando `has_local_capacity == false`, ou `maxi(0, local_capacity - stored)` na T3+)*
  - `get_interaction_anchor() -> Vector3`
  - `get_max_interact_distance_xz() -> float`
  - `deposit_from_carry_load(carry_load: UnitCarryLoad, settlement_inventory: SettlementInventory, preferred_order: Array[StringName] = []) -> Dictionary`
    - **Contrato atômico de transferência:** para cada `res_id` na carga compatível com `can_accept_category(res_id)`:
      1. Calcula `qty = carry_load.get_amount(res_id)` e limita por `get_remaining_storage_space` (se aplicável).
      2. Chama `removed = carry_load.remove_resource(res_id, transfer_qty)`.
      3. Chama `credited = settlement_inventory.add_resource(res_id, removed)`.
      4. Se por erro defensivo `credited != removed`, restaura diferença ou falha com erro explícito (garantia anti-perda/duplicação).
      5. Emite `delivery_received` e retorna `{ &"transferred": { res_id: credited }, &"total_units": total }`.

#### B. `StorageRegistry` (`src/economy/storage_registry.gd`, `class_name StorageRegistry extends Node`)
Composto explicitamente em `MainScene` (sem autoload), evitando buscas globais repetitivas em `SceneTree` e preparando substituição/adição dinâmica de edifícios na T3:
- Mantém lista registrada de `StoragePoint` ativos (auto-descobre de `TestMap` na inicialização e escuta `register_storage` / `unregister_storage`).
- `find_best_storage_for(resource_id: StringName, from_pos: Vector3, world_nav: WorldNavigation) -> StorageResult`
  - Filtra pontos com `is_active` e `can_accept_category(resource_id)` e espaço > 0.
  - Ordena por maior `priority` (futuro) e menor distância XZ; calcula um slot alcançável na borda (`snap_to_navmesh` + `is_position_reachable` evitando posições ocupadas) e verifica alcançabilidade via `WorldNavigation` antes de mandar a unidade andar!

---

## 6. Picking Contextual, Estados da Unidade e Ciclo Completo de Trabalho

### 6.1 Extensão do Picking (`PickResult`, `WorldPicker`, `CommandController`, `RtsInputController`)
- `PickResult.Kind`: `NONE`, `UNIT`, `RESOURCE`, `STORAGE`, `GROUND`, `OBSTACLE`.
- `PickResult` ganha `storage_point: StoragePoint = null`, `from_storage(...)` e `is_storage() -> bool`.
- `WorldPicker.pick_along_ray` consulta `MASK_SELECTION` (áreas), `MASK_RESOURCES` (áreas), `MASK_BUILDINGS` (áreas) e `MASK_WORLD_SOLID` (corpos), usando o filtro anti-auto-oclusão para `ResourceNode` e `StoragePoint` e selecionando o hit interativo não ocluído mais próximo à câmera.
- **Clique direito contextual no `CommandController`:**
  - `RESOURCE`: aloca slots ao redor do recurso e emite `GatherOrder` (a unidade pode já estar carregando restos de outra coleta compatível ou mista; ver Seção 6.3).
  - `STORAGE`: se unidades selecionadas tiverem itens em `UnitCarryLoad` compatíveis com aquele depósito (ou qualquer carga se o clique indicar entrega), emite `DeliverOrder(storage_point, storage_registry, settlement_inventory)` — dando ao jogador um comando direto e intuitivo para descarregar uma unidade interrompida no meio do caminho! Se a carga estiver vazia, comporta-se de forma segura aproximando-se do ponto sem erro.
  - `GROUND` / `OBSTACLE` / `UNIT`: comportamento preservado da T1 (`MoveOrder`); nunca apaga a carga carregada na unidade ao cancelar uma `GatherOrder` por um movimento!

### 6.2 Estados da Unidade (`Unit.State`)
Expandir `Unit.State` (`src/units/unit.gd`) para alinhar diretamente com o ciclo físico aprovado e com a proposta `§4` do GDD:
- `IDLE` (`"IDLE"`)
- `MOVING` (`"MOVING"`) — locomoção comum (`MoveOrder`) ou aproximação até a fonte de recurso.
- `WORKING` (`"WORKING"`) — executando extração na fonte (`UnitMovement` parado, `avoidance_priority = AVOIDANCE_PRIORITY_IDLE`, `face_position` voltado para a fonte).
- `TRANSPORTING` (`"TRANSPORTING"`) — retornando fisicamente ao acampamento carregando materiais até um `StoragePoint` compatível.

`UnitOrder` passa a expor `get_requested_unit_state() -> int` (padrão `Unit.State.MOVING` para compatibilidade integral com `MoveOrder`), sincronizado por `Unit` após `start()` e em cada `_physics_process()`.

### 6.3 Máquina de Estados de `GatherOrder` e `DeliverOrder`

```text
                        [APPROACHING_RESOURCE] (State.MOVING)
                          │                 ▲
   free_weight <          │ chegou no       │ após descarregar tudo e
   unit_weight (já        │ alcance         │ fonte ainda harvestable()
   estava cheia)          ▼                 │
        │             [HARVESTING] ─────────┴────────────────────┐
        │             (State.WORKING)                            │
        │                 │                                      │
        │                 │ ciclo completo:                      │ fonte esgotou
        │                 │ extrai min(yield, max_fit, rem)      │ com carga == 0
        │                 ▼                                      ▼
        │       carga >= limite OU (!cabe_mais) OU           [SUCCEEDED]
        │       (fonte esgotou && carga > 0)                  (IDLE)
        │                 │
        ▼                 ▼
  ┌───► [TRANSPORTING_TO_STORAGE] (State.TRANSPORTING)
  │                       │
  │                       │ chegou ao StoragePoint compatível
  │                       ▼
  │               [UNLOADING] → move itens compatíveis
  │                       │     CarryLoad ──► SettlementInventory
  │                       │
  │     ainda há outro    ├──► CarryLoad não vazio (multi-recurso):
  └───── recurso na carga ┘    busca próximo StoragePoint compatível
                          │
                          ├──► CarryLoad vazio && fonte harvestable() && auto_repeat:
                          │    reserva novo slot (se necessário) → [APPROACHING_RESOURCE]
                          │
                          └──► CarryLoad vazio && (!harvestable() || !auto_repeat):
                               libera slot → [SUCCEEDED] (IDLE)
```

- **`DeliverOrder` (`src/units/orders/deliver_order.gd`):** executa exclusivamente o subfluxo `TRANSPORTING_TO_STORAGE → UNLOADING` (incluindo encadeamento se houver múltiplas categorias na carga) até `CarryLoad.is_empty()`, encerrando `SUCCEEDED`. Pode ser disparada manualmente por clique direito em depósito ou reutilizar o mesmo helper de entrega interno da `GatherOrder` sem duplicação de código (`GatherOrder` e `DeliverOrder` podem compartilhar um helper puro de resolução/descarga de depósito!).

### 6.4 Análise Explícita de Casos de Borda (§4)

| Cenário Crítico | Comportamento Projetado e Garantia de Integridade |
| :--- | :--- |
| **1. Carga completa ou sem espaço para +1 unidade** | Se `max_carry = 10`, pedra pesa `4` e carga tem `8/10` (`80%`), `free_weight = 2 < 4`. Antes de iniciar novo ciclo de extração (ou logo após extrair `min(yield, max_fit)`), detecta `should_return_to_storage(unit_weight)` → entra em `TRANSPORTING` sem nunca ultrapassar `100%`. |
| **2. Fonte se esgota com carga parcial na unidade** | Ex.: fonte tinha apenas `1` unidade restante; trabalhador extrai `1` (`30%` de carga) e nó entra em `DEPLETED`. Como `!node.is_harvestable()` e `carry_load.is_empty() == false`, **não** abandona o recurso no bolso: muda para `TRANSPORTING`, vai ao depósito, descarrega a carga parcial no `SettlementInventory` e encerra como `SUCCEEDED`. |
| **3. Cancelamento ou substituição durante `TRANSPORTING`** | Se o jogador clicar com o direito no chão (`MoveOrder`) ou em outro recurso no meio da caminhada de volta, `GatherOrder.cancel(REASON_REPLACED)` interrompe o movimento e **preserva intactos** os materiais dentro de `UnitCarryLoad`. Nada é destruído nem creditado antecipadamente ao estoque. O jogador pode depois clicar em outro recurso (completando a carga) ou clicar direito em um depósito para descarregar (`DeliverOrder`). |
| **4. Múltiplos recursos dentro da mesma carga** | `UnitCarryLoad` armazena `Dictionary[StringName, int]`. Se uma unidade tem `3 madeiras` (peso 6/20) e vai colher frutinhas (`comida`, peso 1), colhe até 14 comidas (`100%`). Ao voltar ao acampamento, descarrega primeiro no `CampFoodCache` (transferindo só `&"food"`), percebe que ainda resta `&"wood"` na carga, roteia automaticamente até `CampWoodPile` para entregar as `3 madeiras`, e só então retorna à fonte de comida (se ainda válida). |
| **5. Falha ao encontrar caminho até o depósito (ou sem depósito compatível)** | `StorageRegistry.find_best_storage_for` verifica alcançabilidade real pela `WorldNavigation`. Se nenhum depósito compatível existir ou todos estiverem inacessíveis (ex.: cercados), `GatherOrder`/`DeliverOrder` encerra com `Status.FAILED` (`REASON_STORAGE_UNREACHABLE` ou `REASON_NO_STORAGE`), **mantém toda a carga intacta em `UnitCarryLoad`** e volta a `IDLE` sem travar nem duplicar itens. |
| **6. Destruição ou invalidação da fonte (`queue_free` ou remoção)** | Durante `HARVESTING` ou `APPROACHING`: se `!is_instance_valid(node) || !node.is_inside_tree()`, se a carga atual estiver vazia encerra com `FAILED (REASON_INVALID_RESOURCE)`; se a unidade já carregar `> 0` itens coletados antes da invalidação, muda para `TRANSPORTING` para salvar/entregar a carga já extraída antes de finalizar! Durante `TRANSPORTING`: a perda da fonte não impede entregar o que já foi coletado; ao terminar a descarga, encerra sem voltar à fonte inválida. |
| **7. Dois ou mais moradores coletando e descarregando simultaneamente** | Na fonte: `ResourceNode` reserva até `max_concurrent_workers` slots radiais distintos (`>= 2 * agent_radius + clearance`). Ao longo do transporte ida/volta: RVO (`NavigationAgent3D`) evita interpenetração. No depósito: `StoragePoint` calcula um ponto periférico alcançável de descarga (`dropoff_radius_m`) considerando `_collect_occupied_positions` ou aceita múltiplos entregadores em ângulos distintos ao redor da pilha/cesta para evitar deadlock na descarga. |
| **8. Ausência de espaço de armazenamento (T3+ com depósito cheio) e descarga parcial** | Na T2 inicial os pontos rústicos operam sem limite punitivo local (`has_local_capacity = false`), mantendo espaço sempre disponível. Ainda assim, `StoragePoint.deposit_from_carry_load` já aceita limite por categoria: se um depósito futuro aceitar só `k < qty` unidades, apenas `k` são removidas de `UnitCarryLoad` e creditadas em `SettlementInventory`, enquanto `qty - k` permanecem na unidade, que tenta outro depósito compatível ou falha com `REASON_STORAGE_FULL` preservando exatamente o restante sem perda. |

---

## 7. Decisões em Aberto vs Soluções Internas de Engenharia

- **Soluções internas de engenharia (já definidas na arquitetura):**
  - Aritmética inteira para quantidades e pesos; `Dictionary[StringName, int]` em `UnitCarryLoad` e `SettlementInventory`.
  - Separação `SolidBody` (`MASK_OBSTACLES`) + `PickArea` (`MASK_RESOURCES` / `MASK_BUILDINGS`) para compatibilidade com `test_test_map.gd` e zero rebake de NavMesh.
  - Desacoplamento via `UnitCarryLoad`, `StoragePoint`, `StorageRegistry`, `DeliverOrder` e `GatherOrder`.
  - Composição explícita em `MainScene` sem autoloads ocultos.
- **Decisões de produto ainda ABERTAS (não fechadas pela arquitetura):**
  1. **Valores numéricos de peso, capacidade e coleta (`ABERTO` em `GDD §5`):** pesos iniciais sugeridos por unidade (`comida = 1`, `madeira = 2`, `pedra = 4`), capacidade base sugerida (`20` para os protagonistas → cabem `20` comidas, `10` madeiras ou `5` pedras por viagem; ciclos de `2,0–2,5 s`), todos configuráveis via `.tres`.
  2. **Busca automática de nova fonte ao esgotar (`D2-2`, `ABERTO`):** na base da T2, após entregar a carga parcial da fonte esgotada, recomenda-se encerrar a ordem como `SUCCEEDED` (`IDLE`) em vez de sair procurando árvores aleatórias pelo mapa sem comando do jogador; retargeting automático por raio pode ser avaliado futuramente como melhoria opcional de `JobSystem`.
  3. **Finitude vs regeneração de nós (`D2-3`, `ABERTO`):** finitos com estado visual esgotado na T2 (`regenerates = false` padrão em `ResourceDefinition`).
  4. **Comportamento se depósitos futuramente tiverem capacidade limitada cheia (`ABERTO` para T3+):** na T2 os pontos iniciais não possuem teto local bloqueante; teto físico por construção entra com a T3.

---

## 8. Interface Mínima Reativa e Guardrails na Intel UHD 620

### 8.1 Interface Mínima (`UiLayer`, tudo com `mouse_filter = MOUSE_FILTER_IGNORE`)
1. **`SettlementResourceHud`:** exibe `Madeira: X | Pedra: Y | Comida: Z` no canto superior esquerdo. Atualiza exclusivamente por sinal `SettlementInventory.resource_changed` — provando visualmente que o contador permanece em `0` enquanto a unidade corta a árvore e só sobe quando ela descarrega no depósito!
2. **`UnitCarryStatusHud` (ou painel discreto de seleção):** quando houver unidade selecionada (`SelectionManager.selection_changed`), exibe de forma discreta o estado (`Ocioso / Movendo / Trabalhando / Transportando`), a **ocupação da carga em `0%–100%`** (`ex.: Carga: 60% (12/20) — Madeira x6`) conectado exclusivamente a `unit.carry_load_changed` e `unit.state_changed` (sem polling em `_process`!).

### 8.2 Guardrails de Desempenho (Intel UHD 620, 1920×1080)
Com a introdução do transporte físico, os dois protagonistas passam mais tempo em deslocamento ativo ida-e-volta com RVO (`~0,26–0,30 ms` por unidade móvel segundo `KNOWN_ISSUES.md`):
- Manter `_process` desligado em `ResourceNode`, `StoragePoint`, `SettlementInventory`, `SettlementResourceHud` e `UnitCarryStatusHud`.
- Usar no máximo 1 pequena `MeshInstance3D` composta ou poucos submeshes com materiais compartilhados nos 3 pontos de armazenamento e no `BerryBushPlaceholder`, avaliando sombras (`cast_shadow`) e `p95 <= 16,7 ms` em medição real no `tools/perf.ps1` ao final da T2.
- Desativar locomoção/avoidance ativo (`AVOIDANCE_PRIORITY_IDLE`) enquanto a unidade estiver parada em `WORKING`.
- Incluir no `T2.6` um cenário específico de estresse/perf validando múltiplas unidades em vai-e-vem simultâneo entre recursos e depósitos na resolução `1920×1080`.
