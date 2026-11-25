# Dawn of Kin — Relatório Técnico da Revisão Corretiva Focal `R-03A D1 R1`
## Correção Focal de `F01` (Captura do `Shift`), Complementações `T01`/`T02` e Reconciliação Documental `DOC01`

**Data:** 25/11/2026  
**Etapa:** `R-03A D1 R1` *(revisão corretiva focal da candidata `R-03A D1`)*  
**Branch candidata:** `feat/r-03a-community-work-main-scene`  
**Worktree candidato:** `C:\Projetos\Dawn_of_Kin_wt_r_03a`  
**Base auditada (`R-03A D1`):** `a56af98c11429bbadb4ae855ed6c1d994dece27e` *(ancestrais lineares: `D0` @ `a39f3b5e5abdfcf43f69a1e9e6865fe4446a3b8b`, `R1.1` @ `f77e99e7ea2404120baafe7a16ca47e94236d922`)*  
**Base canônica preservada (`develop`):** `21c34ee645725a74f1fefac9db0309ec711ab5f2` *(não alterada)*  
**Linha estável preservada (`main`):** `25e0a20f1d6a2f10a9e059afe69759fbe263db4a` *(não alterada)*  
**Status obrigatório:** **`R-03A D1 R1 — IMPLEMENTADA`** · **`F01 CORRIGIDA`** · **`T01 E T02 COMPLEMENTADOS`** · **`DOC01 CORRIGIDA`** · **`VALIDADA TECNICAMENTE`** · **`PUBLICADA EM BRANCH CANDIDATA`** · **`AUDITORIA INDEPENDENTE PENDENTE`** · **`TESTES HUMANOS PENDENTES`** · **`R-03A NÃO HOMOLOGADA`** · **`NÃO INTEGRADA À DEVELOP`** · **`D2 NÃO AUTORIZADA`** · **`R-03B BLOQUEADA`**

> [!IMPORTANT]
> Esta revisão corretiva alterou código de produção **exclusivamente** para **`F01`** (`src/rts/autonomous_gather_input.gd`). **Não houve nenhuma alteração de código de produção para `T01` ou `T02`** — todos os cenários adversariais novos passaram diretamente sobre a arquitetura existente da `D1`. Nenhuma funcionalidade de `D2` (`Parar`), `D3` (corte progressivo) ou `D4` foi antecipada; GDD `v1.3`, atlas D2.2 (`d2_2_faithful_atlas.png`/`atlas_manifest.json`), `use_d2_2_hud = false`, `develop`, `main`, tags e checkout permanente `C:\Projetos\Dawn of Kin` permanecem integralmente preservados.

---

## 1. Autorização e Escopo Focal

Após a auditoria independente do ChatGPT sobre a candidata `R-03A D1` (`a56af98`), o proprietário autorizou exclusivamente **`R-03A D1 R1`** cobrindo quatro pontos:
1. **`F01`:** corrigir a captura do modificador `Shift` para ocorrer exatamente quando o gesto cruza o limiar de arraste (e não no pressionamento inicial), preservando o travamento pós-limiar e a garantia anti-`F02`.
2. **`T01`:** complementar cobertura adversarial de reautorização explícita sob admissão econômica bloqueada (`T01-A`), durante transação regional legítima `ReservedWithdrawalCoordinator` + retomada espontânea por evento (`T01-B`) e seletividade frente a tarefa bloqueada alheia.
3. **`T02`:** complementar a comprovação de invariância econômica completa (mochilas, proveniência, estoque, pilhas, ledger, fontes e autoridade regional) imediatamente antes e depois de tentativas explícitas de autorização recusadas nas três categorias (`wood`, `stone`, `food`).
4. **`DOC01`:** corrigir inconsistências documentais do relatório [R_03A_D1_source_selection_and_authorization_candidate_report.md](R_03A_D1_source_selection_and_authorization_candidate_report.md) (delta de asserções `R1.1 → D1` e destinação das ressalvas `D0-A02`/`D0-A03`/`D0-A04`/`D4`).

---

## 2. `F01` — Diagnóstico, Correção Focal e Evidência RED → GREEN

### 2.1 Causa Confirmada
Em `src/rts/autonomous_gather_input.gd` (`a56af98`, linhas 284–297 e 344–348), `_on_drag_threshold_crossed(_start_pos, _current_pos, _shift_held)` ignorava o parâmetro `_shift_held` recebido do evento que efetivamente cruzava o limiar de arraste (`InputEventMouseMotion` em `RtsInputController:150` ou `InputEventMouseButton` release em `RtsInputController:125`) e decidia `_drag_mode` usando `_press_shift_held` armazenado no pressionamento inicial.

### 2.2 Correção Mínima Aplicada
- **Produção (`src/rts/autonomous_gather_input.gd`):**
  - Removido o campo redundante `_press_shift_held`.
  - `_on_drag_threshold_crossed(_start_pos, _current_pos, shift_held)` passa a travar `_drag_mode = DragMode.SOURCE_BOX_ADD` se `multi_source_enabled and shift_held`, caso contrário `DragMode.UNIT_BOX_RTS`, sincronizando imediatamente `_selection_box_overlay.set_box_style(_drag_mode == DragMode.SOURCE_BOX_ADD)`.
  - No fallback defensivo de `_handle_box_selection`, caso `_drag_mode == DragMode.NONE`, utiliza `shift_held` do evento de soltura.
  - Preservado o travamento pós-limiar, cancelamento por `Esc`, limpeza de overlay, garantia anti-`F02` e ausência total de estado residual de `Shift`.
- **Helper sintético de teste (`tests/integration/test_box_selection.gd`):**
  - `_push_mouse_move` e `_simulate_box_drag` atualizados para propagar `shift_held` também nos eventos intermediários `InputEventMouseMotion` (evitando que o helper antigo simulasse soltura de `Shift` antes de cruzar o limiar). Zero enfraquecimento das asserções históricas (`7/7 PASS`, `58` asserções).

### 2.3 Evidência Comportamental RED → GREEN (`test_d1_07_f01_pre_and_post_threshold_shift_capture_and_esc_hygiene`)
- **RED genuíno sobre `a56af98` (`evidencias\R-03A\D1\R1\red_green\f01_red_before.txt`):**
  - `Suites: 1 | Tests: 13 | Passed: 12 | Failed: 1 | SuiteErrors: 0 | Assertions: 213 | Exit: 1`
  - **10 falhas comportamentais exatas** (zero erros de compilação/fixture): `F01-A` (3 falhas: overlay, seleção de fonte e invasão da seleção RTS), `F01-B` (3 falhas: overlay, seleção RTS e seleção indevida de fonte), `F01-E` (2 falhas: limiar apenas na soltura com `Shift=true`) e `F01-F` (2 falhas: limiar apenas na soltura com `Shift=false`).
- **GREEN pós-correção (`evidencias\R-03A\D1\R1\red_green\f01_green_after.txt`):**
  - `Suites: 1 | Tests: 13 | Passed: 13 | Failed: 0 | SuiteErrors: 0 | Assertions: 213 | Exit: 0` (`42/42` asserções em `test_d1_07`) + `test_box_selection.gd` `7/7 PASS` (`58` asserções).
- **Matriz completa verificada:**
  - `F01-A` (press `false` → pré-limiar `true`): trava `SOURCE_BOX_ADD` + overlay dourado + seleção RTS preservada + `0` tarefas. **PASS**
  - `F01-B` (press `true` → pré-limiar `false`): trava `UNIT_BOX_RTS` + overlay RTS + `0` fontes + `0` tarefas. **PASS**
  - `F01-C` (pós-limiar `true` → `false`): permanece travado em `SOURCE_BOX_ADD` + overlay dourado. **PASS**
  - `F01-D` (pós-limiar `false` → `true`): permanece travado em `UNIT_BOX_RTS` + overlay RTS. **PASS**
  - `F01-E` (limiar apenas na soltura `false → true`): trava `SOURCE_BOX_ADD`. **PASS**
  - `F01-F` (limiar apenas na soltura `true → false`): trava `UNIT_BOX_RTS`. **PASS**
  - `F01-G` (`Esc` durante arraste + soltura ignorada + próximo gesto sem `Shift` residual + `Esc` fora do arraste preserva tarefas ativas). **PASS**
  - Anti-`F02` preservada (`test_r1_f02_drag_gesture_preserves_source_nature_across_origin_invalidation`: `24/24` asserções **PASS**).

---

## 3. `T01` — Complementação Adversarial da Reautorização *(Zero Alteração de Produção)*

Adicionados dois cenários completos em `tests/integration/test_r_03a_d1_selection_and_authorization.gd`:

1. **`test_d1_14_t01a_reauthorization_refused_under_blocked_admission_preserves_state` (`T01-A` — `27` asserções, PASS):**
   - **Natureza:** Fluxo comportamental real na `MainScene` até o bloqueio `BLOCKED_REAUTHORIZATION` (HUD real + ordens pessoais legítimas em ambos os líderes) + **fixture controlada mínima declarada** para estabelecer `economy_admission_reason = "load_unavailable_for_admission"` via `configure_community_work()` / `hud.configure()` (a produção avalia admissão uma vez em `_ready()` e não oferece transição dinâmica de admissão).
   - **Comprovado:** HUD exibe `STATE_ECONOMY_BLOCKED` com botão `disabled = true`; chamada de defesa em profundidade `authorize_selected_category(&"wood")` retorna `ok = false, reason = "economy_blocked"` e feedback honesto; `task.state` permanece `BLOCKED_REAUTHORIZATION`; `task_id`, `group_id`, `excluded_unit_ids` e contagem total de tarefas preservados; ordem pessoal de `LeaderB` intacta; `LeaderA` livre não despachado; zero mutação econômica.
2. **`test_d1_15_t01b_reauthorization_during_regional_tx_and_selective_scope` (`T01-B` + Seletividade — `47` asserções, PASS):**
   - **Natureza:** Fluxo comportamental real na `MainScene` com pilhas físicas depositadas, `ConstructionSite` real, duas tarefas legitimamente bloqueadas (`wood_task` em `wood_tree_01` e `stone_task` em `stone_rock_01`), seleção restrita a `wood_tree_01`, `ConstructOrder` real em `LeaderB` disparando callback autêntico `reservations_changed` dentro de `ReservedWithdrawalCoordinator.withdraw_reserved_from_pile_to_carry_load()`, combinado com **prova focal declarada** de guarda (`dispatcher.call("_flush_dispatch")`) durante o callback e **retomada espontânea real** via `inventory_changed` (sem `request_dispatch()` manual).
   - **Comprovado:**
     - Durante o callback: `is_region_transaction_active_readonly == true`, `RegionalAuthority.has_active_operation() == true`, `inventory.is_transaction_busy() == true`, `dispatcher._is_economy_busy() == true`.
     - Reautorização administrativa (`authorize_selected_category(&"wood")`) aceita a intenção (`PENDING_WORKERS`, limpando `excluded_unit_ids` somente em `wood_task`), mas a prova focal de guarda bloqueia o despacho com `last_reason == "economy_busy"`, zero trabalhador atribuído, zero ordem emitida a `LeaderA` e zero mutação econômica direta.
     - Após a conclusão da retirada real, `inventory_changed` desperta o dispatcher espontaneamente (`assigned_events.size() == 1`, zero duplicação), atribuindo `wood_task` (mesmo `task_id`/`group_id`) ao `LeaderA` livre enquanto `LeaderB` permanece soberano em seu `ConstructOrder`.
     - **Seletividade (`§6.5`):** `stone_task` (fora da seleção / outra categoria) permanece `BLOCKED_REAUTHORIZATION` com `task_id` e `excluded_unit_ids` 100% intactos durante e após a conclusão física de `wood_task`.
     - Conservação exata de madeira e pedra + proveniência válida confirmadas ao final do ciclo.
- **Alteração de produção para `T01`:** **Nenhuma** (zero defeitos demonstrados).

---

## 4. `T02` — Invariância Econômica Completa Após Autorização Recusada *(Zero Alteração de Produção)*

Expandido `test_r1_1_t04_full_provenance_and_storage_invariance_under_blocked_admission` em `tests/integration/test_r_03a_community_work_main_scene.gd` (`141 → 318` asserções, **PASS**), preservando integralmente a fixture histórica real de admissão inválida (carga legada pré-`_ready` em `LeaderA` → `"load_unavailable_for_admission"`) e todos os vetores históricos 1–6:
- Monitoradas fontes das 3 categorias (`wood_tree_01`, `wood_tree_02`, `stone_rock_01`, `food_bush_01`).
- Selecionadas fontes válidas de todas as 3 categorias (`click`, `Shift+click`, `Shift+drag`), comprovando `count >= 1` em madeira, pedra e alimento antes das tentativas de autorização (eliminando qualquer falso positivo por `no_selected_sources`).
- Comprovado que os 3 botões da HUD permanecem visíveis, em `STATE_ECONOMY_BLOCKED` e `disabled == true` (sem forçar sinal artificial de botão desabilitado).
- Exercitada a API pública `authorize_selected_category(&"wood")`, `authorize_selected_category(&"stone")` e `authorize_selected_category(&"food")` como prova de defesa em profundidade, comprovando para cada categoria:
  - `ok == false` e `reason == "economy_blocked"`;
  - `0` tarefas ativas, `0` registros no histórico do board, `0` ordens emitidas;
  - `is_region_transaction_active_readonly == false` e `economy_admission_reason == "load_unavailable_for_admission"` preservados;
  - Snapshot completo (`_snapshot_economic_invariants_r1_1`: mochilas, proveniência, lotes, carga legada, estoque físico/disponível/reservado/reservation_ids, pilhas + posições + reservas, `PileReservationLedger` e quantidades das 4 fontes) **100% invariante** imediatamente antes e depois de cada recusa e perante a linha de base `snap0`.
- **Alteração de produção para `T02`:** **Nenhuma** (zero defeitos demonstrados).

---

## 5. `DOC01` — Reconciliação Documental

Corrigidas com errata rastreável em [R_03A_D1_source_selection_and_authorization_candidate_report.md](R_03A_D1_source_selection_and_authorization_candidate_report.md) (preservando histórico Git sem reescrita destrutiva):
1. **Contagem de asserções `R1.1 → D1`:** corrigido de `29.716` (`+285`) para o valor exato **`29.756`** da `R1.1` (`f77e99e`), com delta exato de **`+245` asserções** (`29.756 → 30.001`).
2. **Destinação correta das ressalvas `D0`:**
   - **`D0-A02` → `D2`:** cancelamento comunitário definitivo pela HUD (`[Parar]`), impedindo extração contínua após encerramento e preservando carga/ordem pessoal sem retorno indevido.
   - **`D0-A03` → `D3`:** fronteira irreversível da derrubada (decisão entre início da queda vs confirmação definitiva a submeter ao proprietário em `D3`).
   - **`D0-A04` → `D3`:** conservação econômica do novo ciclo de corte (balanço regional completo ou rastreabilidade individual comprovada, sem comparar uma única árvore com todo o estoque comunitário e sem dupla contagem de pilhas no estoque).
   - **`D4`:** auditoria consolidada, regressão final, desempenho (incluindo avaliação do pico a frio), smokes e novo protocolo humano completo `M1`–`M8` (não substitui `D0-A04`).

---

## 6. Validação Técnica Consolidada (`R-03A D1 R1`)

| Verificação | Resultado Verificado | Delta vs `D1` (`a56af98`) |
|---|---|---|
| **F01 RED → GREEN** | RED `12/13` (`10` falhas em `F01-A/B/E/F`, `0` `SuiteErrors`) → GREEN `13/13` (`213` asserções) | Correção focal comprovada |
| **10 suítes focais** *(7 obrigatórias + 3 proveniência/região: `c4_6`, `c4_10`, `c4_12`)* | **PASS** — **`98/98` testes**, **`2.226` asserções**, `0` falhas, `0` `SuiteErrors` | `+2` testes novos (`T01-A`/`T01-B`), `+3` suítes regionais/proveniência incluídas |
| **Validação estática (`.\tools\validate.ps1`)** | **PASS** — `0` erros, `0` avisos, **`213` scripts**, boot headless limpo, `DOCS_DESIGN_IMPORT_COUNT = 0` | Mantido `0/0` (`213` scripts) |
| **Regressão segmentada integral** (`.\tools\run_tests.ps1 -Segmented -MaxIntegrationPerGroup 1`) | **PASS** — `62/62` lotes, **`88/88` suítes**, **`639/639` testes**, **`30.285` asserções**, `0` falhas, `0` `SuiteErrors`, `Discovered=88 == ExecutedUnique=88`, `Duplicates=0`, `Missing=0`, exit `0` | `+2` testes (`637 → 639`), `+284` asserções (`30.001 → 30.285`); vs `R1.1` (`29.756`): `+529` asserções |
| **Smokes `MainScene` real** (`run_game.ps1 -QuitAfter 45 -FailOnWarnings`) | **PASS** — `SMOKE_720P = 0`, `SMOKE_1080P = 0` (Intel UHD Graphics 620, OpenGL 3.3 Compatibility) | Mantido `0/0` |
| **Verificação visual proporcional** | 2 capturas focais novas (`720p_f01a_source_overlay_locked.png`, `720p_f01b_rts_overlay_locked.png`) inspecionadas + limpeza pós-`Esc` (`active=false, source_mode=false`) + reutilização expressa das 14 capturas D1 para HUD/anéis não alterados | Cobertura visual completa |
| **Desempenho** | Reutilizadas medições D1 (CA: `8,556` / `9,112` / `11,578 ms` `p95`; pico a frio `72,630 ms` / `p95 22,710 ms` mantido para avaliação consolidada na `D4`) — `F01` altera apenas interpretação de evento pontual sem custo por quadro | Sem regressão de frame cost |

> [!NOTE]
> A duração de relógio (`TotalWallElapsed`) da regressão integral (`36.074 s`) inclui período de suspensão/hibernação do sistema operacional durante os dois últimos lotes (`integration-60` e `integration-61`), sem qualquer falha, timeout ou anomalia funcional (`639/639 PASS`, `exit 0`).

---

## 7. Limitações e Próximo Passo Recomendado

- **Testes humanos:** `NÃO REALIZADOS` (aguardam auditoria independente da `D1 R1` e validação humana focal recomendada da experiência de seleção e HUD na `MainScene` mediante autorização do proprietário).
- **Preservado para etapas futuras:** `D0-A02` (`D2`), `D0-A03` (`D3`), `D0-A04` (`D3`), `D4` (auditoria consolidada, avaliação a frio e protocolo `M1`–`M8`), limitação `R01` multirregional para `T4`, `use_d2_2_hud = false` até `R-05B`.
