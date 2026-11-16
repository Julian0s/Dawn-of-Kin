# Dawn of Kin — T3.0-R4+: Arquitetura Consolidada da T3 (Construção)

**Status:** T3.1, T3.2 e T3.3 CONCLUÍDAS, HOMOLOGADAS E INTEGRADAS NA `main` (`3c6fc0bd36fc3828af5a89662fb23cfb60d37865`, tag `t3-3-complete`; ver [T3_3_closeout_ACCEPTANCE.md](../testing/T3_3_closeout_ACCEPTANCE.md)); etapas `T3.4` a `T3.9` permanecem planejadas e bloqueadas (`T3.4-ARCHITECTURE-R2` pendente de aprovação; nenhuma autorização de implementação para `T3.4`).<br>
**Base Auditada:** Branch `main` (`ceb3f7194a750e66dbf73ebb0b0a7460d51eb87f`), baseada no histórico consolidado da tag `t2-complete` (`f7c24592e3a6d936dbcb63f648c474280695ab9b`).<br>
**Referência GDD:** [Dawn_of_Kin_GDD.md](../Dawn_of_Kin_GDD.md) (`v1.2 — Conteúdo Aprovado pelo Proprietário`, revisão `R4.1`, commit `6e5764f67125da103eec68adb95e5b67ac329ed9` em 16/11/2026); quando integrado à `main` mediante autorização expressa, vigora como o GDD normativo único (antes dessa integração na `main`, o antigo `Dawn_of_Kin_GDD_v1.0.md` permanece vigente na `main`).<br>
**Engine e Alvo de Referência:** Godot `4.7.2.stable` (`gl_compatibility`), Intel UHD Graphics 620 (`1920×1080`, meta $p95 \le 16,7\text{ ms}$ em tomada CA).

---

## 1. Diretrizes Estruturais Aprovadas pelo Proprietário (Decisões Iniciais D1–D7 e Complementos Aprovados D8–D9)

Em 14/11/2026, o proprietário do projeto deliberou sobre os pontos abertos da proposta inicial T3.0 (D1 a D7) e consolidou em seguida os complementos D8 e D9, estabelecendo os seguintes direcionamentos vinculantes que permanecem integralmente preservados nesta revisão:

1. **D1 — Persistência em disco na T3 (DECIDIDO: P2):**
   - As construções e o estado econômico relevante do assentamento deverão ser salvos em disco já na T3.
   - Persistência mínima versionada (`schema_version = 1`), compatível com o futuro `SaveManager` da T4.
   - Garantir consistência estrita entre construções concluídas, canteiros ativos, progresso, reservas, estoque físico e materiais em trânsito, impedindo duplicação ou perda após carregamento.
   - Não antecipar calendário, ciclo dia/noite ou outros sistemas previstos para a T4.

2. **D2 — Transporte físico dos materiais até o canteiro (DECIDIDO: Reserva e Transporte Físico):**
   - Ao posicionar uma obra, os materiais necessários são **reservados no estoque existente**, sem consumo instantâneo.
   - Os trabalhadores retiram materiais das pilhas físicas do acampamento, transportam-nos respeitando peso unitário e capacidade individual de carga (`UnitCarryLoad`, com desaceleração conforme carga validada na T2) e descarregam no canteiro.
   - A construção progride conforme materiais são disponibilizados no canteiro, consumindo-os proporcionalmente ao progresso de montagem.

3. **D3 — Cancelamento com reembolso proporcional (DECIDIDO: Proporcional ao trabalho restante):**
   - Regra contábil consistente para materiais reservados nas pilhas, materiais em transporte, materiais no buffer do canteiro e materiais já incorporados na estrutura.
   - O cancelamento jamais poderá criar recursos do nada nem gerar duplicações.

4. **D4 — Custos, dimensões e tempos provisórios (APROVADOS EM 14/11/2026 como valores provisórios sujeitos a balanceamento):**
   - Parâmetros da tabela T3.0-R3 para o **Abrigo Básico** ($4 \times 4\text{ m}$, 12 madeiras, 6 pedras, 30 s-construtor, máx. 2 construtores) e **Depósito Rústico** ($5 \times 4\text{ m}$, 18 madeiras, 10 pedras, 45 s-construtor, máx. 2 construtores, capacidade 50 madeiras, 50 pedras e 30 alimentos).
   - Valores calibrados com base na capacidade de 20 unidades de peso e nos dados reais da T2 (madeira peso 2, pedra peso 3).

5. **D5 — Depósitos protetores incluídos na própria T3 (DECIDIDO: Escopo da T3):**
   - Implementar depósitos construíveis após o primeiro abrigo funcional, reduzindo ou eliminando a deterioração dos recursos armazenados.
   - Preservar uma autoridade única de estoque (`SettlementInventory`), distinguindo materiais expostos e protegidos sem duplicar saldos.

6. **D6 — Construção na CampStorageZone (DECIDIDO: Opção A — Área das pilhas reservada):**
   - Edifícios e canteiros não podem ocupar o interior da `CampStorageZone` durante a T3.
   - Prévia indica rejeição clara quando a posição interceptar a zona reservada.
   - Preservar acessos às pilhas, pontos de descarga e corredores de navegação, sem impor quadrículas visíveis ao mapa.

7. **D7 — Interface de construção (DECIDIDO: Opção A — Botão Construir com painel retrátil):**
   - Botão discreto **Construir** no canto inferior direito.
   - Painel retrátil contendo os edifícios disponíveis.
   - Prévia de posicionamento no terreno (verde/vermelha com motivo de rejeição), confirmação por clique esquerdo e cancelamento por `Esc` ou clique direito.
   - Painel contextual de canteiro com progresso e botão de cancelamento, sem sobrepor HUDs existentes.

8. **D8 — Armazenamento e materiais no mundo (DECIDIDO):**
   - O acampamento inicial (`CampStorageZone`) é o primeiro local de armazenamento da T2/T3, **não** uma restrição permanente do jogo.
   - Futuramente, qualquer item ou material poderá ser deixado fisicamente no chão de qualquer região; contudo, materiais largados fora de um local de armazenamento válido **não** entram automaticamente no estoque coletivo — precisam ser transportados fisicamente até um local de armazenamento válido para integrá-lo.
   - Materiais mantidos no chão permanecem expostos à deterioração conforme perfis configuráveis por categoria (madeira e alimentos deterioram quando expostos; pedra bruta exposta não sofre deterioração temporal conforme ratificação `DEC-11A`, preservando `decay_stone_provisional.tres` com `can_decay = false`; futuras categorias terão regras próprias).
   - Construções poderão existir em diferentes locais e regiões, desde que o posicionamento seja válido; a restrição D6 continua protegendo especificamente a zona inicial das pilhas durante a T3.

9. **D9 — Organização dos trabalhadores na construção (DECIDIDO):**
   - 1 trabalhador: busca materiais e constrói sequencialmente.
   - 2 trabalhadores: 1 pode transportar materiais enquanto o outro constrói.
   - 3 trabalhadores: 1 pode transportar materiais enquanto 2 constroem.
   - Permanece o limite provisório de até **2 construtores** atuando simultaneamente na montagem do Abrigo Básico e do Depósito Rústico.
   - Não haverá pilha obrigatória ao lado de cada obra; o transporte dos materiais permanece físico até o canteiro.

---

## 2. Matriz GDD × Código Real (`main`) × Correções Técnicas (T3.0-R3)

| Requisito / Referência | Realidade no Código da `main` (`f7c2459`) | Inconsistência Corrigida | Solução Arquitetural Proposta *(sujeita à aprovação)* |
|---|---|---|---|
| Pesos dos recursos e capacidade de carga (§5, §13 T2) | `wood.tres`: peso **2**; `stone.tres`: peso **3**; `food.tres`: peso **1**; capacidade inicial: **20** de peso. | R1 utilizou peso 3 para madeira e 4 para pedra, calculando pesos irreais (60 e 94). | Tabela recalculada (**APROVADA em 14/11/2026 como valores provisórios sujeitos a balanceamento**): Abrigo = **42 de peso**; Depósito = **66 de peso**. |
| Área e dimensões da `CampStorageZone` (§5, D6) | `test_map.tscn`: `zone_bounds_half_extents = Vector2(2.8, 2.2)`. Área efetiva = **5,6 × 4,4 m** (âncora em `(0, 0, 0.5)`). | R1 mencionava 8 × 8 m (valor padrão do script desacoplado da cena). | `PlacementValidator` lê `camp_zone.zone_bounds_half_extents` dinamicamente da instância real na cena. |
| Funcionamento do `WorldNavigation.request_rebake()` e conectividade (§12, §13 T1) | `parse_source_geometry_data()` e `bake_from_source_geometry_data()` executam de forma **síncrona** na thread chamadora; `find_path()` consulta exclusivamente a malha já assada. | R1 afirmava bake em background; R2 usava `find_path()` na malha antiga sem simular a obra futura. | Validação híbrida proposta: checagem espacial conservadora no *hover* + avaliação em malha candidata na confirmação antes de reservar recursos. |
| Máscaras de colisão e NavMesh (§12, `src/core/collision_layers.gd`) | `MASK_WORLD_SOLID = MASK_TERRAIN \| MASK_OBSTACLES`. `LAYER_BUILDINGS = 5` reservado. | R1 propunha fundir globalmente `LAYER_BUILDINGS` em `MASK_WORLD_SOLID`, afetando picking e física sem isolamento. | Proposta de `MASK_NAV_STATIC = MASK_TERRAIN \| MASK_OBSTACLES \| MASK_BUILDINGS` específico para bake; picking de obras via consulta dedicada em `MASK_BUILDINGS`. |
| Contabilidade de estoque físico e reservas (D2, §5) | `SettlementInventory` e `GroundPileManager` controlam apenas saldo físico em pilhas no chão (`deposit_batch`, `withdraw`). | R1 não isolava buffer do canteiro de entregas acumuladas; R2 duplicava trânsito no JSON. | Formalizada a Invariante Contábil Fundamental com parcelas disjuntas e fonte única por item físico. |
| Política de deterioração com reservas (D2) | `EconomyClockController.step_decay()` atinge pilhas reais pelo tempo. | R1 propunha proteger artificialmente materiais reservados no chão contra desgaste. | **DECIDIDO: Alternativa B — Deterioração física com perda direta da reserva**, preservando `step_decay()` e reduzindo reservas comprometidas ao saldo físico restante. |
| Persistência em disco e fontes naturais (D1, P2) | Nenhuma persistência em disco na base atual; `ResourceSource` possui estoque finito por `source_id`. | R2 tinha somas inconsistentes no JSON, dupla referência de trânsito e não persistia `ResourceSource`. | Snapshot consistente sem dupla contagem, incluindo `source_id`/`remaining_amount` das fontes e validação de integridade pré-carga. |
| Sequenciamento de incrementos (§13) | Base pronta para T3.1. | R1 posicionava canteiros jogáveis antes da validação espacial. | Validação espacial e prévia (T3.2) precedem a colocação jogável e suprimento (T3.3). |

---

## 3. Contabilidade Física, Reservas e Ciclo de Suprimento (D2)

### 3.1. Invariante Contábil Fundamental do Assentamento
Para impedir duplicação, criação espontânea ou desaparecimento de recursos em qualquer estado do jogo, a economia obedece à equação de conservação estrita por tipo de recurso $R$:

$$Q_{\text{inicial}}(R) + Q_{\text{coletado}}(R) = Q_{\text{pilhas\_livre}}(R) + Q_{\text{pilhas\_reservado}}(R) + \sum_{u} Q_{\text{mochila}}(u, R) + \sum_{c} Q_{\text{buffer\_canteiro}}(c, R) + \sum_{c} Q_{\text{incorporado}}(c, R) + \sum_{d} Q_{\text{depósito}}(d, R) + Q_{\text{deteriorado}}(R) + Q_{\text{perda\_demolição}}(R)$$

Onde cada termo representa uma quantidade fisicamente disjunta:
- $Q_{\text{pilhas\_livre}}(R)$: Recursos no chão da `CampStorageZone`, livres para novas reservas ou consumo.
- $Q_{\text{pilhas\_reservado}}(R)$: Recursos no chão da `CampStorageZone`, fisicamente presentes nas pilhas, mas contratualmente alocados a uma obra ativa.
- $Q_{\text{mochila}}(u, R)$: Recursos sendo carregados nas costas do trabalhador $u$ (`UnitCarryLoad`).
- $Q_{\text{buffer\_canteiro}}(c, R)$: Recursos entregues no canteiro $c$ que **ainda não foram consumidos** pelo avanço da construção.
- $Q_{\text{incorporado}}(c, R)$: Recursos consumidos pelo trabalho e fisicamente integrados à estrutura da obra.
- $Q_{\text{depósito}}(d, R)$: Recursos guardados em depósitos protegidos (T3.7).
- $Q_{\text{deteriorado}}(R)$: Total acumulado de perdas por desgaste temporal (`step_decay()`).
- $Q_{\text{perda\_demolição}}(R)$: Total acumulado de materiais destruídos na desmontagem de obras canceladas.

### 3.2. Diferenciação nos Totais e Interface HUD
Para evitar dupla contagem no HUD e nas validações:
- **Estoque Livre Disponível:** $Q_{\text{disponível}}(R) = Q_{\text{pilhas\_livre}}(R) + \sum_d Q_{\text{depósito\_livre}}(d, R)$ (o que a interface exibe como disponível para novas obras).
- **Estoque Físico Total da Comunidade:**
  $$Q_{\text{comunitário\_total}}(R) = Q_{\text{disponível}}(R) + Q_{\text{pilhas\_reservado}}(R) + \sum_u Q_{\text{mochila}}(u, R) + \sum_c Q_{\text{buffer\_canteiro}}(c, R) + \sum_d Q_{\text{depósito\_reservado}}(d, R)$$
- **No Canteiro de Obras:**
  $$\text{Entregue Acumulado}(c, R) = Q_{\text{buffer\_canteiro}}(c, R) + Q_{\text{incorporado}}(c, R)$$
  O HUD do canteiro exibe $\text{Entregue Acumulado} / \text{Necessário}$ para informar o avanço logístico, mas a lógica de construção consome estritamente de $Q_{\text{buffer\_canteiro}}(c, R)$.

### 3.3. Transições de Estado e Atomicidade das Operações
Todas as transferências entre estados contábeis operam sob transações atômicas com verificação de pré-condição e capacidade de reversão (*rollback*):

1. **Criação da Obra (`Reserva`):**
   - `SettlementInventory.reserve_batch(costs)` valida se $Q_{\text{pilhas\_livre}}(R) \ge \text{cost}(R)$.
   - Se aprovado, transfere atomicamente de $Q_{\text{pilhas\_livre}}$ para $Q_{\text{pilhas\_reservado}}$.
   - Falha em qualquer recurso aborta a reserva inteira sem efeitos colaterais.
2. **Retirada para Transporte (`Saque Físico`):**
   - O trabalhador chega à pilha correspondente na `CampStorageZone`.
   - Executa `GroundPileManager.withdraw_reserved(resource_id, amount)`.
   - A quantidade é subtraída da pilha física e creditada em `UnitCarryLoad` na mesma transação.
   - $Q_{\text{pilhas\_reservado}} \mathrel{-}= \text{amount}$, $Q_{\text{mochila}} \mathrel{+}= \text{amount}$.
3. **Entrega no Canteiro (`Descarga`):**
   - O trabalhador chega ao canteiro (`BuildSlotPlanner.get_dropoff_slot()`).
   - A quantidade é retirada da mochila e creditada no buffer do canteiro:
   - $Q_{\text{mochila}} \mathrel{-}= \text{amount}$, $Q_{\text{buffer\_canteiro}} \mathrel{+}= \text{amount}$.
4. **Trabalho Construtivo (`Incorporação`):**
   - À medida que construtores realizam trabalho $\Delta W$, unidades inteiras são transferidas do buffer para a estrutura:
   - $Q_{\text{buffer\_canteiro}} \mathrel{-}= \Delta M$, $Q_{\text{incorporado}} \mathrel{+}= \Delta M$.

### 3.4. Política de Deterioração com Reservas (**DECIDIDO: Alternativa B — Perda Direta**)
Materiais expostos no chão do acampamento (e futuramente em qualquer chão exposto conforme D8) continuam sofrendo desgaste pelo tempo por meio de `GroundPileManager.step_decay()`, cujo funcionamento existente da T2 **não será alterado** nem neutralizado artificialmente por reservas. Proteger pilhas no chão por estarem reservadas permitiria usar canteiros como escudo contra deterioração.

Por decisão do proprietário, adota-se a **Alternativa B — Deterioração física com perda direta da reserva**:

- **Regra de perda na pilha:** A reserva **não** protege materiais expostos. Quando `step_decay()` reduz o saldo físico de uma pilha de forma a comprometer quantidades reservadas ($\sum_c \text{reserva}(p, c) > \text{novo\_amount}(p)$), as reservas afetadas naquela pilha são reduzidas diretamente até corresponderem ao saldo físico real restante, **sem reancoragem automática** para outras pilhas.
- **Ordem determinística em múltiplas reservas na mesma pilha:** Quando uma única pilha possui reservas de mais de uma obra e perde unidades abaixo do total reservado, a redução aplica-se de forma determinística (por ordem inversa de registro/ID de reserva da pilha, preservando $\sum_c \text{reserva}(p, c) \le \text{amount}(p)$ em toda mutação).
- **Déficit no canteiro:** A obra afetada pode enfrentar déficit de material reservado (exibido ao jogador / aguardando nova entrega ou nova reserva quando houver disponibilidade), mesmo que exista saldo livre em outra pilha — mantendo contabilidade estrita e sem criar saldos do nada.
- **Prevenção de duplicação:** A dedução na reserva ocorre na própria transação de `step_decay()` junto à dedução física, mantendo $Q_{\text{pilhas\_livre}} \ge 0$, $Q_{\text{pilhas\_reservado}} + Q_{\text{pilhas\_livre}} == Q_{\text{pilhas\_físico}}$ e $Q_{\text{deteriorado}}(R)$ integralmente conservado.

---

## 4. NavMesh, Colisão e Validação Espacial (D6)

### 4.1. Comportamento Real do `WorldNavigation.request_rebake()`
A inspeção direta de `src/navigation/world_navigation.gd` revela o fluxo síncrono/assíncrono real:
```gdscript
NavigationServer3D.parse_source_geometry_data(nav_mesh, source_data, source_root)
NavigationServer3D.bake_from_source_geometry_data(nav_mesh, source_data)
```
1. **Fase Síncrona:** A análise geométrica dos colisores e a geração dos polígonos do `NavigationMesh` ocorrem **bloqueando a thread principal** na chamada de `request_rebake()`.
2. **Fase Assíncrona de Sincronização:** Após o bake síncrono, o nó entra em `_is_syncing = true` e desativa `_is_ready = false`. Nos quadros de física seguintes (`_physics_process`), ele aguarda o `NavigationServer3D` sincronizar o mapa até emitir `navigation_ready`.
3. **Contrato de Segurança para Unidades:**
   - Durante `_is_ready == false`, consultas `find_path()` retornam `QueryStatus.NOT_READY`.
   - Unidades que já possuem caminho traçado continuam seguindo os waypoints existentes sem falhar.
   - **Comportamento real implementado na base (`src/rts/command_controller.gd`, linhas 80–82 e 215–217):** enquanto `not _world_navigation.is_navigation_ready()`, novas ordens emitidas pelo jogador são **rejeitadas imediatamente** com a razão `"navigation_not_ready"` (**não** existe fila ou retenção automática implementada). Uma eventual retenção/enfileiramento curto durante o intervalo de sincronização (`1` a `3` quadros de física) permanece apenas como **proposta futura opcional (`PROPOSTA`)**, nunca comportamento vigente.
4. **Impacto e Medição na Intel UHD 620:**
   - No mapa de testes (64 × 64 m), o bake síncrono consome ~6 ms.
   - O benchmark de desempenho da T3.9 monitorará `get_last_bake_metrics()` em 1080p para assegurar que nenhum evento de colocação/conclusão gere quadros $> 100\text{ ms}$.

### 4.2. Isolamento de Máscaras de Colisão (PROPOSTA TÉCNICA)
Para evitar que edifícios quebrem a física de unidades ou o raycast de terreno:
- **`MASK_WORLD_SOLID` (inalterado):** `MASK_TERRAIN | MASK_OBSTACLES` (camadas 1 e 2). Mantido estritamente para suporte de solo, gravidade de unidades e picking básico.
- **`MASK_NAV_STATIC` (proposto):** `MASK_TERRAIN | MASK_OBSTACLES | MASK_BUILDINGS` (camadas 1, 2 e 5). Atribuído a `nav_mesh.geometry_collision_mask` para que o NavMesh contorne fundações e paredes construídas.
- **`WorldPicker` (proposto):** A busca de alvos executa uma consulta dedicada para `CollisionLayers.MASK_BUILDINGS` antes do raycast de terreno, retornando `PickResult.Kind.CONSTRUCTION_SITE` ou `BUILDING` sem interferência de colisão com o solo.

### 4.3. Validação Espacial da `CampStorageZone` e Conectividade Futura (D6)
- **Área Efetiva na Cena:** `levels/test_map/test_map.tscn` define `zone_bounds_half_extents = Vector2(2.8, 2.2)`, totalizando **$5,6\text{ m}$ de largura por $4,4\text{ m}$ de profundidade** em torno da âncora `(0, 0, 0.5)`.
- **Regra de Exclusão (D6):** O `PlacementValidator` lê as propriedades dinâmicas da instância ativa de `CampStorageZone`:
  $$\text{AABB}(\text{Obra}) \cap \text{AABB}(\text{CampStorageZone}) = \emptyset$$
  Qualquer sobreposição invalida a colocação com a mensagem de rejeição: `"Posição inválida: Área reservada para pilhas do acampamento"`.
- **Limitação da Malha Atual para Conectividade Futura:** Consultar `WorldNavigation.find_path()` sobre o `NavigationMesh` existente **não prova** que a nova obra preservará corredores livres, pois o edifício ainda não foi adicionado como colisor nem assado na malha atual (o caminho poderia atravessar a própria área onde o prédio será erguido).
- **Comparação de Estratégias de Validação Considerando Ocupação Futura (PROPOSTA TÉCNICA — Estimativas Históricas da Proposta Inicial):**

> [!NOTE]
> Os tempos na tabela abaixo representam **estimativas teóricas preliminares formuladas durante a elaboração da proposta arquitetural**, antes da implementação real da T3.2. Para os tempos e custos de CPU efetivamente medidos na Intel UHD 620 (`1920×1080`) com bake assíncrono em worker thread e cache estático de geometria, consulte os relatórios de benchmark reais em [T3_2_technical_notes.md](../testing/T3_2_technical_notes.md) e [T3_2_closeout.md](../testing/T3_2_closeout.md).

| Estratégia | Mecanismo | Custo Estimado de CPU (Estimativa Histórica Pré-Implementação) | Limitações / Riscos |
|---|---|---|---|
| **Estratégia A — Avaliação em Malha Candidata** | Ao confirmar (ou após pausa curta do cursor), gera um `NavigationMeshSourceGeometryData3D` incluindo o colisor temporário da obra candidata, executa um *bake* em malha candidata isolada e consulta `NavigationServer3D` entre a `CampStorageZone`, as fontes ativas e as unidades selecionadas. | ~5 a 8 ms pontuais por verificação (estimativa preliminar; o custo real de bake Recast medido na Intel UHD 620 foi de ~44 a 93 ms no worker thread, mitigado via bake assíncrono com impacto na thread principal reduzido a ~6,6–13,5 ms). | Pico síncrono mitigado via bake assíncrono em worker thread (`bake_from_source_geometry_data_async`), cache de geometria estática e descarte seguro de RIDs. |
| **Estratégia B — Validação Espacial Conservadora** | Durante o *hover* em tempo real, verifica uma caixa de consulta expandida (*clearance* mínimo $\ge 2 \times \text{agent\_radius} + \text{folga} \approx 1,5\text{ m}$) em torno da *footprint* contra `MASK_OBSTACLES \| MASK_BUILDINGS \| MASK_RESOURCES`, além de checar pontos de acesso perimetrais no `NavMesh` atual. | $< 0,2\text{ ms}$ por quadro (estimativa preliminar; medição real de hover em 1080p: $p50 \approx 0,32\text{–}0,77\text{ ms}$, $p95 \le 2,12\text{ ms}$). | Pode gerar falsos negativos em encaixes justos (exige margem ao redor) e não detecta fechamentos topológicos à distância (ex.: bloquear a única boca de um corredor longo em U). |

- **Proposta Híbrida e Invariante Pré-Reserva:**
  1. **No *hover* em tempo real:** aplicar a **Estratégia B (conservadora)** para retorno visual imediato verde/vermelho sem degradar *frametime*.
  2. **Na confirmação (clique esquerdo):** antes de instanciar qualquer `ConstructionSite` ou chamar `reserve_batch()`, executar a **Estratégia A (avaliação em malha candidata)** confirmando que nenhuma fonte ativa, ponto de entrega na `CampStorageZone` ou unidade selecionada ficou isolada.
  3. **Garantia de Não Consumo Prematuro:** nenhuma obra consome ou reserva recursos definitivamente antes que todas as validações (terreno, exclusão da `CampStorageZone`, sobreposição, acessibilidade perimetral e conectividade pós-ocupação) tenham sido integralmente aprovadas.

---

## 5. Tabela de Custos, Dimensões e Tempos (APROVADA EM 14/11/2026 COMO VALORES PROVISÓRIOS — D4)

Os parâmetros foram recalculados com base nos dados reais do projeto:
- Madeira: peso **2** (`data/resources/wood.tres`).
- Pedra: peso **3** (`data/resources/stone.tres`).
- Capacidade de transporte: **20 de peso**.
- Ritmo de extração na T2: Madeira = 2 unidades / 2,5 s; Pedra = 1 unidade / 3,5 s.
- Caminhada: $4,8\text{ m/s}$ (vazio) a $\approx 2,88\text{ m/s}$ (com 100% de carga).

| Parâmetro | Abrigo Básico (`shelter_basic`) | Depósito Rústico (`storage_depot`) | Justificativa Técnica / Pressupostos |
|---|---|---|---|
| **Classificação** | Residência unifamiliar (GDD §6) | Armazém coberto protetor (GDD §5, §6; D5) | Abrigo cumpre meta T3; depósito protege excedente. |
| **Dimensões (XZ)** | $4,0\text{ m} \times 4,0\text{ m}$ ($16\text{ m}^2$) | $5,0\text{ m} \times 4,0\text{ m}$ ($20\text{ m}^2$) | Espaço externo rústico, proporção legível em 45°. |
| **Altura Visual** | $3,0\text{ m}$ (teto inclinado) | $2,8\text{ m}$ (cobertura rústica) | Diferenciação volumétrica para visão isométrica. |
| **Custo: Madeira** | **12 unidades** (peso: $12 \times 2 = 24$) | **18 unidades** (peso: $18 \times 2 = 36$) | Madeira para pilares e esteios. |
| **Custo: Pedra** | **6 unidades** (peso: $6 \times 3 = 18$) | **10 unidades** (peso: $10 \times 3 = 30$) | Pedra para sapatas, base seca e muretas. |
| **Peso Total de Materiais** | **42 unidades de peso** | **66 unidades de peso** | Valores reais corrigidos conforme `data/resources/*.tres`. |
| **Logística de Viagens** *(capacidade: 20; sob regra **D9**, apenas 1 transportador ativo por canteiro — `SOLO_SUPPLIER` com 1 trab. ou `TRANSPORTER` único com 2–3 trab.; em `src/units/orders/construct_order.gd`, `_execute_pile_withdrawal()` saca um tipo de recurso por viagem)* | **3 viagens pelo transportador ativo:**<br>• Viagem 1: 10 madeiras (peso 20)<br>• Viagem 2: 2 madeiras (peso 4)<br>• Viagem 3: 6 pedras (peso 18) | **4 viagens pelo transportador ativo:**<br>• 18 madeiras = 2 viagens de 9 (peso 18)<br>• 10 pedras = 2 viagens de 5 (peso 15)<br>*(Sob D9, mesmo com 2–3 trabalhadores, apenas 1 transporta enquanto 1–2 montam)* | Cargas homogêneas por viagem em números inteiros, sem exceder a capacidade individual de `20`, respeitando D4 e D9. |
| **Estimativa de Transporte** *(estimativa ilustrativa de planejamento para ~15 m de distância, não medição executada)* | ~ $30\text{ a }40\text{ s}$ estimados (ilustrativo) para o transportador ativo | ~ $45\text{ a }60\text{ s}$ estimados (ilustrativo) para o transportador ativo *(enquanto 1–2 construtores já podem iniciar montagem parcial na T3.4)* | Valores ilustrativos supondo materiais previamente acumulados nas pilhas do acampamento (não representam benchmark medido). |
| **Tempo de Coleta Prévia** *(se pilhas vazias)* | Madeira: 6 operações $\times$ 2,5 s = 15 s<br>Pedra: 6 operações $\times$ 3,5 s = 21 s | Madeira: 9 operações $\times$ 2,5 s = 22,5 s<br>Pedra: 10 operações $\times$ 3,5 s = 35 s | Ritmo real das fontes do `TestMap` na T2. |
| **Esforço de Construção** | **30,0 s-construtor** (**15,0 s** com casal junto) | **45,0 s-construtor** (**22,5 s** com casal junto) | Tempo de trabalho no perímetro após materiais entregues. |
| **Máximo Construtores** | **2 trabalhadores** | **2 trabalhadores** | Casal inicial sem congestionamento perimetral. |
| **Função / Benefício** *(APROVADO — provisório)* | Residência permanente do casal (conclusão T3). | Protege até **50 madeiras, 50 pedras, 30 alimentos**. Decaimento = **0,0**. *(Capacidade provisória aprovada em 14/11/2026, sujeita a balanceamento)* | Elimina perda por exposição dentro da capacidade aprovada. |

> **Registro de Governança (14/11/2026):** Todos os valores numéricos desta tabela (dimensões, custos de madeira/pedra, esforço de construção, limite de 2 construtores e capacidade provisória do depósito de 50 madeiras, 50 pedras e 30 alimentos) foram **aprovados pelo proprietário em 14/11/2026 como valores provisórios sujeitos a balanceamento** em testes jogáveis.

---

## 6. Cancelamento e Reembolso Proporcional (D3)

### 6.1. Regra de Devolução Contábil
O cancelamento de obra em andamento devolve recursos sem gerar duplicações nem abandonar pilhas espalhadas pelo mapa:

1. **Materiais Reservados nas Pilhas ($M_{\text{reservado\_pendente}}$):**
   - Liberação imediata nas pilhas físicas da `CampStorageZone`:
   - $Q_{\text{pilhas\_livre}} \mathrel{+}= M_{\text{reservado\_pendente}}, \quad Q_{\text{pilhas\_reservado}} \mathrel{-}= M_{\text{reservado\_pendente}}$.
   - **Reembolso: 100% integral.**
2. **Materiais em Transporte nas Mochilas ($M_{\text{em\_transporte}}$):**
   - A ordem de suprimento é convertida imediatamente em `DeliverToCampOrder`.
   - O trabalhador retorna à `CampStorageZone` e descarrega os materiais no chão do acampamento.
   - **Reembolso: 100% integral após caminhada de retorno.**
3. **Materiais no Buffer do Canteiro Não Consumidos ($Q_{\text{buffer\_canteiro}}$):**
   - Materiais entregues e intactos.
   - Trabalhadores no local recebem ordem para recolher o buffer e transportá-lo de volta à `CampStorageZone`. Não são criadas pilhas soltas no terreno fora do acampamento.
   - **Reembolso: 100% integral.**
4. **Materiais Incorporados à Estrutura ($Q_{\text{incorporado}}$):**
   - Materiais fixados sofrem perda por demolição proporcional ao progresso da obra:
     $$M_{\text{recuperado\_incorporado}}(R) = \left\lfloor Q_{\text{incorporado}}(R) \times (1.0 - \text{progresso}) \times \eta_{\text{demolição}} \right\rfloor$$
   - Onde a eficiência de recuperação $\eta_{\text{demolição}} = 0,50$ foi **APROVADA em 14/11/2026** como taxa provisória sujeita a balanceamento.
   - Detalhes técnicos operacionais da logística de retorno (ex.: ordem automática dos trabalhadores ao recolher o saldo recuperado vs. fila de devolução e arredondamentos em cenários de borda) permanecem sujeitos a testes durante a etapa T3.6.
   - O saldo recuperado é somado ao lote de transporte de retorno ao acampamento. A fração restante é contabilizada como $Q_{\text{perda\_demolição}}(R)$.

### 6.2. Exemplos Concretos de Cancelamento (Abrigo Básico: 12 Madeiras, 6 Pedras)

- **Cenário A — Cancelamento em 0% de montagem (materiais já entregues no canteiro):**
  - $Q_{\text{buffer}} = 12\text{ madeiras}, 6\text{ pedras}$; $Q_{\text{incorporado}} = 0$.
  - Reembolso do buffer: 12 madeiras, 6 pedras (100%).
  - Reembolso do incorporado: 0.
  - **Devolvido ao acampamento:** 12 madeiras, 6 pedras (**100%**). Perda: 0.

- **Cenário B — Cancelamento em 50% de progresso de montagem:**
  - $Q_{\text{buffer}} = 6\text{ madeiras}, 3\text{ pedras}$; $Q_{\text{incorporado}} = 6\text{ madeiras}, 3\text{ pedras}$.
  - Reembolso do buffer: 6 madeiras, 3 pedras (100%).
  - Reembolso do incorporado:
    - Madeira: $\lfloor 6 \times (1.0 - 0.5) \times 0.5 \rfloor = \lfloor 1,5 \rfloor = 1\text{ madeira}$.
    - Pedra: $\lfloor 3 \times (1.0 - 0.5) \times 0.5 \rfloor = \lfloor 0,75 \rfloor = 0\text{ pedras}$.
  - **Devolvido ao acampamento:** $6 + 1 = 7\text{ madeiras}$; $3 + 0 = 3\text{ pedras}$ (**58,3% madeira, 50% pedra**).
  - Perda justificada por demolição: 5 madeiras, 3 pedras.

- **Cenário C — Cancelamento em 90% de progresso de montagem:**
  - $Q_{\text{buffer}} = 1\text{ madeira}, 0\text{ pedras}$; $Q_{\text{incorporado}} = 11\text{ madeiras}, 6\text{ pedras}$.
  - Reembolso do buffer: 1 madeira, 0 pedras.
  - Reembolso do incorporado:
    - Madeira: $\lfloor 11 \times (1.0 - 0.9) \times 0.5 \rfloor = \lfloor 0,55 \rfloor = 0\text{ madeiras}$.
    - Pedra: $\lfloor 6 \times (1.0 - 0.9) \times 0.5 \rfloor = \lfloor 0,30 \rfloor = 0\text{ pedras}$.
  - **Devolvido ao acampamento:** $1 + 0 = 1\text{ madeira}$; $0 + 0 = 0\text{ pedras}$ (**8,3% madeira, 0% pedra**).
  - Perda justificada por demolição: 11 madeiras, 6 pedras.

---

## 7. Persistência Mínima em Disco na T3 (P2 — D1)

### 7.1. Mecanismo de Escrita Segura e Tratamento de Falhas
Godot não oferece primitivas nativas de transação POSIX atômica multiplataforma em seu subsistema de arquivos (e no Windows a substituição de arquivos existentes pode falhar se houver bloqueio). Portanto, a escrita segura adota o seguinte protocolo sequencial em `user://saves/`:

1. **Gravação Temporária:** Escreve todo o conteúdo JSON em `user://saves/t3_settlement_buildings.json.tmp`.
2. **Validação Estrutural:** O arquivo temporário é reaberto e submetido ao validador de integridade (§7.4). Se falhar ou estiver incompleto, o `.tmp` é removido e a gravação é abortada, preservando os arquivos anteriores.
3. **Backup de Segurança:** Se `t3_settlement_buildings.json` já existir, ele é copiado/movido para `t3_settlement_buildings.json.bak` após remoção de `.bak` obsoleto.
4. **Substituição:** O `.tmp` validado é movido para `t3_settlement_buildings.json` via `DirAccess.rename_absolute()`.
5. **Recuperação em Inicialização (Crash Recovery):**
   - Ao carregar, executa a validação completa (§7.4) sobre `t3_settlement_buildings.json`.
   - Se ausente, ilegível ou reprovado na integridade, tenta carregar e validar `t3_settlement_buildings.json.bak`.
   - Se ambos falharem, registra erro explícito e mantém/inicializa estado limpo seguro sem corromper o inventário em memória.

### 7.2. Snapshot Consistente do Estado da T3 (Sem Dupla Contagem)
Para evitar duplicação contábil, **cada unidade física de recurso aparece em exatamente um local no arquivo**:
- Materiais no chão do acampamento ficam em `camp_storage.piles` (com `reservations` por `site_id`).
- Materiais já carregados por trabalhadores ficam em `units[].carry_load`, com **vínculo explícito por canteiro de origem** (ex.: `transit_claims_by_site` / `target_site_id` derivado do contrato real de `_transit_claims`), **independentemente de a unidade ainda estar executando `ConstructOrder` ou ter sido interrompida por outra ordem**. O canteiro **não** duplica um contador independente fora dessa soma validada em carregamento.
- Materiais já entregues ao canteiro ficam em `materials_buffer` ou `materials_consumed`.
- **Déficit legítimo por deterioração (Alternativa B + `DEC-11B`):** caso pilhas reservadas tenham sofrido desgaste antes da retirada física, a parcela perdida que ainda não recebeu complementação manual autorizada permanece registrada (ou derivada explicitamente como `deficit_uncompensated`), garantindo que o progresso já incorporado ao canteiro jamais seja invalidado ou bloqueado na validação de save.

```json
{
  "schema_version": 1,
  "generator": "DawnOfKin_T3",
  "save_time_sec": 384.2,
  "camp_storage": {
    "piles": [
      {
        "pile_id": 1,
        "resource_id": "wood",
        "amount": 16,
        "reservations": { "site_depot_1": 6 },
        "position": [0.0, 0.0, 0.5],
        "elapsed_exposure_sec": 45.2,
        "decay_accumulator_sec": 0.0
      },
      {
        "pile_id": 2,
        "resource_id": "stone",
        "amount": 9,
        "reservations": { "site_depot_1": 6 },
        "position": [1.2, 0.0, 0.5],
        "elapsed_exposure_sec": 12.0,
        "decay_accumulator_sec": 0.0
      }
    ]
  },
  "storage_depots": [],
  "buildings_completed": [
    {
      "instance_id": "bld_shelter_1",
      "definition_id": "shelter_basic",
      "transform": {
        "origin": [6.5, 0.0, -8.0],
        "basis": [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]]
      }
    }
  ],
  "construction_sites": [
    {
      "site_id": "site_depot_1",
      "definition_id": "storage_depot",
      "transform": {
        "origin": [-7.0, 0.0, 5.0],
        "basis": [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]]
      },
      "work_progress_sec": 9.0,
      "materials_required": { "wood": 18, "stone": 10 },
      "materials_consumed": { "wood": 3, "stone": 2 },
      "materials_buffer": { "wood": 3, "stone": 2 },
      "materials_reserved_pending": { "wood": 6, "stone": 6 }
    }
  ],
  "units": [
    {
      "unit_id": "unit_leader_a",
      "character_id": "leader_a",
      "position": [-3.2, 0.0, 2.4],
      "rotation_y": 0.45,
      "carry_load": { "wood": 6 },
      "active_order": "ConstructOrder",
      "order_phase": "DELIVERING_TO_SITE",
      "target_site_id": "site_depot_1"
    },
    {
      "unit_id": "unit_leader_b",
      "character_id": "leader_b",
      "position": [-6.1, 0.0, 4.2],
      "rotation_y": -1.10,
      "carry_load": {},
      "active_order": "ConstructOrder",
      "order_phase": "ASSEMBLING",
      "target_site_id": "site_depot_1"
    }
  ],
  "resource_sources": [
    { "source_id": "wood_tree_01", "remaining_amount": 0, "has_extracted": true },
    { "source_id": "wood_tree_02", "remaining_amount": 8, "has_extracted": true },
    { "source_id": "stone_rock_01", "remaining_amount": 0, "has_extracted": true },
    { "source_id": "stone_rock_02", "remaining_amount": 17, "has_extracted": true },
    { "source_id": "food_bush_01", "remaining_amount": 30, "has_extracted": false },
    { "source_id": "food_bush_02", "remaining_amount": 30, "has_extracted": false }
  ]
}
```
*Nota contábil do exemplo acima (`deficit_uncompensated = 0` neste snapshot sem perdas pendentes):*
- **Madeira em `site_depot_1`:** `consumed (3) + buffer (3) + in_transit_for_site [unit_leader_a: 6] + reserved_pending (6) + deficit_uncompensated (0) = 18` (= `materials_required.wood`).
- **Pedra em `site_depot_1`:** `consumed (2) + buffer (2) + in_transit_for_site (0) + reserved_pending (6) + deficit_uncompensated (0) = 10` (= `materials_required.stone`).
- **Reserva nas pilhas:** `pile 1` reserva `6 wood` (= `reserved_pending.wood`); `pile 2` reserva `6 stone` (= `reserved_pending.stone`).
- **Balanço global contra fontes naturais:** Extraídos `40 wood` (`24 + 16`) = `12 (bld_shelter_1) + 18 (site_depot_1) + 10 (livre na pile 1)`. Extraídos `19 stone` (`18 + 1`) = `6 (bld_shelter_1) + 10 (site_depot_1) + 3 (livre na pile 2)`.
- **Estrutura de `storage_depots` (quando concluídos):** cada entrada registra `depot_id`, `building_instance_id`, `definition_id`, `capacities` e `stored_amounts` (`{ "wood": int, "stone": int, "food": int }`) mais `reservations` por `site_id`, permitindo restaurar estoques protegidos sem duplicar com `camp_storage.piles`.

### 7.3. Preservação de Fontes Naturais (`ResourceSource`) entre Salvamentos
Na T2, cada árvore, rocha e arbusto em `levels/test_map/test_map.tscn` possui `source_id` estável (`wood_tree_01`, `stone_rock_01`, `food_bush_01`, etc.) e estoque finito (`initial_amount` e `_remaining_amount`), sem regeneração. Sem persistir essas fontes na T3, recarregar uma partida após construir o abrigo restauraria todas as árvores e rochas para o valor inicial, permitindo coleta infinita e duplicação econômica.

**Solução Mínima na T3 (sem antecipar sistema de mundo da T4):**
- O snapshot persiste apenas o par mínimo `{ source_id, remaining_amount, has_extracted }` das fontes existentes no mapa.
- Na carga: cada `ResourceSource` identificada por `source_id` restaura `_remaining_amount` (limitado a `[0, initial_amount]`) e `_has_extracted`.
- Se `remaining_amount == 0` em uma árvore, o estado visual `TreeVisualState.FALLEN` é aplicado diretamente sem reproduzir a animação de queda, mantendo `is_depleted() == true` e bloqueando novas extrações.

### 7.4. Validação de Integridade Pré-Aceite do Save *(alinhada à Alternativa B, `DEC-11B` e contrato de trânsito da T3.3 / `T3.4-ARCHITECTURE-R2`)*
Antes de aplicar qualquer arquivo carregado ao estado da cena, `BuildingPersistenceManager` executa validação estrita em memória. Se **qualquer** verificação falhar, o arquivo é rejeitado e o carregador recorre ao `.bak` ou aborta com erro seguro:
1. **Esquema e Tipos:** `schema_version == 1`, chaves obrigatórias presentes, valores numéricos finitos (`is_finite`) e quantidades inteiras $\ge 0$.
2. **Identificadores Válidos:** `definition_id` existente no catálogo, `character_id` reconhecido, `source_id` existente no mapa e unicidade de `instance_id`, `site_id`, `pile_id` e `unit_id`.
3. **Capacidade e Limites:** soma de pesos em `carry_load` de cada unidade $\le$ sua capacidade efetiva; `remaining_amount` de cada `ResourceSource` em `[0, initial_amount]`; saldos de depósito dentro da capacidade configurada.
4. **Lastro Físico das Reservas:** para toda pilha $p$, $\sum_{c} \text{reservations}(p, c) \le \text{amount}(p)$; e para todo canteiro $c$ e recurso $R$, $\sum_{p} \text{reservations}(p, c, R) == \text{materials\_reserved\_pending}(c, R)$.
5. **Conservação e Déficit por Deterioração no Canteiro:** definindo `in_transit_for_site(c, R)` como o total físico em posse de unidades com vínculo de trânsito ativo para o canteiro $c$ (via `_transit_claims`, mesmo se a unidade estiver atualmente executando outra ordem após interrupção), todo canteiro $c$ e recurso $R$ deve satisfazer:
   - Todos os termos não negativos: $\text{consumed}(c, R) \ge 0$, $\text{buffer}(c, R) \ge 0$, $\text{reserved\_pending}(c, R) \ge 0$, $\text{in\_transit\_for\_site}(c, R) \ge 0$, e $\text{deficit\_uncompensated}(c, R) \ge 0$.
   - Soma coberta nunca excede o exigido: $\text{consumed}(c, R) + \text{buffer}(c, R) + \text{reserved\_pending}(c, R) + \text{in\_transit\_for\_site}(c, R) \le \text{materials\_required}(c, R)$.
   - Equação exata com déficit legítimo de decaimento (`Alternativa B`):
     $$\text{consumed}(c, R) + \text{buffer}(c, R) + \text{reserved\_pending}(c, R) + \text{in\_transit\_for\_site}(c, R) + \text{deficit\_uncompensated}(c, R) == \text{materials\_required}(c, R)$$
   - `deficit_uncompensated(c, R)` só pode ser $> 0$ quando corresponder a perda legítima por deterioração sob Alternativa B aguardando eventual complementação manual autorizada (`DEC-11B`), garantindo que nenhum save válido com progresso preservado seja rejeitado após decaimento de pilha exposta — nem permita fabricação silenciosa de materiais sem saldo livre real.
6. **Progresso Coerente:** $0.0 \le \text{work\_progress\_sec} \le \text{build\_work\_required}$.

### 7.5. Cenário: Carga Interrompida Durante Transporte
Se a partida for salva enquanto `unit_leader_a` caminha com 6 madeiras sacadas da `pile 1` para `site_depot_1`:
- **Caso A — Ordem de construção ainda ativa:** o snapshot registra `carry_load: {"wood": 6}`, vínculo de trânsito para `"site_depot_1"` (`transit_claims_by_site`), `active_order: "ConstructOrder"`, `order_phase: "DELIVERING_TO_SITE"`.
- **Caso B — Trabalhador interrompido antes da entrega (ex.: recebeu `MoveOrder` ou ordem de coleta):** as 6 madeiras permanecem fisicamente na mochila (`carry_load`) e vinculadas ao trânsito do canteiro (`_transit_claims`) conforme o contrato validado na T3.3-R1, **sem depender** de `active_order == "ConstructOrder"`. Na restauração, a conservação em §7.4 continua fechando exatamente e a carga física não desaparece nem se duplica.
- Em ambos os casos, as 6 madeiras já foram subtraídas do `amount` da `pile 1` no saque e ainda não constam no `materials_buffer` de `site_depot_1`.
- **Restauração:** o carregador valida a conservação (§7.4), posiciona `LeaderA` em `[-3.2, 0.0, 2.4]`, restaura sua mochila e seu vínculo em `_transit_claims`, e reconstitui `ConstructOrder` (no Caso A) ou a ordem interrompida/devolução à `CampStorageZone` (no Caso B ou se o canteiro tiver sido cancelado via `D3`), sempre após `WorldNavigation` emitir `navigation_ready`. Se houver vínculo para `target_site_id` inexistente sem cancelamento correspondente, o snapshot falha na validação pré-aceite (§7.4). *(O contrato completo do snapshot de `T3.8` será consolidado após a homologação da `T3.4-ARCHITECTURE-R2` e das etapas `T3.5`–`T3.7`).*

---

## 8. Sequenciamento Incremental Corrigido (T3.1 a T3.9)

A ordem dos incrementos foi reestruturada para garantir que a validação espacial preceda a criação de canteiros jogáveis, evitando que obras sejam instanciadas em locais inválidos:

| Etapa | Objetivo Principal | Dependências | Arquivos Previstos | Riscos Técnicos | Testes Automatizados Previstos | Critério de Aceite |
|---|---|---|---|---|---|---|
| **T3.0 — Revisão Arquitetural** *(CONCLUÍDA)* | Correção técnica de consistência contábil, NavMesh e dimensões | `main` (`t2-complete`) | `docs/architecture/T3_architecture_PROPOSAL.md` | Inconsistência conceitual | `git diff --check` | Documento corrigido e aprovado pelo proprietário |
| **T3.1 — Contabilidade, Reservas e Saque em Lote** *(CONCLUÍDA E APROVADA)* | Implementar `reserve_batch()`, `release_batch()`, `withdraw_reserved()`, saques em lote atômicos e redução direta de reserva no decaimento (Alternativa B) com interface extensível | T3.0 aprovada | `src/economy/settlement_storage_source.gd`, `ground_pile_manager.gd`, `in_memory_storage_source.gd`, `settlement_inventory.gd`, `pile_reservation_ledger.gd` | Regressão em invariantes contábeis da T2 | 17 testes unitários (`test_t3_1_reservations.gd`) cobrindo reservas, concorrência, cancelamento, rollback e decaimento | CONCLUÍDA: Aprovada pelo proprietário e integrada na `main` em 15/11/2026 após auditoria técnica; 199/199 testes aprovados (6.899 asserções) reportados |
| **T3.2 — Validação Espacial, Área Reservada e Prévia sem Grid** *(CONCLUÍDA E APROVADA)* | `PlacementValidator` (exclusão da `CampStorageZone` na T3 sem impedir futuras regiões/locais de depósito, amostragem 3×3 de terreno, malha candidata isolada via cache estático com `append_arrays()`, bake assíncrono em worker thread, revalidação TOCTOU e isolamento por região) e prévia visual contínua sem grid | T3.1 | `src/buildings/building_definition.gd`, `placement_validator.gd`, `placement_preview.gd`, `placement_controller.gd`, `placement_test_overlay.gd`, `src/navigation/world_navigation.gd` | Falsos positivos de rejeição, pausas na thread principal ou condição de corrida antes do callback | 12 testes unitários e de integração (`test_t3_2_placement_validation.gd`, `test_t3_2_placement_flow.gd`) cobrindo cenários A–E e benchmark 1080p | CONCLUÍDA: Aprovada formalmente pelo proprietário em 15/11/2026 após 11/11 testes manuais aprovados (A1–D3), auditoria técnica do ChatGPT e 211/211 testes automatizados (7.147 asserções) reportados |
| **T3.3 — Canteiro de Obra e Suprimento Físico (Transporte)** *(CONCLUÍDA E HOMOLOGADA)* | Instanciação de canteiro em local válido (sem pilha obrigatória ao lado da obra), reserva nas pilhas e trabalhadores transportando materiais com peso real (regra 1 / 2 / 3 trabalhadores **D9** até espera `BUILDER_STANDBY`) | T3.2 | `src/buildings/construction_site.gd`, `construction_manager.gd`, `src/units/orders/construct_order.gd`, `build_slot_planner.gd` | Trabalhador travar no percurso ou tentar sacar mais do que aguenta carregar | Testes unitários e de integração T3.3 (`test_t3_3_construction_site.gd`, `test_t3_3_construction_logistics.gd`) | **CONCLUÍDA:** Homologada pelo proprietário e integrada na `main` em `16/11/2026` (`3c6fc0bd36fc3828af5a89662fb23cfb60d37865`, tag `t3-3-complete`; ver [T3_3_closeout_ACCEPTANCE.md](../testing/T3_3_closeout_ACCEPTANCE.md)) |
| **T3.4 — Ordem de Construção, Progresso com Consumo e Conclusão** | Consumo progressivo do buffer, avanço de progresso, transmutação em `BuildingInstance` e rebake do NavMesh | T3.3 | `src/buildings/construction_site.gd`, `building_instance.gd`, `src/units/orders/construct_order.gd`, `src/navigation/world_navigation.gd` | Deadlocks com múltiplos construtores ou unidades presas no bake | Testes de integração: 1 e 2 construtores, interrupção por nova ordem e conclusão do abrigo | Abrigo conclui em 100%, consome materiais do buffer e unidades contornam a nova construção |
| **T3.5 — Interface de Construção (Botão, Painel Retrátil e Contexto)** | Botão inferior direito, catálogo retrátil de obras e painel contextual do canteiro | T3.4 | `src/ui/construction_hud.gd`, `building_inspector_panel.gd`, `src/rts/rts_input_controller.gd`, `src/main/main.gd` | Bloqueio de cliques RTS do mapa pela UI | Testes de integração de UI: abrir painel, selecionar, posicionar e cancelar com Esc | Interface funcional sem sobrepor painel do personagem nem estoque |
| **T3.6 — Cancelamento com Reembolso Proporcional** | Desfazer reservas, redirecionar transportadores para devolução e recolher buffer do canteiro com taxa de demolição | T3.5 | `src/buildings/construction_site.gd`, `building_manager.gd`, `src/units/orders/deliver_to_camp_order.gd` | Geração indevida de recursos ou perda de material transportado | Testes unitários e de integração de cancelamento em 0%, 50% e 90% | Reembolso nunca excede custo original; materiais retornam fisicamente à `CampStorageZone` |
| **T3.7 — Depósitos Protetores contra Deterioração** | Construir `StorageDepotInstance`, integrar `CompositeStorageSource` e zerar decaimento da capacidade protegida | T3.6 | `src/buildings/storage_depot.gd`, `src/economy/composite_storage_source.gd`, `src/ui/settlement_stockpile_panel.gd` | Conflito de autoridade entre pilhas livres e depósitos | Testes com `EconomyClockController`: recursos no depósito não sofrem deterioração | Depósito concluído protege recursos até o limite de capacidade e atualiza o HUD |
| **T3.8 — Persistência Mínima Versionada em Disco (P2)** | Serialização segura (`.tmp` $\rightarrow$ `.bak` $\rightarrow$ replace), fontes naturais (`ResourceSource`), unidades em trânsito e validação pré-carga | T3.7 | `src/persistence/building_persistence_manager.gd`, `src/economy/resource_source.gd`, `src/main/main.gd` | Corrupção de arquivo, dessincronização contábil ou regeneração de fontes ao recarregar | Testes de save/load: consistência de progresso, fontes exauridas, rejeição de save inválido e recuperação de `.bak` | Jogo recarregado preserva obras, fontes e cargas em trânsito sem duplicar recursos |
| **T3.9 — Validação Global, Protocolo Manual e Benchmarks** | Execução de suíte segmentada completa, bateria de testes manuais e medição de performance na Intel UHD 620 | T3.8 | `tests/perf/t3_perf_benchmark.gd`, `docs/testing/T3_manual_test_protocol.md` | Queda de FPS abaixo da meta ($p95 > 16,7\text{ ms}$ em CA) ou picos de rebake | Suíte completa via `run_tests.ps1 -Segmented` + benchmark 1080p | 100% testes aprovados, 0 avisos/erros e $p95 \le 16,7\text{ ms}$ na tomada CA |

---

## 9. Governança, Aprovações de 14/11/2026 e Pendência Final

### 9.1. Decisões Aprovadas em 14/11/2026
Além das sete diretrizes estruturais (**D1–D7**) integralmente preservadas, o proprietário aprovou em **14/11/2026**:
1. **Tabela de Valores Provisórios (D4 — APROVADA como valores provisórios sujeitos a balanceamento):**
   - **Abrigo Básico (`shelter_basic`):** $4,0 \times 4,0\text{ m}$, 12 madeiras, 6 pedras, 30,0 s-construtor, máximo 2 construtores.
   - **Depósito Rústico (`storage_depot`):** $5,0 \times 4,0\text{ m}$, 18 madeiras, 10 pedras, 45,0 s-construtor, máximo 2 construtores.
2. **Capacidade Provisória do Depósito Rústico (D5 — APROVADA como valor provisório sujeito a balanceamento):**
   - 50 madeiras, 50 pedras e 30 alimentos (com decaimento `0,0` dentro da capacidade).
3. **Eficiência de Demolição no Cancelamento (D3 — APROVADA como taxa provisória sujeita a balanceamento):**
   - $\eta_{\text{demolição}} = 0,50$ para recuperação de materiais já incorporados à estrutura física (mantendo a fórmula proporcional da §6.1 e sujeitando apenas detalhes operacionais da logística de retorno aos testes da etapa T3.6).

### 9.2. Decisão de Deterioração sobre Reservas e Escopo Atual de Implementação
- **Política de Deterioração de Materiais Reservados nas Pilhas Expostas (§3.4 — DECIDIDO):**
  - Aprovada a **Alternativa B — Deterioração física com perda direta da reserva**. `step_decay()` prossegue normalmente e, caso comprometa saldo reservado, reduz diretamente as reservas afetadas na pilha até o saldo físico restante, sem reancoragem automática para outras pilhas.
- **Armazenamento no Mundo e Organização de Trabalhadores (D8 e D9 — DECIDIDO):**
  - Materiais poderão futuramente ser largados no chão de qualquer região, sem integrar o estoque coletivo até transporte físico a armazenamento válido. Madeira e alimentos expostos seguem seus perfis configuráveis de deterioração; **pedra bruta exposta não sofre deterioração temporal**, conforme ratificação expressa **`DEC-11A`** (preservando `data/resources/decay_stone_provisional.tres` com `can_decay = false`); ferro, aço e futuras categorias terão perfis próprios configuráveis, ainda não definidos. Reservas não protegem materiais efetivamente deterioráveis (**Alternativa B — Perda Direta**), e a complementação de reservas deterioradas exige autorização manual expressa no canteiro (**`DEC-11B`**).
  - Organização de trabalhadores na construção: 1 trabalhador busca e constrói; 2 trabalhadores (1 transporta, 1 constrói); 3 trabalhadores (1 transporta, 2 constroem), mantendo o teto provisório de 2 construtores simultâneos sem pilha obrigatória ao lado de cada obra.
- **Encerramento da Etapa T3.1 (15/11/2026):** a etapa **T3.1 — Contabilidade, Reservas e Saque em Lote** foi **IMPLEMENTADA, AUDITADA, APROVADA PELO PROPRIETÁRIO E INTEGRADA NA MAIN EM 15/11/2026** (commit `ceb3f7194a750e66dbf73ebb0b0a7460d51eb87f`).
- **Encerramento da Etapa T3.2 (15/11/2026):** a etapa **T3.2 — Validação Espacial, Área Reservada e Prévia sem Grid** foi **IMPLEMENTADA, AUDITADA TECNICAMENTE, TESTADA MANUALMENTE (11/11 ITENS) E FORMALMENTE APROVADA PELO PROPRIETÁRIO EM 15/11/2026** (branch `feature/t3-2-placement`, commit técnico final `f2110b619640a149b2c3190b05d7f08d3359891d`). O método implementado adotou:
  - Silhueta 3D contínua sem grid e sem sombras (`PlacementPreview`).
  - Amostragem 3×3 de terreno, verificação dinâmica de `CampStorageZone` (D6) e colisão contra recursos/obstáculos/unidades/pilhas.
  - Malha navegável candidata isolada via cache estático (`_cached_static_vertices`/`_cached_static_indices` copiados por `append_arrays()`), eliminando re-parsing de colisores e erros da Godot 4.7.2.
  - Bake assíncrono em worker thread via `NavigationServer3D.bake_from_source_geometry_data_async()` e revalidação de estado no callback (prevenindo condições de corrida com unidades/pilhas/rebake).
  - Isolamento de escopo por região em `ValidationContext.from_region()`, eliminando vazamento entre subárvores/mundos.
  - Com **T3.1**, **T3.2** e **T3.3** já concluídas, homologadas e integradas na `main` (`t3-3-complete`, commit `3c6fc0b`), as etapas subsequentes (**T3.4** a **T3.9**) permanecem planejadas e **estritamente bloqueadas para implementação** até revisão técnica aplicável (incluindo `T3.4-ARCHITECTURE-R2`) e autorização expressa do proprietário.

### 9.3. Histórico de Aprovação e Encerramento (T3.1 a T3.3)
- **T3.1:** condições prévias atendidas em 14/11/2026. Implementação (`81266a9`, `736be79`, `b05e8e6`) auditada pelo ChatGPT, formalmente aprovada pelo proprietário e integrada à `main` em 15/11/2026.
- **T3.2:** autorizada em 15/11/2026. Implementada e refinada com correções T3.2-R1 e T3.2-R2 (`ec4a61f`, `cbbddc5`, `643af2e`, `6340099`, `f2110b6`), com 211/211 testes automatizados (30/30 suítes) reportados, 11/11 testes manuais (A1–D3) aprovados pelo proprietário em 1280×720 e 1920×1080 e auditoria técnica independente do ChatGPT, integrada na `main` (`931ad19`).
- **T3.3:** concluída, testada manualmente (`10/10` itens aprovados pelo proprietário), formalmente homologada e integrada na `main` em 16/11/2026 (`3c6fc0bd36fc3828af5a89662fb23cfb60d37865`, tag `t3-3-complete`; ver [T3_3_closeout_ACCEPTANCE.md](../testing/T3_3_closeout_ACCEPTANCE.md)). A próxima etapa (**T3.4 — Ordem de Construção, Progresso com Consumo e Conclusão**) permanece **bloqueada** e requer conclusão/aprovação da revisão técnica `T3.4-ARCHITECTURE-R2` e autorização expressa do proprietário antes de qualquer implementação.
