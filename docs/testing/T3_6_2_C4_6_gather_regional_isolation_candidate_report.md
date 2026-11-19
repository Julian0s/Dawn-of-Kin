# Dawn of Kin — Relatório Técnico da Candidata T3.6.2-C4.6
## Robustez da coleta transacional e notificações de canteiro — R1

- **Data:** 19/11/2026
- **Engine:** Godot 4.7.2 (`Godot_v4.7.2-stable_win64.exe`)
- **Escopo autorizado:** Exclusivamente correção dos riscos **R1-A** (verificação somente leitura da atividade da `RegionalAuthority` em retentativas de coleta com `operation_id` já alocado) e **R1-B** (supressão de revisões e sinais espúrios em `ConstructionSite` quando `load_changed` mantém os transit claims inalterados), sem ativar proveniência no fluxo RTS normal nem implementar `P2`, `P4`, `P6` ou cancelamento D3.
- **Parecer objetivo:** **CANDIDATA C4.6 PRONTA PARA AUDITORIA** (reprodução `RED` confirmada em `5/5` testes no baseline `8c9d251`; correções validadas em `5/5` testes focados, `144/144` testes T3.6.2 e `441/441` testes segmentados em `60/60` suítes com `0` erros/avisos; **não** declarada homologação formal do proprietário).

---

## 1. Baseline Git

- **Repositório:** `Julian0s/Dawn-of-Kin`
- **Worktree:** `C:\Projetos\Dawn_of_Kin_wt_t3_4_5`
- **Branch:** `feat/t3-6-2-provenance-transactions`
- **HEAD inicial verificado:** `8c9d25188b58885f02d1ef818a6f1f8fa3018327` (`0` ahead / `0` behind `origin/feat/t3-6-2-provenance-transactions`, árvore limpa)
- **`main` de referência (intocada):** `25e0a20f1d6a2f10a9e059afe69759fbe263db4a`
- **Commits publicados desta candidata (anteriores a este relatório):**
  - `3068da05856627a3c5dda617a0ed8751bf86a602` — `fix(t3.6.2-c4.6): check regional authority on gather retries (R1-A) and suppress spurious site notifications on unchanged claims (R1-B)`
  - `b85c2ebd644df8cec62f3e0e554b7ea19551b8b7` — `test(t3.6.2-c4.6): add focused integration suite for gather retry isolation and site claim notifications (R1)`

---

## 2. R1-A e R1-B — Causa raiz e evidências RED

Antes de qualquer alteração em `src/`, foi executada a suíte `tests/integration/test_t3_6_2_c4_6_gather_regional_isolation.gd` contra o baseline `8c9d25188b58885f02d1ef818a6f1f8fa3018327`:

- **Comando RED:** `.\tools\run_tests.ps1 -Filter test_t3_6_2_c4_6_gather_regional_isolation`
- **Exit code:** `1`
- **Resultado:** `Suites: 1 | Tests: 5 | Passed: 0 | Failed: 5 | SuiteErrors: 0 | Assertions: 197 | Elapsed: 8067.2 ms`

### Evidências RED observadas por risco

1. **R1-A — Retentativa de coleta ultrapassando `RegionalAuthority` ativa (`GatherTransferSession._execute_locked`):**
   - No código original (`src/units/orders/gather_transfer_session.gd:233-247`), `_domain_allocator._allocate_gather_operation_ids(...)` só era executado dentro de `if _operation_id.is_empty():`. Em qualquer retentativa subsequente (`not _operation_id.is_empty()` e `existing_receipt.is_empty()`), a execução seguia diretamente para `_invoke_source_transfer(source, load)` sem verificar `RegionalAuthority` para `(world, region)`.
   - Como `ResourceSource.transfer_to_carry_load_with_provenance(...)` verifica apenas `_is_transferring` e as travas da mochila do próprio coletor, uma segunda unidade conseguia extrair recurso durante o callback pós-commit (`load_changed`) de outro participante comprometendo a mesma autoridade regional.
   - **Reprodução RED em `test_01` (`9` falhas):** com `LeaderA` em `RETRY_SCHEDULED` (`_operation_id` congelado em `gather:...:default:...` e `busy_retries == 1`) e `LeaderB` executando `SelectiveCampDeliveryCoordinator` na mesma região `default`, a retentativa de `LeaderA` disparada dentro de `load_b.load_changed` (enquanto `auth.is_executing == true`) retornou `{ "ok": true, "extracted": 3 }`, drenou a árvore de `6` para `3` e adicionou lote `FREE_GATHERED` na mochila em plena transação ativa do par.
   - **Reprodução RED em `test_02` (`6` falhas):** no subteste de limite de retentativas com `auth_a.is_executing = true` e `_operation_id` previamente alocado, a chamada seguinte de `lim_sess.execute_or_retry(...)` executou e concluiu a extração em vez de retornar `"busy"` e respeitar `MAX_BUSY_RETRIES` até `"busy_retry_exhausted"`.
   - Já o isolamento entre regiões distintas (`c46_reg_a` vs. `c46_reg_b`) e o replay de recibo já comprometido na própria fonte passaram desde o baseline e foram mantidos integralmente intactos.

2. **R1-B — Revisões e sinais espúrios em `ConstructionSite` (`_on_unit_carry_load_changed`):**
   - Em `src/buildings/construction_site.gd:1483-1488`, `_on_unit_carry_load_changed(uid)` chamava `_clamp_unit_transit_claim(uid)` (que já controlava internamente a variável `mutated` para só incrementar `_transaction_revision` quando o claim mudava), mas logo em seguida executava **incondicionalmente** `_transaction_revision += 1` e `state_changed.emit(self)`.
   - Quando uma unidade carregando lote `SITE_RESERVED` da Obra A coletava recurso `FREE_GATHERED` (inclusive do mesmo `resource_id`, como madeira livre sobre madeira reservada, ou outro recurso como alimento/pedra), o claim da Obra A permanecia idêntico (`clamped == claimed`, `mutated == false`), porém cada extração gerava revisão e `state_changed` espúrios na Obra A.
   - **Reprodução RED em `test_03` (`5` falhas):** enquanto `LeaderA` transportava `2 wood` reservados da Obra A e coletava `2 wood` livres + `3 food` livres, a revisão da Obra A saltou espuriamente de `16` para `20`, `site_a.state_changed` disparou `3` vezes indevidamente e um plano concorrente previamente preparado para `LeaderB` na Obra A (`SelectiveSiteDeliveryPlanner`) foi invalidado ao tentar confirmar (`"ok": false, "reason": "stale_revision"`).
   - **Reprodução RED em `test_04` e `test_05` (`4` e `3` falhas):** também no modo legado, ganhar madeira livre (`add_units` / `transfer_to_carry_load`) enquanto carregava claim da Obra A disparava `state_changed` e bump de revisão espúrios (`3 -> 4`), e `accept_delivery_from_carry_load` recebia um `state_changed` adicional redundante durante `end_batch(false)`.

---

## 3. Correções realizadas

1. **`src/units/orders/gather_transfer_session.gd` (`_execute_locked`, linhas 233–257 — R1-A):**
   - Dentro de `if existing_receipt.is_empty():`, quando `not _operation_id.is_empty()` (caminho de retentativa sem recibo comprometido na fonte):
     - Consulta `ReservedWithdrawalCoordinator.is_region_transaction_active_readonly(world, region)`: se ativo (`is_executing`, `active_delivery != null` ou `active_camp_delivery != null`), retorna `_failure("busy", "coordinator")` sem invocar a fonte nem gerar novo `operation_id`/`lot_id`.
     - Em seguida, executa `ReservedWithdrawalCoordinator.inspect_camp_domain_for_preparation(world, region, inventory, storage, _operation_id, unit.get_tree())` (igualmente puro e somente leitura) para validar integridade contínua do domínio regional e ausência de conflito de recibo antes de invocar `_invoke_source_transfer(...)`.
   - O caminho `not existing_receipt.is_empty()` (replay de recibo já comprometido na fonte) permanece livre dessa barreira pré-extrator para preservar replays idempotentes mesmo quando outro participante utiliza a autoridade regional.

2. **`src/buildings/construction_site.gd` (`_on_unit_carry_load_changed` e `_clamp_unit_transit_claim`, linhas 1483–1530 — R1-B):**
   - Alterado `_clamp_unit_transit_claim(uid: int) -> bool` para retornar `true` somente quando `_transit_claims` foi efetivamente alterado (redução/remoção de claim por queda de carga abaixo do reclamado, limpeza de entrada vazia ou limpeza de unidade/`CarryLoad` inválidos — casos que já incrementam `_transaction_revision += 1` dentro da função) e `false` quando o claim do canteiro permaneceu idêntico.
   - `_on_unit_carry_load_changed(uid)` passou a emitir `state_changed.emit(self)` somente `if _clamp_unit_transit_claim(uid):`, eliminando o incremento incondicional duplicado de `_transaction_revision` e o `state_changed` espúrio quando a alteração de `carry_load` não altera a responsabilidade da obra.
   - O sinal `UnitCarryLoad.load_changed` continua sendo emitido integralmente para HUD, peso, movimentação e demais observadores.

---

## 4. Arquivos afetados

| Arquivo | Tipo | Escopo / Observação |
| --- | --- | --- |
| `src/units/orders/gather_transfer_session.gd` | Modificado (`+13`) | Guarda somente leitura de atividade/domínio regional em retentativas com `_operation_id` já alocado (**R1-A**). |
| `src/buildings/construction_site.gd` | Modificado (`+6 / -6`) | Retorno booleano de `_clamp_unit_transit_claim` e emissão condicional de `state_changed` em `_on_unit_carry_load_changed` (**R1-B**). |
| `tests/integration/test_t3_6_2_c4_6_gather_regional_isolation.gd` (+ `.uid`) | Novo (`+774`) | Suíte de integração focada cobrindo os 12 casos exigidos em 5 testes (`198` asserções). |
| `docs/testing/T3_6_2_C4_6_gather_regional_isolation_candidate_report.md` | Novo | Este relatório técnico. |

**Arquivos intocados conforme restrição de escopo:** `src/main/main.gd`, `src/rts/command_controller.gd`, `src/economy/resource_source.gd`, `src/economy/reserved_withdrawal_coordinator.gd`, `src/economy/unit_carry_load.gd`, além da branch `main`.

---

## 5. Tratamento de retentativas e sinais

- **Retentativas R1-A (`GatherTransferSession.execute_or_retry`):**
  - Verificação puramente read-only: nunca cria `RegionalAuthority`, nunca escreve em `World3D` e nunca consome serial nem gera segundo `operation_id`/`lot_id` quando bloqueada.
  - Em `"busy"` regional, `execute_or_retry` conserva `_operation_id` e `_lot_id`, incrementa `_busy_retries` (`<= MAX_BUSY_RETRIES = 4`), agenda `RETRY_INTERVAL_SEC` e transita para `State.RETRY_SCHEDULED` (sem transformar `busy` em falha definitiva prematura nem girar em loop infinito).
  - Ao atingir o limite `MAX_BUSY_RETRIES`, encerra com `"busy_retry_exhausted"`.
  - Após o término da transação concorrente na região, a retentativa seguinte conclui normalmente usando os IDs originalmente congelados.
  - Em replay já comprometido na fonte (`existing_receipt` presente e compatível com `_receipt_matches_session`), retorna `ok = true, replayed = true, extracted = 0` sem novo débito na fonte.
  - Chamadas reentrantes durante sinais pós-commit (`load_changed`, `amount_changed`, `depleted`) recebem `"busy"` (`is_executing` da sessão ou `_is_transferring`/`_coordinator_transaction_locked` da fonte/mochila) sem transferência duplicada.
- **Sinais R1-B (`ConstructionSite` e observadores):**
  - Política `DEC-T3.6-SIGNALS-01` preservada integralmente (publicação pós-commit com guardas vigentes).
  - Coleta de lotes livres (`FREE_GATHERED`) ou ganho de carga legada que preserva o claim da Obra A dispara `load_changed` normalmente para `SelectedUnitPanel` (HUD), `UnitMovement` (redução de velocidade por peso) e demais ouvintes, sem alterar `_transaction_revision` nem disparar `state_changed` na Obra A.
  - Reduções reais de claim (ex.: `remove_units` em modo legado abaixo do valor reclamado), descarte por unidade inválida e entregas reais à obra (legado `accept_delivery_from_carry_load` e opt-in `SelectiveSiteDeliveryCoordinator`) continuam atualizando `_transaction_revision` e emitindo `buffer_changed` / `state_changed` adequadamente.

---

## 6. Conservação econômica

Verificada integralmente em todos os cenários da suíte C4.6 e na regressão T3.6.2 (`144/144`):

- **Madeira:** `test_01` e `test_03` confirmam `fonte + mochila + estoque/buffer + pilhas` invariante em todos os estágios (incluindo retentativas bloqueadas em `auth.is_executing == true`, coleta livre mista com lote `SITE_RESERVED` e descarga seletiva apenas dos lotes livres ao acampamento); `test_04` e `test_05` confirmam conservação no modo legado.
- **Pedra:** `test_02` valida extração de pedra em `c46_reg_a` durante transação ativa de `c46_reg_b` e replay posterior com `extracted == 0` (conservação exata `6 -> 3 + 3`); `test_03` e `test_04` preservam pedra reservada para Obra A e Obra B entre saques, entregas concorrentes e descargas seletivas.
- **Alimento:** `test_01`, `test_02`, `test_03` e `test_05` validam conservação exata em arbustos e acampamento tanto em opt-in (`4 -> 4`, `3 -> 3`, `4 -> 4` com reentrância) quanto em modo legado.

---

## 7. Isolamento regional e de obras

- **Isolamento regional (`test_02`):** no mesmo `World3D`, uma transação ativa em `RegionalAuthority` de `c46_reg_b` (`SelectiveCampDeliveryCoordinator`) não bloqueia a retentativa com ID pré-alocado de `GatherTransferSession` na região distinta `c46_reg_a`; além disso, sondar `is_region_transaction_active_readonly` em região não inicializada (`c46_uninit_reg`) não cria `RegionalAuthority`.
- **Isolamento entre Obra A e Obra B (`test_03`):** quando `LeaderA` carrega madeira reservada da Obra A e coleta lotes livres de madeira e alimento enquanto `LeaderB` carrega pedra reservada para a Obra A e para a Obra B:
  - A Obra B mantém revisão, reservas físicas, transit claims, contagem de `state_changed`/`buffer_changed`/`workers_changed` (`0`) e lotes `SITE_RESERVED` absolutamente inalterados.
  - A Obra A não sofre revisão nem sinal espúrio e um plano `SelectiveSiteDeliveryPlanner` concorrente preparado previamente para `LeaderB` confirma normalmente sem falso `stale_revision`.

---

## 8. Testes GREEN e regressão consolidada

| Comando | Resultado |
| --- | --- |
| `.\tools\run_tests.ps1 -Filter test_t3_6_2_c4_6_gather_regional_isolation` (baseline `8c9d251`, **RED**) | **Exit 1.** `1` suíte, `0/5 PASS`, `5/5 FAIL`, `197` asserções, `0` erros de suíte. |
| `.\tools\run_tests.ps1 -Filter test_t3_6_2_c4_6_gather_regional_isolation` (candidata, **GREEN**) | **Exit 0.** `1` suíte, **`5/5 PASS`**, **`198` asserções**, `0` falhas, `0` erros/avisos. |
| `git diff --check` | **Exit 0.** |
| `.\tools\validate.ps1` | **Exit 0.** **`Validation PASSED (0 errors, 0 warnings, 154 scripts checked)`**. |
| `.\tools\run_tests.ps1 -Filter test_t3_6_2 -TimeoutSeconds 240` | **Exit 0.** `17` suítes (`b3_2`, `c1`, `c2`, `c3_1`–`c3_5`, `c4_2`–`c4_6`, `a`, `b2`), **`144/144 PASS`**, **`10.005` asserções**, `0` falhas, `0` erros/avisos. |
| `.\tools\run_tests.ps1 -Segmented -GroupTimeoutSeconds 240` | **Exit 0.** **`14/14` lotes PASS** (`unit` + `integration-01`..`13`), **`60/60` suítes** (`Discovered=60 \| ExecutedUnique=60 \| Duplicates=0 \| Missing=0`), **`441/441 PASS`**, **`24.782` asserções**, `0` falhas, `0` erros de suíte, `0` erros/avisos Godot (`SumGodotElapsed: 551111,6 ms \| TotalWallElapsed: 562506,7 ms`). |

---

## 9. Limitações e riscos residuais

- **Observação da auditoria C4.5 sobre assimetria na validação de região-alvo (registrada conforme §7):** em `ReservedWithdrawalCoordinator.validate_unit_identity_in_domain_readonly` (`src/economy/reserved_withdrawal_coordinator.gd:535-538`), a associação regional da unidade-alvo (`unit`) verifica apenas o metadado explícito `unit.get_meta(&"region_id")`, enquanto unidades conflitantes (`other_u`) têm sua região apurada pelas 4 fontes em `_collect_unit_proven_regions_readonly`. Confirmado que essa assimetria **não afetou nenhum teste da C4.6**; ela permanece documentada aqui, sem refatoração geral de identidade fora de escopo, para revisão posterior quando a ativação multi-regional integrada (`P2`/`D-INT-03`) for avaliada.
- **Pendências pré-existentes fora do escopo C4.6:** `P2` (integração de despacho/região/diagnósticos no `CommandController` e overlay), `P4` (migrador atômico de mochilas legadas carregadas se aplicável), `P6` (fronteira unificada de obra e restrição de bypasses públicos antes da `T3.6.3`), `R2` / `DEC-T3.6-SIGNALS-01` (`D-INT-02`), decisões `D-INT-01` e `D-INT-03`, e todo o cancelamento/custódia D3.
- **Validação exclusivamente automatizada headless nesta etapa:** não houve alteração visual nem ativação de proveniência no jogo normal; nenhum novo teste manual foi necessário ou solicitado.

---

## 10. Confirmação do comportamento legado

- `MainScene` e `CommandController` permaneceram inalterados (`use_provenance_transactions = false` como padrão em todas as ordens criadas pelo RTS).
- Todas as suítes legadas T1, T2, T3.1–T3.5.2 (unidades e integração dentro dos `441/441` testes segmentados) e os casos dedicados `test_04` e `test_05` da C4.6 passaram sem regressão — garantindo inclusive a ausência de `state_changed` espúrio durante coleta livre em modo legado e a preservação dos sinais legítimos de perda/entrega em canteiro.

---

## 11. Parecer objetivo sobre a candidata

**CANDIDATA C4.6 PRONTA PARA AUDITORIA.**

- Escopo **R1-A** e **R1-B** integralmente atendido com alterações cirúrgicas (`+19 / -6` linhas em `src/`), reprodução RED inequívoca, conservação econômica validada, regressão integral limpa (`60/60` suítes, `441/441` testes, `24.782` asserções, `154` scripts validados, `0` erros/avisos) e branch sincronizada em `feat/t3-6-2-provenance-transactions`.
- **Não** é declarada homologação formal pelo proprietário; nenhum merge ou avanço para `C4.7` foi realizado, aguardando auditoria técnica independente.
