# R-03A D2 R1 — Relatório de Auditoria Adversarial, Correção Cirúrgica e Cobertura Complementar

- **Incremento:** `R-03A D2 R1` (revisão adversarial da candidata `R-03A D2`, sem auto-homologação)
- **Status real:** `IMPLEMENTADO` · `VALIDADO TECNICAMENTE` · `AUDITORIA INDEPENDENTE PENDENTE` · `RETESTE HUMANO PENDENTE` · `D2 NÃO HOMOLOGADA` · `R-03A NÃO HOMOLOGADA` · `NÃO INTEGRADO À DEVELOP`
- **Base imediata investigada (RED):** `c9f10841b3235f0a1b1a020c41cf784f71bc685e` (`feat/r-03a-community-work-main-scene`)
- **Base D1 definitivamente homologada:** `9964a063893971cd0473afc567627d0da0c4493e` (preservada integralmente)
- **Engine / Ambiente:** `Godot 4.7.2.stable.official.ed1daf0bf` (`gl_compatibility`, `Jolt Physics`, Intel UHD Graphics 620, tomada CA `AC_Battery_100pct`)
- **Flags canônicas preservadas em `src/main/main.tscn`:** `use_provenance_economy = true`, `automatic_cancellation_recovery = true`, `use_d2_2_hud = false`

---

## 1. Autorização Expressa e Escopo

Após auditoria independente da candidata `R-03A D2` (`c9f1084`), o proprietário autorizou exclusivamente:
1. Investigar **`D2-A01`** (interferência de ordem antiga sobre ordens pessoais instaladas em callbacks síncronos de cancelamento/entrega);
2. Corrigir **somente defeitos efetivamente demonstrados por RED/GREEN válidos**;
3. Complementar a cobertura adversarial **`D2-T01`** (reconciliação honesta dos 64 requisitos originais da D2 + complementos obrigatórios `T01-A`–`T01-I`);
4. Medir **`D2-P01`** com o maior lote legítimo de uma única categoria (`6` árvores via clique real no selo `×` da HUD) e aplicar otimização mínima somente se comprovadamente justificada com equivalência visual verificada.

Permanecem fora de escopo / `BLOQUEADO`: `D3`, `D4`, `R-03B`–`T3.9`, `T4`–`T8`, cancelamento global, e qualquer alteração em `project.godot`, atlas D2.2, ícones, colisores, picking, Shift, câmera, GDD v1.3 ou Design System D2.2.

---

## 2. D2-A01 — Investigação Forense, RED/GREEN e Classificação

| Cenário | Sinal / Fronteira | Base `c9f1084` (RED) | Classificação | Revisão `R1` (GREEN) |
|---|---|---|---|---|
| **A01-R1** | `worker_slot_released` (com carga `FREE_GATHERED`) | **DEFEITO CONFIRMADO:** ordem pessoal aceita (`rev 1→2`, `target=(-10, 0.5, 8)`), mas `_start_delivering()` criou `_deliver_order`, sobrescreveu movimento para o acampamento `(-2.4, 0.5, 1.7)` e afastou a unidade (`3,74 m → 8,17 m`), com `delivering_count=1` falso. | **Resultado A — Defeito confirmado e corrigido** | `hijacked=false`, `old_deliver_created=false`, `old_status=4 (CANCELLED)`, chegada física `3,74 m → 0,13 m` (`SUCCEEDED`), `delivering_count=0`, `preserved_personal_orders_count=1`. |
| **A01-R1b** | `worker_slot_released` com nova `GatherResourceOrder` pessoal na **mesma fonte** | Risco de liberação dupla de vaga durante limpeza tardia da ordem antiga. | **Resultado A — Protegido por liberação idempotente** | `_has_reservation = false` antes do sinal; vaga da ordem nova preservada (`active_worker_count == 1`). |
| **A01-R2** | `unit.state_changed (-> TRANSPORTING)` (com carga) | **DEFEITO CONFIRMADO:** `_start_delivering()` criou `_deliver_order` após `_unit.set_order_state()`, sequestrando movimento para `(-2.4, 0.5, 1.7)` (`3,74 m → 8,24 m`). | **Resultado A — Defeito confirmado e corrigido** | `hijacked=false`, `old_deliver_created=false`, chegada física `3,74 m → 0,13 m` (`SUCCEEDED`), `preserved_personal_orders_count=1`. |
| **A01-R3A** | `worker_slot_released` em cancelamento imediato sem carga (`cancel()`) | **DEFEITO CONFIRMADO:** `super.cancel(movement)` chamou `stop_movement()` após o callback, derrubando a ordem pessoal de `MOVING (1)` para `IDLE (0)` e `FAILED (cancelled)`. | **Resultado A — Defeito confirmado e corrigido** | `move_state 1 → 1 (MOVING)`, ordem pessoal `RUNNING` → chegada física `SUCCEEDED`, `preserved_personal_orders_count=1`. |
| **A01-R3B** | `worker_slot_released` em cancelamento sem carga em `RETRY_SCHEDULED` (`begin_batch()`) | **DEFEITO CONFIRMADO:** mesmo corte de movimento (`1 → 0`, `FAILED`, `preserved_personal_orders_count=0`). | **Resultado A — Defeito confirmado e corrigido** | `move_state 1 → 1`, ordem pessoal `RUNNING` → chegada física `SUCCEEDED`, `preserved_personal_orders_count=1`. |
| **A01-R3C** | `worker_slot_released` no caminho diferido `_finish_cancelled()` | Mesmo risco de limpeza tardia de movimento em `_finish_cancelled()`/`_finish_failed()`/`_finish_succeeded()`. | **Resultado A — Corrigido na mesma intervenção** | Movimento pessoal preservado (`MOVING`) até chegada física `SUCCEEDED`. |
| **A01-R4** | Ordem pessoal durante entrega residual já ativa (`DELIVERING_TO_CAMP`) | **PASSOU NA BASE:** `dist 3,82 → 0,06`, `cargo 2→2`, `inv 0→0`, `src_rem 28→28`. | **Resultado B/C — Hipótese refutada; cobertura `O09` adicionada** | Coberto permanentemente em `test_r1_t01a_...`. |
| **A01-R5A** | `ResourceSource.amount_changed` (extração ativa) | Guarda transacional ativa (`tx_exec=true`, `coord_locked=true`), recusa legítima `unit_transaction_locked`; cancelamento diferido (`deferred_transfer_count=1`). | **Resultado B — Guarda econômica legítima confirmada** | Preservado + aceitação limpa comprovada logo após destravamento. |
| **A01-R5B / T01-E** | `SettlementInventory.inventory_changed` (entrega ativa) | Dispara **pós-commit dentro da janela de lock transacional** (`tx_exec=true`, `deliver_exec=true`, `region_exec=true`, `coord_locked=true`, `inv_at_cb > inv_before`, `carry_at_cb=0`), recusando ordem pessoal (`unit_transaction_locked`). | **Resultado B/C — Guarda confirmada; telemetria e classificação corrigidas** | Telemetria, recibo e replay de entrega asseridos em `test_r1_t01e_...`. |
| **A01-R6** | `_deliver_order` invalidada durante `physics_update()` em modo proveniência | **Refutada no modo canônico (`use_provenance_economy=true`):** `_coordinator_transaction_locked=true` bloqueia `issue_order()`/`cancel_current_order()` durante `_publish()`. | **Resultado B — Hipótese refutada (sem edição especulativa)** | Nenhuma alteração preventiva em `_update_delivering()`. |
| **A01-R7** | `CommunityWorkBoard.task_closed` (`E12`) | Protegida na base; reforçada com avanço físico real. | **Resultado B/C — Preservada e fortalecida** | Coberta em `test_r1_t01a_...` e `test_r1_t01f_t01g_...`. |
| **T01-H** | Retomada do `CommunityTaskDispatcher` após lote (`_flush_dispatch`) | **Refutada:** `cancel_tasks_for_sources()` é síncrono na main thread (fila deferred não consome mid-batch); `natural_signal_resumed=true`. | **Resultado B — Hipótese refutada (sem alteração em produção)** | Coberta em `test_r1_t01h_t01i_...`. |

### Alterações Cirúrgicas Efetivas em Produção
1. **`src/units/orders/gather_resource_order.gd`:** adicionados `_capture_unit_order_revision()`, `_still_owns_unit_execution(expected_revision)` e `_still_owns_movement_cleanup(expected_revision)`; `_release_source_reservation()` tornada idempotente (`_has_reservation = false` antes do sinal); guardas pós-callback em `_start_delivering()`, `request_community_cancel()`, `cancel()`, `_finish_succeeded()`, `_finish_failed()` e `_finish_cancelled()`. `Unit.gd` permaneceu 100% intocado.
2. **`src/rts/community_task_dispatcher.gd`:** contabilização exata de `"superseded_by_newer_order"` e de substituições durante `"cancelled_immediately"` em `preserved_personal_orders_count`.
3. **`src/ui/community_selection_actions_hud.gd` e `src/rts/autonomous_gather_input.gd` (otimização focal `D2-P01`):** `begin_batch_refresh()`/`end_batch_refresh()` reentrantes (limpos em `unbind()`/`configure()`) + guardas no-op em propriedades/layout inalterados, consolidando `6 → 1` `refresh()` por lote de cancelamento **sem suprimir nenhum sinal do `CommunityWorkBoard`** e com `0,00 px` de deslocamento visual.

---

## 3. D2-T01 — Reconciliação da Matriz Original (64 Requisitos) e Nova Suíte Adversarial

A suíte histórica `tests/integration/test_r_03a_d2_selective_work_cancellation.gd` (`8` testes, `330` asserções) foi preservada intacta sem renumeração silenciosa. A reconciliação integral dos 64 requisitos originais contra a base `c9f1084` identificou **38 completos, 22 parciais e 4 ausentes** (`S11`, `S13`, `O07`, `O09`, além de `O10` defeituosa em `worker_slot_released`/`state_changed`).

A nova suíte **`tests/integration/test_r_03a_d2_r1_adversarial_cancellation.gd`** (`7/7 PASS`, **`319` asserções**, `0` erros/avisos) cobre integralmente `T01-A`–`T01-I` e todas as 26 lacunas parciais/ausentes, elevando a matriz original para **64/64 cobertas com pré-condições verificadas** (tabela completa em `evidencias/R-03A/D2/R1/05_d2_t01_matriz_original/MATRIZ_RECONCILIADA_64_REQUISITOS_D2.md`).

### Alcance da Conservação Econômica e Lotes de Recuperação (`T01-C`, `T01-D`, `T01-E`)
- **Caminho público completo:** produzidos lotes `CANCEL_BUFFER` reais a partir de cancelamento real de `ConstructionSite` (`ReservedWithdrawalCoordinator.execute_site_cancellation` + `recover_cancellation_materials`); confirmado que `CommunityTaskDispatcher` recusa legitimamente trabalhadores com carga não-`FREE_GATHERED` (`reserved_or_recovery_cargo`), preservando intactos mochila e `CancellationCustodyRecord` (`validate_custody_accounting_pure == true`).
- **Defesa em profundidade na ordem (`T01-D`):** com carga mista (`CANCEL_BUFFER` real + `SITE_RESERVED` + `FREE_GATHERED`), a entrega residual deposita **exclusivamente** os lotes `FREE_GATHERED` e preserva exatamente `lot_id`, `origin`, `quantity`, `site_id`, `generation` e `region_id` dos demais lotes.
- **Recibos e Replay (`T01-E`, `E05`):** verificados `last_extraction_receipt`, `last_delivery_receipt` (`operation_id`) e replay idempotente via `SelectiveCampDeliveryCoordinator` (`replayed=true`, `+0` ao estoque).

---

## 4. D2-P01 — Desempenho do Maior Lote Legítimo (`1920×1080`, UHD 620, AC, VSync OFF, 10 reps)

| Cenário (`1920×1080`, `AC_Battery_100pct`) | Base D2 (`c9f1084`) CPU síncrona média (`frame p95`) | R1 (`R1_OPTIMIZED`) CPU síncrona média (`frame p95`) | Diferença CPU síncrona | Atualizações HUD / lote |
|---|---:|---:|---:|---:|
| Cancelamento individual (`1` árvore) | `1,889 ms` (`12,266 ms`) | `1,587 ms` (`9,348 ms`) | `-16,0%` | `1 → 1` |
| **Seis árvores** (c/ carga + entrega residual) | `9,227 ms` (`15,118 ms`) | `5,888 ms` (`13,247 ms`) | **`-36,2%`** | `6 → 1` |
| Quatro pedras (`4`) | `7,016 ms` (`13,831 ms`) | `5,293 ms` (`10,595 ms`) | **`-24,6%`** | `4 → 1` |
| Quatro arbustos (`4`) | `7,972 ms` (`17,693 ms`) | `5,506 ms` (`11,972 ms`) | **`-30,9%`** | `4 → 1` |
| **Seis árvores em seleção heterogênea (`14` sel.)** | `18,964 ms` (`26,169 ms`) | `8,769 ms` (`16,991 ms`) | **`-53,8%` (`-10,195 ms`)** | `6 → 1` |
| **Seis árvores mantendo pedra/alimento ativas** | `21,149 ms` (`50,569 ms`) | `7,752 ms` (`35,846 ms`) | **`-63,3%` (`-13,397 ms`)** | `6 → 1` |

- **`1280×720`:** redução consistente de **`-58,1%`** (`17,160 ms → 7,187 ms`, frame p95 `13,612 ms`) em seleção heterogênea e **`-62,0%`** (`19,716 ms → 7,496 ms`) mantendo pedra/alimento ativas.
- **Polling:** `0` (`hud` e `dispatcher` com `_process = false`, `_physics_process = false`).
- **Equivalência visual (`720p`/`1080p`):** deslocamento de lajes e selos `0,00 px`, `PROTECTED_HASH_DIFF_COUNT=0` nos 11 arquivos protegidos.
- **D4 permanece `ABERTA`:** não foram iniciadas otimizações globais da D4 (pico a frio histórico `110,101 ms`, carga máxima 14 tarefas `17,57 ms` e custo residual de render/despacho simultâneo com 14 fontes permanecem reservados à D4).

---

## 5. Validação Integral, Regressão e Preservação da D1

| Indicador | Base D2 (`c9f1084`) | Revisão D2 R1 | Observação |
|---|---:|---:|---|
| Suítes descobertas / executadas | `89 / 89` | **`90 / 90`** | `+1` suíte adversarial R1 (`Duplicates=0`, `Missing=0`) |
| Testes executados / aprovados | `657 / 657` | **`664 / 664`** | `+7` testes adversariais R1 (`0` falhas, `0` erros de suíte) |
| Asserções | `30.936` | **`31.236`** | `+319` novas asserções R1 e `-19` variação natural por contagem de quadros em testes de física |
| Scripts checados (`validate.ps1`) | `214` (`0/0`) | **`215` (`0/0`)** | `DOCS_DESIGN_IMPORT_COUNT=0` |
| Lotes segmentados | `63` | **`64`** | `63/64` exit `0` + `integration-22` (`test_t3_2_placement_flow.gd`, intocado) `5/5 PASS` (`111` asserções) seguido de exit pós-resumo intermitente `-1073741819` no Godot 4.7.2 headless Windows, reconfirmado **`3/3 PASS (exit=0)`** |
| Suítes focais (§18) | `16 / 16` | **`19 / 19`** | Inclui `D1`, `D2`, `D2 R1`, `RUX-*`, `T2`, `T3.6.2` e `T3.6.3` (`b1_4` com `-TimeoutSeconds 240`) |
| Smokes (`720p` e `1080p`, `-FailOnWarnings`) | Aprovados | **Aprovados** | `0` erros, `0` avisos |
| Arquivos protegidos (`SHA-256`) | `0` diffs | **`0` diffs** | Atlas, manifesto, ícones, `main.tscn`, `project.godot`, `rts_input_controller.gd`, `tree_source.tscn`, GDD v1.3 e D2.2 intactos |

---

## 6. Limitações e Reteste Humano Pendente

- **Limitações declaradas:** `A01-R6` foi refutada no modo canônico de proveniência (`use_provenance_economy=true`, onde `_coordinator_transaction_locked` bloqueia reentrância); `T01-E` (`inventory_changed`) ocorre pós-commit ainda sob lock transacional (e assim classificado); `D4` permanece em aberto; `integration-22` apresentou exit `-1073741819` pós-resumo em 1 execução headless Windows (reconfirmada `3/3 exit=0`).
- **Reteste humano (`PENDENTE` — não executado por humano ainda):** roteiro completo `HD2-01`–`HD2-10` + `HD2-R1-01`–`HD2-R1-03` arquivado em `evidencias/R-03A/D2/R1/14_reteste_humano/ROTEIRO_RETESTE_HUMANO_R03A_D2_R1.md`.
- **Comando de execução da candidata:** `Set-Location 'C:\Projetos\Dawn_of_Kin_wt_r_03a'; .\tools\run_game.ps1`
