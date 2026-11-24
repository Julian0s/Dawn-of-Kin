# Dawn of Kin — Relatório Técnico da Candidata R-03A R1 (Revisão Corretiva)

**Incremento:** `R-03A R1` — Revisão corretiva da integração do trabalho comunitário na `MainScene`  
**Status na Taxonomia Obrigatória:**
- `R-03A R1 — IMPLEMENTADO`
- `VALIDADO TECNICAMENTE`
- `PUBLICADO EM BRANCH CANDIDATA`
- `AUDITORIA INDEPENDENTE DA R1 PENDENTE`
- `TESTES HUMANOS M1–M8 PENDENTES`
- `NÃO HOMOLOGADO`
- `NÃO INTEGRADO À DEVELOP`
- `R-03B BLOQUEADA`

**Data:** 24/11/2026  
**Candidata original auditada (preservada no histórico):** `4254011799a34960a70334fbcde8672aba171ea3` ([relatório original](R_03A_community_work_main_scene_candidate_report.md))  
**Base homologada (`develop`, intacta):** `21c34ee645725a74f1fefac9db0309ec711ab5f2`  
**Linha estável (`main`, intacta):** `25e0a20f1d6a2f10a9e059afe69759fbe263db4a`  
**Branch candidata:** `feat/r-03a-community-work-main-scene`  
**Worktree candidato:** `C:\Projetos\Dawn_of_Kin_wt_r_03a`  
**Ambiente:** Godot `4.7.2.stable.official.ed1daf0bf`, GDScript tipado, `gl_compatibility`, `Jolt Physics`, Intel UHD Graphics 620 (`1280×720` e `1920×1080`)

---

## 1. Autorização Recebida e Escopo
O proprietário autorizou exclusivamente a execução da revisão corretiva **`R-03A R1`** após auditoria técnica independente do ChatGPT sobre a candidata `4254011`, visando corrigir dois defeitos confirmados (`F01`, `F02`), suprir quatro lacunas de cobertura automatizada (`T01`, `T02`, `T03`, `T04`) e investigar o risco arquitetural de isolamento regional (`R01`), sem iniciar `R-03B`–`T8` nem integrar à `develop`.

---

## 2. Análise e Plano Executado
O plano técnico revisável foi produzido antes de qualquer edição de código e arquivado fora do checkout principal em `evidencias/R-03A/R1/auditoria/plano_tecnico_r03a_r1.md`, distinguindo explicitamente defeitos comprovados, lacunas de cobertura, risco sob investigação e contratos preservados.

---

## 3. Inventário Completo dos Consumidores de Fontes Investigados (`F01`)

| Consumidor (Arquivo / Método) | Responsabilidade | Conjunto esperado | Comportamento anterior (`4254011`) | Comportamento após R1 | Alterado / Preservado | Justificativa |
|---|---|---|---|---|---|---|
| `src/buildings/placement_validator.gd` (`ValidationContext.from_region`, `refresh_dynamic_state`) | Proteção de conectividade e validação de sobreposição na construção (hover, confirmação e revalidação assíncrona) | Todas as 14 fontes jogáveis da região, filtradas por `World3D` e `region_id`, deduplicadas | Usava `if has_method("get_resource_sources") ... else _collect_scoped_sources_recursive(...)`, omitindo as 8 fontes adicionais de `PlayableCommunitySources` (`6` em vez de `14`) | Prioriza `get_all_region_resource_sources()` (ou `get_resource_sources()`) **e** complementa com `_collect_scoped_sources_recursive()` (mesmo padrão de `units` e `piles`), filtrando por `World3D`, `region_id` e `not is_queued_for_deletion()` (`14/14`) | **Alterado** | Corrige omissão real sem criar registros concorrentes nem alterar `get_resource_sources()` |
| `src/buildings/placement_controller.gd` (`build_validation_context`) | Construir contexto regional de validação | 14 fontes via `from_region()` | Indiretamente limitado a 6 | Recebe automaticamente todas as 14 fontes da região | **Preservado** (beneficiado via `from_region`) | Fonte única de verdade mantida na hierarquia de `TestMap` |
| `levels/test_map/test_map.gd` (`get_resource_sources`) | Enumeração canônica de `TestMap/ResourceSources` para fixtures históricas | 6 fontes canônicas | 6 fontes canônicas | 6 fontes canônicas (inalterado) | **Preservado** | Contrato histórico de `T2`/`T3`/`UI-1` preservado |
| `levels/test_map/test_map.gd` (`get_all_region_resource_sources`) | Enumeração completa de fontes jogáveis sob `TestMap` | Todas as fontes `ResourceSource` válidas sob `TestMap` (14 na `MainScene`, 6 em sandboxes sem bosque extra) | Inexistente | Coleta recursiva deduplicada por instância, sem hardcode de nomes/IDs | **Adicionado** | Distingue semanticamente conjunto canônico (6) de conjunto regional completo (14) |
| `levels/test_map/test_map.gd` (`set_resource_discoverability_badges_visible`) | Alternar visibilidade das `DiscoverabilityBadge` do mapa e `CampBadge` | Todas as 14 fontes jogáveis da região | Iterava `get_resource_sources()` (omitindo 8 badges de `PlayableCommunitySources`) | Itera `get_all_region_resource_sources()` (todas as 14 badges alternam coerentemente) | **Alterado** | Defeito reproduzido em RED (`wood_tree_03`..`food_bush_04` permaneciam visíveis quando desligadas) |
| `src/ui/tree_work_menu.gd` (`_confirm`) | Protótipo histórico isolado `UX-1` (não ativo na `MainScene`) | Escopo histórico `UX-1` | 6 fontes via `get_resource_sources()` | 6 fontes (inalterado) | **Preservado** | Fora do escopo R-03A; reconciliação pertence à `R-03C` |
| `src/rts/autonomous_gather_input.gd` (`_handle_source_box_selection`) | Seleção por caixa em fontes disponíveis | Todas as 14 fontes do `World3D` e região | Usava `GROUP_RESOURCE_SOURCES` + `SelectionBoxMath` (14 fontes) | Mantém 14 fontes e filtra explicitamente por `_board.is_source_in_region_domain()` | **Alterado** (F02 + filtro regional) | Preserva natureza do gesto e domínio regional |
| `src/navigation/world_navigation.gd` | Bake inicial dos colisores `SolidBody` sob `TestMap` | 14 fontes | Já incluía as 14 fontes (`PlayableCommunitySources` filho de `TestMap`) | Inalterado | **Preservado** | Já operacional |
| `src/main/main.gd` (`_setup_playable_community_grove`) | Instanciar 8 fontes adicionais sob `TestMap/PlayableCommunitySources` | 8 fontes extras | 8 fontes extras | Inalterado | **Preservado** | Já operacional |
| Fixtures/Testes históricos (`test_t2_*`, `test_t3_*`, `test_ui_1_*`, `test_rux_*`, `test_ux_1_*`, `t2_perf_benchmark.gd`, `t3_6_2_c3_4_3_manual_harness.gd`) | Cobertura de contratos históricos | 6 fontes canônicas (`get_resource_sources()` / `get_resource_sources_root()`) | 6 fontes | Inalterado | **Preservado** | Nenhuma alteração ou enfraquecimento em testes históricos |

---

## 4. Classificação, Causas Confirmadas, Correções e Rastreabilidade (`F01`–`R01`)

| ID | Classificação pós-investigação | Causa identificada | Correção realizada / Decisão | Arquivos alterados | Testes associados | Resultado RED → GREEN |
|---|---|---|---|---|---|---|
| **F01** | **Defeito comprovado no código e reproduzido dinamicamente** (enumeração e badges; bloqueio de alcova rasa já parcialmente coberto por `pre_corridor_probes`) | `PlacementValidator.ValidationContext.from_region()` tinha `else:` bloqueando coleta recursiva; `set_resource_discoverability_badges_visible()` usava `get_resource_sources()` (6) | Adicionado `TestMap.get_all_region_resource_sources()`; atualizado `set_resource_discoverability_badges_visible()`; unificada coleta em `ValidationContext.from_region()` com filtro `World3D` + `region_id` | `levels/test_map/test_map.gd`, `src/buildings/placement_validator.gd` | `test_r1_f01_placement_connectivity_all_14_sources_and_badges` (`73` asserções) | **RED comportamental** (`13` falhas: `6` vs `14` + `8` badges omitidas) → **GREEN** (`73/73` PASS) |
| **F02** | **Defeito comprovado no código e reproduzido dinamicamente** | `_handle_box_selection()` condicionava o ramo de fontes a `is_instance_valid(_drag_origin_source)`, caindo em `super._handle_box_selection()` quando a fonte era destruída; `_on_left_press_started()` retornava cedo sob economia bloqueada | Separados `_drag_started_on_source: bool`, `_drag_origin_resource_id` e `_drag_origin_source`; natureza do gesto congelada no `mouse_down` sem jamais converter em seleção de habitantes | `src/rts/autonomous_gather_input.gd` | `test_r1_f02_drag_gesture_preserves_source_nature_across_origin_invalidation` (`20` asserções) | **RED comportamental** (`3` falhas em `F02-C2`/`F02-C3`: converteu em seleção RTS de `LeaderB`) → **GREEN** (`20/20` PASS) |
| **T01** | **Lacuna comprovada de cobertura** | `A02` retornava sem `assert_not_null(task.assigned_unit)`; `A14` checava `assert_not_null` sobre `Dictionary` sem checar `ok`; `A18` condicionava remoção a `if first_worker != null` e usava `else true`; outros testes omitiam `assert_not_null` de fixtures e pós-loop | Fortalecidas todas as precondições em `_fixture()` e `A01`–`A20` com asserções explícitas antes de retornos defensivos e validação de não-timeout; esclarecido agrupamento `A09`+`A10` | `tests/integration/test_r_03a_community_work_main_scene.gd` | `A01`–`A20` (`+70` asserções) + prova controlada reversível de mutação (`t01_mutation_proof.txt`) | **RED por mutação controlada** (`A02` falhou em `assigned_unit`) → revertido limpo → **GREEN** |
| **T02** | **Lacuna comprovada de cobertura** (comportamento de produção já correto) | `A14` original usava apenas injeção interna de lote `SITE_RESERVED` e não depositava estoque real | Corrigido `A14` para criar canteiro real (`ok=true`) e adicionado teste completo de integração real com estoque físico, `ConstructOrder`, `ReservedWithdrawalCoordinator`, bloqueio transacional e conservação | `tests/integration/test_r_03a_community_work_main_scene.gd` | `test_r1_t02_real_construction_reserved_withdrawal_and_community_coexistence` (`29` asserções) | **GREEN de cobertura complementar** sem alteração de produção (`29/29` PASS) |
| **T03** | **Lacuna de cobertura + defeito de reativação via `_ensure_wired()` + erro de engine em `stop_movement()` pós-`remove_child()` reproduzidos dinamicamente** | `teardown_community_work()` zerava `_wired = false` sem flag `_torn_down`, permitindo que `_ensure_wired()` reativasse input/dispatcher; `UnitMovement.stop_movement()` lia `_body.global_position` fora da árvore durante `request_controlled_teardown()` | Adicionada guarda `_torn_down` em `AutonomousGatherInput` (`true` em `teardown_community_work()`, `false` em `configure_community_work()`); adicionada guarda `and _body.is_inside_tree()` em `UnitMovement.stop_movement()`; captura síncrona de `get_last_domain_release_result()` + verificação em `World3D` + reinstanciação | `src/rts/autonomous_gather_input.gd`, `src/units/unit_movement.gd`, `tests/integration/test_r_03a_community_work_main_scene.gd` | `test_a18_*` (`12` asserções), `test_r1_t03_lifecycle_signals_ensure_wired_and_reinstantiation` (`23` asserções) | **RED comportamental** (`2` falhas `_ensure_wired` + erro engine `!is_inside_tree()`) → **GREEN** (`EXIT=0`, `0` erros) |
| **T04** | **Lacuna de cobertura + sub-defeito em arraste sob economia bloqueada reproduzido dinamicamente** | `_on_left_press_started()` retornava cedo com `_is_community_economy_blocked() == true`, deixando arraste sobre fonte cair na seleção RTS de unidades | Resolvido pela preservação de `_drag_started_on_source` em F02 + cobertura dos 6 vetores (clique, `Shift+Clique`, arraste, `register_gather_group`, `register_gather_task`, `request_dispatch`) | `src/rts/autonomous_gather_input.gd`, `tests/integration/test_r_03a_community_work_main_scene.gd` | `test_a19_*` (`11` asserções), `test_r1_t04_invalid_economic_admission_all_entry_vectors` (`28` asserções) | **RED comportamental** (`2` falhas em `T04-3`: vazou seleção para `LeaderA` e feedback vazio) → **GREEN** (`28/28` PASS) |
| **R01** | **Risco arquitetural investigado — sem violação demonstrável do contrato T2/T3 vigente (nenhuma alteração especulativa)** | Fontes canônicas de `TestMap/ResourceSources` não possuem `meta("region_id")` no contrato T2/T3 atual (1 `TestMap` por `World3D`); multi-região espacial sem metadados pertence à **T4** | Mantida a lógica de `CommunityWorkBoard.is_source_in_region_domain()`; validados os cenários adversariais (canônica sem meta, adicional `default`, região estrangeira, outro `World3D`, 2 regiões `region_alpha`/`region_beta` no mesmo `World3D`, reparenting pós-registro) | Apenas teste adversarial em `tests/integration/test_r_03a_community_work_main_scene.gd` (zero alteração especulativa em produção) | `test_r1_r01_regional_isolation_adversarial_investigation` (`22` asserções) | **GREEN adversarial** (`22/22` PASS, zero mutação entre domínios) |

---

## 5. Investigação R01 — Conclusão Documentada
- **Contrato vigente reconstruído:** na arquitetura T2/T3, a autoridade econômica regional (`ReservedWithdrawalCoordinator.RegionalAuthority`) é indexada em `(World3D, region_id)`. Unidades admitidas carregam `meta("region_id")`, `PlayableCommunitySources` carrega `meta("region_id") = &"default"`, e as 6 fontes canônicas históricas em `TestMap/ResourceSources` não possuem `meta("region_id")`. Nem `CommandController._inspect_economic_command()`, nem `GatherTransferSession`, nem `ReservedWithdrawalCoordinator._allocate_gather_operation_ids()` exigem `meta("region_id")` em `ResourceSource` (validam `World3D` + autoridade do acampamento/unidade).
- **Resultado dos testes adversariais (`22/22` PASS):**
  - Fontes canônicas sem meta e fontes adicionais com `region_id = &"default"` funcionam corretamente;
  - Fontes marcadas com outra região (`region_beta`) são rejeitadas com `region_mismatch` em registro direto, grupo, clique e caixa;
  - Fontes em outro `World3D` são rejeitadas em `SelectionBoxMath`, `CommunityWorkBoard`, `CommunityTaskDispatcher` e `CommandController`;
  - Duas regiões distintas (`region_alpha` e `region_beta`) no mesmo `World3D` com raízes marcadas mantêm isolamento mútuo total;
  - Reparenting de fonte já registrada para outra região impede despacho e extração (`0` ordens, `0` mutação econômica).
- **Classificação final de R01:** **refutado como defeito no contrato T2/T3 vigente; limitação conhecida / questão arquitetural futura de T4** (quando existir mundo contínuo multi-região no mesmo `World3D` com fontes sem metadados explícitos). Nenhuma alteração especulativa foi feita em produção.

---

## 6. Validação Estática, Regressão Integral, Smoke e Desempenho

### 6.1 Validação Estática (`.\tools\validate.ps1`)
- **Resultado:** **`PASSED`** (`0` erros, `0` avisos, **`209` scripts verificados**, `0` resíduos `.import`, `1032,36 s`).
- **Evidência:** `evidencias/R-03A/R1/validacao/validate_r03a_r1.txt`.

### 6.2 Regressão Integral Segmentada (`.\tools\run_tests.ps1 -Segmented -MaxIntegrationPerGroup 1`)
- **Resultado R1:** **`86/86` suítes** (`Discovered=86 | ExecutedUnique=86 | Duplicates=0 | Missing=0`) | **`617/617` testes PASS** | **`0` falhas** | **`0` SuiteErrors** | **`29.457` asserções** (`1289,92 s`).
- **Comparação com a candidata original (`4254011`):**
  - Suítes: `86` → `86` (`+0`)
  - Testes: `611` → `617` (`+6` novos testes dedicados R1: `F01`, `F02`, `T02`, `T03`, `T04`, `R01`)
  - Asserções: `29.179` → `29.457` (`+278` asserções: fortalecimento `T01` nos 19 testes `A01`–`A20` + 6 novos testes R1)
- **Evidência:** `evidencias/R-03A/R1/regressao/run_tests_full_r03a_r1.txt`.

### 6.3 Smoke Real e Verificação Visual (`1280×720` e `1920×1080`)
- `.\tools\run_game.ps1 -Resolution 1280x720 -QuitAfter 45 -FailOnWarnings`: **`EXIT=0`** (`0` erros/avisos).
- `.\tools\run_game.ps1 -Resolution 1920x1080 -QuitAfter 45 -FailOnWarnings`: **`EXIT=0`** (`0` erros/avisos).
- Capturas reais da Godot inspecionadas em `1280×720` e `1920×1080` (`evidencias/R-03A/R1/visual/`): ocioso, hover de construção com 14 fontes enumeradas e 5 de 6 árvores marcadas — zero sobreposição visual, HUD legada (`use_d2_2_hud = false`) preservada.

### 6.4 Medição Proporcional de Desempenho (`1920×1080`, `--disable-vsync`, Intel UHD Graphics 620)
*(Medição proporcional da R1 em tomada CA; não substitui o benchmark formal CA/DC completo de T2 registrado em `docs/KNOWN_ISSUES.md`.)*

| Cenário (`1920×1080`, sem VSync) | Original (`4254011`) `p95` | R1 `mean` | R1 `p95` | R1 `max` | R1 FPS médio | Meta CA (`<= 16,7 ms`) |
|---|---:|---:|---:|---:|---:|---|
| Ocioso (`120` quadros) | `13,167 ms` | `9,205 ms` | **`16,321 ms`** | `19,479 ms` | `108,64` | Atendida |
| Hover de construção com `14` fontes (`120` quadros) | *N/A* | `8,298 ms` | **`10,671 ms`** | `12,853 ms` | `120,51` | Atendida |
| 5 árvores marcadas + 2 trabalhadores ativos (`120` quadros) | `9,298 ms` | `9,074 ms` | **`13,824 ms`** | `31,074 ms` | `110,21` | Atendida |
| Pós-conclusão (`60` quadros, `active_tasks=0`, `orphan_rings=0`) | `9,395 ms` | `8,605 ms` | **`10,559 ms`** | `11,687 ms` | `116,21` | Atendida |

- **Avaliação direta do custo de F01 (`14` fontes no `PlacementValidator`):**
  - `validate_hover` (`14` fontes): `11,283 ms` (e frame time em hover contínuo `p95 = 10,671 ms`, `120,51 FPS`).
  - `validate_confirm` síncrono (com bake completo de malha candidata Recast): `137,341 ms` (em gameplay real, `PlacementController` executa `validate_confirm_async` em worker thread sem travar a thread principal).
- **Verificações estruturais:** `canonical=6`, `all_region=14`, `placement_ctx=14`, `board_proc=false`, `disp_proc=false`, `disp_phys=false`, `orphan_rings=0`.

---

## 7. Limitações, Preservação de Contratos e Pendências
- **Limitação observada em F01 (reprodução dinâmica):** a omissão de 8/14 fontes no `ValidationContext` e de 8/14 badges em `set_resource_discoverability_badges_visible()` foram reproduzidas diretamente em RED; já no cenário de alcova rasa fechada pela construção, o mecanismo `pre_corridor_probes` (`1,35 m`) do `PlacementValidator` já bloqueava a entrada mesmo antes da correção de F01 (com a correção R1, todas as 14 fontes passam a integrar formalmente `pre_source_groups` também para bolsas profundas ou casos onde o probe local cai fora da malha).
- **Contratos preservados:** `use_provenance_economy = true`, `automatic_cancellation_recovery = true`, `use_d2_2_hud = false`, `TestMap.get_resource_sources().size() == 6`, GDD `v1.3` intacto, D2.2 intacta, zero polling por frame, zero autoridades econômicas/de fontes paralelas.
- **Pendências obrigatórias antes da homologação:**
  1. Nova auditoria técnica independente do ChatGPT sobre o SHA final da R1 publicado em `origin/feat/r-03a-community-work-main-scene`;
  2. Execução dos testes humanos **`M1`–`M8`** pelo proprietário na Godot `4.7.2` (`C:\Projetos\Dawn_of_Kin_wt_r_03a`), conforme roteiro preservado em [R_03A_community_work_main_scene_candidate_report.md](R_03A_community_work_main_scene_candidate_report.md) §7;
  3. Homologação expressa do proprietário e autorização posterior para integração à `develop` e encerramento do worktree candidato.
