# Dawn of Kin — T3.4.3 — Relatório técnico da candidata

**Status:** **T3.4.3 IMPLEMENTADA COMO CANDIDATA — AGUARDANDO AUDITORIA INDEPENDENTE DO CHATGPT E HOMOLOGAÇÃO EXPRESSA DO PROPRIETÁRIO. SEM MERGE, SEM TAG, T3.4.4–T3.4.5 BLOQUEADAS.**

**Data:** 17/11/2026. **Branch:** `feat/t3-4-3-reactive-construction-orders`.

**Worktree:** `C:/Projetos/Dawn_of_Kin_wt_t3_4_3`.

**Commit de implementação funcional:** `bb55f9a195a3deb45ca329553631c774cbb7a48f`. **Commit de testes automatizados:** `194e1f44bd159a82acf6ad142881ccd41af5d235`. *(O commit seguinte nesta branch é estritamente documental.)*

---

## 1. Base e governança verificadas

- **`origin/main` integrado (base obrigatória):** `700c1bb9bfbd422e26a53afbbc34ddb3119aa2d7` (contendo `T3.4.2` homologada em `54cc0818cc54a4b4275e64bc92946773c5842173` e `T3.4.1` em `60cfbe67382ccc321ee879c90c21fe449f16bf13`).
- **Arquitetura normativa (`T3.4-R2.3`):** `da20244f4320f0ae5e03236553f5c0e3f57f3a6f`, com aprovação registrada em `origin/planning/t3-4-architecture-r2` commit `39cdaac674d78111efd300b70b8f2f3909e347f9`.
- **GDD normativo:** `docs/Dawn_of_Kin_GDD.md`, versão `1.2`.
- **Tags preservadas sem alteração:** `t1-complete`, `t2-complete`, `t3-3-complete`.
- **Engine executada:** Godot `4.7.2.stable.official.ed1daf0bf` (headless CLI), renderer `gl_compatibility`. Nenhuma alteração em `main`, `GDD v1.2`, `AGENTS.md`, `T3_4_implementation_plan_PROPOSAL.md`, nem código das etapas futuras (`T3.4.4`–`T3.8`).

---

## 2. Arquivos alterados e criados

### Código de produção
1. [`src/buildings/construction_site.gd`](../../src/buildings/construction_site.gd)
   - Adicionados getters/predicados de ciclo e elegibilidade de montagem:
     - `is_completed_or_completing() -> bool` (`COMPLETING` ou `COMPLETED`).
     - `has_any_received_materials() -> bool` (soma positiva em buffer + consumido).
     - `has_consumable_work_available() -> bool` (`is_active() and has_any_received_materials() and _can_unblock_starvation()`).
     - `get_assigned_builder_slot_position(unit: Unit) -> Dictionary`.
     - `has_deliverable_transit_claim_for_unit(unit: Unit) -> bool`.
   - Implementadas as APIs de transição `D9` / `DEC-18`:
     - `try_promote_solo_to_builder(unit: Unit) -> bool`: promove `SOLO_SUPPLIER` para `BUILDER` apenas quando livre de carga reivindicada para a obra e quando `is_fully_supplied()` é verdadeiro **ou** não há pilhas reservadas reivindicáveis (`_has_claimable_reserved_piles_for`) e existe material consumível no buffer (`has_consumable_work_available()`).
     - `rebalance_for_assembly_on_supply_complete(unit: Unit) -> WorkerRole`: quando `is_fully_supplied()` é atingido: (i) preserva `force_transporter` encerrando ao fim do suprimento; (ii) se houver vaga abaixo de `mini(2, max_builders)`, promove o transportador após os construtores já ativos em `_worker_order_ids` (preservando a âncora de `slot 0` sem deslocamento indevido); (iii) em equipe de `3` (quando `2` construtores já estão ativos), desregistra o transportador (`UNASSIGNED`) para retornar a `Unit.State.IDLE`.
   - Reforços de ciclo reativo em `_on_inventory_reservations_changed()` e `_rebalance_worker_roles()`:
     - Caso um trabalhador solitário promovido a construtor (`solo_promoted_builder`) esteja aguardando em `PAUSED_STARVED` e receba nova reserva via `authorize_manual_complement()` (`DEC-11B`), retorna automaticamente para `SOLO_SUPPLIER` para buscar as pilhas recém-reservadas antes de retomar a montagem.
     - O rastreador `_supply_rebalance_completed` preserva integralmente o comportamento de registro inicial `D9` (`1 TRANSPORTER + até 2 BUILDER`) esperado pelas suítes de backend da `T3.4.2` (`BackendOrder`).
   - Preservação integral das `9` guardas de `contribute_work()` e da aritmética exata em microssegundos (`evaluate_work_transaction_usec`).

2. [`src/units/orders/construct_order.gd`](../../src/units/orders/construct_order.gd)
   - Adicionadas as fases `Phase.BUILDER_ASSEMBLING` e `Phase.WAITING_FOR_MATERIALS`, com `is_preparing_work()` atualizado.
   - Conexão e desconexão reativa dos sinais `site.buffer_changed`, `site.workers_changed` e `site.state_changed`:
     - Despertar orientado exclusivamente por eventos para transição `WAITING_FOR_MATERIALS` / `BUILDER_STANDBY` -> `BUILDER_ASSEMBLING` quando `has_consumable_work_available()` e `_can_unit_assemble_now()` são verdadeiros.
     - Zero polling e zero chamadas a `site.contribute_work()` em `Phase.WAITING_FOR_MATERIALS`.
   - Registro real e ocupação contínua do slot de construtor (`R2.1-D`):
     - `_resolve_or_assign_builder_anchor(slot_idx)` calcula via `BuildSlotPlanner.compute_site_perimeter_slot()` e registra via `site.assign_builder_slot_position(_unit, slot_idx, resolved_pos)`.
     - Verifica `BuildSlotPlanner.is_unit_at_assigned_builder_slot()` (`0,75 m` XZ / `0,85 m` Y) e `BuildSlotPlanner.is_unit_in_site_dropoff_range()` antes de entrar em montagem e antes de cada passo em `_update_builder_assembling()`.
   - Loop físico em `_update_builder_assembling(movement, delta)`:
     - Invoca `site.contribute_work(_unit, minf(delta, ConstructionSite.MAX_WORK_DELTA_SEC))` no máximo uma vez por quadro de física do trabalhador.
     - Em `completed == true` ou `site.is_completed_or_completing()`, para o movimento e finaliza com `_finish_succeeded()` (`Unit.State.IDLE`), mantendo o canteiro em `SiteState.COMPLETING` sem criar `BuildingInstance` (`T3.4.4`).
     - Em `starved == true` ou `PAUSED_STARVED`, transiciona imediatamente para `Phase.WAITING_FOR_MATERIALS`.
   - Integração `D9` / `DEC-18` em `_advance_by_role()` e `_select_and_approach_next_pile()`:
     - Em `is_fully_supplied()` para papéis não forçados, invoca `site.rebalance_for_assembly_on_supply_complete(_unit)` e direciona o trabalhador promovido ao slot de construtor ou encerra com `_finish_succeeded()` no caso de `3º` trabalhador excedente.
     - Em `SOLO_SUPPLIER` sem mais pilhas reivindicáveis (`no_reserved_piles`) e com buffer consumível, invoca `site.try_promote_solo_to_builder(_unit)` e inicia a montagem física.

### Testes automatizados
3. [`tests/integration/test_t3_4_3_reactive_construction_orders.gd`](../../tests/integration/test_t3_4_3_reactive_construction_orders.gd) (+ `.uid`) *(novo)*:
   - **`test_01_t34_aut_09b_reactive_order_cycles_starvation_zero_polling_and_wakeup` (`T34-AUT-09` Parte B — 150 asserções):**
     - Verifica rejeição de `contribute_work(u1, 6.0)` pela Guarda 2 (`"invalid_delta"`).
     - Executa `20` ciclos de `0,25 s` em `ConstructOrder` sobre `SpyConstructionSite`: consumo exato de `1 wood` no ciclo `10` (`2,5 s`), pausa exata em `4_999_999 µs` (`4.999999 s`) com `starved == true` e `PAUSED_STARVED` no ciclo `20`, e transição imediata da ordem para `Phase.WAITING_FOR_MATERIALS`.
     - Executa ciclos `21..24` sem entrada de pedra confirmando **`0` chamadas** a `contribute_work()` e **`0` sinais redundantes** de `buffer_changed`/`state_changed`.
     - Confirma retorno não-mutante na chamada unitária direta `contribute_work(u1, 0.25)` em `PAUSED_STARVED`.
     - Entrega física de `1` pedra dispara `buffer_changed`, desperta a ordem para `Phase.BUILDER_ASSEMBLING`, cruza `5_000_000 µs` (`5,0 s`) consumindo `{wood: 2, stone: 1}` e prossegue exatamente até travar novamente no próximo teto de madeira (`7_499_999 µs`).
   - **`test_02_t34_aut_10_parallel_logistics_starvation_wakeup_and_full_completion` (`T34-AUT-10` — 33 asserções):**
     - `Abrigo Básico` com `2` trabalhadores (`1 TRANSPORTER + 1 BUILDER`), buffer inicial `{wood: 2, stone: 0}` e `{wood: 10, stone: 6}` reservados em pilhas.
     - Valida pausa em `4_999_999 µs` (`PAUSED_STARVED` / `WAITING_FOR_MATERIALS`), `0` polling em frames ociosos, retomada por sinal após entrega física da `1ª` pedra, continuação integral da logística (`12 wood, 6 stone`), promoção automática do transportador ao `2º` slot de construtor ao concluir suprimento, e conclusão exata em `30,0 s` (`SiteState.COMPLETING`, ordens `SUCCEEDED`, unidades `IDLE`, canteiro sem `BuildingInstance`).
   - **`test_03_t34_aut_10b_wood_decay_starvation_no_auto_realloc_and_manual_complement` (`T34-AUT-10B` — 52 asserções):**
     - Pilha 1 de madeira (`10 wood` reservadas após entrega inicial `{wood: 2, stone: 6}`, `apply_state(10, 420.0, 0.0)`) expira completamente após `+1200,0 s` em `step_decay()` preservando pedra (`DEC-11A`).
     - Pilha 3 livre criada pós-decay (`try_create_pile_at(&"wood", 10, pos_3)`) mantém `0` reserva automática (`missing(wood) == 10`).
     - Montagem pausa exatamente em `7_499_999 µs` (`consumed = {w: 2, s: 1}`, `buffer = {w: 0, s: 5}`, `0` polling).
     - `ManualComplementIntent.create_for_test` reserva `10 wood` na Pilha 3 sem alterar progresso; trabalhador retorna para `SOLO_SUPPLIER`, transporta fisicamente a madeira até o canteiro e finaliza em `30,0 s` (`consumed = {12, 6}`, `buffer = {0, 0}`, `COMPLETING`).
   - **`test_04_t34_aut_11_d9_one_two_three_fourth_worker_and_interruption_resume` (`T34-AUT-11` — 47 asserções):**
     - `1` trabalhador (`DEC-18`): `0,0 s` de montagem enquanto supre, promoção para `BUILDER` a `1,0 s/s` após `is_fully_supplied()` até `COMPLETING` -> `IDLE`.
     - `2` trabalhadores (`D9`): montagem paralela antes do fim do transporte + promoção do transportador ao `2º` slot (`2,0 s/s`) até `COMPLETING` -> `IDLE`.
     - `3` trabalhadores + recusa do `4º`: `1 TRANSPORTER + 2 BUILDER`, `4º` recusado com `REASON_NO_WORKER_SLOT`, transportador volta a `IDLE` após suprimento enquanto os `2` construtores concluem em `COMPLETING`.
     - Interrupção por `MoveOrder` em `>= 12,0 s` -> `PAUSED_NO_WORKERS`, conservação intacta de progresso/consumo/buffer e retomada limpa até `COMPLETING` sem duplicar consumo.

4. Ajustes pontuais documentados em duas asserções pré-T3.4 de regressões T3.3 *(nenhuma guarda ou invariante foi flexibilizado; asserções passaram a verificar explicitamente o comportamento `T3.4.3` + conservação integral)*:
   - [`tests/integration/test_t3_3_construction_logistics.gd`](../../tests/integration/test_t3_3_construction_logistics.gd) (`test_01`, L203–230): antes verificava `Unit.State.IDLE` `4` quadros após `is_fully_supplied()` quando ainda não havia montagem na T3.3. Atualizado para confirmar os `12 wood / 6 stone` recebidos e a promoção `SOLO_SUPPLIER -> BUILDER` (`WORKING`/`MOVING`) `4` quadros após suprimento, aguardando em seguida a conclusão física para verificar `SiteState.COMPLETING`, `consumed = {12, 6}`, `buffer = {0, 0}`, `Unit.State.IDLE` e ausência de `BuildingInstance` (`T3.4.4`).
   - [`tests/integration/test_t3_3_ux_flow.gd`](../../tests/integration/test_t3_3_ux_flow.gd) (`test_03`, L244–251): na montagem paralela de `2` trabalhadores promovidos, parte da madeira já havia sido consumida antes de `is_fully_supplied()` (`delivered_buffer = 11`, `consumed = 1`). Atualizado para verificar conservação exata via `get_total_received_amount` (`buffer + consumed == 12` madeira e `== 6` pedra) conforme o contrato da `T3.4.1` §3.2.

---

## 3. Resultados completos de validação e testes

Todos os comandos abaixo foram executados diretamente na worktree `C:\Projetos\Dawn_of_Kin_wt_t3_4_3` após a última edição:

| Verificação | Resultado observado |
|---|---|
| `.\tools\validate.ps1` | **APROVADO** — importação headless, `--check-only` em **113 scripts** e boot headless da cena principal com **0 erros e 0 avisos** (`exit 0`). |
| `.\tools\run_tests.ps1 -Segmented` | **37/37 suítes, 257/257 testes, 9.004 asserções, 0 falhas, 0 erros de suíte, 0 avisos/erros** em 8 lotes disjuntos (`Discovered=37`, `ExecutedUnique=37`, `Duplicates=0`, `Missing=0`, `SumGodotElapsed=341.957,1 ms`, `TotalWallElapsed=349.234,9 ms`). |
| Suíte `test_t3_4_3_reactive_construction_orders.gd` *(no lote `integration-06`)* | **4/4 testes, 282 asserções, 0 falhas** (`42.853,4 ms`). |
| Regressão `test_t3_4_1_accounting_and_complement.gd` | **8/8 testes, 299 asserções, 0 falhas** (`43,8 ms`). |
| Regressão `test_t3_4_2_deterministic_assembly.gd` | **11/11 testes, 829 asserções, 0 falhas** (`3.030,8 ms`). |
| Regressões `T3.3` | `test_t3_3_construction_site.gd`: **7/7** (`164`); `test_t3_3_ux_display_and_workers.gd`: **2/2** (`9`); `test_t3_3_construction_logistics.gd`: **11/11** (`212`); `test_t3_3_ux_flow.gd`: **3/3** (`57`). |
| Regressões `T1`, `T2`, `T3.1`, `T3.2` | Todas as demais `28/28` suítes unitárias e de integração aprovadas (`0` falhas). |
| `git diff --check` | **Aprovado**, `0` erros de formatação/whitespace. |

---

## 4. Desvios, falhas detectadas e correções aplicadas

1. **Conflito de reequilíbrio no registro inicial em `T3.4.2`:** a primeira versão de `_rebalance_worker_roles()` convertia trabalhadores para `BUILDER` sempre que `is_fully_supplied()` estivesse verdadeiro durante `register_worker()`/`unregister_worker()`, afetando os fixtures de backend de `test_t3_4_2` (`test_03` e `test_07`) que usam `BackendOrder` com buffer pré-cheio esperando o papel inicial `1 TRANSPORTER + 2 BUILDER`. Introduziu-se `_supply_rebalance_completed` para restringir o pós-suprimento às transições reais de `ConstructOrder` (`try_promote_solo_to_builder` / `rebalance_for_assembly_on_supply_complete`), restaurando `11/11` em `test_t3_4_2`.
2. **Expectativa numérica pós-entrega em `test_01` (`T34-AUT-09B`):** após entregar `1` pedra e cruzar `5_000_000 µs`, ainda existe folga de `2_499_999 µs` (`[5_000_000 .. 7_499_999]`) suportada por `consumed + buffer = {w:2, s:1}`; portanto o estado imediato em `5,0 s` é `ASSEMBLING` / `BUILDER_ASSEMBLING`, atingindo `PAUSED_STARVED` / `WAITING_FOR_MATERIALS` somente em `7_499_999 µs`. O teste passou a validar os dois marcos consecutivos (`5_000_000 µs` ativo e `7_499_999 µs` pausado).
3. **Asserções pré-T3.4 em duas suítes de integração `T3.3`:** ajustadas de forma pontual conforme documentado na Seção 2.

---

## 5. Classificação estrita de estado (`implementado` vs. `não verificado` vs. `bloqueado`)

- **Implementado e testado automaticamente (headless):** fases `BUILDER_ASSEMBLING` e `WAITING_FOR_MATERIALS`, despertar reativo orientado a sinais sem polling por frame, registro e verificação contínua de âncora perimetral de construtor, promoções `D9` / `DEC-18` (1, 2, 3, recusa do 4º e retorno do solitário pós-complemento `DEC-11B`), encerramento em `SiteState.COMPLETING` e suíte `T34-AUT-09B`, `T34-AUT-10`, `T34-AUT-10B`, `T34-AUT-11` integradas às regressões globais (`257/257`).
- **Não verificado visualmente/manualmente:** execução interativa por jogador humano com mouse, inspeção visual em tela das animações/posturas/painéis temporários durante montagem em andamento e medição empírica de desempenho em GPU alvo (`Intel UHD 620`, prevista para o incremento `T3.4.5`).
- **Bloqueado / fora de escopo:** criação e validação transacional de `BuildingInstance` com cooldown de retentativa e proteção de sobreposição em `PlacementValidator` (`T3.4.4`), camada regional `_buildings_root` / rebake assíncrono N1 / barreira transitória `_pending_building_blockers` / benchmark `T34-PERF-01` (`T3.4.5`), UI definitiva (`T3.5`), cancelamento/reembolso (`T3.6`), depósito funcional (`T3.7`) e persistência (`T3.8`).

**T3.4.3 IMPLEMENTADA COMO CANDIDATA — AGUARDANDO AUDITORIA INDEPENDENTE DO CHATGPT E HOMOLOGAÇÃO EXPRESSA DO PROPRIETÁRIO. SEM MERGE. T3.4.4–T3.4.5 BLOQUEADAS.**
