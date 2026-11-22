# DAWN OF KIN — UI-0 R2.2: CORREÇÃO DE FIDELIDADE VISUAL DA DIREÇÃO D2 (PROPOSTA)

> **Status:** `PROPOSTA` — Restauração de fidelidade visual da **Direção D2 — Marcos de Pedra e Eclipse** originalmente escolhida pelo proprietário (`design/ui-0-r2-identity` @ `f1381774ec462b0865787087e591fe70c0dbcbff`), agora reproduzida fielmente ao vivo dentro da **Godot 4.7.2**.  
> **Decisão pendente:** Avaliação e decisão exclusiva do proprietário. **A `UI-0` não foi declarada aprovada e `UI-1` permanece BLOQUEADA.**  
> **Branch documental:** `design/ui-0-r2-2-d2-visual-fidelity` (worktree isolado `C:\Projetos\Dawn_of_Kin_wt_ui_0_r2_2`, derivada de `fe7ca589a1f217aa56dafa8eb66009a948bca695`, preservando integralmente o histórico, scripts e benchmarks da R2 e da R2.1).  
> **Escopo respeitado:** Zero alterações em gameplay, `MainScene` de produção, economia, transporte, construção de produção, RTS, seleção, sistemas de linhagem, testes de produção, `docs/Dawn_of_Kin_GDD.md`, `AGENTS.md`, `main`, branches técnicas protegidas ou `C:\Projetos\Dawn of Kin`.

---

## 1. Motivo desta Correção (Por que R2.1 foi Reprovada)

Na revisão anterior, o proprietário reprovou explicitamente a UI-0 R2.1:

> *"Não está igual ao escolhido. Você me mostrou uma HUD com elementos separados. Quero igual ao que eu escolhi."*

**Diagnóstico honesto do desvio cometido na R2.1:**
1. A R2.1 substituiu os **3 seixos/pedras escalonadas de recursos** da D2 original por uma barra retangular única contendo 3 caixas internas e rótulos extras (`MADEIRA`, `PEDRA`, `ALIMENTOS`, `EXPOSTO`).
2. A R2.1 trocou a **placa superior direita de topo em cumeeira** (`Clareira Inicial / Primavera · Ano I / || 1× 2× 4× / ● EXPOSTO · ☰ MENU`) por um retângulo inclinado com bandeja interna.
3. A R2.1 fundiu as **duas estelas inclinadas separadas de Alden e Brena** num díptico colado com coroa circular no topo, etiqueta `CASA · 2` e caixas internas atrás dos nomes.
4. A R2.1 alterou o texto e a composição da **laje de alabastro `Maquetes / Construir [B]`**, inseriu caixas internas em `Tarefas [T]` / `Linhagem [H]` e substituiu as **duas maquetes verticais em alabastro** (`D2_C_construction`) por uma prancha horizontal diferente.
5. Já na R2 original, o primeiro protótipo Godot (`G_godot_D2_marcos_kintsugi_1280x720.png`) havia ficado simplificado demais (polígonos lisos sem textura real, linhas douradas cruzando o texto e sem os ícones da D2).

**Regra absoluta aplicada nesta UI-0 R2.2:** **fidelidade antes de criatividade.** Nenhuma composição, silhueta, proporção, agrupamento ou hierarquia da D2 original foi reinventada; reconstruímos **exatamente a D2 escolhida** dentro da Godot 4.7.2, aplicando apenas melhorias técnicas invisíveis à composição (Atlas 2D pré-assado 2× supersampled, ícones originais nítidos, escala calibrada para 720p/1080p e eliminação total de sobreposições de texto).

---

## 2. Referência Visual Restaurada e Comparação Obrigatória (3 Vias + Detalhes)

### 2.1 Comparação Direta: `A — D2 Original Escolhida` × `B — D2.1 Reprovada` × `C — D2 Restaurada na Godot`
- **Comparação 3 Vias — HUD `1920×1080`:** [C1_comparison_3way_HUD_1920x1080.png](../design/ui-0-r2-2/C1_comparison_3way_HUD_1920x1080.png)
- **Comparação 3 Vias — HUD `1280×720`:** [C2_comparison_3way_HUD_1280x720.png](../design/ui-0-r2-2/C2_comparison_3way_HUD_1280x720.png)
- **Análise por Regiões (Recortes Reais 1080p das 4 Áreas da HUD):** [C3_region_detail_audit_1920x1080.png](../design/ui-0-r2-2/C3_region_detail_audit_1920x1080.png)
- **Comparação D2 Original × Godot 4.7.2 (Construção, Seleção/Linhagem e Menu):** [C4_comparison_views_build_lineage_menu_1920x1080.png](../design/ui-0-r2-2/C4_comparison_views_build_lineage_menu_1920x1080.png)

### 2.2 Capturas Reais Executadas na Godot 4.7.2 (`1920×1080` e `1280×720`)
Todas as 8 capturas abaixo foram renderizadas ao vivo na **Godot 4.7.2** sobre a mesma cena 3D de referência (`res://tests/visual/rux_2b_multi_source_selection.tscn`) com a HUD legada oculta e sem alterar nenhum sistema de gameplay:

| Visão Restaurada da D2 | Captura Godot `1920×1080` | Captura Godot `1280×720` | Referência Original R2 |
|---|---|---|---|
| **1. HUD Normal** | [G_godot_D2_2_hud_1920x1080.png](../design/ui-0-r2-2/G_godot_D2_2_hud_1920x1080.png) | [G_godot_D2_2_hud_1280x720.png](../design/ui-0-r2-2/G_godot_D2_2_hud_1280x720.png) | [D2_B 1080p](../design/ui-0-r2/D2_B_hud_1920x1080.png) / [720p](../design/ui-0-r2/D2_B_hud_1280x720.png) |
| **2. Construção** | [G_godot_D2_2_construction_1920x1080.png](../design/ui-0-r2-2/G_godot_D2_2_construction_1920x1080.png) | [G_godot_D2_2_construction_1280x720.png](../design/ui-0-r2-2/G_godot_D2_2_construction_1280x720.png) | [D2_C 1080p](../design/ui-0-r2/D2_C_construction_1920x1080.png) |
| **3. Seleção & Linhagem** | [G_godot_D2_2_lineage_1920x1080.png](../design/ui-0-r2-2/G_godot_D2_2_lineage_1920x1080.png) | [G_godot_D2_2_lineage_1280x720.png](../design/ui-0-r2-2/G_godot_D2_2_lineage_1280x720.png) | [D2_D 1080p](../design/ui-0-r2/D2_D_lineage_1920x1080.png) |
| **4. Menu Principal** | [G_godot_D2_2_menu_1920x1080.png](../design/ui-0-r2-2/G_godot_D2_2_menu_1920x1080.png) | [G_godot_D2_2_menu_1280x720.png](../design/ui-0-r2-2/G_godot_D2_2_menu_1280x720.png) | [D2_E 1080p](../design/ui-0-r2/D2_E_menu_1920x1080.png) |

---

## 3. Relatório Honesto: Correções Executadas × Diferenças Remanescentes

### 3.1 Problemas técnicos corrigidos sem alterar a composição escolhida
| Problema da R2 (Godot) e da R2.1 | Correção técnica aplicada na R2.2 |
|---|---|
| Linhas douradas diagonais cruzavam textos (`MAD 24`, `PED 14`, `ALI 18`, `Ano I`, `Brena`, `Linhagem`) na Godot R2. | Superfícies das 12 peças pré-assadas em [`d2_2_faithful_atlas.png`](../design/ui-0-r2-2/assets/d2_2_faithful_atlas.png) (`208 KB`) aplicando exatamente o gradiente escuro da classe `.k-stone` sobre `d2_kintsugi_basalt.png`: textura vulcânica + veios sutis preservados, **zero linhas cruzando letras**. |
| Ausência dos ícones originais da D2 na Godot R2. | Todos os **5 ícones originais da D2** (madeira, pedra, alimentos, tarefas `↗`, linhagem `A`) rasterizados em 2× no mesmo Atlas 2D (`ico_wood`, `ico_stone`, `ico_food`, `ico_tasks`, `ico_lineage`). |
| Corte da palavra `Construir` e desalinhamento de `720p` em `canvas_items`. | Escala calibrada matematicamente (`scale = 1.00` em `1080p`, `scale = 1.22` sobre o canvas lógico `1920×1080` em `720p`), reproduzindo as proporções físicas exatas de `D2_B_hud_1280x720.png` (estelas ~`88 px`, placa ~`160 px`) com margens amplas e zero clipping. |
| Overflow inicial na faixa de validação de Construção (`Esc soltar`) e no subtítulo do Menu em `720p` (detectados na primeira inspeção visual desta R2.2). | Faixa `build_valid_bar` alargada para `760 px` com margens simétricas; subtítulo do Menu quebrado em duas linhas limpas e usando escala proporcional à altura do monólito (`h / 1080`), eliminando 100% do overflow em `720p` e `1080p`. |
| Showcase da R2 exibia apenas HUD em repouso. | Showcase da R2.2 reproduz **HUD Normal**, **Construção**, **Seleção & Linhagem** e **Menu Principal**, tanto em capturas automatizadas quanto em modo interativo ao vivo (`-Interactive`, teclas `1`, `2`/`B`, `3`/`H`, `4`/`M`, `Esc` ou cliques diretos nas estelas, `Maquetes`, `Linhagem` e `☰ MENU`). |

### 3.2 Diferenças remanescentes identificadas e justificadas (sem esconder nada)
Não declaramos equivalência absoluta de 100%; as diferenças residuais observáveis nas pranchas comparativas são:
1. **Deslocamento leve de câmera no fundo 3D (`~3 m`):** os mockups originais da R2 usaram `base_m1_clean` (capturado com a câmera levemente deslocada ao sul na cena `rux_2b_multi_source_selection.tscn`), enquanto o showcase Godot R2.2 abre a mesma cena em sua câmera inicial padrão sem alterar a câmera de produção. Isso muda apenas quais objetos 3D passam atrás dos cantos inferiores (ex.: pedra azul atrás da estela de Brena e rótulo 3D `Madeira` atrás de `Maquetes`), sem alterar posições nem proporções da HUD.
2. **Elementos 3D de gameplay ausentes no showcase isolado:** em `D2_C` (mockup), a captura `base_m3_build` exibia o fantasma verde de posicionamento 3D e um canteiro no solo; em `D2_D`, Alden exibia o anel 3D amarelo de seleção no chão. Como o showcase R2.2 é estritamente isolado e não manipula gameplay nem `PlacementController`, o mundo 3D permanece em seu estado neutro de abertura.
3. **Contorno dourado integral nos 4 lados dos polígonos na Godot:** no HTML/CSS original, `clip-path: polygon(...)` aparava parcialmente os cantos do `border` retangular; no Atlas pré-assado da Godot, o filete dourado acompanha integralmente todo o perímetro poligonal — acabamento mais limpo preservando exatamente as mesmas coordenadas de vértice.
4. **Quebra de linha melhorada no botão `Liberar para Comunidade (P-RUX-2)` em `D2_D`:** no mockup HTML original, `2)` quebrava sozinho numa segunda linha; na Godot R2.2 o rótulo ajusta-se numa única linha limpa dentro do mesmo botão.
5. **Nota sobre narrativa do GDD (pendência de decisão, não alterada unilateralmente):** para cumprir rigorosamente a ordem de **fidelidade visual à D2 escolhida**, preservamos na R2.2 a aparência integral da placa superior e dos rótulos da referência `D2_B`–`D2_E` (inclusive a legenda `Basalto Kintsugi` e `Primavera · Ano I`, sendo estações/calendário marcados como `PROPOSTA T4` e `Continuar`/`Carregar` como `PROPOSTA T3.8`). Caso o proprietário deseje ajustar qualquer texto específico (ex.: substituir termos de referência estética por terminologia final do GDD) na futura `UI-1`, isso poderá ser feito em 1 minuto sem alterar nenhuma forma visual.

---

## 4. Código Reproduzível do Showcase e Benchmark Preliminar (Sem V-Sync)

### 4.1 Execução reproduzível
- **Capturas (8 PNGs em 720p/1080p) + Benchmark sem V-Sync:**
  ```powershell
  .\docs\design\ui-0-r2-2\godot_showcase\run_ui0_r2_2_showcase.ps1
  ```
- **Visualização interativa ao vivo na Godot 4.7.2 (isolada do gameplay):**
  ```powershell
  .\docs\design\ui-0-r2-2\godot_showcase\run_ui0_r2_2_showcase.ps1 -Interactive
  ```
- **Arquivos versionados:** [`ui0_r2_2_d2_faithful_showcase.gd`](../design/ui-0-r2-2/godot_showcase/ui0_r2_2_d2_faithful_showcase.gd) · [`run_ui0_r2_2_showcase.ps1`](../design/ui-0-r2-2/godot_showcase/run_ui0_r2_2_showcase.ps1) · [`benchmark_results_r2_2.json`](../design/ui-0-r2-2/godot_showcase/benchmark_results_r2_2.json) · [`d2_2_faithful_atlas.png`](../design/ui-0-r2-2/assets/d2_2_faithful_atlas.png) · [`d2_2_menu_monolith.png`](../design/ui-0-r2-2/assets/d2_2_menu_monolith.png).

### 4.2 Medições reais na Godot 4.7.2 (`Intel(R) UHD Graphics 620`, `OpenGL 3.3 Compatibility`, `VSYNC_DISABLED`)
Metodologia idêntica e reproduzível: `60` quadros de aquecimento + `3` rodadas intercaladas × `180` quadros = **`540` quadros válidos por cenário e resolução** sobre `res://tests/visual/rux_2b_multi_source_selection.tscn`.

#### `1280×720` (`logical = 1920×1080`, `scale = 1.22`, V-Sync OFF)
| Cenário | Média mediana (ms) | `p95` mediano (mín..máx) (ms) | `p99` mediano (mín..máx) (ms) | `> 100 ms` | Draw calls | Nós |
|---|---:|---|---|---:|---:|---:|
| `BASELINE_3D` | `6,445` | `8,841` (`7,506..9,252`) | `9,405` (`9,384..11,237`) | `0` | `201` | `518` |
| `D2_2_FAITHFUL_HUD` | `8,187` | `11,563` (`11,503..11,656`) | `13,638` (`13,544..13,678`) | `0` | `241` (`+40`) | `708` |
| `D2_2_FAITHFUL_CONSTRUCTION` | `8,516` | `10,848` (`8,339..11,387`) | `11,789` (`10,683..12,665`) | `0` | `267` (`+66`) | `708` |
| `D2_2_FAITHFUL_LINEAGE` | `7,511` | `10,646` (`8,868..10,797`) | `11,708` (`9,792..12,728`) | `0` | `238` (`+37`) | `708` |

#### `1920×1080` (`logical = 1920×1080`, `scale = 1.00`, V-Sync OFF)
| Cenário | Média mediana (ms) | `p95` mediano (mín..máx) (ms) | `p99` mediano (mín..máx) (ms) | `> 100 ms` | Draw calls | Nós |
|---|---:|---|---|---:|---:|---:|
| `BASELINE_3D` | `7,159` | `9,925` (`9,778..10,830`) | `11,250` (`10,612..11,614`) | `0` | `201` | `518` |
| `D2_2_FAITHFUL_HUD` | `8,136` | `10,828` (`10,323..11,127`) | `12,034` (`11,146..12,094`) | `0` | `241` (`+40`) | `708` |
| `D2_2_FAITHFUL_CONSTRUCTION` | `9,070` | `12,334` (`11,720..12,581`) | `14,075` (`13,077..14,301`) | `0` | `267` (`+66`) | `708` |
| `D2_2_FAITHFUL_LINEAGE` | `7,919` | `10,195` (`9,921..11,368`) | `11,607` (`10,975..11,994`) | `0` | `238` (`+37`) | `708` |

**Leitura honesta e limitações:**
- A HUD D2 fiel em repouso (`D2_2_FAITHFUL_HUD`) adicionou `+40` draw calls (contra `+71` da D2 procedural da R2), mantendo em `1920×1080` média mediana `8,136 ms` (`+0,977 ms` sobre o baseline equivalente), `p95` mediano `10,828 ms` e `p99` mediano `12,034 ms` (com máxima de `12,094 ms` nas 3 rodadas e `0` quadros `> 100 ms`). Mesmo a tela mais densa (`D2_2_FAITHFUL_CONSTRUCTION`, `+66` draw calls) manteve `p99` máximo de `14,301 ms`.
- Os benchmarks históricos da R2 (`docs/design/ui-0-r2/godot_showcase/benchmark_results.json`) e da R2.1 (`docs/design/ui-0-r2-1/godot_showcase/benchmark_results_r2_1.json`) permanecem preservados integralmente na árvore como evidência histórica.
- **Limitação explícita:** trata-se de **benchmark preliminar de renderização isolada** (sem simulação pesada simultânea de múltiplos ciclos de IA/navegação/construção nem medição formal de tomada CA × bateria DC); portanto **não constitui homologação final de desempenho de gameplay**.

---

## 5. Governança, Preservação e Próxima Decisão do Proprietário

- **Arquivos/branches protegidos intactos:** `main` (`25e0a20`), `feat/rux-2b-multi-source-selection` (`cddd582`), `design/ui-0-r1-art-direction` (`c45f15c`), `design/ui-0-r2-identity` (`f138177`), `design/ui-0-r2-1-d2-refinement` (`fe7ca58`), `C:\Projetos\Dawn of Kin` (`7293908`), `docs/Dawn_of_Kin_GDD.md`, `AGENTS.md`, cenas e código de produção.
- **Pendências abertas preservadas:** `UX-1` (3 testes manuais), aceite manual `RUX-1`/`RUX-2A`/`RUX-2B`, `D3-04` e `D3-07` (`T3.6.4-R1`), decisões `P-RUX-1`..`P-RUX-4`/`P-RUX-6`, classificação DC da T2.
- **Aguardando decisão exclusiva do proprietário:** confirmar se esta reprodução fiel da **Direção D2 na Godot 4.7.2 (`UI-0 R2.2`)** corresponde ao visual escolhido e se autoriza (ou solicita ajustes antes de) qualquer especificação futura de `UI-1`.
