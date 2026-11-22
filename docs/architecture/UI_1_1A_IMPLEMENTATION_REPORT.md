# DAWN OF KIN — UI-1.1A: RELATÓRIO TÉCNICO DE IMPLEMENTAÇÃO
## Fundação Visual e Integração de Dados Reais — Identidade D2.2 ("Marcos de Pedra e Eclipse")

> **Status:** `CANDIDATA PRONTA PARA AUDITORIA E ACEITE` — Subincremento **`UI-1.1A`** implementado, testado automaticamente (**`79/79` suítes, `570/570` testes, `28.051` asserções, `0` falhas, `0` avisos de tipagem estrita**, com execução integral segmentada limpa e código de saída **`0`**) e validado visualmente ao vivo na **Godot 4.7.2** (`Intel(R) UHD Graphics 620`, `OpenGL 3.3 Compatibility`) em `1280×720` e `1920×1080`.  
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
  - `test_ui_1_1a_visual_data.gd`: **4/4 aprovados (`100` asserções)** — modo legado intacto em `main.tscn`, modo dual sem HUD duplicada, coleta física real com proveniência (`use_provenance_economy = true`) sem crédito antecipado antes da descarga, atualização real do indicador de exposição, preservação de pausa externa, layout sem clipping/sobreposição em `1280×720` e `1920×1080`, e teardown controlado com `0` listeners remanescentes em `SettlementInventory`.
- **Regressão Completa do Repositório (`.\tools\run_tests.ps1 -Segmented -MaxIntegrationPerGroup 1`):**
  - Execução segmentada completa em lote unitário para suítes de integração, sem concorrência de processos e sem alterar timeouts ou código do runner.
  - **Resultado Oficial da Execução Integral Única:** **Código de saída `0` · 79/79 suítes concluídas · 570/570 testes aprovados · 0 falhas · 0 erros de suíte · 28.051 asserções · 0 avisos de tipagem estrita** (ver Seções 6.2 e 7 para o histórico completo das rodadas).

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

---

## 6. Adendo R1 — Fechamento das Evidências de Integração (`use_provenance_economy = true`) e Regressão Limpa

### 6.1 Pendência A — Cobertura em Economia Real de Produção (`use_provenance_economy = true`)
Adicionado o teste de integração `test_production_provenance_economy_real_gathering_and_controlled_teardown()` em [`tests/integration/test_ui_1_1a_visual_data.gd`](../../tests/integration/test_ui_1_1a_visual_data.gd) executando **sem sobrescrever** `use_provenance_economy` (mantendo o padrão de produção `true` tanto em `src/main/main.tscn` quanto em `tests/visual/ui_1_d2_2_sandbox.tscn`):
- **Resultado:** **PASS (`35` asserções)** dentro de `test_ui_1_1a_visual_data.gd` (**4/4 testes aprovados, `100` asserções, `5.984,4 ms`, 0 erros, 0 avisos**).
- **Itens comprovados com proveniência ativa:**
  1. Admissão econômica válida em `MainScene` (`use_provenance_economy == true`, `PlacementController` ativo, `D2HudRoot` instanciado).
  2. Saldos iniciais verdadeiros (`0/0/0`) nas 3 pedras e `EXPOSED_IDLE` na placa superior.
  3. Coleta física real de madeira por trabalhador (`LeaderA`) via `CommandController`.
  4. Zero crédito antecipado antes da descarga física (`wood == 0` na pedra enquanto `carry_load > 0` com `validate_provenance() == true`).
  5. Atualização imediata da pedra de madeira após descarga física com carga esvaziada (`avail_wood == phys_wood > 0`, `reserved_wood == 0`, zero duplicação de saldo/transporte/reserva).
  6. Exposição atualizada para `EXPOSED_ACTIVE` (`● EXPOSTO`).
  7. `preflight_economic_teardown()` (`ok == true`), `request_controlled_teardown()` (`ok == true`), liberação limpa do domínio regional (`get_last_domain_release_result().ok == true`) e `0` listeners remanescentes em `SettlementInventory.inventory_changed`.
  8. Modo legado (`main.tscn` com `use_provenance_economy = true` e `use_d2_2_hud = false`) preservado e com teardown controlado bem-sucedido.

### 6.2 Pendência B (Histórico R1) — Diagnóstico da Regressão e Causa Raiz do Timeout em Lote de 3 Suítes
Executado `.\tools\run_tests.ps1 -Segmented` (com o valor padrão `MaxIntegrationPerGroup = 3`) de forma isolada durante a rodada R1:
- **Código de saída:** **`1`** (por timeout de `120 s` no lote `BATCH integration-17`, **não** por falha de asserção).
- **Contagem exata dessa execução histórica:** `78/79` suítes concluídas · `554/554` testes aprovados · `0` falhas · `0` avisos de tipagem estrita · `27.882` asserções.
- **Diagnóstico objetivo da causa raiz do timeout em `BATCH integration-17`:**
  O runner `tools/run_tests.ps1 -Segmented` agrupa por padrão até 3 suítes por lote (`max_per_batch = 3`) sob limite fixo de `GroupTimeoutSeconds = 120`. O lote `integration-17` reúne as 3 suítes pesadas de cancelamento e recuperação da `T3.6.3`:
  1. `test_t3_6_3_b1_2_cancellation_commit_transaction.gd` — **`10,00 s`** (`4/4` PASS, `201` asserções)
  2. `test_t3_6_3_b1_3_physical_recovery.gd` — **`34,47 s`** (`9/9` PASS, `370` asserções)
  3. `test_t3_6_3_b1_4_recovery_dispatch.gd` — **`89,90 s`** (`16/16` PASS, `178` asserções)
  - **Soma real das 3 suítes no lote:** `10,00 + 34,47 + 89,90 = 134,37 s` (+ inicialização da Godot ≈ `138 s` > `120 s`).
  - **Conclusão:** O timeout decorre puramente da soma aritmética do tempo de execução de 3 suítes intensivas de simulação que excedem 120 segundos combinadas, e não de qualquer anomalia de código ou da interface UI-1.1A. O próprio script `tools/run_tests.ps1` já dispõe nativamente do parâmetro `-MaxIntegrationPerGroup` para configurar o tamanho do lote sem necessitar de alteração de código.

### 6.3 Arquivos Modificados na Revisão R1
- **Arquivos modificados:** [`tests/integration/test_ui_1_1a_visual_data.gd`](../../tests/integration/test_ui_1_1a_visual_data.gd) e [`docs/architecture/UI_1_1A_IMPLEMENTATION_REPORT.md`](UI_1_1A_IMPLEMENTATION_REPORT.md).
- **Preservação integral confirmada:** nenhum código de produção (`src/`), asset (`assets/ui/d2/`, `docs/design/ui-0-r2-2/assets/`), captura visual (`docs/design/ui-1-1a/`), `tools/run_tests.ps1`, `main` ou worktree protegido foi alterado.

---

## 7. Adendo R2 — Validação Final da Regressão Integral Limpa com Código de Saída Zero

### 7.1 Histórico Consolidado das Execuções de Regressão

| Rodada / Contexto | Comando Executado | Lotes / Agrupamento | Código de Saída | Suítes / Testes | Asserções | Observações |
|---|---|---|:---:|:---:|:---:|---|
| **Execução Inicial UI-1.1A** | `.\tools\run_tests.ps1 -Segmented` | 42 lotes (`MaxIntegrationPerGroup = 3`) | `1` (timeout no lote 17) | 78/79 suítes concluídas (553/553 PASS) + `b1_4` isolado (16/16 PASS) | 28.017 | Concorrência de CPU com script de captura visual Godot em segundo plano. |
| **Execução R1 (Diagnóstico)** | `.\tools\run_tests.ps1 -Segmented` | 42 lotes (`MaxIntegrationPerGroup = 3`) | `1` (timeout no lote 17) | 78/79 suítes concluídas (554/554 PASS) | 27.882 | Execução isolada comprovando que a soma das 3 suítes (`134,37 s`) excede aritmeticamente o timeout de 120 s. |
| **Execução R2 (Oficial Limpa)** | `.\tools\run_tests.ps1 -Segmented -MaxIntegrationPerGroup 1` | 57 lotes (1 unit com 23 suítes + 56 de integração com 1 suíte/lote) | **`0`** | **79/79 suítes (570/570 PASS)** | **28.051** | **Sucesso integral absoluto. Zero timeouts, zero falhas, zero erros de suíte, zero avisos.** |

### 7.2 Execução Integral Oficial (R2) — Métricas Precisas

Executado no worktree isolado `C:\Projetos\Dawn_of_Kin_wt_ui_1_1a` na branch `feat/ui-1-1a-d2-visual-foundation` sem concorrência de processos:

```powershell
.\tools\run_tests.ps1 -Segmented -MaxIntegrationPerGroup 1
```

- **Código de Saída (`$LASTEXITCODE`):** **`0`**
- **Suítes Descobertas:** **79**
- **Particionamento em Lotes:** **57 lotes disjuntos** (1 lote `unit` com 23 suítes + 56 lotes `integration` com 1 suíte cada).
- **Lotes Concluídos com Sucesso:** **57/57 (`PASS unit`, `PASS integration-01` a `PASS integration-56`)**
- **Total de Suítes Executadas:** **79 / 79**
- **Total de Testes Executados:** **570**
- **Testes Aprovados:** **570**
- **Testes com Falha:** **0**
- **Erros de Suíte (`SuiteErrors`):** **0**
- **Total de Asserções Aprovadas:** **28.051**
- **Avisos de Tipagem Estrita:** **0**
- **Verificação de Cobertura (`Coverage Check`):** `Discovered = 79 | ExecutedUnique = 79 | Duplicates = 0 | Missing = 0`
- **Tempo Acumulado das Instâncias Godot (`SumGodotElapsed`):** `1.117.453,9 ms` (~`18,62 min`)
- **Tempo Real de Parede (`TotalWallElapsed`):** `1.199.988,0 ms` (~`20,00 min`)

### 7.3 Preservação Absoluta do Código e Assets (Zero Modificações)

Na presente revisão R2:
- **Código de produção (`src/`):** **ZERO alterações.**
- **Assets (`assets/ui/d2/`, `docs/design/ui-0-r2-2/assets/`):** **ZERO alterações.**
- **Cenas (`main.tscn`, `ui_1_d2_2_sandbox.tscn`):** **ZERO alterações.**
- **Testes automatizados (`tests/`):** **ZERO alterações.**
- **Script de execução (`tools/run_tests.ps1`):** **ZERO alterações** (utilizada funcionalidade nativa já existente `-MaxIntegrationPerGroup 1`).
- **Repositório principal (`C:\Projetos\Dawn of Kin`, branch `review/t2-closeout-candidate`):** **100% intocado e protegido.**
- **Único arquivo modificado:** este relatório técnico documental ([`UI_1_1A_IMPLEMENTATION_REPORT.md`](UI_1_1A_IMPLEMENTATION_REPORT.md)).

### 7.4 Reafirmação Expressa de Proposta Candidata

- A implementação **UI-1.1A** permanece formalmente como uma **candidata de implementação técnica e visual**.
- Nenhum merge para `main` ou para a base de desenvolvimento foi realizado.
- Nenhuma tag Git foi criada.
- A etapa subsequente **UI-1.1B** **NÃO FOI INICIADA**.
- O trabalho permanece estritamente interrompido para auditoria independente do ChatGPT e deliberação/homologação formal pelo proprietário.


