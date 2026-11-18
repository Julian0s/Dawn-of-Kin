# T3.6.2-C3.1 — Preparação da entrega seletiva ao canteiro

Candidata para auditoria independente. Base local e remota `73b084a3fdce0957096490e423fdfe46adb07d29` na branch `feat/t3-6-2-provenance-transactions`. Main de referência `25e0a20f1d6a2f10a9e059afe69759fbe263db4a`. Worktree `C:\Projetos\Dawn_of_Kin_wt_t3_4_5`.

## Contrato

`SelectiveSiteDeliveryPlanner.prepare_selective_site_delivery(site, unit, operation_id, requested_amounts)` deriva a mochila da unidade e verifica a obra ativa, os participantes, o estoque, o mundo e a região. Uma solicitação vazia seleciona o máximo elegível por recurso. Uma solicitação explícita exige quantidades positivas inteiras e é aceita integralmente ou recusada. A ordem determinística é lexical por recurso e, dentro dele, por ID do lote. Cada débito registra quantidade original, entrega proposta, saldo do lote e um identificador local da simulação. Um débito parcial preserva a identidade do lote residual.

A seleção usa somente lotes `SITE_RESERVED` atribuídos à obra e à geração atuais, com a identidade do trabalhador e igualdade entre agregado, proveniência e claim. Usa a verificação pura da C1-R1 para obras vizinhas e rejeita procedência desconhecida, ambígua ou divergente. O ledger clonado é reconstruído pelo histórico antes da simulação. Os pesos registrados são conferidos contra as definições da fonte, e o recurso selecionado também é comparado com a definição do canteiro. Os débitos ocorrem somente no clone. O plano contém os estados anterior e projetado de carga, pesos por recurso, ledger, claim e contabilidade.

A entrega legada calcula o mínimo entre claim, necessidade restante, carga física e teto após reservas e trânsito de outros trabalhadores. A preparação usa o mesmo teto, com a restrição adicional de origem. Exige previamente a contabilidade reconciliada da obra, com trânsito, buffer, incorporado e reservas dentro do custo. Cada débito reduz o trânsito e eleva o buffer pelo mesmo valor, preservando `T + B`, reservas, déficit e material incorporado. Nenhum saldo livre ou de outra obra entra no buffer desta obra.

## Revalidação e autoridade

`SelectiveSiteDeliveryPlanner.validate_selective_site_delivery_plan(site, unit, plan)` verifica tipos e campos, recompõe um plano independente e compara identidade, revisões e conteúdo integral. A identidade cobre instâncias de site, mundo, unidade, mochila, inventário e fonte, além da geração, região e IDs econômicos. As revisões cobrem canteiro, mochila, inventário, estoque, ledger de reservas e obras com claims correspondentes. A proveniência da mochila usa seu snapshot completo e a revisão da própria mochila, pois o ledger de proveniência não possui revisão separada. Alterações legítimas de capacidade que retornam ao valor original invalidam o plano pela revisão.

O planejador consulta a mesma validação de domínio da C2-R1 por uma entrada de leitura. Ela recusa domínio ambíguo, ocupado ou operação já confirmada. A consulta funciona sem criar autoridade, metadados ou recibo. Também são recusados conflitos com operações da mochila e dos débitos simulados. Planos não comprometidos não reservam recursos nem IDs. A C3.2 deverá garantir a unicidade entre saque e entrega no commit regional.

## Fronteira física e normas

O resultado declara `dry_run_only = true`, `commit_supported = false`, `physical_delivery_authorized = false` e `validation_scope = "accounting_only"`. Uma `ConstructOrder` ativa não é exigida no diagnóstico. A carga e o claim válidos continuam demonstráveis após a interrupção de uma ordem. A autorização no instante de uma futura entrega depende das regras operacionais e de `BuildSlotPlanner.is_unit_in_site_dropoff_range()` com a posição e o mundo atuais.

A revisão aplica os contratos de proveniência e contabilidade da T3.6-R2 §§4–5, commit `69c13275a34a30564ac839ec920f83ef36590812`, com D2, D9, D3 e DEC-11A/B do GDD v1.2 §§4.2–4.3 preservados. O legado T3.3–T3.5.2 conserva seu fluxo. A ordem dos sinais da C2-R1 permanece em vigor na candidata. A diferença em relação à proposta R2, sob a referência provisória `DEC-T3.6-SIGNALS-01`, continua pendente de consolidação pelo proprietário. A C3.1 é uma preparação pura e não emite sinais econômicos.

## Validação

Os testes utilizam pilhas e canteiros reais, saque comprometido pela C2-R1, coleta livre pela B3.2, claims de outras obras e trabalhadores, e cargas de ordens interrompidas. Casos adversariais cobrem quantidades inválidas, excesso, saldos ou pesos divergentes, identidade e geração, conflitos de ID, adulteração, ABA e alterações em mochila, claim, buffer e obra vizinha. As verificações de pureza comparam snapshots com pilhas, reservas, recibos, autoridades, revisões, mochila, claims, buffer, progresso, ordem, posição e número de nós. A captura de sinais cobre mochila, canteiro, estoque e inventário. Um teste usa uma carga reconciliada pré-existente na fixture para provar que uma preparação válida também é pura na ausência de autoridade regional.

Na primeira execução específica, a classe nova ainda não estava no cache global do editor. A suíte passou a carregar o script explicitamente. Na execução seguinte, uma comparação acusou os nós de um trabalhador criado pela própria fixture entre os snapshots. A comparação foi deslocada para antes e depois da preparação, com as mutações deliberadas isoladas, preservando a verificação de ausência de efeitos.

| Verificação | Resultado |
|---|---|
| `tools/run_tests.ps1 -Filter test_t3_6_2_c3_1` | 6/6 testes, 1 suíte e 159 asserções. |
| `tools/run_tests.ps1 -Filter test_t3_6_2` | 44/44 testes, 6 suítes e 1.294 asserções, incluindo B3.2, C1-R1 e C2-R1. |
| `tools/validate.ps1` | 133 scripts e inicialização headless aprovados, zero erros ou avisos no Godot 4.7.2.stable.official.ed1daf0bf. |
| `tools/run_tests.ps1 -Segmented` | 333/333 testes, 48 suítes e 14.327 asserções. Dez lotes aprovados, zero falhas ou erros de suíte, nenhuma omissão ou duplicata. |
| `git diff --check` | Aprovado. |

## Arquivos e limites

- [Planejador e revalidação](../../src/economy/selective_site_delivery_planner.gd) e seu UID.
- [Coordenador C2](../../src/economy/reserved_withdrawal_coordinator.gd), com consulta pura ao domínio econômico.
- [Suíte de integração](../../tests/integration/test_t3_6_2_c3_1_selective_delivery_prep.gd) e seu UID.

Os resultados são headless. A C3.2 continua bloqueada e depende de autorização própria para revalidar sob guardas, verificar alcance e elegibilidade da ordem, aplicar débitos e créditos, restaurar participantes em caso de falha, gravar um recibo regional e publicar sinais. A análise do plano não comprova chegada ao ponto de entrega. A política de seleção é determinística para diagnóstico e não altera o gameplay.
