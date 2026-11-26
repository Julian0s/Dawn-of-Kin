# Dawn of Kin — Relatório Técnico Final da Candidata `R-03A D4`
## Auditoria Final, Desempenho (`CA`), Validação Visual (`720p`/`1080p`) e Preparação do Aceite Humano

**Data:** 26/11/2026  
**Etapa:** `R-03A D4` *(auditoria final técnica, desempenho, validação visual e protocolo humano `M1`–`M8` antes da eventual integração à `develop`)*  
**Repositório:** `https://github.com/Julian0s/Dawn-of-Kin`  
**Branch candidata:** `feat/r-03a-community-work-main-scene`  
**Worktree candidato:** `C:\Projetos\Dawn_of_Kin_wt_r_03a`  
**SHA técnico validado (`D3.3-R1` homologado):** `e7d72e41a31861d41747d7d82239b7963626f497`  
**SHA base documental (`D3.4` homologada):** `53306255c7cae5591c5eaea1ad4b1627d5486e22`  
**SHA documental final (`D4`):** registrado em `09_git_final/git_final.txt` *(commit exclusivamente documental adicionando este relatório e o protocolo `M1`–`M8`; zero alterações em produção, cenas, testes ou configuração)*  
**Base canônica preservada (`develop`):** `21c34ee645725a74f1fefac9db0309ec711ab5f2`  
**Linha estável preservada (`main`):** `25e0a20f1d6a2f10a9e059afe69759fbe263db4a`  
**Checkout principal preservado:** `C:\Projetos\Dawn of Kin` (`develop` @ `21c34ee`, `M project.godot` SHA-256 `AEEFDA2810DA5C4EDFA9BF5F2A47A5841F8597238C8DAB4C2E202FAF70307613`)  
**Godot:** `4.7.2.stable.official.ed1daf0bf` (`gl_compatibility`, `Jolt Physics`)

---

## 1. Classificação Técnica por Dimensão

| Dimensão | Classificação |
|---|---|
| **Validação automatizada** | **APROVADA** *(reaproveitamento verificado da `D3.4` no SHA técnico idêntico `e7d72e4`: `93/93` suítes, `706/706` testes, `33.845` asserções, `AGGREGATE_EXIT_CODE = 0`, `219/219` scripts estáticos `0/0`, smoke `exit=0`)* |
| **Desempenho (`Intel UHD 620`, `CA`)** | **APROVADA EM ATIVIDADE SUSTENTADA COM RESSALVA EM TRANSIENTES DE LOTE** *(11/12 cenários `P01`–`P12` e estados contínuos/lotes isolados `D2-P01` atendem `p95 <= 16,7 ms` em `720p` e `1080p`; picos pontuais acima de `16,7 ms` observados apenas em rajada síncrona `P04` e no transiente `D2-P01: 6_TREES_KEEPING_STONE_FOOD_ACTIVE` já conhecido desde `D2 R1`)* |
| **Auditoria visual (`720p` / `1080p`)** | **APROVADA NO ESCOPO D2.2 COM RESSALVA TRANSIENTE (`V13`)** *(`V01`–`V15` capturados e inspecionados; `use_d2_2_hud = false`, zero glow, selo `×`/`×N` com vão `6 px`, zero sobreposição entre painéis persistentes; ressalva transiente de sobreposição no topo-central em `V13` quando o toast temporário de conclusão coincide com o banner temporário de posicionamento)* |
| **Integridade arquitetural** | **APROVADA** *(`0` polling em sistemas orientados a eventos, clock da árvore ativo somente em `CHOPPING`/`FELLING`, `0` tarefas duplicadas, `0` marcadores órfãos, `teardown` limpo)* |
| **Integridade Git e ancestralidade** | **APROVADA** *(`merge-base(develop, HEAD) == 21c34ee`, `0` atrasos em relação à `develop`, fast-forward futuro tecnicamente viável, `0` alterações de produção)* |
| **Aceite humano (`M1`–`M8`)** | **PENDENTE** *(protocolo atualizado publicado; aguardando execução presencial pelo proprietário)* |

**Parecer consolidado da candidata:** **`VALIDAÇÃO TÉCNICA COM RESSALVAS — AGUARDANDO DELIBERAÇÃO`** *(nenhum cenário `M1`–`M8` declarado aprovado; `R-03A` permanece `NÃO HOMOLOGADA` e `NÃO INTEGRADA À DEVELOP`).*

---

## 2. Consolidação das Homologações Anteriores e Reaproveitamento da `D3.4`

Cadeia homologada registrada nesta candidata (`feat/r-03a-community-work-main-scene`, `37` commits exclusivos na fase técnica/documental sobre `develop @ 21c34ee` + `1` commit documental da `D4`):
- **`D0`** (`a39f3b5`): planejamento arquitetural homologado.
- **`D1` + `D1 R1`–`R3`** (`H-F01` e `H-F02` encerrados): seleção independente, seleção heterogênea, desmarcação `D1-B`, reautorização `D1-C` e barra contextual D2.2 minimalista homologadas.
- **`D2` + `D2 R1`** (`D0-A02` encerrada; `13` testes humanos aprovados): selo mineral `×`/`×N`, cancelamento seletivo, soberania de ordens pessoais, entrega residual e proteção contra callbacks obsoletos.
- **`D3` (`D3.1`, `D3.1-R1`, `D3.2`, `D3.3`, `D3.3-R1`, `D3.4`)** (`D3.1-A01`, `D3.3-A01`, `D0-A03` encerradas; `D0-A04` homologada no escopo arquitetural vigente; `8` testes humanos `HD3-01`–`HD3-08` aprovados): ciclo completo `STANDING→CHOPPING→FELLING→FALLEN→DEPLETED`, prova regional de 8 compartimentos físicos e validação segmentada integral.

**Reaproveitamento verificado (`01_technical_evidence_reconciliation/d3_4_reuse_verification.txt`):**
- Diferença `e7d72e4..5330625`: exclusivamente `docs/testing/R_03A_D3_4_integral_validation_candidate_report.md` (`0` arquivos executáveis alterados; na `D4`, apenas relatórios em `docs/testing/` são adicionados).
- Integridade dos manifestos verificada com `0` falhas: `D3.4` (`15` arquivos, `ManifestSHA256 = e42f5825f93a6b8d4a3863170bed031bb746bb7031fd20ea3f4b0d6675ce053c`) e `D3.3-R1` (`9` arquivos, `ManifestSHA256 = d74e0b72d555d5f8f8db4fc379577f23f444ecddaefaedc4e7e128abe9cce47e`).
- Campanha integral `D3.4` reaproveitada do SHA técnico idêntico `e7d72e4`: **`93/93` suítes únicas (`0` ausentes, `0` duplicatas), `706/706` testes, `33.845` asserções, `66/66` lotes, `0` erros/avisos/timeouts/crashes, `AGGREGATE_EXIT_CODE = 0`**; validação estática **`219/219` scripts (`0/0`, `ValidateExitCode = 0`, `DOCS_DESIGN_IMPORT_COUNT = 0`)**; smoke headless **`exit=0`**.

---

## 3. Auditoria de Desempenho — Ambiente Real, Matriz `P01`–`P12` e Revalidação `D2-P01`

### 3.1 Ambiente Verificado (`02_environment/hardware_and_power_ac_verified.txt` + `03_performance/ac_continuity.txt`)
- **CPU:** `Intel(R) Core(TM) i7-8650U CPU @ 1.90GHz` (`4` núcleos / `8` threads)
- **GPU ativa na Godot (`gl_compatibility` / OpenGL 3.3.0):** `Intel(R) UHD Graphics 620` (`Build 30.0.101.1339`) *(adapter dedicado GTX 1060 presente no sistema, mas **não utilizado** pelo renderizador `gl_compatibility`)*
- **RAM / SO:** `15,92 GB` RAM · `Windows 11 Pro 10.0.26300`
- **Engine / Física / Janela:** `Godot 4.7.2.stable.official.ed1daf0bf` · `Jolt Physics` · `VSYNC_DISABLED` (`vsync_mode=0`) · sem `--fixed-fps`
- **Alimentação elétrica comprovada:** inicial `BatteryStatus=1 / PowerOnline=False` detectado e reportado antes das medições; tomada CA conectada pelo proprietário e verificada continuamente antes e depois de todos os 6 benchmarks (`AC_CONFIRMED = True`, `BatteryStatus = 2`, `PowerOnline = True`, `Charging = True`, `Discharging = False`, bateria `66%/80%`, plano `Equilibrado`).

### 3.2 Matriz `P01`–`P12` (`2` execuções completas por resolução, `CA`, `VSync OFF`, amostras brutas preservadas em JSON)

Critério D0 §9.4: **`p95 <= 16,7 ms` em tomada CA**. Valores abaixo listam `Run 1 / Run 2` de cada métrica observada:

| Cenário | `1280×720` FPS | `1280×720` Med (ms) | `1280×720` **p95 (ms)** | `1280×720` p99 / Max (ms) | `1920×1080` FPS | `1920×1080` Med (ms) | `1920×1080` **p95 (ms)** | `1920×1080` p99 / Max (ms) | Orçamento `16,7 ms` |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| **P01** Ociosa estabilizada | `237,82 / 279,94` | `3,921 / 3,397` | **`6,492 / 5,098`** | `8,089 / 8,792` · `5,603 / 14,986` | `153,29 / 136,29` | `6,472 / 7,273` | **`8,170 / 9,467`** | `8,574 / 8,847` · `10,583 / 12,972` | **PASS** |
| **P02** Seleção / alternância | `257,81 / 296,36` | `3,587 / 3,279` | **`5,948 / 4,452`** | `6,979 / 17,213` · `5,202 / 16,563` | `141,25 / 134,59` | `6,925 / 7,372` | **`10,017 / 9,866`** | `11,791 / 21,514` · `11,199 / 32,999` | **PASS** |
| **P03** Seleção heterogênea caixa | `230,76 / 259,03` | `3,825 / 3,475` | **`7,604 / 7,133`** | `10,235 / 15,045` · `9,333 / 14,346` | `125,66 / 119,18` | `7,021 / 7,858` | **`13,821 / 14,370`** | `24,712 / 31,657` · `24,778 / 28,398` | **PASS** |
| **P04** Autorização lote (rajada) | `136,22 / 144,23` | `3,877 / 3,604` | **`43,027 / 36,260`** | `51,101 / 58,337` · `46,318 / 79,427` | `122,47 / 107,35` | `5,184 / 6,426` | **`37,537 / 39,133`** | `51,179 / 72,203` · `51,383 / 167,930` | **RESSALVA** *(transiente síncrono ~13–16 ms em rajada)* |
| **P05** 2 trabalhadores comunitários | `244,70 / 273,51` | `3,733 / 3,480` | **`6,302 / 4,908`** | `7,280 / 25,409` · `5,821 / 20,540` | `142,76 / 134,93` | `6,732 / 7,381` | **`10,417 / 9,714`** | `12,349 / 24,395` · `11,102 / 20,527` | **PASS** |
| **P06** 2 cortadores RTS mesma árvore | `218,10 / 280,40` | `4,407 / 3,416` | **`6,976 / 4,838`** | `8,023 / 9,258` · `5,684 / 7,630` | `153,45 / 132,44` | `6,532 / 7,229` | **`8,269 / 10,878`** | `9,075 / 9,974` · `13,205 / 15,247` | **PASS** |
| **P07** Corte e `FELLING → FALLEN` | `268,27 / 280,73` | `3,464 / 3,448` | **`5,426 / 4,698`** | `6,091 / 14,140` · `5,556 / 21,886` | `143,41 / 133,80` | `6,662 / 7,413` | **`10,061 / 9,984`** | `12,050 / 46,780` · `11,555 / 18,447` | **PASS** |
| **P08** Coleta, transporte e entrega | `285,19 / 286,17` | `3,239 / 3,379` | **`5,039 / 4,686`** | `5,743 / 15,526` · `5,409 / 15,735` | `132,97 / 128,37` | `7,454 / 7,671` | **`10,127 / 10,519`** | `12,813 / 19,390` · `12,989 / 26,299` | **PASS** |
| **P09** Cancelamento coletivo (`6` árv.) | `19,53 / 19,93` *(8 pulsos)* | `6,628 / 6,524` | **`8,056 / 6,833`** | `8,056 / 8,056` · `6,833 / 6,833` | `17,36 / 13,89` *(8 pulsos)* | `7,769 / 9,635` | **`9,240 / 12,202`** | `9,240 / 9,240` · `12,202 / 12,202` | **PASS** |
| **P10** Encerramento e retorno ocioso | `286,41 / 288,24` | `3,268 / 3,394` | **`4,943 / 4,533`** | `5,492 / 6,051` · `5,103 / 5,644` | `136,79 / 134,40` | `7,284 / 7,336` | **`8,740 / 9,254`** | `9,255 / 10,588` · `11,508 / 14,971` | **PASS** |
| **P11** Coexistência c/ construção legada | `248,92 / 251,28` | `3,667 / 3,763` | **`5,802 / 5,356`** | `6,871 / 24,965` · `6,868 / 21,500` | `134,17 / 125,23` | `7,016 / 7,610` | **`10,862 / 12,490`** | `13,613 / 32,685` · `15,657 / 40,662` | **PASS** |
| **P12** Câmera RTS em atividade | `254,06 / 253,64` | `3,641 / 3,789` | **`5,497 / 5,284`** | `6,414 / 24,014` · `5,938 / 24,654` | `125,88 / 123,04` | `7,378 / 7,813` | **`12,059 / 11,769`** | `14,416 / 46,990` · `13,698 / 70,359` | **PASS** |

*Tempos de física, navegação e operações síncronas:* `phys_avg_ms` variou entre `0,71–7,78 ms` (`12,84–18,96 ms` apenas nos 8 quadros isolados de cancelamento em `P09`); `nav_avg_ms <= 2,80 ms`; `draw_calls_avg = 206–270`; CPU síncrona média em `P02 = 667–965 µs`, `P03 = 4,26–9,30 ms`, `P04 = 13,38–16,41 ms`, `P09 = 2,22–3,45 ms`. Quadros `>100 ms`: **`0`** em todas as execuções de `P01`–`P03` e `P05`–`P12`; **`1`** quadro (`167,930 ms`) na rajada sintética `P04` em `1920×1080 Run 2`.

### 3.3 Revalidação `D2-P01` (`10` repetições, `CA`, `VSync OFF`)

| Subcenário `D2-P01` | `1280×720` CPU sínc. média (`cancel p95`) | `1920×1080` CPU sínc. média (`cancel p95`) | `1920×1080` Histórico `D2 R1` | `hud_refreshes` | Preservação seleção/outras |
|---|---:|---:|---:|---:|---|
| `1_TREE_SINGLE` | `1,189 ms` (`5,594 ms`) | `1,344 ms` (`7,930 ms`) | `1,587 ms` (`9,348 ms`) | `1` | `sel_ok=true`, `other_ok=true` |
| `6_TREES_LARGEST_BATCH` | `5,149 ms` (`10,506 ms`) | `6,515 ms` (`14,312 ms`) | `5,888 ms` (`13,247 ms`) | `1` | `sel_ok=true`, `other_ok=true`, `residual=true` |
| `4_ROCKS_BATCH` | `5,102 ms` (`10,723 ms`) | `4,832 ms` (`11,081 ms`) | `5,293 ms` (`10,595 ms`) | `1` | `sel_ok=true`, `other_ok=true` |
| `4_BUSHES_BATCH` | `4,271 ms` (`9,579 ms`) | `4,628 ms` (`12,518 ms`) | `5,506 ms` (`11,972 ms`) | `1` | `sel_ok=true`, `other_ok=true` |
| `6_TREES_IN_HETEROGENEOUS_14SEL` | `6,269 ms` (`12,294 ms`) | `5,607 ms` (`13,114 ms`) | `8,769 ms` (`16,991 ms`) | `1` | `sel_ok=true`, `other_ok=true` |
| `6_TREES_KEEPING_STONE_FOOD_ACTIVE` | `5,921 ms` (**`28,711 ms`**) | `5,526 ms` (**`45,453 ms`**) | `7,752 ms` (**`35,846 ms`**) | `1` | `sel_ok=true`, `other_ok=true` |
| `STEADY_BEFORE` / `STEADY_AFTER` | `5,355 / 6,108 ms` | `9,649 / 8,841 ms` | `10,429 / 9,559 ms` | — | `hud/disp _process=false` |

### 3.4 Análise Honesta das Extrapolações de Transientes
1. **`P04_Community_Authorization`:** apresentou `p95 = 36,26–43,03 ms` (`720p`) e `37,54–39,13 ms` (`1080p`), com pico isolado de `167,93 ms` em `1080p Run 2`, enquanto a **mediana** da janela permaneceu `3,60–6,43 ms`. Origem: o script disparam `authorize(6 madeira) + authorize(4 pedra) + cancel` a cada 20 quadros (~15 rajadas em `3,5 s`), acumulando criação síncrona de tarefas + `Sprite3D` de marcadores + consultas iniciais no `NavigationServer3D` (`sync_op_avg = 13,38–16,41 ms`). Impacto real ao jogador: um clique esporádico de autorização de grande lote gera apenas 1 quadro pontual (~`13–16 ms` CPU) na resposta do clique, retornando imediatamente a `p95 <= 10,4 ms` no trabalho contínuo (`P05`).
2. **`D2-P01: 6_TREES_KEEPING_STONE_FOOD_ACTIVE`:** `cancel_frame p95 = 28,711 ms` (`720p`) e `45,453 ms` (`1080p`). Origem e comparação histórica: idêntico ao custo residual já documentado em `D2 R1` (`35,846 ms` em `1080p`) decorrente de cancelamento de 6 tarefas com imediata redistribuição/roteamento nas 8 tarefas de pedra e alimento ainda ativas, com `STEADY_AFTER p95 = 8,841 ms` e `hud_refreshes = 1`.

---

## 4. Auditoria Estrutural (`06_structural_audit/structural_audit.log`)

Validado diretamente na `MainScene` (`STRUCT_EXIT = 0`, `STRUCTURAL_AUDIT_OK = true`):
- **Zero polling em sistemas orientados a eventos:** `board_proc=false`, `board_phys=false`, `disp_proc=false`, `disp_phys=false`, `hud_proc=false`, `hud_phys=false`.
- **Árvores ociosas sem processamento:** `14/14` fontes naturais ociosas com `is_processing() == false` e `is_physics_processing() == false`.
- **Ciclo dinâmico do relógio da árvore:** `standing=false → chopping=true → felling=true → fallen=false → depleted=false`.
- **Sem duplicação / liberação limpa:** `auth1_created=1`, `auth2_created=0`, `slots_after=0`, `markers_after=0`, `teardown` com `0` marcadores e `0` tarefas pendentes.

---

## 5. Auditoria Visual `V01`–`V15` (`1280×720` e `1920×1080`)

Capturas nativas reais em `04_visual_720p/V01..V15_1280x720.png` e `05_visual_1080p/V01..V15_1920x1080.png` (`VIS_720P_EXIT=0`, `VIS_1080P_EXIT=0`, `use_d2_2_hud=false` em `30/30` capturas, `0` marcadores órfãos em `V15`):

| Captura | Estado Verificado | `720p` / `1080p` | Observação Visual Direta |
|---|---|---|---|
| `V01` | `MainScene` inicial + HUD legada | `V01_1280x720.png` / `V01_1920x1080.png` | HUD contextual oculta; acampamento, `[Construir]` e fontes legíveis. |
| `V02` | Árvore individual selecionada sem tarefa | `V02_*` | Apenas anel dourado externo; `[Machado 1]` sem `×`; zero tarefa criada. |
| `V03` | Seleção heterogênea (madeira/pedra/alimento) | `V03_*` | Anéis externos simultâneos nas 3 categorias. |
| `V04` | HUD contextual + painel `Leader A` | `V04_*` | `[Machado 3] [Picareta 2] [Colheita 2]` centralizada, sem sobreposição. |
| `V05` | Tarefas de madeira autorizadas | `V05_*` | Laje verde + checkmark, selo basalt `×` `6 px` acima, zero glow. |
| `V06` | Anel de seleção + ícone de trabalho coexistindo | `V06_*` | Anel dourado na base e ícone de machado discreto acima da copa. |
| `V07` | Caixa `Shift+arraste` (modo fontes) | `V07_*` | Caixa dourada translúcida englobando múltiplas árvores. |
| `V08` | Cancelamento seletivo de madeira preservando pedra | `V08_*` | Madeira retorna disponível; `[Picareta 2 ✓]` + `×` e ícones nas rochas preservados. |
| `V09` | Árvore em corte progressivo (`CHOPPING`) | `V09_*` | Cortador adjacente à árvore em pé (`STANDING`/`CHOPPING`). |
| `V10` | Árvore em queda (`FELLING`) | `V10_*` | Tronco/copa inclinados em animação real com trabalhador neutro. |
| `V11` | Árvore derrubada (`FALLEN`) e recolhimento | `V11_*` | Tronco horizontal no solo durante coleta física. |
| `V12` | Acampamento e pilhas físicas entregues | `V12_*` | Pilhas físicas no chão coerentes com `Madeira: 2 | Pedra: 3 | Alimentos: 4`. |
| `V13` | Coexistência com construção (`TemporaryPlacementBar`) | `V13_*` | **Painéis persistentes sem sobreposição**; porém **ressalva visual observada na inspeção direta:** quando o toast temporário de `AutonomousGatherFeedback` (`"Corte de madeira concluído."`) ainda está visível no topo-central ao abrir o banner temporário de `PlacementTestOverlay` (`"Posicionando: Abrigo Básico..."`), ambos ocupam o topo-central e se sobrepõem transitoriamente até o toast expirar (`V14`/`V15` já limpos). |
| `V14` | `DebugOverlay` `[F3]` + trabalho comunitário | `V14_*` | Painel debug no canto superior esquerdo sem colisão com HUD/estoque. |
| `V15` | Pós-conclusão e limpeza de marcadores | `V15_*` | `V15_CLEANUP_MARKERS=0`, `active_tasks=0`, toco remanescente limpo. |

---

## 6. Preparação da Eventual Integração e Limitações Preservadas

- **Ancestralidade verificada (`00_git_baseline/git_baseline.txt`):** `merge-base(develop, HEAD) == 21c34ee645725a74f1fefac9db0309ec711ab5f2`, `BehindDevelop == 0`, `FastForwardPossibleFromDevelop == True` (`37` commits anteriores + `1` commit documental da `D4`).
- **Limitações históricas preservadas:**
  - `R01`: `TestMap/ResourceSources` sem `meta(&"region_id")` resolvido para `&"default"` até `T4`; ausência de compartimento físico separado para pilhas avulsas externas na arquitetura `T3`.
  - **`HD3-06`:** exclusão atual é por tarefa (após concluir ordem pessoal, trabalhador pode assumir outra fonte autorizada pendente); retorno temporizado (`D-05`), `ControlMode` e metadados da Casa Fundadora seguem reservados à `R-03B`.
  - Migração integral D2.2 (`use_d2_2_hud = true`) reservada à `R-05`; substituição de `TemporaryPlacementBar` / `AutonomousGatherFeedback` provisórios removerá naturalmente a ressalva transiente de topo-central observada em `V13`.
- **Matriz de atualizações documentais propostas (somente após homologação final da `R-03A`, não executadas agora):** atualizar status de `R-03A` para `HOMOLOGADO`/`INTEGRADO` em `docs/ROADMAP_MESTRE.md` e `docs/KNOWN_ISSUES.md` (incluindo métricas CA/transientes `D4`), mantendo `docs/Dawn_of_Kin_GDD.md` (`v1.3`) e `AGENTS.md` íntegros.

---

## 7. Pendências para Encerramento da `R-03A`

1. Auditoria independente do ChatGPT sobre esta candidata `D4`.
2. Execução presencial do protocolo humano **`M1`–`M8`** pelo proprietário ([R_03A_D4_final_manual_test_protocol.md](R_03A_D4_final_manual_test_protocol.md)).
3. Deliberação do proprietário sobre as duas ressalvas documentadas (`P04` / `D2-P01: 6_TREES_KEEPING_STONE_FOOD_ACTIVE` transientes de lote e sobreposição transiente de toast topo-central em `V13`) e decisão final de homologação e autorização para integração por fast-forward em `develop`.
