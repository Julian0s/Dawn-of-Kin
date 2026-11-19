# Dawn of Kin — Relatório Técnico da Candidata T3.6.2-C4.4
## Correção da aceitação de ordens RTS — R3

- **Data:** 19/11/2026
- **Engine:** Godot 4.7.2 (`Godot_v4.7.2-stable_win64.exe`)
- **Escopo autorizado:** Exclusivamente correção do risco **R3** em `CommandController` (verificação explícita de aceitação de ordens nos caminhos RTS de movimento, coleta e construção).
- **Parecer objetivo:** **CANDIDATA C4.4 PRONTA PARA AUDITORIA TÉCNICA** (reprodução `RED` confirmada no baseline, correção mínima validada em `5/5` testes focados e `431/431` testes segmentados com `0` erros/avisos; **não** declarada homologação formal do proprietário).

---

## 1. Baseline Git

- **Repositório:** `Julian0s/Dawn-of-Kin`
- **Worktree:** `C:\Projetos\Dawn_of_Kin_wt_t3_4_5`
- **Branch:** `feat/t3-6-2-provenance-transactions`
- **HEAD inicial verificado:** `c113524f3047ec049f20d8c12d9f506d33c90b11` (`0` ahead / `0` behind `origin/feat/t3-6-2-provenance-transactions`)
- **`main` de referência (intocada):** `25e0a20f1d6a2f10a9e059afe69759fbe263db4a`
- **Commits publicados desta candidata (anteriores a este relatório):**
  - `035b967a323942b7207388af360ad758e4970e33` — `fix(t3.6.2-c4.4): enforce explicit RTS order acceptance in CommandController (R3)`
  - `92cf7d6882a588d98039dc58863fe49078a95063` — `test(t3.6.2-c4.4): add focused integration suite for RTS order acceptance (R3)`

---

## 2. Causa raiz de R3

- Em `src/units/unit.gd`, `Unit.issue_order(order)` retorna imediatamente sem assumir `order` nem cancelar `_current_order` quando `_is_reserved_withdrawal_locked()` é verdadeiro (condição real durante bloqueio transacional em coordenadores de proveniência e seus sinais pós-commit).
- Uma `UnitOrder` recém-instanciada inicia em `Status.PENDING`, e `UnitOrder.is_active()` retorna `true` tanto para `Status.PENDING` quanto para `Status.RUNNING`.
- Em `src/rts/command_controller.gd`:
  1. `_command_gather_resource` (linhas 202–204) aceitava `if order.is_active(): started_count += 1`;
  2. `_command_supply_construction_site` (linhas 265–267) aceitava `if order.is_active() or order.is_succeeded(): started_count += 1`;
  3. `command_at` no caminho de movimento (`MoveOrder`, linhas 160–169) sequer contabilizava aceitação individual — emitia `command_issued(..., units.size(), ...)` e exibia `DestinationMarker` incondicionalmente, mesmo quando todas ou parte das unidades rejeitavam a ordem.
- Consequência: ordens nunca iniciadas (`PENDING` rejeitadas por trava transacional) ou falhas síncronas em movimento eram contabilizadas como comandos aceitos, disparando `command_issued` e `DestinationMarker` indevidos.

---

## 3. Reprodução RED no baseline `c113524`

Executado `.\tools\run_tests.ps1 -Filter test_t3_6_2_c4_4_rts_order_acceptance` antes de qualquer edição em `src/`:

- **Exit code:** `1`
- **Resultado:** `Tests: 5 | Passed: 1 | Failed: 4 | SuiteErrors: 0 | Assertions: 65`
- **Falhas observadas:**
  - `test_01_gather_command_rejected_under_real_transactional_lock`: durante `load_changed` pós-commit de `SelectiveCampDeliveryCoordinator`, `cmd.command_at(pick)` retornou `true` (esperado `false`), emitiu `command_issued` (`1`, esperado `0`) e não emitiu `command_rejected` (`0`, esperado `1`).
  - `test_02_construct_command_rejected_under_real_transactional_lock`: durante `load_changed` pós-commit de `ReservedWithdrawalCoordinator`, `cmd.command_units_to_site(site_b, [leader_a])` retornou `true` (esperado `false`), emitiu `command_issued` (`1`, esperado `0`) e não emitiu `command_rejected` (`0`, esperado `1`).
  - `test_03_move_command_rejected_under_real_transactional_lock`: durante `load_changed` pós-commit de `SelectiveCampDeliveryCoordinator`, `cmd.command_at(move_pick)` retornou `true` (esperado `false`), emitiu `command_issued` (`1`, esperado `0`) e não emitiu `command_rejected` (`0`, esperado `1`).
  - `test_04_group_partial_acceptance_counts_only_accepting_units_across_all_paths`: com `LeaderA` travado e `LeaderB` livre, `command_issued` contou `unit_count: 2` (esperado `1`) em movimento e coleta, e retornou `true` falso em construção mesmo quando `LeaderB` não pôde ingressar na obra sob o escopo de `SelectiveCampDeliveryCoordinator`.

---

## 4. Arquivos alterados

| Arquivo | Escopo | Justificativa |
| --- | --- | --- |
| `src/rts/command_controller.gd` | R3 | Critério explícito `_is_order_accepted(unit, order)`, diagnóstico `_resolve_order_rejection_reason(unit, order)` (`REASON_UNIT_TRANSACTION_LOCKED = "unit_transaction_locked"`), atualização coerente de `started_count`, `command_issued`, `command_rejected`, `get_last_command_reason()` e `DestinationMarker` nos três caminhos (`MoveOrder`, `GatherResourceOrder`, `ConstructOrder`). |
| `tests/integration/test_t3_6_2_c4_4_rts_order_acceptance.gd` (+ `.uid`) | R3 | Suíte de integração focada com 5 testes (`84` asserções) reproduzindo trava real via sinais pós-commit, rejeição total/parcial, sucesso instantâneo, falha síncrona e substituição normal. |

`Unit.issue_order()` e demais arquivos em `src/` não precisaram ser alterados, mantendo compatibilidade total com todos os chamadores.

---

## 5. Critério adotado para ordem aceita vs. ignorada

Implementado em `CommandController._is_order_accepted(unit, order)`:

- Retorna `true` se e somente se:
  1. `order.is_succeeded()` (execução instantânea legítima concluída com sucesso dentro de `issue_order`); **ou**
  2. `unit != null and is_instance_valid(unit) and unit.get_current_order() == order and order.is_active()` (ordem efetivamente assumida pela unidade).
- Ordens que permanecem `Status.PENDING` porque `Unit.issue_order` retornou cedo sob `_is_reserved_withdrawal_locked()` não satisfazem `unit.get_current_order() == order` nem `order.is_succeeded()`, portanto retornam `false`.
- Ordens terminadas em `Status.FAILED` ou `Status.CANCELLED` têm `order.is_succeeded() == false` e `order.is_active() == false` (além de `unit.get_current_order() != order`), portanto retornam `false`.
- Diagnóstico (`_resolve_order_rejection_reason`): preserva `order.failure_reason` quando preenchido (falha síncrona real); quando vazio e a unidade está travada ou a ordem permaneceu `PENDING`, registra `REASON_UNIT_TRANSACTION_LOCKED` (`"unit_transaction_locked"`), emitindo `command_rejected` e atualizando `get_last_command_reason()` quando `started_count <= 0`.

---

## 6. Tratamento de sucesso instantâneo

- Quando `MoveOrder.start()` detecta `movement.is_at_target(resolved_target)` no caminho `OK`, chama `mark_succeeded()` sincronamente e `Unit.issue_order()` limpa `_current_order = null`.
- Como `_is_order_accepted()` verifica `order.is_succeeded()` antes de `get_current_order() == order`, o sucesso instantâneo é contabilizado como aceito (`started_count += 1`), exibe `DestinationMarker`, emite `command_issued` e retorna `true`.
- Validado explicitamente em `test_05_instant_success_sync_failure_and_unlocked_replacement`.

---

## 7. Comportamento de grupos parcialmente aceitos

- Nos três caminhos (`command_at` movimento, `_command_gather_resource` e `_command_supply_construction_site`), cada unidade é avaliada individualmente após `unit.issue_order(order)`.
- Quando parte do grupo está sob trava transacional (ex.: `LeaderA`) e parte está livre (ex.: `LeaderB`):
  - `started_count` contabiliza exclusivamente as unidades que aceitaram (`1`, não `2`);
  - `command_issued` é emitido com `unit_count = started_count`;
  - `DestinationMarker` é exibido apenas quando `started_count > 0`;
  - `command_rejected` **não** é emitido na aceitação parcial, apenas quando `started_count <= 0`.
- Quando todas as unidades rejeitam (`started_count <= 0`), nenhum `DestinationMarker` é ativado, `command_issued` não é emitido, `command_rejected` é emitido com o motivo apurado e o método retorna `false`.

---

## 8. Conservação de recursos e ordens anteriores

- Como `Unit.issue_order()` retorna antes de cancelar `_current_order`, qualquer rejeição por trava em `MoveOrder`, `GatherResourceOrder` ou `ConstructOrder` preserva intacta a ordem anterior da unidade travada (`prior_order` / `ConstructOrder` em andamento), seus claims de trânsito (`site_a.get_transit_claim_for_unit`), slots de fonte (`bush.get_active_worker_count() == 0` para a coleta rejeitada) e saldos físicos comprometidos pela transação em curso.

---

## 9. Testes GREEN e regressão consolidada

| Comando | Resultado |
| --- | --- |
| `.\tools\run_tests.ps1 -Filter test_t3_6_2_c4_4_rts_order_acceptance` | **Exit 0.** `1` suíte, `5/5 PASS`, `84` asserções, `0` falhas/erros/avisos. |
| `git diff --check` | **Exit 0.** |
| `.\tools\validate.ps1` | **Exit 0.** `Validation PASSED (0 errors, 0 warnings, 152 scripts checked)`. |
| `.\tools\run_tests.ps1 -Segmented -GroupTimeoutSeconds 240` | **Exit 0.** `14/14` lotes (`unit` + `integration-01`..`13`), `58/58` suítes descobertas e executadas (`Duplicates=0`, `Missing=0`), **`431/431 PASS`**, **`24.499` asserções**, `0` falhas, `0` erros de suíte, `0` erros/avisos Godot. |

A regressão segmentada cobriu integralmente comandos/seleção T1 (`test_commands.gd`, `test_picking_selection.gd`, `test_box_selection.gd`, `test_rvo_separation.gd`, `test_unit_movement.gd`), coleta/construção T2/T3 (`test_t2_*`, `test_t3_2_*`, `test_t3_3_*`, `test_t3_4_*`, `test_t3_5_*`) e todas as suítes de proveniência `C1`–`C4.4`.

---

## 10. Riscos residuais

- Em rejeição parcial de grupo de movimento (`units.size() > 1` com `started_count < units.size()`), `command_issued` usa `plan.anchor_position` e `plan.all_slots_reachable` do plano original de `GroupMovePlanner` para o grupo selecionado (sem replanejar a formação removendo a unidade travada).
- `PlacementTestOverlay._format_command_rejection_reason` ainda não possui caso dedicado para `"unit_transaction_locked"`, caindo no fallback `"Motivo: unit_transaction_locked"` (tratamento completo de motivos de proveniência pertence a `P2`, fora do escopo C4.4).
- Permanecem pendentes e fora de escopo: `P2`, `P3`, `P4`, `P6` e decisões `D-INT-01/02/03`.

---

## 11. Confirmação do modo legado padrão

- `CommandController` não habilita proveniência (`use_provenance_transactions` e `use_selective_provenance` permanecem `false`), `MainScene` não inicializa unidades com proveniência, e nenhuma regra do GDD (D2, D3, D9, DEC-11A/B) ou lógica de reservas/lotes foi alterada.

---

## 12. Parecer objetivo

**CANDIDATA C4.4 PRONTA PARA AUDITORIA.** A correção de R3 fecha a contabilização falsa de ordens ignoradas nos três caminhos RTS com alteração mínima e localizada em `CommandController`, mantendo compatibilidade legada e `431/431` testes aprovados. Este relatório não declara homologação formal do proprietário nem avança para o próximo incremento.
