# Dawn of Kin — Relatório Técnico da Candidata T3.6.2-C4.2
## Proteção do ciclo de vida econômico (P1) e remoção segura de trabalhadores temporários (P5)

- **Data:** 19/11/2026
- **Engine:** Godot 4.7.2 (`Godot_v4.7.2-stable_win64.exe`)
- **Escopo autorizado:** Exclusivamente **P1** (ciclo de vida controlado da `RegionalAuthority` no encerramento de sessão econômica) e **P5** (guardas transacionais e de domínio na remoção segura de trabalhadores temporários). `R3`, `P2`, `P3`, `P4`, `P6` e decisões `D-INT-01/02/03` foram explicitamente mantidos fora de escopo.
- **Parecer objetivo:** **CANDIDATA C4.2 PRONTA PARA AUDITORIA TÉCNICA** (testes automatizados headless e regressão segmentada aprovados com `0` erros e `0` avisos; **não** declarada homologação formal do proprietário).

---

## 1. SHA-base, branch e estado Git inicial

Verificação não destrutiva executada antes de qualquer edição:

- **Repositório:** `Julian0s/Dawn-of-Kin`
- **Worktree utilizado:** `C:\Projetos\Dawn_of_Kin_wt_t3_4_5` *(worktree raiz `C:\Projetos\Dawn of Kin` em `review/t2-closeout-candidate` e `main` permaneceram intocados)*
- **Branch de trabalho:** `feat/t3-6-2-provenance-transactions`
- **HEAD inicial verificado:** `3639db56bf21f52bc49895780fae186d7378a6d7` (sincronizado com `origin/feat/t3-6-2-provenance-transactions`: `0` ahead / `0` behind, working tree limpo)
- **`main` de referência:** `25e0a20f1d6a2f10a9e059afe69759fbe263db4a`
- **Commits de código e testes desta candidata (anteriores a este relatório):**
  - `9230680e56529f05f0fc1d4f343262733e1fa0ed` — `fix(t3.6.2-c4.2): harden RegionalAuthority shutdown lifecycle (P1) and safe worker removal (P5)`
  - `ff4e19fc847c7af56386ccca47080b0447c4e4f6` — `test(t3.6.2-c4.2): add focused integration suite for P1 domain lifecycle and P5 worker removal`

---

## 2. Causa raiz comprovada de P1 e P5

### 2.1 Causa raiz de P1 (Ciclo de vida da `RegionalAuthority` no mesmo `World3D`)

- `ReservedWithdrawalCoordinator` registra a `RegionalAuthority` no metadado `DOMAIN_META` (`&"_reserved_withdrawal_domains"`) do `World3D`, vinculando `authority.storage = weakref(storage)` e gravando `storage._withdrawal_world` / `storage._withdrawal_region` no `GroundPileManager`.
- Em `src/main/main.gd`, `MainScene._exit_tree()` executava `_ground_pile_manager.cleanup()` e anulava `_ground_pile_manager = null`, mas **não** desvinculava a entrada regional em `World3D`.
- Quando uma segunda instância de `MainScene` montava no **mesmo `World3D`** (como ocorre em recarga de cena no `root`, sem `SubViewport` isolado), `DOMAIN_META[&"default"]` permanecia preso ao `WeakRef` do armazenamento encerrado; toda operação de proveniência da segunda sessão falhava permanentemente em `_inspect_camp_economic_domain` / `_matches_economic_domain` com `"ambiguous_domain"`.
- **Reprodução `RED` observada antes da correção:** executando `test_p1_repro_two_sequential_main_scenes_same_world_3d` sobre o código base `3639db5`, a Sessão 1 concluiu entrega opt-in ao acampamento (`4` wood), encerrou `MainScene` 1 e montou `MainScene` 2 no mesmo `root` `World3D`; a entrega da Sessão 2 falhou exatamente com:
  `{ "ok": false, "reason": "ambiguous_domain", "dependency": "coordinator", "replayed": false, "delivered_now": 0, ... }`.

### 2.2 Causa raiz de P5 (Remoção segura de trabalhadores temporários)

- Em `src/units/temporary_test_workers_controller.gd`, `can_remove_temporary_workers()` checava apenas `carry.is_empty()` e iterava somente os filhos diretos de `_construction_sites_root` chamando `site.get_transit_claim_for_unit(worker)` (que ainda disparava `_prune_stale_state()` mutador).
- Não havia verificação de:
  1. trava de transação na unidade (`_is_reserved_withdrawal_locked()`), na mochila (`is_transaction_busy()`, `_coordinator_transaction_locked`), nas ordens em transferência ativa (`is_provenance_transfer_executing`, `is_selective_transfer_executing`, `_defer_transfer_replan`), no armazenamento/inventário/zona ou na `RegionalAuthority` responsável (`is_executing`, `active_delivery`, `active_camp_delivery`);
  2. canteiros válidos montados fora de `_construction_sites_root` (presentes no grupo `ConstructionSite.GROUP_CONSTRUCTION_SITES`);
  3. revalidação após cancelamento de ordens e antes de `remove_child()`/`queue_free()`, nem proteção contra ordens que recusassem cancelamento (além de `Unit.cancel_current_order()` limpar `_current_order = null` e emitir `order_finished` mesmo quando `order.cancel()` retornava precocemente sem encerrar a ordem).
- **Reprodução `RED` observada antes da correção:** executando `test_p5_repro_outside_root_claim_post_commit_reentrancy_and_uncancellable_order` sobre `3639db5`, durante o sinal pós-commit `load_changed` de `SelectiveCampDeliveryCoordinator` (instante em que a mochila de `Worker3` acabara de ficar vazia, ainda com travas transacionais ativas), `ctrl.remove_temporary_workers_safely()` retornou:
  `{ "ok": true, "reason": "", "message": "Worker3 e Worker4 removidos com segurança." }` e removeu/enfileirou `Worker3` e `Worker4` para destruição em plena transação ativa.

---

## 3. Arquivos alterados e justificativas

| Arquivo | Escopo | Justificativa técnica |
| --- | --- | --- |
| `src/economy/ground_pile_manager.gd` | P1 | Adicionado token de capacidade de propriedade de domínio (`_domain_owner_token`, `bind_domain_owner`, `verify_domain_owner`, `has_domain_owner`), estado de encerramento (`_is_shut_down`, `is_shut_down`), leitores puros de vínculo (`get_bound_withdrawal_region`, `get_bound_withdrawal_world`) e reforço de `cleanup()` para recusar execução sob `is_locked() or is_batch_active()`. |
| `src/economy/reserved_withdrawal_coordinator.gd` | P1 / P5 | Adicionado `release_regional_domain(...)` com autorização por token do proprietário, validação exata de `(World3D, region_id, storage)`, recusa sob transação/sessão ativa e limpeza cirúrgica somente da região encerrada; bloqueio de reuso de storage encerrado (`is_shut_down()`); e helpers estritamente read-only (`is_region_transaction_active_readonly`, `inspect_domain_for_worker_removal_readonly`) que nunca criam `RegionalAuthority` nem gravam `DOMAIN_META`. |
| `src/main/main.gd` | P1 / P5 | Geração de token privado `_economy_domain_owner_token` em `_setup_economy()` (sem getter público); encerramento ordenado em `_exit_tree()` (checagem read-only de transação ativa antes de `cleanup()`, recusa conservadora sem destruir recibos/pilhas se `busy`, liberação controlada do domínio após `cleanup()` e registro de diagnóstico em `get_last_domain_release_result()`); repasse opcional de `_settlement_inventory` e `_economy_region_id` ao `TemporaryTestWorkersController`. |
| `src/units/unit.gd` | P5 | Em `cancel_current_order()`, quando `cancelled_order.cancel(...)` retornar sem encerrar a ordem (`not cancelled_order.is_finished()`), restaura `_current_order = cancelled_order` e retorna sem transicionar para `IDLE` nem emitir `order_finished` indevidamente. |
| `src/units/temporary_test_workers_controller.gd` | P5 | Refatoração de `can_remove_temporary_workers()` (estritamente read-only via `_read_transit_claim_for_unit_pure` e consultas read-only de `RegionalAuthority`) e `remove_temporary_workers_safely()` em fluxo multifásico (identificação → preflight completo → cancelamento seguro com verificação de término → revalidação pós-cancelamento → deseleção → revalidação final antes de `remove_child()`/`queue_free()`), consultando todos os canteiros do domínio via `ConstructionSite.GROUP_CONSTRUCTION_SITES`. |
| `tests/integration/test_t3_6_2_c4_2_lifecycle_readiness.gd` (+ `.uid`) | P1 / P5 | Nova suíte de integração com 8 testes (`226` asserções) cobrindo todos os cenários obrigatórios de P1 (#1–#8) e P5 (#1–#9) com participantes e transações reais. |

`src/rts/command_controller.gd`, cenas `.tscn`, assets, `docs/Dawn_of_Kin_GDD.md`, arquitetura R2, protocolos manuais e relatórios anteriores **não foram modificados**.

---

## 4. Descrição dos novos contratos de segurança

### 4.1 Contrato de liberação controlada da `RegionalAuthority` (P1)

1. **Propriedade verificável:** `GroundPileManager.bind_domain_owner(owner_token)` aceita um `RefCounted` opaco apenas uma única vez, antes de qualquer vínculo regional ou shutdown e fora de locks/batches. Em `MainScene`, `_economy_domain_owner_token` permanece privado.
2. **Correspondência exata e fail-closed:** `ReservedWithdrawalCoordinator.release_regional_domain(world, region_id, storage, owner_token, tree, inventory)` exige main thread, `world`/`region_id`/`storage`/`tree` válidos, `storage.verify_domain_owner(owner_token) == true` e correspondência exata entre `authority.storage.get_ref() == storage`, `storage.get_bound_withdrawal_world() == world` e `storage.get_bound_withdrawal_region() == region_id`.
3. **Proteção de transação e sessão ativa:** recusa com `"busy"` se `authority.is_executing`, `authority.active_delivery != null`, `authority.active_camp_delivery != null`, `storage.is_locked()`, `storage.is_batch_active()` ou `inventory.is_transaction_busy()`; recusa com `"session_still_active"` se `_piles_root` ou `_camp_zone` ainda estiverem na árvore; recusa com `"storage_not_cleaned_up"` se restarem pilhas ou reservas; recusa com `"active_sites_present"` se houver `ConstructionSite` ativo no domínio em `GROUP_CONSTRUCTION_SITES`.
4. **Isolamento regional e idempotência:** apaga exclusivamente `domains[region_id]` (removendo `DOMAIN_META` apenas quando `domains` fica vazio), marca `storage._is_shut_down = true` (impedindo reuso do armazenamento encerrado), trata chamadas repetidas sem nova sessão como no-op seguro (`ok: true, released: false, reason: "not_bound"`) e rejeita (`"storage_mismatch"`) se outra sessão já tiver assumido a região.
5. **Ordem segura em `MainScene._exit_tree()`:** executa após `_exit_tree()` dos filhos (unidades, canteiros, `TestMap`/pilhas/zona já saíram da árvore), desconecta sinais da cena/HUD, consulta `is_region_transaction_active_readonly` + locks locais **antes** de chamar `_ground_pile_manager.cleanup()`, e em caso de transação ativa recusa de forma conservadora sem destruir pilhas nem recibos, registrando o resultado em `_last_domain_release_result`.
6. **Zero criação implícita de autoridade:** nenhum caminho de verificação ou liberação chama `_resolve_authority`, `_resolve_camp_authority` ou grava `DOMAIN_META` quando ausente.

### 4.2 Contrato de remoção segura de trabalhadores temporários (P5)

1. **Preflight estritamente read-only (`can_remove_temporary_workers()`):**
   - valida integridade do nó, `World3D`, `SceneTree` e `UnitCarryLoad`;
   - recusa (`"transaction_in_progress"`) sob `_is_reserved_withdrawal_locked()`, `carry.is_transaction_busy()`, `carry._coordinator_transaction_locked`, transferência ativa em `GatherResourceOrder`/`DeliverToCampOrder`/`ConstructOrder`, fonte transferindo (`_is_transferring`), ou `ConstructionSite`/`CampStorageZone`/`GroundPileManager`/`SettlementInventory` ocupados no domínio;
   - consulta `ReservedWithdrawalCoordinator.inspect_domain_for_worker_removal_readonly(...)` sem criar autoridade, recusando com `"regional_transaction_active"` se a autoridade responsável estiver executando ou `"ambiguous_economic_domain"` em caso de ambiguidade;
   - quando a proveniência está habilitada, valida `provenance_unit_id`, `carry.validate_provenance()` e unicidade do `provenance_unit_id` no `World3D` (`"ambiguous_unit_identity"`, `"unreconciled_carry_load"`);
   - inspeciona todos os canteiros do `World3D` em `ConstructionSite.GROUP_CONSTRUCTION_SITES` (mais filhos de `_construction_sites_root`) usando `_read_transit_claim_for_unit_pure(uid)` e verificando identidade exata da unidade (`entry["unit"] == worker`), respeitando isolamento de outras regiões e falhando conservadoramente em conflitos;
   - recusa `"transit_claim_active"` (inclusive em canteiros fora de `_construction_sites_root`) e `"cargo_in_backpack"` (quantidades, peso ou lotes no ledger).
2. **Execução segura anti-remoção parcial (`remove_temporary_workers_safely()`):**
   - executa preflight completo em todos os trabalhadores;
   - cancela ordens ativas individualmente antes de alterar seleção ou árvore, verificando `worker.get_current_order() == null and active_order.is_finished()` após cada cancelamento (e preservando a ordem ativa em `Unit.cancel_current_order()` caso `order.cancel()` recuse encerrar);
   - revalida o conjunto completo de trabalhadores e todas as condições econômicas/transacionais após cancelamentos e novamente após remoção da seleção, antes de qualquer `remove_child()`/`queue_free()`. Qualquer falha aborta com `0` unidades removidas.

---

## 5. Testes criados e evidências realmente executadas

### 5.1 Evidência `RED` (antes das alterações em `src/`)

- `.\tools\run_tests.ps1 -Filter test_t3_6_2_c4_2_lifecycle_readiness` (sobre `3639db5`):
  - **P1 reproduzido:** `test_p1_repro_two_sequential_main_scenes_same_world_3d` falhou na Sessão 2 no mesmo `root` `World3D` com `reason: "ambiguous_domain"`.
- `.\tools\run_tests.ps1 -Filter test_p5_repro` (sobre `3639db5`):
  - **P5 reproduzido:** durante o sinal pós-commit `load_changed` com mochila recém-esvaziada, `remove_temporary_workers_safely()` retornou `ok: true` e removeu `Worker3` e `Worker4` em plena transação ativa.

### 5.2 Suíte focada `tests/integration/test_t3_6_2_c4_2_lifecycle_readiness.gd` (`GREEN`)

Comando executado: `.\tools\run_tests.ps1 -Filter test_t3_6_2_c4_2_lifecycle_readiness`

| Teste | Cobertura | Resultado | Asserções |
| --- | --- | --- | --- |
| `test_p1_01_two_sequential_main_scenes_same_world_3d_full_opt_in_cycle` | P1 #1–#4 + legado padrão em `MainScene` (coleta/entrega ao acampamento, saque reservado e entrega seletiva à obra em duas `MainScene` consecutivas no mesmo `root` `World3D`) | PASS | 42 |
| `test_p1_02_active_storage_replacement_and_mid_session_release_still_rejected` | P1 #5 (substituição de armazenamento ativo segue rejeitada com `ambiguous_domain`; recibos/replay preservados) | PASS | 11 |
| `test_p1_03_wrong_owner_storage_region_world_busy_and_repeated_release_guards` | P1 #6 (token inválido, storage incorreto, região incorreta, `World3D` incorreto, transação ativa `busy`, sessão ativa, falta de `cleanup`, repetição idempotente e proteção contra liberação tardia após nova sessão) | PASS | 33 |
| `test_p1_04_other_regions_independent_and_main_exit_during_busy_is_conservative` | P1 #7 + saída conservadora de `MainScene._exit_tree()` durante transação ativa sem destruir pilhas/recibos + não criação de autoridade em consultas read-only | PASS | 34 |
| `test_p5_01_normal_removal_cargo_refusal_and_recovery_after_delivery` | P5 #1, #2, #9 + não criação de `DOMAIN_META` em `can_remove_temporary_workers()` | PASS | 20 |
| `test_p5_02_transit_claim_refusal_inside_and_outside_default_sites_root` | P5 #3, #4, #8, #9 (claim físico real via `ReservedWithdrawalCoordinator` em canteiro dentro e fora de `_construction_sites_root`, remoção após entrega via `SelectiveSiteDeliveryCoordinator`) | PASS | 27 |
| `test_p5_03_transactional_lock_and_post_commit_reentrancy_with_empty_backpack` | P5 #5, #6, #8, #9 (reentrância durante `load_changed` pós-commit com mochila vazia + recusa sob `RegionalAuthority` ocupada por outra unidade `LeaderA` + remoção após liberação) | PASS | 25 |
| `test_p5_04_uncancellable_order_no_partial_removal_and_multi_region_isolation` | P5 #7, #8 (ordem não cancelável preservada em `Unit.cancel_current_order()`, zero remoção parcial, revalidação pós-cancelamento com injeção de carga, recusa de `provenance_unit_id` duplicado e isolamento de outra região no mesmo `World3D`) | PASS | 34 |

- **Total da suíte focada:** `1` suíte, `8/8` testes aprovados, `0` falhas, `226` asserções, `0` erros/avisos Godot.

### 5.3 Validação de projeto e diff

- `git diff --check`: aprovado (`0` problemas de formatação/espaços).
- `.\tools\validate.ps1`: **`Validation PASSED (0 errors, 0 warnings, 150 scripts checked).`** (importação headless, `--check-only` nos 150 scripts GDScript e inicialização headless da `MainScene` por 3 quadros).

---

## 6. Resultados da regressão segmentada

Comando executado: `.\tools\run_tests.ps1 -Segmented` (com `-FailOnWarnings` ativo em todos os lotes).

- **Lotes executados:** `13/13 PASS` (`unit`, `integration-01` a `integration-12`)
- **Suítes descobertas e executadas:** `56/56` (`Duplicates=0`, `Missing=0`), incluindo todas as suítes de `RegionalAuthority` (`test_t3_6_2_c2_reserved_withdrawal_transaction.gd` com `test_r1_regions_worlds_and_domain_lifetime`, `c3_1`–`c3_5`), construção (`test_t3_3_*`, `test_t3_4_*`, `test_t3_5_*`), trabalhadores temporários (`test_t3_3_ux_flow.gd`, `test_t3_3_ux_display_and_workers.gd`), validação headless M1–M10 (`test_m1_m10_independent_headless.gd`) e a nova suíte `test_t3_6_2_c4_2_lifecycle_readiness.gd`.
- **Totais consolidados:**
  - **Testes:** `418/418 PASS` (`+8` sobre o baseline C3.5 de `410`)
  - **Falhas:** `0`
  - **Erros de suíte:** `0`
  - **Asserções:** `24.215`
  - **Erros/avisos Godot:** `0`
  - **Tempo agregado:** `SumGodotElapsed: 565.719,8 ms` | `TotalWallElapsed: 582.383,4 ms`

---

## 7. Riscos residuais

1. **Saída forçada durante transação ativa (`MainScene._exit_tree()`):** quando uma cena é removida do `SceneTree` no meio de uma transação síncrona ativa, a C4.2 falha de forma conservadora (`reason: "busy"`) preservando recibos e pilhas sem corromper o domínio; o domínio retido só volta a ficar disponível se o chamador/owner realizar encerramento posterior após a transação concluir (comportamento intencionalmente fail-closed).
2. **Desmontagem externa não controlada (`free()`/`remove_child()` fora de `TemporaryTestWorkersController`):** `Unit._exit_tree()` continua apenas cancelando ordens ativas; remoção arbitrária de um `Unit` diretamente pelo código de cena fora do controlador continua fora do escopo desta etapa (R5 do relatório C4.1).
3. **Demais riscos residuais já catalogados na C4.1 (`R1`, `R2`, `R4`, `R5`, `R6`):** permanecem inalterados e documentados em `docs/testing/T3_6_2_C4_1_readiness_inspection_report.md` (incluindo o fato de **M4–M6** e **M8–M10** seguirem com cobertura automatizada headless, sem homologação visual do proprietário).

---

## 8. Confirmação de compatibilidade legada e decisões vigentes

- **RTS normal permanece legado:** `CommandController` não foi alterado; todas as ordens emitidas pelo fluxo RTS padrão continuam com `use_provenance_transactions = false` / `use_selective_provenance = false`, e `LeaderA`/`LeaderB` iniciam com proveniência desabilitada (verificado explicitamente em `test_p1_01` e em toda a regressão T1/T2/T3).
- **Decisões preservadas:** transporte físico obrigatório antes de crédito econômico, isolamento de reservas entre obras (D2/D3), limite e papéis de trabalhadores (D9), complemento manual sem realocação automática silenciosa (`DEC-11A/B`), ausência de cancelamento operacional D3 e ausência de persistência em disco (T3.8).
- **Nenhuma mecânica nova criada:** não foram introduzidas pilhas de recuperação automática, recipientes de fallback nem transferência instantânea de materiais.

---

## 9. Pendências que permanecem após C4.2

Permanecem integralmente pendentes para etapas posteriores (deliberadamente fora do escopo C4.2):

- **`R3`:** verificação defensiva de aceitação de `unit.issue_order(order)` em `CommandController` (retirada explicitamente do escopo C4.2).
- **`P2`:** suporte opt-in controlado em `CommandController` (`region_id` / roteamento) e formatação de motivos de rejeição de proveniência em `PlacementTestOverlay`.
- **`P3`:** atribuição e garantia de unicidade de `provenance_unit_id` em `Unit` / `MainScene` / `TemporaryTestWorkersController`, além do tratamento do retorno `bool` de `set_base_capacity()` no setter `Unit.definition`.
- **`P4`:** serviço atômico e fail-closed de migração de mochilas legadas carregadas, sobrecarga e claims multi-obra (ou política formal de ativação somente em sessão limpa).
- **`P6`:** fechamento de mutadores diretos de bypass e enquadramento das operações de obra (`complete_site_transaction`, `try_create_site_from_placement`, `contribute_work`, `authorize_manual_complement`) sob `RegionalAuthority` antes de iniciar `T3.6.3`.
- **Decisões pendentes do proprietário:** `D-INT-01` (política de `return_other_site_reserved`), `D-INT-02` (`DEC-T3.6-SIGNALS-01`) e `D-INT-03` (estratégia de ativação em sessão limpa vs. migração `P4`).

---

## 10. Parecer técnico da candidata C4.2

- **P1 e P5 foram corrigidos dentro do escopo estrito autorizado**, com reprodução `RED` prévia comprovada, implementação mínima e fail-closed, `8/8` novos testes de integração (`226` asserções), `150/150` scripts validados em `tools/validate.ps1` e `418/418` testes em `56/56` suítes (`24.215` asserções, `0` erros e `0` avisos) na regressão segmentada.
- **Não foi necessário solicitar nova rodada manual M1–M10**, pois não foi introduzida alteração visual nem defeito visual relacionado à C4.2.
- **Status:** **CANDIDATA C4.2 PRONTA PARA AUDITORIA** pelo ChatGPT e revisão/decisão do proprietário. Este relatório **não** declara homologação automática nem autoriza avanço para `C4.3`, merge ou alterações em `main`.
