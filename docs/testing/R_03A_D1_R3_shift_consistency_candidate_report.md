# R-03A D1 R3 (Corretiva) — Correção Cirúrgica da Interpretação de Shift, Consistência do Modo de Arraste e Complementação `R2-T01`

- **Data:** 25/11/2026
- **Incremento:** **`R-03A D1 R3 (Corretiva)`**
- **Status real:** **`IMPLEMENTADO`** · **`VALIDADO TECNICAMENTE`** · **`AUDITORIA INDEPENDENTE PENDENTE`** · **`RETESTE HUMANO POSTERIOR PENDENTE`** · **`R-03A NÃO HOMOLOGADA`** · **`NÃO INTEGRADO À DEVELOP`** · **`D2 NÃO AUTORIZADA`** · **`R-03B BLOQUEADA`**
- **Base imediata auditada:** `5824c3ea5471bab5dbcddfb7b63d00e859e47a76` (`R-03A D1 R2`, preservando [relatório D1 R2](R_03A_D1_R2_human_feedback_and_visual_fidelity_candidate_report.md))
- **Ancestralidade linear:** `21c34ee` (`develop`) → `f77e99e` (`R1.1`) → `a39f3b5` (`D0`) → `a56af98` (`D1`) → `9f5b307` (`D1 R1`) → `5824c3e` (`D1 R2`) → **`R-03A D1 R3 Corretiva`**
- **Branch candidata:** `feat/r-03a-community-work-main-scene`
- **Worktree utilizado:** `C:\Projetos\Dawn_of_Kin_wt_r_03a`
- **Flags preservadas em `src/main/main.tscn`:** `use_provenance_economy = true`, `automatic_cancellation_recovery = true`, `use_d2_2_hud = false`.

---

## 1. Autorização expressa e fundamentação

Após a investigação forense `D1 R3` sobre `5824c3e`, a revisão instrumental `R1` do observador externo e o novo relato comportamental do proprietário (descrevendo que, ao travar a desmarcação sem pressionar Shift, cliques em novas fontes passaram a **somar fontes aditivamente**, como se Shift estivesse preso), o proprietário autorizou exclusivamente:
1. **`C-03`:** correção cirúrgica da interpretação de `Shift` em `RtsInputController._is_shift_held(event)`.
2. **`C-02 focal`:** consistência do modo de arraste travado em `AutonomousGatherInput._handle_box_selection()` quanto ao estado de `Shift` na soltura (`R2-A01`).
3. **`R2-T01`:** complementação determinística da cobertura automatizada do marcador `BLOCKED_REAUTHORIZATION` em `tests/integration/test_r_03a_d1_selection_and_authorization.gd`.

Expressamente **adiados / não autorizados nesta revisão:** `C-01` (limpeza por clique em obstáculo), ampliação de `C-02` para extremos em fonte/obstáculo, `C-04` (colisores de `TreeSource`), `C-05` (âncora/borda RTS), `C-06` (pipeline `_input`), `D2` (cancelamento seletivo / botão `X`), `D3`, `D4`, `R-03B` e quaisquer alterações artísticas ou visuais.

---

## 2. Investigação forense, revisão instrumental `R1` e limites da evidência anterior

- Na captura humana `diag_r03a_d1_r3_20261125_111326_1920x1080.log`, foram observadas duas ocorrências de `Escape` com divergência persistente entre estado de evento/tecla e ação global (`f=3347..3352` por `112,2 ms` e `f=4100..4108` por `192,4 ms`): `ev_shift=false`, `key_shift=false`, `act_shift=true`.
- Os registros de detalhes de gestos e marcações `F9` dessa captura anterior não foram gravados (irrecuperáveis) porque a ferramenta diagnóstica original `diag_session_observer.gd` chamava métodos inexistentes em `_capture_state()`, gerando `331` erros em tempo de execução no `godot.log`, e filtrava eventos `echo=true`.
- A investigação experimental em Godot `4.7.2` provou que um evento `InputEventKey` de `KEY_SHIFT` com `pressed=true` e `echo=true` (com mapeamento `physical_keycode = 4194325` em `project.godot`) ativa `Input.is_action_pressed(&"selection_modifier") = true` enquanto mantém `Input.is_key_pressed(KEY_SHIFT) = false` e `Input.is_physical_key_pressed(KEY_SHIFT) = false`.
- **Diferenciação epistêmica obrigatória:** a inconsistência no código de `_is_shift_held()` foi **comprovada e corrigida**, e o mecanismo experimental `echo=true` foi **reproduzido e corrigido** em `RED/GREEN`. Entretanto, sem os traces originais perdidos dos cliques problemáticos da primeira sessão humana, trata-se de **causa humana provável fundamentada** — ainda **não confirmada definitivamente no humano** até a execução do reteste humano posterior na candidata corrigida.

---

## 3. Alterações de produção aplicadas (`git diff src/`)

### 3.1 `C-03` — `src/rts/rts_input_controller.gd` (`_is_shift_held`, `L348`–`L350`)
- **Antes:**
  ```gdscript
  static func _is_shift_held(event: InputEvent) -> bool:
  	if event is InputEventWithModifiers and (event as InputEventWithModifiers).shift_pressed:
  		return true
  	return Input.is_action_pressed(InputActions.SELECTION_MODIFIER) or Input.is_key_pressed(KEY_SHIFT)
  ```
- **Depois:**
  ```gdscript
  static func _is_shift_held(event: InputEvent) -> bool:
  	if event is InputEventWithModifiers:
  		return (event as InputEventWithModifiers).shift_pressed
  	return Input.is_action_pressed(InputActions.SELECTION_MODIFIER) or Input.is_key_pressed(KEY_SHIFT)
  ```
- **Justificativa:** todos os 3 chamadores existentes em `RtsInputController` (`L102` press `SELECT`, `L122` release `SELECT`, `L150` `MouseMotion` ao cruzar limiar) recebem eventos de entrada concretos. Quando `event is InputEventWithModifiers`, `(event as InputEventWithModifiers).shift_pressed` passa a ser autoritativo tanto para `true` quanto para `false`, impedindo que estado global dessincronizado (`act_shift=true` após `echo=true` ou `FOCUS_OUT`) contamine cliques e arrastes explícitos com `shift_pressed=false`, preservando o fallback global somente para eventos sem modificadores (ex.: `InputEventAction`).

### 3.2 `C-02 focal` — `src/rts/autonomous_gather_input.gd` (`_handle_box_selection`, `L364`–`L372`)
- **Antes:**
  ```gdscript
  	if not unit_shift and not shift_held and _selection_manager != null and _selection_manager.is_empty():
  ```
- **Depois:**
  ```gdscript
  	if active_mode == DragMode.UNIT_BOX_RTS and not unit_shift and _selection_manager != null and _selection_manager.is_empty():
  ```
- **Justificativa:** respeita o modo `DragMode.UNIT_BOX_RTS` já resolvido e travado ao cruzar o limiar (`D1 R1`), impedindo que pressionar `Shift` após o limiar e soltar com `shift_held=true` impeça a limpeza `R2-A01` em caixa RTS vazia sobre terreno livre (`GROUND`/`NONE`), mantendo intactas as barreiras contra obstáculos, fontes, unidades capturadas, canteiros e `SOURCE_BOX_ADD`.

---

## 4. Complementação `R2-T01` (`tests/integration/test_r_03a_d1_selection_and_authorization.gd`)

- **Lacuna corrigida:** em `test_r2_hv03_work_marker_lifecycle_pending_blocked_depletion_removal_and_picker`, a autorização simultânea de 3 tarefas (`wood`, `stone`, `food`) com apenas 2 líderes mantinha o 2º líder ocupado em `stone`, deixando `task_w` (`wood`) em `PENDING_WORKERS` (`state = 0`) ao final dos 2 overrides e pulando silenciosamente o bloco `if task_w.is_blocked_reauthorization():` (`29` asserções na base `5824c3e`).
- **Correção:** após validar o estado `PENDING_WORKERS` simultâneo e `WorldPicker` intacto, o teste encerra `r1` (`stone`) e `b1` (`food`) legitimamente por esgotamento (`extract()`), verifica a remoção de ambos os marcadores e então conduz `task_w` deterministicamente até `BLOCKED_REAUTHORIZATION` via 2 ordens pessoais reais, executando **asserções incondicionais** sobre estado ativo da tarefa, marcador único `"blocked"`, estado `"blocked_reauthorization"` na HUD e restauração via clique público na HUD (`43` asserções em `test_r2_hv03`). Adicionalmente, criado o teste isolado `test_r3_r2t01_blocked_marker_lifecycle_and_reauthorization_invariants` (`33` asserções) validando preservação estrita de `task_id`, `group_id`, ordens pessoais de ambos os líderes, zero duplicação de marcadores e invariância econômica integral.

---

## 5. Resultados `RED → GREEN`, janela nativa, regressão integral e smokes

- **RED genuíno sobre `5824c3e` (`src/` intacto):**
  - Suíte `test_r_03a_d1_selection_and_authorization.gd`: `25` testes (`22 PASS`, **`3 FAIL` / `14` falhas comportamentais**, `0` erros de script):
    - `test_r3_c03_01` (`6` falhas): sob divergência real induzida por `KEY_SHIFT(pressed=true, echo=true)` (`act_shift=true, key_shift=false, phys_shift=false`), clique no chão manteve 3 fontes (`0/3` anéis limpos, HUD visível) e clique em nova fonte (`r1`) somou `[wood_tree_01, wood_tree_02, stone_rock_01]` em vez de substituir por `[stone_rock_01]`.
    - `test_r3_c03_02` (`6` falhas): arraste sem Shift travou `DragMode.SOURCE_BOX_ADD` (`2`) em vez de `UNIT_BOX_RTS` (`1`), deixou de selecionar `LeaderA` e adicionou `wood_tree_01`.
    - `test_r3_c02_01` Cenário A (`2` falhas): arraste travado em `UNIT_BOX_RTS` seguido de Shift na soltura manteve 3 fontes selecionadas e HUD visível em terreno livre vazio.
  - Probe em janela nativa (`1280×720` e `1920×1080`, `DPI=192`, `thresh=12.00 px`, `edge_pan=true`): reproduziu em ambas as resoluções todos os 3 comportamentos (`after=["wood_tree_01", "wood_tree_02", "stone_rock_01"]`, clique no terreno preso em `3` fontes, `locked_mode=2`, `6_C02` preso em `4` fontes).
- **GREEN pós-correções:**
  - `test_r_03a_d1_selection_and_authorization.gd`: **`25/25 PASS` (`592` asserções, `0` falhas)** — cobrindo `C-03` (`echo=true`, verdade completa dos modificadores, seleção individual vs aditiva), `C-02 focal` Cenários `A`–`G` (§8.4), `R2-T01` determinístico e matriz de quantidades (`1, 2, 3, 6 wood, heterogênea, todas as 14 fontes` via cliques reais + economia).
  - Janela nativa `1280×720` e `1920×1080` (`Exit=0, Errors=0, Warnings=0`): clique em `stone_rock_01` retorna `[stone_rock_01]`, clique no terreno zera `[]`, arraste RTS trava `locked_mode=1` (`units=1, sources=[]`), `C-02` Cenário A zera `[]`.
- **Suítes focais (`11/11 PASS`, `0` falhas):** `test_source_selection_model` (`4/4`, `52`), `test_picking_selection` (`9/9`, `70`), `test_box_selection` (`7/7`, `58`), `test_commands` (`5/5`, `72`), `test_rux_1_autonomous_gather` (`7/7`, `87`), `test_rux_2a_auto_resources` (`10/10`, `166`), `test_rux_2b_multi_source_selection` (`14/14`, `116`), `test_r_03a_community_work_main_scene` (`28/28`, `964`), `test_r_03a_d1_selection_and_authorization` (`25/25`, `592`), `test_t3_6_2_c4_10_work_regional_authority` (`3/3`, `179`), `test_t3_6_2_c4_12_rts_provenance` (`5/5`, `119`).
- **Validação estática (`.\tools\validate.ps1`):** `PASSED` (`0` erros, `0` avisos, `213` scripts verificados, boot headless limpo, `DOCS_DESIGN_IMPORT_COUNT=0`).
- **Regressão integral segmentada (`.\tools\run_tests.ps1 -Segmented -MaxIntegrationPerGroup 1`):**
  - `88/88` suítes (`Discovered=88 | ExecutedUnique=88 | Duplicates=0 | Missing=0`), **`649/649` testes**, **`30.589` asserções**, `62/62` lotes, `0` falhas, `0` erros de suíte (`SEGMENTED_EXIT=0`).
  - Delta vs Base `R2` (`88` suítes, `644` testes, `30.447` asserções, `213` scripts, `62` lotes): `+5` testes deliberados (`R2-T01`, `C-03` ×2, `C-02` `A`–`G`, matriz §10) e `+149` asserções em `test_r_03a_d1_selection_and_authorization.gd` (`443 → 592`), com `-7` de variação física natural entre execuções segmentadas (`+142` líquido).
- **Smokes e integridade visual (`720p` e `1080p`):**
  - `run_game.ps1 -QuitAfter 60 -FailOnWarnings`: `1280×720` (`EXIT=0`) e `1920×1080` (`EXIT=0`).
  - Capturas inspecionadas (`hud_720p.png`, `hud_1080p.png`): lajes minerais D2.2, ícones independentes, anel único + selo octogonal preservados, zero botão `X`.
  - `PROTECTED_HASH_DIFF_COUNT=0` (hashes SHA-256 idênticos antes/depois para `project.godot`, `d2_2_faithful_atlas.png`, `atlas_manifest.json`, `ico_work_{chop,mine,harvest}.png`, `community_selection_actions_hud.gd`, `autonomous_gather_feedback.gd` e `tree_source.tscn`).
  - Medição pontual focal `1920×1080` (`VSync=OFF`, Intel UHD Graphics 620, 120f): `avg=9,912 ms | p50=9,185 ms | p95=15,001 ms | max=24,438 ms`. A pendência geral de desempenho `D4` permanece aberta.

---

## 6. Pendências preservadas fora do escopo e reteste humano obrigatório

- Mecanismos secundários **intencionalmente preservados fora do escopo** desta revisão: `C-01` (clique em obstáculo mantém fontes), `C-02` ampliada (extremos em fonte/obstáculo), `C-04` (cilindros do bosque leste), `C-05` (âncora única de unidade + `WM_MOUSE_EXIT`), `C-06` (consumo de `MouseMotion` em controles `STOP` e limiar `12 px` a `192 DPI`), e pendências de desempenho `D4`.
- **`H-F01` e `H-F02` aguardam reteste humano obrigatório** (`RH-R3-01` a `RH-R3-05`) no worktree `C:\Projetos\Dawn_of_Kin_wt_r_03a` após auditoria independente do ChatGPT sobre esta candidata.
