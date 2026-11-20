# T3.6.2-C4.12 — Bloco A

Base `45762d59d7b2f85414781effeb1ffc2e1149ccb3`, branch `feat/t3-6-2-provenance-transactions`. Motor Godot 4.7.2 stable no Windows.

## Registro das decisões

| Decisão aprovada pelo proprietário | Aplicação |
|---|---|
| D-INT-01/B | Retorno físico ao acampamento e restauração na reserva da obra de origem antes de iniciar trabalho incompatível na nova obra |
| D-INT-02/A | Guardas cooperativas durante os sinais pós-commit, conforme `DEC-T3.6-SIGNALS-01` |
| D-INT-03/A | Admissão de unidades novas, com identidade válida e mochila vazia |

A autorização expressa de implementação do Bloco A sucedeu à revisão do plano C4.12. As opções estão definidas no [relatório C4.1](T3_6_2_C4_1_readiness_inspection_report.md).

## Marco 1 — Admissão e despacho

A cena jogável solicita o modo transacional. O coordenador verifica o domínio, os participantes, a ausência de transação concorrente, a identidade da definição e a disponibilidade de todas as mochilas antes de aplicar a admissão. A aplicação usa apenas atribuições síncronas sem sinais. O bootstrap publica o modo econômico ao controlador RTS depois dessa admissão. Uma recusa deixa o despacho econômico bloqueado com motivo e impede a configuração do posicionamento e do spawn. O par temporário é preparado fora da árvore, com verificação conjunta antes de ser inserido.

O controlador recebe a região efetiva da cena e verifica o domínio e o grupo escolhido antes de emitir ordens econômicas. Coleta aciona o fluxo transacional de fonte e descarga. Construção ativa saque, entrega seletiva e devolução de lotes reservados de outras obras. As suítes e os cenários feitos para testar os fluxos legados explicitam a configuração da cena antes de montá-la.

## Marco 2 — Conservação e precedência

O RED de carga mista em C3.4.3 mostrou a ordem entrando em entrega a A com o lote de B ainda em trânsito. Quando A recebeu pedra, o contador de retornos era zero, duas madeiras continuavam em trânsito e a reserva de B tinha duas das quatro madeiras esperadas. A suíte teve oito sucessos em nove testes e quatro falhas de asserção no novo caso. A correção prioriza o retorno elegível do lote de B antes da entrega ou do trabalho em A. Ela reaproveita os planos, o movimento e os recibos da entrega seletiva. O commit físico restaura a reserva e baixa o claim da obra de origem.

A suíte da cena jogável exercita coleta RTS de madeira, pedra e alimento, peso, saque e transporte, montagem e conclusão, recusa de admissão, preservação de ordem na recusa de despacho, recarga regional e retorno interrompido e retomado. A regressão C3.4.3 cobre ainda entrega sem slot, capacidade, replay, reentrância e bloqueio de D3.

## Validação

| Execução | Suítes | Testes aprovados | Asserções | Falhas / erros de suíte |
|---|---:|---:|---:|---:|
| C4.12 na cena jogável | 1 | 5/5 | 119 | 0 / 0 |
| Regressão focada T3.6.2, incluindo o GREEN de precedência | 25 | 187/187 | 11.508 | 0 / 0 |
| Regressão focada do inspetor após ajuste de fixture | 1 | 3/3 | 64 | 0 / 0 |
| Regressão segmentada final | 68 | 484/484 | 26.311 | 0 / 0 |

`validate.ps1` aprovou importação, 163 scripts e inicialização headless da cena jogável, com zero erros ou avisos. A segmentada final concluiu 17 lotes, executou uma vez cada suíte descoberta e registrou zero erros ou avisos de Godot. `git diff --check` passou.

A primeira segmentada passou em 483 de 484 testes. O cenário de conservação do inspetor criava diretamente uma ordem legada na cena agora transacional. A guarda recusou essa combinação e o teste parou antes da montagem. O cenário passou a escolher explicitamente o modo legado, preservando suas asserções e mantendo os outros testes do inspetor no modo padrão da cena.

O commit técnico é `71de1c5fcb47e35438d116930b18a86140ee2af3`. O commit documental que contém este relatório identifica a revisão final da candidata. [Branch candidata](https://github.com/Julian0s/Dawn-of-Kin/tree/feat/t3-6-2-provenance-transactions).

## Pendências

O Bloco A aguarda auditoria independente e aprovação manual do proprietário. Migração de mochilas carregadas, os demais mutadores econômicos pendentes de P6, D3, custódia, armazenamento protegido e persistência permanecem fora do aceite deste incremento. [Protocolo manual](T3_6_2_C4_12_block_a_manual_protocol.md).
