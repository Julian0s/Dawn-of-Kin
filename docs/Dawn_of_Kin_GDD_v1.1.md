# DAWN OF KIN

**Documento mestre de design (GDD) — versão 1.1 (MINUTA AGUARDANDO APROVAÇÃO)**  
**Data:** 14 de novembro de 2026  
**Base documental:** [Dawn_of_Kin_GDD_v1.0.md](Dawn_of_Kin_GDD_v1.0.md) + Adendo de Design aprovado conceitualmente em 14/11/2026 (Personagens Modulares, Herança Visual, Vestuário e Identidade)<br>
**Uso:** minuta de referência de produto para revisão do proprietário antes de substituir a v1.0 em `AGENTS.md`  
**Nome de trabalho:** *Dawn of Kin* («Aurora da Linhagem»); verificar disponibilidade de marca e lojas antes da publicação.

> **Aviso de vigência:** Esta versão `v1.1` é uma **minuta documental não promovida aguardando aprovação formal do proprietário**. O documento [Dawn_of_Kin_GDD_v1.0.md](Dawn_of_Kin_GDD_v1.0.md) é a fonte normativa vigente e recebeu as atualizações e decisões aprovadas pelo proprietário. A fase **T2** encontra-se oficialmente concluída e aprovada; na fase **T3**, a etapa **T3.1 — Contabilidade, Reservas e Saque em Lote** foi **IMPLEMENTADA, AUDITADA E APROVADA PELO PROPRIETÁRIO EM 15/11/2026** (integrada na `main`), e a etapa **T3.2 — Validação Espacial, Área Reservada e Prévia sem Grid** foi **IMPLEMENTADA, AUDITADA TECNICAMENTE, TESTADA MANUALMENTE (11/11 ITENS) E FORMALMENTE APROVADA PELO PROPRIETÁRIO EM 15/11/2026** (branch `feature/t3-2-placement`, commit `f2110b6`), permanecendo as etapas posteriores (**T3.3+**) planejadas e estritamente sem autorização de implementação.
>
> **Regra de leitura:** **DECIDIDO** = aprovado pelo proprietário; **PROPOSTA** / **PROPOSTA TÉCNICA** / **PROPOSTA FUTURA** = sugestão técnica ou de design para avaliação, não compromisso fechado; **ABERTO** = depende de definição futura e não deve ser presumido na implementação.
>
> **Estado real observado do projeto em 15/11/2026:**
> - **T1 — Fundação RTS:** **concluída e aprovada** (`t1-complete`, commit `2808799`, 90 testes automatizados e 1.607 asserções).
> - **T2 — Trabalho e Recursos (`T2.0`–`T2.6` + `B1`):** **concluída e aprovada** pelo proprietário em 14/11/2026 (`t2-complete`, commit `f7c2459`, 182/182 testes em 27 suítes e 21/21 itens manuais aprovados), com limitação de desempenho em bateria DC aceita como não bloqueante para a T2.
> - **T3 — Construção:** Arquitetura consolidada (`docs/architecture/T3_architecture_PROPOSAL.md`); etapa **T3.1** concluída e integrada na `main`; etapa **T3.2** concluída, testada manualmente e formalmente aprovada pelo proprietário em 15/11/2026; etapas `T3.3` em diante continuam estritamente bloqueadas sem autorização de implementação.

---

## 1. Visão do jogo

**Pitch:** Um casal foge das explosões da Terceira Guerra Mundial, atravessa um fenômeno espacial e desperta sem pertences em uma Terra selvagem, sem civilização preexistente. Com comandos simples de estratégia em tempo real, o jogador transforma a sobrevivência de duas pessoas no começo de uma comunidade familiar. Um mistério sombrio contrasta com a beleza relaxante da natureza.

- **DECIDIDO — Gênero:** sobrevivência simplificada + construção de assentamento + RTS leve + evolução familiar; single-player inicialmente.
- **DECIDIDO — Perspectiva:** câmera 3D isométrica, interação prioritariamente pelo mouse.
- **DECIDIDO — Ritmo:** contemplativo, intuitivo, agradável de observar; perigo episódico, não combate constante.
- **DECIDIDO — Diferencial:** partir de um casal identificável, acompanhar filhos, casamentos, casas e profissões, depois descobrir outras comunidades.
- **Referências funcionais:** Age of Empires (seleção e ordens); Durango: Wild Lands (natureza e sobrevivência); Ragnarok/Albion (regiões conectadas). Referências são inspiração, não ativos a reproduzir.

---

## 2. Premissa narrativa e regras do mundo

- **DECIDIDO — Prólogo:** o casal dirige em meio ao colapso da Terceira Guerra Mundial, com bombardeios e explosões nucleares. Quando parece não haver saída, um buraco de minhoca os transporta.
- **DECIDIDO — Travessia e roupa inicial:** não levam carro, inventário ou ferramentas. A passagem só transporta seres vivos. Os protagonistas iniciam com **representação visual fixa de roupas rasgadas** (convenção visual de apresentação e classificação etária), que **não constituem itens equipáveis nem objetos transportados pelo fenômeno espacial** e podem ser substituídas futuramente por roupas produzidas pela comunidade.
- **DECIDIDO — Destino:** uma versão da Terra, com biomas e animais semelhantes aos do nosso planeta, sem cidades, estradas, ruínas de civilização ou habitantes humanos originários daquele mundo.
- **DECIDIDO — Outros sobreviventes:** todos também vieram do mundo em colapso. Alguns atravessaram juntos, outros em momentos diferentes; surgiram em regiões distintas e começaram pequenos assentamentos. Isso é desconhecido para o casal no início.
- **DECIDIDO — Escopo de seres inteligentes:** não introduzir povos não humanos para justificar o crescimento populacional.
- **ABERTO — Cosmologia:** a natureza exata daquela Terra, as regras físicas do fenômeno e o motivo da travessia são mistérios narrativos; não fixar agora explicações de viagem no tempo ou universos paralelos.
- **ABERTO — Ameaça sombria:** existe algo anormal de que os habitantes precisam se proteger; sua origem, forma, frequência e relação com a passagem ainda não foram definidas.

---

## 3. Progressão narrativa por capítulos

### Capítulo 1 — O isolamento

- **DECIDIDO:** só o casal original e, mais tarde, seus próprios filhos; nenhuma aparição ou recrutamento de outros humanos.
- O jogador aprende ordens RTS, coleta, proteção, construção, agricultura e gestão de alimentos.
- O casal estabelece uma propriedade, tem filhos e acompanha a passagem de bebê para criança e jovem.
- O mundo é belo, vasto e aparentemente vazio; indícios discretos do mistério podem surgir sem tirar o foco da vida familiar.
- **Portão narrativo:** encontros com outros humanos ficam proibidos até que pelo menos um filho chegue à fase jovem.

### Capítulo 2 — Não estamos sozinhos

- **DECIDIDO:** após a condição acima, só **um ou dois encontros humanos significativos inicialmente**; nada de fluxo constante de colonos.
- Visitantes ou grupos encontrados vieram da mesma guerra e construíram assentamentos distantes, possivelmente com outra cronologia de chegada.
- A descoberta deve parecer extraordinária, não um botão de recrutamento de aldeões.

### Capítulo 3 — Laços entre comunidades

- **DIREÇÃO APROVADA:** contato, cooperação e eventual formação de novas famílias entre descendentes de comunidades distintas.
- **ABERTO:** regras exatas de comércio, circulação de pessoas, diplomacia e limites da evolução da civilização.

---

## 4. Loop central e controles RTS

**Ciclo desejado:** observar a comunidade → selecionar um ou mais moradores → dar tarefas → coletar e transportar recursos até um local de armazenamento válido (na **T2 implementada**, descarga nas pilhas físicas do acampamento inicial; pela **regra futura aprovada**, materiais poderão existir no chão de qualquer região, mas só integram o estoque coletivo quando entregues a armazenamento válido) → proteger e evoluir o armazenamento conforme a comunidade cresce → sustentar famílias → explorar e lidar com ameaças ocasionais.

- **DECIDIDO:** clique esquerdo seleciona personagem; clique direito dá ordem contextual (mover no chão, colher, cortar, coletar, entregar carga, construir, interagir). Na T2, o clique direito em terreno livre permanece estritamente como movimento RTS.
- **DECIDIDO:** tarefas são executadas automaticamente; o jogador não precisa controlar fisicamente cada golpe, deslocamento ou retorno de descarga.
- **PROPOSTA:** arrastar caixa para seleção múltipla; Shift para enfileirar ordens; ícones discretos de estado e barra/porcentagem de carga; câmera com zoom, arraste e limites do mapa.
- **PROPOSTA:** estados da unidade: ocioso, deslocando, trabalhando, transportando, defendendo, incapacitado (com `ocioso`, `deslocando`, `trabalhando` e `transportando` diretamente associados ao ciclo físico de coleta e entrega no acampamento).
- **Regra de UX:** preferir uma única ação contextual clara a painéis cheios de microcomandos.

---

## 5. Sobrevivência, economia simplificada e vestuário

### Núcleo econômico e de coleta

- **DECIDIDO:** não há barras individuais de fome ou sede.
- **DECIDIDO — Início sem infraestrutura prévia:** o casal protagonista começa sem ferramentas, sem equipamentos equipáveis e sem construções humanas pré-existentes no mapa.
- **DECIDIDO:** o assentamento mantém um **estoque coletivo de pontos de alimentos** e demais recursos compartilhados utilizáveis pela comunidade. Cada pessoa tem um consumo periódico; todos são sustentados por esse estoque.
- **DECIDIDO:** não é necessário cozinhar receitas complexas ou fabricar alimento ingrediente por ingrediente.
- **DECIDIDO — Transporte físico e proibição de crédito instantâneo:** os materiais coletados (madeira, pedra, alimentos e futuras categorias) **não** aparecem instantaneamente no estoque compartilhado durante a coleta. Cada trabalhador carrega fisicamente os materiais coletados e o estoque coletivo só é atualizado após descarga física em armazenamento válido (**T2 implementada:** descarga no acampamento inicial; **regra futura aprovada:** materiais poderão permanecer no chão de qualquer região, mas só integrarão o estoque coletivo quando entregues a um local de armazenamento válido).
- **DECIDIDO — Escopo inicial T2 e expansão futura de materiais no mundo:** na T2, os materiais descarregados formam **pilhas físicas individuais** de madeira, pedra ou alimentos exclusivamente **dentro do acampamento inicial** (primeiro local de armazenamento em zona lógica inicial sem construções pré-prontas; placeholders simples permitidos inicialmente e modelos 3D finais posteriormente). Cada pilha mantém quantidade própria, localização e estado de exposição, podendo pilhas da mesma categoria ser agrupadas conforme regra técnica determinística.
  - **DECIDIDO — Materiais largados e múltiplos locais de armazenamento:** a restrição da T2 ao acampamento inicial não é permanente. Qualquer item ou material poderá futuramente ser deixado fisicamente no chão de qualquer região; contudo, materiais largados fora de um local de armazenamento válido **não** entram automaticamente no estoque coletivo — para integrá-lo, devem ser transportados fisicamente até um local de armazenamento válido.
- **DECIDIDO — Sincronia entre pilhas válidas e estoque:** todas as pilhas válidas de armazenamento contribuem para o estoque coletivo utilizável, que reflete exatamente as quantidades livres/disponíveis nessas pilhas (sem contagem duplicada).
- **DECIDIDO — Exposição, deterioração por categoria e política sobre reservas:** materiais mantidos expostos no chão — incluindo madeira, pedra, alimentos e futuros recursos como ferro e aço — sofrem desgaste ao longo do tempo conforme regras configuráveis por categoria e podem desaparecer se permanecerem expostos por tempo prolongado, reduzindo corretamente os recursos disponíveis no estoque. Reservas de obra **não** protegem materiais expostos: quando o desgaste físico reduz uma pilha abaixo do reservado, as reservas afetadas sofrem redução direta até o saldo físico restante (Alternativa B — Perda Direta), sem reancoragem automática para outras pilhas. Armazéns construíveis pertencem à **T3+** e deverão proteger os materiais.
- **DECIDIDO — Peso, capacidade individual e porcentagem de carga:** cada tipo de material possui peso unitário específico e cada habitante (incluindo o casal protagonista) possui capacidade individual de carga. A capacidade ocupada deve ser representada em porcentagem (`0%` a `100%`) com base no peso total transportado, permitindo futura evolução da capacidade por características, profissão, equipamentos ou melhorias.
- **DECIDIDO — Retorno automático ao acampamento:** quando a carga do trabalhador atingir `100%`, ou não houver espaço livre suficiente para comportar mais uma unidade coletável do material, ele interrompe o ciclo na fonte e retorna automaticamente ao acampamento para descarregar.
- **DECIDIDO — Armazenamento por categoria e evolução progressiva:** o armazenamento contempla madeira, pedra, alimentos e futuras categorias, partindo de pilhas individuais no chão do acampamento inicial (sem construções pré-existentes) até armazéns e depósitos construíveis em marcos posteriores (`T3+`).
- **Fontes iniciais previstas:** coleta de frutos, pesca, caça, plantações e, posteriormente, criação de animais.
- **Recursos de trabalho iniciais previstos:** madeira, pedra e alimentos; minério é uma expansão posterior.
- **DECIDIDO:** a aparência das fontes deve refletir coerentemente a extração.
- **DECIDIDO:** a árvore não permanece vertical após fornecer troncos; frutos podem ser coletados sem destruir a planta.
- **PROPOSTA:** implementação provisória de árvores pequenas/frágeis e animação de derrubada sem ferramentas.
- **ABERTO:** ferramentas para árvores maduras, regeneração de frutos e regras futuras de sustentabilidade.
- **PROPOSTA:** permitir entrega parcial quando a fonte se esgota antes de `100%` e suportar múltiplas categorias na mochila em caso de redirecionamento de ordem.
- **PROPOSTA:** interface mostrar porcentagem de carga individual do morador selecionado (diferenciando peso transportado de quantidades unitárias), estoque utilizável por categoria (sincronizado com as pilhas do acampamento), indicação/alerta de pilhas expostas à deterioração, saldo alimentar por dia e autonomia estimada; consequências graduais se faltar alimento (redução de produtividade e risco para moradores comuns).
- **ABERTO:** duração exata da exposição, perda gradual versus desaparecimento integral, política de exposição ao adicionar materiais novos a uma pilha antiga, diferenças de deterioração por categoria, valores numéricos exatos de peso unitário, capacidade individual inicial, taxa de coleta, consumo e eventuais tetos por pilha ou depósito, a calibrar por testes.

### Vestuário comunitário — DECIDIDO EM CONCEITO

- **DECIDIDO — Produção e distribuição inicial:** roupas serão produzidas utilizando recursos da comunidade e, na primeira implementação, poderão ser distribuídas automaticamente de forma simples, com variações visuais, substituindo a representação inicial de roupas rasgadas.
- **ABERTO:** efeitos funcionais de vestuário (clima, proteção, conforto), qualidade, durabilidade e custos exatos de produção.

### Economia pessoal e compra de roupas — PROPOSTA FUTURA

- **PROPOSTA FUTURA:** em uma fase posterior, famílias ou moradores adultos poderão receber remuneração e comprar produtos produzidos pela comunidade, incluindo vestuário.
- **Regra de integridade:** qualquer economia pessoal futura deverá preservar a autoridade única do estoque coletivo existente, sem criar recursos duplicados nem introduzir uma economia paralela na T2.
- **ABERTO (não decidir antecipadamente):**
  - Remuneração individual ou familiar.
  - Origem da moeda e regras de emissão/circulação.
  - Frequência dos pagamentos.
  - Formação de preços e transações.
  - Critérios de compra automática.
  - Distinção entre roupas essenciais gratuitas e vestuário opcional comprado.
  - Marco de implementação (sem marco aprovado no roadmap).

---

## 6. Construção, profissões e nível da comunidade

- **DECIDIDO:** o início no campo ocorre sem construções humanas pré-existentes; casas e edifícios são vistos e administrados pelo exterior, sem interiores jogáveis.
- **DECIDIDO:** o jogador posiciona obras, reserva e transporta fisicamente os recursos compartilhados disponíveis até o canteiro (sem pilha obrigatória ao lado de cada obra) e designa trabalhadores para concluí-las. Construções poderão existir em diferentes locais e regiões, desde que o posicionamento seja válido (com a zona inicial das pilhas protegida durante a T3).
- **DECIDIDO — Organização dos trabalhadores na construção:** 1 trabalhador busca materiais e constrói; com 2 trabalhadores, 1 pode transportar enquanto o outro constrói; com 3 trabalhadores, 1 pode transportar enquanto 2 constroem (mantendo o limite provisório de até 2 construtores atuando simultaneamente na montagem do abrigo básico e do depósito rústico).
- **DECIDIDO:** cada casal casado deve ter uma casinha/residência própria.
- **DECIDIDO:** o jogador direciona a força de trabalho e decide quem atua como agricultor, pescador, lenhador, construtor, ferreiro, guarda etc.
- **DECIDIDO:** a expansão de prédios e profissões será associada ao **nível de desenvolvimento da comunidade**, ainda sem fórmula definida.
- **DECIDIDO — Evolução do armazenamento:** o armazenamento por categoria (madeira, pedra, alimentos e futuras categorias) evolui progressivamente de pilhas individuais expostas no chão do acampamento (`T2`) até depósitos rústicos e armazéns protetores construíveis pelo jogador (`T3+`) que reduzem ou eliminam a perda por exposição.
- **ABERTO:** teto tecnológico; intenção atual é manter uma identidade rústica, com aparência melhorada progressivamente, e não avançar obrigatoriamente à indústria moderna.

**Escada de progressão — PROPOSTA, não fechada:**

| Nível | Marco visual | Possíveis desbloqueios |
|---|---|---|
| 1 | Acampamento | Pilhas individuais no acampamento, abrigo básico, coleta, fogueira |
| 2 | Propriedade | Primeira casa, roça, primeiro armazém/depósito coberto (T3+) |
| 3 | Povoado | Carpintaria, criação de animais |
| 4 | Aldeia | Ferraria, arsenal, estruturas de defesa |
| 5 | Vila | Oficinas, comércio local, melhorias estéticas |

**Orientação de design:** o nível libera ferramentas para crescer; não é um teto arbitrário de população.

---

## 7. Personagens modulares, aparência, identidade e família

### 7.1. Criação do casal inicial — DECIDIDO

- Os dois protagonistas iniciais serão escolhidos a partir de modelos-base personalizáveis.
- O jogador poderá personalizar:
  - Formato do rosto e detalhes faciais (olhos, nariz e mandíbula).
  - Modelo, textura e cor do cabelo.
  - Cor dos olhos.
  - Tom de pele dentro de uma ampla faixa de tonalidades naturais.
- O criador deverá oferecer um botão **Randomizar**, capaz de gerar combinações válidas de aparência.

### 7.2. Sistema de personagens modulares — DECIDIDO

- Personagens serão construídos por componentes 3D intercambiáveis:
  - **Cabeça**
  - **Cabelo**
  - **Corpo**
  - **Vestuário**
- A produção de variantes 3D dos componentes poderá utilizar **Tripo AI**, desde que cada peça seja adaptada a um padrão técnico compatível com Godot.
- **Regra de cautela:** **não assumir compatibilidade automática entre modelos produzidos separadamente** (malhas geradas em separado exigem padronização de escala, pivô, peso de ossos e encaixes).
- **PROPOSTA TÉCNICA:** padronizar esqueletos compatíveis, encaixes (*sockets*/pontos de ancoragem), materiais recoloríveis e parâmetros faciais moderados, além de adotar medidas explícitas de otimização para a GPU-alvo **Intel UHD 620** (orçamento de polígonos, redução de *draw calls*, materiais compartilhados e LODs/simplificação distante).

### 7.3. Sistema de cores — DECIDIDO

- Cabelo, olhos e roupas terão seleção livre de cores.
- A pele utilizará uma paleta ampla de tonalidades naturais.
- As cores escolhidas na criação do casal inicial são consideradas naturais e hereditárias, inclusive quando forem cores incomuns.
- **PROPOSTA TÉCNICA:** utilizar materiais ou shaders parametrizados por instância/superfície para recolorização, evitando duplicação desnecessária de modelos e texturas.

### 7.4. Herança visual e crescimento consistente — DECIDIDO

- Cada filho terá sua aparência determinada por uma combinação probabilística das características dos pais, com pequenas variações (aproximação visual de hereditariedade, não simulação genética científica).
- Traços herdáveis obrigatórios:
  - Formato do rosto e proporções faciais.
  - Cor dos olhos.
  - Tom de pele.
  - Cor e textura natural do cabelo.
  - Tendência de altura.
  - Tendência de constituição física.
- Haverá modelos corporais apropriados para as quatro fases de vida já estabelecidas (**Bebê → Criança → Jovem → Adulto**), preservando a identidade visual reconhecível do personagem entre fases e entre carregamentos de partidas salvas.
- **ABERTO:** intensidade das variações hereditárias, eventual influência de gerações anteriores/ancestrais e limites numéricos das características corporais.

### 7.5. Sistema de nomes e identidade persistente — DECIDIDO

- **Personagens externos e novos habitantes:** todo personagem humano fora do núcleo inicial dos protagonistas deverá possuir um **nome próprio persistente**, mesmo antes de integrar o assentamento do jogador. Personagens encontrados em outras comunidades já devem surgir com nomes próprios pré-gerados, **sem identificadores genéricos** (como `Aldeão 1` ou `Morador 15`), e o nome não pode mudar aleatoriamente entre encontros ou carregamentos.
- **Núcleo inicial:** o casal líder original e seus próprios filhos terão regra específica de nomeação vinculada ao jogador.
- **Renomeação opcional:** ao passar a integrar o acampamento ou comunidade do jogador, o personagem poderá ser renomeado manualmente (opcional).
- **Invariância de identidade:** alterar o nome **nunca** pode mudar o identificador interno único (`ID`), a genealogia, os vínculos familiares, relacionamentos, histórico ou residência do personagem.
- **Nomes automáticos para filhos de habitantes comuns:** recebem nome próprio automaticamente no nascimento. O gerador consultará os nomes já utilizados na comunidade e especialmente em cada residência, priorizando diversidade entre famílias e residências e considerando histórico de gerações anteriores.
- **Prevenção de repetições e exceção familiar:**
  - Irmãos não deverão receber automaticamente nomes idênticos.
  - **Exceção permitida:** um filho poderá excepcionalmente receber o nome do pai, ou uma filha o da mãe, como homenagem e continuidade familiar (comportamento excepcional, nunca padrão).
  - Nomes definidos manualmente pelo jogador não deverão ser revertidos pelo sistema automático.
  - Os nomes deverão permanecer consistentes entre sessões e salvamentos.
- **ABERTO (não presumir na implementação):**
  - Como o jogador nomeia os protagonistas e seus próprios filhos (totalmente manual ou com sugestões automáticas).
  - Existência e regras de sobrenomes/nomes familiares.
  - Influência cultural ou regional nas listas de nomes.
  - Regras de homenagem a avós e ancestrais.
  - Possibilidade de nomes iguais em comunidades distintas.
  - Convenções e tratamento de nomes compostos.
- **PROPOSTA TÉCNICA — Arquitetura modular de nomes:** implementar serviço modular (`Identity/NameService`) totalmente **desacoplado de modelos 3D, renderização visual, profissão e equipamentos**, operando com:
  - Identificadores internos únicos independentes do nome exibido.
  - Listas configuráveis de nomes, histórico de nomes atribuídos e consulta por comunidade e residência.
  - Seleção determinística em relação ao estado salvo, priorizando nomes inéditos e buscando novas combinações ou variantes válidas caso uma lista se esgote, em vez de repetir continuamente nomes populares.

### 7.6. Ciclo de vida — DECIDIDO

- Fases: **bebê → criança → jovem → adulto**.
- Ao atingir a fase adulta, os personagens **param de envelhecer**; o jogo não precisa fornecer justificativa narrativa.
- Bebês são dependentes, crianças podem colaborar levemente, jovens passam a contribuir mais, adultos podem executar as atividades apropriadas.
- A progressão das idades ocorre num calendário do jogo, não em tempo real.

### 7.7. Casais e lares — DECIDIDO

- Personagens comuns têm **autonomia para criar afinidades e formar casais**; não são emparelhados diariamente de forma aleatória pelo jogador.
- Vínculo de casal é persistente. Cada união está associada a uma residência da família.
- Filhos pertencem a uma família identificável e podem, depois, constituir seus próprios lares.
- **PROPOSTA TÉCNICA:** guardar IDs estáveis de personagem, pais, cônjuge, família e residência para impedir inconsistências e permitir regras futuras de parentesco.
- **ABERTO:** regras de união quando um cônjuge morre, critérios de afinidade e compatibilidade entre moradores, consentimento ou confirmação por interface.

### 7.8. Nascimentos — PROPOSTA EM TESTE

- Reprodução discreta e autônoma, sem cenas íntimas ou microssimulação de gravidez.
- Sugerir condições de moradia, alimentos e intervalo entre nascimentos; evitar comportamento de “fábrica de humanos”.
- **Não aprovado:** qualquer limite rígido de 1–3 filhos por casal; esse número foi apenas um exemplo de balanceamento.
- **ABERTO:** o que dispara um nascimento, como são as notificações e se existe alguma influência indireta do jogador.

### 7.9. População — DECIDIDO

- **Sem limite artificial predeterminado** de habitantes ou famílias; a administração, a disponibilidade de casas e alimentos e a capacidade técnica determinam o crescimento real.
- Implementação deve permitir atualização simplificada de moradores distantes, porque “sem limite de design” não significa capacidade computacional infinita.

---

## 8. Mortalidade, combate, ferramentas e arsenal

- **DECIDIDO:** os dois protagonistas originais são líderes protegidos. Não morrem por idade nem por ataques. Se derrotados, ocorre **uma cena/evento de recuperação exclusivo para líderes** e uma penalidade temporária ainda a definir.
- **DECIDIDO:** demais habitantes, **inclusive filhos dos protagonistas**, podem morrer por perigos e ataques. Como ninguém envelhece além de adulto, não há morte por velhice.
- **DECIDIDO:** armas previstas: **espada + escudo, lança, arco e flecha**.
- **DECIDIDO — Ferramentas e armas compartilhadas por profissão:** equipamentos (ferramentas e armas) serão atribuídos automaticamente conforme a profissão do habitante, permitindo opção simples de atribuição manual. O sistema utilizará o **arsenal e os recursos compartilhados** da comunidade, **sem gerenciamento obrigatório de inventário individual com múltiplos slots de MMORPG**.
- **DECIDIDO:** profissões e fabricação evoluem com a comunidade; ferreiros podem produzir ferramentas e armas e guardas utilizá-las.
- **ABERTO:** regras de alcance, formação, defesa, animais hostis, recuperação, critérios detalhados de atribuição automática de ferramentas/armas e detalhes dos eventos sombrios.

---

## 9. Mundo, regiões e ecossistema

- **DECIDIDO:** não será um mapa mundial aberto e contínuo. O mundo é dividido em **regiões conectadas por passagens**, em estrutura semelhante a Ragnarok/Albion.
- **DECIDIDO:** floresta, rios, praias/mar, montanhas, campos e fauna terrestre reconhecível, com mapas amplos para explorar e desenvolver.
- **DECIDIDO:** os outros assentamentos podem existir em regiões distantes sem precisar manter toda a geometria e IA carregadas ao mesmo tempo.
- **PROPOSTA:** carregar uma região principal por vez, guardando alterações persistentes, recursos consumidos, casas e populações em dados.
- **ABERTO:** tamanho de cada região, número total de mapas e regras para expedições entre regiões.

---

## 10. Direção artística e atmosfera

**DECIDIDO — Direção visual:** **3D isométrico estilizado vibrante naturalista**, com paisagens ricas, acolhedoras e fáceis de ler em perspectiva alta. Referências visuais: quatro imagens fornecidas durante o planejamento.

- Cores vivas e naturais; vegetação abundante, relva, árvores, arbustos e pedras com boa composição visual.
- Ambiente vivo: **vento movendo árvores e grama**, chuva, variações de tempo, rios e mar com movimento perceptível.
- Iluminação de dia agradável e noites mais misteriosas, mantendo legibilidade de jogo RTS.
- Personagens bem identificáveis mesmo quando pequenos (preservando legibilidade mesmo após personalização e troca de vestuário); casas rústicas bonitas, com evolução visual por estágio da comunidade.
- Evitar realismo pesado, aparência excessivamente blocada, neon/glow exagerado e contornos pretos grossos.
- **ABERTO:** intensidade exata do estilo cartunesco, nível de detalhe das texturas e uso ou não de cel shading suave/outlines discretos.

---

## 11. Calendário — proposta de protótipo

**Ainda não aprovado; serve apenas como hipótese de teste.**

| Etapa | Idade proposta |
|---|---|
| Bebê | 0–2 anos |
| Criança | 3–11 anos |
| Jovem | 12–17 anos |
| Adulto | 18 anos em diante; idade congelada |

- **PROPOSTA:** 1 ano de jogo ≈ 50 minutos na velocidade 1×; controles de velocidade 1×, 2× e 4×.
- Isso daria cerca de 10 horas de tempo 1× até um bebê chegar ao início da juventude; esse número deve ser testado para o Capítulo 1 ter duração substancial sem se tornar espera artificial.
- **ABERTO:** congelar ou não o calendário em eventos, duração de estações, ritmo ideal dos nascimentos e efeito da aceleração no equilíbrio.

---

## 12. Stack, arquitetura e desempenho

| Camada | Ferramenta / abordagem | Status |
|---|---|---|
| Engine | **Godot 4.7.2+** | Escolhida |
| Código | **GDScript** | Recomendado |
| Assistência | **Antigravity** | Escolhido |
| Versionamento | **Git local** | Recomendado |
| Arte 3D | Blender | Previsto / opcional conforme ativos |
| Geração de malhas | Tripo AI (com adaptação ao padrão Godot) | Opcional |
| Movimentação | NavigationAgent3D / navegação Godot + RVO | Validado na T1 |
| Dados | Resources (`.tres`) e IDs estáveis | Recomendado |
| Salvamento | Arquivos locais versionados por esquema | Planejado (T4) |
| Rede | Sem servidor para MVP single-player | Decidido |

**Arquitetura modular recomendada:**

- `World/RegionManager`: entradas e saídas de regiões, estado persistente e carregamento seletivo.
- `Units/SelectionController` e `Orders`: seleção RTS, comandos, fila e execução.
- `Units/CharacterAppearance` *(planejado — T5)*: montagem modular (cabeça, cabelo, corpo, vestuário), esqueleto padrão, encaixes e materiais recoloríveis parametrizados.
- `Identity/NameService` *(planejado — T4/T5)*: IDs persistentes, geração determinística de nomes e regras anti-repetição, desacoplado de modelos 3D, profissão e equipamentos.
- `AI/JobSystem`: ocupações, priorização, navegação, trabalho e comportamento ocioso.
- `Economy/SettlementInventory`: estoque comum, produção, consumo alimentar, vestuário comunitário e arsenal.
- `Buildings/ConstructionSystem`: posicionamento, custos, progresso e melhoria estética.
- `Families/PopulationSystem`: famílias, casamento, vínculo de casa, nascimento, herança visual e progressão de fase.
- `Progression/SettlementLevel`: desbloqueios por desenvolvimento, separados da população.
- `Narrative/ChapterState`: requisitos narrativos (sem aparições humanas antes de jovens) e eventos misteriosos.
- `Save/SaveManager`: serialização estável de IDs, nomes, parâmetros de aparência, construções e migração de saves.

**Desempenho e orçamento visual:** testar em hardware modesto (referência de desenvolvimento: **Intel UHD Graphics 620**, 16 GB RAM, `gl_compatibility`). A adoção de personagens modulares e múltiplas peças exige controle rigoroso de *draw calls*, materiais/shaders compartilhados, LODs, vegetação animada por shaders leves, chuva controlada e simplificação distante. Na T2 pós-correção `B1`, o benchmark em `1920×1080` atendeu ao critério de `p95 ≤ 16,7 ms` em tomada CA (`p95 = 9,757 ms`, `0` quadros `> 100 ms`), enquanto em bateria DC registrou `p95 = 33,038 ms` (`0` quadros `> 100 ms`, critério de `p95` não atendido em bateria). O orçamento geométrico das futuras fases deverá manter margem segura na Intel UHD 620 em tomada CA e respeitar a decisão do proprietário sobre o comportamento em bateria DC.

---

## 13. Roadmap executável para Antigravity

> **Regra de autorização:** as anotações de `T3`–`T8` abaixo consolidam planejamento documental e **não autorizam antecipação dessas etapas** nem o encerramento da `T2` antes do aceite manual final.

| Marco | Escopo | Evidência mínima de conclusão / notas de coordenação |
|---|---|---|
| T1 — Fundação RTS | Câmera, terreno demonstrativo, casal selecionável, clique para mover | **Concluída e aprovada** (`t1-complete`, commit `2808799`) |
| T2 — Trabalho e recursos | Recursos coletáveis com peso, capacidade individual (`0%`–`100%`), transporte físico, pilhas individuais no acampamento com exposição/deterioração configurável, HUD de carga/estoque e sincronia exata | **Candidata a encerramento (`review/t2-closeout-candidate`):** `T2.0`–`T2.6` + correção `B1` (`8f53a3f`) implementadas; 182/182 testes e 6.469 asserções reportadas (execução segmentada); 21/21 testes manuais aprovados pelo proprietário e `B1` confirmada visualmente ("testei esta correto"); benchmark `B1.1` em tomada CA com `p95 = 9,757 ms` e `0` quadros `> 100 ms` (critério atendido); benchmark `B1` em bateria DC com `p95 = 33,038 ms` e `0` quadros `> 100 ms` (critério de `p95` não atendido em bateria); aceite formal do marco (incluindo decisão sobre DC) ainda pendente |
| T3 — Construção | Posicionar obra, descontar recursos, designar construtor, armazéns protetores iniciais | Abrigo/casa completado e persistido; redução de exposição quando aplicável |
| T4 — Mundo e calendário | Ciclo dia/noite, tempo, região inicial, salvar/carregar; **preparar persistência de identidade, nomes e parâmetros de aparência** | Estado, construções, IDs estáveis, nomes e parâmetros visuais persistem após reiniciar |
| T5 — Família | Entidades familiares, fases (`Bebê → Criança → Jovem → Adulto`), residência, nascimentos em modo teste; **implementação proposta do criador inicial do casal, personagens modulares, herança visual, crescimento e nomeação automática (sujeita a planejamento próprio antes da implementação)** | Vínculos, aparência hereditária consistente, nomes persistentes e progressão sobrevivem ao save/load |
| T6 — Combate e arsenal | Armas coletivas, ameaças simples, derrota/recuperação; **integração futura com armas, arsenal compartilhado, ferramentas e profissões (inclusive atribuição simples por profissão/manual)** | Líder recupera; NPC comum segue regra de mortalidade; equipamentos usam arsenal compartilhado sem slots de MMORPG |
| T7 — História e atmosfera | Eventos do capítulo 1, vento, chuva, água, mistério discreto | Capítulo 1 não apresenta nenhum humano externo |
| T8 — Primeiro contato | Regras de capítulo 2, 1–2 encontros, comunidades simuladas (com nomes próprios pré-gerados e persistentes) | Encontros só são possíveis após filho jovem |
| **Economia salarial / pessoal (futura)** | Remuneração de moradores/famílias e compra de roupas/produtos comunitários | **Marco ABERTO** (`PROPOSTA FUTURA`; não iniciar nem alocar sem aprovação própria) |

**Prioridade absoluta:** concluir formalmente o aceite da **T2** (incluindo decisão do proprietário sobre o comportamento em bateria DC) e entregar **T3** antes de implementar nascimento, diplomacia ou mundo grande.

---

## 14. Critérios de aceite do primeiro protótipo (T1–T4)

1. Jogador consegue selecionar um ou ambos protagonistas e dar ordens pelo mouse.
2. Personagens encontram caminho, executam trabalho de coleta acumulando carga física individual e entregam os recursos em pilhas físicas no acampamento (sem construções prévias) sincronizadas ao estoque coletivo.
3. Existe estoque coletivo com alimentos e outro recurso de construção.
4. Jogador posiciona e conclui um abrigo sem entrar em interior.
5. Interface é legível em câmera isométrica e não exige microgestão de fome individual.
6. Testes básicos cobrem seleção, ordem, estoque, construção, save e carregamento.
7. Nenhuma mecânica de população, economia salarial ou mistério é adicionada prematuramente apenas para “parecer completo”.

---

## 15. Riscos e pendências reais

- **Validação da T2:** os 21 itens do protocolo manual [T2_manual_test_protocol.md](testing/T2_manual_test_protocol.md) foram executados e relatados como aprovados pelo proprietário em 14/11/2026, com o ajuste B1 testado e confirmado ("testei esta correto"). O benchmark em tomada CA (B1.1) registrou `p95 = 9,757 ms` e `0` quadros `> 100 ms` (critério atendido), enquanto em bateria DC (B1) registrou `p95 = 33,038 ms` e `0` quadros `> 100 ms` (critério de `p95` não atendido em bateria). Os resultados sustentam associação entre alimentação e desempenho sem telemetria síncrona suficiente para comprovar o mecanismo físico específico; a classificação do desempenho em DC como limitação aceitável para encerrar a T2 e a autorização de aceite formal do marco permanecem pendentes de decisão expressa do proprietário.
- **ABERTO (marca):** nome comercial *Dawn of Kin* exige pesquisa de disponibilidade e marca antes de lançamento.
- **ABERTO (família):** taxa de envelhecimento e nascimento, lógica de afinidade, casamentos autônomos e viuvez, e integração de parceiros vindos de outras comunidades.
- **ABERTO (herança visual e corpos):** intensidade das variações hereditárias, eventual influência de avós/gerações anteriores e limites numéricos de altura e constituição física.
- **ABERTO (vestuário):** efeitos funcionais, qualidade, durabilidade, proteção climática e receitas de produção de roupas.
- **ABERTO (nomes):** regra de nomeação do casal protagonista e de seus próprios filhos (manual vs sugestões), uso de sobrenomes, regras culturais/regionais, homenagem a avós/ancestrais, nomes iguais entre comunidades e nomes compostos.
- **ABERTO (economia pessoal — `PROPOSTA FUTURA`):** salário individual vs familiar, moeda e emissão, frequência de pagamento, preços e transações, compras automáticas, roupas básicas gratuitas vs compradas e marco de implementação.
- **ABERTO (combate, ameaça sombria e progresso):** forma e regras da ameaça sombria, ritmo de combate/fome, progressão exata de níveis, tech tree e teto tecnológico.
- **ABERTO (arte e orçamento técnico):** compatibilidade efetiva de peças geradas via Tripo AI após padronização, polígonos, shaders recoloríveis em `gl_compatibility`, limite de unidades modulares simultaneamente animadas e impacto na Intel UHD 620.

---

## 16. Instrução de handoff e governança da minuta v1.1

**Situação documental:** esta **v1.1** consolida o GDD v1.0 com o adendo de 14/11/2026 sobre personagens modulares, personalização, herança visual, nomes persistentes, vestuário e equipamentos, mantendo-se como **minuta aguardando aprovação** consolidada na branch `review/t2-closeout-candidate`.

**Regras de execução:**

1. Enquanto a v1.1 não for formalmente aceita pelo proprietário, [AGENTS.md](../AGENTS.md) permanece apontando para [Dawn_of_Kin_GDD_v1.0.md](Dawn_of_Kin_GDD_v1.0.md), e nenhuma implementação de `T3.3`–`T8` está autorizada (T3.1 integrada na `main` e T3.2 aprovada pelo proprietário em 15/11/2026).
2. Trabalhar em passos pequenos, testáveis e reversíveis; não modificar código nem antecipar sistemas descritos nesta minuta.
3. Separar rigorosamente marcadores **DECIDIDO**, **PROPOSTA** e **ABERTO**, preservando todas as questões abertas sem suposições silenciosas na futura fase de planejamento técnico de `T4`, `T5` e `T6`.
4. Toda afirmação sobre testes, benchmarks e aprovações deve distinguir explicitamente: implementado, testado automaticamente (processo único vs segmentado), medido em benchmark e aprovado manualmente pelo proprietário.
