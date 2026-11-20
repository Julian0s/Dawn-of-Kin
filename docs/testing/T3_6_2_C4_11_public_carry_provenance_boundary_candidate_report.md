# T3.6.2-C4.11 — Fronteira pública da proveniência na mochila

| Referência | Valor |
|---|---|
| Branch | `feat/t3-6-2-provenance-transactions` |
| Baseline local e remota | `2af4fb030d852176f5ba6c721e23f42373efd130` |
| Ambiente de validação | Windows, Godot 4.7.2 stable |

O escopo é a pendência P6 registrada em C4.1 para `UnitCarryLoad.add_with_provenance()`. A validação local do ledger garante a equivalência entre os lotes e a mochila. A conservação entre participantes exige que a entrada corresponda a um débito físico ou contábil na transação. O GDD v1.2, a arquitetura T3 e a arquitetura histórica T3.6-R2 no commit `69c13275a34a30564ac839ec920f83ef36590812` dão o contexto para essa distinção. Os relatórios C4.8 a C4.10 registram as fronteiras de obra e a política atual de publicação. [GDD](../Dawn_of_Kin_GDD.md) · [Arquitetura T3](../architecture/T3_architecture_PROPOSAL.md) · [C4.1](T3_6_2_C4_1_readiness_inspection_report.md) · [C4.10](T3_6_2_C4_10_work_regional_authority_candidate_report.md).

## Inventário no baseline

A busca por símbolo encontrou a definição e um comentário em produção, sem chamadas diretas. A coleta física prepara e aplica o plano por `ResourceSource`. O saque reservado prepara pelo canteiro e aplica pelo `ReservedWithdrawalCoordinator`, que coordena pilha, reserva e claim. As descargas seletivas usam suas transações próprias. [Mochila](../../src/economy/unit_carry_load.gd) · [Fonte física](../../src/economy/resource_source.gd) · [Saque reservado](../../src/economy/reserved_withdrawal_coordinator.gd).

| Arquivos de teste no baseline | Chamadas | Finalidade |
|---|---:|---|
| B2 `carry_binding` | 15 | Preparação de lotes, independência, replay, conflitos de operação e de ID, peso, capacidade e tentativa durante sinal |
| C1 `reserved_withdrawal_prep` | 6 | Carga inicial livre e reservada, histórico, estados incompatíveis e isolamento |
| C2 `reserved_withdrawal_transaction` | 4 | Carga com peso incompatível, geração errada, obra externa e tentativa em callback |
| C3.1 e C3.2 `selective_delivery` | 5 | Lotes desconhecidos ou históricos e colisões de identificadores |
| C3.4.3 `order_integration` e harness visual | 3 | Carga sintética para cenários de entrega seletiva |
| C3.5 `gather_order_integration` | 2 | Carga inicial e tentativa em callback da coleta |
| C4.2 `lifecycle_readiness` | 10 | Carga para entrega, ciclo de vida, isolamento, recusa de remoção e injeção deliberada no callback de ordem |
| C4.4 `rts_order_acceptance` | 2 | Carga inicial para fluxo RTS |
| C4.5 `unit_identity_capacity` | 8 | Carga inicial para identidade, capacidade e isolamento |
| C4.6 `gather_regional_isolation` | 3 | Carga inicial em unidades de regiões distintas |
| C4.7, C4.8 e C4.9 `authority` | 5 | Carga inicial para interações com conclusão, criação e complementação |
| Total | 63 | 14 suítes e 1 harness |

## RED e correção

No baseline, o novo teste registrou quatro cenários com duas madeiras criadas em cada mochila de teste. Cobriu lote `FREE_GATHERED` sem fonte, `SITE_RESERVED` sem saque ou claim, batch ativo e guarda do coordenador ativa. Em todos, o snapshot e a revisão mudaram, enquanto a validação da soma dos lotes continuou verdadeira. Houve um sinal imediato nos cenários sem batch e um sinal ao encerrar o batch. O RED passou em 4 de 5 testes, com 97 asserções e 27 falhas de asserção concentradas no novo teste, sem erros de suíte. [Teste RED/GREEN](../../tests/unit/test_t3_6_2_b2_carry_binding.gd).

A entrada pública conserva a assinatura posicional. Uma mochila habilitada e disponível retorna `transfer_required`. Uma mochila indisponível, em batch ou sob guarda retorna `unavailable`. A recusa não modifica carga, ledger, revisão ou sinais. Os pontos transacionais existentes continuam responsáveis por aplicar seu plano em conjunto com o débito correspondente. Manter apenas checagens adicionais de batch e guarda deixaria aberta a escrita pública em estado ocioso. Uma nova arquitetura de autorização seria redundante para esta entrada.

O fixture sob `tests/framework` usa o planejador, as guardas de aplicação e a publicação existentes para preparar estados sintéticos. Os argumentos e as asserções das chamadas migradas foram preservados. As tentativas dos callbacks existentes continuam verificando a guarda ocupada no caminho de aplicação exercitado pelo fixture. O novo teste verifica diretamente a recusa pública nos quatro estados. O harness também usa esse fixture. [Fixture](../../tests/framework/carry_provenance_fixture.gd).

## Validação e publicação

| Verificação | Suítes | Testes aprovados | Asserções | Falhas / erros de suíte |
|---|---:|---:|---:|---:|
| B2, incluindo o teste C4.11 | 1 | 5/5 | 97 | 0 / 0 |
| `run_tests.ps1 -Filter test_t3_6_2 -TimeoutSeconds 240` | 24 | 181/181 | 11.369 | 0 / 0 |
| `run_tests.ps1 -Segmented -GroupTimeoutSeconds 240` | 67 | 478/478 | 26.152 | 0 / 0 |

O GREEN confirmou a ausência de mutações e de sinais nas quatro tentativas públicas. A regressão focada também exercitou coleta real, saque reservado, claims, entregas seletivas, replay, idempotência e reentrância.

A execução segmentada concluiu 17 lotes, com as 67 suítes descobertas e executadas uma vez cada. Os logs das três execuções GREEN registraram zero erros ou avisos de Godot. `validate.ps1` aprovou importação, 162 scripts e inicialização headless, com zero erros ou avisos. `git diff --check` passou.

O commit de implementação e testes é `8092ed40929376ae3fcd7a3217f914a69da059a9`. O commit documental que contém este relatório identifica a revisão final da candidata. [Branch candidata](https://github.com/Julian0s/Dawn-of-Kin/tree/feat/t3-6-2-provenance-transactions).

## Limites

A mudança cobre a escrita pela entrada pública cooperativa. A mutação arbitrária de campos internos do GDScript fica fora dessa garantia. `ResourceSource.extract()` e os mutadores diretos de estoque permanecem no escopo pendente de P6. `DEC-T3.6-SIGNALS-01` permanece pendente. As verificações desta candidata são headless.
