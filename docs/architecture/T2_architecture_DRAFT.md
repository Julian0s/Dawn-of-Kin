# T2 — Arquitetura Técnica: Trabalho, Transporte Físico, Pilhas no Chão e Armazenamento Progressivo

> **STATUS: RASCUNHO — NÃO APROVADO**
>
> Documento de planejamento e revisão técnica em `docs/t2-review`. **Nenhuma linha de código da T2 deve ser implementada antes da aprovação expressa do proprietário**, conforme `AGENTS.md`.

---

## 1. Linha de base e invariantes da T1

- **Engine e alvo:** Godot `4.7.2`, GDScript tipado, renderer `Compatibility / OpenGL 3.3`, hardware de referência **Intel UHD 620 (16 GB RAM)**.
- **Base Git herdada:** marco **T1 — Fundação RTS** encerrado na tag `t1-complete` (commit `2808799`, `90` testes e `1.607` asserções), mantendo `MainScene` por composição modular explícita, **zero autoloads globais obrigatórios**.
- **Orçamento de desempenho (`KNOWN_ISSUES.md`):** em `1920×1080`, a mediana medida pós-T1.10 foi `p95 = 16,586 ms` para teto obrigatório de `16,7 ms` (**margem de apenas `0,114 ms`**), e o custo RVO cresce com a contagem de unidades (`2 → 10 → 25 → 50`). Qualquer desenho de pilhas, deterioração ou UI na T2 precisa manter custo de CPU/GPU por frame próximo de zero em estado ocioso.
- **Invariantes espaciais e comportamentais que a T2 NÃO pode quebrar:**
  - Corredores livres usados pela suíte automática da T1 (`test_commands.gd`: corredor `(0, 0, -2.5..+5)` e `WallWithGap` em `x ∈ [-2, 2], z = -6`).
  - `test_test_map.gd`: `TestMap/Obstacles` deve continuar contendo apenas os obstáculos estáticos esperados (`> 10` `StaticBody3D` estritamente em `MASK_OBSTACLES`).
  - RVO na `Unit`: prioridade `1.0` parada vs `0.5` em movimento e projeção segura via `_clamp_avoidance_to_navmesh`.
  - **Clique direito padrão no chão (`PickResult.Kind.GROUND` → `MoveOrder`):** continua sendo movimento simples; novas ações de soltar carga no chão não podem quebrar ou substituir silenciosamente esse contrato.

---

## 2. Classificação estrita conforme o GDD (`DECIDIDO` vs `PROPOSTA` vs `ABERTO`)

| Classificação | Itens que orientam esta arquitetura |
|---|---|
| **DECIDIDO** | • Casal protagonista inicia **sem ferramentas, sem equipamentos e sem construções humanas pré-existentes**.<br>• **Transporte físico obrigatório (D2-1):** nada vai instantaneamente ao estoque ao coletar nem ao largar arbitrariamente no mapa.<br>• Peso unitário por material, capacidade individual e exibição em porcentagem (`0%`–`100%`).<br>• Interrupção automática ao atingir `100%` ou não caber mais 1 unidade, iniciando retorno para descarregar.<br>• **Armazenamento no chão:** materiais (`madeira`, `pedra`, `alimentos` e futuros) podem ser deixados diretamente no chão em qualquer posição válida e acessível.<br>• **Pilhas visuais variáveis:** cada pilha forma agrupamento visual reconhecível (placeholders simples permitidos na T2; modelos 3D finais depois) representando diferentes quantidades (ex.: `24` madeiras é ilustrativo, **não** teto fixo).<br>• **Exposição e deterioração:** materiais expostos sem proteção sofrem desgaste e podem desaparecer se permanecerem expostos por tempo prolongado, justificando armazéns protetores futuros (`T3+`).<br>• Armazenamento por categoria e evolução estrutural progressiva. |
| **PROPOSTA** | • Modelo híbrido de estoque: áreas/zonas lógicas de acampamento no chão (`CampStorageZone`, zero construções) que contabilizam pilhas compatíveis no `SettlementInventory`, mantendo-as expostas à deterioração até existirem armazéns cobertos (`T3+`).<br>• UX de depósito livre no chão via ação explícita (`botão/modo "Soltar carga"` no HUD ou `Alt + Clique Direito`, preservando `Shift` para fila futura e clique direito simples para mover).<br>• Entrega de carga parcial quando a fonte esgota antes de `100%`; mochila com suporte a múltiplas categorias se o jogador redirecionar a unidade.<br>• Alerta visual discreto de exposição e deterioração na HUD/pilha. |
| **ABERTO** | • Valores numéricos exatos: pesos unitários, capacidade inicial dos protagonistas, taxas de coleta, consumo alimentar, durações/taxas exatas de deterioração por categoria.<br>• Teto opcional (ou ausência de teto) de unidades por pilha visual única.<br>• Regra de cálculo de exposição ao adicionar materiais novos em pilha já parcialmente deteriorada (média ponderada vs pior idade vs reinício parcial).<br>• Regra definitiva de entrada no estoque utilizável (zona lógica no chão vs restrição mais rígida até existir depósito).<br>• Escolha final do comando UX para soltar carga no chão. |

---

## 3. Resolução da incompatibilidade do rascunho anterior

O rascunho anterior propunha iniciar `TestMap` com três cenas fixas pré-montadas (`CampWoodPile`, `CampStoneCairn`, `CampFoodCache` com `StaticBody3D` dedicados). Essa abordagem entrou em conflito com duas decisões atuais:

1. **Zero infraestrutura pré-existente:** estruturas pré-construídas no mapa inicial dão a aparência de um acampamento humano já pronto antes da chegada/ação do casal protagonista.
2. **Liberdade de pilhas no chão:** o jogador e as unidades precisam poder deixar materiais no chão em qualquer posição válida e acessível, formando pilhas dinâmicas de tamanho variável, sujeitas ao tempo e exposição.

### Arquitetura modular revista (composição em cena, sem autoloads)

1. **`ResourceDefinition` (`Resource` `.tres` parametrizado):**
   Define `resource_id` (`wood`, `stone`, `food`, extensível), `category`, `unit_weight`, `decay_profile` (parâmetros de exposição) e referência leve de visual placeholder por categoria.
2. **`UnitCarryLoad` (componente acoplado à `Unit`):**
   Mantém inventário físico individual por `resource_id`, peso total atual, `max_weight_capacity` (evolutiva no futuro por profissão/equipamento/melhoria), cálculo exato `get_fill_ratio()` / `0%`–`100%`, `can_fit_one(resource_id)` e operações transacionais (`add_units`, `take_units`, `take_all`).
3. **`GroundResourcePile` + `GroundPileManager`:**
   - `GroundResourcePile` representa uma pilha física no chão em posição navegável válida, armazenando `resource_id`, `amount`, estado de exposição/deterioração (`exposure_progress` / `remaining_lifetime_sec` parametrizado) e `storage_zone_id` opcional.
   - Usa `Area3D` leve em máscara de picking dedicada (ou compartilhada com recursos via `MASK_RESOURCES` e `PickResult.Kind.PILE`) — **não** entra em `TestMap/Obstacles` nem usa `StaticBody3D` pesado — permitindo `pick_up`, inspeção no HUD e agrupamento (`merge`). Se necessário para evitar sobreposição visual de unidades, pode usar ajuste leve de posição ou raio pequeno livre no NavMesh sem criar congestionamento RVO.
   - `GroundPileManager` (nó coordenador único na cena) concentra criação, consulta espacial para agrupamento (`merge`), atualização em lote de deterioração e emissão de eventos ao estoque.
4. **`CampStorageZone` / `StoragePoint` + `StorageRegistry`:**
   - Na **T2 (sem construções pré-prontas)**, uma `CampStorageZone` é uma **área lógica demarcada no chão** (sem paredes, sem teto, sem colisor físico e com sinalização visual mínima/desligável de acampamento no terreno, ou designável pelo jogador em revisão futura), funcionando como alvo de entrega compatível no `StorageRegistry`.
   - Na **T3+**, um armazém/depósito construído pelo jogador implementa a mesma interface de `StoragePoint` registrado no `StorageRegistry`, porém com atributo `protection_factor` (`decay_multiplier = 0.0` ou reduzido) e bônus de organização/capacidade.
5. **`SettlementInventory` (estoque utilizável da comunidade):**
   - Mantém o total utilizável disponível por categoria/recurso para consumo (T2+) e futuras construções (T3+).
   - **Invariante estrita:** coleta na árvore/arbusto/rocha altera **somente** `ResourceSource` → `UnitCarryLoad`; abandono em chão comum altera **somente** `UnitCarryLoad` → `GroundResourcePile` externa (sem creditar `SettlementInventory`).

---

## 4. Avaliação explícita: Regra Híbrida para Entrada no Estoque Utilizável (**PROPOSTA / ABERTO**)

Como ainda não há decisão fechada do proprietário sobre o exato limite entre "pilha solta no chão" e "estoque utilizável do acampamento", comparamos abaixo a **Proposta Avaliada (Híbrida)** contra alternativas mais simples:

| Modelo | Como funciona na prática | Vantagens técnicas e de gameplay | Custos, riscos e impactos | Status |
|---|---|---|---|---|
| **A. Proposta Híbrida: `CampStorageZone` lógica no chão (Recomendada para avaliação)** | Pilhas deixadas **dentro** de uma `CampStorageZone` (área demarcada no chão do acampamento, sem edifício) passam a contar no `SettlementInventory`, mas **continuam sujeitas à deterioração por exposição** até o jogador construir armazéns cobertos na `T3+`. Pilhas fora da zona ficam só no mundo físico e precisam ser recolhidas/trazidas. | • Preserva "zero construções pré-existentes" no início.<br>• Torna a T2 jogável e testável com ciclo completo (coleta → entrega → estoque utilizável).<br>• Cria motivação clara e orgânica para construir armazéns na T3+: proteger recursos que hoje estão no estoque, mas se perdem ao relento.<br>• Se uma pilha dentro da zona deteriorar, `SettlementInventory` reflete a perda real em tempo real. | • Exige sincronização bidirecional limpa entre `GroundPileManager` (pilhas dentro de `zone_id != ""`) e `SettlementInventory` quando há adição, retirada ou deterioração.<br>• Exige cuidado para evitar dupla contagem em reservas futuras de construção (T3). | **PROPOSTA** |
| **B. Alternativa Simples 1: Área única fixa invisível ao redor do casal/fogueira inicial sem retirada parcial direta** | Ao entregar na área designada do acampamento, os itens são absorvidos pelo `SettlementInventory` e uma única pilha visual representativa da zona reflete o total, ainda sofrendo deterioração global lenta até haver depósito T3+. | • Simplifica reserva de recursos para T3 e reduz número de instâncias visuais no acampamento.<br>• Menor custo de sincronia entre muitas pilhas individuais na zona. | • Menos flexível se o jogador quiser organizar várias pilhas por categoria dentro do acampamento.<br>• Aproximação visual mais rígida por categoria na zona. | **ABERTO (alternativa)** |
| **C. Alternativa Simples 2: Isolamento estrito (pilhas no chão NUNCA contam no estoque)** | Qualquer pilha no chão é apenas objeto físico no mundo; `SettlementInventory` fica zerado até existir uma estrutura/depósito explícito construído. | • Separação conceitual trivial: mundo físico vs prédio construído.<br>• Zero sincronização entre deterioração de pilhas e `SettlementInventory`. | • **Incompatível com T2 independente:** sem construção (que pertence à T3), o jogador nunca conseguiria colocar comida/madeira no estoque coletivo durante a T2, quebrando o requisito mínimo de conclusão da T2 e o início sem construções. | **Descartada para T2** |

> **Conclusão arquitetural (PROPOSTA):** adotar a interface unificada `StoragePoint` permitindo que a T2 use `CampStorageZone` lógica no chão (sem estruturas físicas humanas) com sincronização explícita por evento com `GroundPileManager` e `SettlementInventory`, deixando exatamente o mesmo contrato pronto para os armazéns protetores da `T3+`. A decisão final entre **Modelo A** (pilhas individuais dentro da zona) e **Modelo B** (pilha consolidada por categoria na zona) permanece **ABERTO** para validação do proprietário antes da `T2.1`.

---

## 5. Contratos e mecânicas das pilhas no chão

### 5.1 Soltar carga em posição válida e acessível (`Ground Drop`)
1. **Validação espacial:** a posição escolhida passa por `WorldNavigation.snap_to_navmesh` dentro de tolerância configurável, checando que a posição está sobre área navegável, fora de obstáculos (`MASK_OBSTACLES`) e não invade corredores críticos ou colisão sólida de fontes.
2. **Deslocamento e descarga:** a unidade recebe ordem `DropLoadOrder(target_pos, optional_resource_filter)`, navega até o raio de alcance (reaproveitando navegação T1) e executa descarga física instantânea ou animada curta.
3. **Preservação de carga em interrupções:** se a ordem for cancelada manualmente antes de alcançar `target_pos`, ou se o caminho falhar, a carga permanece **100% preservada** em `UnitCarryLoad` — nada se perde nem cai automaticamente no meio do trajeto salvo ordem explícita.

### 5.2 UX contextual de soltar no chão sem conflitar com T1 (`PROPOSTA / ABERTO`)
- **Regra inegociável:** clique direito simples em terreno vazio (`PickResult.Kind.GROUND`) **deve continuar disparando `MoveOrder`**.
- Opções limpas para o jogador soltar carga no chão em revisão:
  - **Opção UX-1 (Recomendada na T2):** botão contextual no HUD de seleção (**"Soltar carga"** — visível apenas quando ao menos uma unidade selecionada tem `carga > 0%`), que coloca o cursor em modo temporário de alvo no chão (`click direito/esquerdo` confirma posição; `Esc` cancela) + atalho opcional `Alt + Clique Direito` no chão. (Preserva `Shift` livre para futura fila de ordens do GDD.)
  - **Opção UX-2:** apenas modificador (`Alt + Clique Direito` no chão). Mais rápido para veteranos, porém menos descobrível sem botão no HUD.

### 5.3 Criação, agrupamento (`Merge`) e representação visual variável
- Ao depositar `amount` de `resource_id` na posição `pos`:
  1. `GroundPileManager` busca se já existe uma `GroundResourcePile` do **mesmo `resource_id`** dentro de `merge_radius` navegável (e na mesma `CampStorageZone` se aplicável).
  2. Se existir (e respeitando um eventual teto configurável caso venha a ser definido no futuro — por padrão **sem limite fixo arbitrário**; "24 unidades" é apenas exemplo visual), soma `amount` na pilha existente (`merge`), atualiza a malha placeholder para refletir a faixa de volume (ex.: pequeno / médio / grande) e aplica a política configurada de exposição.
  3. Se existir apenas pilha de categoria incompatível exatamente no ponto, aplica pequeno offset seguro em anel válido no NavMesh antes de instanciar nova pilha.
- **Placeholders visuais T2 (substituíveis sem tocar em lógica):**
  - Madeira: agrupamento simples de cilindros/toras em camadas conforme quantidade.
  - Pedra: agrupamento baixo de prismas/rochas acinzentadas escalonadas conforme faixa.
  - Alimentos: cestos/fardos simples agrupados com cor de identificação discreta.

### 5.4 Recolhimento (`Pick Up`) e transporte de pilhas externas para o acampamento
- **Clique direito sobre `GroundResourcePile` (`PickResult.Kind.PILE`):**
  - **Caso padrão (unidade tem espaço livre `>= 1` unidade do material da pilha):** gera `CollectFromPileOrder(pile_ref, auto_deliver_after = true/config)`. A unidade caminha até `pile_ref`, transfere `min(pile.amount, max_fit_units)` para `UnitCarryLoad` — garantindo nunca passar de `100%` — e decrementa a pilha (ou a remove com `queue_free()` ao zerar).
  - **Se `auto_deliver` estiver ativo (ou se pilha for externa ao acampamento):** ao atingir `100%` (ou ao não caber mais 1 unidade, ou ao esgotar a pilha externa caso configurado para entrega imediata), a unidade prossegue automaticamente para descarregar na `CampStorageZone` / `StoragePoint` compatível mais próxima (`DeliverLoadOrder`).
  - **Caso unidade carregue a mesma categoria e clique especificamente em pilha compatível já dentro do acampamento (ou esteja cheia `>= 1` unidade com intenção de descarregar):** se `pile` pertence à `CampStorageZone` e a unidade já carrega aquele recurso sem espaço para coletar, clique direito na pilha da zona prioriza **descarregar/agrupar** nela; fora da zona, unidade cheia recebe feedback claro ou prioriza entrega no acampamento (detalhes finais de prioridade ficam parametrizados e claros para teste na `T2.3`).
- **Carga parcial ao esgotar fonte:** se uma árvore/arbusto/rocha zera antes da unidade atingir `100%`, a unidade não trava: dependendo da regra de retorno configurável (`return_on_source_deplete = true` por padrão após tentar próxima fonte ou finalizar tarefa), leva sua carga parcial para descarregar normalmente.

### 5.5 Conservação matemática e trilha anti-duplicação
- Toda transferência passa por métodos transacionais únicos (`TransferService` / métodos coordenados entre fonte, unidade, pilha e estoque).
- Não existe criação ou destruição silenciosa de material. Inclusive a **perda intencional por deterioração** é contabilizada em contador auditável próprio (`total_decayed_by_resource`), mantendo a invariante matemática exata em testes unitários e de regressão:

$$\Delta \text{Fontes} + \Delta \text{CargasEmUnidades} + \Delta \text{PilhasExternas} + \Delta \text{EstoqueUtilizavel} + \Delta \text{PerdaIntencionalPorDeterioracao} = 0$$

---

## 6. Arquitetura de deterioração por exposição e desempenho (UHD 620)

### 6.1 Orçamento de CPU e GPU na Intel UHD 620
- **Zero `_process` / `_physics_process` por pilha:** pilhas não executam scripts frame a frame.
- **Varredura centralizada em baixa frequência:** apenas `GroundPileManager` possui um acumulador ou `Timer` de intervalo largo (ex.: `1,0 s` de tempo simulado, ou passo discreto configurável). Com 50 ou 100 pilhas no mapa, o custo médio por frame em `1920×1080` tende a ser irrelevante em relação ao limite de `16,7 ms`.
- **Sombras e draw calls:** meshes placeholder simples reutilizando materiais por categoria (`StandardMaterial3D` compartilhado), sem luzes extras por pilha e seguindo o orçamento de sombras direcionais validado na T1.10 (pilhas pequenas no chão podem desabilitar `cast_shadow` ou usar sombra leve apenas se couber na folga de `0,114 ms`, a ser medido no benchmark da `T2.6`).

### 6.2 Modelo de tempo preparado para a T4 (`WorldTimeProvider`)
- O gerente de deterioração consome delta de tempo simulado via interface mínima `WorldTimeProvider` (que na T2 usa delta de simulação pausável padrão e, na T4, recebe o relógio/calendário e escalas `1x / 2x / 4x` sem refatorar pilhas).

### 6.3 Regras configuráveis de exposição e proteção (`DecayProfile`)
- Cada material possui um `DecayProfile` em dados:
  - `can_decay: bool` e `base_exposure_duration_sec: float` (ou taxa de perda gradual por unidade/lote — **valores exatos mantidos em ABERTO**).
  - `decay_mode`: suporte previsto para (a) **desaparecimento ao expirar exposição** ou (b) **perda gradual por unidades/ciclo**, ambos parametrizáveis para calibração após decisão do proprietário.
  - `location_decay_multiplier`: `1.0` no chão descoberto (`GroundResourcePile` comum ou `CampStorageZone` a céu aberto), reduzido em coberturas intermediárias futuras e **`0.0` dentro de armazéns protegidos construídos na `T3+`**.
- **Retirada parcial e reagrupamento (`merge`) em pilhas em decomposição:**
  - Quando uma unidade recolhe parte da pilha, a fração restante mantém seu progresso de exposição (ou contador proporcional) sem reset gratuito infinito;
  - Ao mesclar carga recém-colhida em pilha parcialmente exposta, o contrato suporta regra explícita configurável (`WEIGHTED_AVERAGE`, `KEEP_WORST` ou `RESET_PROPORTIONAL`), evitando exploração mecânica e aguardando definição de gameplay (`ABERTO`).

---

## 7. Caminho de evolução do armazenamento (`T2 → T3+`)

| Etapa | Estrutura presente no mapa | Onde os itens ficam | Contabiliza em `SettlementInventory`? | Deteriora por exposição? |
|---|---|---|---|---|
| **Início T2 (Nível 1, sem construções)** | Zero edifícios humanos; apenas terreno, fontes naturais e área lógica `CampStorageZone` (PROPOSTA) | Pilhas físicas no chão (`GroundResourcePile`), fora ou dentro da zona do acampamento | **Não** fora da zona; **Sim** (PROPOSTA) quando dentro da `CampStorageZone` compatível | **Sim** (exposto ao tempo, tanto fora quanto no chão do acampamento) |
| **T3 — Primeiros depósitos construíveis** | Estruturas rústicas posicionadas e construídas pelo jogador (`StoragePoint` com cobertura) | Dentro do depósito construído (com visualização externa de estoque/pilha) | **Sim** | **Reduzida ou zero** (`decay_multiplier` baixo / `0.0`) |
| **T3+/T4+ — Armazéns especializados e melhorias** | Armazéns maiores por categoria (celeiro de alimentos, telheiro de madeira, pátio de pedra) | Estoque estruturado protegido com maior organização | **Sim** | **Zero** (`protection_factor = 1.0`) enquanto mantidos íntegros |

Essa progressão dá sentido mecânico real à construção de armazéns na T3+: no começo o casal sobrevive empilhando recursos no chão, mas paga o preço da exposição e dispersão até erguer estruturas de proteção.

---

## 8. Riscos arquiteturais identificados

1. **Margem estreita de `0,114 ms` no `p95` da UHD 620 (`1920×1080`):** dezenas de pilhas com colisor pesado ou sombras dinâmicas podem estourar `16,7 ms`. Mitigação: `Area3D` só na máscara de picking, `cast_shadow` avaliado em benchmark e zero `_process` por pilha.
2. **Ambiguidade de clique direito em pilha (`recolher` vs `entregar`):** sem regra clara quando a unidade já tem carga, o jogador pode enviar para buscar quando queria empilhar junto. Mitigação: separar comportamento determinístico por contexto (`pilha externa` vs `pilha em CampStorageZone`) + ação explícita de soltar carga.
3. **Congestionamento de múltiplos trabalhadores na mesma pilha ou zona:** vários agentes RVO convergindo para exatamente o mesmo ponto podem oscilar. Mitigação: pontos de aproximação distribuídos em anel dentro do raio de interação e preservação de `Idle` com prioridade `1.0`.
4. **Reserva futura na T3 vs deterioração na zona T2:** se um item dentro da `CampStorageZone` deteriorar antes do início de uma obra, o inventário precisa descontar imediatamente antes da dedução de construção. Mitigação: fonte única de verdade transacional entre `GroundPileManager` e `SettlementInventory`.

---

## 9. Decisões em `ABERTO` para validação antes de implementar código

Solicita-se definição ou autorização provisória parametrizável do proprietário antes da `T2.1`/`T2.2` para os pontos abaixo:

1. **Entrada no estoque utilizável na T2 (`PROPOSTA` vs alternativa):** confirmar se na T2 pilhas compatíveis deixadas dentro de uma `CampStorageZone` lógica do acampamento contam como `SettlementInventory` (ainda sofrendo deterioração) ou se o acampamento terá demarcação configurável pelo jogador desde o início.
2. **UX para soltar carga no chão:** preferência entre botão contextual **"Soltar carga"** no HUD, modificador `Alt + Clique Direito`, ou ambos.
3. **Política inicial de deterioração (placeholders T2):** se expor no chão reduz unidades gradualmente até sumir ou faz a pilha expirar integralmente após um prazo, além da ordem de grandeza desejada em minutos de jogo e política de `merge` (média ponderada vs reset parcial).
4. **Pesos, capacidade inicial e teto de pilha:** valores numéricos provisórios parametrizáveis para madeira, pedra e alimentos, capacidade do casal protagonista e se haverá algum limite visual/numérico por pilha única.
5. **Comportamento ao recolher pilha externa ou esgotar fonte:** retorno automático imediato ao acampamento ao recolher pilha externa parcial vs aguardar atingir `100%` buscando outra pilha/fonte próxima.
