# Dawn of Kin — Relatório Técnico da Candidata `R-03A D4-R2`
## Auditoria de Equivalência Algorítmica e Segurança de Lotes das Otimizações `D4-R1`

**Data:** 26/11/2026  
**Etapa:** `R-03A D4-R2` *(auditoria focal das otimizações `D4-R1`: `D4-R1-A01`, `D4-R1-A02` e `D4-R1-A03`)*  
**Repositório:** `https://github.com/Julian0s/Dawn-of-Kin`  
**Branch candidata:** `feat/r-03a-community-work-main-scene`  
**Worktree candidato:** `C:\Projetos\Dawn_of_Kin_wt_r_03a`  
**SHA auditado (`D4-R1`):** `b088620dbd7042a926f3bcd0c2357c48131c0821`  
**Baseline pré-otimizações (`D4`):** `94744eca16e9eea60b03033f82a318f8e7825dc2`  
**SHA final da `D4-R2`:** registrado em `evidencias\R-03A\D4\D4-R2\09_git_final\git_final.txt`  
**Base canônica preservada (`develop`):** `21c34ee645725a74f1fefac9db0309ec711ab5f2`  
**Linha estável preservada (`main`):** `25e0a20f1d6a2f10a9e059afe69759fbe263db4a`  
**Checkout principal preservado:** `C:\Projetos\Dawn of Kin` (`develop` @ `21c34ee`, `project.godot` SHA-256 `AEEFDA2810DA5C4EDFA9BF5F2A47A5841F8597238C8DAB4C2E202FAF70307613`)  
**Godot:** `4.7.2.stable.official.ed1daf0bf` (`gl_compatibility`, `Jolt Physics`, `Intel(R) UHD Graphics 620`)

---

## 1. Resultado Individual (`D4-R1-A01`, `D4-R1-A02`, `D4-R1-A03`)

| Frente | Diagnóstico Inicial em `b088620` | Classificação Pós-Correção `D4-R2` |
|---|---|---|
| **`D4-R1-A01`** (`GatherSlotPlanner`) | `0` violações funcionais nos 12 cenários + `28/28` pares reais da `MainScene`; diferença legítima de anel (`<= 0,06 m`, Categoria 2); porém **degradação relevante confirmada (Categoria 3)** sob snapping deslocado atravessando obstáculo (`+1,45 m`: `6,8700 m` vs `5,4198 m`). | **CORRIGIDA E APROVADA TECNICAMENTE** *(guarda de deslocamento `snap_shift_sq <= 0.25` elimina degradação sem restaurar 48 consultas em terreno aberto)* |
| **`D4-R1-A02`** (`CommunityTaskDispatcher`) | **2 defeitos confirmados em `b088620`**: (1) `is_equal_approx` em `sort_custom` divergiu do `<` estrito do baseline (`100,000404` vs `100,000000` escolheu `wood_tree_01` em vez de `wood_tree_02`) e não forma ordem fraca estrita; (2) `unit_base_eligible` não evitava repetição em unidades elegíveis (`14` chamadas de base contra `12` sem pré-cheque). | **CORRIGIDA E APROVADA TECNICAMENTE** *(comparador estrito `da != db -> da < db`, helper `_check_task_specific_eligibility()` reduzindo checagens base de `14 → 2` sem cache persistente e guarda de teardown mid-dispatch)* |
| **`D4-R1-A03`** (`dispatch_batch_*` e HUD) | **3 violações confirmadas em `b088620`**: (1) `agi.teardown_community_work()` mid-dispatch travava HUD em `_batch_refresh_depth = 1`; (2) `agi.configure_community_work(..., null)` mid-dispatch travava a HUD anterior em `_batch_refresh_depth = 1`; (3) `_flush_dispatch()` vazio sobrescrevia `get_last_refresh_count()` de `1` para `0`. | **CORRIGIDA E APROVADA TECNICAMENTE** *(rastreamento `_dispatcher_batch_hud`/`_dispatcher_batch_depth` com liberação obrigatória em `_disconnect_signals()`, skip de batch em flush sem tarefas ativas e preservação de `_last_batch_refresh_count` em lotes vazios)* |

---

## 2. Contratos Efetivamente Verificados

- **Geometria e navegação (`A01`):** faixa válida `[min_safe_radius, interaction_radius]`, altura máxima `<= 2,5 m`, separação mínima entre trabalhadores (`agent_radius * 2 + 0,1`), fallback sem slot separado, exaustão dos 48 candidatos em fontes totalmente inacessíveis e preservação do baixo custo em terreno aberto (`3` consultas em vez de `48`).
- **Distribuição comunitária (`A02`):** ordem FIFO entre grupos, prioridade espacial intra-grupo, desempate determinístico (`task_idx`, `character_id`, `instance_id`), comparação estrita de distâncias quase iguais, unidades excluídas (`excluded_unit_ids`), precedência de `manually_overridden` sobre `busy`/`not_idle`, proteção de cargas reservadas/recuperação, validação de identidade regional, preservação de ordens pessoais e segurança sob teardown/callbacks durante o despacho.
- **Sinais de lote e HUD (`A03`):** balanceamento incondicional `begin_batch_refresh` / `end_batch_refresh`, lotes aninhados, cancelamento durante callback, reconfiguração da HUD e do `AutonomousGatherInput`, teardown mid-dispatch, encerramento limpo de cena, desconexão de sinais, preservação dos sinais individuais do `CommunityWorkBoard` (`task_registered`, `task_updated`, `task_closed`), equivalência integral de estados visuais/contagens canceláveis e zero polling.

---

## 3. Casos de Equivalência e 4. Diferenças Legítimas (`A01` e `A02`)

### 3.1 Matriz Oráculo `94744ec` × `D4-R2` (`01_a01_slot_planner/a01_oracle_green_after.log`)
| Cenário | Classificação | `ok` (Ref/Cur) | `sep` (Ref/Cur) | `pos_diff` | `Δ travel_dist` | Consultas `Ref → Cur` |
|---|---|---:|---:|---:|---:|---:|
| `S01a/b/c` Terreno plano (`Tree01`/`Rock01`/`Bush01`) | **Cat. 2** *(diferente, válida e equivalente)* | `T/T` | `T/T` | `0,0074–0,0600 m` | `+0,0009 a +0,0600 m` | `48/48 → 3/3` |
| `S02a` Anéis — ângulo direto `Tree01` | **Cat. 1** *(exatamente equivalente)* | `T/T` | `T/T` | `0,0000 m` | `0,0000 m` | `48/48 → 3/3` |
| `S02b` Anéis — ângulo diagonal `Tree01` | **Cat. 2** *(diferente, válida e equivalente)* | `T/T` | `T/T` | `0,0118 m` | `+0,0024 m` | `48/48 → 3/3` |
| `S03` Navmesh irregular | **Cat. 2** *(diferente, válida e equivalente)* | `T/T` | `T/T` | `0,0600 m` | `+0,0599 m` | `48/48 → 3/3` |
| `S04a` Obstáculo bloqueando frente | **Cat. 1** *(exatamente equivalente)* | `T/T` | `T/T` | `0,0000 m` | `0,0000 m` | `48/48 → 8/8` |
| `S04b` Obstáculo c/ snap moderado | **Cat. 2** *(diferente, válida e equivalente)* | `T/T` | `T/T` | `0,0600 m` | `+0,0538 m` | `48/45 → 4/3` |
| `S05` Snapping deslocado moderado (`+0,15 m`) | **Cat. 2** *(diferente, válida e equivalente)* | `T/T` | `T/T` | `0,0600 m` | `+0,0600 m` | `48/29 → 3/2` |
| `S06` Posições elevadas (`+1,2 m` ok / `+3,2 m` rej.) | **Cat. 2** *(diferente, válida e equivalente)* | `T/T` | `T/T` | `0,0600 m` | `+0,0538 m` | `48/45 → 4/3` |
| `S07a/b` Candidatos ocupados (`1` e `3` no arco frontal) | **Cat. 1** *(exatamente equivalente)* | `T/T` | `T/T` | `0,0000 m` | `0,0000 m` | `48/48 → 10–12` |
| `S08a/b` Dois trabalhadores simultâneos (`A` depois `B`) | **Cat. 2** *(diferente, válida e equivalente)* | `T/T` | `T/T` | `0,0189–0,0600 m` | `+0,0061 a +0,0169 m` | `48/48 → 3–9` |
| `S09` Fonte parcialmente inacessível (só anel 1 lateral) | **Cat. 1** *(exatamente equivalente)* | `T/T` | `T/T` | `0,0000 m` | `0,0000 m` | `48/48 → 32/32` |
| `S10` Fallback sem posição separada | **Cat. 1** *(exatamente equivalente)* | `T/T` | `F/F` | `0,0000 m` | `0,0000 m` | `48/48 → 48/48` |
| `S11` Ausência completa de caminho válido | **Cat. 1** *(exatamente equivalente)* | `F/F` | `F/F` | `—` | `—` | `48/48 → 48/48` |
| `S12` Distâncias quase iguais simétricas | **Cat. 2** *(diferente, válida e equivalente)* | `T/T` | `T/T` | `0,0600 m` | `+0,0538 m` | `48/48 → 4/4` |
| **Varredura `14×2` da `MainScene` real** | **Cat. 1 (`2`) + Cat. 2 (`26`) · `0` violações** | `28/28` | `28/28` | `max 0,3276 m` | **`max 0,0600 m`** | `48/48 → 3/3` |

- **Explicação técnica da diferença legítima (Categoria 2):** no oráculo `94744ec`, `ring 1` (`min_safe_radius + 0.08`) ficava `0,06 m` mais próximo da unidade em linha reta do que `ring 0` (`preferred_radius = min_safe_radius + 0.02`). O algoritmo otimizado encerra ao obter slot separado válido em `ring 0`, permanecendo `100%` dentro de `[min_safe_radius, interaction_radius]`, com `Δ travel_dist <= 0,06 m` (`< 0,5%` do trajeto) e redução de `48 → 3` consultas. Não constitui violação de contrato.

---

## 5. Violações / Degradações Confirmadas (`RED`) e 6. Correções Mínimas (`GREEN`)

Evidências brutas preservadas em `04_red_evidence/d4_r2_red_proofs.log` e `05_green_evidence/d4_r2_green_proofs.log`:

1. **`A01` — Degradação por snapping deslocado atravessando obstáculo (Categoria 3):**
   - **RED (`b088620`):** quando o cone frontal (`±30°`) fazia snap para o lado oposto da árvore, o early-exit disparava e retornava `cur_trav = 6,8700 m` (`DEGRADED_GT_1M = true`), ignorando `±45°` aberto do lado próximo.
   - **Correção mínima ([gather_slot_planner.gd](../../src/units/orders/gather_slot_planner.gd)):** só arma `separated_hit_step = step` quando `Vector2(resolved.x - candidate.x, resolved.z - candidate.z).length_squared() <= 0.25` (`<= 0,5 m`).
   - **GREEN:** `cur_trav = 5,4198 m` (`DEGRADED_GT_1M = false`, `-1,45 m`), mantendo `3/3` consultas em terreno aberto.

2. **`A02` — Divergência em distâncias quase iguais + pré-cheque `unit_base_eligible` redundante:**
   - **RED (`b088620`):** (a) `d0 = 100,000404` vs `d1 = 100,000000` (`is_equal_approx = true`) atribuiu `wood_tree_01` em vez do estritamente mais próximo `wood_tree_02` (`DIVERGED = true`); (b) `unit_base_eligible` gerou `14` chamadas de `_check_unit_base_eligibility` (`2` + `12` via `_check_pre_nav_eligibility`) contra `12` sem pré-cheque.
   - **Correção mínima ([community_task_dispatcher.gd](../../src/rts/community_task_dispatcher.gd)):** (a) comparador estrito `if da != db: return da < db` preservando ordem fraca estrita e desempate determinístico; (b) extração de `_check_task_specific_eligibility(unit, task)` chamada apenas após `unit_base_eligible[uid]` validado na mesma rodada (reduzindo chamadas de base de `14 → 2`, sem cache persistente e mantendo `validate_unit_identity_in_domain_readonly` intacta); (c) guardas `_is_tearing_down or _board == null` em `_flush_dispatch()` e `_dispatch_group_tasks()`.
   - **GREEN:** `u0_assigned = wood_tree_02` (`DIVERGED = false`); `starts = 1, ends = 1, hud_depth = 0` sob `disp.teardown()` mid-dispatch.

3. **`A03` — Congelamento da HUD sob teardown/reconfigure mid-dispatch e sobrescrita de `_last_batch_refresh_count`:**
   - **RED (`b088620`):** `agi.teardown_community_work()` e `agi.configure_community_work(..., null)` em callback `task_assigned` deixaram `hud._batch_refresh_depth = 1` (`HUD_STUCK = true`); `_flush_dispatch()` vazio pós-cancelamento sobrescreveu `get_last_refresh_count()` de `1` para `0` (`CLOBBERED = true`).
   - **Correções mínimas:**
     - [autonomous_gather_input.gd](../../src/rts/autonomous_gather_input.gd): rastreia `_dispatcher_batch_hud` e `_dispatcher_batch_depth` com drenagem obrigatória `_release_active_dispatcher_batch()` em `_disconnect_signals()`.
     - [community_task_dispatcher.gd](../../src/rts/community_task_dispatcher.gd): retorna antes de emitir `dispatch_batch_started/finished` quando `active_tasks.is_empty()`.
     - [community_selection_actions_hud.gd](../../src/ui/community_selection_actions_hud.gd): não zera `_last_batch_refresh_count` em `begin_batch_refresh()` para lotes vazios (atualiza apenas ao executar `refresh()` em `end_batch_refresh()` e zera em `unbind()`).
   - **GREEN:** `hud_depth = 0` (`HUD_STUCK = false`) em ambos os cenários mid-dispatch e `after_cancel = 1 → after_empty_flush = 1` (`CLOBBERED = false`).

---

## 7. Testes Executados e Códigos de Saída

| Verificação | Resultado | Exit Code | Log |
|---|---|---:|---|
| Nova suíte focal `test_r_03a_d4_r2_algorithmic_equivalence.gd` | **`6/6` testes (`39` asserções)** | `0` | `06_focal_tests/test_r_03a_d4_r2_algorithmic_equivalence.log` |
| Auditoria estrutural (`audit_structural_perf.gd`) | **`STRUCTURAL_AUDIT_OK=true`** | `0` | `07_full_validation/d4_r2_structural_audit.log` |
| Validação estática (`.\tools\validate.ps1`) | **`221/221` scripts (`0` erros, `0` avisos, smoke ok)** | `0` | `07_full_validation/validate_final.log` |
| **Regressão segmentada integral** (`.\tools\run_tests.ps1 -Segmented -MaxIntegrationPerGroup 1 -GroupTimeoutSeconds 240`) | **`95/95` suítes · `724/724` testes · `34.026` asserções · `68/68` lotes · `Discovered=95`, `ExecutedUnique=95`, `Duplicates=0`, `Missing=0`** | **`0`** | `07_full_validation/full_regression.log` |

*(Referência histórica preservada da `D4-R1 @ b088620`: `94/94` suítes, `718/718` testes, `33.992` asserções, `220` scripts.)*

---

## 8. Impacto no Desempenho (`CA`, `Intel UHD 620`, `VSync OFF`)

`AC_CHECK_BEFORE = True,True` e `AC_CHECK_AFTER = True,True` confirmados continuamente.

| Cenário | Referência Histórica `D4-R1` (`720p` / `1080p`) | Nova Execução `D4-R2` (`720p` / `1080p`) | Observação |
|---|---:|---:|---|
| **`P04_Community_Authorization` p95** | `13,075 ms` / `14,452 ms` | **`12,516 ms` / `14,122 ms`** | Ambos `< 16,7 ms` (`>33,3 ms`: `0` em `720p`, `1` em `1080p`; `sync_us = 3,06 / 3,31 ms`) |
| **`P01`–`P12` demais cenários p95** | `<= 8,81 ms` / `<= 21,89 ms` | **`<= 7,46 ms` / `<= 10,34 ms`** | `12/12` cenários `P01`–`P12` abaixo de `16,7 ms` em `720p` e `1080p` |
| **`D2-P01: 6_TREES_KEEPING_STONE_FOOD_ACTIVE` avg / p95** | `17,191 / 18,285 ms` (`720p`) · `17,523 / 18,431 ms` (`1080p`) | **`15,558 / 16,445 ms` (`720p`) · `18,922 / 19,879 ms` (`1080p`)** | **`hud_refreshes = 1` restaurado em todos os subcenários**; `1080p` permanece transiente de lote acima de `16,7 ms` *(não declarado aprovado sob `16,7 ms`)* |

---

## 9. Limitações Remanescentes

- **Transiente de cancelamento com redistribuição em `1920×1080` (`D2-P01: 6_TREES_KEEPING_STONE_FOOD_ACTIVE`):** `cancel_frame p95 = 19,879 ms` em `1080p` (versus `~6,4 ms` de frame base ocioso na UHD 620); limitação conhecida preservada sem mascaramento.
- **Diferença geométrica de `<= 0,06 m` em `GatherSlotPlanner` (Categoria 2):** escolha preferencial em `ring 0` (`preferred_radius`) em vez de `ring 1` (`+0,06 m`) — contratualmente válida e documentada sem alegar identidade bit-a-bit com 48 consultas.
- **Limitações históricas preservadas:** `R01`, observação `HD3-06` (reservada à `R-03B`), `use_d2_2_hud = false` até `R-05B`, construção legada `P-REC-1`.

---

## 10. SHA Final, 11. Integridade Git e 12. Manifesto SHA-256

- **Integridade Git:** branch `feat/r-03a-community-work-main-scene` linear sobre `b088620`, `develop` preservada em `21c34ee645725a74f1fefac9db0309ec711ab5f2`, `main` preservada em `25e0a20f1d6a2f10a9e059afe69759fbe263db4a`, checkout principal `C:\Projetos\Dawn of Kin` intocado (`project.godot` SHA-256 `AEEFDA2810DA5C4EDFA9BF5F2A47A5841F8597238C8DAB4C2E202FAF70307613`), sem branches ou worktrees adicionais.
- **SHA final e manifesto verificado:** registrados em `evidencias\R-03A\D4\D4-R2\09_git_final\git_final.txt` e `evidencias\R-03A\D4\D4-R2\MANIFEST_SHA256.txt` (`MANIFEST_VERIFY_FAIL = 0`).

---

## 13. Parecer sobre Preparação para `M1`–`M8`

A candidata **`R-03A D4-R2`** está **TECNICAMENTE PRONTA PARA AUDITORIA INDEPENDENTE E EXECUÇÃO PRESENCIAL DOS TESTES HUMANOS `M1`–`M8`** ([R_03A_D4_final_manual_test_protocol.md](R_03A_D4_final_manual_test_protocol.md)).

- **`M1`–`M8`:** **`PENDENTES`** *(nenhum cenário declarado aprovado)*.
- **`R-03A`:** **`VALIDADA TECNICAMENTE — NÃO HOMOLOGADA — NÃO INTEGRADA À DEVELOP`**.
- **`R-03B`:** **`BLOQUEADA`** até homologação e autorização expressa do proprietário.
