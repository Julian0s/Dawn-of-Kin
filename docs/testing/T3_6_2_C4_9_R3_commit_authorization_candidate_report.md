# Dawn of Kin — Candidata T3.6.2-C4.9-R3

## Base e escopo

Branch `feat/t3-6-2-provenance-transactions`, baseline `3c20251dffa4cfbed31a75f1d2d80ef0cf77baca` verificada localmente e no GitHub. Worktree `C:/Projetos/Dawn_of_Kin_wt_t3_4_5`, limpo no início. Main de referência `25e0a20f1d6a2f10a9e059afe69759fbe263db4a`. Execução headless em Godot `4.7.2.stable.official.ed1daf0bf`.

A correção segue [AGENTS](../../AGENTS.md), [GDD v1.2](../Dawn_of_Kin_GDD.md), [proposta T3.6-R2 §4](https://github.com/Julian0s/Dawn-of-Kin/blob/69c13275a34a30564ac839ec920f83ef36590812/docs/architecture/T3_6_cancellation_architecture_R2_PROPOSAL.md), [C4.9-R1](T3_6_2_C4_9_R1_internal_helper_boundary_candidate_report.md) e [C4.9-R2](T3_6_2_C4_9_R2_scope_finalization_candidate_report.md).

## RED

A primeira execução reutilizou o fixture e os quatro testes R2 numa suíte temporária, acrescentando seis casos adversariais antes de tocar em `src/`. O comando `run_tests.ps1 -Filter test_t3_6_2_c4_9_r3` saiu com código 1: 4/10 passaram, os seis novos falharam nas asserções de proteção, com 201 asserções e zero erros de suíte. Os quatro controles R2 cobrem a chamada direta à publicação, checkpoint divergente e repetição de finalização.

| Caso em cada backend | Resultado na R2 |
|---|---|
| `site_creator_override` autoriza, publica e retorna `null` | Commit aceito, quatro sinais econômicos prematuros, 4 madeiras reservadas para uma obra que falhou |
| `child_entered_tree` autoriza, publica e força sobreposição | Mesmo resultado, com o nó presente na árvore e ausente do registro naquele instante |
| `site_creator_override` apenas autoriza e retorna `null` | Nenhum sinal econômico, mas a mesma reserva órfã e revisões de armazenamento não restauradas |

Nos seis casos o estoque físico ficou em 8, a reserva total subiu de 4 para 8 e o saldo livre caiu de 4 para 0. A causa era a autorização aceitar um escopo genuíno ainda que o canteiro não estivesse registrado. A transição já apagava o checkpoint e impedia autorizar o rollback. No fluxo interno, o gerenciador ignorava o retorno do autorizador.

## Correção

- O [coordenador](../../src/economy/reserved_withdrawal_coordinator.gd) exige escopo ativo, reserva aplicada, checkpoint presente e uma transição ainda aberta. Verifica o mesmo canteiro em `_sites`, raiz e mundo esperados, validade, ausência de exclusão pendente, estado ativo, IDs, região, inventário, definição e igualdade entre custo, quantidades exigidas e reserva aplicada. A recusa não modifica flags nem checkpoint. A autorização conserva o checkpoint até que a publicação o consuma.
- O [gerenciador](../../src/buildings/construction_manager.gd) congela os dados da tentativa antes dos callbacks e registra o nó provisoriamente após a checagem de sobreposição. Se o autorizador recusar, retira esse registro, reverte a reserva pelo caminho existente, restaura a sequência, remove o nó e libera as guardas. A conexão de `state_changed` e o incremento de revisão do commit só são feitos após autorização. O caminho legítimo preserva a ordem de publicação e `site_created`.

## GREEN e regressão

Os novos cenários agora integram a [suíte de finalização C4.9](../../tests/integration/test_t3_6_2_c4_9_r2_scope_finalization.gd), com nomes `test_r3_*`, para reutilizar os fixtures sem duplicar a execução dos controles R2. Os seis casos verificam recusa, retenção do checkpoint até rollback, zero reservas órfãs ou sinais econômicos, 4 madeiras livres, revisões restauradas, canteiro existente preservado e guardas liberadas.

O caso adicional agenda a exclusão do nó em `child_entered_tree` mantendo o canteiro válido e sem sobreposição. Nos dois backends a tentativa alcança a recusa interna `site_commit_not_authorized`. O teste confirma remoção de `_sites` antes da saída do nó, ausência da conexão do gerenciador, reserva revertida e revisões restauradas. Em seguida confirma que uma criação legítima reutiliza o mesmo ID, publica a reserva correta e registra o canteiro.

| Comando | Resultado |
|---|---|
| `run_tests.ps1 -Filter test_r3_` | Exit 0. 7/7 testes, 182 asserções, zero erros de suíte. |
| `run_tests.ps1 -Filter test_t3_6_2 -TimeoutSeconds 240` | Exit 0. 23 suítes, 177/177 testes, 11.146 asserções, zero erros de suíte. |
| `run_tests.ps1 -Segmented -GroupTimeoutSeconds 240` | Exit 0. 16/16 lotes, 66 suítes únicas, 474/474 testes, 25.923 asserções, zero falhas, erros de suíte, suítes omitidas ou duplicadas. |
| `validate.ps1` | Exit 0. 160 scripts validados, importação e inicialização headless aprovadas, zero erros e avisos. |
| `git diff --check` | Exit 0. |

O commit de produção é `ceed3bebd72ccdb5a4b599fd9736c063c3f7c8d2`. O commit de testes é `45a4278c7f942625828cb1be36df317c9ef067d5`.

As contagens dos filtros fazem parte da cobertura segmentada. Asserções executadas em laços por quadro podem variar entre rodadas.

## Limites

A garantia cobre os pontos de entrada e callbacks cooperativos do jogo. Código GDScript com acesso direto às estruturas internas continua sujeito à disciplina arquitetural. As regras de economia, a política de sinais pós-commit e as pendências de P6 permanecem fora desta correção.

**Parecer.** A candidata C4.9-R3 está pronta para auditoria independente.
