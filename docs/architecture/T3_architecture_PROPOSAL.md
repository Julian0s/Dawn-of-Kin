# Dawn of Kin — T3.0-R2: Revisão da Arquitetura e Planejamento Incremental da T3 (Construção)

**Status:** PROPOSTA ARQUITETURAL REVISADA (T3.0-R2) — somente planejamento documental; nenhuma linha de código T3 implementada.<br>
**Base Auditada:** Branch `main` (`f7c24592e3a6d936dbcb63f648c474280695ab9b`), tag `t2-complete`.<br>
**Fonte Normativa:** [Dawn_of_Kin_GDD_v1.0.md](../Dawn_of_Kin_GDD_v1.0.md) (com referências informativas à minuta [Dawn_of_Kin_GDD_v1.1.md](../Dawn_of_Kin_GDD_v1.1.md)).<br>
**Engine e Alvo de Referência:** Godot `4.7.2.stable` (`gl_compatibility`), Intel UHD Graphics 620 (`1920×1080`, meta $p95 \le 16,7\text{ ms}$ em tomada CA).

---

## 1. As Sete Decisões Aprovadas pelo Proprietário (D1 a D7)

Em 14/11/2026, o proprietário do projeto deliberou sobre os pontos abertos da proposta inicial T3.0, estabelecendo os seguintes direcionamentos vinculantes que permanecem integralmente preservados nesta revisão:

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

4. **D4 — Custos, dimensões e tempos provisórios (DECIDIDO: Apresentar tabela para aprovação):**
   - Parâmetros para o **Abrigo Básico** e o **Depósito Rústico**.
   - Valores calibrados com base na capacidade de 20 unidades de peso e nos dados reais da T2 (madeira peso 2, pedra peso 3).
   - Identificados expressamente como **PROPOSTA — NÃO APROVADO**.

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

---

## 2. Matriz GDD × Código Real (`main`) × Correções Técnicas (T3.0-R2)

| Requisito / Referência | Realidade no Código da `main` (`f7c2459`) | Inconsistência Corrigida (R1 $\rightarrow$ R2) | Solução Arquitetural Aprovada |
|---|---|---|---|
| Pesos dos recursos e capacidade de carga (§5, §13 T2) | `wood.tres`: peso **2**; `stone.tres`: peso **3**; `food.tres`: peso **1**; capacidade inicial: **20** de peso. | R1 utilizou peso 3 para madeira e 4 para pedra, calculando pesos irreais (60 e 94). | Tabela corrigida: Abrigo = **42 de peso**; Depósito = **66 de peso**. Viagens recalculadas com base nos dados reais. |
| Área e dimensões da `CampStorageZone` (§5, D6) | `test_map.tscn`: `zone_bounds_half_extents = Vector2(2.8, 2.2)`. Área efetiva = **5,6 × 4,4 m** (âncora em `(0, 0, 0.5)`). | R1 mencionava 8 × 8 m (valor padrão do script desacoplado da cena). | `PlacementValidator` lê `camp_zone.zone_bounds_half_extents` dinamicamente da instância real na cena. |
| Funcionamento do `WorldNavigation.request_rebake()` (§12, §13 T1) | `parse_source_geometry_data()` e `bake_from_source_geometry_data()` executam de forma **síncrona** na thread chamadora; apenas a sincronização no `NavigationServer3D` é monitorada em ticks subsequentes via `_physics_process()`. Durante a sincronização, `_is_ready = false` e `find_path()` retorna `NOT_READY`. | R1 afirmava erroneamente que todo o bake ocorria em background e que unidades continuavam usando a malha anterior com segurança sem demonstrar o contrato. | Documentado o comportamento síncrono real. Ordens de movimento durante `_is_ready == false` são pausadas/enfileiradas até o sinal `navigation_ready`. Medição obrigatória de latência de bake na Intel UHD 620. |
| Máscaras de colisão e NavMesh (§12, `src/core/collision_layers.gd`) | `MASK_WORLD_SOLID = MASK_TERRAIN \| MASK_OBSTACLES` (usado por corpos de unidades, picking sólido e bake). `LAYER_BUILDINGS = 5` reservado. | R1 propunha fundir globalmente `LAYER_BUILDINGS` em `MASK_WORLD_SOLID`, afetando picking e física sem isolamento. | Criação de `MASK_NAV_STATIC = MASK_TERRAIN \| MASK_OBSTACLES \| MASK_BUILDINGS` específico para bake. Picking de canteiros consulta `MASK_BUILDINGS` em passo dedicado. |
| Contabilidade de estoque físico e reservas (D2, §5) | `SettlementInventory` e `GroundPileManager` controlam apenas saldo físico em pilhas no chão (`deposit_batch`, `withdraw`). | R1 unificava variáveis e não isolava buffer do canteiro de entregas acumuladas. | Formalizada a Invariante Contábil Fundamental com 7 parcelas disjuntas, separando buffer disponível de materiais incorporados. |
| Política de deterioração com reservas (D2) | `EconomyClockController.step_decay()` atinge pilhas reais pelo tempo. | R1 propunha proteger artificialmente materiais reservados no chão contra desgaste. | Proposta técnica realista: materiais no chão deterioram fisicamente; se a perda atingir cota reservada, busca-se reancoragem ou alerta de carência no canteiro. |
| Persistência e atomicidade (D1, P2) | Nenhuma persistência em disco na base atual. | R1 prometia "atomicidade universal" de arquivo sem detalhar limitações do sistema de arquivos da Godot. | Especificado fluxo de escrita em `.tmp`, validação estrutural com `JSON.parse_string()`, backup em `.bak` e substituição atômica via `DirAccess.rename_absolute()` com estratégia de recuperação de falha. |
| Sequenciamento de incrementos (§13) | Base pronta para T3.1. | R1 posicionava a criação de canteiros jogáveis antes da validação espacial e de prévia. | Sequenciamento corrigido: validação espacial e prévia (T3.2) precedem a colocação jogável e suprimento (T3.3). |

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

### 3.4. Proposta Técnica: Política de Deterioração com Reservas
Materiais mantidos no chão sofrem desgaste pelo tempo, quer estejam reservados ou não. Proteger artificialmente pilhas reservadas permitiria ao jogador usar obras como "escudo de conservação", violando a coerência do mundo.

**Política Recomendada (PROPOSTA TÉCNICA):**
1. O desgaste temporal (`step_decay()`) atinge a pilha física real na `CampStorageZone`.
2. Se a quantidade total da pilha física cair, a dedução consome primeiro o saldo livre da pilha.
3. Se a pilha for tão degradada que seu volume total fique inferior ao montante reservado ($Q_{\text{físico}} < Q_{\text{reservado}}$), ocorreu **perda real de material reservado**.
4. O `GroundPileManager` tenta imediatamente reancorar a reserva pendente em outra pilha física da mesma categoria que possua saldo livre.
5. Se o assentamento não dispuser de saldo livre em nenhuma pilha, o canteiro é notificado do déficit:
   - A obra entra no estado `AWAITING_RESOURCES` (Aguardando Suprimentos).
   - O painel do canteiro e o HUD exibem alerta: *"Faltam materiais no acampamento (perda por exposição)"*.
   - Viagens de coleta futuras descarregadas no acampamento restauram automaticamente as reservas pendentes prioritárias antes de liberar saldo geral.

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
   - Novas ordens emitidas pelo jogador durante o intervalo de sincronização (normalmente 1 a 3 quadros de física) devem ser pausadas ou retidas pelo `CommandController` até a emissão de `navigation_ready`.
4. **Impacto e Medição na Intel UHD 620:**
   - No mapa de testes (64 × 64 m), o bake síncrono consome ~6 ms.
   - O benchmark de desempenho da T3.9 monitorará `get_last_bake_metrics()` em 1080p para assegurar que nenhum evento de colocação/conclusão gere quadros $> 100\text{ ms}$.

### 4.2. Isolamento de Máscaras de Colisão
Para evitar que edifícios quebrem a física de unidades ou o raycast de terreno:
- **`MASK_WORLD_SOLID` (inalterado):** `MASK_TERRAIN | MASK_OBSTACLES` (camadas 1 e 2). Mantido estritamente para suporte de solo, gravidade de unidades e picking básico.
- **`MASK_NAV_STATIC` (novo):** `MASK_TERRAIN | MASK_OBSTACLES | MASK_BUILDINGS` (camadas 1, 2 e 5). Atribuído a `nav_mesh.geometry_collision_mask` para que o NavMesh contorne fundações e paredes construídas.
- **`WorldPicker`:** A busca de alvos executa uma consulta dedicada para `CollisionLayers.MASK_BUILDINGS` antes do raycast de terreno, retornando `PickResult.Kind.CONSTRUCTION_SITE` ou `BUILDING` sem interferência de colisão com o solo.

### 4.3. Validação Espacial da `CampStorageZone` (D6)
- **Área Efetiva na Cena:** `levels/test_map/test_map.tscn` define `zone_bounds_half_extents = Vector2(2.8, 2.2)`, totalizando **$5,6\text{ m}$ de largura por $4,4\text{ m}$ de profundidade** em torno da âncora `(0, 0, 0.5)`.
- **Regra de Exclusão:** O `PlacementValidator` lê as propriedades dinâmicas da instância ativa de `CampStorageZone`:
  $$\text{AABB}(\text{Obra}) \cap \text{AABB}(\text{CampStorageZone}) = \emptyset$$
  Qualquer sobreposição invalida a colocação com a mensagem de rejeição: `"Posição inválida: Área reservada para pilhas do acampamento"`.
- **Preservação de Corredores de Coleta:** Antes de aprovar a colocação, o validador projeta a *footprint* da obra e testa se existe ao menos um caminho navegável contínuo entre o acampamento e cada fonte de recursos ativa (`WorldNavigation.find_path()`).

---

## 5. Tabela de Custos, Dimensões e Tempos (PROPOSTA — NÃO APROVADO — D4)

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
| **Logística de Viagens** *(capacidade: 20)* | **3 viagens totais:**<br>• Viagem 1 (Trab. A): 10 madeiras (peso 20)<br>• Viagem 2 (Trab. B): 2 madeiras + 5 pedras (peso 19)<br>• Viagem 3 (Trab. A): 1 pedra (peso 3) | **4 viagens totais:**<br>• 18 madeiras = 2 viagens de 9 (peso 18)<br>• 10 pedras = 2 viagens de 5 (peso 15)<br>*(2 viagens por trabalhador atuando juntos)* | Cargas em números inteiros, sem exceder a capacidade de carga individual de 20. |
| **Estimativa de Transporte** *(pressuposto: ~15 m distância)* | ~ $30\text{ a }40\text{ s}$ acumulados de transporte (ida vazia + volta carregada a $\approx 3,3\text{ m/s}$) | ~ $45\text{ a }60\text{ s}$ acumulados de transporte com os 2 trabalhadores atuando em paralelo | Pressupõe que os materiais já estejam previamente acumulados nas pilhas do acampamento. |
| **Tempo de Coleta Prévia** *(se pilhas vazias)* | Madeira: 6 operações $\times$ 2,5 s = 15 s<br>Pedra: 6 operações $\times$ 3,5 s = 21 s | Madeira: 9 operações $\times$ 2,5 s = 22,5 s<br>Pedra: 10 operações $\times$ 3,5 s = 35 s | Ritmo real das fontes do `TestMap` na T2. |
| **Esforço de Construção** | **30,0 s-construtor** (**15,0 s** com casal junto) | **45,0 s-construtor** (**22,5 s** com casal junto) | Tempo de trabalho no perímetro após materiais entregues. |
| **Máximo Construtores** | **2 trabalhadores** | **2 trabalhadores** | Casal inicial sem congestionamento perimetral. |
| **Função / Benefício** | Residência permanente do casal (conclusão T3). | Protege até **50 madeiras, 50 pedras, 30 alimentos**. Decaimento = 0,0. | Elimina perda por exposição dentro da capacidade. |

> **Aviso:** Todos os parâmetros acima permanecem como **PROPOSTA — NÃO APROVADO**, sujeitos à validação em testes de ritmo de jogo.

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
   - Onde $\eta_{\text{demolição}} = 0,50$ (**PROPOSTA — NÃO APROVADO**).
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
Godot não oferece primitivas nativas de transação POSIX atômica multiplataforma em seu subsistema de arquivos. Portanto, a escrita segura adota o seguinte protocolo sequencial em `user://saves/`:

1. **Gravação Temporária:** Escreve todo o conteúdo JSON em `user://saves/t3_settlement_buildings.json.tmp`.
2. **Validação Estrutural:** O arquivo temporário é reaberto e analisado com `JSON.parse_string()`. Se falhar ou estiver incompleto, o `.tmp` é deletado e o processo é abortado, preservando o arquivo principal existente.
3. **Backup de Segurança:** Se `t3_settlement_buildings.json` já existir, ele é copiado para `t3_settlement_buildings.json.bak`.
4. **Substituição:** O `.tmp` validado é renomeado para o arquivo principal via `DirAccess.rename_absolute()`.
5. **Recuperação em Inicialização (Crash Recovery):**
   - Ao iniciar, tenta ler `t3_settlement_buildings.json`.
   - Se ausente ou corrompido, tenta carregar `t3_settlement_buildings.json.bak`.
   - Se ambos falharem, reporta erro e inicializa o mapa em estado padrão seguro, sem travar o motor.

### 7.2. Snapshot Consistente do Estado da T3
O JSON versionado serializa exclusivamente as entidades e saldos sob escopo da T3:
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
        "reserved_amount": 6,
        "position": [0.0, 0.0, 0.5],
        "elapsed_exposure_sec": 45.2
      },
      {
        "pile_id": 2,
        "resource_id": "stone",
        "amount": 8,
        "reserved_amount": 3,
        "position": [1.2, 0.0, 0.5],
        "elapsed_exposure_sec": 12.0
      }
    ]
  },
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
      "work_progress_sec": 10.0,
      "materials_required": { "wood": 18, "stone": 10 },
      "materials_buffer": { "wood": 6, "stone": 3 },
      "materials_consumed": { "wood": 2, "stone": 1 },
      "materials_in_transit": { "wood": 6, "stone": 0 },
      "materials_reserved_pending": { "wood": 6, "stone": 7 }
    }
  ],
  "units_logistics": [
    {
      "unit_name": "LeaderA",
      "carry_load": { "wood": 6, "stone": 0 },
      "active_order": "SupplyConstructionOrder",
      "target_site_id": "site_depot_1"
    }
  ]
}
```

### 7.3. Cenário: Carga Interrompida Durante Transporte
Se a partida for salva e recarregada enquanto o trabalhador caminha da pilha ao canteiro carregando 6 madeiras:
- O arquivo armazena a mochila do trabalhador (`carry_load: {"wood": 6}`) e a meta da ordem.
- O canteiro registra `materials_in_transit: {"wood": 6}`.
- As pilhas físicas no acampamento já deduziram essas 6 unidades.
- **Restauração:** O carregamento reconstitui o trabalhador na posição salva com sua carga e reinicia sua ordem para o canteiro. Se o canteiro foi destruído/cancelado, o trabalhador é automaticamente redirecionado para a `CampStorageZone` via `DeliverToCampOrder`. A Invariante Contábil permanece 100% conservada.

---

## 8. Sequenciamento Incremental Corrigido (T3.1 a T3.9)

A ordem dos incrementos foi reestruturada para garantir que a validação espacial preceda a criação de canteiros jogáveis, evitando que obras sejam instanciadas em locais inválidos:

| Etapa | Objetivo Principal | Dependências | Arquivos Previstos | Riscos Técnicos | Testes Automatizados Previstos | Critério de Aceite |
|---|---|---|---|---|---|---|
| **T3.0 — Revisão Arquitetural** *(atual)* | Correção técnica de consistência contábil, NavMesh e dimensões | `main` (`t2-complete`) | `docs/architecture/T3_architecture_PROPOSAL.md` | Inconsistência conceitual | `git diff --check` | Documento corrigido e aprovado pelo proprietário |
| **T3.1 — Contabilidade, Reservas e Saque em Lote** | Implementar `reserve_batch()`, `release_batch()`, `withdraw_reserved()` e deduções atômicas | T3.0 aprovada | `src/economy/settlement_storage_source.gd`, `ground_pile_manager.gd`, `settlement_inventory.gd` | Regressão em invariantes contábeis da T2 | Testes unitários com reservas múltiplas, concorrência, cancelamento de reserva e rollback | Conservação estrita: livre + reservado = físico; 0 falhas na suíte T2 |
| **T3.2 — Validação Espacial, Área Reservada e Prévia sem Grid** | `PlacementValidator` (exclusão da `CampStorageZone`, terreno e rotas) e prévia visual verde/vermelha | T3.1 | `src/buildings/building_definition.gd`, `placement_validator.gd`, `placement_preview.gd`, `placement_controller.gd` | Falsos positivos de rejeição ou obra flutuando em desníveis | Testes unitários de validação geométrica (fora vs dentro da `CampStorageZone`, declives) | Validação impede posicionamento no acampamento ou em locais que bloqueiem rotas de coleta |
| **T3.3 — Canteiro de Obra e Suprimento Físico (Transporte)** | Instanciação de canteiro em local válido, reserva nas pilhas e trabalhadores transportando materiais com peso real | T3.2 | `src/buildings/construction_site.gd`, `src/units/orders/construct_order.gd`, `build_slot_planner.gd` | Trabalhador travar no percurso ou tentar sacar mais do que aguenta carregar | Testes de integração: trabalhador retira cota da pilha, carrega com peso e descarrega no canteiro | Material sai da pilha física com peso real e passa a constar no buffer do canteiro |
| **T3.4 — Ordem de Construção, Progresso com Consumo e Conclusão** | Consumo progressivo do buffer, avanço de progresso, transmutação em `BuildingInstance` e rebake do NavMesh | T3.3 | `src/buildings/construction_site.gd`, `building_instance.gd`, `src/units/orders/construct_order.gd`, `src/navigation/world_navigation.gd` | Deadlocks com múltiplos construtores ou unidades presas no bake | Testes de integração: 1 e 2 construtores, interrupção por nova ordem e conclusão do abrigo | Abrigo conclui em 100%, consome materiais do buffer e unidades contornam a nova construção |
| **T3.5 — Interface de Construção (Botão, Painel Retrátil e Contexto)** | Botão inferior direito, catálogo retrátil de obras e painel contextual do canteiro | T3.4 | `src/ui/construction_hud.gd`, `building_inspector_panel.gd`, `src/rts/rts_input_controller.gd`, `src/main/main.gd` | Bloqueio de cliques RTS do mapa pela UI | Testes de integração de UI: abrir painel, selecionar, posicionar e cancelar com Esc | Interface funcional sem sobrepor painel do personagem nem estoque |
| **T3.6 — Cancelamento com Reembolso Proporcional** | Desfazer reservas, redirecionar transportadores para devolução e recolher buffer do canteiro com taxa de demolição | T3.5 | `src/buildings/construction_site.gd`, `building_manager.gd`, `src/units/orders/deliver_to_camp_order.gd` | Geração indevida de recursos ou perda de material transportado | Testes unitários e de integração de cancelamento em 0%, 50% e 90% | Reembolso nunca excede custo original; materiais retornam fisicamente à `CampStorageZone` |
| **T3.7 — Depósitos Protetores contra Deterioração** | Construir `StorageDepotInstance`, integrar `CompositeStorageSource` e zerar decaimento da capacidade protegida | T3.6 | `src/buildings/storage_depot.gd`, `src/economy/composite_storage_source.gd`, `src/ui/settlement_stockpile_panel.gd` | Conflito de autoridade entre pilhas livres e depósitos | Testes com `EconomyClockController`: recursos no depósito não sofrem deterioração | Depósito concluído protege recursos até o limite de capacidade e atualiza o HUD |
| **T3.8 — Persistência Mínima Versionada em Disco (P2)** | Serialização segura (`.tmp` $\rightarrow$ replace), schema versionado e reconciliação contábil pós-carregamento | T3.7 | `src/persistence/building_persistence_manager.gd`, `src/main/main.gd` | Corrupção de arquivo ou dessincronização de estoque ao recarregar | Testes de save/load: consistência de progresso, integridade de arquivo e teste de recuperação de `.bak` | Jogo recarregado preserva obras concluídas e em andamento sem duplicar recursos |
| **T3.9 — Validação Global, Protocolo Manual e Benchmarks** | Execução de suíte segmentada completa, bateria de testes manuais e medição de performance na Intel UHD 620 | T3.8 | `tests/perf/t3_perf_benchmark.gd`, `docs/testing/T3_manual_test_protocol.md` | Queda de FPS abaixo da meta ($p95 > 16,7\text{ ms}$ em CA) ou picos de rebake | Suíte completa via `run_tests.ps1 -Segmented` + benchmark 1080p | 100% testes aprovados, 0 avisos/erros e $p95 \le 16,7\text{ ms}$ na tomada CA |

---

## 9. Decisões Técnicas Ainda Pendentes de Aprovação

Para que o primeiro incremento (**T3.1**) possa ser iniciado após aprovação formal:

1. **Aprovação da Tabela Provisória Recalculada (D4):**
   - Confirmar custos do Abrigo Básico (12 Madeiras, 6 Pedras; peso 42; 3 viagens; 30 s de esforço).
   - Confirmar custos do Depósito Rústico (18 Madeiras, 10 Pedras; peso 66; 4 viagens; 45 s de esforço; capacidade 50/50/30).
2. **Aprovação da Eficiência de Demolição para Cancelamento (D3):**
   - Homologar a taxa provisória $\eta_{\text{demolição}} = 0,50$ (ou definir percentual alternativo) para recuperação de materiais já incorporados à estrutura física.
3. **Aprovação da Política de Deterioração de Pilhas com Reserva (D2):**
   - Confirmar a política técnica proposta (deterioração atinge a pilha física real; perda da cota reservada gera reancoragem ou alerta de carência no canteiro, sem proteção artificial do chão).
4. **Autorização para Início da Implementação:**
   - Autorização expressa para iniciar a codificação do incremento **T3.1 — Contabilidade, Reservas e Saque em Lote**.
