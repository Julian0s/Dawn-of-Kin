# Dawn of Kin

Jogo single-player em 3D isométrico de sobrevivência familiar, construção de assentamento e estratégia em tempo real (RTS), desenvolvido em **Godot 4.7.2** com **GDScript tipado**.

---

## Estado real do projeto (23/11/2026)

| Camada / Marco | Status Real | Referência Git / Evidência |
|---|---|---|
| **T1 — Fundação RTS** | **`HOMOLOGADO` / `INTEGRADO`** | `t1-complete` (`2808799`, na `main`) — 90 testes, 1.607 asserções |
| **T2 — Trabalho e Recursos** | **`HOMOLOGADO` / `INTEGRADO`** (14/11/2026) | `t2-complete` (`f7c2459`, na `main`) — 182/182 testes (27 suítes), 21/21 manuais; benchmark CA `147,33 FPS` (`p95 = 9,757 ms`), DC `55,80 FPS` (`p95 = 33,038 ms`, aceito como limitação conhecida em [docs/KNOWN_ISSUES.md](docs/KNOWN_ISSUES.md)) |
| **T3.1–T3.6.1** | **`HOMOLOGADO` / `INTEGRADO`** | Na `main` (`25e0a20`): `T3.1`–`T3.3` (`t3-3-complete` @ `3c6fc0b`, [T3_3_closeout_ACCEPTANCE.md](docs/testing/T3_3_closeout_ACCEPTANCE.md)), `T3.4` (`2a6cce6`), `T3.5.1` (`56d8e97`), `T3.5.2` (`fb31887`) e `T3.6.1` (`25e0a20`, matemática pura `D3`) |
| **T3.6.2 Bloco A e Design System D2.2** | **`HOMOLOGADO` *(não integrados à `main`)*** | `T3.6.2 Bloco A` (`ec17f42`, `use_provenance_economy = true` na linha `c4a6361`) e Design System `D2.2` (`cdd9f2f`, homologado documentalmente) + plano `UI-1.0 R1` (`7dbfeb1`) |
| **UI-1.1A R2, UI-1.1B R1, UI-1.2 e UI-1.3 R1 (`R-01`)** | **`HOMOLOGADO` *(não integradas à `main`)*** (23/11/2026) | `fix/ui-1-3-r1-validation-uid` (`c4a6361919564fca59ddbad3362468a0c1b1708e`, `+148` commits à frente da `main`): `validate.ps1` com `0` erros / `0` avisos (`208` scripts), `85/85` suítes (`592/592` testes, `28.989` asserções na regressão histórica da R1) e `8/8` itens manuais aprovados em `1280×720` e `1920×1080` |
| **Reconciliação Documental Única (`R-02A R1`)** | **Candidata documental em revisão** | Branch isolada `docs/r-02a-canonical-reconciliation` (base `c4a6361`), aguardando auditoria independente e aceite expresso do proprietário |
| **T3.6.4-R1, UX-1, RUX-1, RUX-2A e RUX-2B** | **`NÃO HOMOLOGADO`** | Retestes `D3-04`/`D3-07` pendentes (`T3.6.4-R1` @ `8deeef1`, mantido pela regra de transição `P-REC-1` até `R-04C`); sandboxes `UX-1` (`0e78f9a`) e `RUX-*` (`cddd582`) aguardam integração jogável na `MainScene` em `R-03A`–`R-03D` |
| **Branch `main` e checkout `C:\Projetos\Dawn of Kin`** | **Ainda não atualizados** | A `main` permanece em `25e0a20` e o diretório principal local em `7293908` (com alterações locais preservadas). Organização dos worktrees e preparação da `main` ocorrerão **somente na próxima etapa planejada: `R-02B`**, após autorização expressa |

- **Renderizador configurado:** `gl_compatibility`
- **Motor de física 3D:** `Jolt Physics`
- **Próxima etapa planejada (após homologação da `R-02A`):** **`R-02B`** — Preservação de alterações locais/históricos, organização controlada dos worktrees e preparação segura da `main` (ver [docs/ROADMAP_MESTRE.md](docs/ROADMAP_MESTRE.md)).

---

## Documentação canônica

1. **[docs/Dawn_of_Kin_GDD.md](docs/Dawn_of_Kin_GDD.md)** — Game Design Document consolidado único (candidata `v1.3` da `R-02A R1`).
2. **[docs/ROADMAP_MESTRE.md](docs/ROADMAP_MESTRE.md)** — Roadmap Mestre único (`R-01`–`T3.9` + horizonte `T4`–`T8`), topologia Git e Matriz de Decisões e Rastreabilidade (`D1`–`D9`, `DEC-01`–`DEC-19`, `D-01`–`D-13`, `P-REC-1`–`P-REC-4`, `D-ERR-1 B`, `D-ERR-2 C`, `DT-01`–`DT-06`).
3. **[docs/design/DAWN_OF_KIN_VISUAL_DESIGN_SYSTEM.md](docs/design/DAWN_OF_KIN_VISUAL_DESIGN_SYSTEM.md)** — Design System Mestre **D2.2 ("Marcos de Pedra e Eclipse")** e Visual Consistency Gate (VCG).
4. **[docs/architecture/UI_1_0_R1_INTEGRATION_PLAN.md](docs/architecture/UI_1_0_R1_INTEGRATION_PLAN.md)** — Plano técnico de integração da série `UI-1` e Adendo `R-02A R1`.
5. **[AGENTS.md](AGENTS.md)** — Regras permanentes de engenharia, taxonomia de status e governança de colaboração.
6. **[docs/KNOWN_ISSUES.md](docs/KNOWN_ISSUES.md)** — Limitações medidas e pendências conhecidas.

---

## Diferença entre a `MainScene` e os sandboxes visuais

É fundamental não confundir o jogo principal com as cenas de avaliação isoladas:

- **`MainScene` (`res://src/main/main.tscn` — executada por `F5` ou `.\tools\run_game.ps1`):**
  - É a cena principal do jogo.
  - Por decisão deliberada e preservada na `UI-1.3 R1`, `main.tscn` mantém **`use_d2_2_hud = false`** (HUD legada ativa) até a etapa autorizada **`R-05B`** (`D-ERR-1 B`), após a homologação da `UI-1.4`.
  - Os controles de trabalho comunitário autônomo (`RUX-*`) e a nova construção com débito imediato (`D-01`/`D-02`) **ainda não foram integrados à `MainScene`** — entrarão de forma jogável e verificável respectivamente em `R-03A`–`R-03D` e `R-04A`–`R-04C`.
- **Sandbox visual da `UI-1.3 R1` (`res://tests/visual/ui_1_d2_2_sandbox.tscn`):**
  - Instancia a `MainScene` com **`use_d2_2_hud = true`**, exibindo a HUD D2.2 homologada até `UI-1.3 R1`: pedras de recursos escalonadas, placa superior com pausa real (`||`/`1×`), estelas dos fundadores, lajes de ação, mesa retrátil de maquetes (`[B]`, `[1]`, `[2]`) e faixa `D2PlacementStatusBar` no centro superior.
- **Sandboxes históricos não homologados (`tests/visual/ux_1_*.tscn`, `rux_*.tscn`):**
  - Cenas técnicas intermediárias de prototipação (`UX-1`, `RUX-1`, `RUX-2A`, `RUX-2B`). Não representam funcionalidades homologadas na `MainScene`.

---

## Requisitos de ambiente

- **Godot Engine:** `4.7.2.stable.official` (Windows 64-bit).
- Se o executável não estiver no `PATH`, defina a variável de ambiente `GODOT_BIN` apontando para `Godot_v4.7.2-stable_win64.exe`, ou utilize os scripts em `tools/`.
- **Git:** 2.55+.

---

## Como executar, validar e testar

No PowerShell, a partir da raiz do worktree/checkout desejado:

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
├─ AGENTS.md                           # Regras permanentes de engenharia e governança
├─ README.md                           # Este arquivo
├─ assets/                             # Assets runtime (inclui res://assets/ui/d2/ da UI-1.1A)
├─ data/                               # Recursos .tres (personagens, recursos econômicos, edifícios)
├─ docs/
│  ├─ Dawn_of_Kin_GDD.md               # GDD único consolidado (v1.3 candidata R-02A)
│  ├─ ROADMAP_MESTRE.md                # Roadmap Mestre único e Matriz de Decisões/Rastreabilidade
│  ├─ KNOWN_ISSUES.md                  # Limitações medidas e pendências reais
│  ├─ architecture/                    # Planos técnicos (UI-1.0 R1 + históricos T1/T3/UX/RUX com adendos)
│  ├─ design/                          # Design System Mestre D2.2 e referências visuais congeladas
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

## Convenções do projeto

- Código-fonte, identificadores, nós, cenas e comentários técnicos em **inglês**.
- Documentação, protocolos de teste e relatórios de progresso em **português**.
- Qualquer aviso (`WARNING`) ou erro (`ERROR` / `SCRIPT ERROR`) emitido pela Godot durante validação é tratado como falha bloqueante.
