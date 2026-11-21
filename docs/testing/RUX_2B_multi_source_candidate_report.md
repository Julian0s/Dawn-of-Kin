# RUX-2B — Relatório Técnico da Candidata de Seleção Múltipla de Fontes com Trabalho Comunitário Automático

- **Status:** **IMPLEMENTADA E TESTADA AUTOMATICAMENTE (HEADLESS + SMOKE GRÁFICO 1280×720 e 1920×1080)** — **homologação visual/jogável pelo proprietário PENDENTE**.
- **Branch candidata:** `feat/rux-2b-multi-source-selection`
- **Base:** `feat/rux-2a-auto-resource-types` em `5d2f1b934d15a352cc34d833cdf73032806cf77d` ([RUX_2A_auto_resources_candidate_report.md](RUX_2A_auto_resources_candidate_report.md))
- **Commit RED (testes B1–B14 + cena + stubs de contrato):** `c9d5b8c62c06279cb29e64335afcc52e50843e80`
- **Commit GREEN (seleção múltipla + distribuição justa + sinal de vaga + endurecimento de bloqueio):** `683e4c4088b1269ce5971fe02b246df82376a5c9`
- **Engine / ambiente verificado:** Godot `4.7.2.stable.official.ed1daf0bf`, `gl_compatibility` (`OpenGL API 3.3.0 - Build 30.0.101.1339`), `Jolt Physics`, `Intel(R) UHD Graphics 620`.

---

## 1. Arquivos Criados e Alterados

### Criados
- [tests/visual/rux_2b_multi_source_selection.tscn](../../tests/visual/rux_2b_multi_source_selection.tscn) — cena de avaliação isolada herdando `src/main/main.tscn`, com `AutonomousGatherInput` configurado para `["wood", "stone", "food"]` e `multi_source_enabled = true`, adicionando fontes extras de madeira (`WoodTree03`–`WoodTree06`), pedra (`StoneRock03`–`StoneRock04`) e alimentos (`FoodBush03`–`FoodBush04`) sem alterar o mapa compartilhado.
- [tests/integration/test_rux_2b_multi_source_selection.gd](../../tests/integration/test_rux_2b_multi_source_selection.gd) — suíte de integração real em `SubViewport` cobrindo B1–B14 (**14 testes, 114 asserções**).
- [docs/testing/RUX_2B_multi_source_candidate_report.md](RUX_2B_multi_source_candidate_report.md) — este relatório.

### Alterados (evolução incremental dos componentes existentes, sem duplicação)
- [src/rts/work_task.gd](../../src/rts/work_task.gd) — adicionado campo `group_id: int = 0` para vincular logicamente tarefas por fonte criadas em um mesmo gesto de seleção múltipla.
- [src/economy/resource_source.gd](../../src/economy/resource_source.gd) — adicionado sinal `worker_slot_released(source: ResourceSource)`, emitido em `release_worker()` e `clear_worker_reservations()` somente quando `_reserved_worker_ids` efetivamente diminui (orientado a eventos, zero polling).
- [src/rts/selection_box_math.gd](../../src/rts/selection_box_math.gd) — adicionados helpers puros `get_source_world_anchor()`, `is_source_in_box()` e `collect_sources_in_box()` reutilizando a mesma normalização e projeção de câmera da seleção RTS de unidades.
- [src/rts/rts_input_controller.gd](../../src/rts/rts_input_controller.gd) — adicionados ganchos virtuais vazios `_on_left_press_started(press_pos)` e `_on_drag_cancelled()`, preservando integralmente o comportamento da classe base.
- [src/rts/community_work_board.gd](../../src/rts/community_work_board.gd) — implementados `allocate_group_id()`, `register_gather_group(sources, p_group_id)`, `get_tasks_in_group()`, `has_active_tasks_in_group()`, `get_group_resource_id()`, conexão ao sinal `worker_slot_released` (reemitindo `task_updated` apenas quando a tarefa está em `PENDING_WORKERS`) e guarda segura contra fonte já liberada em `close_task()`.
- [src/rts/community_task_dispatcher.gd](../../src/rts/community_task_dispatcher.gd) — endurecida a guarda de `BLOCKED_REAUTHORIZATION` no Passo 1 de `_flush_dispatch()` (impedindo qualquer despacho silencioso mesmo sob entrada de novo trabalhador ou término de outra ordem) e implementada distribuição determinística justa por **FIFO de grupo + menor distância espacial** em `_partition_pending_tasks_by_group_fifo()` e `_dispatch_group_tasks()`.
- [src/rts/autonomous_gather_input.gd](../../src/rts/autonomous_gather_input.gd) — adicionado `@export var multi_source_enabled: bool = false` (preservando intactos `rux_1_auto_gather.tscn` e `rux_2a_auto_resources.tscn`), implementado `Shift + clique esquerdo` homogêneo não destrutivo, seleção por caixa iniciada sobre fonte (preservando arraste no chão para unidades RTS), cancelamento de arraste com `Esc` sem afetar tarefas confirmadas, e armazenamento de anéis de realce via `weakref(mesh_inst)` para limpeza segura se a fonte sair da árvore antes do encerramento da tarefa.

### Preservados intactos
`src/main/main.tscn`, `src/main/main.gd`, `levels/test_map/test_map.tscn`, `tests/visual/ux_1_tree.tscn`, `tests/visual/rux_1_auto_gather.tscn`, `tests/visual/rux_2a_auto_resources.tscn`, scripts UX-1 (`tree_work_input.gd`, `tree_work_menu.gd`), `docs/Dawn_of_Kin_GDD.md`, `AGENTS.md`, `main` (`25e0a20`), `design/rux-0-autonomous-work-family` (`e9d502e`), `feat/rux-1-autonomous-gather` (`30bda48`) e `feat/rux-2a-auto-resource-types` (`5d2f1b9`).

---

## 2. Decisões Arquiteturais e Modelo de Grupo Escolhido

1. **Modelo de grupo lógico (`group_id`) sobre `WorkTask` por fonte:**
   - Em vez de criar um segundo executor paralelo para "grupos", cada fonte marcada continua sendo uma `WorkTask` unitária idempotente no `CommunityWorkBoard`, vinculada às demais do mesmo gesto por um `group_id` lógico.
   - Isso garante uma única autoridade econômica (`CommandController` → `GatherResourceOrder` → `DeliverToCampOrder` → `SettlementInventory`), idempotência automática entre clique simples, `Shift + clique` e caixa (`_active_by_source_id`), e isolamento estrito das fontes não marcadas (ex.: a 6ª árvore fora da seleção nunca entra no quadro).
2. **Interação homogênea e coexistência segura com RTS existente:**
   - **Clique esquerdo simples em fonte:** comportamento idêntico à RUX-2A (inicia novo `group_id` unitário).
   - **`Shift + clique esquerdo` em fonte:** adiciona fonte do mesmo tipo ao `group_id` ativo; se a fonte já estiver marcada, preserva a tarefa e informa `"Fonte já está selecionada."` (sem remoção destrutiva, respeitando `P-RUX-6` em aberto); se for de outro tipo de recurso, recusa a mistura e exibe feedback orientativo.
   - **Caixa com arraste iniciado sobre fonte:** projeta fontes disponíveis do mesmo recurso dentro do retângulo via `SelectionBoxMath.collect_sources_in_box()` e registra o grupo inteiro de uma vez, preservando a fonte de origem mesmo que o ponteiro termine próximo.
   - **Caixa iniciada em terreno livre / fora de fonte:** delega integralmente para `RtsInputController._handle_box_selection()` (seleção clássica de unidades). `PlacementController` mantém prioridade de entrada e `Esc` cancela apenas o arraste sem cancelar tarefas já registradas.
3. **Distribuição determinística justa e continuidade orientada a eventos:**
   - As tarefas pendentes são agrupadas em ordem FIFO de criação do grupo; dentro de cada grupo, `_dispatch_group_tasks()` pareia iterativamente o par `(unidade livre elegível, tarefa pendente navegável)` de menor distância ao quadrado. Assim, 2 líderes se distribuem naturalmente em 2 árvores distintas de um grupo de 5, e ao concluir entrega/esgotamento o sinal `order_finished` dispara imediatamente o re-despacho para a próxima fonte marcada restante.
4. **Correção do sinal de liberação de vaga (`ResourceSource.worker_slot_released`):**
   - Na auditoria pré-implementação verificou-se que `ResourceSource.release_worker()` não notificava quando um trabalhador liberava a vaga (por exemplo, ao entrar em `DELIVERING_TO_CAMP`). O sinal `worker_slot_released` fecha essa lacuna sem polling: o `CommunityWorkBoard` reemite `task_updated` apenas para tarefas em `PENDING_WORKERS`.
5. **Endurecimento de `BLOCKED_REAUTHORIZATION`:**
   - Na fase RED (`test_b12`), comprovou-se que a entrada de um novo trabalhador em `Units` (ou o término de ordem de outro trabalhador) provocava despacho silencioso de uma tarefa já em `BLOCKED_REAUTHORIZATION`. A guarda explícita no Passo 1 de `_flush_dispatch()` agora ignora definitivamente tarefas bloqueadas (fechando-as apenas se a fonte se tornar esgotada ou inválida), sem reconvocar trabalhadores nem acionar recém-chegados sem reautorização futura (`P-RUX-6`).

---

## 3. Evidências RED e GREEN (Godot 4.7.2)

### 3.1 Fase RED (`c9d5b8c`)
- Comando: `.\tools\run_tests.ps1 -Filter test_rux_2b_multi_source_selection`
- Resultado: **1/14 aprovados** (`B11` compatibilidade RTS já existente), **13/14 falharam** (`B1`–`B10`, `B12`–`B14`), **0 `SuiteErrors`**, **0 avisos**.

### 3.2 Defeitos encontrados durante a transição RED → GREEN e corrigidos
1. **Geometria de projeção isométrica em `test_b3`:** no layout inicial da cena, `WoodTree04` ficou fora do retângulo único de arraste entre `WoodTree01` e `WoodTree02` (4/5 árvores capturadas). `WoodTree03`–`WoodTree05` foram posicionadas dentro da projeção de tela de `WoodTree01`–`WoodTree02`, mantendo `WoodTree06` estritamente fora, permitindo que `test_b3` valide um único arraste contínuo capturando exatamente 5 de 6 árvores.
2. **Acesso tipado a fonte já liberada em `CommunityWorkBoard.close_task()`:** ao encerrar tarefa cuja fonte fora removida com `queue_free()` (`B9`/`B14`), passar `task.source` diretamente para `_unbind_source_signals(sid, source: ResourceSource)` gerou `SCRIPT ERROR`. Corrigido passando `task.source if is_instance_valid(task.source) else null`.
3. **Cast de anel de realce liberado junto com a fonte em `AutonomousGatherInput`:** como o `MeshInstance3D` de realce é filho da fonte, `source.queue_free()` liberava o anel antes de `_remove_highlight()` / `_clear_all_highlights()`. Corrigido armazenando `weakref(mesh_inst)` em `_task_highlights` e validando `is_instance_valid(obj)` antes do `queue_free()`.

### 3.3 Fase GREEN (`683e4c4`) — Suíte RUX-2B e Regressões Focadas
| Verificação | Resultado observado |
|---|---|
| `run_tests.ps1 -Filter test_rux_2b_multi_source_selection` | **14/14 aprovados, 114 asserções**, 0 falhas, 0 `SuiteErrors`, 0 erros de script, 0 avisos (`B1`–`B14`). |
| `run_tests.ps1 -Filter test_rux_2a_auto_resources` | **10/10 aprovados, 166 asserções**, 0 erros/avisos. |
| `run_tests.ps1 -Filter test_rux_1_autonomous_gather` | **7/7 aprovados, 87 asserções**, 0 erros/avisos. |
| `run_tests.ps1 -Filter test_ux_1_contextual_tree` | **3/3 aprovados, 35 asserções**, 0 erros/avisos. |
| `run_tests.ps1 -Filter test_selection_box_math` | **3/3 aprovados, 18 asserções**, 0 erros/avisos. |
| `run_tests.ps1 -Filter test_box_selection` | **7/7 aprovados, 58 asserções**, 0 erros/avisos. |
| `run_tests.ps1 -Filter test_picking_selection` | **9/9 aprovados, 70 asserções**, 0 erros/avisos. |
| `run_tests.ps1 -Filter test_commands` | **5/5 aprovados, 72 asserções**, 0 erros/avisos. |
| `run_tests.ps1 -Filter test_t2_worker_cycle` | **8/8 aprovados, 2.660 asserções**, 0 erros/avisos. |
| `run_tests.ps1 -Filter test_t3_6_2_c4_12_rts_provenance` | **5/5 aprovados, 119 asserções**, 0 erros/avisos. |
| `run_tests.ps1 -Filter test_t3_6_3_b1_4_recovery_dispatch` | **16/16 aprovados, 178 asserções**, 0 erros/avisos. |
| `run_tests.ps1 -Filter test_t3_6_4_cancellation_ui` | **8/8 aprovados, 153 asserções**, 0 erros/avisos. |

### 3.4 Validação Estática, Abertura Gráfica e Regressão Segmentada Completa
| Verificação | Resultado observado |
|---|---|
| `.\tools\validate.ps1` | **APROVADO** — importação headless, **184 scripts** verificados com `--check-only` e boot headless com **0 erros e 0 avisos**. |
| `.\tools\run_game.ps1 -Resolution "1280x720" -QuitAfter 30 -FailOnWarnings -ExtraArgs @("res://tests/visual/rux_2b_multi_source_selection.tscn")` | **APROVADO** — abertura gráfica em `1280×720` (`OpenGL API 3.3.0 - Build 30.0.101.1339 - Compatibility`, `Intel(R) UHD Graphics 620`), 30 quadros limpos, **0 erros e 0 avisos**. |
| `.\tools\run_game.ps1 -Resolution "1920x1080" -QuitAfter 30 -FailOnWarnings -ExtraArgs @("res://tests/visual/rux_2b_multi_source_selection.tscn")` | **APROVADO** — abertura gráfica em `1920×1080` (`OpenGL API 3.3.0 - Build 30.0.101.1339 - Compatibility`, `Intel(R) UHD Graphics 620`), 30 quadros limpos, **0 erros e 0 avisos**. *(Abertura gráfica não substitui homologação visual/jogável do proprietário.)* |
| `.\tools\run_tests.ps1 -Segmented -GroupTimeoutSeconds 240` | **APROVADO** — **20/20 lotes PASS**, **77/77 suítes descobertas e executadas unicamente** (`Duplicates=0`, `Missing=0`), **562/562 testes aprovados**, **27.850 asserções**, **0 falhas, 0 erros de suíte e 0 avisos** (`SumGodotElapsed = 944.621,6 ms`, `TotalWallElapsed = 981.472,8 ms`). |

---

## 4. Evidências de Comportamento e Conservação Econômica (B1–B14)

- **Cenário obrigatório — 5 de 6 árvores (`B3`):** um único arraste iniciado em `WoodTree01` até `WoodTree02` capturou exatamente `WoodTree01`–`WoodTree05` no mesmo `group_id`; os 2 líderes se distribuíram em árvores distintas e seguiram automaticamente pelas marcadas restantes até conclusão; **`WoodTree06` permaneceu com 100% da quantidade inicial, sem tarefa criada e sem qualquer reserva ou coleta**.
- **Pedra e alimentos em seleção múltipla (`B4`, `B5`):** arraste sobre múltiplas rochas e múltiplos arbustos despachou líderes respeitando pesos físicos (`stone = 3`, `food = 1`), entregas reais no acampamento e conservação exata.
- **Distribuição sem concentração e sinal `worker_slot_released` (`B6`):** líderes alocados em fontes distintas; liberação real de vaga em `ResourceSource` emitiu `worker_slot_released` e acordou tarefa em espera sem polling.
- **Continuidade e prioridade manual (`B7`, `B8`):** ao concluir e entregar, o líder assumiu automaticamente a próxima fonte marcada do grupo; ordem manual interrompeu o trabalhador imediatamente sem perda de carga nem reconvocação indevida.
- **Falhas parciais e bloqueio (`B9`, `B12`):** fontes esgotadas, removidas (`queue_free()`) ou inacessíveis em `ClosedEnclosure` não travaram as demais fontes do grupo; tarefa em `BLOCKED_REAUTHORIZATION` permaneceu estritamente inerte mesmo após entrada de um terceiro trabalhador em `Units` e término de ordens de outros trabalhadores.
- **Conservação concorrente multi-recurso (`B13`):** grupos simultâneos de madeira, pedra e alimentos concluíram com `extraído == entregue + carregado` para cada recurso, `validate_provenance() == true` em todos os trabalhadores e zero contaminação cruzada.
- **Ciclo de vida (`B14`):** saída da cena e remoção de fontes desconectaram sinais e limparam anéis de realce sem `SCRIPT ERROR` nem nós órfãos.

---

## 5. Como Abrir a Cena de Avaliação

No worktree `C:\Projetos\Dawn_of_Kin_wt_t3_4_5`:

```powershell
.\tools\run_game.ps1 -Resolution "1280x720" -FailOnWarnings -ExtraArgs @("res://tests/visual/rux_2b_multi_source_selection.tscn")
```

Ou em `1920×1080`:

```powershell
.\tools\run_game.ps1 -Resolution "1920x1080" -FailOnWarnings -ExtraArgs @("res://tests/visual/rux_2b_multi_source_selection.tscn")
```

Ensaios manuais sugeridos (para homologação posterior):
1. Arrastar a caixa de seleção a partir de `WoodTree01` abrangendo `WoodTree01`–`WoodTree05` (deixando `WoodTree06` de fora) e confirmar os dois líderes dividindo as árvores marcadas, continuando para as seguintes após descarga e deixando `WoodTree06` intocada.
2. Usar `Shift + clique esquerdo` em `StoneRock01`, `StoneRock02` e `StoneRock03` (e repetir o clique numa rocha já marcada para confirmar feedback não destrutivo, além de tentar `Shift + clique` num arbusto para confirmar bloqueio de mistura).
3. Arrastar a caixa começando em terreno aberto sobre os dois líderes e confirmar que a seleção RTS de unidades continua intacta, assim como o movimento por clique direito e o cancelamento de arraste com `Esc`.

---

## 6. Limitações Conhecidas e Pendências Preservadas

- **Escopo deliberadamente limitado à RUX-2B:** sem remoção destrutiva / cancelamento / reautorização de tarefas na interface (`P-RUX-6`), sem painel completo de inspeção de tarefas, sem Casa Fundadora / genealogia / `ControlMode`, sem profissões e sem construção com débito imediato.
- **Seleção por caixa de fontes exige início sobre fonte suportada:** arraste iniciado em terreno aberto preserva intencionalmente a seleção RTS de unidades; a caixa de fontes é homogênea ao tipo da fonte de origem.
- **Benchmark de $p95$ em `1920×1080` na Intel UHD 620:** não medido nesta entrega isolada (executado smoke gráfico de 30 quadros em `1280×720` e `1920×1080`).
- **Pendências preservadas intactas:**
  - 3 testes manuais UX-1: **pendentes**.
  - Homologação jogável RUX-1: **pendente**.
  - Homologação jogável RUX-2A: **pendente**.
  - Homologação jogável RUX-2B: **pendente**.
  - Retestes D3-04 e D3-07 da T3.6.4-R1: **pendentes**.
  - Decisões abertas da RUX-0 (`P-RUX-1` reembolso de construções, `P-RUX-2` retorno definitivo pós-ordem pessoal, `P-RUX-3` cônjuges externos, `P-RUX-4` ordem de débito entre pilhas e depósitos, `P-RUX-6` interface definitiva de cancelamento/reautorização de coleta).
