# T3.6.3-B1.2 — Commit interno de cancelamento D3

Base `9babe27cfd6a6dc3284a40448c2016a67f05b7f0`, branch `feat/t3-6-3-cancellation-custody`. Godot 4.7.2 stable no Windows.

## Fronteira e conservação

A preparação consulta o registro do gerenciador, estado `ACTIVE`, geração, região, `World3D`, participantes e revisões. Compara a reserva agregada às alocações nas pilhas físicas e reconcilia o trânsito com os lotes `SITE_RESERVED` das mochilas. A varredura inclui unidades com ordens substituídas e rejeita divergências entre claim, lote, mochila e identidade. A projeção econômica usa `ConstructionCancellationMath`.

O escopo B1.1-R1 mantém inventário e pilhas sob a guarda regional. B1.2 acrescenta guardas cooperativas para o gerenciador, os sites do inventário, o acampamento e as mochilas participantes. A ordem de aquisição é fixa e os participantes são ordenados por ID de instância. A preparação é repetida sob as guardas e comparada à previsão original. Planos obsoletos são recusados.

O fluxo validado libera `S` nas pilhas existentes, reclassifica em memória os lotes da obra para `CANCEL_TRANSIT`, transfere a responsabilidade por `B + K` à custódia local, registra perda e déficit e acrescenta o estado `CANCELLED` ao fim da enumeração do canteiro. A custódia armazena a relação entre IDs dos trabalhadores e dos lotes em trânsito. `A` e `H` ficam fora do estoque do acampamento e `E` começa em zero. A reserva e os lotes de outra obra ficam preservados.

O recibo e os índices são instalados antes do selo definitivo. O backend revalida sua aplicação e sela a transação antes de emitir o primeiro sinal. Todos os participantes estão sob guarda durante os sinais, conforme D-INT-02/A. Reexecutar a operação sobre o mesmo canteiro retorna o recibo original, e outra obra com o mesmo identificador de operação é recusada. A consulta regional do recibo permanece disponível enquanto a autoridade existir, mesmo após a remoção do nó.

Antes do selo, o rollback restaura o ledger original das mochilas, o estado, o buffer, o incorporado, os claims, os listeners e as atribuições. Os mapas e recibos provisórios são retirados e o escopo B1.1-R1 restaura a reserva silenciosamente. Progresso, ordens e temporizadores de conclusão ficam fora das mutações anteriores ao selo. As revisões dos participantes efetivamente revertidos avançam para invalidar planos antigos.

O canteiro bloqueia novas operações econômicas em `CANCELLED`. Ordens ativas de construção veem o canteiro como inválido e terminam sem prosseguir com saque, entrega ou montagem. A ocupação é mantida com custódia local. Apenas trânsito em mochilas permite liberar a área, conforme D-CANC-02/A. A posição e a referência visual nunca são usadas como autoridade de saldo.

## Evidências

O RED chegou a um canteiro ativo com reserva física e recebeu `d3_cancellation_not_implemented` na base. Foi 1 falha em 1 teste, com 6 asserções. As primeiras tentativas de montar esse RED exigiram corrigir a declaração de constantes e aguardar a navegação antes de abastecer o fixture.

O GREEN usa a cena principal e pilhas reais. Os cenários incluem 0%, reserva vazia legítima, deterioração de madeira com pedra intacta, duas obras e mochila mista com `MoveOrder` após o saque. Há injeção de falha depois da aplicação de reserva, carga, canteiro e registros. O teste compara os snapshots, as reservas, os claims, os listeners, as ordens e os sinais. A publicação usa callbacks que tentam replay, novo cancelamento, liberação da reserva vizinha e conclusão. O teste também verifica a sobrevivência da custódia e do recibo à remoção de um nó com apenas custódia em trânsito.

A montagem real chega a 50% e 90% antes da execução interna. Aos 90%, o abrigo tem 10 madeiras e 5 pedras incorporadas. O exemplo histórico com materiais integralmente incorporados a 90% é hipotético. A fórmula aplicada permanece `K = floor(C × (W − P) / (2 × W))`, conforme T3.6.1. Os estados de conclusão recusam cancelamento e preservam os diagnósticos de retry.

| Execução GREEN | Suítes | Aprovados | Asserções |
|---|---:|---:|---:|
| B1.2 | 1 | 4/4 | 201 |
| B1.1-R1 | 1 | 7/7 | 254 |
| T3.6.1 focada | 1 | 5/5 | 113 |
| T3.6.2 focada | 25 | 187/187 | 11.499 |
| Segmentada final | 70 | 495/495 | 26.739 |

A validação completa foi reiniciada após acrescentar a recusa e a cobertura de regiões distintas que compartilham o mesmo estoque físico. A execução final teve zero falhas e erros de suíte, sem omissões ou duplicatas. `validate.ps1` aprovou a importação, 166 scripts e a inicialização headless. Os logs GREEN não registraram erros, avisos ou vazamentos do Godot. `git diff --check` passou.

O commit técnico é `c95a97dd55fa297d3ffce2f615cdd0850b298110`. O commit documental que contém este relatório fixa a revisão final da candidata. [Branch candidata](https://github.com/Julian0s/Dawn-of-Kin/tree/feat/t3-6-3-cancellation-custody).

## Limites

O commit operacional desta etapa exige o backend de pilhas físicas. A implementação em memória continua coberta pelos testes das primitivas da B1.1-R1. O contrato interno tem chamadas de teste e segue sem entrada no RTS, no HUD ou na cena principal. A recuperação física, o redirecionamento automático, a proteção anterior ao teardown e a persistência seguem pendentes. D-CANC-01/A e D-INT-03/A permanecem aplicáveis aos seus respectivos fluxos.

[Transação](../../src/economy/site_cancellation_transaction.gd) · [Suíte B1.2](../../tests/integration/test_t3_6_3_b1_2_cancellation_commit_transaction.gd) · [Relatório B1.1-R1](T3_6_3_B1_1_R1_safety_review_candidate_report.md).
