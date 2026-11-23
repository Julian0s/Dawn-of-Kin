# Dawn of Kin — Relatório de Implementação, VCG e Regressão: UI-1.3

## 1. Identificação, Ancestralidade Git e Escopo

| Campo | Valor verificado |
|---|---|
| Etapa | **UI-1.3 — Lajes de Comando, Mesa de Maquetes e Faixa de Validação de Posicionamento** |
| Branch candidata | `feat/ui-1-3-d2-construction-dock` |
| Base homologada (UI-1.2) | `feat/ui-1-2-founder-steles-lineage` @ `9f84d335cc2eecd3ea04765d4c0dde4672112304` |
| Commit técnico 1 (produção) | `d6d45fa8fa43d1bebc4193ad58a14d631d670307` |
| Commit técnico 2 (testes + capturas VCG) | `b5a8d51a15432b26d6c38183f494a29314d9938b` |
| Worktree isolado | `C:\Projetos\Dawn_of_Kin_wt_ui_1_3` |
| Engine / Renderer verificados | Godot `v4.7.2.stable.official.ed1daf0bf` · `gl_compatibility` (OpenGL 3.3.0) |
| Hardware de captura GPU (VCG) | Intel(R) UHD Graphics 620 |
| Governança Git | **Sem merge**, **sem tag**, **sem UI-1.4**, `use_d2_2_hud = false` preservado em `src/main/main.tscn` |
| Status de validação | **Implementado, testado automaticamente (regressão integral 85/85) e auditado visualmente por capturas GPU reais (VCG)**; aguardando auditoria independente (ChatGPT), teste manual interativo humano e homologação do proprietário |

### Escopo entregue na UI-1.3
1. **`D2ActionSlabsView`:** Lajes inferiores direitas fiéis à D2.2 — laje clara em alabastro `slab_maquetes_alab` (`Maquetes / Construir [B]`, funcional com elevação ativa `-6 px`) e laje escura em basalto `slab_cmd_basalt` (`Tarefas [T]` e `Linhagem [H]`, visualmente preservadas porém honestamente desabilitadas/inertes).
2. **`D2ConstructionDockView`:** Mesa vertical de maquetes em alabastro reutilizando `maquette_shelter` (repouso) e `maquette_depot_sel` (selecionada/em posição elevada `-14 px` com selo `● EM POSIÇÃO`), ilustrações `d1_shelter_mini.png` e `d1_depot_mini.png`, leitura dinâmica direta de `BuildingDefinition` (nomes, dimensões, esforço, custos `12 Mad · 6 Ped` e `18 Mad · 10 Ped`, sem duplicação hardcoded e sem prometer proteção T3.7 ainda inexistente), atalhos `[B]` e `[1]`/`[2]` restritos ao contexto de construção.
3. **`D2PlacementStatusBar`:** Faixa de validação usando `build_valid_bar` conectada aos sinais e resultados reais de `PlacementController` e `PlacementValidator`, distinguindo estritamente `HIDDEN`, `UNEVALUATED`, `VALID`, `INVALID` (com `reason_text`/`reason_code` reais) e `CONFIRMING` (`is_confirm_pending()`), jamais fabricando `LOCAL VÁLIDO` quando ausente, obsoleto ou em confirmação assíncrona.
4. **Roteamento determinístico de `Esc`:** Ativação exclusiva de `PRIORITY_MAQUETTES = 30` e `PRIORITY_PLACEMENT = 40` em `D2UiEscapeRouter` (sem fallback de Menu Principal da UI-1.5), com ordem de entrega validada via `Viewport.push_input(InputEventKey)`, proteção durante pausa e pass-through preservado para `RtsInputController`.
5. **Coexistência limpa e modo legado preservado:** Em `use_d2_2_hud = true`, o catálogo legado `ConstructionHud` não é instanciado e o banner duplicado de `PlacementTestOverlay` é suprimido (mantendo `F8`/`F6`/`F7` e `BuildingInspectorPanel` intactos até UI-1.4). Em `use_d2_2_hud = false` (padrão de `main.tscn`), 100% do legado permanece inalterado.

---

## 2. Arquivos Criados, Modificados e Preservados

### Arquivos criados
| Arquivo | Finalidade |
|---|---|
| `src/ui/d2/components/d2_action_slabs_view.gd` (+ `.gd.uid`) | Lajes inferiores direitas D2.2 (`slab_maquetes_alab` interativa + `slab_cmd_basalt` inerte). |
| `src/ui/d2/components/d2_construction_dock_view.gd` (+ `.gd.uid`) | Mesa vertical de maquetes em alabastro dirigida por `Array[BuildingDefinition]` e atalhos `[B]`/`[1]`/`[2]`. |
| `src/ui/d2/components/d2_placement_status_bar.gd` (+ `.gd.uid`) | Faixa poligonal de validação de posicionamento (`HIDDEN`/`UNEVALUATED`/`VALID`/`INVALID`/`CONFIRMING`). |
| `tests/unit/test_ui_1_3_construction_views.gd` (+ `.gd.uid`) | Testes unitários de atlas, polígonos, custos dinâmicos, honestidade T3.7, estados da faixa e `unbind()`. |
| `tests/integration/test_ui_1_3_construction_flow.gd` (+ `.gd.uid`) | Testes de integração em `MainScene` (`use_provenance_economy = true`): cliques reais, `[B]`/`[1]`/`[2]`, `Esc` via `Viewport`, pausa, click-through, resize `720p↔1080p`, confirmação assíncrona, prevenção de duplo commit, economia real e modo legado intacto. |
| `docs/design/ui-1-3/*` (14 PNGs GPU + 3 pranchas comparativas) | Evidências reais do Visual Consistency Gate (VCG) em `1280×720` e `1920×1080`. |

### Arquivos modificados (7 arquivos estritamente no escopo UI-1.3)
| Arquivo | Alteração cirúrgica |
|---|---|
| `src/ui/d2/d2_tokens.gd` | Adição dos polígonos exatos do atlas (`POLYGON_MAQUETTE_SHELTER`, `POLYGON_MAQUETTE_DEPOT_SEL`, `POLYGON_BUILD_VALID_BAR`) e constantes dimensionais da UI-1.3. |
| `src/ui/d2/d2_hud_root.gd` | Composição, layout responsivo, vinculação (`configure`/`unbind`/`refresh_all`) dos 3 novos views e registro exclusivo de `PRIORITY_MAQUETTES (30)` e `PRIORITY_PLACEMENT (40)` em `D2UiEscapeRouter`. |
| `src/buildings/placement_controller.gd` | Adição estritamente observacional de `signal confirm_pending_changed(pending: bool)` emitido apenas em transições reais de `_confirm_in_flight`, permitindo UI 100% dirigida por sinais sem polling e sem alterar qualquer regra de validação ou economia. |
| `src/buildings/placement_test_overlay.gd` | Adição retrocompatível de `set_placement_status_banner_suppressed(bool)` (padrão `false`), ocultando o banner legado `_status_panel` durante posicionamento no modo D2.2 sem afetar `F8`/`F6`/`F7` nem o modo legado. |
| `src/main/main.gd` | Em `use_d2_2_hud == true`: omite instanciação de `ConstructionHud`, suprime banner de `PlacementTestOverlay`, e passa `_placement_controller` + `[SHELTER_BASIC_DEFINITION, STORAGE_DEPOT_DEFINITION]` para `D2HudRoot.configure()`. |
| `tests/integration/test_ui_1_1a_visual_data.gd` | Atualização da asserção transitória da UI-1.1A (confirma ausência de `ConstructionHud` duplicado e presença de `D2ActionSlabsView`/`D2ConstructionDockView`/`D2PlacementStatusBar` no modo D2.2). |
| `tests/integration/test_ui_1_1b_hitboxes_and_pause.gd` | Atualização da asserção transitória de `test_05` para validar os 2 handlers ativos da UI-1.3 (`PRIORITY_MAQUETTES` e `PRIORITY_PLACEMENT`) no modo D2.2 mantendo 100% do contrato de `Esc` e modo legado. |

### Arquivos protegidos verificados sem alteração (`git diff 9f84d33` vazio)
- `src/main/main.tscn` (`use_d2_2_hud = false` preservado como padrão).
- Todos os 9 assets em `assets/ui/d2/*`.
- `data/buildings/shelter_basic.tres`, `data/buildings/storage_depot.tres`, `data/characters/*.tres`.
- `docs/Dawn_of_Kin_GDD.md`, `docs/design/DAWN_OF_KIN_VISUAL_DESIGN_SYSTEM.md`.
- `src/camera/rts_camera_rig.gd`, `src/rts/rts_input_controller.gd`, `src/rts/selection_manager.gd`.
- `src/ui/resource_hud.gd`, `src/ui/selected_unit_panel.gd`, `src/ui/construction_hud.gd`, `src/ui/building_inspector_panel.gd`.
- `src/ui/d2/components/d2_founder_steles_view.gd`, `src/ui/d2/components/d2_lineage_blade_view.gd`.

---

## 3. Decisões Técnicas e Contrato de Interação

1. **Ordem de entrega real de `Esc` no `Viewport`:** Em `MainScene`, `UiLayer` é filho posterior a `RtsInputController`, e `D2HudRoot` é o último filho de `UiLayer`. Como Godot despacha `_unhandled_input()` em ordem inversa da árvore, `D2UiEscapeRouter` recebe `KEY_ESCAPE` **antes** de `RtsInputController`. Sem `ConstructionHud` instanciado em modo D2.2, zero consumidores concorrentes interferem:
   - Mesa aberta (com ou sem placement) → `PRIORITY_MAQUETTES (30)` fecha **apenas** a mesa e consome o evento.
   - Placement ativo (mesa fechada) → `PRIORITY_PLACEMENT (40)` chama `PlacementController.cancel_placement()` e consome o evento (sem reabrir mesa nem limpar seleção).
   - Sem mesa e sem placement → pass-through para `RtsInputController` (cancela drag ou limpa seleção RTS).
   - Pausa ativa (`get_tree().paused == true`) → ambos os handlers retornam `false`, impedindo ações de construção ou despausa indevida via `Esc`.
2. **Estado determinístico da mesa:** Ao selecionar uma maquete (clique ou `[1]`/`[2]`), `PlacementController.start_placement()` inicia a prévia 3D e a mesa fecha automaticamente para liberar o campo visual inferior direito; o jogador pode reabrir a mesa a qualquer momento via `[B]` ou clique em `Maquetes` (visualizando a maquete ativa erguida com `● EM POSIÇÃO`) para trocar de estrutura sem perder o fluxo. Cancelamento ou confirmação nunca reabre a mesa inesperadamente.
3. **Sem conflito de atalhos:** Auditoria em `project.godot` e `src/**/*.gd` confirmou ausência de conflitos para `[B]`, `[1]` e `[2]`. `[1]`/`[2]` só operam dentro do contexto de construção (mesa aberta ou placement ativo) e são ignorados durante pausa ou com modificadores (`Ctrl`/`Alt`/`Meta`).
4. **Proveniência e conservação econômica preservadas:** A UI delega exclusivamente a `PlacementController.start_placement()`; a confirmação continua passando por `PlacementValidator.validate_confirm_async()` → `PlacementController.placement_confirmed` → `MainScene._on_placement_confirmed()` → `ConstructionManager.try_create_site_from_placement()`. Nenhuma ação da UI cria canteiros diretamente ou muta estoque/reservas.

---

## 4. Resultados Exatos dos Testes e Validação

> **Separação rigorosa (`AGENTS.md`):** distinguem-se abaixo validação estática, testes automatizados headless, capturas GPU reais (VCG) e teste manual interativo humano (ainda pendente do proprietário).

### 4.1 Validação Estática (`.\tools\validate.ps1`)
- **Comando:** `.\tools\validate.ps1` (em `C:\Projetos\Dawn_of_Kin_wt_ui_1_3`)
- **Resultado:** `Validation PASSED (0 errors, 0 warnings, 208 scripts checked).` — Exit code `0`.

### 4.2 Suítes Específicas da UI-1.3 e Compatibilidade Direta
| Suíte | Escopo | Resultado | Asserções |
|---|---|---|---|
| `tests/unit/test_ui_1_3_construction_views.gd` | Atlas, polígonos, custos dinâmicos, honestidade T3.7, estados da faixa, `unbind()`, bounds `720p`/`1080p` | **2/2 PASS** | 99 |
| `tests/integration/test_ui_1_3_construction_flow.gd` | Cliques reais, `[B]`/`[1]`/`[2]`, `Esc` real no `Viewport`, pausa, click-through, shadow pad, resize `720p↔1080p`, revalidação dinâmica, confirmação assíncrona, duplo commit, economia com `use_provenance_economy = true`, legado intacto | **3/3 PASS** | 155 |
| `tests/unit/test_ui_1_2_*` + `tests/integration/test_ui_1_2_*` | Compatibilidade UI-1.2 (estelas e lâmina) | **5/5 PASS** | 187 |
| `tests/unit/test_ui_1_1*` + `tests/integration/test_ui_1_1*` | Compatibilidade UI-1.1A e UI-1.1B R1 (pedras, placa, pausa, câmera, hitboxes) | **20/20 PASS** | 698 |
| `tests/integration/test_t3_5_1_construction_hud.gd` | Preservação do catálogo legado em `use_d2_2_hud = false` | **3/3 PASS** | 35 |

### 4.3 Regressão Segmentada Completa
- **Comando:** `.\tools\run_tests.ps1 -Segmented -MaxIntegrationPerGroup 1` (em `C:\Projetos\Dawn_of_Kin_wt_ui_1_3`)
- **Exit Code:** `0`
- **Lotes:** `60 / 60 PASS` (`unit` + `integration-01` a `integration-59`)
- **Suítes:** **85 / 85 PASS** (`Discovered=85 | ExecutedUnique=85 | Duplicates=0 | Missing=0`)
- **Testes:** **592 / 592 PASS** (`Failed=0 | SuiteErrors=0`)
- **Asserções:** **28.992**
- **Duração:** `SumGodotElapsed = 1.162.048,9 ms` | `TotalWallElapsed = 1.252.162,9 ms`

---

## 5. Visual Consistency Gate (VCG) — Evidências Reais em GPU (Godot 4.7.2)

Renderizado em `Godot v4.7.2.stable` (`OpenGL 3.3.0 - Compatibility`, `Intel(R) UHD Graphics 620`) sobre a `MainScene` real (`use_provenance_economy = true`), com zero erros e teardowns limpos.

### 5.1 Catálogo de Capturas e Pranchas Comparativas (`docs/design/ui-1-3/`)
| Arquivo | Resolução | Cenário capturado |
|---|---|---|
| `G_ui_1_3_hud_closed_1920x1080.png` / `1280x720.png` | 1080p / 720p | HUD normal D2.2 com catálogo fechado (lajes `Maquetes` + `Tarefas`/`Linhagem` inertes). |
| `G_ui_1_3_dock_open_1920x1080.png` / `1280x720.png` | 1080p / 720p | Mesa de maquetes aberta em repouso (duas maquetes verticais em alabastro). |
| `G_ui_1_3_shelter_valid_1920x1080.png` / `1280x720.png` | 1080p / 720p | `Abrigo Básico` selecionado (`● EM POSIÇÃO`), preview 3D verde válido + faixa `LOCAL VÁLIDO`. |
| `G_ui_1_3_depot_selected_valid_1920x1080.png` / `1280x720.png` | 1080p / 720p | `Depósito Rústico` selecionado (`● EM POSIÇÃO`), preview 3D verde válido + faixa `LOCAL VÁLIDO`. |
| `G_ui_1_3_preview_invalid_1920x1080.png` / `1280x720.png` | 1080p / 720p | Preview 3D vermelho sobre `CampStorageZone` + faixa `INVÁLIDO` com motivo real do validador. |
| `G_ui_1_3_coexistence_1920x1080.png` / `1280x720.png` | 1080p / 720p | Coexistência simultânea de todos os 4 cantos + lâmina de fundador + mesa aberta + faixa + preview 3D. |
| `G_ui_1_3_paused_1920x1080.png` | 1080p | Pausa real ativa (`||` ativo no selo superior direito, componentes de construção pausados). |
| `G_ui_1_3_legacy_intact_1280x720.png` | 720p | Modo padrão (`use_d2_2_hud = false`): `ResourceHud` e catálogo legado `ConstructionHud` 100% preservados. |
| `C_ui_1_3_compare_action_slabs.png` | 1060×544 | Comparativo regional direto: `G_godot_D2_2_hud_1920x1080` × UI-1.3 lajes inferiores direitas. |
| `C_ui_1_3_compare_maquettes_dock.png` | 1060×1004 | Comparativo regional direto: `G_godot_D2_2_construction_1920x1080` × UI-1.3 mesa de maquetes. |
| `C_ui_1_3_compare_status_bar.png` | 920×676 | Comparativo regional direto: `G_godot_D2_2_construction_1920x1080` × UI-1.3 faixa de validação (válido e inválido). |

### 5.2 Checklist VCG de 10 Passos (Design System §8)
1. **[x] Conferência Estrita de Tokens:** Todos os tons (basalto, alabastro, ouro kintsugi, verde `#385B2A`, terracota `#C66A58`, rosa `#F2B8AC`, âmbar `#EAB464`, nanquim `#1D1813`) derivam exclusivamente de `D2Tokens` / Seção 2.
2. **[x] Reutilização Canônica de Assets:** `slab_maquetes_alab`, `slab_cmd_basalt`, `maquette_shelter`, `maquette_depot_sel`, `build_valid_bar`, `ico_tasks`, `ico_lineage`, `d1_shelter_mini.png`, `d1_depot_mini.png` carregados via `D2AtlasLibrary` sem alteração dos arquivos originais.
3. **[x] Silhueta Mineral e Chanfros:** Todas as peças preservam polígonos chanfrados assimétricos e sombras `shadow_pad = 10 px`; zero listas/botões retangulares genéricos.
4. **[x] Coerência de Posicionamento:** Validado em `G_ui_1_3_coexistence_1280x720.png` e `1920x1080.png` com todos os painéis abertos simultaneamente e zero colisão.
5. **[x] Legibilidade em `1280×720`:** Sem cortes, sem overflow e com contraste AAA/AA verificado.
6. **[x] Fidelidade e Nitidez em `1920×1080`:** Alinhamento e proporções fiéis às pranchas D2.2.
7. **[x] Inspeção de Estados e Click-Through:** Estados Normal/Hover/Pressed/Selected/Disabled verificados; `D2PolygonalSlab`/`D2SlabButton` com `MOUSE_FILTER_STOP` + `mouse_force_pass_scroll_events = false` + `FOCUS_NONE`; áreas vazias e `shadow_pad` com `MOUSE_FILTER_IGNORE` / `_has_point() == false`.
8. **[x] Comparação com Referências Oficiais:** Confrontado lado a lado nas 3 pranchas `C_ui_1_3_compare_*.png` contra `G_godot_D2_2_hud_1920x1080.png` e `G_godot_D2_2_construction_1920x1080.png`.
9. **[x] Identificação Honesta de Diferenças:** Registrada integralmente na Seção 6 abaixo.
10. **[ ] Decisão Exclusiva do Proprietário:** Pendente de auditoria independente e aceite expresso do proprietário (sem merge nem tag).

---

## 6. Divergências Técnicas e Limitações (Protocolo por Criticidade)

### Bloqueantes
- **Nenhum identificado.** Zero falhas de regressão, economia, RTS, pausa, câmera, `Esc`, click-through, compilação, sobreposição ou desvio artístico da D2.2.

### Não bloqueantes (justificados e transparentes)
1. **Posicionamento superior central da `D2PlacementStatusBar` (reconciliação documental):** Embora a prosa do Design System §3 (Componente 07) mencione "Centro inferior", as capturas visuais oficiais homologadas (`G_godot_D2_2_construction_1920x1080.png`, `G_godot_D2_2_construction_1280x720.png`, `ui0_r2_2_d2_faithful_showcase.gd:320-324`) e o próprio `PlacementTestOverlay` posicionam `build_valid_bar` no **topo central** (`y = 24 * s`). Em `1280×720`, a largura inferior livre entre `D2LineageBladeView` e `D2ActionSlabsView` é insuficiente para uma faixa de `760 px` escalada, o que causaria sobreposição grave; o topo central garante fidelidade exata às capturas aprovadas e zero interseção em todas as resoluções.
2. **Omissão da legenda `"Protege 50/50/30"` na maquete `Depósito Rústico`:** Para cumprir a proibição expressa de anunciar armazenamento protegido da T3.7 antes da sua implementação, a maquete exibe estritamente metadados reais de `BuildingDefinition` (`5×4 m · 45 s · máx. 2` e `18 Mad · 10 Ped`).
3. **Controles `Tarefas [T]` e `Linhagem [H]` inertes na laje de basalto:** Mantêm a aparência canônica D2.2 com contraste visualmente rebaixado (`COLOR_DISABLED_TEXT`), sem disparar ações falsas até as etapas autorizadas correspondentes.
4. **Badge `[1]`/`[2]` nas maquetes e tag `INVÁLIDO` / `VALIDANDO` na faixa:** Adições mínimas estritamente dentro da paleta `D2Tokens` (garantindo contraste AAA sobre alabastro para motivos de erro e confirmação assíncrona).
5. **Verificação manual humana pendente:** O teste tátil direto em jogo pelo proprietário ainda não foi executado por humano e segue detalhado na Seção 7.

---

## 7. Instruções para Testar em Jogo (`MainScene` Real em Modo D2.2) e Protocolo Humano

### Como abrir a `MainScene` real no modo D2.2
- **Opção A (via `ui_1_d2_2_sandbox.tscn`, recomendada — não altera `main.tscn`):**
  1. Abrir o projeto `C:\Projetos\Dawn_of_Kin_wt_ui_1_3` na Godot 4.7.2.
  2. Executar a cena `res://tests/visual/ui_1_d2_2_sandbox.tscn` (instância direta da `MainScene` real com `use_d2_2_hud = true` e `use_provenance_economy = true`).
- **Opção B (diretamente em `src/main/main.tscn`):**
  1. Abrir `res://src/main/main.tscn`, marcar temporariamente `Use D2 2 Hud = On` no Inspector do nó `Main` (sem commitar) e pressionar `F6`.
  2. Para conferir o modo legado preservado, manter `Use D2 2 Hud = Off` (padrão) e executar `src/main/main.tscn`.

### Protocolo curto de verificação humana (5–8 minutos)
1. **HUD normal e lajes inferiores direitas:** Confirmar laje de alabastro `Maquetes / Construir [B]` e laje de basalto `Tarefas [T]` / `Linhagem [H]` (inertes); confirmar ausência do botão legado `Construir`.
2. **Abrir/fechar mesa:** Clicar em `Maquetes` e alternar com a tecla `[B]`. Confirmar abertura/fechamento das duas maquetes verticais em alabastro com ilustrações e custos reais (`12 Mad · 6 Ped` e `18 Mad · 10 Ped`).
3. **Iniciar posicionamento por clique e `[1]`/`[2]`:** Clicar em `Abrigo Básico` (ou pressionar `[1]` com mesa aberta) → confirmar fechamento da mesa, surgimento do preview 3D e da faixa superior `build_valid_bar`, sem banner legado duplicado. Pressionar `[2]` para trocar para `Depósito Rústico` e `[B]` para conferir `● EM POSIÇÃO` erguida.
4. **Feedback válido e inválido:** Passar o cursor sobre solo livre (`LOCAL VÁLIDO` + ghost verde) e sobre o `Acampamento` ou obstáculo (`INVÁLIDO` + motivo real + ghost vermelho); clicar sobre área inválida e confirmar rejeição mantendo o modo ativo.
5. **Confirmação real de canteiro:** Com recursos coletados no acampamento (ou usando `F8` para QA), clicar em solo válido → confirmar criação do canteiro via `ConstructionManager`, reserva física refletida nas pedras de recursos superiores e ocultação automática da faixa.
6. **Hierarquia de `Esc`:** Selecionar um fundador → abrir mesa (`[B]`) → escolher maquete (`[1]`) → reabrir mesa (`[B]`):
   - 1º `Esc`: fecha **apenas** a mesa (placement e seleção continuam).
   - 2º `Esc`: cancela **apenas** o placement (seleção continua, mesa não reabre).
   - 3º `Esc`: limpa seleção do fundador.
7. **Pausa e Anti-Click-Through:** Testar clique direito e scroll sobre lajes, maquetes e faixa (zero ordem RTS e zero zoom). Pausar via `||`: confirmar que `[B]`, `[1]`, clique em `Maquetes` e `Esc` não disparam construção nem despausam a simulação; retomar em `1×`.
8. **Resolução `1280×720` ↔ `1920×1080`:** Alternar resolução via `F8` (botões `1280×720` e `1920×1080`) com fundador selecionado, mesa aberta e preview ativo; confirmar ausência total de cortes ou sobreposições.
