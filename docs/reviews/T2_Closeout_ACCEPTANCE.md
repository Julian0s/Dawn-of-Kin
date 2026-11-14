# Dawn of Kin — Aceite Formal e Fechamento Oficial da Fase T2 (ACCEPTANCE)

**Documento:** Termo de Aceite Formal e Encerramento do Marco T2 — Trabalho e Recursos<br>
**Data da Decisão:** 14 de novembro de 2026<br>
**Branch de Destino:** `main`<br>
**Commit da Candidata Auditada:** `729390832883587180e3df89193522a72f27299d`<br>
**Commit de Merge na `main`:** `e7b46377dd9ed285177ea6ef1b6d16c25fab87f0`<br>
**Tag Anotada de Encerramento:** `t2-complete`<br>
**Hardware de Referência:** Intel(R) Core(TM) i7-8650U CPU @ 1.90GHz | Intel(R) UHD Graphics 620<br>
**Engine:** Godot 4.7.2.stable.official.ed1daf0bf | Renderizador: `gl_compatibility`

---

## 1. Decisões Expressas do Proprietário (14/11/2026)

Após a consolidação técnica na branch `review/t2-closeout-candidate` e a auditoria independente do ChatGPT sobre o commit `729390832883587180e3df89193522a72f27299d`, o proprietário do projeto emitiu as seguintes decisões formais:

1. **APROVADO — Desempenho em bateria DC:**
   > Aceitou expressamente o resultado em bateria DC ($p95 = 33,038\text{ ms}$, acima do critério formal de $16,7\text{ ms}$) como limitação conhecida **não bloqueante para o encerramento da fase T2**. O resultado permanece documentado como não conforme à meta nessa condição específica, mantendo-se a meta de desempenho inalterada e sem constituir aprovação universal sob qualquer regime de bateria móvel.
2. **APROVADO — Encerramento Oficial da Fase T2:**
   > Autorizou formalmente a integração da candidata T2 à branch `main`, a formalização documental do encerramento do marco, a criação da tag Git anotada `t2-complete` e a publicação dos resultados no GitHub.
3. **DECISÃO PENDENTE — Minuta GDD v1.1:**
   > O proprietário manteve pendente a promoção formal do GDD v1.1. O documento [Dawn_of_Kin_GDD_v1.0.md](../Dawn_of_Kin_GDD_v1.0.md) permanece como a única fonte normativa vigente da engenharia do projeto. A minuta [Dawn_of_Kin_GDD_v1.1.md](../Dawn_of_Kin_GDD_v1.1.md) permanece versionada no repositório como proposta integral consolidada aguardando avaliação e promoção futura.

---

## 2. Síntese dos Resultados Técnicos e Evidências Consolidadas

### A. Cobertura da Implementação Técnica (T2.0 a T2.6 + B1)
- **T2.0 / T2.0.1:** Definições atômicas de dados (`ResourceDefinition`), pesos físicos individuais (`UnitCarryLoad`) e inventário coletivo (`SettlementInventory`).
- **T2.1:** Zona de descarga no chão (`CampStorageZone`), autoridade única e pilhas físicas (`GroundResourcePile`, `GroundPileManager`), deterioração centralizada periódica sem processamento por frame individual (`EconomyClockController`).
- **T2.2 / T2.2.1:** Fontes naturais (`wood_tree`, `stone_rock`, `food_bush`), picking 3D e atualização dinâmica de `WorldNavigation`.
- **T2.3 / T2.3.1:** Máquina de estados de ordens (`GatherResourceOrder`, `DeliverToCampOrder`), alternância automática por capacidade cheia ou esgotamento, e concorrência simultânea sem deadlocks.
- **T2.4 a T2.4.3:** Tempos de extração escalonados (1,5 s alimentos, 2,5 s madeira, 3,5 s pedra), redução contínua de velocidade por peso transportado, e estados visuais transitórios das fontes.
- **T2.5 / T2.5.1:** Interface HUD completa (`ResourceHud`, `SelectedUnitPanel`, `SettlementStockpilePanel`) distinguindo estritamente peso transportado de contagem unitária de itens.
- **T2.6 / B1:** Validação global, eliminação de corridas de concorrência no NavMesh entre cenas, executor segmentado disjunto, e unificação da velocidade de deslocamento sem carga em 4,8 m/s em todas as ordens (ajuste B1).

### B. Suíte de Testes Automatizados
- **Total de Suítes Executadas:** 27 de 27 descobertas (bijeção exata: 0 duplicatas, 0 omissões).
- **Total de Testes:** 182 testes.
- **Resultado da Execução:** **182 Aprovados (100% de sucesso, 0 falhas).**
- **Total de Asserções:** **6.469 asserções validadas.**
- **Erros / Avisos (Warnings):** 0 erros, 0 avisos sob flag estrita de interrupção por aviso (`-FailOnWarnings`).
- **Metodologia:** Execução segmentada em 6 lotes disjuntos via `.\tools\run_tests.ps1 -Segmented` (tempo acumulado de simulação: 262,4 s).

### C. Validação Manual Interativa
- **Protocolo Manual (`docs/testing/T2_manual_test_protocol.md`):** Todos os 21 itens (A1 a F2) foram executados pelo proprietário e informados como aprovados em 14/11/2026.
- **Revalidação da Correção B1:** O apontamento manual sobre a velocidade ao se deslocar para coletar foi corrigido no commit `8f53a3f`, retestado pelo proprietário e expressamente confirmado: *"testei esta correto"*.

### D. Benchmarks de Desempenho (1920×1080, Intel UHD Graphics 620, `gl_compatibility`)
- **Tomada CA (B1.1 — Bateria de Referência Aprovada):**
  - **FPS Médio Mediano:** `147,33 FPS`
  - **Frame Médio:** `6,788 ms`
  - **p50 Mediano:** `6,608 ms`
  - **p95 Mediano:** **`9,757 ms`** (folga de 6,943 ms em relação ao teto de 16,7 ms)
  - **p99 Mediano:** `11,679 ms`
  - **Pior Quadro Absoluto:** `25,258 ms`
  - **Quadros > 100 ms:** **0 (zero absoluto)**
  - **Conformidade Formal:** **CRITÉRIO DE p95 ATENDIDO COM FOLGA**.
- **Bateria DC (B1 — Limitação Não Bloqueante Aceita):**
  - **FPS Médio Mediano:** `55,80 FPS`
  - **p50 Mediano:** `14,872 ms`
  - **p95 Mediano:** **`33,038 ms`** (critério de $p95 \le 16,7\text{ ms}$ não atendido na bateria B1)
  - **Quadros > 100 ms:** **0 (zero absoluto)**
  - **Conformidade Formal:** Aceito pelo proprietário em 14/11/2026 como limitação não bloqueante para o fechamento da T2.
- **Ressalva Metodológica:** Os dados sustentam associação entre as condições de alimentação e o desempenho medido, sem que haja telemetria direta suficiente para comprovar o mecanismo físico específico. A aprovação da tomada CA não é extrapolada como aprovação universal em DC.

---

## 3. Rastreabilidade Git e Encerramento

- **Base T1 Anterior:** Commit `2808799c43b815cf876144807f41f92902bc2983` (tag `t1-complete`).
- **Candidata Consolidada:** Commit `729390832883587180e3df89193522a72f27299d` na branch `review/t2-closeout-candidate`.
- **Integração na `main`:** Realizada via merge preservando histórico (`git merge --no-ff review/t2-closeout-candidate`), gerando o commit de merge `e7b46377dd9ed285177ea6ef1b6d16c25fab87f0`.
- **Tag do Marco:** Tag anotada `t2-complete`.
- **Evidências Preservadas:** O dossiê [T2_Closeout_CANDIDATE.md](T2_Closeout_CANDIDATE.md) permanece versionado como evidência técnica da auditoria.

---

## 4. Confirmação de Governança e Escopo Estrito

1. **GDD Vigente:** Conforme determinação explícita, [Dawn_of_Kin_GDD_v1.0.md](../Dawn_of_Kin_GDD_v1.0.md) segue como documento normativo vigente; [Dawn_of_Kin_GDD_v1.1.md](../Dawn_of_Kin_GDD_v1.1.md) permanece como minuta não promovida.
2. **Ausência de Código T3–T8:** Nenhum código, cena, asset ou script referente às fases futuras (Construção T3, Ciclos T4, Família T5, Combate T6–T8) foi implementado.
3. **Próximo Passo:** O encerramento da fase T2 autoriza o início dos estudos e da elaboração da proposta de arquitetura técnica da etapa **T3 — Construção**, a ser submetida para aprovação prévia antes de qualquer codificação.
