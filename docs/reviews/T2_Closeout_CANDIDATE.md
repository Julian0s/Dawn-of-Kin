# Dawn of Kin — T2-CLOSEOUT: Consolidação Documental e Preparação para Aceite Final (CANDIDATE)

**Documento:** Relatório Consolidado de Encerramento da Etapa T2<br>
**Data:** 14 de novembro de 2026<br>
**Branch de consolidação:** `review/t2-closeout-candidate`<br>
**Commit-base técnico:** `f3cb7e9ee0b3a5cf35264623013688a0df2a5696`<br>
**Hardware de referência:** Intel(R) Core(TM) i7-8650U CPU @ 1.90GHz | Intel(R) UHD Graphics 620<br>
**Engine:** Godot 4.7.2.stable.official.ed1daf0bf | Renderizador: `gl_compatibility`

---

## Sumário Executivo de Classificação

> ### VALIDADO TECNICAMENTE
> - **Economia, Coleta, Transporte e Estoque (T2.0 a T2.5.1):** Contratos de dados de recursos (`ResourceDefinition`), pesos e carga individual (`UnitCarryLoad`), zona de descarga no chão (`CampStorageZone`), pilhas físicas individuais (`GroundResourcePile`, `GroundPileManager`), fontes naturais coletáveis (`ResourceSource`), ciclo de trabalho e entrega (`GatherResourceOrder`, `DeliverToCampOrder`), deterioração centralizada por tempo de exposição (`EconomyClockController`) e HUD completo (`ResourceHud`).
> - **Validação Global e Concorrência (T2.6):** Correções de corrida de sincronização pós-rebake de navegação entre múltiplas cenas, estabilidade de amostragem de testes, suíte segmentada em 6 lotes disjuntos e benchmark representativo contínuo.
> - **Unificação de Velocidade de Deslocamento (T2.6-B1):** Velocidade de deslocamento sem carga unificada em 4,8 m/s em ordens de movimento manual e ordens de coleta/trabalho, com desaceleração contínua incidindo estritamente sobre a carga física transportada (2,88 m/s a 100% de carga; recuperação imediata para 4,8 m/s após descarregar).
> - **Suíte Automatizada Completa:** **182 de 182 testes aprovados (100%) em 27 suítes**, totalizando **6.469 asserções** com zero erros e zero avisos via `.\tools\run_tests.ps1 -Segmented`.
> - **Desempenho em Tomada CA (B1.1):** Mediana de **147,33 FPS** com **$p95 = 9,757\text{ ms}$** em 1920×1080 (folga de 6,943 ms sobre o teto de 16,7 ms) e **zero quadros acima de 100 ms** (pior quadro medido: 25,258 ms em 13.278 quadros analisados).
>
> ### VALIDADO MANUALMENTE PELO PROPRIETÁRIO
> - **Protocolo de Testes Manuais (A1 a F2):** Todos os 21 itens do protocolo `docs/testing/T2_manual_test_protocol.md` foram executados interativamente e relatados como aprovados pelo proprietário em 14/11/2026.
> - **Correção de Velocidade B1:** O apontamento manual sobre a velocidade ao ir coletar foi corrigido no commit `8f53a3f`, retestado pelo proprietário e expressamente confirmado: *"testei esta correto"*.
>
> ### LIMITAÇÃO CONHECIDA / PENDÊNCIA DE DECISÃO
> - **Desempenho em Bateria DC:** Quando desconectado da tomada (bateria DC, bateria B1), registrou-se mediana de 55,80 FPS e **$p95 = 33,038\text{ ms}$** — **critério de `p95 <= 16,7 ms` não atendido nessa bateria** (enquanto na tomada CA, bateria B1.1, o critério foi atendido com **$p95 = 9,757\text{ ms}$**). Em ambas as baterias (CA e DC), o critério de spikes foi cumprido com **zero quadros acima de 100 ms**. A classificação do desempenho em DC como limitação aceitável para encerrar a T2 **ainda depende de decisão expressa do proprietário**.
> - **Limites Visuais Provisórios Aceitos (T2.4.3):** Assets geométricos simples para pilhas e fontes, feedback de trabalho provisório e ausência de efeitos sonoros permanecem intencionais nesta fase de protótipo greybox.
>
> ### AGUARDANDO ACEITE FORMAL DO MARCO
> - A presente consolidação documental submete à decisão do proprietário o encerramento formal do marco **T2 — Trabalho e Recursos** e a autorização de transição para a etapa **T3 — Construção**.

---

## 1. Linha do Tempo Técnica da T1 à T2-B1.1

```
[Commit 2808799] Tag 't1-complete' — Fundação RTS Concluída (90 testes, 1.607 asserções)
       │
       ▼
[T2.0 - T2.0.1] Contratos Econômicos, UnitCarryLoad e SettlementInventory
       │
       ▼
[T2.1] CampStorageZone, GroundResourcePile e Deterioração Centralizada
       │
       ▼
[T2.2 - T2.2.1] Fontes Naturais (Árvore, Rocha, Arbusto), Picking 3D e Rebake NavMesh
       │
       ▼
[T2.3 - T2.3.1] GatherResourceOrder, DeliverToCampOrder e Concorrência de Trabalhadores
       │
       ▼
[T2.4 - T2.4.3] Ritmos Reais (1,5s / 2,5s / 3,5s), Desaceleração por Peso e Estados das Fontes
       │
       ▼
[T2.5 - T2.5.1] HUD de Recursos, Distinção Peso vs Quantidade ("Peso transportado: X / Y")
       │
       ▼
[T2.6] Commit 3ba3255 — Validação Global, Executor Segmentado e Benchmark Inicial
       │
       ├────────────────────────────────────────┬─────────────────────────────────────┐
       ▼                                        ▼                                     ▼
[GDD v1.1] Commit ef57470             [D2 Review] Commit 1355542            [B1 Fix] Commit 8f53a3f
Minuta de Personagens Modulares       Auditoria de Spikes e Benchmarks      Unificação de Velocidade (4,8 m/s)
       │                                        │                                     │
       │                                        │                           [B1.1 Bench] Commit f3cb7e9
       │                                        │                           Benchmark em Tomada CA (9,757 ms)
       │                                        │                                     │
       └────────────────────────────────────────┴─────────────────────────────────────┘
                                                │
                                                ▼
                   [T2-CLOSEOUT CANDIDATE] Branch 'review/t2-closeout-candidate'
                   Consolidação Documental, Rastreabilidade Total e Preparação de Aceite
```

---

## 2. Commits e Branches Relevantes

| Identificador | Branch | Commit Hash | Conteúdo e Papel Técnico |
| :--- | :--- | :---: | :--- |
| **Base T1** | `main` | `2808799c43b815cf876144807f41f92902bc2983` | Tag anotada `t1-complete`: Fundação RTS aprovada. |
| **Base T2.6** | `feat/t2-final-validation` | `3ba32552915fb81cec896aa809612f210ad0be94` | Validação global T2, suíte segmentada e benchmark inicial. |
| **GDD v1.1** | `docs/gdd-v1.1-characters` | `ef57470e26f091357012ef8c8214fee0e4f83c1e` | Minuta documental aprovada em conteúdo pelo proprietário. |
| **Revisão D2** | `docs/t2-6-d2-performance-review` | `1355542d52350595b433dff5bc241f84f384fe3e` | Auditoria de telemetria, diagnóstico driver Intel e integridade. |
| **Correção B1** | `fix/t2-6-b1-unified-travel-speed` | `8f53a3f0137d6e450b5af0b87d8fb52a02c22bc3` | Unificação da velocidade de deslocamento sem carga em 4,8 m/s. |
| **Benchmark B1.1** | `fix/t2-6-b1-unified-travel-speed` | `f3cb7e9ee0b3a5cf35264623013688a0df2a5696` | Validação de desempenho pós-correção B1 em tomada CA. |
| **Candidata Closeout** | `review/t2-closeout-candidate` | *(este commit)* | Consolidação integrada documental e de evidências. |

---

## 3. Evidências dos Testes Automatizados

A suíte completa de testes automatizados do Dawn of Kin foi executada via `.\tools\run_tests.ps1 -Segmented`, dividida em 6 lotes disjuntos de processos independentes do Godot 4.7.2 para evitar o limite de 240 segundos de processo único (devido à simulação física de tempos reais de coleta a 60 Hz):

- **Total de Suítes Executadas:** 27 de 27 descobertas (bijeção exata: 0 duplicatas, 0 omissões).
- **Total de Testes:** 182 testes.
- **Resultado:** **182 Aprovados (100% de sucesso, 0 falhas).**
- **Total de Asserções:** **6.469 asserções validadas.**
- **Erros de Suíte:** 0.
- **Avisos (Warnings):** 0 (validado sob proteção estrita de interrupção por avisos).
- **Tempo Acumulado de Simulação:** 262,4 segundos.

### Composição Consolidada da Suíte e Limitação de Verificação por Lote
- **Origem do total consolidado:** Os totais consolidados acima (**27 suítes, 182 testes, 182 aprovados, 0 falhas, 0 erros/avisos, 6.469 asserções, 262,4 s em 6 lotes disjuntos**) provêm do relatório de execução da suíte segmentada em [T2_6_B1_speed_alignment_DRAFT.md](T2_6_B1_speed_alignment_DRAFT.md) (seção 4.B).
- **Composição estática verificável no código-fonte (`tests/`):**
  - **Suítes unitárias (`tests/unit/`):** 12 arquivos de suíte contendo **85** funções `test_*` (cálculos de câmera, matemática de seleção, planejamento de grupos, matemática de colisão, economia T2, pilhas, HUD e fontes).
  - **Suítes de integração (`tests/integration/`):** 15 arquivos de suíte contendo **97** funções `test_*` (caixa de seleção, câmera RTS, comandos, navegação, picking, RVO, pilhas no NavMesh, estados de fontes, ritmo/carga inclusive `test_12` e `test_13` de B1, economia jogável, HUD e ciclo de trabalhador).
  - **Total estático verificado:** `12 + 15 = 27` suítes e `85 + 97 = 182` funções de teste.
- **Limitação de verificação independente por lote:** Os logs brutos individuais de cada um dos 6 lotes (`unit` e `integration-01`..`05`) da última execução segmentada não foram persistidos no repositório; portanto, os subtotais de asserções por lote individual não são verificáveis de forma independente a partir do histórico versionado (motivo pelo qual os subtotais por lote foram retirados desta versão revisada, mantendo-se apenas os totais consolidados reportados e a contagem estática verificável por categoria).

---

## 4. Resultados de Desempenho em Tomada CA vs Bateria DC

Medições representativas de 3 corridas de 30 segundos com 5 segundos de aquecimento cada, na resolução nativa de teste de 1920×1080 (Full HD, VSync desligado, sem `--fixed-fps`) na GPU integrada Intel UHD Graphics 620:

| Métrica | Referência D2 em CA | Pós-B1 em Bateria DC | Pós-B1.1 em Tomada CA | Status Formal |
| :--- | :---: | :---: | :---: | :---: |
| **Condição de Alimentação** | Tomada CA (Bateria ~95%) | Bateria DC (Bateria ~50–79%) | Tomada CA (Bateria 42%–79%) | Comparação controlada |
| **FPS Médio Mediano** | 125,42 | 55,80 | **147,33** | +21,91 FPS sobre D2 |
| **Frame Médio** | 7,973 ms | 17,921 ms | **6,788 ms** | Sub-7 ms estável |
| **p50 Mediano** | 7,198 ms | 14,872 ms | **6,608 ms** | -0,590 ms sobre D2 |
| **p95 Mediano** | 13,487 ms | 33,038 ms | **9,757 ms** | **Folga de 6,943 ms** |
| **p99 Mediano** | 17,053 ms | 41,797 ms | **11,679 ms** | -5,374 ms sobre D2 |
| **Pior Quadro Absoluto** | 32,101 ms | 79,899 ms | **25,258 ms** | Zero spikes graves |
| **Quadros > 16,7 ms** | 112 / 11.458 (0,98%) | 2.409 / 5.030 (47,89%) | **14 / 13.278 (0,11%)** | Quase imperceptível |
| **Quadros > 100 ms** | **0 (0,00%)** | **0 (0,00%)** | **0 (0,00%)** | **Zero absoluto** |
| **Critério Formal (p95 ≤ 16,7 ms)** | **APROVADO** | Reprovado (DC) | **APROVADO (CA)** | **Aprovado em CA** |

### Ressalvas de Causalidade e Metodologia
- Os resultados sustentam uma **associação observada** entre as condições de alimentação (tomada CA vs bateria DC) e o desempenho medido, porém não há telemetria síncrona direta (de clock, temperatura ou energia) suficiente para comprovar de forma definitiva o mecanismo físico específico.
- **Estado objetivo por critério:**
  - **CA:** `p95 = 9,757 ms` — critério de `p95 <= 16,7 ms` **atendido** na bateria B1.1.
  - **DC:** `p95 = 33,038 ms` — critério de `p95 <= 16,7 ms` **não atendido** na bateria B1.
  - **Critério de spikes:** **zero quadros acima de 100 ms** em ambas as baterias (CA e DC).
- A aprovação em CA atesta conformidade apenas nessa condição de alimentação; a classificação do desempenho em DC como limitação aceitável para encerrar a T2 **ainda depende de decisão expressa do proprietário**.

---

## 5. Registro dos Testes Manuais e da Observação B1

Conforme informado diretamente pelo proprietário em 14/11/2026:
- Todos os **21 itens de teste manual (A1 a F2)** descritos no protocolo [docs/testing/T2_manual_test_protocol.md](../testing/T2_manual_test_protocol.md) foram executados e aprovados.
- **Apontamento em B1:** Observou-se inicialmente que a marcha sem carga ao receber uma ordem de coleta ocorria a 2,5 m/s, diferindo da caminhada livre de 4,8 m/s.
- **Resolução B1:** A velocidade sem carga foi unificada em 4,8 m/s em `src/units/orders/gather_resource_order.gd` e `src/units/orders/deliver_to_camp_order.gd`, fazendo com que qualquer redução de ritmo decorra exclusivamente do peso transportado (atingindo 2,88 m/s a 100% de carga e retornando a 4,8 m/s pós-descarga).
- **Reteste pelo proprietário:** O proprietário executou novo teste visual interativo da versão corrigida no commit `8f53a3f` e confirmou expressamente: *"testei esta correto"*.

---

## 6. Confronto: GDD × Arquitetura × Código Real

A auditoria confrontou o código implementado com os marcadores de design do GDD v1.0 / minuta v1.1 e da arquitetura T2:

| Pilar de Engenharia | Contrato Previsto no GDD / Arquitetura | Implementação Real no Código | Classificação de Conformidade |
| :--- | :--- | :--- | :--- |
| **Preservação RTS T1** | Comandos de movimento no chão via clique direito, câmera isométrica e seleção múltipla sem regressões. | `MoveOrder`, `RtsCameraRig` e `SelectionManager` preservados e validados nas suítes de integração executadas (sem regressões detectadas). | **VALIDADO TECNICAMENTE** |
| **Fontes Naturais** | Três categorias (Madeira, Pedra, Alimentos) com tempos de extração distintos e feedback visual. | `tree_source.tscn` (2,5s), `rock_source.tscn` (3,5s), `bush_source.tscn` (1,5s), pausas de preparação e feedback corporal. | **VALIDADO TECNICAMENTE** |
| **Capacidade e Pesos** | Mochila física com pesos unitários (madeira 2, pedra 3, alimento 1), capacidade 20 e redução contínua de velocidade. | `UnitCarryLoad` atômico; multiplicador de velocidade interpolado de 1,00 a 0,60; teto de 20 de carga sem estouro. | **VALIDADO TECNICAMENTE** |
| **Transporte e Descarga** | Retorno automático ao acampamento quando cheia ou no esgotamento da fonte; descarga somente no acampamento. | `GatherResourceOrder` comuta para `DeliverToCampOrder`; descarrega em `CampStorageZone` sem entrega prematura. | **VALIDADO TECNICAMENTE** |
| **Conservação e Não Duplicação** | Recursos não são perdidos nem duplicados nas operações de transporte; perda ocorre apenas por deterioração intencional. | Invariante nas operações de extração/transporte/descarga ($Q_{\text{fonte}} + Q_{\text{mochila}} + Q_{\text{estoque}} = \text{constante}$ na ausência de deterioração), distinguindo-se da perda intencional por deterioração temporal. | **VALIDADO TECNICAMENTE** |
| **Autoridade Única de Pilhas** | Pilhas individuais no chão do acampamento como única autoridade de estoque coletivo, sem armazéns construíveis. | `GroundPileManager` posiciona pilhas determinísticas em slots; `SettlementInventory` reflete rigorosamente as pilhas. | **VALIDADO TECNICAMENTE** |
| **Deterioração Centralizada** | Alimentos (180s) e madeira (420s) expostos decaem com o tempo; pedra não deteriora. Sem processamento por frame individual de cada pilha, com processamento centralizado periódico. | `EconomyClockController` atualiza pilhas por intervalo discreto periódico (zero `_process` por pilha); perda refletida no HUD. | **VALIDADO TECNICAMENTE** |
| **Concorrência de Trabalhadores** | Trabalhadores compartilham a mesma fonte em vagas distintas sem deadlock ou sobreposição. | `GatherSlotPlanner` aloca slots circulares no NavMesh; liberação de vaga durante o transporte para outro trabalhador. | **VALIDADO TECNICAMENTE** |
| **HUD de Recursos e Carga** | Exibição de estoque coletivo e painel inferior distinguindo claramente peso transportado de contagem de unidades. | `ResourceHud` exibe `Peso transportado: X / 20` com barra proporcional e contagem individual em unidades. | **VALIDADO TECNICAMENTE** |
| **Velocidade Unificada (B1)** | Marcha sem carga uniforme (4,8 m/s) em todas as ordens; redução decorrendo estritamente do peso transportado. | `SpeedContext.NORMAL` em ordens de coleta e entrega; velocidade-alvo de 4,8 m/s sem carga e 2,88 m/s com 100% de carga. | **VALIDADO TECNICAMENTE** |

---

## 7. Classificação das Pendências Restantes

Para governança transparente do projeto, todas as questões foram categorizadas:

### A. Decisões e Correções antes de Encerrar a T2
- **Discrepâncias funcionais relatadas:** As divergências funcionais observadas (inclusive a observação de velocidade B1) foram corrigidas, testadas automaticamente e aprovadas manualmente nos testes realizados.
- **Decisão pendente do proprietário sobre bateria DC:** A aceitação do desempenho em bateria DC ($p95 = 33,038\text{ ms}$, critério de $p95$ não atendido na bateria B1, com zero quadros $> 100\text{ ms}$) como limitação aceitável para o encerramento do marco T2 depende de decisão expressa do proprietário.

### B. Limitações Conhecidas e Pontos de Atenção
1. **Desempenho em Bateria DC vs Tomada CA:** Na bateria B1 em modo DC registrou-se $p95 = 33,038\text{ ms}$ (critério de $p95 \le 16,7\text{ ms}$ não atendido), enquanto na bateria B1.1 em tomada CA registrou-se $p95 = 9,757\text{ ms}$ (critério atendido). Em ambas as baterias registrou-se zero quadros $> 100\text{ ms}$. Os dados sustentam associação entre condição de alimentação e desempenho, sem telemetria síncrona suficiente para comprovar o mecanismo físico específico.
2. **Representação Visual Provisória:** Malhas greybox para pilhas no chão e feedback corporal provisório na coleta (declarados e aceitos na etapa T2.4.3).

### C. Funcionalidades Corretamente Adiadas para Etapas Futuras
1. **Armazéns Construíveis com Proteção contra Deterioração:** Previsto para a etapa **T3 — Construção**.
2. **Ciclo Dia/Noite, Calendário e Save/Load em Disco:** Previsto para a etapa **T4 — Mundo e Calendário**.
3. **Criação de Filhos, Herança Genética e Casamentos:** Previsto para a etapa **T5 — Família**.
4. **Economia Salarial / Pessoal:** **ABERTO / PROPOSTA FUTURA** — sem marco de implementação atribuído (não vinculada a T6–T8).
5. **Combate, Arsenal e Outras Comunidades:** Previsto para as etapas **T6 a T8** conforme o roadmap do GDD.

### D. Questões de Design em Aberto (Sem Impacto na T2)
1. Nome comercial final do jogo (*Dawn of Kin* requer checagem prévia de marca antes da publicação).
2. Curva exata de envelhecimento e frequência de nascimentos familiares.
3. Intensidade dos parâmetros hereditários faciais e limites corporais.
4. Tabela de receitas e durabilidade de roupas/equipamentos.

---

## 8. Arquivos Documentais Consolidados

- [README.md](../../README.md): Atualizado com o estado consolidado da T2, métricas B1.1 e pendências conhecidas.
- [AGENTS.md](../../AGENTS.md): Atualizado com a consolidação da T2, cobertura da suíte e preservação da trava de T3.
- [docs/KNOWN_ISSUES.md](../KNOWN_ISSUES.md): Atualizado com o histórico de medições D2, B1 e B1.1, links relativos e ressalvas de energia.
- [docs/testing/T2_manual_test_protocol.md](../testing/T2_manual_test_protocol.md): Registrado com os 21 itens executados e aprovados pelo proprietário em 14/11/2026.
- `docs/Dawn_of_Kin_GDD_v1.1.md` ([histórico Git `3c6fc0b`](https://github.com/Julian0s/Dawn-of-Kin/blob/3c6fc0bd36fc3828af5a89662fb23cfb60d37865/docs/Dawn_of_Kin_GDD_v1.1.md), posteriormente consolidado em [Dawn_of_Kin_GDD.md](../Dawn_of_Kin_GDD.md)): Minuta consolidada com adendo de personagens modulares, links locais corrigidos para caminhos relativos e histórico atualizado.
- [docs/architecture/T2_architecture_DRAFT.md](../architecture/T2_architecture_DRAFT.md): Atualizado para status consolidado com links relativos.
- [docs/T2_Implementation_Plan_DRAFT.md](../T2_Implementation_Plan_DRAFT.md): Atualizado para status consolidado de encerramento.
- [docs/reviews/T2_6_D2_performance_DRAFT.md](T2_6_D2_performance_DRAFT.md): Revisão D2 integrada com rastreabilidade total de commits.
- [docs/reviews/T2_6_B1_speed_alignment_DRAFT.md](T2_6_B1_speed_alignment_DRAFT.md): Registro técnico do ajuste de velocidade B1.
- [docs/reviews/T2_6_B1_1_performance_DRAFT.md](T2_6_B1_1_performance_DRAFT.md): Registro técnico do benchmark pós-B1 em tomada CA.
- Pasta [docs/reviews/evidence/](evidence/): 18 arquivos JSON sanitizados de telemetria bruta preservados intactos.

---

## 9. Verificação de Escopo Estrito (Ausência de Código T3–T8)

- **Auditoria de Código:** Nenhum sistema de construção de edifícios, posicionamento de estruturas, salvamento/carregamento em disco, criação de personagens modulares, genética, casamento ou combate foi introduzido no repositório.
- **Rigor de Governança:** O escopo implementado restringe-se estritamente aos requisitos aprovados da etapa T2.

---

## 10. Dependências e Ponto de Decisão para a Fase T3

A etapa **T3 — Construção** está planejada para introduzir:
1. Posicionamento de obras de construção no mapa com validação de terreno/NavMesh.
2. Consumo ordenado de materiais coletivos (Madeira e Pedra) do estoque.
3. Alocação de moradores ao trabalho de construção e ritmo de erguer estruturas.
4. Conclusão de uma cabana/abrigo inicial.
5. Construção de armazéns/depósitos capazes de proteger materiais contra a deterioração (`decay_multiplier = 0.0`).

### Ponto de Decisão Arquitetural para o Planejamento T3 (`PROPOSTA`)
> **PROPOSTA — Conceito de "Abrigo Completado e Persistido":**<br>
> O roadmap histórico cita para o primeiro protótipo jogável a conclusão de um abrigo persistido. Como o sistema definitivo de serialização e carregamento em disco (Save/Load) está planejado para a **etapa T4**, **propõe-se** (como `PROPOSTA`, não `DECIDIDO`) para a T3 que a "persistência" signifique a manutenção do estado da obra terminada na memória da sessão (`MainScene`), permitindo que moradores utilizem a estrutura como ponto de referência, sem implementar prematuramente a arquitetura de arquivos `.save` antes do marco T4. Essa definição permanece em aberto e dependerá de confirmação expressa do proprietário no momento do planejamento da T3.

---

## 11. Proposta Fundamentada de Encerramento da T2

Com base em:
1. **182 de 182 testes automatizados aprovados** com zero erros e zero avisos na suíte segmentada;
2. **21 de 21 critérios de teste manual executados e aprovados** pelo proprietário em 14/11/2026;
3. **Resolução e confirmação visual da observação B1** ("testei esta correto");
4. **Desempenho aprovado com folga em tomada CA** ($p95 = 9,757\text{ ms}$, zero quadros $> 100\text{ ms}$ em 1080p);
5. **Preservação integral dos contratos e controles da T1**;

**Recomendação Técnica:** A etapa **T2 — Trabalho e Recursos** encontra-se tecnicamente e documentalmente apta para encerramento formal. Submete-se a presente branch candidata `review/t2-closeout-candidate` à apreciação e autorização final do proprietário.
