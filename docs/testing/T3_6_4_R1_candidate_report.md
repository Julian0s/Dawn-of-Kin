# T3.6.4-R1 — Diagnóstico de recuperação e layout do inspetor

Candidata na branch `feat/t3-6-3-cancellation-custody`. Base manual `818b2bc67e627151025d9392580fcb0a61136f1f`. Commit dos testes RED `b700cb172b31056679331b8251d016eac73dcea0`. Correção e cobertura complementar em `aa46793b2f852beb0eccad4855ab8da14813cfd2`.

**Situação** — regressão automatizada aprovada. D3-04 e D3-07 aguardam reteste manual do proprietário. A homologação integral continua pendente.

## Rodada manual de 21/11/2026 na candidata original

Resultados históricos conforme a rodada comunicada para esta revisão. Os seis aceites permanecem registrados para aquela candidata. Os procedimentos originais continuam disponíveis no [protocolo manual](T3_6_4_manual_test_protocol.md).

| Caso | Resultado na base | Observação da rodada |
| --- | --- | --- |
| D3-01 | Aprovado | Voltar e trocar a seleção descartaram a prévia. |
| D3-02 | Aprovado | A prévia distinguiu reserva, material físico e perdas. |
| D3-03 | Aprovado | Retorno observado de 10 madeiras e 6 pedras. Estoque de madeira de 14 para 24, pedra de 6 para 12. |
| D3-04 | Reprovado | Líder B obedeceu ao movimento e conservou 6 pedras, com carga 18/20. Após a descarga do colega, o painel omitiu a interrupção. |
| D3-05 | Aprovado | Sem equipe, 10 madeiras e 5 pedras permaneceram no local. |
| D3-06 | Aprovado | Acompanhamento concluído após a descarga, com local e trânsito zerados. |
| D3-07 | Reprovado | O Debug cobriu parte de Recuperações nas duas resoluções. |
| D3-08 | Aprovado | Cliques e controles RTS verificados. A verificação de DEC-11B usou cenário preparado com déficit de uma madeira. A reserva passou de 11 para 12, a madeira livre de 3 para 2 e o déficit chegou a zero. |

## D3-04 — Interrupção com outro trabalhador em atividade

Na base, `RecoveryOrder.cancel()` registrava `RETURN_BLOCKED/manual_override`. Uma retirada ou descarga subsequente passava por `CancellationRecoveryTransaction._advance()`, que mudava o registro agregado para `RETURNING` e limpava o motivo. O inspetor dependia exclusivamente desse par de valores. No RED ele mostrou bloqueio global durante uma recuperação mista e, depois da descarga do colega, exibiu “Trabalhadores devolvendo materiais” com diagnóstico vazio.

O [despachante](../../src/units/cancellation_recovery_dispatcher.gd) consulta as designações daquele cancelamento e os lotes em trânsito por identidade de trabalhador na custódia regional. Uma interrupção manual é exibida enquanto o trabalhador conserva carga dessa recuperação. Uma ordem ativa só conta para a lista de trabalhadores em recuperação se houver carga própria ou material local para retirar. O [gerenciador](../../src/buildings/construction_manager.gd) expõe a consulta ao [inspetor](../../src/ui/building_inspector_panel.gd). O painel mostra os dois trabalhadores no caso misto, mantém o diagnóstico quando resta só a carga interrompida e o descarta na redesignação ou liquidação. A atualização usa o timer já existente do acompanhamento.

Na MainScene de teste, dois trabalhadores receberam ordens de recuperação. Um recebeu e concluiu um MoveOrder com carga. O colega continuou até descarregar e esgotar o saldo local. A mochila do interrompido permaneceu idêntica e ele terminou o movimento sem receber ordem automática. A reabertura e atualização do painel preservaram o snapshot de custódia (incluindo A/H/E/D, revisão e lotes), os recibos regionais, os totais físicos, livres e reservados, a reserva do canteiro e as mochilas com proveniência. A redesignação pela API B1.4 removeu o alerta e a descarga final chegou a SETTLED.

## D3-07 — Tamanho efetivo do Debug e F3

No RED, nas duas resoluções, o painel Debug ocupou de y=14 até y=133. O botão começava em y=116, com 17 pixels lógicos de sobreposição. A [MainScene](../../src/main/main.gd) agora fornece ao inspetor o controle real do painel Debug. O inspetor reage a mudanças de retângulo e visibilidade. Ele posiciona Recuperações seis pixels abaixo do Debug visível e coloca o inspetor abaixo do botão visível. F3 libera o espaço quando o Debug é ocultado.

O teste usou a cena jogável em SubViewport nas duas resoluções, aumentou a altura mínima do Debug em 24 pixels, enviou F3, verificou os retângulos do botão, inspetor, estoque, seleção, catálogo, Construir e barra temporária e enviou clique ao viewport para reabrir o painel. A seleção persistiu e o personagem continuou sem ordem. A legibilidade na janela real e o conforto do clique permanecem para o reteste humano. [Suíte de integração](../../tests/integration/test_t3_6_4_cancellation_ui.gd).

## Execuções em Godot 4.7.2

| Execução | Resultado |
| --- | --- |
| T3.6.4 RED na base, com dois testes novos | 6/8 aprovados, 124 asserções, 9 verificações falharam nos dois cenários esperados, zero erros de suíte |
| T3.6.4 GREEN com os testes do RED | 8/8 aprovados, 124 asserções |
| T3.6.4 GREEN com verificações adicionais | 8/8 aprovados, 153 asserções |
| T3.6.3-B1.4, despacho e recuperação | 16/16 aprovados, 178 asserções |
| T3.5.2, inspetor e complementação | 3/3 aprovados, 64 asserções |
| Regressão segmentada, timeout por grupo de 240 s | 528/528 aprovados, 27.449 asserções, 18 grupos, 73 suítes descobertas e 73 únicas executadas, zero faltantes, duplicatas, falhas ou erros de suíte |
| validate.ps1 | Importação, verificação dos 173 scripts e inicialização headless aprovadas, zero erros e avisos |
| git diff --check | Aprovado. O Git informou normalização CRLF/LF no worktree Windows. |

## Reteste no jogo

Na pasta `C:\Projetos\Dawn_of_Kin_wt_t3_4_5`, execute `.\tools\run_game.ps1 -Resolution "1280x720" -FailOnWarnings`.

1. **D3-04.** Reúna pelo menos 12 madeiras e 6 pedras, posicione um Abrigo Básico a alguma distância do acampamento e designe os dois líderes. Aguarde transporte ou entrega física de material. Com a obra ainda ativa, selecione o canteiro, abra **Cancelar construção**, confira que há carga recuperável e confirme. Se a prévia expirar por mudança na obra, abra-a novamente.
2. Quando os dois estiverem em recuperação e o Líder B estiver carregado, selecione **somente B** e dê clique direito em terreno livre, longe do acampamento. Clique em **Recuperações**. Enquanto o colega continua, procure **Recuperação em andamento**, o nome do colega em recuperação e o de B na mensagem de carga pendente por ordem manual.
3. Deixe o colega descarregar. Confira o aumento de E e do estoque pela descarga efetiva. Após esgotar o material no local, a carga de B deve continuar em H e na mochila, com **Recuperação bloqueada** e a identificação de B. Feche e reabra o painel. O diagnóstico deve persistir e B deve respeitar a ordem de movimento. A quantidade exata depende do instante da interrupção. A redesignação explícita é uma API interna coberta na automação. Para conferir **Recuperação concluída** na interface, use uma segunda obra e deixe ambos retornarem sem interrupção até A=H=0.
4. **D3-07.** Após confirmar pelo menos um cancelamento, pressione F3 até o Debug ficar visível. Confira o botão inteiro abaixo dele. Clique no centro e perto das bordas do botão, fechando o inspetor entre tentativas. Verifique que o painel abre e o clique preserva seleção e ordens.
5. Oculte e reexiba o Debug com F3. Confira que o botão ocupa o espaço liberado e volta a ficar abaixo do Debug. Com um personagem selecionado, confira estoque e seleção. Abra o catálogo **Construir** e alterne a barra temporária com **F8**. Confira que botão e inspetor continuam legíveis e acessíveis. Repita em **1920×1080** pelo controle de resolução ou reiniciando com `-Resolution "1920x1080"` e reproduzindo um cancelamento.

| Reteste R1 | Resultado do proprietário | Observações |
| --- | --- | --- |
| D3-04 | Aguardando reteste | |
| D3-07 | Aguardando reteste em ambas as resoluções | |
