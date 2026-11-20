# T3.6.2-C4.10 — Autoridade regional na contribuição de trabalho

| Referência | Valor |
|---|---|
| Branch candidata | `feat/t3-6-2-provenance-transactions` |
| Baseline C4.9-R3 | `a6ba8e6b595f57bbb546daef1b1c76cf3ab8eeab` |
| Main de referência | `25e0a20f1d6a2f10a9e059afe69759fbe263db4a` |
| Ambiente | Godot 4.7.2 stable, Windows, testes headless |

## Escopo e referências

A candidata trata apenas a contribuição de trabalho de P6. A verificação confrontou AGENTS.md, o GDD v1.2, a arquitetura T3, a auditoria C4.1, os registros C4.7 a C4.9-R3 e a arquitetura histórica T3.6-R2 no commit `69c13275a34a30564ac839ec920f83ef36590812`. A R2 histórica serviu como referência técnica. O percurso inspecionado incluiu `ConstructOrder`, `ConstructionSite`, `ConstructionManager`, `ReservedWithdrawalCoordinator`, `RegionalAuthority` e as guardas de inventário e dos backends de armazenamento. [GDD](../Dawn_of_Kin_GDD.md) · [Arquitetura T3](../architecture/T3_architecture_PROPOSAL.md) · [Auditoria C4.1](T3_6_2_C4_1_readiness_inspection_report.md) · [C4.9-R3](T3_6_2_C4_9_R3_commit_authorization_candidate_report.md).

## RED no baseline

A suíte rodou com a produção no baseline. Um teste passou e um falhou, com 154 asserções e zero erros de suíte. Em `buffer_changed` de um canteiro A, a consulta regional respondia desocupado e outro canteiro B do mesmo domínio conseguia consumir 1 madeira e avançar 250.000 µs. O snapshot de B passou de 4 para 3 madeiras no buffer, e a revisão passou de 13 para 14. Um depósito síncrono no inventário também foi aceito e creditou 1 madeira ao estoque. Em `state_changed`, a região também era observada como desocupada. Os mesmos resultados ocorreram em `GroundPileManager` e `InMemoryStorageSource`. Isso demonstra mutações econômicas concorrentes no callback. A reprodução não demonstrou duplicação nem perda de materiais.

As guardas preexistentes já recusavam a reentrada no próprio canteiro e a criação de outro canteiro na região. O trabalho em outra região funcionou. O controle de escassez, retomada e conclusão automática passou no baseline. Um RED complementar, sobre a primeira versão da guarda regional, reproduziu a troca de ordem do mesmo trabalhador dentro de um quadro físico. Dois canteiros contabilizavam o mesmo trabalhador naquele quadro e as duas asserções adversariais falharam.

## Correção

- `ConstructionSite.contribute_work()` adquire o escopo econômico antes de avaliar e aplicar o trabalho. Continua como o ponto de entrada para o débito proporcional e para a atualização de progresso. Os sinais existentes são emitidos após a aplicação, com a guarda regional ainda ativa. O escopo é liberado no mesmo retorno, inclusive se a avaliação recusar o trabalho. [Canteiro](../../src/buildings/construction_site.gd).
- O coordenador usa a `RegionalAuthority` vinculada quando existente, ou registra uma autoridade temporária em `World3D` durante a chamada síncrona para os fluxos legados. Os dois backends usam suas guardas existentes e o físico protege também a zona de estoque, quando presente. O escopo reutiliza a validação de participantes da complementação e recusa domínios ambíguos. Regiões independentes no mesmo mundo continuam operantes quando usam participantes econômicos distintos. [Coordenador](../../src/economy/reserved_withdrawal_coordinator.gd).
- O marcador do último quadro físico passa a pertencer ao trabalhador. A troca de obra não apaga o marcador, dois trabalhadores diferentes podem contribuir no mesmo quadro e o primeiro volta a contribuir no quadro seguinte. [Unidade](../../src/units/unit.gd).
- A suíte C4.10 usa canteiros, ordens e trabalhadores reais, com posicionamento controlado no slot para acionar as contribuições determinísticas. O teste verifica contabilidade, pausa, retomada e substituição pelo edifício via gerenciador. O fixture com dois estoques independentes da T3.4.2 passa a montar cada cenário em seu próprio mundo. As expectativas foram preservadas. Os fixtures da C4.10 também isolam o mundo de teste para a conclusão de uma obra física não compartilhar metadados com testes de ciclo de vida montados na raiz. [C4.10](../../tests/integration/test_t3_6_2_c4_10_work_regional_authority.gd) · [T3.4.2](../../tests/unit/test_t3_4_2_deterministic_assembly.gd).

## Validação e publicação

| Verificação | Suítes | Testes aprovados | Asserções | Falhas / erros de suíte |
|---|---:|---:|---:|---:|
| Suíte C4.10 | 1 | 3/3 | 179 | 0 / 0 |
| `run_tests.ps1 -Filter test_t3_6_2 -TimeoutSeconds 240` | 24 | 180/180 | 11.325 | 0 / 0 |
| `run_tests.ps1 -Segmented -GroupTimeoutSeconds 240` | 67 | 477/477 | 26.105 | 0 / 0 |

A regressão segmentada executou 17 lotes, com todas as 67 suítes descobertas, zero duplicatas e zero omissões. Incluiu logística e interface T3.3, consumo e ordens reativas T3.4, conclusão e navegação T3.4.4/T3.4.5, e catálogo e inspetor T3.5.1/T3.5.2. As três execuções de testes não registraram avisos ou erros do Godot.

`validate.ps1` passou na importação, na validação de 161 scripts e na inicialização headless da cena principal, com zero erros e zero avisos. `git diff --check` passou.

Durante o GREEN, as duas notificações observaram a região ocupada. A contribuição da obra B e o depósito de madeira foram recusados. Os snapshots de B permaneceram idênticos, e a operação em outra região continuou possível. No mesmo quadro, os dois construtores de A consumiram duas madeiras em 0,5 s de trabalho total. Na retomada após escassez, o gerenciador removeu o canteiro e criou exatamente um edifício com quatro madeiras incorporadas em cada backend.

| Commit | SHA |
|---|---|
| Produção | `7b20728884a65068a360d7398d3f008db3cb781e` |
| Testes e UID Godot | `2eff34fe9b8476e4db8ae03a4f2aebb3cbb47706` |

O commit documental que contém este arquivo identifica o SHA final da candidata. [Branch no GitHub](https://github.com/Julian0s/Dawn-of-Kin/tree/feat/t3-6-2-provenance-transactions).

## Limites

Os testes são headless. Inspeção visual e benchmark de desempenho não foram executados. A verificação de participantes percorre os canteiros registrados a cada contribuição e dispensa a ordenação nesse caminho. O custo para regiões maiores não foi medido. A garantia cobre os pontos de entrada cooperativos exercitados. A política de sinais pós-commit de `DEC-T3.6-SIGNALS-01` continua pendente, e a auditoria dos demais acessos diretos da economia permanece em P6. Esta candidata não encerra P6 nem T3.6.2. D3, C4.11 e a ativação global de proveniência permanecem fora da entrega.
