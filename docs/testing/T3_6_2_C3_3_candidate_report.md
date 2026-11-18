# T3.6.2-C3.3 — Ciclo de construção com proveniência opt-in

**Candidata para auditoria independente.** Base `51c29d75f67d974a2c5deb7a2a3d9ca3cb7d3e2b`, branch `feat/t3-6-2-provenance-transactions` e worktree existente `C:\Projetos\Dawn_of_Kin_wt_t3_4_5`. A referência da `main` no início foi `25e0a20f1d6a2f10a9e059afe69759fbe263db4a`.

## Contratos consultados

Foram confrontados [AGENTS.md](../../AGENTS.md), o [GDD v1.2](../Dawn_of_Kin_GDD.md) para D2, D3, D9, DEC-11A/B e DEC-18/19, a [arquitetura T3](../architecture/T3_architecture_PROPOSAL.md), o [plano T3.4-R2.3](https://github.com/Julian0s/Dawn-of-Kin/blob/da20244f4320f0ae5e03236553f5c0e3f57f3a6f/docs/architecture/T3_4_implementation_plan_PROPOSAL.md) e a [proposta T3.6-R2, revisão 69c1327](https://github.com/Julian0s/Dawn-of-Kin/blob/69c13275a34a30564ac839ec920f83ef36590812/docs/architecture/T3_6_cancellation_architecture_R2_PROPOSAL.md). A C3.3 é uma subdivisão de implementação autorizada e a R2 continua uma referência arquitetural com questões abertas.

Foram comparados o [protocolo manual T3.3](T3_3_manual_test_protocol.md), os aceites [T3.3](T3_3_closeout_ACCEPTANCE.md), [T3.4.5](T3_4_5_closeout_ACCEPTANCE.md), [T3.5.1](T3_5_1_closeout_ACCEPTANCE.md), [T3.5.2](T3_5_2_closeout_ACCEPTANCE.md) e os incrementos de proveniência [A](T3_6_2_A_candidate_report.md), [B1](T3_6_2_B1_candidate_report.md), [B2](T3_6_2_B2_binding_candidate_report.md), [B3.1](T3_6_2_B3_1_candidate_report.md), [B3.2](T3_6_2_B3_2_candidate_report.md), [C1-R1](T3_6_2_C1_R1_candidate_report.md), [C2-R1](T3_6_2_C2_R1_candidate_report.md), [C3.1](T3_6_2_C3_1_candidate_report.md) e [C3.2](T3_6_2_C3_2_candidate_report.md). A ordem atual usa a autoridade econômica e os contratos efetivos de saque e entrega desses incrementos.

## Admissão, papéis e divergências encontradas

[ConstructOrder](../../src/units/orders/construct_order.gd) recebe um quarto argumento opcional, `p_use_provenance_transactions`, com padrão `false`. O argumento define o modo na criação da ordem. A mochila é habilitada separadamente pela fixture, antes de iniciar o trabalho. O ponto de entrada RTS continua usando o construtor no modo padrão. Uma ordem opt-in em mochila comum falha com `provenance_required`. Uma ordem padrão em mochila com proveniência falha com `provenance_opt_in_required`. A ordem verifica o modo novamente em execução para evitar cruzar a fronteira de transferência se uma mochila vazia for habilitada externamente enquanto a ordem já estiver ativa.

O D9 vigente mantém o transportador quando novos construtores são adicionados, permite promoção depois de suprir a obra e limita a equipe automática a um transportador e dois construtores. Uma atribuição nova pode transformar em `BUILDER` a unidade que ainda carrega um claim interrompido, caso o papel de transporte já esteja ocupado. O legado deixaria esse construtor entregar o claim. A C3.2 autoriza somente `TRANSPORTER` e `SOLO_SUPPLIER`. O opt-in recusa o caso com `provenance_builder_cargo_blocked` e conserva carga e claim para uma atribuição autorizada posterior. As regras e limites de promoção do canteiro permanecem aplicáveis.

O retorno genérico ao acampamento exige despejar a mochila inteira. Quando uma ordem opt-in precisa desse retorno, encerra com `selective_camp_delivery_required` antes de criar a subordem de entrega no acampamento. Uma carga mista que tem claim para a obra atual ainda pode entregar seus lotes elegíveis. Lotes livres e de outras obras conservam a origem. Um transportador forçado pode terminar o suprimento com a carga alheia ainda na mochila quando o canteiro já estiver suprido.

## Transferências e retentativas

1. A ordem seleciona e reclama uma parcela da pilha. No alcance físico, recalcula reserva restante, necessidade do canteiro, peso e capacidade. O modo opt-in invoca o [saque C2-R1](../../src/economy/reserved_withdrawal_coordinator.gd). O coordenador registra o lote e o claim no mesmo commit. A ordem continua pela fase de transporte após o retorno do coordenador.
2. Na chegada ao perímetro, a ordem chama a [entrega C3.2](../../src/economy/selective_site_delivery_coordinator.gd) com pedido vazio para transferir o máximo elegível. A API revalida o plano C3.1 e a autorização física e operacional sob guarda. A entrega registra uma viagem e a quantidade efetiva quando `delivered_now > 0`. Replays recuperam o resultado sem registrar uma viagem adicional.
3. A [sessão de transferência da ordem](../../src/units/orders/construction_transfer_session.gd) mantém um único intento operacional. Cada transferência obtém um serial crescente da autoridade regional que C2 e C3 já compartilham. O ID inclui mundo, região, instância e geração da obra, unidade, ordem, tipo e, para saque, pilha e recurso. O ID do lote deriva do intento de saque. A alocação verifica recibos regionais e o histórico da mochila, aceitando IDs de instância com sinal. As APIs C2 e C3 conferem novamente as identidades no commit. A alocação não altera o saldo.
4. `busy` congela os parâmetros e IDs do intento e permite até quatro retentativas, espaçadas por 0,25 s de simulação. A prontidão da navegação continua sendo exigida para conduzir a ordem. A identidade do mundo, região, obra, geração, reserva, unidade, mochila, ordem e tipo de operação é congelada junto com a intenção. Uma alteração invalida a retentativa com `transaction_identity_changed`. Uma recusa definitiva encerra a operação com o diagnóstico do coordenador. Uma resposta indeterminada exige consulta ao recibo e replay do mesmo ID ou termina com `unknown_transaction_outcome`. Uma nova ordem recebe outro serial, e a carga já vinculada ao canteiro é considerada antes de selecionar nova pilha.
5. Ao substituir ou cancelar a ordem, o canteiro libera o claim pendente de retirada e a atribuição operacional. O claim em trânsito e os lotes já comprometidos permanecem. A ordem seguinte usa o estado econômico efetivo. Os caminhos de falha deixam a mochila carregada enquanto o trabalhador e a sessão continuam vivos.

## Notificações e navegação

Durante uma transferência própria ou uma publicação com o canteiro sob guarda, a ordem opt-in marca o replanejamento e evita novos estágios econômicos, movimento ou cancelamento provocado por um callback. Em seguida, a atualização física reavalia a posição, a carga e o papel. Saque e entrega não encadeiam um segundo commit no mesmo callback. A ordem desconecta os sinais de canteiro e navegação no encerramento. A sessão guarda IDs e parâmetros, e os coordenadores usam referências fracas ao domínio.

**DEC-T3.6-SIGNALS-01 segue pendente.** A C3.3 conserva a ordem efetiva de publicação C2-R1/C3.2, com guardas ativas até o fim dos sinais. A proposta R2 prevê liberação antes de notificar. A candidata segue a política em vigor e preserva os documentos normativos.

## Evidências e regressões

A [suíte C3.3](../../tests/integration/test_t3_6_2_c3_3_order_integration.gd) instancia a cena principal e o `TestMap` em mundos isolados. O trabalhador recebe a ordem por `Unit.issue_order()`. O ciclo roda com `ConstructOrder.start()` e a atualização física real do `Unit`. O cenário central registra distâncias entre retirada e entrega, carga durante o deslocamento, peso de madeira e pedra, redução de velocidade e abastecimento no perímetro. O Abrigo Básico termina com 12 madeiras e 6 pedras incorporadas. A fixture adiciona apenas o estoque físico inicial ao acampamento.

| Área | Evidência |
| --- | --- |
| Ciclo real | Saques da pilha, transporte com mochila carregada e entrega ao perímetro observados por notificações sob guarda e pelo deslocamento na NavMesh |
| D9 | Fornecedor solo, transportador, montagem com dois construtores, limite do quarto, recusa segura de construtor com claim em trânsito e retomada autorizada |
| Interrupção e conservação | Ordem manual, cancelamento, outra obra, carga livre misturada, geração divergente, destino inacessível, perda da pilha por deterioração |
| Navegação transitória | Blocker controlado no trajeto da fixture, espera com cargo e continuação ao sinal de prontidão. O rebake real permanece coberto pela regressão T3.4.5 |
| Transações | Rollback da C2 por falha após alteração da mochila, `busy` com limite e intervalo, replays C2 e C3 com outro coordenador usando o intento congelado, conflito entre tipos de recibo e geração que muda durante `busy` |
| Reentrância | Atualizações e cancelamento reentrantes durante `load_changed`, `state_changed` e `buffer_changed` sem mudança de fase nem contagem duplicada |
| Compatibilidade | Admissão fail-closed nos modos incompatíveis, ordem padrão usando fluxo legado, regressões C2-R1, C3.1, C3.2, logística T3.3, montagem T3.4 e navegação |

No desenvolvimento, a primeira rodada apontou acesso a sinais de um canteiro já liberado na limpeza da suíte. A limpeza passou a conferir o ID do emissor. O caso D9 passou a reservar material suficiente para manter o substituto ativo enquanto o primeiro trabalhador carrega seu claim. O blocker transitório passou a cruzar a rota sem conter o alvo, reproduzindo `pending_building_nav_sync` em vez da recusa para alvo dentro do blocker.

## Validação

| Comando | Resultado |
| --- | --- |
| `tools/run_tests.ps1 -Filter test_t3_6_2_c3_3` | 10/10 testes, 1 suíte, 328 asserções |
| `tools/run_tests.ps1 -Filter test_t3_6_2_c3_2` | 8/8 testes, 1 suíte, 360 asserções |
| `tools/run_tests.ps1 -Filter test_t3_6_2_c3_1` | 6/6 testes, 1 suíte, 161 asserções |
| `tools/run_tests.ps1 -Filter test_t3_6_2_c2` | 16/16 testes, 1 suíte, 651 asserções |
| `tools/run_tests.ps1 -Filter test_t3_6_2` | 62/62 testes, 8 suítes, 1.984 asserções |
| `tools/validate.ps1` | 138 scripts, importação e inicialização headless aprovadas. Zero erros ou avisos |
| `tools/run_tests.ps1 -Segmented` | 351/351 testes em 50 suítes, 15.016 asserções, 11 lotes aprovados, 50 descobertas e 50 executadas uma vez, zero omissões ou duplicatas |
| `git diff --check` | Aprovado |

Godot `4.7.2.stable.official.ed1daf0bf`. A execução segmentada foi refeita após adicionar a verificação de identidade da retentativa. Os resultados da tabela são da revisão final. Todos os executores terminaram com código 0, sem falhas, erros de suíte, avisos Godot ou diagnósticos de vazamento de objetos.

## Arquivos e limites

- Produção: [ConstructOrder](../../src/units/orders/construct_order.gd), [sessão de transferência](../../src/units/orders/construction_transfer_session.gd), seu `.uid` e [alocação na autoridade regional da C2-R1](../../src/economy/reserved_withdrawal_coordinator.gd).
- Testes: [suíte de integração da ordem C3.3](../../tests/integration/test_t3_6_2_c3_3_order_integration.gd) e seu `.uid`.
- Documentação: este relatório.

A candidata usa ativação explícita e rotas de teste. A evidência de navegação é automatizada em Godot headless e a validação manual jogável permanece pendente. A descarga seletiva no acampamento, cancelamento D3, custódia, reembolso, persistência, migração legada, proteção contra destruição arbitrária de unidades carregadas, limitação e benchmark de histórico de longa duração e ativação global permanecem fora do incremento. T3.6.3 e T3.6.4 continuam bloqueadas. A candidata aguarda auditoria independente.

A implementação está em `2e4af4a74af8e2b508646852bbda90e4b6e06e66` e os testes em `35b2e70ef1634836ec8e979251c13c87bf6f69dd`. Este relatório acompanha ambos na branch candidata.
