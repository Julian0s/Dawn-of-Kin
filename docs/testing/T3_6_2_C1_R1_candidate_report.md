# T3.6.2-C1-R1 — Revisão da preparação de saque reservado

Base `8f13827e6360e025395ed776dcc7032f5145f961` na branch `feat/t3-6-2-provenance-transactions`. Main de referência `25e0a20f1d6a2f10a9e059afe69759fbe263db4a`. Candidata para auditoria independente.

## R1-A — Proveniência de obras

Defeito reproduzido na base. Um lote reservado com obra inexistente e quantidade física reconciliada foi aceito sem claim. A preparação agora recusa a origem desconhecida com `unknown_reserved_site`. Para obras reconhecidas, exige correspondência entre identidade, geração, trabalhador, mochila e quantidades do claim. A descoberta consulta canteiros presentes no grupo da cena, no mesmo `World3D` e `region_id`. IDs duplicados nessa consulta geram `conflicting_site_claims`, e `options.other_sites` não amplia a autoridade da descoberta. Uma unidade de outro mundo também é recusada.

A proveniência livre continua incluída na validação da mochila. Claims de obras vizinhas reconciliados continuam válidos, e suas gerações, instâncias e revisões passam a constar no plano revalidado. O teste com dois mundos demonstra que um ID homônimo fora do mundo não interfere no plano local. O teste regional demonstra que um claim de fora da região, mesmo indicado pelo chamador, não comprova a origem de um lote local.

## R1-B — Identidade e revisões

O teste confirmou dois comportamentos. O mesmo pedido no mesmo estado produz plano idêntico. Pedidos independentes com o mesmo ID podem produzir planos diferentes sem efeitos econômicos. Essa segunda possibilidade é risco preventivo para C2, pois a preparação C1 nunca reserva ou compromete números de operação.

Na base, `prior_plan` adulterado ou com tipo inválido era ignorado ou aceito. A revisão exige um plano anterior íntegro e atual deste canteiro quando o parâmetro é fornecido. A revalidação o recalcula a partir dos participantes atuais. Com esse contexto validado, conflito de operação ou reuso conflitante de lote é recusado. `expected_revisions` exige a tabela completa de revisões inteiras. A revalidação verifica tipos e IDs antes de consultar participantes e compara o plano integral com o novo cálculo. Isso detecta adulterações do plano, sem transformar o conteúdo em recibo autenticado ou capturar a intenção original de pedidos independentes.

A futura autoridade regional deve aplicar identidade única, vincular a operação a site e geração, reserva, pilha, trabalhador, recurso, quantidade e lote, revalidar sob guardas, registrar recibo no commit, retornar o recibo em replay idêntico e recusar conflito. A C1-R1 é uma preparação pura e conserva `commit_supported = false`.

## R1-C — Elegibilidade e alcance

A reprodução confirmou que o diagnóstico contábil aceita uma unidade não registrada e fora do alcance da pilha. O plano e o resultado da revalidação agora expõem `validation_scope = "accounting_only"`, `dry_run_only = true`, `commit_supported = false` e `physical_pickup_authorized = false`. O plano informa `worker_registered`. O modo `require_assigned_worker` recusa unidade não registrada. Para trabalhador registrado, a preparação exige papel de fornecedor solo ou transportador e a ordem de construção ativa e atual daquele trabalhador para este canteiro. A elegibilidade contábil continua respeitando as pendências e o saldo disponível para claims.

A execução futura exige claim de retirada pendente, atribuição e ordem atuais e validação imediatamente anterior à mutação sob guardas. O saque existente em `ConstructOrder._execute_pile_withdrawal()` usa `BuildSlotPlanner.is_unit_in_pile_reach()`, que verifica desnível, distância horizontal e acesso físico no mundo. A posição pode mudar entre preparação e execução sem alterar quantidades ou revisões econômicas. Por isso, o teste usa esse mecanismo para provar que uma unidade distante pode obter diagnóstico contábil sem autorização física. A C2 deve repetir o predicado real no mundo correto e confirmar a pilha e o claim vivos.

## Conformidade e validação

O GDD v1.2 §4.2–4.3 conserva DEC-11A/B, transporte físico D2, organização D9 e separação entre complemento e cancelamento D3. A revisão aplica a conciliação de origem e a fronteira de preparação da T3.6-R2 §§4–5, commit `69c13275a34a30564ac839ec920f83ef36590812`. Nenhuma regra econômica ou fluxo jogável foi alterado.

Arquivos de código e teste alterados

- [ConstructionSite](../../src/buildings/construction_site.gd)
- [Suíte de preparação do saque reservado](../../tests/integration/test_t3_6_2_c1_reserved_withdrawal_prep.gd)

Na reprodução anterior à correção, os cinco testes originais passaram e os três novos falharam com oito divergências esperadas em **252 asserções**. A execução intermediária passou 8/8. Na versão final, cinco testes novos e cinco originais verificaram os diagnósticos, a mistura de carga livre e reservada, isolamento, idempotência local, revisões ABA e ausência de efeitos. Os casos com captura de sinais compararam snapshots de pilhas, reserva, inventário, mochila e ledger, claims, buffer, consumo, estado do canteiro e revisões antes e depois. A inspeção de alcance não executou saque.

| Comando | Resultado |
|---|---|
| `tools/run_tests.ps1 -Filter test_t3_6_2_c1` | 10/10 testes, 1 suíte, 282 asserções. |
| `tools/validate.ps1` | 129 scripts e inicialização headless aprovados, zero erros ou avisos. |
| `tools/run_tests.ps1 -Segmented` | 311/311 testes em 46 suítes, 13.514 asserções, zero falhas ou erros de suíte. Dez lotes aprovados, 46 suítes descobertas e executadas uma vez, sem omissões ou duplicatas. |
| `git diff --check` | Aprovado. |

A candidata é indicada para nova auditoria do contrato de preparação. A evidência é automatizada e headless. A validação contábil não encerra o risco de execução entre pilha, mochila e claim, que depende da futura autoridade regional e do alcance no instante do saque.
