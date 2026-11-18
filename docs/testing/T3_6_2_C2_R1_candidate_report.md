# T3.6.2-C2-R1 — Exclusão transacional e autoridade regional

Candidata para auditoria independente. Base local e remota conferida em `019760022e6af12d41b65be524c5df74da40b291`, na branch `feat/t3-6-2-provenance-transactions`. Worktree `C:\Projetos\Dawn_of_Kin_wt_t3_4_5` inicialmente limpo. Commit técnico `3554c763d02604f14cd10ae8a0e0485fecd592be`. Main de referência `25e0a20f1d6a2f10a9e059afe69759fbe263db4a`.

## C2-R1-A — Capacidade e exclusão

Os testes de reprodução foram executados com o código de produção da base. Os 10 testes C2 originais passaram e os três novos falharam. No hook após dedução da pilha, os três mutadores aceitaram a tentativa. A capacidade-base caiu de 20 para 9, a capacidade efetiva caiu de 23 para 9, a revisão subiu de 2 para 5 e ocorreram três sinais de capacidade antes do rollback. A restauração da pilha e a ausência de recibo não restauraram a configuração da mochila. Durante os sinais do commit, observadores viram capacidades efetivas entre 33 e 38, com quatro notificações de capacidade indevidas.

A C2 adquire uma guarda específica na mochila, além da guarda de proveniência. Os três mutadores de capacidade retornam falso durante essa janela, inclusive em chamadas sem alteração efetiva. A guarda bloqueia também a abertura e o fechamento de lotes de notificação. Testes verificam capacidade-base, capacidade efetiva, modificadores, revisões, peso, saldo, claim, recibo e sinais. Após rollback ou publicação, alterações legítimas voltam a funcionar.

A B3.2 usa a guarda de proveniência. Seu hook continua realizando a sequência 20 → 19 → 20 e invalida o plano pela revisão. A suíte original passou com os mesmos quatro testes e 79 asserções na base e na candidata.

## C2-R1-B — Identidade e retenção

Na base, um segundo coordenador não encontrou o recibo para a mesma solicitação. Após trocar os objetos auxiliares, um pedido de outro trabalhador com o mesmo ID de operação chegou a confirmar um novo saque. A tentativa seguinte de reaproveitar o lote original foi recusada pela falta de claim elegível, sem diagnóstico de lote duplicado. A reentrada pelos sinais do mesmo canteiro era barrada pela guarda local do site, sem exclusão compartilhada do coordenador.

Um `World3D` vivo agora possui uma autoridade por `region_id` em metadados internos. A associação é resolvida pelo canteiro real, seu inventário e o `GroundPileManager` com raiz de pilhas no mesmo mundo. Sites vivos no mesmo domínio devem apontar para o mesmo inventário e fonte física. Um gerenciador já associado a mundo e região vivos recusa nova associação conflitante. Domínio inválido ou ambíguo é recusado antes de replay ou movimentação. A API usa a thread principal e mantém sua afinidade de instância.

A autoridade compartilha a guarda, os IDs de operação e os IDs de lote entre todas as instâncias do coordenador. Replay idêntico devolve o recibo com `replayed = true`, `withdrawn = 0` e o `committed_amount` original. Conflitos de parâmetros e reuso incompatível de lotes são recusados sem dedução. Os recibos têm vínculos fracos com site, trabalhador e mochila, além dos IDs e dados já validados. Consultas `is_busy`, `has_receipt` e `get_receipt` referem-se ao último domínio resolvido pelo objeto auxiliar.

A autoridade permanece sob o mundo após a destruição dos objetos auxiliares. Referências fracas impedem que recibos mantenham participantes, gerente ou mundo vivos. A suíte verificou a liberação da autoridade e do mundo ao destruir o `SubViewport`, e que outro mundo continuou aceitando replay. Cada mundo e cada região independente podem usar os mesmos rótulos de operação e lote sem compartilhar saldos. A substituição do gerenciador em um domínio com histórico vivo é recusada, pois exigiria um protocolo próprio para transferir a identidade econômica.

## C2-R1-C — Política de sinais

A proposta T3.6-R2 §4 prevê liberar guardas antes das notificações. A C2-R1 mantém a exclusão cooperativa até a última notificação. Liberar primeiro, sem uma barreira adicional, permitiria que o primeiro observador alterasse a capacidade, abrisse um lote de sinais ou iniciasse outra transação antes de os demais consultarem o commit. Guardas mantidas preservam o mesmo estado e o recibo durante a publicação, com consultas disponíveis e recusa imediata de mutação. Um observador que precise executar outra operação pode agendá-la para depois do retorno.

A ordem observada é aplicação econômica silenciosa, verificação, avanço das revisões de commit e registro do recibo, atualização visual ou retirada da pilha exaurida, sinais econômicos e liberação reversa. Os sinais encaminhados pelo inventário mantêm a revisão da operação e a supressão de eco do canteiro permanece até o fim. A pilha altera quantidade e exposição sem atualizar visuais no estágio provisório. Em rollback, os visuais permanecem no estado inicial. Observadores de visibilidade e de saída da árvore veem saldos completos e recibo. Os mutadores públicos testados incluem mudanças de pilha, lotes de sinais, troca de estoque, limpeza, identidade do canteiro, conclusão e cancelamento da ordem corrente.

A regra segue a arquitetura R2 quanto à publicação após commit irreversível e difere quanto ao instante da liberação. A referência arquitetural foi preservada, e uma eventual atualização normativa depende de decisão do proprietário. No GDD v1.2, D2, D9, DEC-11A/B e D3 mantêm seus contratos. A aplicação permanece opt-in e o fluxo legado é coberto por testes.

## Evidência automatizada

Em uma execução intermediária, as fixtures reutilizavam o mundo padrão após descarte do gerente. A retenção de domínio recusou a reutilização, e um teste ainda consultava o índice antigo da instância. As fixtures passaram a criar mundos próprios por caso e o teste consulta o índice regional, preservando a asserção. Foi corrigida também a tipagem das referências fracas da fixture e a passagem de uma pilha já liberada a `_release_guards`. A pilha agora consulta a guarda do gerente por referência fraca e a liberação da guarda independe da vida do nó de pilha. A checagem estática inicial também acusou objetos e recursos em uso no encerramento de selection_box_math.gd. A falha foi reproduzida com o mesmo executor do projeto. Foram removidas as novas dependências de tipo em sentido inverso entre unidade e ordem de construção e entre pilha e seu gerente. As checagens de guarda continuam ativas e a checagem direta passou após esse ajuste. A execução segmentada iniciada antes do ajuste terminou com código 1 no executor, que marcou o lote unitário como FAIL apesar de o processo Godot retornar zero, sem falha de asserção ou timeout. Os resultados de aceite abaixo são da nova execução integral com o código final.

Os cinco pontos originais de falha pré-commit continuam exercitados e checam snapshots econômicos, ausência de recibo e ausência de sinais. Os novos casos verificam capacidade na aplicação e nos cinco sinais solicitados, exclusão do segundo coordenador, replay e colisões, ciclo de vida, regiões e mundos, saída de pilha exaurida e visibilidade. A suíte original ainda compara os seis sinais econômicos, incluindo as duas notificações encaminhadas pelo inventário.

Godot `4.7.2.stable.official.ed1daf0bf`.

| Verificação | Resultado |
|---|---|
| `tools/run_tests.ps1 -Filter test_t3_6_2_c2` | 16/16 testes em 1 suíte, 651 asserções. As seis regressões R1 estão nesta suíte. |
| `tools/run_tests.ps1 -Filter test_t3_6_2_b3_2` | 4/4 testes em 1 suíte, 79 asserções. |
| `tools/run_tests.ps1 -Filter test_t3_6_2` | 38/38 testes em 5 suítes, 1.135 asserções. |
| `tools/validate.ps1` | 131 scripts verificados, importação e inicialização headless aprovadas, zero erros e avisos na execução final. |
| `tools/run_tests.ps1 -Segmented` | 327/327 testes em 47 suítes, 14.168 asserções e zero falhas ou erros de suíte. Dez lotes aprovados, 47 suítes descobertas e executadas uma vez, sem omissões ou duplicatas. |
| `git diff --check` | Aprovado. |

## Arquivos

- [Coordenador](../../src/economy/reserved_withdrawal_coordinator.gd), [mochila](../../src/economy/unit_carry_load.gd) e [inventário](../../src/economy/settlement_inventory.gd).
- [Gerente de pilhas](../../src/economy/ground_pile_manager.gd) e [pilha física](../../src/economy/ground_resource_pile.gd), para proteger mutadores e publicar visuais após a dedução confirmada.
- [Canteiro](../../src/buildings/construction_site.gd), [gerente de construção](../../src/buildings/construction_manager.gd) e [unidade](../../src/units/unit.gd), para preservar participantes e ordem durante callbacks.
- [Suíte C2](../../tests/integration/test_t3_6_2_c2_reserved_withdrawal_transaction.gd).

## Limites e pendências

Implementado e verificado automaticamente em Godot headless. Validação manual e gráfica não executada. A exclusão é cooperativa. Destruição direta de participantes por código externo, escrita em campos internos ou alterações diretas em recursos compartilhados não são transações suportadas. O histórico C2 permanece em memória durante a vida do mundo e ocupa espaço proporcional ao número de operações. Migração de gerenciador, persistência, entrega seletiva e cancelamento D3 estão fora deste incremento. A C3 permanece bloqueada até autorização própria. A candidata segue para auditoria independente e decisão do proprietário.
