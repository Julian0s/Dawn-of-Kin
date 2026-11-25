# Dawn of Kin — Relatório Técnico da Candidata `R-03A D1`
## Seleção Independente de Recursos, Autorização Explícita pela HUD Contextual e Reautorização (`D1-A`, `D1-B`, `D1-C`)

**Data:** 24/11/2026  
**Etapa:** `R-03A D1` *(primeiro incremento executável da revisão de experiência `D0`–`D4` dentro da etapa `R-03A`)*  
**Branch candidata:** `feat/r-03a-community-work-main-scene`  
**Worktree candidato:** `C:\Projetos\Dawn_of_Kin_wt_r_03a`  
**Base imediata homologada documentalmente:** `R-03A D0` (`a39f3b5e5abdfcf43f69a1e9e6865fe4446a3b8b`, ancestral `R1.1` @ `f77e99e7ea2404120baafe7a16ca47e94236d922`)  
**Base canônica preservada (`develop`):** `21c34ee645725a74f1fefac9db0309ec711ab5f2` *(não alterada)*  
**Linha estável preservada (`main`):** `25e0a20f1d6a2f10a9e059afe69759fbe263db4a` *(não alterada)*  
**Status obrigatório:** **`IMPLEMENTADO`** · **`VALIDADO TECNICAMENTE`** · **`PENDENTE DE AUDITORIA INDEPENDENTE`** · **`PENDENTE DE TESTES HUMANOS`** · **`NÃO HOMOLOGADO`** · **`NÃO INTEGRADO À DEVELOP`**

> [!IMPORTANT]
> Este incremento **NÃO** está homologado, **NÃO** está integrado à `develop`/`main` e **NÃO** substitui nem encerra `D2` (`Parar`), `D3` (corte progressivo até derrubada de árvores) ou `D4` (homologação humana integral da `R-03A`). Os relatórios históricos [R1.1](R_03A_R1_1_focal_evidence_candidate_report.md), [R1](R_03A_R1_community_work_main_scene_candidate_report.md) e [original](R_03A_community_work_main_scene_candidate_report.md), o GDD `v1.3` ([Dawn_of_Kin_GDD.md](../Dawn_of_Kin_GDD.md)) e o atlas D2.2 homologado (`assets/ui/d2/d2_2_faithful_atlas.png` + `atlas_manifest.json`) foram integralmente preservados sem modificações.

---

## 1. Autorização, Homologação Documental de `D0` e Decisões Aplicadas

O proprietário homologou documentalmente **`R-03A D0`** (`a39f3b5e5abdfcf43f69a1e9e6865fe4446a3b8b`) e autorizou exclusivamente **`R-03A D1`** com três decisões vinculantes:

| Decisão | Determinação Aprovada | Atendimento na Candidata `R-03A D1` |
|---|---|---|
| **`D1-A`** | Criar 3 ícones específicos minimalistas (Machado, Picareta, Colheita) consistentes com o Design System D2.2, **sem modificar o atlas homologado**, exibindo apenas ícone + contagem na HUD contextual (sem botão `Parar` na `D1`). | Criados `assets/ui/d2/icons/ico_work_chop.png`, `ico_work_mine.png` e `ico_work_harvest.png` (`48×48` RGBA, paleta basalto/ouro kintsugi/prata-pedra/folha-fruto); `d2_2_faithful_atlas.png` e `atlas_manifest.json` intactos; `CommunitySelectionActionsHud.has_stop_button() == false`. |
| **`D1-B`** | Clique esquerdo sem `Shift` em fonte **não selecionada** seleciona somente aquela fonte (substituindo a seleção anterior de fontes); clique esquerdo sem `Shift` em fonte **já selecionada** desmarca somente aquela fonte, preservando as demais fontes selecionadas. | Implementado em `AutonomousGatherInput._handle_left_click()` delegando para `SourceSelectionModel.deselect_source()` vs `select_single()`; validado nos testes unitários (`test_01`) e de integração (`test_d1_05`). |
| **`D1-C`** | Permitir **reautorização explícita pela HUD** para tarefas em `BLOCKED_REAUTHORIZATION` das fontes selecionadas na categoria clicada, preservando ordens pessoais, guardas econômicos e identidade da tarefa, sem desbloqueio silencioso por eventos incidentais. | Implementado em `CommunityWorkBoard.reauthorize_gather_task(task)` + `AutonomousGatherInput.authorize_selected_category(resource_id)`; eventos incidentais (selecionar/desmarcar, caixa, trabalhador livre, novo trabalhador, sinal de inventário, refresh de HUD) nunca desbloqueiam `BLOCKED_REAUTHORIZATION` (`test_d1_09`). |

---

## 2. Arquitetura e Inventário de Arquivos (`R-03A D1`)

### 2.1 Separação de Responsabilidades (Zero Polling)

1. **`src/rts/source_selection_model.gd`** *(novo — `class_name SourceSelectionModel extends RefCounted`)*:
   - Modelo visual puro de fontes naturais selecionadas (`WeakRef` + limpeza automática via sinais `tree_exited` e `depleted`).
   - Totalmente desacoplado de `CommunityWorkBoard`, `CommunityTaskDispatcher`, `SelectionManager`, ordens e economia.
   - Suporta `select_single`, `deselect_source` (`D1-B`), `toggle_source`, `add_sources` (união heterogênea idempotente), `clear`, `teardown`, filtro regional (`region_checker`) e agrupamento por categoria (`wood`, `stone`, `food`).
2. **`src/rts/rts_input_controller.gd`** *(editado — +12 linhas de hooks virtuais)*:
   - Adicionados hooks virtuais limpos (`_on_left_press_started_with_shift`, `_on_drag_threshold_crossed`, `_on_clear_selection_requested`) preservando integralmente o contrato base de `RtsInputController`.
3. **`src/ui/selection_box_overlay.gd`** *(editado)*:
   - Adicionado `set_box_style(is_source_mode: bool)` / `is_source_mode()` diferenciando sutilmente a caixa de seleção de fontes (`Shift+arraste`, tom dourado-âmbar suave) da caixa RTS tradicional de unidades (verde-oliva), com reset automático em `clear_selection_box()`.
4. **`src/rts/community_work_board.gd`** *(editado — +21 linhas)*:
   - Adicionado `reauthorize_gather_task(task: WorkTask) -> Dictionary` (`D1-C`): valida atividade, estado `BLOCKED_REAUTHORIZATION`, usabilidade e domínio regional; limpa `excluded_unit_ids` **somente** nessa tarefa; retorna a `PENDING_WORKERS` e notifica o dispatcher via `task_updated` (mantendo 100% da arquitetura orientada a eventos sem polling).
5. **`src/rts/autonomous_gather_input.gd`** *(refatorado para o contrato único D1)*:
   - Possui e gerencia `_selection_model: SourceSelectionModel` e a máquina de gestos `enum DragMode { NONE, UNIT_BOX_RTS, SOURCE_BOX_ADD }`.
   - Trava `_drag_mode` uma única vez no cruzamento do limiar com base no `Shift` no início do gesto (evitando alternância imprevisível ao soltar/pressionar `Shift` no meio do arraste).
   - `Shift + arraste` a partir de **qualquer ponto jogável** (chão vazio, árvore, rocha, arbusto ou unidade) executa união heterogênea idempotente de fontes elegíveis na caixa sem tocar em `SelectionManager` nem fazer fallback para seleção de unidades (preservando `F02`).
   - Arraste **sem `Shift`** executa **sempre** seleção RTS tradicional de unidades (mesmo iniciado sobre uma fonte natural).
   - Mantém dois anéis concêntricos compartilhados (sem glow, sem nós órfãos):
     - Anel externo de seleção: `SourceSelectionRing_<sid>` (`r = 0,98..1,12`, `y = 0,06`, ouro-marfim D2.2).
     - Anel interno de tarefa autorizada: `AutoGatherTaskRing_<task_id>` (`r = 0,72..0,90`, `y = 0,05`, cor do recurso).
   - Expõe `authorize_selected_category(resource_id: StringName) -> Dictionary`: particiona fontes selecionadas da categoria em novas (`register_gather_group`), bloqueadas (`reauthorize_gather_task`) e já ativas (idempotente), preservando a seleção visual intacta e respeitando bloqueio de admissão econômica regional.
6. **`src/ui/community_selection_actions_hud.gd`** *(novo — `class_name CommunitySelectionActionsHud extends Control`)*:
   - Barra contextual minimalista D2.2 (basalto `#0E1013` + filete dourado `#DFBC72` + ícones independentes `22×22` + contagem numérica), ancorada no centro inferior (`offset_bottom = -16 px`, altura `48 px`, largura dinâmica `88 px` / `164 px` / `240 px` para 1/2/3 categorias).
   - Estritamente orientada a sinais (`selection_changed`, `task_registered`, `task_updated`, `task_closed`), com `set_process(false)` e `set_physics_process(false)`.
   - `MOUSE_FILTER_IGNORE` no container raiz full-rect e `MOUSE_FILTER_STOP` + `FOCUS_NONE` no painel e botões (anti-click-through total).
   - Estados visuais explícitos por categoria: `available`, `partial`, `authorized`, `blocked_reauthorization` (âmbar) e `economy_blocked` (desabilitado). Sem botão `Parar` na `D1`.
7. **`src/main/main.tscn` e `src/main/main.gd`** *(editados)*:
   - Composto `UiLayer/CommunitySelectionActionsHud` na `MainScene`, conectado em `_setup_community_work()` e desconectado em `_teardown_community_work()`; getters `get_source_selection_model()` e `get_community_selection_actions_hud()`.
   - Flags preservadas integralmente: `use_provenance_economy = true`, `automatic_cancellation_recovery = true`, `use_d2_2_hud = false`, `include_playable_community_grove = true`.
8. **Ícones minimalistas independentes (`D1-A`):**
   - `assets/ui/d2/icons/ico_work_chop.png` (+ `.import`)
   - `assets/ui/d2/icons/ico_work_mine.png` (+ `.import`)
   - `assets/ui/d2/icons/ico_work_harvest.png` (+ `.import`)

---

## 3. Evidência Comportamental RED → GREEN

- **RED genuíno (sobre `a39f3b5` sem alterações de produção):**
  - Arquivo: `tests/integration/test_r_03a_d1_selection_and_authorization.gd` (4 testes comportamentais iniciais usando APIs públicas existentes).
  - Resultado arquivado (`evidencias\R-03A\D1\red_green\d1_red_before.txt`): **`Suites: 1 | Tests: 4 | Passed: 0 | Failed: 4 | SuiteErrors: 0 | Assertions: 25 | Exit: 1`** (zero erros de compilação; todas as 4 falhas exclusivamente sobre o contrato antigo de clique-dispara-tarefa, arraste sem Shift sobre árvore, Shift+arraste selecionando unidades e rejeição mista).
- **GREEN após implementação D1:**
  - Mesmos 4 testes comportamentais passaram **`4/4` (`27` asserções, `0` erros/avisos)**.
  - Expansão completa de `test_r_03a_d1_selection_and_authorization.gd` para **`13/13` testes (`187` asserções, `0` falhas, `0` avisos)** + nova suíte unitária `tests/unit/test_source_selection_model.gd` (**`4/4` testes, `52` asserções, `0` falhas**).

---

## 4. Tabela de Reconciliação Transparente de Testes Existentes

Nenhuma asserção econômica, de proveniência, de conservação, de autoridade regional ou de ciclo de vida foi enfraquecida ou removida. Todas as adaptações decorrem exclusivamente da substituição deliberada do contrato de entrada aprovada em `R-03A D0` (`a39f3b5`):

| Suíte | Testes Adaptados | Motivo da Reconciliação (Contrato D0/D1) | Invariantes Preservadas 100% |
|---|---|---|---|
| `tests/integration/test_box_selection.gd` | `test_04_shift_box_adds_units_without_duplicates` | Na `MainScene` (`multi_source_enabled = true`), `Shift + arraste` foi canonicamente atribuído à adição de fontes naturais (validado em `test_d1_02` e `test_d1_06`). `test_04` desativa `multi_source_enabled = false` no controlador para preservar a regressão da classe base `RtsInputController`. | 7/7 testes (`58` asserções); `test_01`–`03`, `05`–`07` intocados. |
| `tests/integration/test_rux_1_autonomous_gather.gd` | `test_r1`–`test_r7` (helper `_select_and_authorize_wood` / `_click_hud_authorize`) | Seleção por clique agora é desacoplada da criação de tarefa; o fluxo D1 seleciona a árvore e clica no botão `[Machado]` da HUD. Idempotência (`test_r3`) validada sobre cliques repetidos de autorização na HUD. | 7/7 testes (`87` asserções); conservação, peso, proveniência, ordem manual, vaga e `SITE_RESERVED` intactos. |
| `tests/integration/test_rux_2a_auto_resources.gd` | `test_a1`–`test_a8` (helper `_select_and_authorize` / `_click_hud_authorize`) | Mesmo desacoplamento D1 (selecionar fonte → autorizar categoria na HUD) aplicado a madeira, pedra e alimento. | 10/10 testes (`166` asserções); `test_a9`/`a10`, peso por unidade, exclusão manual e conservação intactos. |
| `tests/integration/test_rux_2b_multi_source_selection.gd` | `test_b1`–`test_b5`, `test_b10`, `test_b11` | `Shift + arraste` substitui arraste sem `Shift` para caixa de fontes; `test_b2` reconciliado para seleção heterogênea (árvores + rocha) seguida de autorização isolada de madeira pela HUD (sem autorizar rocha); `test_b3` usa caixa com folga a partir de chão vazio (`5` de `6` árvores). | 14/14 testes (`116` asserções); `test_b6`–`b9`, `b12`–`b14`, continuidade, `worker_slot_released`, conservação e teardown intactos. |
| `tests/integration/test_r_03a_community_work_main_scene.gd` | `A02`–`A06`, `A16`, `A19`, `R1-F02`, `R1-T03`, `R1-T04`, `R1.1-R01`, `R1.1-T04` | Fluxo único D1 (`Shift+arraste` + clique no botão contextual da HUD); `A03` valida seleção mista + autorização homogênea por categoria; `A19`/`R1-T04`/`R1.1-T04` validam estado `STATE_ECONOMY_BLOCKED` na HUD + recusa honesta em `authorize_selected_category`; `R1-F02` valida invalidação de origem durante `Shift+arraste` sem fallback para unidades. | 28/28 testes (`785` asserções); `A01`, `A07`–`A15`, `A17`, `A18`, `A20`, `R1-F01`, `R1-R01`, `R1-T02`, `R1.1-T02`, `R1.1-R01`, `R1.1-T04` (invariância de proveniência e storage) 100% preservados. |

---

## 5. Resultados de Validação Técnica e Regressão Integral

| Verificação | Comando / Critério | Resultado Verificado | Delta vs `R1.1` (`f77e99e`) |
|---|---|---|---|
| **Validação estática** | `.\tools\validate.ps1` | **PASS** — `0` erros, `0` avisos, **`213`** scripts verificados, boot headless limpo, `DOCS_DESIGN_IMPORT_COUNT = 0` | `+4` scripts (`209 → 213`) |
| **Suítes focais (7 suítes)** | `source_selection_model`, `d1`, `box_selection`, `rux_1`, `rux_2a`, `rux_2b`, `r_03a_main_scene` | **PASS** — `83/83` testes, `1.451` asserções, `0` falhas, `0` avisos | `+17` testes novos D1 (`4` unit + `13` int) |
| **Regressão segmentada integral** | `.\tools\run_tests.ps1 -Segmented -MaxIntegrationPerGroup 1` | **PASS** — `62/62` lotes, **`88/88` suítes**, **`637/637` testes**, **`30.001` asserções**, `0` falhas, `0` `SuiteErrors`, `Discovered=88 == ExecutedUnique=88`, `Duplicates=0`, `Missing=0`, exit `0` | `+2` suítes (`86 → 88`), `+17` testes (`620 → 637`), **`+245` asserções (`29.756 → 30.001`)** *(errata `DOC01`: substitui `+285` / `29.716` grafados incorretamente na versão `a56af98`)* |
| **Smoke real `MainScene`** | `.\tools\run_game.ps1 -Resolution 1280x720 / 1920x1080 -QuitAfter 45 -FailOnWarnings` | **PASS** — `SMOKE_720P = 0`, `SMOKE_1080P = 0` (OpenGL 3.3 Compatibility, Intel UHD Graphics 620) | Mantido `0`/`0` |

---

## 6. Inspeção Visual Real (`1280×720` e `1920×1080`) e Desempenho Proporcional

### 6.1 Evidências Visuais Reais (Inspecionadas Diretamente)

Foram capturados e inspecionados diretamente `14` screenshots reais renderizados na GPU (7 estados em `1280×720` + 7 estados em `1920×1080`, arquivados em `C:\Projetos\Backups\Dawn_of_Kin_Archive_Local\evidencias\R-03A\D1\visual\`):
- Seleção vazia (`01`): HUD contextual oculta, zero poluição visual.
- Seleção individual (`02`) e 5 de 6 árvores (`03`): apenas anel externo dourado nas fontes selecionadas; 6ª árvore sem anel; HUD exibe apenas `[Machado 1]` / `[Machado 5]`.
- Coexistência mista 3 categorias + unidade selecionada (`04`): `[Machado 5] [Picareta 2] [Colheita 1]` centralizada na base, coexistindo com `SelectedUnitPanel` (canto inferior esquerdo), `ConstructionHud` (canto inferior direito), `SettlementStockpilePanel` (canto superior direito) e `DebugOverlay` (canto superior esquerdo) com **zero sobreposição** em `720p` e `1080p` (validado também geometricamente em `test_d1_12`).
- Autorização seletiva de madeira mantendo seleção (`05`): árvores autorizadas exibem **ambos os anéis concêntricos** (verde interno + dourado externo); botão de madeira assume tom verde-floresta autorizado; pedra e alimento mantêm estado disponível.
- Desmarcação com tarefas ativas (`06`): HUD oculta; anéis externos somem; anéis verdes de tarefa permanecem somente nas 5 árvores autorizadas.
- Reautorização bloqueada + `DebugOverlay` (`07`): botão de madeira assume tom âmbar (`blocked_reauthorization`) com banner `"Tarefa aguardando nova autorização."` e sem sobreposição.

### 6.2 Desempenho Proporcional (`1920×1080`, `--disable-vsync`, Intel UHD Graphics 620, CA)

Hardware/energia verificados: **Intel(R) UHD Graphics 620** (OpenGL 3.3 Compatibility), **`BatteryStatus=2` (`100%`, tomada CA)**.  
Zero polling confirmado em runtime: `board_proc=false`, `board_phys=false`, `disp_proc=false`, `disp_phys=false`, `hud_proc=false`, `hud_phys=false`.

| Fase (`240` quadros em regime permanente, após warmup de 90 quadros) | Média (`ms`) | `p50` (`ms`) | `p95` (`ms`) | `p99` (`ms`) | Máx (`ms`) | FPS Médio | Meta CA (`p95 <= 16,7 ms`) |
|---|---:|---:|---:|---:|---:|---:|---|
| **P1 — Idle baseline (`MainScene`)** | `6,655` | `6,474` | **`8,556`** | `9,530` | `10,404` | `150,3` | **ATENDIDO** |
| **P2 — Seleção mista + atualizações de HUD (3 categorias)** | `6,880` | `6,840` | **`9,112`** | `11,259` | `19,935` | `145,3` | **ATENDIDO** |
| **P3 — Trabalho comunitário ativo (madeira+pedra) + hover 14 fontes** | `7,804` | `7,497` | **`11,578`** | `15,021` | `16,345` | `128,1` | **ATENDIDO** |

> [!NOTE]
> Na primeira execução a frio (sem pré-aquecimento do shader de anel no OpenGL 3.3 Compatibility, arquivada integralmente em `perf_r03a_d1_1080p.txt`), registrou-se o pico esperado de primeira compilação do material de anel (`P2 max = 72,630 ms`, `p95 = 22,710 ms`, caindo para `P3 p95 = 16,131 ms` ainda na mesma execução). Em regime permanente (`perf_r03a_d1_1080p_steady.txt`), todas as fases permanecem confortavelmente abaixo de `11,6 ms` no `p95`.

---

## 7. Itens Não-Escopo e Pendências Preservadas para `D2`–`D4` *(atualizado pela Errata `D1 R1 / DOC01`)*

- **`D0-A02` (Aberto para `D2`):** Cancelamento comunitário definitivo via ação contextual `[Parar]` na HUD (explicitamente ausente na `D1`), garantindo que uma ordem existente não continue extraindo após o encerramento da autorização, preservando carga e ordem pessoal e sem retorno indevido à fonte cancelada.
- **`D0-A03` (Aberto para `D3`):** Fronteira irreversível da derrubada no corte progressivo de árvores (decisão entre irreversibilidade no início da queda vs confirmação definitiva a ser submetida ao proprietário em `D3`).
- **`D0-A04` (Aberto para `D3`):** Conservação econômica do novo ciclo de corte (utilizando balanço regional completo ou rastreabilidade individual efetivamente comprovada, considerando materiais fora do armazenamento válido e evitando dupla contagem das pilhas já integrantes do estoque — sem comparar a quantidade inicial de uma única árvore com todo o estoque comunitário).
- **`D4` (não substitui `D0-A04`):** Auditoria consolidada, regressão final, desempenho (incluindo avaliação do comportamento a frio), smokes e novo protocolo humano completo `M1`–`M8`, com preparação para homologação/integração final de `R-03A` à `develop`.
- **Testes humanos da `D1`:** `NÃO REALIZADOS` (aguardam auditoria independente e execução humana opcional/orientada pelo proprietário).
- **Flags e invariantes preservados:** `use_d2_2_hud = false` mantido até `R-05B`; `docs/Dawn_of_Kin_GDD.md` (`v1.3`) intocado; `assets/ui/d2/d2_2_faithful_atlas.png` e `atlas_manifest.json` intocados; `develop`, `main`, tags e checkout permanente `C:\Projetos\Dawn of Kin` intocados.

---

## 8. Errata Rastreável (`R-03A D1 R1` — `DOC01`)

Na revisão corretiva focal **`R-03A D1 R1`** (ver relatório completo em [R_03A_D1_R1_focal_correction_candidate_report.md](R_03A_D1_R1_focal_correction_candidate_report.md)), foram corrigidas duas inconsistências editoriais identificadas na auditoria independente sobre o commit `a56af98`:
1. **Contagem de asserções `R1.1 → D1`:** o valor correto da `R1.1` (`f77e99e`) é **`29.756`** (e não `29.716`), resultando no delta correto de **`+245` asserções** (`29.756 → 30.001`), e não `+285`.
2. **Destinação das ressalvas `D0`:** `D0-A02` pertence à **`D2`**, `D0-A03` e **`D0-A04`** pertencem à **`D3`**, enquanto **`D4`** permanece reservada à auditoria consolidada, regressão final, desempenho, smokes e protocolo humano `M1`–`M8` (não substituindo `D0-A04`).
3. **Observação sobre desempenho a frio (`§6.2`):** a atribuição do pico a frio (`max = 72,630 ms`, `p95 = 22,710 ms` em `P2`) à primeira compilação de shader permanece como hipótese observacional de `D1`, sujeita a avaliação consolidada na `D4` (não como comprovação independente encerrada).
