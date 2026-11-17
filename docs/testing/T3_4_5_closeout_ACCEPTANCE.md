# T3.4.5 — Registro de aceite e encerramento

## Identificação e decisão

- Data declarada: 17/11/2026. Autoridade: proprietário do projeto.
- Candidata auditada: `afc43636db0e519462c40c9d94b12a2b0e90fb89` na branch `feat/t3-4-5-navigation-bake`.
- Base remota da main: `85bbe3ff2edc74d45f2083956fd0932e4ec35919`.
- Correção técnica do falso sucesso após rebake parcial: `737482750675b7d580e10225571a5abd787843e4`; relatório documental auditado: `afc43636db0e519462c40c9d94b12a2b0e90fb89`.
- O proprietário informou 8/8 testes manuais aprovados sem observações, autorizou o encerramento documental e, atendidas as verificações, a integração por fast-forward. Ver [protocolo manual](T3_4_manual_test_protocol.md).

## Escopo e evidências

A etapa entrega navegação regional N1, rebake assíncrono, proteção transitória por blockers, sincronização, retentativas e modo degradado. A correção de `MoveOrder` impede sucesso falso ao alcançar um ponto parcial após recálculo. Os detalhes e limitações da cobertura estão no [relatório da candidata](T3_4_5_candidate_report.md).

O relatório registra execução anterior do Codex de **278/278 testes em 39 suítes, 12.821 asserções**, sem falhas ou erros de suíte, e validação de **118 scripts**. Essas execuções são evidências históricas, não foram repetidas nesta etapa documental.

O proprietário declarou os oito testes manuais aprovados em 17/11/2026; hardware, alimentação e resoluções efetivas de sua execução não foram informados. As observações parciais do Codex não substituem essa declaração.

O benchmark gráfico histórico na Intel UHD 620 registrou p95 de **13,505 ms**, sob CA, no cenário descrito no relatório. Não foi repetido após a última correção de movimento e não constitui medição da versão corrigida.

Conforme informado na solicitação do proprietário, o ChatGPT realizou auditoria independente estática favorável sem defeitos bloqueantes; essa revisão é distinta da execução direta de testes.

## Limites e governança

O modo degradado preserva a proteção e encerra ordens afetadas; não há interface definitiva de recuperação. HUD definitivo e complementação manual (T3.5), cancelamento e reembolso (T3.6), armazenamento protegido (T3.7) e persistência em disco (T3.8) permanecem futuros.

O proprietário estabeleceu continuidade sem confirmações repetidas quando a etapa estiver tecnicamente auditada, testada e sem bloqueios; isso não autoriza alterações futuras sem análise. T3.5 não é iniciada neste encerramento e não há autorização para criar tag nesta tarefa.

## Critérios de integração

Publicar apenas documentação após verificar SHAs remotos, limpeza dos dois worktrees envolvidos, links e ausência de alterações em código ou testes. A integração exige que a candidata contenha a main remota e que a main local esteja limpa; realizar somente `git merge --ff-only`, publicar e verificar o SHA remoto. Qualquer divergência ou alteração inesperada interrompe a integração. Este documento registra os critérios, não afirma por si só que o push foi realizado.
