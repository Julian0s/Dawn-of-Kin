# DAWN OF KIN — UI-0 R2.1: REFINAMENTO ARTÍSTICO DA DIREÇÃO D2 — MARCOS DE PEDRA E ECLIPSE (PROPOSTA)

> **Status:** `PROPOSTA` — Refinamento exclusivo da Direção **D2 (Marcos de Pedra e Eclipse)**, aguardando avaliação e decisão do proprietário.  
> **Escopo:** Documentação, arte visual, protótipo interativo isolado na Godot 4.7.2 e medição empírica preliminar. **`UI-1` NÃO está autorizada.**  
> **Branch documental:** `design/ui-0-r2-1-d2-refinement` (derivada de `design/ui-0-r2-identity` @ `f1381774ec462b0865787087e591fe70c0dbcbff`, worktree isolado `C:\Projetos\Dawn_of_Kin_wt_ui_0_r2_1`).  
> **Integridade preservada:** Zero alterações em `MainScene`, gameplay, economia, transporte, construção de produção, RTS, seleção, sistemas familiares, testes de produção, `docs/Dawn_of_Kin_GDD.md`, `AGENTS.md`, `main`, `design/ui-0-r2-identity` ou `C:\Projetos\Dawn of Kin`. As direções D1 e D3 permanecem arquivadas sem aprovação.

---

## 1. Auditoria Inicial: O que Foi Preservado, O que Foi Corrigido e Adequação ao GDD

### 1.1 O que foi preservado da Direção D2 original
Mantivemos intacta a alma visual que agradou ao proprietário na UI-0 R2:
- Materialidade escultural de **basalto escuro** em contraste direto com o cenário 3D naturalista vibrante.
- **Veios metálicos dourados** quentes como acento nobre de foco e continuidade.
- **Silhuetas assimétricas chanfradas** de caráter monumental e misterioso.
- **Estelas dos fundadores** com retratos circulares e elevação física na seleção.
- **Contraste tátil claro × escuro** usando **alabastro claro** para construção/maquetes e ações primárias.

### 1.2 Adequação narrativa obrigatória ao GDD v1.2 (Transformação Autoral)
A releitura rigorosa de [`docs/Dawn_of_Kin_GDD.md`](../Dawn_of_Kin_GDD.md) (v1.2 consolidado) confirmou um erro conceitual na redação da D2 original:
- **O que o GDD realmente estabelece (`DECIDIDO`):** um casal foge da Terceira Guerra Mundial através de um fenômeno espacial e desperta sem pertences em uma **versão selvagem da Terra, sem cidades, ruínas humanas ou povos preexistentes** (§2.1), sustentada por cinco pilares — especialmente **Linhagem Viva** e **Natureza Vibrante em Contraste com o Mistério Sombrio** (*Ser de Trevas* × *Ser de Luz* em bastidores).
- **O que foi removido na D2.1:** **100% das referências a cultura japonesa, templos, arquipélago japonês e placas religiosas *ema***, que não têm lastro no GDD.
- **Como a estética foi transformada em linguagem própria de *Dawn of Kin*:**
  - **Basalto Bruto (`#181B1F`)** → *A Terra Selvagem & A Memória*: a pedra natural sem ruínas e o silêncio da Sombra ao redor da clareira.
  - **Fenda de Aurora (`#DFBC72`)** → *A Centelha & O Encaixe*: a linha de luz contida que corre exclusivamente pelas **arestas de junção** dos blocos (onde peças se unem, se elevam ou se abrem), expressando o contraste **Luz × Sombra** e a união familiar **sem jamais atravessar texto**.
  - **Alabastro / Calcário Claro (`#EFEADF`)** → *A Intenção Humana & A Obra*: reservado funcionalmente ao ato de **planejar, construir e iniciar ações primárias** — jamais usado como decoração arbitrária.
  - **Placa *ema* substituída pelo Marco de Ciclo:** bloco de basalto chanfrado no mesmo ângulo de `8°`, com fenda luminosa à direita e bandeja rebaixada para velocidade (`|| 1× 2× 4×`), exposição e menu (`☰`).

---

## 2. Solução Sistemática dos 5 Problemas Artísticos da D2 Original

| Problema auditado na D2 original | Diagnóstico real | Solução arquitetural entregue na D2.1 |
|---|---|---|
| **1. Composição fragmentada** | Quatro grupos independentes nos cantos, com ângulos variados e sem gramática unificadora. | **Ângulo arquitetural único de `8°`** em 100% das peças, **prumos verticais sutis** ligando visualmente os blocos nas margens `24 px` sem barra contínua, **bloco unificado de estoques** com 3 bandejas rebaixadas (borda âmbar para `Madeira`/`Alimentos` expostos e ardósia fria para `Pedra` imune — `DEC-11A`) e gramática material funcional única (Basalto = estado/memória, Alabastro = criação/ação). |
| **2. Ornamentação confundida com originalidade** | Polígonos escuros com linhas douradas decorativas passando sobre o conteúdo. | Criação da assinatura funcional **Fenda de Aurora + Encaixe de Pedra**: toda linha dourada marca uma **junta mecânica real de UX** (costura central do Díptico, dobradiça da Laje deslizante, régua superior da Mesa de Maquetes, corte diagonal do Menu onde a chave de alabastro cruza para o mundo 3D). |
| **3. Personagens pouco integrados** | Estelas separadas agindo como cartões verticais de retrato. | **Díptico da Casa Fundadora**: Alden e Brena formam uma peça dupla indivisível unida pelo **Veio da União** central e coroada pelo Emblema; ao selecionar um fundador, sua metade sobe `+12 px` e uma **Laje de Inspeção** desliza acoplada na junta de `8°` exibindo carga física (`UnitCarryLoad`), modo *Pessoal × Comunitário* e vínculo `A ═ B`, com expansão lateral do **Pilar das Gerações (`[H]`)** sem invadir o centro do 3D. |
| **4. Construção ainda convencional** | Dois cartões verticais altos em alabastro empilhados no canto. | **Mesa de Maquetes horizontal em alabastro** ancorada acima da chave `Construir [B]`, com **abas de evolução** (`Nível I` ativo; `Nível II–III` marcados como `PROPOSTA`), miniaturas 3D elevadas sobre o bisel, plantas cotadas (`4×4 m`, `5×4 m`), custos reais do GDD (`D4`), **faixa-chave superior** alternando entre **Prévia Válida** (alabastro/musgo) e **Prévia Inválida** (basalto/terracota com razão real do `PlacementValidator` — `D6`) e **Inspetor de Canteiro** alinhado à esquerda (`DEC-11B`, `D3`, `D9`). |
| **5. Menu desconectado da linguagem** | Lista vertical convencional de faixas sobre fundo escuro. | **Monólito Fendido & Chaves de Pedra na Fenda de Aurora**: a chave primária `INICIAR ASSENTAMENTO` (alabastro claro) **atravessa fisicamente a Fenda de Aurora** para dentro da clareira 3D viva, enquanto as chaves secundárias em basalto chanfrado (`Continuar T3.8`, `Carregar Marco T3.8`, `Configurações`, `Sair`) escalonam-se alinhadas ao ângulo diagonal da fenda. |

---

## 3. Catálogo Completo de Entregáveis (`A`–`G` + Comparativo `H`)

| Entregável | Arquivo PNG | Fonte Editável (HTML/SVG) |
|---|---|---|
| **A — Nova Prancha de Identidade** | [D2_1_A_identity_1920x1080.png](../design/ui-0-r2-1/D2_1_A_identity_1920x1080.png) | [D2_1_A_identity.html](../design/ui-0-r2-1/sources/D2_1_A_identity.html) |
| **B — HUD Normal (`1920×1080`)** | [D2_1_B_hud_1920x1080.png](../design/ui-0-r2-1/D2_1_B_hud_1920x1080.png) | [D2_1_B_hud.html](../design/ui-0-r2-1/sources/D2_1_B_hud.html) |
| **B — HUD Normal (`1280×720`)** | [D2_1_B_hud_1280x720.png](../design/ui-0-r2-1/D2_1_B_hud_1280x720.png) | [D2_1_B_hud.html](../design/ui-0-r2-1/sources/D2_1_B_hud.html) |
| **C — Seleção de Fundador** | [D2_1_C_founder_selection_1920x1080.png](../design/ui-0-r2-1/D2_1_C_founder_selection_1920x1080.png) | [D2_1_C_founder_selection.html](../design/ui-0-r2-1/sources/D2_1_C_founder_selection.html) |
| **D — Construção (Prévia Válida + Canteiro)** | [D2_1_D1_construction_valid_1920x1080.png](../design/ui-0-r2-1/D2_1_D1_construction_valid_1920x1080.png) | [D2_1_D1_construction_valid.html](../design/ui-0-r2-1/sources/D2_1_D1_construction_valid.html) |
| **D — Construção (Prévia Inválida `D6`)** | [D2_1_D2_construction_invalid_1920x1080.png](../design/ui-0-r2-1/D2_1_D2_construction_invalid_1920x1080.png) | [D2_1_D2_construction_invalid.html](../design/ui-0-r2-1/sources/D2_1_D2_construction_invalid.html) |
| **E — Linhagem (Pilar das Gerações)** | [D2_1_E_lineage_1920x1080.png](../design/ui-0-r2-1/D2_1_E_lineage_1920x1080.png) | [D2_1_E_lineage.html](../design/ui-0-r2-1/sources/D2_1_E_lineage.html) |
| **F — Menu Principal (Monólito Fendido)** | [D2_1_F_menu_1920x1080.png](../design/ui-0-r2-1/D2_1_F_menu_1920x1080.png) | [D2_1_F_menu.html](../design/ui-0-r2-1/sources/D2_1_F_menu.html) |
| **G — Storyboard de Comportamento (7 Estados)** | [D2_1_G_behavior_storyboard_1920x1080.png](../design/ui-0-r2-1/D2_1_G_behavior_storyboard_1920x1080.png) | [D2_1_G_behavior_storyboard.html](../design/ui-0-r2-1/sources/D2_1_G_behavior_storyboard.html) |
| **H — Comparativo Direto D2 Original × D2.1** | [D2_1_H_comparison_D2_vs_D2_1_1920x1080.png](../design/ui-0-r2-1/D2_1_H_comparison_D2_vs_D2_1_1920x1080.png) | [D2_1_H_comparison_D2_vs_D2_1.html](../design/ui-0-r2-1/sources/D2_1_H_comparison_D2_vs_D2_1.html) |

### Contrato de Comportamento, `Esc` e Proteção contra *Click-Through*
- **Duração das microtransições:** `120–160 ms` (`Tween.TRANS_CUBIC`, `EASE_OUT`) — responsivas, jamais bloqueiam cliques rápidos consecutivos.
- **Hierarquia determinística da tecla `Esc`:**
  1. Se houver prévia de construção no terreno → solta a prévia sem cancelar tarefas comunitárias;
  2. Se a Mesa de Maquetes estiver aberta → recolhe a Mesa de Maquetes;
  3. Se o Pilar de Linhagem ou Inspetor de Canteiro estiver aberto → fecha o painel contextual;
  4. Se houver seleção RTS de habitante(s) → limpa seleção e recolhe a elevação do Díptico + Laje de Inspeção;
  5. Em repouso absoluto → abre/fecha o Monólito de Pausa.
  - **Regra preservada (`RUX-0 §4.1`):** `Esc` **nunca** cancela silenciosamente tarefas comunitárias de coleta ativas no mapa.
- **Anti-*click-through*:** container raiz da HUD usa `Control.MOUSE_FILTER_IGNORE` (todo espaço livre repassa clique/arraste/zoom diretamente ao 3D); toda placa sólida de basalto/alabastro e botão interativo usa `Control.MOUSE_FILTER_STOP`.

---

## 4. Showcase Interativo Godot 4.7.2, Correção das Sobreposições e Fidelidade

### 4.1 Como reproduzir e testar interativamente
- **Modo automatizado (capturas + benchmark A/B sem V-Sync):**
  ```powershell
  .\docs\design\ui-0-r2-1\godot_showcase\run_ui0_r2_1_showcase.ps1
  ```
- **Modo interativo ao vivo (isolado, sem modificar gameplay):**
  ```powershell
  .\docs\design\ui-0-r2-1\godot_showcase\run_ui0_r2_1_showcase.ps1 -Interactive
  ```
  - Clique em **Alden** ou **Brena** (ou teclas `1` / `2`): eleva a metade selecionada do Díptico (`Tween 140 ms`), ilumina a Fenda de Aurora e abre a Laje de Inspeção com botão funcional `Liberar · P-RUX-2`.
  - Clique em **Construir [B]** (ou tecla `B`): abre a Mesa de Maquetes em Alabastro (seleção entre `Abrigo Básico` e `Depósito Rústico`), exibe o Inspetor de Canteiro e a Faixa de Validação no topo (clique na faixa ou pressione `V` para alternar **Terreno Válido × Bloqueado D6**).
  - Clique em **`☰`** ou pressione **`Esc`**: executa a hierarquia completa de desfazimento e abre/fecha o Monólito de Pausa.

### 4.2 Evidências visuais de correção das sobreposições (Auditoria Seção 4.1)
Na captura da R2 ([`G_godot_D2_marcos_kintsugi_1280x720.png`](../design/ui-0-r2/G_godot_D2_marcos_kintsugi_1280x720.png)), linhas douradas diagonais desenhadas no meio dos polígonos cruzavam diretamente os rótulos `MAD 24`, `PED 14`, `ALI 18`, `Ano I`, `Brena` e `Linhagem [H]`, e a palavra `Construir` encostava na borda direita.

Na R2.1, todas as 12 peças foram pré-assadas no Atlas 2D [`d2_1_ui_atlas.png`](../design/ui-0-r2-1/assets/d2_1_ui_atlas.png) ([`atlas_manifest.json`](../design/ui-0-r2-1/assets/atlas_manifest.json)) com **veios restritos às arestas externas de encaixe** e **bandejas rebaixadas de texto**, respeitando o viewport lógico `canvas_items` (`1920×1080`) do `project.godot`. Todas as 5 capturas reais da Godot foram auditadas visualmente:

| Captura real da Godot 4.7.2 | Estado demonstrado e verificação visual |
|---|---|
| [G_godot_D2_1_rest_1280x720.png](../design/ui-0-r2-1/G_godot_D2_1_rest_1280x720.png) | HUD em repouso (`1280×720`): 4 cantos ancorados com precisão, **zero linhas sobre texto**, `● Exposto` separado de `☰`, `Construir` com margem ampla, >93% do 3D livre. |
| [G_godot_D2_1_rest_1920x1080.png](../design/ui-0-r2-1/G_godot_D2_1_rest_1920x1080.png) | HUD em repouso (`1920×1080`): mesma clareza tipográfica e texturas reais de basalto/alabastro. |
| [G_godot_D2_1_founder_selected_1280x720.png](../design/ui-0-r2-1/G_godot_D2_1_founder_selected_1280x720.png) | Interação real: Alden elevado, Fenda iluminada, Laje de Inspeção acoplada (`Carga: 8 / 20 peso (40%)`, `Liberar · P-RUX-2`, `VÍNCULO A ═ B`) sem nenhuma colisão de rótulo. |
| [G_godot_D2_1_construction_1280x720.png](../design/ui-0-r2-1/G_godot_D2_1_construction_1280x720.png) | Interação real: Mesa de Maquetes em Alabastro, Faixa de Validação no topo (`TERRENO VÁLIDO · Depósito (5x4 m)`) e Canteiro à esquerda (`Abrigo Básico · 42%`), zero sobreposição. |
| [G_godot_D2_1_pause_1280x720.png](../design/ui-0-r2-1/G_godot_D2_1_pause_1280x720.png) | Interação real: Monólito de Pausa centralizado com escurecimento atmosférico e mesma identidade de basalto chanfrado. |

### 4.3 Diferenças registradas honestamente entre Mockups e Showcase Godot (Seção 4.2 e Seção 6)
A distância visual entre mockups e Godot foi **drasticamente reduzida** graças ao Atlas 2D real (`d2_1_ui_atlas.png` com textura de basalto, textura de alabastro, sombras suaves, bandejas rebaixadas e veios nas arestas), porém **não declaramos paridade de 100%**. Permanecem diferenças conhecidas, propositalmente mantidas fora do escopo do protótipo isolado:
1. Os **ícones vetoriais minerais** (árvore, rocha, fruto, sol, tarefas, linhagem) presentes nos mockups HTML ainda aparecem no protótipo Godot como rótulos textuais limpos (`MAD`, `PED`, `ALI`, `☰`); na futura `UI-1` eles serão incluídos no mesmo Atlas 2D.
2. As **abas de evolução** (`Nível I / II / III`) sobre a Mesa de Maquetes, o **Pilar de Linhagem completo (`[H]`)** e o **Menu Principal completo (`D2_1_F`)** estão especificados nos mockups e não foram replicados integralmente no script isolado (que priorizou HUD de repouso, Seleção de Fundador, Construção/Validação e Pausa).
3. As **linhas de prumo sutis** nas bordas laterais dos mockups foram omitidas do protótipo Godot para manter a cena limpa enquanto não existe integração com câmera/Edge Pan real.

---

## 5. Benchmark Empírico Reproduzível: Procedural × Atlas 2D (Sem V-Sync)

### 5.1 Metodologia e ambiente medido
- **Script:** [`docs/design/ui-0-r2-1/godot_showcase/ui0_r2_1_d2_showcase.gd`](../design/ui-0-r2-1/godot_showcase/ui0_r2_1_d2_showcase.gd)
- **Dados brutos:** [`docs/design/ui-0-r2-1/godot_showcase/benchmark_results_r2_1.json`](../design/ui-0-r2-1/godot_showcase/benchmark_results_r2_1.json)
- **Configuração:** `Godot Engine v4.7.2.stable.official.ed1daf0bf`, `OpenGL API 3.3.0 - Build 30.0.101.1339 - Compatibility`, `Intel(R) UHD Graphics 620`, **`DisplayServer.VSYNC_DISABLED` (`vsync_mode = 0`)**, `60` quadros de aquecimento por bloco, `3` rodadas intercaladas × `180` quadros = **`540` quadros válidos por cenário e resolução** (`logical = 1920×1080` via `canvas_items`).
- **Cenários comparados no mesmo run contra baseline equivalente:**
  1. `BASELINE_3D`: cena 3D real (`MainScene`) com HUD legada oculta.
  2. `D2_1_PROCEDURAL_REST`: HUD D2.1 em repouso desenhada com polígonos/linhas procedurais (`Control._draw()`).
  3. `D2_1_ATLAS_REST`: exatamente a mesma HUD D2.1 em repouso renderizada a partir do **Atlas 2D pré-assado** (`d2_1_ui_atlas.png` + `AtlasTexture`).
  4. `D2_1_ATLAS_ACTIVE`: HUD D2.1 via Atlas com **Seleção de Fundador + Mesa de Maquetes + Faixa de Validação + Inspetor de Canteiro abertos simultaneamente**.

### 5.2 Resultados exatos medidos (`benchmark_results_r2_1.json`)

#### Resolução `1280×720` (`logical = 1920×1080`, V-Sync OFF)
| Cenário | Média mediana (ms) | `p95` mediano (mín..máx) (ms) | `p99` mediano (mín..máx) (ms) | `> 100 ms` | Draw calls | Nós |
|---|---:|---|---|---:|---:|---:|
| `BASELINE_3D` | `4,606` | `6,501` (`3,979..7,192`) | `7,932` (`4,285..8,368`) | `0` | `117` | `382` |
| `D2_1_PROCEDURAL_REST` | `8,141` | `11,614` (`4,959..11,649`) | `14,178` (`5,360..14,315`) | `0` | `190` (`+73`) | `415` |
| `D2_1_ATLAS_REST` | `6,550` | `8,209` (`4,905..8,633`) | `9,231` (`5,260..9,834`) | `0` | `157` (`+40`) | `479` |
| `D2_1_ATLAS_ACTIVE` | `4,154` | `5,646` (`5,372..9,539`) | `6,604` (`5,756..10,231`) | `0` | `188` (`+71`) | `479` |

#### Resolução `1920×1080` (`logical = 1920×1080`, V-Sync OFF)
| Cenário | Média mediana (ms) | `p95` mediano (mín..máx) (ms) | `p99` mediano (mín..máx) (ms) | `> 100 ms` | Draw calls | Nós |
|---|---:|---|---|---:|---:|---:|
| `BASELINE_3D` | `7,244` | `10,102` (`8,274..11,101`) | `15,736` (`9,189..16,230`) | `0` | `117` | `382` |
| `D2_1_PROCEDURAL_REST` | `8,616` | `11,121` (`10,901..11,939`) | `12,465` (`12,107..14,274`) | `0` | `190` (`+73`) | `415` |
| `D2_1_ATLAS_REST` | `8,416` | `12,311` (`10,615..12,638`) | `13,894` (`12,978..14,982`) | `0` | `157` (`+40`) | `479` |
| `D2_1_ATLAS_ACTIVE` | `8,600` | `11,929` (`11,610..12,746`) | `13,977` (`13,253..14,962`) | `0` | `188` (`+71`) | `479` |

### 5.3 Interpretação técnica honesta e limitações (Seção 4.3)
1. **Avaliação empírica do Atlas 2D (`d2_1_ui_atlas.png`):**
   - **Ganho determinístico confirmado em draw calls:** o Atlas reduziu o acréscimo de draw calls em repouso de `+73` (`190`) para `+40` (`157`) — economia de **`-33` draw calls (`-45,2%` do overhead de UI)** — enquanto elevou drasticamente a fidelidade visual (texturas reais de basalto e alabastro + sombras + biséis antialiados). Mesmo em `D2_1_ATLAS_ACTIVE` (com seleção + construção + inspetor todos abertos simultaneamente), os draw calls (`188`) permaneceram abaixo da versão procedural em repouso (`190`).
   - **Sem promessa infundada em milissegundos em `1080p`:** em `1920×1080`, todas as rodadas de todos os cenários ficaram abaixo de `15 ms` mesmo em `p99` (`0` quadros `> 100 ms`), com custo adicional típico de ~`1,2–1,4 ms` na média sobre o `BASELINE_3D` (`7,244 ms`). Entretanto, as faixas de `p95` entre `PROCEDURAL_REST` (`10,901..11,939 ms`), `ATLAS_REST` (`10,615..12,638 ms`) e `ATLAS_ACTIVE` (`11,610..12,746 ms`) **se sobrepõem** — logo, o benefício comprovado do Atlas aqui é **fidelidade visual + redução determinística de draw calls**, não uma redução mensurável isolada de `p95` em 1080p.
2. **Variabilidade entre rodadas (transparência):**
   - Em `1280×720`, observou-se oscilação relevante entre rodadas (ex.: `BASELINE_3D` `p95` de `3,979` a `7,192 ms`; `D2_1_ATLAS_ACTIVE` apresentou média mediana `4,154 ms` menor que `BASELINE_3D` `4,606 ms`). Essa inversão demonstra influência de escalonamento dinâmico de clock/energia da Intel UHD Graphics 620 e do sistema operacional; portanto, **diferenças de `1–2 ms` não devem ser atribuídas exclusivamente à HUD**.
3. **Diferença em relação ao baseline da R2 (`11,856 ms`, `dc=217`):**
   - Na R2.1, a ocultação limpa de toda a HUD legada na cena de referência reduziu o `BASELINE_3D` de `217` para `117` draw calls (`537` → `382` nós). As medições devem ser lidas sempre contra o baseline equivalente desta suíte (`117` draw calls).
4. **Limites obrigatórios (o que este benchmark NÃO comprova):**
   - **Não comprova estabilidade de 60 FPS em gameplay completo**, pois a cena base foi medida sem múltiplos ciclos ativos de IA/navegação/construção simultâneos nem comparação formal de alimentação CA × bateria DC.
   - Qualquer otimização adicional futura (ex.: consolidar ícones e labels repetidos ou otimizar `CLIP_CHILDREN_AND_DRAW` em retratos) permanece **hipótese futura não medida** até ser implementada e validada na `UI-1`.

---

## 6. Compatibilidade com Sistemas Existentes, Recursos Futuros e Pendências

### 6.1 Mapeamento limpo para os controladores reais (somente referência arquitetural — `UI-1` bloqueada)
- **Top-Left Stockpile Monolith** ← `SettlementStockpilePanel` (`src/ui/settlement_stockpile_panel.gd`, orientado a `SettlementInventory.inventory_changed`, zero polling).
- **Díptico + Laje de Inspeção** ← `SelectedUnitPanel` (`src/ui/selected_unit_panel.gd`, orientado a `SelectionManager.selection_changed` e sinais de `UnitCarryLoad`).
- **Mesa de Maquetes + Faixa de Validação** ← `ConstructionHud` (`src/ui/construction_hud.gd`) + `PlacementController` / `PlacementValidator` (`D6`).
- **Inspetor de Canteiro** ← `BuildingInspectorPanel` (`src/ui/building_inspector_panel.gd`, preservando `DEC-11B` e `D3` enquanto vigentes).
- **Feedback leve de coleta comunitária** ← `AutonomousGatherFeedback` (`src/ui/autonomous_gather_feedback.gd`, `PRESET_CENTER_TOP`, `MOUSE_FILTER_IGNORE`).

### 6.2 Separação estrita: Implementado × Proposta Futura
- **Apoiado em código existente (`IMPLEMENTADO` / `RUX`):** `Madeira`/`Pedra`/`Alimentos`, `Exposto` (`DEC-11A`), `Alden`/`Brena`, `UnitCarryLoad` (`peso / 20`, `4,8 → 2,88 m/s`), `Abrigo Básico` (`12 Mad · 6 Ped · 4×4 m · 30 s`), `Depósito Rústico` (`18 Mad · 10 Ped · 5×4 m · 45 s`), validação `D6` (`≤ 10°`, exclusão da `CampStorageZone`), inspetor `DEC-11B` / `D3`, coleta comunitária `RUX-1/2A/2B`.
- **Explicitamente marcado como `PROPOSTA` (futuro — NÃO implementado):** Ciclo/Calendário (`Ano I · Ciclo 1`, `T4`), abas `Nível II–III` (GDD §6), `Continuar`/`Carregar`/`Salvar` (`T3.8`), `Geração II · Descendentes` e fases de vida (`T5`), `Alento` (`T6`), e ação `Liberar p/ Comunidade` (`P-RUX-2`).

### 6.3 Pendências abertas preservadas integralmente
- `UX-1` (3 testes manuais pendentes), `RUX-1` / `RUX-2A` / `RUX-2B` (aceite manual), `T3.6.4-R1` (`D3-04` e `D3-07`), decisões `P-RUX-1`, `P-RUX-2`, `P-RUX-3`, `P-RUX-4`, `P-RUX-6`, e classificação de benchmark DC da T2 (`AGENTS.md`).

### 6.4 Decisões que exigem deliberação do proprietário
1. **Aprovação artística da Direção D2.1:** aprovar a linguagem unificada *Marcos de Pedra e Eclipse (D2.1)* como base oficial de identidade visual para especificar a futura `UI-1`, ou solicitar ajustes pontuais em algum componente (`HUD`, `Díptico`, `Mesa de Maquetes`, `Linhagem` ou `Menu`).
2. **Autorização explícita futura para `UI-1`:** somente após aprovação expressa desta proposta (nenhum código de produção foi alterado nem será iniciado sem nova ordem).
3. **Definição oportuna de `P-RUX-2`:** impactará futuramente se o botão `Liberar p/ Comunidade` na Laje de Inspeção da D2.1 será necessário em produção.
