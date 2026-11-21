# RUX-0 — Reformulação do Trabalho Comunitário, Construção Simplificada e Casa Fundadora

**PROPOSTA DE REFORMULAÇÃO — PENDENTE DE REVISÃO DO PROPRIETÁRIO**

- **Base auditada:** branch `feat/ux-1-contextual-tree`, commit `0e78f9ab282f635cfb772b2d1c5c2b256e57f3ab` (worktree `C:\Projetos\Dawn_of_Kin_wt_t3_4_5`).
- **Engine / alvo técnico:** Godot `4.7.2.stable`, GDScript tipado estrito, `gl_compatibility`, `Jolt Physics`, Intel UHD Graphics 620 (`1920×1080`, meta $p95 \le 16,7\text{ ms}$ em tomada CA).
- **Escopo desta entrega:** exclusivamente documental e arquitetural. Nenhuma alteração de código, cena, teste, `AGENTS.md` ou GDD normativo foi executada.
- **Pendências preservadas:** a candidata **UX-1** permanece **não homologada visualmente** (3 ensaios manuais pendentes em [UX_1_contextual_tree_candidate_report.md](../testing/UX_1_contextual_tree_candidate_report.md)); a candidata **T3.6.4-R1** permanece com **D3-04 e D3-07 pendentes de reteste manual** ([T3_6_4_R1_candidate_report.md](../testing/T3_6_4_R1_candidate_report.md)).

---

## 1. Motivação e Direção Estratégica

Após a avaliação conceitual de [UX-0](UX_0_contextual_work_PROPOSAL.md), do protótipo [UX-1](../testing/UX_1_contextual_tree_candidate_report.md) e do planejamento da UX-2, identificou-se que exigir escolha manual de trabalhadores para quase toda tarefa impõe microgestão desnecessária ao ritmo contemplativo e comunitário de *Dawn of Kin*.

A reformulação **RUX-0** propõe um **modelo híbrido em dois níveis**:
1. **Condução comunitária por objetivos:** o jogador marca fontes de recursos ou posiciona construções; um distribuidor comunitário seleciona automaticamente habitantes livres e aptos e os despacha respeitando regras físicas, vagas, idade e navegação.
2. **Controle pessoal permanente da Casa Fundadora:** os dois protagonistas originais e **todos os descendentes de sua linhagem** mantêm controle individual permanente em qualquer fase selecionável, com prioridade absoluta sobre o trabalho comunitário automático.
3. **Construção simplificada com débito imediato:** ao confirmar a colocação de uma obra, os materiais são debitados atomicamente do estoque coletivo e os construtores caminham diretamente ao canteiro para montar a estrutura, eliminando a etapa intermediária de transporte de pilhas até a obra (`D2`), sem abrir mão da economia física na coleta, armazenamento, deterioração e conservação contábil.

---

## 2. Matriz de Divergências: GDD Atual (`v1.2`) × Arquitetura T3/UX-0 × Proposta RUX-0

Referências confrontadas: [Dawn_of_Kin_GDD.md](../Dawn_of_Kin_GDD.md), [T3_architecture_PROPOSAL.md](T3_architecture_PROPOSAL.md), [UX_0_contextual_work_PROPOSAL.md](UX_0_contextual_work_PROPOSAL.md), [T3_closeout_contextual_plan.md](T3_closeout_contextual_plan.md) e código-fonte real no commit `0e78f9a`.

| Tema / Regra | Estado atual (GDD v1.2 / T3 / UX-0 / Código) | Proposta RUX-0 | Status da regra |
|---|---|---|---|
| **Entrada de coleta** | GDD §9.1: clique direito em fonte (`IMPLEMENTADO`). UX-0/UX-1: menu contextual exigindo escolha manual de equipe (`PROPOSTA` / protótipo). | Selecionar uma ou mais fontes cria uma tarefa comunitária limitada àquelas fontes; trabalhadores livres/aptos são enviados automaticamente, sem menu obrigatório de equipe. | **SUBSTITUI UX-0/UX-1 e altera §9.1** *(pendente de aprovação)* |
| **Transporte físico na coleta** | GDD §4.1: `UnitCarryLoad`, peso (`wood=2`, `stone=3`, `food=1`), redução de velocidade e descarga física em armazenamento válido (`IMPLEMENTADO`). | **Integralmente mantido.** Toda coleta continua passando por `GatherResourceOrder`, mochila física e entrega real na `CampStorageZone` (ou futuro depósito T3.7). | **MANTIDA** |
| **Alcance finito das tarefas de coleta** | UX-0 §2 e `DEC-08`: tarefa manual não invade fontes não selecionadas; busca autônoma pertence ao futuro `JobSystem`. | **Mantido.** Selecionar 5 árvores limita a tarefa estritamente às 5 árvores (6ª preservada). | **MANTIDA** |
| **Suprimento de construção (`D2`)** | `T3_architecture_PROPOSAL` §3 e `ConstructOrder`: reserva nas pilhas + transporte físico até buffer do canteiro (`IMPLEMENTADO` T3.3–T3.6). | Na confirmação, valida terreno/estoque e **debita atomicamente** do estoque coletivo; trabalhadores vão direto montar o canteiro sem buscar materiais nas pilhas. | **SUBSTITUÍDA** *(pendente de aprovação)* |
| **Papéis de obra (`D9` / `DEC-18`)** | `ConstructionSite`: `SOLO_SUPPLIER`, `TRANSPORTER` e `BUILDER` (1–3 trab., máx. 2 construtores, 4º recusado). | Simplificado para papel único **`BUILDER`** até o teto de construtores da obra (provisório `2`, sujeito a `D4`). | **SUBSTITUÍDA** *(pendente de aprovação)* |
| **Complementação de reserva deteriorada (`DEC-11B`)** | GDD §4.2 e `BuildingInspectorPanel`: autorização manual para repor reserva perdida por decaimento na pilha. | **Obsoleta no fluxo de débito imediato**, pois a obra não mantém reservas expostas nas pilhas. Infraestrutura preservada até o corte formal (ver §8.3). | **OBSOLETA NO NOVO FLUXO** *(aguarda decisão de descontinuação)* |
| **Cancelamento e reembolso (`D3`)** | GDD §4.3 / T3.6: liberação de reserva + devolução física de trânsito/buffer + $\lfloor Q_{\text{inc}}(1-p)\cdot 0,5\rfloor$ com recuperação física no mapa. | Sem transporte de obra nem reserva em pilha, a política exata de reembolso sob débito imediato precisa ser escolhida (ver §9). | **PENDENTE DE DECISÃO** |
| **Deterioração por categoria (`DEC-11A`) e Depósito (`D5`)** | Madeira/alimento deterioram expostos; pedra bruta não deteriora (`can_decay = false`); Depósito Rústico protege 50/50/30 com decaimento `0,0`. | **Integralmente mantidas.** Pilhas expostas continuam sofrendo `step_decay()`; T3.7 continua protegendo estoques. | **MANTIDA** |
| **Validação espacial sem grid e `CampStorageZone` (`D6`, `DEC-19`)** | `PlacementValidator`, `PlacementController`, exclusão da `CampStorageZone`, malha candidata assíncrona e rebake após conclusão. | **Integralmente mantidas.** | **MANTIDA** |
| **Catálogo Construir (`D7`)** | `ConstructionHud` (botão inferior direito + catálogo + prévia verde/vermelha). | **Mantido**, com checagem de saldo integral informando déficit exato na confirmação e despacho automático da obra. | **MANTIDA (adaptada)** |
| **Controle pessoal e Casa Fundadora** | GDD §1.2: ordem RTS soberana para todos selecionáveis; não diferenciava linhagem fundadora de moradores comuns. | Protagonistas e **todos os descendentes** têm controle pessoal permanente (mesmo adultos e casados), convivendo com participação automática quando livres. Demais moradores atuam pelo sistema comunitário. | **NOVA REGRA** *(pendente de aprovação)* |
| **Cônjuges externos na Casa Fundadora** | Não especificado no GDD v1.2. | Extensão ou não do controle pessoal a cônjuges que entram na Casa Fundadora por casamento sem serem descendentes. | **ABERTO / PENDENTE DE DECISÃO** |
| **Imortalidade / Proteção de derrota (`DEC-07`)** | Exclusiva dos 2 protagonistas originais; filhos e moradores comuns podem morrer. | **Integralmente mantida.** Descendentes têm controle pessoal permanente, mas **continuam mortais**. | **MANTIDA** |
| **Residência de casais (GDD §3.4)** | GDD §3.4: "Cada casal casado exige residência própria." | **Reconciliada:** descendentes da Casa Fundadora residem na **Casa Principal** (sem interiores, núcleos registrados em dados) mesmo após casar; famílias comuns seguem usando Casas Familiares próprias (ver §7). | **RECONCILIADA / ALTERADA** *(pendente de aprovação)* |
| **Idades, genealogia, casamento `18+` e consanguinidade (`DEC-02`, `DEC-03`, `DEC-04`)** | 4 fases (`Bebê`, `Criança`, `Jovem`, `Adulto`), restrições por idade, proibição até primos de 1º grau, vínculo conjugal persistente, identidade imutável. | **Integralmente mantidas.** | **MANTIDA** |
| **Profissões e `JobSystem` (`DEC-08`)** | GDD §5.1: profissões despertam gradualmente e executam rotinas autônomas quando `IDLE`. | **Separado em 2 camadas:** (1) Distribuidor comunitário básico no Cap. 1 (sem exigir profissão); (2) `JobSystem` futuro (profissões permanentes ampliam eficiência/autonomia sem reintroduzir microgestão). | **MANTIDA (estruturada em 2 camadas)** |
| **Persistência em disco (`D1`, `DEC-17`)** | `T3.8`: snapshot versionado `schema_version = 1`, escrita `.tmp → .bak → rename`, conservação pré-carga. | **Mantida e simplificada para obras**, acrescentando serialização das tarefas comunitárias pendentes e do estado de controle pessoal (ver §10). | **MANTIDA (esquema ajustado)** |

### 2.1 Resumo de Governança: Mantidas × Substituídas × Pendentes

- **Regras preservadas sem conflito:** transporte físico na coleta (`UnitCarryLoad` + `GatherResourceOrder` + `DeliverToCampOrder`), `SettlementInventory` como autoridade única, `DEC-11A`, `D4` (parâmetros provisórios sujeitos a balanceamento), `D5`, `D6`, `D7`, `D8`, `DEC-01`–`DEC-07`, `DEC-09`, `DEC-10`, `DEC-12`–`DEC-17`, `DEC-19` e meta de desempenho na Intel UHD 620.
- **Regras propostas para substituição:** `D2` (transporte obrigatório até canteiros), `D9`/`DEC-18` (papéis de suprimento de obra), `DEC-11B` (complementação de reserva deteriorada na obra), obrigatoriedade do menu manual de equipe da `UX-0`/`UX-1` e exigência de casa separada para descendentes casados da Casa Fundadora (§3.4).
- **Decisões pendentes que exigem deliberação explícita do proprietário antes de implementar os módulos afetados:**
  1. **P-RUX-1 (Reembolso de cancelamento de obra — §9):** escolher entre R1, R2, R3 ou R4.
  2. **P-RUX-2 (Retorno pós-ordem pessoal — §5.2):** definir se após concluir um `MoveOrder` pessoal o membro da Casa Fundadora aguarda comando/botão "Voltar ao trabalho" ou retorna automaticamente após concluir (ou após um atraso/regra por tipo de ordem).
  3. **P-RUX-3 (Cônjuges externos na Casa Fundadora — §6.2):** cônjuges não descendentes que casam com descendentes passam a ter controle pessoal ou permanecem comunitários?
  4. **P-RUX-4 (Política de débito entre pilhas expostas e depósitos protegidos — §8.2):** ao debitar obra na T3.7+, consumir pilhas expostas mais antigas primeiro (recomendado) ou depósitos primeiro?
  5. **P-RUX-5 (Escopo do protótipo RUX-1 vs UX-1):** confirmar criação da cena isolada `rux_1_auto_gather.tscn` preservando `ux_1_tree.tscn` e clique direito durante a transição.
  6. **P-RUX-6 (Gesto de cancelamento de tarefa de coleta — §4.1):** confirmar se o cancelamento ocorre por clique na fonte já marcada (cartão leve com botão "Cancelar tarefa") e/ou atalho contextual.

---

## 3. Diagnóstico dos Sistemas Existentes (Reutilização vs Adaptação)

A inspeção direta do código em `0e78f9a` mostra que a maior parte da fundação técnica construída em T1–T3.6 permanece altamente reutilizável:

| Módulo / Arquivo real | Papel atual | Destino na RUX-0 |
|---|---|---|
| [world_picker.gd](../../src/rts/world_picker.gd), [pick_result.gd](../../src/rts/pick_result.gd) | Picking 3D com oclusão sólida para `UNIT`, `RESOURCE_SOURCE`, `CONSTRUCTION_SITE`, `GROUND`, `OBSTACLE`. | **Reutilizado integralmente.** (Futuramente incluir `BUILDING` para inspecionar Casa Principal / Depósito.) |
| [selection_box_math.gd](../../src/rts/selection_box_math.gd), [selection_box_overlay.gd](../../src/ui/selection_box_overlay.gd) | Caixa de seleção em espaço de tela $O(N)$ sem raycasts por pixel. | **Reutilizado e estendido** com helper puro para projetar `ResourceSource` em caixa iniciada sobre fonte. |
| [selection_manager.gd](../../src/rts/selection_manager.gd) | Seleção tipada de `Array[Unit]`. | **Reutilizado integralmente** para controle pessoal de habitantes (sem misturar fontes nele). |
| [rts_input_controller.gd](../../src/rts/rts_input_controller.gd) | Entrada RTS, hover, arraste, prioridade de `PlacementController`. | **Reutilizado** como base; extensão limpa para distinguir clique/arraste em fonte vs terreno livre. |
| [command_controller.gd](../../src/rts/command_controller.gd) | Despacho de `MoveOrder`, `GatherResourceOrder`, `ConstructOrder`, validação regional e de proveniência (`_admit_economic_command`). | **Reutilizado e ampliado** com entradas explícitas por unidade (`command_units_to_gather`, `command_units_to_build`, `command_unit_to_deliver_free_cargo`) sem depender de alterar `SelectionManager`. |
| [gather_resource_order.gd](../../src/units/orders/gather_resource_order.gd), [deliver_to_camp_order.gd](../../src/units/orders/deliver_to_camp_order.gd), [gather_slot_planner.gd](../../src/units/orders/gather_slot_planner.gd) | Ciclo físico completo de coleta, peso, queda de árvore, descarga seletiva e espera de rebake. | **Reutilizados integralmente** pelo distribuidor comunitário e por ordens pessoais. |
| [resource_source.gd](../../src/economy/resource_source.gd) | Estoque finito, vagas (`max_simultaneous_workers`), sinais `amount_changed` / `depleted`, visuais de árvore/rocha/arbusto. | **Reutilizado integralmente.** |
| [unit.gd](../../src/units/unit.gd), [unit_movement.gd](../../src/units/unit_movement.gd), [unit_carry_load.gd](../../src/economy/unit_carry_load.gd), [carry_provenance_ledger.gd](../../src/economy/carry_provenance_ledger.gd) | Corpo, movimento, mochila com peso/desaceleração, proveniência de lotes, `order_finished` e `_order_revision`. | **Reutilizados integralmente.** `_order_revision` é a peça-chave para detectar substituição por ordem pessoal sem corrida. |
| [settlement_inventory.gd](../../src/economy/settlement_inventory.gd), [ground_pile_manager.gd](../../src/economy/ground_pile_manager.gd), [economy_clock_controller.gd](../../src/economy/economy_clock_controller.gd) | Autoridade econômica única, pilhas físicas, `withdraw_batch`, `deposit_batch`, `step_decay()` (`DEC-11A`). | **Reutilizados integralmente.** `withdraw_batch` atômico já existe e suporta débito imediato de obra (com extensão de checkpoint/rollback transacional sob guarda regional). |
| [placement_validator.gd](../../src/buildings/placement_validator.gd), [placement_controller.gd](../../src/buildings/placement_controller.gd), [world_navigation.gd](../../src/navigation/world_navigation.gd), [building_instance.gd](../../src/buildings/building_instance.gd) | Validação sem grid (`D6`), malha candidata assíncrona, transmutação em edifício sólido e rebake (`DEC-19`). | **Reutilizados integralmente.** |
| [construction_manager.gd](../../src/buildings/construction_manager.gd), [construction_site.gd](../../src/buildings/construction_site.gd), [construct_order.gd](../../src/units/orders/construct_order.gd) | Hoje acoplados a reservas (`reserve_batch`), transporte D2 e papéis D9 (`1.479` linhas em `ConstructOrder`, `2.906` em `ConstructionSite`). | **Adaptados de forma isolada na RUX-4** (modo/caminho de obra com débito imediato e papel único `BUILDER`), preservando os testes antigos intactos até decisão formal de corte. |
| [construction_hud.gd](../../src/ui/construction_hud.gd), [building_inspector_panel.gd](../../src/ui/building_inspector_panel.gd) | Catálogo Construir e inspetor de obra (hoje expõe `DEC-11B` e `D3`/Recuperações). | **Reutilizados e simplificados na RUX-4/RUX-5** após aprovação da política de reembolso. |
| [tree_work_input.gd](../../src/rts/tree_work_input.gd), [tree_work_menu.gd](../../src/ui/tree_work_menu.gd), [ux_1_tree.tscn](../../tests/visual/ux_1_tree.tscn) | Protótipo UX-1 isolado de árvore única. | **Preservados intactos** durante a migração para revisão posterior do proprietário. |

### 3.1 Por que a infraestrutura econômica existente continua indispensável
Mesmo eliminando o transporte físico até canteiros (`D2`), **não** se pode descartar a camada econômica:
- **Estoque físico e conservação:** `SettlementInventory` + `GroundPileManager` continuam sendo a autoridade única das pilhas na `CampStorageZone` (e futuros depósitos `CompositeStorageSource` na T3.7).
- **Coleta física e mochila:** `UnitCarryLoad` e `CarryProvenanceLedger` garantem peso real, redução de velocidade, entrega física no acampamento e ausência de duplicação quando um trabalhador carregado recebe uma ordem pessoal ou a partida é salva/carregada.
- **Deterioração (`DEC-11A`):** `EconomyClockController` + `DecayProfile` continuam regendo desgaste de alimentos/madeira expostos vs imunidade da pedra bruta e proteção do Depósito Rústico (T3.7).
- **Atomicidade e guarda regional:** `ReservedWithdrawalCoordinator` (ou sua guarda de escopo regional) evita corridas entre criação de obra, entrega de coleta, conclusão com rebake e cancelamento.

---

## 4. Contrato de Coleta Automática e Projeto do Distribuidor Comunitário

### 4.1 Controles e interação no mapa (coerentes com RTS existente)
- **Clique esquerdo em fonte disponível (árvore, rocha, arbusto):**
  - Se a fonte **não** pertence a uma tarefa ativa: cria uma `WorkTask` comunitária de coleta para aquela fonte (com destaque visual discreto de tarefa ativa) e aciona o distribuidor.
  - Se a fonte **já** pertence a uma tarefa ativa: **idempotente** — não cria tarefa duplicada nem gera recursos adicionais; abre um cartão leve de inspeção da tarefa (alvo/restante, trabalhadores alocados ou `"Aguardando trabalhador"`, botão `Cancelar tarefa`).
- **`Shift` + clique esquerdo em fonte:**
  - Com uma seleção/tarefa de fontes em edição ou ativa do **mesmo tipo** (`resource_id`): alterna (adiciona/remove) a fonte do conjunto finito. Se de tipo diferente, informa claramente que tipos distintos não se misturam na mesma tarefa (ou cria tarefa independente apenas se o jogador clicar sem `Shift`).
- **Arraste (caixa de seleção) discriminado pela origem (`mouse_down`):**
  - **Iniciado sobre uma `ResourceSource`:** acima do limiar de arraste (`get_drag_threshold_px()`), projeta fontes visíveis e disponíveis do **mesmo `resource_id`** dentro do retângulo via `SelectionBoxMath` e cria uma única `WorkTask` finita abrangendo exatamente aquele conjunto. Fontes fora da caixa (ex.: 6ª árvore) permanecem intocadas.
  - **Iniciado em terreno livre / fora de fonte:** preserva integralmente a seleção RTS por caixa de habitantes (`SelectionManager`).
- **Clique direito em terreno livre / alvo (para membros controláveis da Casa Fundadora):**
  - Emite ordem pessoal (`MoveOrder`, ou ordem direta de trabalho/interação quando aplicável), sempre soberana sobre o distribuidor.
- **`Esc`:**
  - Cancela prévia de construção ativa, fecha cartão de inspeção ou limpa seleção RTS de habitantes — **nunca** cancela silenciosamente tarefas comunitárias já registradas no quadro.
- **Cancelamento de tarefa de coleta:**
  - Feito explicitamente pelo botão `Cancelar tarefa` no cartão leve de inspeção da fonte marcada (ou ação equivalente definida em **P-RUX-6**). Ao cancelar: remove a tarefa do quadro e desmarca o destaque das fontes; quem estava apenas caminhando vazio para a fonte para e fica livre; quem já extraiu carga física `FREE_GATHERED` descarrega normalmente no acampamento (ou mantém a carga íntegra na mochila se receber ordem pessoal).

### 4.2 Arquitetura do Distribuidor Comunitário (`CommunityWorkBoard` + `CommunityTaskDispatcher`)

Para evitar god-scripts e manter **custo zero por frame na Intel UHD 620** (`set_process(false)`, `set_physics_process(false)`), a distribuição comunitária separa **dados de tarefa** de **alocação reativa**:

1. **`WorkTask` (`RefCounted`):**
   - `task_id: int`, `kind: Kind` (`GATHER_SOURCES`, `BUILD_SITE`), `region_id: StringName`, `created_seq: int`.
   - `state: State` (`PENDING_WORKERS`, `IN_PROGRESS`, `COMPLETED`, `CANCELLED`).
   - Para `GATHER_SOURCES`: `resource_id: StringName`, `targets: Array[ResourceSource]` (lista finita fechada), `target_issues: Dictionary` (`source_id -> "depleted" | "removed" | "unreachable"`).
   - Para `BUILD_SITE`: `site: ConstructionSite`.
   - `assigned_members: Dictionary` (`unit_instance_id -> {unit_ref, order_ref, order_revision, target_source_ref}`).
   - **Sem contabilidade econômica própria:** não altera saldos, mochilas nem reservas.

2. **`CommunityWorkBoard` (`Node` por região):**
   - Mantém a lista ordenada de `WorkTask` ativas da região e índice rápido `source_instance_id -> task_id` / `site_id -> task_id` garantindo **idempotência** (cliques repetidos na mesma fonte ou obra nunca duplicam tarefas).
   - Emite sinais `task_added`, `task_updated`, `task_removed`.

3. **`CommunityTaskDispatcher` (`Node` por região, 100% orientado a eventos):**
   - **Gatilhos reativos (zero polling por frame):**
     - `board.task_added` / `task_updated`
     - `unit.order_finished` (quando um trabalhador termina coleta, construção ou fica disponível após ordem pessoal)
     - `source.depleted` / `source.tree_exited`
     - `site.state_changed` / `site.workers_changed`
     - `world_navigation.navigation_ready`
     - Registro de novo habitante apto ou saída de residência (`unit_became_available`).
   - **Coalescência por frame (`call_deferred("_flush_dispatch")`):** múltiplos eventos no mesmo frame de física resultam em **uma única passada determinística** de alocação, evitando reentrância e spikes de CPU.
   - **Critérios de elegibilidade (`CommunityEligibilityEvaluator`):**
     1. Domínio regional (`region_id`, `World3D`), identidade válida e ausência de lock transacional (`_is_reserved_withdrawal_locked()`, `carry_load.is_transaction_busy()`).
     2. Não estar em residência (`not sheltered`) e não possuir ordem pessoal ativa ou bloqueio de controle pessoal.
     3. Não possuir ordem comunitária ativa (trabalhador já alocado não é arrancado silenciosamente de sua tarefa atual).
     4. Faixa etária compatível (`DEC-04` hook: hoje todos são adultos; na T5, `BABY` bloqueado, `CHILD` apenas tarefas leves como `food`, `YOUTH`/`ADULT` aptos a madeira/pedra/obra).
     5. Mochila compatível: sem lotes de custódia/obra bloqueantes; capacidade efetiva $\ge$ peso unitário do recurso alvo. (Trabalhador livre portando sobra `FREE_GATHERED` pode ser admitido se `GatherResourceOrder` puder entregar primeiro ou complementar, conforme política consistente de proveniência.)
     6. Vaga disponível (`source.has_worker_slot(unit)` ou `site.has_builder_slot()`) e acesso navegável (checagem **preguiçosa**: ordena fontes da tarefa por distância euclidiana ao trabalhador e para no **primeiro** alvo alcançável).
   - **Regra determinística de prioridade entre tarefas pendentes (PROPOSTA inicial para Cap. 1):**
     1. Primeiro, garantir ao menos 1 trabalhador em cada tarefa com vaga livre por ordem de criação (`FIFO` por `created_seq`) para que nenhuma tarefa fique parada enquanto outra absorve toda a comunidade — ou prioridade configurável `BUILD_SITE` vs `GATHER_SOURCES` (documentada como parâmetro simples e transparente, sem heurísticas ocultas).
     2. Segundo, preencher vagas adicionais das tarefas ainda incompletas priorizando menor distância entre o trabalhador livre e o alvo.
     3. Se nenhum trabalhador estiver elegível no momento, a tarefa permanece em `PENDING_WORKERS` sem erro, sendo assumida automaticamente no primeiro evento de liberação.
   - **Ciclo de execução:**
     - Despacha exclusivamente via `CommandController.command_units_to_gather(source, [unit])` (ou `command_units_to_build(site, [unit])`).
     - Quando uma fonte da tarefa esgota ou é removida, o trabalhador conclui a descarga física de eventual carga (`GatherResourceOrder` → `SUCCEEDED`) e, no `order_finished`, o distribuidor o envia à próxima fonte válida da **mesma tarefa** (jamais fora da lista).
     - Se uma fonte ficar inacessível (`REASON_SOURCE_UNREACHABLE` / `REASON_STUCK`), marca-a em `target_issues` e direciona o trabalhador para outro alvo válido da tarefa.
     - A tarefa conclui (`COMPLETED`) somente quando todos os alvos estiverem esgotados/removidos/inacessíveis (ou obra concluída) **e** todas as descargas físicas pendentes dos seus membros tiverem terminado.

### 4.3 Separação clara frente ao futuro `JobSystem` de Profissões (Cap. 2+)
- **Camada 1 — Distribuidor Comunitário (RUX / Cap. 1):** atende tarefas criadas pelo jogador (`CommunityWorkBoard`) usando qualquer habitante livre e apto, sem exigir profissão.
- **Camada 2 — `JobSystem` de Profissões Permanentes (T5+ / Cap. 2+):**
  - Lenhadores, mineradores, construtores, agricultores etc. passam a atuar como **modificadores de afinidade/prioridade e autonomia contínua** sobre o mesmo ecossistema:
    1. Ao pontuar candidatos para uma tarefa do `CommunityWorkBoard`, especialistas naquela atividade recebem prioridade e bônus de eficiência definidos no balanceamento futuro.
    2. Quando o `CommunityWorkBoard` não tiver tarefas diretas pendentes, moradores com profissão permanente podem gerar/assumir suas rotinas autônomas (ex.: buscar próxima fonte adjacente conforme `DEC-08` ou cuidar da Roça), mantendo sempre prioridade menor que ordens pessoais da Casa Fundadora e tarefas explícitas do jogador.

---

## 5. Contrato de Prioridade: Ordens Pessoais × Trabalho Automático

### 5.1 Estados de controle da unidade
Cada `Unit` mantém um modo explícito de controle (`ControlMode`, ou componente leve `UnitControlState`):
- `COMMUNITY_FREE`: disponível para o `CommunityTaskDispatcher`.
- `COMMUNITY_WORKING`: executando uma ordem emitida pelo `CommunityTaskDispatcher` (vinculada a `(task_id, order_ref, order_revision)`).
- `PERSONAL_ACTIVE`: executando uma ordem pessoal explícita do jogador (permitida a membros da Casa Fundadora).
- `PERSONAL_HOLD` *(opcional, sujeito à decisão **P-RUX-2**)*: aguardando após ordem pessoal de posicionamento até novo comando ou liberação explícita.

### 5.2 Regras invioláveis de prioridade
1. **Soberania da ordem pessoal:** qualquer ordem pessoal emitida pelo jogador para um membro da Casa Fundadora incrementa `unit._order_revision`, cancela a participação dele em eventual tarefa comunitária (liberando sua vaga na fonte/obra para outro habitante) e muda o estado para `PERSONAL_ACTIVE`.
2. **Proibição de sobrescrita silenciosa:** o `CommunityTaskDispatcher` verifica `control_mode == COMMUNITY_FREE` e `unit.get_order_revision() == expected_revision` antes de emitir qualquer ordem. Nunca sobrescreve `PERSONAL_ACTIVE` nem `PERSONAL_HOLD`.
3. **Preservação de carga física em interrupção:** se um membro da Casa Fundadora estava carregando madeira/pedra/frutos (`FREE_GATHERED`) e recebe um `MoveOrder` pessoal, a carga permanece intacta na mochila (proveniência preservada, sem perda nem crédito mágico).
4. **Regra previsível ao concluir uma ordem pessoal (P-RUX-2 — Opções para aprovação):**
   - **Opção A (Recomendada — diferenciada por intenção):**
     - Ao concluir uma **ordem pessoal de trabalho** (ex.: mandou o líder cortar uma árvore ou construir uma obra e ela terminou com descarga completa): volta automaticamente para `COMMUNITY_FREE` e pode assumir tarefas pendentes.
     - Ao concluir um **movimento pessoal (`MoveOrder`)**: entra em `PERSONAL_HOLD` (mantém a posição escolhida pelo jogador, com botão discreto `"Liberar para comunidade"` no painel de seleção ou novo clique em tarefa), evitando a frustração de mover um líder para um ponto e vê-lo imediatamente sair correndo para cortar uma árvore do outro lado do mapa.
   - **Opção B (Retorno imediato universal):** toda ordem pessoal concluída (inclusive `MoveOrder`) devolve imediatamente para `COMMUNITY_FREE`. Mais simples, porém um líder reposicionado manualmente volta a sair do lugar imediatamente se houver tarefa pendente.
   - **Opção C (Retorno automático após temporizador curto de ociosidade, ex.: 5 s):** meio-termo, porém menos previsível quando o jogador quer manter o personagem parado em vigília/exploração.

---

## 6. Modelo Mínimo de Identificação da Casa Fundadora

A expressão "família real" aqui significa exclusivamente o **vínculo de linhagem e privilégio de controle pessoal + residência na Casa Principal** — sem sistemas políticos, títulos nobiliárquicos, sucessão monárquica ou construções palacianas.

### 6.1 Estrutura mínima de dados (extensível para T5)
Sem alterar `CharacterDefinition` nesta entrega documental, propõe-se a evolução mínima dos dados de identidade do personagem:

```text
CharacterIdentityData (em CharacterDefinition / futuro CharacterRecord)
- character_id: StringName            # imutável (ex.: &"leader_a", &"leader_b")
- given_name: String                  # editável pelo jogador sem alterar ID
- family_name: String                 # sobrenome da linhagem
- is_original_founder: bool           # true SOMENTE para LeaderA e LeaderB (únicos com proteção contra morte definitiva)
- is_founder_descendant: bool         # true para TODOS os descendentes diretos da linhagem fundadora (permanente)
- house_affiliation: enum { FOUNDING_HOUSE, COMMUNITY }
- age_stage: enum { BABY, CHILD, YOUTH, ADULT }  # gancho futuro (default ADULT na T3)
- parent_ids: Array[StringName]       # genealogia persistente (T5)
- spouse_id: StringName               # vínculo conjugal persistente (T5)
- home_residence_id: StringName       # aponta para a Casa Principal para toda a Casa Fundadora
```

### 6.2 Regras normativas preservadas e ponto em aberto
- **Permissão única de controle pessoal:** `has_personal_control(char)`:
  - `false` se `age_stage == BABY` (bebês não são selecionáveis no mapa — `DEC-04`).
  - `true` permanentemente se `is_original_founder` ou `is_founder_descendant` (em `CHILD`, `YOUTH` e `ADULT`, **mesmo após casar**).
  - Para cônjuge que entra na `FOUNDING_HOUSE` por casamento sem ser descendente: controlado por regra única dependente da decisão **P-RUX-3** (`ABERTO`).
- **Imortalidade estrita:** somente `is_original_founder == true` possui a Proteção Especial dos Líderes (`DEC-07`). Todos os descendentes (`is_founder_descendant == true`) são **mortais** (`DEC-04`), embora conservem controle pessoal permanente enquanto vivos.
- **Genealogia e casamento:** preservação integral de `DEC-02` (bloqueio até primos de 1º grau; casamento somente entre `ADULT 18+`), `DEC-03` e `DEC-04` (viuvez e acolhimento de menores por avós/parentes).

---

## 7. Modelo de Residência Principal Simplificada (Sem Interiores) e Reconciliação com o GDD

### 7.1 Arquitetura da Residência Sem Interiores (`ResidenceRecord`)
Acoplada como dado/componente leve a uma `BuildingInstance` residencial (sem quartos navegáveis, móveis, colisores internos, câmera interna ou IA doméstica):
- **Dados:**
  - `residence_id: StringName`, `building_id: StringName`, `is_founding_house: bool`.
  - `entry_anchor_local: Vector3` (ponto externo navegável em frente à entrada da edificação).
  - `resident_ids: Array[StringName]` (moradores vinculados permanentemente à residência).
  - `family_nuclei: Array[Dictionary]` (`{nucleus_id, partner_ids, dependent_ids}` — representa os casais e dependentes residentes apenas por dados).
  - `sheltered_unit_ids: Array[StringName]` (moradores atualmente abrigados "dentro" da casa).
  - `adult_capacity: int` / `dependent_capacity: int` (capacidade em dados, podendo evoluir com melhorias/níveis futuros da Casa Principal sem exigir geometria interna).
- **Fluxo de Entrada:**
  1. Unidade recebe intenção/ordem de entrar na residência e caminha pelo `WorldNavigation` até `entry_anchor` (validado via `snap_to_navmesh`).
  2. Ao chegar, verifica que não há transação econômica ativa (`not _is_reserved_withdrawal_locked()`).
  3. Unidade transita para `SHELTERED`: removida da representação visual/colisão/seleção no mundo (`visible = false`, camadas de seleção/física desabilitadas), mantendo **100% do estado interno persistente** (ID, mochila, genealogia, idade, vínculo familiar) e aparecendo na lista de moradores do painel da Casa Principal.
- **Fluxo de Saída:**
  1. Acionada pelo jogador (ao selecionar o morador no painel da Casa Principal ou emitir comando) ou pelo sistema comunitário/rotina quando aplicável.
  2. Resolve um ponto navegável livre próximo ao `entry_anchor` (evitando sobrepor outras unidades/obstáculos).
  3. Reposiciona a unidade, restaura visibilidade/colisão/seleção e a coloca em `IDLE` pronta para receber ordem pessoal ou trabalhar automaticamente.

### 7.2 Reconciliação com o GDD v1.2 §3.4
O GDD v1.2 §3.4 estabelecia que *"cada casal casado exige residência própria"*. Com a nova diretriz da Casa Fundadora, propõe-se reconciliar o GDD em duas regras complementares e sem contradição:
1. **Casa Fundadora (Protagonistas + todos os descendentes):** permanecem vinculados e residindo na **Casa Principal** mesmo após atingirem a idade adulta e casarem. Os múltiplos núcleos conjugais da linhagem são registrados em `family_nuclei` dentro da capacidade de dados da Casa Principal (iniciada pelo primeiro Abrigo Básico no Cap. 1 e expansível por melhorias futuras, sem palácios nem interiores).
2. **Famílias comuns (habitantes não pertencentes à Casa Fundadora, Cap. 2–3):** continuam necessitando de **Casas Familiares** próprias para formar novos casais e ter filhos, preservando integralmente o sentido de expansão urbana da comunidade (Níveis 2–5 do GDD §6).
3. **Regra de nascimentos (`DEC-03`):** mantida integralmente (casal residindo junto + vaga de dependente disponível na residência + estabilidade alimentar coletiva + intervalo progressivo por casal), apenas avaliada por núcleo conjugal dentro da Casa Principal ou da Casa Familiar correspondente.

---

## 8. Contabilidade para Construção com Débito Imediato

### 8.1 Nova Equação de Conservação do Assentamento
Substituindo reserva-em-pilha + transporte + buffer de obra por débito imediato atômico na confirmação, a equação de conservação por recurso $R$ torna-se:

$$Q_{\text{inicial}}(R) + Q_{\text{coletado}}(R) = Q_{\text{estoque\_livre}}(R) + \sum_{u} Q_{\text{mochila}}(u, R) + \sum_{c} Q_{\text{obra\_paga}}(c, R) + \sum_{b} Q_{\text{edificado}}(b, R) + Q_{\text{deteriorado}}(R) + Q_{\text{perda\_cancelamento}}(R)$$

Onde:
- $Q_{\text{estoque\_livre}}(R) = Q_{\text{pilhas\_livres}}(R) + \sum_{d} Q_{\text{depósito\_livre}}(d, R)$ (autoridade única em `SettlementInventory`).
- $Q_{\text{mochila}}(u, R)$ contém **exclusivamente** recursos em transporte de coleta (ou eventual carga de recuperação, se escolhida opção física), nunca reserva de suprimento de obra.
- $Q_{\text{obra\_paga}}(c, R) = \text{cost}(c, R)$ representa o material já debitado e custodiado contabilmente pelo canteiro ativo $c$ desde sua criação.
- Na conclusão do canteiro $c \to b$: $Q_{\text{obra\_paga}}(c, R)$ transfere-se integralmente para $Q_{\text{edificado}}(b, R)$ (`BuildingInstance.incorporated_materials`).
- No cancelamento de $c$: $Q_{\text{obra\_paga}}(c, R) = Q_{\text{reembolsado}}(c, R) + Q_{\text{perda\_cancelamento}}(c, R)$, fechando a conservação com exatidão inteira.

### 8.2 Fluxo Atômico de Criação de Obra (`try_create_site_direct_debit`)
1. **Validação espacial completa (inalterada):** `PlacementValidator` + malha candidata assíncrona (`D6`, exclusão da `CampStorageZone`, sem sobreposição com obras/prédios/recursos/unidades).
2. **Guarda regional e checagem integral:** verificar `inventory.can_withdraw_batch(costs)` sob lock regional (mesma proteção anti-reentrância de `ConstructionManager`). Se qualquer recurso for insuficiente, rejeitar **antes de qualquer mutação** e informar o déficit exato (ex.: `"Faltam 4 madeiras e 2 pedras."`).
3. **Débito atômico com rollback:** executar retirada atômica `withdraw_batch` com snapshot/checkpoint interno (em T3.7+, seguindo ordem determinística definida em **P-RUX-4** — recomendado: pilhas expostas mais antigas primeiro para reduzir perdas por exposição, recorrendo aos depósitos protegidos apenas para o restante).
4. **Instanciação do canteiro e registro comunitário:** criar `ConstructionSite` já integralmente pago (`paid_materials = costs`, `work_progress_usec = 0`), validar entrada na árvore e registrar automaticamente uma `WorkTask(BUILD_SITE)` no `CommunityWorkBoard`. Qualquer falha de instanciação restaura integralmente o checkpoint do estoque (zero perda, zero duplicação).
5. **Montagem direta:** até `max_builders` (`2` provisórios em `D4`) caminham até o perímetro (`BuildSlotPlanner`) e avançam `work_progress_usec` até `total_work_usec` → transmutação em `BuildingInstance` + rebake assíncrono em `WorldNavigation` (`DEC-19`). Se não houver trabalhador livre no momento, o canteiro aguarda em `PENDING_WORKERS` sem perder os materiais já pagos.

### 8.3 Destino dos mecanismos de T3.1–T3.6 (sem descarte prematuro)
- **O que deixa de ser usado no novo fluxo de construção:** reservas em pilhas (`reserve_batch`), transporte de suprimento (`MOVING_TO_PILE` / `MOVING_TO_SITE_DROPOFF`), papéis `SOLO_SUPPLIER`/`TRANSPORTER` e complementação manual `DEC-11B`.
- **Regra de segurança na migração:** **não** apagar `PileReservationLedger`, testes T3.1/T3.3/T3.4/T3.6 ou `CancellationRecoveryDispatcher` durante `RUX-1`–`RUX-3`. Apenas após aprovação formal da `RUX-4` (construção simplificada) e escolha da política de cancelamento (§9) deve-se decidir quais componentes antigos serão aposentados em `RUX-5` e quais testes serão migrados vs arquivados com justificativa explícita.

---

## 9. Alternativas de Cancelamento e Reembolso sob Débito Imediato (`PENDENTE DE DECISÃO — P-RUX-1`)

Com o pagamento integral no ato da confirmação, não há mais reservas em pilhas nem materiais em trânsito para o canteiro. Abaixo estão quatro alternativas tecnicamente válidas e conservativas — **nenhuma está aprovada ainda**:

| Alternativa | Fórmula / Regra contábil | Destino do reembolso | Prós | Contras / Riscos |
|---|---|---|---|---|
| **R1 — Proporcional imediato (equivalente numérico à D3 sem transporte)** | Reembolsa $\lfloor C(R) \cdot (1 - p) \cdot \eta_{\text{efetivo}} \rfloor$ ou separa fração não montada $(1-p)$ integral + parcela montada com $\eta = 0,50$, sempre em inteiros exatos: $Q_{\text{ret}} + Q_{\text{perda}} = C(R)$. | Crédito imediato nas pilhas da `CampStorageZone` (ou depósito T3.7 com espaço) na transação de cancelamento. | Alinhado à filosofia D3 (cancelar tarde tem custo); zero microgestão de recolhimento de sobras; evita cancelamento-abuso. | Em `0%` (antes de qualquer martelada), se aplicar $\eta$ ao total penalizaria erro de clique; por isso R2 costuma ser preferível. |
| **R2 — 100% em `0%` de progresso; proporcional após iniciar montagem** | Se `work_progress_usec == 0`: devolve **100%** de $C(R)$. Se `work_progress_usec > 0`: devolve fração não montada + $\lfloor \text{montada} \cdot (1 - p) \cdot \eta \rfloor$ (com $\eta = 0,50$ provisório) ou fórmula única $\lfloor C(R) \cdot (1 - p) \rfloor$. | Crédito imediato em armazenamento válido (`CampStorageZone` / depósito protegido). | Corrige erros acidentais de posicionamento sem punição (0% = 100% de volta); mantém custo real após trabalho iniciado; muito simples em UI e Save/Load. | Exige definir se a fração já montada usa $\eta = 0,50$ ou proporção linear simples $(1-p)$. |
| **R3 — Reembolso integral (100%) antes da conclusão** | Devolve **100%** de $C(R)$ em qualquer progresso $p < 100\%$. | Crédito imediato em armazenamento válido. | Máxima simplicidade técnica e de entendimento para o jogador; elimina perdas por cancelamento. | Permite usar canteiros como "cofre temporário" contra deterioração de madeira exposta (para mitigar, exigiria guardar tempo de exposição ou limitar a obras protegidas). |
| **R4 — Proporcional com recuperação física no local (híbrido com D3 atual)** | Mesma fórmula de R2, mas o valor recuperável fica como sobras físicas no terreno exigindo recolhimento pelos trabalhadores. | Transporte físico de retorno à `CampStorageZone` via `CancellationRecoveryDispatcher`. | Reaproveita boa parte da T3.6 já construída. | Incoerente com o objetivo de simplificação: se o material não foi transportado até a obra na ida, exigir transporte manual na volta cria fricção assimétrica e mantém toda a complexidade de custódia em trânsito. |

> [!IMPORTANT]
> **Observação sobre risco de "cofre anti-decaimento":** nas opções R1, R2 e R3, se um jogador posicionar e cancelar repetidamente uma obra em 0% apenas para "resetar" a idade de exposição da madeira nas pilhas, o crédito do reembolso deve ou (a) herdar a exposição média ponderada das pilhas debitadas (em `R1/R2/R3`), ou (b) aplicar a regra de conservação de exposição já suportada por `GroundPileManager.MergeExposurePolicy`. Isso garante que nenhum cancelamento sirva de exploit contra `DEC-11A`.

---

## 10. Impacto sobre T3.7, T3.8 e T3.9

- **T3.7 — Depósito Rústico (`storage_depot`, 50 madeiras / 50 pedras / 30 alimentos, decaimento `0,0`):**
  - **Simplificação positiva:** sem reservas de obra espalhadas por pilhas e depósitos, o `CompositeStorageSource` (agregando `GroundPileManager` + instâncias de `StorageDepot`) tem contrato muito mais limpo:
    - Coleta física (`DeliverToCampOrder` estendido) entrega preferencialmente no depósito protegido mais próximo com espaço; se lotado, descarrega na `CampStorageZone` (sobra exposta).
    - Construção debita atomicamente seguindo prioridade determinística (**P-RUX-4**: recomendado debitar pilhas expostas mais antigas primeiro, preservando estoque protegido).
    - Reconciliação de saldos e deterioração (`DEC-11A` + `0,0` no depósito) permanece 100% auditável.
- **T3.8 — Persistência Versionada em Disco (`schema_version = 1`, D1 / DEC-17):**
  - **Simplificações no snapshot de obras:** cada canteiro ativo precisa apenas de `{site_id, definition_id, transform, work_progress_usec, paid_materials}` (sem `reservations`, `materials_buffer`, `transit_claims_by_site` nem `deficit_uncompensated` para obras novas).
  - **Novos campos obrigatórios no snapshot:**
    - `work_board.tasks`: lista ordenada de tarefas pendentes/ativas (`task_id`, `kind`, `resource_id`, `source_ids` finitos, `site_id`, `created_seq`).
    - `units[].control_mode` (comunitário livre/ocupado vs ordem pessoal / hold) e `units[].house_affiliation` / `is_original_founder` / `is_founder_descendant` (quando introduzidos em RUX-3).
    - `residences[]` com `sheltered_unit_ids` e `family_nuclei` (quando a residência sem interiores entrar em T4/T5).
  - Protocolo `.tmp → validação em memória → .bak → rename` e restauração de `ResourceSource` permanecem inalterados.
- **T3.9 — Validação Global, Protocolo Manual e Benchmarks (Intel UHD 620):**
  - Mantém integralmente os critérios: 0 erros, 0 avisos, 100% das suítes na regressão segmentada, protocolo manual completo em `1280×720` e `1920×1080` e benchmark gráfico em `1920×1080` (`gl_compatibility`, tomada CA, $p95 \le 16,7\text{ ms}$, `0` quadros $> 100\text{ ms}$).
  - Risco de desempenho mitigado desde o desenho: `CommunityTaskDispatcher` sem `_process`/`_physics_process`, coalescência deferred, busca preguiçosa de acesso no `GatherSlotPlanner`, e realces de tarefas compartilhando 1 mesh + 1 material `unshaded` sem sombra.

---

## 11. Plano Incremental de Migração (Dependências Reais, RED → GREEN)

A migração avança em incrementos pequenos, reversíveis e isolados, **sem implementar tudo de uma vez** e **sem destruir a UX-1 nem a `MainScene`** antes da validação jogável.

| Fase | Escopo e objetivo | Dependências | Entregáveis / Cena | Testes RED → GREEN obrigatórios |
|---|---|---|---|---|
| **RUX-1** *(1º protótipo futuro)* | **Protótipo mínimo de coleta automática (1 fonte + 2 líderes):** clique esquerdo em 1 árvore cria tarefa comunitária → distribuidor escolhe o líder livre mais próximo → coleta, mochila e descarga física reais → clique repetido não duplica → se ambos ocupados, tarefa aguarda e inicia quando alguém libera. | Aprovação de RUX-0 (e P-RUX-5) | `WorkTask`, `CommunityWorkBoard`, `CommunityTaskDispatcher` (mínimo), entrada isolada e cena `tests/visual/rux_1_auto_gather.tscn` (preservando `ux_1_tree.tscn` e `main.tscn`). | **RED/GREEN:** criação por clique único, idempotência no duplo clique, despacho automático ao livre mais próximo, espera quando ambos ocupados + retomada automática ao ficar livre, conservação física e proveniência (`FREE_GATHERED`). |
| **RUX-2** | **Grupos de fontes, 3 recursos e inspeção/cancelamento:** estender para árvores, rochas e arbustos; `Shift` e caixa iniciada sobre fonte (lista finita, 6ª fonte preservada); caixa em terreno livre preserva seleção RTS; cartão leve de inspeção/cancelamento de tarefa; tratamento de fonte esgotada, removida ou inacessível sem travar a tarefa. | RUX-1 + P-RUX-6 | `SelectionBoxMath` (fontes), `SourceHighlightPool` leve, cartão de inspeção/cancelamento, cena `tests/visual/rux_2_auto_sources.tscn`. | **RED/GREEN:** 5 árvores marcadas e 6ª intacta; rochas e arbustos; arraste em fonte vs chão; fonte inacessível/removida pulada; cancelamento de tarefa preservando carga já coletada; layout sem sobreposição em 720p e 1080p. |
| **RUX-3** | **Casa Fundadora (identificação mínima) e prioridade pessoal:** adicionar metadados mínimos de linhagem (`is_original_founder`, `is_founder_descendant`, `house_affiliation`, gancho `age_stage`) e máquina de estados `ControlMode`; garantir soberania absoluta de ordens pessoais sobre o distribuidor e regra aprovada pós-ordem pessoal. | RUX-2 + P-RUX-2 + P-RUX-3 | Extensão mínima em `CharacterDefinition`/`Unit` + integração com `CommunityTaskDispatcher` + seleção pessoal da Casa Fundadora. | **RED/GREEN:** ordem pessoal interrompe trabalho comunitário e libera vaga para colega sem perder carga; distribuidor nunca sobrescreve ordem pessoal ativa; comportamento pós-`MoveOrder` conforme P-RUX-2; morador comum vs membro da Casa Fundadora. |
| **RUX-4** | **Construção simplificada com débito imediato e cancelamento:** `try_create_site_direct_debit`, validação de déficit integral, tarefa automática `BUILD_SITE` no `CommunityWorkBoard`, montagem direta por até `max_builders` sem transporte D2, transmutação em `BuildingInstance` + rebake, e política de reembolso aprovada (`P-RUX-1`). | RUX-3 + P-RUX-1 + P-RUX-4 | Novo caminho de criação/montagem/cancelamento em `ConstructionManager`/`ConstructionSite`/`ConstructOrder` + adaptação do inspetor de obra. | **RED/GREEN:** débito atômico exato e rollback em falha; recusa limpa em déficit; espera sem trabalhadores e retomada automática; montagem até `BuildingInstance` + rebake; cancelamento em 0%/50%/90% conservando estoque e exposição. |
| **RUX-5** | **Integração na `MainScene`, corte controlado e atualização normativa:** conectar fluxo aprovado na cena principal, decidir/executar retirada de caminhos obsoletos (clique direito antigo / D2 / DEC-11B) com migração transparente de testes, e atualizar `Dawn_of_Kin_GDD.md`, `AGENTS.md` e `README`. | Aceite manual do proprietário em RUX-1..RUX-4 | `src/main/main.tscn`, `src/main/main.gd`, documentação normativa atualizada. | `validate.ps1` (0 erros/avisos), `run_tests.ps1 -Segmented` (100% suítes descobertas) e protocolo manual completo em 720p/1080p. |
| **T3.7 → T3.8 → T3.9** | **Encerramento da T3 sobre a base RUX:** Depósito Rústico (`CompositeStorageSource`), Save/Load `schema_version = 1` (incluindo `CommunityWorkBoard` e `ControlMode`), campanha final e benchmark Intel UHD 620. | RUX-5 | Escopos já definidos no plano T3 ajustados conforme §10. | Regressão segmentada integral + testes de corrupção/backup de save + benchmark CA 1080p. |
| **T4 / T5** | **Residência Principal sem interiores, Ciclo de Vida e `JobSystem`:** implementar `ResidenceRecord` (entrar/sair `SHELTERED` + `family_nuclei` em dados), idades (`DEC-04`), nascimentos (`DEC-03`) e profissões permanentes (Camada 2). | T3.9 concluída | Módulos de família, residência e profissões no roadmap T4/T5. | Suítes dedicadas de genealogia, restrição etária, entrada/saída segura e profissões. |

---

## 12. Critérios Objetivos de Aceite, Preservação de Testes e Rollback

### 12.1 Critérios objetivos de aceite por incremento futuro
1. **Qualidade estática:** `.\tools\validate.ps1` com **0 erros e 0 avisos** em todos os scripts GDScript tipados e boot headless limpo.
2. **TDD real (RED → GREEN):** cada incremento inicia provando a ausência/falha do requisito em teste novo antes da implementação e passa 100% após a implementação.
3. **Integridade de regressão:** `.\tools\run_tests.ps1 -Segmented` executando 100% das suítes descobertas (0 faltantes, 0 duplicatas, 0 falhas). **Nenhum teste existente pode ser removido ou silenciado para aparentar sucesso**; testes ligados a regras substituídas (`D2`/`D9`/`DEC-11B`) permanecem ativos durante `RUX-1`–`RUX-3` e só podem ser aposentados/substituídos em `RUX-5` mediante registro explícito de correspondência.
4. **Conservação econômica comprovada:** em todos os testes de coleta, interrupção pessoal, construção e cancelamento, a equação da §8.1 fecha com diferença `0`.
5. **Separação rigorosa de validação:** diferenciar sempre *implementado*, *testado automaticamente (headless)* e *homologado visualmente pelo proprietário*.

### 12.2 Estratégia de Rollback
- **Isolamento de histórico:** cada fase (`RUX-1` a `RUX-5`) é desenvolvida em branch própria ou commits pequenos e atômicos a partir da base verificada, **nunca** reescrevendo `main` (`25e0a20`), `feat/t3-6-3-cancellation-custody` (`8deeef1`) ou `feat/ux-1-contextual-tree` (`0e78f9a`).
- **Coexistência segura:** `RUX-1` e `RUX-2` operam em cenas isoladas (`tests/visual/rux_*.tscn`) sem modificar `src/main/main.tscn` nem `tests/visual/ux_1_tree.tscn`.
- **Recuo imediato sem comandos destrutivos:** se qualquer fase apresentar problema conceitual, regressão ou degradação na Intel UHD 620, o recuo ocorre retornando ao último commit validado da fase anterior ou por `git revert` rastreável.

---

## 13. Checklist de Decisões para Revisão do Proprietário

Para liberar a implementação do primeiro protótipo mínimo (**RUX-1**), solicita-se revisão deste documento e definição dos pontos abaixo:

1. **Aprovação geral da direção RUX-0** (coleta automática por seleção de fontes, construção com débito imediato, Casa Fundadora com controle pessoal permanente e residência principal sem interiores).
2. **P-RUX-1 (Reembolso de cancelamento de obra — §9):** R1, R2 *(recomendada)*, R3 ou R4? *(Se R2, confirmar se fração montada usa $\eta = 0,50$ ou proporção linear $(1-p)$.)*
3. **P-RUX-2 (Retorno pós-ordem pessoal — §5.2):** Opção A *(recomendada: trabalho pessoal retorna ao concluir; `MoveOrder` mantém posição até liberação/nova ordem)*, Opção B ou Opção C?
4. **P-RUX-3 (Cônjuges externos na Casa Fundadora — §6.2):** manter em aberto para T5 ou definir desde já se ganham controle pessoal?
5. **P-RUX-4 (Ordem de débito na construção em T3.7+ — §8.2):** pilhas expostas mais antigas primeiro *(recomendado)* ou depósitos primeiro?
6. **P-RUX-5 (Escopo da RUX-1):** autorizar, após esta revisão, o protótipo isolado mínimo `RUX-1` (1 fonte + 2 líderes em cena dedicada, preservando `ux_1_tree.tscn` e `main.tscn`)?
7. **P-RUX-6 (Cancelamento de tarefa de coleta — §4.1):** confirmar cartão leve ao clicar em fonte marcada com botão `Cancelar tarefa`?
