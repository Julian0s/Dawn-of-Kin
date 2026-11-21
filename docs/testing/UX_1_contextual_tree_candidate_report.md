# UX-1 — Primeiro teste jogável do menu de trabalho

Candidata `feat/ux-1-contextual-tree`, baseada no [plano de encerramento da T3](../architecture/T3_closeout_contextual_plan.md) em `d914e1965b471230c432a93d9fc07eced8a37cf5`. O aceite do proprietário sobre o gesto está pendente.

## O que experimentar

No worktree da candidata, abra a cena de avaliação em 1280×720.

```powershell
.\tools\run_game.ps1 -Resolution "1280x720" -FailOnWarnings -ExtraArgs @("res://tests/visual/ux_1_tree.tscn")
```

| Ensaio | Ação e resultado esperado | Avaliação do proprietário |
| --- | --- | --- |
| Começar pela árvore | Clique com o esquerdo numa árvore. Confira o saldo e os dois nomes. Troque a sugestão e feche com Esc. Os líderes devem continuar parados. Reabra, marque uma pessoa e aperte **Cortar madeira**. Só a pessoa marcada deve cortar e descarregar no acampamento. | Pendente |
| Começar pela pessoa | Com um líder disponível, clique nele, escolha **Cortar madeira** e clique em uma árvore destacada. Observe qual árvore foi usada, a mochila no trajeto e a chegada da madeira ao estoque. | Pendente |
| Trabalhar em dupla | Em uma partida nova, marque os dois nomes na mesma árvore e confirme. Clique novamente na árvore para conferir a ocupação. A consulta deve explicar a falta de vagas e preservar as ordens em curso. | Pendente |

O ponto a avaliar é se fica fácil saber **quem vai trabalhar, em qual árvore e qual clique inicia a tarefa**. Registre onde esperou um resultado diferente.

## Implementação e alcance

A [cena de avaliação](../../tests/visual/ux_1_tree.tscn) herda a cena jogável com a economia de proveniência. O [adaptador de entrada](../../src/rts/tree_work_input.gd) interpreta o clique esquerdo e delega seleção, movimento e posicionamento aos controladores existentes. O [menu](../../src/ui/tree_work_menu.gd) oferece os nomes da equipe, sugere o habitante livre mais próximo com acesso e revalida a equipe na confirmação. Carga em trânsito, ocupação e falta de vagas impedem a troca silenciosa de tarefa. O despacho usa o mesmo CommandController e a mesma GatherResourceOrder da cena jogável.

Esta entrega abrange uma árvore por ordem. O jogo mantém sua cena inicial anterior. Grupos de fontes, rochas, frutos, obras e retirada do gesto antigo pertencem aos passos posteriores do plano.

## Evidências

A [suíte de integração](../../tests/integration/test_ux_1_contextual_tree.gd) envia eventos de mouse ao viewport. Em cada percurso individual, verifica o líder escolhido, a ordem do outro líder, a passagem da madeira pela mochila e o saldo físico no acampamento. Com dois líderes, verifica a lotação da árvore e a identidade das ordens após reabrir o menu.

Commit técnico `54a541a41c740e54de0b69a82c4205da7ed76a2e`. Execuções em Godot 4.7.2:

| Verificação | Resultado observado |
| --- | --- |
| `run_tests.ps1 -Filter test_ux_1_contextual_tree -TimeoutSeconds 240` | 3/3 testes, 35 asserções, zero erros de suíte. Os caminhos iniciados na árvore e no habitante chegaram à descarga. Na árvore lotada, as duas ordens originais permaneceram ativas. |
| `run_tests.ps1 -Filter test_t3_6_2_c4_12_rts_provenance -TimeoutSeconds 240` | 5/5 testes, 119 asserções, zero erros de suíte. Abrange admissão da equipe, recusa de identidade ambígua, coleta, descarga, construção e retorno de material à reserva original. |
| Abertura da cena de avaliação | Inicialização headless e abertura gráfica em 1280×720 com encerramento após 30 quadros e verificação de avisos. O log identificou OpenGL Compatibility e Intel UHD Graphics 620. |

O executor `tools/validate.ps1` concluiu a importação, a verificação dos 176 scripts e o arranque headless da cena principal com zero erros e zero avisos.

A avaliação de facilidade de uso permanece com o proprietário. A regressão segmentada completa e a medição de desempenho de encerramento da T3 continuam pendentes.
