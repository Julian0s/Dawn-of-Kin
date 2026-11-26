# Dawn of Kin — R-03A D3.1-R1 — Ciclo de vida das autorizações de corte

**D3.1-A01 confirmado e corrigido.** A homologação depende de auditoria independente e de decisão do proprietário.

## Reprodução e correção

Na produção intacta de **6aa4c6955fbedf2dae8df939e6005b9bbe8dc947**, A cortou por 1,0 s e se retirou. O tempo ficou congelado. A referência fraca deixou de resolver após a liberação de A. Mesmo assim, B entrou com os 1,0 s acumulados e iniciou a queda após apenas 1,5 s de trabalho próprio. A remoção do registro vencido deixava o relógio compartilhado intacto.

A fonte registra quais autorizações efetivamente avançaram o corte atual. Antes de admitir um novo cortador, descarta referências extintas e reinicia o corte abandonado se não houver trabalhador independente válido nem contribuição vigente para esse corte. Se o retorno a `STANDING` acionar observadores, a fonte revalida a admissão depois das notificações e bloqueia avanço reentrante do relógio durante a publicação. O reset limpa a contribuição anterior e conserva a identidade e o registro de revogação dos tokens vivos.

Uma autorização vigente que contribuiu pode sustentar o congelamento. Um cortador independente que continua trabalhando preserva o avanço. Autorizações revogadas, históricas ou que ainda não contribuíram são insuficientes para sustentar o tempo congelado. O proprietário continua responsável por revogar explicitamente um token que ainda retém. A fonte faz a reconciliação na admissão, sem monitoramento contínuo de árvores congeladas. O corte continua provisoriamente em 2,5 s com um cortador e fator 1,5× com dois, com queda irreversível de 0,50 s a partir de `FELLING`.

## Evidências

| Execução | Resultado | Saída | Duração |
| --- | --- | ---: | ---: |
| `01_red` | Falha de compilação na fixture nova por inferência de `Variant`, corrigida com tipagem `WeakRef` antes da reprodução válida. | 1 | 26,65 s |
| `02_red_comportamental` | 14/17 testes aprovados. Falharam herança de progresso, registros que não sustentavam o corte e reconciliação reentrante. | 1 | 25,21 s |
| `03_green` | 17/17 testes, 300 asserções, 0 falhas. | 0 | 26,11 s |
| `04_estatica_resource_source` | Godot `--check-only` com `-FailOnWarnings`, sem erros nem avisos. | 0 | 2,66 s |
| `05_estatica_suite` | Godot `--check-only` com `-FailOnWarnings`, sem erros nem avisos. | 0 | 5,27 s |

Foram preservados os 12 testes e as 227 asserções anteriores. Eles cobrem revogação explícita, cancelamento desconhecido e seletivo, continuidade e rejeição de callbacks tardios, barreira pré-queda, pedra, alimentos, replay, rollback e conservação local. Os cinco cenários novos acrescentam 73 asserções e cobrem contribuição independente após congelamento, expiração antes, durante e depois da queda, tokens revogados ou históricos e reentrada em observadores. A reconciliação mantém saldo e revisão econômica. O teste reentrante executa duas asserções extras quando a notificação ocorre, o que explica 298 asserções no RED válido e 300 no GREEN.

Os registros incluem comandos, horários, stdout/stderr e códigos de saída obtidos dos processos. A validação estática executou a checagem dos dois scripts alterados com a Godot 4.7.2. A validação de 216 scripts consta no relatório da candidata D3.1. A regressão integral e a validação manual da D3 ficam para a integração autorizada. A prova regional completa de D0-A04 continua pendente. A futura integração deve revogar explicitamente autorizações ainda referenciadas quando seu vínculo com o trabalho terminar.

Evidências arquivadas em `C:\Projetos\Backups\Dawn_of_Kin_Archive_Local\evidencias\R-03A\D3\D3.1-R1`.
