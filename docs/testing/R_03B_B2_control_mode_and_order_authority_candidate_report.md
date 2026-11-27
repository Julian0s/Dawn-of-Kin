# Dawn of Kin — Relatório Técnico Candidato `R-03B B2` (`ControlMode`, Autoridade das Ordens e Protocolo `F03`)

> **Status Obrigatório:** **`CANDIDATA TÉCNICA B2 — AGUARDANDO AUDITORIA INDEPENDENTE — NÃO HOMOLOGADA`**
> **Escopo:** Implementação exclusiva da etapa **`R-03B B2`** conforme o plano arquitetural homologado `B0-R2` (`30b791571a7594f3e1de5a2403a69a1f11713eee`) e as ressalvas da auditoria independente da `B1-R1` (`01ad509e734930763ce70f1c2b0f63de08f37b35`).
> **Fronteira preservada:** **`B3`** (`PERSONAL_POST_MOVE_WAIT`, temporizador `D-05`, `B0-Q04 A`, `B0-Q05 B`, `T1c`, rótulos completos de HUD) e **`B4`** permanecem **integralmente bloqueadas**.

---

## 1. Autorização

- O proprietário homologou definitivamente **`R-03B B1-R1`** (commit `01ad509e734930763ce70f1c2b0f63de08f37b35`), encerrando integralmente **`B1`**.
- Foi autorizada exclusivamente a implementação **`R-03B B2`**, cobrindo:
  1. Máquina de estados `ControlMode` (`UnitControlState` com os 3 estados autorizados em `B2`).
  2. Prioridade formal das ordens pessoais sobre o trabalho comunitário.
  3. Protocolo `F03` completo de propriedade por revisão (`can_cancel_now()`, `_transition_seq`, reserva interna, commit tardio de `_order_revision`, notificação única `_finished_notified` e `InterruptionCause`).
  4. Proteção contra callbacks síncronos, cancelamento recursivo incompatível e reentrância.
  5. Integração orientada a eventos do `ControlMode` com `CommunityWorkBoard` e `CommunityTaskDispatcher`.
  6. Preservação integral de `F01`, `F02`, construção legada `P-REC-1`, recuperação `T1a`/`T1b` e conservação regional `D0-A04`.
  7. Correção das ressalvas pós-consolidação (`task_updated` e `task_assigned`) da auditoria `B1-R1` (`B2-AR01`–`B2-AR05`).
- Relatórios anteriores (`B0`, `B0-R1`, `B0-R2`, `B1`, `B1-R1`) e documentos normativos (`AGENTS.md`, `GDD v1.3`, `ROADMAP_MESTRE.md`) não foram modificados.

---

## 2. Base Git

| Referência | Valor verificado |
|---|---|
| Repositório | `https://github.com/Julian0s/Dawn-of-Kin` |
| Branch candidata | `feat/r-03b-founding-house-control-mode` |
| Worktree candidato | `C:\Projetos\Dawn_of_Kin_wt_r_03b` (mantido ativo) |
| Checkout principal permanente | `C:\Projetos\Dawn of Kin` (em `develop`, preservado) |
| SHA B1-R1 homologado (base direta da B2) | `01ad509e734930763ce70f1c2b0f63de08f37b35` |
| SHA B1 original (ancestral) | `1ad8ac397ff67f514b4c6d1f14316bf6c29744a6` |
| SHA B0-R2 homologado (ancestral) | `30b791571a7594f3e1de5a2403a69a1f11713eee` |
| `develop` protegida | `94c718024359dc7ff8360949313969b3ceaf9776` (intocada) |
| `main` protegida | `25e0a20f1d6a2f10a9e059afe69759fbe263db4a` (intocada) |
| Tags históricas | `t1-complete` (`3dcbba93`), `t2-complete` (`049ba9c7`), `t3-3-complete` (`c7947c96`) (intocadas) |
| `project.godot` local protegido (`C:\Projetos\Dawn of Kin`) | SHA-256 `AEEFDA2810DA5C4EDFA9BF5F2A47A5841F8597238C8DAB4C2E202FAF70307613` (intocado) |
| Manifesto B1-R1 anterior preservado | SHA-256 `41E7F5BD4F1925F441B1B3C6760D680A965BE2376A1485924952B7202A538EBF` (intocado) |

---

## 3. Escopo implementado

- **Produção (8 arquivos + `.uid`):**
  - `src/units/unit_control_state.gd` *(novo + `.uid`)* — máquina de estados leve `UnitControlState` (`COMMUNITY_FREE`, `COMMUNITY_WORKING`, `PERSONAL_ACTIVE`).
  - `src/units/orders/unit_order.gd` — enum `InterruptionCause`, `_finished_notified`, `can_cancel_now()`, `was_finished_notified()`, `mark_finished_notified()`, `get_interruption_cause()`, `set_interruption_cause()` (write-once).
  - `src/units/orders/gather_resource_order.gd` — `can_cancel_now()` puro espelhando `use_provenance_transactions and is_provenance_transfer_executing()`.
  - `src/units/orders/construct_order.gd` — `can_cancel_now()` puro espelhando `is_transfer_executing_readonly()` sem mutar `_replan_requested` + guarda `entry_rev` em `cancel()`.
  - `src/units/orders/deliver_to_camp_order.gd` — `can_cancel_now()` puro espelhando `use_selective_provenance and is_selective_transfer_executing()` + guarda `entry_rev` em `cancel()`.
  - `src/units/orders/recovery_order.gd` — `can_cancel_now()` verificando trava de retirada e delegado ativo + guarda `entry_rev` em `cancel()`.
  - `src/units/unit.gd` — composição de `UnitControlState`, sinal `control_mode_changed`, interface de consulta somente leitura, protocolo atômico `F03` de 4 estágios (`_transition_seq`, `_pending_transition_seq`, `_cancelling_order`, `_is_exiting_tree`), notificação única `_emit_order_finished_once()`, causa comprometida `InterruptionCause`, reconciliação em `_sync_definition()` e `_exit_tree()`.
  - `src/rts/community_work_board.gd` — integração de `unit.is_community_dispatch_eligible()` em `begin_task_dispatch()` e `validate_dispatch_lease_for_installation()`.
  - `src/rts/community_task_dispatcher.gd` — conexão/desconexão orientada a eventos de `unit.control_mode_changed`, classificação `"personal_control_active"` como espera temporária em `_check_unit_base_eligibility()`/`_evaluate_unassigned_task()`, e `_reconcile_committed_assignment_after_signal()` após `notify_task_updated(task)` e após `task_assigned.emit(...)`.
- **Novas suítes de testes (2 arquivos + `.uid`):**
  - `tests/unit/test_r_03b_b2_control_mode_and_f03_unit.gd` (`3` testes, `71` asserções).
  - `tests/integration/test_r_03b_b2_control_mode_f03_and_reentrancy.gd` (`6` testes, `195` asserções).
- **Documentação desta revisão (1 arquivo novo):**
  - `docs/testing/R_03B_B2_control_mode_and_order_authority_candidate_report.md`.

---

## 4. Inventário dos caminhos de ordens

Auditoria completa registrada em `01_order_lifecycle_and_revision_audit/revision_and_lifecycle_scan.txt`:
- Entradas de admissão em `Unit`: `issue_order()` (delega `null` a `_perform_administrative_cancel` e não-nulo a `issue_personal_order`), `issue_personal_order()`, `issue_community_order(order, dispatch_lease)`, `issue_recovery_order(order, expected_revision, explicit)`.
- Caminhos de término/cancelamento em `Unit`: `_physics_process()` → `_finalize_order_completion()`, `cancel_current_order()` / `_clear_current_order_for_null_issue()` → `_perform_administrative_cancel()`, `_install_admitted_order()` (Estágios 2 e 4B), `_exit_tree()`, e `_reconcile_active_order_after_definition_change()`.
- Todos os pontos convergem para as mesmas primitivas `_emit_order_finished_once()` e `_publish_control_mode_if_changed()`, eliminando emissões paralelas ou duplicadas.

---

## 5. Consumidores de revisão

Os 5 consumidores reais de `_order_revision` em `src/` foram mapeados e preservados integralmente:
1. `ResourceSource` (`src/economy/resource_source.gd:519` — `cutter.revision`)
2. `CommunityTaskDispatcher` (`src/rts/community_task_dispatcher.gd` — `task.assigned_order_revision` e guardas de reconciliação)
3. `CommunityWorkBoard` (`src/rts/community_work_board.gd` — `lease._expected_unit_revision`)
4. `CancellationRecoveryDispatcher` (`src/units/cancellation_recovery_dispatcher.gd` — `expected_revision` / `entry.revision`)
5. `GatherResourceOrder` (`_still_owns_unit_execution` / `_still_owns_movement_cleanup`), `ConstructOrder`, `DeliverToCampOrder`, `RecoveryOrder` e `SiteCancellationTransaction` (`L163`).

Em nenhum cenário de recusa de cancelamento `_order_revision` é incrementado ou decrementado.

---

## 6. Máquina de estados (`UnitControlState` / `ControlMode`)

- Estados implementados em `src/units/unit_control_state.gd`: `COMMUNITY_FREE`, `COMMUNITY_WORKING`, `PERSONAL_ACTIVE` (estritamente 3 estados; `PERSONAL_POST_MOVE_WAIT` não existe em `B2`).
- Autoridade única em `Unit`; nenhuma API pública permite forçar `ControlMode` arbitrariamente.
- Interface de consulta somente leitura em `Unit`: `get_control_mode()`, `get_control_mode_name()`, `get_active_order_origin()`, `has_pending_control_transition()`, `is_community_dispatch_eligible()`.
- Separação ortogonal mantida: `ControlMode` expressa autoridade de controle, `Unit.State` expressa condição física operacional, e `UnitOrder.OrderOrigin` distingue `COMMUNITY` de `SYSTEM_RECOVERY` dentro de `COMMUNITY_WORKING`.
- Sinal `control_mode_changed(new_mode, previous_mode)` publicado apenas quando `_mode != _last_published_mode` após estabilização final (zero emissões redundantes em `T5` e zero emissões transitórias em falhas/conclusões síncronas a partir de `COMMUNITY_FREE`).

---

## 7. Protocolo `F03` (Visão Geral e Matriz de Fechamento — §71)

| Contrato | Caminho real | Evidência RED | Solução implementada | Evidência GREEN | Estado |
|---|---|---|---|---|---|
| **Revisão preservada após recusa** | `Unit.issue_personal_order` / `cancel_current_order` / `issue_order(null)` | `02_red/red_b2_behavioral_on_b1_r1.log`: `_order_revision` corrompido (`1 → 2`) enquanto `WorkTask.assigned_order_revision == 1` | Pré-checagem `can_cancel_now()` + `_transition_seq` separado de `_order_revision`; commit apenas após encerramento efetivo | `test_c02_01_to_04_refused_cancel_preserves_revision_and_consumers` + `behavioral_red_turned_green.log` (`revision preserved (1)`) | **FECHADO TECNICAMENTE** |
| **Cancelabilidade pura (`can_cancel_now()`)** | `UnitOrder`, `MoveOrder`, `GatherResourceOrder`, `ConstructOrder`, `DeliverToCampOrder`, `RecoveryOrder` | `02_red/red_b2_suites_on_b1_r1.log` (API ausente) | Predicado puro sem efeitos colaterais (sem mutar `_replan_requested` em `ConstructOrder`) | `test_f03_unit_order_primitives_can_cancel_notified_and_interruption_cause` + `test_e02_and_c02_12...` | **FECHADO TECNICAMENTE** |
| **Transição interna (`_transition_seq` + reserva)** | `Unit._install_admitted_order`, `_perform_administrative_cancel`, `is_community_dispatch_eligible` | `02_red/red_b2_suites_on_b1_r1.log` | `_transition_seq` monotônico + `_pending_transition_seq` bloqueando despacho comunitário concorrente | `test_c01_...`, `test_c02_05_to_10_...` | **FECHADO TECNICAMENTE** |
| **Cancelamento efetivo e falha após substituição** | `Unit._install_admitted_order` Estágios 2B/4B | `02_red/red_b2_suites_on_b1_r1.log` | Ordem anterior encerrada não é ressuscitada; estabilização limpa em `COMMUNITY_FREE` + `State.IDLE` | `test_c02_05_to_10_...` (`C02-08`, `C02-09`) | **FECHADO TECNICAMENTE** |
| **Reentrância sem cancelamento recursivo incompatível** | `Unit._cancelling_order` + `entry_rev` em `Gather`/`Construct`/`Deliver`/`Recovery` | `02_red/red_b2_suites_on_b1_r1.log` | `_current_order` limpo antes de `cancel()`, `_cancelling_order` rastreado, `owns_movement` checado por `entry_rev` | `test_c02_05_to_10_...` (`worker_slot_released`, `order_finished`, `control_mode_changed`) | **FECHADO TECNICAMENTE** |
| **Proteção de sucessoras** | `Unit._has_mutation_authority` + `CommunityTaskDispatcher._reconcile_committed_assignment_after_signal` | `02_red/red_b2_behavioral_on_b1_r1.log` | Transição obsoleta cessa mutações; sucessora mantém ordem, movimento, vaga, revisão e `ControlMode` | `test_c02_05_to_10_...` + `test_b2_ar01_to_ar05_...` | **FECHADO TECNICAMENTE** |
| **Notificação única (`_finished_notified`)** | `Unit._emit_order_finished_once` + `UnitOrder._finished_notified` | `02_red/red_b2_suites_on_b1_r1.log` | Marcação antes da emissão em todos os caminhos; entregue 1× mesmo após sucessora; 0× para ordens rejeitadas | `test_c02_05_to_10_...` (`C02-06`, `C02-07`) + unit | **FECHADO TECNICAMENTE** |
| **Causa comprometida (`InterruptionCause`)** | `UnitOrder._interruption_cause` (write-once) + `Unit._interruption_cause_for` | `02_red/red_b2_suites_on_b1_r1.log` | Gravada no evento efetivamente comprometido (`PERSONAL_MOVE`, `PERSONAL_OTHER`, `SYSTEM_RECOVERY`, `ADMIN_CANCEL`); imutável após gravação | `test_c02_05_to_10_...` (`C02-10`), `test_c02_01_to_04_...` (`C02-11`), `test_e02_...` | **FECHADO TECNICAMENTE** |
| **Recuperação (`T1a`/`T1b`, `entry.manual`, trava)** | `Unit.issue_recovery_order` + `_revalidate_recovery_authority_post_cancel` | `02_red/red_b2_suites_on_b1_r1.log` | `T1a` exige `COMMUNITY_FREE`; `T1b` valida `can_cancel_now()`, revalida F02 pós-cancelamento e grava `SYSTEM_RECOVERY`; `entry.manual` preservado | `test_e02_and_c02_12_...` + `test_r_03b_b1_recovery_authority.gd` (`4/4` PASS) | **FECHADO TECNICAMENTE** |
| **Conservação regional (`D0-A04`)** | `RegionalConservationAudit` (`8` compartimentos) | `02_red/red_b2_suites_on_b1_r1.log` | Zero efeito econômico em mudanças de `ControlMode`; auditoria antes/depois para `&"wood"` e `&"stone"` | `test_e02_and_c02_12_...` (`verify_conservation().ok == true`) | **FECHADO TECNICAMENTE** |
| **Teardown, remoção e reconfiguração de definição** | `Unit._exit_tree`, `_sync_definition`, `MainScene.request_controlled_teardown` | `02_red/red_b2_suites_on_b1_r1.log` | `_is_exiting_tree` bloqueia readmissão; downgrade cancela ordem incompatível; domínio regional liberado | `test_f01_timerless_lifecycle_removal_definition_downgrade_and_teardown` + `11_smoke` | **FECHADO TECNICAMENTE** |
| **Callbacks posteriores a `task_updated` / `task_assigned`** | `CommunityTaskDispatcher._reconcile_committed_assignment_after_signal` | `02_red/red_b2_behavioral_on_b1_r1.log` (`B2-AR01` feedback obsoleto + `B2-AR05` trabalho órfão) | Revalidação de época, board, tarefa, unidade e `(order, revision)` após ambos os sinais, limpando somente a atribuição comprometida obsoleta | `test_b2_ar01_to_ar05_post_commit_dispatcher_callbacks` (`26/26` asserções) + `behavioral_red_turned_green.log` | **FECHADO TECNICAMENTE** |

---

## 8. Admissão pura

No Estágio 0 de `issue_personal_order()`, `issue_community_order()`, `issue_recovery_order()` e `issue_order(null)`: validam-se presença na árvore (`not _is_exiting_tree and is_inside_tree() and not is_queued_for_deletion()`), locks transacionais (`not _is_reserved_withdrawal_locked()`), permissões (`UnitControlPermissions`), autoridades `F01`/`F02` e cancelabilidade pura (`_current_order.can_cancel_now()`). Rejeições retornam `false` com zero mutação de `_current_order`, `_order_revision`, `ControlMode`, movimento, vagas ou custódia.

---

## 9. Cancelabilidade (`can_cancel_now()`)

- `UnitOrder` / `MoveOrder`: `true`.
- `GatherResourceOrder`: `not (use_provenance_transactions and is_provenance_transfer_executing())`.
- `ConstructOrder`: `not is_transfer_executing_readonly()` (estritamente somente leitura; não altera `_replan_requested`).
- `DeliverToCampOrder`: `not (use_selective_provenance and is_selective_transfer_executing())`.
- `RecoveryOrder`: bloqueia quando `_unit._is_reserved_withdrawal_locked()` ou quando `_delegate` ativo retorna `can_cancel_now() == false`; `RecoveryOrder.cancel()` espelha exatamente `can_cancel_now()`.

---

## 10. Reserva interna

`_transition_seq` monotônico e `_pending_transition_seq` reservam silenciosamente a unidade antes de `previous_order.cancel()`, bloqueando `is_community_dispatch_eligible()` e `issue_recovery_order()` durante a transição sem emitir `control_mode_changed` prematuro e sem avançar `_order_revision`.

---

## 11. Comprometimento de revisão

`_order_revision` só avança após confirmação de que `previous_order.is_finished()` (ou diretamente quando não havia ordem ativa) e somente se `_transition_seq == my_seq`. Nunca é decrementado.

---

## 12. Reentrância

- `_current_order` é zerado antes de `previous_order.cancel()` enquanto `_cancelling_order = previous_order` rastreia a ordem em cancelamento:
  - **Despacho comunitário / recuperação reentrante durante cancelamento:** recusado legitimamente no Estágio 0 (`_pending_transition_seq != 0` / `_cancelling_order != null`).
  - **Nova ordem pessoal válida durante callback de cancelamento (`worker_slot_released`, etc.):** admitida com segurança sem invocar recursivamente `previous_order.cancel()`; compromete sua causa de interrupção diretamente sobre `_cancelling_order` (write-once), avança `_transition_seq` e `_order_revision`; ao desenrolar, `previous_order.cancel()` detecta divergência de `entry_rev` e omite limpeza de movimento (`super.cancel(null, reason)`), enquanto a transição externa preterida cessa mutações sem tocar na sucessora.
  - **Cancelamento administrativo reentrante (`cancel_current_order()` durante `previous_order.cancel()`):** suplanta a transição externa gravando `ADMIN_CANCEL` em `_cancelling_order`, sem cancelar recursivamente a mesma ordem.

---

## 13. Notificações únicas

`UnitOrder._finished_notified` + `Unit._emit_order_finished_once()` garantem que toda ordem admitida e encerrada emita `order_finished(order)` exatamente uma vez (mesmo após tomada por sucessora), e que ordens rejeitadas no Estágio 0 ou preteridas antes de instalação nunca emitam notificações falsas.

---

## 14. `InterruptionCause`

Enum `UnitOrder.InterruptionCause { NONE, PERSONAL_MOVE, PERSONAL_OTHER, SYSTEM_RECOVERY, ADMIN_CANCEL }` gravado de forma imutável (write-once) sobre `previous_order` antes de `order_finished`. Em `B2`, a causa é armazenada e verificada em testes, mantendo integralmente preservadas as regras históricas de `excluded_unit_ids` / `BLOCKED_REAUTHORIZATION` (a ativação de `B0-Q05 B` permanece reservada à `B3`).

---

## 15. Integração comunitária

- `CommunityWorkBoard` verifica `unit.is_community_dispatch_eligible()` em `begin_task_dispatch()` e `validate_dispatch_lease_for_installation()`.
- `CommunityTaskDispatcher` conecta/desconecta `unit.control_mode_changed`, agendando `request_dispatch()` coalescido ao retornar a `COMMUNITY_FREE` (zero polling), e classifica `PERSONAL_ACTIVE` / transição pendente como `"personal_control_active"` em `has_temporary_wait = true`.
- Todas as proteções `B1-R1` (`_config_epoch`, `owner_board`, `owner_cmd`, `DispatchLease`, fallback restritivo) permanecem integralmente ativas.

---

## 16. Recuperação

`T1a` (`COMMUNITY_FREE` + `IDLE`), `T1b` (substituição de `ConstructOrder` do canteiro `CANCELLED` correspondente ao `record.site_id` real com revalidação pós-cancelamento e `InterruptionCause.SYSTEM_RECOVERY`), `entry.manual` e trava transacional permanecem íntegros. `T1c` permanece bloqueada para `B3`.

---

## 17. Ressalvas da auditoria `B1-R1` (`B2-AR01`–`B2-AR05`)

`_reconcile_committed_assignment_after_signal()` revalida época, board proprietário, validade da unidade (inclusive `not is_queued_for_deletion()`), tarefa e `(order, installed_revision)` tanto após `owner_board.notify_task_updated(task)` quanto após `task_assigned.emit(task, chosen_unit, order)`. Em caso de invalidação, limpa exclusivamente a atribuição comprometida obsoleta e cancela a ordem comunitária apenas se ainda pertencer exatamente a `(order, installed_revision)`, sem emitir feedback obsoleto e sem tocar em sucessoras ou em novos boards.

---

## 18. Conservação (`D0-A04`)

Validada com `tests/framework/regional_conservation_audit.gd` (`before` e `after` para `&"wood"` e `&"stone"` sobre os 8 compartimentos físicos e perdas legítimas independentes) em `test_e02_and_c02_12_recovery_control_mode_transactional_block_and_conservation` e nas suítes históricas `B1`/`R-03A`/`T3.6`.

---

## 19. Testes RED

Evidências preservadas em `evidencias/R-03B/B2/02_red/`:
- `red_b2_behavioral_on_b1_r1.log` (`RED_BEHAVIORAL_EXIT=1`): reproduziu 3 defeitos comportamentais reais sobre `01ad509`: (1) corrupção de `_order_revision` (`1 → 2`) em cancelamento recusado com `WorkTask.assigned_order_revision=1`; (2) emissão de `task_feedback` obsoleto após sucessora pessoal em `task_assigned` (`B2-AR01`); (3) trabalho comunitário órfão após `teardown()` em `task_updated` (`B2-AR05`).
- `red_b2_suites_on_b1_r1.log` (`RED_B2_SUITES_EXIT=1`): falha de compilação das duas novas suítes `B2` antes da criação de `UnitControlState` e das primitivas `F03`.

---

## 20. Testes GREEN

Evidências em `evidencias/R-03B/B2/05_green/`:
- `b2_tests_green.log` (`GREEN_B2_EXIT=0`): **`2/2` suítes, `9/9` testes, `266/266` asserções PASS**, `0` falhas, `0` erros (`15.512,7 ms`).
- `b1_preservation_green.log` (`GREEN_B1_EXIT=0`): **`3/3` suítes, `18/18` testes, `446/446` asserções PASS** (`B1` + `B1-R1` 100% preservados).
- `behavioral_red_turned_green.log` (`BEHAVIORAL_GREEN_EXIT=0`): `BEHAVIORAL_RED_FAILURES=0`, `F03-CHECK: revision preserved (1)`.

---

## 21. Reconciliação histórica

- **Testes históricos modificados na `B2`: `0`** (`08_historical_test_reconciliation/reconciliation_summary.txt`).
- Todas as `98` suítes históricas (incluindo as 3 reconciliadas em `B1`, as 3 de `B1`/`B1-R1` e todas as suítes `R-03A`/`Q05`) foram preservadas integralmente e aprovadas sem nenhuma edição.

---

## 22. Validação estática

- Comando: `.\tools\validate.ps1` (`09_static_validation/validate.log`).
- Resultado: **`Validation PASSED (0 errors, 0 warnings, 228 scripts checked)`**, **`VALIDATE_EXIT=0`**.
- `docs/design/*.import`: **`0`** (`DOCS_DESIGN_IMPORT_COUNT=0`).
- `git diff --check`: **`DIFF_CHECK_EXIT=0`**.
- Símbolos proibidos `B3` em `src/`: **`0`** (`FORBIDDEN_B3_SRC_HITS=0`).

---

## 23. Regressão integral

- Comando: `.\tools\run_tests.ps1 -Segmented -MaxIntegrationPerGroup 1 -GroupTimeoutSeconds 240` (`10_full_regression/segmented_regression.log`).
- Resultado consolidado:
  - **Batches:** **`71/71` `PASS`** (`unit` + `integration-01`..`integration-70`)
  - **Suítes:** **`100`** (`Discovered=100 | ExecutedUnique=100 | Duplicates=0 | Missing=0`)
  - **Testes:** **`751/751` `PASS`** (`Failed=0 | SuiteErrors=0`)
  - **Asserções:** **`34.765`**
  - **Tempo somado Godot:** `1.253.165,4 ms` | **Tempo de parede total:** `1.300.073,4 ms`
  - **`REGRESSION_EXIT=0`**
- **Explicação das diferenças frente à baseline `B1-R1` (`98` suítes / `742` testes / `34.500` asserções / `70` lotes):**
  - `+2` suítes (`98 → 100`) e `+1` lote de integração (`70 → 71`): `test_r_03b_b2_control_mode_and_f03_unit.gd` (no lote `unit`) e `test_r_03b_b2_control_mode_f03_and_reentrancy.gd` (novo lote de integração).
  - `+9` testes (`742 → 751`): `3` unitários + `6` de integração cobrindo `C01`, `C02-01`..`C02-12`, `E02`, `F01` e `B2-AR01`–`B2-AR05`.
  - `+265` asserções (`34.500 → 34.765`): `+266` novas asserções das 2 suítes `B2` combinadas com `-1` variação normal de quadro de física nos laços `while` da suíte histórica `test_t2_worker_cycle.gd` (comportamento já documentado em `CLOSEOUT-DOC-02`).

---

## 24. Smoke da `MainScene`

- Executado via `Invoke-Godot` com `scratch/b2_mainscene_smoke.gd` (`11_smoke/smoke.log`, `11_smoke/smoke_summary.json`): **`SMOKE_EXIT=0`**, `HAS_ERROR=False`, `HAS_WARNING=False`, `6.229,4 ms`.
- Todos os 10 itens da §63 confirmados como `true`: inicialização limpa, protagonistas comandáveis, `Worker3`/`Worker4` comunitários, trabalho comunitário autorizado (`COMMUNITY_WORKING`), interrupção pessoal (`PERSONAL_ACTIVE` + `PERSONAL_MOVE`), proteção contra sequestro comunitário, retorno a `COMMUNITY_FREE`, construção legada, recuperação `T1b` (`COMMUNITY_WORKING` + `SYSTEM_RECOVERY`) e encerramento controlado (`remove_temporary_workers_safely` + `request_controlled_teardown`).

---

## 25. Desempenho

- Nenhum polling por frame, alocação contínua, consulta redundante de navegação ou redistribuição recursiva foi introduzido.
- `CommunityTaskDispatcher` reage a `control_mode_changed(COMMUNITY_FREE)` via fila coalescida `call_deferred("_flush_dispatch")` já existente; otimizações `D4-R1`/`D4-R2` integralmente preservadas.
- Orçamento nominal `p95 <= 16,7 ms` CA na Intel UHD Graphics 620 inalterado; campanha completa de benchmarks permanece reservada à `B4`.

---

## 26. Limitações

- `PERSONAL_POST_MOVE_WAIT`, temporizador pausável `D-05`, calibração `3 s`/`8 s`/`15 s`, `B0-Q04 A`, `B0-Q05 B` (retorno à mesma tarefa sem `excluded_unit_ids`), `T1c` e rótulos completos de `ControlMode` na HUD permanecem intencionalmente fora da `B2` (reservados à `B3`).
- Nenhum teste humano ou campanha de benchmark `B4` foi executado ou declarado nesta etapa.

---

## 27. Evidências

Diretório externo: `C:\Projetos\Backups\Dawn_of_Kin_Archive_Local\evidencias\R-03B\B2\`
- `00_git_baseline` · `01_order_lifecycle_and_revision_audit` · `02_red` · `03_control_mode_implementation` · `04_f03_authority_and_reentrancy` · `05_green` · `06_dispatcher_callback_hardening` · `07_recovery_and_conservation` · `08_historical_test_reconciliation` · `09_static_validation` · `10_full_regression` · `11_smoke` · `12_git_final` + `MANIFEST_SHA256.txt` verificado após commit/push.

---

## 28. Integridade Git

- Publicada com commit linear sobre `01ad509e734930763ce70f1c2b0f63de08f37b35` na branch existente `feat/r-03b-founding-house-control-mode` (registrada integralmente em `12_git_final/git_final_state.txt`).
- `develop` (`94c718024359dc7ff8360949313969b3ceaf9776`), `main` (`25e0a20f1d6a2f10a9e059afe69759fbe263db4a`), tags históricas, `C:\Projetos\Dawn of Kin\project.godot` e manifestos históricos (`B0`, `B0-R1`, `B0-R2`, `B1`, `B1-R1`) preservados intactos.

---

## 29. Critérios de aceite (§75)

Todas as 20 garantias obrigatórias da `B2` (estados `ControlMode`, autoridade em `Unit`, prioridade pessoal, proteção contra sequestro comunitário, `T1a`/`T1b`, preservação de revisão em cancelamento recusado, `_transition_seq`, proteção de sucessoras, notificação única, `InterruptionCause`, coerência comunitária, `DispatchLease`, teardown/reconfiguração, callbacks pós-`task_assigned`/`task_updated`, permissões `B1`, economia e conservação `D0-A04`, regressão integral `100/100` e bloqueio de `B3`) foram verificadas tecnicamente com códigos de saída reais iguais a `0`.

---

## 30. Critério de parada

- **`R-03A`:** definitivamente encerrada.
- **`R-03B B0-R2`:** definitivamente homologada.
- **`R-03B B1-R1` / `B1`:** definitivamente homologada e encerrada.
- **`R-03B B2`:** **`CANDIDATA TÉCNICA AGUARDANDO AUDITORIA INDEPENDENTE — NÃO HOMOLOGADA`**.
- **`R-03B B3` e `B4`:** **`BLOQUEADAS`** até auditoria independente do ChatGPT e autorização expressa do proprietário.
