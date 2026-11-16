# DAWN OF KIN

**Documento Mestre de Design (GDD) — Versão 1.2 (CANDIDATA PROPOSTA PARA AUDITORIA)**
**Data:** 16 de novembro de 2026
**Status Documental:** **PROPOSTA CONSOLIDADA** — Aguardando auditoria independente do ChatGPT e aprovação expressa do proprietário
**Fonte Normativa Vigente:** [Dawn_of_Kin_GDD_v1.0.md](Dawn_of_Kin_GDD_v1.0.md) permanece como única fonte normativa até promoção formal pelo proprietário
**Base Técnica Auditada:** `main` em `3c6fc0bd36fc3828af5a89662fb23cfb60d37865` (Tag `t3-3-complete`)
**Nome de Trabalho:** *Dawn of Kin* («Aurora da Linhagem»); disponibilidade comercial/marca **ABERTO** antes da publicação

> **Regra de Leitura e Governança:**
> - **DECIDIDO:** escolha expressamente aprovada pelo proprietário (em `v1.0`, `D1–D9`, auditoria/entrevista de 16/11/2026 ou ratificações formais como `DEC-11A`/`DEC-11B`).
> - **IMPLEMENTADO:** comportamento confirmado no código GDScript, cenas `.tscn` ou recursos `.tres` na `main` (`3c6fc0b`).
> - **VALIDADO:** comportamento testado com evidência registrada (testes automatizados, protocolos manuais aprovados e benchmarks).
> - **PROPOSTA:** sugestão técnica ou de design sujeita a validação ou decisão futura, **não** compromisso fechado.
> - **ABERTO:** questão intencionalmente sem definição final, a calibrar/decidir na etapa correspondente.
> - **PENDENTE DE APROVAÇÃO:** item de planejamento técnico dependente de revisão adicional (ex.: revisão `T3.4-ARCHITECTURE-R2`).
>
> **Estado Real do Projeto em 16/11/2026:**
> - **T1 — Fundação RTS:** **CONCLUÍDA, VALIDADA E INTEGRADA** (`t1-complete`, commit `2808799`).
> - **T2 — Trabalho e Recursos:** **CONCLUÍDA, VALIDADA E INTEGRADA** (`t2-complete`, commit `f7c2459`, 14/11/2026; limitação em bateria DC aceita como não bloqueante para a T2).
> - **T3.1 — Contabilidade, Reservas e Saque em Lote:** **CONCLUÍDA, VALIDADA E INTEGRADA** (`ceb3f71`, 15/11/2026).
> - **T3.2 — Validação Espacial, Área Reservada e Prévia sem Grid:** **CONCLUÍDA, VALIDADA E INTEGRADA** (`931ad19`, 15/11/2026).
> - **T3.3 — Canteiro de Obra e Suprimento Físico:** **CONCLUÍDA, HOMOLOGADA E INTEGRADA** (`t3-3-complete`, commit `3c6fc0b`, 16/11/2026).
> - **T3.4+ a T8:** **PLANEJADAS E BLOQUEADAS** para implementação (T3.4 exige revisão técnica `T3.4-ARCHITECTURE-R2` antes de autorização de código).

---

## 1. Identidade, Visão e Pilares de Design

**Pitch:** Um casal foge das explosões da Terceira Guerra Mundial, é resgatado através de uma passagem espacial aberta pelo **Ser de Luz** e desperta sem pertences em uma versão selvagem da Terra, sem civilização humana preexistente. Com comandos simples de estratégia em tempo real (RTS), o jogador transforma a sobrevivência de duas pessoas na origem de uma linhagem familiar que reconstruirá a sociedade, formará laços com outras comunidades sobreviventes e enfrentará a ameaça primordial do **Ser de Trevas**.

### 1.1 Classificação e Experiência Desejada (`DECIDIDO`)
- **Gênero:** Sobrevivência simplificada + construção de assentamento + RTS leve + evolução familiar/linhagem; single-player inicialmente.
- **Perspectiva:** Câmera 3D isométrica, interação prioritariamente pelo mouse.
- **Ritmo:** Contemplativo, intuitivo e agradável de observar; perigo episódico, não combate incessante.
- **Fantasia Central:** Partir de um único casal identificável e personalizável, vê-lo construir um lar, criar filhos com nome, sobrenome e traços herdados, evoluir de um acampamento rústico a uma vila protegida e descobrir outros sobreviventes da mesma tragédia.
- **Referências Funcionais:** *Age of Empires* (seleção e ordens RTS), *Durango: Wild Lands* (natureza e sobrevivência), *Ragnarok/Albion* (regiões conectadas por passagens). Referências servem apenas como inspiração funcional, jamais como ativos a reproduzir.

### 1.2 Os Cinco Pilares de Identidade (`DECIDIDO`)
1. **Linhagem Viva e Identidade Persistente:** Nenhum morador é um recurso descartável. Cada pessoa tem ID imutável, nome próprio, sobrenome familiar, genealogia rastreável, herança visual e vínculo com sua residência.
2. **Economia Física Visível sem Microgestão Excessiva:** Recursos têm peso físico, são carregados pelos trabalhadores e só integram o estoque após entrega em armazenamento válido — mas sem barras individuais de fome/sede ou salários internos entre familiares.
3. **Comando RTS Soberano + Autonomia por Profissão:** As ordens diretas do mouse do jogador têm prioridade máxima, enquanto moradores com profissão trabalham autonomamente quando ociosos (`JobSystem`) e buscam a próxima fonte próxima quando a atual se esgota.
4. **Natureza Vibrante vs. Mistério Sombrio:** Uma paisagem naturalista acolhedora e viva (onde árvores crescem organicamente em solo livre) contrasta com a presença oculta de uma entidade primordial das trevas que corrompe animais e seduz corações humanos.
5. **Escala Regional Sustentável:** Mundo estruturado em regiões amplas conectadas por passagens, mantendo foco em legibilidade e viabilidade técnica para hardware modesto (referência de desenvolvimento: **Intel UHD Graphics 620**).

---

## 2. História, Cosmologia e Progressão Narrativa

### 2.1 Premissa do Mundo e Cosmologia (`DECIDIDO` e `ABERTO`)
- **Prólogo (`DECIDIDO`):** O casal protagonista foge de carro em meio ao colapso da Terceira Guerra Mundial, cercado por bombardeios e explosões nucleares. Quando não parece haver saída, um buraco de minhoca se abre e os transporta.
- **Travessia e Vestuário Inicial (`DECIDIDO`):** A passagem transporta exclusivamente seres vivos (sem carro, inventário, armas ou ferramentas). As roupas rasgadas iniciais são apenas uma convenção visual de apresentação/classificação etária (não itens equipáveis trazidos da Terra), podendo ser substituídas futuramente por roupas produzidas pela comunidade.
- **Destino (`DECIDIDO`):** Uma versão da Terra com biomas e fauna terrestre reconhecíveis, sem cidades, estradas, ruínas de civilização anterior ou humanos originários daquele mundo.
- **O Ser de Luz (`DECIDIDO` — `DEC-05`):** Foi **O Ser de Luz** quem decidiu salvar alguns sobreviventes através da passagem, escolhendo-os para repovoar a terra e enfrentar o mal ali instalado. A identidade última de *"Quem é Ele"* e seus desígnios completos não são explicados de forma expositiva.
- **O Ser de Trevas (`DECIDIDO` — `DEC-05`):** Há milhares de anos, antes de existir vida nessa versão da Terra, uma entidade ancestral maligna — de natureza sombria e opressiva, cujo nome ninguém conhece — instalou-se naquele lugar. Ela não cria exércitos de fantasia genéricos: seu poder corrompe parte da fauna local, deixando esses animais mais fortes e **irradiando trevas** (coexistindo com animais naturais normais), além de tentar seduzir sobreviventes humanos vulneráveis.
- **Outros Sobreviventes (`DECIDIDO`):** Todos os humanos existentes nesse mundo também vieram da Terra em colapso através do fenômeno, chegando em regiões distantes e possivelmente em cronologias diferentes. O casal ignora isso no início. Não existem povos inteligentes não humanos para justificar crescimento populacional.
- **Mistérios Mantidos Intencionalmente em Aberto (`ABERTO`):**
  - A natureza cosmológica exata dessa versão da Terra e a física da travessia (não fixar como fato se trata do mesmo planeta original, viagem no tempo, universo paralelo ou outra explicação).
  - A identidade suprema do Ser de Luz e o critério completo da escolha dos salvos.
  - O nome verdadeiro e a origem última do Ser de Trevas.
  - A estética exata das aparições do Ser de Luz e do Ser de Trevas no Capítulo 1 (a definir na `T7`).

### 2.2 Progressão Narrativa por Capítulos (`DECIDIDO`)

#### Capítulo 1 — O Isolamento
- **Ato I (Sobrevivência Inicial):** Apenas o casal original no mapa; sem aparição ou recrutamento de humanos externos. O jogador aprende seleção RTS, coleta, armazenamento em pilhas, proteção contra deterioração e constrói o **Abrigo Básico** e o **Depósito Rústico**.
- **Ato II (O Evento Fundador — `DEC-06`):** Após erguerem o **Abrigo Básico**, ocorre ainda no Capítulo 1 a primeira aparição do **Ser de Trevas**, revelando ao jogador que o casal não está sozinho ali. Diante do perigo, um **Ser de Luz** se manifesta; sem combate físico direto, a simples presença do Ser de Luz faz o Ser de Trevas recuar e se ocultar. O Ser de Luz abençoa o casal com:
  1. **Sabedoria para Reconstruir:** habilita a evolução de construções simples para avançadas, agricultura, metalurgia, produção de armas e proteções.
  2. **Dons da Luz:** habilita futuramente o despertar de **Guerreiros**, **Arqueiros**, **Curandeiros** e **Magos/Canalizadores da Luz** para vencer as forças das trevas.
- **Ato III (Raízes da Linhagem):** O casal estabelece sua propriedade, tem seus primeiros filhos e acompanha seu crescimento de Bebê para Criança e Jovem, defendendo o lar de animais comuns e das primeiras feras tocadas pela sombra.
- **Portão Narrativo Obrigatório (`DECIDIDO`):** Encontros com outros humanos permanecem estritamente proibidos até que **pelo menos um filho atinja a fase Jovem (12 anos)**.

#### Capítulo 2 — Não Estamos Sozinhos
- **DECIDIDO:** Liberado após o portão do Capítulo 1. Ocorrem apenas **1 ou 2 encontros humanos significativos** inicialmente — nada de fluxo constante ou botão de recrutamento de aldeões.
- Os grupos encontrados vieram da mesma guerra e ergueram pequenos assentamentos distantes; a descoberta deve soar extraordinária e iniciar laços reais entre famílias.

#### Capítulo 3 — Laços entre Comunidades e Conflito contra a Sombra
- **DIREÇÃO APROVADA (`DECIDIDO` — `DEC-02`, `DEC-07`, `DEC-12`):**
  - Contato, cooperação, comércio por trocas de excedentes e casamentos entre jovens das comunidades pacíficas distintas.
  - Em regiões mais distantes, descobre-se que **um grupo de humanos foi seduzido pelo Ser de Trevas**, desencadeando guerras futuras em que a comunidade mobiliza suas vocações de combate e os Dons da Luz contra os seguidores da Sombra e as feras corrompidas.
- **ABERTO:** Regras detalhadas de diplomacia avançada, rotas de troca e desfecho final da campanha contra o Ser de Trevas.

---

## 3. Família, Linhagem, Personagens Modulares e População

### 3.1 Criação do Casal Inicial e Sistema Modular (`DECIDIDO` — consolidado da minuta `v1.1` §7.1–7.5)
- **Criação do Casal Protagonista (`DECIDIDO`):** O jogador pode personalizar formato do rosto e detalhes faciais (olhos, nariz, mandíbula), modelo/textura/cor do cabelo, cor dos olhos e ampla paleta de tons naturais de pele, além de dispor de botão **Randomizar**. Cores escolhidas na criação inicial (inclusive incomuns em cabelo/olhos) são tratadas como naturais e hereditárias.
- **Arquitetura Modular de Personagens (`DECIDIDO`):** Personagens são compostos por peças 3D intercambiáveis (**Cabeça**, **Cabelo**, **Corpo**, **Vestuário**). Peças produzidas com apoio de ferramentas como Blender ou Tripo AI devem passar obrigatoriamente por padronização técnica para Godot (escala, pivô, *skinning*, esqueleto único por faixa etária e materiais recoloríveis).
- **Herança Visual (`DECIDIDO`):** Cada filho herda de forma probabilística (com pequenas variações) formato do rosto/proporções, cor dos olhos, tom de pele, cor/textura natural do cabelo, tendência de altura e constituição física, preservando identidade reconhecível em todas as fases. *(Intensidade numérica exata das variações e influência de avós: `ABERTO`).*

### 3.2 Nomes, Sobrenomes e Identidade Persistente (`DECIDIDO` — `v1.1` §7.5 + `DEC-16`)
- **Identificador Imutável:** Todo personagem possui ID interno único e estável; renomeações nunca alteram ID, genealogia, cônjuge ou residência.
- **Nome e Sobrenome da Linhagem (`DEC-16`):** O casal inicial e cada família possuem **Nome + Sobrenome Familiar** (digitado ou sorteado no criador). Filhos herdam o sobrenome da família.
- **Nomes Automáticos e Edição Livre:** Todo humano (inclusive moradores de comunidades externas, mesmo antes de integrarem a vila) possui nome próprio persistente — sem rótulos genéricos como `Aldeão 1`. Nascimentos na vila recebem automaticamente um nome inédito sugerido (evitando repetição entre irmãos, salvo exceção rara de homenagem a pai/mãe), podendo o jogador editá-lo livremente sem pausar o jogo à força. *(Regras sobre sobrenomes compostos e homenagens a avós: `ABERTO`).*

### 3.3 Ciclo de Vida, Atuação RTS e Calendário (`DECIDIDO` — `DEC-01`, `DEC-04`)
- **Fases:** **Bebê (`0–2 anos`) → Criança (`3–11 anos`) → Jovem (`12–17 anos`) → Adulto (`18+ anos`)**.
- **Vitalidade Adulta:** Ao atingir 18 anos (Adulto), o personagem **para de envelhecer** (não há morte por velhice), mantendo vitalidade plena.
- **Atuação e Limites por Idade (`DEC-04`):**
  - **Bebê (`0–2`):** Dependente, protegido dentro da residência familiar (visível no painel da família/casa, **não** é unidade RTS selecionável ou comandável no mapa).
  - **Criança (`3–11`):** Unidade visível e selecionável no mapa; pode colaborar apenas em **tarefas leves e seguras** (colher frutos de arbustos, pequenas cargas leves), sendo **proibida** de cortar árvores, quebrar pedras, construir estruturas pesadas ou combater.
  - **Jovem (`12–17`):** Contribui quase como adulto no trabalho (coleta madeira/pedra, constrói e aprende profissões); destrava o Capítulo 2 ao atingir essa fase, porém **não pode casar**.
  - **Adulto (`18+`):** Capacidade plena de trabalho, combate e elegibilidade para casamento e residência própria.
- **Escala do Calendário (`PROPOSTA CALIBRADA` — `DEC-01`):**
  - **1 ano de jogo ≈ 12 a 15 minutos** na velocidade `1×` (com controles de velocidade `1×`, `2×` e `4×`).
  - Isso resulta em aproximadamente **2,5 a 3 horas** em `1×` **contadas a partir do nascimento do primeiro filho** até que ele alcance a fase Jovem (12 anos). A duração total do Capítulo 1 até o portão do Capítulo 2 depende também do tempo inicial até ocorrer o primeiro nascimento. *(Pausa automática em eventos e duração de estações: `ABERTO`).*

### 3.4 Nascimentos, Casais, Genealogia, Viuvez e Mortalidade (`DECIDIDO` — `DEC-02`, `DEC-03`, `DEC-04`)
- **Moradia por Casal:** Cada casal casado possui sua própria residência. O **Abrigo Básico** (T3) já serve como primeira residência do casal líder, permitindo iniciar a família no Capítulo 1.
- **Gatilho Autônomo de Nascimento (`DEC-03`):** Reprodução discreta e autônoma (sem cenas íntimas nem microssimulação de gravidez). Exige simultaneamente: (1) casal residindo junto, (2) **vaga de dependente** (Bebê/Criança) disponível na residência, (3) estabilidade alimentar no estoque coletivo, e (4) **intervalo progressivo** que aumenta conforme o número de filhos já tidos pelo mesmo casal — evitando comportamento de "fábrica de humanos" sem impor um teto rígido artificial de 1–3 filhos. *(Valores numéricos exatos de vagas por casa e curva de intervalo: `ABERTO`).*
- **Genealogia e Casamento (`DEC-02`):** Personagens comuns formam afinidades autonomamente (sem pareamento manual diário). É **proibida** afinidade romântica entre parentes diretos até **primos de 1º grau** (pais/filhos, irmãos, tios/sobrinhos e primos de 1º grau), exigindo rastreamento de ancestrais por IDs estáveis. A partir da 2ª geração, jovens de comunidades vizinhas pacíficas (Capítulos 2 e 3) criam afinidade com adultos do assentamento, casam-se e mudam-se para a vila quando houver residência disponível.
- **Viuvez e Orfandade (`DEC-04`):** Se um cônjuge comum morrer por perigos/ataques, o sobrevivente mantém a titularidade da residência e a guarda dos filhos menores; após período de luto no calendário, torna-se elegível a novo casamento sem abandonar os filhos existentes. Se ambos os pais de menores morrerem, os avós (casal líder) ou parentes acolhem as crianças.
- **Mortalidade vs. Proteção dos Líderes (`DECIDIDO`):** Moradores comuns, **inclusive filhos dos protagonistas**, podem morrer em ataques/perigos. Os **dois protagonistas originais nunca morrem**: em 0 HP ocorre resgate pela Luz (`§7.4`).
- **População (`DECIDIDO`):** Sem limite artificial predeterminado de habitantes; o crescimento é limitado pela administração (casas e comida) e pela capacidade computacional (exigindo simulação simplificada para moradores distantes/fora da região ativa).

---

## 4. Trabalho, Economia Física e Construção

### 4.1 Núcleo Econômico e Transporte Físico (`DECIDIDO` e `IMPLEMENTADO` T2)
- **Sem Barras Individuais de Fome/Sede (`DECIDIDO`):** Os moradores são sustentados periodicamente por um estoque coletivo compartilhado de alimentos (sem cozimento complexo ingrediente por ingrediente). *(Consequências graduais de escassez alimentar: `PROPOSTA`).*
- **Transporte Físico Obrigatório (`DECIDIDO` / `IMPLEMENTADO`):** Materiais coletados (madeira, pedra, alimentos e futuras categorias) **não** entram instantaneamente no estoque. Cada trabalhador carrega os itens em `UnitCarryLoad` respeitando peso unitário (`madeira = 2`, `pedra = 3`, `alimentos = 1` — valores provisórios implementados em `data/resources/*.tres`) e capacidade individual (`20` de peso inicial, com desaceleração proporcional ao peso até `2,88 m/s` em 100% vs. `4,8 m/s` vazio).
- **Retorno Automático (`IMPLEMENTADO`):** Ao atingir 100% da capacidade ou não caber mais 1 unidade da fonte atual, o trabalhador retorna ao armazenamento válido mais próximo.
- **Armazenamento Inicial e Pilhas no Mundo (`DECIDIDO` / `IMPLEMENTADO`):** Na T2, descargas formam pilhas físicas individuais (`GroundResourcePile`) na `CampStorageZone` (`5,6 × 4,4 m` no `TestMap`). Pela regra **D8 (`DECIDIDO`)**, materiais poderão futuramente ser largados no chão de qualquer região, mas **só integram o estoque coletivo quando entregues fisicamente a um local de armazenamento válido** (acampamento ou depósito construído). Todas as pilhas/depósitos válidos sincronizam o estoque coletivo sem contagem duplicada.

### 4.2 Deterioração por Categoria e Reposição de Reservas (`DECIDIDO` — `DEC-11A` e `DEC-11B` **RATIFICADAS**)
- **Exposição e Deterioração por Categoria (`DEC-11A` — `RATIFICADO` em 16/11/2026):**
  - **Alimentos e Madeira** mantidos expostos no chão sofrem desgaste temporal configurável (`decay_food_provisional.tres`, `decay_wood_provisional.tres`) e podem perder unidades ao longo do tempo.
  - **Pedra bruta exposta não sofre deterioração temporal** (`decay_stone_provisional.tres` mantido com `can_decay = false`).
  - Futuras categorias de recursos (ex.: ferro, aço, ferramentas) terão perfis de exposição próprios definidos posteriormente, sem presumir automaticamente desgaste idêntico ao de madeira ou alimentos.
- **Perda Direta sobre Reservas (`DECIDIDO` — Alternativa B, `IMPLEMENTADO` na T3.1):** Reservas de obra **não** protegem materiais expostos. Se o desgaste físico (`step_decay()`) reduzir uma pilha abaixo do reservado, as reservas afetadas naquela pilha são reduzidas diretamente até o saldo físico restante, **sem realocação automática silenciosa** para outras pilhas.
- **Reposição de Reservas Deterioradas (`DEC-11B` — `RATIFICADO` em 16/11/2026):**
  - Se material reservado numa pilha se deteriorar antes de ser transportado, a obra preserva o progresso e os materiais já recebidos/incorporados no canteiro, mas passa a apresentar déficit de reserva.
  - A **complementação dessa reserva exige autorização manual expressa do jogador no canteiro**; uma vez autorizada, a nova quantidade só é reservada se houver saldo livre real no estoque (sem retirar reservas de outras obras), após o quê os trabalhadores realizam o **transporte físico normal** até o canteiro (jamais crédito instantâneo).
  - *(Nota de escopo: a interface definitiva pertence à T3.5; eventual comando provisório ou fluxo técnico na T3.4 será especificado na revisão `T3.4-ARCHITECTURE-R2`).*

### 4.3 Construção Progressiva (`D1–D9`, `DEC-18`, `DEC-19`)
- **Exterior sem Interiores Jogáveis (`DECIDIDO`):** Casas e edifícios são vistos e administrados pelo exterior. Área da `CampStorageZone` fica protegida contra construções durante a T3 (`D6` — `IMPLEMENTADO` na T3.2).
- **Prévia Contínua sem Grid (`D6` / `IMPLEMENTADO` T3.2):** Posicionamento livre sobre terreno válido (inclinação $\le 10^\circ$, desnível $\le 0,35\text{ m}$), validação topológica em malha navegável candidata e reserva atômica em lote apenas na confirmação válida (`T3.1` + `T3.3`).
- **Parâmetros Provisórios `D4` (`DECIDIDO` como provisórios sujeitos a balanceamento):**
  - **Abrigo Básico (`shelter_basic`):** $4,0 \times 4,0\text{ m}$, custo **12 Madeiras + 6 Pedras** (`42` de peso), esforço **30,0 s-construtor**, máx. **2 construtores** simultâneos.
  - **Depósito Rústico (`storage_depot`):** $5,0 \times 4,0\text{ m}$, custo **18 Madeiras + 10 Pedras** (`66` de peso), esforço **45,0 s-construtor**, máx. **2 construtores** simultâneos; capacidade provisória de proteção contra decaimento (`0,0`) para **50 madeiras, 50 pedras e 30 alimentos** (`D5`).
- **Organização de Trabalhadores `D9` e Montagem Progressiva (`D2`, `DEC-18`):**
  - **1 trabalhador:** transporta primeiro todos os materiais reservados e acessíveis (`SOLO_SUPPLIER`); quando não houver mais entregas possíveis, assume o posto de construtor e monta com o que estiver disponível no canteiro.
  - **2 trabalhadores:** 1 transporta materiais enquanto 1 constrói simultaneamente com suprimento parcial já entregue no buffer; após finalizar entregas, o transportador pode assumir a 2ª vaga de construtor (`2×` velocidade).
  - **3 trabalhadores:** 1 transporta enquanto 2 constroem simultaneamente (limite máximo de 2 construtores em `shelter_basic` e `storage_depot`); após concluir entregas, o transportador é liberado.
  - **4º trabalhador:** recusado com `no_worker_slot`.
- **Consumo Proporcional e Transmutação (`T3.4` — `PENDENTE DE APROVAÇÃO` da `R2`):** Materiais do buffer do canteiro são consumidos em números inteiros proporcionais ao avanço transacional da montagem (`T3.4-R1`, pendente de fechamento técnico na `T3.4-R2`). Ao atingir 100% com todos os materiais incorporados, o canteiro transmuta-se em `BuildingInstance` e é incluído no `WorldNavigation` da região (`DEC-19` — Opção N1 selecionada para planejamento).
- **Cancelamento com Reembolso (`D3` — planejado para `T3.6`):** Reembolso de 100% do que ainda estiver reservado, em trânsito ou no buffer não consumido (devolvido fisicamente ao acampamento), e recuperação proporcional sobre material já incorporado ($\eta_{\text{demolição}} = 0,50$ provisório).

### 4.4 Profissões, Vestuário, Equipamentos e Economia Cooperativa (`DECIDIDO` — `DEC-08`, `DEC-12`)
- **Modelo Híbrido RTS + Autonomia (`DEC-08`):** Ordens manuais pelo clique direito têm prioridade absoluta. Ao esgotar uma fonte natural, após descarregar no acampamento/depósito, o trabalhador busca automaticamente a fonte próxima do mesmo recurso. Quando o jogador atribui uma profissão (*Lenhador*, *Minerador/Pedreiro*, *Agricultor*, *Construtor*, *Ferreiro*, *Costureiro*, *Curandeiro*, *Guarda/Guerreiro*, *Arqueiro*, *Mago da Luz*), o morador executa sua função autonomamente sempre que estiver `IDLE`.
- **Economia Cooperativa sem Salário Interno (`DEC-12`):** Não há salários, moeda interna nem compra individual de itens entre membros da comunidade. Roupas produzidas (substituindo as roupas rasgadas iniciais) e ferramentas/armas forjadas integram o estoque/arsenal compartilhado da comunidade e equipam automaticamente os moradores conforme sua profissão (com opção simples de atribuição manual, sem inventário complexo de múltiplos slots de MMORPG).
- **Comércio Futuro (`DECIDIDO` — `DEC-12`):** Trocas comerciais ocorrem apenas entre comunidades distintas a partir do Capítulo 3. *(Regras detalhadas de troca e preços relativos: `ABERTO`).*

---

## 5. Evolução da Comunidade (Níveis 1 a 5)

A comunidade evolui por **marcos reais de construção e narrativa** (ligados à **Bênção de Sabedoria** do Ser de Luz), **sem** barra artificial de pontos de experiência e **sem** impor teto rígido arbitrário de população (`DECIDIDO` — `DEC-13`):

| Nível | Marco Visual | Gatilho de Transição e Desbloqueios (`DECIDIDO`) |
|---|---|---|
| **1** | **Acampamento** | Início da jornada: pilhas físicas na `CampStorageZone`, Fogueira (proteção noturna inicial), **Abrigo Básico** e **Depósito Rústico**. *(Concluir o Abrigo Básico dispara o evento do Capítulo 1 — aparição do Ser de Trevas e Bênção de Sabedoria/Dons do Ser de Luz — destravando o Nível 2).* |
| **2** | **Propriedade** | Primeiras **Casas Familiares**, **Roça** (Agricultura contínua), Oficina de **Costura/Tecelagem** (vestuário comunitário substituindo trapos), **Tenda de Cura** (**Curandeiros**) e defesas rústicas iniciais (lanças simples). |
| **3** | **Povoado** | **Carpintaria** (ferramentas aprimoradas, **Arco e Flecha para Arqueiros** e lanças reforçadas), **Criação de Animais** e **Montarias**, **Caminhos** estruturados e Paliçadas. |
| **4** | **Aldeia** | Extração mineral, **Ferraria e Arsenal** (**Espada + Escudo** e proteções metálicas para **Guerreiros**), **Santuário da Luz** (**Magos/Canalizadores da Luz**) e Torres de Defesa. |
| **5** | **Vila** | Oficinas avançadas, **Posto de Trocas** entre comunidades (Cap. 3), fortificações pesadas e mobilização de exércitos/expedições organizadas contra o Ser de Trevas e grupos humanos seduzidos. |

*Nota sobre teto tecnológico (`ABERTO` §6):* A identidade visual e tecnológica mantém caráter rústico evoluído (madeira, pedra, alvenaria, ferraria artesanal), sem avançar para industrialização moderna.

---

## 6. Mundo, Regiões e Ecologia

### 6.1 Estrutura Regional e Expedições (`DECIDIDO` — `DEC-14`)
- **Regiões Conectadas:** O mundo não é um mapa contínuo único gigante; é dividido em regiões amplas conectadas por passagens naturais nas bordas (trilhas, vales, pontes), no espírito estrutural de *Ragnarok/Albion*.
- **Dimensões Planejadas:** O `TestMap` (`64×64 m`) serve exclusivamente aos testes de base (T1–T3). A Região Inicial oficial (T4+) e demais regiões terão entre **`256 × 256 m` e `384 × 384 m`**.
- **Carregamento e Simulação em Segundo Plano:** Apenas a região atualmente observada pelo jogador é renderizada em 3D. Durante expedições em outra região (a pé ou com montarias a partir do Nível 3), a Vila principal continua evoluindo via simulação matemática leve em dados (colheitas, obras, calendário), permitindo alternar a câmera entre Vila e Expedição.
- **Ressalva de Desempenho (`R1-G`):** Nenhuma taxa de FPS é garantida antecipadamente para mapas de `256×256 m`–`384×384 m`; a viabilidade técnica será validada obrigatoriamente por medição empírica na **Intel UHD Graphics 620**.

### 6.2 Ecossistema Vivo, Remoção de Fontes Esgotadas e Caminhos (`DECIDIDO` — `DEC-09`, `DEC-10`)
- **Biomas e Fauna:** Florestas, rios, praias/mar, montanhas e campos com fauna terrestre reconhecível (animais passivos/caçáveis, predadores territoriais e parte dos animais corrompida pelo Ser de Trevas).
- **Remoção Completa de Árvores e Pedras Esgotadas (`DEC-09`):**
  - Diferente do comportamento provisório da T2 (em que `ResourceSource` exibe `StumpMesh` marrom / `RubbleMesh` cinza em `DepletedVisual` e mantém colisores no chão), na versão consolidada do jogo, ao atingir `0` unidades, **Árvores** (após queda) e **Pedras** serão **removidas 100% do mapa (`queue_free()`)**, liberando imediatamente a navegação e o espaço para construir.
- **Regeneração Ecológica de Árvores (`DEC-09`):** Novas árvores (Muda → Jovem → Adulta) brotam organicamente em qualquer solo natural livre do mapa **onde não existam construções, canteiros, `CampStorageZone` ou caminhos**. *(Ritmo exato de crescimento: `ABERTO`).*
- **Arbustos e Roças (`DEC-10`):** Arbustos de frutas regeneram frutos sem destruir a planta, mas podem ser arrancados quando o jogador posicionar uma obra ou caminho sobre eles. **Roças** funcionam como lotes agrícolas contínuos geridos pelo Agricultor.
- **Caminhos (`DEC-09`):** Caminhos construídos pelo jogador organizam a vila, bloqueiam brotação de árvores no trajeto e facilitam o deslocamento dos trabalhadores.

---

## 7. Combate e Ameaças

### 7.1 Ameaças (`DECIDIDO`)
- **Fauna Natural:** Predadores terrestres territoriais e animais caçáveis.
- **Feras Corrompidas pela Sombra (`DEC-05`):** Animais fortalecidos pelo Ser de Trevas que irradiam aura sombria; ameaça episódica (especialmente noturna ou em regiões profundas/anômalas). No início rústico (Nível 1), a **Fogueira** ajuda a manter o perímetro seguro durante a noite até que existam armas e guardas.
- **Grupos Humanos Seduzidos pelo Ser de Trevas (`DEC-07`):** A partir dos capítulos avançados (Capítulo 3), facções humanas que cederam à influência da Sombra protagonizam guerras futuras contra as comunidades da Luz.

### 7.2 Vocações, Arsenal Compartilhado e Formação Tática (`DECIDIDO` — `DEC-06`, `DEC-15`)
- **Arsenal Compartilhado (`DECIDIDO`):** Armas (**Espada + Escudo**, **Lança**, **Arco e Flecha**) e equipamentos são produzidos e distribuídos a partir do arsenal coletivo conforme a vocação.
- **As Quatro Vocações (`DEC-06`, `DEC-15`):**
  1. **Guerreiros (Espada + Escudo / Lança):** Linha de frente física que retém ameaças e protege os aliados.
  2. **Arqueiros (Arco e Flecha):** Dano físico à distância e caça.
  3. **Curandeiros:** Usam ervas e o Dom da Luz para curar aliados feridos e purificar efeitos sombrios automaticamente em batalha.
  4. **Magos / Canalizadores da Luz:** Usam os Dons da Luz para atacar à distância com feixes luminosos e **dissipar/enfraquecer a aura de trevas** das bestas e inimigos corrompidos (sem magia elemental clichê de fantasia alta).
- **Formação Automática e Comandos Especiais dos Líderes (`DEC-15`):** Ao comandar um grupo misto via clique direito, o planejador posiciona automaticamente Guerreiros à frente e Arqueiros/Curandeiros/Magos na retaguarda, com suporte autônomo de cura/purificação. Os **2 Líderes originais** possuem comandos especiais que acionam ou potencializam os *skills* dos soldados em combate.

### 7.3 Derrota, Recuperação e Mortalidade (`DECIDIDO` — `DEC-07`)
- **Líderes Imortais:** Em 0 HP, a proteção do Ser de Luz resgata o líder caído de volta à residência da vila em estado de **Exaustão Temporária** (que passa com o tempo ou pode ser acelerada por um Curandeiro).
- **Moradores Comuns:** Podem morrer definitivamente em combate ou perigos graves (acionando regras de viuvez/acolhimento de §3.4). *(Parâmetros numéricos de HP, dano, alcance e cooldowns: `ABERTO`).*

---

## 8. Interface, Controles, Arte e Experiência do Jogador

### 8.1 Controles RTS e Câmera (`DECIDIDO` e `IMPLEMENTADO` T1–T3)
- **Câmera Isométrica (`IMPLEMENTADO`):** Hierarquia `FocusPivot` → `YawPivot (-45°)` → `PitchPivot (-48°)` → `Camera3D` (`FOV 42°`), zoom suave, pan por teclado (`WASD`/setas), arraste com botão do meio (`MMB`), limites estritos no mapa e **Edge Scrolling acionado exclusivamente na borda real da viewport** (`edge_pan_margin_base_px = 6.0` escalado, somente com foco na janela e mouse dentro da viewport).
- **Seleção e Ordens (`IMPLEMENTADO`):** Clique esquerdo seleciona; arraste cria caixa de seleção; `Shift` adiciona; clique direito dá ordem contextual automática (mover, coletar, entregar, construir; futuramente atacar/interagir); `Esc` cancela prévia/seleção.
- **Interface de Construção (`DECIDIDO` D7 — planejada para `T3.5`):** Botão discreto **Construir** no canto inferior direito, painel retrátil com catálogo de obras, prévia 3D verde/vermelha com motivo claro de rejeição e painel contextual de canteiro com progresso, complemento manual de reserva (`DEC-11B`) e cancelamento — sem sobrepor o HUD de recursos ou o painel da unidade selecionada. *(Na T3.2/T3.3, opera temporariamente o `PlacementTestOverlay`).*

### 8.2 Direção Artística e Orçamento Técnico (`DECIDIDO` e `PROPOSTA`)
- **Estilo Visual (`DECIDIDO`):** **3D isométrico estilizado vibrante naturalista** com materiais PBR limpos, cores vivas e acolhedoras, vegetação abundante com vento leve em shader, água com movimento, variação dia/noite legível em perspectiva RTS e rejeição explícita a realismo pesado, aparência blocada excessiva, neon/glow exagerado e contornos pretos grossos.
- **Legibilidade e Evolução Visual (`DECIDIDO`):** Personagens facilmente identificáveis do alto mesmo após troca de vestuário e crescimento; edificações rústicas evoluindo esteticamente com os níveis da comunidade; construção visual progressiva nas obras.
- **Hipótese de Orçamento 3D (`PROPOSTA` — `DEC-16`):** Para compatibilidade com a GPU-alvo **Intel UHD Graphics 620** em `gl_compatibility`, propõe-se padronização em Esqueleto Único por faixa etária e meta inicial de **`~1.500 a 3.500` triângulos por personagem** com materiais compartilhados parametrizados — tratando-se de **hipótese técnica inicial a validar por medição**, não garantia definitiva.

---

## 9. Arquitetura, Persistência, Desempenho e Roadmap

### 9.1 Stack e Arquitetura Modular (`IMPLEMENTADO` T1–T3.3 e `PROPOSTA` T3.4+)
- **Stack (`IMPLEMENTADO`):** Godot `4.7.2.stable`, `GDScript` tipado estrito (avisos tratados como falha), renderizador `gl_compatibility`, física `Jolt Physics`, sem autoloads globais ocultos.
- **Módulos Já Implementados na `main` (`3c6fc0b`):**
  - `src/camera/`: `RtsCameraRig`, `CameraMath`.
  - `src/core/`: `CollisionLayers` (`terrain`, `obstacles`, `units`, `selection`, `buildings`, `resources`), `InputActions`.
  - `src/rts/`: `SelectionManager`, `SelectionBoxMath`, `WorldPicker`, `PickResult`, `RtsInputController`, `CommandController`, `GroupMovePlanner`, `DestinationMarker`.
  - `src/navigation/`: `WorldNavigation` (bake com *curbs* laterais em rampas, cache estático e sessões candidatas assíncronas).
  - `src/units/`: `Unit`, `UnitMovement` (RVO 2D + anti-queda em borda de navmesh), `CharacterDefinition`, `UnitOrder`, `MoveOrder`, `GatherResourceOrder`, `DeliverToCampOrder`, `ConstructOrder`.
  - `src/economy/`: `ResourceDefinition`, `DecayProfile`, `UnitCarryLoad`, `SettlementInventory`, `SettlementStorageSource`, `GroundPileManager`, `GroundResourcePile`, `PileReservationLedger`, `CampStorageZone`, `EconomyClockController`, `ResourceSource`.
  - `src/buildings/`: `BuildingDefinition`, `PlacementValidator`, `PlacementPreview`, `PlacementController`, `ConstructionManager`, `ConstructionSite`, `BuildSlotPlanner`.
  - `src/ui/`: `ResourceHud`, `SettlementStockpilePanel`, `SelectedUnitPanel`, `DisplayResolutionService`, além de controles temporários de teste (`PlacementTestOverlay`, `TemporaryTestWorkersController`).
- **Módulos Futuros Planejados (`PROPOSTA` T3.4–T8):** `BuildingInstance`, `StorageDepotInstance`, `SaveManager` (núcleo extensível desde a T3.8 — `DEC-17`), `RegionManager`, `EcologicalSpawner`, `JobSystem`, `CharacterAppearance`, `NameService`, `PopulationSystem`, `SettlementLevel`, `CombatSystem`, `ChapterState`.

### 9.2 Desempenho Medido vs. Metas (`VALIDADO` até T3.3)
- **Hardware de Referência:** Intel Core i7-8650U + **Intel UHD Graphics 620**, 16 GB RAM, `1920×1080`, `gl_compatibility`.
- **Critério Alvo:** $p95 \le 16,7\text{ ms}$ ($\ge 60\text{ FPS}$ efetivo de quadro) e `0` quadros $> 100\text{ ms}$ em tomada **CA** (na T2 pós-`B1`, CA mediu mediana $p95 = 9,757\text{ ms}$; bateria DC mediu $p95 = 33,038\text{ ms}$, aceita pelo proprietário em 14/11/2026 como limitação conhecida não bloqueante para a T2, registrada em `docs/KNOWN_ISSUES.md`).
- **Regra de Integridade:** Nenhuma promessa de FPS é assumida para mapas de `256×256 m`–`384×384 m` ou populações maiores sem medição empírica real na Intel UHD 620.

### 9.3 Roadmap Executável Atualizado (`T1`–`T8`)

| Marco | Escopo Consolidado | Situação Real Verificada (`16/11/2026`) |
|---|---|---|
| **T1 — Fundação RTS** | Câmera isométrica, terreno, seleção, ordens de movimento, RVO | **CONCLUÍDA e APROVADA** (`t1-complete`, `2808799`). |
| **T2 — Trabalho e Recursos** | Coleta física com peso, capacidade, pilhas, deterioração, HUD | **CONCLUÍDA e APROVADA** (`t2-complete`, `f7c2459`, 14/11/2026). |
| **T3.1 — Reservas e Saque** | `PileReservationLedger`, lotes atômicos, Alternativa B | **CONCLUÍDA e INTEGRADA** (`ceb3f71`, 15/11/2026). |
| **T3.2 — Validação Espacial** | Prévia contínua sem grid, exclusão D6, malha candidata assíncrona | **CONCLUÍDA e INTEGRADA** (`931ad19`, 15/11/2026). |
| **T3.3 — Canteiro e Logística** | `ConstructionSite`, transporte físico D9, correção de rampas | **CONCLUÍDA, HOMOLOGADA e INTEGRADA** (`t3-3-complete`, `3c6fc0b`, 16/11/2026). |
| **T3.4 — Montagem e Conclusão** | Consumo proporcional, `BuildingInstance`, rebake regional N1 | **EM PLANEJAMENTO BLOQUEADO** (`T3.4-R1` em `6ac2c51`; aguarda `T3.4-ARCHITECTURE-R2` antes de codificar). |
| **T3.5 a T3.9 — Fechamento T3** | UI oficial de construção (T3.5), cancelamento D3 + complemento manual DEC-11B (T3.6), depósitos protetores D5 (T3.7), `SaveManager` extensível v1 (T3.8), validação global (T3.9) | **PLANEJADAS E BLOQUEADAS.** |
| **T4 — Mundo, Calendário e Ecologia** | Ciclo dia/noite, calendário (`12–15 min/ano`), remoção 100% de árvores/pedras esgotadas (`DEC-09`), brotação ecológica, caminhos, `RegionManager` (`256–384 m`) e simulação leve | **PLANEJADA E BLOQUEADA.** |
| **T5 — Família e Personagens Modulares** | Criador do casal (Nome+Sobrenome), esqueleto único modular, herança visual, `Bebê→Criança→Jovem→Adulto`, nascimentos, genealogia e `JobSystem` | **PLANEJADA E BLOQUEADA.** |
| **T6 — Combate, Vocações e Ameaças** | Guerreiros, Arqueiros, Curandeiros, Magos da Luz, formação automática, comandos especiais dos Líderes, resgate pela Luz, feras corrompidas | **PLANEJADA E BLOQUEADA.** |
| **T7 — História e Atmosfera** | Evento fundador do Cap. 1 (Ser de Trevas + Ser de Luz + Bênção), clima, vento, chuva, água e atmosfera noturna | **PLANEJADA E BLOQUEADA.** |
| **T8 — Comunidades e Capítulos 2–3** | Encontros do Cap. 2 após 1º filho Jovem, casamentos entre comunidades, trocas comerciais e guerra contra grupo humano seduzido pela Sombra | **PLANEJADA E BLOQUEADA.** |

---

## 10. Registro Consolidado de Decisões e Pendências

### 10.1 Diretrizes Arquiteturais T3 (`D1`–`D9`) e Decisões da Auditoria Global (`DEC-01`–`DEC-19`)

| ID | Regra Consolidada | Origem Verificada | Estado Atual | Seções Afetadas | Dependências / Pendências Remanescentes |
|---|---|---|---|---|---|
| **D1–D9** | Persistência T3 (D1), transporte físico sem crédito instantâneo (D2), reembolso proporcional `0,50` (D3), custos provisórios Abrigo/Depósito (D4), depósitos protetores T3 (D5), área reservada da `CampStorageZone` (D6), UI botão Construir + painel (D7), armazenamento no mundo (D8), organização 1/2/3/4 trab. (D9) + Alternativa B de decaimento | `T3_architecture_PROPOSAL.md` (14/11/2026) | **DECIDIDO** *(D1, D2, D4, D6, D8, D9 parcialmente **IMPLEMENTADO/VALIDADO** em T3.1–T3.3)* | §4, §8, §9 | D3 em T3.6, D5 em T3.7, D7 em T3.5, D1 em T3.8. |
| **DEC-01** | Calendário compacto: `1 ano ≈ 12–15 min` em `1×` (`~2,5–3h` após nascimento até Jovem 12 anos) | Entrevista `/grill-me` (16/11/2026, Pergunta 1) | **DECIDIDO** *(como regra de ritmo; implementação futura)* | §2.2, §3.3, §9.3 | Calibração fina de estações e consumo na T4 (`ABERTO`). |
| **DEC-02** | Bloqueio de casamento até primos de 1º grau + parceiros de comunidades vizinhas nos Cap. 2 e 3 | Entrevista `/grill-me` (16/11/2026, Pergunta 2) | **DECIDIDO** | §2.2, §3.4 | Implementação do grafo genealógico na T5 e vilas na T8. |
| **DEC-03** | Abrigo Básico inicia família; nascimento autônomo exige vaga de dependente + estabilidade alimentar + intervalo progressivo | Entrevista `/grill-me` (16/11/2026, Pergunta 3) | **DECIDIDO** | §3.4 | Valores numéricos exatos de vagas/curva (`ABERTO`). |
| **DEC-04** | Atuação RTS por idade (Bebê protegido, Criança coleta leve, Jovem quase adulto, Casamento 18+) e viuvez com recasamento após luto / acolhimento | Entrevista `/grill-me` (16/11/2026, Pergunta 4) | **DECIDIDO** | §3.3, §3.4 | Implementação na T5. |
| **DEC-05** | Espinha dorsal mítica: Ser de Luz salvou escolhidos; Ser de Trevas ancestral sem nome corrompe parte da fauna irradiando trevas | Entrevista `/grill-me` (16/11/2026, Pergunta 5) | **DECIDIDO** | §2.1, §7.1 | Estética e mistérios cosmológicos mantidos `ABERTO`. |
| **DEC-06** | Evento fundador após erguer Abrigo Básico no Cap. 1 (Ser de Trevas + Ser de Luz sem luta + Bênção de Sabedoria e Dons da Luz) | Entrevista `/grill-me` (16/11/2026, Pergunta 6) | **DECIDIDO** | §2.2, §5, §7.2 | Encenação na T7 (`ABERTO`). |
| **DEC-07** | Grupo humano seduzido pelo Ser de Trevas gerando guerras futuras no Cap. 3; Líderes salvos pela Luz em 0 HP com exaustão temporária | Entrevista `/grill-me` (16/11/2026, Pergunta 7) | **DECIDIDO** | §2.2, §7.1, §7.3 | Duração da exaustão na T6 (`ABERTO`). |
| **DEC-08** | Modelo Híbrido RTS + Autonomia por Profissão (`JobSystem`): clique direito soberano + busca de próxima fonte + rotina autônoma em `IDLE` | Entrevista `/grill-me` (16/11/2026, Pergunta 8) | **DECIDIDO** | §1.2, §4.4 | Implementação gradual T4/T5. |
| **DEC-09** | Árvores e pedras esgotadas somem 100% (`queue_free()`); novas árvores brotam em solo livre; caminhos evitam brotação e facilitam passo | Entrevista `/grill-me` (16/11/2026, Pergunta 9) | **DECIDIDO** | §6.2, §9.3 | Substitui `DepletedVisual` atual (`INC-01`) na T4 (ou ajuste pós-T3). |
| **DEC-10** | Arbustos regeneram frutas mas podem ser arrancados ao construir; Roças agrícolas contínuas | Entrevista `/grill-me` (16/11/2026, Pergunta 11) | **DECIDIDO** | §6.2 | Implementação na T4/T5. |
| **DEC-11A** | Pedra bruta exposta não sofre deterioração temporal (`can_decay = false` preservado) | Ratificação expressa no pedido de 16/11/2026 | **DECIDIDO (RATIFICADO)** *(parcialmente `IMPLEMENTADO` em `.tres`)* | §4.2 | Corrige antigo texto do GDD v1.0 §5. |
| **DEC-11B** | Reposição de reserva deteriorada exige autorização manual no canteiro; reserva só em saldo livre real; transporte físico sem crédito instantâneo | Ratificação expressa no pedido de 16/11/2026 | **DECIDIDO (RATIFICADO)** | §4.2, §8.1 | Especificar protocolo na `T3.4-R2` e UI definitiva na T3.5. |
| **DEC-12** | Economia cooperativa sem salários ou dinheiro interno; roupas/armas pelo estoque/arsenal coletivo; trocas entre vilas no Cap. 3 | Entrevista `/grill-me` (16/11/2026, Pergunta 12) | **DECIDIDO** | §1.2, §4.4 | Descarta proposta salarial da minuta `v1.1`. |
| **DEC-13** | Escada Níveis 1 a 5 por marcos reais (Depósito Rústico no Nível 1; Curandeiros no 2; Arqueiros no 3; Guerreiros/Magos da Luz no 4; Trocas/Exército no 5) | Entrevista `/grill-me` (16/11/2026, Pergunta 13) | **DECIDIDO** | §5 | Reconcilia tabela antiga da §6 (`PLAN-01`). |
| **DEC-14** | Mapas regionais de `256×256 m` a `384×384 m` conectados por passagens + simulação leve da Vila durante expedições | Entrevista `/grill-me` (16/11/2026, Pergunta 14) | **DECIDIDO** | §6.1, §9.2 | Desempenho sujeito a medição real na UHD 620 (`ABERTO`). |
| **DEC-15** | Combate RTS com formação automática, suporte autônomo de Curandeiros/Magos da Luz e comandos especiais nos Líderes para skills dos soldados | Entrevista `/grill-me` (16/11/2026, Pergunta 15) | **DECIDIDO** | §7.2 | Balanceamento numérico na T6 (`ABERTO`). |
| **DEC-16** | Nome + Sobrenome da Linhagem; padrão 3D estilizado naturalista em esqueleto único (`~1.5k–3.5k` triângulos tratado como `PROPOSTA` inicial) | Entrevista `/grill-me` (16/11/2026, Pergunta 16) | **DECIDIDO** *(orçamento numérico = `PROPOSTA`)* | §3.1, §3.2, §8.2 | Validar orçamento em benchmark na T5. |
| **DEC-17** | `SaveManager` extensível desde a T3.8 + unificação futura do GDD após auditoria independente | Entrevista `/grill-me` (16/11/2026, Pergunta 17) | **DECIDIDO** | §9.1, §9.3 | Aplicável na T3.8 e na promoção documental futura. |
| **DEC-18** | T3.4: montagem com suprimento parcial em equipes (2–3 trab.) e trabalhador solitário transporta reservados acessíveis antes de montar | Diretriz pré-entrevista (preparação T3.4) | **DECIDIDO** | §4.3 | Implementação sujeita à `T3.4-R2` (**PENDENTE DE APROVAÇÃO**). |
| **DEC-19** | T3.4: Opção N1 de inclusão regional de `buildings_root` no `WorldNavigation` | Diretriz preliminar selecionada para planejamento T3.4 | **DECIDIDO (planejamento)** | §4.3 | Especificação e testes sujeitos à `T3.4-R2` (**PENDENTE DE APROVAÇÃO**). |

### 10.2 Resumo de Pendências Legitimamente Abertas (`ABERTO` e `PENDENTE DE APROVAÇÃO`)
1. **`PENDENTE DE APROVAÇÃO` (`T3.4-ARCHITECTURE-R2`):** Complementação transacional manual de reservas (`DEC-11B`), retentativa após falha de `BuildingInstance`, proteção contra obras sobre edifícios concluídos, validação contínua de contribuições no slot, teto inteiro de progresso e suíte ampliada de testes.
2. **`ABERTO` (Marca):** Disponibilidade jurídica/comercial de *Dawn of Kin*.
3. **`ABERTO` (Cosmologia e Mistério):** Natureza exata da versão da Terra/travessia, identidade última do Ser de Luz, nome/origem do Ser de Trevas e apresentação visual final do evento fundador.
4. **`ABERTO` (Balanceamento Numérico):** Taxas de brotação de árvores e regeneração de arbustos, vagas de dependentes por casa, curva do intervalo de nascimentos, HP/dano/alcance/cooldowns de combate, duração da exaustão dos Líderes, receitas de vestuário/ferramentas e regras exatas de troca entre comunidades.
5. **`ABERTO` (Desempenho Empírico):** Medição real de mapas `256×256 m`–`384×384 m`, shaders de corrupção e personagens modulares na **Intel UHD Graphics 620**.

---

**Fim da Candidata GDD v1.2 PROPOSAL.** Documento íntegro para auditoria independente do ChatGPT; nenhuma norma foi promovida e nenhuma implementação da T3.4+ foi iniciada.
