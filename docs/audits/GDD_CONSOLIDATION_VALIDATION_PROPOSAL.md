# DAWN OF KIN — MATRIZ DE VALIDAÇÃO DA CONSOLIDAÇÃO DEFINITIVA DO GDD ÚNICO (`docs/Dawn_of_Kin_GDD.md`)

**Documento:** Matriz de Auditoria e Rastreabilidade da Migração para GDD Único (`v1.2 RC — Aguardando Aprovação`)
**Repositório:** `https://github.com/Julian0s/Dawn-of-Kin`
**Base Oficial (`main`):** `3c6fc0bd36fc3828af5a89662fb23cfb60d37865` (Tag `t3-3-complete`)
**Auditoria Global R1:** `audit/global-vision-and-design` (`23fd493174e73e80599c13cef8a824314196a731`)
**Candidata Anterior:** `docs/global-vision-gdd-candidate` (`05ca3467c325082b16d9c71b35febb894c6b34d2`)
**Branch de Revisão Canônica:** `docs/gdd-canonical-review`
**Worktree Isolado:** `C:\Projetos\Dawn_of_Kin_wt_gdd_canonical`
**Data:** 16 de novembro de 2026

> **Regra de Governança:** Por determinação expressa do proprietário, esta branch unifica todo o Game Design em **um único documento ativo**: [`docs/Dawn_of_Kin_GDD.md`](../Dawn_of_Kin_GDD.md) (identificado internamente como **v1.2 RC — Aguardando Aprovação**). Os arquivos concorrentes `Dawn_of_Kin_GDD_v1.0.md`, `Dawn_of_Kin_GDD_v1.1.md` e `Dawn_of_Kin_GDD_v1.2_PROPOSAL.md` foram removidos da árvore ativa via `git rm` (permanecendo integralmente recuperáveis pelo histórico Git em `3c6fc0b` e `05ca346`). A `main` permanece intocada até auditoria do ChatGPT e autorização final do proprietário.

---

## 1. Justificativa e Topologia da Migração para GDD Único

| Arquivo Anterior | Destino na Branch `docs/gdd-canonical-review` | Referência Permanente no Git |
|---|---|---|
| `docs/Dawn_of_Kin_GDD_v1.0.md` | Removido via `git rm`; todo conteúdo válido migrado para [`docs/Dawn_of_Kin_GDD.md`](../Dawn_of_Kin_GDD.md). | [Commit `3c6fc0b` (`main`)](https://github.com/Julian0s/Dawn-of-Kin/blob/3c6fc0bd36fc3828af5a89662fb23cfb60d37865/docs/Dawn_of_Kin_GDD_v1.0.md) |
| `docs/Dawn_of_Kin_GDD_v1.1.md` | Removido via `git rm`; decisões aprovadas (§7.1–7.5, §8) migradas para [`docs/Dawn_of_Kin_GDD.md`](../Dawn_of_Kin_GDD.md). | [Commit `3c6fc0b` (`main`)](https://github.com/Julian0s/Dawn-of-Kin/blob/3c6fc0bd36fc3828af5a89662fb23cfb60d37865/docs/Dawn_of_Kin_GDD_v1.1.md) |
| `docs/Dawn_of_Kin_GDD_v1.2_PROPOSAL.md` | Removido via `git rm`; evoluído diretamente para [`docs/Dawn_of_Kin_GDD.md`](../Dawn_of_Kin_GDD.md). | [Commit `05ca346`](https://github.com/Julian0s/Dawn-of-Kin/blob/05ca3467c325082b16d9c71b35febb894c6b34d2/docs/Dawn_of_Kin_GDD_v1.2_PROPOSAL.md) |
| `docs/audits/DAWN_OF_KIN_GLOBAL_VISION_AUDIT_PROPOSAL.md` | Preservado fielmente como registro histórico de auditoria (não é GDD), inclusive onde decisões originais foram posteriormente substituídas; apenas cabeçalho de status e links aos GDDs antigos foram adaptados para URLs permanentes do commit `3c6fc0b` na importação, mantendo intacto o conteúdo e as decisões originais. | [Commit `23fd493`](https://github.com/Julian0s/Dawn-of-Kin/blob/23fd493174e73e80599c13cef8a824314196a731/docs/audits/DAWN_OF_KIN_GLOBAL_VISION_AUDIT_PROPOSAL.md) |

---

## 2. O Que Foi Mantido, Substituído e Descartado da Proposta do Argon

### 2.1 Ideias e Decisões do Argon Integralmente Preservadas
- **DEC-01:** Calendário compacto (`1 ano ≈ 12–15 min` em `1×`, `~2,5–3h` após o nascimento até Jovem 12 anos).
- **DEC-02 a DEC-04:** Bloqueio de consanguinidade até primos de 1º grau; o Capítulo 2 é desbloqueado quando pelo menos um filho atinge 12 anos (fase Jovem), porém **somente Adultos (`18+ anos`) podem casar** (nunca casamento de menores), respeitando afinidade autônoma persistente, parentesco, residência e demais regras aprovadas ao formar casais no Capítulo 3 (inclusive com adultos oriundos de comunidades vizinhas); Abrigo Básico habilitando início da família, nascimento autônomo (vaga de dependente + estabilidade alimentar + intervalo progressivo), limites RTS por idade (`Bebê`/`Criança`/`Jovem`/`Adulto`) e regras de viuvez/acolhimento.
- **DEC-05 (Cosmologia de Bastidores e Fauna Corrompida):** Existência de bastidores do Ser de Luz e do Ser de Trevas ancestral sem nome; coexistência entre animais naturais normais e animais corrompidos mais fortes irradiando trevas.
- **DEC-07:** Existência de grupo humano seduzido pelo Ser de Trevas causando guerras futuras no Cap. 3 e proteção especial contra morte definitiva dos dois líderes originais.
- **DEC-08 a DEC-10:** Modelo Híbrido RTS + Autonomia por Profissão (`JobSystem`), remoção 100% (`queue_free()`) de árvores e pedras esgotadas em `0`, brotação orgânica em solo livre, caminhos que bloqueiam vegetação, arbustos arrancáveis ao construir e Roças contínuas.
- **DEC-11A e DEC-11B (Ratificadas):** Pedra bruta exposta não deteriora (`can_decay = false`); complementação de reserva deteriorada exige autorização manual no canteiro + saldo livre real + transporte físico sem crédito instantâneo.
- **DEC-12, DEC-14, DEC-15, DEC-16, DEC-17, DEC-18 e DEC-19:** Economia cooperativa sem salários internos; regiões `256–384 m` conectadas com simulação leve em 2º plano; formação automática de combate e comandos especiais dos Líderes; Nome + Sobrenome da Linhagem e **Esqueleto Único por faixa etária** (`DECIDIDO`, mantendo orçamento `~1.5k–3.5k` triângulos e shaders/sockets como `PROPOSTA`); `SaveManager` extensível desde a T3.8; montagem com suprimento parcial / trabalhador solitário (`DEC-18`) e diretriz N1 de navegação regional (`DEC-19`).

### 2.2 Decisões Substituídas pela Nova Direção Narrativa e Mecânica
1. **Substituição da Aparição do Ser de Luz no Capítulo 1:**
   - *Antes (`v1.2_PROPOSAL`):* Após o abrigo, o Ser de Trevas cercava o casal e o Ser de Luz aparecia para fazê-lo recuar e conceder uma bênção explícita.
   - *Agora (`Dawn_of_Kin_GDD.md` §2.2):* **O Ser de Luz não aparece no Capítulo 1.** Após erguer o primeiro abrigo, ocorre uma noite silenciosa em que o **Ser de Trevas** surge à distância, profere breves palavras (ex.: *"Saudações, visitantes... O dia se aproxima."*), não ataca e desaparece — sendo sua **única aparição pessoal direta** nos capítulos planejados.
2. **Substituição da Bênção Explícita pelo Sistema de Dons Latentes e *Alento*:**
   - *Antes:* Poderes e sabedoria entregues em cena pelo Ser de Luz após o primeiro abrigo.
   - *Agora (§5.2 e §5.3):* **Os dons já existem latentes** nas pessoas e os líderes ajudam a despertá-los por treino, experiência e mentoria (sem exclusividade genética e sem obrigatoriedade para todos). Ambos os líderes começam com a cura inicial latente **Alento** (recuperação limitada de ferimentos, distinta da proteção especial que impede a morte definitiva dos líderes em 0 HP).
3. **Substituição da Mistura de Classes pela Tripartição Profissão × Vocação × Dom:**
   - *Antes:* Profissões e classes de combate tratadas num mesmo bloco.
   - *Agora (§5.1):* Separação estrita entre **Profissão** (trabalho cotidiano), **Vocação** (Guerreiro, Arqueiro, Curandeiro, Canalizador da Luz — coexistindo com a profissão, executando 1 tarefa por vez) e **Dom** (capacidade sobrenatural latente).
4. **Substituição do Gatilho do Nível 2:**
   - *Antes:* Condicionado à bênção visível do Ser de Luz.
   - *Agora (§6):* Todos os 5 níveis (Acampamento → Propriedade → Povoado → Aldeia → Vila) avançam por **marcos concretos de desenvolvimento**, sem exigir que o jogador alcance os 5 níveis no Capítulo 1.
5. **Adição da Estratégia de Lançamento em 4 Horizontes (§10):**
   - Separação explícita entre **Visão Completa (A)**, **Demo Jogável (B)**, **1º Lançamento Comercial — Capítulo 1 (C)** e **Conteúdo Posterior — Capítulos 2–3 (D)**, com matriz de correspondência contra `T1`–`T8`.

### 2.3 Conteúdos Deliberadamente Descartados
- Proposta de economia salarial/moeda interna da minuta `v1.1` (§5 L110–121).
- Recomendação inicial do Argon de reposição automática silenciosa de reservas deterioradas (substituída por `DEC-11B`).
- Formulação antiga da `v1.0` de que pedra bruta se deteriora no chão (substituída por `DEC-11A`).
- Contradição interna da `v1.1` (§13 L337) que tratava a T2 como pendente de aceite.

---

## 3. Sincronização das Referências na Branch `docs/gdd-canonical-review`

Todos os documentos ativos da árvore foram atualizados nesta branch para apontar para [`docs/Dawn_of_Kin_GDD.md`](../Dawn_of_Kin_GDD.md) (ou para links permanentes do histórico Git quando se trata de citação histórica em termos de aceite):

1. [`AGENTS.md`](../../AGENTS.md): sincronizado para refletir o status `t3-3-complete` na `main` e explicitar que na `main` o antigo `v1.0` permanece normativo até promoção expressa, enquanto nesta branch `docs/Dawn_of_Kin_GDD.md` (`v1.2 RC`) é o GDD candidato único sob auditoria (sem autorizar `T3.4`).
2. [`README.md`](../../README.md): atualizado o estado da `T3.3` (`t3-3-complete` na `main`), a árvore de arquivos (`Dawn_of_Kin_GDD.md` candidato v1.2 RC nesta branch vs. `v1.0` normativa na `main`), o status do protocolo `T2` (`21/21` aprovados em `14/11/2026`), a coerência da aceitação de desempenho DC (`T2_Closeout_ACCEPTANCE.md`) e o registro `D1`/`DEC-17` da persistência `T3.8`.
3. [`docs/KNOWN_ISSUES.md`](../KNOWN_ISSUES.md) e [`docs/T1_Implementation_Plan.md`](../T1_Implementation_Plan.md): referências atualizadas para `Dawn_of_Kin_GDD.md`.
4. [`docs/architecture/T3_architecture_PROPOSAL.md`](../architecture/T3_architecture_PROPOSAL.md): cabeçalho e roadmap atualizados para `t3-3-complete` (`3c6fc0b`); nota em D8 alinhada à `DEC-11A`; §4.1 corrigida para o comportamento real do `CommandController` (`navigation_not_ready`); exemplos D9 em §5 alinhados a transportador único + até 2 construtores; invariante de save em §7.2/§7.4/§7.5 alinhada a déficit legítimo por decaimento (Alternativa B + `DEC-11B`) e carga interrompida independente de `active_order`.
5. **Registros Históricos (`T2_Closeout_ACCEPTANCE.md`, `T2_Closeout_CANDIDATE.md`, `T3_3_closeout_ACCEPTANCE.md`, `T3_3_closeout_CANDIDATE.md`, `T3_3_technical_notes.md`, `T3_3_UX_technical_notes.md`, `T3_3_R2_plateau_navigation_diagnostic.md`, `DAWN_OF_KIN_GLOBAL_VISION_AUDIT_PROPOSAL.md`):** preservados integralmente em seu conteúdo probatório, convertendo apenas os links dos antigos arquivos removidos para URLs permanentes do commit `3c6fc0bd36fc3828af5a89662fb23cfb60d37865` no GitHub e adicionando adendos datados de contextualização posterior (`16/11/2026`) nos registros aplicáveis da T3.3 sem reescrever os termos originais.

---

## 3B. Correções Aplicadas na Revisão R2 (`R2-A` a `R2-I` + Rastreabilidade)

- **`R2-A` (Câmera e Controles):** Corrigida a §9.1 do GDD único para refletir exatamente os valores verificados em `src/camera/rts_camera_rig.gd` e `rts_camera_rig.tscn` (`fov_degrees = 35.0`, `yaw_degrees = 45.0`, `pitch_degrees = 55.0` aplicado como `-55°`, `edge_pan_margin_base_px = 6.0`), sem overrides em `main.tscn`.
- **`R2-B` (Idade e Casamento):** Eliminada ambiguidade sobre "jovens" no Cap. 3; explicitado que **somente Adultos (`18+ anos`) podem casar**, e que o marco de 12 anos abre apenas o portão do Cap. 2 (sem casamento precoce).
- **`R2-C` (Regras Recuperadas da `v1.1`):** Restauradas integralmente as regras aprovadas da antiga `v1.1` (§7.1–7.5 e §7.7): seleção livre de cores de cabelo/olhos/roupas, paleta natural de pele, os 6 traços herdáveis, afinidade autônoma persistente (não aleatória por dia), nomes externos persistentes, renomeação opcional sem alterar ID e sem reversão automática de nomes definidos manualmente — preservando propostas técnicas (`NameService`, shaders) apenas como `PROPOSTA`.
- **`R2-D` (Calendário):** Explicitado em §3.3 que `1 ano ≈ 12–15 min` (`1×`, velocidades `1×/2×/4×`) e o intervalo de `2,4–3 horas` até 12 anos contam **a partir do nascimento**, além do tempo inicial anterior ao nascimento, com validação empírica pendente (`ABERTO`).
- **`R2-E` (Biologia e Ambiente):** Restaurados na visão completa todos os biomas aprovados de §9 da antiga `v1.0` (florestas, campos, montanhas, rios, praias/mar, fauna/flora terrestre reconhecíveis, variações climáticas e atmosfera), distinguindo-os da primeira região e da demo.
- **`R2-F` (Implementado vs. Planejado):** Explicitado que remoção 100% de árvores/pedras (`DEC-09`), regeneração, agricultura, calendário, famílias, *Alento*, `JobSystem`, dons latentes, 4 vocações, regiões e T3.4 são **PLANEJADOS (NÃO IMPLEMENTADOS)**; distinguidos também os trabalhadores temporários de teste `Worker3` e `Worker4` da população canônica inicial (estritamente os 2 protagonistas).
- **`R2-G` (Demonstração e Lançamento):** Esclarecido que a aparição do Ser de Trevas na Demo é opcional caso o sistema narrativo já esteja pronto (sem bloquear o núcleo sobrevivência/construção), mas obrigatória no 1º Lançamento completo do Cap. 1.
- **`R2-H` (Status Normativo):** Ajustados `AGENTS.md`, `T3_architecture_PROPOSAL.md` e o cabeçalho de `Dawn_of_Kin_GDD.md` deixando claro que na `main` o antigo `v1.0` continua vigente até promoção expressa, enquanto nesta branch `Dawn_of_Kin_GDD.md` (`v1.2 RC`) é o candidato único para auditoria (sem autorizar T3.4).
- **`R2-I` (Registros Históricos):** Adicionados adendos datados (16/11/2026) em `T3_3_technical_notes.md` e `T3_3_closeout_ACCEPTANCE.md` mantendo originais intactos, e registrada a preservação histórica de `DAWN_OF_KIN_GLOBAL_VISION_AUDIT_PROPOSAL.md`.
- **`R2-11` (Rastreabilidade da Direção Criativa):** §12.2 do GDD único agora distingue expressamente escolhas do proprietário, aprovações da entrevista com Argon, ratificações `DEC-11A/B`, diretrizes estruturadas pelo ChatGPT sob delegação do proprietário e hipóteses `PROPOSTA`/`ABERTO`.

---

## 3C. Correções Aplicadas na Revisão R3 (`R3-A` a `R3-H`)

- **`R3-A` (Consumo Alimentar por Habitante):** Restaurada na §4.1 do GDD único a regra de necessidade alimentar periódica por habitante descontada do estoque coletivo compartilhado (sem barras individuais), explicitando que a implementação atual da T2 ainda não executa consumo populacional (`PLANEJADO (NÃO IMPLEMENTADO)`) e mantendo taxas e consequências de escassez como `PROPOSTA` / `ABERTO`.
- **`R3-B` (Casamentos Somente entre Adultos):** Corrigida a §2.1 desta matriz de consolidação para alinhar-se à regra canônica da §3.4 do GDD único (Cap. 2 abre aos 12 anos de um filho, mas somente Adultos `18+` podem casar). Registros históricos da entrevista mantidos sem reescrita.
- **`R3-C` (`DEC-11A` na Arquitetura):** Corrigida a §9.2 de `docs/architecture/T3_architecture_PROPOSAL.md` para remover pedra da lista de deterioração automática e registrar `DEC-11A` e `DEC-11B`, preservando `T3.1–T3.3` e `.tres`.
- **`R3-D` (Retorno Automático na Coleta):** Restaurada explicitamente na §4.1 do GDD único a regra de retorno automático ao atingir `100%` de carga ou não caber `+1` unidade (`UnitCarryLoad.can_fit_one`), confrontada com `gather_resource_order.gd` e distinguindo acampamento inicial (`IMPLEMENTADO` T2) de depósitos/regiões futuros (`PLANEJADO`).
- **`R3-E` (Hereditariedade e Cores):** Refinada a §3.1 do GDD único para deixar explícito que apenas traços biológicos influenciam a hereditariedade (6 traços herdáveis obrigatórios), enquanto a coloração de roupas é personalizável e **não** hereditária.
- **`R3-F` (Pesca e Profissões):** Restauradas na visão completa (§4.1 e §5.1 do GDD único) a **pesca** (e profissão **Pescador**), **caça** e **criação de animais** como atividades/profissões planejadas compatíveis com transporte físico e estoque coletivo, sem antecipar para a Demo.
- **`R3-G` (Limites entre `T3.4`, `T3.5` e `T3.6`):** Registrada na §4.2 e §4.3 do GDD único a separação entre `T3.4-R2` (integridade transacional da complementação), `T3.5` (UI definitiva de inspeção e ação manual) e `T3.6` (cancelamento/reembolso proporcional `D3` com fórmula explícita e $\eta_{\text{demolição}} = 0,50$).
- **`R3-H` (Consistência Editorial):** Ajustado o título da §1 de `T3_architecture_PROPOSAL.md` (explicando D1–D7 iniciais e D8–D9 consolidados em sequência) e reclassificada a **Fogueira** no Nível 1 do GDD (§6) estritamente como estrutura prevista (`PROPOSTA`), removendo afirmação de proteção noturna não fundamentada como decisão aprovada.

---

## 3D. Auditoria Final de Cobertura (Comparação Integral das 7 Fontes)

Comparação realizada entre: (1) `GDD v1.0` (`3c6fc0b`), (2) `GDD v1.1` (`3c6fc0b`), (3) `GDD v1.2 PROPOSAL` (`05ca346`), (4) Auditoria Global R1 (`23fd493`), (5) GDD único R3 (`Dawn_of_Kin_GDD.md`), (6) Código `T1–T3.3` na `main` (`3c6fc0b`) e (7) `T3_architecture_PROPOSAL.md` (`D1–D9`).

| Item / Regra Comparada | Origem Histórica | Classificação na R3 |
|---|---|---|
| Consumo periódico de alimentos por habitante no estoque coletivo (sem barras individuais) | `v1.0` §5 | **Corrigida / Preservada** (restaurada em §4.1 como `DECIDIDO` / `PLANEJADO (NÃO IMPLEMENTADO)`). |
| Retorno automático ao atingir `100%` ou não caber `+1` unidade | `v1.0` §5 + `gather_resource_order.gd` | **Corrigida / Preservada** (restaurada em §4.1 separando T2 implementada de futuro `T3.7`/`T4+`). |
| Pesca, Pescador, Caça e Criação de Animais | `v1.0` §5 e §6 | **Corrigida / Preservada** (restaurada em §4.1 e §5.1 como `PLANEJADO`, sem antecipar para Demo). |
| Biomas completos (florestas, campos, montanhas, rios, praias/mar, clima) | `v1.0` §9 | **Preservada** (§7.2, distinguindo visão completa de Demo/Cap. 1). |
| Seleção livre de cores (cabelo/olhos/roupas) e 6 traços biológicos herdáveis (sem herança de cor de roupa) | `v1.1` §7.3–7.4 | **Corrigida / Preservada** (§3.1 R3-E). |
| Afinidade autônoma persistente, nomes externos persistentes, renomeação sem mudar ID/sem reversão automática | `v1.1` §7.5 e §7.7 | **Preservada** (§3.2 e §3.4). |
| Serviço `Identity/NameService` e shaders/orçamento `~1.5k–3.5k` triângulos | `v1.1` §7.5 e `DEC-16` | **Proposta não aprovada** (mantidos explicitamente como `PROPOSTA` / hipótese técnica). |
| Economia pessoal / salários e compra de roupas | `v1.1` §5 | **Substituída expressamente** por economia cooperativa (`DEC-12`). |
| Aparição e bênção visível do Ser de Luz no Cap. 1 e desbloqueio do Nível 2 pela bênção | `v1.2 PROPOSAL` / Auditoria R1 | **Substituída expressamente** (ausência do Ser de Luz no Cap. 1; Dons Latentes; marcos concretos para Níveis 1–5). |
| Reposição automática de reservas deterioradas | Auditoria inicial do Argon | **Substituída expressamente** por complementação manual (`DEC-11B`). |
| Deterioração de pedra bruta no chão | `v1.0` §5 e `T3_arch` §9.2 | **Corrigida / Substituída expressamente** por `DEC-11A` (`can_decay = false`). |
| Função defensiva noturna da Fogueira no Nível 1 | Nenhuma decisão aprovada (`v1.0` §6 listava apenas "fogueira") | **Proposta não aprovada** (corrigida em §6 como `PROPOSTA` de acampamento, sem inventar efeito). |
| Casamento de menores / ambiguidade "jovens" no Cap. 3 | R2 anterior / matriz | **Corrigida** (§2.2, §3.4 e §2.1 desta matriz: somente `18+` casam). |
| Câmera isométrica real (`FOV 35°`, `yaw 45°`, `pitch -55°`, `edge_pan_margin_base_px = 6.0`) | `rts_camera_rig.gd`/`.tscn` | **Corrigida / Preservada** (§9.1). |
| Remoção 100% de árvores/pedras esgotadas (`DEC-09`) vs. código atual (`DepletedVisual`) | `resource_source.gd` vs. `DEC-09` | **Preservada** como `DECIDIDO` e `PLANEJADO (NÃO IMPLEMENTADO)` (§7.2). |
| Trabalhadores de teste `Worker3` e `Worker4` vs. população inicial canônica | `TemporaryTestWorkersController` | **Preservada** (separação explícita no cabeçalho do GDD: 2 protagonistas canônicos). |
| Taxas de consumo alimentar, consequências de fome, equilíbrio de calendário, *Alento*, combate e marca | `v1.0` / `v1.1` / Entrevista | **Questão legítima em aberto** (`ABERTO` / `PROPOSTA` na §12.3). |

---

## 3E. Correções Aplicadas na Revisão R4 (`AUD-01` a `AUD-08`, `R4-I` e `R4-J`)

- **`AUD-01` (Validação de Save vs. Decaimento/Interrupção em `T3_architecture_PROPOSAL.md` §7.2, §7.4 e §7.5):** Corrigida a invariante contábil do snapshot para representar explicitamente `deficit_uncompensated(c, R)` sob Alternativa B (`DEC-11B`), impedindo falsa rejeição de saves após deterioração legítima de pilhas reservadas; desacoplado o vínculo físico de carga interrompida (`carry_load` + `_transit_claims`) da obrigatoriedade de `active_order == "ConstructOrder"`, alinhado à futura revisão `T3.4-ARCHITECTURE-R2`.
- **`AUD-02` (`DEC-16` em `Dawn_of_Kin_GDD.md` §3.1, §9.2 e §12.2):** Separada a padronização de **esqueleto único por faixa etária** (`DECIDIDO`) do orçamento `~1.500–3.500` triângulos, shaders recoloríveis e detalhes de *sockets* (`PROPOSTA`).
- **`AUD-03` (Comandos RTS Implementados vs. Planejados em `Dawn_of_Kin_GDD.md` §9.1):** Confrontada diretamente com `src/rts/command_controller.gd`, distinguindo clique direito implementado (mover, coletar com retorno automático, suprir canteiro T3.3) de comandos futuros planejados (entrega avulsa direta, montagem T3.4 e ataque/interação T6+).
- **`AUD-04` (`README.md`):** Eliminada a contradição sobre a aceitação da limitação em bateria DC (alinhada a `T2_Closeout_ACCEPTANCE.md` em `14/11/2026`), atualizada a nota de persistência para refletir `D1`/`DEC-17` (`T3.8`), removido `(pendente)` do protocolo manual `T2`, e corrigida a árvore documental distinguindo `Dawn_of_Kin_GDD.md` como candidato `v1.2 RC` nesta branch enquanto `v1.0` segue vigente na `main`.
- **`AUD-05` (Sincronização Pós-Aceite `T3.3`):** Atualizados `T3_architecture_PROPOSAL.md` (§8 e §9.2–9.3) e adicionados adendos datados (`16/11/2026`) em `T3_3_UX_technical_notes.md`, `T3_3_R2_plateau_navigation_diagnostic.md` e `T3_3_closeout_CANDIDATE.md` mantendo originais intactos e preservando o bloqueio estrito de `T3.4`.
- **`AUD-06` (`CommandController` durante sincronização de navegação em `T3_architecture_PROPOSAL.md` §4.1):** Explicitado o comportamento real implementado em `src/rts/command_controller.gd` (rejeição imediata com `"navigation_not_ready"`), reclassificando qualquer retenção/fila automática como proposta futura opcional (`PROPOSTA`).
- **`AUD-07` (Exemplos de Logística D4 × D9 em `T3_architecture_PROPOSAL.md` §5):** Alinhadas as descrições de viagens na tabela aos transportadores únicos de `D9` (`SOLO_SUPPLIER` ou `1 TRANSPORTER` + `1–2 BUILDER`), preservando integralmente custos, pesos, dimensões e tempos `D4`.
- **`AUD-08` (Links Locais `file:///` e Seções Inexistentes):** Substituídos todos os 9 links `file:///` em `docs/architecture/T1_architecture.md` e todos os 13 links `file:///` em `docs/testing/T3_2_technical_notes.md` por caminhos relativos portáveis verificados em disco; corrigidas as referências inexistentes `§8.1` e `§8.2` em `Dawn_of_Kin_GDD.md` (§12.2) para `§8`.
- **`R4-I` (Parâmetros de Câmera em `docs/architecture/T1_architecture.md` §3.1):** Alinhados aos valores reais de `src/camera/rts_camera_rig.gd` e `.tscn` (`fov_degrees = 35.0`, `YawPivot +45°`, `PitchPivot -55°`, em vez de `FOV 42°`, `-45°`, `-48°`).
- **`R4-J` (Decisões Recuperadas da `v1.0` e `v1.1`):** Restauradas no `Dawn_of_Kin_GDD.md` (1) atribuição automática de ferramentas/armas por profissão a partir do arsenal compartilhado com opção simples de atribuição manual (`v1.1` §8 → §4.4, §8, §12.2), (2) capacidade individual de carga em porcentagem (`0%`–`100%`) permitindo futura evolução por características, profissão, equipamentos ou melhorias (`v1.0` §5 → §4.1, §12.2), e (3) aparência coerente das fontes durante extração (`v1.0` §5 → §7.2, §12.2: árvore não permanece vertical após troncos; arbustos não são destruídos na colheita), além da nota de fronteira cronológica entre Abrigo Básico e Depósito Rústico sem bloqueio artificial (§2.2).

---

## 4. Pendências Técnicas da `T3.4-ARCHITECTURE-R2` e Questões Abertas

- **Bloqueio Técnico da T3.4:** Permanece obrigatória a publicação e aprovação da revisão **`T3.4-ARCHITECTURE-R2`** cobrindo: (1) complementação manual transacional de reservas (`DEC-11B`), (2) retentativa após falha de `BuildingInstance`, (3) proteção contra novas obras sobre edifícios concluídos, (4) validação de contribuições no slot, (5) teto inteiro de progresso e (6) testes adicionais de regressão, navegação (`DEC-19`) e contabilidade.
- **Questões Abertas de Design/Calibração (`ABERTO`):** Marca comercial *Dawn of Kin*, cosmologia última da versão da Terra, momento/forma de eventual revelação futura do Ser de Luz, texto definitivo da fala do Ser de Trevas no Cap. 1, recalibração empírica do calendário e parâmetros numéricos de combate, natalidade, regeneração ecológica e performance em regiões `256–384 m` na **Intel UHD Graphics 620**.

---

## 5. Checklist de Auditoria Final

- [x] Existe **exatamente um único GDD** na árvore ativa: `docs/Dawn_of_Kin_GDD.md`.
- [x] `v1.0`, `v1.1` e `v1.2_PROPOSAL` foram removidos via `git rm` sem cópias órfãs, permanecendo intactos no histórico Git.
- [x] Nova direção narrativa (aparição única do Ser de Trevas, ausência do Ser de Luz no Cap. 1, Dons Latentes, *Alento*, Profissão × Vocação × Dom, 5 níveis por marcos concretos e 4 horizontes de lançamento) integralmente consolidada.
- [x] `DEC-11A` e `DEC-11B` ratificadas em todas as seções pertinentes.
- [x] Todas as referências Markdown da branch sincronizadas sem links `file:///` ou destinos quebrados.
- [x] Divergências `AUD-01` a `AUD-08`, `R4-I` e `R4-J` corrigidas em revisão documental `R4`.
- [x] Nenhum código GDScript, cena `.tscn`, recurso `.tres` ou teste foi modificado.
