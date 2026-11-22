# DAWN OF KIN — UI-1.0 R1
## Revisão Final do Plano Técnico de Integração da Interface D2.2 ("Marcos de Pedra e Eclipse")

> **Status:** `PLANO TÉCNICO REVISADO (UI-1.0 R1 — AGUARDANDO ACEITE DO PROPRIETÁRIO)`  
> **Escopo:** Revisão exclusivamente documental do plano [UI_1_0_INTEGRATION_PLAN.md](UI_1_0_INTEGRATION_PLAN.md) (`82934dc3410b058c5dfef8c1b1b25bc9aa33cc4c`), incorporando as **5 correções técnicas obrigatórias (A–E)** e a **revisão das decisões `DT-01` a `DT-06`** levantadas na auditoria independente do ChatGPT.  
> **Restrições cumpridas:** Nenhum código de produção foi alterado; `UI-1.1A` **não foi iniciada**; nenhuma decisão técnica foi tratada como homologada em nome do proprietário.  
> **Referências Imutáveis:**
> - **Identidade Visual Aprovada D2.2:** `design/ui-0-r2-2-d2-visual-fidelity` @ `1ab8ffb78c269f3a659712491de91ab1f317e919`
> - **Design System Homologado Documentalmente:** `design/ui-0-r2-3-2-closeout` @ `cdd9f2f4308a05d822c8f7c72f57c0a07756f0a6`
> - **Branch Documental desta Revisão:** `planning/ui-1-0-r1-integration-plan` (worktree isolado `C:\Projetos\Dawn_of_Kin_wt_ui_1_0_r1_plan`).

---

## 1. Diagnóstico das 5 Correções Obrigatórias (Auditoria Independente)

A auditoria real do código em `cdd9f2f` (`Select-String process_mode src/**/*.gd`, `main.gd`, `rts_camera_rig.gd`, `economy_clock_controller.gd`, `rts_input_controller.gd`, `construction_hud.gd`) confirmou os 5 riscos apontados:

| Código | Risco Detectado na UI-1.0 (`82934dc`) | Causa Raiz Verificada no Código Real | Solução Definida nesta R1 |
|---|---|---|---|
| **Correção A** | Pausa via `SceneTree.paused` travaria os próprios controles da UI e poderia divergir de `EconomyClockController`. | Em todo `src/`, apenas `RtsCameraRig` (`PROCESS_MODE_ALWAYS`) e `EconomyClockController` + `_timer` (`PROCESS_MODE_PAUSABLE`) definem `process_mode`. `UiLayer` e seus `Control` herdam `PAUSABLE` — ao pausar a árvore, o botão `1×` deixaria de responder! Além disso, `EconomyClockController.is_paused()` combina `get_tree().paused or _time_provider.is_paused()`, criando risco de dupla pausa divergente se ambos forem acionados separadamente. | Introduzir **`D2SimulationPauseController`** (`PROCESS_MODE_ALWAYS`) como **autoridade única** baseada em pilha de motivos (`_pause_reasons`), sincronizada exclusivamente com `SceneTree.paused` + `RtsCameraRig.set_input_locked()`, mantendo apenas controles de pausa/menu em `PROCESS_MODE_ALWAYS` e restaurando tudo em `_exit_tree()`. |
| **Correção B** | `MOUSE_FILTER_STOP` em `TextureRect` retangular bloquearia cliques/scroll/edge-pan nos cantos transparentes e nos `10 px` de sombra (`shadow_pad`). | Todas as peças de `d2_2_faithful_atlas.png` possuem silhuetas poligonais chanfradas + margem transparente de `10 px` (`atlas_manifest.json`). Um retângulo simples intercepta cliques fora da pedra. | Criar **`D2PolygonalSlab`** / **`D2SlabButton`** sobrescrevendo **`Control._has_point(point: Vector2) -> bool`** com **`Geometry2D.is_point_in_polygon(point, _scaled_polygon)`**, alinhado às coordenadas exatas dos polígonos D2.2 + `shadow_pad`, com `mouse_force_pass_scroll_events = false`. |
| **Correção C** | `D2UiEscapeRouter` na UI-1.1 assumiria abertura de Menu Principal que só existirá na UI-1.5. | Sem menu implementado na UI-1.1, consumir `Esc` para um destino inexistente quebraria o comportamento esperado e criaria conflito com `RtsInputController._unhandled_input()`, `PlacementController` e `ConstructionHud._input()`. | Adoção **progressiva por registro de capacidades**: ausente na `UI-1.1A`; introduzido em modo **pass-through** na `UI-1.1B` (só consome `Esc` se houver handler ativo registrado); cada incremento (`UI-1.3`, `UI-1.4`, `UI-1.5`) registra apenas seus próprios painéis reais. |
| **Correção D** | `D2MainMenuMonolith` (UI-1.5) previa `get_tree().quit()` direto, violando os contratos econômicos de `MainScene`. | `main.gd:167–238` define `preflight_economic_teardown()` (que bloqueia se houver `transaction_in_progress`, custódia pendente ou `pending_material_obligation` em trabalhadores carregando carga) e `request_controlled_teardown()`. `get_tree().quit()` ignora o preflight e pode interromper obrigações econômicas. | Redesenhar o fluxo de saída da `UI-1.5` para consultar **`MainScene.preflight_economic_teardown()`** e executar **`MainScene.request_controlled_teardown()`** somente quando `ok == true`, recusando/adiando o encerramento limpo com mensagem honesta ao jogador quando houver transporte ou transação pendente. |
| **Correção E** | `UI-1.1` acumulava fundação visual, assets, tema, escala, pedras, placa, pausa real, câmera e `Esc` num único incremento grande. | Misturar layout/dados com pausa global e alteração em `RtsCameraRig` dificulta diagnóstico e rollback. | Subdividir em **`UI-1.1A` (Fundação Visual e Dados, zero mudança em `RtsCameraRig`/pausa/`Esc`)** e **`UI-1.1B` (Hitboxes Poligonais, Pausa Segura, Proteção de Câmera e `Esc` Router Progressivo)**. |

---

## 2. Arquitetura Ajustada (Correções A, B, C e D)

### 2.1 Arquitetura de Pausa Segura (`Correção A`)

| Componente / Nó | `process_mode` | Comportamento Durante `SceneTree.paused == true` |
|---|---|---|
| `MainScene`, `Units`, `Unit`, `ConstructionSites`, `ConstructionSite`, `RtsInputController`, `PlacementController`, `CommunityTaskDispatcher` | `INHERIT` (`PAUSABLE`) | **Pausados integralmente** — zero movimento, zero extração/transporte, zero montagem de canteiro, zero comandos RTS. |
| `EconomyClockController` + `DecayTickTimer` | `PAUSABLE` (já existente) | **Pausado automaticamente** por `SceneTree.paused`. **Regra estrita:** `D2SimulationPauseController` **NÃO** chama `EconomyClockController.set_paused()` para evitar segundo estado divergente; `EconomyClockController.is_paused()` já retorna `true` via `get_tree().paused`. |
| `RtsCameraRig` | `ALWAYS` (já existente) | Recebe `_camera_rig.set_input_locked(true)` do `D2SimulationPauseController`: zera `_pan_velocity_xz`, cancela `_is_dragging` e bloqueia WASD/Setas, Edge Pan, Wheel Zoom e MMB Drag durante a pausa. |
| `D2SimulationPauseController` | **`ALWAYS`** | **Única autoridade de pausa da UI.** Mantém conjunto de motivos ativos (`_reasons: Dictionary`, ex.: `&"hud_pause"`, `&"modal_menu"`). Define `get_tree().paused = not _reasons.is_empty()` e `_camera_rig.set_input_locked(not _reasons.is_empty())`. Emite `pause_state_changed(is_paused: bool)`. |
| `D2TopPlaqueView` (controles `||` e `1×`) | **`ALWAYS`** | Continua recebendo cliques durante a pausa para permitir clicar em `1×` (ou `||`) e retomar a simulação imediatamente. |
| `D2MainMenuMonolith` & `D2UiEscapeRouter` (`UI-1.5`) | **`ALWAYS`** | Continuam responsivos para fechar menu via `Continuar` ou `Esc`. |
| Demais componentes D2.2 (`D2ResourceRocksView`, `D2FounderStelesView`, `D2ActionSlabsView`, `D2ConstructionDockView`, `D2BuildingInspectorMonolith`, `D2LineageBladeView`, `D2TasksDrawerView`) | `PAUSABLE` | Impede seleção de estelas, início de construção ou ações econômicas (`DEC-11B` / `D3`) enquanto pausado. |

**Garantias contra estados divergentes e erros:**
1. **Idempotência:** `request_pause(&"hud_pause")` repetido não duplica entradas; `release_pause(&"hud_pause")` só despausa a árvore se nenhum outro motivo (ex.: `&"modal_menu"`) estiver ativo.
2. **Restauração garantida:** Em `_exit_tree()`, `unbind()` e erros de inicialização, `D2SimulationPauseController.force_clear_all_pauses()` restaura obrigatoriamente `get_tree().paused = false` e `_camera_rig.set_input_locked(false)` (garantindo zero vazamento de pausa entre cenas ou testes).
3. **Sem confusão com `EconomyClockController.set_paused()`:** Testes automatizados de `EconomyClockController` continuam usando `set_paused()` isoladamente sem interferência; em runtime normal, `EconomyClockController.is_paused()` reflete fielmente `SceneTree.paused`.

### 2.2 Hitboxes Poligonais Compatíveis com a Silhueta D2.2 (`Correção B`)

Para preservar 100% da aparência D2.2 sem criar bloqueios retangulares fantasmas:

```gdscript
# Contrato conceitual de D2PolygonalSlab (estende TextureRect ou Control)
# - _base_polygon: PackedVector2Array em coordenadas do conteúdo (ex.: 84x42 para resource_rock)
# - _pad: float = 10.0 (shadow_pad do atlas_manifest.json)
# - _scaled_polygon: recalculado apenas em _notification(NOTIFICATION_RESIZED) ou set_scale_factor()
func _has_point(point: Vector2) -> bool:
    if _scaled_polygon.size() < 3:
        return Rect2(Vector2.ZERO, size).has_point(point)
    return Geometry2D.is_point_in_polygon(point, _scaled_polygon)
```

- **Polígonos canônicos exatos (do Design System D2.2):**
  - `resource_rock` (`84×42`): `[(6,0), (84,3), (79,42), (0,38)]` + offset `pad = 10`.
  - `top_plaque` (`196×110`): `[(0,4), (98,0), (196,4), (190,110), (6,106)]` + offset `pad = 10`.
  - `founder_stele` (`108×136`) / `raised` (`108×154`): `[(6,6), (108,0), (104,H), (0,0.98*H)]` + offset `pad = 10`.
  - `slab_maquetes_alab` (`176×72`) / `slab_cmd_basalt` (`146×72`): `[(8,0), (W,4), (W-6,72), (0,69)]` + offset `pad = 10`.
  - `d2_2_menu_monolith` (`632×1080`): `[(0,0), (632,0), (468,1080), (0,1080)]` escalado proporcionalmente.
- **Propriedades de entrada obrigatórias:**
  - Peça mineral (`D2PolygonalSlab` / `D2SlabButton`): `mouse_filter = MOUSE_FILTER_STOP`, `mouse_force_pass_scroll_events = false`, `focus_mode = FOCUS_NONE`.
  - Textos, ícones e retratos internos: `mouse_filter = MOUSE_FILTER_IGNORE`.
  - Containers de layout e vãos entre pedras: `mouse_filter = MOUSE_FILTER_IGNORE`.
- **Benefício duplo automático no Edge Pan:** Como `Viewport.gui_get_hovered_control()` respeita `Control._has_point()`, o Edge Pan de `RtsCameraRig` será bloqueado **exclusivamente** quando o ponteiro estiver sobre a rocha sólida, e continuará funcionando normalmente sobre os `10 px` transparentes e na borda livre da janela!

### 2.3 Introdução Gradual do `D2UiEscapeRouter` (`Correção C`)

O roteador de `Esc` usa um registro ordenado por prioridade (`priority: int`, `can_handle: Callable`, `handle: Callable`) e **nunca** chama `get_viewport().set_input_as_handled()` quando nenhum handler registrado responde `true`:

| Etapa | Estado do `D2UiEscapeRouter` (`use_d2_2_hud == true`) | Modo Legado (`use_d2_2_hud == false`) |
|---|---|---|
| **UI-1.1A** | **Não instanciado / inativo.** `Esc` segue 100% o fluxo atual (`ConstructionHud` → `PlacementController` → `RtsInputController`). | Intocado. |
| **UI-1.1B** | **Instanciado em modo pass-through** (0 handlers bloqueantes ativos; estrutura unitariamente testada). Não intercepta `Esc` enquanto nenhum painel D2.2 estiver registrado; se `||` estiver pausado e nenhum modal existir, decisão conservadora: `Esc` não abre menu inexistente. | Desativado / não conectado. |
| **UI-1.3** | Registra handlers reais: (1) fechar Mesa de Maquetes (`priority 30`), (2) `PlacementController.cancel_placement()` (`priority 40`). `ConstructionHud` legado desligado quando `use_d2_2_hud == true`. | Intocado. |
| **UI-1.4** | Registra handler real: fechar `D2BuildingInspectorMonolith` (`priority 50`). | Intocado. |
| **UI-1.5** | Registra handlers reais: (1) fechar Configurações (`priority 10`), (2) fechar Menu/Pausa (`priority 20`), e **somente aqui** o fallback de menor prioridade (`priority 90`): abrir Menu/Pausa quando `not RtsInputController.is_drag_gesture_active()` e `SelectionManager.is_empty()` e nenhum painel contextual estiver aberto. | Intocado. |

### 2.4 Encerramento Econômico Seguro na UI-1.5 (`Correção D` — Planejado, Não Implementado Agora)

O botão `"Sair"` do futuro `D2MainMenuMonolith` (`UI-1.5`) **nunca** chamará `get_tree().quit()` diretamente. O protocolo obrigatório será:

```mermaid
flowchart TD
    A["Jogador clica 'Sair' no Menu (UI-1.5)"] --> B["Chama MainScene.preflight_economic_teardown()"]
    B --> C{"preflight.ok == true?"}
    C -- Não --> D["RECUSA / ADIA encerramento limpo\nNÃO descarta carga nem mascara transação"]
    D --> E["Exibe motivo real ao jogador:\n• 'pending_material_obligation': trabalhadores carregando materiais\n• 'transaction_in_progress': operação econômica ativa\n• custódia de cancelamento pendente\nAção: botão 'Retomar jogo' para concluir entregas"]
    C -- Sim --> F["Exibe confirmação simples de saída"]
    F --> G["Jogador confirma"]
    G --> H["D2HudRoot.unbind() + D2SimulationPauseController.force_clear_all_pauses()"]
    H --> I["var res = MainScene.request_controlled_teardown()"]
    I --> J{"res.ok == true?"}
    J -- Sim --> K["Aguarda 1 process_frame + get_tree().quit(0)"]
    J -- Não --> D
```

- **Proteção garantida:** Nenhum material em transporte, reserva em pilha ou transação de custódia regional (`ReservedWithdrawalCoordinator` / `CancellationLifecycleGuard`) é descartado ou mascarado. *(Nota: a eventual inclusão de um botão secundário explícito de "Forçar saída perdendo estado da sessão" fica como decisão opcional futura do proprietário, fora do escopo padrão da `UI-1.5`.)*

---

## 3. Revisão da Matriz de Decisões Técnicas (`DT-01` a `DT-06`)

> **Importante:** Todas as decisões abaixo permanecem **`PENDENTE DE ACEITE DO PROPRIETÁRIO`**. As ressalvas da auditoria independente do ChatGPT foram incorporadas, sem presumir aprovação prévia.

| ID | Decisão | Proposta Revisada com Ressalvas da Auditoria | Estado |
|---|---|---|---|
| **DT-01** | **Base Git da `UI-1`** | Derivar `feat/ui-1-1a-d2-visual-foundation` de **`design/ui-0-r2-3-2-closeout` (`cdd9f2f`)**. Topologia Git revalidada nesta R1: `0` diffs de código entre `feat/rux-2b-multi-source-selection` (`cddd582`) e `cdd9f2f`. | `PENDENTE DE ACEITE` |
| **DT-02** | **Assets Runtime** | Copiar bit-a-bit os 9 assets de `docs/design/ui-0-r2-2/assets/` para `res://assets/ui/d2/` para importação Godot limpa (`.import` fora de `docs/`), **sem modificar os originais** e **mantendo integralmente as ressalvas de procedência/licença** da Seção 6.1 do Design System. | `PENDENTE DE ACEITE` |
| **DT-03** | **Tipografia** | Usar `SystemFont` nativo como solução **provisória** na `UI-1.1A/1.1B` (sem redistribuir fontes proprietárias), **sujeito à validação visual de aparência** em `720p`/`1080p` e à posterior definição de fontes abertas com licença verificada (SIL OFL) antes de qualquer build distribuível. | `PENDENTE DE ACEITE` |
| **DT-04** | **Nomes nas Estelas (`UI-1.2`)** | Preservar leitura dinâmica de `CharacterDefinition.display_name` (`"Leader A"` / `"Leader B"` hoje), mantendo 100% dos testes existentes intactos; nenhuma alteração em `.tres` sem autorização explícita. | `PENDENTE DE ACEITE` |
| **DT-05** | **Placa Superior (`UI-1.1A` / `UI-1.1B`)** | Exibir `"Clareira Inicial"` + exposição real (`HudFormatter`) na `UI-1.1A`; ativar **Pausa real (`||`) + `1×`** via `D2SimulationPauseController` na `UI-1.1B`. **Sem estações simuladas (`T4`) e sem multiplicadores `2×`/`4×` não validados.** | `PENDENTE DE ACEITE` |
| **DT-06** | **Comportamento Final de `Esc`** | `D2UiEscapeRouter` assume cada ação **somente quando o respectivo painel existir**; a abertura do Menu/Pausa com tudo fechado e seleção vazia entra **exclusivamente na `UI-1.5`**. | `PENDENTE DE ACEITE` |

---

## 4. Primeiro Incremento Subdividido (`UI-1.1A` e `UI-1.1B`) — Correção E

O roadmap global passa a ser **`UI-1.1A` → `UI-1.1B` → `UI-1.2` → `UI-1.3` → `UI-1.4` → `UI-1.5` → `UI-1.6` → `UI-1.7`**:

### 4.1 Subincremento `UI-1.1A` — Fundação Visual e Dados (Somente Leitura / Zero Mudança em Câmera, Pausa ou `Esc`)
- **Objetivo:** Provar a fidelidade visual D2.2, o carregamento de assets/tema/escala responsiva (`720p`/`1080p`), o modo dual (`use_d2_2_hud`) e o sincronismo reativo por sinais (`SettlementInventory` + `HudFormatter`) sem tocar em `RtsCameraRig`, `RtsInputController`, `SceneTree.paused` nem `Esc`.
- **Componentes:**
  - Cópia runtime bit-a-bit em `res://assets/ui/d2/`.
  - `D2Tokens`, `D2AtlasLibrary`, `D2ThemeFactory` (`SystemFont`), `D2ScaleController`, `D2HudRoot`.
  - `D2ResourceRocksView` (3 pedras escalonadas: Madeira `+0`, Pedra `+7`, Alimento `+2` px).
  - `D2TopPlaqueView` (modo informativo: `"Clareira Inicial"`, status real de exposição `● EXPOSTO` / `PROTEGIDO`, indicadores visuais `||`/`1×`/`☰ MENU` ainda inertes/informativos até `UI-1.1B`/`UI-1.5`).
- **Mudança em produção existente:** Apenas `src/main/main.gd` (`@export var use_d2_2_hud: bool = false`, instanciação condicional de `D2HudRoot` e deslocamento do `DebugOverlay` sob as pedras quando `use_d2_2_hud == true`). `main.tscn` mantém `use_d2_2_hud = false` (100% legado preservado).
- **Testes `UI-1.1A`:**
  - `tests/unit/test_ui_1_1a_foundation.gd` (manifesto 17 regiões, escala `1.00`/`1.22`, `unbind()`, zero polling, `apply_count`).
  - `tests/integration/test_ui_1_1a_visual_data.gd` (sincronismo real de coleta → descarga física → pedras, exposição `HudFormatter`, layout sem corte/sobreposição em `1280×720` e `1920×1080`, regressão 100% da suíte legada).
  - Inspeção visual manual na Godot 4.7.2 via `tests/visual/ui_1_d2_2_sandbox.tscn` + VCG parcial (regiões superior esquerda e superior direita vs `G_godot_D2_2_hud_*`).

### 4.2 Subincremento `UI-1.1B` — Hitboxes Poligonais, Pausa Segura, Proteção de Câmera e `Esc` Router Progressivo
- **Objetivo:** Adicionar interação poligonal exata, pausa/retomada real segura com trava de câmera, proteção de Edge Pan sobre peças sólidas e base pass-through do `D2UiEscapeRouter`, **após** a `UI-1.1A` estar validada e aprovada.
- **Componentes:**
  - `D2PolygonalSlab` e `D2SlabButton` (`_has_point()` + `Geometry2D.is_point_in_polygon()`, `mouse_force_pass_scroll_events = false`).
  - `D2SimulationPauseController` (`PROCESS_MODE_ALWAYS`, pilha de motivos, sincronismo com `SceneTree.paused` + `RtsCameraRig.set_input_locked()`, limpeza garantida em `_exit_tree()`).
  - Ativação interativa dos botões `||` e `1×` em `D2TopPlaqueView` (`process_mode = PROCESS_MODE_ALWAYS`).
  - `D2UiEscapeRouter` (registro por prioridade em modo pass-through: não consome `Esc` sem handler ativo).
- **Mudança cirúrgica em produção existente:**
  - `src/camera/rts_camera_rig.gd`: adicionar `set_input_locked(locked: bool)` e checagem de `viewport.gui_get_hovered_control()` no Edge Pan (100% retrocompatível com testes T1/T2).
- **Dependência:** Exclusivamente `UI-1.1A` aprovada.

---

## 5. Testes Adicionais Exigidos (Automáticos + Manuais)

### 5.1 Suíte de Hitboxes Poligonais e Proteção de Entrada (`tests/integration/test_ui_1_1b_hitboxes_and_pause.gd`)
1. **Clique esquerdo na pedra** (ponto interno ao polígono) → consumido pela UI; não altera `SelectionManager` nem inicia box-select.
2. **Clique direito na pedra** (ponto interno ao polígono) → consumido pela UI; unidade selecionada **não** recebe `MoveOrder` nem `GatherResourceOrder`.
3. **Clique sobre canto transparente / margem de sombra `10 px`** → `_has_point()` retorna `false`; evento passa normalmente ao mundo 3D.
4. **Clique no vão entre as pedras escalonadas** → passa normalmente ao mundo 3D.
5. **Scroll (roda do mouse) sobre pedra ou placa** → consumido (`mouse_force_pass_scroll_events = false`); `RtsCameraRig.get_target_zoom_distance()` permanece inalterado.
6. **Scroll e Edge Pan na borda real livre da janela** → funcionam normalmente (zoom altera distância; ponteiro na borda livre move foco da câmera), enquanto ponteiro sobre peça sólida junto à borda **não** dispara Edge Pan.
7. **Zero vazamento de comando RTS** por áreas sólidas em `1280×720` e `1920×1080`.

### 5.2 Suíte de Pausa Segura e Integridade Econômica (`test_ui_1_1b_hitboxes_and_pause.gd`)
1. **Pausa e retomada repetidas (`||` → `1×` → `||` → `1×`)**: `SceneTree.paused`, `EconomyClockController.is_paused()`, `D2SimulationPauseController.is_paused()` e `RtsCameraRig` permanecem 100% sincronizados.
2. **Responsividade durante a pausa:** Com `get_tree().paused == true`, clicar em `1×` na `D2TopPlaqueView` retoma a simulação normalmente (`PROCESS_MODE_ALWAYS`).
3. **Câmera travada na pausa:** WASD/Setas, Edge Pan, Wheel Zoom e MMB Drag produzem deslocamento `0,0` enquanto pausado, voltando a responder após `1×`.
4. **Pausa com transporte e construção ativos:** Pausar no meio de `GatherResourceOrder` / `ConstructOrder` / montagem de `ConstructionSite`, aguardar múltiplos frames reais, retomar com `1×` e comprovar conclusão íntegra com **conservação exata de materiais** (zero perda, zero duplicação, zero trava de estado).
5. **Restauração em saída de cena:** Remover/destruir `MainScene` enquanto pausada restaura `get_tree().paused == false` sem contaminar testes seguintes.
6. **Roteador `Esc` pass-through na `UI-1.1B`:** `Esc` continua cancelando seleção/drag/posicionamento normalmente sem ser engolido para menu inexistente; modo legado (`use_d2_2_hud = false`) 100% idêntico.

---

## 6. Riscos Residuais

| Risco Residual | Gravidade | Mitigação / Controle |
|---|---|---|
| **Aparência de `SystemFont` em máquinas sem `Palatino Linotype`/`Segoe UI`** | Média | Validar visualmente na `UI-1.1A` e planejar pacote de fontes abertas SIL OFL (`DT-03`) antes de builds externos. |
| **Precisão de `_has_point()` após resize dinâmico `720p ↔ 1080p`** | Média | Recalcular `_scaled_polygon` em `NOTIFICATION_RESIZED` + teste automatizado de hitbox antes e depois de resize. |
| **Conflito de foco de teclado em botões Godot** | Baixa | Impor `focus_mode = Control.FOCUS_NONE` em todos os botões D2.2 para impedir que `Space`/`Enter` reativem botões acidentalmente durante comandos RTS. |
| **Encerramento forçado pelo botão `[X]` da janela do SO (`NOTIFICATION_WM_CLOSE_REQUEST`)** | Média | Documentado para a `UI-1.5`: avaliar interceptação de `WM_CLOSE_REQUEST` apenas na `UI-1.5` para aplicar o mesmo preflight de `Correção D` sem bloquear fechamento em testes headless. |
| **Ressalva jurídica dos 6 assets base gerados por IA** | Documental | Preservada integralmente; `D2AtlasLibrary` isola caminhos para substituição futura sem impacto de código. |

---

## 7. Lista Exata de Arquivos Previstos (`UI-1.1A` e `UI-1.1B`)

### Previstos na `UI-1.1A` (após aceite)
- **Criar (assets runtime copiados bit-a-bit de `docs/design/ui-0-r2-2/assets/`):**
  - `assets/ui/d2/d2_2_faithful_atlas.png`, `d2_2_menu_monolith.png`, `atlas_manifest.json`, `portrait_alden.jpg`, `portrait_brena.jpg`, `emblem_dawn_of_kin.png`, `d1_shelter_mini.png`, `d1_depot_mini.png`, `d2_kintsugi_basalt.png`
- **Criar (código UI-1.1A):**
  - `src/ui/d2/d2_tokens.gd`
  - `src/ui/d2/d2_atlas_library.gd`
  - `src/ui/d2/d2_theme_factory.gd`
  - `src/ui/d2/d2_scale_controller.gd`
  - `src/ui/d2/d2_hud_root.gd`
  - `src/ui/d2/components/d2_resource_rocks_view.gd`
  - `src/ui/d2/components/d2_top_plaque_view.gd`
- **Modificar (mínimo e retrocompatível):**
  - `src/main/main.gd` (flag `use_d2_2_hud = false`, composição condicional de `D2HudRoot` e offset de `DebugOverlay`).
- **Criar (cena visual e testes):**
  - `tests/visual/ui_1_d2_2_sandbox.tscn`
  - `tests/unit/test_ui_1_1a_foundation.gd`
  - `tests/integration/test_ui_1_1a_visual_data.gd`

### Previstos na `UI-1.1B` (somente após aprovação da `UI-1.1A`)
- **Criar (código UI-1.1B):**
  - `src/ui/d2/components/d2_polygonal_slab.gd`
  - `src/ui/d2/components/d2_slab_button.gd`
  - `src/ui/d2/d2_simulation_pause_controller.gd`
  - `src/ui/d2/d2_ui_escape_router.gd`
- **Modificar:**
  - `src/camera/rts_camera_rig.gd` (`set_input_locked(bool)` + checagem `gui_get_hovered_control()` no Edge Pan)
  - `src/ui/d2/d2_hud_root.gd`, `d2_resource_rocks_view.gd`, `d2_top_plaque_view.gd` (adoção de `D2PolygonalSlab`, pausa `||`/`1×`, `PROCESS_MODE_ALWAYS` na placa e `D2UiEscapeRouter` pass-through)
  - `src/main/main.gd` (ligação do `D2SimulationPauseController` ao `RtsCameraRig` e `EconomyClockController`)
- **Criar (testes):**
  - `tests/unit/test_ui_1_1b_polygon_and_pause.gd`
  - `tests/integration/test_ui_1_1b_hitboxes_and_pause.gd`

---

## 8. Critérios de Aceite e Parada

### Critérios de Aceite da `UI-1.1A`
1. `.\tools\run_tests.ps1 -Segmented` — 100% das suítes legadas + `test_ui_1_1a_*` verdes, 0 erros, 0 avisos de tipagem estrita.
2. Visual fiel às regiões superior esquerda e superior direita de `G_godot_D2_2_hud_1280x720.png` e `G_godot_D2_2_hud_1920x1080.png` (VCG).
3. Contadores das 3 pedras e status de exposição 100% sincronizados a `SettlementInventory` e `HudFormatter` sem polling.
4. `main.tscn` (`use_d2_2_hud = false`) sem nenhuma alteração de comportamento.

### Critérios de Aceite da `UI-1.1B`
1. Todos os 7 testes de hitbox poligonal e todos os 6 testes de pausa segura/transporte/construção/Esc verdes.
2. `.\tools\run_tests.ps1 -Segmented` — 100% verde sem regressões em T1, T2, T3.1–T3.6.4, UX-1 ou RUX-1/2A/2B.
3. Validação manual interativa na Godot 4.7.2 (`1280×720` e `1920×1080`) comprovando pausa real, câmera imóvel na pausa, zero Edge Pan sobre pedras/placa e cliques limpos nos vãos transparentes.

### Condições de Parada
- Interromper imediatamente e reportar se houver qualquer falha em teste legado, aviso de tipagem, overflow visual em `720p`, divergência de estado de pausa, ou necessidade de alterar qualquer elemento visual da D2.2.
- **Parada obrigatória após cada subincremento (`UI-1.1A` e `UI-1.1B`)** para revisão do proprietário antes de avançar.
