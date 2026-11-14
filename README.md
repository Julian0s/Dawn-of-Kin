# Dawn of Kin

Jogo single-player em 3D isométrico de sobrevivência familiar, construção de assentamento e estratégia em tempo real (RTS), desenvolvido em **Godot 4.7.2** com **GDScript**.

## Estado atual

- **Marco ativo:** T2 — Trabalho e Recursos (**Candidata a Encerramento na branch `review/t2-closeout-candidate`**; implementada, validada automaticamente, com testes manuais A1–F2 relatados como aprovados pelo proprietário e aguardando aceite formal definitivo)
  - **Implementado e aprovado manualmente em etapas parciais (`T2.0`–`T2.5.1`):**
    - `T2.0` / `T2.0.1`: definições de recursos, pesos (`madeira=2`, `pedra=3`, `alimentos=1`), `UnitCarryLoad`, `SettlementInventory` e atomicidade contra perda/duplicação.
    - `T2.1`: `CampStorageZone`, `GroundResourcePile`, `GroundPileManager`, pilhas físicas individuais e deterioração centralizada por `EconomyClockController`.
    - `T2.2` / `T2.2.1`: fontes coletáveis (`wood_tree`, `stone_rock`, `food_bush`), `WorldPicker`/`PickResult` com oclusão e rebake de `WorldNavigation`.
    - `T2.3` / `T2.3.1`: `GatherResourceOrder`, `DeliverToCampOrder`, retorno automático com carga cheia ou esgotamento, liberação de vaga durante transporte e concorrência simultânea dos dois trabalhadores.
    - `T2.4` / `T2.4.1` / `T2.4.2` / `T2.4.3`: composição jogável no `TestMap`/`MainScene`, tempos distintos de coleta (`1,5 s` alimentos, `2,5 s` madeira, `3,5 s` pedra), redução progressiva de velocidade proporcional ao peso e estados naturais das fontes.
    - `T2.5` / `T2.5.1`: HUD não bloqueante (`ResourceHud`, `SettlementStockpilePanel`, `SelectedUnitPanel`) distinguindo `Peso transportado: X / Y`, porcentagem por peso e quantidades individuais (`Madeira: X un`, `Pedra: X un`, `Alimentos: X un`).
  - **Implementado na `T2.6` e ajuste `B1`:**
    - Correção de corrida de sincronização de `WorldNavigation` pós-rebake entre cenas no mesmo processo e ajuste de amostragem de tween em testes.
    - **Ajuste B1:** velocidade-base de deslocamento sem carga unificada em `4,8 m/s` tanto na marcha livre quanto na aproximação para coletar recursos (`GatherResourceOrder`), com a redução de velocidade incidindo estritamente sobre a carga física transportada (`2,88 m/s` a 100% de carga; recuperação imediata a `4,8 m/s` pós-descarga no acampamento).
    - Suíte automatizada validada: **182/182 testes verdes em 27 suítes (6.469 asserções) com zero erros e zero avisos** via `.\tools\run_tests.ps1 -Segmented`.
  - **Desempenho medido em `1920x1080` (Intel UHD Graphics 620, `gl_compatibility`, VSync OFF):**
    - **Tomada CA (B1.1):** mediana de `147,33 FPS` (`p50 = 6,608 ms`, `p95 = 9,757 ms`, `p99 = 11,679 ms`, pior max `25,258 ms`, `0` quadros `> 100 ms`) — **APROVADO com folga de 6,943 ms**.
    - **Bateria DC (B1):** mediana de `55,80 FPS` (`p50 = 14,872 ms`, `p95 = 33,038 ms`, `0` quadros `> 100 ms`) — registrado como limitação física de consumo energético do hardware sob bateria, com `0` travamentos.
    - *Nota de integridade:* A diferença de energia não possui comprovação física definitiva sem amostragem síncrona de temperatura/clock; a aprovação em CA não atesta conformidade universal em qualquer modo de bateria DC.
  - **Testes manuais (informados pelo proprietário em 14/11/2026):**
    - Todos os 21 itens do protocolo `docs/testing/T2_manual_test_protocol.md` (A1–F2) foram executados e relatados como aprovados pelo proprietário.
    - O item B1 (velocidade de coleta) recebeu apontamento inicial, foi corrigido no commit `8f53a3f`, retestado pelo proprietário e expressamente confirmado ("testei esta correto").
  - **Situação para encerramento:** Branch candidata `review/t2-closeout-candidate` consolidada; aguardando autorização expressa do proprietário para o aceite formal definitivo da T2.
- **Marco anterior:** T1 — Fundação RTS (**encerrada e aprovada**, registrada no commit `2808799` e tag anotada `t1-complete` com 90 testes aprovados e 1.607 asserções)
- **Renderizador configurado:** `gl_compatibility`
- **Motor de física 3D:** `Jolt Physics`

### Pendências conhecidas e limites provisórios

- Limitação de desempenho da Intel UHD 620 operando sob bateria DC (`p95 = 33,038 ms` vs meta formal `p95 <= 16,7 ms` atendida em CA com `9,757 ms`; `docs/KNOWN_ISSUES.md`).
- Itens visuais provisórios declarados em T2.4.3 (oscilação simples no feedback de coleta e pilhas geométricas provisórias; sem bloqueio funcional para a T2).
- Decisão de arquitetura para a T3 sobre o conceito de "abrigo concluído e persistido" antes do save/load em disco na T4.

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
