# T3.6.3-B1.3 — Recuperação física e descarga transacional

Status: implementada e testada automaticamente como candidata técnica; aguardando auditoria independente. Não homologada.

## Base e escopo

- Base local/remota conferida antes da implementação: `933353e3fe8d70544f866e0e00ec54f9c154b5bc` (B1.2).
- Branch exclusiva: `feat/t3-6-3-cancellation-custody`.
- Worktree reutilizado: `C:\Projetos\Dawn_of_Kin_wt_t3_4_5`.
- Godot confirmado: `4.7.2.stable.official.ed1daf0bf`.
- `main` de referência: `25e0a20f1d6a2f10a9e059afe69759fbe263db4a`.
- Commit técnico desta candidata: `d40d6c28f5efabc0a6dacc330d5f4848058a18d6`.

Foram consultados AGENTS.md, GDD vigente, arquitetura T3, a proposta histórica T3.6-R2 e os relatórios [B1.1-R1](T3_6_3_B1_1_R1_safety_review_candidate_report.md) e [B1.2](T3_6_3_B1_2_cancellation_commit_transaction_candidate_report.md). A proposta histórica não foi promovida automaticamente a norma. A autorização específica da B1.3 cobre estas primitivas internas e seus testes.

Não foram alterados GDD, arquitetura, custos, fórmula D3 ou regras de coleta. Preservadas D-CANC-01/A, D-CANC-02/A, D-CANC-03/A e D-INT-01/B, D-INT-02/A, D-INT-03/A. Nenhuma interface ou ordem RTS passa a disparar recuperação ou cancelamento.

## Arquivos e APIs

| Arquivo | Alteração |
| --- | --- |
| [cancellation_recovery_transaction.gd](../../src/economy/cancellation_recovery_transaction.gd) | Novo helper transacional: preparação A→H, recuperação, reconciliação física, projeção H→E e ocupação da custódia |
| [reserved_withdrawal_coordinator.gd](../../src/economy/reserved_withdrawal_coordinator.gd) | Fachada `recover_cancellation_materials()`, âncora e pesos no registro, referências fracas e selo definitivo do escopo |
| [site_cancellation_transaction.gd](../../src/economy/site_cancellation_transaction.gd) | Registro espacial no cancelamento, colisor independente e correção do filtro regional |
| [selective_camp_delivery_planner.gd](../../src/economy/selective_camp_delivery_planner.gd) | Elegibilidade explícita de CANCEL_*, revisão/snapshot da custódia incorporado à preparação |
| [selective_camp_delivery_coordinator.gd](../../src/economy/selective_camp_delivery_coordinator.gd) | Atualização H→E dentro da transação existente, rollback conjunto e selo antes dos sinais |
| [construction_manager.gd](../../src/buildings/construction_manager.gd) | Consulta de footprint inclui custódias regionais sem nó visual |
| [placement_validator.gd](../../src/buildings/placement_validator.gd) | Proteção lógica e filtro regional do colisor de custódia |
| [test_t3_6_3_b1_3_physical_recovery.gd](../../tests/integration/test_t3_6_3_b1_3_physical_recovery.gd) | Suíte adversarial B1.3 com MainScene, navegação, mochilas e pilhas reais |

Incluídos os dois arquivos `.gd.uid` dos novos scripts. Os testes anteriores foram preservados.

### Retirada

`ReservedWithdrawalCoordinator.recover_cancellation_materials(cancel_id, unit, requests, operation_id, region_id = &"default")` delega ao helper interno. Regiões diferentes da padrão devem ser informadas explicitamente.

Cada pedido possui `lot_id`, `resource_id`, `amount` inteiro positivo e `origin` (`CANCEL_BUFFER` ou `CANCEL_INCORPORATED`). O helper ordena os pedidos por ID e coleta até a capacidade física disponível, sem ultrapassar o saldo local solicitado. O recibo informa as quantidades efetivas. Solicitações acima da custódia disponível são recusadas; nenhuma quantidade é estimada ou criada para completar uma carga.

`CancellationRecoveryTransaction.prepare()` é somente leitura. Produz estados destacados da mochila e do ledger, snapshot da custódia e revisões. Confere identidade, geração, índice regional, vínculo de inventário, pesos oficiais, capacidade, histórico de IDs e todas as cargas CANCEL_* do domínio. Lotes e operações preparados não são registrados no estado ativo.

A posição é conferida contra a âncora imutável e a borda da footprint: trabalhador fora do retângulo, alcance e altura válidos, navegação pronta no mesmo World3D, dono de ponto navegável válido e acesso físico desobstruído. A operação não desloca o trabalhador.

### Descarga

A descarga reutiliza o planejador, os checkpoints de pilhas/índices/reservas/mochila, a autorização física de slot e a publicação da `SelectiveCampDeliveryCoordinator`. `DeliverToCampOrder` já existente pode transportar uma seleção explícita até o acampamento; nenhum despacho novo foi implementado.

`CANCEL_TRANSIT`, `CANCEL_BUFFER` e `CANCEL_INCORPORATED` somente são elegíveis quando o registro regional e todos os lotes em trânsito estão conciliados. A descarga genérica continua selecionando apenas `FREE_GATHERED`. Quantidade parcial exige seleção explícita. Lotes livres e de outras obras permanecem na mochila e os claims alheios permanecem intactos.

O snapshot da custódia participa da comparação de preparações antigas, além das revisões existentes. O destino precisa comportar integralmente a seleção projetada; não há depósito econômico separado seguido de crédito tardio da custódia.

## Fronteiras transacionais

1. Preparação destacada e validação de participantes.
2. Aquisição da autoridade regional e das guardas existentes, na ordem da entrega seletiva: sites, inventário, armazenamento, acampamento e mochila.
3. Revalidação sob o escopo verdadeiro e captura de checkpoints.
4. Aplicação silenciosa dos participantes.
5. Conferência da proveniência, dos vínculos físicos e de `Q = L + A + H + E + D + M`.
6. Selo econômico definitivo e recibo regional antes de qualquer callback.
7. Publicação de notificações sob as mesmas guardas; liberação posterior.

Na retirada: `A -= x`, `H += x`, sem modificar E ou as pilhas. Na descarga: a mochila perde y, as pilhas recebem y, `H -= y`, `E += y`. L, D e M permanecem fixos.

Antes do commit, falhas restauram os mapas da custódia, links por unidade, mochila, pesos, ledger, histórico de operações, IDs e demais participantes alterados. Revisões de participantes tocados avançam para invalidar preparações anteriores; não são artificialmente rebobinadas. IDs globais de lotes recuperados são reservados apenas no commit.

Após o selo não existe rollback econômico por observador. Os helpers de aplicação/reversão da descarga exigem um escopo possuído e ainda não selado. Testes tentam reentrância e rollback durante sinais de retirada e descarga. `add_with_provenance()` continua sem permitir criação física irrestrita.

`DEC-T3.6-SIGNALS-01` permanece pendente. Este incremento reutiliza a política aprovada de sinais pós-commit sob guardas, sem antecipar uma solução geral para essa pendência.

Replay de um operation_id comprometido retorna o recibo original sem novo débito, crédito ou sinal. Troca de parâmetros ou mochila é conflito. Um lot_id comprometido não pode ser reutilizado em outra mochila.

## Registro, estados e footprint

A custódia guarda posição global, tamanho, altura do colisor, pesos e identidade regional. As referências ao nó visual, inventário e corpo físico são fracas. A conta regional e sua âncora permanecem disponíveis depois de `queue_free()` do canteiro.

No commit do cancelamento com A>0, cria-se um `StaticBody3D` irmão do nó visual, cobrindo a mesma área. A validação lógica consulta o registro regional, inclusive antes da sincronização física. O corpo carrega a região para o filtro espacial. Não é uma pilha de recursos nem um novo depósito fora do acampamento.

Quando a retirada zera A, o corpo perde a camada de colisão antes de ser liberado e a visualização remanescente é ocultada. A área fica livre mesmo com H>0. O registro regional continua existindo. Ao zerar A e H, o helper passa pelas transições homologadas até SETTLED, após conferir a conservação.

O helper retoma RETURN_BLOCKED por RETURNING quando uma operação válida é executada. Uma preparação recusada não muda o estado econômico nem inventa entregas. O registro de bloqueio utiliza a API de transição já existente; escolha de trabalhadores, marcação automática de bloqueios, retentativas e despacho continuam fora deste incremento. O teste de retomada coloca explicitamente a custódia em RETURN_BLOCKED e usa uma retirada real para voltar a RETURNING.

## RED e correção adversarial regional

Na baseline foram executados dois testes: **0/2 aprovados, 11 asserções, 0 erros de suíte**. As duas falhas esperadas foram: carga SITE_RESERVED da obra alvo ignorada por região incompatível e ausência da operação de recuperação física.

Comando RED: `tools/run_tests.ps1 -Filter test_t3_6_3_b1_3 -TimeoutSeconds 240`, antes de alterar produção, quando a suíte nova continha somente os dois testes iniciais. Trecho da saída capturada:

```text
FAIL test_foreign_region_lot_cannot_be_hidden_from_cancellation (5 assertions, 1 failures)
  -> Target-site cargo in another region must be diagnosed
FAIL test_recovery_requires_a_physical_debit (6 assertions, 1 failures)
  -> B1.3 physical recovery entry is required
Suites: 1 | Tests: 2 | Passed: 0 | Failed: 2 | SuiteErrors: 0 | Assertions: 11
```

O cenário regional retira reserva real, interrompe a ordem, remove o listener/claim e atribui região incompatível ao trabalhador ainda carregado. A correção inspeciona os lotes da obra alvo antes de permitir exclusão pelo filtro regional. O cancelamento é recusado por inconsistência, sem mover recursos entre domínios. Não foi alterada a regra de identidade das unidades.

Iterações de desenvolvimento também identificaram erros de fixture (nome do sinal do inventário e campo `reason_code` do resultado espacial), corrigidos nos testes novos. Um MoveOrder genérico para o slot usado no teste de fault injection terminou em `stuck`; esse fixture passou a iniciar na posição de descarga autorizada, sem usar esse teste como prova de transporte. As provas de transporte são os testes distintos com deslocamento e `DeliverToCampOrder` reais. Nenhum teste anterior foi removido, reduzido ou adaptado para ocultar falhas.

## Cobertura B1.3

| Requisitos do pedido | Evidência executável na suíte nova |
| --- | --- |
| 1–4: buffer, incorporados, capacidade e viagens | `test_local_buffer_incorporated_multitrip_and_settlement`: capacidade de 6 unidades de peso, lotes distintos e múltiplas caminhadas/descargas |
| 5–7: origens CANCEL_* | Testes de viagens para BUFFER/INCORPORATED e teste misto para TRANSIT |
| 8–9: A/B/livre e ausência de crédito antecipado | `test_cancel_transit_mixed_free_and_other_site_remain_untouched` e comparação de E/pilhas antes de cada transporte |
| 10–11: posição, navegação, slot e destino | Testes de domínio/âncora e de recusa de slot/capacidade/destino; snapshots econômicos preservados |
| 12–14: falhas, rollback, revisões, replay e conflito | Quatro pontos de falha na retirada e catorze na descarga; comparação de ledger completo, saldos, reservas, custódia, IDs e eventos |
| 15: reentrância pós-commit | Callbacks tentam nova transferência, mutação legada e rollback após o selo |
| 16: estados | RETURN_BLOCKED→RETURNING e liquidação real em SETTLED |
| 17–19: área e independência visual | Consulta lógica, raycast no corpo independente, remoção visual e liberação com H>0 |
| 20–21: domínio e obrigações alheias | Caso regional RED→GREEN; snapshots de lotes livres, obra B, claims e reservas preservados |
| 22: T2/T3.6.2 | Suítes existentes de coleta/entrega e regressão segmentada completa |

Exemplo econômico observado no fixture a aproximadamente 50% de montagem, por recurso:

| Recurso | Q | L | A inicial | H inicial | E inicial | D | M | A/H finais | E final |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: |
| Madeira | 12 | 0 | 7 (6 buffer + 1 incorporado recuperável) | 0 | 0 | 5 | 0 | 0/0 | 7 |
| Pedra | 6 | 0 | 3 (buffer) | 0 | 0 | 3 | 0 | 0/0 | 3 |

As quantidades acima vêm de execução registrada, não de alteração da fórmula D3. São emitidos snapshots `B13_ACCOUNTING_BEFORE` e `B13_ACCOUNTING_SETTLED`; o teste confere a igualdade por recurso depois de cada commit. Outras execuções podem atingir o limite de progresso em quadro diferente; seus resultados econômicos são validados contra os snapshots reais.

## Validação final

Resultados reais das execuções finais concluídas nesta entrega:

- `tools/run_tests.ps1 -Filter test_t3_6_3 -TimeoutSeconds 240`: **20/20 testes, 3 suítes, 825 asserções**, zero falhas e erros de suíte. Inclui 9 testes B1.3 (370 asserções), 4 B1.2 e 7 B1.1/R1.
- `tools/run_tests.ps1 -Filter test_t3_6_2_c3_4 -TimeoutSeconds 240`: **46/46 testes, 3 suítes, 6.275 asserções**, zero falhas e erros de suíte. Inclui preparação, commit e ordens físicas de entrega seletiva.
- `tools/validate.ps1`: **168 scripts validados, zero erros e zero avisos**, incluindo importação, check-only individual e inicialização headless da MainScene.
- `tools/run_tests.ps1 -Segmented -GroupTimeoutSeconds 240`: **504/504 testes, 71 suítes, 27.118 asserções**, 18 lotes aprovados, zero falhas e erros de suíte. Descobertas=71, executadas únicas=71, duplicatas=0, ausentes=0. Tempo total do executor: 733.332,2 ms; não é benchmark de gameplay.
- `git diff --check` e `git diff --cached --check`: aprovados.

Nas execuções finais dos testes não foram detectados erros Godot, warnings, timeouts ou diagnósticos de vazamento. A verificação de saída do executor usa FailOnWarnings. Isso não constitui prova formal de ausência de vazamentos em todos os fluxos externos.

O Git emitiu um aviso de normalização CRLF→LF ao adicionar o novo helper ao índice, conforme a política do repositório; os checks de whitespace passaram. Esse aviso de versionamento é distinto dos diagnósticos Godot das execuções finais.

Não houve validação manual gráfica nem benchmark nesta etapa. Headless não representa homologação visual do proprietário.

## Limites preservados

- Sem despacho automático, RecoveryOrder, retomada de tarefas ou interface D3.
- Sem proteção geral de teardown B1.4: destruição externa da raiz regional, `free()` arbitrário de trabalhador carregado e encerramento forçado não são cobertos.
- Registro somente em memória; não foi implementada persistência T3.8.
- Sem pilhas livres fora do acampamento, novo cálculo D3, novas regras de coleta ou mudanças de gameplay.
- A reconciliação completa de cargas ocorre nas operações de recuperação/descarga, sem polling de cargas por frame. Não se reivindica benchmark de escala para essa varredura.
- A B1.4 e a interface T3.6.4 permanecem bloqueadas. Sem merge, tag ou homologação automática.

## Publicação

Commit técnico `d40d6c28f5efabc0a6dacc330d5f4848058a18d6`; este relatório integra um commit documental separado, descendente dele. O SHA documental final e sua confirmação remota são apresentados na conversa, evitando uma referência autorrecursiva ao próprio commit.

A revisão final confirmou somente os dez caminhos técnicos enumerados (incluindo UIDs) e este relatório. Os links relativos e os checks de whitespace passaram. A main local permaneceu limpa no SHA de referência; os worktrees existentes foram preservados. O projeto original `C:\Projetos\Dawn of Kin`, inclusive suas alterações preexistentes, não foi utilizado para implementação. A publicação é exclusiva da candidata, sem merge e sem tags.
