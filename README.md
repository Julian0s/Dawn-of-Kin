# Dawn of Kin

Jogo single-player em 3D isométrico de sobrevivência familiar, construção de assentamento e estratégia em tempo real (RTS), desenvolvido em **Godot 4.7.2** com **GDScript**.

## Estado atual

- **Marco ativo:** T2 — Trabalho e Recursos (**preparada tecnicamente para encerramento em T2.6; aguardando aceite manual final do proprietário antes de declarar T2 concluída**)
  - **Implementado e aprovado manualmente em etapas parciais (`T2.0`–`T2.5.1`):**
    - `T2.0` / `T2.0.1`: definições de recursos, pesos (`madeira=2`, `pedra=3`, `alimentos=1`), `UnitCarryLoad`, `SettlementInventory` e atomicidade contra perda/duplicação.
    - `T2.1`: `CampStorageZone`, `GroundResourcePile`, `GroundPileManager`, pilhas físicas individuais e deterioração centralizada por `EconomyClockController`.
    - `T2.2` / `T2.2.1`: fontes coletáveis (`wood_tree`, `stone_rock`, `food_bush`), `WorldPicker`/`PickResult` com oclusão e rebake de `WorldNavigation`.
    - `T2.3` / `T2.3.1`: `GatherResourceOrder`, `DeliverToCampOrder`, retorno automático com carga cheia ou esgotamento, liberação de vaga durante transporte e concorrência simultânea dos dois trabalhadores.
    - `T2.4` / `T2.4.1` / `T2.4.2` / `T2.4.3`: composição jogável no `TestMap`/`MainScene`, tempos distintos de coleta (`1,5 s` alimentos, `2,5 s` madeira, `3,5 s` pedra), redução progressiva de velocidade proporcional ao peso e estados naturais das fontes.
    - `T2.5` / `T2.5.1`: HUD não bloqueante (`ResourceHud`, `SettlementStockpilePanel`, `SelectedUnitPanel`) distinguindo `Peso transportado: X / Y`, porcentagem por peso e quantidades individuais (`Madeira: X un`, `Pedra: X un`, `Alimentos: X un`).
  - **Implementado na `T2.6` (validação global e benchmark):** correção de corrida de sincronização de `WorldNavigation` pós-rebake entre cenas no mesmo processo, correção da janela de amostragem do tween em `test_t2_pace_and_load.gd`, executor segmentado verificável (`.\tools\run_tests.ps1 -Segmented`), benchmark representativo (`tests/perf/t2_perf_benchmark.gd` / `.\tools\perf.ps1 -Mode t2`), cenário dedicado de deterioração (`tests/visual/scenario_t2_decay.gd`) e protocolo manual (`docs/testing/T2_manual_test_protocol.md`).
  - **Medido em benchmark (`gl_compatibility`, `VSYNC_DISABLED`, Intel UHD Graphics 620, plano `Equilibrado`, bateria 37–38% em carga):** `0` quadros `> 100 ms`; `1920x1080` T2 obteve mediana `53,96 FPS` (`p50 = 14,910 ms`, `p95 = 33,766 ms`), praticamente idêntica à referência T1 medida na mesma sessão (`54,78 FPS`, `p50 = 13,113 ms`, `p95 = 35,435 ms`), portanto **acima da meta formal `p95 <= 16,7 ms`** nessas condições de energia/hardware (detalhes em `docs/KNOWN_ISSUES.md`).
  - **Pendente para encerramento da T2:** execução e assinatura manual completa do protocolo `docs/testing/T2_manual_test_protocol.md` pelo proprietário.
- **Marco anterior:** T1 — Fundação RTS (**encerrada e aprovada**, registrada no commit `2808799` e tag anotada `t1-complete` com 90 testes aprovados e 1.607 asserções)
- **Renderizador configurado:** `gl_compatibility`
- **Motor de física 3D:** `Jolt Physics`

### Pendências conhecidas pós-T2.6

- Execução manual integral de `docs/testing/T2_manual_test_protocol.md` em `1280x720` e `1920x1080` (incluindo `tests/visual/scenario_t2_decay.gd`).
- Investigação da folga de `p95 <= 16,7 ms` em `1920x1080` na Intel UHD 620 / perfil de energia em bateria (`docs/KNOWN_ISSUES.md`).
- Itens visuais provisórios declarados em T2.4.3 (oscilação simples na coleta e pilhas geométricas provisórias; sem bloqueio funcional para T2).

## Requisitos de ambiente

- **Godot Engine:** `4.7.2.stable.official` (Windows 64-bit).
- Se o executável não estiver no `PATH`, defina a variável de ambiente `GODOT_BIN` apontando para o executável da Godot, ou utilize os scripts em `tools/`.
- **Git:** 2.55+.

## Estrutura de pastas

```text
Dawn of Kin/
├─ project.godot                       # Configuração da engine, camadas 3D, InputMap e avisos GDScript
├─ AGENTS.md                           # Regras permanentes de engenharia
├─ README.md                           # Este arquivo
├─ docs/
│  ├─ Dawn_of_Kin_GDD_v1.0.md          # Game Design Document (fonte de verdade)
│  ├─ T1_Implementation_Plan.md        # Plano técnico da T1 e critérios AC-01..AC-16
│  ├─ KNOWN_ISSUES.md                  # Limitações e pendências reais medidas
│  ├─ architecture/T1_architecture.md  # Arquitetura consolidada da T1
│  └─ testing/
│     ├─ T1_manual_test_protocol.md   # Protocolo de validação manual da T1
│     └─ T2_manual_test_protocol.md   # Protocolo de validação manual da T2 (pendente)
├─ levels/test_map/                    # Mapa demonstrativo da T1
├─ src/                                # Código-fonte do jogo (câmera, RTS, unidades, navegação, UI)
├─ tests/
│  ├─ unit/                            # Testes unitários puros
│  ├─ integration/                     # Testes de integração com física e navegação reais
│  ├─ perf/                            # Benchmarks em janela (T1 e T2), análise RVO e estresse
│  └─ visual/                          # Cenários visuais e diagnósticos (inclui scenario_t2_decay.gd)
└─ tools/                              # Scripts PowerShell (validate, run_tests, run_game, perf)
```

## Como executar, validar e testar

No PowerShell, a partir da raiz do projeto (`C:\Projetos\Dawn of Kin`):

```powershell
# 1. Validar importação headless, checagem estática (--check-only) e startup da cena principal
.\tools\validate.ps1

# 2. Executar a suíte completa de forma confiável em lotes disjuntos (evita timeout de 240s em processo único)
.\tools\run_tests.ps1 -Segmented

# 2b. Ou executar em processo único (excede 240s na suíte combinada completa; use -Filter para focar)
.\tools\run_tests.ps1 -Filter "tests/unit"

# 3. Executar o jogo em janela (1280x720 por padrão; ou passe -Resolution "1920x1080")
.\tools\run_game.ps1

# 3b. Observar deterioração centralizada em poucos segundos sem alterar o jogo padrão
.\tools\run_game.ps1 -Resolution "1280x720" -ExtraArgs "--script","res://tests/visual/scenario_t2_decay.gd" -FailOnWarnings

# 4. Executar benchmark T1 ou benchmark representativo T2 na Intel UHD 620
.\tools\perf.ps1 -Mode t2
.\tools\perf.ps1 -Mode all
```

## Convenções do projeto

- Código-fonte, identificadores, nós, cenas e comentários técnicos em **inglês**.
- Documentação, protocolos de teste e relatórios de progresso em **português**.
- Qualquer aviso (`WARNING`) ou erro (`ERROR` / `SCRIPT ERROR`) emitido pela Godot durante validação é tratado como falha bloqueante.
