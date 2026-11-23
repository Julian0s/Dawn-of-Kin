# DAWN OF KIN

**Documento Mestre de Design (GDD Único Consolidado)**  
**Versão Interna:** **v1.3 — Candidata Documental de Reconciliação Canônica (`R-02A`)** (Caminho canônico estável: `docs/Dawn_of_Kin_GDD.md`)  
**Data:** 23 de novembro de 2026  
**Uso:** Documento mestre único consolidado de Game Design, atualizando a revisão `v1.2` (`R4.1`, `6e5764f67125da103eec68adb95e5b67ac329ed9`, aprovada em `16/11/2026`) para incorporar todas as decisões canônicas posteriores (`D-01`–`D-13`, `P-REC-1`–`P-REC-4`, `D-ERR-1 B`, `D-ERR-2 C`, Design System `D2.2` e homologação `UI-1.3 R1`).  
**Base Técnica Auditada:** `fix/ui-1-3-r1-validation-uid` @ `c4a6361919564fca59ddbad3362468a0c1b1708e` (`+148` commits lineares à frente da `main` em `25e0a20f1d6a2f10a9e059afe69759fbe263db4a`)  
**Roadmap e Matriz de Rastreabilidade:** [ROADMAP_MESTRE.md](ROADMAP_MESTRE.md)  
**Nome de Trabalho:** *Dawn of Kin* («Aurora da Linhagem»); disponibilidade comercial e registro de marca permanecem **`ABERTO`** antes da publicação.

> **Governança e Status Normativo (`R-02A`):**
> - **Status desta revisão (`v1.3`):** `CANDIDATA DOCUMENTAL R-02A` — submetida à auditoria independente do ChatGPT e à homologação expressa do proprietário antes de qualquer integração à `main`.
> - **Autoridade de Decisões:** Uma versão anterior de documento não prevalece sobre decisão posterior expressamente aprovada pelo proprietário; da mesma forma, código presente no repositório não se torna canônico ou homologado automaticamente sem aprovação formal.
> - **Bloqueio de Implementação:** Esta reconciliação documental **não** autoriza implementação de `R-02B`, `R-03A`, `UI-1.4`, `T3.7` ou qualquer etapa futura.
>
> **Marcadores de Status (Não Equivalentes — ver [ROADMAP_MESTRE.md](ROADMAP_MESTRE.md) §1):**
> - **`DECIDIDO`:** regra de produto expressamente aprovada pelo proprietário.
> - **`PLANEJADO`:** implementação futura prevista para uma regra aprovada (ainda não existe em código).
> - **`IMPLEMENTADO`:** comportamento efetivamente existente no código GDScript, cenas `.tscn` ou recursos `.tres`.
> - **`VALIDADO`:** comportamento verificado com evidências objetivas (suítes automatizadas, VCG ou protocolos manuais).
> - **`HOMOLOGADO`:** entrega com aceite formal e expresso do proprietário.
> - **`INTEGRADO`:** incorporado à branch `main` mediante autorização expressa.
> - **`ATIVO NA MAINSCENE`:** funcionalidade efetivamente acessível ao jogador em `res://src/main/main.tscn`.
> - **`PROPOSTA`:** sugestão técnica, hipótese de orçamento ou parâmetro inicial sem aprovação fechada.
> - **`ABERTO`:** questão intencionalmente sem definição final, reservada para calibração ou decisão futura.
> - **`SUBSTITUÍDO`:** contrato histórico supersedido por decisão posterior (podendo permanecer temporariamente ativo em código durante a transição segura `P-REC-1`).
> - **`DESCARTADO`:** funcionalidade expressamente excluída do escopo do projeto.
>
> **Estado Real do Projeto em `23/11/2026` (`main` @ `25e0a20` vs ponta homologada `c4a6361`):**
> - **Integrado na `main` (`25e0a20`):** `T1` (`t1-complete` @ `2808799`), `T2` (`t2-complete` @ `f7c2459`), `T3.1`–`T3.3` (`t3-3-complete` @ `3c6fc0b`), `T3.4` (`2a6cce6`), `T3.5.1` (`56d8e97`), `T3.5.2` (`fb31887`) e `T3.6.1` (`25e0a20`, módulo matemático puro).
> - **Homologado na cadeia linear (ainda não integrado à `main`):** `T3.6.2 Bloco A` (`ec17f42`, `use_provenance_economy = true` ativo em `main.tscn`), Design System `D2.2` (`cdd9f2f`), plano `UI-1.0 R1` (`7dbfeb1`), `UI-1.1A R2` (`a02aa97`), `UI-1.1B R1` (`a6542ca`), `UI-1.2` (`9f84d33`) e **`UI-1.3 R1` (`c4a6361`)**. A HUD D2.2 permanece com `use_d2_2_hud = false` na `MainScene` até o cutover antecipado autorizado em `R-05B`.
> - **Candidatas existentes no histórico (NÃO homologadas):** `T3.6.3`/`T3.6.4-R1` (`8deeef1`, `D3-04`/`D3-07` pendentes — preservada em transição `P-REC-1`), `UX-1` (`0e78f9a`) e `RUX-1`/`RUX-2A`/`RUX-2B` (`cddd582`, isoladas em `tests/visual/`, nunca jogadas pelo proprietário — `D-09a`).
> - **Nota sobre Controles Temporários de Teste (`R2-F`):** `Worker3`/`Worker4` (`TemporaryTestWorkersController`) e `PlacementTestOverlay` permanecem exclusivamente como ferramentas transitórias de desenvolvimento até sua retirada na `UI-1.7` (`R-07`). **Não fazem parte da população canônica do Capítulo 1**, no qual o jogo começa exclusivamente com **os 2 protagonistas originais**.

---

## 1. Identidade, Visão e Pilares de Design

**Pitch:** Um casal foge das explosões da Terceira Guerra Mundial, atravessa um fenômeno espacial e desperta sem pertences em um mundo selvagem original, sem civilização humana preexistente conhecida. Com comandos intuitivos de trabalho comunitário e controle pessoal da Casa Fundadora em estratégia em tempo real (RTS), o jogador transforma a sobrevivência de duas pessoas no início de uma linhagem familiar e de uma comunidade viva, enquanto uma presença sombria ancestral anuncia que um grande conflito se aproxima.

### 1.1 Classificação e Experiência Central (`DECIDIDO`)
- **Gênero:** Sobrevivência simplificada + construção de assentamento + RTS comunitário leve + evolução familiar/linhagem; single-player inicialmente.
- **Perspectiva:** Câmera 3D isométrica, interação prioritariamente pelo mouse.
- **Ritmo:** Contemplativo, intuitivo e agradável de observar; perigo episódico, não combate constante.
- **Diferencial:** Partir de um único casal identificável e personalizável na primavera, sobreviver ao primeiro ano e acolher o primeiro encontro humano no inverno que inaugura o Capítulo 2, acompanhar o nascimento e amadurecimento dos filhos (`Bebê → Criança → Jovem → Adulto`), ver o despertar gradual de profissões, vocações e dons latentes, e descobrir outras comunidades sobreviventes em um mundo contínuo.
- **Referências Funcionais:** *Age of Empires* (seleção e ordens RTS), *Durango: Wild Lands* (natureza e sobrevivência). Referências servem exclusivamente como inspiração funcional, jamais como ativos a copiar.

### 1.2 Os Cinco Pilares de Identidade (`DECIDIDO`)
1. **Linhagem Viva e Identidade Persistente:** Nenhum habitante é genérico ou descartável. Todos possuem ID imutável, nome próprio, sobrenome familiar, genealogia rastreável, herança visual e vínculo residencial.
2. **Economia Física sem Microgestão Excessiva:** A coleta e o transporte de recursos das fontes naturais até o armazenamento são estritamente físicos (peso, mochila, descarga real e regras de exposição), sem crédito instantâneo na coleta, sem barras individuais de fome/sede e sem salários/moeda interna (`DEC-12`). Na construção, o débito imediato atômico (`D-01`) elimina viagens repetitivas de suprimento até canteiros sem abrir mão da conservação econômica.
3. **Trabalho Comunitário Fluido + Soberania da Casa Fundadora (`D-03`, `D-04`, `D-05`, `D-10`, `DEC-08`):** O jogador marca objetivos (fontes de recursos e construções) e o sistema distribui trabalhadores comunitários automaticamente, mantendo atribuição manual opcional e controle pessoal prioritário para toda a **Casa Fundadora** (protagonistas, descendentes e cônjuges externos), evoluindo posteriormente para rotinas profissionais autônomas (`JobSystem`, `PLANEJADO T5`).
4. **Despertar Gradual de Profissões, Vocações e Dons:** Habilidades de trabalho, defesa e capacidades especiais desenvolvem-se por aprendizado, treino, experiência e mentoria — nunca como distribuição mágica instantânea de classes.
5. **Natureza Vibrante em Contraste com o Mistério Sombrio:** Uma paisagem 3D estilizada vibrante e naturalista — marcada pela passagem de quatro estações e névoa natural — contrasta com o mistério silencioso do Ser de Trevas e suas influências sobre o mundo.

---

## 2. História, Universo e Progressão Narrativa

### 2.1 Premissa do Mundo e Cosmologia: Bastidores vs. Percepção Jogável (`DECIDIDO` e `ABERTO`)
Para manter a consistência narrativa e o mistério durante a campanha, distingue-se rigorosamente o que pertence à **mitologia de bastidores** daquilo que **os personagens e o jogador sabem em cena**:

- **A Chegada (`DECIDIDO` — Visível ao Jogador):**
  - No prólogo, o casal dirige em meio ao colapso da Terceira Guerra Mundial, cercado por bombardeios e explosões nucleares. Quando parece não haver saída, um buraco de minhoca os transporta.
  - A passagem transporta **apenas seres vivos** (sem carro, inventário, armas ou ferramentas). As roupas rasgadas iniciais são uma convenção visual de apresentação e classificação etária (não equipamento utilizável trazido da Terra), podendo ser substituídas futuramente por roupas produzidas pela comunidade.
  - O destino é **um mundo selvagem fictício original** — inspirado na geografia e nos ecossistemas japoneses (sem constituir uma representação literal do Japão terrestre) — com biomas e animais reconhecíveis, sem cidades, estradas, ruínas humanas ou povos não humanos inteligentes.
- **Outros Sobreviventes (`DECIDIDO`):**
  - Todos os outros humanos existentes nesse mundo também vieram da Terra em colapso através do fenômeno, surgindo em locais distintos e possivelmente em momentos diferentes. Isso é desconhecido para o casal no início do Capítulo 1.
- **Cosmologia de Bastidores (`DECIDIDO` como cânone oculto — `DEC-05`):**
  - **O Ser de Trevas:** Há milhares de anos, antes de existir vida naquele planeta, uma entidade ancestral maligna — cujo nome ninguém conhece — instalou-se naquele lugar. Seu poder pode corromper parte da fauna (tornando esses animais mais fortes e irradiando trevas, enquanto animais normais continuam existindo) e seduzir corações humanos vulneráveis.
  - **O Ser de Luz:** Em bastidores, foi o Ser de Luz quem abriu a passagem para salvar escolhidos da guerra a fim de repovoar a terra e enfrentar o mal ali instalado. Contudo, **o Ser de Luz não aparece no Capítulo 1**, não trava combate direto e sua eventual manifestação ou revelação futura permanece em **`ABERTO`**, sem data ou capítulo obrigatório.
- **Mistérios Mantidos Intencionalmente em Aberto (`ABERTO`):**
  - A natureza cosmológica exata desse mundo e a física da travessia (não fixar como fato se é o mesmo planeta original, viagem no tempo, universo paralelo ou passado remoto).
  - A identidade última do Ser de Luz, o nome/origem do Ser de Trevas e suas verdadeiras intenções.
  - A origem última dos dons latentes (que permanece misteriosa para os protagonistas durante o início da campanha).

### 2.2 Progressão Narrativa por Capítulos (`DECIDIDO` — `D-07`, `D-12`, `P-REC-3` — `PLANEJADO T7/T8`)

#### Capítulo 1 — A Chegada e o Primeiro Ano
- **Início na Primavera (`DECIDIDO` — `D-07`):**
  - O jogo começa na **primavera**, em uma clareira inicial próxima à floresta e ao rio, exclusivamente com **os 2 protagonistas originais**, sem outros humanos conhecidos.
  - O jogador aprende os controles de trabalho comunitário e controle pessoal, explora os arredores revelando a névoa natural, coleta frutos, madeira e pedra, forma pilhas no acampamento inicial e constrói o **Abrigo Básico** e o **Depósito Rústico** *(ambas as estruturas pertencem ao Nível 1; pela diretriz técnica `D5`, a implementação funcional do depósito protegido ocorre na `T3.7`, mantendo-se `ABERTO` no design se haverá pré-requisito de desbloqueio entre elas dentro do jogo; a conclusão do primeiro abrigo continua sendo o marco narrativo que dispara a cena noturna do Ser de Trevas)*.
- **A Única Aparição Pessoal do Ser de Trevas (`DECIDIDO` — `DEC-06`, `P-REC-3`):**
  - Ainda durante o **Capítulo 1**, depois que o casal constrói seu primeiro abrigo, ocorre um evento misterioso, preferencialmente em uma noite apropriada.
  - A natureza ao redor fica estranhamente silenciosa; uma figura sombria surge à distância e dirige algumas palavras ao casal *(exemplo provisório, não texto final obrigatório: «Saudações, visitantes... O dia se aproxima.»)*.
  - A entidade **não luta, não ataca e não explica sua identidade**; após a mensagem, desaparece.
  - **Regra Canônica:** Esta é a **única aparição pessoal direta** do Ser de Trevas nos capítulos atualmente planejados. O Ser de Luz **não** aparece no Capítulo 1 e não há concessão explícita de bênção após o abrigo.
- **Transição para o Capítulo 2 — A Família no Primeiro Inverno (`DECIDIDO` — `D-07`, `D-12`, `P-REC-3`):**
  - O casal percorre o primeiro ciclo sazonal (primavera → verão → outono → inverno), consolidando sobrevivência, estoque e preparo para o frio.
  - Durante o **primeiro inverno** — **antes do nascimento do primeiro filho dos fundadores** — chega uma **família visitante**, formada por **um casal e uma criança**, também sobreviventes trazidos pelo fenômeno.
  - **Marco Canônico de Passagem:** A chegada dessa família visitante no primeiro inverno marca oficialmente a **transição do Capítulo 1 para o Capítulo 2**, substituindo integralmente o antigo portão narrativo que bloqueava encontros humanos até que um filho atingisse 12 anos.

#### Capítulo 2 — Raízes, Linhagem e Sobreviventes (`DECIDIDO` — `D-12`, `P-REC-3`)
- **Convivência e Expansão Familiar:**
  - Os fundadores e a família acolhida enfrentam a nova realidade de que existem outros sobreviventes humanos nesse mundo, sem fluxo artificial constante de colonos nem botão genérico de recrutamento.
  - **Nascimento e Crescimento dos Filhos (`P-REC-3`):** O nascimento e o amadurecimento dos filhos dos protagonistas (`Bebê → Criança → Jovem → Adulto`), a consolidação da propriedade, agricultura (`Roça`), manifestação gradual do *Alento* e profissões comunitárias ocorrem ao longo do Capítulo 2.
  - Casamentos seguem estritamente restritos à fase **Adulta (`18+ anos`)** e às regras de parentesco (`DEC-02`).

#### Capítulo 3 — Laços entre Comunidades e Conflitos contra a Sombra (`DECIDIDO` — `DEC-02`, `DEC-07`, `DEC-12`)
- **DIREÇÃO APROVADA:**
  - Cooperação, comércio por trocas de recursos e formação de novas famílias por casamentos **exclusivamente entre personagens Adultos (`18+ anos`)** de comunidades pacíficas distintas, satisfeitas as demais condições familiares, de parentesco e de moradia.
  - Em terras distantes, revela-se que **um grupo humano foi seduzido pela influência do Ser de Trevas**, originando conflitos e guerras futuras contra as comunidades livres e contra feras corrompidas.
- **ABERTO:** Regras detalhadas de diplomacia, rotas comerciais permanentes, gatilho eventual para transição do Cap. 2 para o Cap. 3 e capítulos finais da campanha.

---

## 3. Família, Linhagem, Casa Fundadora e População (`PLANEJADO T5`; metadados mínimos em `R-03B`)

### 3.1 Criação do Casal, Personagens Modulares e Herança Visual (`DECIDIDO` e `PROPOSTA` — `v1.1` §7.1–7.4 + `DEC-16`)
- **Criação do Casal Inicial (`DECIDIDO`):** Os dois protagonistas serão escolhidos a partir de modelos-base personalizáveis (formato do rosto/detalhes faciais, modelo/textura/cor do cabelo, cor dos olhos, tom de pele em ampla paleta natural e botão **Randomizar**).
- **Sistema de Cores (`DECIDIDO` — `R3-E`):** Cabelo e olhos com seleção livre de cores (inclusive incomuns); pele em paleta ampla de tonalidades naturais; roupas personalizáveis mas **não hereditárias**. Apenas os traços biológicos escolhidos influenciam os descendentes.
- **Peças Modulares e Padronização de Esqueleto (`DECIDIDO` — `DEC-16`):** Componentes 3D intercambiáveis (**Cabeça**, **Cabelo**, **Corpo**, **Vestuário**) com **esqueleto único padronizado por faixa etária** e padronização técnica obrigatória para Godot (escala, pivô, peso de ossos e encaixes).
- **Herança Visual e Crescimento Consistente (`DECIDIDO`):** Seis traços herdáveis obrigatórios (formato/proporções faciais, cor dos olhos, tom de pele, cor/textura natural do cabelo, tendência de altura e tendência de constituição física), com modelos corporais adequados às quatro fases (`Bebê → Criança → Jovem → Adulto`).
- **`PROPOSTA` TÉCNICA (`DEC-16`):** Orçamento indicativo de `~1.500–3.500` triângulos por personagem, shaders recoloríveis por instância e detalhamento de *sockets* permanecem propostas sujeitas a medição na Intel UHD 620.

### 3.2 Nomes, Sobrenomes e Identidade Persistente (`DECIDIDO` e `PROPOSTA` — `v1.1` §7.5 + `DEC-16`)
- Todo humano externo possui **nome próprio persistente** mesmo antes de integrar o assentamento do jogador (sem identificadores genéricos como `Aldeão 1`).
- O casal protagonista e cada família possuem **Nome + Sobrenome Familiar**; filhos herdam o sobrenome.
- Renomeação manual opcional nunca altera o `ID` interno imutável, genealogia, vínculos ou residência, e **nunca pode ser revertida pelo sistema automático**.
- Nascimentos recebem nome inédito automaticamente (com exceção rara de homenagem a pai/mãe), editável livremente sem pausar o jogo à força.
- **`PROPOSTA` TÉCNICA:** Serviço modular `Identity/NameService` desacoplado de modelos 3D, profissão e equipamentos.

### 3.3 Ciclo de Vida, Limites por Idade e Calendário (`DECIDIDO` e `ABERTO` — `DEC-04`, `D-08`, `P-REC-3`)
- **Quatro Fases (`DECIDIDO`):** **Bebê (`0–2 anos`) → Criança (`3–11 anos`) → Jovem (`12–17 anos`) → Adulto (`18+ anos`)**. Ao atingir **Adulto (18 anos)**, os personagens **param de envelhecer** (sem morte por velhice).
- **Atuação e Restrições por Idade (`DECIDIDO` — `DEC-04`):**
  - **Bebê (`0–2`):** Dependente; permanece protegido na residência familiar (visível no painel da casa/família, **não** é unidade RTS selecionável ou comandável no mapa).
  - **Criança (`3–11`):** Visível e selecionável (quando elegível pela Casa Fundadora); colabora apenas em **tarefas leves e seguras** (colher frutos, pequenas cargas leves), **proibida** de cortar árvores, quebrar pedras, construir pesado ou combater.
  - **Jovem (`12–17`):** Trabalha em coleta, construção e atividades apropriadas à idade; **não pode casar** e a **especialização combatente plena é reservada aos adultos**.
  - **Adulto (`18+`):** Aptidão plena para todas as profissões, vocações combatentes, casamento e residência.
- **Calendário Sazonal e Ritmo Experimental (`D-08`, `P-REC-3` — `PLANEJADO T4/T5`):**
  - **Velocidades Previstas (`DECIDIDO`):** Pausa (`||`), `1×`, `2×` e `4×` *(na HUD D2.2 atual apenas `||` e `1×` estão implementados e homologados — `DT-05`)*.
  - **Duração das Estações (`PROPOSTA` / HIPÓTESE EXPERIMENTAL — `D-08`):** A faixa de **2 a 3 horas por estação** (consequência aritmética de `8–12 h` por ciclo completo de 4 estações) é preservada estritamente como **hipótese experimental de teste**, **não** como duração final homologada.
  - **Relação Estações × Anos do Mundo × Envelhecimento Humano (`ABERTO` — `P-REC-3`):** Permanece explicitamente **`ABERTO`** para calibração empírica em `T4/T5`. **Não** se deve presumir automaticamente que 1 ano de envelhecimento humano precise equivaler literalmente a 1 ciclo completo de 4 estações sem especificação aprovada.
  - **Diretriz Anti-Espera Artificial (`DECIDIDO`):** Distribuir atividades significativas ao longo das estações e do crescimento familiar sem alongar artificialmente tempos de coleta ou construção apenas para preencher relógio.

### 3.4 Casa Fundadora, Residência, Nascimentos e Genealogia (`DECIDIDO` — `D-04`, `D-06`, `D-10`, `DEC-02`, `DEC-03`, `DEC-04`)
- **Casa Fundadora e Alcance do Controle Pessoal (`DECIDIDO` — `D-04`, `D-10` — `PLANEJADO R-03B/R-03C/T5`):**
  - Integram a **Casa Fundadora**: os **2 protagonistas originais**, **todos os seus descendentes diretos** e os **cônjuges externos** que ingressarem na Casa Fundadora por casamento.
  - Todos os integrantes selecionáveis e aptos da **Casa Fundadora** (respeitadas as restrições etárias `DEC-04`) possuem **controle pessoal direto prioritário** e podem ser selecionados para **equipes manuais opcionais** (`D-03`/`D-10`).
  - Quando não estiverem sob ordem pessoal ativa, integrantes da Casa Fundadora participam automaticamente do trabalho comunitário.
  - **Demais moradores** (fora da Casa Fundadora) atuam pelo sistema comunitário automático (e posteriormente por suas profissões no `JobSystem`), evitando microgestão em vilas grandes.
  - **Proteção contra Morte (`DECIDIDO` — `DEC-07`, `D-04`):** Continua **estritamente exclusiva dos 2 protagonistas originais**. Descendentes, cônjuges externos e demais moradores são mortais e podem morrer por perigos e ataques.
- **Residências sem Interiores e Escolha de Moradia (`DECIDIDO` — `D-06`, `RUX-0` — `PLANEJADO T5`):**
  - Residências (incluindo a Casa Principal e Casas Familiares) são geridas **pelo exterior, sem interiores jogáveis** (`DESCARTADO` interior jogável), mantendo todos os vínculos familiares e núcleos residenciais registrados nos dados.
  - **Escolha do Jogador para Casais Descendentes (`D-06`):** Quando um descendente da Casa Fundadora forma casal (Adulto `18+`), **o jogador escolhe** se o novo casal permanece residindo na **Casa Principal** ou muda-se para uma **casa própria** (mantendo a afiliação à Casa Fundadora separada da residência física).
- **Afinidade, Nascimentos, Consanguinidade e Viuvez (`DECIDIDO` — `DEC-02`, `DEC-03`, `DEC-04`, `v1.1` §7.7):**
  - Moradores têm autonomia para criar afinidades e formar casais persistentes (não emparelhamento aleatório diário), respeitando idade adulta (`18+`), bloqueio de consanguinidade até **primos de 1º grau** e vínculo residencial.
  - **Gatilho Autônomo de Nascimento (`DEC-03`):** Discreto e autônomo (iniciando-se no **Capítulo 2** conforme `D-12`/`P-REC-3`); exige casal residindo junto, vaga de dependente disponível, estabilidade alimentar coletiva e intervalo progressivo crescente conforme o número de filhos do casal. *(Vagas exatas e curva numérica: `ABERTO`).*
  - **Viuvez e Orfandade (`DEC-04`):** O cônjuge sobrevivente mantém titularidade da casa e guarda dos menores (podendo recasar após luto); se ambos os pais morrerem, os avós (casal líder) ou parentes acolhem as crianças.
  - **População (`DECIDIDO`):** Sem teto artificial predeterminado; regulada por moradia, alimentos e capacidade técnica.

---

## 4. Trabalho, Economia Física e Construção

### 4.1 Coleta Física, Consumo Alimentar e Armazenamento (`DECIDIDO`, `IMPLEMENTADO` e `PLANEJADO`)
- **Consumo Alimentar Coletivo sem Fome/Sede Individual (`DECIDIDO` / `PLANEJADO`):**
  - Não existem barras individuais de fome ou sede nem cozimento ingrediente por ingrediente. Cada habitante terá necessidade periódica descontada do estoque coletivo compartilhado de alimentos (a implementar em etapa futura; taxas e penalidades: `PROPOSTA`/`ABERTO`).
- **Fontes e Atividades Alimentares (`DECIDIDO`):**
  - *`IMPLEMENTADO` e `ATIVO NA MAINSCENE` (T2):* coleta física de frutos em arbustos (`food_bush`), madeira (`wood_tree`) e pedra (`stone_rock`).
  - *`PLANEJADO`:* pesca, caça, plantações/roças e criação de animais — todos compatíveis com transporte físico e estoque coletivo.
- **Coleta e Entrega Estritamente Físicas (`DECIDIDO` / `IMPLEMENTADO` / `HOMOLOGADO` — `P-REC-2`):**
  - Recursos extraídos (`wood` peso `2`, `stone` peso `3`, `food` peso `1` — provisórios em `data/resources/*.tres`) são carregados em `UnitCarryLoad` (`0%` a `100%` da capacidade base provisória `20`, com desaceleração proporcional de `4,8 m/s` vazio até `2,88 m/s` cheio e evolução futura de capacidade `PLANEJADO`).
  - **Proibição de Crédito Instantâneo na Coleta:** Materiais coletados **jamais** entram magicamente no estoque; só são creditados após descarga física em armazenamento válido (`CampStorageZone` hoje; futuros depósitos protegidos em `T3.7`), preservando a proveniência (`FREE_GATHERED`) e a separação entre quantidade unitária e peso.
  - **Retorno Automático na Coleta (`IMPLEMENTADO` T2):** Ao atingir `100%` da capacidade ou quando não couber mais uma unidade (`UnitCarryLoad.can_fit_one`), o trabalhador interrompe a extração e descarrega automaticamente.
- **Armazenamento Inicial vs. Depósito Rústico (`D5`, `D8`):**
  - *`IMPLEMENTADO` e `ATIVO NA MAINSCENE` (T2):* pilhas físicas expostas na `CampStorageZone` (`5,6 × 4,4 m` no `TestMap`).
  - *`DECIDIDO` / `PLANEJADO T3.7`:* **Depósito Rústico** com proteção real (`decay = 0,0`, capacidade provisória `50 madeiras, 50 pedras, 30 alimentos` — `D4`/`D5`), sob autoridade única `SettlementInventory` (`CompositeStorageSource`). **Não afirmar proteção funcional antes da conclusão da `T3.7`.**

### 4.2 Deterioração por Categoria (`DECIDIDO` — `DEC-11A` **RATIFICADA**)
- **Alimentos e Madeira** mantidos expostos no chão sofrem desgaste temporal configurável (`decay_food_provisional.tres`, `decay_wood_provisional.tres`).
- **Pedra bruta exposta não sofre deterioração temporal** (`decay_stone_provisional.tres` com `can_decay = false` — `IMPLEMENTADO` e `HOMOLOGADO`).
- **Nota Histórica de Transição (`DEC-11B` — `SUBSTITUÍDO` em transição `P-REC-1`):** A regra de perda direta sobre reservas de obra (Alternativa B) e a complementação manual de reserva deteriorada (`DEC-11B`, implementada na `T3.5.2`) pertencem exclusivamente ao fluxo antigo de reserva em pilha (`D2`). Elas permanecem ativas em código apenas durante a transição e deixam de existir quando o novo modelo de débito imediato (`D-01`) for validado e aposentado o legado em `R-04B`/`R-04C`.

### 4.3 Construção Canônica (`DECIDIDO` — `D-01`, `D-02`, `D-13`, `P-REC-1`, `P-REC-2` — `PLANEJADO R-04`)
- **Posicionamento Contínuo sem Grid (`D6` — `IMPLEMENTADO` / `HOMOLOGADO` / `ATIVO NA MAINSCENE`):**
  - Edifícios vistos e geridos pelo exterior; `CampStorageZone` protegida contra obras na T3; validação de inclinação ($\le 10^\circ$), desnível ($\le 0,35\text{ m}$), colisões, conectividade em malha candidata assíncrona e inclusão regional no `WorldNavigation` pós-conclusão (`DEC-19` N1).
- **Parâmetros Provisórios `D4` (`DECIDIDO` como provisórios em `data/buildings/*.tres`):**
  - **Abrigo Básico (`shelter_basic`):** $4,0 \times 4,0\text{ m}$, **12 Madeiras + 6 Pedras**, **30,0 s-construtor**, máx. **2 construtores**.
  - **Depósito Rústico (`storage_depot`):** $5,0 \times 4,0\text{ m}$, **18 Madeiras + 10 Pedras**, **45,0 s-construtor**, máx. **2 construtores**; proteção real de **50 madeiras, 50 pedras e 30 alimentos** com `decay = 0,0` (`D5` — **`PLANEJADO T3.7`**).
  - **Restrição (`P-REC-2`):** **Não** introduzir alimentos como custo de construção sem autorização específica.
- **Novo Modelo Canônico de Construção (`DECIDIDO` / `PLANEJADO R-04` — NÃO implementado ainda):**
  1. **Débito Imediato Atômico (`D-01`, `P-REC-2`):** Ao confirmar uma posição válida, o sistema verifica o estoque disponível integral via `SettlementInventory` (recusando integralmente em déficit sem cobrar nada) e executa o **débito imediato e atômico** dos materiais necessários, com rollback integral em caso de falha na criação do canteiro.
  2. **Prioridade de Armazenamento no Débito (`D-13`, `P-REC-2`):** Ao debitar recursos para construção, consumir **primeiro o estoque disponível em depósitos protegidos** e **depois as pilhas expostas**, para todas as categorias de recursos aplicáveis. *(Interface preparada em `R-04`; validação operacional real com depósitos protegidos ocorre exclusivamente em `T3.7`.)*
  3. **Montagem Direta sem Transporte ao Canteiro (`D-01`):** Não é mais necessário transportar fisicamente materiais das pilhas até o canteiro. Ao criar o canteiro, registra-se tarefa comunitária `BUILD_SITE`; trabalhadores (até `max_builders`, hoje `2`) caminham diretamente ao canteiro e executam a montagem até conclusão em `BuildingInstance` + rebake assíncrono (`DEC-19`).
  4. **Cancelamento `R2 Simples` com Arredondamento `floor` (`D-02`, `P-REC-2`):**
     - **Antes de iniciar a montagem (`progresso == 0%`):** devolver **100%** dos recursos pagos.
     - **Após iniciar a montagem (`progresso p > 0%`):** devolver diretamente ao armazenamento válido, por recurso $R$:
       $$M_{\text{reembolso}}(R) = \left\lfloor Q_{\text{pago}}(R) \times (1 - p) \right\rfloor$$
     - **Destino do Reembolso e Anti-Exploração (`P-REC-2`):** Creditar **primeiro nos depósitos protegidos com capacidade disponível** e o eventual excedente nas pilhas válidas do acampamento (`CampStorageZone`), **preservando os dados de exposição dos materiais** para impedir que ciclos de construir e cancelar renovem artificialmente a vida útil de recursos perecíveis.
- **Implementação Histórica Atualmente Ativa em Transição (`P-REC-1`):**
  - No código atual (`c4a6361`), a `MainScene` ainda executa o fluxo antigo (`T3.3`–`T3.6.3`: reserva em pilha `D2`, transporte físico ao canteiro `D9`/`DEC-18`, complementação manual `DEC-11B`, e custódia/recolha física `D3` $\eta = 0,50$).
  - Conforme **`P-REC-1`**, toda essa infraestrutura, seus testes e os retestes pendentes `D3-04`/`D3-07` permanecem preservados (sem declarar `T3.6.4-R1` homologada) e só serão aposentados formalmente em **`R-04C`**, **após** o novo fluxo `D-01`/`D-02` ser implementado, validado e homologado em **`R-04B`**.

### 4.4 Economia Cooperativa, Vestuário, Ferramentas e Comércio Futuro (`DECIDIDO` — `DEC-12`, `v1.1` §8, `PLANEJADO`)
- **Sem Salários ou Moeda Interna (`DECIDIDO` — `DEC-12` / `DESCARTADO` salário interno):** A comunidade opera de forma cooperativa.
- **Vestuário, Ferramentas e Arsenal Compartilhado (`DECIDIDO` — `v1.1` §8, `PLANEJADO T5/T6`):** Roupas produzidas e ferramentas/armas integram o arsenal compartilhado, com atribuição automática por profissão/vocação e opção simples de atribuição manual, sem inventário individual multi-slot de MMORPG.
- **Comércio entre Comunidades (`PLANEJADO Cap. 3`):** Trocas comerciais apenas entre comunidades distintas nos capítulos avançados (`ABERTO` em detalhes).

---

## 5. Profissões, Vocações, Dons Latentes e Cura Inicial (*Alento*) (`PLANEJADO T5/T6`)

### 5.1 Distinção entre Profissão, Vocação e Dom (`DECIDIDO` — `PLANEJADO`)

| Sistema | Definição | Exemplos | Regras de Funcionamento |
|---|---|---|---|
| **1. Profissão** | Trabalho cotidiano produtivo do morador na comunidade. | Agricultor, Pescador, Caçador, Lenhador, Minerador/Pedreiro, Construtor, Costureiro, Ferreiro. | Evolui em **2 camadas (`DEC-08` reconciliada):** (1) distribuidor comunitário básico por tarefas marcadas (`R-03`); (2) `JobSystem` futuro (`T5`) com rotinas autônomas quando `IDLE`. |
| **2. Vocação** | Especialização de defesa ou apoio comunitário. | **Guerreiro**, **Arqueiro**, **Curandeiro**, **Canalizador da Luz**. | Coexiste com a profissão, executando uma tarefa por vez, com prioridade absoluta para ordens pessoais da Casa Fundadora / comandos diretos. |
| **3. Dom** | Capacidade sobrenatural latente ou despertada. | **Alento** (recuperação inicial), proteção luminosa, canalização da Luz. | Já existe em potencial nas pessoas em diferentes ritmos; desperta por aprendizado, treino e mentoria; não obrigatório para todos. |

### 5.2 Regras do Sistema de Dons Latentes (`DECIDIDO` — `PLANEJADO`)
1. **Despertar, não Concessão:** Os protagonistas ajudam a identificar e despertar capacidades latentes que já existem nas pessoas.
2. **Aptidões Individuais e Sem Exclusividade Genética:** Nem todos despertam dons; outras linhagens e comunidades também podem manifestá-los.
3. **Treino, Experiência e Independência Física:** Guerreiros e Arqueiros dependem de treino físico e equipamento; nenhuma vocação exige contador arbitrário de população (exige idade adulta para combatentes plenos, aprendizado, equipamento e infraestrutura).

### 5.3 Cura Inicial dos Líderes: *Alento* vs. Proteção pós-Derrota (`DECIDIDO` — `PLANEJADO T6`)
- ***Alento* (Nome Provisório):** Habilidade limitada de recuperação de ferimentos que desperta nos protagonistas durante a sobrevivência; não ressuscita mortos e não substitui alimentação, cuidados ou moradia.
- **Proteção Especial dos Líderes (`DEC-07`, `D-04`):** Exclusiva dos **2 protagonistas originais** — impede morte definitiva em combate (evento de recuperação com penalidade temporária). Filhos, descendentes, cônjuges externos e demais moradores **podem morrer**.

---

## 6. Evolução da Comunidade (Cinco Níveis Reconciliados) (`DECIDIDO` — `DEC-13`, `PLANEJADO`)

A comunidade avança por **marcos concretos de desenvolvimento e construção**, sem barra de XP e sem depender de aparição/bênção do Ser de Luz:

| Nível | Marco Visual | Desbloqueios Coerentes (`DECIDIDO` — `PLANEJADO`) |
|---|---|---|
| **1** | **Acampamento** | Pilhas físicas na `CampStorageZone` (`IMPLEMENTADO`), coleta física (`IMPLEMENTADO`), **Abrigo Básico**, **Depósito Rústico** (proteção na `T3.7`) e elemento previsto de **Fogueira** (`PROPOSTA`). Sobrevivência do primeiro ano (Cap. 1), manifestação inicial do *Alento* e aparição única do Ser de Trevas após o abrigo. |
| **2** | **Propriedade** | Primeiras **Casas Familiares**, **Roça** (agricultura contínua), **Costura/Tecelagem**, cuidados básicos/ervas e defesa rudimentar (lanças simples), compatíveis com o núcleo familiar e primeiros sobreviventes acolhidos (Cap. 2). |
| **3** | **Povoado** | **Carpintaria** (ferramentas melhores, arco e flecha), **Criação de Animais** e **Montarias**, **Caminhos** estruturados, Paliçadas e infraestrutura inicial de treino para **Arqueiros** e defensores. |
| **4** | **Aldeia** | Mineração, **Ferraria e Arsenal** (**Espada + Escudo** e equipamentos completos para **Guerreiros**), estrutura de cuidados/mentoria (**Curandeiros** especializados e despertar avançado de **Canalizadores da Luz**) e Torres de Defesa. |
| **5** | **Vila** | Oficinas avançadas, **Posto de Trocas** entre comunidades (Cap. 3), fortificações pesadas e organização completa das quatro vocações para enfrentar ameaças sombrias e facções seduzidas. |

*Regra do 1º Lançamento Comercial:* A progressão inicial (Níveis 1–3) sustenta plenamente a experiência familiar dos Capítulos 1 e 2; o teto tecnológico mantém identidade rústica evoluída (sem industrialização moderna — `ABERTO`).

---

## 7. Mundo Contínuo, Clima, Estações e Ecologia (`DECIDIDO` — `D-07`, `D-08`, `DEC-09`, `DEC-10`)

### 7.1 Mundo Contínuo, Geografia Inspirada e Névoa de Exploração (`DECIDIDO` — `D-07`, `PLANEJADO T4`)
- **Topologia Contínua (`DECIDIDO` — substitui `DEC-14`):** O mundo é um **território contínuo original**, inspirado na geografia e nos ecossistemas japoneses (sem constituir representação literal do Japão terrestre), substituindo a antiga divisão por regiões desconectadas via passagens (`DEC-14` = `SUBSTITUÍDO`).
- **Cenário Inicial (`DECIDIDO` — `D-07`):** Região inicial inspirada no **vale de Ueda e no rio Chikuma (Nagano)**, iniciando em uma **clareira inicial próxima à floresta e ao rio**.
- **Visão de Biomas no Mundo Completo (`DECIDIDO`):** Florestas temperadas, vales, rios, montanhas, regiões nevadas ao norte, dunas costeiras (inspiração tipo Tottori), planícies, litoral e áreas subtropicais ao sul — produzidos progressivamente conforme as etapas (`T4+`).
- **Quatro Estações (`DECIDIDO` — `D-07`, `D-08`):** Primavera (estação inicial da chegada), Verão, Outono e Inverno (incluindo neve e o encontro da família visitante no primeiro inverno).
- **Névoa Natural e Exploração (`DECIDIDO` — `D-07`):** Uma **névoa natural** cobre territórios inexplorados e se dissipa organicamente conforme a exploração real dos personagens. **A câmera não pode revelar artificialmente território ainda não explorado.**
- **Mapa Técnico Atual (`IMPLEMENTADO`):** `TestMap` (`64×64 m`) permanece exclusivamente como terreno de fundação técnica durante `T1`–`T3`, sujeito posteriormente ao orçamento gráfico de streaming/LOD na Intel UHD 620 na `T4`.

### 7.2 Ecologia Dinâmica e Fontes Naturais (`DECIDIDO` — `v1.0` §5, `DEC-09`, `DEC-10`)
- **Aparência Coerente Durante a Extração (`DECIDIDO`):** Árvores não permanecem verticais após fornecer troncos; frutos podem ser colhidos sem destruir o arbusto. *(Estado atual `IMPLEMENTADO` T2: animação de queda e `DepletedVisual` temporário com tocos/cascalho.)*
- **Remoção Completa de Fontes Esgotadas (`DEC-09` — `PLANEJADO T4`):** Ao atingir `0` unidades, árvores (após queda) e pedras serão removidas 100% da cena (`queue_free()`), liberando imediatamente navegação e terreno.
- **Regeneração Ecológica, Arbustos, Roças e Caminhos (`DEC-09`, `DEC-10` — `PLANEJADO T4/T5`):** Novas árvores (Muda → Jovem → Adulta) brotam em solo livre onde não existam construções, canteiros, `CampStorageZone` ou **Caminhos** (que bloqueiam vegetação e facilitam o passo). Arbustos regeneram frutas (podendo ser arrancados ao construir). **Roças** funcionam como campos agrícolas contínuos.

---

## 8. Combate e Ameaças (`PLANEJADO T6/T8`)

- **Ameaças (`DECIDIDO`):** Fauna terrestre natural (caça e predadores territoriais), **animais corrompidos pelo Ser de Trevas** (`DEC-05`, perigo episódico) e, no Capítulo 3, **grupos humanos seduzidos pelo Ser de Trevas** (`DEC-07`).
- **Arsenal Compartilhado e Formação Automática (`DECIDIDO` — `v1.1` §8, `DEC-15`):** Armas (`Espada + Escudo`, `Lança`, `Arco e Flecha`) distribuídas a partir do arsenal compartilhado; ao comandar grupos mistos, Guerreiros avançam na frente e Arqueiros/Curandeiros/Canalizadores atuam na retaguarda, com comandos táticos dos 2 Líderes.
- **Mortalidade vs. Proteção (`DECIDIDO`):** Moradores comuns (incluindo filhos e cônjuges externos da Casa Fundadora) podem morrer; os 2 protagonistas originais possuem proteção especial pós-derrota (distinta do *Alento*). *(Números de combate: `ABERTO`).*

---

## 9. Interface, Controles, Arte e Desempenho

### 9.1 Câmera, Trabalho Comunitário e Interface D2.2 (`DECIDIDO`, `IMPLEMENTADO` e `PLANEJADO`)
- **Câmera Isométrica (`IMPLEMENTADO` / `HOMOLOGADO` / `ATIVO NA MAINSCENE`):** `src/camera/rts_camera_rig.gd` — perspectiva `fov = 35°`, `yaw = +45°`, `pitch = -55°`, zoom suave `22–58` (padrão `36`), `WASD`/setas, `MMB` drag, scroll e Edge Scrolling (`6 px`) bloqueado sobre peças sólidas da UI e travado durante pausa (`UI-1.1B R1`).
- **Controles de Trabalho e Coleta Canônicos (`DECIDIDO` — `D-03`, `D-04`, `D-05`, `D-10`, `D-11` — `PLANEJADO R-03A`–`R-03D`):**
  - Seleção de árvores, pedras e arbustos como fontes de trabalho e marcação de múltiplas fontes (clique, `Shift`, caixa iniciada sobre fonte preservando fontes externas ao conjunto).
  - Distribuição automática de trabalhadores comunitários aptos via `CommunityWorkBoard` + `CommunityTaskDispatcher`.
  - **Atribuição manual opcional** restrita a integrantes aptos da **Casa Fundadora** (incluindo cônjuges externos), sem duplicar tarefas.
  - **Prioridade absoluta de ordens pessoais** da Casa Fundadora sobre o trabalho automático; após concluir uma ordem pessoal de movimento (`MoveOrder`), **esperar intervalo configurável** (`D-05`, valor a calibrar) e retornar automaticamente ao trabalho comunitário.
  - **Lista flutuante de tarefas em andamento na HUD (`D-11`)** em um canto livre (sem criar minimapa), com cancelamento fácil que **preserva 100% dos materiais já coletados/transportados** na mochila.
  - *Separação de Estado Real (`23/11/2026`):* Na `MainScene` atual (`c4a6361`), operam ainda a seleção RTS e o clique direito clássico (`IMPLEMENTADO`/`ATIVO NA MAINSCENE`). Os protótipos `UX-1` (`tests/visual/ux_1_tree.tscn`) e `RUX-1/2A/2B` (`tests/visual/rux_*.tscn`) estão **implementados apenas em sandboxes e NÃO homologados** (`D-09a`), sendo unificados e trazidos à `MainScene` em `R-03A`–`R-03D`.
- **Design System D2.2 — Marcos de Pedra e Eclipse (`DECIDIDO` / `HOMOLOGADO DOCUMENTALMENTE` em `cdd9f2f`):**
  - Identidade visual oficial de toda a interface: basalto vulcânico escuro, alabastro claro esculpido, filetes ouro kintsugi, silhuetas chanfradas assimétricas e Visual Consistency Gate (VCG — 10 passos) em [DAWN_OF_KIN_VISUAL_DESIGN_SYSTEM.md](design/DAWN_OF_KIN_VISUAL_DESIGN_SYSTEM.md).
  - *Estado Real (`23/11/2026`):* `UI-1.1A R2` (pedras de recursos, placa superior), `UI-1.1B R1` (hitboxes poligonais, pausa segura `||`/`1×`, proteção de câmera, roteador `Esc`), `UI-1.2` (estelas dos fundadores e lâmina contextual) e **`UI-1.3 R1`** (`c4a6361`: lajes de ação, mesa de maquetes e faixa de validação no topo central) estão **`HOMOLOGADO`**, operando sob dual-mode (`use_d2_2_hud = false` na `MainScene`, testáveis em `tests/visual/ui_1_d2_2_sandbox.tscn`).
  - *Ativação na `MainScene` (`D-ERR-1 B`):* `use_d2_2_hud = true` será ativado por padrão na `MainScene` em **`R-05B`**, logo após a homologação do inspetor D2.2 (`UI-1.4` / `R-05A`), deixando `UI-1.7` (`R-07`) para encerramento definitivo, retirada de legados e benchmark.

### 9.2 Direção Artística e Orçamento Técnico (`DECIDIDO` e `PROPOSTA`)
- **Estilo Visual (`DECIDIDO`):** 3D isométrico estilizado vibrante naturalista, materiais PBR limpos, paisagens acolhedoras legíveis e noites misteriosas legíveis; sem realismo pesado, sem blocos rudes excessivos e sem neon/glow exagerado.
- **Desempenho Alvo (`DECIDIDO`):** Medição empírica obrigatória na **Intel UHD Graphics 620** (`1920×1080`, `gl_compatibility`, meta $p95 \le 16,7\text{ ms}$ e `0` quadros $> 100\text{ ms}$ em tomada CA; limitação em bateria DC documentada em [KNOWN_ISSUES.md](KNOWN_ISSUES.md)). Orçamento de triângulos por personagem e técnicas específicas (LOD, hibernação de RVO, `MultiMesh`) seguem como **`PROPOSTA`**.

---

## 10. Estratégia de Lançamento e Horizontes de Produto (`DECIDIDO` — `P-REC-3`)

### 10.1 Os Quatro Horizontes
1. **A. Visão Completa do Jogo:** Obra integral abrangendo os Capítulos 1–3, linhagem multigeracional, cinco níveis da comunidade, mundo contínuo completo (vales, florestas, montanhas, rios, neve ao norte, dunas costeiras e sul subtropical), quatro estações, quatro vocações plenas, sistema de dons e mentoria, comunidades externas, trocas e guerras contra forças/seguidores das trevas.
2. **B. Demonstração Jogável (Demo):** Experiência curta, polida e representativa contendo o casal controlável, coleta e transporte físico, estoque/depósito, construção do primeiro abrigo, trabalho comunitário fluido e HUD D2.2 em ambiente natural legível. A aparição do Ser de Trevas poderá integrar a demo se pronta, sem bloquear a validação do núcleo de sobrevivência.
3. **C. Primeiro Lançamento Comercial (`Capítulos 1 e 2` — reconciliado por `P-REC-3`):** Experiência familiar completa distribuída entre o **Capítulo 1** (chegada na primavera no vale inspirado em Ueda–Chikuma, sobrevivência inicial, primeiro abrigo, **aparição única do Ser de Trevas** e chegada da **família visitante no primeiro inverno**) e o **Capítulo 2** (convivência com outros sobreviventes, **nascimento e crescimento dos filhos** `Bebê → Criança → Jovem`, agricultura `Roça`, profissões básicas, construções Níveis 1–3, ecologia dinâmica, perigos moderados e cura inicial *Alento*), sem eliminar conteúdos anteriormente aprovados nem antecipar prematuramente as guerras e facções do Capítulo 3.
4. **D. Conteúdo Posterior (`Capítulo 3` e expansão):** Evolução completa das quatro vocações e canalização da Luz, mentoria avançada, expansão plena dos biomas do mundo contínuo, encontros e casamentos (`18+`) com outras comunidades, comércio inter-comunitário, facções humanas seduzidas e guerras contra as trevas.

### 10.2 Matriz de Correspondência: Etapas Técnicas × Entregas Comerciais

*(Sequência operacional detalhada definida em [ROADMAP_MESTRE.md](ROADMAP_MESTRE.md) §4.)*

| Etapa Técnica | Estado Real em `23/11/2026` | Demo Jogável (B) | 1º Lançamento — Cap. 1 e 2 (C) | Conteúdo Posterior — Cap. 3 (D) |
|---|---|---|---|---|
| **T1 — Fundação RTS** | `HOMOLOGADO` / `INTEGRADO` (`t1-complete`) | Obrigatória | Obrigatória | Base |
| **T2 — Trabalho e Recursos** | `HOMOLOGADO` / `INTEGRADO` (`t2-complete`) | Obrigatória | Obrigatória | Base |
| **Reconciliação `R-01`–`R-07` + `T3.7`–`T3.9`** | `R-01` (`UI-1.3 R1` @ `c4a6361`) `HOMOLOGADO`; `R-02A` em candidata; `R-02B`–`T3.9` `PLANEJADO` | Obrigatória (núcleo jogável D2.2 + obra `D-01`/`D-02` + depósito `T3.7` + save `T3.8`) | Obrigatória | Base |
| **T4 — Mundo Contínuo, Estações e Ecologia** | `PLANEJADO` *(não autorizada)* | Ambiente inicial legível | Obrigatória (vale Ueda–Chikuma, 4 estações, névoa natural, remoção/brotação) | Mundo contínuo completo e todos os biomas |
| **T5 — Família, Modulares e `JobSystem`** | `PLANEJADO` *(não autorizada)* | Casal inicial | Obrigatória (Casa Fundadora, escolha de moradia `D-06`, nascimentos/crescimento no Cap. 2, profissões) | Genealogia multigeracional e casamentos externos |
| **T6 — Combate, *Alento* e Vocações** | `PLANEJADO` *(não autorizada)* | Opcional mínimo | Escopo Cap. 1–2 (*Alento*, defesa rústica, ameaças moderadas) | Completo (4 vocações plenas e guerras) |
| **T7 — Narrativa Cap. 1 e Transição Cap. 2** | `PLANEJADO` *(não autorizada)* | Aparição do Ser de Trevas se pronta (não bloqueante) | Obrigatória (Ser de Trevas no Cap. 1 + família visitante no 1º inverno abrindo Cap. 2) | Eventos sombrios posteriores |
| **T8 — Comunidades Externas e Cap. 3** | `PLANEJADO` *(não autorizada)* | Não incluída | Convivência inicial da família acolhida no Cap. 2 | Obrigatória (outras comunidades, casamentos `18+`, trocas e facções seduzidas) |

---

## 11. Arquitetura Técnica e Roadmap Canônico (`T1`–`T8`)

- **Stack (`IMPLEMENTADO`):** Godot `4.7.2.stable`, `GDScript` tipado estrito, `gl_compatibility`, `Jolt Physics`, sem autoloads globais.
- **Persistência (`D1` / `DEC-17` — `PLANEJADO T3.8`):** `SaveManager` versionado (`schema_version = 1`), cobrindo inventário, exposição, depósitos `T3.7`, fontes, `CommunityWorkBoard`, `ControlMode`, obras `D-01`/`D-02` e edifícios concluídos.
- **Roadmap Operacional Único:** Toda a sequência detalhada (`R-01` → `R-02A` → `R-02B` → `R-03A`–`R-03D` → `R-04A`–`R-04C` → `R-05A`–`R-05B` → `T3.7` → `T3.8` → `R-06A` → `R-06B` → `R-07` → `T3.9` → `T4`–`T8`) está normatizada em [ROADMAP_MESTRE.md](ROADMAP_MESTRE.md) §4, com um único incremento ativo por vez e regra permanente de acessibilidade pela `MainScene`.

---

## 12. Registro Consolidado de Decisões Substituídas, Ativas e Pendências

### 12.1 Decisões Históricas Substituídas ou Descartadas (Rastreabilidade)

| Tema | Formulação Histórica Superada | Regra Canônica Vigente (`DECIDIDO`) | Origem / Status |
|---|---|---|---|
| **Ser de Luz no Cap. 1** | Aparição do Ser de Luz fazendo o Ser de Trevas recuar após o abrigo. | O Ser de Luz **não aparece no Capítulo 1**; permanece em bastidores (`ABERTO` para futuro). | `DEC-06` (`DESCARTADO` no Cap. 1) |
| **Encontro com Ser de Trevas** | Confronto agressivo inicial. | **Única aparição pessoal direta** à distância à noite após o 1º abrigo no **Cap. 1**, sem atacar. | `DEC-06` + `P-REC-3` |
| **Origem dos Poderes** | Concessão mágica pelo Ser de Luz. | **Dons Latentes** despertados por aprendizado, treino e mentoria; *Alento* inicial nos líderes. | `DEC-06` |
| **Deterioração da Pedra** | `v1.0` incluía pedra entre materiais perecíveis. | **Pedra bruta exposta não deteriora** (`can_decay = false`). | `DEC-11A` (`IMPLEMENTADO`) |
| **Economia Salarial** | `PROPOSTA` de salários e compra de roupas (`v1.1`). | **Economia cooperativa sem salários internos**; trocas apenas entre comunidades no Cap. 3. | `DEC-12` (`DESCARTADO`) |
| **Suprimento Físico de Obras (`D2`, `D9`/`DEC-18`)** | Reserva em pilha + transporte físico ao buffer do canteiro + papéis `SOLO_SUPPLIER`/`TRANSPORTER`. | **Débito imediato atômico (`D-01`)** + montagem direta (coleta segue física). Código antigo mantido apenas em transição até `R-04C`. | `D-01` + `P-REC-1` (`SUBSTITUÍDO`) |
| **Complementação de Reserva Deteriorada (`DEC-11B`)** | Autorização manual no canteiro para repor reserva em pilha perdida por decaimento. | **Obsoleta no fluxo `D-01`** (não há reserva exposta de obra). Código antigo aposentado somente em `R-04C`. | `D-01` + `P-REC-1` (`SUBSTITUÍDO`) |
| **Cancelamento `D3` ($\eta=0,50$) e Recolha Física** | Reembolso com fator `0,50` sobre incorporado + sobras físicas recuperadas por trabalhadores (`T3.6.3`/`T3.6.4-R1`). | **Reembolso `R2 simples`** (`100%` em `0%`; $\lfloor Q \times (1-p)\rfloor$ `floor` após montar) direto ao armazenamento válido, preservando exposição. | `D-02` + `P-REC-1` + `P-REC-2` (`SUBSTITUÍDO`) |
| **Ordem de Débito na Construção (`P-RUX-4`)** | Recomendação preliminar da minuta `RUX-0` §8.2 de consumir pilhas expostas primeiro. | **Depósito protegido primeiro, depois pilhas expostas** (e reembolso depósito livre → pilhas) para todas as categorias aplicáveis (`T3.7`). | `D-13` + `P-REC-2` (`SUBSTITUÍDO`) |
| **Menu Obrigatório de Equipe (`UX-0`/`UX-1`)** | Exigência de escolher equipe manualmente em toda fonte. | **Marcação automática + atribuição manual opcional restrita à Casa Fundadora** + lista flutuante de tarefas `D-11` na HUD. | `D-03` + `D-10` + `D-11` (`SUBSTITUÍDO` / reconciliado) |
| **Residência Obrigatória de Descendentes (`v1.2` §3.4)** | Todo casal casado obrigado a ocupar casa separada (ou fixado só na Casa Principal em `RUX-0`). | **O jogador escolhe** se o casal descendente fica na Casa Principal ou ocupa casa própria; residências sem interiores jogáveis. | `D-06` (`SUBSTITUÍDO`) |
| **Topologia por Regiões Separadas (`DEC-14`)** | Regiões desconectadas `256–384 m` ligadas por passagens. | **Mundo contínuo original inspirado no Japão** (vale de Ueda–Chikuma, 4 estações, névoa natural por exploração). | `D-07` (`SUBSTITUÍDO`) |
| **Portão Cap. 1 → Cap. 2 aos 12 Anos (`v1.2` §2.2)** | Encontros humanos proibidos até um filho atingir 12 anos (Jovem). | **Família visitante (casal + 1 criança) no primeiro inverno**, antes do 1º filho, abre o **Capítulo 2**; filhos nascem/crescem no Cap. 2; 1º lançamento cobre Cap. 1 e 2. | `D-07` + `D-12` + `P-REC-3` (`SUBSTITUÍDO`) |
| **Calendário Rígido (`DEC-01` `12–15 min/ano`)** | Ritmo fixo `1 ano ≈ 12–15 min` em `1×`. | **`2–3 h/estação`** preservado apenas como hipótese experimental (`D-08`); relação estações × envelhecimento permanece **`ABERTO`** (`P-REC-3`). | `D-08` + `P-REC-3` (`SUBSTITUÍDO` / `ABERTO`) |

### 12.2 Tabela Rastreável de Decisões Ativas
A tabela completa com todos os identificadores (`D1`–`D9`, `DEC-01`–`DEC-19`, `D-01`–`D-13`, `P-REC-1`–`P-REC-4`, `D-ERR-1 B`, `D-ERR-2 C`, `DT-01`–`DT-06`, `D2.2` e `PR #1`), origens, estados de implementação/homologação e etapas futuras está consolidada sem duplicação em **[ROADMAP_MESTRE.md §5](ROADMAP_MESTRE.md#5-matriz-completa-de-decisões-canônicas-e-rastreabilidade)**.

### 12.3 Pendências Abertas (`ABERTO`)
- **Narrativa e Marca:** registro comercial de *Dawn of Kin*, cosmologia última desse mundo, eventual revelação futura do Ser de Luz, texto final do Ser de Trevas no Cap. 1, gatilho Cap. 2 → Cap. 3 e regras detalhadas de diplomacia/troca.
- **Calendário, Balanceamento e Gameplay:** duração definitiva das estações (`D-08` experimental), relação entre estações/anos e envelhecimento humano (`P-REC-3`), duração do intervalo pós-`MoveOrder` (`D-05`), gesto exato da atribuição manual opcional (`R-03C`), posição final de canto da lista `D-11` (`R-03D`/`R-05B`), taxas de consumo alimentar, vagas de dependentes, curva de natalidade, brotação e números de combate.
- **Produção, Licenças e Performance:** escolha de fontes abertas SIL OFL (`DT-03`), verificação jurídica dos 6 assets base gerados por IA (`UI_0_R2_3_2_CLOSEOUT.md` §2), eventual otimização de bateria DC (`KNOWN_ISSUES.md`) e medições empíricas na **Intel UHD Graphics 620** para mundo contínuo (`T4`) e personagens modulares (`T5`).
