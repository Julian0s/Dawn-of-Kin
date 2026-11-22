# DAWN OF KIN — UI-0 R2: OPERAÇÃO IDENTIDADE (PROPOSTA)

> **Status:** `PROPOSTA` — Estudo de identidade visual, direção de arte e validação técnica isolada na Godot 4.7.2.  
> **Decisão pendente:** Aprovação, escolha ou pedido de revisão **exclusivamente pelo proprietário**. Nenhuma direção está aprovada; nenhuma implementação de `UI-1` foi iniciada.  
> **Branch documental:** `design/ui-0-r2-identity` (derivada de `design/ui-0-r1-art-direction` @ `c45f15c251737d8f38ec77aa46837d3e5c8bf5f1`).  
> **Escopo respeitado:** Zero alterações em código de gameplay, cenas de produção, economia, RTS, seleção, construção, RUX, testes automatizados, `AGENTS.md`, `docs/Dawn_of_Kin_GDD.md`, `main`, branches anteriores ou no diretório protegido `C:\Projetos\Dawn of Kin`.

---

## 1. Diagnóstico Honesto das Reprovações Anteriores (UI-0 e UI-0 R1)

### 1.1 Por que UI-0 e UI-0 R1 foram reprovadas
1. **UI-0 (reprovada visualmente):** parecia um conjunto de janelas de software convencional — retângulos escuros/bege organizados como dashboard administrativo, sem personalidade autoral de jogo comercial.
2. **UI-0 R1 (Conceitos A, B e C todos reprovados):** embora tenha elevado materiais, tipografia e limpeza de tela em relação à UI-0, os três conceitos ainda partiam de **barras retangulares e caixas de diálogo convencionais** apenas vestidas com texturas (madeira/ferro em A, papel em B, ardósia/dourado em C).
3. **Leitura correta da decisão do proprietário (*"Gostei mais C, me mostre algo mais original"*):**
   - O que **agradou** no antigo Conceito C: elegância contida, sobriedade, excelente contraste sobre a grama 3D, destaque respeitoso aos fundadores Alden e Brena, e sensação de calma estratégica sem poluir o cenário.
   - O que **faltou** para aprovação: uma **assinatura formal própria de Dawn of Kin** — abandonar barras retangulares genéricas e criar silhuetas, metáforas táteis e comportamentos contextuais que tornem a interface imediatamente reconhecível mesmo sem o logotipo.

### 1.2 Falhas técnicas da R1 corrigidas na R2
| Falha identificada na UI-0 R1 | Correção estrutural aplicada nesta UI-0 R2 |
|---|---|
| Protótipos Godot (`G1–G3`) eram visivelmente mais simples que os mockups e 9-slices decorativos invadiam áreas de texto. | Substituição de molduras 9-slice genéricas por **silhuetas esculturais nativas na Godot 4.7.2** (`Control._draw()` antialiased + `CLIP_CHILDREN_AND_DRAW` para retratos circulares + fontes reais do sistema + miniaturas/ativos autorais), com zero invasão de bordas sobre texto. |
| Benchmark preliminar rodou apenas `45` quadros, com **V-Sync ligado**, sem script reproduzível versionado na branch. | Criação de runner reproduzível de um comando (`docs/design/ui-0-r2/godot_showcase/run_ui0_r2_showcase.ps1` + `ui0_r2_godot_showcase.gd`), com **`DisplayServer.VSYNC_DISABLED`**, `60` quadros de aquecimento, `3` repetições intercaladas × `180` quadros = **`540` quadros válidos por cenário**, medidos em **`1280×720` e `1920×1080`** com resultados brutos salvos em `benchmark_results.json`. |
| Pouca divergência estrutural entre conceitos (variações de cor/textura sobre o mesmo esqueleto de HUD). | Criação de **três direções radicalmente distintas em silhueta, materialidade, ancoragem, construção, linhagem e Menu Principal** — nenhuma delas usa barras retangulares convencionais. |

---

## 2. Núcleo Narrativo, Referências e Auditoria de Biblioteca

### 2.1 Identidade temática que governa o design
*Dawn of Kin* não é um jogo de guerra medieval clichê nem um simulador burocrático de planilhas. Sua coluna vertebral narrativa (GDD v1.0 + proposta RUX-0) segue o arco:

> **ORIGEM → UNIÃO → DESCOBERTA → CONSTRUÇÃO → CONTINUIDADE → CIVILIZAÇÃO**

Dois fundadores (**Alden** e **Brena**) chegam a uma clareira intocada. O jogador orienta o trabalho comunitário por intenção (RUX-1, RUX-2A, RUX-2B), mantém vínculo pessoal com a **Casa Fundadora**, ergue estruturas físicas com peso real e, nos ciclos futuros do GDD (**PROPOSTA**), vê gerações nascerem (T5), estações virarem (T4) e o acampamento evoluir do **Nível I ao Nível V** (até a futura travessia ao arquipélago e a dualidade Luz × Sombra).

### 2.2 Repertório estudado (inspiração conceitual sem cópia)
Em vez de copiar interfaces prontas de RTS clássicos (barras inferiores cheias de botões quadrados), o estudo da R2 cruzou quatro famílias de linguagem visual:
1. **Instrumentos de orientação e astronomia antiga (astrolábios, anéis orbitais e linhas de horizonte)** — inspira a *Direção 1*.
2. **Escultura lítica, *kintsugi* japonês, placas *ema* e maquetes arquitetônicas de contraste claro/escuro** — inspira a *Direção 2*.
3. **Artesanato orgânico vivo: cerâmica esmaltada fosca, linho cru tramado, sementes e herbanários botânicos** — inspira a *Direção 3*.
4. **Interfaces de revelação contextual progressiva:** em repouso, > 92% do mundo 3D permanece livre; a interface **se transforma fisicamente** (abre em arco, eleva uma estela ou desenrola uma faixa) apenas quando o jogador seleciona um fundador ou ativa o modo de construção.

### 2.3 Auditoria da Biblioteca do Google Drive e Ferramentas Godot
A auditoria realizada na biblioteca pública `https://drive.google.com/drive/folders/19yISOiB7Zw5xeIE6fSYcmCWeKlO37FTh` (`CATALOGO.md` e `09_Documentacao/LICENCAS.csv`, 41 registros verificados em R1) permanece válida e foi estritamente respeitada:
- **Pacotes restritos (`emberhold`, `gravewatch`, `ui-kit-sampler`, `GildedFantasyUIKit_Lite`):** proibidos de redistribuição em repositório público e de uso para treino de IA. **Zero arquivos desses pacotes foram baixados, copiados ou usados.**
- **Pacote CC0 (`kenney_fantasy-ui-borders`) e ferramentas Godot MIT (`theme_assist`, `UI_Builder`, `dot-ui`, `G.U.I.D.E`):** úteis como referência de arquitetura de tema/input em etapas futuras, porém **nenhuma moldura pronta foi aplicada na R2**, justamente porque molduras genéricas destruíram a originalidade na R1.
- **Conclusão técnica para Godot 4.7.2:** para entregar uma interface verdadeiramente autoral em `gl_compatibility` (Intel UHD Graphics 620), a combinação ideal é:
  - `Theme` nativo da Godot para tipografia, espaçamento e foco de teclado;
  - silhuetas customizadas via `Control._draw()` (usado no protótipo R2) **ou** um único **Texture Atlas PNG 2D pré-assado** com `AtlasTexture` (recomendação para `UI-1` de produção, reduzindo o custo de draw calls mantendo 100% da silhueta autoral);
  - `CLIP_CHILDREN_AND_DRAW` para máscaras circulares/orgânicas de retratos sem shaders pesados.

---

## 3. As Três Direções Artísticas Inéditas

Todas as três direções possuem:
- prancha de identidade densa (`A`),
- HUD normal sobre capturas reais em `1920×1080` e `1280×720` (`B`),
- fluxo completo de construção sobre captura real (`C`),
- visualização contextual de personagens e linhagem sobre captura real (`D`),
- Menu Principal memorável sobre o mundo vivo (`E`),
- protótipo interativo renderizado ao vivo na Godot 4.7.2 (`G_godot_D1/D2/D3`).

---

### Direção 1 — "O Fio da Aurora" *(Evolução Radical do Conceito C)*

- **Pranchas:** [D1_A Identidade](../design/ui-0-r2/D1_A_identity_1920x1080.png) · [D1_B HUD 1080p](../design/ui-0-r2/D1_B_hud_1920x1080.png) · [D1_B HUD 720p](../design/ui-0-r2/D1_B_hud_1280x720.png) · [D1_C Construção](../design/ui-0-r2/D1_C_construction_1920x1080.png) · [D1_D Linhagem](../design/ui-0-r2/D1_D_lineage_1920x1080.png) · [D1_E Menu](../design/ui-0-r2/D1_E_menu_1920x1080.png) · [Godot 720p](../design/ui-0-r2/G_godot_D1_fio_da_aurora_1280x720.png) · [Godot 1080p](../design/ui-0-r2/G_godot_D1_fio_da_aurora_1920x1080.png)
- **Tese estética:** Preserva a sobriedade noturna, o dourado sereno e o respeito à linhagem que agradaram no antigo Conceito C, mas **elimina 100% das barras retangulares permanentes**. Toda a interface vive como um instrumento astronômico delicado flutuando sobre o terreno: fios finos de ouro, seixos circulares de matéria, um astrolábio de quatro estações e um **Nó da Origem** orbital onde Alden e Brena orbitam o emblema da família.

#### Respostas às 9 Perguntas Obrigatórias (Direção 1)
1. **O que torna esta interface impossível de confundir com outro jogo?**  
   A ausência total de barras e caixas retangulares em repouso combinada ao trio escultural: **3 Seixos de Matéria enfiados num fio dourado** (topo esquerdo), **Astrolábio Sazonal flutuante** (topo direito) e **Nó da Origem orbital** (base central) que desabrocha num **leque semicircular de raízes** ao selecionar um fundador — além do Menu Principal em **Portal do Anel da Origem** emoldurando o acampamento 3D vivo ao centro.
2. **Como ela reflete o tema de Dawn of Kin?**  
   O fio dourado representa a continuidade do sangue; os dois anéis fundadores conectados ao emblema central simbolizam *União* e *Origem*; o astrolábio expressa *Descoberta* e passagem dos ciclos; a *Rosa de Construção* organiza o crescimento do assentamento por círculos concêntricos de maturidade civilizacional.
3. **Qual elemento central ou mecânica visual é assinatura exclusiva dela?**  
   O **Nó da Origem Orbital** (que se expande em arco semicircular de linhagem com anel radial de carga física ao clicar em Alden/Brena) em par com a **Rosa de Construção Semicircular** no canto inferior direito, onde miniaturas 3D pintadas das edificações flutuam sobre anéis concêntricos.
4. **Como organiza recursos, tempo, fundadores, construção, tarefas e menus sem parecer formulário ou barra genérica?**  
   - *Recursos:* 3 seixos circulares com anel tracejado de exposição (sem caixa ao redor), conectados por um único fio horizontal.
   - *Tempo e Estação:* texto flutuante com sombra suave ao lado do astrolábio circular + micro-nós redondos de velocidade (`|| 1× 2× 4× ☰`).
   - *Fundadores e Tarefas:* dois medalhões orbitais flutuantes com botões satélites (`Tarefas [T]` e `Construir [B]`) apoiados sobre dois arcos abertos.
   - *Construção:* Rosa Semicircular no canto inferior direito + faixa-horizonte delgada no topo validando o terreno plano, mantendo o centro do mapa livre.
   - *Menu Principal:* grande anel portal centralizado no acampamento 3D com os botões curvados ao longo do arco inferior.
5. **Como se comporta em repouso vs em ação?**  
   Em repouso, ~94% do cenário 3D fica livre e sem nenhuma janela aberta. Ao selecionar Alden, o Nó da Origem **floresce em 140 ms** revelando o leque de raízes, o arco radial de carga (`40%`), o controle *Pessoal vs Comunitário* e o broto pontilhado da futura 1ª geração (`T5`). Ao apertar `[B]`, a Rosa de Construção se abre no canto inferior direito e o pivô central exibe o progresso radial da obra ativa (`42%`). `Esc` recolhe suavemente de volta ao repouso.
6. **Como funciona em `1280×720` e `1920×1080` sem poluir a tela?**  
   Validada nas duas resoluções (mockups `D1_B` e capturas reais `G_godot_D1`). Por usar elementos compactos ancorados em pontos focais (e não faixas contínuas de ponta a ponta), o escalonamento proporcional (`~82%` em 720p) mantém folga generosa para *Edge Pan*, leitura imediata dos números tabulares e zero colisão entre grupos.
7. **Como evolui visualmente conforme o assentamento cresce (Nível I → V — PROPOSTA)?**  
   - *Nível I (Acampamento):* fio simples fino e seixos foscos rústicos; apenas o arco interno da Rosa de Construção aceso.
   - *Nível III (Povoado — PROPOSTA):* arcos duplos em bronze polido com detalhes cerâmicos; abertura do segundo anel de construção.
   - *Nível V (Vila — PROPOSTA):* astrolábio completo de latão e marfim com anéis graduados e constelação expandida de linhagem, mantendo 100% da mesma memória muscular e posições.
8. **Maiores forças artísticas e de UX:**  
   Elegância de jogo autoral AAA/indie premium; altíssima respiração do cenário 3D; forte continuidade com o que o proprietário já aprovou no espírito do antigo Conceito C, porém elevado a uma identidade inconfundível; leitura excelente sobre verde/pedra/sombra.
9. **Maiores riscos ou limitações:**  
   Formas curvas e múltiplas chamadas `_draw()` de arcos elevam o custo de draw calls se desenhadas proceduralmente a cada quadro (no protótipo Godot, `+67` draw calls); exige pré-assar os arcos e anéis em um **Texture Atlas único** na `UI-1` para manter `p99` baixo em `1080p`. Além disso, futuras janelas densas (ex.: árvore genealógica com > 12 descendentes em T5) precisarão de uma tela modal dedicada harmonizada com o anel, pois o leque semicircular tem limite confortável para 2–5 membros próximos.

---

### Direção 2 — "Marcos de Pedra e Eclipse" *(Monólitos Kintsugi & Maquetes de Alabastro)*

- **Pranchas:** [D2_A Identidade](../design/ui-0-r2/D2_A_identity_1920x1080.png) · [D2_B HUD 1080p](../design/ui-0-r2/D2_B_hud_1920x1080.png) · [D2_B HUD 720p](../design/ui-0-r2/D2_B_hud_1280x720.png) · [D2_C Construção](../design/ui-0-r2/D2_C_construction_1920x1080.png) · [D2_D Linhagem](../design/ui-0-r2/D2_D_lineage_1920x1080.png) · [D2_E Menu](../design/ui-0-r2/D2_E_menu_1920x1080.png) · [Godot 720p](../design/ui-0-r2/G_godot_D2_marcos_kintsugi_1280x720.png) · [Godot 1080p](../design/ui-0-r2/G_godot_D2_marcos_kintsugi_1920x1080.png)
- **Tese estética:** Escultura monolítica assimétrica inspirada em pedras vulcânicas, estelas memoriais, reparos *kintsugi* dourados e placas *ema* japonesas — dialogando diretamente com a futura identidade do arquipélago e a dualidade **Luz × Sombra** do GDD. Seu contraste tátil exclusivo opõe a **HUD em basalto escuro** às **peças de construção em alabastro claro**, criando a sensação física de segurar maquetes de pedra clara sobre o terreno 3D.

#### Respostas às 9 Perguntas Obrigatórias (Direção 2)
1. **O que torna esta interface impossível de confundir com outro jogo?**  
   Nenhuma silhueta possui ângulos de 90° triviais: cada bloco é um polígono chanfrado assimétrico (`12°–16°`) com textura de basalto e finos veios dourados *kintsugi*, contraposto a **placas claras de alabastro** reservadas exclusivamente ao ato de construir e à ação principal — além do Menu Principal cortado por um monólito diagonal fendido a ouro.
2. **Como ela reflete o tema de Dawn of Kin?**  
   Conecta a sobrevivência na terra bruta (pedras empilhadas em *cairn*) à ideia de deixar marcos permanentes na história (*Marcos de Pedra*) e antecipa de forma coesa a estética de santuário, travessia e contraste Luz/Sombra prevista no horizonte narrativo do GDD.
3. **Qual elemento central ou mecânica visual é assinatura exclusiva dela?**  
   O **Sistema de Estelas Eleváveis + Maquetes de Alabastro**: no canto inferior esquerdo, Alden e Brena vivem como duas estelas inclinadas que **se elevam fisicamente** ao serem selecionadas; no canto inferior direito, a prancha de construção alterna o material do basalto escuro para **alabastro claro**, tornando impossível confundir modo normal com modo de construção.
4. **Como organiza recursos, tempo, fundadores, construção, tarefas e menus sem parecer formulário ou barra genérica?**  
   - *Recursos:* três pedras assimétricas escalonadas em desnível sutil (como um *cairn* de trilha).
   - *Tempo e Estação:* placa *ema* suspensa no topo direito com topo em cumeeira suave.
   - *Fundadores:* par de estelas inclinadas no canto inferior esquerdo; ao clicar em Alden, uma laje contextual de basalto se estende ao lado mostrando carga física e a **Pilha da Linhagem** (blocos empilhados de gerações).
   - *Construção:* bandeja de peças em alabastro claro no canto inferior direito com miniaturas arquitetônicas + placa de obra ativa em basalto no topo esquerdo.
   - *Menu Principal:* monólito diagonal de basalto ocupando o terço esquerdo, cortado por um filete de ouro contínuo, deixando dois terços do cenário 3D respirando à direita.
5. **Como se comporta em repouso vs em ação?**  
   Em repouso, apenas quatro agrupamentos pétreos pequenos ocupam os quatro cantos extremos, deixando todo o corredor central (horizontal e vertical) desobstruído. Ao selecionar um fundador, sua estela sobe `22 px` com acento dourado e desliza a ficha de carga/linhagem. Ao entrar em construção (`[B]`), as maquetes de alabastro se destacam visualmente sobre a cena, e a faixa de validação no topo confirma terreno plano.
6. **Como funciona em `1280×720` e `1920×1080` sem poluir a tela?**  
   Excelente escalabilidade em ambas as resoluções (`D2_B` e `G_godot_D2`), pois os polígonos chanfrados mantêm leitura nítida mesmo em larguras reduzidas e preservam alto contraste (ouro/marfim sobre basalto, tinta escura sobre alabastro).
7. **Como evolui visualmente conforme o assentamento cresce (Nível I → V — PROPOSTA)?**  
   - *Nível I (Acampamento):* pedras rústicas brutas em equilíbrio (*cairn*) com chanfros irregulares.
   - *Nível III (Povoado — PROPOSTA):* estelas talhadas com veios *kintsugi* mais definidos e inscrições sutis.
   - *Nível V (Vila — PROPOSTA):* marcos monumentais combinando basalto polido e encaixes de alabastro, celebrando a maturidade arquitetônica sem alterar a disposição dos comandos.
8. **Maiores forças artísticas e de UX:**  
   Silhueta extremamente marcante e memorável; contraste de leitura impecável (WCAG AAA tanto no basalto quanto no alabastro); distinção tátil instantânea entre "observar/gerir" (escuro) e "construir/agir" (claro); grande compatibilidade com janelas futuras mais informativas (polígonos chanfrados acomodam tabelas e árvores genealógicas sem esforço).
9. **Maiores riscos ou limitações:**  
   O clima mais dramático e monolítico pode parecer um pouco mais "severo/misterioso" do que "acolhedor/familiar" nos primeiros minutos da clareira ensolarada. Exige cuidado cirúrgico com margens internas de texto próximas aos chanfros diagonais (como observado no micro-ajuste de padding do botão `Construir` na captura Godot `G_godot_D2`, facilmente corrigível).

---

### Direção 3 — "Tear de Trama e Semente" *(Cerâmica Fosca, Linho Tramado & Botânica Viva)*

- **Pranchas:** [D3_A Identidade](../design/ui-0-r2/D3_A_identity_1920x1080.png) · [D3_B HUD 1080p](../design/ui-0-r2/D3_B_hud_1920x1080.png) · [D3_B HUD 720p](../design/ui-0-r2/D3_B_hud_1280x720.png) · [D3_C Construção](../design/ui-0-r2/D3_C_construction_1920x1080.png) · [D3_D Linhagem](../design/ui-0-r2/D3_D_lineage_1920x1080.png) · [D3_E Menu](../design/ui-0-r2/D3_E_menu_1920x1080.png) · [Godot 720p](../design/ui-0-r2/G_godot_D3_tear_semente_1280x720.png) · [Godot 1080p](../design/ui-0-r2/G_godot_D3_tear_semente_1920x1080.png)
- **Tese estética:** Ruptura completa com a estética *dark fantasy / metal medieval*. Celebra o calor humano, a natureza viva, a sobrevivência artesanal e o florescimento da família usando **cerâmica esmaltada fosca (verde musgo e terracota)**, **linho cru tramado**, costuras sutis e formas orgânicas assimétricas (bordas em folha/semente).

#### Respostas às 9 Perguntas Obrigatórias (Direção 3)
1. **O que torna esta interface impossível de confundir com outro jogo?**  
   Enquanto 95% dos jogos de estratégia medievais apostam em metal escuro ou pergaminho gasto, esta direção veste a interface como um **artefato têxtil e cerâmico**: um **Cordão de Sementes** de cerâmica para os recursos, uma **Roseta Botânica de 4 Pétalas** para as estações, um **Ninho Familiar** de discos sobrepostos com broto verde, **fichas físicas de matéria** nos custos de construção e um **Estandarte de Linho Suspenso** no Menu Principal.
2. **Como ela reflete o tema de Dawn of Kin?**  
   Coloca *Família*, *Vida* e *Crescimento Orgânico* no centro da emoção: o lar é literalmente tecido (trama) e semeado (semente), com a descendência brotando como folha real ao lado dos retratos de Alden e Brena.
3. **Qual elemento central ou mecânica visual é assinatura exclusiva dela?**  
   O **Ninho Familiar Sobreposto + Roseta de 4 Pétalas + Fichas Físicas de Matéria**: os retratos dos fundadores se encaixam em discos cerâmicos parcialmente sobrepostos (com o broto `+` reservado à descendência futura); na construção, o custo não é só texto — cada recurso aparece como **pequenas fichas/sementes táteis** que facilitam leitura visual instantânea.
4. **Como organiza recursos, tempo, fundadores, construção, tarefas e menus sem parecer formulário ou barra genérica?**  
   - *Recursos:* 3 medalhões cerâmicos esmaltados ligados por um cordão fino no topo esquerdo + pílula clara `Exposto` quando aplicável.
   - *Tempo e Estação:* Roseta cerâmica de 4 pétalas (uma pétala acesa por estação) + pílula de linho com estação, ano e velocidade.
   - *Fundadores:* Ninho sobreposto no canto inferior esquerdo + etiqueta de linho resumindo a Casa Fundadora; ao clicar em Alden, uma **faixa de linho horizontal se desenrola** a partir do Ninho mostrando barra de carga costurada e um **Ramo Botânico da Família**.
   - *Construção:* prancha de linho de cantos orgânicos alternados (`36px / 10px`) no canto inferior direito + cartão costurado `Obra em Trama` no topo esquerdo.
   - *Menu Principal:* estandarte de linho cru pendurado numa haste de madeira flutuando a `88 px` da borda esquerda (nunca colado como barra lateral), com corte inferior em cauda de andorinha.
5. **Como se comporta em repouso vs em ação?**  
   Em repouso, os elementos orgânicos (sementes, roseta, ninho e 3 pílulas de ação) ocupam pouquíssimo espaço e harmonizam com a paleta natural da clareira. Na seleção de fundador, a faixa têxtil desenrola para a direita revelando detalhes pessoais e o ramo familiar; no modo construção, o card selecionado vira cerâmica esmaltada verde-musgo (`Em mãos`), criando alto contraste com o linho.
6. **Como funciona em `1280×720` e `1920×1080` sem poluir a tela?**  
   Validada em ambas as resoluções (`D3_B` e `G_godot_D3`). Nos testes Godot, foi inclusive a direção com **menor quantidade de nós (`551`) e menor custo médio em 1080p (`p95 = 15,680 ms`)**, mantendo leitura cristalina em `720p`.
7. **Como evolui visualmente conforme o assentamento cresce (Nível I → V — PROPOSTA)?**  
   - *Nível I (Acampamento):* fibra crua, cordão simples e sementes cerâmicas básicas.
   - *Nível III (Povoado — PROPOSTA):* cerâmica esmaltada dupla e pontos bordados mais ricos nas bordas do linho.
   - *Nível V (Vila — PROPOSTA):* tapeçaria completa com fios dourados tecidos na trama e copa botânica expandida no Ninho Familiar.
8. **Maiores forças artísticas e de UX:**  
   Originalidade altíssima no mercado de RTS; calor emocional excepcional para o tema de família e comunidade; estética extremamente fotogênica e convidativa; excelente desempenho técnico na Godot 4.7.2.
9. **Maiores riscos ou limitações:**  
   É a direção que mais se afasta do tom escuro/sóbrio que o proprietário inicialmente elogiou no Conceito C. Em cenários futuros muito claros (ex.: neve pesada no inverno em T4), superfícies de linho claro exigiriam reforço de contorno escuro/sombra projetada para preservar contraste AA/AAA.

---

## 4. Catálogo Completo de Entregáveis Visuais (`A`–`G`)

### 4.1 Quadros de Síntese e Comportamento
- **Comparação lado a lado (D1 × D2 × D3):** [F_comparison_D1_D2_D3_1920x1080.png](../design/ui-0-r2/F_comparison_D1_D2_D3_1920x1080.png)
- **Storyboard de Comportamento e Transições (Repouso → Seleção → Construção → Portal/Evolução):** [G_behavior_storyboards_1920x1080.png](../design/ui-0-r2/G_behavior_storyboards_1920x1080.png)

### 4.2 Mapa de Todas as Pranchas e Capturas Reais
| Entregável | Direção 1 — O Fio da Aurora | Direção 2 — Marcos de Pedra e Eclipse | Direção 3 — Tear de Trama e Semente |
|---|---|---|---|
| **A — Identidade (1080p)** | [D1_A](../design/ui-0-r2/D1_A_identity_1920x1080.png) | [D2_A](../design/ui-0-r2/D2_A_identity_1920x1080.png) | [D3_A](../design/ui-0-r2/D3_A_identity_1920x1080.png) |
| **B — HUD Normal (1080p)** | [D1_B 1080p](../design/ui-0-r2/D1_B_hud_1920x1080.png) | [D2_B 1080p](../design/ui-0-r2/D2_B_hud_1920x1080.png) | [D3_B 1080p](../design/ui-0-r2/D3_B_hud_1920x1080.png) |
| **B — HUD Normal (720p)** | [D1_B 720p](../design/ui-0-r2/D1_B_hud_1280x720.png) | [D2_B 720p](../design/ui-0-r2/D2_B_hud_1280x720.png) | [D3_B 720p](../design/ui-0-r2/D3_B_hud_1280x720.png) |
| **C — Construção (1080p)** | [D1_C](../design/ui-0-r2/D1_C_construction_1920x1080.png) | [D2_C](../design/ui-0-r2/D2_C_construction_1920x1080.png) | [D3_C](../design/ui-0-r2/D3_C_construction_1920x1080.png) |
| **D — Linhagem (1080p)** | [D1_D](../design/ui-0-r2/D1_D_lineage_1920x1080.png) | [D2_D](../design/ui-0-r2/D2_D_lineage_1920x1080.png) | [D3_D](../design/ui-0-r2/D3_D_lineage_1920x1080.png) |
| **E — Menu Principal (1080p)** | [D1_E](../design/ui-0-r2/D1_E_menu_1920x1080.png) | [D2_E](../design/ui-0-r2/D2_E_menu_1920x1080.png) | [D3_E](../design/ui-0-r2/D3_E_menu_1920x1080.png) |
| **Godot 4.7.2 Real (720p)** | [G_godot_D1 720p](../design/ui-0-r2/G_godot_D1_fio_da_aurora_1280x720.png) | [G_godot_D2 720p](../design/ui-0-r2/G_godot_D2_marcos_kintsugi_1280x720.png) | [G_godot_D3 720p](../design/ui-0-r2/G_godot_D3_tear_semente_1280x720.png) |
| **Godot 4.7.2 Real (1080p)** | [G_godot_D1 1080p](../design/ui-0-r2/G_godot_D1_fio_da_aurora_1920x1080.png) | [G_godot_D2 1080p](../design/ui-0-r2/G_godot_D2_marcos_kintsugi_1920x1080.png) | [G_godot_D3 1080p](../design/ui-0-r2/G_godot_D3_tear_semente_1920x1080.png) |

> Todas as fontes HTML/SVG editáveis das 20 pranchas estão versionadas em [`docs/design/ui-0-r2/sources/`](../design/ui-0-r2/sources/).

---

## 5. Validação Reproduzível na Godot 4.7.2 e Benchmark Sem V-Sync (Preliminar)

### 5.1 Como reproduzir exatamente este teste
Na raiz do repositório/worktree:
```powershell
.\docs\design\ui-0-r2\godot_showcase\run_ui0_r2_showcase.ps1
```
- **Script GDScript versionado:** [`docs/design/ui-0-r2/godot_showcase/ui0_r2_godot_showcase.gd`](../design/ui-0-r2/godot_showcase/ui0_r2_godot_showcase.gd)
- **Runner PowerShell versionado:** [`docs/design/ui-0-r2/godot_showcase/run_ui0_r2_showcase.ps1`](../design/ui-0-r2/godot_showcase/run_ui0_r2_showcase.ps1)
- **Dados brutos gerados:** [`docs/design/ui-0-r2/godot_showcase/benchmark_results.json`](../design/ui-0-r2/godot_showcase/benchmark_results.json)

### 5.2 Configuração técnica real medida
- **Engine:** `Godot Engine v4.7.2.stable.official.ed1daf0bf`
- **Renderer e GPU:** `OpenGL API 3.3.0 - Build 30.0.101.1339 - Compatibility` (`gl_compatibility`) — `Intel(R) UHD Graphics 620`
- **V-Sync:** **Desligado explicitamente** (`DisplayServer.VSYNC_DISABLED`, `vsync_mode = 0`)
- **Amostragem:** `60` quadros de aquecimento (*warm-up*) descartados + `3` repetições intercaladas × `180` quadros = **`540` quadros válidos por cenário** (total de `4.320` quadros medidos entre 720p e 1080p), sempre renderizando a cena 3D real (`MainScene`) sob a UI isolada.
- **Tipografia usada no protótipo Godot:** `palab.ttf` / `pala.ttf` (Palatino serif) e `segoeui.ttf` carregadas via `FontFile` com fallback para `SystemFont` (sem depender de fonte externa licenciada).

### 5.3 Resultados exatos medidos (`benchmark_results.json`)

#### Resolução `1280×720` (Intel UHD Graphics 620, V-Sync OFF)
| Cenário | Média mediana (ms) | `p95` mediano (ms) | `p99` mediano (ms) | Quadros `> 100 ms` | Draw calls | Nós |
|---|---:|---:|---:|---:|---:|---:|
| `BASELINE_3D` (cena 3D sem UI R2) | `5,577` | `8,437` | `10,708` | `0` | `217` | `537` |
| `GODOT_D1_FIO_DA_AURORA` | `6,390` (`+0,813`) | `8,651` | `9,607` | `0` | `284` (`+67`) | `556` (`+19`) |
| `GODOT_D2_MARCOS_KINTSUGI` | `6,098` (`+0,521`) | `7,347` | `8,389` | `0` | `288` (`+71`) | `557` (`+20`) |
| `GODOT_D3_TEAR_SEMENTE` | `6,022` (`+0,445`) | `7,857` | `9,575` | `0` | `277` (`+60`) | `551` (`+14`) |

#### Resolução `1920×1080` (Intel UHD Graphics 620, V-Sync OFF)
| Cenário | Média mediana (ms) | `p95` mediano (ms) | `p99` mediano (ms) | Quadros `> 100 ms` | Draw calls | Nós |
|---|---:|---:|---:|---:|---:|---:|
| `BASELINE_3D` (cena 3D sem UI R2) | `11,856` | `15,889` | `17,744` | `0` | `217` | `537` |
| `GODOT_D1_FIO_DA_AURORA` | `12,028` (`+0,172`) | `16,319` | `20,884` | `0` | `284` (`+67`) | `556` (`+19`) |
| `GODOT_D2_MARCOS_KINTSUGI` | `12,482` (`+0,626`) | `16,390` | `20,594` | `0` | `288` (`+71`) | `557` (`+20`) |
| `GODOT_D3_TEAR_SEMENTE` | `12,438` (`+0,582`) | `15,680` | `18,137` | `0` | `277` (`+60`) | `551` (`+14`) |

### 5.4 Análise técnica honesta (Fidelidade, Draw Calls e Limites)
1. **Salto de fidelidade em relação à R1:** todas as 6 capturas reais da Godot (`G_godot_D1/D2/D3` em 720p e 1080p) reproduzem fielmente as silhuetas, cores, tipografia serifada, retratos circulares com máscara real (`CLIP_CHILDREN_AND_DRAW`) e ativos pintados das pranchas — sem nenhum artefato de 9-slice invadindo texto.
2. **Micro-ajustes visuais já identificados nas capturas Godot (transparência):**
   - Em `G_godot_D1` (topo direito), o marcador `4×` encosta por ~`2 px` na borda esquerda do astrolábio; basta deslocar o rótulo `12 px` à esquerda na `UI-1`.
   - Em `G_godot_D2` (canto inferior direito), a letra final de `Construir` fica muito próxima do chanfro direito da placa de alabastro; basta aumentar `14 px` na largura da placa na `UI-1`.
3. **Achado crítico de engenharia para `UI-1` (Draw Calls em `1080p`):**
   - Todas as três direções mantiveram a mediana de `p95` **abaixo de `16,7 ms`** tanto em `720p` (`7,35–8,65 ms`) quanto em `1080p` (`15,68–16,39 ms`), com **zero quadros `> 100 ms`** e acréscimo médio modesto (`+0,17` a `+0,81 ms`).
   - Porém, o desenho procedural com múltiplas chamadas `_draw()` de arcos/polígonos e `CLIP_CHILDREN_AND_DRAW` adicionou `+60` a `+71` draw calls (`277–288` vs `217` do baseline), elevando a mediana de `p99` em `1080p` para `20,59–20,88 ms` em D1 e D2.
   - **Solução arquitetural recomendada para `UI-1`:** pré-assar as silhuetas estáticas da direção escolhida em um **único Texture Atlas PNG 2D** (com `AtlasTexture` e `StyleBoxTexture` sem distorção), reduzindo o acréscimo de `~65` para `~4–8` draw calls com fidelidade visual idêntica ou ainda mais refinada.
4. **Ressalva explícita obrigatória:** este benchmark é uma **validação preliminar isolada de renderização de UI** (a cena 3D está aberta e renderizando, mas sem múltiplos ciclos pesados simultâneos de IA/pathfinding/construção nem variação de energia CA vs bateria DC). Ele **NÃO substitui nem constitui homologação final de desempenho de gameplay**.

---

## 6. Compatibilidade com GDD, RUX e Pendências Preservadas

### 6.1 Fidelidade ao estado real do projeto (sem converter PROPOSTA em DECIDIDO)
- **Implementado hoje e contemplado em D1/D2/D3:**
  - Recursos físicos `Madeira`, `Pedra`, `Alimentos` e estado `Exposto` (T2 / T3).
  - Fundadores `Alden` e `Brena`, carga física (`peso / 20`, velocidade proporcional B1), seleção RTS e clique direito.
  - Coleta comunitária automática de árvore/pedra/alimentos e seleção múltipla de fontes (`RUX-1`, `RUX-2A`, `RUX-2B`).
  - Construção Nível I (`Abrigo Básico` e `Depósito Rústico`), prévia de posicionamento no terreno, progresso de obra e cancelamento (`T3.1–T3.6`).
- **Explicitamente marcado como `PROPOSTA` (sistemas futuros — NÃO implementados):**
  - Estações/Calendário (`Primavera · Ano I`, `T4`).
  - `Continuar` e `Carregar` no Menu Principal (`T3.8`).
  - Descendência / 1ª Geração / Árvore Genealógica Viva (`T5`).
  - Evolução visual da interface entre **Nível I → Nível V** (GDD §6).
  - Ação `Liberar para Comunidade / Pessoal` (`P-RUX-2`, ainda em aberto).

### 6.2 Pendências abertas preservadas integralmente
Esta etapa documental **não homologa, não fecha e não altera** nenhuma das pendências vigentes:
- `UX-1`: 3 testes manuais pendentes.
- `RUX-1`, `RUX-2A` e `RUX-2B`: aceite visual/manual pelo proprietário pendente.
- `T3.6.4-R1`: retestes manuais `D3-04` e `D3-07` pendentes.
- Decisões abertas da proposta `RUX-0`: `P-RUX-1`, `P-RUX-2`, `P-RUX-3`, `P-RUX-4` e `P-RUX-6`.
- Decisão pendente sobre classificação do benchmark de bateria DC da T2 (em `AGENTS.md`).

---

## 7. Proveniência de Ativos e Licenciamento (`docs/design/ui-0-r2/assets/`)

Todos os ativos usados em UI-0 R2 são **100% autorais ou procedurais determinísticos**, com **zero redistribuição de ativos restritos do Google Drive**:

| Arquivo | Uso nas direções | Origem e Licença |
|---|---|---|
| `d1_astrolabe.png` | Astrolábio sazonal 4 estações (D1 + Godot D1) | Arte original gerada para UI-0 R2 + recorte circular limpo |
| `d1_shelter_mini.png` | Miniatura isométrica pintada de Abrigo (D1, D2 + Godot D2) | Arte original gerada para UI-0 R2 + recorte alfa limpo |
| `d1_depot_mini.png` | Miniatura isométrica pintada de Depósito (D1, D2, D3) | Arte original gerada para UI-0 R2 + recorte alfa limpo |
| `d2_kintsugi_basalt.png` | Superfície basalto vulcânico com veios kintsugi (D2) | Arte original gerada para UI-0 R2 |
| `d3_linen_weave.png` | Textura de linho cru tramado (D3) | Textura procedural determinística gerada via Pillow (sem terceiros) |
| `d3_ceramic_moss.png` | Textura de cerâmica esmaltada fosca musgo (D3) | Textura procedural determinística gerada via Pillow (sem terceiros) |
| `portrait_alden.jpg` / `portrait_brena.jpg` | Retratos dos fundadores (D1, D2, D3 + Godot) | Arte original autoral herdada da própria R1 do projeto |
| `emblem_dawn_of_kin.png` | Emblema da Casa Fundadora (D1, D2, D3 + Godot) | Arte original autoral herdada da própria R1 do projeto |
| `sketch_shelter_ink.png` / `sketch_depot_ink.png` | Croquis arquitetônicos em nanquim (D3) | Arte original autoral herdada da própria R1 do projeto |

---

## 8. Comparação Crítica e Recomendação Não-Vinculante

| Critério | Direção 1 — O Fio da Aurora | Direção 2 — Marcos de Pedra e Eclipse | Direção 3 — Tear de Trama e Semente |
|---|---|---|---|
| **Originalidade formal** | **Muito alta** (zero barras; orbital + portal + rosa de construção) | **Muito alta** (monólitos *kintsugi* assimétricos + contraste alabastro) | **Altíssima** (cerâmica/linho/botânica rompe o padrão do gênero) |
| **Continuidade com o que agradou em C** | **Direta e superada** (mesma alma elegante, forma 100% reinventada) | **Alta** (mantém sobriedade escura com muito mais caráter) | **Ruptura deliberada** (troca o noturno solene por calor diurno/orgânico) |
| **Legibilidade em 720p e 1080p** | Excelente (94% da tela livre em repouso) | Excelente (contraste máximo escuro × claro) | Muito boa (atenção extra apenas em futuros biomas de neve) |
| **Escalabilidade p/ telas densas (T4/T5)** | Moderada-alta (pede modal circular dedicado para árvores grandes) | **Excelente** (lajes assimétricas acomodam listas e genealogia facilmente) | **Excelente** (faixas e pranchas têxteis escalam com naturalidade) |
| **Desempenho preliminar Godot 1080p (`p95` mediano)** | `16,319 ms` (otimizável com Atlas único na UI-1) | `16,390 ms` (otimizável com Atlas único na UI-1) | `15,680 ms` (mais leve já no protótipo bruto) |

### Parecer curatorial (estritamente não-vinculante)
- **Se o objetivo for evoluir o que já encantou no antigo Conceito C até o patamar de identidade única e memorável:** a **Direção 1 — O Fio da Aurora** é a recomendação principal. Ela mantém a sofisticação silenciosa, deixa praticamente todo o mundo 3D livre em repouso, transforma a seleção dos fundadores e a construção em gestos orbitais únicos e entrega um Menu Principal em Portal que parece capa de jogo premiado.
- **Se o objetivo for máxima força escultural, dramatismo e diálogo direto com o futuro arquipélago japonês e Luz × Sombra:** a **Direção 2 — Marcos de Pedra e Eclipse** oferece uma assinatura geométrica impossível de copiar e o melhor contraste funcional entre modo normal (basalto) e modo construção (alabastro).
- **Se o objetivo for diferenciar *Dawn of Kin* de todos os RTS medievais sombrios apostando em acolhimento familiar e vida orgânica:** a **Direção 3 — Tear de Trama e Semente** tem o maior potencial de carisma instantâneo e o menor custo de renderização medido na Godot.

> **A decisão pertence integralmente ao proprietário.**  
> Possíveis próximos passos após sua avaliação:
> 1. Aprovar uma das três direções (`D1`, `D2` ou `D3`) para detalhamento técnico e especificação de `UI-1`;
> 2. Solicitar uma fusão pontual (por exemplo, a estrutura orbital da `D1` com algum elemento tátil da `D2` ou `D3`);
> 3. Reprovar e indicar ajustes de direção antes de qualquer trabalho de código.
