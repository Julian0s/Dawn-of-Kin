# Dawn of Kin — Relatório Técnico da Candidata R-03A

**Incremento:** `R-03A` — Seleção Múltipla de Fontes e Trabalho Comunitário Automático na `MainScene`  
**Status na Taxonomia Obrigatória:** **`IMPLEMENTADO`** · **`VALIDADO TECNICAMENTE`** · **`PUBLICADO` (branch candidata)** · **`NÃO AUDITADO`** · **`NÃO HOMOLOGADO`** · **`NÃO INTEGRADO À DEVELOP`** · **Testes humanos `M1`–`M8` `PENDENTES`**  
**Data:** 24/11/2026  
**Branch candidata:** `feat/r-03a-community-work-main-scene`  
**Base canônica (`develop`):** `21c34ee645725a74f1fefac9db0309ec711ab5f2` (reorganização `R-02B` encerrada e homologada)  
**Linha estável (`main` preservada):** `25e0a20f1d6a2f10a9e059afe69759fbe263db4a`  
**Ambiente:** Godot `4.7.2.stable.official.ed1daf0bf`, GDScript tipado, `gl_compatibility`, `Jolt Physics`, Intel UHD Graphics 620 (`1280×720` e `1920×1080`)

---

## 1. Objetivo e Escopo Autorizado

Integrar na **`MainScene` real** (`res://src/main/main.tscn`, executável por `F5` / `.\tools\run_game.ps1`) a seleção múltipla homogênea de fontes naturais (`wood`, `stone`, `food`) e o trabalho comunitário automático, reutilizando integralmente os subsistemas econômicos e RTS existentes sem criar sistemas paralelos nem antecipar etapas futuras (`R-03B`–`R-03D`, `R-04A`–`R-04C`, `R-05B`, `T4`–`T8`).

### Fora de escopo (explicitamente preservado / bloqueado)
- `R-03B` (`ControlMode`, metadados da Casa Fundadora, retorno configurável pós-`MoveOrder` `D-05`);
- `R-03C` (atribuição manual opcional da Casa Fundadora `UX-1` / `D-03`/`D-10`);
- `R-03D` (lista flutuante de tarefas `D-11` na HUD);
- `R-04A`–`R-04C` (`D-01`/`D-02`, débito imediato, reembolso `R2 simples`, aposentadoria do fluxo `D2`/`D3`);
- `R-05B` (ativação de `use_d2_2_hud = true` na `MainScene` — preservado `use_d2_2_hud = false`);
- `JobSystem` / `T4`–`T8`.

---

## 2. Arquitetura Integrada e Sistemas Reutilizados

| Componente | Caminho | Papel na `MainScene` |
|---|---|---|
| Entrada unificada RTS + coleta comunitária | `res://src/rts/autonomous_gather_input.gd` | Substitui o script base em `Main/RtsInputController` (subclasse direta de `RtsInputController`), preservando seleção RTS no chão, clique/arraste em unidades, prioridade de `PlacementController`, `UI` blocking, `Esc` e ordens pessoais com botão direito |
| Quadro comunitário de tarefas | `res://src/rts/community_work_board.gd` | Nó `Main/CommunityWorkBoard`; registra tarefas homogêneas (`wood`/`stone`/`food`), valida domínio regional e `World3D`, gerencia anéis visuais sutis (`AutoGatherTaskRing_*`), idempotência e limpeza em `teardown()` |
| Distribuidor orientado a eventos | `res://src/rts/community_task_dispatcher.gd` | Nó `Main/CommunityTaskDispatcher`; reage a eventos do quadro, liberação de slots e conclusão/cancelamento de ordens com `set_process(false)` e `set_physics_processing(false)`, respeitando admissão econômica regional e economia de proveniência |
| Feedback visual leve | `res://src/ui/autonomous_gather_feedback.gd` | Nó `Main/UiLayer/AutonomousGatherFeedback`; faixa discreta centralizada no topo sem sobreposição com `DebugOverlay` ou `ResourceHud` |
| Matemática de seleção em caixa | `res://src/rts/selection_box_math.gd` | Filtra fontes apenas do mesmo `World3D` da câmera ativa |
| Orquestração da cena principal | `res://src/main/main.gd` e `res://src/main/main.tscn` | Configura o bosque/fontes jogáveis adicionais (`PlayableCommunitySources` sob `TestMap`, preservando `TestMap.get_resource_sources().size() == 6`), inicializa o trabalho comunitário somente após admissão econômica e executa `_teardown_community_work()` em `request_controlled_teardown()` e `_exit_tree()` |

### Preservação de contratos críticos da `MainScene`
- `use_provenance_economy = true` preservado em `src/main/main.tscn`.
- `automatic_cancellation_recovery = true` preservado (`P-REC-1`).
- `use_d2_2_hud = false` preservado (`D-ERR-1 B` até `R-05B`).
- Fontes adicionais da `MainScene` (`PlayableCommunitySources`: `WoodTree03`–`06`, `StoneRock03`–`04`, `FoodBush03`–`04`) são filhas de `TestMap` como irmãs de `TestMap/ResourceSources`, garantindo bake automático dos colisores sólidos em `WorldNavigation` e mantendo `TestMap.get_resource_sources()` com exatamente `6` fontes canônicas.
- Sandboxes herdados (`tests/visual/rux_1_auto_gather.tscn`, `rux_2a_auto_resources.tscn`, `rux_2b_multi_source_selection.tscn`) desduplicados para herdar os nós comunitários de `main.tscn` com `include_playable_community_grove = false`, mantendo seus contratos originais intactos; `tests/visual/ui_1_d2_2_sandbox.tscn` intacto.

---

## 3. Arquivos Alterados e Criados

### Código e cenas
- `src/main/main.tscn` — script de `RtsInputController` promovido para `autonomous_gather_input.gd`, adição de `CommunityWorkBoard`, `CommunityTaskDispatcher` e `UiLayer/AutonomousGatherFeedback`.
- `src/main/main.gd` — adição de `include_playable_community_grove`, `_setup_playable_community_grove()`, `_setup_community_work()`, `_teardown_community_work()`, getters públicos e integração segura com `request_controlled_teardown()` / `_exit_tree()`.
- `src/rts/autonomous_gather_input.gd` — `configure_community_work()`, `teardown_community_work()` e bloqueio honesto quando a admissão econômica regional falha.
- `src/rts/community_work_board.gd` — validação estrita de `region_id` e `World3D` (`region_mismatch`) e `teardown()` idempotente.
- `src/rts/community_task_dispatcher.gd` — guarda `_is_tearing_down`, recusa de despacho com admissão econômica inválida ou fonte fora do domínio regional e `teardown()` determinístico.
- `src/rts/selection_box_math.gd` — guarda de isolamento `World3D` em `is_source_in_box()`.
- `src/ui/autonomous_gather_feedback.gd` — reposicionamento horizontal centrado no topo (`_recenter_top()`) após `reset_size()`, eliminando sobreposição com `DebugOverlay`.
- `tests/visual/rux_1_auto_gather.tscn`, `tests/visual/rux_2a_auto_resources.tscn`, `tests/visual/rux_2b_multi_source_selection.tscn` — remoção de declarações duplicadas de nós herdados e `include_playable_community_grove = false`.

### Testes automatizados
- `tests/integration/test_r_03a_community_work_main_scene.gd` (+ `.uid`) — nova suíte dedicada com **19 testes (`A01`–`A20`) e 189 asserções** executando sobre a `MainScene` real (`res://src/main/main.tscn`).

### Documentação normativa
- `AGENTS.md`, `README.md`, `docs/ROADMAP_MESTRE.md`, `docs/architecture/R_02B_WORKSPACE_CONSOLIDATION_REPORT.md` — registro da homologação final de `R-02B.5` (`21c34ee`), encerramento de `R-02B` e status `CANDIDATA EM AUDITORIA` de `R-03A`.
- `docs/testing/R_03A_community_work_main_scene_candidate_report.md` — este relatório técnico versionado.

---

## 4. Evidência RED → GREEN e Validação Automatizada

1. **Fase RED (`test_r_03a_community_work_main_scene.gd` antes da integração na `MainScene`):**
   - `1` suíte | `19` testes | **`0` PASS / `19` FAIL** | `0` SuiteErrors | `63` asserções (falhas comportamentais puras pela ausência dos nós e fiação comunitária na `MainScene`).
2. **Fase GREEN (`test_r_03a_community_work_main_scene.gd` pós-integração):**
   - `1` suíte | `19` testes | **`19` PASS / `0` FAIL** | `0` SuiteErrors | **`189` asserções** (`41,22 s`).
3. **Validação estática (`.\tools\validate.ps1`):**
   - **`PASSED`** (`0` erros, `0` avisos, **`209` scripts verificados**, `0` resíduos `.import`, `559,03 s`).
4. **Regressão completa segmentada (`.\tools\run_tests.ps1 -Segmented -MaxIntegrationPerGroup 1`):**
   - **`86/86` suítes descobertas e executadas (`0` duplicadas, `0` faltantes)**
   - **`611/611` testes aprovados (`0` falhas, `0` SuiteErrors)**
   - **`29.179` asserções executadas** (`1027,27 s` wall clock)
   - Inclui compatibilidade integral de `T1`, `T2`, `T3.1`–`T3.6.2`, `UI-1.1A`–`UI-1.3 R1`, `UX-1`, `RUX-1`, `RUX-2A`, `RUX-2B` e `R-03A`.

---

## 5. Verificação Visual e Desempenho Proporcional (Intel UHD Graphics 620)

- **Smoke real (`.\tools\run_game.ps1 -QuitAfter 45 -FailOnWarnings`):**
  - `1280×720`: `EXIT=0` (`0` erros/avisos)
  - `1920×1080`: `EXIT=0` (`0` erros/avisos)
- **Capturas visuais inspecionadas (`1280×720` e `1920×1080`, ocioso e 5 de 6 árvores marcadas):**
  - Todas as categorias (`wood`, `stone`, `food`) claramente legíveis;
  - 5 de 6 árvores exibem anel comunitário verde-sálvia discreto e a 6ª árvore permanece sem marcação;
  - Faixa `AutonomousGatherFeedback` centralizada no topo sem sobrepor `DebugOverlay` ou `ResourceHud`;
  - HUD legada (`use_d2_2_hud = false`) preservada.
- **Medição proporcional sem VSync em `1920×1080` (`--disable-vsync`, Intel UHD Graphics 620):**
  - Ocioso (`120` quadros): `mean = 7,940 ms` | **`p95 = 13,167 ms`** | `max = 21,083 ms` | `125,95 FPS`
  - 5 árvores marcadas + 2 trabalhadores ativos (`120` quadros): `mean = 6,899 ms` | **`p95 = 9,298 ms`** | `max = 11,345 ms` | `144,95 FPS`
  - Pós-conclusão (`60` quadros): `mean = 6,963 ms` | **`p95 = 9,395 ms`** | `max = 11,118 ms` | `143,61 FPS`
  - Verificações estruturais: `active_tasks = 0`, `orphan_rings = 0`, `board.is_processing() = false`, `dispatcher.is_processing() = false`, `dispatcher.is_physics_processing() = false`.

*(Nota: benchmark formal completo CA vs DC com protocolo T2 completo não foi substituído por esta medição proporcional; mantém-se o registro oficial de limitações conhecidas em `docs/KNOWN_ISSUES.md`.)*

---

## 6. Limitações Transitórias Declaradas

1. **Sem `ControlMode` completo nem retorno temporizado pós-`MoveOrder` (`D-05`):** permanecem reservados para **`R-03B`**. Uma ordem pessoal interrompe a tarefa comunitária preservando a mochila e liberando a vaga, e o trabalhador só é reatribuído pelo evento de conclusão da ordem ou quando fica ocioso no fluxo atual.
2. **Sem atribuição manual opcional (`D-03`/`D-10`):** reservada para **`R-03C`**.
3. **Sem lista flutuante de tarefas (`D-11`) nem HUD D2.2 ativa por padrão:** reservados respectivamente para **`R-03D`** e **`R-05B`** (`use_d2_2_hud = false` mantido na `MainScene`).
4. **Fluxo antigo de construção (`D2`/`D3`) ainda ativo em transição (`P-REC-1`):** convivência validada em `A14`, com aposentadoria prevista apenas em **`R-04C`**.

---

## 7. Roteiro Obrigatório de Testes Humanos (`M1`–`M8` — **`PENDENTES`**)

Executar na Godot `4.7.2` abrindo a `MainScene` (`F5` ou `.\tools\run_game.ps1` a partir do worktree candidato `C:\Projetos\Dawn_of_Kin_wt_r_03a`):

- **`M1` — Abertura real da `MainScene` (`1280×720` e `1920×1080`):** confirmar inicialização sem erros/avisos, visibilidade das fontes (`6` árvores, `4` pedras, `4` arbustos), HUD legada intacta (`use_d2_2_hud = false`) e câmera RTS funcional.
- **`M2` — Clique simples em árvore, pedra e arbusto:** clicar em uma fonte de cada tipo (sem unidade selecionada ou com unidade selecionada), confirmar marcação visual discreta, deslocamento automático de trabalhador ocioso, extração, retorno físico ao acampamento e crédito no estoque apenas na entrega.
- **`M3` — `Shift + Clique` homogêneo e rejeição de mistura:** marcar múltiplas árvores com `Shift + Clique` (verificar idempotência ao repetir clique na mesma árvore); tentar adicionar pedra/arbusto com `Shift + Clique` e confirmar mensagem clara no topo sem corromper o grupo anterior.
- **`M4` — Caixa de seleção em 5 de 6 árvores:** iniciar arraste com botão esquerdo sobre uma árvore e envolver 5 das 6 árvores; confirmar que exatamente 5 são marcadas, os 2 trabalhadores coletam sequencialmente todas as 5 e a 6ª árvore permanece 100% intacta após a conclusão.
- **`M5` — Caixa de seleção mista (pedras e arbustos) e seleção RTS clássica no chão:** testar arraste começando em pedra (seleciona apenas pedras) e em arbusto (seleciona apenas arbustos); testar arraste começando no chão vazio atravessando árvores/unidades e confirmar seleção RTS clássica de unidades sem marcar fontes.
- **`M6` — Prioridade de ordem pessoal:** durante coleta comunitária ativa, selecionar um líder e dar ordem pessoal de movimento (botão direito); confirmar obediência imediata, preservação da carga já carregada na mochila e continuidade da coleta pelo outro trabalhador/re-despacho sem travar vagas.
- **`M7` — Coexistência com construção, `Esc` e UI:** abrir o botão `Construir`, confirmar que cliques de posicionamento não marcam fontes; cancelar arraste de seleção de fontes com `Esc` e confirmar que nada foi registrado; alternar `F3` (`DebugOverlay`) e confirmar ausência de sobreposição com o banner no topo.
- **`M8` — Conservação econômica e encerramento limpo:** observar o estoque no `ResourceHud` e as pilhas físicas no acampamento após múltiplos ciclos de madeira, pedra e alimento, e fechar o jogo sem erros no console.

---

## 8. Estado de Integração, Publicação e Próxima Etapa

- **Branch publicada para auditoria:** `origin/feat/r-03a-community-work-main-scene` (ancestralidade linear direta de `develop` @ `21c34ee`).
- **`develop`:** preservada intacta em `21c34ee645725a74f1fefac9db0309ec711ab5f2` (integração bloqueada até auditoria independente + testes humanos `M1`–`M8` + homologação expressa do proprietário).
- **`main`:** preservada intacta em `25e0a20f1d6a2f10a9e059afe69759fbe263db4a`.
- **Próxima etapa planejada (ainda NÃO autorizada / `BLOQUEADO`):** **`R-03B`** — Metadados mínimos da Casa Fundadora, máquina `ControlMode`, prioridade pessoal absoluta e retorno automático configurável pós-`MoveOrder` (`D-04`/`D-05`).
