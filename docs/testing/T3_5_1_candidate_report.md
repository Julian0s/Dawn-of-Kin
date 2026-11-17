# T3.5.1 — Relatório da candidata

Base: `2a6cce6d190f6d93679b7921cb973770a0c5f9a5`. Branch: `feat/t3-5-1-build-catalog-ui`. A candidata aguarda auditoria independente e testes manuais do proprietário.

## Implementação

`ConstructionHud` apresenta o botão e o catálogo retrátil. Nome e custo são lidos das instâncias `BuildingDefinition` já usadas no jogo; a escolha aciona `PlacementController` existente. O catálogo fecha ao selecionar ou iniciar posicionamento e Esc fecha o catálogo aberto. A prévia, confirmação assíncrona e cancelamento de posicionamento permanecem no controlador original.

Os controles provisórios do `PlacementTestOverlay` ficam ocultos na experiência normal e podem ser abertos por F8. Seus botões de catálogo são ocultados nessa composição; F6/F7, inspeção provisória, resolução, trabalhadores temporários e as APIs de teste permanecem disponíveis. A interface usa a paleta `HudStyle` e filtros de mouse dos controles para impedir propagação dos cliques ao RTS.

O GDD e `AGENTS.md` registram estados históricos anteriores à integração da T3.4.5. A decisão D7 continua normativa; o [aceite T3.4.5](T3_4_5_closeout_ACCEPTANCE.md) e a autorização específica do incremento definem o estado posterior. Inspetor definitivo, complementação manual, cancelamento de obra, depósito protegido e persistência permanecem fora deste incremento.

## Verificação

A suíte específica `test_t3_5_1_construction_hud` passou com 3 testes e 35 asserções: catálogo e custos, cliques e seleção, Esc/RMB, confirmação e rejeição, e geometria/interação nas duas resoluções em SubViewport. Essas verificações não substituem a inspeção visual ou a aprovação manual. Consulte o [protocolo manual](T3_5_1_manual_test_protocol.md).

`tools/validate.ps1`: 120 scripts, inicialização headless, zero erros e avisos. `tools/run_tests.ps1 -Segmented`: 40 suítes, 281/281 testes e 12.854 asserções, zero falhas e erros de suíte; 40 descobertas e 40 executadas sem duplicação ou omissão. Foram incluídas as regressões de T1 a T3.4.5. `git diff --check`: sem erros.

Inspeção gráfica: pendente. A sessão gráfica aberta pertence à execução anterior e foi preservada; não há captura da interface atualizada ou aprovação visual do proprietário neste registro.
