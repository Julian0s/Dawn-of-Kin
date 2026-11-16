# DAWN OF KIN

**Documento Mestre de Design (GDD Único Consolidado)**
**Versão Interna:** **v1.2 — Conteúdo Aprovado pelo Proprietário** (Caminho canônico estável: `docs/Dawn_of_Kin_GDD.md`)
**Data:** 16 de novembro de 2026
**Uso:** Documento mestre único consolidado de Game Design (conteúdo da revisão `R4.1` formalmente aprovado pelo proprietário em `16/11/2026`, commit-base `6e5764f67125da103eec68adb95e5b67ac329ed9`)
**Base Técnica Auditada:** `main` em `3c6fc0bd36fc3828af5a89662fb23cfb60d37865` (Tag `t3-3-complete`)
**Nome de Trabalho:** *Dawn of Kin* («Aurora da Linhagem»); disponibilidade comercial e registro de marca permanecem **ABERTO** antes da publicação

> **Governança e Status Normativo (`R2-H` / Promoção Normativa):**
> - **Aprovação de Conteúdo (`CONCLUÍDA`):** O conteúdo consolidado desta versão `v1.2` (revisão `R4.1`, commit `6e5764f67125da103eec68adb95e5b67ac329ed9`) foi **formalmente aprovado pelo proprietário em 16/11/2026**. Os arquivos concorrentes `Dawn_of_Kin_GDD_v1.0.md`, `Dawn_of_Kin_GDD_v1.1.md` e `Dawn_of_Kin_GDD_v1.2_PROPOSAL.md` foram removidos da árvore ativa via `git rm`, permanecendo integralmente recuperáveis no histórico Git (`3c6fc0b` e `05ca346`).
> - **Vigência Normativa na `main`:** Enquanto este documento não for integrado à `main` mediante autorização expressa do proprietário, o antigo `docs/Dawn_of_Kin_GDD_v1.0.md` permanece vigente na árvore da `main`. Uma vez integrado à `main` por autorização expressa, `docs/Dawn_of_Kin_GDD.md` passa a vigorar como a **única fonte normativa oficial** de Game Design do projeto.
> - **Bloqueio de Implementação:** A aprovação documental deste GDD **não** autoriza a implementação da etapa `T3.4` nem de etapas futuras.
>
> **Marcadores de Status:**
> - **DECIDIDO:** escolha aprovada pelo proprietário (ou estruturada sob delegação expressa de design — ver rastreabilidade na §12.2).
> - **IMPLEMENTADO:** comportamento efetivamente confirmado no código GDScript, cenas `.tscn` ou recursos `.tres` na `main` (`3c6fc0b`).
> - **VALIDADO:** comportamento testado com evidências documentadas (suítes automatizadas, protocolos manuais aprovados e benchmarks).
> - **PLANEJADO (NÃO IMPLEMENTADO):** regra ou sistema aprovado/previsto no design que **ainda não existe** no código atual da `main`.
> - **PROPOSTA:** sugestão técnica, hipótese de orçamento ou parâmetro inicial sujeito a teste — **não** compromisso fechado.
> - **ABERTO:** questão intencionalmente sem definição final, reservada para calibração ou decisão futura.
> - **PENDENTE DE APROVAÇÃO:** especificação técnica dependente de revisão antes de codificar (ex.: `T3.4-ARCHITECTURE-R2`).
>
> **Estado Real do Código na `main` (`3c6fc0b` — 16/11/2026):**
> - **T1 — Fundação RTS:** **CONCLUÍDA, VALIDADA E INTEGRADA** (`t1-complete`, commit `2808799`).
> - **T2 — Trabalho e Recursos:** **CONCLUÍDA, VALIDADA E INTEGRADA** (`t2-complete`, commit `f7c2459`, 14/11/2026).
> - **T3.1 — Contabilidade, Reservas e Saque em Lote:** **CONCLUÍDA, VALIDADA E INTEGRADA** (`ceb3f71`, 15/11/2026).
> - **T3.2 — Validação Espacial, Área Reservada e Prévia sem Grid:** **CONCLUÍDA, VALIDADA E INTEGRADA** (`931ad19`, 15/11/2026).
> - **T3.3 — Canteiro de Obra e Suprimento Físico:** **CONCLUÍDA, HOMOLOGADA E INTEGRADA** (`t3-3-complete`, commit `3c6fc0b`, 16/11/2026).
> - **Nota sobre Controles Temporários de Teste (`R2-F`):** A cena atual contém `Worker3` e `Worker4` (`TemporaryTestWorkersController`) e `PlacementTestOverlay` exclusivamente como ferramentas temporárias de desenvolvimento para testar a regra `D9`. **Eles não fazem parte da população canônica do Capítulo 1**, na qual o jogo começa exclusivamente com **os 2 protagonistas originais** (`LeaderA` e `LeaderB`).
> - **T3.4 a T8:** **PLANEJADAS E BLOQUEADAS** para implementação (T3.4 exige revisão técnica `T3.4-ARCHITECTURE-R2` e autorização expressa antes de qualquer código).

---

## 1. Identidade, Visão e Pilares de Design

**Pitch:** Um casal foge das explosões da Terceira Guerra Mundial, atravessa um fenômeno espacial e desperta sem pertences em uma versão selvagem da Terra, sem civilização humana preexistente conhecida. Com comandos simples de estratégia em tempo real (RTS), o jogador transforma a sobrevivência de duas pessoas no começo de uma linhagem familiar e de uma comunidade viva, enquanto uma presença sombria ancestral anuncia que um grande conflito se aproxima.

### 1.1 Classificação e Experiência Central (`DECIDIDO`)
- **Gênero:** Sobrevivência simplificada + construção de assentamento + RTS leve + evolução familiar/linhagem; single-player inicialmente.
- **Perspectiva:** Câmera 3D isométrica, interação prioritariamente pelo mouse.
- **Ritmo:** Contemplativo, intuitivo e agradável de observar; perigo episódico, não combate constante.
- **Diferencial:** Partir de um único casal identificável e personalizável, acompanhar o nascimento e amadurecimento dos filhos (`Bebê → Criança → Jovem → Adulto`), ver o despertar gradual de profissões, vocações e dons latentes, e mais tarde descobrir outras comunidades sobreviventes.
- **Referências Funcionais:** *Age of Empires* (seleção e ordens RTS), *Durango: Wild Lands* (natureza e sobrevivência), *Ragnarok/Albion* (regiões conectadas por passagens). Referências servem exclusivamente como inspiração funcional, jamais como ativos a copiar.

### 1.2 Os Cinco Pilares de Identidade (`DECIDIDO`)
1. **Linhagem Viva e Identidade Persistente:** Nenhum habitante é genérico ou descartável. Todos possuem ID imutável, nome próprio, sobrenome familiar, genealogia rastreável, herança visual e vínculo residencial.
2. **Economia Física sem Microgestão Excessiva:** Recursos têm peso físico, são transportados pelos trabalhadores até locais válidos de armazenamento e sofrem regras claras de exposição, sem barras individuais de fome/sede e sem salários/moeda interna.
3. **Comando RTS Soberano + Autonomia Cotidiana:** Ordens diretas do jogador pelo mouse têm prioridade máxima, enquanto moradores com profissão executam suas rotinas autonomamente quando ociosos (`JobSystem`, `PLANEJADO`) e buscam a próxima fonte próxima quando a atual se esgota.
4. **Despertar Gradual de Profissões, Vocações e Dons:** Habilidades de trabalho, defesa e capacidades especiais desenvolvem-se por aprendizado, treino, experiência e mentoria — nunca como distribuição mágica instantânea de classes.
5. **Natureza Vibrante em Contraste com o Mistério Sombrio:** Uma paisagem 3D estilizada vibrante e naturalista contrasta com o mistério silencioso do Ser de Trevas e suas influências sobre o mundo.

---

## 2. História, Universo e Progressão Narrativa

### 2.1 Premissa do Mundo e Cosmologia: Bastidores vs. Percepção Jogável (`DECIDIDO` e `ABERTO`)
Para manter a consistência narrativa e o mistério durante a campanha, distingue-se rigorosamente o que pertence à **mitologia de bastidores** daquilo que **os personagens e o jogador sabem em cena**:

- **A Chegada (`DECIDIDO` — Visível ao Jogador):**
  - No prólogo, o casal dirige em meio ao colapso da Terceira Guerra Mundial, cercado por bombardeios e explosões nucleares. Quando parece não haver saída, um buraco de minhoca os transporta.
  - A passagem transporta **apenas seres vivos** (sem carro, inventário, armas ou ferramentas). As roupas rasgadas iniciais são uma convenção visual de apresentação e classificação etária (não equipamento utilizável trazido da Terra), podendo ser substituídas futuramente por roupas produzidas pela comunidade.
  - O destino é **uma versão da Terra**, com biomas e animais terrestres semelhantes aos conhecidos, sem cidades, estradas, ruínas humanas ou povos não humanos inteligentes.
- **Outros Sobreviventes (`DECIDIDO`):**
  - Todos os outros humanos existentes nesse mundo também vieram da Terra em colapso através do fenômeno, surgindo em regiões distintas e possivelmente em momentos diferentes. Isso é desconhecido para o casal no Capítulo 1.
- **Cosmologia de Bastidores (`DECIDIDO` como cânone oculto — `DEC-05`):**
  - **O Ser de Trevas:** Há milhares de anos, antes de existir vida naquele planeta, uma entidade ancestral maligna — cujo nome ninguém conhece — instalou-se naquele lugar. Seu poder pode corromper parte da fauna (tornando esses animais mais fortes e irradiando trevas, enquanto animais normais continuam existindo) e seduzir corações humanos vulneráveis.
  - **O Ser de Luz:** Em bastidores, foi o Ser de Luz quem abriu a passagem para salvar escolhidos da guerra a fim de repovoar a terra e enfrentar o mal ali instalado. Contudo, **o Ser de Luz não aparece no Capítulo 1**, não trava combate direto e sua eventual manifestação ou revelação futura permanece em aberto, sem data ou capítulo obrigatório.
- **Mistérios Mantidos Intencionalmente em Aberto (`ABERTO`):**
  - A natureza cosmológica exata dessa versão da Terra e a física da travessia (não fixar como fato se é o mesmo planeta original, viagem no tempo, universo paralelo ou passado remoto).
  - A identidade última do Ser de Luz, o nome/origem do Ser de Trevas e suas verdadeiras intenções.
  - A origem última dos dons latentes (que permanece misteriosa para os protagonistas durante o Capítulo 1).

### 2.2 Progressão Narrativa por Capítulos (`DECIDIDO` — `PLANEJADO T7/T8`)

#### Capítulo 1 — O Isolamento
- **Ato I — Sobrevivência e Primeiro Abrigo:**
  - Apenas os **2 protagonistas originais** e, posteriormente, seus próprios filhos; nenhuma aparição ou recrutamento de humanos externos.
  - O jogador aprende os controles RTS, coleta frutos, madeira e pedra, forma pilhas no acampamento inicial e constrói o **Abrigo Básico** e o **Depósito Rústico** *(ambas as estruturas pertencem ao Nível 1; pela diretriz técnica `D5`, a implementação funcional do depósito ocorre após o primeiro abrigo funcional, mantendo-se `ABERTO` no design se haverá ou não pré-requisito de desbloqueio entre elas dentro do jogo; a conclusão do primeiro abrigo continua sendo o marco narrativo que dispara a cena noturna do Ato II)*.
- **Ato II — A Única Aparição Pessoal do Ser de Trevas:**
  - Depois que o casal constrói seu primeiro abrigo, ocorre um evento misterioso, preferencialmente em uma noite apropriada.
  - A natureza ao redor fica estranhamente silenciosa.
  - Uma figura sombria surge à distância e dirige algumas palavras ao casal. *(Exemplo provisório de diálogo, ainda não texto final obrigatório: «Saudações, visitantes... O dia se aproxima.»).*
  - A entidade **não luta, não ataca e não explica sua identidade**; após a mensagem, desaparece.
  - **Regra Canônica:** Esta é a **única aparição pessoal direta** do Ser de Trevas nos capítulos atualmente planejados. Ele poderá continuar influenciando animais, o ambiente e grupos humanos em capítulos futuros, sem reaparecer pessoalmente.
  - **Ausência do Ser de Luz:** O Ser de Luz **não** aparece no Capítulo 1, não há confronto entre entidades e não há cena de concessão de bênção após o abrigo.
- **Ato III — Crescimento da Família e Despertar Gradual:**
  - O casal estabelece a propriedade, cultiva alimentos, manifesta sua capacidade inicial de recuperação (*Alento*), tem filhos e acompanha seu amadurecimento de Bebê para Criança e Jovem, lidando com perigos naturais e indícios sombrios moderados.
- **Portão Narrativo Obrigatório (`DECIDIDO`):** Encontros com outros humanos são estritamente proibidos até que **pelo menos um filho alcance a fase Jovem (12 anos)**.

#### Capítulo 2 — Não Estamos Sozinhos
- **DECIDIDO:** Liberado após um filho alcançar a fase **Jovem (12 anos)**. Ocorrem apenas **1 ou 2 encontros humanos significativos** inicialmente — sem fluxo constante de colonos nem botão de recrutamento.
- A descoberta de outras comunidades sobreviventes (também vindas da mesma guerra) não libera casamento precoce: os jovens ainda precisam atingir a fase **Adulta (`18+ anos`)** para casar.

#### Capítulo 3 — Laços entre Comunidades e Conflitos contra a Sombra (`R2-B`)
- **DIREÇÃO APROVADA (`DECIDIDO` — `DEC-02`, `DEC-07`, `DEC-12`):**
  - Cooperação, comércio por trocas de recursos e formação de novas famílias por casamentos **exclusivamente entre personagens Adultos (`18+ anos`)** de comunidades pacíficas distintas, satisfeitas as demais condições familiares, de parentesco e de residência própria.
  - Em regiões distantes, revela-se que **um grupo humano foi seduzido pela influência do Ser de Trevas**, originando conflitos e guerras futuras contra as comunidades livres e contra feras corrompidas.
- **ABERTO:** Regras detalhadas de diplomacia, rotas comerciais permanentes, gatilho numérico eventual para transição do Cap. 2 para o Cap. 3 e capítulos finais da campanha.

---

## 3. Família, Linhagem, Personagens Modulares e População (`PLANEJADO T4/T5`)

### 3.1 Criação do Casal, Personagens Modulares e Herança Visual (`DECIDIDO` e `PROPOSTA` — recuperado da `v1.1` §7.1–7.4 + `DEC-16`)
- **Criação do Casal Inicial (`DECIDIDO`):** Os dois protagonistas serão escolhidos a partir de modelos-base personalizáveis. O jogador poderá personalizar:
  - Formato do rosto e detalhes faciais (olhos, nariz e mandíbula).
  - Modelo, textura e cor do cabelo.
  - Cor dos olhos.
  - Tom de pele dentro de uma ampla faixa de tonalidades naturais.
  - Botão **Randomizar**, capaz de gerar combinações válidas de aparência.
- **Sistema de Cores (`DECIDIDO` — `R3-E`):**
  - **Cabelo e olhos** terão **seleção livre de cores**, inclusive cores incomuns.
  - A **pele** utilizará uma **paleta ampla de tonalidades naturais**.
  - Apenas os **traços biológicos escolhidos para os protagonistas** podem influenciar hereditariamente a aparência dos descendentes, seguindo estritamente os seis traços herdáveis aprovados.
  - **Roupas** possuem cores personalizáveis, **mas a coloração da vestimenta não constitui característica hereditária**.
- **Peças Modulares e Padronização de Esqueleto (`DECIDIDO` — `DEC-16`):** Personagens serão construídos por componentes 3D intercambiáveis (**Cabeça**, **Cabelo**, **Corpo**, **Vestuário**), adotando **esqueleto único padronizado por faixa etária** e padronização técnica obrigatória para Godot (escala, pivô, peso de ossos e encaixes) para evitar duplicação entre variantes (inclusive oriundas de Blender ou Tripo AI).
- **Herança Visual e Crescimento Consistente (`DECIDIDO`):**
  - Cada filho terá sua aparência determinada por uma combinação probabilística das características biológicas dos pais, com pequenas variações (aproximação visual de hereditariedade, não simulação genética científica).
  - **Seis traços herdáveis obrigatórios:**
    1. Formato do rosto e proporções faciais.
    2. Cor dos olhos.
    3. Tom de pele.
    4. Cor e textura natural do cabelo.
    5. Tendência de altura.
    6. Tendência de constituição física.
  - Haverá modelos corporais apropriados para as quatro fases de vida (**Bebê → Criança → Jovem → Adulto**), preservando a identidade visual reconhecível entre fases e entre carregamentos de partidas salvas.
  - **ABERTO:** Intensidade das variações hereditárias, eventual influência de gerações anteriores/ancestrais e limites numéricos das características corporais.
- **PROPOSTA TÉCNICA (orçamento e otimização — `DEC-16` / `v1.1` §7.2–7.3, NÃO promovida a norma fechada):** Orçamento indicativo de `~1.500–3.500` triângulos por personagem, uso de shaders/materiais recoloríveis por instância/superfície e detalhamento específico de *sockets* permanecem propostas técnicas sujeitas a medição empírica na Intel UHD 620.

### 3.2 Nomes, Sobrenomes e Identidade Persistente (`DECIDIDO` e `PROPOSTA` — `v1.1` §7.5 + `DEC-16`)
- **Personagens Externos (`DECIDIDO`):** Todo humano fora do núcleo inicial dos protagonistas possui **nome próprio persistente** mesmo antes de integrar o assentamento do jogador (personagens de outras comunidades já surgem com nomes próprios pré-gerados, sem identificadores genéricos como `Aldeão 1`, e o nome não muda aleatoriamente entre encontros ou carregamentos).
- **Nome e Sobrenome da Linhagem (`DECIDIDO` — `DEC-16`):** O casal protagonista e cada família possuem **Nome + Sobrenome Familiar** (definido ou sorteado na criação). Filhos herdam o sobrenome da família.
- **Renomeação Opcional e Invariância de Identidade (`DECIDIDO`):**
  - Ao passar a integrar o acampamento ou comunidade do jogador, o personagem poderá ser **renomeado manualmente (opcional)**.
  - Alterar o nome **nunca** muda o identificador interno único (`ID`), a genealogia, os vínculos familiares, relacionamentos, histórico ou residência.
  - **Nomes definidos manualmente pelo jogador nunca podem ser substituídos/revertidos pelo sistema automático.**
- **Nomes Automáticos para Filhos (`DECIDIDO`):** Nascimentos na comunidade recebem nome próprio inédito automaticamente (consultando nomes já usados na comunidade e na residência para evitar repetições). Irmãos não recebem nomes idênticos automaticamente, salvo **exceção rara permitida** em que um filho recebe o nome do pai ou uma filha o da mãe como homenagem familiar (nunca padrão). Para filhos dos protagonistas e habitantes, a sugestão automática pode ser editada livremente sem pausar o jogo à força.
- **ABERTO:** Uso de sobrenomes compostos, influência cultural/regional nas listas, homenagem a avós e nomes iguais em comunidades distintas.
- **PROPOSTA TÉCNICA (da `v1.1` §7.5):** Serviço modular `Identity/NameService` totalmente desacoplado de modelos 3D, profissão e equipamentos.

### 3.3 Ciclo de Vida, Limites por Idade e Calendário (`DECIDIDO` e `ABERTO` — `R2-D`)
- **Quatro Fases (`DECIDIDO`):** **Bebê (`0–2 anos`) → Criança (`3–11 anos`) → Jovem (`12–17 anos`) → Adulto (`18+ anos`)**. Ao atingir **Adulto (18 anos)**, os personagens **param de envelhecer** (sem morte por velhice). A progressão das idades ocorre pelo calendário do jogo, não em tempo real.
- **Atuação e Restrições por Idade (`DECIDIDO` — `DEC-04`):**
  - **Bebê (`0–2`):** Dependente; permanece protegido na residência familiar (visível no painel da casa/família, **não** é unidade RTS selecionável ou comandável no mapa).
  - **Criança (`3–11`):** Visível e selecionável; colabora apenas em **tarefas leves e seguras** (colher frutos, pequenas cargas leves), **proibida** de cortar árvores, quebrar pedras, construir pesado ou combater.
  - **Jovem (`12–17`):** Trabalha em coleta, construção e atividades apropriadas à idade; destrava o Capítulo 2 ao atingir 12 anos, porém **não pode casar** e a **especialização combatente plena é reservada aos adultos**.
  - **Adulto (`18+`):** Aptidão plena para todas as profissões, vocações combatentes, casamento e residência própria.
- **Calendário e Ritmo de Jogo (`DECIDIDO` em escala / `ABERTO` em balanceamento fino — `DEC-01`, `R2-D`):**
  - **Escala Base (`DECIDIDO`):** `1 ano de jogo ≈ 12–15 minutos` na velocidade `1×`.
  - **Velocidades Previstas:** `1×`, `2×` e `4×`.
  - **Cronologia do Capítulo 1:** O intervalo de aproximadamente **`2,4 a 3 horas`** em `1×` até um filho completar **12 anos (fase Jovem)** é contado **a partir do nascimento** desse filho, **não** da chegada do casal ao mundo. O tempo inicial anterior ao primeiro nascimento acrescenta duração adicional ao Capítulo 1.
  - **Diretrizes Anti-Espera Artificial (`DECIDIDO`):** Distribuir atividades de sobrevivência, construção, agricultura e exploração ao longo do crescimento familiar; permitir atividades simultâneas; introduzir mudanças observáveis conforme os filhos amadurecem; e **evitar alongar artificialmente** tempos de coleta/construção apenas para ocupar o calendário.
  - **ABERTO (Validação Empírica):** O ritmo final exige testes de experiência do jogador em sessões de diferentes durações antes de recalibrar o calendário; congelamento em eventos e duração de estações seguem em aberto.

### 3.4 Nascimentos, Afinidade, Casais, Genealogia e Viuvez (`DECIDIDO` — `R2-B`, `R2-C`)
- **Afinidade Autônoma e Persistente (`DECIDIDO` — recuperado da `v1.1` §7.7):**
  - Personagens comuns têm **autonomia para criar afinidades e formar casais**.
  - **Casais não são emparelhados/formados aleatoriamente a cada dia pelo sistema.**
  - O vínculo de casal é **persistente** e cada união está associada a uma residência própria da família, sujeita às regras estritas de **idade adulta (`18+ anos`)**, **parentesco** e **moradia**.
- **Residência Inicial:** Cada casal casado exige residência própria. O **Abrigo Básico** (T3) já habilita o casal protagonista a ter seus primeiros filhos no Capítulo 1.
- **Gatilho Autônomo de Nascimento (`DECIDIDO` — `DEC-03`):** Discreto e autônomo (sem cenas íntimas ou microssimulação de gravidez). Exige: (1) casal residindo junto, (2) **vaga de dependente** (Bebê/Criança) disponível na residência, (3) estabilidade alimentar no estoque coletivo, e (4) **intervalo progressivo** que cresce conforme o número de filhos já tidos pelo mesmo casal — evitando comportamento de "fábrica de humanos" sem impor teto rígido artificial de 1–3 filhos. *(Vagas exatas por casa e curva numérica de intervalo: `ABERTO`).*
- **Bloqueio de Consanguinidade e União entre Comunidades (`DECIDIDO` — `DEC-02`, `R2-B`):** Proibida afinidade romântica entre parentes até **primos de 1º grau** (pais/filhos, irmãos, tios/sobrinhos e primos de 1º grau). No Capítulo 3, personagens **Adultos (`18+`)** de comunidades vizinhas pacíficas podem criar afinidade, casar com descendentes adultos do jogador e mudar-se para a vila quando houver residência própria disponível.
- **Viuvez e Orfandade (`DECIDIDO` — `DEC-04`):** Moradores comuns (inclusive filhos dos protagonistas) podem morrer por perigos e ataques. O cônjuge sobrevivente mantém a titularidade da residência e a guarda dos filhos menores, podendo recasar após período de luto no calendário. Se ambos os pais de menores morrerem, os avós (casal líder) ou parentes acolhem as crianças.
- **População (`DECIDIDO`):** Sem teto artificial predeterminado; regulada por moradia, alimentos e capacidade técnica (com simulação simplificada para moradores distantes).

---

## 4. Trabalho, Economia Física e Construção

### 4.1 Coleta, Consumo Alimentar, Retorno Automático e Armazenamento (`DECIDIDO`, `IMPLEMENTADO` T2 e `PLANEJADO`)
- **Consumo Alimentar Coletivo sem Fome/Sede Individual (`DECIDIDO` em regra / `PLANEJADO (NÃO IMPLEMENTADO)` — `R3-A`):**
  1. **Não existem barras individuais de fome ou sede** nem cozimento complexo ingrediente por ingrediente.
  2. **Cada habitante possui uma necessidade periódica de alimentos**, sustentada por um **estoque coletivo compartilhado de alimentos** da comunidade.
  3. O consumo é **descontado periodicamente do estoque coletivo**, de modo que o crescimento populacional aumenta proporcionalmente a demanda alimentar.
  4. A **estabilidade alimentar** do estoque coletivo participa das condições necessárias para novos nascimentos (§3.4).
  5. *Estado atual (`main` `3c6fc0b`):* A implementação atual da T2 ainda **não** executa consumo alimentar periódico por habitante (mecânica futura marcada como `PLANEJADO (NÃO IMPLEMENTADO)`).
  6. *Calibração (`PROPOSTA` / `ABERTO`):* Taxas numéricas exatas de consumo por idade e consequências graduais da escassez alimentar (como eventual redução de produtividade ou risco para moradores comuns) permanecem como `PROPOSTA` / `ABERTO` sujeitas a balanceamento.
- **Fontes e Atividades Alimentares (`DECIDIDO` e `PLANEJADO` — `R3-F`):**
  - *Já implementado na T2 (`IMPLEMENTADO`):* coleta física de frutos em arbustos (`food_bush`), madeira (`wood_tree`) e pedra (`stone_rock`).
  - *Previstos na visão completa (`PLANEJADO`, sem antecipar para a demo sem suporte documental):* **pesca**, **caça**, **plantações/roças** e **criação de animais**, todos compatíveis com transporte físico e estoque coletivo compartilhado.
- **Proibição de Crédito Instantâneo e Capacidade Evolutiva (`DECIDIDO` / `IMPLEMENTADO` T2):** Recursos extraídos (`wood` peso `2`, `stone` peso `3`, `food` peso `1` — provisórios em `data/resources/*.tres`) são carregados em `UnitCarryLoad`, representando a ocupação em porcentagem (`0%` a `100%` da capacidade base provisória `20` por peso na T2, com redução proporcional da velocidade de `4,8 m/s` vazio até `2,88 m/s` cheio) e **permitindo futura evolução da capacidade individual de carga por características, profissão, equipamentos ou melhorias (`DECIDIDO` em regra / `PLANEJADO`, sem valores numéricos fixados na T2)**. Os materiais só entram no estoque coletivo após descarga física em armazenamento válido, distinguindo-se rigorosamente peso de carga e quantidade unitária de itens.
- **Retorno Automático na Coleta (`DECIDIDO` / `IMPLEMENTADO` T2 — `R3-D`):**
  - Quando a carga do trabalhador atingir **100% da capacidade**, ou quando **não houver espaço livre suficiente para comportar mais uma unidade coletável do material** (`UnitCarryLoad.can_fit_one`), ele interrompe automaticamente o ciclo na fonte e retorna para descarregar.
  - *Já implementado na T2 (`IMPLEMENTADO` na `main`):* em `GatherResourceOrder`, o trabalhador retorna exclusivamente às pilhas físicas do acampamento inicial (`CampStorageZone`, `5,6 × 4,4 m` no `TestMap`), formando/agrupando pilhas individuais sincronizadas ao estoque coletivo.
  - *Comportamento futuro (`PLANEJADO` `T3.7` / `T4+`):* suporte a múltiplos depósitos protegidos construíveis e locais de armazenamento em outras regiões (`D8`), mantendo que materiais eventualmente largados fora de armazenamento válido **não** integram o estoque coletivo até transporte físico.

### 4.2 Deterioração por Categoria e Reposição Manual de Reservas (`DECIDIDO` — `DEC-11A` e `DEC-11B` **RATIFICADAS**)
- **Deterioração por Categoria (`DEC-11A` — `RATIFICADO`):**
  - **Alimentos e Madeira** mantidos expostos no chão sofrem desgaste temporal configurável (`decay_food_provisional.tres`, `decay_wood_provisional.tres`).
  - **Pedra bruta exposta não sofre deterioração temporal** (`data/resources/decay_stone_provisional.tres` mantido com `can_decay = false`).
  - Futuras categorias terão perfis próprios sem presumir desgaste automático idêntico.
- **Perda Direta sobre Reservas (`DECIDIDO` — Alternativa B, `IMPLEMENTADO` T3.1):** Reservas de obra não protegem pilhas expostas. Se `step_decay()` reduzir uma pilha abaixo do reservado, a reserva afetada cai até o saldo físico restante, **sem realocação automática** para outras pilhas.
- **Complementação Manual de Reservas Deterioradas (`DEC-11B` — `RATIFICADO` — separação `T3.4` / `T3.5` / `T3.6` conforme `R3-G`):**
  1. Se material reservado numa pilha deteriorar antes do transporte, a reserva diminui e a obra passa a apresentar déficit, preservando integralmente o progresso e os materiais já recebidos/incorporados no canteiro.
  2. O **jogador deve autorizar manualmente o complemento da reserva no canteiro** (não existe reposição automática silenciosa).
  3. A nova quantidade só pode ser reservada se houver **materiais livres reais** no estoque (jamais retirando reservas de outras obras).
  4. Uma vez autorizada e reservada a complementação, os trabalhadores realizam o **transporte físico normal** até o canteiro (jamais crédito instantâneo).
  5. *Separação estrita entre etapas:* a **`T3.4-R2`** especifica a integridade transacional da complementação e seus testes (qualquer acesso provisório só mediante autorização técnica separada); a **`T3.5`** concentra a interface definitiva de inspeção do canteiro e ação manual do jogador; e a **`T3.6`** trata exclusivamente do cancelamento/reembolso proporcional `D3` (mecanismo distinto da complementação).

### 4.3 Construção Progressiva (`D1–D9`, `DEC-18`, `DEC-19`)
- **Posicionamento Contínuo sem Grid (`D6` / `IMPLEMENTADO` T3.2):** Edifícios vistos e administrados pelo exterior; `CampStorageZone` protegida contra obras na T3; validação de inclinação ($\le 10^\circ$), desnível ($\le 0,35\text{ m}$), colisões e conectividade em malha navegável candidata assíncrona.
- **Parâmetros Provisórios `D4` (`DECIDIDO` como provisórios, definidos em `data/buildings/*.tres`):**
  - **Abrigo Básico (`shelter_basic`):** $4,0 \times 4,0\text{ m}$, **12 Madeiras + 6 Pedras** (`42` de peso), **30,0 s-construtor**, máx. **2 construtores**.
  - **Depósito Rústico (`storage_depot`):** $5,0 \times 4,0\text{ m}$, **18 Madeiras + 10 Pedras** (`66` de peso), **45,0 s-construtor**, máx. **2 construtores**; protege até **50 madeiras, 50 pedras e 30 alimentos** com decaimento `0,0` (`D5` — `PLANEJADO T3.7`).
- **Organização de Trabalhadores `D9` e Montagem (`D2`, `DEC-18`):**
  - Na `main` (`3c6fc0b`), a T3.3 implementa o transporte físico até 100% do buffer e a alocação de papéis `D9` até a espera em `BUILDER_STANDBY`.
  - Na etapa futura **`T3.4` (`PLANEJADO / BLOQUEADO`, aguardando `T3.4-ARCHITECTURE-R2`)**:
    - **1 trabalhador:** transporta primeiro todos os materiais reservados e acessíveis (`SOLO_SUPPLIER`); quando não houver mais entregas possíveis, monta a obra com o que estiver disponível no buffer.
    - **2 trabalhadores:** 1 transporta enquanto 1 constrói simultaneamente consumindo suprimento parcial; após concluir entregas, o transportador pode assumir o 2º slot de construtor.
    - **3 trabalhadores:** 1 transporta enquanto 2 constroem (teto de 2 construtores); ao concluir entregas, o transportador é liberado.
    - **4º trabalhador:** recusado com `no_worker_slot` (`IMPLEMENTADO` na T3.3).
    - Consumo inteiro proporcional transacional, conversão em `BuildingInstance` e inclusão no `WorldNavigation` regional (`DEC-19` — Opção N1, sujeita à revisão `T3.4-ARCHITECTURE-R2`).
- **Cancelamento com Reembolso (`D3` — `PLANEJADO T3.6`, distinto da complementação `DEC-11B`):** Devolução integral (100%) de materiais reservados nas pilhas, em transporte e no buffer não consumido do canteiro (retornando fisicamente à área de armazenamento sem criar pilhas avulsas fora dela), e recuperação proporcional sobre material já incorporado à estrutura conforme a fórmula arquitetural aprovada:
  $$M_{\text{recuperado\_incorporado}}(R) = \left\lfloor Q_{\text{incorporado}}(R) \times (1.0 - \text{progresso}) \times \eta_{\text{demolição}} \right\rfloor$$
  onde $\eta_{\text{demolição}} = 0,50$ é taxa provisória sujeita a balanceamento.

### 4.4 Economia Cooperativa, Vestuário, Ferramentas e Comércio Futuro (`DECIDIDO` — `DEC-12`, `v1.1` §8, `PLANEJADO`)
- **Sem Salários ou Moeda Interna (`DECIDIDO` — `DEC-12`):** Não existe pagamento de salário nem compra individual de itens dentro da comunidade.
- **Vestuário, Ferramentas e Arsenal Compartilhado (`DECIDIDO` — `v1.1` §8, `PLANEJADO T5/T6`):** Roupas produzidas (substituindo os trapos iniciais) e ferramentas/armas integram o estoque e arsenal compartilhados da comunidade. **Ferramentas e armas serão atribuídas automaticamente conforme a profissão/vocação do habitante, permitindo uma opção simples de atribuição manual**, sempre **sem** gerenciamento obrigatório de inventário individual com múltiplos slots de MMORPG. *(Critérios detalhados de atribuição automática e efeitos/durabilidade do vestuário: `ABERTO`.)*
- **Comércio entre Comunidades (`PLANEJADO Cap. 3`):** Trocas comerciais ocorrem apenas entre comunidades distintas nos capítulos avançados (`ABERTO` para regras detalhadas).

---

## 5. Profissões, Vocações, Dons Latentes e Cura Inicial (*Alento*) (`PLANEJADO T5/T6`)

O jogo separa claramente três dimensões de desenvolvimento humano, evitando a distribuição artificial e instantânea de classes:

### 5.1 Distinção entre Profissão, Vocação e Dom (`DECIDIDO` — `PLANEJADO`)

| Sistema | Definição | Exemplos | Regras de Funcionamento |
|---|---|---|---|
| **1. Profissão** | Trabalho cotidiano produtivo do morador na comunidade. | Agricultor, Pescador, Caçador, Lenhador, Minerador/Pedreiro, Construtor, Costureiro, Ferreiro. | Qualquer morador em idade apta pode exercer uma profissão; quando `IDLE`, executa sua rotina automaticamente (`JobSystem` — `DEC-08`, `PLANEJADO`). |
| **2. Vocação** | Especialização de defesa ou apoio comunitário. | **Guerreiro**, **Arqueiro**, **Curandeiro**, **Canalizador da Luz**. | Coexiste com a profissão (a profissão **não** é abandonada ao receber uma vocação), mas o personagem executa **uma tarefa por vez**, com prioridade absoluta para ordens manuais do jogador. |
| **3. Dom** | Capacidade sobrenatural latente ou despertada. | **Alento** (recuperação inicial), proteção luminosa, canalização da Luz. | Já existe em potencial nas pessoas em diferentes aptidões/ritmos; desperta e evolui por aprendizado, treino e mentoria. Não é obrigatório para todos. |

### 5.2 Regras do Sistema de Dons Latentes (`DECIDIDO` — `PLANEJADO`)
1. **Despertar, não Concessão:** Os protagonistas **não concedem** poderes sobrenaturais a outras pessoas; eles ajudam a identificar, compreender e despertar capacidades latentes que já existem nos indivíduos.
2. **Aptidões e Ritmos Individuais:** A manifestação de dons sobrenaturais **não é obrigatória** para todos os habitantes; ocorre em diferentes ritmos e escolhas pessoais.
3. **Sem Exclusividade Genética:** Outras linhagens e comunidades também podem manifestar capacidades latentes.
4. **Treinamento, Experiência e Mentoria:** O controle e a eficácia dos dons crescem com uso e treino; aprendizes experientes poderão futuramente ensinar outros habitantes.
5. **Independência das Vocações Físicas:** **Guerreiros** e **Arqueiros** desenvolvem suas especializações por treinamento físico e equipamento, sem depender de poderes sobrenaturais; **Curandeiros** combinam cuidados práticos com eventual despertar de capacidades especiais; **Canalizadores da Luz** constituem especialização avançada posterior (adiados para quando o crescimento da vila justificar).
6. **Requisitos Coerentes:** Nenhuma vocação exige um contador arbitrário de população; exige idade adulta (para combatentes plenos), aprendizado/instrutor, equipamentos e infraestrutura.

### 5.3 Cura Inicial dos Líderes: *Alento* vs. Proteção pós-Derrota (`DECIDIDO` — `PLANEJADO T6`)
- **Habilidade Inicial — *Alento* (Nome Provisório):**
  - Ambos os protagonistas começam com capacidade latente de recuperação que poderá se manifestar naturalmente durante a sobrevivência.
  - Oferece **recuperação limitada de ferimentos**, de uso simples e compreensível, com intervalo de recarga ou custo temporário sujeito a balanceamento (sem sistema complexo de mana no primeiro lançamento).
  - Evolui com a experiência, mas **não ressuscita mortos** e **não substitui** alimentação, cuidados médicos, moradia ou proteção.
- **Distinção Crítica — *Alento* vs. Proteção Especial dos Líderes:**
  - *Alento* é uma habilidade ativa limitada de recuperação.
  - A **Proteção Especial dos Líderes** impede exclusivamente que os **dois protagonistas originais morram definitivamente** em combate: ao caírem em derrota, ocorre um evento especial de recuperação/resgate com penalidade temporária (ex.: exaustão). Moradores comuns (inclusive filhos) **não** possuem essa proteção nem imortalidade indiscriminada e podem morrer.

---

## 6. Evolução da Comunidade (Cinco Níveis Reconciliados) (`PLANEJADO`)

A comunidade avança por **marcos concretos de desenvolvimento e construção**, **sem** depender de aparição ou bênção visível do Ser de Luz, **sem** barra de XP e **sem** exigir mais trabalhadores do que a família pode possuir naquele momento (`DECIDIDO` — `DEC-13` reconciliada):

| Nível | Marco Visual | Desbloqueios Coerentes (`DECIDIDO` — `PLANEJADO`) |
|---|---|---|
| **1** | **Acampamento** | Pilhas físicas na `CampStorageZone` (`IMPLEMENTADO`), coleta inicial (`IMPLEMENTADO`), **Abrigo Básico**, **Depósito Rústico**, e elemento previsto de **Fogueira** (`PROPOSTA` como estrutura de acampamento, sem efeito defensivo numérico fixado). Sobrevivência inicial do casal, manifestação natural do *Alento* e evento noturno da única aparição pessoal do Ser de Trevas após o abrigo. |
| **2** | **Propriedade** | Primeiras **Casas Familiares**, **Roça** (agricultura contínua), **Costura/Tecelagem** (roupas comunitárias), tratamentos básicos/ervas (sem exigir classe Curandeiro especializada) e treinamento rudimentar de defesa (lanças simples) compatível com o núcleo familiar do Capítulo 1. |
| **3** | **Povoado** | **Carpintaria** (ferramentas melhores, arco e flecha), **Criação de Animais** e **Montarias**, **Caminhos** estruturados, Paliçadas e infraestrutura inicial de treino para **Arqueiros** e defensores. |
| **4** | **Aldeia** | Mineração, **Ferraria e Arsenal** (**Espada + Escudo** e equipamentos completos para **Guerreiros**), estrutura de cuidados/mentoria (**Curandeiros** especializados e despertar avançado de **Canalizadores da Luz**) e Torres de Defesa. |
| **5** | **Vila** | Oficinas avançadas, **Posto de Trocas** entre comunidades (Cap. 3), fortificações pesadas e organização completa das quatro vocações e exércitos para enfrentar ameaças sombrias e facções humanas seduzidas. |

*Regra do Capítulo 1:* O jogador **não** precisa alcançar os cinco níveis no Capítulo 1; a progressão inicial (Níveis 1–3) sustenta plenamente a fase familiar isolada. O teto tecnológico mantém identidade rústica evoluída (sem industrialização moderna — `ABERTO`).

---

## 7. Mundo, Regiões, Biomas e Ecologia

### 7.1 Regiões Conectadas e Simulação em Segundo Plano (`DECIDIDO` — `PLANEJADO T4/T8`, `DEC-14`)
- **Topologia Regional:** O mundo não é um mapa aberto contínuo gigante; divide-se em regiões conectadas por passagens nas bordas (estilo *Ragnarok/Albion*), permitindo que outros assentamentos existam em regiões distantes sem manter toda a geometria 3D e IA carregadas simultaneamente.
- **Dimensões Planejadas:** `TestMap` (`64×64 m`) permanece restrito aos testes de fundação (T1–T3). A Região Inicial oficial (T4+) e regiões vizinhas terão entre **`256 × 256 m` e `384 × 384 m`**. *(Número total de regiões e regras exatas de expedições: `ABERTO`).*
- **Simulação Leve:** Apenas uma região principal é renderizada em 3D por vez; regiões inativas mantêm alterações, recursos, casas e populações em simulação matemática leve, permitindo alternar a câmera entre Vila e Expedição. *(Desempenho sujeito a medição empírica na Intel UHD 620).*

### 7.2 Biomas, Ambiente e Ecologia Dinâmica (`DECIDIDO` — `R2-E`, `R2-F`)
- **Biomas e Ambiente da Visão Completa (`DECIDIDO` — preservado da `v1.0` §9):** O mundo completo contempla **florestas, campos, montanhas, rios, praias e mar**, com **fauna e flora terrestre reconhecíveis**, **variações climáticas** e **atmosfera natural** (vento movendo árvores e grama, chuva, água em movimento e variação dia/noite legível).
  - *Separação de Escopo de Produção (`R2-E`):* A **primeira região (1º lançamento Cap. 1)** implementa a paisagem e os ecossistemas necessários à sobrevivência familiar inicial, enquanto a **demonstração jogável** exige apenas ambiente natural legível representativo (sem exigir produzir todos os biomas para a demo).
- **Aparência Coerente Durante a Extração (`DECIDIDO` — `v1.0` §5):** A aparência das fontes de recurso deve refletir coerentemente a extração — **árvores não permanecem verticais após fornecer troncos**, enquanto **frutos podem ser colhidos sem destruir o arbusto**.
  - *Estado Real na `main` (`3c6fc0b` — `IMPLEMENTADO` T2):* árvores pequenas/frágeis atuais utilizam animação de queda sem ferramentas visuais e, ao esgotar (`_remaining_amount == 0`), `ResourceSource` exibe `DepletedVisual` (`StumpMesh` marrom / `RubbleMesh` cinza) mantendo colisores ativos no chão.
  - *Regras Futuras (`PLANEJADO` / `ABERTO`):* ferramentas para árvores maduras e regeneração detalhada de frutos permanecem em aberto/planejadas, além da remoção completa abaixo (`DEC-09`).
- **Remoção Completa de Árvores e Pedras Esgotadas (`DEC-09` — `DECIDIDO`, `PLANEJADO` ainda NÃO implementado):**
  - *Regra Aprovada para Implementação Futura:* Ao atingir `0` unidades, **Árvores** (após queda) e **Pedras** serão **removidas 100% da cena (`queue_free()`)**, liberando imediatamente a navegação e o terreno para construir.
- **Regeneração Ecológica, Arbustos, Roças e Caminhos (`DEC-09`, `DEC-10` — `DECIDIDO`, `PLANEJADO`):**
  - Novas árvores (Muda → Jovem → Adulta) brotarão em qualquer solo livre onde não existam construções, canteiros, `CampStorageZone` ou **Caminhos** (que bloqueiam vegetação e facilitam o passo). *(Tempo exato de brotação: `ABERTO`).*
  - Arbustos regeneram frutas sem destruir a planta, mas podem ser arrancados ao construir sobre o local. **Roças** funcionam como campos agrícolas contínuos cuidados pelo Agricultor.

---

## 8. Combate e Ameaças (`PLANEJADO T6/T8`)

- **Ameaças (`DECIDIDO`):** Fauna terrestre natural (caça e predadores territoriais), **animais corrompidos pelo Ser de Trevas** (mais fortes e irradiando trevas — `DEC-05`, perigo episódico especialmente à noite/locais sombrios) e, no Capítulo 3, **grupos humanos seduzidos pelo Ser de Trevas** (`DEC-07`).
- **Arsenal Compartilhado e Atribuição por Função (`DECIDIDO` — `v1.0` §8 + `v1.1` §8):** Armas (**Espada + Escudo**, **Lança**, **Arco e Flecha**) e ferramentas são produzidas e distribuídas a partir do **arsenal compartilhado**, com **atribuição automática conforme a profissão/vocação do morador e opção simples de atribuição manual**, **sem** gerenciamento obrigatório de múltiplos slots individuais de MMORPG.
- **Formação Automática, Apoio e Líderes (`DECIDIDO` — `DEC-15`):**
  - Ao comandar um grupo misto via clique direito, **Guerreiros** posicionam-se automaticamente na frente, enquanto **Arqueiros**, **Curandeiros** e **Canalizadores da Luz** atuam na retaguarda (com cura/purificação autônoma e dissipação da aura sombria).
  - Os **2 Líderes originais** possuem comandos especiais táticos que acionam ou potencializam os *skills* dos soldados.
- **Mortalidade vs. Proteção (`DECIDIDO`):** Moradores comuns (inclusive filhos) podem morrer em combate; os dois Líderes nunca morrem definitivamente (possuem evento de recuperação com penalidade temporária, distinto da habilidade *Alento*). *(HP, dano, alcance, formações avançadas e cooldowns: `ABERTO`).*

---

## 9. Interface, Controles, Arte e Desempenho

### 9.1 Câmera e Controles RTS (`IMPLEMENTADO` na `main` `3c6fc0b` — `R2-A`)
Configuração exata confirmada em `src/camera/rts_camera_rig.gd` e `src/camera/rts_camera_rig.tscn` (sem overrides em `src/main/main.tscn`):
- **Projeção e Pivôs (`IMPLEMENTADO`):** Câmera perspectiva com **`fov_degrees = 35.0`** (`near = 0.5`, `far = 250.0`), **`yaw_degrees = 45.0`** (`+45°` no `YawPivot`) e **`pitch_degrees = 55.0`** (aplicado como rotação negativa **`-55°`** no `PitchPivot`).
- **Zoom e Limites (`IMPLEMENTADO`):** Distância padrão `36.0` (zoom suave exponencial entre `min_distance = 22.0` e `max_distance = 58.0`), velocidade de pan proporcional à distância, uso de `delta` real de processo e contenção estrita do foco dentro de `map_bounds`.
- **Controles de Entrada (`IMPLEMENTADO`):**
  - Seleção individual por clique esquerdo e seleção múltipla por caixa (com `Shift` aditivo).
  - Clique direito contextual (`src/rts/command_controller.gd`):
    - *Implementado (`main` `3c6fc0b`):* **mover** (clique em terreno, obstáculo ou unidade), **coletar** recurso em fonte (`ResourceSource`, com retorno automático de descarga à `CampStorageZone` ao encher ou esgotar via `GatherResourceOrder`) e **suprir canteiro** (`ConstructionSite` via `ConstructOrder` na T3.3, levando materiais até o buffer).
    - *Planejado (`PLANEJADO T3.4+ / T6+`):* **montagem progressiva** de construções até conclusão (`T3.4`) e comandos contextuais de **atacar/interagir** (`T6+`).
    - *Proposta futura opcional (`PROPOSTA`, sem compromisso de implementação na `T3.4`):* eventual comando manual direto de **entregar** carga fora do ciclo automático (preservando os comportamentos já implementados de descarga automática na coleta e suprimento físico de canteiros). `Esc` cancela prévia/seleção.
  - Movimento da câmera via `WASD`/setas, arraste com botão do meio (`MMB`), zoom no scroll e **Edge Scrolling (`edge_pan_enabled = true`, `edge_pan_margin_base_px = 6.0`) acionado exclusivamente na borda real da viewport** quando a janela tem foco e o mouse está dentro da janela.
- **UI de Construção e Contexto (`D7` — `PLANEJADO T3.5`):** Botão discreto **Construir** no canto inferior direito, painel retrátil de edifícios e inspetor contextual de canteiro (progresso, botão manual de complemento de reserva `DEC-11B` e cancelamento `D3`), sem sobrepor os HUDs existentes. *(Na T3.2/T3.3 opera temporariamente o `PlacementTestOverlay`).*

### 9.2 Direção Artística e Orçamento Técnico (`DECIDIDO` e `PROPOSTA`)
- **Estilo Visual (`DECIDIDO`):** **3D isométrico estilizado vibrante naturalista**, materiais PBR limpos, paisagens acolhedoras legíveis de perspectiva alta, iluminação diurna agradável e noites misteriosas legíveis; evitar realismo pesado, aparência excessivamente blocada, neon/glow exagerado e contornos pretos grossos. *(Intensidade exata de estilização/shaders: `ABERTO`).*
- **Personagens Modulares e Desempenho (`DECIDIDO` + `PROPOSTA` — `DEC-16`):** A padronização de **esqueleto único por faixa etária** integra a arquitetura aprovada de personagens modulares (`DECIDIDO`, §3.1); já o orçamento de `~1.500–3.500` triângulos por personagem e técnicas específicas de otimização (LOD, hibernação de RVO, `MultiMesh`, shaders recoloríveis) permanecem como **propostas técnicas iniciais (`PROPOSTA`)**, não garantias validadas. Mantém-se a obrigação de medição empírica na **Intel UHD Graphics 620** (`1920×1080`, `gl_compatibility`, meta $p95 \le 16,7\text{ ms}$ e `0` quadros $> 100\text{ ms}$ em tomada CA; limitação em DC documentada em [KNOWN_ISSUES.md](KNOWN_ISSUES.md)).

---

## 10. Estratégia de Lançamento e Horizontes de Produto (`R2-G`)

### 10.1 Os Quatro Horizontes (`DECIDIDO`)
1. **A. Visão Completa do Jogo:** Obra integral abrangendo os Capítulos 1–3, linhagem multigeracional, cinco níveis da comunidade, regiões conectadas com todos os biomas (florestas, campos, montanhas, rios, praias/mar), quatro vocações plenas, sistema de dons e mentoria, comunidades externas, trocas e guerras contra as forças/seguidores das trevas.
2. **B. Demonstração Jogável (Demo):** Experiência curta, polida e representativa contendo o casal controlável, coleta e transporte físico, estoque/alimentação/depósito, construção do primeiro abrigo e ambiente natural legível. A aparição misteriosa do Ser de Trevas **poderá** ser incluída na demo caso o sistema narrativo já esteja pronto, mas **não** transforma a T7 inteira em bloqueio obrigatório para validar o núcleo de sobrevivência e construção. *(Não exige genealogia completa, todos os biomas, exércitos ou múltiplas regiões).*
3. **C. Primeiro Lançamento Comercial (Capítulo 1 Completo):** Experiência familiar completa do isolamento: casal e residência, nascimento e crescimento dos filhos (`Bebê → Criança → Jovem`), agricultura (`Roça`), profissões básicas autônomas, construções funcionais (Níveis 1–3), economia coletiva, natureza dinâmica (remoção e brotação de árvores), perigos moderados, cura inicial dos líderes (*Alento*), **aparição única e misteriosa do Ser de Trevas após o abrigo**, e encerramento do Capítulo 1 quando o primeiro filho atinge a juventude (preparando o Capítulo 2 sem antecipá-lo nem liberar classes avançadas prematuramente).
4. **D. Conteúdo Posterior (Capítulos 2 e 3):** Evolução completa das quatro vocações e canalização da Luz, mentoria avançada de dons, múltiplas regiões conectadas, encontros e casamentos (entre Adultos `18+`) com outras comunidades, comércio inter-comunitário, facções humanas seduzidas e guerras contra as trevas.

### 10.2 Matriz de Correspondência: Etapas Técnicas (`T1`–`T8`) × Entregas Comerciais

*(Esta matriz não altera a sequência técnica `T3.4`–`T8` e não promete datas).*

| Etapa Técnica do Roadmap | Estado Real em `16/11/2026` | Demo Jogável (B) | 1º Lançamento — Cap. 1 (C) | Conteúdo Posterior — Cap. 2–3 (D) |
|---|---|---|---|---|
| **T1 — Fundação RTS** | **IMPLEMENTADA / VALIDADA** (`t1-complete`) | Obrigatória | Obrigatória | Base |
| **T2 — Trabalho e Recursos** | **IMPLEMENTADA / VALIDADA** (`t2-complete`) | Obrigatória | Obrigatória | Base |
| **T3 — Construção, Depósitos e Save Base** | `T3.1–T3.3` **CONCLUÍDAS** (`t3-3-complete`); `T3.4–T3.9` **PLANEJADAS** | Obrigatória | Obrigatória | Base |
| **T4 — Mundo, Calendário e Ecologia** | **PLANEJADA** | Ambiente básico | Obrigatória (região Cap. 1, calendário, remoção/brotação) | Multirregional completa + todos os biomas |
| **T5 — Família, Modulares e `JobSystem`** | **PLANEJADA** | Casal inicial (criador opcional) | Obrigatória (`Bebê→Jovem`, criador, profissões básicas) | Genealogia multigeracional e casamentos externos |
| **T6 — Combate, *Alento* e Vocações** | **PLANEJADA** | Opcional mínimo | Escopo Cap. 1 (*Alento*, defesa rústica e ameaças moderadas) | Completo (4 vocações plenas, exércitos e guerras) |
| **T7 — História Cap. 1 e Atmosfera** | **PLANEJADA** | Aparição do Ser de Trevas apenas se pronta (não bloqueante) | Obrigatória (evento noturno do Ser de Trevas + clima/vento/água) | Eventos sombrios posteriores |
| **T8 — Comunidades, Cap. 2–3 e Diplomacia** | **PLANEJADA** | Não incluída | Apenas gancho de abertura ao atingir Jovem 12 anos | Obrigatória (encontros, casamentos `18+`, trocas e facções) |

---

## 11. Arquitetura Técnica e Roadmap (`T1`–`T8`)

- **Stack (`IMPLEMENTADO`):** Godot `4.7.2.stable`, `GDScript` tipado estrito, `gl_compatibility`, `Jolt Physics`, sem autoloads globais.
- **Persistência (`DEC-17` — `PLANEJADO T3.8`):** O módulo da `T3.8` será construído como núcleo extensível do `SaveManager` versionado (`schema_version = 1`), evitando descarte na `T4`.
- **Bloqueio Estrito da `T3.4` (`PENDENTE DE APROVAÇÃO`):** A etapa `T3.4` segue bloqueada para implementação até revisão **`T3.4-ARCHITECTURE-R2`** cobrindo: (1) complementação manual transacional de reservas (`DEC-11B`), (2) retentativa após falha de `BuildingInstance`, (3) proteção contra novas obras sobre edifícios concluídos, (4) validação de contribuições no slot, (5) teto inteiro de progresso e (6) testes adicionais de regressão, navegação (`DEC-19`) e contabilidade.

---

## 12. Registro Consolidado de Decisões, Evoluções Substituídas e Pendências

### 12.1 Registro Compacto de Decisões Substituídas (Rastreabilidade Histórica)

| Tema | Formulação Histórica Superada | Regra Canônica Vigente nesta RC (`DECIDIDO`) | Origem da Substituição |
|---|---|---|---|
| **Ser de Luz no Cap. 1** | Auditoria Argon inicialmente previa aparição do Ser de Luz no Cap. 1 fazendo o Ser de Trevas recuar após o abrigo. | **O Ser de Luz não aparece no Capítulo 1**; permanece apenas em bastidores, com manifestação/revelação reservada para decisão futura. | **Diretriz expressa do Proprietário** |
| **Encontro com Ser de Trevas** | Encontro agressivo/confronto direto inicial. | **Única aparição pessoal direta** à distância à noite após o abrigo, proferindo poucas palavras sem atacar e desaparecendo. | **Diretriz expressa do Proprietário** |
| **Origem dos Poderes** | Cena explícita de concessão de bênção pelo Ser de Luz após o abrigo. | **Dons Latentes:** os dons já existem nas pessoas; os líderes ajudam a identificá-los e despertá-los por treino/mentoria; líderes iniciam com *Alento* latente. | **Diretriz expressa do Proprietário** |
| **Gatilho do Nível 2** | Condicionado à aparição/bênção do Ser de Luz. | **Marcos concretos de desenvolvimento** (sem depender do Ser de Luz). | **Diretriz de design delegada ao ChatGPT** |
| **Classes / Vocações** | Mistura inicial de profissões e classes de combate prontas cedo. | **Tripartição Profissão × Vocação × Dom**, com especialização gradual e combatentes plenos apenas adultos (`18+`). | **Diretriz de design delegada ao ChatGPT** |
| **Reposição de Reserva Deteriorada** | Recomendação inicial do Argon de reposição automática silenciosa. | **Autorização manual obrigatória no canteiro (`DEC-11B`)**, usando saldo livre real e transporte físico. | **Ratificação expressa do Proprietário** |
| **Deterioração da Pedra** | Texto antigo da `v1.0` (§5) incluía pedra entre materiais que deterioram no chão. | **Pedra bruta exposta não deteriora (`DEC-11A`)**, mantendo `decay_stone_provisional.tres` (`can_decay = false`). | **Ratificação expressa do Proprietário** |
| **Economia Salarial** | `PROPOSTA FUTURA` da antiga `v1.1` (§5) com salários e compra de roupas. | **Economia cooperativa sem salários internos (`DEC-12`)**; trocas apenas entre comunidades no Cap. 3. | **Aprovada na entrevista `/grill-me`** |

### 12.2 Tabela Rastreável de Decisões Ativas (`D1`–`D9` e `DEC-01`–`DEC-19` — `R2-11`)

| ID | Regra Consolidada | Origem / Rastreabilidade Autoral | Estado Técnico / Normativo | Seção |
|---|---|---|---|---|
| **D1–D9** | Persistência T3, transporte físico (D2), reembolso `0,50` (D3), custos provisórios (D4), depósitos T3 (D5), exclusão `CampStorageZone` (D6), UI Construir (D7), itens no mundo (D8), equipe 1–4 trab. (D9) e Alternativa B | **Escolhas expressas do Proprietário** (14/11/2026 em `T3_architecture_PROPOSAL.md`) | `DECIDIDO` (`T3.1–T3.3` `IMPLEMENTADO` / `VALIDADO`; restante `PLANEJADO`) | §4 |
| **v1.0 §5** | Capacidade individual de carga (`0%`–`100%`) evolutiva por características/profissão/equipamentos/melhorias; aparência coerente de fontes durante extração (árvores não permanecem verticais após fornecer troncos; frutos colhidos sem destruir arbusto) | **Escolhas expressas preservadas da `v1.0`** (recuperadas na `R4-J`) | `DECIDIDO` (`T2` `IMPLEMENTADO` em parte; evolução de capacidade e remoção final `DEC-09` = `PLANEJADO`) | §4.1, §7.2 |
| **v1.1 §7.1–7.7, §8** | Criação personalizável, seleção livre de cores/pele natural, 6 traços herdáveis, afinidade autônoma persistente (não aleatória por dia), nomes externos persistentes, renomeação opcional sem mudar ID/sem reversão automática, ferramentas e armas atribuídas automaticamente por profissão a partir do arsenal compartilhado com opção simples de atribuição manual | **Escolhas expressas do Proprietário** (`v1.1` de 14/11/2026 recuperadas em `R2-C` e `R4-J`) | `DECIDIDO` (`PLANEJADO T5/T6`; implementação `NameService`/shaders = `PROPOSTA`) | §3, §4.4, §8 |
| **DEC-01** | Calendário `1 ano ≈ 12–15 min` em `1×` (`2,4–3h` após o nascimento até 12 anos); velocidades `1×/2×/4×` | **Aprovada na entrevista com Argon** (P1) + **refinamento cronológico R1-G / R2-D** | `DECIDIDO` (`PLANEJADO T4`; balanceamento fino = `ABERTO`) | §3.3 |
| **DEC-02** | Bloqueio até primos de 1º grau; casamentos no Cap. 3 somente entre **Adultos (`18+`)** incluindo jovens adultos de comunidades vizinhas | **Aprovada na entrevista com Argon** (P2) + **correção normativa R2-B** | `DECIDIDO` (`PLANEJADO T5/T8`) | §2.2, §3.4 |
| **DEC-03** | Abrigo Básico inicia família; nascimento autônomo exige vaga + estabilidade alimentar + intervalo progressivo | **Aprovada na entrevista com Argon** (P3) | `DECIDIDO` (`PLANEJADO T5`; valores numéricos = `ABERTO`) | §3.4 |
| **DEC-04** | Atuação RTS por idade (`Bebê`/`Criança`/`Jovem`/`Adulto`) e regra de viuvez/acolhimento | **Aprovada na entrevista com Argon** (P4) | `DECIDIDO` (`PLANEJADO T5`) | §3.3, §3.4 |
| **DEC-05** | Cosmologia de bastidores (Ser de Luz / Ser de Trevas sem nome) + animais normais e corrompidos irradiando trevas | **Escolha expressa do Proprietário** (resposta autoral na P5) + **enquadramento de bastidores pelo ChatGPT** | `DECIDIDO` (`PLANEJADO T6/T7`; mistérios = `ABERTO`) | §2.1, §8 |
| **DEC-06** | Única aparição pessoal do Ser de Trevas após o abrigo no Cap. 1 (sem Ser de Luz); **Dons Latentes** despertados por aprendizado/mentoria; **Alento** inicial dos líderes; separação Profissão × Vocação × Dom | **Escolha expressa do Proprietário + direção de design delegada ao ChatGPT** | `DECIDIDO` (`PLANEJADO T5–T7`) | §2.2, §5 |
| **DEC-07** | Grupo humano seduzido pela Sombra (Cap. 3) + proteção especial de derrota dos Líderes distinta do *Alento* | **Escolha expressa do Proprietário** (P7) + **distinção pelo ChatGPT** | `DECIDIDO` (`PLANEJADO T6/T8`) | §2.2, §5.3, §8 |
| **DEC-08** | Modelo Híbrido RTS + Autonomia por Profissão (`JobSystem`) e busca automática de fonte adjacente | **Aprovada na entrevista com Argon** (P8) | `DECIDIDO` (`PLANEJADO T4/T5`) | §1.2, §5.1 |
| **DEC-09** | Árvores/pedras em `0` somem 100% (`queue_free()`); brotação em solo livre; caminhos bloqueiam vegetação | **Diretriz expressa do Proprietário** (P9) + **Aprovada na entrevista com Argon** | `DECIDIDO` (`PLANEJADO T4` — código atual T3.3 ainda usa `DepletedVisual`) | §7.2 |
| **DEC-10** | Arbustos regeneram frutas mas podem ser arrancados ao construir; Roças agrícolas contínuas | **Aprovada na entrevista com Argon** (P11) | `DECIDIDO` (`PLANEJADO T4/T5`) | §7.2 |
| **DEC-11A** | Pedra bruta exposta não sofre deterioração temporal (`can_decay = false`) | **Ratificação expressa posterior do Proprietário** (16/11/2026) | `DECIDIDO (RATIFICADO)` (`IMPLEMENTADO` em `.tres`) | §4.2 |
| **DEC-11B** | Complementação de reserva deteriorada exige autorização manual no canteiro + saldo livre + transporte físico | **Ratificação expressa posterior do Proprietário** (16/11/2026) | `DECIDIDO (RATIFICADO)` (`PLANEJADO T3.4-R2 / T3.5`) | §4.2 |
| **DEC-12** | Economia cooperativa sem salários internos; trocas entre vilas no Cap. 3 | **Aprovada na entrevista com Argon** (P12) | `DECIDIDO` (`PLANEJADO`) | §4.4 |
| **DEC-13** | Níveis 1–5 por marcos concretos de desenvolvimento (sem aparição/bênção do Ser de Luz e sem exigir 5 níveis no Cap. 1) | **Aprovada na entrevista com Argon** (P13) + **reconciliação pelo ChatGPT** | `DECIDIDO` (`PLANEJADO`) | §6 |
| **DEC-14** | Regiões `256–384 m` conectadas + simulação leve em 2º plano (preservando biomas completos `v1.0` §9) | **Aprovada na entrevista com Argon** (P14) + **revisão R2-E** | `DECIDIDO` (`PLANEJADO T4/T8`; FPS a medir = `ABERTO`) | §7.1, §7.2 |
| **DEC-15** | Formação RTS automática + apoio autônomo + comandos especiais dos Líderes (aplicável à evolução posterior) | **Diretriz do Proprietário** (P15) + **contenção de escopo pelo ChatGPT** | `DECIDIDO` (`PLANEJADO T6+`) | §8 |
| **DEC-16** | Nome + Sobrenome da Linhagem; personagens modulares com **esqueleto único por faixa etária** (`DECIDIDO`), mantendo orçamento `~1.5k–3.5k` triângulos e shaders/sockets como `PROPOSTA` | **Aprovada na entrevista com Argon** (P16) | `DECIDIDO` (esqueleto/linhagem) / `PROPOSTA` (orçamento/shaders) (`PLANEJADO T5`) | §3.1, §3.2, §9.2 |
| **DEC-17** | `SaveManager` extensível desde T3.8 + unificação em GDD único (`docs/Dawn_of_Kin_GDD.md`) | **Aprovada na entrevista com Argon** (P17) + **decisão do Proprietário de GDD único** | `DECIDIDO` (`PLANEJADO T3.8`) | §11 |
| **DEC-18** | T3.4: montagem parcial (2–3 trab.) e solitário transporta reservados acessíveis antes de montar | **Escolha expressa do Proprietário pré-entrevista** (preparação T3.4) | `DECIDIDO` *(impl. bloqueada até `T3.4-R2`)* | §4.3 |
| **DEC-19** | T3.4: diretriz N1 de inclusão regional de `buildings_root` no `WorldNavigation` | **Seleção preliminar do Proprietário para planejamento T3.4** | `DECIDIDO (planejamento)` *(sujeita a `T3.4-R2`)* | §4.3, §11 |
| **Estratégia 4 Horizontes** | Separação Visão Completa (A), Demo (B), 1º Lançamento Cap. 1 (C) e Conteúdo Posterior (D) + matriz `T1–T8` | **Diretriz de viabilidade estruturada pelo ChatGPT** sob delegação do Proprietário | `DECIDIDO` | §10 |

### 12.3 Pendências Abertas (`ABERTO` e `PENDENTE DE APROVAÇÃO`)
- **`PENDENTE DE APROVAÇÃO` (`T3.4-ARCHITECTURE-R2`):** As 6 especificações técnicas da §11 antes de autorizar qualquer código da T3.4.
- **`ABERTO` (Marca e Narrativa):** Registro comercial de *Dawn of Kin*, cosmologia última dessa versão da Terra, momento/forma de eventual revelação futura do Ser de Luz, fala definitiva do Ser de Trevas no Cap. 1 e regras de diplomacia/troca do Cap. 3.
- **`ABERTO` (Balanceamento e Performance):** Recalibração empírica do calendário, taxas numéricas de consumo alimentar por habitante e consequências graduais da escassez alimentar, custo/recarga do *Alento*, ritmo de brotação/regeneração, vagas de dependentes, curva de natalidade, números de combate e medições reais na **Intel UHD Graphics 620** para regiões `256–384 m` e modelos modulares.
