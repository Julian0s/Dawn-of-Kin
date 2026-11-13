# DAWN OF KIN

**Documento mestre de design (GDD) — versão 1.0**  
**Data:** 12 de novembro de 2026  
**Uso:** referência de produto e handoff de desenvolvimento para Antigravity + Godot  
**Nome de trabalho:** *Dawn of Kin* («Aurora da Linhagem»); verificar disponibilidade de marca e lojas antes da publicação.

> **Regra de leitura:** **DECIDIDO** = aprovado na conversa; **PROPOSTA** = sugestão para testar, não compromisso; **ABERTO** = depende de definição futura. Nenhum sistema foi implementado neste projeto até o momento.

## 1. Visão do jogo

**Pitch:** Um casal foge das explosões da Terceira Guerra Mundial, atravessa um fenômeno espacial e desperta sem pertences em uma Terra selvagem, sem civilização preexistente. Com comandos simples de estratégia em tempo real, o jogador transforma a sobrevivência de duas pessoas no começo de uma comunidade familiar. Um mistério sombrio contrasta com a beleza relaxante da natureza.

- **DECIDIDO — Gênero:** sobrevivência simplificada + construção de assentamento + RTS leve + evolução familiar; single-player inicialmente.
- **DECIDIDO — Perspectiva:** câmera 3D isométrica, interação prioritariamente pelo mouse.
- **DECIDIDO — Ritmo:** contemplativo, intuitivo, agradável de observar; perigo episódico, não combate constante.
- **DECIDIDO — Diferencial:** partir de um casal identificável, acompanhar filhos, casamentos, casas e profissões, depois descobrir outras comunidades.
- **Referências funcionais:** Age of Empires (seleção e ordens); Durango: Wild Lands (natureza e sobrevivência); Ragnarok/Albion (regiões conectadas). Referências são inspiração, não ativos a reproduzir.

## 2. Premissa narrativa e regras do mundo

- **DECIDIDO — Prólogo:** o casal dirige em meio ao colapso da Terceira Guerra Mundial, com bombardeios e explosões nucleares. Quando parece não haver saída, um buraco de minhoca os transporta.
- **DECIDIDO — Travessia:** não levam carro, inventário ou ferramentas. A passagem só transporta seres vivos. As roupas rasgadas que aparecem na apresentação inicial são uma convenção visual de classificação etária, não equipamento utilizável.
- **DECIDIDO — Destino:** uma versão da Terra, com biomas e animais semelhantes aos do nosso planeta, sem cidades, estradas, ruínas de civilização ou habitantes humanos originários daquele mundo.
- **DECIDIDO — Outros sobreviventes:** todos também vieram do mundo em colapso. Alguns atravessaram juntos, outros em momentos diferentes; surgiram em regiões distintas e começaram pequenos assentamentos. Isso é desconhecido para o casal no início.
- **DECIDIDO — Escopo de seres inteligentes:** não introduzir povos não humanos para justificar o crescimento populacional.
- **ABERTO — Cosmologia:** a natureza exata daquela Terra, as regras físicas do fenômeno e o motivo da travessia são mistérios narrativos; não fixar agora explicações de viagem no tempo ou universos paralelos.
- **ABERTO — Ameaça sombria:** existe algo anormal de que os habitantes precisam se proteger; sua origem, forma, frequência e relação com a passagem ainda não foram definidas.

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

## 4. Loop central e controles RTS

**Ciclo desejado:** observar a comunidade → selecionar um ou mais moradores → dar tarefas → coletar e transportar recursos até locais de armazenamento → recursos entram no estoque → construir e melhorar → sustentar famílias → explorar e lidar com ameaças ocasionais.

- **DECIDIDO:** clique esquerdo seleciona personagem; clique direito dá ordem contextual (mover, colher, cortar, entregar carga, construir, interagir).
- **DECIDIDO:** tarefas são executadas automaticamente; o jogador não precisa controlar fisicamente cada golpe, deslocamento ou retorno de descarga.
- **PROPOSTA:** arrastar caixa para seleção múltipla; Shift para enfileirar ordens; ícones discretos de estado e barra/porcentagem de carga; câmera com zoom, arraste e limites do mapa.
- **PROPOSTA:** estados da unidade: ocioso, deslocando, trabalhando, transportando, defendendo, incapacitado (com `ocioso`, `deslocando`, `trabalhando` e `transportando` diretamente associados ao ciclo físico de coleta e entrega).
- **Regra de UX:** preferir uma única ação contextual clara a painéis cheios de microcomandos.

## 5. Sobrevivência e economia simplificadas

- **DECIDIDO:** não há barras individuais de fome ou sede.
- **DECIDIDO:** o assentamento mantém um **estoque coletivo de pontos de alimentos** e demais recursos compartilhados. Cada pessoa tem um consumo periódico; todos são sustentados por esse estoque.
- **DECIDIDO:** não é necessário cozinhar receitas complexas ou fabricar alimento ingrediente por ingrediente.
- **DECIDIDO — Transporte físico e entrada no estoque:** os materiais coletados (madeira, pedra, alimentos e futuras categorias) **não** aparecem instantaneamente no estoque compartilhado durante a coleta. Cada trabalhador carrega fisicamente os materiais coletados e a transferência para o estoque coletivo acontece apenas quando ele descarrega em um local de armazenamento válido do assentamento.
- **DECIDIDO — Peso, capacidade individual e porcentagem de carga:** cada tipo de material possui peso unitário específico e cada habitante (incluindo o casal protagonista) possui capacidade individual de carga. A capacidade ocupada deve ser representada em porcentagem (`0%` a `100%`) com base no peso total transportado, permitindo futura evolução da capacidade por características, profissão, equipamentos ou melhorias.
- **DECIDIDO — Retorno automático ao acampamento:** quando a carga do trabalhador atingir `100%`, ou não houver espaço livre suficiente para comportar mais uma unidade coletável do material, ele interrompe o ciclo na fonte e retorna ao acampamento para descarregar.
- **DECIDIDO — Armazenamento por categoria e evolução:** devem existir locais apropriados para armazenar madeira, pedra, alimentos e, futuramente, outras categorias, com suporte à evolução estrutural e de capacidade conforme a comunidade se desenvolve.
- **Fontes iniciais previstas:** coleta de frutos, pesca, caça, plantações e, posteriormente, criação de animais.
- **Recursos de trabalho iniciais previstos:** madeira, pedra e alimentos; minério é uma expansão posterior.
- **PROPOSTA:** começar no Nível 1 com pontos rústicos especializados de acampamento para madeira, pedra e alimentos sem exigir construção prévia, evoluindo para depósitos construíveis na T3+; permitir que o trabalhador carregue múltiplas categorias na mesma carga em caso de redirecionamento e entregue carga parcial caso a fonte se esgote antes de atingir `100%`.
- **PROPOSTA:** interface mostrar porcentagem de carga individual do morador selecionado, estoque coletivo por categoria, saldo alimentar por dia e autonomia estimada; consequências graduais se faltar alimento (redução de produtividade e risco para moradores comuns).
- **ABERTO:** valores numéricos exatos de peso unitário, capacidade individual inicial, taxa de coleta, consumo, tetos de capacidade dos depósitos por nível e comportamento ao esgotar ou lotar todos os depósitos disponíveis, a calibrar por testes.

## 6. Construção, profissões e nível da comunidade

- **DECIDIDO:** casas e edifícios são vistos e administrados pelo exterior; não existirão interiores jogáveis.
- **DECIDIDO:** o jogador posiciona obras, gasta recursos compartilhados e designa trabalhadores para concluí-las.
- **DECIDIDO:** cada casal casado deve ter uma casinha/residência própria.
- **DECIDIDO:** o jogador direciona a força de trabalho e decide quem atua como agricultor, pescador, lenhador, construtor, ferreiro, guarda etc.
- **DECIDIDO:** a expansão de prédios e profissões será associada ao **nível de desenvolvimento da comunidade**, ainda sem fórmula definida.
- **DECIDIDO — Evolução do armazenamento:** o armazenamento por categoria (madeira, pedra, alimentos e futuras categorias) evolui com o desenvolvimento do assentamento, partindo de pontos rústicos no acampamento inicial até depósitos dedicados e ampliações construíveis.
- **ABERTO:** teto tecnológico; intenção atual é manter uma identidade rústica, com aparência melhorada progressivamente, e não avançar obrigatoriamente à indústria moderna.

**Escada de progressão — PROPOSTA, não fechada:**

| Nível | Marco visual | Possíveis desbloqueios |
|---|---|---|
| 1 | Acampamento | Abrigo, coleta, fogueira |
| 2 | Propriedade | Primeira casa, roça, depósito |
| 3 | Povoado | Carpintaria, criação de animais |
| 4 | Aldeia | Ferraria, arsenal, estruturas de defesa |
| 5 | Vila | Oficinas, comércio local, melhorias estéticas |

**Orientação de design:** o nível libera ferramentas para crescer; não é um teto arbitrário de população.

## 7. Família, casamento, descendência e população

### Ciclo de vida — DECIDIDO

- Fases: **bebê → criança → jovem → adulto**.
- Ao atingir a fase adulta, os personagens **param de envelhecer**; o jogo não precisa fornecer justificativa narrativa.
- Bebês são dependentes, crianças podem colaborar levemente, jovens passam a contribuir mais, adultos podem executar as atividades apropriadas.
- A progressão das idades ocorre num calendário do jogo, não em tempo real.

### Casais e lares — DECIDIDO

- Personagens comuns têm **autonomia para criar afinidades e formar casais**; não são emparelhados diariamente de forma aleatória pelo jogador.
- Vínculo de casal é persistente. Cada união está associada a uma residência da família.
- Filhos pertencem a uma família identificável e podem, depois, constituir seus próprios lares.
- **PROPOSTA TÉCNICA:** guardar IDs estáveis de personagem, pais, cônjuge, família e residência para impedir inconsistências e permitir regras futuras de parentesco.
- **ABERTO:** regras de união quando um cônjuge morre, critérios de afinidade e compatibilidade entre moradores, consentimento ou confirmação por interface.

### Nascimentos — PROPOSTA EM TESTE

- Reprodução discreta e autônoma, sem cenas íntimas ou microssimulação de gravidez.
- Sugerir condições de moradia, alimentos e intervalo entre nascimentos; evitar comportamento de “fábrica de humanos”.
- **Não aprovado:** qualquer limite rígido de 1–3 filhos por casal; esse número foi apenas um exemplo de balanceamento.
- **ABERTO:** o que dispara um nascimento, como são as notificações e se existe alguma influência indireta do jogador.

### População — DECIDIDO

- **Sem limite artificial predeterminado** de habitantes ou famílias; a administração, a disponibilidade de casas e alimentos e a capacidade técnica determinam o crescimento real.
- Implementação deve permitir atualização simplificada de moradores distantes, porque “sem limite de design” não significa capacidade computacional infinita.

## 8. Mortalidade, combate e arsenal

- **DECIDIDO:** os dois protagonistas originais são líderes protegidos. Não morrem por idade nem por ataques. Se derrotados, ocorre **uma cena/evento de recuperação exclusivo para líderes** e uma penalidade temporária ainda a definir.
- **DECIDIDO:** demais habitantes, **inclusive filhos dos protagonistas**, podem morrer por perigos e ataques. Como ninguém envelhece além de adulto, não há morte por velhice.
- **DECIDIDO:** armas previstas: **espada + escudo, lança, arco e flecha**.
- **DECIDIDO:** não haverá necessidade de gerenciar slots individuais complexos; armas são produzidas, contabilizadas e distribuídas a partir de um **arsenal compartilhado**.
- **DECIDIDO:** profissões e fabricação evoluem com a comunidade; ferreiros podem produzir ferramentas e armas e guardas utilizá-las.
- **ABERTO:** regras de alcance, formação, defesa, animais hostis, recuperação, equipamento automático e detalhes dos eventos sombrios.

## 9. Mundo, regiões e ecossistema

- **DECIDIDO:** não será um mapa mundial aberto e contínuo. O mundo é dividido em **regiões conectadas por passagens**, em estrutura semelhante a Ragnarok/Albion.
- **DECIDIDO:** floresta, rios, praias/mar, montanhas, campos e fauna terrestre reconhecível, com mapas amplos para explorar e desenvolver.
- **DECIDIDO:** os outros assentamentos podem existir em regiões distantes sem precisar manter toda a geometria e IA carregadas ao mesmo tempo.
- **PROPOSTA:** carregar uma região principal por vez, guardando alterações persistentes, recursos consumidos, casas e populações em dados.
- **ABERTO:** tamanho de cada região, número total de mapas e regras para expedições entre regiões.

## 10. Direção artística e atmosfera

**DECIDIDO — Direção visual:** **3D isométrico estilizado vibrante naturalista**, com paisagens ricas, acolhedoras e fáceis de ler em perspectiva alta. Referências visuais: quatro imagens fornecidas durante o planejamento.

- Cores vivas e naturais; vegetação abundante, relva, árvores, arbustos e pedras com boa composição visual.
- Ambiente vivo: **vento movendo árvores e grama**, chuva, variações de tempo, rios e mar com movimento perceptível.
- Iluminação de dia agradável e noites mais misteriosas, mantendo legibilidade de jogo RTS.
- Personagens bem identificáveis mesmo quando pequenos; casas rústicas bonitas, com evolução visual por estágio da comunidade.
- Evitar realismo pesado, aparência excessivamente blocada, neon/glow exagerado e contornos pretos grossos.
- **ABERTO:** intensidade exata do estilo cartunesco, nível de detalhe das texturas e uso ou não de cel shading suave/outlines discretos.

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

## 12. Stack, arquitetura e desempenho

| Camada | Ferramenta / abordagem | Status |
|---|---|---|
| Engine | **Godot 4.x** | Escolhida |
| Código | **GDScript** | Recomendado |
| Assistência | **Antigravity** | Escolhido |
| Versionamento | **Git local** | Recomendado |
| Arte 3D | Blender | Previsto / opcional conforme ativos |
| Geração de malhas | Tripo AI | Opcional |
| Movimentação | NavigationAgent3D / navegação Godot, a validar | A testar |
| Dados | Resources (.tres) e IDs estáveis | Recomendado |
| Salvamento | Arquivos locais versionados por esquema | Planejado |
| Rede | Sem servidor para MVP single-player | Decidido |

**Arquitetura modular recomendada:**

- `World/RegionManager`: entradas e saídas de regiões, estado persistente e carregamento seletivo.
- `Units/SelectionController` e `Orders`: seleção RTS, comandos, fila e execução.
- `AI/JobSystem`: ocupações, priorização, navegação, trabalho e comportamento ocioso.
- `Economy/SettlementInventory`: estoque comum, produção, consumo alimentar e arsenal.
- `Buildings/ConstructionSystem`: posicionamento, custos, progresso e melhoria estética.
- `Families/PopulationSystem`: famílias, casamento, vínculo de casa, nascimento e progressão de fase.
- `Progression/SettlementLevel`: desbloqueios por desenvolvimento, separados da população.
- `Narrative/ChapterState`: requisitos narrativos (sem aparições humanas antes de jovens) e eventos misteriosos.
- `Save/SaveManager`: serialização estável e migração de saves.

**Desempenho:** testar desde T1 em hardware modesto (referência de desenvolvimento: Intel UHD 620, 16 GB RAM). Vegetação animada por shaders leves; água estilizada; chuva controlada; culling, LOD/multimesh conforme necessidade. Avaliar renderizadores Compatibility/Mobile com medição real, sem assumir resultados antecipadamente.

## 13. Roadmap executável para Antigravity

| Marco | Escopo | Evidência mínima de conclusão |
|---|---|---|
| T1 — Fundação RTS | Câmera, terreno demonstrativo, casal selecionável, clique para mover | Os dois recebem e concluem ordens de movimento sem travar |
| T2 — Trabalho e recursos | Recursos coletáveis com peso, capacidade individual (0%–100%), transporte físico, pontos de armazenamento por categoria e estoque compartilhado | Ordem em árvore/arbusto/rocha acumula carga na unidade e o estoque coletivo só aumenta após entrega física no depósito compatível |
| T3 — Construção | Posicionar obra, descontar recursos, designar construtor | Abrigo/casa completado e persistido |
| T4 — Mundo e calendário | Ciclo dia/noite, tempo, região inicial, salvar/carregar | Estado e construções persistem após reiniciar |
| T5 — Família | Entidades familiares, fases, residência, nascimentos em modo teste | Vínculos e progressão sobrevivem ao save/load |
| T6 — Combate e arsenal | Armas coletivas, ameaças simples, derrota/recuperação | Líder recupera; NPC comum segue regra de mortalidade |
| T7 — História e atmosfera | Eventos do capítulo 1, vento, chuva, água, mistério discreto | Capítulo 1 não apresenta nenhum humano externo |
| T8 — Primeiro contato | Regras de capítulo 2, 1–2 encontros, comunidades simuladas | Encontros só são possíveis após filho jovem |

**Prioridade absoluta:** entregar **T1 a T3** antes de tentar implementar nascimento, diplomacia ou mundo grande.

## 14. Critérios de aceite do primeiro protótipo

1. Jogador consegue selecionar um ou ambos protagonistas e dar ordens pelo mouse.
2. Personagens encontram caminho, executam trabalho de coleta acumulando carga física individual e entregam os recursos nos locais de armazenamento apropriados do assentamento.
3. Existe estoque coletivo com alimentos e outro recurso de construção.
4. Jogador posiciona e conclui um abrigo sem entrar em interior.
5. Interface é legível em câmera isométrica e não exige microgestão de fome individual.
6. Testes básicos cobrem seleção, ordem, estoque, construção, save e carregamento.
7. Nenhuma mecânica de população ou mistério é adicionada prematuramente apenas para “parecer completo”.

## 15. Riscos e pendências reais

- **ABERTO:** nome comercial *Dawn of Kin* exige pesquisa de disponibilidade e marca antes de lançamento.
- **ABERTO:** taxa de envelhecimento e nascimento; o jogador quer observar a família sem ter uma “fábrica de humanos”.
- **ABERTO:** lógica de afinidade, casamentos autônomos e como lidar com viúvos.
- **ABERTO:** como personagens de outras comunidades se tornam parceiros e passam a morar no assentamento.
- **ABERTO:** forma e regras da ameaça sombria; não fixar monstro, magia ou fraqueza à luz antes de decidir.
- **ABERTO:** progressão exata de níveis, tech tree e teto tecnológico.
- **ABERTO:** ritmo e detalhes de combate, perdas e consequências de fome.
- **ABERTO:** polígonos, shaders, renderizador final, limite de unidades simultaneamente animadas e orçamento de desempenho.

## 16. Instrução de handoff para o Antigravity

**Missão inicial:** implementar apenas o marco **T1 — Fundação RTS** usando este GDD como fonte de verdade. Antes de alterar arquivos, analisar a estrutura existente do projeto, caso haja uma; caso não exista, propor uma estrutura mínima de Godot 4.x. Não assumir que já exista código para *Dawn of Kin*.

**Regras de execução:**

1. Trabalhar em passos pequenos, testáveis e reversíveis; não implementar T2–T8 antes da validação de T1.
2. Preservar funcionalidades já existentes; antes de mudanças estruturais, registrar o estado do Git e explicar o plano.
3. Preferir código modular, nomes claros, cenas reutilizáveis e dados desacoplados de UI.
4. Separar comportamento de protótipo de decisões fechadas; qualquer valor temporário deve estar documentado e parametrizado.
5. Executar testes e informar arquivos alterados, comandos usados, resultados, limitações e próximos passos.
6. Não produzir ativos finais de arte até definição de orçamento visual e validação do núcleo RTS.

**Primeiro resultado esperado:** um mapa de teste isométrico com dois personagens distinguíveis, seleção por clique, comando de movimento por clique direito, feedback visual e câmera funcional. Nada além disso é obrigatório para T1.

---

**Status do documento:** base consolidada e pronta para orientar implementação incremental. Pendências estão explicitamente marcadas para que o Antigravity não as transforme em decisões implícitas.
