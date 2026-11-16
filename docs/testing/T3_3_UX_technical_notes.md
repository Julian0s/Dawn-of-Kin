# Notas Técnicas T3.3-UX — Resolução Dinâmica e Teste C4 com Quatro Trabalhadores

- **Branch:** `feature/t3-3-construction-logistics`
- **Base (`bb62e85`):** `T3.3-R2` (`origin/main` preservada em `931ad196346251e3f24a3ea5db6facb3641233bc`)
- **Worktree:** `C:\Projetos\Dawn_of_Kin_wt_t3_3_construction`
- **Status:** Implementado, validado em execução gráfica real (`1280×720` e `1920×1080`) e suíte automatizada completa (`34/34` suítes, `234/234` testes). **Adendo de status (16/11/2026):** os **10/10 testes manuais** (incluindo `C4-A..E` e troca dinâmica `1280×720 ↔ 1920×1080`) foram aprovados pelo proprietário em [T3_3_manual_test_protocol.md](T3_3_manual_test_protocol.md); **homologação formal da T3.3 permanece pendente, sem integração à `main` e com T3.4+ não iniciadas** (ver [T3_3_closeout_CANDIDATE.md](T3_3_closeout_CANDIDATE.md)).

---

## 1. Arquitetura Modular Implementada

1. **Seletor modular de resolução ([`src/ui/display_resolution_service.gd`](../../src/ui/display_resolution_service.gd)):**
   - Classe reutilizável `DisplayResolutionService` (`PRESET_1280X720`, `PRESET_1920X1080`) projetada para futura transferência ao menu de Configurações.
   - Altera apenas o `Window` do jogo em modo janela (`window.size` / `window.position`) sem recarregar cena, sem reiniciar partida e sem alterar a resolução do Windows.
   - Consulta `DisplayServer.screen_get_usable_rect()` / `screen_get_size()` e `get_size_with_decorations()` via `compute_safe_window_geometry()`, ajustando e reposicionando a janela dentro da área útil do monitor para impedir que barra de título ou bordas fiquem inacessíveis.
   - Exibe na barra temporária a resolução efetivamente aplicada (`Atual: W×H`, indicando limitação pelo monitor quando aplicável) conectada a `window.size_changed`.

2. **Trabalhadores temporários de teste C4 ([`src/units/temporary_test_workers_controller.gd`](../../src/units/temporary_test_workers_controller.gd)):**
   - Classe `TemporaryTestWorkersController` estritamente de teste/desenvolvimento, sem alterar narrativa, campanha, recrutamento, reprodução, recursos existentes ou os líderes originais (`LeaderA`, `LeaderB`).
   - Botão **`Adicionar 2 trabalhadores de teste — C4`** instancia `Worker3` e `Worker4` usando a infraestrutura padrão de `Unit` (`unit.tscn`, `CharacterDefinition`, `SelectionManager`, `WorldNavigation`), posicionados em pontos navegáveis validados (`snap_to_navmesh` + `find_path().reachable` + cota do terreno + distância mínima de unidades e canteiros) ao redor do acampamento.
   - Bloqueia criação duplicada quando clicado repetidamente (`already_exists`).
   - Botão **`Remover temporários`** verifica `UnitCarryLoad.is_empty()` e `ConstructionSite.get_transit_claim_for_unit()` antes de remover; se houver carga na mochila (`cargo_in_backpack`) ou reserva em trânsito (`transit_claim_active`), bloqueia a remoção com aviso explícito sem descartar materiais. Caso contrário, cancela ordens ativas, remove da seleção e libera os nós com segurança.

3. **Visibilidade de recusa do 4º trabalhador ([`src/rts/command_controller.gd`](../../src/rts/command_controller.gd), [`src/buildings/placement_test_overlay.gd`](../../src/buildings/placement_test_overlay.gd), [`src/main/main.gd`](../../src/main/main.gd)):**
   - `CommandController` emite `command_rejected(pick, reason)` quando `_command_supply_construction_site` falha (ex.: `no_worker_slot`), garantindo que o banner em `PlacementTestOverlay` exiba motivo legível tanto via clique direito (`RMB`) no canteiro quanto via botão `Designar selecionados`.

---

## 2. Evidências Reais Renderizadas (`tests/visual/t3_3_ux_repro.gd`)

Executado com janela real (`--rendering-driver opengl3`) em **`1280×720`** e **`1920×1080`** na GPU `NVIDIA GeForce GTX 1060` (`OpenGL 3.3.0 NVIDIA 461.40`, `EXIT=0, ERR=False, WARN=False`):
- Alternância ao vivo `1280×720 → 1920×1080 → 1280×720` durante transporte ativo, com painel do canteiro aberto e 4 trabalhadores visíveis, preservando `MainScene`, `ConstructionSite`, reservas, mochilas, seleção e câmera.
- Sequência completa **C4-A..E**: `1` supridor solo -> `2` (`1` transportador + `1` construtor) -> `3` (`1` transportador + `2` construtores em prontidão) -> `4º` recusado com banner (`no_worker_slot`) -> interrupção do transportador com promoção automática e entrega final exata (`wood: 12, stone: 6`, sem progresso T3.4) + limpeza segura (`units_count_after_remove: 2`).

Artefatos publicados em `docs/testing/evidence/t3_3_ux/`:
- Resumos: [`summary_1280x720.json`](evidence/t3_3_ux/summary_1280x720.json), [`summary_1920x1080.json`](evidence/t3_3_ux/summary_1920x1080.json)
- Logs JSONL: [`telemetry_1280x720.jsonl`](evidence/t3_3_ux/telemetry_1280x720.jsonl), [`telemetry_1920x1080.jsonl`](evidence/t3_3_ux/telemetry_1920x1080.jsonl)
- Capturas inspecionadas: [`1280x720/01_four_workers_and_site.png`](evidence/t3_3_ux/1280x720/01_four_workers_and_site.png), [`1280x720/04_c4_c_three_workers.png`](evidence/t3_3_ux/1280x720/04_c4_c_three_workers.png), [`1280x720/05_mid_transport_1920x1080_target.png`](evidence/t3_3_ux/1280x720/05_mid_transport_1920x1080_target.png), [`1280x720/06_c4_d_fourth_rejected.png`](evidence/t3_3_ux/1280x720/06_c4_d_fourth_rejected.png), [`1920x1080/07_c4_e_promoted_and_supplied.png`](evidence/t3_3_ux/1920x1080/07_c4_e_promoted_and_supplied.png)

---

## 3. Regressão Automatizada Pós-Edição Final

| Verificação | Comando | Resultado Observado |
|---|---|---|
| Validação de scripts e cena | `.\tools\validate.ps1` | **PASSOU** — `0 errors, 0 warnings, 109 scripts checked` |
| Suítes filtradas T3.3 (`+ T3.3-UX`) | `.\tools\run_tests.ps1 -Filter "t3_3"` | **4/4 suítes, 23/23 testes aprovados, 433 asserções** (`test_t3_3_ux_display_and_workers.gd`: `2/2`, `9` asserções; `test_t3_3_ux_flow.gd`: `3/3`, `55` asserções; `test_t3_3_construction_logistics.gd`: `11/11`, `205` asserções; `test_t3_3_construction_site.gd`: `7/7`, `164` asserções) |
| Bateria global segmentada | `.\tools\run_tests.ps1 -Segmented` | **7/7 batches PASS, 34/34 suítes (`Discovered=34, ExecutedUnique=34, Duplicates=0, Missing=0`), 234/234 testes aprovados, 7.585 asserções, 0 falhas, 0 erros de suíte** (`SumGodotElapsed: 323746,5 ms`, `TotalWallElapsed: 340459,5 ms`) |
| Higiene de diff | `git diff --check` | Limpo (`exit 0`) |
