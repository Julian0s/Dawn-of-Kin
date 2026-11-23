# Dawn of Kin — Relatório de Implementação, VCG e Regressão: UI-1.2

## 1. Identificação e Escopo

| Campo | Valor verificado |
|---|---|
| Etapa | **UI-1.2 — Estelas dos Fundadores e Lâmina Contextual D2.2** |
| Branch candidata | `feat/ui-1-2-founder-steles-lineage` |
| Base homologada (UI-1.1B R1) | `fix/ui-1-1b-r1-pause-ownership` @ `a6542caea29d55fa07db0429e4aeb113b48135b3` |
| Commit técnico (código + testes + capturas VCG) | `a433e63cd8e43e08cc93f36a8366ba0fe9f011d2` |
| Worktree isolado | `C:\Projetos\Dawn_of_Kin_wt_ui_1_2` |
| Engine / Renderer verificados | Godot `v4.7.2.stable.official.ed1daf0bf` · `gl_compatibility` (OpenGL 3.3.0) |
| Hardware de captura GPU (VCG) | Intel(R) UHD Graphics 620 |
| Estado de publicação | Publicado na branch candidata; **sem merge**, **sem tags**, **sem início da UI-1.3** |
| Status de homologação | **Implementado, testado automaticamente e validado visualmente por capturas GPU (VCG)**; aguardando auditoria independente (ChatGPT), teste manual interativo e aceite do proprietário |

### Escopo autorizado executado
- Duas estelas independentes e escalonadas para os fundadores (`D2FounderStelesView`) com retratos aprovados (`portrait_alden.jpg` e `portrait_brena.jpg`) e fallback seguro de monograma para habitantes futuros.
- Seleção RTS bidirecional integrada ao `SelectionManager` (clique simples, `Shift+clique`, seleção 3D, seleção por caixa, `Esc` progressivo, seleção vazia e limpeza segura em remoção de unidade).
- Estados visuais reais de seleção (`founder_stele` em repouso vs. `founder_stele_raised` elevada `+22 px` com moldura dourada e selo `SELECIONADO`, além de microbarra de carga proporcional ao peso real).
- Hitboxes poligonais reutilizando `D2PolygonalSlab` e `D2SlabButton` com área transparente de `shadow_pad` pass-through, proteção da câmera/RMB/scroll e bloqueio de interação durante pausa (`PROCESS_MODE_PAUSABLE`).
- Lâmina contextual de unidade e linhagem (`D2LineageBladeView`) exibindo estritamente dados reais de trabalho, transporte e carga em seleção individual (`HudFormatter.build_carry_snapshot()` e `HudFormatter.format_unit_state()`), resumo honesto sem métricas inventadas em seleção múltipla, e ocultação completa em seleção vazia.
- Coexistência dual-mode preservada (`use_d2_2_hud = false` permanece padrão em `src/main/main.tscn`), ocultando e desconectando `ResourceHud` e `SelectedUnitPanel` no modo D2.2 sem duplicidade de listeners e sem alterar nenhum arquivo legado de UI.

---

## 2. Fontes Normativas Consultadas

1. **`Dawn_of_Kin_GDD_v1.0.md`** — preservação integral de marcadores DECIDIDO / PROPOSTA / ABERTO; nenhum dado especulativo de T5/T6/P-RUX-2 promovido a UI ativa.
2. **Design System Mestre D2.2 homologado** (`design/ui-0-r2-3-2-closeout` @ `cdd9f2f4308a05d822c8f7c72f57c0a07756f0a6`, `docs/design/DAWN_OF_KIN_VISUAL_DESIGN_SYSTEM.md`) — paleta, tipografia, anatomia das estelas e da lâmina contextual, geometria do atlas.
3. **Referência visual imutável D2.2** (`design/ui-0-r2-2-d2-visual-fidelity` @ `1ab8ffb78c269f3a659712491de91ab1f317e919`) — capturas `G_godot_D2_2_hud_1920x1080.png`, `G_godot_D2_2_lineage_1920x1080.png`, `G_godot_D2_2_lineage_1280x720.png` e script de referência `ui0_r2_2_d2_faithful_showcase.gd`.
4. **Plano técnico aprovado UI-1.0 R1** (`planning/ui-1-0-r1-integration-plan` @ `7dbfeb148f68f353bad71e1363db01eae7c41018`, `docs/architecture/UI_1_0_R1_INTEGRATION_PLAN.md`) — decisões técnicas **DT-01 a DT-06**, especialmente **DT-04** (preservação dos nomes canônicos nos `.tres` via `HudFormatter.format_unit_name()`).
5. **`AGENTS.md`** e código real de `SelectionManager`, `Unit`, `UnitCarryLoad`, `HudFormatter`, `ResourceHud`, `SelectedUnitPanel` e `D2HudRoot`.

---

## 3. Arquivos Criados, Modificados e Preservados

### Criados (código de produção e testes)
| Arquivo | Função |
|---|---|
| `src/ui/d2/components/d2_founder_steles_view.gd` (+ `.gd.uid`) | Estelas independentes dos fundadores com retratos, fallback de monograma, seleção bidirecional, `Shift+clique`, hitboxes poligonais e barra de carga real. |
| `src/ui/d2/components/d2_lineage_blade_view.gd` (+ `.gd.uid`) | Lâmina contextual D2.2 com modos `EMPTY` (oculta), `SINGLE` (carga/peso/recursos reais) e `MULTI` (resumo honesto de grupo). |
| `tests/unit/test_ui_1_2_steles_and_blade.gd` (+ `.gd.uid`) | Suíte unitária cobrindo geometria, DT-04, fallback de monograma, estados `EMPTY`/`SINGLE`/`MULTI`, sobrecarga real, polígonos e ausência de termos especulativos T5/T6. |
| `tests/integration/test_ui_1_2_selection_and_lineage.gd` (+ `.gd.uid`) | Suíte de integração em cena real (`use_provenance_economy = true`) cobrindo seleção bidirecional, clique/Shift/box/Esc, pausa, hitboxes, coleta/transporte real e modo legado intacto. |

### Modificados (4 arquivos estritamente no escopo UI-1.2)
| Arquivo | Alteração objetiva |
|---|---|
| `src/ui/d2/d2_tokens.gd` | Adição de `POLYGON_LINEAGE_BLADE` (extraído dos vértices alfa reais do atlas D2.2) e constantes canônicas de posicionamento das estelas e da lâmina contextual. |
| `src/ui/d2/d2_hud_root.gd` | Composição, layout responsivo (`1280×720` e `1920×1080`), vinculação retrocompatível (`configure(..., selection_manager = null, units = [])`), `unbind()`, `refresh_all()` e getters para `D2FounderStelesView` e `D2LineageBladeView`. |
| `src/main/main.gd` | No modo `use_d2_2_hud == true`: omite `_resource_hud.configure()`, executa `_resource_hud.unbind()`, oculta `_resource_hud` + `get_stockpile_panel()` + `get_selected_unit_panel()` e passa `_selection_manager` e `get_units()` para `_d2_hud_root.configure(...)`. Modo legado (`use_d2_2_hud == false`) inalterado. |
| `tests/integration/test_ui_1_1a_visual_data.gd` | Atualização cirúrgica da asserção provisória da UI-1.1A (agora valida ocultação e desconexão do `SelectedUnitPanel` legado e ativação da `D2LineageBladeView` no modo D2.2, mais não-sobreposição de layout com estelas e lâmina). |

### Evidências visuais (VCG) adicionadas em `docs/design/ui-1-2/`
- 10 capturas reais renderizadas em Godot 4.7.2 GPU (`1280×720` e `1920×1080`) + 2 pranchas comparativas diretas lado a lado com a referência D2.2 (`C_ui_1_2_compare_steles_hud.png` e `C_ui_1_2_compare_lineage_blade.png`).

### Arquivos protegidos verificados sem qualquer alteração (`git diff a6542ca` vazio)
- `src/main/main.tscn` (`use_d2_2_hud = false` preservado como padrão).
- Todos os 9 assets em `assets/ui/d2/*`.
- Todos os arquivos `data/characters/*.tres` (`leader_a.tres`, `leader_b.tres`).
- `src/ui/resource_hud.gd` e `src/ui/selected_unit_panel.gd`.
- `src/rts/selection_manager.gd`, `src/rts/rts_camera_rig.gd`, `src/units/unit.gd`, `src/units/unit_carry_load.gd`.
- `src/ui/d2/d2_simulation_pause_controller.gd` e `src/ui/d2/d2_ui_escape_router.gd`.
- `Dawn_of_Kin_GDD_v1.0.md` e `docs/design/DAWN_OF_KIN_VISUAL_DESIGN_SYSTEM.md`.

---

## 4. Arquitetura Técnica Implementada

### 4.1 `D2FounderStelesView` (Estelas dos Fundadores)
- **Geometria fiel D2.2:** cada estela utiliza `D2PolygonalSlab` com os recortes exatos do atlas `d2_2_faithful_atlas.png` (`founder_stele` `128×156` / `108×136` ativo em repouso; `founder_stele_raised` `128×174` / `108×154` ativo quando selecionada), posicionadas independentemente em `x0 = 20`, `x1 = 142` (`gap = 14 px`), segunda estela escalonada `+6 px` abaixo e elevação de `-22 px` quando selecionada.
- **Retratos e fallback:** mapeamento determinístico por `character_id` (`leader_a` → `assets/ui/d2/portrait_alden.jpg`, `leader_b` → `assets/ui/d2/portrait_brena.jpg`), com fallback automático de monograma (`??` / iniciais do nome formatado) caso uma unidade futura não possua retrato dedicado.
- **DT-04 preservada:** o nome exibido em cada estela provém diretamente de `HudFormatter.format_unit_name(unit)` (`Leader A` / `Leader B` conforme `.tres` atuais), sem sobrescrever `character_display_name`.
- **Interação poligonal e bloqueio de vazamento:** um controle interno `_SteleHitButton extends D2SlabButton` compartilha o polígono exato do `D2PolygonalSlab` (`shadow_pad = 10 px` pass-through para o mundo 3D). Cliques esquerdo, direito, do meio e scroll dentro do polígono são consumidos sem acionar ordens RTS nem zoom/pan da câmera. Em clique esquerdo: seleção simples chama `SelectionManager.select_single(unit)`; com `Shift` pressionado (`mb.shift_pressed or Input.is_key_pressed(KEY_SHIFT)`) chama `SelectionManager.toggle_unit(unit)`.
- **Pausa segura:** `process_mode = Node.PROCESS_MODE_PAUSABLE`; durante `SceneTree.paused == true`, o clique na estela não altera a seleção RTS nem vaza para o mundo.
- **Atualização orientada a eventos (zero polling):** escuta `SelectionManager.selection_changed`, `unit.state_changed`, `unit.carry_load.changed` e `unit.tree_exiting`, com desconexão limpa em `unbind()` / `_exit_tree()`.

### 4.2 `D2LineageBladeView` (Lâmina Contextual D2.2)
- **Geometria fiel D2.2:** utiliza `D2PolygonalSlab` com o recorte `lineage_blade` (`474×234` / `454×214` ativo, `shadow_pad = 10 px`) e polígono `POLYGON_LINEAGE_BLADE = [(0,6), (454,0), (445,214), (3,210)]`.
- **Posicionamento sem sobreposição:** ancorada em `x = (20 + 108 + 14 + 108 + 14) * s = 264 * s` (14 px à direita da segunda estela), mantendo **ambas as estelas dos fundadores 100% visíveis e clicáveis** simultaneamente em `1920×1080` e `1280×720`, sem conflito com `DebugOverlay` ou `ConstructionHud`.
- **Três modos estritamente honestos:**
  - `EMPTY` (0 unidades selecionadas): lâmina completamente oculta (`visible = false`), sem capturar entrada de mouse.
  - `SINGLE` (1 unidade selecionada): exibe nome real (`HudFormatter.format_unit_name()`), pílula de estado (`HudFormatter.format_unit_state()`), barra de carga física, percentual real, peso transportado (`current / capacity`), capacidade efetiva, destaque de sobrecarga quando `is_overloaded == true` e contadores reais de `Madeira`, `Pedra` e `Alimento` via `HudFormatter.build_carry_snapshot()`. Zero dados especulativos (sem genealogia T5, saúde/vigor, botões de liberação comunitária ou linhagem fictícia).
  - `MULTI` (2+ unidades selecionadas): exibe `N unidades selecionadas`, pílula `GRUPO`, lista real `• <Nome> — <Estado>` de cada unidade selecionada e instrução contextual para selecionar uma unidade individual caso deseje inspecionar carga e transporte. Não exibe carga individual nem inventa somas artificiais de grupo.
- **Zero polling:** atualiza exclusivamente via sinais (`selection_changed`, `state_changed`, `carry_load.changed`, `tree_exiting`) com deduplicação por chave de renderização (`_last_render_key`).

### 4.3 Coexistência Dual-Mode e Contrato de Seleção Bidirecional
- Quando `use_d2_2_hud == false` (padrão de produção em `src/main/main.tscn`), `D2HudRoot` não é instanciado e `ResourceHud` + `SelectedUnitPanel` operam exatamente como antes.
- Quando `use_d2_2_hud == true`, `main.gd` omite `_resource_hud.configure()`, chama `_resource_hud.unbind()` e oculta `_resource_hud`, `get_stockpile_panel()` e `get_selected_unit_panel()`, garantindo **zero HUD duplicada** e **zero listeners duplicados** em `SelectionManager` ou inventário.
- A tecla `Esc` continua roteada por `D2UiEscapeRouter` (UI-1.1B) → `SelectionManager.clear_selection()` → atualização instantânea das estelas (retorno ao repouso) e ocultação da `D2LineageBladeView`.

---

## 5. Validação Executada e Evidências Concretas

> **Distinção rigorosa (`AGENTS.md`):** os resultados abaixo separam validação estática, testes automatizados headless, capturas visuais reais em GPU (VCG) e verificação manual interativa humana (ainda pendente do proprietário).

### 5.1 Validação Estática (`.\tools\validate.ps1`)
- **Comando:** `.\tools\validate.ps1` (em `C:\Projetos\Dawn_of_Kin_wt_ui_1_2`)
- **Resultado:** `Validation PASSED (0 errors, 0 warnings, 203 scripts checked).` — Exit code `0`.

### 5.2 Suítes Específicas da UI-1.2 e Compatibilidade UI-1.1A / UI-1.1B
| Suíte | Escopo | Resultado | Asserções |
|---|---|---|---|
| `tests/unit/test_ui_1_2_steles_and_blade.gd` | Geometria D2.2, DT-04, retratos/fallback, `EMPTY`/`SINGLE`/`MULTI`, sobrecarga real, polígonos, ausência de textos especulativos T5/T6 | **2/2 PASS** | 102 |
| `tests/integration/test_ui_1_2_selection_and_lineage.gd` | Seleção bidirecional em `main.tscn` (`use_provenance_economy = true`), clique/Shift/box/Esc, pausa, hitboxes, coleta/transporte real, modo legado intacto | **3/3 PASS** | 85 |
| `tests/unit/test_ui_1_1a_foundation.gd` + `tests/integration/test_ui_1_1a_visual_data.gd` | Compatibilidade da fundação D2.2, dual-mode, não-sobreposição de layout | **8/8 PASS** | 100% |
| `tests/unit/test_ui_1_1b_polygon_and_pause.gd` + `tests/integration/test_ui_1_1b_hitboxes_and_pause.gd` | Hitboxes poligonais, propriedade de pausa, proteção da câmera, roteador `Esc` | **12/12 PASS** | 100% |

### 5.3 Regressão Segmentada Completa
- **Comando:** `.\tools\run_tests.ps1 -Segmented -MaxIntegrationPerGroup 1` (em `C:\Projetos\Dawn_of_Kin_wt_ui_1_2`)
- **Exit Code:** `0`
- **Lotes:** `59 / 59 PASS` (`unit` + `integration-01` a `integration-58`)
- **Suítes:** `83 / 83 PASS` (`Discovered=83 | ExecutedUnique=83 | Duplicates=0 | Missing=0`)
- **Testes:** `587 / 587 PASS` (`Failed=0 | SuiteErrors=0`)
- **Asserções:** `28.686`
- **Duração:** `SumGodotElapsed = 948.382,6 ms` | `TotalWallElapsed = 987.076,7 ms`

---

## 6. Visual Consistency Gate (VCG) — Capturas Reais em GPU (Godot 4.7.2)

Todas as capturas foram renderizadas diretamente no executável Godot 4.7.2 (`OpenGL 3.3.0 - Compatibility`, `Intel(R) UHD Graphics 620`) sobre a cena real `src/main/main.tscn` com `use_provenance_economy = true` (exit code `0`, zero erros).

### 6.1 Catálogo de Capturas e Pranchas Comparativas
| Arquivo (`docs/design/ui-1-2/`) | Resolução | Cenário verificado |
|---|---|---|
| `G_ui_1_2_none_1920x1080.png` | 1920×1080 | D2.2 sem seleção: estelas em repouso, lâmina oculta, zero HUD legada. |
| `G_ui_1_2_none_1280x720.png` | 1280×720 | D2.2 sem seleção em 720p: escala proporcional sem cortes ou sobreposição. |
| `G_ui_1_2_leader_a_1920x1080.png` | 1920×1080 | Leader A selecionado: estela esquerda elevada + `SELECIONADO`, anel 3D, lâmina `SINGLE`. |
| `G_ui_1_2_leader_a_1280x720.png` | 1280×720 | Leader A selecionado em 720p: legibilidade plena sem colisão com estela direita. |
| `G_ui_1_2_leader_b_1920x1080.png` | 1920×1080 | Leader B selecionado: estela direita elevada + `SELECIONADO`, anel 3D, lâmina `SINGLE`. |
| `G_ui_1_2_transport_active_1920x1080.png` | 1920×1080 | Coleta/transporte real: Leader A na árvore com `2 Madeira` (`4 / 20`, `20%`, `TRABALHANDO`), microbarra verde-oliva na estela e na lâmina. |
| `G_ui_1_2_transport_active_1280x720.png` | 1280×720 | Mesmo estado de transporte real validado em 720p. |
| `G_ui_1_2_multi_1920x1080.png` | 1920×1080 | Seleção múltipla: ambas estelas elevadas + anéis 3D + lâmina `MULTI` (`2 unidades selecionadas`, `GRUPO`, lista real). |
| `G_ui_1_2_multi_1280x720.png` | 1280×720 | Seleção múltipla validada em 720p. |
| `G_ui_1_2_legacy_intact_1280x720.png` | 1280×720 | Modo padrão (`use_d2_2_hud = false`): `ResourceHud` e `SelectedUnitPanel` legados 100% intactos. |
| `C_ui_1_2_compare_steles_hud.png` | 1620×824 | Prancha comparativa direta: `G_godot_D2_2_hud_1920x1080.png` vs. UI-1.2 real (repouso, individual, múltiplo). |
| `C_ui_1_2_compare_lineage_blade.png` | 1620×824 | Prancha comparativa direta: `G_godot_D2_2_lineage_1920x1080.png` vs. UI-1.2 real (transporte ativo, Leader B, múltiplo). |

### 6.2 Checklist VCG Inspecionado Visualmente
- [x] **Fidelidade ao Design System D2.2:** basalto escuro, filetes dourados, silhuetas trapezoidais assimétricas, retratos emoldurados, tipografia e glifos geométricos preservados sem alteração de assets.
- [x] **Duas estelas independentes e escalonadas:** espaçamento lateral, deslocamento vertical de `+6 px` na segunda estela e elevação de `+22 px` com destaque dourado e selo `SELECIONADO`.
- [x] **Honestidade funcional:** zero menções a T5/T6/P-RUX-2 (`Casa Fundadora`, `Pilha da Linhagem`, `1ª Geração`, `Liberar para Comunidade`, saúde/vigor fictícios).
- [x] **DT-04:** nomes exibidos fielmente como `Leader A` e `Leader B` (vindos dos `.tres` via `HudFormatter`).
- [x] **Legibilidade em `1280×720` e `1920×1080`:** alto contraste de texto, zero recorte, zero sobreposição entre estelas, lâmina, `DebugOverlay` e `ConstructionHud`.
- [x] **Zero HUD duplicada:** `SelectedUnitPanel` e `ResourceHud` legados ausentes no modo D2.2 e intactos no modo padrão (`use_d2_2_hud = false`).

---

## 7. Riscos, Limitações e Pendências (Classificação por Criticidade)

### Crítico (bloqueador de homologação)
- **Nenhum identificado** na análise estática, testes automatizados ou inspeção visual VCG.

### Moderado (pendente de validação humana)
- **Verificação manual interativa pelo proprietário não realizada por humano ainda:** testes automatizados e capturas GPU não substituem o teste tátil no editor/executável Godot (sensação de clique nas estelas, `Shift+clique`, seleção por caixa, cliques RMB/scroll sobre áreas opacas e transparentes da lâmina e das estelas, tecla `Esc` e pausa interativa).

### Baixo / Conhecido fora do escopo da UI-1.2
- **Botão legado `Construir` no canto inferior direito:** mantido provisoriamente conforme roadmap (substituição prevista para **UI-1.3**).
- **`DebugOverlay` (`[F3]`):** permanece como ferramenta técnica de diagnóstico fora da arte D2.2, com ancoragem sem colisão.
- **Nomes `Leader A` / `Leader B`:** refletem fielmente os recursos `.tres` atuais por força da **DT-04**; renomeação narrativa permanece fora do escopo da UI-1.2.
- **Estado pausado nas capturas `transport_active`:** o script de captura congelou a simulação (`tree.paused = true`) no instante em que `Leader A` coletou `2 Madeira` (`4 / 20`, `20%`) para registrar o quadro sem deriva temporal; por esse motivo o botão `||` no selo superior direito aparece corretamente destacado naquela captura específica.

---

## 8. Protocolo Curto de Verificação Manual pelo Proprietário

1. Abrir o projeto no worktree `C:\Projetos\Dawn_of_Kin_wt_ui_1_2` na Godot 4.7.2.
2. **Modo legado (padrão):** executar `src/main/main.tscn` com `use_d2_2_hud = false` e confirmar que `ResourceHud` e `SelectedUnitPanel` continuam idênticos.
3. **Modo D2.2:** alternar `use_d2_2_hud = true` temporariamente no inspetor (sem commitar) e executar `src/main/main.tscn`:
   - Confirmar duas estelas independentes no canto inferior esquerdo com os retratos de Alden (`Leader A`) e Brena (`Leader B`), sem lâmina visível inicialmente e sem painel legado duplicado.
   - Clicar na estela `Leader A`: confirmar elevação da estela, anel 3D em `Leader A` e abertura da lâmina contextual com `0%` / `0 / 20`.
   - Clicar com `Shift` na estela `Leader B`: confirmar ambas as estelas elevadas, anéis 3D em ambos e lâmina em modo `2 unidades selecionadas` (`GRUPO`).
   - Testar seleção direta no mundo 3D e por caixa de arraste: confirmar sincronização imediata das estelas e da lâmina.
   - Ordenar coleta em uma árvore com botão direito (fora da UI): acompanhar em tempo real atualização de estado (`Trabalhando` / `Transportando`), microbarra na estela, percentual, peso e contador `Madeira` na lâmina.
   - Testar clique direito e roda do mouse sobre a lâmina e as estelas: confirmar que não geram ordem RTS nem dão zoom na câmera.
   - Pausar no selo superior direito (`||`): confirmar que cliques nas estelas não alteram a seleção durante a pausa; despausar e pressionar `Esc` para limpar seleção e ocultar a lâmina.

---

## 9. Governança Git e Isolamento de Worktrees

- **Branch publicada:** `feat/ui-1-2-founder-steles-lineage` (base `a6542caea29d55fa07db0429e4aeb113b48135b3`).
- **Commit técnico:** `a433e63cd8e43e08cc93f36a8366ba0fe9f011d2`.
- **Workspace principal (`C:\Projetos\Dawn of Kin`) e worktrees anteriores (`ui-1-1a`, `ui-1-1b`, `ui-1-1b-r1`):** preservados intactos.
- **Merge e tags:** **não executados**, conforme autorização estrita da UI-1.2.
