# DAWN OF KIN — UI-1.1A: RELATÓRIO TÉCNICO DE IMPLEMENTAÇÃO
## Fundação Visual e Integração de Dados Reais — Identidade D2.2 ("Marcos de Pedra e Eclipse")

> **Status:** `CANDIDATA PRONTA PARA AUDITORIA E ACEITE` — Subincremento **`UI-1.1A`** implementado, testado automaticamente (`79/79` suítes, `569/569` testes, `28.017` asserções, `0` falhas, `0` avisos de tipagem estrita) e validado visualmente ao vivo na **Godot 4.7.2** (`Intel(R) UHD Graphics 620`, `OpenGL 3.3 Compatibility`) em `1280×720` e `1920×1080`.  
> **Escopo respeitado:** Somente **`UI-1.1A`** foi implementada. `UI-1.1B` e incrementos posteriores **não foram iniciados**. Zero alterações em gameplay, câmera, pausa, `Esc`, economia, transporte ou construção.  
> **Branch de Implementação:** `feat/ui-1-1a-d2-visual-foundation` (worktree isolado `C:\Projetos\Dawn_of_Kin_wt_ui_1_1a`).  
> **Base Técnica (`DT-01`):** `design/ui-0-r2-3-2-closeout` @ `cdd9f2f4308a05d822c8f7c72f57c0a07756f0a6`.

---

## 1. Referências Normativas e Decisões Aprovadas Aplicadas

- **Plano Técnico Aprovado:** `planning/ui-1-0-r1-integration-plan` @ `7dbfeb148f68f353bad71e1363db01eae7c41018` (`docs/architecture/UI_1_0_R1_INTEGRATION_PLAN.md`).
- **Design System Homologado Documentalmente:** `design/ui-0-r2-3-2-closeout` @ `cdd9f2f4308a05d822c8f7c72f57c0a07756f0a6` ([DAWN_OF_KIN_VISUAL_DESIGN_SYSTEM.md](../design/DAWN_OF_KIN_VISUAL_DESIGN_SYSTEM.md)).
- **Referência Visual Aprovada D2.2:** `design/ui-0-r2-2-d2-visual-fidelity` @ `1ab8ffb78c269f3a659712491de91ab1f317e919` (`G_godot_D2_2_hud_1920x1080.png`, `G_godot_D2_2_hud_1280x720.png`).
- **Decisões `DT-01` a `DT-06` e 3 Salvaguardas Aplicadas:**
  - **DT-01:** Base técnica `cdd9f2f4308a05d822c8f7c72f57c0a07756f0a6` verificada intacta (`0` diffs de código sobre `cddd582`).
  - **DT-02:** 9 assets copiados bit-a-bit de `docs/design/ui-0-r2-2/assets/` para `res://assets/ui/d2/` com paridade SHA-256 verificada em teste automatizado; originais em `docs/` 100% intocados e ressalvas de procedência/licença preservadas.
  - **DT-03:** `SystemFont` provisório via `D2ThemeFactory` (zero fontes proprietárias copiadas, zero caminhos `C:/Windows/Fonts/`).
  - **DT-04 / DT-05 / DT-06:** Nomes dinâmicos preservados; Placa Superior exibe `"CLAREIRA INICIAL"`, `"Acampamento"` e status real de exposição sem estações simuladas nem multiplicadores inventados; `Esc` intocado na `UI-1.1A`.
  - **Salvaguarda 1 (Sem HUD Duplicada):** `@export var use_d2_2_hud: bool = false` em `src/main/main.gd`. Quando `true`, oculta e desconecta (`unbind()`) o `SettlementStockpilePanel` legado, mantendo `SelectedUnitPanel`, `ConstructionHud` e `BuildingInspectorPanel` operacionais até suas respectivas etapas. `main.tscn` permanece em modo legado (`false`).
  - **Salvaguarda 2 (Zero Botão Falsamente Funcional):** Slots `||`, `1×`, `2×`, `4×` e `· ☰ MENU` na `D2TopPlaqueView` renderizados em estilo desabilitado discreto, sem `BaseButton`, sem hover, sem callbacks e com `MOUSE_FILTER_IGNORE`.
  - **Salvaguarda 3 (Preservação de Pausas Externas):** Nenhum código toca `SceneTree.paused`, `Engine.time_scale`, `EconomyClockController.set_paused()`, `RtsCameraRig` ou `Esc`.

---

## 2. Arquivos Criados e Modificados

### 2.1 Único Arquivo de Produção Existente Modificado
- [`src/main/main.gd`](../../src/main/main.gd): Adicionado `@export var use_d2_2_hud: bool = false`, `_setup_d2_hud()`, `_on_d2_layout_updated()` (acomodando `DebugOverlay/Panel` abaixo das 3 pedras no modo D2.2), `unbind()` em `_exit_tree()` e getter `get_d2_hud_root()`. Zero alteração nos demais arquivos em `src/`.

### 2.2 Novos Arquivos Criados
- **Assets Runtime (`res://assets/ui/d2/` — cópia bit-a-bit + `.import` Godot):** `atlas_manifest.json`, `d2_2_faithful_atlas.png`, `d2_2_menu_monolith.png`, `d2_kintsugi_basalt.png`, `emblem_dawn_of_kin.png`, `portrait_alden.jpg`, `portrait_brena.jpg`, `d1_shelter_mini.png`, `d1_depot_mini.png`.
- **Fundação e Componentes D2.2 (`src/ui/d2/`):**
  - [`src/ui/d2/d2_tokens.gd`](../../src/ui/d2/d2_tokens.gd) — Tokens cromáticos WCAG 2.1, dimensões canônicas e calibração responsiva.
  - [`src/ui/d2/d2_atlas_library.gd`](../../src/ui/d2/d2_atlas_library.gd) — Carregamento exclusivo por `res://`, validação das 17 regiões do manifesto e cache de `AtlasTexture`.
  - [`src/ui/d2/d2_theme_factory.gd`](../../src/ui/d2/d2_theme_factory.gd) — `SystemFont` serif/sans e `Theme` nativo Godot.
  - [`src/ui/d2/d2_scale_controller.gd`](../../src/ui/d2/d2_scale_controller.gd) — Fator `1,00` (`1080p`), `1,22` (`720p` em `canvas_items` esticado) e proporção física equivalente em `SubViewport`.
  - [`src/ui/d2/d2_hud_root.gd`](../../src/ui/d2/d2_hud_root.gd) — Compositor raiz leve, zero polling, `configure()` / `unbind()` e `viewport.size_changed`.
  - [`src/ui/d2/components/d2_resource_rocks_view.gd`](../../src/ui/d2/components/d2_resource_rocks_view.gd) — 3 pedras independentes e escalonadas (`+0`, `+7`, `+2` px) dirigidas por `SettlementInventory.inventory_changed` + `HudFormatter`.
  - [`src/ui/d2/components/d2_top_plaque_view.gd`](../../src/ui/d2/components/d2_top_plaque_view.gd) — Placa superior com cumeeira (`196×110`), `"CLAREIRA INICIAL"`, `"Acampamento"`, exposição real (`HudFormatter`) e slots inertes (`||`, `1×`, `2×`, `4×`, `· ☰ MENU`).
- **Cena Visual Isolada & Testes:**
  - [`tests/visual/ui_1_d2_2_sandbox.tscn`](../../tests/visual/ui_1_d2_2_sandbox.tscn) (`main.tscn` com `use_d2_2_hud = true`).
  - [`tests/unit/test_ui_1_1a_foundation.gd`](../../tests/unit/test_ui_1_1a_foundation.gd) (`4` testes, `108` asserções).
  - [`tests/integration/test_ui_1_1a_visual_data.gd`](../../tests/integration/test_ui_1_1a_visual_data.gd) (`3` testes, `65` asserções).

---

## 3. Evidências de Testes Automatizados e Bug Encontrado/Corrigido na Inspeção Visual

### 3.1 Resultados dos Testes (Godot 4.7.2, Tipagem Estrita Ativa)
- **Suítes novas `UI-1.1A` (`.\tools\run_tests.ps1 -Filter "test_ui_1_1a"`):**
  - `test_ui_1_1a_foundation.gd`: **4/4 aprovados (`108` asserções)** — 17 regiões do atlas, SHA-256 bit-a-bit dos 9 assets, escala `720p`/`1080p`, sincronismo reativo sem polling, idempotência, `unbind()`, regressão de redução de escala `1,22 → 1,00` e zero botões interativos/estações inventadas.
  - `test_ui_1_1a_visual_data.gd`: **3/3 aprovados (`65` asserções)** — modo legado intacto em `main.tscn`, modo dual sem HUD duplicada, coleta física real sem crédito antecipado antes da descarga, atualização real do indicador de exposição, preservação de pausa externa, layout sem clipping/sobreposição em `1280×720` e `1920×1080`, e teardown com `0` listeners remanescentes em `SettlementInventory`.
- **Regressão completa (`.\tools\run_tests.ps1 -Segmented` + reexecução isolada de `test_t3_6_3_b1_4_recovery_dispatch.gd`):**
  - Na primeira passagem paralela, o lote `integration-17` atingiu o timeout de `120 s` por concorrência de CPU com a captura visual da Godot; reexecutado isoladamente em seguida, passou **16/16 (`178` asserções)**.
  - **Total consolidado único verificado:** **79/79 suítes · 569/569 testes aprovados · 0 falhas · 28.017 asserções · 0 erros · 0 avisos de tipagem estrita.**

### 3.2 Bug Real Detectado na Inspeção Visual e Corrigido
Na primeira captura real em `1920×1080` após redimensionar de `1280×720` (`s = 1,22 → 1,00`), a inspeção visual revelou que os `TextureRect` das pedras e da placa permaneciam presos em `1,22×` porque `size` era atribuído antes de `custom_minimum_size` (causando clamp pelo tamanho mínimo anterior). Corrigido definindo `custom_minimum_size` antes de `size` em `D2ResourceRocksView` e `D2TopPlaqueView`, validado por nova captura e coberto por teste unitário dedicado.

---

## 4. Validação Visual Real na Godot 4.7.2 e Comparação com D2.2

Todas as capturas abaixo foram geradas diretamente na **Godot 4.7.2** (`Intel(R) UHD Graphics 620`, `gl_compatibility`) sobre `tests/visual/ui_1_d2_2_sandbox.tscn` (com depósitos reais nas pilhas do acampamento via `SettlementInventory`) e `src/main/main.tscn`:

| Evidência Visual Real | Arquivo |
|---|---|
| **HUD D2.2 Real — `1280×720`** | [`G_ui_1_1a_sandbox_1280x720.png`](../design/ui-1-1a/G_ui_1_1a_sandbox_1280x720.png) |
| **HUD D2.2 Real — `1920×1080`** | [`G_ui_1_1a_sandbox_1920x1080.png`](../design/ui-1-1a/G_ui_1_1a_sandbox_1920x1080.png) |
| **Comparação Canto Superior Esquerdo (D2.2 Aprovada × UI-1.1A Real)** | [`C_ui_1_1a_compare_top_left.png`](../design/ui-1-1a/C_ui_1_1a_compare_top_left.png) |
| **Comparação Canto Superior Direito (D2.2 Aprovada × UI-1.1A Real)** | [`C_ui_1_1a_compare_top_right.png`](../design/ui-1-1a/C_ui_1_1a_compare_top_right.png) |
| **Comprovação da HUD Legada Intacta (`main.tscn`, `1280×720`)** | [`G_ui_1_1a_legacy_intact_1280x720.png`](../design/ui-1-1a/G_ui_1_1a_legacy_intact_1280x720.png) |

### Diferenças Visuais Conhecidas e Justificadas (Honestidade VCG)
1. **Placa Superior (`Acampamento` vs `Primavera · Ano I` e controles inertes):** Diferença intencional e exigida por **Salvaguarda 2** e **`DT-05`** — calendário/estações pertencem à `T4`, pausa real à `UI-1.1B` e menu à `UI-1.5`.
2. **Elementos inferiores ainda em modo legado/ausentes no sandbox:** Estelas dos Fundadores (`UI-1.2`), Laje de Alabastro `Maquetes [B]` (`UI-1.3`) e Monólito de Canteiro (`UI-1.4`) pertencem aos próximos incrementos; na `UI-1.1A`, o botão `Construir` legado permanece funcional no canto inferior direito para não desabilitar funcionalidades existentes.
3. **`DebugOverlay [F3]` visível abaixo das pedras:** No sandbox real (`main.tscn`), `DebugOverlay` inicia visível e é deslocado automaticamente abaixo das 3 pedras pelo `D2HudRoot.get_debug_overlay_top_offset()`, evitando qualquer sobreposição.
4. **Tipografia `SystemFont` (`DT-03`):** Visualmente fiel no Windows (`Palatino Linotype` + `Segoe UI`); em plataformas sem essas fontes instaladas, o fallback de sistema poderá variar ligeiramente até a adoção futura de fontes abertas SIL OFL.

---

## 5. Limitações, Riscos Residuais e Parada Obrigatória

- **Limitações esperadas desta etapa (`UI-1.1A`):**
  - Hitboxes poligonais (`_has_point`), pausa real (`D2SimulationPauseController`), trava de câmera/Edge Pan em `RtsCameraRig` e roteador `Esc` pass-through pertencem estritamente à **`UI-1.1B`** (não implementados aqui).
  - Ressalvas de procedência/licenciamento dos 6 assets base gerados por IA (`UI_0_R2_3_2_CLOSEOUT.md` §2) permanecem vigentes.
- **Integridade do Repositório:** `main`, `C:\Projetos\Dawn of Kin`, `docs/design/ui-0-r2-2/assets/*`, `docs/Dawn_of_Kin_GDD.md`, `AGENTS.md` e todas as branches anteriores permanecem intocados.
- **Estado:** **Aguardando auditoria independente do ChatGPT e avaliação/aceite do proprietário.** Não declarada homologada unilateralmente; `UI-1.1B` não iniciada.
