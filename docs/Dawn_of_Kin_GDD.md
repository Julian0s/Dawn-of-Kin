# DAWN OF KIN

**Documento Mestre de Design (GDD Único Consolidado)**
**Versão Interna:** **v1.2 RC — Aguardando Aprovação** (Caminho canônico estável: `docs/Dawn_of_Kin_GDD.md`)
**Data:** 16 de novembro de 2026
**Uso:** Fonte única de verdade de produto, narrativa, mecânicas e arquitetura para o projeto *Dawn of Kin*
**Base Técnica Auditada:** `main` em `3c6fc0bd36fc3828af5a89662fb23cfb60d37865` (Tag `t3-3-complete`)
**Nome de Trabalho:** *Dawn of Kin* («Aurora da Linhagem»); disponibilidade comercial e registro de marca permanecem **ABERTO** antes da publicação

> **Governança e Regra de Leitura:**
> Este documento unifica e substitui na branch de revisão os antigos arquivos `Dawn_of_Kin_GDD_v1.0.md`, `Dawn_of_Kin_GDD_v1.1.md` e `Dawn_of_Kin_GDD_v1.2_PROPOSAL.md` (cujos históricos permanecem integralmente preservados no Git e nos relatórios em `docs/audits/`). Na `main`, a substituição normativa só ocorrerá após auditoria independente do ChatGPT e autorização expressa do proprietário.
>
> **Marcadores de Status:**
> - **DECIDIDO:** regra de design ou arquitetura expressamente aprovada pelo proprietário.
> - **IMPLEMENTADO:** comportamento confirmado no código GDScript, cenas `.tscn` ou recursos `.tres` na `main` (`3c6fc0b`).
> - **VALIDADO:** comportamento testado com evidências documentadas (suítes automatizadas, protocolos manuais aprovados e benchmarks).
> - **PROPOSTA:** sugestão técnica, hipótese de orçamento ou parâmetro inicial sujeito a teste — **não** compromisso fechado.
> - **ABERTO:** questão intencionalmente sem definição final, reservada para calibração ou decisão futura.
> - **PENDENTE DE APROVAÇÃO:** especificação técnica dependente de revisão antes de codificar (ex.: `T3.4-ARCHITECTURE-R2`).
>
> **Estado Real do Desenvolvimento em 16/11/2026:**
> - **T1 — Fundação RTS:** **CONCLUÍDA, VALIDADA E INTEGRADA** (`t1-complete`, commit `2808799`).
> - **T2 — Trabalho e Recursos:** **CONCLUÍDA, VALIDADA E INTEGRADA** (`t2-complete`, commit `f7c2459`, 14/11/2026).
> - **T3.1 — Contabilidade, Reservas e Saque em Lote:** **CONCLUÍDA, VALIDADA E INTEGRADA** (`ceb3f71`, 15/11/2026).
> - **T3.2 — Validação Espacial, Área Reservada e Prévia sem Grid:** **CONCLUÍDA, VALIDADA E INTEGRADA** (`931ad19`, 15/11/2026).
> - **T3.3 — Canteiro de Obra e Suprimento Físico:** **CONCLUÍDA, HOMOLOGADA E INTEGRADA** (`t3-3-complete`, commit `3c6fc0b`, 16/11/2026).
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
3. **Comando RTS Soberano + Autonomia Cotidiana:** Ordens diretas do jogador pelo mouse têm prioridade máxima, enquanto moradores com profissão executam suas rotinas autonomamente quando ociosos (`JobSystem`) e buscam a próxima fonte próxima quando a atual se esgota.
4. **Despertar Gradual de Profissões, Vocações e Dons:** Habilidades de trabalho, defesa e capacidades especiais desenvolvem-se por aprendizado, treino, experiência e mentoria — nunca como distribuição mágica instantânea de classes.
5. **Natureza Vibrante em Contraste com o Mistério Sombrio:** Uma paisagem 3D estilizada vibrante e naturalista contrasta com o mistério silencioso do Ser de Trevas e suas influências sobre o mundo.

---

## 2. História, Universo e Progressão Narrativa

### 2.1 Premissa do Mundo e Cosmologia: Bastidores vs. Percepção Jogável (`DECIDIDO` e `ABERTO`)
Para manter a consistência narrativa e o mistério durante a campanha, distingue-se rigorosamente o que pertence à **mitologia de bastidores do autor** daquilo que **os personagens e o jogador sabem em cena**:

- **A Chegada (`DECIDIDO` — Visível ao Jogador):**
  - No prólogo, o casal dirige em meio ao colapso da Terceira Guerra Mundial, cercado por bombardeios e explosões nucleares. Quando parece não haver saída, um buraco de minhoca os transporta.
  - A passagem transporta **apenas seres vivos** (sem carro, inventário, armas ou ferramentas). As roupas rasgadas iniciais são uma convenção visual de apresentação e classificação etária (não equipamento utilizável trazido da Terra), podendo ser substituídas futuramente por roupas produzidas pela comunidade.
  - O destino é **uma versão da Terra**, com biomas e animais terrestres semelhantes aos conhecidos, sem cidades, estradas, ruínas humanas ou povos não humanos inteligentes.
- **Outros Sobreviventes (`DECIDIDO`):**
  - Todos os outros humanos existentes nesse mundo também vieram da Terra em colapso através do fenômeno, surgindo em regiões distintas e possivelmente em momentos diferentes. Isso é desconhecido para o casal no Capítulo 1.
- **Cosmologia de Bastidores (`DECIDIDO` como cânone autoral oculto — `DEC-05`):**
  - **O Ser de Trevas:** Há milhares de anos, antes de existir vida naquele planeta, uma entidade ancestral maligna — cujo nome ninguém conhece — instalou-se naquele lugar. Seu poder pode corromper parte da fauna (tornando esses animais mais fortes e irradiando trevas, enquanto animais normais continuam existindo) e seduzir corações humanos vulneráveis.
  - **O Ser de Luz:** Em bastidores, foi o Ser de Luz quem abriu a passagem para salvar escolhidos da guerra a fim de repovoar a terra e enfrentar o mal ali instalado. Contudo, **o Ser de Luz não aparece no Capítulo 1**, não trava combate direto e sua eventual manifestação ou revelação futura permanece aberta, sem data ou capítulo obrigatório.
- **Mistérios Mantidos Intencionalmente em Aberto (`ABERTO`):**
  - A natureza cosmológica exata dessa versão da Terra e a física da travessia (não fixar como fato se é o mesmo planeta original, viagem no tempo, universo paralelo ou passado remoto).
  - A identidade última do Ser de Luz, o nome/origem do Ser de Trevas e suas verdadeiras intenções.
  - A origem última dos dons latentes (que permanece misteriosa para os protagonistas durante o Capítulo 1).

### 2.2 Progressão Narrativa por Capítulos (`DECIDIDO`)

#### Capítulo 1 — O Isolamento
- **Ato I — Sobrevivência e Primeiro Abrigo (`DECIDIDO`):**
  - Apenas o casal original e, posteriormente, seus próprios filhos; nenhuma aparição ou recrutamento de humanos externos.
  - O jogador aprende os controles RTS, coleta frutos, madeira e pedra, forma pilhas no acampamento inicial e constrói o **Abrigo Básico** (e o **Depósito Rústico**).
- **Ato II — A Única Aparição Pessoal do Ser de Trevas (`DECIDIDO` — Direção Narrativa Atualizada):**
  - Depois que o casal constrói seu primeiro abrigo, ocorre um evento misterioso, preferencialmente em uma noite apropriada.
  - A natureza ao redor fica estranhamente silenciosa.
  - Uma figura sombria surge à distância e dirige algumas palavras ao casal. *(Exemplo provisório de diálogo, não texto final obrigatório: «Saudações, visitantes... O dia se aproxima.»).*
  - A entidade **não luta, não ataca e não explica sua identidade**; após a mensagem, desaparece.
  - **Regra Canônica:** Esta é a **única aparição pessoal direta** do Ser de Trevas nos capítulos atualmente planejados. Ele continuará influenciando parte dos animais, o ambiente e grupos humanos em capítulos futuros, mas sem reaparecer pessoalmente.
  - **Ausência do Ser de Luz:** O Ser de Luz **não** aparece no Capítulo 1, não há confronto entre entidades e não há cena de concessão de bênção após o abrigo.
- **Ato III — Crescimento da Família e Despertar Gradual (`DECIDIDO`):**
  - O casal estabelece a propriedade, cultiva alimentos, manifesta sua capacidade inicial de recuperação (*Alento*), tem filhos e acompanha seu amadurecimento de Bebê para Criança e Jovem, lidando com perigos naturais e indícios sombrios moderados.
- **Portão Narrativo Obrigatório (`DECIDIDO`):** Encontros com outros humanos são estritamente proibidos até que **pelo menos um filho alcance a fase Jovem (12 anos)**.

#### Capítulo 2 — Não Estamos Sozinhos
- **DECIDIDO:** Superado o portão da juventude do primeiro filho, ocorrem apenas **1 ou 2 encontros humanos significativos** inicialmente — sem fluxo constante de colonos nem botão de recrutamento.
- Esses sobreviventes vieram da mesma guerra e fundaram pequenos assentamentos em regiões distantes.

#### Capítulo 3 — Laços entre Comunidades e Conflitos contra a Sombra
- **DIREÇÃO APROVADA (`DECIDIDO` — `DEC-02`, `DEC-07`, `DEC-12`):**
  - Cooperação, comércio por trocas de recursos e formação de novas famílias por casamentos entre jovens de comunidades pacíficas distintas.
  - Em regiões distantes, revela-se que **um grupo humano foi seduzido pela influência do Ser de Trevas**, originando conflitos e guerras futuras contra as comunidades livres e contra feras corrompidas.
- **ABERTO:** Regras detalhadas de diplomacia, rotas comerciais permanentes e capítulos finais da campanha.

---

## 3. Família, Linhagem, Personagens Modulares e População

### 3.1 Criação do Casal, Personagens Modulares e Herança Visual (`DECIDIDO` — `v1.1` §7.1–7.4 + `DEC-16`)
- **Criação do Casal Inicial (`DECIDIDO`):** Modelos-base personalizáveis permitindo escolher formato do rosto e detalhes faciais (olhos, nariz, mandíbula), modelo/textura/cor do cabelo, cor dos olhos, tom de pele dentro de ampla faixa natural e botão **Randomizar**. Cores escolhidas na criação inicial (inclusive incomuns) são tratadas como naturais e hereditárias.
- **Peças Modulares (`DECIDIDO`):** Personagens compostos por **Cabeça**, **Cabelo**, **Corpo** e **Vestuário** intercambiáveis. Variantes produzidas em Blender ou Tripo AI exigem padronização obrigatória para Godot (escala, pivô, pesos de ossos, esqueleto único por faixa etária e materiais recoloríveis parametrizados).
- **Herança Visual (`DECIDIDO`):** Filhos herdam probabilisticamente (com pequenas variações) formato do rosto, cor dos olhos, tom de pele, cor/textura do cabelo, tendência de altura e constituição física, mantendo identidade visual consistente entre fases e salvamentos. *(Limites numéricos e influência de avós: `ABERTO`).*

### 3.2 Nomes, Sobrenomes e Identidade Persistente (`DECIDIDO` — `v1.1` §7.5 + `DEC-16`)
- **ID Estável:** Cada personagem possui identificador único imutável; renomear nunca altera genealogia, vínculos ou residência.
- **Nome e Sobrenome da Linhagem (`DEC-16`):** O casal protagonista e cada família possuem **Nome + Sobrenome Familiar** (definido ou sorteado na criação). Todo humano externo já surge com nome e sobrenome próprios persistentes (nunca `Aldeão 1`).
- **Nomeação de Filhos:** Ao nascer, a criança recebe o sobrenome da família e um nome próprio inédito sugerido automaticamente (evitando repetição entre irmãos, salvo rara homenagem a pai/mãe), podendo o jogador editar o nome livremente sem pausar a partida à força.

### 3.3 Ciclo de Vida, Limites por Idade e Calendário (`DECIDIDO` — `DEC-01`, `DEC-04`)
- **Quatro Fases (`DECIDIDO`):** **Bebê (`0–2 anos`) → Criança (`3–11 anos`) → Jovem (`12–17 anos`) → Adulto (`18+ anos`)**. Ao atingir **Adulto (18 anos)**, o personagem **para de envelhecer** (não há morte por velhice).
- **Atuação e Restrições por Idade (`DEC-04`):**
  - **Bebê (`0–2`):** Dependente, permanece protegido na residência da família (visível na interface da casa/família, **não** é unidade RTS selecionável ou comandável no mapa).
  - **Criança (`3–11`):** Visível e selecionável; colabora apenas em **tarefas leves e seguras** (colher frutos, pequenas cargas leves), proibida de cortar árvores, quebrar pedras, construir pesado ou combater.
  - **Jovem (`12–17`):** Trabalha em coleta, construção e aprendizado de profissões/ofícios apropriados à idade; destrava o Capítulo 2, mas **não pode casar** e **não atua em especialização combatente plena**.
  - **Adulto (`18+`):** Aptidão plena para todas as profissões, vocações combatentes, casamento e residência própria.

### 3.4 Nascimentos, Genealogia, Viuvez e Mortalidade (`DECIDIDO` — `DEC-02`, `DEC-03`, `DEC-04`)
- **Residência por Casal:** Cada casal casado exige residência própria. O **Abrigo Básico** já habilita o casal protagonista a ter seus primeiros filhos no Capítulo 1.
- **Gatilho Autônomo de Nascimento (`DEC-03`):** Discreto e autônomo. Requer: (1) casal residindo junto, (2) **vaga de dependente** (Bebê/Criança) disponível na residência, (3) estabilidade alimentar no estoque coletivo, e (4) **intervalo progressivo** que cresce a cada filho já tido pelo mesmo casal (evitando comportamento de "fábrica de humanos" sem impor limite rígido de 1–3 filhos).
- **Bloqueio de Consanguinidade e União entre Comunidades (`DEC-02`):** Proibida afinidade romântica entre parentes até **primos de 1º grau** (pais/filhos, irmãos, tios/sobrinhos e primos de 1º grau). Nos Capítulos 2 e 3, jovens adultos de comunidades vizinhas podem criar afinidade, casar com filhos adultos do jogador e mudar-se para a vila quando houver residência disponível.
- **Viuvez e Orfandade (`DEC-04`):** Moradores comuns (inclusive filhos adultos) podem morrer em ataques e perigos. O cônjuge sobrevivente mantém a residência e a guarda dos filhos menores, podendo recasar após período de luto no calendário. Se ambos os pais de menores morrerem, os avós (casal líder) ou parentes acolhem as crianças.
- **População (`DECIDIDO`):** Sem teto artificial predeterminado; regulada por moradia, alimentos e capacidade técnica (com simulação simplificada para moradores distantes).

---

## 4. Trabalho, Economia Física e Construção

### 4.1 Coleta, Transporte Físico e Armazenamento (`DECIDIDO` e `IMPLEMENTADO` T2)
- **Sem Fome/Sede Individual (`DECIDIDO`):** Consumo alimentar periódico atendido pelo estoque coletivo compartilhado, sem receitas culinárias complexas.
- **Proibição de Crédito Instantâneo (`DECIDIDO` / `IMPLEMENTADO`):** Recursos extraídos (`wood` peso `2`, `stone` peso `3`, `food` peso `1` — provisórios em `data/resources/*.tres`) são carregados em `UnitCarryLoad` (`0%` a `100%` da capacidade base `20`, reduzindo a velocidade de `4,8 m/s` até `2,88 m/s` quando cheio) e só entram no estoque coletivo após descarga física em armazenamento válido.
- **Pilhas e Armazenamento no Mundo (`DECIDIDO` D8 / `IMPLEMENTADO` T2):** Na T2, as descargas formam pilhas físicas (`GroundResourcePile`) na `CampStorageZone` (`5,6 × 4,4 m` no `TestMap`). Futuramente, materiais largados fora de armazenamento válido não integram o estoque coletivo até serem transportados a uma zona/depósito válido.

### 4.2 Deterioração por Categoria e Reposição Manual de Reservas (`DECIDIDO` — `DEC-11A` e `DEC-11B` **RATIFICADAS**)
- **Deterioração por Categoria (`DEC-11A` — `RATIFICADO`):**
  - **Alimentos e Madeira** expostos no chão sofrem desgaste temporal configurável (`decay_food_provisional.tres`, `decay_wood_provisional.tres`).
  - **Pedra bruta exposta não sofre deterioração temporal** (`data/resources/decay_stone_provisional.tres` mantido com `can_decay = false`).
  - Futuras categorias terão regras próprias sem presumir desgaste automático idêntico.
- **Perda Direta sobre Reservas (`DECIDIDO` — Alternativa B, `IMPLEMENTADO` T3.1):** Reservas de obra não protegem pilhas expostas. Se `step_decay()` reduzir uma pilha abaixo do reservado, a reserva naquela pilha cai até o saldo físico restante, **sem realocação automática** para outras pilhas.
- **Complementação Manual de Reservas Deterioradas (`DEC-11B` — `RATIFICADO`):**
  1. Se material reservado numa pilha deteriorar antes do transporte, a reserva diminui e a obra passa a ter déficit de suprimento, preservando integralmente o progresso e os materiais já entregues/incorporados no canteiro.
  2. O **jogador deve autorizar manualmente o complemento da reserva no canteiro** (não existe reposição automática silenciosa).
  3. A nova quantidade só pode ser reservada se houver **materiais livres reais** no estoque (jamais retirando reservas de outras obras).
  4. Uma vez autorizada e reservada a complementação, os trabalhadores realizam o **transporte físico normal** até o canteiro (jamais crédito instantâneo).

### 4.3 Construção Progressiva (`D1–D9`, `DEC-18`, `DEC-19`)
- **Posicionamento Contínuo sem Grid (`D6` / `IMPLEMENTADO` T3.2):** Edifícios vistos pelo exterior; `CampStorageZone` protegida contra obras na T3; validação de inclinação ($\le 10^\circ$), desnível ($\le 0,35\text{ m}$), colisões e conectividade em malha navegável candidata assíncrona.
- **Parâmetros Provisórios `D4` (`DECIDIDO` como provisórios):**
  - **Abrigo Básico (`shelter_basic`):** $4,0 \times 4,0\text{ m}$, **12 Madeiras + 6 Pedras** (`42` de peso), **30,0 s-construtor**, máx. **2 construtores**.
  - **Depósito Rústico (`storage_depot`):** $5,0 \times 4,0\text{ m}$, **18 Madeiras + 10 Pedras** (`66` de peso), **45,0 s-construtor**, máx. **2 construtores**; protege até **50 madeiras, 50 pedras e 30 alimentos** com decaimento `0,0` (`D5`).
- **Organização de Trabalhadores `D9` e Montagem (`D2`, `DEC-18`):**
  - **1 trabalhador:** transporta primeiro todos os materiais reservados e acessíveis (`SOLO_SUPPLIER`); quando não houver mais entregas possíveis, monta a obra com o que estiver disponível no buffer.
  - **2 trabalhadores:** 1 transporta enquanto 1 constrói simultaneamente consumindo suprimento parcial; após concluir entregas, o transportador pode assumir o 2º slot de construtor.
  - **3 trabalhadores:** 1 transporta enquanto 2 constroem (teto de 2 construtores); ao concluir entregas, o transportador fica livre.
  - **4º trabalhador:** recusado com `no_worker_slot`.
- **Consumo, Transmutação e Cancelamento (`T3.4`–`T3.6`):** Consumo inteiro proporcional transacional do buffer e conversão em `BuildingInstance` com inclusão no `WorldNavigation` regional (`DEC-19` — Opção N1, sujeita à revisão `T3.4-ARCHITECTURE-R2`). Cancelamento (`D3` na `T3.6`) devolve 100% do não consumido e recupera $\lfloor Q_{\text{inc}} \times (1 - p) \times 0,50 \rfloor$ do incorporado.

### 4.4 Economia Cooperativa, Vestuário e Comércio Futuro (`DECIDIDO` — `DEC-12`)
- **Sem Salários ou Moeda Interna (`DEC-12`):** Não existe pagamento de salário nem compra individual de itens dentro da comunidade. Roupas produzidas (substituindo os trapos iniciais) e ferramentas/armas integram o estoque/arsenal coletivo e equipam os moradores conforme sua função.
- **Comércio entre Comunidades:** Ocorre por trocas de recursos/itens entre vilas distintas no Capítulo 3 (`ABERTO` para taxas exatas).

---

## 5. Profissões, Vocações, Dons Latentes e Cura Inicial (*Alento*)

O jogo separa claramente três dimensões de desenvolvimento humano, evitando a distribuição artificial e instantânea de "classes de RPG":

### 5.1 Distinção entre Profissão, Vocação e Dom (`DECIDIDO`)

| Sistema | Definição | Exemplos | Regras de Funcionamento |
|---|---|---|---|
| **1. Profissão** | Trabalho cotidiano produtivo do morador na comunidade. | Agricultor, Lenhador, Minerador/Pedreiro, Construtor, Costureiro, Ferreiro. | Qualquer morador em idade apta pode exercer uma profissão; quando `IDLE`, executa sua rotina automaticamente (`JobSystem` — `DEC-08`). |
| **2. Vocação** | Especialização de defesa ou apoio comunitário. | **Guerreiro**, **Arqueiro**, **Curandeiro**, **Canalizador da Luz**. | Coexiste com a profissão (o morador não abandona sua profissão ao ter uma vocação, mas executa **uma tarefa por vez**, com prioridade para ordens manuais do jogador). |
| **3. Dom** | Capacidade sobrenatural latente ou despertada. | **Alento** (recuperação inicial), proteção luminosa, canalização da Luz. | Latente nas pessoas; desperta e evolui por prática, experiência e mentoria. Não é obrigatório para todos os habitantes. |

### 5.2 Regras do Sistema de Dons Latentes (`DECIDIDO`)
1. **Despertar, não Concessão:** Os dois líderes protagonistas **não concedem** poderes sobrenaturais a outras pessoas; eles ajudam a identificar, compreender e despertar capacidades latentes que já existem em potencial nos indivíduos.
2. **Aptidões e Ritmos Individuais:** Cada pessoa possui potencial, aptidão, ritmo e escolha próprios; a manifestação de dons sobrenaturais **não é obrigatória** para todos os moradores.
3. **Sem Exclusividade Genética:** Pessoas de outras linhagens e comunidades também podem manifestar dons latentes.
4. **Treinamento, Experiência e Mentoria:** O controle e a eficácia de um dom crescem com uso e treinamento; aprendizes que se tornam experientes poderão futuramente ensinar outros habitantes.
5. **Independência das Vocações Físicas:** **Guerreiros** e **Arqueiros** desenvolvem suas especializações por treinamento físico e equipamento, sem depender de poderes sobrenaturais; **Curandeiros** combinam cuidados práticos/ervas com eventual despertar de dons de recuperação; **Canalizadores da Luz** constituem especialização avançada posterior.
6. **Requisitos Coerentes (Sem Contadores Arbitrários):** Nenhuma vocação exige um número arbitrário de população; exige idade adulta (para combatentes plenos), aprendizado/instrutor, ferramentas/armas e infraestrutura correspondente.

### 5.3 Cura Inicial dos Líderes: *Alento* vs. Proteção pós-Derrota (`DECIDIDO`)
- **Habilidade Inicial — *Alento* (Nome Provisório):**
  - Ambos os protagonistas começam com uma capacidade latente de recuperação que se manifesta naturalmente durante a sobrevivência no Capítulo 1.
  - Proporciona **recuperação limitada de ferimentos**, com utilização simples e compreensível, sujeita a intervalo de recarga ou custo temporário de esforço (sem introduzir sistema complexo de mana no primeiro lançamento).
  - Evolui com a experiência, mas **não ressuscita mortos** e **não substitui** alimentação, moradia, cuidados médicos ou proteção física.
- **Distinção Crítica — *Alento* vs. Proteção de Sobrevivência dos Líderes:**
  - *Alento* é uma habilidade ativa limitada de cuidado.
  - A **Proteção Especial dos Líderes** é a regra exclusiva segundo a qual os **dois protagonistas originais nunca morrem definitivamente**: ao caírem a 0 HP, são resgatados e recolhidos à residência com penalidade de *Exaustão Temporária*. Moradores comuns (inclusive filhos) **não** possuem essa imortalidade e podem morrer se seus ferimentos não forem tratados a tempo.

---

## 6. Evolução da Comunidade (Cinco Níveis Reconciliados)

A comunidade avança por **marcos concretos de desenvolvimento e construção**, **sem** depender de aparição ou bênção visível do Ser de Luz, **sem** barra de XP artificial e **sem** exigir mais trabalhadores do que a família pode possuir naquele momento (`DECIDIDO` — `DEC-13` reconciliada):

| Nível | Marco da Comunidade | Marcos de Acesso e Desbloqueios Coerentes (`DECIDIDO`) |
|---|---|---|
| **1** | **Acampamento** | **Início:** Pilhas físicas na `CampStorageZone`, Fogueira, **Abrigo Básico** e **Depósito Rústico**. Sobrevivência inicial do casal, manifestação natural do *Alento* e, após erguer o abrigo, ocorrência do evento noturno da única aparição pessoal do Ser de Trevas. |
| **2** | **Propriedade** | **Marcos:** Estabilização do abrigo, depósito e sustento inicial.<br>**Desbloqueios:** Primeiras **Casas Familiares**, **Roça** (agricultura contínua), **Costura/Tecelagem** (roupas comunitárias substituindo os trapos), cuidados básicos de saúde/ervas e defesa rudimentar (lanças simples de madeira/pedra) compatíveis com o isolamento familiar do Capítulo 1. |
| **3** | **Povoado** | **Marcos:** Consolidação agrícola, vestuário e crescimento familiar.<br>**Desbloqueios:** **Carpintaria** (ferramentas melhores, arcos e flechas), **Criação de Animais** e **Montarias**, **Caminhos** estruturados, Paliçadas e formação inicial de **Arqueiros** e defensores. |
| **4** | **Aldeia** | **Marcos:** Infraestrutura de madeira/pedra consolidada e comunidade expandida (Capítulos 2/3).<br>**Desbloqueios:** Mineração, **Ferraria e Arsenal** (**Espada + Escudo** e proteções metálicas para **Guerreiros** completos), espaço de mentoria/estudo (**Curandeiros** especializados e despertar de **Canalizadores da Luz**) e Torres de Defesa. |
| **5** | **Vila** | **Marcos:** Domínio metalúrgico, defesas e laços regionais.<br>**Desbloqueios:** Oficinas avançadas, **Posto de Trocas** entre comunidades, fortificações pesadas e organização completa das quatro vocações para enfrentar grandes ameaças sombrias e facções humanas seduzidas. |

*Regra de Escopo do Capítulo 1:* O jogador **não** precisa alcançar os Níveis 4 ou 5 no Capítulo 1; os Níveis 1 a 3 oferecem progressão completa e autossuficiente para o casal e seus filhos durante o isolamento.

---

## 7. Mundo, Regiões e Ecologia

### 7.1 Regiões Conectadas e Simulação em Segundo Plano (`DECIDIDO` — `DEC-14`)
- **Topologia Regional:** Mundo dividido em regiões conectadas por passagens nas bordas (estilo *Ragnarok/Albion*).
- **Escala Planejada:** `TestMap` (`64×64 m`) mantido para testes da T1–T3; regiões oficiais da T4+ dimensionadas entre **`256 × 256 m` e `384 × 384 m`**.
- **Simulação Leve:** Apenas a região ativa é renderizada em 3D; durante expedições, o assentamento principal opera em simulação matemática leve (mantendo lavouras, obras e calendário), permitindo alternar a câmera entre Vila e Expedição. *(Desempenho sujeito a medição empírica obrigatória na Intel UHD 620).*

### 7.2 Ecologia, Limpeza de Fontes Esgotadas e Caminhos (`DECIDIDO` — `DEC-09`, `DEC-10`)
- **Remoção 100% de Árvores e Pedras Esgotadas (`DEC-09`):** Ao chegar a `0` unidades restantes, **Árvores** (após queda) e **Pedras** desaparecem completamente da cena (`queue_free()`, eliminando os resíduos visuais `StumpMesh`/`RubbleMesh` e colisores permanentes do protótipo T2), liberando o terreno para passagem e construção.
- **Brotação Orgânica e Caminhos (`DEC-09`):** Novas árvores brotam gradualmente em qualquer solo natural livre onde **não** existam construções, canteiros, `CampStorageZone` ou **Caminhos** (que bloqueiam vegetação e melhoram o deslocamento).
- **Arbustos e Roças (`DEC-10`):** Arbustos regeneram frutos ciclicamente, mas podem ser arrancados quando o jogador construir sobre o local. **Roças** produzem ciclos sucessivos de alimentos sob cuidado do Agricultor.

---

## 8. Combate e Ameaças

### 8.1 Ameaças Naturais, Corrompidas e Humanas (`DECIDIDO`)
- **Fauna Terrestre:** Animais naturais (caça e predadores territoriais) e **animais corrompidos pelo Ser de Trevas** (maiores, mais fortes e irradiando trevas — `DEC-05`).
- **Facções Humanas Seduzidas (`DEC-07`):** Nos capítulos posteriores (Cap. 3), grupos humanos seduzidos pela Sombra provocam conflitos e guerras.

### 8.2 Controle RTS de Combate, Vocações e Líderes (`DECIDIDO` — `DEC-15`)
- **Arsenal Compartilhado:** Armas (**Espada + Escudo**, **Lança**, **Arco e Flecha**) produzidas e distribuídas pelo estoque/arsenal comunitário sem inventário individual complexo de múltiplos slots.
- **Formação e Suporte Automático (`DEC-15`):** Ao comandar um grupo misto com clique direito, **Guerreiros** posicionam-se automaticamente na linha de frente, enquanto **Arqueiros**, **Curandeiros** e **Canalizadores da Luz** atuam na retaguarda (curando aliados feridos e dissipando a aura sombria dos inimigos corrompidos).
- **Comandos Especiais dos Líderes (`DEC-15`):** Os 2 Líderes originais dispõem de comandos especiais táticos que acionam ou potencializam os *skills* dos combatentes em momentos críticos.

---

## 9. Interface, Controles, Arte e Desempenho

- **Câmera e Input RTS (`DECIDIDO` / `IMPLEMENTADO`):** Câmera isométrica (`-45°` yaw, `-48°` pitch, `FOV 42°`), zoom, `WASD`/setas, `MMB` drag, seleção por clique/caixa e **Edge Scrolling acionado exclusivamente no limite real da viewport** (`6 px` base com janela em foco).
- **UI de Construção e Contexto (`D7` — `T3.5`):** Botão discreto **Construir** no canto inferior direito, painel retrátil e inspetor contextual do canteiro (progresso, complemento manual de reserva `DEC-11B` e cancelamento `D3`), sem obstruir os painéis existentes.
- **Direção Artística (`DECIDIDO`):** **3D isométrico estilizado vibrante naturalista** com materiais PBR limpos, vegetação viva, água animada, iluminação diurna acolhedora e noites misteriosas legíveis, sem contornos pretos grossos ou neon exagerado.
- **Personagens Modulares e Desempenho (`DECIDIDO` e `PROPOSTA` — `DEC-16`):** Esqueleto Único padronizado por faixa etária e materiais recoloríveis. O orçamento de `~1.500–3.500` triângulos por personagem e técnicas de hibernação de RVO/`MultiMesh` permanecem como **propostas técnicas a validar empiricamente** na **Intel UHD Graphics 620** (`1920×1080`, `gl_compatibility`, meta $p95 \le 16,7\text{ ms}$ e `0` quadros $> 100\text{ ms}$ em tomada CA).

---

## 10. Estratégia de Lançamento e Horizontes de Produto

Para assegurar viabilidade de produção sem sacrificar a visão completa do projeto, *Dawn of Kin* organiza suas entregas em quatro horizontes:

### 10.1 Os Quatro Horizontes (`DECIDIDO`)
1. **A. Visão Completa do Jogo:** Obra integral abrangendo os Capítulos 1, 2 e 3, linhagem multigeracional, cinco níveis da comunidade, regiões conectadas, quatro vocações plenamente desenvolvidas, sistema de dons e mentoria, comunidades externas, trocas comerciais e guerra contra as forças e seguidores do Ser de Trevas.
2. **B. Demonstração Jogável (Demo):** Experiência curta, polida e representativa contendo o casal controlável, coleta e transporte físico, estoque/alimentação/depósito, construção do primeiro abrigo, ambiente natural legível e — quando o sistema narrativo estiver integrado — a aparição misteriosa do Ser de Trevas após erguer o abrigo. *(Não exige genealogia completa, exércitos ou múltiplas regiões).*
3. **C. Primeiro Lançamento Comercial (Capítulo 1 Completo):** Experiência familiar completa do isolamento: casal e residência, nascimento e crescimento dos filhos (`Bebê → Criança → Jovem`), agricultura (`Roça`), profissões básicas autônomas, construções funcionais (Níveis 1 a 3), economia coletiva, natureza dinâmica (remoção e brotação de árvores), perigos moderados, cura inicial dos líderes (*Alento*), aparição misteriosa do Ser de Trevas e encerramento do Capítulo 1 quando o primeiro filho atinge a juventude (preparando o Capítulo 2).
4. **D. Conteúdo Posterior (Capítulos 2 e 3 / Expansões):** Evolução completa das quatro vocações e canalização avançada da Luz, mentoria avançada de dons, múltiplas regiões simuladas, encontros e casamentos com outras comunidades, comércio inter-comunitário, facções humanas seduzidas e guerras contra as trevas.

### 10.2 Matriz de Correspondência: Etapas Técnicas (`T1`–`T8`) × Entregas Comerciais

*(A estratégia comercial não altera a ordem técnica sequencial `T3.4`–`T8` nem promete datas).*

| Etapa Técnica do Roadmap | Status Técnico Atual (`16/11/2026`) | Demo Jogável (B) | 1º Lançamento — Cap. 1 (C) | Conteúdo Posterior — Cap. 2–3 (D) |
|---|---|---|---|---|
| **T1 — Fundação RTS** | **CONCLUÍDA** (`t1-complete`) | Obrigatória | Obrigatória | Base |
| **T2 — Trabalho e Recursos** | **CONCLUÍDA** (`t2-complete`) | Obrigatória | Obrigatória | Base |
| **T3 — Construção, Depósitos e Save Base** | `T3.1–T3.3` **CONCLUÍDAS** (`t3-3-complete`); `T3.4–T3.9` planejadas | Obrigatória | Obrigatória | Base |
| **T4 — Mundo, Calendário (`12–15m/ano`) e Ecologia** | Planejada | Parcial (ambiente/dia-noite básico) | Obrigatória (região inicial + ecologia + calendário) | Expansão multirregional completa |
| **T5 — Família, Modulares e `JobSystem` Básico** | Planejada | Opcional (casal inicial fixo ou criador) | Obrigatória (`Bebê→Jovem`, criador, profissões básicas) | Genealogia multigeracional e casamentos externos |
| **T6 — Combate, *Alento* e Vocações** | Planejada | Mínimo (perigo pontual opcional) | Escopo Cap. 1 (*Alento*, defesa rústica e ameaças moderadas) | Completo (4 vocações plenas, exércitos e guerras) |
| **T7 — História Cap. 1 e Atmosfera** | Planejada | Aparição misteriosa do Ser de Trevas | Obrigatória (arco completo do Cap. 1 + clima/vento/água) | Eventos sombrios avançados |
| **T8 — Comunidades, Cap. 2–3 e Diplomacia** | Planejada | Não incluída | Gancho final de abertura do Cap. 2 | Obrigatória (encontros, casamentos externos, trocas e facções) |

---

## 11. Arquitetura Técnica e Roadmap (`T1`–`T8`)

- **Stack (`IMPLEMENTADO`):** Godot `4.7.2.stable`, `GDScript` tipado, `gl_compatibility`, `Jolt Physics`.
- **Persistência (`DEC-17`):** O módulo da `T3.8` será construído já como núcleo extensível do `SaveManager` versionado (`schema_version = 1`), evitando retrabalho na `T4`.
- **Bloqueio de Governança da `T3.4`:** A etapa `T3.4` permanece **estritamente bloqueada** até que a revisão técnica **`T3.4-ARCHITECTURE-R2`** seja publicada e aprovada cobrindo: (1) complementação manual transacional de reservas (`DEC-11B`), (2) retentativa após falha de `BuildingInstance`, (3) proteção contra novas obras sobre edifícios concluídos, (4) validação de contribuições no slot, (5) teto inteiro de progresso e (6) testes adicionais de regressão, navegação (`DEC-19`) e contabilidade.

---

## 12. Registro de Decisões, Evoluções Substituídas e Pendências

### 12.1 Registro Compacto de Decisões Substituídas / Evoluídas (Rastreabilidade Histórica)

| Tema | Formulação Anterior (Histórica) | Nova Direção Canônica Consolidada (`DECIDIDO`) | Motivo da Substituição |
|---|---|---|---|
| **Ser de Luz no Cap. 1** | `v1.2_PROPOSAL` previa aparição do Ser de Luz no Cap. 1 fazendo o Ser de Trevas recuar após o abrigo. | **O Ser de Luz não aparece no Capítulo 1**; existe apenas a aparição única e silenciosa do Ser de Trevas à distância (*"Saudações, visitantes... O dia se aproxima."*). | Preservar o mistério e a tensão contida do isolamento no Capítulo 1. |
| **Origem de Habilidades** | `v1.2_PROPOSAL` previa cena de concessão explícita de bênção/poderes após o abrigo. | **Sistema de Dons Latentes:** os dons já existem em potencial nas pessoas e os líderes ajudam a despertá-los por treino e mentoria; líderes começam com *Alento* latente. | Evitar distribuição mágica artificial de classes e valorizar evolução orgânica. |
| **Gatilho do Nível 2** | `v1.2_PROPOSAL` condicionava o Nível 2 à bênção visível do Ser de Luz. | **Marcos concretos de desenvolvimento** (abrigo, depósito e sustento inicial estabilizados). | Independência mecânica e coerência com a ausência do Ser de Luz no Cap. 1. |
| **Vocações de Combate** | Apresentadas como classes prontas desde cedo. | **Separação entre Profissão, Vocação e Dom**, com especialização gradual conforme maturidade e estrutura da vila. | Evitar exigir exército no isolamento familiar do Capítulo 1. |
| **Reposição de Reserva Deteriorada** | Auditoria inicial do Argon sugeria reposição automática pelo trabalhador da obra. | **Autorização manual obrigatória no canteiro (`DEC-11B`)**, usando saldo livre real e transporte físico. | Ratificação expressa do proprietário preservando controle sobre o estoque livre. |
| **Deterioração da Pedra** | `GDD v1.0` (§5) listava pedra entre os materiais sujeitos a desgaste no chão. | **Pedra bruta exposta não deteriora (`DEC-11A`)**, mantendo `decay_stone_provisional.tres` (`can_decay = false`). | Ratificação expressa do proprietário alinhando design e código. |
| **Economia Salarial** | `GDD v1.1` (§5) continha `PROPOSTA FUTURA` de salários e compra interna de roupas. | **Economia 100% cooperativa sem salário interno (`DEC-12`)**; trocas ocorrem entre comunidades no Cap. 3. | Coerência com o núcleo familiar e contenção de escopo. |

### 12.2 Tabela de Decisões Ativas (`D1`–`D9` e `DEC-01`–`DEC-19`)

| ID | Regra Consolidada Vigente | Status | Seção |
|---|---|---|---|
| **D1–D9** | Persistência T3 (D1), transporte físico (D2), reembolso `0,50` (D3), custos provisórios Abrigo/Depósito (D4), depósitos T3 (D5), exclusão `CampStorageZone` (D6), UI Construir (D7), itens no mundo (D8), equipe 1/2/3/4 (D9) e Alternativa B | `DECIDIDO` (`T3.1–T3.3` `IMPLEMENTADO/VALIDADO`) | §4 |
| **DEC-01** | Calendário `1 ano ≈ 12–15 min` em `1×` (`~2,5–3h` após nascimento até Jovem 12 anos); validar ritmo em testes | `DECIDIDO` | §3.3 |
| **DEC-02** | Bloqueio até primos de 1º grau + casamentos com jovens de comunidades vizinhas nos Cap. 2–3 | `DECIDIDO` | §2.2, §3.4 |
| **DEC-03** | Abrigo Básico inicia família; nascimento exige vaga de dependente + comida estável + intervalo progressivo | `DECIDIDO` | §3.4 |
| **DEC-04** | Limites RTS por idade (`Bebê`/`Criança`/`Jovem`/`Adulto`) e regra de viuvez/acolhimento | `DECIDIDO` | §3.3, §3.4 |
| **DEC-05** | Cosmologia de bastidores (Ser de Luz / Ser de Trevas) + animais normais e animais corrompidos irradiando trevas | `DECIDIDO` | §2.1, §8.1 |
| **DEC-06** | Revisada: única aparição pessoal do Ser de Trevas no Cap. 1 após o abrigo (sem Ser de Luz); despertar gradual de Dons Latentes e 4 vocações | `DECIDIDO (REVISADO)` | §2.2, §5 |
| **DEC-07** | Grupo humano seduzido pela Sombra (Cap. 3) + proteção pós-derrota dos Líderes distinta da cura comum (*Alento*) | `DECIDIDO (REVISADO)` | §2.2, §5.3, §8 |
| **DEC-08** | Modelo Híbrido RTS + Autonomia por Profissão (`JobSystem`) e busca automática da próxima fonte | `DECIDIDO` | §1.2, §5.1 |
| **DEC-09** | Árvores e pedras em `0` somem 100% (`queue_free()`); brotação em solo livre; caminhos bloqueiam vegetação | `DECIDIDO` | §7.2 |
| **DEC-10** | Arbustos regeneram frutas mas podem ser arrancados ao construir; Roças contínuas | `DECIDIDO` | §7.2 |
| **DEC-11A** | Pedra bruta exposta não sofre deterioração temporal (`can_decay = false`) | `DECIDIDO (RATIFICADO)` | §4.2 |
| **DEC-11B** | Complemento de reserva deteriorada exige autorização manual no canteiro + saldo livre + transporte físico | `DECIDIDO (RATIFICADO)` | §4.2 |
| **DEC-12** | Economia cooperativa sem salários internos; roupas/armas pelo estoque coletivo; trocas entre vilas no Cap. 3 | `DECIDIDO` | §4.4 |
| **DEC-13** | Revisada: Níveis 1–5 por marcos concretos de desenvolvimento (sem aparição do Ser de Luz) | `DECIDIDO (REVISADO)` | §6 |
| **DEC-14** | Regiões `256–384 m` conectadas por passagens + simulação leve da Vila em expedições | `DECIDIDO` | §7.1 |
| **DEC-15** | Formação RTS automática + suporte autônomo + comandos especiais nos Líderes (aplicáveis na progressão posterior) | `DECIDIDO` | §8.2 |
| **DEC-16** | Nome + Sobrenome da Linhagem + personagens modulares em Esqueleto Único (`~1.5k–3.5k` triângulos = `PROPOSTA`) | `DECIDIDO` / `PROPOSTA` | §3.1, §3.2, §9 |
| **DEC-17** | `SaveManager` extensível desde a T3.8 + adoção deste GDD único (`docs/Dawn_of_Kin_GDD.md`) | `DECIDIDO` | §11 |
| **DEC-18** | T3.4: montagem com suprimento parcial (2–3 trab.) e trabalhador solitário transporta reservados antes de montar | `DECIDIDO` *(impl. sujeita a `T3.4-R2`)* | §4.3 |
| **DEC-19** | T3.4: diretriz N1 de inclusão regional de edifícios no `WorldNavigation` | `DECIDIDO (planejamento)` | §4.3, §11 |

### 12.3 Pendências Abertas (`ABERTO` e `PENDENTE DE APROVAÇÃO`)
- **`PENDENTE DE APROVAÇÃO` (`T3.4-ARCHITECTURE-R2`):** As 6 especificações técnicas obrigatórias da §11 antes de autorizar código da T3.4.
- **`ABERTO` (Marca):** Verificação comercial/jurídica de *Dawn of Kin*.
- **`ABERTO` (Narrativa e Mistério):** Cosmologia última da versão da Terra, momento/forma de eventual revelação futura do Ser de Luz, texto definitivo da fala do Ser de Trevas no Cap. 1 e regras de diplomacia do Cap. 3.
- **`ABERTO` (Balanceamento e Performance):** Recalibração empírica do calendário em sessões de teste, custo/recarga do *Alento*, taxas de regeneração ecológica, vagas por casa, curva de natalidade, números de combate e medição real de regiões `256–384 m` e modelos modulares na **Intel UHD Graphics 620**.
