# RUX-2A — Relatório Técnico da Candidata de Coleta Automática para Madeira, Pedra e Alimentos

- **Status:** **IMPLEMENTADA E TESTADA AUTOMATICAMENTE (HEADLESS + SMOKE GRÁFICO)** — **homologação visual/jogável pelo proprietário PENDENTE**.
- **Branch candidata:** `feat/rux-2a-auto-resource-types`
- **Base:** `feat/rux-1-autonomous-gather` em `30bda488640e5fb5fdaea74053463b3580e7165f` ([RUX_1_autonomous_gather_candidate_report.md](RUX_1_autonomous_gather_candidate_report.md))
- **Commit RED (testes A1–A10 + cena + assinaturas mínimas):** `7ab1a00ac80afe4c7e8fcf1478fd6f02e146daff`
- **Commit GREEN (generalização + prevenção de bloqueio por exclusão manual):** `67295ae6935d28066c813e1f91596e658efba601`
- **Engine / ambiente verificado:** Godot `4.7.2.stable.official.ed1daf0bf`, `gl_compatibility`, `Jolt Physics`, Intel(R) UHD Graphics 620.

---

## 1. Arquivos Criados e Alterados

### Criados
- [tests/visual/rux_2a_auto_resources.tscn](../../tests/visual/rux_2a_auto_resources.tscn) — cena de avaliação isolada herdando `src/main/main.tscn`, com `AutonomousGatherInput` configurado para `["wood", "stone", "food"]`.
- [tests/integration/test_rux_2a_auto_resources.gd](../../tests/integration/test_rux_2a_auto_resources.gd) — suíte de integração real em `SubViewport` cobrindo A1–A10 (10 testes, 166 asserções).
- [docs/testing/RUX_2A_auto_resources_candidate_report.md](RUX_2A_auto_resources_candidate_report.md) — este relatório.

### Alterados (generalização dos componentes compartilhados da RUX-1, sem duplicação)
- [src/rts/work_task.gd](../../src/rts/work_task.gd) — estendido `Kind` (`GATHER_WOOD`, `GATHER_STONE`, `GATHER_FOOD`), adicionados `resource_id`, `resource_definition`, `State.BLOCKED_REAUTHORIZATION`, `REASON_ALL_WORKERS_EXCLUDED`, `is_blocked_reauthorization()` e `kind_from_resource_id()`.
- [src/rts/community_work_board.gd](../../src/rts/community_work_board.gd) — adicionados `SUPPORTED_RESOURCE_IDS` (`wood`, `stone`, `food`), `register_gather_task(source)` idempotente por identidade real de fonte, `get_blocked_tasks()` separado de `get_pending_tasks()`, preservando `register_wood_gather_task(source)` para compatibilidade integral com RUX-1.
- [src/rts/community_task_dispatcher.gd](../../src/rts/community_task_dispatcher.gd) — único distribuidor unificado orientado a eventos para os três recursos, com detecção explícita de bloqueio por exclusão manual (`task_blocked`, estado `BLOCKED_REAUTHORIZATION`, feedback `"Tarefa aguardando nova autorização."`) sem polling nem tentativas infinitas, além de mensagens específicas por recurso.
- [src/rts/autonomous_gather_input.gd](../../src/rts/autonomous_gather_input.gd) — adicionado `@export var supported_resource_ids: PackedStringArray = PackedStringArray(["wood"])` (mantendo `rux_1_auto_gather.tscn` estritamente em madeira sem alterá-lo), mensagens contextualizadas por tipo e cache de materiais compartilhados (até 3 materiais `unshaded` + 1 `ArrayMesh`, `cast_shadow = OFF`, sem `_process`).

### Preservados intactos
`src/main/main.tscn`, `src/main/main.gd`, `tests/visual/ux_1_tree.tscn`, `tests/visual/rux_1_auto_gather.tscn`, scripts UX-1 (`tree_work_input.gd`, `tree_work_menu.gd`), `docs/Dawn_of_Kin_GDD.md`, `AGENTS.md`, `main` (`25e0a20`), `design/rux-0-autonomous-work-family` (`e9d502e`) e `feat/rux-1-autonomous-gather` (`30bda48`).

---

## 2. Decisões Arquiteturais

1. **Distribuidor único e economia única:** nenhuma economia paralela nem distribuidores separados foram criados. Madeira (`unit_weight = 2`), pedra (`unit_weight = 3`) e alimentos (`unit_weight = 1`) trafegam pelo mesmo `CommunityWorkBoard` → `CommunityTaskDispatcher` → `CommandController.command_units_to_gather()` → `GatherResourceOrder` → `DeliverToCampOrder` → `SettlementInventory`.
2. **Prevenção de bloqueio silencioso por exclusão manual (`State.BLOCKED_REAUTHORIZATION`):**
   - `PENDING_WORKERS` continua representando espera temporária (trabalhadores ocupados, navegação sincronizando, transação econômica ativa ou vaga cheia).
   - Quando nenhum trabalhador está elegível, não há motivo temporário nem inacessibilidade, e `excluded_count > 0` (todos os trabalhadores disponíveis foram excluídos por sobreposição manual), a tarefa transita uma única vez para `State.BLOCKED_REAUTHORIZATION` com `last_reason = "all_workers_manually_excluded"` e emite `"Tarefa aguardando nova autorização."`.
   - `get_pending_tasks()` não inclui tarefas bloqueadas; `_on_board_task_updated()` ignora re-enfileiramento em `BLOCKED_REAUTHORIZATION`, impedindo loops de retentativa e polling.
   - Cliques repetidos na fonte bloqueada preservam idempotência, repetem o aviso claro e jamais reconvocam silenciosamente os trabalhadores excluídos (mantendo a futura interface de cancelamento/reautorização em aberto sob `P-RUX-6`).
3. **Isolamento de cena por exportação configurável:** o default `supported_resource_ids = ["wood"]` em `AutonomousGatherInput` permite evoluir o adaptador compartilhado sem alterar `tests/visual/rux_1_auto_gather.tscn` nem quebrar o escopo madeira-apenas da RUX-1.

---

## 3. Evidências RED e GREEN (Godot 4.7.2)

### 3.1 Fase RED (`7ab1a00`)
- `.\tools\run_tests.ps1 -Filter test_rux_2a_auto_resources -TimeoutSeconds 180`
- Resultado: **2/10 aprovados** (`A1` madeira da RUX-1 e `A10` controles/cenas anteriores), **8/10 falharam** (`A2`–`A9`, `74` asserções, `17` falhas comportamentais esperadas, `0` erros de suíte, `0` avisos).

### 3.2 Fase GREEN (`67295ae`) — Suíte RUX-2A e Regressões Focadas
| Verificação | Resultado observado |
|---|---|
| `run_tests.ps1 -Filter test_rux_2a_auto_resources` | **10/10 aprovados, 166 asserções**, 0 erros/avisos (A1–A10). |
| `run_tests.ps1 -Filter test_rux_1_autonomous_gather` | **7/7 aprovados, 87 asserções**, 0 erros/avisos. |
| `run_tests.ps1 -Filter test_ux_1_contextual_tree` | **3/3 aprovados, 35 asserções**, 0 erros/avisos. |
| `run_tests.ps1 -Filter test_commands` | **5/5 aprovados, 72 asserções**, 0 erros/avisos. |
| `run_tests.ps1 -Filter test_picking_selection` | **9/9 aprovados, 70 asserções**, 0 erros/avisos. |
| `run_tests.ps1 -Filter test_t2_worker_cycle` | **8/8 aprovados, 2.663 asserções**, 0 erros/avisos. |
| `run_tests.ps1 -Filter test_t3_6_2_c4_12_rts_provenance` | **5/5 aprovados, 119 asserções**, 0 erros/avisos. |
| `run_tests.ps1 -Filter test_t3_6_3_b1_4_recovery_dispatch` | **16/16 aprovados, 178 asserções**, 0 erros/avisos. |
| `run_tests.ps1 -Filter test_t3_6_4_cancellation_ui` | **8/8 aprovados, 153 asserções**, 0 erros/avisos. |

### 3.3 Validação Estática, Abertura Gráfica e Regressão Segmentada Completa
| Verificação | Resultado observado |
|---|---|
| `.\tools\validate.ps1` | **APROVADO** — importação headless, **183 scripts** verificados com `--check-only` e boot headless com **0 erros e 0 avisos**. |
| `.\tools\run_game.ps1 -Resolution "1280x720" -QuitAfter 30 -FailOnWarnings -ExtraArgs @("res://tests/visual/rux_2a_auto_resources.tscn")` | **APROVADO** — abertura gráfica em `1280×720` (`OpenGL API 3.3.0 - Compatibility`, `Intel(R) UHD Graphics 620`), 30 quadros limpos, **0 erros e 0 avisos**. *(Abertura gráfica não substitui homologação visual do proprietário.)* |
| `.\tools\run_tests.ps1 -Segmented -GroupTimeoutSeconds 240` | **APROVADO** — **19/19 lotes PASS**, **76/76 suítes descobertas e executadas unicamente** (0 faltantes, 0 duplicatas), **548/548 testes aprovados**, **27.748 asserções**, **0 falhas, 0 erros de suíte e 0 avisos**. |

---

## 4. Conservação Física por Recurso e Situações de Bloqueio

### Conservação verificada (A1, A2, A3, A6, A9)
- **Madeira (`wood`, peso `2`):** entrou em `UnitCarryLoad` com peso exato `qty * 2` e proveniência `FREE_GATHERED` antes do crédito ao estoque; fechou `extraída == entregue + carregada` tanto em conclusão integral (`4 == 4 + 0`) quanto sob interrupção manual com colega assumindo.
- **Pedra (`stone`, peso `3`):** entrou em `UnitCarryLoad` com peso exato `qty * 3` e proveniência `FREE_GATHERED` antes do crédito ao estoque; fechou `extraída == entregue + carregada` (`2 == 2 + 0`) e sob interrupção manual em transporte.
- **Alimentos (`food`, peso `1`):** entrou em `UnitCarryLoad` com peso exato `qty * 1` e proveniência `FREE_GATHERED` antes do crédito ao estoque; fechou `extraída == entregue + carregada` (`4 == 4 + 0`) e sob interrupção manual em transporte.
- **Execução combinada (A9):** os três tipos registrados juntos foram concluídos pelos dois líderes sem contaminação cruzada e com `validate_provenance() == true` em todas as unidades.

### Situações de bloqueio verificadas (A7, A8)
- **Fonte esgotada:** rocha e arbusto esgotados recusados na entrada sem criar tarefa ou ordem.
- **Fonte inacessível:** rocha em `ClosedEnclosure` fechada como `FAILED ("source_unreachable")` sem loops; distribuidor permanece saudável para novas tarefas válidas.
- **Fonte removida em espera:** arbusto liberado (`queue_free()`) enquanto ambos os líderes estavam ocupados fechou a tarefa como `FAILED ("invalid_source")` com desconexão limpa de sinais.
- **Todos os trabalhadores excluídos manualmente (A8):** após interrupção manual de ambos os líderes na mesma rocha, a tarefa entrou em `BLOCKED_REAUTHORIZATION ("all_workers_manually_excluded")`, exibiu `"Tarefa aguardando nova autorização."`, manteve ambos os líderes `IDLE`, manteve zero polling e permaneceu idempotente em cliques subsequentes.

---

## 5. Como Abrir a Cena de Avaliação

No worktree `C:\Projetos\Dawn_of_Kin_wt_t3_4_5`:

```powershell
.\tools\run_game.ps1 -Resolution "1280x720" -FailOnWarnings -ExtraArgs @("res://tests/visual/rux_2a_auto_resources.tscn")
```

Ensaios manuais sugeridos (para homologação posterior):
1. Clicar individualmente em `WoodTree01`, `StoneRock01` e `FoodBush01` e confirmar despacho automático, realce por cor, carga física na mochila e descarga no acampamento.
2. Repetir cliques na mesma rocha/arbusto e confirmar ausência de duplicação.
3. Interromper o primeiro líder com movimento manual (clique direito) e observar o segundo assumindo; interromper o segundo também e observar `"Tarefa aguardando nova autorização."` sem reconvocação automática.

---

## 6. Limitações Conhecidas e Pendências Preservadas

- **Escopo deliberadamente limitado à RUX-2A:** uma fonte por tarefa (sem seleção múltipla, Shift ou caixa sobre fontes, sem inspeção/cancelamento definitivo de tarefas, sem `ControlMode` definitivo da Casa Fundadora e sem construção com débito imediato).
- **Tarefa em `BLOCKED_REAUTHORIZATION`:** permanece claramente marcada e inerte sem polling; a ação de interface para cancelar ou reautorizar deliberadamente depende de `P-RUX-6` (próximo incremento).
- **Benchmark de $p95$ em `1920×1080` na Intel UHD 620:** não medido nesta entrega isolada (executado smoke gráfico em `1280×720`).
- **Pendências preservadas intactas:**
  - 3 testes manuais UX-1: **pendentes**.
  - Homologação jogável RUX-1: **pendente**.
  - Homologação jogável RUX-2A: **pendente**.
  - Retestes D3-04 e D3-07 da T3.6.4-R1: **pendentes**.
  - Decisões abertas da RUX-0 (`P-RUX-1` reembolso de construções, `P-RUX-2` retorno definitivo pós-ordem pessoal, `P-RUX-3` cônjuges externos, `P-RUX-4` ordem de débito entre pilhas e depósitos, `P-RUX-6` interface definitiva de cancelamento/reautorização de coleta).
