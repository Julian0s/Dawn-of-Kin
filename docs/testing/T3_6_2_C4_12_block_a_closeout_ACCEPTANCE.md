# T3.6.2-C4.12 — Homologação do Bloco A

**Candidata homologada pelo proprietário** `d76dde6e13611ffc038496bfffc2aa3ffbb7db8c`, na branch `feat/t3-6-2-provenance-transactions`.

O proprietário declarou **6/6 testes manuais aprovados, sem reprovações**. [Protocolo manual](T3_6_2_C4_12_block_a_manual_protocol.md).

| Caso | Resultado |
|---|---|
| A1 — Inicialização e comandos dos líderes e temporários | Aprovado |
| A2 — Coleta e descarga física de madeira, pedra e alimentos | Aprovado com observação |
| A3 — Conclusão do Abrigo Básico com dois trabalhadores | Aprovado |
| A4 — Retorno de carga reservada de B antes do trabalho em A | Aprovado |
| A5 — Interrupção e nova ordem com conservação dos materiais | Aprovado |
| A6 — Nova coleta após reinício e indisponibilidade de D3 | Aprovado |

**Observação A2.** De quatro personagens selecionados para a mesma árvore, dois receberam a tarefa e dois ficaram parados. A auditoria confirmou o limite existente de duas vagas em `ResourceSource.max_simultaneous_workers` e a checagem de vaga por unidade em `CommandController._command_gather_resource()`. O comportamento é compatível com a regra existente e foi classificado como limite da fonte, sem evidência de regressão C4.12. A falta de feedback claro para os personagens excedentes fica registrada como melhoria futura de UX. Alterar o limite ou distribuir trabalhadores automaticamente requer aprovação específica. [Limite da fonte](../../src/economy/resource_source.gd#L41) · [Despacho RTS](../../src/rts/command_controller.gd#L221).

A auditoria estática independente foi favorável à candidata. Seu parecer cobre a inspeção do código e dos contratos. A execução gráfica A1–A6 foi declarada pelo proprietário. Os resultados automatizados abaixo foram reportados pelo Codex na candidata e não foram repetidos pela auditoria ou neste encerramento. [Relatório da candidata](T3_6_2_C4_12_block_a_candidate_report.md).

| Evidência automatizada reportada | Resultado |
|---|---|
| C4.12 na cena jogável | 5/5 testes, 119 asserções |
| T3.6.2 focada | 187/187 testes, 25 suítes, 11.508 asserções |
| Regressão segmentada final | 484/484 testes, 68 suítes, 26.311 asserções |
| Validação de scripts e inicialização headless | 163 scripts, zero erros ou avisos |

Continuam aplicáveis **D-INT-01/B** para retorno físico à reserva de origem, **D-INT-02/A** para guardas durante sinais pós-commit e **D-INT-03/A** para admissão de unidades com identidade válida e mochila vazia.

Permanecem pendentes D3 e custódia, migração de mochilas carregadas, demais superfícies de P6, armazenamento protegido, persistência e o feedback de vagas de coleta. O aceite está limitado ao Bloco A.
