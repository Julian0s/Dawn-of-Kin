# Dawn of Kin — Relatório Técnico da Complementação Focal R-03A R1.1 (`T02`, `R01`, `T04`)

**Incremento / Sub-revisão:** `R-03A R1.1` — Complementação focal de evidências técnicas (`T02`, `R01`, `T04`) sobre a candidata `R-03A R1`  
**Status na Taxonomia Obrigatória:**
- `R-03A R1` — `IMPLEMENTADO` *(código de produção integralmente preservado de `294b0fe`)*
- `R-03A R1.1` — `IMPLEMENTADO` (testes e evidências complementares) / `VALIDADO TECNICAMENTE` / `PUBLICADO EM BRANCH CANDIDATA`
- `AUDITORIA INDEPENDENTE DA R1.1 PENDENTE`
- `TESTES HUMANOS M1–M8 PENDENTES`
- `NÃO HOMOLOGADO`
- `NÃO INTEGRADO À DEVELOP`
- `R-03B BLOQUEADA`

**Data:** 24/11/2026  
**Candidata R1 de referência (produção inalterada):** `294b0fed91c7e42f2e831b4eaed1c541080c57d7` ([relatório R1](R_03A_R1_community_work_main_scene_candidate_report.md))  
**Candidata original auditada (preservada no histórico):** `4254011799a34960a70334fbcde8672aba171ea3` ([relatório original](R_03A_community_work_main_scene_candidate_report.md))  
**Base homologada (`develop`, intacta):** `21c34ee645725a74f1fefac9db0309ec711ab5f2`  
**Linha estável (`main`, intacta):** `25e0a20f1d6a2f10a9e059afe69759fbe263db4a`  
**Branch candidata:** `feat/r-03a-community-work-main-scene`  
**Worktree candidato:** `C:\Projetos\Dawn_of_Kin_wt_r_03a`  
**Ambiente:** Godot `4.7.2.stable.official.ed1daf0bf`, GDScript tipado, `gl_compatibility`, `Jolt Physics`, Intel UHD Graphics 620 (`1280×720` e `1920×1080`)

---

## 1. Autorização Recebida e Limites Cumpridos
O proprietário autorizou exclusivamente a complementação focal **`R-03A R1.1`** para endereçar os três pontos apontados na auditoria independente da candidata `R-03A R1` (`294b0fe`):
1. **T02:** Comprovação do bloqueio por transação regional legítima (`RegionalAuthority` / `SiteCreationScope`) e retomada orientada a eventos (`inventory_changed` / `task_registered`), sem dependência exclusiva de `_is_delivering = true` ou chamada manual de `dispatcher.request_dispatch()`.
2. **R01:** Execução do cenário adversarial específico de fonte navegável válida no mesmo `World3D` da `MainScene`, posicionada fora de `TestMap` e fora de `PlayableCommunitySources`, sem `meta("region_id")` na própria fonte nem em qualquer nó ancestral.
3. **T04:** Complementação da verificação de invariância completa de proveniência econômica, saldos físicos/disponíveis/reservados, pilhas físicas, ledger de reservas e recursos remanescentes em todos os vetores de admissão bloqueada.

**Diretriz de produção cumprida:** Zero alterações em código de produção (`src/**`, `assets/**`, `scenes/**`) e zero alterações nos achados já aceitos (`F01`, `F02`, `T01`, `T03`) nem nos relatórios anteriores da `R-03A` e `R-03A R1`.

---

## 2. Análise e Plano Executado
O plano técnico revisável foi redigido antes da edição dos testes em `C:\Projetos\Backups\Dawn_of_Kin_Archive_Local\evidencias\R-03A\R1.1\auditoria\plano_tecnico_r03a_r1_1.md`.

### Mecanismo real verificado no código (`294b0fe`)
- **T02:** Na `MainScene`, as transações de `ReservedWithdrawalCoordinator.withdraw_reserved_from_pile_to_carry_load()` (disparada por `ConstructOrder` real de `LeaderB`) e de `ConstructionManager.try_create_site_from_placement()` (`SiteCreationScope`) são síncronas na thread principal e mantêm `is_region_transaction_active_readonly(world, region_id) == true` e `RegionalAuthority.has_active_operation() == true` durante a emissão de `SettlementInventory.reservations_changed`. Na retirada real de construção, logo após `reservations_changed` e **antes** de `_release_guards()`, `ReservedWithdrawalCoordinator` emite `pile_manager._dispatch_storage_changed()` (`inventory.inventory_changed`), que aciona automaticamente `CommunityTaskDispatcher._on_inventory_changed() -> request_dispatch()` (enfileirando `_flush_dispatch` para o próximo frame de processo).
- **R01:** `CommunityWorkBoard.is_source_in_region_domain()` valida correspondência de `World3D` e ausência de `meta("region_id")` divergente na cadeia ancestral (herdado do contrato T2/T3 de região única ativa por `World3D` na `MainScene`, onde as próprias 6 fontes históricas em `TestMap/ResourceSources` também não carregam `meta("region_id")`). `CommandController`, `GatherTransferSession` e `ReservedWithdrawalCoordinator._allocate_gather_operation_ids()` também validam `World3D` + autoridade do acampamento/unidade sem exigir `meta("region_id")` na `ResourceSource`.
- **T04:** Quando a admissão econômica regional falha (ex.: carga legada pré-existente `{wood: 1}` sem proveniência em `LeaderA` -> `load_unavailable_for_admission`), a falha é **atômica para a região**: nem `LeaderA` nem `LeaderB` habilitam proveniência (`is_provenance_enabled() == false`, `validate_provenance() == false`, `provenance_snapshot() == {}`), preservando a carga não admitida sem convertê-la; vetores de input bloqueiam na origem (`AutonomousGatherInput`) e chamadas diretas ao `CommunityWorkBoard` não geram qualquer despacho no `CommunityTaskDispatcher` nem mutação econômica.

---

## 3. Evidências Implementadas e Resultados por Achado (`294b0fe` Inalterado)

| Achado | Novo Teste em `test_r_03a_community_work_main_scene.gd` | Asserções | Classificação | Produção Alterada? | O que foi efetivamente comprovado |
|---|---|---:|---|---|---|
| **T02** | `test_r1_1_t02_legitimate_regional_transaction_block_and_event_resumption` *(preservando `test_r1_t02_*`)* | **46** (`46/46 PASS`) | **GREEN de cobertura complementar** | **Não** | **Fase 1 (`SiteCreationScope`):** durante `try_create_site_from_placement()`, `reservations_changed` observou `is_region_transaction_active_readonly == true` e `_is_economy_busy == true`; flush reentrante bloqueado com `"economy_busy"`, zero ordem em `LeaderA`, retomada automática via `task_registered` pós-liberação. **Fase 2 (`ReservedWithdrawalCoordinator` via `ConstructOrder` real):** na primeira emissão de `reservations_changed` dentro de `withdraw_reserved_from_pile_to_carry_load()`, `is_region_transaction_active_readonly == true`, `RegionalAuthority.has_active_operation() == true`, `inventory.is_transaction_busy() == true`, `_is_economy_busy == true`; flush reentrante bloqueado com `"economy_busy"` e `_flush_queued == false`; em seguida `inventory_changed` disparou naturalmente na mesma transação e **sem nenhuma chamada manual a `dispatcher.request_dispatch()`** `LeaderA` retomou e executou `Task2` exatamente **1 vez** (`task_assigned == 1`), com proveniência válida e conservação exata de madeira (`14 + 2 = 16`) e pedra (`6`) junto com `LeaderB`. |
| **R01** | `test_r1_1_r01_external_untagged_source_same_world3d` *(preservando `test_r1_r01_*`)* | **113** (`113/113 PASS`) | **Comportamento observado compatível com contrato T2/T3; limitação multi-região documentada para T4** | **Não** | Uma `ResourceSource` navegável válida sob `SubViewport` (mesmo `World3D` da `MainScene`, **fora de `TestMap` e de `PlayableCommunitySources`**, com zero `meta("region_id")` em si ou em qualquer ancestral) foi testada nos 10 vetores: aceita por `is_source_in_region_domain()`, `register_gather_task()`, `register_gather_group()` com fonte canônica, clique esquerdo, box drag de fontes, despacho automático, extração até `0`, entrega física `+2 wood` ao `SettlementInventory` e rastreabilidade `FREE_GATHERED` válida. No vetor 10 (dois `CommunityWorkBoard` distintos no mesmo `World3D`), ambos os boards enxergam e aceitam a fonte externa sem `meta("region_id")`: **confirmado objetivamente** que o isolamento atual depende do `World3D` e do `meta("region_id")` explícito nas fontes/raízes estrangeiras, permanecendo limitação conhecida documentada para multi-região contínua na **T4**. |
| **T04** | `test_r1_1_t04_full_provenance_and_storage_invariance_under_blocked_admission` *(preservando `test_r1_t04_*`)* | **141** (`141/141 PASS`) | **GREEN de cobertura complementar** | **Não** | Após semear pilhas físicas reais no acampamento (`wood=4`, `stone=3`) e provocar falha de admissão legítima em `LeaderA` (`{wood: 1}` legado sem proveniência -> `load_unavailable_for_admission`), confirmou falha atômica (`LeaderA` e `LeaderB` permanecem `is_provenance_enabled() == false`, `validate_provenance() == false`, `provenance_snapshot() == {}`; carga `{wood: 1}` preservada intacta sem conversão). Snapshots completos antes/depois após cada um dos **6 vetores** (clique, `Shift+Clique`, arraste sobre fonte com preservação de seleção RTS, `register_gather_group`, `register_gather_task` e `dispatcher.request_dispatch()`) provaram invariância estrita de `provenance_snapshot()`, quantidades/pesos de `UnitCarryLoad`, `SettlementInventory` (físico/disponível/reservado/IDs de reserva), `GroundPileManager._ledger.snapshot_state()`, IDs/quantidades/reservas das pilhas físicas e `ResourceSource.get_remaining_amount()`. |

---

## 4. Validações Executadas Após Edição Final dos Testes

### 4.1 Suíte Focal `test_r_03a_community_work_main_scene.gd`
- **Comando:** `.\tools\run_tests.ps1 -Filter test_r_03a_community_work_main_scene`
- **Resultado:** **`28/28` testes `PASS` (`0` falhas, `0` SuiteErrors, `772` asserções, `48.465,5 ms` internos / `65.691,6 ms` totais)** — abaixo do timeout padrão de `120 s`.
- **Evidência:** `evidencias/R-03A/R1.1/testes_focais/r1_1_r03a_run.txt`.

### 4.2 Suítes Focais Correlatas (Proveniência, Retirada Reservada, Construção, Economia e RUX)
Todas executadas com `0` falhas e `0` avisos:
- `test_t3_6_2_c4_9_manual_complement_authority.gd`: `5/5` (`178` asserções)
- `test_t3_6_2_c4_9_r1_internal_helper_boundary.gd`: `4/4` (`117` asserções)
- `test_t3_6_2_c4_9_r2_scope_finalization.gd`: `11/11` (`268` asserções)
- `test_t3_6_2_c4_12_rts_provenance.gd`: `5/5` (`119` asserções)
- `test_t3_3_construction_logistics.gd`: `11/11` (`223` asserções)
- `test_t2_playable_economy.gd`: `8/8` (`351` asserções)
- `test_rux_2b_multi_source_selection.gd`: `14/14` (`114` asserções)
- `test_rux_1_autonomous_gather.gd`: `7/7` (`87` asserções)
- `test_rux_2a_auto_resources.gd`: `10/10` (`166` asserções)
- **Evidências:** `evidencias/R-03A/R1.1/testes_focais/focal_regression_suites.txt` e `focal_rux_1_2a.txt`.

### 4.3 Validação Estática Completa (`.\tools\validate.ps1`)
- **Resultado:** **`PASSED`** (`0` erros, `0` avisos, **`209` scripts verificados**, `DOCS_DESIGN_IMPORT_COUNT=0`).
- **Evidência:** `evidencias/R-03A/R1.1/validacao/validate_r03a_r1_1.txt`.

### 4.4 Regressão Integral Segmentada (`.\tools\run_tests.ps1 -Segmented -MaxIntegrationPerGroup 1`)
- **Resultado R1.1:** **`86/86` suítes** (`Discovered=86 | ExecutedUnique=86 | Duplicates=0 | Missing=0` em `61` lotes) | **`620/620` testes `PASS`** | **`0` falhas** | **`0` SuiteErrors** | **`29.756` asserções** (`1.063.487,6 ms` Godot / `1.115,74 s` wall).
- **Delta em relação à `R-03A R1` (`294b0fe`):** `+3` testes dedicados (`617 -> 620`) e `+299` asserções (`29.457 -> 29.756`).
- **Evidência:** `evidencias/R-03A/R1.1/regressao/run_tests_full_r03a_r1_1.txt`.

### 4.5 Smoke Visual e Medição de Desempenho (Preservados de `294b0fe`)
- Como **nenhum arquivo de produção (`src/**`, `assets/**`, `scenes/**`) foi alterado** na `R1.1`, as medições visuais (`1280×720` e `1920×1080`, `EXIT=0`) e proporcionais CA realizadas exatamente sobre o código de produção `294b0fed91c7e42f2e831b4eaed1c541080c57d7` em `R_03A_R1_community_work_main_scene_candidate_report.md` §6.3–6.4 permanecem válidas sem nova reexecução.

---

## 5. Pendências Mantidas Antes da Homologação
1. Auditoria técnica independente do ChatGPT sobre a candidata publicada em `origin/feat/r-03a-community-work-main-scene`.
2. Execução dos **testes humanos `M1`–`M8`** pelo proprietário na Godot `4.7.2` (`C:\Projetos\Dawn_of_Kin_wt_r_03a`), conforme roteiro preservado em [R_03A_community_work_main_scene_candidate_report.md](R_03A_community_work_main_scene_candidate_report.md) §7.
3. Homologação expressa do proprietário e autorização posterior para integração à `develop` e encerramento do worktree candidato (`R-03B` permanece **`BLOQUEADO`**).
