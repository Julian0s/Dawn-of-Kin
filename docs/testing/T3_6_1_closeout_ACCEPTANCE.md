# T3.6.1 — Aceite técnico e encerramento

**Data:** 18/11/2026. **Candidata auditada:** `feat/t3-6-1-refund-math-contracts`, commit `629eca8fc8d803e1cd8ba4f8856366240f5b2e9d`. **Base:** `fb31887e9ee6671d81a6797ea0d921c6d8b7a979`. **Arquitetura de referência:** [T3.6-R2](https://github.com/Julian0s/Dawn-of-Kin/blob/69c13275a34a30564ac839ec920f83ef36590812/docs/architecture/T3_6_cancellation_architecture_R2_PROPOSAL.md).

A auditoria estática independente do ChatGPT foi favorável. O aceite é técnico e limitado ao módulo puro T3.6.1; não homologa o cancelamento de construções nem a T3.6 integral.

## Escopo aceito

`ConstructionCancellationMath.evaluate_refund()` calcula a fórmula D3 com aritmética inteira e proteção conservadora contra overflow. `evaluate_snapshot()` valida categorias e balanço contábil sem afirmar verificação física. `plan_transition()` valida contratos puros de estado. Os testes abrangem precisão, limites, tipos inválidos, transições e imutabilidade.

## Evidências

Conforme a execução da candidata registrada no [relatório](T3_6_1_candidate_report.md): suíte específica 5/5 testes e 113 asserções; suíte segmentada 289/289 testes, 42 suítes, 13.031 asserções, nenhuma falha ou erro de suíte; 42 suítes descobertas e executadas uma única vez, sem omissões nem duplicatas. Validação: 124 scripts e inicialização headless aprovados sem erros ou avisos. As execuções terminaram com sucesso, sem timeout; os testes não foram repetidos neste encerramento.

O total histórico de 12.922 mais as 113 asserções novas resulta em 13.035, quatro acima do total segmentado. Existem asserções em laços por quadro, inclusive em `tests/integration/test_t2_worker_cycle.gd:223`, portanto a contagem total pode variar entre execuções. A origem exata das quatro asserções não foi determinada; a cobertura é avaliada pela descoberta e execução das suítes, e não pela igualdade entre totais históricos.

## Limitações

O módulo não cancela obras nem movimenta recursos, e não houve alteração visível no gameplay. Não houve teste manual do proprietário para este módulo puro. Permanecem pendentes proveniência física, guardas transacionais, rollback entre componentes, custódia, transporte de retorno, interface e validação manual do fluxo futuro. A proteção de overflow pode rejeitar entradas matematicamente válidas quando o produto intermediário não cabe em 64 bits. A T3.6.2 depende de autorização e validação próprias.
