# T2 — Arquitetura Técnica: Trabalho, Transporte Físico e Pilhas Individuais no Acampamento

> **STATUS: CONSOLIDADO PARA ACEITE FINAL (CANDIDATO T2-CLOSEOUT)**
>
> Documento de planejamento e arquitetura técnica consolidado na branch `review/t2-closeout-candidate`. A implementação técnica cobriu integralmente as etapas `T2.0` a `T2.6` e o ajuste `B1` (velocidade unificada). Preservado como registro histórico da arquitetura implementada.

---

## 1. Linha de base e invariantes da T1

- **Engine e alvo:** Godot `4.7.2`, GDScript tipado, renderer `Compatibility / OpenGL 3.3`, hardware de referência **Intel UHD 620 (16 GB RAM)**.
- **Base Git herdada:** marco **T1 — Fundação RTS** encerrado na tag `t1-complete` (commit `2808799`, `90` testes e `1.607` asserções), mantendo `MainScene` ([main.gd](../../src/main/main.gd)) por composição modular explícita, **zero autoloads globais obrigatórios**.
- **Orçamento de desempenho (`KNOWN_ISSUES.md`):** em `1920×1080`, a mediana medida pós-T1.10 foi `p95 = 16,586 ms` para teto obrigatório de `16,7 ms` (**margem de apenas `0,114 ms`**), e o custo RVO cresce com a contagem de unidades (`2 → 10 → 25 → 50`). Pilhas no acampamento e deterioração devem ter custo por frame próximo de zero.
- **Contratos reais da T1 que a T2 preserva sem regressão:**
  - `CollisionLayers` ([collision_layers.gd](../../src/core/collision_layers.gd)): `LAYER_RESOURCES` (`6`) já reservada para a T2 (`MASK_RESOURCES`), mantendo `LAYER_OBSTACLES` (`2`) e `LAYER_BUILDINGS` (`5`) intactas.
  - `PickResult` ([pick_result.gd](../../src/rts/pick_result.gd)) e `CommandController` ([command_controller.gd](../../src/rts/command_controller.gd)): `PickResult.Kind.GROUND` continua disparando estritamente `MoveOrder` via `GroupMovePlanner`. Não haverá comando nem modo de soltar materiais em terreno livre na T2.
  - Corredores livres de `test_commands.gd` (`(0, 0, -2.5..+5)` e `WallWithGap` em `x ∈ [-2, 2], z = -6`) e contagem/máscara de `TestMap/Obstacles` em `test_test_map.gd` (`> 10` `StaticBody3D` estritamente em `MASK_OBSTACLES`).
  - RVO na `Unit`: prioridade `1.0` parada vs `0.5` em movimento e `_clamp_avoidance_to_navmesh`.

---

## 2. Nota histórica de escopo e classificação (`DECIDIDO` vs `PROPOSTA` vs `ABERTO`)

- **Restrição aprovada nesta revisão:** na T2, haverá **somente pilhas físicas individuais dentro do acampamento**.
- **Registro histórico:** a proposta anterior (pilhas livres espalhadas pelo mapa externo, botão/atalho de soltar carga em qualquer lugar e sistema `CollectFromPileOrder` para recuperar materiais abandonados fora do acampamento) foi **retirada do escopo da T2** e poderá ser reconsiderada futuramente, sem assumir que está aprovada.

| Classificação | Itens que orientam esta arquitetura |
|---|---|
| **DECIDIDO** | • Casal protagonista inicia **sem ferramentas, sem equipamentos e sem construções humanas pré-existentes**.<br>• **Transporte físico obrigatório (D2-1):** cada morador tem capacidade individual em `%` (`0%`–`100%`) e cada material tem peso específico.<br>• Ao atingir `100%` ou não caber mais 1 unidade, o trabalhador retorna automaticamente ao acampamento.<br>• Materiais descarregados formam **pilhas individuais de madeira, pedra ou alimentos exclusivamente dentro do acampamento** (placeholders simples permitidos inicialmente; modelos 3D finais depois).<br>• Cada pilha mantém quantidade própria, localização e estado de exposição; pilhas da mesma categoria podem ser agrupadas conforme contrato determinístico.<br>• Todas as pilhas válidas do acampamento contribuem para o estoque coletivo (`SettlementInventory`), refletindo exatamente o total disponível.<br>• Materiais expostos podem desaparecer com o tempo; a deterioração reduz corretamente os recursos disponíveis no estoque.<br>• Armazéns construíveis pertencem à **T3** e deverão proteger os materiais. |
| **PROPOSTA** | • `CampStorageZone` como área lógica no chão do acampamento (sem edifícios nem colisores sólidos) com regra determinística de posicionamento em slots.<br>• Entrega parcial caso a fonte natural se esgote antes de `100%`; suporte a múltiplas categorias carregadas em caso de redirecionamento.<br>• Defaults provisórios para testes de pesos, capacidade e deterioração (claramente não aprovados). |
| **ABERTO** | • **Deterioração:** duração da exposição, perda gradual versus desaparecimento integral, política de exposição ao adicionar materiais novos a uma pilha antiga e diferenças de deterioração por categoria.<br>• Valores numéricos definitivos de peso unitário, capacidade inicial, taxa de coleta, consumo e eventual teto de unidades por pilha. |

---

## 3. Responsabilidades modulares (sem autoloads, autoridade transacional única)

Preservam-se os seis componentes centrais, simplificados para o escopo exclusivo do acampamento:

1. **`ResourceDefinition` (`Resource` `.tres` parametrizado):**
   Define `resource_id` (`wood`, `stone`, `food`), `category`, `unit_weight`, `decay_profile` e referência de visual placeholder por categoria.
2. **`UnitCarryLoad` (componente acoplado à `Unit`):**
   Mantém quantidades físicas carregadas por `resource_id`, peso atual, `max_weight_capacity`, porcentagem exata (`0%`–`100%`), `can_fit_one(resource_id)` e operações transacionais de entrada/saída.
3. **`CampStorageZone` (área lógica inicial no acampamento, zero construções):**
   - Delimita logicamente a região inicial de descarga no acampamento (sem paredes, sem teto, sem `StaticBody3D` e sem estruturas humanas pré-prontas).
   - Fornece âncora, limites e slots ordenados no `NavMesh` para posicionar pilhas de madeira, pedra e alimentos.
   - Na **T3**, armazéns construíveis implementarão a mesma interface de ponto/zona de armazenamento (`StoragePoint`), porém com proteção (`decay_multiplier = 0.0` ou reduzido).
4. **`GroundResourcePile` (pilha física individual no acampamento):**
   - Nó físico/visual leve no chão do acampamento contendo: `pile_id`, `resource_id`, `amount` (`> 0`), `world_position`, `exposure_state` (tempo acumulado/restante) e `is_protected` (`false` no chão descoberto da T2).
   - Usa apenas malha placeholder simples (escala/faixa visual variando conforme `amount`) e, se necessário para inspeção/tooltip, `Area3D` leve em `MASK_RESOURCES` — nunca `StaticBody3D` em `TestMap/Obstacles`.
5. **`GroundPileManager` + `SettlementInventory` (autoridade transacional única):**
   - **Regra inegociável de autoridade única:** `SettlementInventory` **não** mantém um saldo paralelo independente sujeito a dessincronização. O estoque utilizável consultado pela comunidade e pela HUD é a **projeção exata das pilhas válidas registradas pelo `GroundPileManager` dentro da `CampStorageZone`** (ex.: se as pilhas do acampamento somam `24` unidades de madeira e não houve perda ou consumo, `SettlementInventory` reporta exatamente `24`).
   - Toda operação de **entrega (descarga)**, **consumo/retirada** (incluindo futuras obras na T3) ou **deterioração** passa por transação atômica única no par `GroundPileManager` ↔ `SettlementInventory`, atualizando as `GroundResourcePile`s afetadas e emitindo o novo saldo consolidado no mesmo passo.
   - Se houver múltiplas pilhas da mesma categoria (incluindo quantidades parciais), retiradas/consumos seguem ordem determinística (ex.: **mais antiga / mais exposta primeiro**) abatendo parcialmente uma pilha e, se necessário, prosseguindo para a próxima até completar a quantidade solicitada — nunca permitindo saldo ou pilha negativa.

---

## 4. Contratos removidos e simplificação da T2

Para evitar código morto e complexidade desnecessária nesta etapa:
- **Removido `CollectFromPileOrder`:** não há pilhas externas no mapa para buscar nem recolher na T2.
- **Removido `DropLoadOrder` / comando de soltar no chão / botão ou atalho (`Alt + Clique Direito`):** o jogador não solta carga em pontos arbitrários do mapa; clique direito no chão continua sendo 100% `MoveOrder`.
- **Simplificado picking na T2:** `PickResult` precisa apenas de `RESOURCE_SOURCE` (árvore, arbusto, rocha) e opcionalmente `CAMP_STORAGE_ZONE` (para entrega contextual manual no acampamento, além do retorno automático), mantendo `GROUND`, `UNIT` e `OBSTACLE` da T1.

---

## 5. Regra determinística da zona inicial e posicionamento de pilhas

1. **Localização da `CampStorageZone` inicial:**
   - Definida por dados de cena (`CampStorageZone` posicionada próxima à área inicial do casal protagonista no `TestMap`), **fora** dos corredores protegidos da T1 (`(0, 0, -2.5..+5)` e `WallWithGap` em `x ∈ [-2, 2], z = -6`) e com alcance validado na `NavigationMesh` (`WorldNavigation.is_position_reachable`).
2. **Posicionamento e agrupamento determinístico ao descarregar:**
   - Ao receber descarga de `(resource_id, amount)` vinda de `UnitCarryLoad`:
     1. **Tentativa de agrupamento (`merge`):** `GroundPileManager` procura uma `GroundResourcePile` existente e válida do **mesmo `resource_id`** dentro da `CampStorageZone` que ainda aceite acréscimo (respeitando eventual teto configurável `max_pile_amount` caso habilitado; `<= 0` significa sem teto fixo). Se encontrada, soma `amount` nela atomicamente (aplicando a política configurada de exposição) e atualiza o visual placeholder.
     2. **Criação de nova pilha em slot determinístico:** caso não exista pilha compatível (ou a existente atinja um eventual teto configurado), `GroundPileManager` seleciona o próximo slot livre da `CampStorageZone` (grade/anel ordenado por distância ao centro da zona, validado com `WorldNavigation.snap_to_navmesh` e espaçamento mínimo livre entre pilhas para não bloquear unidades) e instancia uma nova `GroundResourcePile`.
     3. **Múltiplas pilhas da mesma categoria:** suportado nativamente tanto quando houver teto configurável quanto quando múltiplas pilhas coexistirem no acampamento, somando todas no `SettlementInventory` e abatendo em ordem determinística em caso de consumo ou deterioração.

---

## 6. Transações atômicas e invariantes de conservação

Todas as movimentações ocorrem de forma síncrona/atômica em memória no passo de conclusão da ação:

1. **Coleta na fonte (`ResourceSource` → `UnitCarryLoad`):**
   - Transfere `delta` unidades respeitando `ResourceSource.remaining` e `UnitCarryLoad.can_fit_one(resource_id)`.
   - `SettlementInventory` **não** é alterado.
2. **Cancelamento ou redirecionamento em trânsito:**
   - Cancela a ordem ativa da unidade (`CANCELLED`) mantendo **100%** dos materiais já presentes em `UnitCarryLoad`.
3. **Entrega no acampamento (`UnitCarryLoad` → `GroundPileManager` / `SettlementInventory`):**
   - Retira da unidade e credita na(s) `GroundResourcePile`(s) do acampamento na mesma transação atômica, garantindo `unit_carry == 0` para os itens entregues e aumento idêntico em `SettlementInventory`.
4. **Deterioração e consumo (`GroundPileManager` / `SettlementInventory`):**
   - Reduz `amount` da `GroundResourcePile` (removendo-a apenas quando `amount == 0`), atualiza `SettlementInventory` na mesma operação e registra perdas por exposição em `total_decayed_by_resource`.

**Invariante matemática verificável em todos os testes:**

$$\Delta \text{Fontes} + \Delta \text{CargasEmUnidades} + \Delta \text{EstoqueEmPilhasDoAcampamento} + \Delta \text{Consumido} + \Delta \text{PerdaIntencionalPorDeterioracao} = 0$$

---

## 7. Deterioração centralizada e defaults provisórios para testes

### 7.1 Execução eficiente (Intel UHD 620)
- **Zero `_process` ou `_physics_process` por pilha:** somente `GroundPileManager` executa um passo periódico leve (ex.: `Timer` / acumulador de `1,0 s` de tempo simulado via interface `WorldTimeProvider`, já pronta para escalas `1x / 2x / 4x` da T4).
- **Custo gráfico mínimo:** placeholders de pilhas compartilham materiais `StandardMaterial3D` por categoria e evitam sombras pesadas desnecessárias para preservar a margem de `0,114 ms` no `p95` (`1920×1080`).

### 7.2 Pontos mantidos em `ABERTO` vs Defaults provisórios para testes (`PROVISÓRIO — NÃO APROVADO`)

Permanecem estritamente em **`ABERTO`** no GDD:
- Duração exata da exposição;
- Perda gradual por unidade versus desaparecimento integral da pilha;
- Política de exposição ao adicionar materiais novos a uma pilha antiga;
- Diferenças de deterioração por categoria (`food` vs `wood` vs `stone`).

Para viabilizar testes unitários e calibração inicial na T2 sem travar o desenvolvimento, recomendam-se os seguintes **defaults provisórios parametrizáveis (`PROVISÓRIO — NÃO APROVADO`)**:

| Parâmetro | Default provisório sugerido | Status |
|---|---|---|
| **Pesos unitários (`unit_weight`)** | `food = 1.0`, `wood = 2.0`, `stone = 3.0` | **PROVISÓRIO / ABERTO** |
| **Capacidade individual inicial** | `20.0` (ex.: `20` comidas, `10` madeiras ou `6` pedras = `90%` com folga de `2.0`, retornando antes de passar `100%`) | **PROVISÓRIO / ABERTO** |
| **Modo inicial de deterioração** | Parametrizável (`GRADUAL_UNITS` ou `EXPIRE_ALL`), testando ambos em suíte unitária; sugestão inicial para protótipo: `GRADUAL_UNITS` (perda gradual previsível antes de zerar) | **PROVISÓRIO / ABERTO** |
| **Exposição base (para testes/protótipo)** | Configurável por categoria (ex.: `food` mais sensível que `wood`, e `wood` mais sensível que `stone` ou `stone` com taxa mínima/nula em teste) | **PROVISÓRIO / ABERTO** |
| **Política ao somar itens novos em pilha antiga (`merge`)** | `WEIGHTED_AVERAGE` (média ponderada pelas quantidades para evitar reset gratuito de exposição ao adicionar 1 unidade nova) | **PROVISÓRIO / ABERTO** |

---

## 8. Preparação para a T3 (Armazéns construíveis)

- Quando a **T3 — Construção** for implementada, edifícios de armazém implementarão o registro de `StoragePoint` protegido (`decay_multiplier = 0.0` ou reduzido).
- O mesmo `SettlementInventory` continuará consultando o conjunto de armazenamentos válidos (pilhas no chão descoberto da `CampStorageZone` + estoques em armazéns construídos), tornando imediata a vantagem prática de construir armazéns: conservar os recursos coletados sem perda por exposição.

---

## 9. Decisões restantes antes da `T2.0`

Para iniciar a `T2.0` (dados econômicos, pesos, capacidade e estoque), basta o proprietário confirmar:
1. Aprovação desta arquitetura simplificada (`RASCUNHO` → aprovada) e do plano `T2.0`–`T2.6`;
2. Autorização explícita para usar os **defaults provisórios parametrizáveis** na `T2.0` enquanto os valores definitivos de peso, capacidade e deterioração seguem em `ABERTO` para calibração na `T2.1`–`T2.6`.
