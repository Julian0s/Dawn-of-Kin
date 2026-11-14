# Dawn of Kin — Proposta de Arquitetura e Planejamento Incremental da T3 (Construção)

**Status:** PROPOSTA TÉCNICA PARA REVISÃO (somente planejamento autorizado; nenhuma linha de código T3 implementada)<br>
**Base Auditada:** Branch `main` (`f7c24592e3a6d936dbcb63f648c474280695ab9b`), tag `t2-complete`<br>
**Fonte Normativa:** [Dawn_of_Kin_GDD_v1.0.md](../Dawn_of_Kin_GDD_v1.0.md) (com referências informativas à minuta [Dawn_of_Kin_GDD_v1.1.md](../Dawn_of_Kin_GDD_v1.1.md))<br>
**Engine e Alvo de Referência:** Godot `4.7.2.stable` (`gl_compatibility`), Intel UHD Graphics 620 (`1920×1080`, meta `p95 <= 16,7 ms` em tomada CA)

---

## 1. Resumo da Auditoria Técnica da Base Existente (`main`)

A inspeção direta do código-fonte na `main` confirma uma base modular, tipada e desacoplada, sem *singletons* ocultos, pronta para receber a camada de construção sem quebrar os contratos da T1/T2:

- **`src/core/collision_layers.gd`**: já reserva explicitamente `LAYER_BUILDINGS = 5` e `MASK_BUILDINGS = 1 << 4`. **Lacuna identificada:** `MASK_WORLD_SOLID` atualmente inclui apenas `MASK_TERRAIN | MASK_OBSTACLES`. Como `WorldNavigation` usa `MASK_WORLD_SOLID` para o *bake* do `NavigationMesh` e `WorldPicker` usa `MASK_WORLD_SOLID` para oclusão sólida, construções colocadas apenas em `LAYER_BUILDINGS` não bloquearão navegação nem oclusão de raio sem ajuste explícito.
- **`src/economy/`**:
  - `SettlementInventory` atua como fachada de autoridade única sobre `SettlementStorageSource` (`GroundPileManager`).
  - **Lacuna identificada:** `SettlementStorageSource`, `GroundPileManager` e `SettlementInventory` possuem `can_deposit_batch()` e `deposit_batch()` com rollback atômico, mas **não possuem `can_withdraw_batch(amounts: Dictionary)` nem `withdraw_batch(amounts: Dictionary)`**. Hoje `withdraw()` opera apenas sobre um `resource_id` por vez, o que impede consumo atômico de custos compostos (ex.: madeira + pedra).
  - **Lacuna identificada:** `GroundPileManager.step_decay()` aplica um único `decay_multiplier` global vindo de `CampStorageZone`. Não há suporte a redução/anulação de deterioração por categoria ou por capacidade/zona de depósito construído.
- **`src/units/` e `src/units/orders/`**:
  - `Unit` executa qualquer `UnitOrder` via `issue_order()`, `physics_update()`, `cancel_current_order()` e já possui `Unit.State.WORKING` + animação procedural por categoria em `_update_work_and_load_visuals()` (com fallback genérico para categorias desconhecidas).
  - `GatherSlotPlanner` resolve *slots* navegáveis ao redor de `ResourceSource` e dentro de `CampStorageZone`, evitando sobreposição via `collect_other_unit_positions()` e `get_reserved_target()`. **Reutilizável:** o mesmo padrão geométrico pode ser generalizado ou espelhado para perímetros de obras (`BuildSlotPlanner`).
  - `UnitMovement` aplica redução de velocidade proporcional ao peso (`UnitCarryLoad`) e mantém `4,8 m/s` sem carga (ajuste `B1`).
- **`src/navigation/world_navigation.gd`**:
  - `WorldNavigation` já implementa `request_rebake()` assíncrono com verificação de iteração no `NavigationServer3D`, `snap_to_navmesh()`, `find_path()` e `is_position_reachable()`.
- **`src/rts/`**:
  - `PickResult` e `WorldPicker` suportam `UNIT`, `GROUND`, `OBSTACLE` e `RESOURCE_SOURCE` com verificação de oclusão. Falta `CONSTRUCTION_SITE` / `BUILDING` e um modo de posicionamento (ou estado explícito no controlador de entrada) que suspenda seleção/movimento normal durante o posicionamento de uma obra.
  - `CommandController` despacha ordens contextuais por `PickResult.Kind` e pode rotear clique direito em obra em andamento para `ConstructOrder`.
- **`src/main/main.gd` e `levels/test_map/`**:
  - `MainScene` compõe todas as dependências explicitamente em `_ready()`. Falta um nó raiz de construções (ex.: `Buildings` em `TestMap`) e um coordenador de construção (`ConstructionManager` / `BuildingRegistry`) conectado ao `SettlementInventory`, `WorldNavigation` e `ResourceHud`.
- **`src/ui/`**:
  - `ResourceHud` aplica `HudStyle.apply_mouse_filter_ignore_recursive(self)` para não bloquear cliques no mundo. Controles interativos da T3 (botão de construir, seleção de planta, cancelar obra) exigirão `MOUSE_FILTER_STOP` apenas nos botões/painéis interativos, mantendo o restante da HUD passivo.

---

## 2. Matriz GDD × Código Atual × Lacunas (T3)

| Requisito / Referência (GDD v1.0 + notas v1.1) | Status | Evidência no Código Atual (`main` `f7c2459`) | Lacuna para T3 |
|---|---|---|---|
| Início sem construções humanas pré-existentes; administração pelo exterior, sem interiores jogáveis (§6, **DECIDIDO**) | Atendido (início limpo) | `test_map.tscn` possui apenas terreno, obstáculos naturais, fontes e `CampStorageZone` lógica | Criar cenas de canteiro/edifício puramente externas, sem interiores |
| Posicionar obra no terreno pelo jogador (§6, §13 T3, **DECIDIDO**) | Não implementado | `WorldPicker` faz raycast no terreno (`PickResult.Kind.GROUND`); sem modo de posicionamento | Modo de posicionamento (`PlacementController`), prévia fantasma sem grid visível, validação de terreno/colisão/acessibilidade |
| Gastar recursos compartilhados disponíveis — madeira e pedra do estoque coletivo real (§6, §13 T3, **DECIDIDO**) | Parcial | `SettlementInventory` + `GroundPileManager` mantêm saldo real; `withdraw()` é unitário (1 recurso por chamada) | `can_withdraw_batch()` e `withdraw_batch()` atômicos com rollback (ou reserva/entrega equivalente, conforme decisão do proprietário) |
| Designar trabalhadores para construir e acompanhar progresso (§6, §13 T3, **DECIDIDO**) | Parcial | `Unit`, `UnitOrder`, `Unit.State.WORKING` e `GatherSlotPlanner` existem | `PickResult.Kind.CONSTRUCTION_SITE`, `ConstructOrder`, slots de construção ao redor do perímetro, barra/indicador de progresso externo |
| Concluir abrigo básico/casa visível externamente (§6, §13 T3, §14.4, **DECIDIDO**) | Não implementado | `CollisionLayers.LAYER_BUILDINGS` reservada | `BuildingDefinition`, `ConstructionSite`, `BuildingInstance` (abrigo concluído), atualização de colisão e `WorldNavigation` |
| Armazéns/depósitos protetores construíveis que reduzem ou eliminam perda por exposição (§5, §6 **DECIDIDO**; GDD v1.1 §13 inclui na T3) | Parcial | `GroundPileManager.step_decay()` usa `CampStorageZone.decay_multiplier` global | Integração de edifício depósito/abrigo de estoque que proteja recursos contra deterioração sem duplicar saldo no `SettlementInventory` |
| Abrigo completado e **persistido** (§13 T3); save/load em disco previsto na T4 (§13 T4) | **ABERTO / PENDENTE** | Sem sistema de persistência em disco; estado existe apenas na sessão em memória | Decisão do proprietário entre persistência em memória na T3 (até T4) ou persistência mínima em disco já na T3 |
| Interface legível em câmera isométrica sem microgestão (§14.5) | Parcial | `ResourceHud`, `HudStyle`, `SelectedUnitPanel`, `SettlementStockpilePanel` | Botão/painel mínimo de construção, feedback de custo/insuficiência, seleção/inspeção de obra e botão de cancelamento |
| Custos, dimensões físicas, tempo de construção e layout exato de UI | **ABERTO** | Nenhum valor numérico aprovado no GDD | Parametrizar em `BuildingDefinition` (`.tres`) com valores provisórios claramente marcados para aprovação do proprietário |

---

## 3. Arquitetura Proposta (Modular e Simples)

A proposta preserva a separação de responsabilidades da T1/T2 (sem *god scripts* e sem autoloads ocultos), compondo os novos módulos em `MainScene`:

### 3.1. Definições de Edifícios e Custos (`src/buildings/building_definition.gd`)
- `BuildingDefinition extends Resource`:
  - `building_id: StringName` (ID estável, ex.: `&"shelter_basic"`, `&"storage_depot"`).
  - `display_name: String`.
  - `category: Category` (`SHELTER`, `STORAGE`, etc.).
  - `footprint_size: Vector2` (largura × profundidade em metros no plano XZ, para validação e slots de obra sem impor grid).
  - `resource_costs: Dictionary` (`{&"wood": int, &"stone": int}`) — valores configurados em arquivos `.tres` sob `data/buildings/`, nunca fixados em código.
  - `build_work_required: float` (trabalho total em segundos-construtor equivalente).
  - `max_builders: int` (limite opcional de construtores simultâneos no perímetro).
  - `storage_protection_factor: float` / `protected_categories: Array[ResourceDefinition.Category]` (para uso futuro/imediato em depósitos).
  - Método `is_valid() -> bool` seguindo o padrão de `ResourceDefinition` e `CharacterDefinition`.

### 3.2. Prévia de Posicionamento sem Grid Visível (`src/buildings/placement_controller.gd` + `placement_preview.gd`)
- **Sem grid visível:** o posicionamento é contínuo no terreno (`PickResult.Kind.GROUND` / raycast em `MASK_TERRAIN`), alinhado suavemente à superfície do terreno e com rotação discreta ou contínua opcional (ex.: tecla `R`), mantendo estética orgânica de acampamento.
- `PlacementPreview` (`Node3D` leve, sem sombras e sem colisão física): exibe o volume externo aproximado do edifício com material translúcido verde (válido) ou vermelho (inválido), atualizado apenas quando o ponteiro se move ou o estoque muda.

### 3.3. Validação de Localização e Caminhos Acessíveis (`src/buildings/placement_validator.gd`)
Função pura/determinística `validate_placement(def, world_pos, rotation_y, world_nav, space_state, camp_zone, ground_pile_manager)` verificando:
1. **Limites e terreno:** posição dentro de `map_bounds`, sobre `MASK_TERRAIN`, com desnível/inclinação máxima aceitável nos cantos da *footprint* (amostragem de 4 cantos + centro via raycast vertical em `MASK_TERRAIN` — impede obra flutuando em beira de rampa/platô).
2. **Sem sobreposição física:** consulta `PhysicsShapeQueryParameters3D` (BoxShape da *footprint* com pequena margem) contra `MASK_OBSTACLES | MASK_RESOURCES | MASK_BUILDINGS | MASK_UNITS` + distância mínima de `GroundResourcePile` ativas se posicionado sobre a `CampStorageZone` (evita esmagar pilhas existentes ou bloquear totalmente o ponto âncora do acampamento).
3. **Acessibilidade navegável:** `world_nav.is_navigation_ready()` e existência de ao menos um ponto de abordagem válido no perímetro da *footprint* alcançável a partir das unidades selecionadas (ou da zona do acampamento) via `world_nav.find_path()`.

### 3.4. Reserva ou Consumo Atômico de Recursos (`src/economy/`)
- Adicionar em `SettlementStorageSource`, `GroundPileManager` e `SettlementInventory`:
  - `can_withdraw_batch(amounts: Dictionary) -> bool`
  - `withdraw_batch(amounts: Dictionary) -> bool` (com snapshot/rollback exato das pilhas, espelhando `deposit_batch()`).
- Isso garante que a dedução de `wood` + `stone` seja **tudo-ou-nada**, preservando a invariante de autoridade única entre `GroundResourcePile` e `SettlementInventory`. (Ver Alternativa A1 sobre momento do desconto e reembolso.)

### 3.5. Canteiro de Obra, Ordens e Designação de Trabalhadores (`src/buildings/` + `src/units/orders/`)
- `ConstructionSite` (`StaticBody3D` / `Node3D` no grupo `construction_sites`):
  - Estados explícitos: `PLACED` / `UNDER_CONSTRUCTION` / `COMPLETED` / `CANCELLED`.
  - Mantém `work_progress: float`, `work_required: float`, lista de construtores ativos/reservados e sinal `progress_changed(ratio)` / `completed(building)` / `cancelled(site)`.
  - Colisão em `LAYER_BUILDINGS` (e `MASK_OBSTACLES` apenas se optarmos por incluir `LAYER_BUILDINGS` em `MASK_WORLD_SOLID` — ver Alternativa A2).
  - Visual externo progressivo leve (ex.: estacas/fundação -> estrutura -> edifício concluído), sem `cast_shadow` pesado para proteger a Intel UHD 620.
- `ConstructOrder extends UnitOrder`:
  - Fases: `APPROACHING_SITE` -> `BUILDING`.
  - Usa `BuildSlotPlanner` (mesma lógica do `GatherSlotPlanner` com *offset* retangular/circular ao redor da `footprint_size`) e implementa `get_reserved_target() -> Vector3` para evitar colisões entre construtores.
  - Em `BUILDING`, define `Unit.State.WORKING`, aplica progresso proporcional a `delta * build_rate` no `ConstructionSite` e encerra como `SUCCEEDED` quando o canteiro conclui.
- `PickResult` e `CommandController`:
  - Novo `PickResult.Kind.CONSTRUCTION_SITE` (e opcionalmente `BUILDING` para seleção/inspeção).
  - Clique esquerdo em canteiro/edifício: seleciona a construção para exibir estado/progresso na HUD e permitir cancelamento.
  - Clique direito com unidades selecionadas sobre `ConstructionSite`: emite `ConstructOrder` para todas as unidades selecionadas (respeitando `max_builders` se definido).

### 3.6. Progresso, Interrupção, Cancelamento e Conclusão
- **Múltiplos trabalhadores:** cada construtor em `BUILDING` soma trabalho ao mesmo `ConstructionSite.apply_work(amount)`; o progresso é contínuo e compartilhado.
- **Interrupção:** se o jogador der outra ordem ao trabalhador (mover ou coletar), `Unit.issue_order()` cancela a `ConstructOrder` atual, libera o slot no canteiro, e o `ConstructionSite` **preserva o progresso acumulado** aguardando outro construtor.
- **Cancelamento pelo jogador:** disponível apenas enquanto `UNDER_CONSTRUCTION`. Cancela ordens ativas nos construtores vinculados, remove o canteiro, libera navegação e aplica a política de reembolso definida pelo proprietário (ver §5).
- **Conclusão:** ao atingir `work_progress >= work_required`, `ConstructionSite` dispara a transição para `BuildingInstance` concluído (abrigo funcional visível externamente), emite `completed`, libera as ordens dos construtores para `IDLE` e atualiza a malha de navegação.

### 3.7. Integração Futura e Gradual de Depósitos Protegidos
Para atender à evolução de armazenamento (pilhas expostas -> depósitos que reduzem/eliminam deterioração) sem duplicar saldos no `SettlementInventory`:
- Um `StorageDepot` concluído expõe capacidade de proteção (por categoria ou geral) e um `protected_decay_multiplier` (ex.: `0.0` para proteção total ou `0.25` para proteção parcial).
- O `GroundPileManager` (ou um `CompositeStorageSource` coordenando pilhas expostas + compartimentos de depósito) passa a manter a fonte única de verdade, permitindo que o `SettlementStockpilePanel` informe com exatidão quanto do estoque está **exposto** vs **protegido** (ver Alternativa A3).

### 3.8. Interface Mínima Preservando a Leitura RTS (`src/ui/`)
- Barra compacta de construção (ex.: canto inferior esquerdo ou integrada ao `ResourceHud`) com botões para as definições disponíveis (Abrigo Básico, e posteriormente Depósito), exibindo custo em madeira/pedra e estado habilitado/desabilitado conforme `SettlementInventory`.
- Apenas os botões/painéis interativos usam `MOUSE_FILTER_STOP`; o restante da HUD continua `MOUSE_FILTER_IGNORE`.
- Painel contextual mínimo quando um `ConstructionSite` ou `BuildingInstance` é selecionado: nome, estado (`Em construção` / `Concluído`), barra/texto de progresso (`0%–100%`) e botão `Cancelar Obra` durante a construção.
- Atalho `ESC` ou clique direito em modo de posicionamento cancela o posicionamento antes de consumir recursos.

---

## 4. Alternativas Arquiteturais e Recomendações

### A1. Consumo de Recursos: Upfront Atômico vs. Reserva Lógica vs. Transporte Físico ao Canteiro
| Alternativa | Descrição | Prós | Contras |
|---|---|---|---|
| **A1.1 — Consumo atômico ao posicionar (Recomendada para T3 núcleo)** | `withdraw_batch()` desconta madeira e pedra do `SettlementInventory` no instante em que a obra é posicionada. | Simples, determinístico, evita saldo "fantasma" ou dupla alocação entre obras simultâneas; alinha-se ao GDD ("posiciona obra, descontar recursos, designar construtor"). | Se o jogador cancelar a obra, exige política explícita de reembolso (ex.: `deposit_batch()` parcial/total) e espaço na `CampStorageZone`. |
| **A1.2 — Reserva lógica no estoque** | Recursos ficam marcados como reservados nas pilhas até o início/fim da obra. | Evita recriar pilhas no cancelamento. | Complexifica `GroundPileManager`, `step_decay()` (recurso reservado deteriora?) e HUD (disponível vs reservado). |
| **A1.3 — Transporte físico até o canteiro** | Trabalhadores buscam madeira/pedra nas pilhas e carregam até a obra antes de construir. | Máxima fidelidade física ao estilo T2. | Multiplica estados de ordem (`FETCH -> DELIVER_TO_SITE -> BUILD`), aumenta risco de *deadlock* e foge do escopo mínimo aprovado para T3.0. |

**Recomendação:** **A1.1** para o núcleo da T3, mantendo a porta aberta para evolução futura se desejado.

### A2. Atualização da Navegação (`WorldNavigation`) ao Posicionar/Concluir Obras
| Alternativa | Descrição | Prós | Contras |
|---|---|---|---|
| **A2.1 — Incluir `MASK_BUILDINGS` em `MASK_WORLD_SOLID` + `request_rebake()` (Recomendada)** | O canteiro/edifício entra em `LAYER_BUILDINGS`; ao posicionar, concluir ou cancelar, chama `WorldNavigation.request_rebake()`. | Caminho real recalculado no `NavigationMesh` (unidades contornam a obra de verdade, `find_path()` e `BuildSlotPlanner` permanecem 100% consistentes). `WorldNavigation` já possui `request_rebake()` testado. | Pequeno pico de CPU no momento do *bake* (apenas no evento pontual de colocar/cancelar/concluir, nunca por frame). |
| **A2.2 — Apenas `NavigationObstacle3D`** | Usa obstáculo RVO dinâmico sem refazer o `NavigationMesh`. | Zero tempo de *rebake*. | Em Godot 4, `NavigationObstacle3D` sem *bake* só faz desvio local RVO; `find_path()` continuaria traçando caminhos por dentro do prédio. |

**Recomendação:** **A2.1**, medindo `get_last_bake_metrics()` nos testes de desempenho na Intel UHD 620.

### A3. Integração dos Depósitos Protegidos na Economia
| Alternativa | Descrição | Prós | Contras |
|---|---|---|---|
| **A3.1 — `CompositeStorageSource` (`GroundPileManager` + `DepotStorageManager`) (Recomendada)** | `SettlementInventory` aponta para um agregador único que consulta/muta pilhas no chão (`GroundPileManager`) e slots/lotes protegidos nos depósitos construídos (`DepotStorageManager`). | Separação limpa entre armazenamento exposto e protegido; suporta `decay_multiplier` distinto (ex.: `0.0` no depósito); mantém autoridade única sem saldo duplicado. | Exige coordenação de prioridade entre depósito e pilha (onde depositar primeiro / de onde sacar primeiro). |
| **A3.2 — Zona de proteção sobre pilhas (`GroundPileManager` por zona)** | O depósito apenas altera o `decay_multiplier` das pilhas dentro de um raio. | Menos código novo no inventário. | Visualmente estranho se o depósito parecer um prédio fechado com pilhas "atravessando" o chão. |

**Recomendação:** **A3.1**, implementada em etapa dedicada após o núcleo de construção do abrigo.

### A4. Questão Pendente: Persistência do Abrigo na T3 vs. Save/Load na T4
O GDD v1.0 (§13) menciona para T3 *"Abrigo/casa completado e persistido"*, enquanto o sistema geral de *"salvar/carregar"* em disco pertence à **T4** (§13 T4). Como não devemos escolher pelo proprietário, seguem as duas opções objetivas:

| Opção | Descrição | Prós | Contras |
|---|---|---|---|
| **P1 — Persistência em Memória na T3 (até T4)** | `BuildingRegistry` / `BuildingManager` mantém o estado estruturado das obras e edifícios concluídos em memória (desacoplado da cena visual, pronto para serialização), sobrevivendo à sessão ativa e preparado para o `SaveManager` da T4. | Não antecipa código de T4 (`Save/SaveManager` e versionamento de esquema); mantém a T3 focada em construção e reduz risco de retrabalho de formato de arquivo. | Ao fechar e reabrir o jogo na T3, o abrigo construído não estará lá até a implementação da T4. |
| **P2 — Persistência Mínima em Disco já na T3** | Um serializador mínimo (ex.: JSON em `user://buildings_state.json`) salva e restaura apenas a lista de edifícios concluídos entre reinícios na T3. | Cumpre literalmente *"persistido"* entre reinícios do processo já no aceite da T3. | Cria formato provisório fora do `Save/SaveManager` da T4, que precisará ser migrado ou substituído na T4. |

**Decisão requerida do proprietário:** escolher **P1** ou **P2** antes de implementar a etapa de persistência da T3.

---

## 5. Plano Incremental Proposto (Não Implementado)

Cada etapa abaixo é pequena, isolada, testável automaticamente e revisável antes de avançar para a próxima:

| Etapa | Objetivo | Dependências | Arquivos Provavelmente Envolvidos | Riscos | Testes Previstos | Critério de Aceite |
|---|---|---|---|---|---|---|
| **T3.0 — Planejamento** *(atual)* | Auditoria e proposta arquitetural | `main` (`t2-complete`) | `docs/architecture/T3_architecture_PROPOSAL.md` | Divergência de escopo sem revisão | `git diff --check` | Aprovação do proprietário + decisões pendentes respondidas |
| **T3.1 — Dados de Edifício e Saque Atômico** | Criar `BuildingDefinition` (`.tres`) e `can_withdraw_batch` / `withdraw_batch` atômicos | T3.0 aprovada | `src/buildings/building_definition.gd`, `data/buildings/*.tres`, `src/economy/settlement_storage_source.gd`, `ground_pile_manager.gd`, `settlement_inventory.gd` | Regressão em invariantes de `GroundPileManager` | Testes unitários de saque composto válido, insuficiente e rollback exato | `withdraw_batch` conserva 100% do saldo em falhas e passa 100% da suíte T2 |
| **T3.2 — Validação Espacial e Prévia de Posicionamento** | Implementar `PlacementValidator`, `PlacementPreview` (sem grid visível) e modo de posicionamento | T3.1 | `src/buildings/placement_validator.gd`, `placement_preview.gd`, `placement_controller.gd`, `src/core/collision_layers.gd`, `src/rts/rts_input_controller.gd` | Falso positivo em borda de rampa ou bloqueio de cliques na HUD | Testes unitários/integração de inclinação, sobreposição e acessibilidade | Prévia verde/vermelha responde em tempo real; clique inválido não cria obra nem gasta recursos |
| **T3.3 — Canteiro de Obra, Saque e Atualização de Navegação** | Posicionar `ConstructionSite`, descontar recursos atomicamente e atualizar `WorldNavigation` | T3.2 | `src/buildings/construction_site.gd`, `building_manager.gd`, `src/navigation/world_navigation.gd`, `levels/test_map/test_map.tscn`, `src/main/main.gd` | Pico de *rebake* no `WorldNavigation` ou unidades presas dentro da *footprint* | Teste de integração de posicionamento + saque + `rebake` + verificação de desvio de unidades | Obra aparece no terreno, estoque diminui exatamente pelo custo, unidades contornam o canteiro |
| **T3.4 — Ordem de Construção, Progresso e Conclusão do Abrigo** | Implementar `BuildSlotPlanner`, `ConstructOrder`, `PickResult.Kind.CONSTRUCTION_SITE`, progresso cooperativo e transição para `BuildingInstance` (Abrigo) | T3.3 | `src/units/orders/construct_order.gd`, `build_slot_planner.gd`, `src/rts/world_picker.gd`, `pick_result.gd`, `command_controller.gd`, `src/buildings/building_instance.gd` | Concorrência entre múltiplos construtores ou travamento em quina | Testes de integração: 1 e 2 construtores, interrupção por outra ordem, retomada e conclusão | Trabalhador(es) vão ao perímetro, executam `WORKING`, completam o abrigo visível externamente e ficam `IDLE` |
| **T3.5 — Interface Mínima e Cancelamento** | Barra/botões de construção não bloqueantes, seleção/painel de obra e cancelamento com política aprovada | T3.4 | `src/ui/construction_hud.gd`, `building_inspector_panel.gd`, `resource_hud.gd`, `hud_formatter.gd` | HUD interceptar cliques do mapa RTS | Testes unitários/integração de seleção de obra, HUD e cancelamento sem bloquear câmera/mapa | Jogador posiciona, acompanha `%` e cancela obra pela UI sem afetar seleção RTS |
| **T3.6 — Depósitos Protegidos contra Deterioração** | Construir depósito e integrar `CompositeStorageSource` (ou proteção de estoque) reduzindo/eliminando deterioração | T3.5 + decisão de escopo | `src/economy/composite_storage_source.gd`, `depot_storage_manager.gd`, `src/buildings/storage_depot.gd`, `src/ui/settlement_stockpile_panel.gd` | Saldo duplicado ou regressão no `step_decay()` | Testes unitários e de integração de depósito + `EconomyClockController` | Recursos protegidos no depósito não sofrem (ou sofrem menos) deterioração e o estoque total permanece único |
| **T3.7 — Persistência (conforme P1/P2) e Validação Global T3** | Aplicar persistência escolhida, protocolo manual T3 e benchmark Intel UHD 620 | T3.6 + decisão P1/P2 | `tests/perf/`, `docs/testing/T3_manual_test_protocol.md` | Regressão de FPS abaixo da meta CA (`p95 <= 16,7 ms`) | Suíte segmentada completa + benchmark 1080p na Intel UHD 620 | 100% testes passando, 0 erros/avisos, `p95 <= 16,7 ms` em CA |

---

## 6. Decisões Pendentes para o Proprietário

Antes de iniciar a implementação (T3.1+), o proprietário precisa definir:

1. **Persistência na T3 (A4):** escolher **P1 (em memória até T4)** ou **P2 (persistência mínima em disco já na T3)**.
2. **Momento do consumo de recursos (A1):** confirmar **consumo atômico na colocação (A1.1)** ou exigir transporte físico de madeira/pedra até o canteiro (A1.3).
3. **Política de cancelamento de obra:** ao cancelar uma obra em andamento, o reembolso deve ser **100% dos recursos**, **parcial** (ex.: 50% ou proporcional ao não construído) ou **0%**?
4. **Custos, dimensões e tempos iniciais (valores provisórios):** aprovar valores iniciais para o **Abrigo Básico** (ex.: custo em madeira/pedra, área em metros, tempo de construção) e para o **Depósito Rústico** (ou autorizar valores provisórios em `.tres` para calibração).
5. **Escopo de Depósitos na T3:** confirmar se os **depósitos protetores** entram na própria T3 (etapa T3.6, alinhado ao GDD v1.1 e item 6 do objetivo) ou se ficam para uma subfase T3+.
6. **Posicionamento na `CampStorageZone`:** permitir construir sobre a zona lógica do acampamento (deslocando/evitando pilhas existentes) ou exigir construção fora do perímetro das pilhas?
7. **Interface mínima:** preferência por barra fixa discreta no canto inferior (botão `Construir` -> lista de plantas) ou atalho de teclado + painel compacto acoplado ao `ResourceHud`?

---

## 7. Riscos, Desempenho e Estratégia de Testes

- **Desempenho (Intel UHD Graphics 620, `gl_compatibility`):**
  - Placeholders de canteiros e edifícios devem seguir o padrão de `GroundResourcePile` (`SHADOW_CASTING_SETTING_OFF` ou sombras controladas apenas se necessário, malhas primitivas reutilizadas e zero `_process()` por instância ociosa).
  - `WorldNavigation.request_rebake()` ocorre apenas em eventos discretos (colocar/cancelar/concluir obra), mas seu tempo em `ms` deve ser medido no benchmark T3 para garantir ausência de travamentos (`0` quadros `> 100 ms`).
- **Riscos de Integração:**
  - *Unidades dentro da área da obra:* ao colocar uma obra, `PlacementValidator` impede colocação sobre unidades (`MASK_UNITS`) e o `BuildSlotPlanner` posiciona construtores fora da colisão sólida (`solid_radius` / meia-extensão + `agent_radius`).
  - *Corrida no NavMesh:* assim como na T2.6, testes devem aguardar `world_nav.is_navigation_ready()` após `request_rebake()` antes de emitir ordens.
- **Testes Previstos:**
  - Unitários: `BuildingDefinition`, `SettlementInventory.withdraw_batch` (atomicidade e rollback), `PlacementValidator`, `BuildSlotPlanner`, `CompositeStorageSource`/proteção contra decay.
  - Integração: posicionamento + saque + `rebake`, `ConstructOrder` (1 e múltiplos trabalhadores, interrupção, retomada, conclusão, cancelamento), interação HUD sem bloquear seleção RTS.
  - Desempenho e Manual: protocolo manual T3 + benchmark em `1920×1080` na Intel UHD 620 mantendo meta `p95 <= 16,7 ms` em tomada CA e 0 avisos no executor segmentado (`.\tools\run_tests.ps1 -Segmented`).
