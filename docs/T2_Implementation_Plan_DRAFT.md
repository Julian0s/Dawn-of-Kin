# T2 — Plano de Implementação Revisado: Trabalho, Transporte Físico, Pilhas no Chão e Armazenamento Progressivo

> **STATUS: RASCUNHO — NÃO APROVADO**
>
> Este documento consolida a ordem de execução incremental da **T2 — Trabalho e Recursos** para auditoria na branch `docs/t2-review`. **Não iniciar `T2.0` nem alterar código do jogo sem aprovação explícita do proprietário e definição dos pontos em `ABERTO` listados na arquitetura.**

---

## 1. Pré-requisitos e baseline obrigatória

- **Baseline Git e engine:** branch base `main` em `t1-complete` (`2808799`), Godot `4.7.2`, GDScript, `Compatibility / OpenGL 3.3`, **Intel UHD 620 (16 GB RAM)**.
- **Invariante de regressão contínua:** em **todos** os incrementos (`T2.0` a `T2.6`), `tools/validate.ps1` e `tools/run_tests.ps1` devem continuar executando integralmente os **90 testes e 1.607 asserções da T1**, sem exclusões, sem ocultar avisos e sem regressão nos corredores espaciais (`test_commands.gd`) nem em `test_test_map.gd`.
- **Invariante de desempenho (`KNOWN_ISSUES.md`):** pós-T1.10 em `1920×1080`, `p95 = 16,586 ms` (folga de `0,114 ms` para o teto obrigatório de `16,7 ms`). Toda nova entidade visual, colisor ou atualização periódica da T2 deve nascer projetada para orçamento quase nulo.
- **Invariante de início do jogo:** o casal protagonista inicia **sem ferramentas, sem equipamentos e sem construções humanas pré-existentes**; placeholders visuais simples são permitidos para pilhas e fontes na T2.

---

## 2. Escopo da T2 vs adiamentos justificados (`T3+` / `T4+`)

| Item | Entra na T2? | Justificativa técnica e de escopo |
|---|---|---|
| Peso unitário, capacidade individual (`0%`–`100%`) e retorno/descarregamento físico | **Sim** | Decisão **DECIDIDO** (D2-1); núcleo do requisito da T2. |
| Pilhas físicas variáveis no chão em qualquer posição válida e acessível (placeholders simples) | **Sim** | Decisão **DECIDIDO** (Armazenamento no chão); elimina estruturas humanas pré-prontas. |
| Agrupamento (`merge`), recolhimento (`pick up`), transporte de pilhas externas e carga parcial | **Sim** | Necessário para que pilhas no chão não sejam "becos sem saída" físicos. |
| Sistema configurável de exposição/deterioração até o desaparecimento (com contador auditável) | **Sim** | Decisão **DECIDIDO**; fundamenta progressão até armazéns futuros sem construir prédios na T2. |
| Armazenamento inicial sem construções (`CampStorageZone` / regra híbrida) | **Sim** (`PROPOSTA` pendente de aceite) | Permite que recursos entregues no acampamento alimentem o `SettlementInventory` antes da `T3`. |
| Construção posicionável de armazéns/depósitos cobertos | **Não (adiado para T3)** | Construir edifícios pertence ao marco `T3 — Construção`. Na T2 deixamos apenas a interface `StoragePoint` e `decay_multiplier = 0.0` prontos para receber os prédios da T3. |
| Ciclo dia/noite, calendário completo, chuva acelerando estrago e Save/Load em disco | **Não (adiado para T4/T7)** | Pertencem à `T4` e `T7`. Na T2 isolamos apenas `WorldTimeProvider` e serializabilidade simples dos dados. |
| Modelos 3D finais de pilhas e animações definitivas de trabalho | **Não (pós-protótipo)** | GDD §16 e decisão atual autorizam placeholders simples e legíveis na fase inicial. |

---

## 3. Sequência incremental (`T2.0` a `T2.6`)

### Incremento `T2.0` — Contratos de Materiais, Peso, Carga Individual (`0%`–`100%`) e Inventário
- **Objetivo:** estabelecer o núcleo lógico puro e determinístico de materiais, peso, mochila da unidade (`UnitCarryLoad`), `SettlementInventory` e auditoria estrita de conservação (incluindo campo de perda intencional por deterioração).
- **Arquivos/módulos previstos:** definições parametrizadas (`ResourceDefinition`, `DecayProfile`), `UnitCarryLoad`, `SettlementInventory`, livro-razão opcional de conservação em testes e suíte unitária dedicada.
- **Dependências:** aprovação das decisões em `ABERTO` sobre estrutura de pesos/capacidade (valores exatos ficam parametrizados em `.tres`/config).
- **Testes obrigatórios:**
  - Cálculo exato de peso e porcentagem (`0%` a `100%`), checagem de capacidade ao tentar inserir `+1` unidade que ultrapassaria `100%`;
  - Transações sem criação/perda acidental e proibição explícita de crédito direto ao `SettlementInventory` na coleta;
  - Conservação matemática validando entrada, retirada, perda intencional por deterioração e carga multi-categoria;
  - Regressão integral dos **90 testes / 1.607 asserções da T1**.
- **Critério de aceite:** 100% dos testes unitários da `T2.0` e `T1` verdes em headless, zero novos avisos.
- **Modelo de IA sugerido:** **Gemini 4 Hydrogen Medium** (lógica pura bem especificada e testes unitários).

### Incremento `T2.1` — Pilhas Físicas no Chão (`GroundResourcePile`), Deterioração Centralizada e Armazenamento Inicial
- **Objetivo:** implementar `GroundPileManager`, `GroundResourcePile` (com placeholders diferenciados para madeira, pedra e alimentos em quantidades variáveis), validação de posição navegável (`WorldNavigation.snap_to_navmesh`), `CampStorageZone` + `StorageRegistry`, `WorldTimeProvider` (hook para T4) e o motor de deterioração centralizado (zero `_process` por pilha).
- **Dependências:** `T2.0` concluída + definição do proprietário sobre regra híbrida de zona de acampamento (`Modelo A` vs `Modelo B`) e política inicial de deterioração/merge.
- **Testes obrigatórios:**
  - Criação de **pilhas simultâneas** de categorias iguais e diferentes em posições válidas e rejeição/ajuste de posições inválidas;
  - Agrupamento (`merge`) de pilhas compatíveis na mesma área, preservando/combinando exposição conforme regra aprovada;
  - **Retirada parcial** de uma pilha reduzindo quantidade/visual sem duplicação e removendo a pilha apenas ao chegar a zero;
  - **Deterioração controlada:** avanço determinístico do relógio reduzindo/expirando pilhas expostas no chão descoberto, zerando proteção quando `decay_multiplier = 0.0` (simulação de armazém T3+), e registrando a perda em `total_decayed` na equação de conservação;
  - Sincronia entre pilhas dentro da `CampStorageZone` e `SettlementInventory` (crédito na entrega válida, débito na retirada ou deterioração) vs pilha externa não creditada no estoque utilizável;
  - Regressão T1 intacta.
- **Critério de aceite:** todas as invariantes de pilha, deterioração e conservação provadas em testes determinísticos sem usar `_process` por pilha.
- **Modelo de IA sugerido:** **Gemini 4 Hydrogen High** (acoplamento espacial no NavMesh, deterioração temporal e sincronização transacional com o inventário).

### Incremento `T2.2` — Fontes Naturais, Picking Estendido e Ação Contextual sem Quebrar T1
- **Objetivo:** criar `ResourceSource` parametrizado (árvore, arbusto de alimentos, rocha) com estoque finito/esgotável, integrar picking seguro para fontes, `GroundResourcePile` e `CampStorageZone` sem poluir `TestMap/Obstacles`, e implementar o roteamento de clique direito + comando contextual de soltar carga no chão mantendo `PickResult.Kind.GROUND → MoveOrder` intocado.
- **Dependências:** `T2.1` concluída + decisão UX sobre comando explícito de soltar carga no chão (botão contextual no HUD e/ou `Alt + Clique Direito`).
- **Testes obrigatórios:**
  - Picking discrimina corretamente terreno vazio (`MoveOrder`), unidade, fonte de recurso, pilha no chão e área de acampamento;
  - Nenhuma árvore/pedra/pilha invade os corredores de `test_commands.gd` nem quebra `test_test_map.gd`;
  - Regressão completa T1 + novos testes de picking.
- **Critério de aceite:** comandos T1 seguem 100% idênticos; picking e despacho contextual das novas entidades validados em cena e headless.
- **Modelo de IA sugerido:** **Gemini 4 Hydrogen Medium**.

### Incremento `T2.3` — Estados do Trabalhador e Ciclo Completo de Coleta, Transporte, Pilha e Retorno ao Estoque
- **Objetivo:** implementar na unidade o ciclo completo de trabalho (`MOVING`, `WORKING`, `CARRYING` / `DELIVERING`, `DROPPING`, `PICKING_UP_PILE`, `IDLE`): caminhar até fonte, coletar respeitando peso e capacidade (`0%`–`100%`), parar ao atingir `100%` ou não caber `+1` unidade, retornar ao acampamento para descarregar, permitir soltar carga no chão, recolher pilhas externas (total ou parcialmente até o limite de carga) e devolvê-las ao estoque do acampamento.
- **Dependências:** `T2.2` concluída.
- **Testes obrigatórios:**
  - Ciclo fim-a-fim: coleta na fonte não aumenta `SettlementInventory` antes da descarga válida no acampamento;
  - **Carga parcial:** fonte se esgota antes de `100%` → unidade conclui sem travar e entrega carga parcial acumulada;
  - **Retirada e devolução de pilha externa:** unidade recolhe até `floor(livre / peso)` de uma pilha externa (deixando resto na pilha se exceder `100%`) e devolve ao acampamento aumentando `SettlementInventory`;
  - **Cancelamento e redirecionamento:** cancelar ordem ou dar nova ordem de movimento no meio do transporte **preserva** `UnitCarryLoad` integralmente sem perda nem duplicação;
  - **Concorrência:** dois ou mais trabalhadores coletando da mesma fonte/pilha quase esgotada ou entregando juntos respeitam conservação exata sem duplicar a última unidade nem travar estados;
  - Regressão integral T1.
- **Critério de aceite:** todos os cenários de ciclo completo, carga parcial, retirada/entrega, cancelamento e concorrência aprovados com conservação `= 0`.
- **Modelo de IA sugerido:** **Gemini 4 Hydrogen High** (máquina de estados RTS, condições de corrida entre trabalhadores e RVO).

### Incremento `T2.4` — Composição no Mapa Principal e Cenário Jogável sem Estruturas Prévias
- **Objetivo:** integrar fontes naturais, placeholders iniciais e demarcação lógica inicial do acampamento no fluxo jogável principal garantindo **zero construções humanas pré-existentes** e **zero ferramentas iniciais**, preservando integralmente os corredores e obstáculos testados na T1.
- **Dependências:** `T2.3` concluída.
- **Testes obrigatórios:**
  - Verificação automatizada de cena inicial: nenhuma estrutura construída pré-existente; fontes alcançáveis fora dos corredores protegidos;
  - Teste multi-unidade em simulação: múltiplos trabalhadores coletando, formando pilhas simultâneas, reagrupando e trazendo para o acampamento sem deadlock de RVO;
  - `test_test_map.gd` e toda a suíte T1 verdes.
- **Critério de aceite:** fluxo jogável completo de coleta/chão/entrega funcional sobre o mapa validado, sem regressão espacial.
- **Modelo de IA sugerido:** **Gemini 4 Hydrogen Medium**.

### Incremento `T2.5` — HUD da T2: Porcentagem de Carga (`0%`–`100%`), Estoque, Risco de Exposição e Ação de Soltar
- **Objetivo:** exibir de forma limpa e legível em câmera isométrica: porcentagem de carga individual (`0%`–`100%`) e estado da unidade selecionada, estoque utilizável por categoria do assentamento, botão contextual (ou indicador) para soltar carga no chão e alerta discreto sobre pilhas expostas sujeitas à deterioração.
- **Dependências:** `T2.4` concluída.
- **Testes obrigatórios:**
  - Testes de vínculo HUD ↔ sinais sem polling pesado por frame: barra/`%` acompanha carregamento e descarga; painel atualiza imediatamente em entrega, retirada e perda por deterioração;
  - Cancelar seleção / limpar cena sem erros nem vazamento de sinais;
  - Regressão T1 + T2 verdes.
- **Critério de aceite:** HUD funcional, desacoplada dos scripts de simulação e sem custo mensurável por frame em estado parado.
- **Modelo de IA sugerido:** **Gemini 4 Hydrogen Medium**.

### Incremento `T2.6` — Validação Final, Benchmark na Intel UHD 620 e Aceite Manual da T2
- **Objetivo:** auditar toda a T2 com suíte completa (`validate.ps1` + `run_tests.ps1`), medir desempenho real na **Intel UHD 620 em `1920×1080` (`OpenGL Compatibility`)** com fontes, trabalhadores e dezenas de pilhas expostas ativas, e conduzir o checklist manual de mouse e legibilidade visual com o proprietário.
- **Dependências:** `T2.5` concluída.
- **Testes e verificações obrigatórias:**
  - `tools/validate.ps1` e `tools/run_tests.ps1`: `0` erros, `0` avisos, **90 testes / 1.607 asserções da T1** preservados + toda suíte da T2 aprovada;
  - `tools/perf.ps1` (ou benchmark estendido T2 em `1920×1080` na Intel UHD 620): confirmar **`p95 <= 16,7 ms`** com múltiplas pilhas e ciclos ativos (identificando qualquer regressão sobre a margem de `0,114 ms` da T1.10);
  - Checklist manual visual/mouse: selecionar protagonista, coletar madeira/pedra/comida, ver carga ir de `0%` a `100%`, soltar carga formando pilha visual no chão, agrupar outra entrega, observar deterioração/alerta em cenário acelerado de teste, recolher pilha externa e entregar no acampamento vendo o estoque subir somente após a entrega.
- **Critério de aceite:** suíte automatizada verde + `p95 <= 16,7 ms` medido em hardware alvo + aprovação visual explícita do proprietário antes de qualquer commit/tag de encerramento da T2.
- **Modelo de IA sugerido:** **Gemini 4 Hydrogen High** (diagnóstico de gargalo na margem de `0,114 ms` e auditoria final).

---

## 4. Matriz consolidada de testes da T2 (além dos 90 testes / 1.607 asserções da T1)

| Categoria de teste | Cenário mínimo obrigatório | Incremento |
|---|---|---|
| **Peso e capacidade** | Materiais com pesos distintos, cálculo `0%`–`100%`, bloqueio exato quando `+1` unidade excede `100%` | `T2.0` |
| **Pilhas simultâneas** | Múltiplas pilhas criadas no mesmo cenário (mesma categoria e categorias diferentes), validação no NavMesh e agrupamento (`merge`) | `T2.1` |
| **Retirada parcial** | Unidade retira apenas parte da pilha (limitada pelo espaço livre restante) sem destruir o restante da pilha | `T2.1` / `T2.3` |
| **Deterioração controlada** | Tempo simulado faz pilha exposta deteriorar e desaparecer; proteção `0.0` zera perda; perda contabilizada no balanço | `T2.1` |
| **Carga parcial de fonte** | Árvore/arbusto/rocha esgota antes de `100%` e unidade conclui retorno entregando carga parcial | `T2.3` |
| **Devolução ao estoque** | Recolher pilha externa e entregar no acampamento atualiza `SettlementInventory` apenas no ato da entrega válida | `T2.3` |
| **Concorrência** | Duas unidades disputando última unidade de uma fonte ou mesma pilha sem duplicação, valor negativo ou travamento | `T2.3` / `T2.4` |
| **Cancelamento** | Cancelar ou trocar ordem em trânsito preserva 100% da carga física em `UnitCarryLoad` | `T2.3` |
| **Conservação global** | $\Delta\text{Fontes} + \Delta\text{Cargas} + \Delta\text{PilhasExternas} + \Delta\text{Estoque} + \Delta\text{PerdaIntencional} = 0$ em ciclos complexos | `T2.0`–`T2.6` |
| **Desempenho UHD 620** | Benchmark `1920×1080` (`Compatibility`) com múltiplas pilhas e trabalho ativo mantendo `p95 <= 16,7 ms` | `T2.6` |

---

## 5. Riscos principais do plano e mitigações

1. **Estouro da margem de `0,114 ms` no `p95` em `1920×1080`:** mitigado mantendo `GroundPileManager` com timer de baixa frequência, materiais/malhas simples compartilhados, `Area3D` leve sem `StaticBody3D` e medição real na `T2.6`.
2. **Retrabalho caso regras em `ABERTO` mudem depois da `T2.1`:** mitigado exigindo definição explícita do proprietário antes de iniciar `T2.1`/`T2.2` e parametrizando taxas/limites/pesos em recursos de dados.
3. **Regressão na navegação/picking da T1:** mitigado com proteção explícita dos corredores espaciais (`test_commands.gd`), máscara de obstáculos (`test_test_map.gd`) e regra rígida de manter clique direito em terreno vazio como `MoveOrder`.

---

## 6. Gate de aprovação antes da implementação

Antes de autorizar a **`T2.0`**, o proprietário precisa revisar e responder:
1. Aprovação deste plano incremental (`T2.0`–`T2.6`) e da arquitetura revisada;
2. Posição sobre a **Proposta Híbrida de Estoque no Acampamento (`CampStorageZone` vs alternativa)**;
3. Definição inicial (ou autorização de valores provisórios parametrizáveis) para: **UX de soltar carga no chão**, **comportamento inicial de deterioração** e **pesos/capacidades iniciais**.
