# Dawn of Kin

Jogo single-player em 3D isométrico de sobrevivência familiar, construção de assentamento e estratégia em tempo real (RTS), desenvolvido em **Godot 4.7.2** com **GDScript tipado**.

---

## Estado real do projeto (26/11/2026)

| Camada / Marco | Status Real | Referência Git / Evidência |
|---|---|---|
| **T1 — Fundação RTS** | **`HOMOLOGADO` / `INTEGRADO`** | `t1-complete` (`2808799`, na `main`) — 90 testes, 1.607 asserções |
| **T2 — Trabalho e Recursos** | **`HOMOLOGADO` / `INTEGRADO`** (14/11/2026) | `t2-complete` (`f7c2459`, na `main`) — 182/182 testes (27 suítes), 21/21 manuais; benchmark CA `147,33 FPS` (`p95 = 9,757 ms`), DC `55,80 FPS` (`p95 = 33,038 ms`, aceito como limitação conhecida em [docs/KNOWN_ISSUES.md](docs/KNOWN_ISSUES.md)) |
| **T3.1–T3.6.1** | **`HOMOLOGADO` / `INTEGRADO`** | Na `main` (`25e0a20`): `T3.1`–`T3.3` (`t3-3-complete` @ `3c6fc0b`, [T3_3_closeout_ACCEPTANCE.md](docs/testing/T3_3_closeout_ACCEPTANCE.md)), `T3.4` (`2a6cce6`), `T3.5.1` (`56d8e97`), `T3.5.2` (`fb31887`) e `T3.6.1` (`25e0a20`, matemática pura `D3`) |
| **T3.6.2 Bloco A e Design System D2.2** | **`HOMOLOGADO` / `INTEGRADO À DEVELOP`** | `T3.6.2 Bloco A` (`ec17f42`, `use_provenance_economy = true` na linha `develop`) e Design System `D2.2` (`cdd9f2f`, homologado documentalmente) + plano `UI-1.0 R1` (`7dbfeb1`) |
| **UI-1.1A R2, UI-1.1B R1, UI-1.2 e UI-1.3 R1 (`R-01`)** | **`HOMOLOGADO` / `INTEGRADO À DEVELOP`** (23/11/2026) | `fix/ui-1-3-r1-validation-uid` (`c4a6361`, na cadeia linear de `develop`, `+148` commits à frente da `main` antiga): `validate.ps1` `0/0`, `85/85` suítes (`592/592` testes, `28.989` asserções na regressão histórica da R1) e `8/8` itens manuais aprovados em `720p`/`1080p`. `use_d2_2_hud = false` preservado na `MainScene` até `R-05B` |
| **Reconciliação Documental Única (`R-02A R1`)** | **`HOMOLOGADO` / `INTEGRADO À DEVELOP`** (23/11/2026) | `docs/r-02a-canonical-reconciliation` @ `3032f40` (base inicial da `develop`): consolidou GDD `v1.3`, `ROADMAP_MESTRE.md` e reconciliação técnica |
| **Reorganização do Workspace (`R-02B.0`–`R-02B.5`)** | **`HOMOLOGADO` / `INTEGRADO À DEVELOP` / `ENCERRADO`** (24/11/2026) | `develop` @ `21c34ee645725a74f1fefac9db0309ec711ab5f2`: checkout principal único `C:\Projetos\Dawn of Kin`, 22 worktrees redundantes encerrados, backups preservados em `C:\Projetos\Backups\`, prevenção `docs/design/.gdignore` e governança permanente homologadas |
| **R-03A — Trabalho Comunitário Autônomo na `MainScene`** | **`HOMOLOGADO` / `INTEGRADO À DEVELOP` / `ENCERRADO`** *(26/11/2026)* | `develop` (fast-forward via `46ed25a` sobre `7c77e49`): seleção múltipla independente, autorização/cancelamento seletivo, ciclo de derrubada `D3`, precedência pessoal (`D3.2`), conservação `D0-A04`, correção visual `D4-A01`, equivalência `D4-R2`, pós-integração `95/95` suítes (`724/724` testes, `34.029` asserções), `21+5` humanos anteriores + `8/8` finais `M1`–`M8`; limitação `D2-P01` (`1080p` CA `19,879 ms`) aceita em [docs/KNOWN_ISSUES.md](docs/KNOWN_ISSUES.md) §6; relatório em [R_03A_COMMUNITY_WORK_CLOSEOUT_REPORT.md](docs/architecture/R_03A_COMMUNITY_WORK_CLOSEOUT_REPORT.md) |
| **T3.6.4-R1, UX-1, RUX-1, RUX-2A e RUX-2B** | **`NÃO HOMOLOGADO`** | Retestes `D3-04`/`D3-07` pendentes (`T3.6.4-R1` @ `8deeef1`, mantido pela regra de transição `P-REC-1` até `R-04C`); sandboxes `UX-1` (`0e78f9a`) e `RUX-*` (`cddd582`) mantidos apenas como referência histórica de sandbox |
| **Branch `main` (linha estável)** | **`25e0a20`** *(não promovida automaticamente)* | Preservada como linha estável até autorização específica de promoção pelo proprietário |

- **Renderizador configurado:** `gl_compatibility`
- **Motor de física 3D:** `Jolt Physics`
- **Estado atual do próximo passo:** **`R-03A`** definitivamente homologada em `26/11/2026` (SHA técnico `7c77e49d491f70c1867254f1a76a023050815431`, integrada em fast-forward à `develop` e validada pós-integração com worktree candidato encerrado); a próxima etapa planejada é **`R-03B` — Casa Fundadora e `ControlMode` na `MainScene`**, que permanece **`PLANEJADA — NÃO AUTORIZADA`** até decisão expressa do proprietário.

---

## Topologia Git e Organização do Workspace

- **Checkout principal único:** `C:\Projetos\Dawn of Kin` (utilizando a branch canônica de desenvolvimento **`develop`**).
- **Linha estável (`main`):** preservada separadamente em `25e0a20` e promovida apenas mediante autorização expressa do proprietário.
- **Worktrees auxiliares:** regra permanente de no máximo **1 checkout principal + 1 worktree temporário ativo** por incremento quando necessário (sem acumular worktrees encerrados).
- **Backups e históricos:** mantidos exclusivamente fora do checkout principal (`C:\Projetos\Backups\`).
- **Prevenção de resíduos de documentação:** `docs/design/.gdignore` impede a geração de arquivos `.import`/UIDs nas pranchas visuais documentais sem bloquear leitura direta por `FileAccess` nos testes unitários.

---

## Documentação normativa

1. **[AGENTS.md](AGENTS.md)** — Regras permanentes de engenharia, política Git, ciclo obrigatório de desenvolvimento, organização do workspace e governança de colaboração.
2. **[docs/Dawn_of_Kin_GDD.md](docs/Dawn_of_Kin_GDD.md)** — Game Design Document consolidado único (`v1.3` homologada).
3. **[docs/ROADMAP_MESTRE.md](docs/ROADMAP_MESTRE.md)** — Roadmap Mestre único (`R-01`–`T3.9` + horizonte `T4`–`T8`), estados reais e Matriz de Decisões/Rastreabilidade (`D1`–`D9`, `DEC-01`–`DEC-19`, `D-01`–`D-13`, `P-REC-1`–`P-REC-4`, `D-ERR-1 B`, `D-ERR-2 C`, `DT-01`–`DT-06`, `R02B-D1`–`R02B-D11`).
4. **[docs/design/DAWN_OF_KIN_VISUAL_DESIGN_SYSTEM.md](docs/design/DAWN_OF_KIN_VISUAL_DESIGN_SYSTEM.md)** — Design System Mestre **D2.2 ("Marcos de Pedra e Eclipse")** e Visual Consistency Gate (VCG).
5. **[docs/architecture/UI_1_0_R1_INTEGRATION_PLAN.md](docs/architecture/UI_1_0_R1_INTEGRATION_PLAN.md)** — Plano técnico de integração da série `UI-1` e Adendo `R-02A R1`.
6. **[docs/architecture/R_02B_WORKSPACE_CONSOLIDATION_REPORT.md](docs/architecture/R_02B_WORKSPACE_CONSOLIDATION_REPORT.md)** — Registro técnico do encerramento da reorganização `R-02B`.
7. **[docs/KNOWN_ISSUES.md](docs/KNOWN_ISSUES.md)** — Limitações medidas e pendências conhecidas.

---

## Diferença entre a `MainScene` e os sandboxes visuais

É fundamental não confundir o jogo principal com as cenas de avaliação isoladas:

- **`MainScene` (`res://src/main/main.tscn` — executada por `F5` ou `.\tools\run_game.ps1`):**
  - É a cena principal do jogo.
  - Por decisão deliberada e preservada na `UI-1.3 R1`, `main.tscn` mantém **`use_d2_2_hud = false`** (HUD legada ativa) até a etapa autorizada **`R-05B`** (`D-ERR-1 B`), após a homologação da `UI-1.4`.
  - Os controles de trabalho comunitário autônomo (`R-03A`: seleção múltipla independente de fontes, autorização/cancelamento seletivo na HUD contextual, derrubada progressiva `D3`, precedência pessoal por tarefa e recuperação no cancelamento) encontram-se **`HOMOLOGADOS DEFINITIVAMENTE`** (`7c77e49`, `8/8` cenários humanos finais `M1`–`M8` aprovados em `26/11/2026`) e ativos na `MainScene` (`use_provenance_economy = true`, `automatic_cancellation_recovery = true`, `use_d2_2_hud = false`); os controles de `R-03B`–`R-03D` e a nova construção com débito imediato (`D-01`/`D-02`, `R-04A`–`R-04C`) **ainda não foram implementados nem autorizados**.
- **Sandbox visual da `UI-1.3 R1` (`res://tests/visual/ui_1_d2_2_sandbox.tscn`):**
  - Instancia a `MainScene` com **`use_d2_2_hud = true`**, exibindo a HUD D2.2 homologada até `UI-1.3 R1`: pedras de recursos escalonadas, placa superior com pausa real (`||`/`1×`), estelas dos fundadores, lajes de ação, mesa retrátil de maquetes (`[B]`, `[1]`, `[2]`) e faixa `D2PlacementStatusBar` no centro superior.
- **Sandboxes históricos não homologados (`tests/visual/ux_1_*.tscn`, `rux_*.tscn`):**
  - Cenas técnicas intermediárias de prototipação (`UX-1`, `RUX-1`, `RUX-2A`, `RUX-2B`). Não representam funcionalidades homologadas na `MainScene`.

---

## Requisitos de ambiente

- **Godot Engine:** `4.7.2.stable.official` (Windows 64-bit).
- Se o executável não estiver no `PATH`, defina a variável de ambiente `GODOT_BIN` apontando para `Godot_v4.7.2-stable_win64.exe`, ou utilize os scripts em `tools/`.
- **Git:** 2.50+.

---

## Como executar, validar e testar

No PowerShell, a partir da raiz `C:\Projetos\Dawn of Kin` (na branch `develop`):

```powershell
# 1. Validar importação headless, checagem estática (--check-only) e startup da cena principal
.\tools\validate.ps1

# 2. Executar a suíte completa de regressão de forma confiável em lotes segmentados
.\tools\run_tests.ps1 -Segmented -MaxIntegrationPerGroup 1

# 2b. Executar apenas um subconjunto focado de testes
.\tools\run_tests.ps1 -Filter "tests/unit"

# 3. Executar o jogo principal (MainScene, use_d2_2_hud = false; 1280x720 por padrão)
.\tools\run_game.ps1
.\tools\run_game.ps1 -Resolution "1920x1080"

# 4. Abrir o sandbox visual homologado da UI-1.3 R1 (HUD D2.2 ativa) na Godot 4.7.2
#    Cena: res://tests/visual/ui_1_d2_2_sandbox.tscn
& $env:GODOT_BIN --path . --resolution 1280x720 res://tests/visual/ui_1_d2_2_sandbox.tscn
& $env:GODOT_BIN --path . --resolution 1920x1080 res://tests/visual/ui_1_d2_2_sandbox.tscn

# 5. Executar benchmark de desempenho (Intel UHD Graphics 620, 1920x1080)
.\tools\perf.ps1 -Mode t2
.\tools\perf.ps1 -Mode all
```

---

## Estrutura de pastas

```text
Dawn of Kin/
├─ project.godot                       # Configuração da engine, camadas 3D, InputMap e avisos GDScript
├─ AGENTS.md                           # Regras permanentes de engenharia, Git, ciclo e governança
├─ README.md                           # Este arquivo
├─ assets/                             # Assets runtime (inclui res://assets/ui/d2/ da UI-1.1A)
├─ data/                               # Recursos .tres (personagens, recursos econômicos, edifícios)
├─ docs/
│  ├─ Dawn_of_Kin_GDD.md               # GDD único consolidado (v1.3 homologada)
│  ├─ ROADMAP_MESTRE.md                # Roadmap Mestre único e Matriz de Decisões/Rastreabilidade
│  ├─ KNOWN_ISSUES.md                  # Limitações medidas e pendências reais
│  ├─ architecture/                    # Planos técnicos (UI-1.0 R1, R-02B + históricos T1/T3/UX/RUX)
│  ├─ design/                          # Design System Mestre D2.2 e referências visuais (.gdignore)
│  ├─ audits/                          # Auditorias históricas e matrizes de consolidação
│  ├─ reviews/                         # Dossiês e registros de aceite
│  └─ testing/                         # Protocolos manuais, aceites e relatórios de candidatas
├─ levels/test_map/                    # Mapa demonstrativo (`TestMap`, 64×64 m)
├─ src/                                # Código-fonte (buildings, camera, core, economy, main, navigation, rts, ui, units)
├─ tests/
│  ├─ unit/                            # Testes unitários puros
│  ├─ integration/                     # Testes de integração com física e navegação reais
│  ├─ perf/                            # Benchmarks em janela, análise RVO e estresse
│  └─ visual/                          # Cenas visuais (inclui ui_1_d2_2_sandbox.tscn)
└─ tools/                              # Scripts PowerShell (validate, run_tests, run_game, perf)
```

---

## Protocolo de contribuição e convenções

- Todo incremento parte da ponta homologada de `develop`, segue o **Ciclo Obrigatório de Desenvolvimento (20 etapas)** e o **Checklist de Encerramento (18 itens)** definidos em [AGENTS.md](AGENTS.md), com um único incremento ativo por vez e integração obrigatória à `develop` após homologação.
- Código-fonte, identificadores, nós, cenas e comentários técnicos em **inglês**; documentação, protocolos de teste e relatórios de progresso em **português**.
- Qualquer aviso (`WARNING`) ou erro (`ERROR` / `SCRIPT ERROR`) emitido pela Godot durante validação é tratado como falha bloqueante.
