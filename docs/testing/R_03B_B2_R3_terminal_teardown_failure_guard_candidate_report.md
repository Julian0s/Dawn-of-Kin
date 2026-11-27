# Dawn of Kin — R-03B B2-R3 — Relatório de Candidata Técnica (Fechamento Defensivo do Teardown e Cobertura de Recuperação)

> **Status oficial:** **`CANDIDATA TÉCNICA B2-R3 — AGUARDANDO AUDITORIA INDEPENDENTE — NÃO HOMOLOGADA`**
> **Escopo:** Revisão mínima **`R-03B B2-R3`**, limitada estritamente ao tratamento defensivo da falha de finalização terminal durante `MainScene.request_controlled_teardown()` (**`B2-R3-A01`**) e ao fortalecimento da cobertura determinística de `RecoveryOrder` no teardown controlado (**`B2-R3-A02`**).
> **Fronteiras preservadas:** Contrato de eventos `B2-R2` ratificado e intocado; sem reabrir `InterruptionCause`, sem reimplementar `ControlMode`, sem reconstruir `F03`, e com **`R-03B B3`** e **`R-03B B4`** integralmente **BLOQUEADAS**.

---

## 1. Autorização expressa

- O proprietário autorizou exclusivamente a revisão mínima **`R-03B B2-R3`**, restrita a:
  1. Tratamento explícito da falha de finalização terminal durante `MainScene.request_controlled_teardown()` (`B2-R3-A01`).
  2. Fortalecimento da cobertura correspondente, incluindo recuperação econômica (`B2-R3-A02`).
- Nenhum documento normativo (`AGENTS.md`, `docs/Dawn_of_Kin_GDD.md`, `docs/ROADMAP_MESTRE.md`, `docs/architecture/R_03B_B0_founding_house_control_mode_PLAN.md`) ou relatório anterior foi modificado.

---

## 2. Ratificação do contrato de eventos B2-R2

Fica formalmente registrada a ratificação expressa pelo proprietário da separação de eventos introduzida na `B2-R2`:

- **`order_finished(order)`:** comunica o encerramento legítimo da ordem e autoriza a limpeza imediata dos registros correspondentes (`WorkTask`, `CancellationRecoveryDispatcher`).
- **`order_interruption_cause_committed(order, cause)`:** comunica a causa definitiva e imutável da interrupção quando comprometida no ponto de não retorno.
- **Diretriz vinculante para a futura `R-03B B3`:** a `B3` não deverá presumir que `InterruptionCause` já esteja disponível dentro de todo callback de `order_finished`, devendo correlacionar os eventos pela identidade da instância de `UnitOrder` sem depender de ordem arbitrária de listeners.
- Na `B2-R3`, a implementação `B2-R2` desse contrato permanece 100% intacta e o `CommunityTaskDispatcher` não foi alterado para consumir o novo sinal nem antecipar `B0-Q05 B`.

---

## 3. Base Git

| Referência | Valor verificado | Integridade |
|---|---|---|
| Repositório | `https://github.com/Julian0s/Dawn-of-Kin` | Confirmado |
| Branch candidata | `feat/r-03b-founding-house-control-mode` | Confirmado |
| Worktree candidato | `C:\Projetos\Dawn_of_Kin_wt_r_03b` | Preservado ativo |
| SHA base `B2-R2` auditado | `b6adb45d0a2300fc0c50a358204fc9c137eb468c` | `HEAD == origin` no baseline (`WT_CLEAN=True`) |
| Ancestrais lineares verificados | `B2-R1` (`21397b86...`), `B1-R1` (`01ad509e...`), `B0-R2` (`30b79157...`) | `exit=0` |
| Branch `develop` protegida (`C:\Projetos\Dawn of Kin`) | `94c718024359dc7ff8360949313969b3ceaf9776` | Intacta (`DEVELOP_OK=True`) |
| Branch `main` protegida | `25e0a20f1d6a2f10a9e059afe69759fbe263db4a` | Intacta (`MAIN_OK=True`) |
| Tags preservadas | `t1-complete`, `t2-complete`, `t3-3-complete` | Intactas |
| Arquivo local protegido `C:\Projetos\Dawn of Kin\project.godot` | `SHA-256 = AEEFDA2810DA5C4EDFA9BF5F2A47A5841F8597238C8DAB4C2E202FAF70307613` | Intacto (`PROJ_OK=True`) |
| Manifesto anterior `B2-R2` (`evidencias\R-03B\B2\R2\MANIFEST_SHA256.txt`) | `SHA-256 = 4D9DCDF969C1DC7F42454B319C7CA06BE69B942F6B8791F698071E3664E723A0` | Intacto (`PRIOR_B2_R2_MANIFEST_OK=True`) |

---

## 4. Achado residual (`B2-R3-A01` e `B2-R3-A02`)

1. **`B2-R3-A01` (`src/main/main.gd` + `src/units/unit.gd`):** na candidata `B2-R2`, `MainScene.request_controlled_teardown()` invocava `teardown_unit._finalize_controlled_teardown_order(teardown_token, teardown_order, teardown_rev)` ignorando o retorno booleano e prosseguia incondicionalmente com `storage.cleanup()`, `ReservedWithdrawalCoordinator.release_regional_domain()`, `queue_free()` e retorno `{"ok": true}`. Adicionalmente, `Unit._finalize_controlled_teardown_order()` consumia `_controlled_teardown_token = null` logo no início, antes de checar locks recuperáveis (`can_cancel_now() == false` ou `_is_reserved_withdrawal_locked()`).
2. **`B2-R3-A02` (`tests/integration/test_r_03b_b2_r2_committed_cause_and_terminal_teardown.gd`):** no cenário `A02-R03b`, o teste ramificava (`if not rec3_was_still_active ... else ...`) porque em um trabalhador solo a liquidação da custódia e o encerramento de `RecoveryOrder` tendem a coincidir no mesmo tick de física, deixando o ramo com `RecoveryOrder` ainda ativa dependente de condição em tempo de execução.

---

## 5. Reprodução

Sobre o baseline intacto `b6adb45d0a2300fc0c50a358204fc9c137eb468c` (`evidencias\R-03B\B2\R3\01_red\red_b2_r3_behavioral_on_b2_r2.log`, `RED_BEHAVIORAL_EXIT=1`, `7.476,8 ms`):

- **`B2-R3-A01` reproduzido comportamentalmente:** com `LeaderA` executando `GatherResourceOrder` comunitária real (mochila vazia — `preflight_economic_teardown()` retorna `ok=true`) e `_active_gather_session.is_executing = true` (`can_cancel_now() == false` após o desbloqueio do teardown), `MainScene.request_controlled_teardown()` ignorou a falha de finalização e executou:
  - `td_ok = true` (sucesso falso);
  - `queued_for_del = true` (`queue_free()` enfileirado com ordem ainda ativa);
  - `g1_active = true`, `fin_events = 0`, `token_kept = false` (token irreversivelmente destruído mesmo em recusa recuperável).
- **Sonda `B2-R3-A02` na mesma execução:** utilizando dois fundadores (`LeaderA` e `LeaderB`) no mesmo canteiro cancelado (`PROBE_TWO_WORKER_RECOVERY`), comprovou-se que o cenário de custódia `SETTLED` + `preflight_economic_teardown() == true` + `RecoveryOrder` do par ainda `is_active() == true` (`a=true, b=false, preflight=true`) é **naturalmente alcançável** pelo fluxo real do jogo.

---

## 6. Correção mínima

Apenas **2 arquivos de produção** receberam ajustes cirúrgicos (`+153 / -17` linhas no total):

1. **`src/units/unit.gd` (`+4 / -1` dentro de `_finalize_controlled_teardown_order()`):**
   - Mantém `_controlled_teardown_token` intacto quando a recusa decorre de bloqueio transacional recuperável (`_is_reserved_withdrawal_locked()`, `not expected_order.can_cancel_now()` ou `not expected_order.is_finished()` após `cancel()`).
   - Consome `_controlled_teardown_token = null` apenas quando `expected_order.is_finished()` é alcançado (ou quando a ordem já não está ativa), preservando a única possibilidade legítima de reconciliação pós-desbloqueio sem criar qualquer API global.
2. **`src/main/main.gd` (`+149 / -16` em `request_controlled_teardown()` e helpers locais privados):**
   - Adiciona `_pending_controlled_teardown: Dictionary`, `complete_pending_controlled_teardown() -> Dictionary` e `_reconcile_controlled_teardown(ctx)`.
   - Avalia obrigatoriamente o retorno e as pós-condições reais de cada entrada em `orders` e de todas as unidades em `units_snapshot`, classificando falhas em: `transactional_finalization_refused`, `incompatible_identity` (`teardown_token_mismatch` / `order_or_revision_mismatch`), `incompatible_context`, `order_still_active`, `unreconciled_terminal_record` ou `domain_release_failed`.
   - Aceita como sucesso somente ordens comprovadamente reconciliadas (`_is_unit_reconciled_after_teardown()`), incluindo aquelas legitimamente concluídas já em `_exit_tree()`, sem reemitir `order_finished`.
   - Só executa `storage.cleanup()`, `ReservedWithdrawalCoordinator.release_regional_domain(...)` e `queue_free()` quando todas as ordens capturadas estão reconciliadas, nenhuma ordem remanescente existe e a liberação regional retorna `ok=true`.

---

## 7. Semântica do encerramento malsucedido

Quando `_reconcile_controlled_teardown()` detecta qualquer falha:

1. **Sem rollback ilusório nem reinserção na árvore:** a `MainScene` já foi removida pelo `remove_child(self)` e **não** se reinserte nem promete restauração de estado pré-teardown.
2. **Proteção estrita contra destruição prematura:** `storage.cleanup()`, `ReservedWithdrawalCoordinator.release_regional_domain(...)` e `queue_free()` **não** são chamados; o domínio regional e o armazenamento permanecem intactos e não desligados (`storage._is_shut_down == false`).
3. **Preservação diagnóstica e de conclusão legítima:** apenas a própria instância desanexada de `MainScene` guarda em `_pending_controlled_teardown` os metadados da falha (`reason`, `failures`) e as referências estritamente necessárias (`token`, `storage`, `inventory`, `world`, `tree`, `domain_owner`, `region`, `units`, `orders`), sem filas globais, timers ou polling.
4. **Conclusão legítima pós-desbloqueio:** liberada a trava recuperável (ex.: `_active_gather_session = null`), `main.complete_pending_controlled_teardown()` finaliza exclusivamente as ordens remanescentes via `Unit._finalize_controlled_teardown_order()` (sem renotificar ordens já encerradas em `_exit_tree()`), executa `storage.cleanup()`, libera legitimamente o domínio regional e agenda `queue_free()`.

---

## 8. Cobertura de recuperação (`B2-R3-A02`)

Em [test_r_03b_b2_r2_committed_cause_and_terminal_teardown.gd](file:///C:/Projetos/Dawn_of_Kin_wt_r_03b/tests/integration/test_r_03b_b2_r2_committed_cause_and_terminal_teardown.gd):

- **`A02-R03a` preservado:** recusa legítima por `pending_cancellation_custody` antes da liquidação.
- **`A02-R03b` desembaraçado:** liquidação real em trabalhador único seguida de término natural e teardown limpo (sem ramificação condicional ambígua).
- **`A02-R03c` determinístico adicionado:** cenário real com dois fundadores (`LeaderA` e `LeaderB`) no mesmo canteiro cancelado (`RecoveryOrder` real em ambos via `CancellationRecoveryDispatcher._flush()`), comprovando sem branch condicional o exato momento em que `record.state == SETTLED`, `D0-A04` conserva madeira, `preflight_economic_teardown()` aprova e **a `RecoveryOrder` do trabalhador par ainda está `is_active() == true`**; em seguida `MainScene.request_controlled_teardown()` atravessa os locks temporários, finaliza a `RecoveryOrder` após o desbloqueio com `1×` `order_finished`, `1×` `order_interruption_cause_committed`, `rev + 1`, `ADMIN_CANCEL`, `COMMUNITY_FREE`/`IDLE`, `current_order == null`, `release_regional_domain.ok == true` e destruição real pós-`queue_free()`.

---

## 9. RED e GREEN

| Execução | Comando | Exit Code | Duração | Resultado verificado | Log |
|---|---|---|---|---|---|
| **RED comportamental** (em `b6adb45`) | `Invoke-Godot --headless ... b2_r3_behavioral_red.gd` | `1` | `7.476,8 ms` | `B2_R3_BEHAVIORAL_RED_FAILURES=1` (`td_ok=true`, `queued_for_del=true`, `g1_active=true`, `token_kept=false`) + `PROBE_TWO_WORKER_RECOVERY` (`a=true, b=false, preflight=true`) | `01_red\red_b2_r3_behavioral_on_b2_r2.log` |
| **GREEN focal `B2-R3`** (`test_r_03b_b2_r3`) | `.\tools\run_tests.ps1 -Filter test_r_03b_b2_r3` | `0` | `27.273,7 ms` | `1/1` suíte, `1/1` teste, `59` asserções, `0` falhas (`A01-R01a`, `A01-R01b`, `A01-R03`, `A01-R04`) | `03_green\b2_r3_tests_green.log` |
| **GREEN `B2-R2` fortalecida** (`test_r_03b_b2_r2`) | `.\tools\run_tests.ps1 -Filter test_r_03b_b2_r2` | `0` | `30.554,3 ms` | `1/1` suíte, `2/2` testes, `186` asserções (`88 + 98`, incluindo `A02-R03c`), `0` falhas | `03_green\b2_r2_suite_green.log` |
| **RED → GREEN comportamental** | `Invoke-Godot --headless ... b2_r3_behavioral_red.gd` | `0` | `9.859,9 ms` | `B2_R3_BEHAVIORAL_RED_FAILURES=0`, `HAS_ERROR=False` | `03_green\behavioral_red_turned_green.log` |

---

## 10. Preservação econômica

- `preflight_economic_teardown()` e `CancellationLifecycleGuard` mantidos 100% intactos (`A02-R03a`).
- `RegionalConservationAudit` (`D0-A04`) verificado nos pontos estáveis pré-destruição em `A01-R01a`/`A01-R04` (`59` asserções), `A02-R01`..`A02-R03c` (`186` asserções) e nas suítes históricas `test_r_03a_d3_3_regional_conservation`, `test_t3_6_2_c4_2_lifecycle_readiness` e `test_t3_6_3_b1_*`.
- Comprovado que falha na finalização terminal impede `storage.cleanup()` e `release_regional_domain()`, preservando `RegionalAuthority` e `storage._is_shut_down == false` até conclusão legítima.

---

## 11. Campanhas executadas e justificativa de abrangência (§17)

- **Justificativa formal:** conforme §17, esta é a campanha proporcional à revisão mínima `B2-R3`, porque o diff de produção (`+153 / -17` linhas) restringe-se exclusivamente ao caminho de saída controlada (`MainScene.request_controlled_teardown()` + 4 linhas no consumo de `_controlled_teardown_token` em `Unit._finalize_controlled_teardown_order()`), **sem** alterar `_install_admitted_order()`, `ControlMode`, `F01`/`F02`, `order_finished`/`order_interruption_cause_committed`, `CommunityTaskDispatcher` ou transações econômicas. Por transparência, **não foi executada a regressão integral de 103 suítes** (reservada à B4 ou a alterações em caminhos compartilhados).
- **Campanhas executadas e aprovadas (`17` suítes distintas, `113` testes, `4.286` asserções, `0` falhas):**
  1. **Consolidada `R-03B` (`.\tools\run_tests.ps1 -Filter test_r_03b_b`):** `8/8` suítes, `33/33` testes, `1.098` asserções, `exit=0` (`47.403,5 ms`):
     - `test_r_03b_b1_authority_and_dispatch_lease` (`8` testes, `206` asserções)
     - `test_r_03b_b1_recovery_authority` (`4` testes, `105` asserções)
     - `test_r_03b_b2_control_mode_f03_and_reentrancy` (`6` testes, `195` asserções)
     - `test_r_03b_b2_r1_focal_revalidation_and_lifecycle` (`3` testes, `141` asserções)
     - `test_r_03b_b2_r2_committed_cause_and_terminal_teardown` (`2` testes, `186` asserções)
     - `test_r_03b_b2_r3_defensive_teardown_and_recovery` (`1` teste, `59` asserções)
     - `test_r_03b_b1_founding_house_permissions` (`6` testes, `135` asserções)
     - `test_r_03b_b2_control_mode_and_f03_unit` (`3` testes, `71` asserções)
  2. **9 suítes históricas correlatas (`04_validation\historical_related_suites.log`):** `9/9` suítes, `80/80` testes, `3.188` asserções, `0` falhas:
     - `test_t3_6_2_c4_2_lifecycle_readiness` (`8` testes, `236` asserções, `exit=0`, `29.519,9 ms`)
     - `test_t3_6_3_b1_1_custody_and_release_primitives` (`7` testes, `254` asserções, `exit=0`, `27.805,7 ms`)
     - `test_t3_6_3_b1_2_cancellation_commit_transaction` (`4` testes, `201` asserções, `exit=0`, `38.611,5 ms`)
     - `test_t3_6_3_b1_3_physical_recovery` (`9` testes, `370` asserções, `exit=0`, `63.839,2 ms`)
     - `test_t3_6_3_b1_4_recovery_dispatch` (`16` testes, `178` asserções, `exit=0`, `119.852,4 ms`)
     - `test_t3_6_4_cancellation_ui` (`8` testes, `153` asserções, `exit=0`, `41.143,1 ms`)
     - `test_r_03a_d2_selective_work_cancellation` (`8` testes, `330` asserções, `exit=0`, `54.219,6 ms`)
     - `test_r_03a_d2_r1_adversarial_cancellation` (`7` testes, `319` asserções, `exit=0`, `60.047,4 ms`)
     - `test_r_03a_d3_3_regional_conservation` (`13` testes, `1.147` asserções, `exit=0`, `41.055,6 ms`)
  3. **Validação estática (`.\tools\validate.ps1`):** `Validation PASSED (0 errors, 0 warnings, 231 scripts checked)`, `exit=0` (`04_validation\validate.log`).
  4. **Smoke da `MainScene`:** `12/12` critérios `true` (11 critérios `B2-R2` + `12_teardown_failure_guard_and_recovery`), `use_d2_2_hud=false`, `use_provenance_economy=true`, `automatic_cancellation_recovery=true`, `0` erros/avisos (`11.212,5 ms`, `exit=0`, `05_smoke\smoke.log`).

---

## 12. Exit codes reais

Todas as execuções ocorreram em `C:\Projetos\Dawn_of_Kin_wt_r_03b` com captura imediata de `$LASTEXITCODE` e propagação de processos filhos (`0` códigos inferidos ou vazios):

- `red_b2_r3_behavioral_on_b2_r2.log` (`b6adb45`): `RED_BEHAVIORAL_EXIT=1`, `HAS_ERROR=False`, `7.476,8 ms`
- `b2_r3_tests_green.log`: `GREEN_B2_R3_EXIT=0`, `27.273,7 ms`
- `b2_r2_suite_green.log`: `GREEN_B2_R2_EXIT=0`, `30.554,3 ms`
- `r_03b_consolidated_green.log`: `GREEN_R03B_ALL_EXIT=0`, `47.403,5 ms`
- `behavioral_red_turned_green.log`: `BEHAVIORAL_GREEN_EXIT=0`, `HAS_ERROR=False`, `9.859,9 ms`
- `historical_related_suites.log` (`9` filtros individuais): todos `HIST_EXIT(...)=0`
- `validate.log`: `VALIDATE_EXIT=0` (`1.364.205,8 ms`, `0` erros, `0` avisos, `231` scripts)
- `smoke.log`: `SMOKE_EXIT=0`, `SMOKE_HAS_ERROR=False`, `SMOKE_HAS_WARNING=False`, `11.212,5 ms`
- `diff_check.txt`: `DIFF_CHECK_EXIT=0`, `FORBIDDEN_B3_SRC_HITS=0`, `DOCS_DESIGN_IMPORT_COUNT=0`

---

## 13. Limitações

- Conforme §17, não foi executada a suíte completa de ~103 suítes nem a bateria visual/aceite humano ou benchmarks de desempenho (`B4`), permanecendo inalterado o orçamento nominal de `p95 <= 16,7 ms` em CA na Intel UHD Graphics 620.
- `CommunityTaskDispatcher` ainda preserva `Q05` histórico sem consumir `order_interruption_cause_committed` até a **`R-03B B3`**.
- Em falha irrecuperável após `remove_child(self)`, `MainScene` não é destruída nem reinserida na árvore; cabe ao chamador diagnosticar `_pending_controlled_teardown` ou liberar bloqueios e chamar `complete_pending_controlled_teardown()`.

---

## 14. Integridade Git

- Commit cirúrgico publicado na branch `feat/r-03b-founding-house-control-mode` sobre `b6adb45d0a2300fc0c50a358204fc9c137eb468c`, preservando ancestralidade linear, `develop`, `main`, tags e `C:\Projetos\Dawn of Kin\project.godot`.
- SHA final, verificação `HEAD == origin`, estado limpo do worktree e verificação integral do manifesto SHA-256 estão gravados em `evidencias\R-03B\B2\R3\06_git_final\git_final_state.txt` e `evidencias\R-03B\B2\R3\MANIFEST_SHA256.txt`.
- Nenhum merge, tag, rebase ou force push executado; worktree `C:\Projetos\Dawn_of_Kin_wt_r_03b` mantido ativo.

---

## 15. Critério de parada

- **`R-03A`:** definitivamente encerrada.
- **`R-03B B0-R2`:** definitivamente homologada.
- **`R-03B B1-R1`:** definitivamente homologada.
- **Contrato de eventos `B2-R2`:** ratificado pelo proprietário.
- **`R-03B B2-R3`:** **CANDIDATA TÉCNICA B2-R3 — AGUARDANDO AUDITORIA INDEPENDENTE — NÃO HOMOLOGADA**.
- **`R-03B B3` e `R-03B B4`:** **BLOQUEADAS**.
- **`develop`, `main` e tags:** preservadas.
