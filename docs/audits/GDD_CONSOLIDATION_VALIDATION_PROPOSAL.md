# DAWN OF KIN — MATRIZ DE VALIDAÇÃO DA CONSOLIDAÇÃO DO GDD (v1.0 + v1.1 + AUDITORIA R1 → v1.2 PROPOSAL)

**Documento:** Matriz de Auditoria e Rastreabilidade para Consolidação Normativa (`PROPOSAL`)
**Repositório:** `https://github.com/Julian0s/Dawn-of-Kin`
**Base Oficial (`main`):** `3c6fc0bd36fc3828af5a89662fb23cfb60d37865` (Tag `t3-3-complete`)
**Auditoria Global R1:** Branch `audit/global-vision-and-design`, commit `23fd493174e73e80599c13cef8a824314196a731`
**Planejamento T3.4-R1:** Branch `planning/t3-4-architecture`, commit `6ac2c5102e71623224dbd5f1e69bedd0d90bfc45`
**Branch Candidata:** `docs/global-vision-gdd-candidate`
**Worktree Isolado:** `C:\Projetos\Dawn_of_Kin_wt_gdd_candidate`
**Data:** 16 de novembro de 2026

> **Regra de Governança:** Este documento serve exclusivamente como guia verificável para a auditoria independente do ChatGPT sobre [`docs/Dawn_of_Kin_GDD_v1.2_PROPOSAL.md`](../Dawn_of_Kin_GDD_v1.2_PROPOSAL.md). **Nenhum arquivo normativo ou histórico existente foi modificado.** A promoção da `v1.2_PROPOSAL` e as atualizações dos documentos antigos só ocorrerão após aprovação expressa do proprietário em tarefa posterior dedicada.

---

## 1. Comparação Seção por Seção (`v1.0` vs. `v1.1` vs. `v1.2 PROPOSAL`)

| Tema / Conteúdo | `Dawn_of_Kin_GDD_v1.0.md` (Normativo Vigente) | `Dawn_of_Kin_GDD_v1.1.md` (Minuta Não Promovida) | `Dawn_of_Kin_GDD_v1.2_PROPOSAL.md` (Candidata Consolidada) |
|---|---|---|---|
| **Cabeçalho e Status Real do Projeto** | Registra T1, T2, T3.1–T3.2 na `main` e T3.3 ainda fora da `main`. | Contradição interna: L9/15 diz T2 aprovada; §13 L337 diz T2 pendente; omite T3.3. | Sincroniza o estado real verificado (`main` `3c6fc0b`, `t1-complete`, `t2-complete`, `t3-3-complete`, T3.4 bloqueada em `R1` aguardando `R2`). |
| **Identidade e Pilares** | §1 (Gênero, câmera, ritmo, diferencial familiar). | §1 (Mesmo conteúdo de `v1.0`). | **§1:** Preserva `v1.0` integralmente e formaliza os **5 Pilares** consolidados na Auditoria R1. |
| **História e Universo** | §2 e §3 (3ª Guerra, buraco de minhoca, Cap. 1–3, cosmologia e ameaça sombria `ABERTO`). | §2 e §3 (Mesmo conteúdo de `v1.0` + roupa rasgada como convenção visual não equipável). | **§2:** Preserva *"uma versão da Terra"* e mistérios cosmológicos `ABERTO`; incorpora `DEC-05`, `DEC-06` e `DEC-07` (Ser de Luz, Ser de Trevas, animais corrompidos, Evento Fundador do Cap. 1 e humanos seduzidos no Cap. 3). |
| **Família, Modulares e Nomes** | §7 (Fases, casais, nascimentos em teste, população sem limite artificial). | §7.1–7.5 (Criador inicial, peças modulares, cores hereditárias, herança visual, `NameService`). | **§3:** Incorpora §7.1–7.5 da `v1.1` + `DEC-01` a `DEC-04` e `DEC-16` (Sobrenome da Linhagem, limites RTS por idade, gatilho de nascimento no Abrigo/Casas, bloqueio até primos de 1º grau, viuvez). |
| **Trabalho, Economia e Construção** | §4, §5, §6 (Coleta física, deterioração geral incluindo pedra, `v1.0` sem D1–D9 detalhados). | §4, §5, §6 (Inclui `PROPOSTA FUTURA` de economia salarial/compra de roupas). | **§4:** Incorpora `D1–D9`, `DEC-08` (RTS + `JobSystem`), `DEC-11A` (pedra não deteriora), `DEC-11B` (reposição manual com transporte físico), `DEC-12` (economia cooperativa sem salários) e `DEC-18`/`DEC-19`. |
| **Evolução (Níveis 1–5)** | §6 Tabela `PROPOSTA` (Depósito apenas no Nível 2). | §6 Tabela `PROPOSTA` (idêntica à `v1.0`). | **§5:** Nova tabela Níveis 1–5 por marcos reais (`DEC-13`), colocando Depósito Rústico no Nível 1 e integrando Bênção da Luz + 4 vocações. |
| **Mundo e Ecologia** | §9 (Regiões conectadas, tamanho `ABERTO`, fontes finitas sem regra de remoção visual). | §9 (Idêntica à `v1.0`). | **§6:** Regiões `256–384 m` com simulação leve em 2º plano (`DEC-14`), remoção 100% de árvores/pedras em `0` (`DEC-09`), brotação livre, arbustos arrancáveis, roças e caminhos (`DEC-10`). |
| **Combate e Ameaças** | §8 (Líderes protegidos, mortalidade comum, 3 armas, arsenal compartilhado). | §8 (Arsenal compartilhado + atribuição por profissão/manual). | **§7:** Preserva §8 + incorpora as 4 vocações (Guerreiro, Arqueiro, Curandeiro, Mago da Luz), formação automática, skills de comando dos Líderes (`DEC-15`) e resgate pela Luz (`DEC-07`). |
| **Interface e Arte** | §4, §10 (3D estilizado naturalista, sem contornos grossos). | §10 (Preserva legibilidade com peças modulares). | **§8:** Preserva §10 + `Edge Scroll` na borda real (`6 px` base), UI `D7` (T3.5) e hipótese `PROPOSTA` de `~1.5k–3.5k` triângulos (`DEC-16`). |
| **Calendário** | §11 (`1 ano ≈ 50 min` em `1×`, ~10h até 12 anos). | §11 (Idêntica à `v1.0`). | **§3.3:** Calendário calibrado `1 ano ≈ 12–15 min` em `1×` (`~2,5–3h` após nascimento até Jovem — `DEC-01`). |
| **Arquitetura, Roadmap e Decisões** | §12–§16 (T1–T8, pendências). | §12–§16 (Inclui `CharacterAppearance`, `NameService`, `SaveManager` e marco aberto salarial). | **§9 e §10:** Separa `IMPLEMENTADO` vs. `PROPOSTA`, adota `SaveManager` extensível desde T3.8 (`DEC-17`), atualiza roadmap T1–T8 e lista `D1–D9` + `DEC-01`–`DEC-19` + `ABERTO`. |

---

## 2. Matriz `DEC-01`–`DEC-19` com Rastreabilidade

| ID | Síntese | Origem Verificada | Status na `v1.2 PROPOSAL` | Seção na `v1.2 PROPOSAL` |
|---|---|---|---|---|
| **DEC-01** | `1 ano ≈ 12–15 min` (`1×`), `~2,5–3h` após nascimento até Jovem | Entrevista `/grill-me` (16/11/2026, P1) | `DECIDIDO` | §2.2, §3.3, §10.1 |
| **DEC-02** | Bloqueio até primos de 1º grau + parceiros de comunidades vizinhas | Entrevista `/grill-me` (16/11/2026, P2) | `DECIDIDO` | §2.2, §3.4, §10.1 |
| **DEC-03** | Abrigo Básico inicia família; vaga + comida + intervalo progressivo | Entrevista `/grill-me` (16/11/2026, P3) | `DECIDIDO` | §3.4, §10.1 |
| **DEC-04** | Limites RTS por idade (Bebê/Criança/Jovem/Adulto) + viuvez/acolhimento | Entrevista `/grill-me` (16/11/2026, P4) | `DECIDIDO` | §3.3, §3.4, §10.1 |
| **DEC-05** | Ser de Luz vs. Ser de Trevas ancestral sem nome + fauna corrompida | Entrevista `/grill-me` (16/11/2026, P5 — texto autoral) | `DECIDIDO` | §2.1, §7.1, §10.1 |
| **DEC-06** | Evento fundador após Abrigo Básico no Cap. 1 + Bênção (Sabedoria/Luz) | Entrevista `/grill-me` (16/11/2026, P6) | `DECIDIDO` | §2.2, §5, §7.2, §10.1 |
| **DEC-07** | Grupo humano seduzido pela Sombra (Cap. 3) + resgate dos Líderes pela Luz | Entrevista `/grill-me` (16/11/2026, P7 + texto autoral) | `DECIDIDO` | §2.2, §7.1, §7.3, §10.1 |
| **DEC-08** | Modelo Híbrido RTS + Autonomia por Profissão (`JobSystem`) | Entrevista `/grill-me` (16/11/2026, P8) | `DECIDIDO` | §1.2, §4.4, §10.1 |
| **DEC-09** | Árvore/Pedra em `0` somem 100% (`queue_free()`); brotação livre; caminhos | Entrevista `/grill-me` (16/11/2026, P9 + diretriz autoral) | `DECIDIDO` | §6.2, §9.3, §10.1 |
| **DEC-10** | Arbusto regenera frutas mas pode ser arrancado; Roça contínua | Entrevista `/grill-me` (16/11/2026, P11) | `DECIDIDO` | §6.2, §10.1 |
| **DEC-11A** | Pedra bruta exposta não sofre deterioração (`can_decay = false`) | **Ratificação expressa** (16/11/2026, item 4) | `DECIDIDO (RATIFICADO)` | §4.2, §10.1 |
| **DEC-11B** | Reposição de reserva deteriorada exige autorização manual no canteiro + transporte físico | **Ratificação expressa** (16/11/2026, item 4) | `DECIDIDO (RATIFICADO)` | §4.2, §8.1, §10.1 |
| **DEC-12** | Economia cooperativa sem salário interno; trocas entre vilas no Cap. 3 | Entrevista `/grill-me` (16/11/2026, P12) | `DECIDIDO` | §1.2, §4.4, §10.1 |
| **DEC-13** | Escada Níveis 1–5 por marcos reais (sem XP nem teto populacional) | Entrevista `/grill-me` (16/11/2026, P13) | `DECIDIDO` | §5, §10.1 |
| **DEC-14** | Regiões `256×256 m`–`384×384 m` + simulação leve da Vila em expedições | Entrevista `/grill-me` (16/11/2026, P14) | `DECIDIDO` | §6.1, §9.2, §10.1 |
| **DEC-15** | Formação RTS automática + suporte autônomo + comandos especiais nos Líderes | Entrevista `/grill-me` (16/11/2026, P15 + texto autoral) | `DECIDIDO` | §7.2, §10.1 |
| **DEC-16** | Nome + Sobrenome da Linhagem; Esqueleto Único (`~1.5k–3.5k` = `PROPOSTA`) | Entrevista `/grill-me` (16/11/2026, P16) | `DECIDIDO` *(orçamento = `PROPOSTA`)* | §3.1, §3.2, §8.2, §10.1 |
| **DEC-17** | `SaveManager` extensível desde T3.8 + unificação futura do GDD | Entrevista `/grill-me` (16/11/2026, P17) | `DECIDIDO` | §9.1, §9.3, §10.1 |
| **DEC-18** | T3.4: montagem parcial (2–3 trab.) e solitário transporta reservados antes de montar | Diretriz pré-entrevista (preparação T3.4) | `DECIDIDO` *(impl. sujeita a `T3.4-R2`)* | §4.3, §10.1 |
| **DEC-19** | T3.4: diretriz N1 de registro regional de edifícios no `WorldNavigation` | Seleção preliminar de planejamento T3.4 | `DECIDIDO (planejamento)` | §4.3, §10.1 |

---

## 3. Alterações Resultantes Especificamente da Ratificação `DEC-11`

1. **`DEC-11A` (Deterioração da Pedra):**
   - Corrigida a formulação herdada da `v1.0` (§5 L71) e `v1.1` (§5 L91) que incluía pedra entre os materiais sujeitos a desgaste temporal no chão.
   - A `v1.2 PROPOSAL` (§4.2) registra expressamente que **Alimentos e Madeira** deterioram quando expostos, **Pedra bruta não sofre deterioração temporal** (preservando `data/resources/decay_stone_provisional.tres` com `can_decay = false`), e futuras categorias não herdam desgaste automaticamente.
2. **`DEC-11B` (Reposição Manual de Reservas Deterioradas):**
   - **Substituída** a recomendação anterior de reposição automática pelo trabalhador da obra (constante da `GLOBAL-VISION-AUDIT` inicial).
   - A `v1.2 PROPOSAL` (§4.2 e §10.1) determina que perdas em pilhas reduzem diretamente a reserva (Alternativa B, sem realocação automática), o canteiro preserva progresso e materiais já recebidos/incorporados, e **qualquer complemento de reserva deteriorada exige autorização manual expressa do jogador no canteiro**, reservando somente em saldo livre real (sem tocar reservas de outras obras) e mantendo transporte físico obrigatório sem crédito instantâneo.
   - A UI definitiva permanece na `T3.5`; eventual fluxo provisório na `T3.4` fica explicitamente remetido à revisão `T3.4-ARCHITECTURE-R2`.

---

## 4. Conteúdo Aprovado de `v1.1` Incorporado

- **§2 (Travessia e Vestuário Inicial):** Roupas rasgadas iniciais registradas como convenção visual de apresentação/classificação etária, não itens equipáveis trazidos da Terra.
- **§5 (Vestuário Comunitário):** Produção comunitária de roupas com substituição simples dos trapos iniciais.
- **§7.1–7.5 (Personagens Modulares, Herança Visual e Nomes Persistentes):** Criação personalizável do casal inicial (rosto, cabelo, olhos, pele, botão Randomizar), peças 3D modulares com padronização técnica obrigatória para Godot, paleta natural + cores hereditárias, herança visual probabilística entre fases e serviço `Identity/NameService` com IDs estáveis e prevenção de repetições entre irmãos.
- **§8 (Arsenal Compartilhado por Profissão):** Atribuição automática simples de ferramentas/armas conforme profissão (com opção manual), sem slots complexos de MMORPG.
- **§12 (Arquitetura e Desempenho):** Adição de `Units/CharacterAppearance` e `Identity/NameService`, e registro da medição T2 em tomada CA vs. bateria DC na Intel UHD 620.

---

## 5. Conteúdo de `v1.1` Deliberadamente NÃO Incorporado

1. **Economia Pessoal / Salários e Compra de Roupas (`v1.1` §5 L110–121, §13 L344, §15 L370):** Descartada expressamente por `[DEC-12]` (economia interna permanece 100% cooperativa sem salários/moeda entre familiares; comércio ocorre por trocas entre comunidades no Capítulo 3).
2. **Contradição de Status da T2 (`v1.1` §13 L337):** Texto que ainda classificava a T2 como *"Candidata a encerramento... aceite formal do marco ainda pendente"* foi descartado por conflitar com o termo `T2_Closeout_ACCEPTANCE.md` e o cabeçalho da própria `v1.1`.
3. **Propostas Não Ratificadas como Normas:** Estimativas de orçamento de polígonos ou otimizações futuras (ex.: hibernação de RVO) não foram promovidas a `DECIDIDO`, mantendo-se como `PROPOSTA`.

---

## 6. Inconsistências Resolvidas na Candidata `v1.2 PROPOSAL`

- **INC-01 (Fontes esgotadas):** Regra definitiva de remoção 100% (`queue_free()`) para árvores/pedras em `0` definida em §6.2 (`DEC-09`) e mapeada na T4 (§9.3).
- **INC-03 (Pedra exposta):** Conflito entre texto normativo e `decay_stone_provisional.tres` resolvido por `DEC-11A` (§4.2).
- **INC-06 e INC-07 (Status Git na `v1.0`/`v1.1`):** Cabeçalhos e roadmap da `v1.2 PROPOSAL` alinhados ao estado real de `origin/main` (`3c6fc0b`, `t3-3-complete`).
- **BAL-01 (Ritmo do Capítulo 1):** Descompasso dos `50 min/ano` resolvido pelo calendário compacto de `12–15 min/ano` (`DEC-01` — §3.3).
- **PLAN-01 (Depósito Rústico na Escada de Níveis):** Reconciliado no Nível 1 da §5 (`DEC-13`).

---

## 7. Questões que Continuam Abertas (`ABERTO` / `PENDENTE DE APROVAÇÃO`)

1. **`PENDENTE DE APROVAÇÃO` (`T3.4-ARCHITECTURE-R2`):** As 6 exigências técnicas pendentes da T3.4 (detalhadas na Seção 9 abaixo).
2. **`ABERTO` (Marca):** Pesquisa jurídica/comercial de *Dawn of Kin*.
3. **`ABERTO` (Cosmologia e Mistério):** Natureza exata da versão da Terra/travessia, identidade última do Ser de Luz, nome/origem do Ser de Trevas e apresentação visual final do evento fundador.
4. **`ABERTO` (Família e Nomes):** Intensidade numérica da herança visual, vagas exatas por casa, curva do intervalo entre nascimentos, nomes compostos e sobrenomes regionais.
5. **`ABERTO` (Economia, Ecologia e Combate):** Tempos exatos de brotação de árvores e regeneração de arbustos, receitas de vestuário/ferramentas, regras exatas de troca entre comunidades no Cap. 3, HP/dano/alcance/cooldowns de combate e duração da exaustão dos Líderes.
6. **`ABERTO` (Desempenho Empírico):** Medição real de mapas `256–384 m`, shaders de corrupção e personagens modulares na **Intel UHD Graphics 620**.

---

## 8. Alterações Futuras Previstas para Documentos Existentes (NÃO Executadas Agora)

Somente após aprovação formal desta consolidação pelo proprietário em tarefa posterior dedicada:

1. **`AGENTS.md` (Linha 6):** Atualizar o trecho que ainda descreve a T3.3 como não integrada à `main` e sem tag para refletir `origin/main` em `3c6fc0b` (`t3-3-complete`), e apontar o novo GDD normativo unificado como fonte de verdade (mantendo `T3.4+` bloqueadas).
2. **`README.md` (Linha 8):** Atualizar estado da T3.3 para integrada à `main` (`t3-3-complete`) e atualizar referência ao GDD normativo unificado.
3. **`docs/architecture/T3_architecture_PROPOSAL.md` (§1 D8 L51 e Cabeçalho L3):** Atualizar cabeçalho para refletir `t3-3-complete` na `main` e alinhar a nota de deterioração da pedra à `DEC-11A` (preservando `D1–D9` e a Alternativa B).
4. **Termos de Aceite Históricos (`docs/reviews/T2_Closeout_ACCEPTANCE.md`, `docs/testing/T3_3_closeout_ACCEPTANCE.md`):** **Preservar integralmente** os textos originais como registro histórico imutável; caso necessário, adicionar apenas um bloco breve de *Atualização Posterior de Estado* ao final indicando a data de integração na `main` e a tag criada, **nunca** apagando a evidência original.
5. **GDDs Anteriores (`v1.0` e `v1.1`):** Arquivar/substituir normativamente apenas quando o proprietário promover formalmente o novo GDD consolidado.

---

## 9. Compatibilidade com o Plano `T3.4-R1` e Pendências da Futura `T3.4-R2`

A `v1.2 PROPOSAL` é **100% compatível** com a revisão `T3.4-ARCHITECTURE-R1` (`6ac2c51`), mas a implementação da T3.4 **continua bloqueada** até a publicação e auditoria da revisão **`T3.4-ARCHITECTURE-R2`**, que deverá fechar obrigatoriamente:
1. **Complementação transacional manual de reservas (`DEC-11B`):** fluxo exato de autorização manual no canteiro (provisório na T3.4 vs. UI definitiva na T3.5), validação de saldo livre, reserva atômica e transporte físico sem crédito instantâneo.
2. **Retentativa de conclusão após falha de `BuildingInstance`:** protocolo de recuperação caso a instanciação ou validação do edifício falhe.
3. **Proteção contra novas obras sobre edifícios concluídos:** garantia de que `PlacementValidator` / `ConstructionManager` bloqueiem sobreposição contra `BuildingInstance` já existentes.
4. **Validação contínua das contribuições dos trabalhadores:** checagem de alcance, slot válido e estado do trabalhador durante `BUILDER_ASSEMBLING`.
5. **Teto de progresso com materiais inteiros:** impedimento estrito de atingir 100% sem incorporação física de 100% dos materiais requeridos.
6. **Testes adicionais obrigatórios:** suítes automatizadas e manuais cobrindo regressão contábil, navegação com `BuildingInstance` na NavMesh regional (`DEC-19`) e falhas de conclusão.

---

## 10. Checklist de Revisão Antes de Qualquer Promoção Normativa

- [ ] Auditoria independente do ChatGPT concluída sobre `docs/Dawn_of_Kin_GDD_v1.2_PROPOSAL.md` e esta matriz.
- [ ] Conferência de que todas as 19 decisões (`DEC-01`–`DEC-19`), `DEC-11A`/`DEC-11B` e `D1–D9` estão consistentes sem contradições internas.
- [ ] Confirmação de que nenhuma proposta (`PROPOSTA`) ou questão aberta (`ABERTO`) foi promovida silenciosamente a `DECIDIDO`.
- [ ] Autorização expressa do proprietário em novo prompt dedicado para promover o GDD consolidado e sincronizar `AGENTS.md`, `README.md` e `T3_architecture_PROPOSAL.md`.
- [ ] Publicação e auditoria separada da `T3.4-ARCHITECTURE-R2` antes de qualquer autorização de código da T3.4.
