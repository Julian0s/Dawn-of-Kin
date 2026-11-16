# Dawn of Kin — Registro de Aceite Formal e Homologação da Etapa T3.3 (ACCEPTANCE)

---

## A. Identificação

- **Etapa:** T3.3 — Canteiro de Obra e Suprimento Físico (Transporte)
- **Data da homologação:** 16 de novembro de 2026
- **Autoridade de aprovação:** Proprietário do projeto
- **Resultado:** **HOMOLOGADA FORMALMENTE**
- **Branch de implementação:** `feature/t3-3-construction-logistics`
- **Commit técnico final:** `6c5c444b07fd2aa6cb1d2f0f03c38aa78eb0c59b`
- **Commit candidato auditado:** `a84a67bee416f560794cbdfd102207f297f8771e`
- **Documento candidato de referência:** [T3_3_closeout_CANDIDATE.md](T3_3_closeout_CANDIDATE.md)

---

## B. Decisão Formal do Proprietário

Em **16 de novembro de 2026**, após a auditoria independente realizada pelo ChatGPT sobre o commit candidato `a84a67bee416f560794cbdfd102207f297f8771e`, o proprietário declarou expressamente:

> Minha decisão sobre a T3.3 do Dawn of Kin: AUTORIZO A HOMOLOGAÇÃO FORMAL da T3.3, sem autorizar ainda merge, tag ou T3.4. Sem observações adicionais.

Este registro formaliza o **aceite técnico e funcional da etapa T3.3** na branch `feature/t3-3-construction-logistics`. A homologação aqui registrada conclui a avaliação da T3.3, porém **integração na `main`, criação de tag Git e planejamento ou implementação da etapa T3.4 permanecem bloqueados** e exigem autorizações específicas e expressas do proprietário.

---

## C. Escopo Homologado

Estão formalmente homologadas na T3.3 as seguintes capacidades de canteiro e suprimento físico:

- **Criação transacional de canteiros (`ConstructionSite` via `ConstructionManager`):** instanciação após confirmação espacial válida, bloqueando sobreposição com canteiros existentes e com a `CampStorageZone` (**D6**).
- **Reserva atômica de recursos:** reserva transacional (`reserve_batch`) no estoque físico do acampamento (`SettlementInventory` / `PileReservationLedger`), com rollback garantido em falha pós-reserva e aplicação da **Alternativa B — Perda Direta** em caso de deterioração.
- **Retirada física direcionada:** saque exclusivo da pilha física reservada (`pile_id`) visitada pelo trabalhador, sem fabricação de recursos nem consumo de saldo reservado a outras obras.
- **Transporte com capacidade e peso:** carregamento em `UnitCarryLoad` respeitando capacidade individual e desaceleração proporcional ao peso transportado.
- **Entrega ao buffer da construção:** descarregamento no perímetro do canteiro com validação de propriedade dos `_transit_claims`, alcance físico desobstruído (`has_clear_physical_access`) e contabilidade íntegra sem overflow.
- **Organização de trabalhadores segundo a regra D9:** `1` supridor individual; `2` (`1` transportador + `1` construtor em prontidão); `3` (`1` transportador + `2` construtores em prontidão); recusa do `4º` trabalhador (`no_worker_slot`, máximo de `2` construtores).
- **Recuperação e promoção após interrupções:** promoção automática de construtor em prontidão para transportador quando o transportador é interrompido, preservação segura da carga na mochila e espera reativa por colega ativo (`WAITING_FOR_PEER_SUPPLY`).
- **Correção da navegação na rampa:** eliminação da ponte lateral de NavMesh na rampa do `TestMap` (`T3.3-R2`), mantendo passagem aberta pelo pé da rampa e topo do platô e tentativas alternativas em `MoveState.FAILED_STUCK`.
- **Inspeção e controles temporários utilizados na validação:** `PlacementTestOverlay` / `TemporarySitePanel` para inspeção, designação e feedback de recusa (`command_rejected`).
- **Resolução dinâmica testada:** alternância em tempo de execução `1280×720 ↔ 1920×1080` na mesma partida sem reiniciar cena ou partida (`DisplayResolutionService`), respeitando limites do monitor.

*Fronteira estrita:* abastecimento do canteiro até `100%` do buffer **não** executa montagem nem conclui edifícios; a montagem ativa, consumo do buffer e rebake de obra concluída pertencem exclusivamente à **T3.4** (não implementada).

---

## D. Evidências de Aprovação

### 1. Validação Manual (Executada pelo Proprietário em 16/11/2026)
- **Resultado:** **10/10 testes aprovados pelo proprietário** em [T3_3_manual_test_protocol.md](T3_3_manual_test_protocol.md) (`A1`, `A2`, `B1`, `B2`, `C1`, `C2`, `C3`, `C4`, `D1` e `D2`), sem observações adicionais.
- **Detalhamento C4:** `C4-A` (1 trabalhador), `C4-B` (2 trabalhadores), `C4-C` (3 trabalhadores), `C4-D` (4º trabalhador recusado com `no_worker_slot`), `C4-E` (interrupção do transportador, promoção automática, entrega completa e remoção segura de `Worker3` e `Worker4`) — todos aprovados.
- **Resolução dinâmica:** alternância `1280×720 ↔ 1920×1080` durante a mesma partida aprovada.

### 2. Histórico Técnico Preservado (`B2` na R1 → R2 → Reteste)
- Na rodada **T3.3-R1**, o item **B2** reprovou manualmente ao posicionar canteiro no platô próximo à rampa do `TestMap` (travamento na lateral da rampa e suprimento incompleto).
- O defeito foi reproduzido visualmente, diagnosticado e corrigido na **T3.3-R2** ([T3_3_R2_plateau_navigation_diagnostic.md](T3_3_R2_plateau_navigation_diagnostic.md)), e posteriormente aprovado pelo proprietário em reteste manual.

### 3. Validação Automatizada Histórica Reportada pelo Antigravity
*Nota: os números abaixo referem-se à execução automatizada reportada pelo Antigravity sobre o commit técnico `6c5c444`; o ChatGPT não executou o Godot diretamente.*
- **234/234 testes aprovados** em **34/34 suítes** (`.\tools\run_tests.ps1 -Segmented`), totalizando **7.585 asserções** (`0` falhas, `0` erros de suíte).
- **109 scripts GDScript validados** (`.\tools\validate.ps1`), com **0 erros e 0 avisos**.

---

## E. Auditoria Independente

O **ChatGPT** conduziu auditoria documental e estática independente sobre o candidato `a84a67bee416f560794cbdfd102207f297f8771e`, verificando:
- Os **9 arquivos modificados/criados** na entrega candidata.
- Ausência completa de alterações de código GDScript, cenas ou recursos na etapa documental.
- Preservação integral dos contratos normativos do [Dawn_of_Kin_GDD_v1.0.md](../Dawn_of_Kin_GDD_v1.0.md) e das decisões **D1–D9** em [T3_architecture_PROPOSAL.md](../architecture/T3_architecture_PROPOSAL.md).
- Atualização íntegra de [T3_3_manual_test_protocol.md](T3_3_manual_test_protocol.md) com `10/10` aprovações e preservação do histórico de reprovação/correção de `B2`.
- Existência verificada de **80/80 referências relativas** no repositório e ausência de divergências documentais bloqueantes.

*Distinção de escopo:* essa auditoria constitui revisão estática e documental sobre os artefatos publicados no GitHub, distinta da execução direta dos binários ou testes do jogo.

---

## F. Limitações Conhecidas

A homologação formal da T3.3 preserva explicitamente as limitações conhecidas registradas no dossiê candidato:
- **Interface provisória de construção:** `PlacementTestOverlay` e `TemporarySitePanel` permanecem provisórios até a **T3.5**.
- **Trabalhadores temporários exclusivos de testes:** `Worker3` e `Worker4` (`TemporaryTestWorkersController`) e o seletor provisório de resolução existem apenas para apoio de validação em desenvolvimento.
- **Desempenho em bateria DC:** mantida a observação herdada da T2/T3 sobre variação entre alimentação CA e bateria DC sem atribuição causal isolada.
- **Diferenças entre hardwares medidos:** diagnósticos R1/R2 e benchmarks foram medidos em **Intel UHD Graphics 620**, enquanto as capturas automatizadas da **T3.3-UX** foram executadas em **NVIDIA GeForce GTX 1060** (não substituindo medições na Intel UHD 620).
- **Funcionalidades ainda não implementadas:** montagem progressiva e rebake ativo (**T3.4**), UI definitiva (**T3.5**), cancelamento/reembolso (**T3.6**), depósito protetor utilizável (**T3.7**) e persistência em disco (**T3.8**).

---

## G. Governança e Próximos Portões

**T3.3: HOMOLOGADA FORMALMENTE, MAS AINDA ISOLADA NA BRANCH DE IMPLEMENTAÇÃO.**

- **Integração na `main`:** **NÃO AUTORIZADA** (`origin/main` preservada em `931ad196346251e3f24a3ea5db6facb3641233bc`).
- **Criação de tag Git:** **NÃO AUTORIZADA**.
- **Implementação ou planejamento de T3.4:** **NÃO AUTORIZADOS**.
- **Novos recursos ou alterações funcionais:** **NÃO AUTORIZADOS**.
