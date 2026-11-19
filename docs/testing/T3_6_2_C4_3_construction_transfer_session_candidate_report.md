# Dawn of Kin — Candidata T3.6.2-C4.3

Endurecimento R4 das sessões opt-in de saque reservado e de entrega ao canteiro.

## Base e escopo

- Branch `feat/t3-6-2-provenance-transactions`. HEAD local e ponta remota conferidos em `79f36ccff979c3273ae0ab52f825b45655ffd3cf`, com árvore limpa no início.
- Worktree `C:/Projetos/Dawn_of_Kin_wt_t3_4_5`. `main` remota de referência `25e0a20f1d6a2f10a9e059afe69759fbe263db4a`. Validação em Godot `4.7.2.stable.official.ed1daf0bf`, em modo headless.
- A revisão seguiu o [AGENTS](../../AGENTS.md) e o [GDD v1.2 §4.2–4.3](../Dawn_of_Kin_GDD.md). Foram consultados a [proposta T3.6-R2 no commit 69c1327](https://github.com/Julian0s/Dawn-of-Kin/blob/69c13275a34a30564ac839ec920f83ef36590812/docs/architecture/T3_6_cancellation_architecture_R2_PROPOSAL.md), os relatórios [C3.2](T3_6_2_C3_2_candidate_report.md), [C3.3](T3_6_2_C3_3_candidate_report.md), [C3.4.3](T3_6_2_C3_4_3_candidate_report.md) e [C3.5](T3_6_2_C3_5_candidate_report.md), a [inspeção C4.1](T3_6_2_C4_1_readiness_inspection_report.md) e a [candidata C4.2](T3_6_2_C4_2_lifecycle_readiness_candidate_report.md).

## Reprodução e correção

Foi usada a [suíte C4.3](../../tests/integration/test_t3_6_2_c4_3_construction_transfer_session.gd), com canteiros, pilhas, mochila, claims e coordenadores reais do fixture C3.2. O fixture posiciona a unidade na distância autorizada e arma a ordem, para isolar o contrato transacional. O dublê de sessão só simula a perda ou ausência de resposta. Quando o cenário tem commit, ele passa pelo coordenador de produção. A logística e a substituição em movimento também são exercitadas pela regressão C3.3 com navegação real.

| Risco | Evidência RED na C4.2 | Contrato GREEN |
|---|---|---|
| R4-A — identidade em `busy` | Pedidos com quantidade, recurso ou pilha trocados retornaram `busy` e alteraram o estado do intento. Um pedido de entrega conflitante descartou o ID e o lote de saque pendentes. | A sessão congela tipo e parâmetros de saque, mundo, região, obra, geração, reserva, unidade, mochila, ordem, inventário e armazenamento. Conflito preserva o pedido congelado, os saldos e o contador. O retry com o payload original usa o mesmo ID e saca 2. |
| R4-B — entrega comprometida por outro handle | O coordenador externo creditou 2 ao buffer. O handle da sessão não encontrou o recibo e reportou resultado incerto. A retirada equivalente já era reconhecida porque seu alocador havia resolvido o domínio no próprio handle. | Consultas por mundo, região, ID e tipo usam as validações de recibo existentes, com cópia destacada. A confirmação do intento compara seus participantes e parâmetros congelados. Saque e entrega reconciliados retornam delta zero, sem nova chamada executora. |
| R4-C — incerteza sem recibo | O ID foi apagado. Repetir o mesmo pedido na sessão alocou outro serial e sacou 2: a pilha caiu de 20 para 18 e a reserva de 4 para 2. O teste reproduziu uma nova execução indevida, sem demonstrar duas retiradas físicas naquele cenário. | A sessão mantém o ID original e permite apenas releitura. Sem recibo correspondente, retorna `unknown_transaction_outcome`. Um recibo posterior pode confirmar o mesmo commit com delta zero. Sem intervenção externa, a ordem encerra conforme o comportamento existente. |
| R4-C/D — encerramento e pós-commit | Com a ordem cancelada, o handle antigo ainda alocava serial em chamadas tardias. Os coordenadores recusaram mutação devido à falta de atribuição ou elegibilidade. | O encerramento sela a sessão, desagenda retries e conserva os dados do intento pendente para consulta. O commit anterior permanece no domínio. Chamadas tardias não alocam serial. Uma retentativa com geração trocada ou canteiro removido é recusada antes de executar o coordenador. |

No baseline, `run_tests.ps1 -Filter test_t3_6_2_c4_3` terminou com exit 1, **0/4 testes aprovados, 99 asserções, zero erros de suíte**. Os quatro testes originais passaram após a implementação com as mesmas 99 asserções. Foram acrescentadas verificações do recibo no cancelamento e quatro casos de fronteira: confirmação tardia, geração/remoção, dois domínios no mesmo mundo com o mesmo ID e reentrada durante `load_changed`.

## Fronteira transacional

- A [sessão](../../src/units/orders/construction_transfer_session.gd) só cria um intento para uma ordem ativa e participantes vivos no mesmo mundo. Em `busy`, conserva o ID quando já alocado. Quando a própria alocação está ocupada, conserva os parâmetros e aguarda a primeira alocação. O intervalo de 0,25 s e o limite de quatro retries permanecem.
- [Saque reservado](../../src/economy/reserved_withdrawal_coordinator.gd) e [entrega seletiva](../../src/economy/selective_site_delivery_coordinator.gd) expõem leituras específicas por domínio. A busca não cria autoridade, não avança serial, não registra lotes e não altera o domínio lembrado pelo handle. Região, mundo, tipo e operação são conferidos mesmo em consultas que não podem efetuar uma transferência.
- Resultado incerto usa os metadados congelados e a referência fraca ao mundo para ler o recibo. Um recibo de entrega precisa corresponder à identidade completa e ao pedido padrão da sessão (`requested_amounts={}`). Um recibo de saque precisa corresponder ao canteiro, à reserva, à geração, à unidade, à mochila, à pilha, ao recurso, à quantidade e ao lote. A leitura produz o mesmo resultado de replay dos coordenadores, com `withdrawn=0` ou `delivered_now=0`. A confirmação de um commit passado dispensa readmitir o canteiro.
- [ConstructOrder](../../src/units/orders/construct_order.gd) sela a sessão na mesma rotina de encerramento que já desconecta os sinais. Durante a publicação, a reentrada encontra a guarda da sessão e as guardas existentes da ordem e dos coordenadores. A política `DEC-T3.6-SIGNALS-01` segue pendente.

A prova econômica compara snapshots da pilha, livro de reservas, mochila/ledger, claims, revisões de armazenamento e recibos. No caso de conflito, verificou a reserva de 3 madeiras na obra B. No saque seguido de entrega reconciliados, foram 20 madeiras iniciais e finais somando pilha, mochila e buffer, dois recibos, um lote comprometido. O replay de confirmação adicionou zero unidades. A C3.3 cobre replays ordinários, cancelamento em movimento, espera por navegação, falha com rollback, fim da contenção e conclusão da rota de construção.

## Validação executada

| Comando | Resultado |
|---|---|
| `run_tests.ps1 -Filter test_t3_6_2_c4_3` sobre a base | RED conforme acima |
| `run_tests.ps1 -Filter test_t3_6_2 -TimeoutSeconds 240` | Exit 0. 14 suítes, 129/129 testes, 9.618 asserções, zero falhas e erros de suíte. |
| `run_tests.ps1 -Filter test_t3_6_2_c4_3` sobre a candidata | Exit 0. 8/8 testes, 189 asserções, zero falhas, erros ou avisos. |
| `run_tests.ps1 -Segmented -GroupTimeoutSeconds 240` | Exit 0. 13/13 lotes, 57 suítes descobertas e executadas, 426/426 testes, 24.397 asserções. Zero falhas, erros de suíte, diagnósticos Godot, omissões ou duplicatas. |
| `validate.ps1` | Exit 0. Importação e inicialização headless, 151 scripts verificados, zero erros ou avisos. |
| `git diff --check` | Exit 0. |

No filtro T3.6.2, C2 passou 16/16 (651 asserções), C3.2 passou 8/8 (360), C3.3 passou 10/10 (328), C3.4.3 passou 8/8 (1.187), C3.5 passou 6/6 (964) e C4.2 passou 8/8 (226). As contagens por suíte fazem parte do total do filtro. As execuções focada e segmentada têm cobertura sobreposta. Asserções em laços por quadro podem variar entre execuções, como no Grupo B da C3.5 (417 no filtro e 408 na segmentada).

## Arquivos e limites

O commit técnico `f1e1f2e8b15a1ddd708b7023f9d0e91ac33849e6` reúne `ConstructionTransferSession`, `ConstructOrder`, os dois coordenadores de saque e entrega à obra, a suíte C4.3 e seu `.uid` de Godot. Este relatório pertence a um commit documental separado.

Recibos continuam em memória pelo ciclo de vida do domínio regional. Se o domínio foi desmontado e seu recibo não está mais acessível, a sessão preserva o diagnóstico de resultado incerto e não reexecuta o intento. A retirada ou destruição arbitrária de nós, as regras de elegibilidade econômica, a política de sinais, as demais sessões de coleta/acampamento e o fluxo legado conservam os contratos existentes.

Permanecem fora deste incremento D-INT-01/02/03, P2–P4, P6, R3, ativação global, migração legada e cancelamento D3.

**Parecer.** A C4.3 está pronta para auditoria independente. A reprodução RED, os replays de delta zero e a regressão completa sustentam o aceite técnico da candidata para revisão.
