# Dawn of Kin — Relatório Técnico Candidato R-03B B1-R1 (Correção Focal dos Achados B1-A01–A05)

> **Estado oficial da candidata:** **`CANDIDATA TÉCNICA B1-R1 — AGUARDANDO AUDITORIA INDEPENDENTE — NÃO HOMOLOGADA`**
> **Escopo:** Revisão focal estrita aos cinco achados (`B1-A01`–`B1-A05`) da auditoria independente sobre a candidata `B1` (`1ad8ac397ff67f514b4c6d1f14316bf6c29744a6`).
> **Documento B1 original preservado:** `docs/testing/R_03B_B1_founding_house_permissions_candidate_report.md` (não reescrito).

---

## 1. Autorização expressa

- O proprietário autorizou exclusivamente a revisão focal **`R-03B B1-R1`**, restrita aos cinco achados da auditoria independente da candidata `B1`:
  - **`B1-A01` (Crítico):** Teardown e reconfiguração do `CommunityTaskDispatcher` durante callbacks síncronos em `_try_dispatch_unit_to_task()`.
  - **`B1-A02` (Crítico):** Validação incompleta do `DispatchLease` frente à §8.3 do plano homologado `B0-R2` e prevenção de leases presos em `INSTALLING` após falha de instalação.
  - **`B1-A03` (Alto):** Fallback permissivo em `UnitControlPermissions.get_personal_order_rejection_reason_for_order()` para subclasses desconhecidas de `UnitOrder`.
  - **`B1-A04` (Alto):** Cobertura adversarial insuficiente de conclusão síncrona real (`order.is_succeeded() == true` dentro de `start()`, `0` frames físicos), falha síncrona, sucessora pessoal durante callback e esgotamento de fonte durante instalação.
  - **`B1-A05` (Alto):** Precondições insuficientes e caminho condicional (`if rec_disp != null`) no teste de bloqueio transacional da recuperação `T1b`.
- **Limites preservados:** a implementação geral da `B1` foi mantida intacta; **`B2`**, **`B3`**, **`B4`**, `ControlMode`, `UnitControlState`, temporizador `D-05`, protocolo `F03` completo (`_transition_seq`, `_finished_notified`), merges e tags permaneceram bloqueados e não executados.

---

## 2. Base Git

| Referência | Valor verificado |
|---|---|
| Repositório | `https://github.com/Julian0s/Dawn-of-Kin` |
| Branch candidata | `feat/r-03b-founding-house-control-mode` |
| Worktree candidato | `C:\Projetos\Dawn_of_Kin_wt_r_03b` (mantido ativo) |
| Checkout principal permanente | `C:\Projetos\Dawn of Kin` (na branch `develop`) |
| SHA B1 auditado (base da B1-R1) | `1ad8ac397ff67f514b4c6d1f14316bf6c29744a6` |
| SHA B0-R2 homologado (ancestral) | `30b791571a7594f3e1de5a2403a69a1f11713eee` |
| `develop` protegida | `94c718024359dc7ff8360949313969b3ceaf9776` (intocada) |
| `main` protegida | `25e0a20f1d6a2f10a9e059afe69759fbe263db4a` (intocada) |
| Tags históricas | `t1-complete` (`3dcbba93`), `t2-complete` (`049ba9c7`), `t3-3-complete` (`c7947c96`) (intocadas) |
| `project.godot` local protegido (`C:\Projetos\Dawn of Kin`) | SHA-256 `AEEFDA2810DA5C4EDFA9BF5F2A47A5841F8597238C8DAB4C2E202FAF70307613` (intocado) |
| Manifesto B1 anterior preservado | SHA-256 `CDA33DFC72EA56C020FF210AF779C363F968C33B84C993DDF3470CEB4F9C1AF4` (intocado) |

---

## 3. Escopo focal

Alterações estritamente limitadas a:
- **Produção (4 arquivos):**
  - `src/rts/community_task_dispatcher.gd` (`B1-A01`)
  - `src/rts/community_work_board.gd` (`B1-A02`)
  - `src/units/unit.gd` (`B1-A02` / `B1-A04`)
  - `src/units/unit_control_permissions.gd` (`B1-A03`)
- **Testes automatizados (3 arquivos):**
  - `tests/integration/test_r_03b_b1_authority_and_dispatch_lease.gd` (`B1-A01`, `B1-A02`, `B1-A04`)
  - `tests/unit/test_r_03b_b1_founding_house_permissions.gd` (`B1-A03`)
  - `tests/integration/test_r_03b_b1_recovery_authority.gd` (`B1-A05`)
- **Documentação técnica desta revisão (1 arquivo novo):**
  - `docs/testing/R_03B_B1_R1_focal_authority_and_coverage_candidate_report.md`

Nenhum documento canônico (`GDD`, `AGENTS.md`, `ROADMAP_MESTRE.md`, `R_03B_B0_founding_house_control_mode_PLAN.md`) nem o relatório `B1` original foram alterados.

---

## 4. Resultado individual de A01–A05 (Matriz de Fechamento — §28)

| Achado | Teste RED ou lacuna reproduzida | Correção | Teste GREEN | Evidência | Estado |
|---|---|---|---|---|---|
| **B1-A01 (A01-R01..R04)** | `SCRIPT ERROR: Invalid call. Nonexistent function 'is_dispatch_lease_valid_for_commit' in base 'Nil'` (`L719`) e `'abort_task_dispatch' in base 'Nil'` (`L703`) + leases/ordens órfãos em teardown/reconfiguração durante callback síncrono (`4` falhas RED + `2` script errors). | Captura local de `(owner_board, owner_cmd, owner_epoch)` em `CommunityTaskDispatcher._try_dispatch_unit_to_task()`, incremento de `_config_epoch` em `teardown()`/`configure()`, guarda `context_still_valid` nos ramos `ok == false` e `ok == true`, aborto estrito no `owner_board`, reconciliação da ordem comunitária por `(order, installed_revision)` preservando sucessora pessoal. | `test_b1_a01_dispatcher_teardown_and_reconfigure_reentrancy` (`20/20` asserções, `0` script errors). | `02_red/red_b1_r1.log`, `04_green/b1_r1_tests_green.log` | **CORRIGIDO E VERIFICADO TECNICAMENTE** |
| **B1-A02 (A02-R01..R05)** | `excluded_unit_ids`, `_active_by_source_id`, `task.task_id`, `task.kind` e `task.resource_id` ausentes em `validate_dispatch_lease_for_installation` / `is_dispatch_lease_valid_for_commit` + lease preso em `INSTALLING` após falha síncrona de `start()` (`8` falhas RED). | Reconciliação integral das 10 condições da §8.3 em `CommunityWorkBoard.validate_dispatch_lease_for_installation()` e `is_dispatch_lease_valid_for_commit()` + aborto imediato `board.abort_task_dispatch(dispatch_lease)` em `Unit.issue_community_order()` quando `_install_admitted_order()` retorna `false`. | `test_b1_a02_dispatch_lease_full_section_8_3_validation` (`28/28` asserções). | `02_red/red_b1_r1.log`, `04_green/b1_r1_tests_green.log` | **CORRIGIDO E VERIFICADO TECNICAMENTE** |
| **B1-A03 (A03-R01..R05)** | `UnknownCustomOrder` e `UnitOrder.new()` aceitos indevidamente em fundadores adulto e criança, substituindo ordem anterior válida (`17` falhas RED). | Adicionada constante `UnitControlPermissions.REASON_UNSUPPORTED_PERSONAL_ORDER = "unsupported_personal_order"` e substituído o fallback permissivo (`return ""`) por retorno restritivo por padrão em `get_personal_order_rejection_reason_for_order()`. | `test_b1_a03_restrictive_default_denies_unknown_unit_order_subclasses` (`30/30` asserções) + `0` falhas na regressão integral (`98/98` suítes). | `01_adversarial_audit/unit_order_subclasses_scan.txt`, `02_red/red_b1_r1.log`, `04_green/b1_r1_tests_green.log` | **CORRIGIDO E VERIFICADO TECNICAMENTE** |
| **B1-A04 (A04-R01..R04)** | Teste anterior em `L408–420` cobria apenas rejeição pós-instalação por revisão avançada, sem provar conclusão síncrona real em `0` frames físicos; falha síncrona em `start()` deixava lease preso em `INSTALLING` (defeito real reproduzido em `A04-R02`). | Fortalecimento do teste com `GatherResourceOrder` real + `DeliverToCampOrder` legado concluindo `order.is_succeeded() == true` dentro de `start()` em `0` frames físicos (`A04-R01`), falha síncrona com aborto de lease (`A04-R02`, corrigido em `Unit.issue_community_order`), sucessora pessoal durante flush real do dispatcher (`A04-R03`), e esgotamento real da fonte durante instalação (`A04-R04`). Renomeação verídica do bloco `L408–420`. | `test_b1_a04_real_synchronous_completion_and_failure` (`31/31` asserções). | `02_red/red_b1_r1.log`, `04_green/b1_r1_tests_green.log` | **CORRIGIDO E VERIFICADO TECNICAMENTE** |
| **B1-A05** | Bloco condicional `if rec_disp != null` permitia aprovação silenciosa se precondições falhassem; faltava asserção explícita das 11 precondições, dos dois caminhos de trava transacional e da recuperação `T1b` após desbloqueio com auditoria de conservação. | Substituído por teste incondicional `test_b1_a05_t1b_transactional_block_preconditions_and_unlock_recovery` verificando explicitamente todas as 11 precondições, bloqueio `T1b` sob `_coordinator_transaction_locked` (Caminho 1) e `_provenance_transfer.is_executing` (Caminho 2) via flush síncrono determinístico, invariantes pós-bloqueio, desbloqueio com substituição legítima `T1b`, conclusão da recuperação e `RegionalConservationAudit` (`before == after`). | `test_b1_a05_t1b_transactional_block_preconditions_and_unlock_recovery` (`43/43` asserções). | `02_red/red_b1_r1.log`, `04_green/b1_r1_tests_green.log` | **CORRIGIDO E VERIFICADO TECNICAMENTE** |

---

## 5. Reprodução dos achados (RED autêntico)

Campanha RED executada contra a base auditada `1ad8ac397ff67f514b4c6d1f14316bf6c29744a6` (`02_red/red_b1_r1.log`, `RED_B1_R1_EXIT=1`):
- **`Suites: 3 | Tests: 18 | Passed: 13 | Failed: 5 | Assertions: 442`**:
  - `test_b1_a01_dispatcher_teardown_and_reconfigure_reentrancy`: reproduziu `2` crashes reais (`Invalid call. Nonexistent function 'is_dispatch_lease_valid_for_commit' in base 'Nil'` em `community_task_dispatcher.gd:719` e `'abort_task_dispatch' in base 'Nil'` em `L703`) + `4` falhas de leases e ordem órfã.
  - `test_b1_a02_dispatch_lease_full_section_8_3_validation`: reproduziu `8` falhas (aceitação indevida de unidade excluída em `task.excluded_unit_ids`, lacunas de `_active_by_source_id`/`task.kind`, e lease preso em `INSTALLING` após falha de instalação).
  - `test_b1_a03_restrictive_default_denies_unknown_unit_order_subclasses`: reproduziu `17` falhas (aceitação indevida de `UnknownCustomOrder` e `UnitOrder.new()` em fundadores adulto e criança, substituindo ordem ativa válida).
  - `test_b1_a04_real_synchronous_completion_and_failure`: reproduziu o vazamento real de lease em `A04-R02` (`INSTALLING` órfão após falha síncrona de `start()`), além de identificar dois ajustes de fixture no próprio teste (peso unitário da madeira `2` -> `10` unidades = capacidade `20/20`; e loop de `extract()` limitado por `max_extract_per_operation` em `A04-R04`).
  - `test_b1_a05_t1b_transactional_block_preconditions_and_unlock_recovery`: identificou na campanha RED que aguardar frames físicos após apenas `_coordinator_transaction_locked = true` permitia o autoencerramento natural de `ConstructOrder.physics_update()` no canteiro `CANCELLED`, confirmando a necessidade de invocar `rec_disp._flush()` de forma síncrona para testar ambos os caminhos com a ordem genuinamente ativa.

---

## 6. Correções de produção

1. **`src/rts/community_task_dispatcher.gd` (`B1-A01`):**
   - Adicionado contador monotônico `_config_epoch: int = 0`, incrementado em `teardown()` e `configure()`.
   - `_flush_dispatch()` e `_dispatch_group_tasks()` verificam `(flush_epoch, flush_board)` a cada iteração.
   - `_try_dispatch_unit_to_task()` captura `(owner_board, owner_cmd, owner_epoch)` antes de chamar `owner_cmd.dispatch_community_gather()`, calcula `owner_board_alive` e `context_still_valid` no retorno, aborta o lease estritamente no `owner_board` (jamais em `_board` nulo ou em um novo board após reconfiguração), e reconcilia a ordem comunitária apenas se a unidade ainda detiver exatamente `(order, installed_revision)`, preservando qualquer ordem pessoal sucessora.
   - Após `notify_task_updated(task)`, revalida `_is_tearing_down` e `_config_epoch == owner_epoch` antes de emitir `task_assigned` / `task_feedback`.
2. **`src/rts/community_work_board.gd` (`B1-A02`):**
   - `validate_dispatch_lease_for_installation()` passou a validar todas as 10 condições da §8.3: `task.task_id == lease._task_id`, `_active_by_source_id.get(task.source.get_instance_id()) == task`, `not task.excluded_unit_ids.has(unit.get_instance_id())`, `task.resource_id == source_res_id == lease._resource_id`, `task.kind == lease._task_kind == WorkTask.kind_from_resource_id(source_res_id)`, domínio regional (`task.region_id == _region_id`, `lease._region_id == _region_id`, `is_source_in_region_domain`), elegibilidade comunitária e autorização de corte.
   - `is_dispatch_lease_valid_for_commit()` alinhada para verificar igualmente `task.task_id == lease._task_id`, `_active_by_source_id.get(task.source.get_instance_id()) == task`, `not task.excluded_unit_ids.has(lease_unit.get_instance_id())`, `task.kind == lease._task_kind`, `task.resource_id == lease._resource_id`, região e autorização de corte.
3. **`src/units/unit.gd` (`B1-A02` / `B1-A04`):**
   - Em `issue_community_order()`, quando `_install_admitted_order(order)` retorna `false` (por exemplo, falha síncrona dentro de `start()`), o método chama imediatamente `board.abort_task_dispatch(dispatch_lease)` (se `is_instance_valid(board)`), garantindo que nenhum `DispatchLease` permaneça preso em `INSTALLING`.
4. **`src/units/unit_control_permissions.gd` (`B1-A03`):**
   - Adicionada `const REASON_UNSUPPORTED_PERSONAL_ORDER: String = "unsupported_personal_order"`.
   - Em `get_personal_order_rejection_reason_for_order()`, o ramo final deixou de retornar `""` e passou a retornar `REASON_UNSUPPORTED_PERSONAL_ORDER` para qualquer subclasse de `UnitOrder` fora da lista explícita homologada (`MoveOrder`, `GatherResourceOrder`, `DeliverToCampOrder`, `ConstructOrder`), com `RecoveryOrder` mantendo `REASON_RECOVERY_ORDER_NOT_PERSONAL`.

---

## 7. Testes fortalecidos

- **`tests/integration/test_r_03b_b1_authority_and_dispatch_lease.gd`** (`+395` linhas, `8` testes, `206` asserções):
  - `test_b1_a01_dispatcher_teardown_and_reconfigure_reentrancy` (`A01-R01` teardown com `ok == true`, `A01-R02` reconfiguração para novo board preservando novo board intacto, `A01-R03` teardown + ordem pessoal sucessora preservada, `A01-R04` teardown durante `ok == false`).
  - `test_b1_a02_dispatch_lease_full_section_8_3_validation` (`A02-R01` unidade em `excluded_unit_ids`, `A02-R02` divergência `_active_by_source_id`, `A02-R03` divergência `task.kind`/`resource_id`/`task_id`, `A02-R04` revogação no commit após exclusão durante instalação, `A02-R05` falha síncrona de instalação aborta lease sem deixá-lo preso em `INSTALLING`).
  - `test_b1_a04_real_synchronous_completion_and_failure` (`A04-R01` conclusão síncrona real de `GatherResourceOrder` + `DeliverToCampOrder` legado dentro de `start()` em `0` frames físicos com `order.is_succeeded() == true` e entrega única; `A04-R02` falha síncrona em `start()` com aborto de lease; `A04-R03` sucessora pessoal em callback durante flush real do dispatcher; `A04-R04` esgotamento real da fonte durante instalação com fechamento limpo da tarefa e conservação da carga).
  - Rótulo do caso `L408–420` corrigido para refletir fielmente o que testa (validação pós-instalação sob revisão avançada).
- **`tests/unit/test_r_03b_b1_founding_house_permissions.gd`** (`+77` linhas, `6` testes, `135` asserções):
  - `test_b1_a03_restrictive_default_denies_unknown_unit_order_subclasses` (`A03-R01`..`R05`: `UnknownCustomOrder` e `UnitOrder.new()` rejeitados em fundadores adulto/criança e morador comunitário, sem alterar ordem ativa ou revisão; ordens pessoais conhecidas e restrições etárias preservadas).
- **`tests/integration/test_r_03b_b1_recovery_authority.gd`** (`+100` linhas, `4` testes, `105` asserções):
  - `test_b1_a05_t1b_transactional_block_preconditions_and_unlock_recovery` (sem nenhum `if rec_disp != null` opcional; afirma todas as 11 precondições, bloqueio `T1b` nos 2 caminhos de trava transacional, invariantes pós-bloqueio, desbloqueio com recuperação `T1b` legítima até liquidação e `RegionalConservationAudit` antes/depois).

---

## 8. Distinção entre defeitos reais de produção e lacunas de cobertura

- **Defeitos reais de produção corrigidos:**
  1. **`B1-A01`:** `CommunityTaskDispatcher._try_dispatch_unit_to_task()` desreferenciava `_board` nulo/trocado após teardown/reconfiguração síncrona em callbacks, gerando `SCRIPT ERROR` e vazando leases/ordens comunitárias órfãs.
  2. **`B1-A02` (validação §8.3):** `CommunityWorkBoard.validate_dispatch_lease_for_installation()` e `is_dispatch_lease_valid_for_commit()` omitiam checagens obrigatórias (`excluded_unit_ids`, `_active_by_source_id`, `task.task_id`, `task.kind`, `task.resource_id`).
  3. **`B1-A02` / `B1-A04` (vazamento `INSTALLING`):** `Unit.issue_community_order()` marcava o lease como `INSTALLING` antes de `_install_admitted_order()`, mas não o abortava quando a instalação falhava sincronamente em `start()`.
  4. **`B1-A03`:** `UnitControlPermissions.get_personal_order_rejection_reason_for_order()` retornava `""` (permitido) por padrão para subclasses desconhecidas de `UnitOrder`.
- **Lacunas de cobertura adversarial corrigidas (sem defeito adicional no ramo de conclusão síncrona do `CommunityTaskDispatcher`, que já tratava `completed_sync`):**
  1. **`B1-A04` (cobertura de conclusão síncrona real):** O teste anterior não exercitava `order.is_succeeded() == true` dentro de `start()` em `0` frames físicos. Nota técnica importante: no modo provenance (`use_provenance_transactions = true`), `DeliverToCampOrder._start_selective_walk()` adia explicitamente o commit econômico para `physics_update()` (`src/units/orders/deliver_to_camp_order.gd:227`), portanto `GatherResourceOrder` com provenance não conclui dentro de `start()`. O caminho real de conclusão síncrona existe no modo legado (`use_provenance_transactions = false`, mochila cheia na zona do acampamento com parada solicitada em `TRANSPORTING`), agora exercitado de ponta a ponta sem ganchos de teste em produção.
  2. **`B1-A05`:** O teste `T1b` anterior usava `if rec_disp != null` e não comprovava explicitamente todas as 11 precondições, os dois caminhos de trava transacional nem o fluxo completo após desbloqueio até a auditoria de conservação.

---

## 9. Preservação da fronteira B1/B2

- Busca automatizada no diff completo contra os símbolos proibidos (`UnitControlState`, `ControlMode`, `control_mode_changed`, `PERSONAL_POST_MOVE_WAIT`, `InterruptionCause`, `_transition_seq`, `_finished_notified`): **`0` ocorrências (`FORBIDDEN_SYMBOL_HITS=0`)**.
- Flags da `MainScene` preservadas: `use_provenance_economy = true`, `automatic_cancellation_recovery = true`, `use_d2_2_hud = false`.
- Nenhum mecanismo de bypass de permissões adicionado. Nenhum teste removido ou enfraquecido.

---

## 10. Reconciliação de testes históricos

- Varredura estática prévia (`01_adversarial_audit/unit_order_subclasses_scan.txt`) e execução integral da regressão segmentada (`98/98` suítes, `742/742` testes, `0` falhas) confirmaram que **nenhum teste histórico foi quebrado** pela política restritiva `B1-A03` nem pelas demais correções focais.
- **Testes históricos modificados na B1-R1:** `0` (`05_historical_test_reconciliation/reconciliation_summary.txt`). As três suítes históricas reconciliadas na `B1` original permaneceram integralmente preservadas e aprovadas.

---

## 11. Validação estática

- Comando: `.\tools\validate.ps1` (executado em `C:\Projetos\Dawn_of_Kin_wt_r_03b` após a última edição).
- Resultado: **`Validation PASSED (0 errors, 0 warnings, 225 scripts checked)`**, **`VALIDATE_EXIT=0`**.
- `docs/design/*.import`: **`0`** (`DOCS_DESIGN_IMPORT_COUNT=0`).
- `git diff --check`: **`DIFF_CHECK_EXIT=0`**.
- Nenhum novo arquivo `.gd` criado (nenhum `.uid` ausente).

---

## 12. Regressão integral

- Comando: `.\tools\run_tests.ps1 -Segmented -MaxIntegrationPerGroup 1 -GroupTimeoutSeconds 240`.
- Resultado consolidado (`07_full_regression/segmented_regression.log`):
  - **Batches:** `70/70` `PASS` (`unit` + `integration-01`..`integration-69`)
  - **Suítes:** `98` (`Discovered=98 | ExecutedUnique=98 | Duplicates=0 | Missing=0`)
  - **Testes:** `742/742` `PASS` (`Failed=0 | SuiteErrors=0`)
  - **Asserções:** `34.500`
  - **Tempo somado Godot:** `1.273.505,2 ms` | **Tempo de parede total:** `1.325.162,6 ms`
  - **`REGRESSION_EXIT=0`**
- **Explicação das diferenças frente à baseline B1 (`98` suítes / `737` testes / `34.352` asserções):**
  - `+0` suítes (`98` mantidas; os novos testes foram adicionados nas 3 suítes canônicas da `B1`).
  - `+5` testes (`737 → 742`): `test_b1_a01_dispatcher_teardown_and_reconfigure_reentrancy`, `test_b1_a02_dispatch_lease_full_section_8_3_validation`, `test_b1_a03_restrictive_default_denies_unknown_unit_order_subclasses`, `test_b1_a04_real_synchronous_completion_and_failure`, `test_b1_a05_t1b_transactional_block_preconditions_and_unlock_recovery`.
  - `+148` asserções (`34.352 → 34.500`), refletindo exclusivamente as novas verificações adversariais sem remoção de asserções existentes.

---

## 13. Smoke da MainScene

- Executado via `Invoke-Godot` com `scratch/b1_r1_mainscene_smoke.gd`, gravando exclusivamente em `evidencias/R-03B/B1/R1/08_smoke/` (`SMOKE_EXIT=0`, `HAS_ERROR=False`, `HAS_WARNING=False`, `14.285,4 ms`).
- Todos os 8 itens exigidos pela §31 confirmados como `true` em `08_smoke/smoke_summary.json`:
  1. **Abertura limpa:** `nav_ready=true`, `use_d2_2_hud=false`, `use_provenance_economy=true`, `automatic_cancellation_recovery=true`.
  2. **Fundadores comandáveis (+ B1-A03):** `leader_a_valid_founder=true`, `leader_b_valid_founder=true`, `leader_personal_move_ok=true`, `b1_a03_unknown_order_denied=true`.
  3. **Worker3 e Worker4 inspecionáveis e não comandáveis:** `worker3_community=true`, `worker3_personal_denied=true`, `panel_visible_w3=true` (`"Morador — somente leitura · Coleta comunitária: Madeira"`), `worker4_community=true`, `worker4_personal_denied=true`, `panel_visible_w4=true` (`"Morador — somente leitura"`), `panel_zero_polling=true`.
  4. **Seleção mista:** `mixed_selection_filtered_and_preserved_w3=true`.
  5. **Trabalho comunitário:** `worker3_community_gather_ok=true`.
  6. **Construção legada:** `legacy_site_creation_ok=true`, `legacy_site_founder_assign_ok=true`.
  7. **Recuperação legítima (`T1b`):** `legitimate_t1b_recovery_ok=true` (cancelamento real via `ReservedWithdrawalCoordinator.execute_site_cancellation` -> `RecoveryOrder` com `OrderOrigin.SYSTEM_RECOVERY`).
  8. **Encerramento controlado:** `remove_workers_ok=true`, `passed=true`.
- Nenhuma alteração visual ou de texto da HUD foi introduzida na `B1-R1`; as evidências visuais `720p`/`1080p` da `B1` permanecem válidas e intocadas, e nenhum aceite humano é declarado.

---

## 14. Códigos de saída reais (§33)

| Execução | Diretório | Estado / SHA | Duração | Exit Code real | Log |
|---|---|---|---|---|---|
| RED focal (`test_r_03b_b1`) | `C:\Projetos\Dawn_of_Kin_wt_r_03b` | `1ad8ac3` + testes B1-R1 | `21.174,9 ms` | `1` (esperado: RED) | `02_red/red_b1_r1.log` |
| GREEN focal (`test_r_03b_b1`) | `C:\Projetos\Dawn_of_Kin_wt_r_03b` | `1ad8ac3` + correções B1-R1 | `18.156,5 ms` | `0` | `04_green/b1_r1_tests_green.log` |
| Validação estática (`validate.ps1`) | `C:\Projetos\Dawn_of_Kin_wt_r_03b` | `1ad8ac3` + correções B1-R1 | ~`230 s` | `0` | `06_static_validation/validate.log` |
| Regressão segmentada integral (`98` suítes) | `C:\Projetos\Dawn_of_Kin_wt_r_03b` | `1ad8ac3` + correções B1-R1 | `1.325.162,6 ms` | `0` | `07_full_regression/segmented_regression.log` |
| Smoke ampliado da `MainScene` | `C:\Projetos\Dawn_of_Kin_wt_r_03b` | `1ad8ac3` + correções B1-R1 | `14.285,4 ms` | `0` | `08_smoke/smoke.log` |
| `git diff --check` | `C:\Projetos\Dawn_of_Kin_wt_r_03b` | Working tree pré-commit | `< 1 s` | `0` | `03_focal_corrections/diff_check.txt` |

---

## 15. Evidências externas

Diretório raiz externo: `C:\Projetos\Backups\Dawn_of_Kin_Archive_Local\evidencias\R-03B\B1\R1`
- `00_git_baseline/git_baseline.txt`
- `01_adversarial_audit/unit_order_subclasses_scan.txt`
- `02_red/red_b1_r1.log`
- `03_focal_corrections/focal_diff.patch`, `git_diff_stat.txt`, `git_status.txt`, `diff_check.txt`
- `04_green/b1_r1_tests_green.log`
- `05_historical_test_reconciliation/reconciliation_summary.txt`
- `06_static_validation/validate.log`
- `07_full_regression/segmented_regression.log`
- `08_smoke/smoke.log`, `smoke_summary.json`
- `09_git_final/git_final_state.txt` (gerado após commit e push)
- `MANIFEST_SHA256.txt` (manifesto determinístico verificado após commit e push; todos os manifestos anteriores `B0`, `B0-R1`, `B0-R2` e `B1` preservados integralmente).

---

## 16. Limitações conhecidas e desempenho

- **Desempenho:** nenhum polling por frame, varredura global, consulta de navegação redundante, tempestade de sinais ou autoridade econômica paralela foi introduzido. As novas validações em `CommunityWorkBoard` e `CommunityTaskDispatcher` são checagens `O(1)` por dispatch. O orçamento nominal `p95 ≤ 16,7 ms` em tomada CA (Intel UHD 620) permanece inalterado; a limitação histórica de `19,879 ms` em `1080p` permanece restrita ao encerramento da `R-03A`.
- **Conclusão síncrona no modo provenance:** conforme documentado na §8, `DeliverToCampOrder` em modo provenance adia explicitamente commits econômicos para `physics_update()`, de modo que o teste `A04-R01` exercita a conclusão síncrona real em `0` frames pelo caminho de produção legado (`use_provenance_transactions = false`), enquanto `A04-R02` e `A04-R03` operam sobre a `MainScene` em modo provenance (`true`).
- **Testes humanos:** nenhum teste humano de homologação foi executado ou declarado nesta revisão técnica focal; a homologação depende de auditoria independente e deliberação do proprietário.

---

## 17. Estado Git

- Commit focal publicado na branch `feat/r-03b-founding-house-control-mode` diretamente sobre `1ad8ac397ff67f514b4c6d1f14316bf6c29744a6` (registrado integralmente em `09_git_final/git_final_state.txt` após o push normal).
- `develop` (`94c718024359dc7ff8360949313969b3ceaf9776`), `main` (`25e0a20f1d6a2f10a9e059afe69759fbe263db4a`), tags históricas, checkout principal `C:\Projetos\Dawn of Kin` e `project.godot` protegido permanecem integralmente preservados.
- Worktree candidato `C:\Projetos\Dawn_of_Kin_wt_r_03b` mantido ativo para auditoria.

---

## 18. Critério de parada

- **R-03A:** definitivamente encerrada.
- **R-03B B0 (B0-R2):** definitivamente homologada (`30b791571a7594f3e1de5a2403a69a1f11713eee`).
- **R-03B B1-R1:** **`CANDIDATA TÉCNICA AGUARDANDO AUDITORIA INDEPENDENTE — NÃO HOMOLOGADA`**.
- **R-03B B2, B3, B4:** **`BLOQUEADAS`** até auditoria independente do ChatGPT e autorização expressa do proprietário.
