# Dawn of Kin — R-03B B2-R1 — Relatório de Candidata Técnica (Revalidação Pós-Callback, Ciclo Terminal e Propriedade Interna de Ordens)

> **Status oficial:** **`CANDIDATA TÉCNICA B2-R1 — AGUARDANDO AUDITORIA INDEPENDENTE — NÃO HOMOLOGADA`**
> **Escopo:** Revisão focal dos achados **B2-A01 (Crítico)**, **B2-A02 (Crítico)** e **B2-A03 (Alto)** sobre a candidata `R-03B B2` (`4c13db72a0b7abc795d1116299b6fcd76c5e72ff`).
> **Fronteiras preservadas:** Sem reimplementação geral de `ControlMode`, sem reconstrução do protocolo `F03`, sem antecipação da **`R-03B B3`** (`PERSONAL_POST_MOVE_WAIT`, temporizador `D-05`, `Q05-B`, `T1c`) ou **`R-03B B4`**, sem alteração de `develop`, `main`, tags ou documentos normativos.

---

## 1. Autorização expressa

- O proprietário autorizou exclusivamente a execução da revisão focal **`R-03B B2-R1`**, limitada estritamente aos três achados da auditoria independente sobre a candidata `R-03B B2` (`4c13db72a0b7abc795d1116299b6fcd76c5e72ff`):
  - **B2-A01 (Crítico):** revalidação insuficiente das permissões, locks e autoridade após callbacks síncronos durante substituição de ordens.
  - **B2-A02 (Crítico):** possibilidade de emissão falsa de `order_finished` e avanço prematuro de revisão para uma ordem ainda ativa durante `Unit._exit_tree()`.
  - **B2-A03 (Alto):** continuação de operações obsoletas dentro de ordens concretas após callbacks síncronos e limpeza de claims/vagas não vinculada à identidade da ordem dona.
- Etapas **`R-03B B3`** e **`R-03B B4`** permanecem **BLOQUEADAS**.
- Este documento **não** reescreve [R_03B_B2_control_mode_and_order_authority_candidate_report.md](R_03B_B2_control_mode_and_order_authority_candidate_report.md) nem altera os documentos normativos (`AGENTS.md`, `docs/Dawn_of_Kin_GDD.md`, `docs/ROADMAP_MESTRE.md`, `docs/architecture/R_03B_B0_founding_house_control_mode_PLAN.md`).

---

## 2. Base Git

| Referência | Valor verificado | Integridade |
|---|---|---|
| Repositório | `https://github.com/Julian0s/Dawn-of-Kin` | Confirmado |
| Branch candidata | `feat/r-03b-founding-house-control-mode` | Confirmado |
| Worktree candidato | `C:\Projetos\Dawn_of_Kin_wt_r_03b` | Preservado ativo |
| SHA base `B2` auditado | `4c13db72a0b7abc795d1116299b6fcd76c5e72ff` | `HEAD == origin` no baseline (`WT_CLEAN=True`) |
| SHA `B1-R1` homologado | `01ad509e734930763ce70f1c2b0f63de08f37b35` | Ancestral linear (`exit=0`) |
| SHA `B0-R2` homologado | `30b791571a7594f3e1de5a2403a69a1f11713eee` | Ancestral linear (`exit=0`) |
| Branch `develop` protegida (`C:\Projetos\Dawn of Kin`) | `94c718024359dc7ff8360949313969b3ceaf9776` | Intacta (`DEVELOP_OK=True`) |
| Branch `main` protegida | `25e0a20f1d6a2f10a9e059afe69759fbe263db4a` | Intacta (`MAIN_OK=True`) |
| Tags preservadas | `t1-complete` (`3dcbba9386cbbee70025b47f4254ef097688a6e1`), `t2-complete` (`049ba9c7714c9b90b5515ae6ac30a28830454773`), `t3-3-complete` (`c7947c9630c102a9d77603cac0bae68678247c95`) | Intactas |
| Arquivo local protegido `C:\Projetos\Dawn of Kin\project.godot` | `SHA-256 = AEEFDA2810DA5C4EDFA9BF5F2A47A5841F8597238C8DAB4C2E202FAF70307613` | Intacto (`PROJ_OK=True`) |
| Manifesto anterior `B2` (`evidencias\R-03B\B2\MANIFEST_SHA256.txt`) | `SHA-256 = 5EAE91656FEA264846C7FA0D518FA9A69109C57795A64B1C5F378D1F8E75F635` | Intacto (`PRIOR_B2_MANIFEST_OK=True`) |

---

## 3. Escopo focal

Apenas **6 scripts de produção** receberam ajustes cirúrgicos, acompanhados por **1 suíte adversária nova** (+ `.uid`) e este relatório:

- **Produção modificada (`6` arquivos; `+213 / -60` linhas):**
  - `src/units/unit.gd` (`B2-A01`, `B2-A02`)
  - `src/buildings/construction_site.gd` (`B2-A03`)
  - `src/units/orders/construct_order.gd` (`B2-A03`)
  - `src/units/orders/gather_resource_order.gd` (`B2-A03`)
  - `src/units/orders/deliver_to_camp_order.gd` (`B2-A03`)
  - `src/units/orders/recovery_order.gd` (`B2-A03`)
- **Testes novos (`1` suíte + `.uid`):**
  - `tests/integration/test_r_03b_b2_r1_focal_revalidation_and_lifecycle.gd`
  - `tests/integration/test_r_03b_b2_r1_focal_revalidation_and_lifecycle.gd.uid`
- **Documentação nova (`1` relatório candidato):**
  - `docs/testing/R_03B_B2_R1_focal_lifecycle_and_authority_candidate_report.md`
- **Verificação negativa de antecipação `B3`:** `FORBIDDEN_B3_SRC_HITS=0` (nenhuma ocorrência em `src/` de `PERSONAL_POST_MOVE_WAIT`, `post_move_wait`, `_wait_timer`, `_wait_token_id`, `personal_post_move_wait_sec` ou `T1c`).

---

## 4. Resultado individual de A01–A03 e Matriz focal (§27)

### 4.1 Resultado consolidado por achado

- **B2-A01 (Crítico) — CORRIGIDO E VERIFICADO:** Revalidação completa adicionada em dois pontos críticos dentro de `Unit._install_admitted_order()` (pós-`previous_order.cancel()` antes de carimbar `InterruptionCause`, e pós-`_emit_order_finished_once()` imediatamente antes da instalação efetiva), cobrindo afiliação, faixa etária, locks transacionais, status `PENDING`, `DispatchLease` (F01) e autoridade/identidade de recuperação (F02).
- **B2-A02 (Crítico) — CORRIGIDO E VERIFICADO:** `_emit_order_finished_once()` passou a exigir `order.is_finished()` e `Unit._exit_tree()` passou a condicionar avanço de revisão, transição para `COMMUNITY_FREE`/`IDLE` e notificação terminal à efetiva conclusão da ordem (`exiting_order.is_finished()`), restaurando `_current_order = exiting_order` sem sinal falso quando cancelamento é recusado por transação ativa.
- **B2-A03 (Alto) — CORRIGIDO E VERIFICADO:** Guardas de propriedade por `_order_revision` e identidade de instância aplicadas após callbacks síncronos em `ConstructOrder`, `GatherResourceOrder`, `DeliverToCampOrder` e `RecoveryOrder`, e ownership por `UnitOrder` introduzida em `ConstructionSite.claim_pickup()`, `release_pickup_claim()` e `unregister_worker()`.

### 4.2 Matriz focal detalhada (§27)

| Achado | Reprodução | Causa raiz | Correção | GREEN | Contrato preservado | Estado |
|---|---|---|---|---|---|---|
| **B2-A01 / A01-R01** (Perda de `FOUNDING_HOUSE` → `COMMUNITY` durante `order_finished`) | **Reproduzido em RED** (`B2-A01-RED`, `red_b2_r1_behavioral_on_b2.log`): `MoveOrder` pessoal instalada em unidade rebaixada (`ok=true`, `mode=PERSONAL_ACTIVE`) | `_install_admitted_order()` validava permissões apenas no Estágio 0; durante `order_finished`, `_current_order == null`, logo `_reconcile_active_order_after_definition_change()` não interceptava e o Estágio 3 prosseguia com permissão obsoleta | `_revalidate_admitted_order_before_install()` no Check Point 2 (pós-`order_finished`) revalida `get_personal_order_rejection_reason_for_order()`, estabiliza `COMMUNITY_FREE`/`IDLE`, limpa `_pending_transition_seq` e cancela a ordem rejeitada sem emitir `order_finished` | `PASS` (`A01-R01`, `test_r_03b_b2_r1`, `BEHAVIORAL_GREEN_EXIT=0`) | `B1` permissões da Casa Fundadora + `F03` sem ressurreição da ordem anterior | **CORRIGIDO / VALIDADO** |
| **B2-A01 / A01-R02a** (Rebaixamento `ADULT` → `CHILD` durante `order_finished` com `GatherResourceOrder(WOOD)`) | Coberto pela mesma janela de `order_finished` reproduzida em `A01-R01` | Mesma ausência de revalidação pós-callback em `_install_admitted_order()` | Check Point 2 rejeita com `REASON_AGE_RESTRICTED_TASK` antes de instalar | `PASS` (`A01-R02a`) | Restrição etária `B1` (`CHILD` sem corte de madeira) | **CORRIGIDO / VALIDADO** |
| **B2-A01 / A01-R02b** (Rebaixamento `ADULT` → `BABY` dentro de `previous_order.cancel()` via `worker_slot_released` durante `MoveOrder`) | Reproduzível no mesmo fluxo pós-`cancel()` antes do carimbo de `InterruptionCause` | `_install_admitted_order()` carimbava `InterruptionCause.PERSONAL_MOVE` imediatamente após `previous_order.cancel()` antes de saber se a ordem entrante ainda tinha permissão válida | Check Point 1 (pós-`previous_order.cancel()`, **antes** de `set_interruption_cause`): recusa carimba `InterruptionCause.ADMIN_CANCEL` (nunca `PERSONAL_MOVE`), emite `order_finished(previous_order)` exatamente uma vez e rejeita `MoveOrder` | `PASS` (`A01-R02b`) | Coerência `F03` de `InterruptionCause` + restrição `BABY` | **CORRIGIDO / VALIDADO** |
| **B2-A01 / A01-R03** (Lock transacional superveniente em `CarryLoad` durante `order_finished`) | Coberto pela janela pós-`order_finished` | `_is_reserved_withdrawal_locked()` era verificado apenas antes de `previous_order.cancel()` | `_revalidate_admitted_order_before_install()` revalida `_is_reserved_withdrawal_locked()` e rejeita com `REASON_UNIT_TRANSACTION_LOCKED` | `PASS` (`A01-R03`) | Bloqueio transacional econômico `T3.6.2`/`T3.6.3` | **CORRIGIDO / VALIDADO** |
| **B2-A01 / A01-R04** (Recuperação `T1b` com rebaixamento `ADULT` → `CHILD` durante `order_finished`) | Coberto pela revalidação incompleta de recuperação em `4c13db7` | `_revalidate_recovery_authority_post_cancel()` não revalidava `UnitControlPermissions.can_perform_recovery_order(self)`, `order.status == PENDING` nem `validate_unit_identity_in_domain_readonly()` | `_revalidate_admitted_order_before_install()` + `_revalidate_recovery_authority_post_cancel()` revalidam permissão de recuperação, status `PENDING`, custódia não liquidada e identidade econômica readonly; após restaurar adulto, recuperação explícita liquida normalmente | `PASS` (`A01-R04`) | Autoridade `F02` de recuperação + liquidação legítima | **CORRIGIDO / VALIDADO** |
| **B2-A01 / A01-R05** (Sucessora válida instalada dentro de `order_finished`) | Verificação de não-regressão do protocolo `F03` | — | Checagem `_has_mutation_authority(my_seq, issued_revision)` preservada antes do Check Point 2; sucessora permanece dona | `PASS` (`A01-R05`) | Protocolo `F03` de sucessora reentrante | **PRESERVADO / VALIDADO** |
| **B2-A02 / A02-R01** (`GatherResourceOrder` com `GatherTransferSession` ativa durante remoção controlada e `_exit_tree()`) | **Reproduzido em RED** (`B2-A02-RED`): `_exit_tree()` emitiu falso `order_finished` (`count=1`), marcou `was_finished_notified()=true` e avançou revisão com `is_finished()=false` | `_emit_order_finished_once()` não exigia `order.is_finished()` e `_exit_tree()` sempre limpava `_current_order`, incrementava `_order_revision` e emitia `order_finished` | `_emit_order_finished_once()` passou a exigir `order.is_finished()`; `_exit_tree()` só avança revisão/estado/sinal se `exiting_order.is_finished()`, caso contrário preserva `_current_order = exiting_order` | `PASS` (`A02-R01`, `BEHAVIORAL_GREEN_EXIT=0`) | Invariante terminal + remoção controlada `TemporaryTestWorkersController` recusa sob lock | **CORRIGIDO / VALIDADO** |
| **B2-A02 / A02-R02** (`ConstructOrder` com transferência de proveniência ativa durante `_exit_tree()`) | Mesma causa raiz de `A02-R01` aplicada a `ConstructOrder` | `_exit_tree()` emitia falso término e avançava revisão sobre ordem ainda ativa | Revisão, `_current_order` e registro `_assigned_workers` no canteiro preservados; após reanexar e destravar, site permanece íntegro | `PASS` (`A02-R02`) | Transação de proveniência + registro de trabalhador | **CORRIGIDO / VALIDADO** |
| **B2-A02 / A02-R03** (`RecoveryOrder` com custódia bloqueada durante `_exit_tree()`) | Mesma causa raiz de `A02-R01` aplicada a `RecoveryOrder` | `_exit_tree()` podia sinalizar término falso de recuperação ainda bloqueada | `ZERO` `order_finished`, revisão intacta, custódia não liquidada artificialmente; ao reanexar e destravar, custódia liquida (`SETTLED`) | `PASS` (`A02-R03`) | Integridade `F02` / `CancellationRecoveryTransaction` | **CORRIGIDO / VALIDADO** |
| **B2-A02 / A02-R04** (Ordem cancelável normal removida em `_exit_tree()`) | Verificação de fluxo normal + tentativa de readmissão durante `_exit_tree()` | — | Ordem conclui como terminal, emite `order_finished` exatamente `1` vez, readmissão é bloqueada (`_is_exiting_tree`) | `PASS` (`A02-R04`) + `D0-A04` madeira/pedra | Teardown normal + bloqueio de readmissão em saída | **PRESERVADO / VALIDADO** |
| **B2-A03 / A03-R01** (`ConstructOrder.start()` substituída sincronamente em `site.register_worker()` → `workers_changed`) | **Reproduzido em RED** (`B2-A03a-RED`): `ConstructOrder` obsoleta continuou após `register_worker()`, sobrescrevendo movimento da sucessora `MoveOrder` (`move_state=0`) | `ConstructOrder.start()` não revalidava `_order_revision` / `_current_order == self` após `site.register_worker()` e `_bind_site_signals()` | `_capture_unit_order_revision()` + `_still_owns_unit_execution(entry_rev)` após `register_worker()` e `_bind_site_signals()` (com `_unbind_site_signals()` se perder posse) | `PASS` (`A03-R01`, `BEHAVIORAL_GREEN_EXIT=0`) | Sucessora `MoveOrder` mantém alvo/movimento e `0` handlers vazados | **CORRIGIDO / VALIDADO** |
| **B2-A03 / A03-R02** (`ConstructionSite` pickup claim e `unregister_worker` + limpeza de movimento em `_finish_failed`/`_finish_succeeded`) | **Reproduzido em RED** (`B2-A03b-RED`): `site.unregister_worker(unit, c_old)` apagou o pickup claim de `c_new` no mesmo canteiro (`remaining=0`) | `unregister_worker()` chamava `release_pickup_claim(unit)` **antes** de checar `entry["order"] == order`; `_pending_pickups` não armazenava `order` dona; `_finish_failed`/`_finish_succeeded` paravam movimento sem checar posse | `claim_pickup(..., owner_order)` grava `"order"`; `release_pickup_claim(unit, owner_order)` recusa apagar claim de outra ordem; `unregister_worker()` valida `entry["order"] == order` **antes** de liberar claim; `_finish_succeeded`/`_finish_failed`/`cancel()` protegem movimento com `_still_owns_movement_cleanup(entry_rev)` | `PASS` (`A03-R02`, `BEHAVIORAL_GREEN_EXIT=0`) | Claims, vagas e movimento da sucessora preservados | **CORRIGIDO / VALIDADO** |
| **B2-A03 / A03-R03** (`GatherResourceOrder.start()` substituída durante `state_changed(MOVING)`) | Subcenário de callback síncrono em `GatherResourceOrder.start()` | `start()` não verificava `_still_owns_unit_execution(entry_rev)` após `_acquire_source_reservation()`/`mark_running()` | Guarda `_still_owns_unit_execution(entry_rev)` adicionada em `GatherResourceOrder.start()` (somada às guardas já existentes em `_start_approaching_source()`) | `PASS` (`A03-R03`) | Movimento e posse da sucessora `MoveOrder` preservados | **CORRIGIDO / VALIDADO** |
| **B2-A03 / A03-R04** (`DeliverToCampOrder` legado/seletivo e `RecoveryOrder._update()` substituídas via `state_changed(TRANSPORTING)`) | Subcenários de callback síncrono após `set_order_state(TRANSPORTING)` e `_delegate.start()` | `DeliverToCampOrder._start_legacy_walk()`/`_start_selective_walk()` e `RecoveryOrder._update()` não verificavam revisão após callbacks síncronos | `_still_owns_delivery_execution(entry_rev)` em `DeliverToCampOrder` e `_still_owns_unit_execution(entry_rev)` em `RecoveryOrder._update()` (cancelando subordem obsoleta com `movement = null` sem tocar movimento da sucessora) | `PASS` (`A03-R04a`, `A03-R04b`) + `D0-A04` madeira/pedra | Carga conservada, entrega obsoleta abortada, sucessora intacta | **CORRIGIDO / VALIDADO** |

### 4.3 Casos avaliados e explicitamente não reproduzíveis (com justificativa técnica)

1. **`MoveOrder.start()` sob callback de movimento:** `MoveOrder.start()` chama apenas `movement.begin_move_to()` (que não emite sinais externos síncronos) seguido de `_unit.set_order_state(self, Unit.State.MOVING)` já como última operação de `start()`; se `state_changed` substituir `MoveOrder`, não há continuação subsequente em `start()` que possa sobrescrever a sucessora. Por isso não exigiu alteração em `move_order.gd`.
2. **Desmontagem de cena com `queue_free()` puro sem `remove_child()` em `A02-R01..R03`:** o defeito `B2-A02` ocorre especificamente na entrada síncrona de `Unit._exit_tree()` (acionada tanto por `remove_child()` quanto no fechamento da árvore de cena enquanto um bloqueio transacional está ativo). A reprodução direta com `parent.remove_child(unit)` testa exatamente a entrada real de `_exit_tree()` sem depender de destruição irreversível antes das asserções pós-saída.
3. **Execução de `ConstructOrder._start_moving_to_pile()` com substituição pós-`set_order_state()` em modo proveniência:** o caminho `movement.get_move_state() == ARRIVED and _provenance_transfer == null` só executa entrega imediata em modo legado (`_provenance_transfer == null`), razão pela qual a guarda foi inserida defensivamente em `construct_order.gd:716-718` mesmo sem ser alcançável quando `use_provenance_economy = true`.

---

## 5. Evidências RED

Antes de qualquer alteração em `src/`, um script comportamental independente foi executado sobre o baseline auditado `4c13db72a0b7abc795d1116299b6fcd76c5e72ff`, reproduzindo **4/4 falhas reais** com `RED_BEHAVIORAL_EXIT=1`:

- Evidência: `C:\Projetos\Backups\Dawn_of_Kin_Archive_Local\evidencias\R-03B\B2\R1\02_red\red_b2_r1_behavioral_on_b2.log`
- Falhas reproduzidas no baseline `4c13db7`:
  1. `B2-A01-RED REPRODUCED`: `stale personal MoveOrder installed on COMMUNITY unit after downgrade in order_finished (ok=true, mode=PERSONAL_ACTIVE)`
  2. `B2-A02-RED REPRODUCED`: `_exit_tree emitted FALSE order_finished on still-active GatherResourceOrder (count=1, is_finished=false, notified=true)`
  3. `B2-A03a-RED REPRODUCED`: `stale ConstructOrder.start() stopped/clobbered MoveOrder successor after workers_changed (signals_bound=false, move_state=0)`
  4. `B2-A03b-RED REPRODUCED`: `site.unregister_worker(unit, c_old) wiped c_new's pickup claim (remaining=0)`
- Durante o refinamento inicial da suíte de testes nova (`task-2101`, preservado no log do agente), `test_b2_a01` passou `50/50` de imediato; `A02-R02` revelou que `site.get_worker_role()` aciona `_prune_stale_state()` enquanto o nó está fora da árvore (ajustado no teste para verificar `_assigned_workers.has(uid)` enquanto fora da árvore e `get_worker_role()` após reanexar), e `A03-R04b` revelou que `LeaderA` já se encontrava em `Unit.State.TRANSPORTING` ao cancelar o canteiro (ajustado no teste para aguardar `leader_a.get_state() != Unit.State.TRANSPORTING` antes de disparar o cancelamento, exercitando o sinal real `state_changed(TRANSPORTING)`). Nenhuma asserção foi enfraquecida.

---

## 6. Correções aplicadas

Patches individuais arquivados em `03_revalidation_corrections\unit_revalidation_and_exit_tree.patch`, `04_terminal_lifecycle_corrections\unit_terminal_lifecycle.patch` e `05_order_ownership_corrections\orders_and_site_ownership.patch`:

1. **`src/units/unit.gd` (`+91 / -22`):**
   - `B2-A02`: `_emit_order_finished_once()` exige `order.is_finished()`; `_exit_tree()` verifica `if exiting_order.is_finished():` antes de avançar `_order_revision`, zerar `ControlMode`/estado ou notificar `order_finished`; caso o cancelamento seja recusado, preserva `_current_order = exiting_order` sem sinal falso e sem marcar `_finished_notified`.
   - `B2-A01`: `issue_community_order()` encaminha `dispatch_lease` para `_install_admitted_order()`; novo helper `_revalidate_admitted_order_before_install(order, origin, recovery_ctx, dispatch_lease)` chamado em **Check Point 1** (pós-`previous_order.cancel()`, antes de carimbar `InterruptionCause`) e **Check Point 2** (pós-`_emit_order_finished_once(previous_order)`, antes da instalação efetiva); `_revalidate_recovery_authority_post_cancel()` reforçado com `ReservedWithdrawalCoordinator.validate_unit_identity_in_domain_readonly()`.
2. **`src/buildings/construction_site.gd` (`+23 / -5`):**
   - `claim_pickup(..., owner_order: UnitOrder = null)` registra `"order": resolved_owner` em `_pending_pickups[uid]`.
   - `release_pickup_claim(unit, owner_order: UnitOrder = null)` recusa remover claim pertencente a outra `UnitOrder`.
   - `unregister_worker(unit, order: UnitOrder = null)` valida `entry.get("order") == order` **antes** de chamar `release_pickup_claim(unit, order)`.
3. **`src/units/orders/construct_order.gd` (`+53 / -31`):**
   - Helpers `_capture_unit_order_revision()`, `_still_owns_unit_execution(expected_rev)` e `_still_owns_movement_cleanup(expected_rev)`.
   - Guardas em `start()` (após `register_worker()` e `_bind_site_signals()`), `_select_and_approach_next_pile()` (após `set_order_state(MOVING)`), `cancel()`, `_finish_succeeded()` e `_finish_failed()`.
   - Todas as chamadas a `site.claim_pickup(..., self)` e `site.release_pickup_claim(_unit, self)` vinculadas a `self`.
4. **`src/units/orders/gather_resource_order.gd` (`+3 / -0`):**
   - Captura de revisão e guarda `_still_owns_unit_execution(entry_rev)` em `start()` antes de `_start_approaching_source(movement)`.
5. **`src/units/orders/deliver_to_camp_order.gd` (`+14 / -0`):**
   - Helper `_still_owns_delivery_execution(expected_rev)` protegendo `_start_legacy_walk()` e `_start_selective_walk()` imediatamente após `_unit.set_order_state(self, Unit.State.TRANSPORTING)`.
6. **`src/units/orders/recovery_order.gd` (`+27 / -4`):**
   - Helper `_still_owns_unit_execution(expected_rev)` em `_update()` após `_delegate.physics_update()` e após `del_sub.start()` / `mv_sub.start()`, cancelando subordem obsoleta com `movement = null` caso a posse tenha sido perdida.

---

## 7. Evidências GREEN

| Execução | Comando | Exit Code | Resultado verificado | Log |
|---|---|---|---|---|
| GREEN focal `B2-R1` | `.\tools\run_tests.ps1 -Filter test_r_03b_b2_r1` | `0` | `1/1` suíte, `3/3` testes, `141` asserções, `0` falhas, `0` erros (`13.471,9 ms`) | `06_green\b2_r1_tests_green.log` |
| Preservação completa `R-03B` (`B1` + `B2` + `B2-R1`) | `.\tools\run_tests.ps1 -Filter test_r_03b_b` | `0` | `6/6` suítes, `30/30` testes, `853` asserções, `0` falhas, `0` erros (`25.325,3 ms`) | `06_green\b1_and_b2_all_green.log` |
| Reprodução comportamental RED → GREEN | `Invoke-Godot --headless ... b2_r1_behavioral_red.gd` | `0` | `B2_R1_BEHAVIORAL_RED_FAILURES=0`, `HAS_ERROR=False` | `06_green\behavioral_red_turned_green.log` |

---

## 8. Revalidação de permissões

- Em `Unit._install_admitted_order()`, a revalidação é executada tanto após `previous_order.cancel()` (**Check Point 1**) quanto após `_emit_order_finished_once(previous_order)` (**Check Point 2**).
- Para ordens `PERSONAL`, `_revalidate_admitted_order_before_install()` consulta `UnitControlPermissions.get_personal_order_rejection_reason_for_order(self, order)`, impedindo instalação se durante callbacks a unidade perdeu afiliação `FOUNDING_HOUSE`, mudou de faixa etária (`ADULT` → `CHILD`/`BABY`), sofreu lock transacional ou saiu da árvore.
- Para ordens `COMMUNITY`, revalida `order is GatherResourceOrder`, `can_participate_in_community_work_for_order(self, order)` e `board.is_dispatch_lease_valid_for_commit(dispatch_lease)` (F01); em caso de recusa tardia, `issue_community_order()` executa `board.abort_task_dispatch(dispatch_lease)`.
- Na recusa tardia no Check Point 1, a ordem anterior recebe `InterruptionCause.ADMIN_CANCEL` (nunca `PERSONAL_MOVE`), evitando poluir consumidores com causa falsa. Em ambos os pontos de recusa, a unidade estabiliza em `COMMUNITY_FREE`/`IDLE`, limpa `_pending_transition_seq`, marca a ordem rejeitada como cancelada sem emitir `order_finished` para ela e jamais ressuscita a ordem anterior.

---

## 9. Revalidação de recuperação

- Para ordens `SYSTEM_RECOVERY` (`T1b`), `_revalidate_admitted_order_before_install()` revalida:
  1. Unidade na árvore, sem saída e sem lock de retirada reservada (`_is_reserved_withdrawal_locked() == false`).
  2. `order.status == UnitOrder.Status.PENDING` e `not order.is_finished()`.
  3. `UnitControlPermissions.can_perform_recovery_order(self)` (bloqueia `CHILD` e `BABY`, conforme `A01-R04`).
  4. `_revalidate_recovery_authority_post_cancel()`: instância exata da `RecoveryOrder`, `dispatcher.is_admitting_recovery(self, cancel_id, order)`, existência de `record.has_unsettled_custody()` e `ReservedWithdrawalCoordinator.validate_unit_identity_in_domain_readonly(...)`.
- Confirmado em `A01-R04` que uma unidade rebaixada para `CHILD` durante `order_finished` da `ConstructOrder` cancelada tem a `RecoveryOrder` recusada, e que ao restaurar a definição adulta a recuperação explícita (`cm.assign_cancellation_recovery`) liquida a custódia até `SETTLED`.

---

## 10. Notificações terminais

- `_emit_order_finished_once(order)` agora impõe o invariante estrito:
  `if order == null or not order.is_finished() or order.was_finished_notified(): return`
- Com isso, é estruturalmente impossível que qualquer caminho em `Unit` emita `order_finished(order)` ou marque `order._finished_notified = true` para uma ordem ainda ativa (`PENDING` ou `RUNNING`).
- Verificado em `A02-R01`, `A02-R02`, `A02-R03` (`0` sinais emitidos e `was_finished_notified() == false` sob recusa) e `A02-R04` (`1` único sinal em cancelamento normal, sem duplicação).

---

## 11. Remoção transacionalmente segura

- **Remoção controlada (`TemporaryTestWorkersController.remove_temporary_workers_safely()`):** validado em `A02-R01` que a remoção recusa (`ok=false`) enquanto `Worker3` possui `GatherTransferSession` ativa (`can_cancel_now() == false`), e só conclui (`ok=true`) após destravar e cancelar normalmente.
- **Saída efetiva da árvore (`Unit._exit_tree()`):** quando `exiting_order.cancel(_movement, REASON_UNIT_EXITED)` é recusado por lock transacional (`not exiting_order.is_finished()`), `Unit._exit_tree()` **não** incrementa `_order_revision`, **não** força `COMMUNITY_FREE`/`IDLE`, **não** marca `_finished_notified`, **não** emite `order_finished` e restaura `_current_order = exiting_order`, evitando ordens órfãs e permitindo ao protocolo `MainScene.request_controlled_teardown()` concluir a limpeza controlada após desbloquear as cargas.
- **Readmissão bloqueada na saída:** confirmado em `A02-R04` que tentativa de `issue_personal_order()` dentro do callback `order_finished` durante `_exit_tree()` retorna `false`.

---

## 12. Proteção interna das ordens

- **`ConstructOrder`:** verifica `_still_owns_unit_execution(entry_rev)` após `site.register_worker()`, após `_bind_site_signals()` (desconectando sinais se perdeu posse) e após `_unit.set_order_state(self, Unit.State.MOVING)` em `_select_and_approach_next_pile()`. Em `cancel()`, `_finish_succeeded()` e `_finish_failed()`, usa `_still_owns_movement_cleanup(entry_rev)` antes de cancelar subordem com movimento ou chamar `stop_movement()`/`set_speed_context()`.
- **`GatherResourceOrder`:** captura `entry_rev` antes de `_acquire_source_reservation()` e verifica `_still_owns_unit_execution(entry_rev)` após `mark_running()` antes de `_start_approaching_source()`.
- **`DeliverToCampOrder`:** verifica `_still_owns_delivery_execution(entry_rev)` em `_start_legacy_walk()` e `_start_selective_walk()` imediatamente após `_unit.set_order_state(self, Unit.State.TRANSPORTING)`, impedindo que entrega já substituída interrompa movimento ou deposite carga da sucessora (`A03-R04a`).
- **`RecoveryOrder`:** captura `entry_rev` no início de `_update()` e revalida `_still_owns_unit_execution(entry_rev)` após `_delegate.physics_update()`, após `del_sub.start()` e após `mv_sub.start()`, cancelando subordem obsoleta com `movement = null` e limpando `_delegate` sem interferir na sucessora (`A03-R04b`).

---

## 13. Preservação de claims e vagas

- `ConstructionSite.claim_pickup()` grava `"order"` no dicionário `_pending_pickups[uid]` usando `owner_order` (ou `unit.get_current_order()` como fallback).
- `ConstructionSite.release_pickup_claim(unit, owner_order)` recusa apagar o claim caso `_pending_pickups[uid]["order"]` pertença a uma ordem distinta.
- `ConstructionSite.unregister_worker(unit, order)` verifica `entry.get("order") == order` **antes** de chamar `release_pickup_claim(unit, order)`, garantindo que uma `ConstructOrder` antiga (`c_old`) jamais apague nem a vaga em `_assigned_workers` nem o pickup claim em `_pending_pickups` da `ConstructOrder` sucessora (`c_new`) no mesmo canteiro (`A03-R02`).

---

## 14. Conservação econômica

- `RegionalConservationAudit` (`D0-A04`) verificado com sucesso para `wood` e `stone` ao final das cadeias adversárias de **`A02`** (`test_b2_a02_exit_tree_terminal_notification_and_conservation`) e **`A03`** (`test_b2_a03_order_internal_ownership_and_claim_protection`), além da preservação integral de `test_r_03a_d3_3_regional_conservation`, `test_r_03b_b1_recovery_authority`, `test_r_03b_b2_control_mode_f03_and_reentrancy` e toda a série `T3.6.2`/`T3.6.3`.
- Evidência arquivada em `07_economic_conservation\b2_r1_conservation_green.log`.

---

## 15. Preservação dos testes históricos

- Nenhum teste histórico de `T1`, `T2`, `T3`, `UI-1`, `R-03A`, `R-03B B1` ou `R-03B B2` foi alterado, desabilitado ou enfraquecido.
- Todas as `5` suítes anteriores da `R-03B` (`27` testes, `712` asserções) e todas as `95` suítes anteriores à `R-03B` aprovaram integralmente com `0` falhas.

---

## 16. Validação estática

- Comando: `.\tools\validate.ps1` em `C:\Projetos\Dawn_of_Kin_wt_r_03b`
- Resultado: **`Validation PASSED (0 errors, 0 warnings, 229 scripts checked)`**
- `VALIDATE_EXIT=0`
- `DOCS_DESIGN_IMPORT_COUNT=0` (nenhum `.import` indevido sob `docs/design/`)
- `DIFF_CHECK_EXIT=0` (`git diff --check` limpo)
- Evidência: `08_static_validation\validate.log`

---

## 17. Regressão integral

- Comando canônico: `.\tools\run_tests.ps1 -Segmented -MaxIntegrationPerGroup 1 -GroupTimeoutSeconds 240`
- Evidência: `09_full_regression\segmented_regression.log`
- **Resumo verificado:**
  - `Batches: 72` (`PASS unit` + `PASS integration-01` .. `PASS integration-71`)
  - `Suites: 101 | Tests: 754 | Passed: 754 | Failed: 0 | SuiteErrors: 0 | Assertions: 34903`
  - `SumGodotElapsed: 1682333,8 ms | TotalWallElapsed: 1791386,0 ms`
  - `Coverage Check: Discovered=101 | ExecutedUnique=101 | Duplicates=0 | Missing=0`
  - `REGRESSION_EXIT=0`
- **Explicação das diferenças frente ao baseline `B2` (`100` suítes, `751` testes, `34.765` asserções, `71` lotes):**
  - `+1` suíte, `+1` lote, `+3` testes, `+141` asserções pela adição da suíte adversária `res://tests/integration/test_r_03b_b2_r1_focal_revalidation_and_lifecycle.gd`.
  - `-3` asserções em `res://tests/integration/test_t2_worker_cycle.gd` (`3.189 → 3.186`, mantendo `8/8` testes `PASS`), variação normal dependente da quantidade de frames físicos percorridos até a conclusão do ciclo na suíte T2 (não modificada). Saldo líquido exato: `34.765 + 141 - 3 = 34.903`. Todas as outras `99` suítes mantiveram contagem idêntica de testes e asserções.

---

## 18. Smoke da `MainScene`

- Execução isolada em `10_smoke\smoke.log` e `10_smoke\smoke_summary.json` (`SMOKE_EXIT=0`, `SMOKE_HAS_ERROR=False`, `SMOKE_HAS_WARNING=False`, `SMOKE_ELAPSED_MS=5294.2 ms`):
  - `01_clean_init`: `true`
  - `02_protagonists_commandable`: `true`
  - `03_worker3_worker4_community`: `true`
  - `04_community_work_authorized`: `true`
  - `05_personal_interruption`: `true`
  - `06_personal_control_protected`: `true`
  - `07_return_to_community_free`: `true`
  - `08_legacy_construction`: `true`
  - `09_legitimate_t1b_recovery`: `true`
  - `10_controlled_teardown`: `true`
  - Flags preservadas na `MainScene`: `use_d2_2_hud=false`, `use_provenance_economy=true`, `automatic_cancellation_recovery=true`.
- Nenhuma campanha de aceite humano ou benchmark B4 foi antecipada (sem alterações de interface/HUD).

---

## 19. Limitações

- **Sem aceite humano nem benchmarks `B4`:** conforme escopo autorizado da `B2-R1`, não foi executada bateria manual de interface nem campanha completa de desempenho (`B4`), mantendo-se o orçamento nominal do projeto (`p95 <= 16,7 ms` em CA na Intel UHD Graphics 620; exceção histórica `19,879 ms` restrita à `R-03A`).
- **Não foi introduzido polling por frame, varredura global ou fila global:** todas as guardas adicionadas são verificações `O(1)` de revisão/identidade executadas apenas em bordas de transição/callback.
- **Escopo estritamente `B2`:** o intervalo `D-05` (`PERSONAL_POST_MOVE_WAIT`), retorno automático à mesma tarefa comunitária (`Q05-B`), reavaliação após espera e indicadores visuais correspondentes permanecem fora do escopo e bloqueados até autorização expressa da **`R-03B B3`**.

---

## 20. Estado Git

- Este relatório acompanha o commit da candidata **`R-03B B2-R1`** na branch `feat/r-03b-founding-house-control-mode`, imediatamente sobre o SHA base `B2` (`4c13db72a0b7abc795d1116299b6fcd76c5e72ff`), em ancestralidade estritamente linear com `B1-R1` (`01ad509e734930763ce70f1c2b0f63de08f37b35`) e `B0-R2` (`30b791571a7594f3e1de5a2403a69a1f11713eee`).
- O SHA final exato pós-commit/push, a confirmação `HEAD == origin`, o estado limpo do worktree, a integridade de `develop`, `main`, tags e `project.godot`, bem como o manifesto determinístico SHA-256 estão registrados em `C:\Projetos\Backups\Dawn_of_Kin_Archive_Local\evidencias\R-03B\B2\R1\11_git_final\git_final_state.txt` e `C:\Projetos\Backups\Dawn_of_Kin_Archive_Local\evidencias\R-03B\B2\R1\MANIFEST_SHA256.txt`.
- Nenhum merge foi realizado, nenhuma tag foi criada e o worktree candidato `C:\Projetos\Dawn_of_Kin_wt_r_03b` permanece ativo.

---

## 21. Critério de parada

- **`R-03A`:** definitivamente encerrada.
- **`R-03B B0-R2`:** definitivamente homologada.
- **`R-03B B1-R1`:** definitivamente homologada.
- **`R-03B B2-R1`:** **candidata técnica aguardando auditoria independente — NÃO HOMOLOGADA**.
- **`R-03B B3` e `R-03B B4`:** **BLOQUEADAS**.
- **`develop`, `main` e tags:** preservadas.
- Execução encerrada imediatamente após validação técnica e publicação na branch candidata, aguardando auditoria independente do ChatGPT e decisão expressa do proprietário.
