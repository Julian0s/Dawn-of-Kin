# T3.6.3-B1.4 — Despacho de recuperação e ciclo de vida

Status: implementada e testada automaticamente como candidata; aguardando auditoria independente. Não homologada. Escopo exclusivo B1.4.

## Base e fontes

- Base local/remota conferida: `3f9a4393b93777374a45846cb17091648c82343b`.
- Branch: `feat/t3-6-3-cancellation-custody`.
- Worktree reutilizado: `C:\Projetos\Dawn_of_Kin_wt_t3_4_5`; nenhum worktree ou branch foi criado.
- Godot: `4.7.2.stable.official.ed1daf0bf`.
- Main preservada: `25e0a20f1d6a2f10a9e059afe69759fbe263db4a`.
- Commit técnico: `ea2532bb796a433c5e4b72d9e2b09ed87d945798`.

Consultados AGENTS.md, [GDD v1.2](../Dawn_of_Kin_GDD.md), [arquitetura T3 §3/§6](../architecture/T3_architecture_PROPOSAL.md), proposta histórica T3.6-R2 no commit `69c13275a34a30564ac839ec920f83ef36590812` e relatórios [B1.1-R1](T3_6_3_B1_1_R1_safety_review_candidate_report.md), [B1.2](T3_6_3_B1_2_cancellation_commit_transaction_candidate_report.md) e [B1.3](T3_6_3_B1_3_physical_recovery_and_delivery_candidate_report.md). A proposta histórica não foi presumida integralmente vigente. A autorização específica B1.4 fixa D-CANC-01/A, 02/A e 03/A.

Preservados D2, D3, DEC-11B, D-INT-01/B, D-INT-02/A e D-INT-03/A. A fórmula e as mutações econômicas permanecem nos coordenadores existentes. `DEC-T3.6-SIGNALS-01` continua pendente. Não há mudança de GDD, custos, profissões, UI ou regras de coleta.

## Arquivos

| Arquivo | Responsabilidade da mudança |
| --- | --- |
| [recovery_order.gd](../../src/units/orders/recovery_order.gd) | Nova ordem composta: aproximação, retirada B1.3, entrega seletiva, viagens, espera e falha limitada |
| [cancellation_recovery_dispatcher.gd](../../src/units/cancellation_recovery_dispatcher.gd) | Novo despachante regional dirigido por eventos e tokens de ordem |
| [cancellation_lifecycle_guard.gd](../../src/economy/cancellation_lifecycle_guard.gd) | Novo preflight somente leitura de custódias/obrigações e remoção cooperativa |
| [construction_manager.gd](../../src/buildings/construction_manager.gd) | Composição do despachante e API interna de designação |
| [site_cancellation_transaction.gd](../../src/economy/site_cancellation_transaction.gd) | Captura da revisão de ordens e agendamento após selo e liberação das guardas |
| [reserved_withdrawal_coordinator.gd](../../src/economy/reserved_withdrawal_coordinator.gd) | IDs de participantes da recuperação no registro regional |
| [cancellation_recovery_transaction.gd](../../src/economy/cancellation_recovery_transaction.gd) | Invalidação geométrica somente quando a footprint muda |
| [unit.gd](../../src/units/unit.gd) | Revisão monotônica de ordens e preservação do comando mais recente em callbacks |
| [temporary_test_workers_controller.gd](../../src/units/temporary_test_workers_controller.gd) | Recusa de remoção com recuperação/custódia pendente e revalidação por trabalhador |
| [ground_pile_manager.gd](../../src/economy/ground_pile_manager.gd) | `cleanup()` consulta o preflight antes de apagar pilhas |
| [main.gd](../../src/main/main.gd) | Ativação na cena com proveniência e entrada interna de teardown controlado |
| [fixture B1.2](../../tests/integration/test_t3_6_3_b1_2_cancellation_commit_transaction.gd) | Isolamento explícito dos testes das primitivas, sem reduzir asserções |
| [suíte B1.4](../../tests/integration/test_t3_6_3_b1_4_recovery_dispatch.gd) | Dezesseis testes físicos e adversariais com MainScene real |

Incluídos os quatro `.gd.uid` dos novos scripts. Este relatório é o único documento novo da etapa.

## Ordem e despacho

`MainScene.automatic_cancellation_recovery` é habilitado por padrão. O despachante só é composto quando `use_provenance_economy` também está ativo. O cancelamento continua sem comando RTS, botão ou HUD; somente a chamada interna já existente pode gerar o commit D3.

Após o commit definitivo de `SiteCancellationTransaction`, e depois de soltar as guardas, o gerenciador agenda os IDs originalmente atribuídos e aqueles com lotes em trânsito. A preparação captura `Unit.get_order_revision()`. O agendamento não emite ordens durante a transação econômica.

Na execução adiada, o despachante resolve a unidade no World3D correto, valida sua identidade e a revisão esperada, e admite somente unidade disponível ou a ordem da própria obra recém-cancelada. Uma ordem manual já ativa não é substituída. Não se cria trabalhador quando a resolução falha ou não há candidatos.

`ConstructionManager.assign_cancellation_recovery(cancel_id, units)` permite designação interna posterior. Lista vazia, unidade inválida, domínio incorreto ou trabalhador ocupado são recusados. Identidades repetidas na lista são deduplicadas. Uma ordem existente da mesma recuperação não é duplicada. `recovery_unit_ids` registra a participação posterior sem apagar os IDs originais, e a revisão da custódia avança.

`RecoveryOrder` compõe `MoveOrder` e `DeliverToCampOrder`; não soma ou subtrai quantidades. Sua sequência é:

1. Conferir custódia, identidade e proveniência.
2. Devolver primeiro os próprios lotes CANCEL_* já na mochila, quando existirem.
3. Resolver um ponto navegável de perímetro, separado dos alvos reservados por outros trabalhadores.
4. Caminhar, reconsultar saldos atuais e retirar por `recover_cancellation_materials()`.
5. Transportar e descarregar uma seleção explícita através da entrega seletiva existente.
6. Repetir até não haver saldo local; aguardar evento de progresso se outro trabalhador ainda transporta carga.
7. Encerrar em SETTLED após a liquidação real.

Os dois trabalhadores não compartilham uma retirada preparada. Os pedidos são calculados na chegada, com IDs que incluem cancelamento, unidade, instância da ordem e ciclo. A autoridade B1.3 serializa e debita apenas os saldos reais ainda disponíveis. Os alvos de aproximação são expostos por `get_reserved_target()`.

## Prioridade manual e callbacks

Cada comando aceito incrementa a revisão da unidade. Um comando manual posterior ao cancelamento invalida o despacho adiado, inclusive quando o comando já terminou antes do callback antigo. Interromper uma RecoveryOrder preserva os lotes, registra `manual_override` e suprime a retomada automática desse trabalhador.

Eventos de estoque ou navegação não removem essa supressão. Após o comando manual terminar, a retomada exige uma designação interna explícita. Enquanto a ordem manual está ativa, essa designação também é recusada.

O RED identificou duas sequências reentrantes em Unit: emissão de um comando novo em `order_finished` durante substituição e emissão durante `start()` por `state_changed`. A chamada externa continuava e sobrescrevia ou apagava o comando mais recente. A revisão agora é conferida após cancelamento/callback e após `start()`. A atribuição obsoleta retorna sem parar o movimento novo. Callbacks antigos de conclusão também são confrontados com a instância de ordem atual do despachante.

As guardas econômicas existentes continuam impedindo comandos e remoção durante sinais pós-commit. A própria atualização da RecoveryOrder recusa reentrada ou execução durante uma trava da unidade.

## Bloqueios e conservação

Cada ordem limita falhas consecutivas a `MAX_RETRIES = 3`, com `RETRY_COOLDOWN_SEC = 1.0`. Antes da nova tentativa, os materiais permanecem onde estavam. O teste de região de navegação desabilitada verifica explicitamente as três tentativas.

Depois do limite, a ordem termina com diagnóstico, a custódia fica RETURN_BLOCKED e não há loop por quadro de reatribuição. Um evento real de `navigation_ready` ou `inventory_changed` pode reativar somente uma tarefa técnica já atribuída, com o token ainda válido. A API explícita é a alternativa quando a condição foi corrigida sem um desses eventos.

Mochila cheia com materiais de outra obra e coleta livre é recusada sem consumir ou descarregar essas obrigações. Ao restaurar capacidade e designar novamente, somente os lotes do cancelamento são recolhidos/devolvidos. Falha de slot/capacidade do acampamento conserva a carga CANCEL_* e não credita E. Navegação desabilitada é exercitada com a NavigationRegion3D real, seguida de habilitação e rebake real; não se atribui um status de sucesso à ordem no teste.

As equações continuam `A -= x; H += x` na retirada e `H -= y; E += y` na descarga. L, D e M não são modificados. A suíte confere `Q = L + A + H + E + D + M` e consistência em sinais de entrega. A liberação da footprint continua ocorrendo com A=0, mesmo com H>0. A invalidação do cache de geometria ocorre somente ao criar/liberar a ocupação, sem rebake por atualização econômica.

## Remoção e encerramento: garantia e limites

- `TemporaryTestWorkersController` recusa RecoveryOrder ativa, lotes físicos, transações e identidade original ou posterior associada a custódia pendente. Revalida imediatamente antes da remoção de cada unidade. Trabalhadores vazios e sem obrigações continuam removíveis.
- `GroundPileManager.cleanup()` preserva as pilhas quando o preflight detecta custódia pendente ou transação. Sua assinatura pública continua `void`; o motivo está disponível em `CancellationLifecycleGuard.inspect_storage()`.
- `MainScene.preflight_economic_teardown()` verifica transações, custódias e mochilas com obrigações físicas. Uma custódia A liquidada não permite descartar a carga de B.
- `MainScene.request_controlled_teardown()` é uma nova entrada **interna**: consulta o preflight e mantém as guardas regional, inventário, armazenamento, acampamento e cargas durante a saída da árvore. Referências locais mantêm a composição disponível após `_exit_tree()`. Depois da remoção, as guardas são liberadas, delegates que adiaram cancelamento são desvinculados e o armazenamento/domínio são finalizados. Os testes verificam recusa com pendência, bloqueio de novo commit por callback de saída e liberação efetiva da autoridade depois da liquidação.
- `_exit_tree()` permanece limpeza posterior ao início da saída, sem alegação de veto. `release_regional_domain()` preserva sua recusa anterior a custódias não liquidadas.

O projeto não possui um fluxo próprio de menu/reload/quit ligado a esse novo preflight. Não foi introduzida uma interceptação de fechamento da janela, SceneTree.quit, mudança de cena externa ou editor stop. **Essas entradas não estão protegidas por esta API interna.** Um teste chama `remove_child()` externamente apesar da recusa do preflight e demonstra que a cena sai com a obrigação ainda pendente, sem transformá-la em SETTLED. `free()` arbitrário, remoção externa da raiz/unidade, crash e encerramento forçado continuam fora da garantia. Não há save/load ou recipiente fora do acampamento.

A aquisição do encerramento utiliza a região realmente vinculada ao armazenamento e verifica posse e inatividade da autoridade antes de tocar suas guardas. Um probe adicional com duas MainScenes no mesmo World3D, uma delas legada sem domínio próprio, chamou o teardown legado durante sinais de cancelamento da cena com proveniência: **5 asserções aprovadas**, observando `[guarda ativa = true, teardown alheio aceito = false, guarda ainda ativa = true]`. O cancelamento legítimo concluiu normalmente. Esse reforço também recebeu check-only específico de MainScene e nova execução focada dos dezesseis cenários.

## RED → GREEN e ajustes de fixture

RED na base `3f9a439…`, antes de alterar produção: **0/2 testes, 3 asserções, zero erros de suíte**. Faltava a API interna e a limpeza controlada apagou duas madeiras de uma pilha diante de custódia pendente. O teste observou o saldo mudar de `{wood: 2}` para `{}`.

RED adicional de prioridade em callback de substituição: **4/5 testes, 48 asserções**, com duas asserções falhando no cenário reentrante. Um probe temporário fora do repositório executou o teste de callback durante `start()`: **7 asserções, uma falha**, com a ordem manual apagada. Ambos os casos estão na suíte permanente e passam no GREEN.

Durante a revisão da nova entrada de teardown, um teste adicional reproduziu uma janela entre preflight e saída: um filho adicionado ao final da cena executou cancelamento real em `tree_exiting`, criando custódia depois da aprovação inicial. O probe RED teve **7 asserções, uma falha** (`[true]` em vez de `[false]` para o novo commit). A correção mantém as guardas existentes durante a remoção, sem inventar rollback depois que a saída começou. O mesmo probe ficou GREEN. A primeira segmentada já em curso acusou esse caso com o código anterior carregado: **519/520 testes**, 72 suítes, 27.294 asserções, uma falha e zero erros de suíte. A execução completa foi reiniciada sobre a correção final, sem retirar o teste.

As primeiras execuções também detectaram: filtro tridimensional de ponto de NavMesh que recusava a diferença vertical válida do fixture; captura do snapshot antes da sincronização de desativação da região; e avaliação da retomada antes de a fila adiada processar o evento. O código usa tolerâncias XZ/Y separadas; os testes sincronizam as condições reais e exigem a nova ordem antes de continuar. Não se simulou transporte por alteração de contadores.

O fixture B1.2/B1.3 define `automatic_cancellation_recovery = false` por padrão para continuar testando diretamente as primitivas com transporte explícito. A suíte B1.4 usa `_fixture(true)` para o fluxo integrado. Nenhuma asserção anterior foi removida ou reduzida; a cena jogável mantém a automação habilitada.

## Cobertura e resultados

| Itens obrigatórios | Evidência |
| --- | --- |
| 1–3: um/dois trabalhadores e viagens | Testes automático solo/múltiplo com capacidade 6, contagem de viagens e saldo final |
| 4: carga existente | CANCEL_TRANSIT volta por DeliverToCampOrder antes de qualquer retirada local |
| 5–7: comando manual e retomada | Interrupção carregada, eventos sem sequestro, retomada explícita e dois callbacks reentrantes |
| 8: ninguém disponível | Custódia permanece idêntica sem candidatos; designação posterior real, lista vazia/nula e ID repetido |
| 9–12: bloqueios e correção | Região de navegação desabilitada/restaurada e acampamento sem capacidade/restaurado, com eventos reais |
| 13–14: carga mista e dupla retirada | Mochila cheia de B/livre, preservação dos lotes/claim/reserva e dois trabalhadores sem saldo duplicado |
| 15–18: remoção e teardown | Temporário vazio mas vinculado é protegido; remoção após liquidação; preflight e teardown interno efetivo |
| 19–20: conservação e callbacks | Contabilidade por recurso, sinais sob guardas, IDs repetidos e callbacks obsoletos |
| 21–22: regressão e UI | Suíte completa T1–T3.6.3 e ausência de comando/interface D3 no novo fluxo |

| Execução final | Resultado |
| --- | --- |
| `run_tests.ps1 -Filter test_t3_6_3_b1_4 -TimeoutSeconds 240` | 16/16 testes, 1 suíte, 178 asserções; zero falhas/erros de suíte |
| `run_tests.ps1 -Filter test_t3_6_2_c4_2 -TimeoutSeconds 240` | 8/8 testes, 1 suíte, 226 asserções; zero falhas/erros de suíte |
| `validate.ps1` | 172 scripts; importação, check-only e inicialização headless aprovados; zero erros/avisos |
| `run_tests.ps1 -Segmented -GroupTimeoutSeconds 240` | 520/520 testes, 72 suítes, 27.297 asserções; zero falhas/erros de suíte |
| `git diff --check` e `git diff --cached --check` | Aprovados |

Na segmentada final: **18 lotes aprovados; descobertas=72, executadas únicas=72, duplicadas=0 e ausentes=0**. Zero timeouts e zero diagnósticos de erro, warning ou vazamento nos logs finais Godot. Isso não constitui prova formal sobre destruição arbitrária ou todos os fluxos externos. A rodada focada final inclui a proteção do teardown e a liberação da autoridade, além dos quinze cenários anteriores. O último reforço de posse/região da autoridade também recebeu check-only de MainScene (`Success=True, Exit=0, Errors=False, Warnings=False`), probe entre domínios e nova execução focada 16/16. Os 504/71/27.118 da B1.3 são históricos, não foram usados como resultado B1.4.

O Git avisou sobre normalização CRLF→LF no helper de recuperação herdado; não houve falha de whitespace. Esse aviso de versionamento é separado dos diagnósticos Godot.

## Publicação e pendências

Commit técnico `ea2532bb796a433c5e4b72d9e2b09ed87d945798`; este relatório integra um commit documental separado e descendente. O SHA documental e sua confirmação remota são informados na conversa, evitando referência autorrecursiva. Publicação exclusiva na branch candidata. Sem merge ou tag.

A revisão conferiu os dezessete caminhos técnicos (incluindo UIDs) e este relatório, os links relativos e os checks de whitespace. Main local limpa e worktrees existentes preservados. O projeto original `C:\Projetos\Dawn of Kin` e suas alterações preexistentes não foram usados para implementação.

Não houve teste manual gráfico nem benchmark de escala. As provas físicas descritas são headless, com MainScene, navegação, mochilas e pilhas reais. Não se reivindica homologação visual. D3 continua inacessível ao jogador; T3.6.4, HUD, confirmação, depósitos protegidos, persistência e etapas posteriores não foram iniciados.
