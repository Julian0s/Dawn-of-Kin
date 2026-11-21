# RUX-1 — Relatório Técnico da Candidata de Coleta Comunitária Automática

- **Status:** **IMPLEMENTADA E TESTADA AUTOMATICAMENTE (HEADLESS + SMOKE GRÁFICO)** — **homologação visual/jogável pelo proprietário PENDENTE**.
- **Branch candidata:** `feat/rux-1-autonomous-gather`
- **Base:** `design/rux-0-autonomous-work-family` em `e9d502ecafe0737bc7b04b0b8388f92400282801` ([RUX_0_autonomous_work_family_PROPOSAL.md](../architecture/RUX_0_autonomous_work_family_PROPOSAL.md))
- **Commit RED (testes + cascas mínimas):** `178fd2add124d79150241b017c8ef8771dda5fb5`
- **Commit GREEN (implementação + R7):** `0ec38393af9f261b62a81245208b8d51d1e7128c`
- **Engine / ambiente verificado:** Godot `4.7.2.stable.official.ed1daf0bf`, `gl_compatibility`, `Jolt Physics`, Intel(R) UHD Graphics 620.

---

## 1. Escopo Entregue e Preservações

A candidata entrega o primeiro protótipo isolado de coleta comunitária automática para **uma fonte de madeira** com os **dois líderes**, sem menu obrigatório de escolha de equipe:

- **Arquivos criados:**
  - [src/rts/work_task.gd](../../src/rts/work_task.gd) — registro mínimo de tarefa comunitária (`GATHER_WOOD`, estados `PENDING_WORKERS` / `IN_PROGRESS` / `COMPLETED` / `FAILED` / `CANCELLED`, lista de exclusão por sobreposição manual).
  - [src/rts/community_work_board.gd](../../src/rts/community_work_board.gd) — quadro regional orientado a eventos (`set_process(false)`, `set_physics_process(false)`), idempotente por `ResourceSource`, com limpeza automática em `depleted` e `tree_exited`.
  - [src/rts/community_task_dispatcher.gd](../../src/rts/community_task_dispatcher.gd) — distribuidor reativo orientado a sinais (`task_registered`, `task_updated`, `task_closed`, `order_finished`, `state_changed`, `tree_exited`, `navigation_ready`, `inventory_changed`), com coalescência via `call_deferred("_flush_dispatch")` e zero polling por quadro.
  - [src/rts/autonomous_gather_input.gd](../../src/rts/autonomous_gather_input.gd) — adaptador de entrada isolado (herda `RtsInputController`), com realce leve compartilhado (1 `ArrayMesh` + 1 `StandardMaterial3D` `unshaded`, `cast_shadow = OFF`, sem `_process`).
  - [src/ui/autonomous_gather_feedback.gd](../../src/ui/autonomous_gather_feedback.gd) — banner discreto não bloqueante (`MOUSE_FILTER_IGNORE`, `Timer` one-shot, sem polling).
  - [tests/visual/rux_1_auto_gather.tscn](../../tests/visual/rux_1_auto_gather.tscn) — cena de avaliação isolada herdando `src/main/main.tscn`.
  - [tests/integration/test_rux_1_autonomous_gather.gd](../../tests/integration/test_rux_1_autonomous_gather.gd) — suíte de integração real em `SubViewport` (cenários R1–R7).
- **Arquivo alterado:**
  - [src/rts/command_controller.gd](../../src/rts/command_controller.gd) — extração da entrada explícita `command_units_to_gather(source, units, show_marker)` compartilhando `_execute_gather_resource()` com o clique direito antigo, sem alterar `SelectionManager` como efeito colateral.
- **Intactos:** `src/main/main.tscn`, `src/main/main.gd`, `tests/visual/ux_1_tree.tscn`, `src/rts/tree_work_input.gd`, `src/ui/tree_work_menu.gd`, `docs/Dawn_of_Kin_GDD.md`, `AGENTS.md` e o clique direito de trabalho nas cenas existentes.

---

## 2. Decisões Técnicas Adotadas

1. **Zero segunda autoridade econômica:** `CommunityWorkBoard` e `CommunityTaskDispatcher` não mantêm saldos nem transferem madeira. Todo despacho passa por `CommandController.command_units_to_gather()` → `GatherResourceOrder` → `GatherTransferSession` → `DeliverToCampOrder` → `SettlementInventory`.
2. **Coalescência `call_deferred("_flush_dispatch")` contra corrida em `Unit.issue_order()`:** como `Unit.issue_order()` emite `order_finished(previous_order)` com `REASON_REPLACED` **antes** de atribuir a nova ordem manual, o despacho exclusivamente diferido garante que o distribuidor jamais sequestre uma ordem manual em instalação.
3. **Proteção contra retomada indevida sem antecipar `ControlMode` (RUX-3):** quando uma ordem de tarefa comunitária é substituída por ordem manual (`REASON_REPLACED` / `REASON_CANCELLED`), o `instance_id` do trabalhador é adicionado a `task.excluded_unit_ids` para que aquela mesma tarefa não puxe o trabalhador de volta ao concluir a ordem manual, enquanto trabalhadores ocupados **antes** da criação da tarefa (R4) assumem automaticamente assim que ficam livres.
4. **Elegibilidade rigorosa e busca preguiçosa de acesso:** verifica ordem ativa, estado `IDLE`, locks transacionais, capacidade efetiva, `validate_provenance()`, ausência de lotes não-livres (`SITE_RESERVED` / `CANCEL_*`), domínio regional (`region_id`, `World3D`, `validate_unit_identity_in_domain_readonly`), vaga na fonte e navegação válida via `GatherSlotPlanner`, parando no líder livre mais próximo com caminho alcançável.
5. **Segurança em fontes inválidas:** fonte esgotada é recusada imediatamente; fonte inacessível sem trabalhadores temporariamente ocupados fecha como `FAILED ("source_unreachable")` sem ciclos infinitos; fonte removida durante espera fecha como `FAILED ("invalid_source")` desconectando todos os sinais.

---

## 3. Evidências de Execução (Godot 4.7.2)

### 3.1 Fase RED (`178fd2a`)
- `.\tools\run_tests.ps1 -Filter test_rux_1_autonomous_gather -TimeoutSeconds 120`
- Resultado: **0/6 aprovados, 6/6 falharam** (`26` asserções, `0` erros de suíte, `0` avisos) — confirmando falha comportamental real nos cenários R1–R6 antes da implementação.

### 3.2 Fase GREEN (`0ec3839`) — Suíte RUX-1 e Regressões Focadas
| Verificação | Resultado observado |
|---|---|
| `run_tests.ps1 -Filter test_rux_1_autonomous_gather` | **7/7 aprovados, 87 asserções**, 0 erros/avisos (R1–R6 + R7 de preservação de seleção e bloqueio de carga `SITE_RESERVED`). |
| `run_tests.ps1 -Filter test_ux_1_contextual_tree` | **3/3 aprovados, 35 asserções**, 0 erros/avisos. |
| `run_tests.ps1 -Filter test_commands` | **5/5 aprovados, 72 asserções**, 0 erros/avisos. |
| `run_tests.ps1 -Filter test_picking_selection` | **9/9 aprovados, 70 asserções**, 0 erros/avisos. |
| `run_tests.ps1 -Filter test_t2_worker_cycle` | **8/8 aprovados, 2.660 asserções**, 0 erros/avisos. |
| `run_tests.ps1 -Filter test_t3_6_2_c4_12_rts_provenance` | **5/5 aprovados, 119 asserções**, 0 erros/avisos. |
| `run_tests.ps1 -Filter test_t3_6_3_b1_4_recovery_dispatch` | **16/16 aprovados, 178 asserções**, 0 erros/avisos. |
| `run_tests.ps1 -Filter test_t3_6_4_cancellation_ui` | **8/8 aprovados, 153 asserções**, 0 erros/avisos. |

### 3.3 Validação Estática, Abertura Gráfica e Regressão Segmentada Completa
| Verificação | Resultado observado |
|---|---|
| `.\tools\validate.ps1` | **APROVADO** — importação headless, checagem `--check-only` dos **182 scripts** e boot headless da `MainScene` com **0 erros e 0 avisos**. |
| `.\tools\run_game.ps1 -Resolution "1280x720" -QuitAfter 30 -FailOnWarnings -ExtraArgs @("res://tests/visual/rux_1_auto_gather.tscn")` | **APROVADO** — abertura gráfica real em `1280×720` (`OpenGL API 3.3.0 - Compatibility`, `Intel(R) UHD Graphics 620`), encerramento limpo após 30 quadros, **0 erros e 0 avisos**. |
| `.\tools\run_tests.ps1 -Segmented -GroupTimeoutSeconds 240` | **APROVADO** — **19/19 lotes PASS**, **75/75 suítes descobertas e executadas unicamente** (0 faltantes, 0 duplicatas), **538/538 testes aprovados**, **27.572 asserções**, **0 falhas, 0 erros de suíte e 0 avisos**. |

### 3.4 Conservação de Recursos Comprovada
- **R2 (`test_r2_physical_extraction_carry_deposit_and_provenance_conservation`):** madeira entrou na mochila (`FREE_GATHERED`, `validate_provenance() == true`) enquanto o estoque permanecia inalterado antes da chegada ao acampamento; após a descarga final, `delivered == initial_wood (4)`, `remaining == 0`, `still_carried == 0`, `WoodTree02` inalterada e tarefa concluída como `COMPLETED`.
- **R5 (`test_r5_manual_order_protection_and_cargo_conservation`):** interrupção por `MoveOrder` manual durante coleta manteve exatamente a madeira carregada na mochila (`validate_provenance() == true`), liberou a vaga na árvore e conservou `initial_wood - remaining == delivered + carried`.

---

## 4. Como Experimentar a Cena Isolada (Homologação Posterior)

No worktree `C:\Projetos\Dawn_of_Kin_wt_t3_4_5`:

```powershell
.\tools\run_game.ps1 -Resolution "1280x720" -FailOnWarnings -ExtraArgs @("res://tests/visual/rux_1_auto_gather.tscn")
```

Ensaios sugeridos para quando o proprietário desejar homologar visualmente:
1. **Clique único na árvore:** clicar com o botão esquerdo em `WoodTree01` sem selecionar nenhum líder; verificar destaque verde no chão, feedback discreto no topo, deslocamento automático do líder mais próximo (`LeaderB`), carga na mochila e descarga no acampamento, com `WoodTree02` intacta.
2. **Idempotência:** clicar várias vezes na mesma árvore já marcada; verificar mensagem `"Tarefa já registrada para esta árvore."` sem criar segunda tarefa ou enviar o outro líder.
3. **Ambos ocupados → liberação:** mover os dois líderes manualmente e, durante a caminhada, clicar na árvore; observar `"Aguardando trabalhador disponível."` e início automático assim que o primeiro concluir a marcha.
4. **Ordem manual durante coleta:** enquanto o líder corta/carrega madeira, selecioná-lo e mover com botão direito para terreno livre; confirmar obediência imediata, preservação da carga na mochila e ausência de retomada automática indevida.

---

## 5. Limitações Conhecidas e Pendências Preservadas

- **Escopo deliberadamente limitado à RUX-1:** suporta apenas **1 árvore (`wood`) por clique** e 1 trabalhador por tarefa; sem rochas, arbustos, seleção múltipla por Shift/caixa, inspeção/cancelamento de tarefa (RUX-2), `ControlMode` definitivo da Casa Fundadora (RUX-3) ou construção com débito imediato (RUX-4).
- **Retirada manual de trabalhador sem nova tentativa na mesma tarefa:** se ambos os líderes forem interrompidos manualmente enquanto atribuídos à mesma tarefa de árvore, ambos ficam em `excluded_unit_ids` dessa tarefa até o cancelamento/inspeção chegar na RUX-2.
- **Benchmark gráfico completo na Intel UHD 620** (medição de $p95$ em `1920×1080`): não executado nesta etapa isolada (apenas abertura gráfica em `1280×720`).
- **Pendências preservadas intactas (sem decisão inventada):**
  - 3 testes manuais da UX-1: **pendentes**.
  - Retestes manuais D3-04 e D3-07 da T3.6.4-R1: **pendentes**.
  - Decisões abertas da RUX-0 (`P-RUX-1`, `P-RUX-2`, `P-RUX-3`, `P-RUX-4`, `P-RUX-6`): **pendentes de aprovação do proprietário**.
