# R-03A D3.2 — Integração das ordens de corte, derrubada e recolhimento

**Implementado e validado tecnicamente.** Base autorizada e homologada para D3.1-R1 `a88d98d4ea41755de0cb4cecaf58700ecc8e272c`. O SHA publicado e as referências Git estão em `git_depois.txt` no arquivo de evidências. Esta candidata fica para auditoria independente e decisão do proprietário.

## Ciclo e propriedade da autorização

A seleção contextual da MainScene mantém o fluxo pelo Board, dispatcher e `CommandController`. As ordens RTS usam o mesmo ciclo físico, com identidade própria. `GatherSlotPlanner` e `DeliverToCampOrder` continuam responsáveis por aproximação e descarga, respectivamente.

- **Aproximação e preparação.** A ordem reserva vaga, calcula posição navegável e prepara dentro do alcance. Registra um cortador com unidade, ordem, revisão e token a partir do primeiro tick após a preparação. Afastamento ou espera de navegação retiram a participação.
- **Corte e queda.** A fonte mede um relógio de 2,5 s com um cortador e aplica fator 1,5× com dois. A queda provisória de 0,50 s torna-se irreversível ao entrar em `FELLING`. A ordem espera em pose neutra e a fonte conclui a queda com ou sem trabalhador e `Tween`.
- **Recolhimento e entrega.** O intervalo de recolhimento inicia em `FALLEN`, com pose de trabalho em nível baixo. A sessão bloqueia a criação de intenção e a alocação de IDs pré-queda. Recibo compatível anterior continua disponível para replay. Lotes `FREE_GATHERED`, peso, capacidade e descarga física e seletiva seguem pelos caminhos existentes.

O `WorkTask` detém o token da fonte em `PENDING_WORKERS` e `IN_PROGRESS`. Uma troca de trabalhador retira a participação da ordem anterior e conserva o token enquanto a autorização comunitária continua válida. O Board revoga a autorização ao encerrar a tarefa, exigir reautorização em `BLOCKED_REAUTHORIZATION` ou desmontar. A reautorização explícita preserva a tarefa e o grupo e emite outro token. Uma ordem pessoal possui seu próprio token e o revoga no encerramento definitivo. Uma tarefa comunitária continua com uma atribuição.

O Board registra o encerramento antes de reconciliar a ordem vinculada. O dispatcher confere a identidade após notificar observadores. A ordem usa revisão e identidade ao retirar participação e revalida a propriedade depois dos sinais de estágio, vaga, estado e entrega que podem instalar uma sucessora. Operação transacional ativa segue o cancelamento cooperativo da D2. A carga anterior elegível pode seguir diretamente para o acampamento durante a queda. Uma autorização encerrada permite a entrega final legítima sem novo retorno à fonte.

## Matriz de provas

| Requisito | Evidência automatizada |
| --- | --- |
| I01 — Ciclo comunitário | `test_i01_main_contextual_order_cuts_then_delivers` observa aproximação, preparação, corte, queda, recolhimento, transporte e entrega pela MainScene. A suíte MainScene exercita também cliques e o botão contextual. |
| I02 — RTS | Uma e duas unidades executam ordens reais com vagas e alcance. O dispatcher conserva uma atribuição por tarefa. |
| I03 — Relógio | `test_i02_i03_two_rts_workers_share_the_source_clock` mede seis ticks a 1,5× e seis a 1× após cancelar um dos cortadores. |
| I04 — Barreira | I01 verifica carga, recibo, sessão e seriais local e regional até a primeira extração. I04 confirma que a sessão de árvore em pé rejeita a intenção antes de alocar IDs de operação e lote. |
| I05 — Interrupção | Perda de alcance e `MoveOrder` pessoal congelam o corte. Reaproximação e troca de trabalhador da tarefa retomam com autorização legítima. |
| I06 — Cancelamento | Casos antes da queda, no callback do início, durante a queda e após `FALLEN`. Um cortador RTS independente preserva o trabalho ao cancelar a tarefa comunitária. |
| I07 — Autorização | A troca de trabalhador conserva o token. Bloqueio e reautorização trocam a identidade. Admissão tardia de token revogado é recusada. D3.1-R1 cobre referências extintas e herança indevida. |
| I08 — Reentrância | Sucessor pessoal inicia na mesma árvore durante `worker_slot_released` e conserva a vaga. D2 e D2 R1 cobrem `state_changed`, `order_finished`, notificações do Board, `amount_changed` e `depleted`. |
| I09 — Entrega residual | A carga livre anterior parte durante a queda, chega ao estoque por uma entrega e o trabalhador fica sem retorno à fonte cancelada. D2 e D2 R1 cobrem carga reservada ou de recuperação. |
| I10 — Recursos mistos | Madeira, pedra e alimentos passam pelo ciclo físico nos testes legados e na suíte transacional C3.5. |
| I11 — Simulação | Pausa, retomada, `Tween` interrompido, queda sem trabalhadores e remoção de árvore durante corte. D3.1-R1 também cobre pausa do corte. |
| I12 — Compatibilidade | Caminhos legado e transacional, MainScene, UX-1, RUX-1, RUX-2A e RUX-2B executados. Capturas nativas complementam as provas automatizadas. |

## Arquivos e adaptação de históricos

| Classe | Arquivos e escopo |
| --- | --- |
| Produção | `gather_resource_order.gd` e `gather_transfer_session.gd` integram o ciclo e a barreira antes dos IDs. `resource_source.gd` reutiliza a identidade de retirada para consultar participação. `work_task.gd`, `community_work_board.gd`, `community_task_dispatcher.gd` e `command_controller.gd` integram o token. `unit_order.gd` e `unit.gd` reutilizam as posturas de espera e recolhimento. |
| Preservação integral | Suítes D3.1-R1, D1, D2, UX-1 e RUX-2A preservadas. O arquivo D3.1-R1 mantém 17 testes e 300 asserções. |
| Adaptação de fixture | MainScene A15/F02, D2 R1 S12, RUX-1 R6 e RUX-2B B9 partem de fonte caída para construir fonte esgotada. F02 e S12 têm loops limitados. C3.4.1/C3.4.2 preparam lotes por extração em fonte caída. C3.5 usa a mesma pré-condição nos casos de alcance remoto e retentativa ocupada. |
| Contrato substituído | C3.5 B/E verifica saldo integral enquanto a árvore cai. A carga usada para testar cancelamento do transporte e da entrega é recolhida depois da queda. Permanecem as provas de conservação local, peso, custódia, capacidade, recibos, replay e rollback. |
| Nova cobertura | `test_r_03a_d3_2_tree_gather_orders.gd` e `.uid`. Os casos centrais usam callbacks normais de simulação da ordem e da fonte. |

## Validação e evidências

| Execução | Resultado | Saída direta |
| --- | --- | --- |
| RED inicial | A fixture chamava uma asserção inexistente. O teste passou a usar `assert_near`. | `1` do executor |
| RED comportamental com produção intacta | 4 falhas em 4 testes e 28 asserções. A ordem não iniciava corte. A sessão alocava IDs para árvore em pé, embora a fonte recusasse a extração. | `1` do executor |
| GREEN D3.2 | 12/12 testes e 179 asserções. | `0` da Godot e do executor |
| Focais consolidados | 174/174 testes em 13 suítes e 9.263 asserções. Incluem D3.2, D3.1-R1, D1, D2, D2 R1, MainScene, C3.5, C3.4.1/C3.4.2 e UX/RUX. | `0` da Godot e dos executores |
| `validate.ps1` | Importação headless, 217 scripts verificados e inicialização da MainScene na Godot 4.7.2. Zero erros e avisos. | `0` do executor |
| Smoke headless de inicialização | MainScene inicializada com Godot 4.7.2. | `0` da Godot e do executor |
| Capturas nativas | Corte, queda e recolhimento na MainScene em `1280×720` e `1920×1080`. Cada execução entregou três madeiras ao acampamento. | `0` da Godot e dos executores |

Os logs iniciais de D2 e MainScene preservam timeouts associados às fixtures de esgotamento pré-queda. O primeiro reteste conjunto de D2 e o RUX-2B inicial ainda encontraram um erro ao passar referência já liberada à verificação de token. A ordem passou a consultar a revogação diretamente e a tratar a fonte removida pelas verificações de existência. O GREEN cobre esse cenário, e os focais D2, D2 R1 e RUX passaram nos retestes. Nos timeouts, `124` é o código do helper. A saída original da Godot nesses processos encerrados por tempo é indisponível. A execução estática anterior à retomada tem apenas log parcial e código indisponível. Nenhuma dessas execuções sustenta aprovação.

As capturas renderizadas observam a tarefa contextual real. O roteiro registra saldo 3 e carga 0 no corte e na queda, saldo 2 e carga 1 após o primeiro recolhimento, e termina com três madeiras entregues fisicamente. Trata-se de evidência visual automatizada. O aceite humano e a medição formal de desempenho desta candidata não foram realizados.

A reconciliação abrangente dos testes históricos de fontes naturais, extração direta, picking, velocidade e isolamento regional C4.6 e a prova regional completa D0-A04 seguem reservadas à D3.3. A campanha consolidada da D3 e a decisão de homologação pertencem às etapas autorizadas posteriores.

O worktree `C:\Projetos\Dawn_of_Kin_wt_r_03a` acompanha `feat/r-03a-community-work-main-scene` na base homologada acima. Foi usado pelo Codex para integrar e validar D3.2. Permanece ativo para auditoria da candidata e decisão do proprietário. Evidências e manifesto SHA-256 em `C:\Projetos\Backups\Dawn_of_Kin_Archive_Local\evidencias\R-03A\D3\D3.2`.
