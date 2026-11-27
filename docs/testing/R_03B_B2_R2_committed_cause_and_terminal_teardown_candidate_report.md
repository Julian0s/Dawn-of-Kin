# Dawn of Kin — R-03B B2-R2 — Relatório de Candidata Técnica (Fechamento Cirúrgico de F03: Causa Comprometida e Encerramento Controlado)

> **Status oficial:** **`CANDIDATA TÉCNICA B2-R2 — AGUARDANDO AUDITORIA INDEPENDENTE — NÃO HOMOLOGADA`**
> **Escopo:** Fechamento cirúrgico dos dois achados residuais da auditoria independente da `B2-R1` (`21397b86b65d1d6603a290c188b5de6d3088ca66`): **`B2-R2-A01` (Alto)** e **`B2-R2-A02` (Alto)**.
> **Fronteiras preservadas:** Sem reconstrução de `ControlMode`, sem alteração de `F01`/`F02` ou da estrutura principal de `F03`, sem antecipação da **`R-03B B3`** (`PERSONAL_POST_MOVE_WAIT`, temporizador `D-05`, `Q05-B`, `T1c`) ou **`R-03B B4`**, sem alteração de `develop`, `main`, tags ou documentos normativos.

---

## 1. Autorização expressa

- O proprietário autorizou exclusivamente **`R-03B B2-R2`**, restrita aos dois achados residuais identificados na auditoria independente da candidata `B2-R1`:
  - **`B2-R2-A01` (Alto):** causa comprometida de interrupção (`InterruptionCause`) registrada antes da última revalidação de autoridade (`Check Point 2`), permitindo gravar falsamente `PERSONAL_MOVE` em casos de recusa tardia ou substituição por sucessora de natureza distinta durante `order_finished`.
  - **`B2-R2-A02` (Alto):** ausência de reconciliação terminal centralizada na `Unit` para ordens cujo cancelamento inicial foi deferido pelos locks temporários de `MainScene.request_controlled_teardown()` e encerrado após o desbloqueio econômico.
- **`R-03B B3`** e **`R-03B B4`** permanecem **BLOQUEADAS**.
- Nenhum relatório anterior (`B0`, `B0-R1`, `B0-R2`, `B1`, `B1-R1`, `B2`, `B2-R1`) ou documento normativo (`AGENTS.md`, `GDD v1.3`, `ROADMAP_MESTRE.md`, `R_03B_B0_founding_house_control_mode_PLAN.md`) foi modificado.

---

## 2. Base Git

| Referência | Valor verificado | Integridade |
|---|---|---|
| Repositório | `https://github.com/Julian0s/Dawn-of-Kin` | Confirmado |
| Branch candidata | `feat/r-03b-founding-house-control-mode` | Confirmado |
| Worktree candidato | `C:\Projetos\Dawn_of_Kin_wt_r_03b` | Preservado ativo |
| SHA base `B2-R1` auditado | `21397b86b65d1d6603a290c188b5de6d3088ca66` | `HEAD == origin` no baseline (`WT_CLEAN=True`) |
| SHA `B2` anterior | `4c13db72a0b7abc795d1116299b6fcd76c5e72ff` | Ancestral linear (`exit=0`) |
| SHA `B1-R1` homologado | `01ad509e734930763ce70f1c2b0f63de08f37b35` | Ancestral linear (`exit=0`) |
| SHA `B0-R2` homologado | `30b791571a7594f3e1de5a2403a69a1f11713eee` | Ancestral linear (`exit=0`) |
| Branch `develop` protegida (`C:\Projetos\Dawn of Kin`) | `94c718024359dc7ff8360949313969b3ceaf9776` | Intacta (`DEVELOP_OK=True`) |
| Branch `main` protegida | `25e0a20f1d6a2f10a9e059afe69759fbe263db4a` | Intacta (`MAIN_OK=True`) |
| Tags preservadas | `t1-complete` (`3dcbba9386cbbee70025b47f4254ef097688a6e1`), `t2-complete` (`049ba9c7714c9b90b5515ae6ac30a28830454773`), `t3-3-complete` (`c7947c9630c102a9d77603cac0bae68678247c95`) | Intactas |
| Arquivo local protegido `C:\Projetos\Dawn of Kin\project.godot` | `SHA-256 = AEEFDA2810DA5C4EDFA9BF5F2A47A5841F8597238C8DAB4C2E202FAF70307613` | Intacto (`PROJ_OK=True`) |
| Manifesto anterior `B2-R1` (`evidencias\R-03B\B2\R1\MANIFEST_SHA256.txt`) | `SHA-256 = 22325B1A88E5E12D79074383495FC7BEA1AD8B6F3B82B3F6AB6BD04D534B4338` | Intacto (`PRIOR_B2_R1_MANIFEST_OK=True`) |

---

## 3. Escopo estritamente focal

Apenas **3 scripts de produção** receberam ajustes cirúrgicos (`+159 / -24` linhas), acompanhados de **1 suíte adversária nova** (+ `.uid`) e este relatório:

- **Produção modificada (`3` arquivos):**
  - `src/units/orders/unit_order.gd` (`+9 / -0`): guarda single-shot `_interruption_cause_notified`, `was_interruption_cause_notified()`, `mark_interruption_cause_notified()` (preservando `set_interruption_cause()` estritamente write-once).
  - `src/units/unit.gd` (`+136 / -19`): adiamento do commit de `InterruptionCause` até o ponto de não retorno (`Check Point 2` / entrada do Estágio 3 / recusa / cancelamento administrativo), sinal `order_interruption_cause_committed(order, cause)` single-shot, e protocolo autenticado por token de teardown controlado (`_begin_controlled_teardown()`, `_clear_controlled_teardown_token()`, `_finalize_controlled_teardown_order()`).
  - `src/main/main.gd` (`+14 / -5`): criação de token `RefCounted` único por `request_controlled_teardown()`, registro via `unit._begin_controlled_teardown(token)` e delegação pós-desbloqueio via `unit._finalize_controlled_teardown_order(token, ord, rev)` no lugar de `entry.order.cancel()` direto.
- **Testes novos (`1` suíte + `.uid`):**
  - `tests/integration/test_r_03b_b2_r2_committed_cause_and_terminal_teardown.gd`
  - `tests/integration/test_r_03b_b2_r2_committed_cause_and_terminal_teardown.gd.uid`
- **Verificação negativa de antecipação `B3`:** `FORBIDDEN_B3_SRC_HITS=0` em `src/`.

---

## 4. Reprodução de A01

Executado antes de qualquer alteração de produção sobre o baseline intacto `21397b86b65d1d6603a290c188b5de6d3088ca66` (`evidencias\R-03B\B2\R2\02_red\red_b2_r2_behavioral_on_b2_r1.log`, `RED_BEHAVIORAL_EXIT=1`):

1. **`B2-R2-A01-R01` reproduzido:** com `LeaderA` executando coleta comunitária real (via `CommunityWorkBoard` + `CommunityTaskDispatcher`), `MoveOrder` solicitada e afiliação rebaixada para `COMMUNITY` dentro de `order_finished`, `Check Point 2` rejeitou `MoveOrder` (`ok=false`), mas a coleta comunitária permaneceu carimbada com `InterruptionCause.PERSONAL_MOVE (1)`.
2. **`B2-R2-A01-R03` reproduzido:** com `LeaderA` executando coleta comunitária real, tentativa externa `MoveOrder` e callback de `order_finished` instalando legitimamente `GatherResourceOrder` pessoal (`PERSONAL_OTHER`), `succ_gather` assumiu a unidade (`ok=false`, `current_is_succ=true`), mas a coleta comunitária permaneceu carimbada com `InterruptionCause.PERSONAL_MOVE (1)` da tentativa preterida em vez de `PERSONAL_OTHER (2)`.

---

## 5. Solução para a causa comprometida

- Em `src/units/unit.gd`, foi introduzido `_awaiting_interruption_cause_order: UnitOrder = null` (mantendo `_cancelling_order` exclusivamente para prevenir cancelamento recursivo durante `previous_order.cancel()`) e os helpers `_commit_interruption_cause(target, cause)` e `_emit_interruption_cause_committed_once(order)`.
- No Estágio 2 de `_install_admitted_order()`:
  - **Check Point 1 (após `previous_order.cancel()`):** se recusar, grava definitivamente `ADMIN_CANCEL`, emite `order_finished` (1×) e `order_interruption_cause_committed` (1×), e retorna `false`. Se aprovar, avança `_order_revision` e aplica estado interno alvo **sem carimbar `PERSONAL_MOVE`/`PERSONAL_OTHER` ainda**.
  - **Emissão de `order_finished(previous_order)`:** executa normalmente antes do Check Point 2, preservando a limpeza imediata de registros antigos e a capacidade legítima de callbacks invalidarem a tentativa ou instalarem uma sucessora.
  - **Perda de autoridade para sucessora reentrante (`A01-R03`, `A01-R06`):** quando a sucessora legítima entra no Estágio 3, ela própria consome `_awaiting_interruption_cause_order` e grava de forma write-once a sua causa real (ex.: `PERSONAL_OTHER` ou `PERSONAL_MOVE`); se o preemptor foi cancelamento administrativo ou saída sem causa, aplica-se `ADMIN_CANCEL`.
  - **Check Point 2 (após `order_finished`):** se recusar (`A01-R01`, `A01-R02`), grava de forma write-once `ADMIN_CANCEL` (nunca `PERSONAL_MOVE`), estabiliza em `COMMUNITY_FREE`/`IDLE`, publica `control_mode_changed` e emite `order_interruption_cause_committed(previous_order, ADMIN_CANCEL)`.
  - **Entrada do Estágio 3 (ponto de não retorno — `A01-R04`, `A01-R05`):** somente após Check Point 2 aprovar é que `_commit_interruption_cause(cause_target, _interruption_cause_for(order, origin))` grava `PERSONAL_MOVE`/`PERSONAL_OTHER`/`SYSTEM_RECOVERY` de forma write-once, antes de `order.start()`. Se `order.start()` falhar sincronamente (`A01-R05`), `order` **foi** efetivamente admitida (falha pós-admissão, distinta de recusa pré-instalação), portanto `previous_order` preserva `PERSONAL_MOVE`, não é ressuscitada, e `order` conclui como `FAILED` com sua própria notificação `order_finished`.
- `UnitOrder.set_interruption_cause()` permanece estritamente write-once (nunca há sobrescrita de causa já gravada).

---

## 6. Justificativa da fronteira de comprometimento escolhida

Existia uma tensão causal inevitável entre três requisitos simultâneos:
1. Emitir `order_finished(previous_order)` **antes** da instalação efetiva de `order` (exigido pelo protocolo `B0-R2 §14.2`, por todos os testes `B2-R1 A01-R01..R05` e pela especificação `B2-R2 §8 A01-R01/A01-R03`, onde callbacks em `order_finished` invalidam ou substituem a tentativa antes de `Check Point 2`).
2. Permitir que `Check Point 2` rejeite `order` ou ceda posse a uma sucessora de outra natureza instalada dentro de `order_finished`.
3. Impedir que `InterruptionCause` seja gravada falsamente por intenção inicial ou sobrescrita depois de publicada.

Mover `order_finished(previous_order)` para depois do Estágio 3 quebraria `Check Point 2` e faria `MoveOrder` iniciar antes de os callbacks de `order_finished` terem chance de rejeitá-la (violando `B2-R1 A01-R01..R04` e `B2-R2 §8`). Gravar `PERSONAL_MOVE` antes de `order_finished` e sobrescrever depois violaria o contrato write-once (§6 e §10).

A separação adotada — **limpeza imediata via `order_finished(previous_order)` no Estágio 2** + **comprometimento write-once de `InterruptionCause` na fronteira de não retorno (rejeição em Check Point 1/2 ou entrada do Estágio 3)** + **publicação única pós-estabilização via `order_interruption_cause_committed(order, cause)`** — resolve integralmente a tensão sem alterar o comportamento público de `order_finished`, sem sobrescrever causa e oferecendo à futura **`R-03B B3`** um sinal determinístico com causa definitiva e imutável.

---

## 7. Preservação dos consumidores de `order_finished`

- **`CommunityTaskDispatcher` (`src/rts/community_task_dispatcher.gd`):** continua recebendo `order_finished(previous_order)` exatamente uma vez no Estágio 2, limpando imediatamente `task.assigned_unit`/`task.assigned_order` e agendando `request_dispatch()` diferido. A política histórica de `excluded_unit_ids` (`Q05`) permanece intocada até a `B3` (quando `order_interruption_cause_committed` fornecerá a causa definitiva sem ambiguidade).
- **`CancellationRecoveryDispatcher` (`src/units/cancellation_recovery_dispatcher.gd`):** continua recebendo `order_finished(order)` exatamente uma vez, atualizando `entry.order = null`, `entry.manual` e `entry.revision = unit.get_order_revision()` sem alteração de contrato.
- **Todos os ouvintes em testes históricos (`T1`–`T3`, `R-03A`, `B1`, `B2`, `B2-R1`):** 100% preservados sem modificação de um único teste existente.

---

## 8. Reprodução de A02

Executado sobre o baseline intacto `21397b86b65d1d6603a290c188b5de6d3088ca66` (`evidencias\R-03B\B2\R2\02_red\red_b2_r2_behavioral_on_b2_r1.log`):

- **`B2-R2-A02-R01` reproduzido:** invocando diretamente `MainScene.request_controlled_teardown()` com `LeaderA` executando `GatherResourceOrder` em modo proveniência (mochila vazia, preflight aprovado), os locks temporários do próprio teardown (`load._coordinator_transaction_locked = true; load._provenance_busy = true`) impediram legitimamente o cancelamento em `Unit._exit_tree()`. Após o desbloqueio, `main.gd` chamava `entry.order.cancel()` diretamente fora da `Unit`, encerrando a ordem mas deixando `cur_non_null=true`, `rev=1->1`, `mode=1 (COMMUNITY_WORKING)`, `fin_events=0`, `notified=false` e `cause=0 (NONE)`.

---

## 9. Encerramento controlado da `MainScene`

Em `src/main/main.gd` (`request_controlled_teardown()`):
1. `preflight_economic_teardown()` e verificação de domínio regional permanecem **100% preservados** antes de qualquer mutação.
2. Cria-se um token `RefCounted` único (`var teardown_token := RefCounted.new()`) exclusivo daquela chamada de encerramento.
3. Para cada unidade retornada por `get_units()`, registra-se `unit._begin_controlled_teardown(teardown_token)` **antes** de travar `load._coordinator_transaction_locked`/`_provenance_busy`, preservando `{unit, order, revision}`.
4. `_teardown_community_work()`, `get_parent().remove_child(self)` e o desbloqueio dos locks temporários mantêm a sequência exata original.
5. Após o desbloqueio, em vez de `entry.order.cancel()`, cada entrada delega a `teardown_unit._finalize_controlled_teardown_order(teardown_token, teardown_order, teardown_rev)` se `teardown_order.is_active()`, ou limpa o token via `_clear_controlled_teardown_token(teardown_token)` se a ordem já foi concluída em `_exit_tree()` (`A02-R04`).
6. Seguem-se `storage.cleanup()`, `ReservedWithdrawalCoordinator.release_regional_domain(...)` e `queue_free()`.

---

## 10. Reconciliação terminal

Em `src/units/unit.gd`, `_finalize_controlled_teardown_order(token, expected_order, expected_revision)` valida simultaneamente:
1. Autenticidade e consumo imediato de `token` (`_controlled_teardown_token == token`, imediatamente zerado para impedir reentrância ou reuso).
2. Contexto real de saída da árvore (`_is_exiting_tree and not is_inside_tree()`).
3. Identidade exata de ordem e revisão (`_current_order == expected_order and _order_revision == expected_revision`).
4. Ordem ativa e legitimamente cancelável após desbloqueio (`expected_order.is_active() and not _is_reserved_withdrawal_locked() and expected_order.can_cancel_now()`).
5. Execução real de `expected_order.cancel(_movement, UnitOrder.REASON_UNIT_EXITED)` e verificação de estado terminal verdadeiro (`expected_order.is_finished()`); em caso de recusa residual, restaura `_current_order = expected_order` sem forjar término nem emitir sinal falso.
6. Em término efetivo: grava `InterruptionCause.ADMIN_CANCEL` (se `CANCELLED`), incrementa `_order_revision += 1`, transita `ControlMode` para `COMMUNITY_FREE`/`OrderOrigin.NONE`, aplica `State.IDLE`, `reset_work_visuals()`, publica `control_mode_changed`, emite `_emit_order_finished_once()` (exatamente 1×) e `_emit_interruption_cause_committed_once()` (exatamente 1×).
7. Qualquer tentativa de readmissão (`issue_personal_order`, `issue_community_order`, `issue_recovery_order`) durante o callback terminal é bloqueada por `_is_exiting_tree == true` e `not is_inside_tree()`, e qualquer chamada externa com token forjado é rejeitada (`A02-R01`, `A02-R05`).

---

## 11. Preservação econômica

- `MainScene.preflight_economic_teardown()` permanece 100% intacto: confirmado em `A02-R03a` que custódia de cancelamento não liquidada recusa `request_controlled_teardown()` com `reason == "pending_cancellation_custody"`, preservando cena, `RecoveryOrder` e custódia intactos.
- `RegionalConservationAudit` (`D0-A04`) verificado nos pontos estáveis anteriores à destruição em `A02-R01` (pedra), `A02-R02` (madeira em canteiro ativo com mochila vazia) e `A02-R03b` (madeira após liquidação legítima `SETTLED`).
- `ReservedWithdrawalCoordinator.release_regional_domain(...)` comprovado com `ok == true` após cada encerramento controlado legítimo (`A02-R01`, `A02-R02`, `A02-R03b`, `A02-R06`), sem comparar cegamente domínio destruído com snapshot ativo.

---

## 12. Matriz de fechamento (§21)

| Achado/subcenário | Precondições | RED | Correção | GREEN | Contrato preservado |
|---|---|---|---|---|---|
| **A01-R01** (Perda de `FOUNDING_HOUSE` → `COMMUNITY` durante `order_finished` de coleta comunitária real) | Fundador adulto em coleta comunitária real (`Board`+`Dispatcher`); `MoveOrder` solicitada; callback `order_finished` rebaixa para `COMMUNITY` | **Reproduzido em RED** (`red_b2_r2_behavioral_on_b2_r1.log`): `InterruptionCause=1 (PERSONAL_MOVE)` falso apesar de `ok=false` | Adiar commit de causa para depois do Check Point 2; recusa no Check Point 2 grava `ADMIN_CANCEL` write-once + `order_interruption_cause_committed` | `PASS` (`test_r_03b_b2_r2`, `BEHAVIORAL_GREEN_EXIT=0`) | `MoveOrder` não instalada; `comm1` finalizada (`1×` `order_finished`); causa `ADMIN_CANCEL`; `COMMUNITY_FREE`/`IDLE`; `task1` limpa |
| **A01-R02a / A01-R02b** (Rebaixamento etário `BABY` ou `_coordinator_transaction_locked = true` durante `order_finished`) | Fundador adulto em coleta comunitária real; `MoveOrder` solicitada; callback `order_finished` aplica `BABY` ou lock de retirada | Mesma janela prematura do Check Point 1 reproduzida em `A01-R01` | Mesma fronteira Check Point 2 → `ADMIN_CANCEL` | `PASS` (`A01-R02a`, `A01-R02b`) | Recusa preservada (`REASON_AGE_RESTRICTED_TASK` / `REASON_UNIT_TRANSACTION_LOCKED`), causa `ADMIN_CANCEL`, `0` duplicação |
| **A01-R03** (Tentativa `MoveOrder` preterida por `GatherResourceOrder` pessoal instalada durante `order_finished`) | Fundador adulto em coleta comunitária real; `MoveOrder` solicitada; callback `order_finished` instala `GatherResourceOrder` pessoal | **Reproduzido em RED** (`red_b2_r2_behavioral_on_b2_r1.log`): `InterruptionCause=1 (PERSONAL_MOVE)` em vez de `PERSONAL_OTHER (2)` | `_awaiting_interruption_cause_order` consumida pela sucessora real no Estágio 3 → `PERSONAL_OTHER` write-once | `PASS` (`A01-R03`, `BEHAVIORAL_GREEN_EXIT=0`) | Sucessora `GatherResourceOrder` intacta (`PERSONAL_ACTIVE`, vaga preservada); `comm3` com `PERSONAL_OTHER`; `1×` `order_finished` |
| **A01-R04** (`MoveOrder` pessoal legítima interrompendo coleta comunitária real) | Fundador adulto em coleta comunitária real; `MoveOrder` pessoal válida sem callback adversário | Caminho normal preservado | Check Point 2 aprova → Estágio 3 grava `PERSONAL_MOVE` write-once + emite `order_interruption_cause_committed` | `PASS` (`A01-R04`) | `MoveOrder` instalada (`PERSONAL_ACTIVE`), `comm4` com `PERSONAL_MOVE` (`1×`), pronto para `B3`/`Q05-B` |
| **A01-R05** (Falha síncrona em `MoveOrder.start()` após admissão vs recusa pré-instalação) | Fundador adulto em coleta comunitária real; `MoveOrder(NAN)` passa Check Point 2 e falha em `start()` | Verificação de distinção contratual | Commit de `PERSONAL_MOVE` ocorre na admissão ao Estágio 3 (antes de `start()`), mantendo distinção de recusa pré-instalação (`ADMIN_CANCEL`) | `PASS` (`A01-R05`) | `bad_mv` fica `FAILED` (`1×` `order_finished`), `comm5` não é ressuscitada e preserva `PERSONAL_MOVE`, unidade estabiliza `COMMUNITY_FREE`/`IDLE` |
| **A01-R06** (Reentrância durante `cancel()`: `worker_slot_released` e `ConstructOrder` `workers_changed`) | Sucessora de outra natureza instalada durante `GatherResourceOrder.cancel()` ou `ConstructOrder.cancel()` | Cobertura de preservação e simetria | `_awaiting_interruption_cause_order` ativa desde `cancel()` garante que sucessora real grave sua própria causa (`PERSONAL_OTHER` / `PERSONAL_MOVE`) | `PASS` (`A01-R06a`, `A01-R06b`) | Zero gravação prematura, sucessoras intactas, `1×` notificação terminal |
| **A02-R01** (`MainScene.request_controlled_teardown()` com `GatherResourceOrder` proveniência ativa) | `MainScene` real, `LeaderA` em `GatherResourceOrder` comunitária, mochila vazia (preflight ok), locks temporários do teardown bloqueiam `_exit_tree()` | **Reproduzido em RED** (`red_b2_r2_behavioral_on_b2_r1.log`): `cur_non_null=true`, `rev=1->1`, `mode=1`, `fin_events=0`, `notified=false`, `cause=0` | Token `RefCounted` + `Unit._begin_controlled_teardown()` + `Unit._finalize_controlled_teardown_order()` após desbloqueio | `PASS` (`A02-R01`, `BEHAVIORAL_GREEN_EXIT=0`) | `_current_order=null`, `rev+1`, `COMMUNITY_FREE`/`IDLE`, `ADMIN_CANCEL`, `1×` `order_finished`, vaga liberada, token forjado rejeitado, `D0-A04` preservado |
| **A02-R02** (`MainScene.request_controlled_teardown()` com `ConstructOrder` ativa e mochila vazia) | `ConstructOrder` real, mochila vazia (preflight ok), canteiro com registro de trabalhador | Lacuna de cobertura sobre teardown real de `ConstructOrder` | Mesmo protocolo centralizado de teardown + limpeza de trabalhador/claim | `PASS` (`A02-R02`) | `D0-A04` antes do teardown, `1×` `order_finished`, trabalhador e claim removidos, `ADMIN_CANCEL`, domínio liberado, cena destruída |
| **A02-R03a / A02-R03b** (`RecoveryOrder`: recusa legítima por custódia pendente vs teardown pós-liquidação) | Cancelamento real de canteiro criando custódia e `RecoveryOrder`; teste antes e depois de `SETTLED` | Preservação do preflight econômico e verificação pós-liquidação | `preflight_economic_teardown()` 100% preservado; após `SETTLED`, teardown reconcilia `RecoveryOrder` se ainda ativa ou finaliza limpo | `PASS` (`A02-R03a`, `A02-R03b`) | Recusa `pending_cancellation_custody` intacta; `D0-A04` madeira preservado; domínio liberado e cena destruída após `SETTLED` |
| **A02-R04** (Ordem não bloqueada — `MoveOrder` concluída já em `_exit_tree()`) | `LeaderB` com `MoveOrder` ativa durante `request_controlled_teardown()` | Proteção contra regressão de notificação duplicada | `_exit_tree()` consome token e finaliza; pós-desbloqueio vê `not is_active()` e não reemite | `PASS` (`A02-R04`) | `1×` `order_finished`, `rev+1`, `_current_order=null`, zero duplicação |
| **A02-R05** (Callbacks durante notificação terminal do teardown tentando readmissão) | Listener em `order_finished` de `LeaderA` tenta `issue_personal_order()` e `issue_community_order()` | Proteção contra reativação em teardown | `_is_exiting_tree == true`, `not is_inside_tree()` e `_teardown_community_work()` bloqueiam ambas as readmissões | `PASS` (`A02-R05`) | Ambas retornam `false`, board desligado permanece vazio, nenhuma atribuição nova |
| **A02-R06** (Cena e unidades efetivamente destruídas após `queue_free()`, ordem de eventos e liberação regional) | Aguarda frames de processo após `request_controlled_teardown()` | Verificação de ciclo de vida completo até destruição real | `ev_log` determinístico + `release_regional_domain.ok == true` + `not is_instance_valid(main/unit)` | `PASS` (`A02-R06`) | Ordem `["lb_order_finished", "la_order_finished", "la_cause_committed"]`, domínio regional liberado, cena e unidades efetivamente destruídas |

---

## 13. RED e GREEN

| Execução | Comando | Exit Code | Duração | Resultado verificado | Log |
|---|---|---|---|---|---|
| **RED comportamental** (baseline `21397b8`) | `Invoke-Godot --headless ... b2_r2_behavioral_red.gd` | `1` | `10.380,2 ms` | `B2_R2_BEHAVIORAL_RED_FAILURES=3` (`A01-R01`, `A01-R03`, `A02-R01`), `HAS_ERROR=False` | `02_red\red_b2_r2_behavioral_on_b2_r1.log` |
| **GREEN focal `B2-R2`** | `.\tools\run_tests.ps1 -Filter test_r_03b_b2_r2` | `0` | `32.847,7 ms` | `1/1` suíte, `2/2` testes, `158` asserções (`88 + 70`), `0` falhas, `0` erros | `05_green\b2_r2_tests_green.log` |
| **Campanha consolidada `R-03B`** | `.\tools\run_tests.ps1 -Filter test_r_03b_b` | `0` | `47.391,6 ms` | `7/7` suítes, `32/32` testes, `1.011` asserções, `0` falhas, `0` erros | `05_green\b1_and_b2_all_green.log` |
| **RED → GREEN comportamental** | `Invoke-Godot --headless ... b2_r2_behavioral_red.gd` | `0` | `9.325,5 ms` | `B2_R2_BEHAVIORAL_RED_FAILURES=0`, `HAS_ERROR=False` | `05_green\behavioral_red_turned_green.log` |

---

## 14. Preservação dos testes anteriores

- **Zero** testes históricos modificados, removidos ou enfraquecidos.
- Todas as `6` suítes anteriores da `R-03B` (`30` testes, `853` asserções) e todas as `95` suítes anteriores à `R-03B` passaram integralmente com `0` falhas e `0` erros de suíte.
- Exclusões históricas `Q05` preservadas sem antecipação da `B3`.

---

## 15. Validação estática

- Comando: `.\tools\validate.ps1` em `C:\Projetos\Dawn_of_Kin_wt_r_03b`
- Resultado: **`Validation PASSED (0 errors, 0 warnings, 230 scripts checked)`**
- `VALIDATE_EXIT=0`
- `DOCS_DESIGN_IMPORT_COUNT=0`
- `DIFF_CHECK_EXIT=0` (`git diff --check` limpo)
- Evidência: `07_static_validation\validate.log`

---

## 16. Regressão integral

- Comando canônico: `.\tools\run_tests.ps1 -Segmented -MaxIntegrationPerGroup 1 -GroupTimeoutSeconds 240`
- Evidência: `08_full_regression\segmented_regression.log`
- **Resumo verificado:**
  - `Batches: 73` (`PASS unit` + `PASS integration-01` .. `PASS integration-72`)
  - `Suites: 102 | Tests: 756 | Passed: 756 | Failed: 0 | SuiteErrors: 0 | Assertions: 35063`
  - `SumGodotElapsed: 1673647,5 ms | TotalWallElapsed: 1780876,4 ms`
  - `Coverage Check: Discovered=102 | ExecutedUnique=102 | Duplicates=0 | Missing=0`
  - `REGRESSION_EXIT=0`
- **Explicação das diferenças frente ao baseline `B2-R1` (`101` suítes, `754` testes, `34.903` asserções, `72` lotes):**
  - `+1` suíte, `+1` lote, `+2` testes, `+158` asserções pela adição da suíte `res://tests/integration/test_r_03b_b2_r2_committed_cause_and_terminal_teardown.gd`.
  - `+2` asserções em `res://tests/integration/test_t2_worker_cycle.gd` (`3.186 → 3.188`, `8/8 PASS`), variação conhecida dependente de ticks de física naquela suíte histórica (não modificada). Saldo líquido exato: `34.903 + 158 + 2 = 35.063`. Todas as demais `100` suítes mantiveram contagens idênticas.

---

## 17. Smoke da `MainScene`

- Execução isolada em `09_smoke\smoke.log` e `09_smoke\smoke_summary.json` (`SMOKE_EXIT=0`, `SMOKE_HAS_ERROR=False`, `SMOKE_HAS_WARNING=False`, `SMOKE_ELAPSED_MS=11397.1 ms`):
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
  - `11_controlled_teardown_terminal_reconciliation`: `true`
  - Flags preservadas na `MainScene`: `use_d2_2_hud=false`, `use_provenance_economy=true`, `automatic_cancellation_recovery=true`.

---

## 18. Limitações

- **Sem aceite humano nem campanha `B4`:** nenhuma alteração visual/UI foi realizada; aceite manual e benchmarks completos permanecem reservados à `B4`, preservando o orçamento nominal de `p95 <= 16,7 ms` em CA na Intel UHD Graphics 620 (exceção histórica `19,879 ms` restrita à `R-03A`).
- **Consumo de `order_interruption_cause_committed` na `B3`:** o sinal `order_interruption_cause_committed` está pronto, testado e garantido single-shot na `Unit`, mas a alteração da regra de exclusão comunitária `B0-Q05 B` em `CommunityTaskDispatcher` permanece estritamente reservada à **`R-03B B3`** (conforme §10 e §18).
- **Zero custo por frame:** nenhum polling, varredura global ou fila global foi introduzido.

---

## 19. Integridade Git

- Commit cirúrgico na branch `feat/r-03b-founding-house-control-mode` diretamente sobre `21397b86b65d1d6603a290c188b5de6d3088ca66`, em ancestralidade linear com `B2` (`4c13db72...`), `B1-R1` (`01ad509e...`) e `B0-R2` (`30b79157...`).
- SHA final publicado, confirmação `HEAD == origin`, estado limpo do worktree, preservação de `develop`, `main`, tags, `project.godot` e manifestos anteriores estão registrados em `evidencias\R-03B\B2\R2\10_git_final\git_final_state.txt` e no manifesto determinístico `evidencias\R-03B\B2\R2\MANIFEST_SHA256.txt`.
- Nenhum merge foi executado, nenhuma tag foi criada e o worktree `C:\Projetos\Dawn_of_Kin_wt_r_03b` permanece ativo.

---

## 20. Critério de parada

- **`R-03A`:** definitivamente encerrada.
- **`R-03B B0-R2`:** definitivamente homologada.
- **`R-03B B1-R1`:** definitivamente homologada.
- **`R-03B B2-R2`:** **CANDIDATA TÉCNICA B2-R2 — AGUARDANDO AUDITORIA INDEPENDENTE — NÃO HOMOLOGADA**.
- **`R-03B B3` e `R-03B B4`:** **BLOQUEADAS**.
- **`develop`, `main` e tags:** preservadas.
- Execução encerrada imediatamente após publicação na branch candidata, aguardando auditoria independente do ChatGPT e decisão expressa do proprietário.
