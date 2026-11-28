# Dawn of Kin — Relatório Técnico da Candidata `R-03B B3`

**Status normativo:** `CANDIDATA TÉCNICA B3 — AGUARDANDO AUDITORIA INDEPENDENTE — NÃO HOMOLOGADA`  
**Incremento:** `R-03B B3 — Espera Pessoal, Retorno Automático e Reconciliação Comunitária`  
**Data de geração:** `2026-11-27`  
**Branch candidata:** `feat/r-03b-founding-house-control-mode`  
**Base canônica homologada (`B2-R3`):** `4801a6dd95011e865c9eab3be68a3a713c417284`  
**Worktree candidato:** `C:\Projetos\Dawn_of_Kin_wt_r_03b`  
**Diretório de evidências externas:** `C:\Projetos\Backups\Dawn_of_Kin_Archive_Local\evidencias\R-03B\B3\`  
**Próxima etapa (`B4`):** `PLANEJADA — NÃO AUTORIZADA / BLOQUEADA` (aceite humano, campanha de desempenho e escolha definitiva do intervalo `D-05` **não executados** nesta etapa).

---

## 1. Identificação, Escopo Autorizado e Não-Escopo

A etapa `R-03B B3` foi executada sob autorização expressa do proprietário após homologação definitiva da `B2-R3` (`4801a6dd95011e865c9eab3be68a3a713c417284`), implementando estritamente:

1. Quarto estado de autoridade `UnitControlState.ControlMode.PERSONAL_POST_MOVE_WAIT = 3`.
2. Temporizador pausável nativo `D-05` sob demanda (lazy) em `Unit` (`Timer` com `one_shot = true`, `process_mode = Node.PROCESS_MODE_PAUSABLE`, `ignore_time_scale = false`), nunca instanciado para unidades `COMMUNITY` nem na inicialização da `MainScene`, com identidade imutável de espera `(event_token, event_revision)` e parâmetro experimental configurável `personal_post_move_wait_sec` (opções experimentais `[3.0, 8.0, 15.0] s`; padrão intermediário provisório `8.0 s`, **não definitivo**; `0.0 s` como configuração técnica determinística de testes).
3. Transições `T6a` (apenas `MoveOrder` + `PERSONAL` + `SUCCEEDED` + `wait > 0` + elegibilidade pessoal + nó válido na árvore — cobrindo conclusão assíncrona em `_finalize_order_completion()` e conclusão síncrona em `_install_admitted_order()` Etapa 4), `T6b`, `T7`, `T8`, `T9`, `T0` e `T1c`.
4. Retorno automático comunitário conforme `B0-Q05 B` (incluindo retorno permitido à mesma tarefa ainda autorizada, preservando `CutAuthorization`, sem nunca reativar `CANCELLED` nem desbloquear `BLOCKED_REAUTHORIZATION`), consumindo estritamente o contrato de dois eventos ratificado em `B2-R2` (`Unit.order_finished(order)` + `Unit.order_interruption_cause_committed(order, cause)`).
5. Classificação estrita de elegibilidade em 4 categorias no `CommunityTaskDispatcher` (incompatibilidade estrutural de unidade/tarefa antes de exclusão manual `manually_overridden`, e esta antes de indisponibilidade temporária `personal_control_active`/`busy`, preservando `D4-R2 A02-02` e o desempenho da busca em lote).
6. Recuperação econômica explícita durante espera pessoal (`T1c`), recusando recuperação automática (`explicit = false`) e chamadas forjadas fora de `CancellationRecoveryDispatcher.assign()`, preservando temporizador e `entry.manual == true` inviolável antes, durante e após a expiração de `D-05`.
7. Rótulos discretos orientados a eventos na HUD mínima (`SelectedUnitPanel` + `HudFormatter`, conforme `B0-Q07 A` / `B0-A05`): `"Trabalho comunitário"`, `"Ordem pessoal"`, `"Aguardando retorno"`, `"Trabalho comunitário · Recuperação"` e `"Morador — somente leitura"`, com `set_process(false)` e **zero cronômetro regressivo, segundos restantes ou barra de progresso de espera**.
8. Reconciliação das suítes históricas e da `B2` diretamente impactadas por `B0-Q05 B` e pela espera `D-05` sem perda de garantias.

**Fora de escopo (preservado intacto):**
- Sem aceite humano (`B4`), sem campanha completa de desempenho (`B4`), sem escolha definitiva da duração de `D-05` (`3 / 8 / 15 s`), sem menu de configurações, sem ativação de `use_d2_2_hud = true` (reservada à `R-05B`), sem alteração de `develop`, `main`, tags ou documentos canônicos (`AGENTS.md`, `GDD`, `ROADMAP_MESTRE.md`, plano `B0-R2`).

---

## 2. Proteções Canônicas, Flags da `MainScene` e Ancestralidade Git

| Verificação | Estado na Candidata `B3` | Evidência |
|---|---|---|
| `use_provenance_economy` na `MainScene` | `true` (preservado) | `11_smoke/smoke_summary.json` (`S01`) |
| `automatic_cancellation_recovery` na `MainScene` | `true` (preservado) | `11_smoke/smoke_summary.json` (`S02`) |
| `use_d2_2_hud` na `MainScene` | `false` (preservado até `R-05B`) | `11_smoke/smoke_summary.json` (`S03`) |
| `develop` protegida (`C:\Projetos\Dawn of Kin`) | `94c718024359dc7ff8360949313969b3ceaf9776` (intacta) | `00_git_baseline/git_baseline.txt`, `13_git_final/git_final_state.txt` |
| `main` protegida | `25e0a20f1d6a2f10a9e059afe69759fbe263db4a` (intacta) | `00_git_baseline/git_baseline.txt`, `13_git_final/git_final_state.txt` |
| `C:\Projetos\Dawn of Kin\project.godot` | SHA-256 `AEEFDA2810DA5C4EDFA9BF5F2A47A5841F8597238C8DAB4C2E202FAF70307613` (intacto) | `00_git_baseline/git_baseline.txt`, `13_git_final/git_final_state.txt` |
| Manifesto `B2-R3` anterior | SHA-256 `895763EFBA7186446BF608CE3FA3AB2A42E2C2E26CC6E08AF444ADE29E318F85` (intacto) | `00_git_baseline/git_baseline.txt`, `13_git_final/git_final_state.txt` |
| `docs/design/` `.import` | `0` arquivos `.import` | `validate.log` / inspeção final |

---

## 3. Resumo da Implementação por Arquivo de Produção

| Arquivo | Alteração Cirúrgica Realizada |
|---|---|
| `src/units/unit_control_state.gd` | Adição de `ControlMode.PERSONAL_POST_MOVE_WAIT = 3` (mantendo `0..2` intactos), `is_personal_post_move_wait()`, `is_personal_controlled()` e mapeamento em `get_mode_name()`. |
| `src/units/unit.gd` | Export experimental `personal_post_move_wait_sec = 8.0` (constantes `EXPERIMENTAL_POST_MOVE_WAIT_OPTIONS_SEC = [3.0, 8.0, 15.0]`, clamp de valores negativos/não-finitos afetando apenas futuras esperas); temporizador nativo lazy `_wait_timer` (`one_shot`, `PROCESS_MODE_PAUSABLE`, `ignore_time_scale = false`); identidade imutável `(event_token, event_revision)` e 9 guardas em `_on_personal_wait_timeout()`; estabilização `T6a`/`T6b` unificada em `_finalize_order_completion()` e `_install_admitted_order()` Etapa 4; cancelamento de espera em Etapa 3 (`T8`/`T1c`), `_perform_administrative_cancel()` (`T9`), `_exit_tree()` e `_reconcile_active_order_after_definition_change()`; admissão `T1c` estrita (`explicit == true`) em `issue_recovery_order()`. |
| `src/rts/community_task_dispatcher.gd` | Conexão/desconexão de `Unit.order_interruption_cause_committed`; tabela `_pending_interruption_classifications` correlacionada por `order.get_instance_id()`, `_board`, `_config_epoch` e `task.tree_cut_authorization` (`EV01`–`EV08`); classificação `B0-Q05 B` (`PERSONAL_MOVE` não exclui e preserva `CutAuthorization`; `PERSONAL_OTHER` e `ADMIN_CANCEL` real excluem; remoção estrutural / perda de permissão / cancelamento cooperativo / `SYSTEM_RECOVERY` não criam exclusão manual permanente); purga em `teardown()`, `configure()`, `_unbind_all()`, `_handle_unit_unavailable()`, `_on_board_task_updated()` e `_on_board_task_closed()`; classificação estrita em 4 categorias (`_check_unit_structural_eligibility`, `_check_task_structural_eligibility`, `manually_overridden`, `_check_unit_temporary_eligibility` incluindo `PERSONAL_POST_MOVE_WAIT`, `no_worker_slot`). |
| `src/ui/hud_formatter.gd` | Extensão de `format_unit_inspection_meta()` com rótulos discretos para Casa Fundadora (`Trabalho comunitário`, `Ordem pessoal`, `Aguardando retorno`, `Trabalho comunitário · Recuperação`) preservando integralmente `"Morador — somente leitura"` para `COMMUNITY` e garantindo zero dígitos/cronômetro. |
| `src/ui/selected_unit_panel.gd` | Conexão/desconexão de `unit.control_mode_changed` (`_on_unit_control_mode_changed`) em `_bind_single_unit()` / `_unbind_tracked_unit()` e `is_bound_to_unit()`, mantendo `set_process(false)` e `set_physics_process(false)` (zero polling). |
| `src/ui/selected_unit_panel.tscn` | Compactação vertical cirúrgica (~20 px economizados em margens/separações/tipografia) garantindo legibilidade da linha discreta de controle e zero sobreposição com `BuildingInspectorPanel` em `1280×720` (evidenciado por `test_t3_6_4_cancellation_ui` e capturas GPU). |
| `src/main/main.gd` | Export experimental `experimental_personal_post_move_wait_sec = 8.0` e helper `set_experimental_personal_post_move_wait_sec(seconds)` propagando a configuração provisória às unidades da `MainScene` para futura avaliação experimental `3 / 8 / 15 s` na `B4`. |

---

## 4. Contrato de Dois Eventos Ratificado (`B2-R2`) e Correlação `EV01`–`EV08`

O contrato ratificado em `B2-R2` foi preservado integralmente sem restaurar marcação prematura de `InterruptionCause` antes do Check Point 2:

- **`EV01` (Correlação normal em `MoveOrder`):** `order_finished(order)` limpa `task.assigned_unit`/`assigned_order` imediatamente com `cause == NONE` e registra correlação pendente (`count == 1`); `order_interruption_cause_committed(order, PERSONAL_MOVE)` consome o registro (`count == 0`), mantém `excluded_unit_ids` vazio e preserva `CutAuthorization`.
- **`EV02` (Sucessor reentrante `GatherResourceOrder` sobrepondo `MoveOrder`):** `order_interruption_cause_committed(order, PERSONAL_OTHER)` exclui `uid` corretamente apesar da tentativa externa `MoveOrder`.
- **`EV03` (Rejeição tardia Check Point 1/2 de `MoveOrder`):** `Unit` compromete `ADMIN_CANCEL`, tratado como `ADMIN_CANCEL` (exclui `uid`), jamais como `PERSONAL_MOVE`.
- **`EV04` (`cancel_current_order` / `issue_order(null)` vs saída estrutural):** `ADMIN_CANCEL` administrativo exclui `uid`; `REASON_UNIT_EXITED`, `definition_permission_changed` e `REASON_COMMUNITY_WORK_CANCELLED` não geram exclusão permanente.
- **`EV05` (Tarefa fechada ou reautorizada antes de `order_interruption_cause_committed`):** purga imediata no fechamento/reautorização e validação de `task.is_active()` + `tree_cut_authorization` impedem mutação de tarefa fechada ou sucessora.
- **`EV06` (`teardown()` / `configure()` antes do segundo evento):** `_unbind_all()` limpa `_pending_interruption_classifications` e incrementa `_config_epoch`.
- **`EV07` (Conclusão natural `SUCCEEDED`/`FAILED`):** nunca cria registro pendente (`get_pending_interruption_classification_count() == 0`).
- **`EV08` (Emissão tardia/duplicada):** remoção atômica na primeira entrega garante idempotência estrita.

---

## 5. Evidência RED Autêntica (Pré-Implementação sobre `4801a6d`) vs GREEN

- **RED autêntico (`02_red/red_b3_behavioral_on_b2_r3.log`, `exit=1` sobre SHA `4801a6dd95011e865c9eab3be68a3a713c417284`):**
  - `RED-01`: `UnitControlState.ControlMode` sem `PERSONAL_POST_MOVE_WAIT`.
  - `RED-02`: `Unit` sem propriedade `personal_post_move_wait_sec`.
  - `RED-03`: `HudFormatter` retornando `""` para Casa Fundadora.
  - `RED-04`: `MoveOrder` pessoal adicionando exclusão permanente em `task.excluded_unit_ids` (violando `B0-Q05 B`).
  - `RED-05`: ausência da transição `PERSONAL_POST_MOVE_WAIT`.
- **GREEN pós-implementação (`08_green/green_b3_behavioral_probe.log`, `exit=0`):** `B3_BEHAVIORAL_PROBE=PASS` (`0` falhas).

---

## 6. Novas Suítes de Teste `R-03B B3`

| Suíte | Tipo | Testes | Asserções | Resultado | Log |
|---|---:|---:|---:|---|---|
| `tests/unit/test_r_03b_b3_wait_state_and_hud_formatter_unit.gd` | Unitária | 3 | 50 | `PASS (0 falhas)` | `03_timer_and_control_mode/unit_wait_and_hud.log` |
| `tests/integration/test_r_03b_b3_d05_wait_timer_and_pause.gd` | Integração (`D01`, `D02`, `F01`) | 3 | 122 | `PASS (0 falhas)` | `03_timer_and_control_mode/d01_d02_f01_timer_pause.log` |
| `tests/integration/test_r_03b_b3_q05_return_and_event_correlation.gd` | Integração (`D03`, `EV01`–`EV08`, Elegibilidade, `E02`/`D0-A04`) | 3 | 104 | `PASS (0 falhas)` | `04_event_correlation_and_q05/d03_ev01_ev08_eligibility.log` |
| `tests/integration/test_r_03b_b3_recovery_t1c_and_hud.gd` | Integração (`E01-B3` `T1c`, `entry.manual`, `D0-A04`, `G01` HUD) | 2 | 67 | `PASS (0 falhas)` | `05_recovery_t1c/e01_b3_t1c_and_g01_hud.log` |
| **Subtotal `B3` (`-Filter test_r_03b_b3`)** | **4 suítes** | **11** | **343** | **`11/11 PASS`** | `08_green/green_b3_suites.log` |
| **Consolidada `R-03B` (`-Filter test_r_03b_b`)** | **12 suítes (`B1`+`B2`+`B3`)** | **44** | **1.442** | **`44/44 PASS`** | `08_green/green_r03b_consolidated.log` |

---

## 7. Tabela Obrigatória de Adaptação de Testes Históricos e `B2` (§60)

Nenhuma garantia de bloqueio, conservação econômica, soberania pessoal ou reautorização explícita foi removida ou enfraquecida:

| Arquivo | Teste / Trecho | Motivo Técnico da Adaptação | Garantia Preservada |
|---|---|---|---|
| `tests/unit/test_r_03b_b2_control_mode_and_f03_unit.gd` | `test_c01_unit_control_state_enums_defaults_and_mode_mapping` (`L66–68`) | Fronteira `B2`/`B3` superada: `ControlMode` agora possui 4 estados incluindo `PERSONAL_POST_MOVE_WAIT = 3`. | Preserva ordinais `0..2`, mapeamento `mode_for_origin` e estado inicial `COMMUNITY_FREE`. |
| `tests/integration/test_r_03b_b2_control_mode_f03_and_reentrancy.gd` | `test_c01`, `test_c02_05_to_10` (Caso 3), `test_e02`, `test_b2_ar01` | Configura `personal_post_move_wait_sec = 0.0` nos casos originalmente sem temporizador; atualiza `L180` (`task_tree` não excluída por `MoveOrder`, retorno FIFO `B0-Q05 B` e exclusão preservada em `cancel_current_order()`); em `B2-AR01` verifica ausência estrita de feedback obsoleto de despacho (`"indo colher"`). | Preserva 100% da máquina `ControlMode`, F03, reentrância, bloqueio transacional e conservação `D0-A04`. |
| `tests/integration/test_r_03a_d1_selection_and_authorization.gd` | `test_d1_09`, `test_d1_14_t01a`, `test_d1_15_t01b`, `test_d1_17`, `test_d1_18` | Substitui o gatilho de exclusão permanente de `MoveOrder` para `cancel_current_order(REASON_CANCELLED)` (`ADMIN_CANCEL`), pois `MoveOrder` não exclui mais sob `B0-Q05 B`; em `test_d1_18` reaplica ordens pessoais ativas antes da reautorização via HUD. | Preserva 100% dos testes de `BLOCKED_REAUTHORIZATION` inerte, guarda de economia bloqueada, transação regional, escopo seletivo, marcadores únicos e preservação de ordens pessoais. |
| `tests/integration/test_r_03a_community_work_main_scene.gd` | `test_a17_blocked_reauthorization_remains_inert` (`L1085–1102`) | Usa `cancel_current_order(REASON_CANCELLED)` para excluir ambos os líderes e conduzir a tarefa a `BLOCKED_REAUTHORIZATION`. | Preserva 100% a prova de que novo trabalhador admitido jamais desbloqueia tarefa bloqueada. |
| `tests/integration/test_rux_2a_auto_resources.gd` | `test_a8` (`L526–565`) | Usa `cancel_current_order(REASON_CANCELLED)` para excluir ambos os líderes e atingir `BLOCKED_REAUTHORIZATION`. | Preserva 100% feedback `"nova autorização"`, zero polling e idempotência de clique. |
| `tests/integration/test_rux_2b_multi_source_selection.gd` | `test_b8` (`L558`) e `test_b12` (`L760–785`) | Em `L558` valida `B0-Q05 B` (`excluded_unit_ids` não marcada por `MoveOrder`, modo `PERSONAL_ACTIVE`); em `test_b12` exclui via `cancel_current_order()` e usa `wait = 0.0` no Evento 1 para testar retorno a `COMMUNITY_FREE` diante de tarefa bloqueada. | Preserva conservação de madeira, colega ativo e inércia de `BLOCKED_REAUTHORIZATION` frente a eventos e novo trabalhador. |
| `tests/integration/test_r_03a_d2_r1_adversarial_cancellation.gd` | `test_r1_t01a` (`view3`, `L331`) | Adiciona 1 linha (`main3.set_experimental_personal_post_move_wait_sec(0.0)`) para que `A01-R3C` reutilize imediatamente os líderes após `MoveOrder SUCCEEDED` em `A01-R3A`/`A01-R3B` sem aguardar os `8,0 s` do padrão experimental `D-05`. | **Zero** asserções alteradas; todas as `319` asserções de cancelamento adversarial e soberania permanecem intactas. |

**Suítes sensíveis preservadas sem alteração:** `test_r_03a_d3_2_tree_gather_orders.gd` (`12/12 PASS`, `179` asserções), `test_r_03a_d2_selective_work_cancellation.gd` (`PASS`), `test_r_03a_d3_3_regional_conservation.gd` (`13/13 PASS`, `1.147` asserções), `test_r_03a_d4_r2_algorithmic_equivalence.gd` (`PASS`), `test_t2_resource_hud.gd` (`7/7 PASS`, `562` asserções), `test_t3_6_4_cancellation_ui.gd` (`8/8 PASS`, `153` asserções).

---

## 8. Validação Estática, Smoke de 17 Pontos, Capturas Visuais Reais e Regressão Completa

### 8.1 Validação Estática (`validate.ps1`)
- **Comando:** `.\tools\validate.ps1`
- **Resultado:** **`PASSED` (`exit=0`, `0` erros, `0` avisos, `235` scripts verificados, headless startup OK)**
- **Evidência:** `09_static_validation/validate.log`

### 8.2 Smoke de 17 Pontos na `MainScene`
- **Resultado:** **`17/17 PASS` (`exit=0`)** — validando flags protegidas (`S01`–`S03`), padrão experimental `8.0 s` (`S04`), timer lazy ausente na inicialização (`S05`), estado inicial `COMMUNITY_FREE` (`S06`), HUD discreta sem polling (`S07`), despacho comunitário (`S08`), `MoveOrder` sem exclusão `Q05` + `"Ordem pessoal"` (`S09`), `PERSONAL_POST_MOVE_WAIT` + `"Aguardando retorno"` sem dígitos (`S10`), congelamento em pausa (`S11`), retorno automático à mesma tarefa de madeira (`S12`), zero correlações pendentes (`S13`), `Worker3` somente leitura sem timer (`S14`), cancelamento seletivo (`S15`), conservação regional `D0-A04` (`S16`) e teardown controlado (`S17`).
- **Evidência:** `11_smoke/smoke.log`, `11_smoke/smoke_summary.json`

### 8.3 Capturas Visuais Reais via GPU (`OpenGL 3.3.0 — Intel UHD Graphics 620`)
- **Execução:** Godot `4.7.2` com renderização real (sem `--headless`) em `1280×720` e `1920×1080`, todas inspecionadas visualmente (`exit=0`):
  1. `12_visual/main_1280x720_01_founding_community_free.png` — `Leader A` (`Trabalho comunitário`)
  2. `12_visual/main_1280x720_02_founding_personal_active.png` — `Leader A` (`Ordem pessoal`)
  3. `12_visual/main_1280x720_03_founding_post_move_wait.png` — `Leader A` (`Aguardando retorno`, sem contagem regressiva/cronômetro)
  4. `12_visual/main_1280x720_04_community_read_only.png` — `Worker3` (`Morador — somente leitura`)
  5. `12_visual/main_1920x1080_01_founding_post_move_wait.png` — `Leader A` (`Aguardando retorno`) + banner superior `"Corte de madeira autorizado."` sem sobreposição (`D4-A01`)
  6. `12_visual/main_1920x1080_02_community_read_only.png` — `Worker3` (`Morador — somente leitura`) em `1920×1080`
- **Evidência:** `12_visual/visual_capture.log`, `12_visual/visual_capture_summary.json`

### 8.4 Regressão Segmentada Completa Pós-Edição
- **Tentativa 1 (preservada em `10_full_regression/full_segmented_regression_attempt1_pre_fix.log`):** detectou 2 regressões reais (`test_t3_6_4_cancellation_ui` — sobreposição vertical de ~19 px entre `SelectedUnitPanel` e `BuildingInspectorPanel` em `1280×720`; `test_r_03a_d2_r1_adversarial_cancellation` `A01-R3C` — espera experimental `8,0 s` ativa após `A01-R3A`/`A01-R3B`). Ambas diagnosticadas na causa raiz e corrigidas.
- **Execução Final Pós-Correção (`10_full_regression/full_segmented_regression.log`):**
  - **Comando:** `.\tools\run_tests.ps1 -Segmented -MaxIntegrationPerGroup 1 -GroupTimeoutSeconds 240`
  - **Resultado:** **`exit=0`**
  - **Lotes:** **`77/77 PASS`** (`unit` + `integration-01`..`integration-76`)
  - **Suítes:** **`107/107`** (`Discovered=107 | ExecutedUnique=107 | Duplicates=0 | Missing=0`)
  - **Testes:** **`768/768 PASS` (`Failed=0 | SuiteErrors=0`)**
  - **Asserções:** **`35.492`**
  - **Tempos:** `SumGodotElapsed = 1.724.492,6 ms` | `TotalWallElapsed = 1.831.864,6 ms`

---

## 9. Parâmetro Experimental `D-05` para Futura Avaliação Humana (`B4`)

O valor padrão atual (`8.0 s`) é **estritamente experimental e provisório** (não definitivo). Os três candidatos previstos (`3.0 s`, `8.0 s`, `15.0 s`) estão expostos em:
- `Unit.EXPERIMENTAL_POST_MOVE_WAIT_OPTIONS_SEC` (`src/units/unit.gd`)
- `@export var personal_post_move_wait_sec` em `Unit` e `@export var experimental_personal_post_move_wait_sec` + `set_experimental_personal_post_move_wait_sec(seconds)` em `MainScene` (`src/main/main.gd`), podendo ser alternados diretamente no Inspector da `MainScene` ou em runtime sem reiniciar a cena (alterações afetam somente futuras esperas).

---

## 10. Matriz de Fechamento da Candidata `B3` (§71)

| Critério | Verificação | Status |
|---|---|---|
| `PERSONAL_POST_MOVE_WAIT` + 4 estados em `UnitControlState` | Unit + Integração (`D01`, `D02`, `F01`) | **PASS** |
| Timer nativo lazy pausável `D-05` + `(event_token, event_revision)` + 9 guardas | `test_r_03b_b3_d05_wait_timer_and_pause.gd` | **PASS** |
| Zero timer na inicialização da `MainScene` e em unidades `COMMUNITY` | `D01`, `D02`, `S05`, `S14` | **PASS** |
| Consumo do contrato de dois eventos ratificado `B2-R2` (`EV01`–`EV08`) | `test_r_03b_b3_q05_return_and_event_correlation.gd` | **PASS** |
| Retorno automático `B0-Q05 B` (wood/stone/food) preservando `CANCELLED`/`BLOCKED` | `D03` + `S12` | **PASS** |
| Classificação estrita em 4 categorias + `D4-R2 A02-02` | `test_strict_four_category_eligibility_classification_and_d4_r2_precedence` | **PASS** |
| Recuperação `T1c` explícita + recusa auto/forjada + `entry.manual` + `D0-A04` | `test_r_03b_b3_recovery_t1c_and_hud.gd` + `D3.3` | **PASS** |
| HUD discreta sem cronômetro/polling + coexistência `D4-A01` + `1280×720`/`1920×1080` | `G01` + `test_t2_resource_hud` + `test_t3_6_4_cancellation_ui` + 6 PNGs GPU | **PASS** |
| Validação estática `validate.ps1` (`0/0`, `235` scripts) | `09_static_validation/validate.log` | **PASS** |
| Regressão segmentada completa (`107/107` suítes, `768/768` testes, `35.492` asserções) | `10_full_regression/full_segmented_regression.log` | **PASS** |
| Aceite humano / escolha definitiva de `D-05` / campanha de desempenho (`B4`) | **Não executado** (fora de escopo — `B4` bloqueada) | **NÃO EXECUTADO (`B4`)** |
| Homologação do proprietário / promoção à `develop` ou `main` | Aguardando auditoria independente e decisão do proprietário | **PENDENTE / NÃO HOMOLOGADA** |
