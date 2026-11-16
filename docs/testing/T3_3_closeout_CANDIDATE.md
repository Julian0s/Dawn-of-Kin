# Dawn of Kin — Registro Candidato de Encerramento da Etapa T3.3 (CANDIDATE)

> **Adendo de Status Posterior (16/11/2026):** Este documento preserva o **registro candidato histórico (`T3.3-CLOSEOUT-CANDIDATE`)** submetido antes da homologação final. Posteriormente, em **16/11/2026**, a etapa **T3.3 foi formalmente homologada pelo proprietário** em [T3_3_closeout_ACCEPTANCE.md](T3_3_closeout_ACCEPTANCE.md), **integrada à `main` no commit `3c6fc0bd36fc3828af5a89662fb23cfb60d37865`** e marcada com a **tag anotada `t3-3-complete`**. A implementação da **T3.4 permanece bloqueada e não autorizada** (aguardando `T3.4-ARCHITECTURE-R2` e decisão expressa do proprietário).
>
> **Governança Original do Candidato *(preservada como histórico)*:** Este documento consolida a execução técnica e os **10/10 testes manuais aprovados pelo proprietário em 16/11/2026** como **candidato a homologação (`T3.3-CLOSEOUT-CANDIDATE`)**. Na data de geração do candidato, a etapa **T3.3 NÃO estava formalmente homologada** e dependia de auditoria independente e autorização expressa do proprietário.

---

## A. Identificação

- **Etapa:** T3.3 — Canteiro de Obra e Suprimento Físico (Transporte)
- **Branch de implementação:** `feature/t3-3-construction-logistics`
- **HEAD técnico de referência:** `6c5c444b07fd2aa6cb1d2f0f03c38aa78eb0c59b`
- **Base oficial (`origin/main` intacta):** `931ad196346251e3f24a3ea5db6facb3641233bc`
- **Worktree:** `C:\Projetos\Dawn_of_Kin_wt_t3_3_construction`
- **Data de consolidação manual:** 16 de novembro de 2026
- **Engine / Renderer:** Godot `4.7.2.stable` (`gl_compatibility`)
- **Escopo:** Criação transacional de canteiro (`ConstructionSite`), reserva atômica em pilhas, retirada física direcionada, transporte com peso/carga (`UnitCarryLoad`), entrega ao buffer do canteiro, organização **D9** (`1` transportador + até `2` construtores), correções `T3.3-R1` / `T3.3-R2` e melhorias de teste `T3.3-UX`.

---

## B. Contexto Anterior

- **T1 — Fundação RTS:** concluída, aprovada e marcada com a tag `t1-complete` (`2808799`).
- **T2 — Trabalho e Recursos (`T2.0`–`T2.6` + `B1`):** concluída, formalmente aprovada pelo proprietário em 14/11/2026 e marcada com a tag `t2-complete` (`f7c2459`), com 182/182 testes automatizados e 21/21 itens manuais aprovados.
- **T3.1 — Contabilidade, Reservas e Saque em Lote:** implementada, auditada pelo ChatGPT, aprovada pelo proprietário em 15/11/2026 (`b05e8e6`, [T3_1_closeout.md](T3_1_closeout.md)) e integrada na `main` (`ceb3f71`).
- **T3.2 — Validação Espacial, Área Reservada e Prévia sem Grid:** implementada, auditada pelo ChatGPT, aprovada pelo proprietário em 15/11/2026 com 11/11 testes manuais (`f2110b6`, [T3_2_closeout.md](T3_2_closeout.md)) e integrada na `main` (`931ad19`).

---

## C. Escopo da T3.3 vs. Etapas Futuras Não Implementadas (`T3.4`–`T3.9`)

### Incluído na T3.3
- Instanciação de canteiros de obra (`ConstructionSite` via `ConstructionManager`) após confirmação válida do posicionamento.
- Reserva transacional atômica no estoque físico (`SettlementInventory` / `PileReservationLedger`) com rollback em falha.
- Retirada física direcionada à pilha reservada específica (`pile_id`), transporte com desaceleração por peso e entrega ao buffer do canteiro.
- Tratamento de deterioração segundo a **Alternativa B — Perda Direta** (`reservation_lost_to_decay` sem realocação automática).
- Organização **D9** de trabalhadores (`max_builders = 2`), promoção automática de construtor em espera após interrupção do transportador e recusa do 4º trabalhador (`no_worker_slot`).
- Picking RTS de canteiros e painel provisório de inspeção/testes (`PlacementTestOverlay` / `TemporarySitePanel`).

### Explicitamente fora de escopo (não implementado nesta etapa)
- **T3.4:** Consumo do buffer em progresso construtivo, transmutação para edifício concluído, slots de construção ativa e rebake na `WorldNavigation` ativa.
- **T3.5:** Catálogo definitivo e inspetor final de construções.
- **T3.6:** Cancelamento de canteiro e reembolso/restituição proporcional.
- **T3.7:** Armazenamento em depósito físico construído.
- **T3.8:** Persistência em disco / save-load.
- **T3.9 / posteriores:** Etapas futuras de construção, família, recrutamento ou narrativa.

---

## D. Histórico Técnico

1. **Implementação inicial T3.3 (`ea14681`, `a457197`, `82d720d`, `9774035`):** núcleo de `ConstructionSite`, `ConstructionManager`, `BuildSlotPlanner`, `ConstructOrder`, integração RTS/UI provisória e suítes iniciais.
2. **Revisão T3.3-R1 (`187f051`, `ca94d11`):** correção de propriedade dos claims em trânsito (`_transit_claims`), alcance físico desobstruído contra paredes (`MASK_WORLD_SOLID`) e coordenação pós-interrupção (`WAITING_FOR_PEER_SUPPLY` e `has_active_peer_transport_for_site`).
3. **Reprovação manual de B2 (T3.3-R1):** nos testes manuais do proprietário, um canteiro no platô próximo à rampa do `TestMap` fez o trabalhador travar na lateral da rampa, interrompendo o suprimento após uma entrega parcial.
4. **Diagnóstico e correção T3.3-R2 (`bb62e85`):** reprodução visual renderizada em `1280×720` e `1920×1080` na Intel UHD Graphics 620, identificação da ponte lateral de NavMesh na rampa e ajustes em `WorldNavigation`, `BuildSlotPlanner`, `UnitMovement` e `ConstructOrder` ([T3_3_R2_plateau_navigation_diagnostic.md](T3_3_R2_plateau_navigation_diagnostic.md)).
5. **Melhorias T3.3-UX (`6c5c444`):** seletor modular de resolução em tempo de execução (`1280×720 ↔ 1920×1080`) e criação/remoção segura dos trabalhadores temporários `Worker3` e `Worker4` para habilitar o teste manual C4 ([T3_3_UX_technical_notes.md](T3_3_UX_technical_notes.md)).
6. **Aprovação manual consolidada (16/11/2026):** proprietário executou e aprovou **10/10** itens do protocolo manual (incluindo reteste de **B2**, **C4-A..E** e troca dinâmica de resolução), sem observações adicionais.

---

## E. Causas e Correções Consolidadas

1. **Propriedade da carga entregue à obra (`src/buildings/construction_site.gd`):** `accept_delivery_from_carry_load(unit, carry_load)` exige `unit` válido e limita o aceite aos `_transit_claims` atribuídos àquele trabalhador e àquela obra, preservando cargas não atribuídas ou pertencentes a outras obras.
2. **Verificação de alcance físico e bloqueios (`src/buildings/build_slot_planner.gd`, `src/units/orders/construct_order.gd`):** `has_clear_physical_access()` valida via raycast físico 3D (`CollisionLayers.MASK_WORLD_SOLID`) e bloqueia retiradas/entregas através de paredes ou degraus baixos (`minf + 0.35` quando `absf(from_pos.y - to_pos.y) > 0.20`), revalidando no instante da retirada e da entrega.
3. **Espera e continuidade após interrupção (`src/buildings/construction_site.gd`, `src/units/orders/construct_order.gd`):** `has_active_peer_transport_for_site(exclude_unit)` ignora reivindicações órfãs de colegas interrompidos; `WAITING_FOR_PEER_SUPPLY` aguarda reativamente sem corromper cargas pré-existentes de `BUILDER_STANDBY`.
4. **NavMesh na lateral da rampa (`src/navigation/world_navigation.gd`):** `_append_sloped_terrain_side_curbs()` insere barreiras virtuais finas de bake (`0.40 m`) apenas nas laterais de corpos inclinados (`5°..45°`) em `MASK_TERRAIN`, eliminando a ponte lateral da rampa em `z = -12.0` e `z = -16.0` mantendo abertos o pé e o topo.
5. **Posições de trabalho, altura e tentativas de movimento (`src/buildings/build_slot_planner.gd`, `src/units/unit_movement.gd`, `src/units/orders/construct_order.gd`):** `HEIGHT_TOLERANCE` reduzida para `0.85`, checagem de cota física do terreno (`_sample_terrain_ground_y`), `WAYPOINT_VERTICAL_TOLERANCE_Y = 0.65` (preservando `AVOIDANCE_NAVMESH_CLAMP_TOLERANCE_Y = 0.75`) e `_retry_perimeter_slot_move()` para tentar slots alternativos em `MoveState.FAILED_STUCK`.
6. **Alternância dinâmica de resolução (`src/ui/display_resolution_service.gd`, `src/buildings/placement_test_overlay.gd`):** `DisplayResolutionService` alterna `1280×720 ↔ 1920×1080` apenas na janela do jogo sem recarregar cena/partida nem alterar o Windows, respeitando `screen_get_usable_rect()` para impedir janela inacessível e atualizando o HUD.
7. **Criação e remoção segura de `Worker3` e `Worker4` (`src/units/temporary_test_workers_controller.gd`, `src/main/main.gd`):** botão `Adicionar 2 trabalhadores de teste — C4` posiciona `Worker3` e `Worker4` em terreno navegável próximo ao acampamento sem duplicar; `Remover temporários` bloqueia remoção se houver carga na mochila (`cargo_in_backpack`) ou reserva em trânsito (`transit_claim_active`).
8. **Recusa do quarto trabalhador (`src/rts/command_controller.gd`, `src/buildings/placement_test_overlay.gd`):** `command_rejected(pick, reason)` propaga `no_worker_slot` também em comandos via botão direito (`RMB`), exibindo motivo compreensível no banner sem afetar os 3 trabalhadores anteriores.

---

## F. Matriz de Validação Manual (Executada pelo Proprietário em 16/11/2026)

*Execução realizada exclusivamente pelo proprietário em janela real (não pelo ChatGPT). Observações finais do proprietário: nenhuma.*

| ID | Cenário Manual | Histórico / Detalhe | Resultado |
|---|---|---|---|
| **A1** | Rejeição segura com estoque livre insuficiente | — | **APROVADO** |
| **A2** | Criação de canteiro e reserva imediata no HUD | — | **APROVADO** |
| **B1** | Inspeção por `LMB` e botões do painel provisório | — | **APROVADO** |
| **B2** | Ciclo físico completo com 1 trabalhador | Reprovou na R1 (lateral da rampa); corrigido na R2; **aprovado em reteste manual** | **APROVADO** |
| **C1** | Regra D9 com 2 trabalhadores (`1 transportador + 1 construtor`) | — | **APROVADO** |
| **C2** | Promoção automática ao interromper o transportador | — | **APROVADO** |
| **C3** | Interrupção com carga e devolução de recurso incompatível | — | **APROVADO** |
| **C4** | Limite D9 com 3 e 4 trabalhadores (`C4-A` a `C4-E` + remoção segura) | C4-A (1), C4-B (2), C4-C (3), C4-D (4º recusado), C4-E (promoção, entrega e remoção segura) | **APROVADO** |
| **D1** | Bloqueio de sobreposição sobre canteiro existente | — | **APROVADO** |
| **D2** | Câmera, seleção em caixa, console e resoluções (`1280×720 ↔ 1920×1080`) | Inclui aprovação da troca dinâmica na mesma partida | **APROVADO** |

**Veredito Manual Consolidado:** **10/10 aprovados**, 0 reprovações atuais, 0 casos manuais pendentes.

---

## G. Evidências Versionadas

### 1. Evidências T3.3-R2 (`docs/testing/evidence/t3_3_r2_plateau/`, Intel UHD Graphics 620)
- **Resumos JSON:**
  - Antes (`pre_fix`): [pre_fix_summary_1280x720.json](evidence/t3_3_r2_plateau/pre_fix_summary_1280x720.json), [pre_fix_summary_1920x1080.json](evidence/t3_3_r2_plateau/pre_fix_summary_1920x1080.json)
  - Depois (`post_fix`): [post_fix_summary_1280x720.json](evidence/t3_3_r2_plateau/post_fix_summary_1280x720.json), [post_fix_summary_1920x1080.json](evidence/t3_3_r2_plateau/post_fix_summary_1920x1080.json)
- **Telemetria JSONL:**
  - Antes (`pre_fix`): [pre_fix_telemetry.jsonl](evidence/t3_3_r2_plateau/pre_fix_telemetry.jsonl), [pre_fix_telemetry_1920x1080.jsonl](evidence/t3_3_r2_plateau/pre_fix_telemetry_1920x1080.jsonl)
  - Depois (`post_fix`): [post_fix_telemetry.jsonl](evidence/t3_3_r2_plateau/post_fix_telemetry.jsonl), [post_fix_telemetry_1920x1080.jsonl](evidence/t3_3_r2_plateau/post_fix_telemetry_1920x1080.jsonl)
- **Capturas PNG representativas (dimensões reais verificadas: `1280×720` em `1280x720/` e `1920×1080` em `1920x1080/`):**
  - Antes (`pre_fix`): [1280x720/pre_fix/09_pre_fix_failure_state.png](evidence/t3_3_r2_plateau/1280x720/pre_fix/09_pre_fix_failure_state.png), [1920x1080/pre_fix/09_pre_fix_failure_state.png](evidence/t3_3_r2_plateau/1920x1080/pre_fix/09_pre_fix_failure_state.png), [1280x720/pre_fix/scenario_E_final.png](evidence/t3_3_r2_plateau/1280x720/pre_fix/scenario_E_final.png), [1920x1080/pre_fix/scenario_E_final.png](evidence/t3_3_r2_plateau/1920x1080/pre_fix/scenario_E_final.png)
  - Depois (`post_fix`): [1280x720/post_fix/scenario_D_detour.png](evidence/t3_3_r2_plateau/1280x720/post_fix/scenario_D_detour.png), [1920x1080/post_fix/scenario_D_detour.png](evidence/t3_3_r2_plateau/1920x1080/post_fix/scenario_D_detour.png), [1280x720/post_fix/09_post_fix_completed_standby.png](evidence/t3_3_r2_plateau/1280x720/post_fix/09_post_fix_completed_standby.png), [1920x1080/post_fix/09_post_fix_completed_standby.png](evidence/t3_3_r2_plateau/1920x1080/post_fix/09_post_fix_completed_standby.png)

### 2. Evidências T3.3-UX (`docs/testing/evidence/t3_3_ux/`, NVIDIA GeForce GTX 1060)
- **Resumos JSON e Telemetria JSONL:**
  - [summary_1280x720.json](evidence/t3_3_ux/summary_1280x720.json), [summary_1920x1080.json](evidence/t3_3_ux/summary_1920x1080.json)
  - [telemetry_1280x720.jsonl](evidence/t3_3_ux/telemetry_1280x720.jsonl), [telemetry_1920x1080.jsonl](evidence/t3_3_ux/telemetry_1920x1080.jsonl)
- **Capturas PNG (com dimensões reais verificadas por arquivo):**
  - Execução inicial `1280x720/`: [01_four_workers_and_site.png](evidence/t3_3_ux/1280x720/01_four_workers_and_site.png) (`1280×720`), [04_c4_c_three_workers.png](evidence/t3_3_ux/1280x720/04_c4_c_three_workers.png) (`1280×720`), [05_mid_transport_1920x1080_target.png](evidence/t3_3_ux/1280x720/05_mid_transport_1920x1080_target.png) (**`1920×1080`** após troca dinâmica `1280×720 → 1920×1080`), [06_c4_d_fourth_rejected.png](evidence/t3_3_ux/1280x720/06_c4_d_fourth_rejected.png) (`1280×720` após retorno), [07_c4_e_promoted_and_supplied.png](evidence/t3_3_ux/1280x720/07_c4_e_promoted_and_supplied.png) (`1280×720`).
  - Execução inicial `1920x1080/`: [01_four_workers_and_site.png](evidence/t3_3_ux/1920x1080/01_four_workers_and_site.png) (`1920×1080`), [04_c4_c_three_workers.png](evidence/t3_3_ux/1920x1080/04_c4_c_three_workers.png) (`1920×1080`), [05_mid_transport_1920x1080_target.png](evidence/t3_3_ux/1920x1080/05_mid_transport_1920x1080_target.png) (`1920×1080`), [06_c4_d_fourth_rejected.png](evidence/t3_3_ux/1920x1080/06_c4_d_fourth_rejected.png) (**`1280×720`** após troca dinâmica `1920×1080 → 1280×720`), [07_c4_e_promoted_and_supplied.png](evidence/t3_3_ux/1920x1080/07_c4_e_promoted_and_supplied.png) (**`1280×720`**).

---

## H. Testes Automatizados (Histórico Reportado pelo Antigravity)

*Nota de governança: os resultados abaixo representam a última bateria técnica executada e reportada pelo Antigravity sobre o commit `6c5c444` antes deste incremento exclusivamente documental; não foram reexecutados nesta tarefa documental nem pelo ChatGPT.*

- `.\tools\validate.ps1`: **109 scripts GDScript verificados, 0 erros, 0 avisos** (`Validation PASSED`).
- `.\tools\run_tests.ps1 -Filter "t3_3"`: **4/4 suítes, 23/23 testes aprovados, 433 asserções** (`test_t3_3_ux_display_and_workers.gd`: `2/2`, `test_t3_3_ux_flow.gd`: `3/3`, `test_t3_3_construction_logistics.gd`: `11/11`, `test_t3_3_construction_site.gd`: `7/7`).
- `.\tools\run_tests.ps1 -Segmented`: **7/7 lotes PASS, 34/34 suítes aprovadas (`Discovered=34, ExecutedUnique=34, Duplicates=0, Missing=0`), 234/234 testes aprovados, 7.585 asserções, 0 falhas, 0 erros de suíte**.
- `git diff --check`: **limpo** na execução técnica registrada.

---

## I. Ressalva de Hardware

- Os testes gráficos e benchmarks da **T3.3** inicial, **T3.3-R1** e **T3.3-R2** foram executados em **Intel(R) UHD Graphics 620** (`gl_compatibility`).
- As capturas automatizadas da **T3.3-UX** (`tests/visual/t3_3_ux_repro.gd`) foram executadas em **NVIDIA GeForce GTX 1060** (`OpenGL 3.3.0 NVIDIA 461.40`); essas execuções na GTX 1060 **não substituem** medições de desempenho específicas na Intel UHD Graphics 620.

---

## J. Desempenho

- No benchmark `tests/perf/t3_3_logistics_benchmark.gd` pós-R2 em **Intel UHD Graphics 620** sob **tomada CA** (`BatteryStatus = 2`, plano `Equilibrado`):
  - `1920×1080`: `126,08 FPS` médios (`mean 7,931 ms`, `p50 7,053 ms`, `p95 14,080 ms`, `max 93,201 ms`, `0` quadros `> 100 ms`), `site_creation_ms` média `2,552 ms`.
  - `1280×720`: `255,68 FPS` médios (`mean 3,911 ms`, `p50 3,680 ms`, `p95 5,476 ms`, `max 7,710 ms`, `0` quadros `> 100 ms`), `site_creation_ms` média `4,000 ms`.
- Em **bateria DC** (`BatteryStatus = 1`), medições anteriores pós-R1 na Intel UHD Graphics 620 registraram `103,75 FPS` (`p95 15,290 ms`) em `1080p` e `133,88 FPS` (`p95 11,893 ms`) em `720p` (`0` quadros `> 100 ms`), preservando-se a ressalva metodológica já documentada desde a T2 de que variações entre CA e DC não permitem atribuir causalidade física específica sem telemetria síncrona de clock/potência/temperatura.

---

## K. Contratos Técnicos Aprovados (GDD v1.0 e Decisões D4 / D9)

| Construção | Custo | Dimensões |
|---|---|---|
| Abrigo Básico | 12 Madeira + 6 Pedra | 4×4 m |
| Depósito Rústico | 18 Madeira + 10 Pedra | 5×4 m |

Organização **D9** (máximo de **2** construtores simultâneos):
- **1 trabalhador:** supridor individual (`SOLO_SUPPLIER`).
- **2 trabalhadores:** `1` transportador (`TRANSPORTER`) + `1` construtor em espera (`BUILDER`).
- **3 trabalhadores:** `1` transportador (`TRANSPORTER`) + `2` construtores em espera (`BUILDER`).
- **4º trabalhador:** designação automática recusada (`no_worker_slot`).

---

## L. Governança *(Registro Histórico da Submissão Candidata)*

- Os **10/10** testes manuais foram executados e aprovados pelo proprietário em **16/11/2026**.
- Na submissão candidata original, a homologação formal aguardava auditoria independente; **essa homologação foi posteriormente concedida** em [T3_3_closeout_ACCEPTANCE.md](T3_3_closeout_ACCEPTANCE.md) (`main` `3c6fc0b`, tag `t3-3-complete`). **O início da implementação da T3.4 permanece estritamente bloqueado** aguardando `T3.4-ARCHITECTURE-R2` e autorização expressa do proprietário.

---

## M. Pendências e Riscos Futuros

- **Interface temporária:** `PlacementTestOverlay` e `TemporarySitePanel` são provisórios para validação da T3.2/T3.3 e serão substituídos pelo catálogo e inspetor definitivos na **T3.5**.
- **Recursos exclusivos de teste:** os botões de resolução dinâmica (módulo `DisplayResolutionService` pronto para futuro menu de Configurações) e os trabalhadores temporários `Worker3`/`Worker4` (`TemporaryTestWorkersController`) existem apenas como apoio de validação sem alterar narrativa, campanha, recrutamento ou reprodução.
- **Particularidade das capturas após redimensionamento:** no runner `t3_3_ux_repro.gd`, as capturas após o passo 5 refletem a resolução ativa após a troca dinâmica em voo (não necessariamente o nome da pasta de origem).
- **Energia DC e hardware alvo:** manter monitoramento de desempenho em bateria DC e na Intel UHD Graphics 620 nas próximas etapas.
- **Etapas futuras pendentes:** montagem progressiva e rebake ativo (**T3.4**), UI definitiva (**T3.5**), cancelamento/reembolso (**T3.6**), depósito protetor utilizável (**T3.7**) e persistência em disco (**T3.8**).
