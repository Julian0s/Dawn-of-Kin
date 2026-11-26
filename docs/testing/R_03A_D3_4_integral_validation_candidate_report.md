# Dawn of Kin — Relatório Técnico da Candidata `R-03A D3.4`
## Validação Integral e Consolidação Técnica da `D3`

**Data:** 26/11/2026  
**Etapa:** `R-03A D3.4` *(validação segmentada integral e consolidação técnica da série `D3`)*  
**Repositório:** `https://github.com/Julian0s/Dawn-of-Kin`  
**Branch candidata:** `feat/r-03a-community-work-main-scene`  
**Worktree candidato:** `C:\Projetos\Dawn_of_Kin_wt_r_03a`  
**SHA técnico validado (`D3.3-R1` homologado):** `e7d72e41a31861d41747d7d82239b7963626f497`  
**SHA documental publicado (`D3.4`):** registrado em `07_git_final/git_final.txt` *(commit exclusivamente documental de versionamento deste relatório; zero alterações em scripts, cenas, testes, configurações ou comportamento executável)*  
**Base canônica preservada (`develop`):** `21c34ee645725a74f1fefac9db0309ec711ab5f2` *(não alterada)*  
**Linha estável preservada (`main`):** `25e0a20f1d6a2f10a9e059afe69759fbe263db4a` *(não alterada)*  
**Checkout principal preservado:** `C:\Projetos\Dawn of Kin` *(em `develop`, preservando integralmente `M project.godot`, SHA-256 `AEEFDA2810DA5C4EDFA9BF5F2A47A5841F8597238C8DAB4C2E202FAF70307613`)*  
**Godot:** `4.7.2.stable.official.ed1daf0bf`  
**Classificação técnica:** **`VALIDAÇÃO INTEGRAL APROVADA — APTA À HOMOLOGAÇÃO`**  
**Status obrigatório:** **`VALIDADO TECNICAMENTE`** · **`PENDENTE DE AUDITORIA INDEPENDENTE`** · **`NÃO HOMOLOGADO (D3 INTEGRAL)`** · **`NÃO INTEGRADO À DEVELOP`**

> [!IMPORTANT]
> Este relatório consolida a validação técnica integral da `D3` sobre o SHA `e7d72e41a31861d41747d7d82239b7963626f497`. A decisão de homologação definitiva integral da `D3`, bem como qualquer avanço para `D4` ou `R-03B` (que seguem bloqueadas), pertence exclusivamente ao proprietário após auditoria independente.

---

## 1. Diferenciação entre SHA Técnico Validado e SHA Documental

- **SHA técnico validado:** `e7d72e41a31861d41747d7d82239b7963626f497` (`D3.3-R1` homologado). Toda a descoberta de suítes, a campanha segmentada integral de `93` suítes e o smoke funcional foram executados diretamente sobre esse SHA.
- **SHA documental publicado (`D3.4`):** adiciona exclusivamente `docs/testing/R_03A_D3_4_integral_validation_candidate_report.md` (`git diff --name-only e7d72e4..HEAD` contém unicamente este arquivo). Nenhum arquivo em `src/`, `tests/`, `levels/`, `data/`, `assets/`, `tools/` ou `project.godot` foi alterado.

---

## 2. Descoberta Integral e Campanha Segmentada

- **Descoberta (`--discovery-only`):** `93` suítes descobertas (`DiscoveryExitCode = 0`, `Success = True`), confirmando a presença canônica de:
  - `res://tests/unit/test_r_03a_d3_1_tree_harvest.gd` (`D3.1-R1`)
  - `res://tests/integration/test_r_03a_d3_2_tree_gather_orders.gd` (`D3.2`)
  - `res://tests/integration/test_r_03a_d3_3_regional_conservation.gd` (`D3.3` / `D3.3-R1`)
- **Comando executado:**
  ```powershell
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Projetos\Dawn_of_Kin_wt_r_03a\tools\run_tests.ps1" -Segmented -MaxIntegrationPerGroup 1 -GroupTimeoutSeconds 240
  ```
- **Resultado agregado diretamente capturado:**
  - `AGGREGATE_EXIT_CODE = 0` (`exit_code_agregado.txt`)
  - **Lotes:** `66` (`1` lote `unit` com `28` suítes + `65` lotes `integration-01`..`integration-65` com `1` suíte cada; todos os `66` lotes com `PASS` e saída `0`)
  - **Suítes:** `Discovered = 93` · `ExecutedTotal = 93` · `ExecutedUnique = 93` · `Missing = 0` · `Duplicates = 0`
  - **Testes:** `706/706` aprovados (`Failed = 0`, `SuiteErrors = 0`)
  - **Asserções:** `33.845`
  - **Erros, avisos, timeouts e crashes:** `Errors = 0`, `Warnings = 0`, `Timeouts = 0`, `CrashMarkers (-1073741819 / 0xC0000005) = 0`
  - **Duração:** `SumGodotElapsed = 1.503.976,5 ms` (`1.503,98 s`); `TotalWallElapsed = 1.593.066,2 ms` (`1.593,07 s`); duração medida pelo wrapper externo `1.593,954 s`.
- **Nota de transparência (`06_diagnostics/`):** uma tentativa inicial (`task-384`) foi interrompida por reinício do servidor; seu log parcial (`interrupted_run1_regression_full.log`) foi preservado integralmente em `06_diagnostics/` antes da execução completa limpa (`task-390`).

---

## 3. Validação Estática e Smoke Funcional

- **Validação estática (`04_static_validation/static_validation_reuse_record.txt`):** evidência integral reutilizada do SHA técnico idêntico `e7d72e41a31861d41747d7d82239b7963626f497` (`D3.3-R1/03_static/validate_d3_3_r1.log`, `ValidateExitCode = 0`, `219/219` scripts verificados, `0` erros, `0` avisos, `DOCS_DESIGN_IMPORT_COUNT = 0`). Zero alterações em scripts, cenas ou configurações ocorreram na `D3.4`.
- **Smoke funcional (`05_smoke/smoke_headless_main_scene.log`):** inicialização headless da `MainScene` (`--headless --quit-after 3`) concluída com `GodotExitCode = 0`, `HasError = False`, `HasWarning = False`, `Success = True`, `DurationSec = 8.431`. As evidências visuais reais da `D3.2` em `1280×720` e `1920×1080` permanecem aplicáveis sem alteração de produção em `D3.3`/`D3.3-R1`/`D3.4`.

---

## 4. Consolidação das Decisões `D0-A03` e `D0-A04`

### 4.1 `D0-A03` — Derrubada Irreversível e Ciclo Físico de Árvores
- Irreversibilidade econômica e de estágio a partir da entrada em `FELLING`.
- Zero extração de madeira antes de `FALLEN` (validado em `ResourceSource`, `GatherTransferSession` e `GatherResourceOrder`).
- Continuidade autônoma da queda (`FELLING → FALLEN`) mesmo sem trabalhadores ou sem dependência econômica do `Tween` visual.
- Cancelamento pré-queda (`STANDING`/`CHOPPING`) com reset conforme autorização e preservação do congelamento enquanto sustentado por autorização legítima.

### 4.2 `D0-A04` — Conservação Econômica Regional *(homologada pelo proprietário no escopo arquitetural vigente em `D3.3-R1`)*
- Identidade de domínio regional definida por `(World3D, region_id, resource_id)` — nunca apenas por `region_id` textual.
- Conservação exata sobre **8 compartimentos físicos mutuamente exclusivos**: `natural_sources`, `unit_carry_loads`, `camp_storage`, `construction_sites_buffer`, `construction_sites_consumed`, `completed_buildings`, `cancellation_local_buffer` e `cancellation_local_incorporated`.
- Exclusão estrita de espelhos, reservas (`PileReservationLedger`), proveniência (`CarryProvenanceLedger`), recibos e contadores históricos do cálculo de $Q$.
- Perdas legítimas obtidas exclusivamente de registros independentes (`GroundPileManager.get_total_decayed()` e `CancellationCustodyRecord.demolition_loss`), combinadas a deltas locais e transacionais por operação.
- Estabilidade transacional obrigatória (`stable_boundary == true` e explícito em ambos os snapshots) e continuidade da identidade do armazenamento (`domain.storage_instance_id`) exigidas por `RegionalConservationAudit.verify_conservation()`.
- Isolamento regional comprovado entre mundos distintos com mesmo `region_id` e regiões distintas no mesmo `World3D`, preservando integralmente as limitações históricas pré-`T4` (`R01` em `TestMap/ResourceSources` e ausência de compartimento físico separado para pilhas avulsas externas).

---

## 5. Preservação de Aceites Humanos e Pendências

- **21 testes humanos homologados preservados:** `13` da `D2` + `8` da `D3.2` (`HD3-01`–`HD3-08`), sem repetição desnecessária por ausência de alterações jogáveis após `D3.2`.
- **Observação `HD3-06` preservada para `R-03B`:** após concluir uma ordem pessoal de movimento, um trabalhador pode receber outra tarefa comunitária ainda autorizada (exclusão por tarefa); o retorno comunitário com intervalo configurável (`D-05`) e `ControlMode` seguem reservados exclusivamente à `R-03B`.
- **Bloqueios mantidos:** `D4` (homologação humana e consolidação visual/desempenho de `R-03A`), `R-03B`, `R-04A`–`R-04C` e `T4` permanecem bloqueadas até autorização expressa do proprietário.
