# Dawn of Kin

Jogo single-player em 3D isométrico de sobrevivência familiar, construção de assentamento e estratégia em tempo real (RTS), desenvolvido em **Godot 4.7.2** com **GDScript**.

## Estado atual

- **Marco ativo:** T2 — Trabalho e Recursos (**em implementação incremental; T2 completa ainda não concluída nem aprovada**)
  - **Concluídas em código e testadas automaticamente (headless):** `T2.0` (dados econômicos, pesos, carga e atomicidade), `T2.1` (pilhas físicas no acampamento e deterioração centralizada), `T2.2` (fontes naturais coletáveis e picking contextual), `T2.3` (ciclo do trabalhador: coleta, transporte físico, retorno automático ao acampamento, descarga e concorrência) e `T2.4` (composição jogável no `TestMap`/`MainScene`, `EconomyClockController` centralizado, `DecayProfile` provisórios e ocultação visual de ferramentas iniciais nos protagonistas).
  - **Não implementadas:** `T2.5` (HUD) e `T2.6` (validação global e aceite).
  - **Não verificado / pendente:** testes visuais/interativos manuais em janela gráfica e benchmark final da T2 na Intel UHD 620 (`run_game.ps1` validou apenas abertura sem warnings/erros em 90 frames).
- **Marco anterior:** T1 — Fundação RTS (**encerrada e aprovada**, registrada no commit `2808799` e tag anotada `t1-complete` com 90 testes aprovados e 1.607 asserções)
- **Renderizador configurado:** `gl_compatibility`
- **Motor de física 3D:** `Jolt Physics`

### Pendências conhecidas para `T2.5`–`T2.6`

- Atualização do HUD (`T2.5`).
- Teste interativo manual em janela gráfica e benchmark gráfico final na Intel UHD 620 (`T2.6`).

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
│  └─ testing/T1_manual_test_protocol.md # Protocolo de validação manual pelo usuário
├─ levels/test_map/                    # Mapa demonstrativo da T1
├─ src/                                # Código-fonte do jogo (câmera, RTS, unidades, navegação, UI)
├─ tests/
│  ├─ unit/                            # Testes unitários puros
│  ├─ integration/                     # Testes de integração com física e navegação reais
│  ├─ perf/                            # Benchmarks em janela, análise RVO e teste de estresse
│  └─ visual/                          # Cenários visuais e diagnósticos reprodutíveis
└─ tools/                              # Scripts PowerShell (validate, run_tests, run_game, perf)
```

## Como executar, validar e testar

No PowerShell, a partir da raiz do projeto (`C:\Projetos\Dawn of Kin`):

```powershell
# 1. Validar importação headless, checagem estática (--check-only) e startup da cena principal
.\tools\validate.ps1

# 2. Executar toda a suíte automatizada de testes unitários e de integração
.\tools\run_tests.ps1

# 3. Executar o jogo em janela (1280x720 por padrão; ou passe -Resolution "1920x1080")
.\tools\run_game.ps1

# 4. Executar benchmark de desempenho T1.10 (3 resoluções x 3 runs, RVO breakdown e estresse)
.\tools\perf.ps1 -Mode all
```

## Convenções do projeto

- Código-fonte, identificadores, nós, cenas e comentários técnicos em **inglês**.
- Documentação, protocolos de teste e relatórios de progresso em **português**.
- Qualquer aviso (`WARNING`) ou erro (`ERROR` / `SCRIPT ERROR`) emitido pela Godot durante validação é tratado como falha bloqueante.
