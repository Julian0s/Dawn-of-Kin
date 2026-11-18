# T3.6.2-B3.2 — Transferência controlada de fonte para mochila

Base `914cedbbb96bde3a74c8745b10fb9eebfba64209`, branch `feat/t3-6-2-provenance-transactions`; referência T3.6-R2 `69c13275a34a30564ac839ec920f83ef36590812`. Commits técnicos: `ef3007034a6a783fdb706cf6307f73081316160b` (implementação) e `425027e657e60e14a374afb2bd3041949c06309f` (testes).

## Contrato

`ResourceSource.transfer_to_carry_load_with_provenance(load, operation_id, lot_id, requested_amount)` é explícito e opt-in: exige mochila com proveniência. Retorna `ok`, `reason`, `replayed`, `extracted` e, em sucesso, `committed_amount`. A repetição de um recibo consistente retorna `extracted=0` e o valor histórico em `committed_amount`, inclusive com a fonte esgotada; parâmetros conflitantes são recusados. O recibo vincula fonte, identidade da mochila por referência fraca, recurso, peso, lote, solicitação e quantidade. Os recibos residem na fonte durante sua existência e não são persistentes.

Após checagem do recibo, guardas de fonte e mochila são adquiridas antes das validações da nova operação. O plano `FREE_GATHERED` é preparado sem mutação; revisões e estado são revalidados antes de aplicar a mochila silenciosamente. A fonte é deduzida pela mesma quantidade e o recibo é registrado sem callback intermediário; só então ocorrem atualização visual e sinais, com guardas mantidas. Falha antes da aplicação libera guardas e preserva os dados econômicos; não se promete rollback de efeitos introduzidos por código externo de teste. A guarda e os campos internos GDScript são convenções cooperativas, não barreira contra código que modifique deliberadamente dados internos.

A revisão da mochila avança em mutações de carga/capacidade, restauração legada, ativação e aplicação silenciosa; a fonte avança nas mudanças de saldo/configuração e atributos relevantes. O teste alterna capacidade e a devolve ao valor anterior entre preparação e commit; a revisão recusa o plano, apesar da igualdade final. Mudanças diretas e não cooperativas em campos internos ou propriedades mutáveis de recursos compartilhados não são protegidas por uma autoridade regional. A futura coordenação deve tratar essa fronteira antes de ativação global. Não há persistência em disco nem protocolo multicomponente de cancelamento.

O caminho legado continua numérico e sem proveniência global. Em mochila opt-in, a adição legada recusada impede a extração sem contexto. A transferência controlada não modifica ordens, canteiros, depósito ou HUD.

## Verificação

`tools/run_tests.ps1 -Filter t3_6_2_b3_2_source_transfer`: 4/4 testes, 79 asserções. Fontes reais de madeira, pedra e alimento; extrações sucessivas, esgotamento, replay e conflito, capacidade e peso, IDs, falha forçada após preparação, revisão obsoleta, observadores de ambos sinais e reentrância. Os observadores viram fonte=3 e mochila=2 e balanço válido após retirada de 2 de 5, e ambas as tentativas reentrantes foram recusadas. Os testes comparam snapshots da mochila/ledger e saldo da fonte nas falhas; a falha de capacidade não emitiu sinais.

A primeira execução segmentada passou 301 testes em 45 suítes, 13.232 asserções. A ordem de guardas foi então ajustada, e a suíte específica e as validações foram executadas novamente. Na versão final: `tools/validate.ps1` verificou 128 scripts, zero erros e avisos; `tools/run_tests.ps1 -Segmented` passou 301/301 testes, 45 suítes, 13.235 asserções, zero falhas ou erros de suíte, 45 descobertas e executadas sem omissões ou duplicatas. `git diff --check` aprovado. Nenhum teste visual manual foi realizado.

A proveniência não é ativada automaticamente no jogo. Saque reservado, claim, entrega seletiva, retorno e cancelamento D3 permanecem pendentes e não são cobertos por esta transação. O commit deste relatório consta no histórico Git.
