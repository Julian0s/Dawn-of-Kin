# T3.6.2-C3.2 — Entrega seletiva transacional ao canteiro

**Candidata para auditoria independente.** Base `9f614563fdb29d613e6565b86206b957704e725f` em `feat/t3-6-2-provenance-transactions`. A referência da `main` no início era `25e0a20f1d6a2f10a9e059afe69759fbe263db4a`. O incremento usa o worktree existente `C:\Projetos\Dawn_of_Kin_wt_t3_4_5`.

## Contratos e escopo

Foram confrontados o [GDD v1.2, §§4.2–4.3](../Dawn_of_Kin_GDD.md), a [T3.6-R2, §§4–5 no commit 69c1327](https://github.com/Julian0s/Dawn-of-Kin/blob/69c13275a34a30564ac839ec920f83ef36590812/docs/architecture/T3_6_cancellation_architecture_R2_PROPOSAL.md) e os relatórios [C1-R1](T3_6_2_C1_R1_candidate_report.md), [C2](T3_6_2_C2_candidate_report.md), [C2-R1](T3_6_2_C2_R1_candidate_report.md) e [C3.1](T3_6_2_C3_1_candidate_report.md). O código conserva as regras D2, D9, DEC-11A e DEC-11B. O cancelamento D3 permanece fora do fluxo.

O [coordenador de entrega](../../src/economy/selective_site_delivery_coordinator.gd) oferece `execute_selective_site_delivery(site, unit, operation_id, requested_amounts)` e `commit_prepared_selective_delivery(site, unit, plan)`. A requisição vazia seleciona o máximo elegível. Uma requisição explícita exige quantidades inteiras, positivas e integralmente atendíveis. O retorno de sucesso traz `delivered_amounts`, `delivered_now` e `receipt`. A consulta `get_receipt(operation_id)` usa o último domínio resolvido pelo coordenador e retorna uma cópia.

O [planejador C3.1](../../src/economy/selective_site_delivery_planner.gd) continua puro. Suas APIs públicas mantêm `dry_run_only`, rejeitam participantes ocupados e não reservam IDs. O coordenador usa um escopo interno que só é reconhecido quando está registrado como entrega ativa na autoridade regional e os participantes estão sob guarda. Sob esse escopo, recalcula identidade, revisões, carga e pesos, reservas, claims de pares, buffer e débitos. Se um plano for apresentado, exige igualdade com a preparação recém-calculada. As revisões detectam mudanças seguidas de retorno ao valor anterior.

## Autoridade, recibos e IDs

A [autoridade da C2-R1](../../src/economy/reserved_withdrawal_coordinator.gd) continua única por par região/`World3D` e economia física. Ela impede novas transações C2 e C3 durante o commit e a publicação. O acesso é síncrono na thread principal. A ordem da entrega é autoridade, canteiros ordenados por `site_id` e instância, inventário, fonte física e unidade/mochila. Claims e buffer usam a guarda do canteiro. A liberação segue a ordem inversa.

Os recibos têm tipos distintos `reserved_withdrawal` e `selective_site_delivery`. O saque aceita recibos da sessão sem `kind` quando satisfazem a forma original completa. IDs de instância de objetos Godot são inteiros com sinal e podem ser negativos. Gerações, quantidades e IDs de pilha exigem valores positivos. Recibos de tipo errado, formato desconhecido e identidades diferentes produzem conflito.

O replay C3 verifica região, mundo, geração, reserva, inventário, fonte, identidade do canteiro, unidade, mochila e pedido. O commit de um plano também associa o SHA-256 da serialização exata aceita. O replay é consultado antes do saldo e retorna as quantidades originais com `replayed = true` e `delivered_now = 0`. A consulta continua possível durante os sinais. O replay exige participantes originais vivos e ainda identificáveis no domínio. A retenção é em memória enquanto o mundo existe.

A operação regional tem um ID independente dos IDs de simulação e dos débitos definitivos. O planejador procura um ID simulado livre no clone para evitar uma recusa artificial. Para a aplicação, o coordenador recria os débitos do zero em um ledger destacado e verifica disponibilidade tanto no histórico do ledger quanto nos recibos regionais. Compara os lotes e os saldos projetados, preservando o histórico definitivo e os IDs dos lotes residuais.

## Autorização, aplicação e rollback

1. Depois da revalidação contábil, verificar se o trabalhador está ativo na árvore, junto ao canteiro `ACTIVE`, com a mochila, claim e domínio esperados. Confirmar registro como `TRANSPORTER` ou `SOLO_SUPPLIER`, identidade exata da `ConstructOrder` ativa e o alcance atual medido por `BuildSlotPlanner.is_unit_in_site_dropoff_range()` no mundo da obra.
2. Preparar o ledger definitivo antes da primeira alteração. Preservar estado original da mochila, histórico, pesos e sinalização sob guarda. Capturar o claim, buffer, subestado, indicador de suprimento e recursos em falta que causam pausa. As guardas mantêm capacidade, alterações de ordem, progresso, material incorporado, reservas e claims de terceiros protegidos durante a transação.
3. Instalar silenciosamente o ledger debitado e as quantidades físicas projetadas. Reduzir o claim exato da unidade e creditar o buffer. Recalcular o subestado com a regra de suprimento do canteiro. A entrega não avança progresso nem incorpora materiais.
4. Conferir todo o saldo projetado, lotes, pesos, revisão de reservas e claims de pares. Para cada recurso entregue, a redução física e do trânsito deve igualar o crédito de buffer. O total trânsito + buffer, o déficit descoberto, as reservas e o incorporado permanecem iguais. O saldo físico residual deve corresponder à soma dos lotes.
5. Quando o claim termina, desconectar seu listener depois das verificações e antes do commit. Nos caminhos de rollback, a conexão original conserva a posição e as flags, pois permanece conectada durante os estágios falháveis. Registrar o recibo depois de confirmar as invariantes e antes de publicar qualquer sinal.

Os seis checkpoints de falha são `before_ledger_debit`, `after_ledger_debit`, `after_carry_deduction`, `after_claim_deduction`, `after_buffer_credit` e `during_final_invariants`. Se um teste interrompe a operação depois da primeira mudança, o coordenador restaura buffer, subestado, indicador de suprimento, dados da mochila, ledger e claim. As revisões da mochila e do canteiro avançam, evitando ABA. Uma recusa antes da primeira mudança conserva também essas revisões. Os testes comparam snapshots, conexões, estoque físico, reservas, recibos, guardas e sinais. A repetição do ID após falha pré-commit ainda pode concluir uma única operação.

## Publicação de sinais

A ordem observada é `load_changed`, `buffer_changed`, `state_changed` e `supply_completed` na passagem ao suprimento completo. O coordenador suprime temporariamente o eco da mochila no canteiro e nos pares. Os sinais de reserva e estoque da pilha não são disparados. Os observadores veem os saldos finais e o recibo comprometido. O commit é definitivo quando começa a publicação.

**`DEC-T3.6-SIGNALS-01` continua pendente.** A candidata, como a C2-R1, conserva as guardas durante a publicação. A arquitetura R2 propõe liberar as guardas antes dos sinais. O documento normativo permanece sem edição.

## Cobertura

A [suíte C3.2](../../tests/integration/test_t3_6_2_c3_2_selective_delivery_transaction.gd) usa saques C2-R1 reais, coleta livre B3.2, mochilas reais e o teste físico de alcance no `World3D` do fixture. A atribuição da ordem e a posição inicial no fixture são preparadas diretamente. Os testes de entrega não simulam o trajeto autônomo do trabalhador. Os casos de corrupção controlada alteram explicitamente um campo de histórico, geração, peso, claim ou buffer por vez. A regressão segmentada também executa os fluxos legados e de navegação.

| Área | Evidência |
| --- | --- |
| Entrega | Débitos parciais e completos, dois lotes de madeira, madeira e pedra, pedido máximo e exato, recusa de excesso, transição ao suprimento completo |
| Conservação | Carga livre, dois canteiros e dois trabalhadores, comparação de histórico, pesos, reservas, buffer e claims |
| Autorização | Movimento desde a preparação, alcance, papel, ordem ativa e ordem de outra obra, interrupção, unidade na fila de destruição, região incompatível e mundo separado |
| Atomicidade | Seis estágios de falha, snapshots completos, listener preservado, guardas liberadas e replay após sucesso |
| Concorrência | C2 durante C3, C3 durante C2, C3 durante C3, conflito de tipos, isolamento de região e mundo, IDs simulados e definitivos ocupados |
| Notificações | Ordem e quantidades observadas nas callbacks, recibo disponível, zero eco no alvo e nos pares, nenhuma publicação em rollback |
| Revalidação | Plano alterado, mudança de mochila ou canteiro, ABA de capacidade e replay do plano aceito com chaves em ordem diferente |

## Validação

| Comando | Resultado |
| --- | --- |
| `tools/run_tests.ps1 -Filter test_t3_6_2_c3_2` | 8/8 testes, 1 suíte, 360 asserções |
| `tools/run_tests.ps1 -Filter test_t3_6_2_c3_1` | 6/6 testes, 1 suíte, 161 asserções |
| `tools/run_tests.ps1 -Filter test_t3_6_2_c2` | 16/16 testes, 1 suíte, 651 asserções |
| `tools/run_tests.ps1 -Filter test_t3_6_2` | 52/52 testes, 7 suítes, 1.656 asserções |
| `tools/validate.ps1` | 136 scripts verificados, importação e inicialização headless aprovadas |
| `tools/run_tests.ps1 -Segmented` | 341/341 testes, 49 suítes, 14.689 asserções, 11 lotes aprovados. 49 descobertas e 49 executadas uma vez, zero omissões ou duplicatas |
| `git diff --check` | Aprovado |

Versão efetiva `4.7.2.stable.official.ed1daf0bf`. Os executores encerraram com código 0 e sem erros de suíte, erros ou avisos Godot, incluindo avisos de vazamento de objetos.

Na primeira execução da nova suíte, a validação de recibos legados rejeitou IDs de objetos `RefCounted` que o Godot representa como inteiros negativos. O contrato foi corrigido para exigir IDs não nulos e o caso foi reexecutado.

## Arquivos e limites

- Produção: [coordenador de entrega](../../src/economy/selective_site_delivery_coordinator.gd), seu `.uid`, [autoridade compartilhada](../../src/economy/reserved_withdrawal_coordinator.gd) e [planejador contábil](../../src/economy/selective_site_delivery_planner.gd).
- Testes: [suíte C3.2](../../tests/integration/test_t3_6_2_c3_2_selective_delivery_transaction.gd), [suíte C3.1](../../tests/integration/test_t3_6_2_c3_1_selective_delivery_prep.gd), [fixture comum](../../tests/framework/selective_site_delivery_fixture.gd) e os novos `.uid`. A C3.1 substitui a expectativa antiga de recusa por colisão artificial pela prova de ID alternativo, sem remover a recusa de exceder o buffer.
- Documentação: este relatório.

O incremento fica acessível por chamada explícita. A busca por chamadas em produção encontrou somente as declarações da API. Os caminhos de `ConstructOrder`, `DeliverToCampOrder`, cancelamento, descarga no acampamento, persistência, UI e C3.3 permanecem fora desta autorização. Os recibos têm o ciclo de vida da sessão. Destruição arbitrária de nós ou encerramento forçado seguem fora da garantia transacional. A preparação revalida e clona o histórico em memória e não houve benchmark desse custo para sessões longas.

O commit de implementação é `f584b83289c1ec16d256062112d4edb1b79383ac` e o de testes é `e53a3435064ffb66167e63fb7c1165907e77c410`. Este relatório acompanha os dois na branch candidata.

A candidata aguarda auditoria independente. A validação automatizada foi headless. Não houve validação manual ou homologação.
