# Dawn of Kin — Protocolo Atualizado de Testes Humanos Finais (`R-03A D4` · `M1`–`M8`)

**Candidata:** `feat/r-03a-community-work-main-scene` (`C:\Projetos\Dawn_of_Kin_wt_r_03a`)  
**SHA técnico validado:** `e7d72e41a31861d41747d7d82239b7963626f497` (`D3.3-R1`) · **Base documental (`D3.4`):** `53306255c7cae5591c5eaea1ad4b1627d5486e22`  
**SHA documental final esperado na ponta da branch candidata:** confirmado por `git rev-parse HEAD` na entrega D4 e registrado em `evidencias\R-03A\D4\09_git_final\git_final.txt` *(não editar cenas, código ou flags para executar este roteiro)*.  
**Status obrigatório:** **`AGUARDANDO EXECUÇÃO PELO PROPRIETÁRIO`** · **`NENHUM CENÁRIO M1–M8 APROVADO`**

> [!NOTE]
> Este roteiro substitui integralmente o protocolo pré-D1/D2/D3 e reflete os contratos atualmente homologados (`D1`: seleção independente + autorização por categoria na HUD; `D2`: selo mineral `×`/`×N` de cancelamento seletivo; `D3`: corte progressivo de árvores de `2,5 s`, `1,5×` com 2 cortadores, queda irreversível de `0,50 s`, extração apenas pós-`FALLEN`; `P-REC-1`: construção legada ativa; `use_d2_2_hud = false`).  
> Os **21 testes humanos anteriores** (`13` da `D2` + `8` da `D3.2`) permanecem preservados e não precisam ser repetidos separadamente.

---

## 1. Comandos PowerShell Obrigatórios (Worktree Candidato)

### 1.1 Conferir a candidata antes de abrir o jogo
```powershell
Set-Location "C:\Projetos\Dawn_of_Kin_wt_r_03a"
git rev-parse HEAD
git status --short
```
*(O status do worktree deve estar limpo, em `feat/r-03a-community-work-main-scene`, no SHA documental final informado na entrega D4.)*

### 1.2 Abrir em `1280×720`
```powershell
Set-Location "C:\Projetos\Dawn_of_Kin_wt_r_03a"
.\tools\run_game.ps1 -Resolution "1280x720"
```

### 1.3 Abrir em `1920×1080`
```powershell
Set-Location "C:\Projetos\Dawn_of_Kin_wt_r_03a"
.\tools\run_game.ps1 -Resolution "1920x1080"
```

*(Opções verificadas em `tools\run_game.ps1`: `-Resolution`, `-FixedFps`, `-QuitAfter`, `-LogFile`, `-DebugNavigation`, `-DebugCollisions`, `-FailOnWarnings`, `-ExtraArgs`. Não utilizar flags experimentais durante os testes humanos.)*

---

## 2. Roteiro Integrado `M1`–`M8`

### `M1` — Abertura e integridade visual (`720p` e `1080p`)
- **Objetivo:** Confirmar inicialização limpa da `MainScene`, fontes naturais, câmera RTS, HUD legada (`use_d2_2_hud = false`) e legibilidade em `1280×720` e `1920×1080`.
- **Pré-condição:** Abrir a candidata pelos comandos §1.2 e §1.3 (com tomada CA conectada se avaliar fluidez).
- **Passos:**
  1. Observar a tela inicial sem selecionar nenhuma fonte.
  2. Movimentar a câmera RTS (WASD/bordas/zoom) ao redor do acampamento e das fontes.
  3. Pressionar `F3` para alternar o `DebugOverlay` e verificar posicionamento em ambas as resoluções.
- **Resultado esperado:** Cena inicial nítida; `Acampamento` no canto superior direito e `[Construir]` no canto inferior direito visíveis; **HUD contextual oculta** quando nada está selecionado; câmera suave; sem sobreposição indevida de painéis persistentes.
- **Sinais de reprovação:** Erro/travamento na abertura; HUD contextual aparecendo vazia; `DebugOverlay` cobrindo texto do estoque; corte de UI em `720p` ou perda de legibilidade em `1080p`.
- **Criticidade:** Alta (Bloqueante visual/boot).
- **Evidência recomendada:** Confirmação em `720p` e `1080p` (ou print se houver desvio).
- **Observações:** `______________________________________________________________`
- **Resultado:** `[ ] PASS` · `[ ] FAIL` · `[ ] NÃO TESTADO`

---

### `M2` — Seleção independente e autorização contextual
- **Objetivo:** Comprovar `SELEÇÃO → AUTORIZAÇÃO`, desmarcação seletiva `D1-B` e idempotência de cliques repetidos na HUD.
- **Pré-condição:** `MainScene` aberta com os dois protagonistas ociosos.
- **Passos:**
  1. Clicar com o botão esquerdo (sem `Shift`) em uma árvore (`Madeira`).
  2. Observar se algum habitante se move antes de clicar na HUD.
  3. Clicar novamente com o botão esquerdo (sem `Shift`) na **mesma** árvore selecionada.
  4. Selecionar `2` árvores com `Shift+clique` e clicar no botão `[Machado 2]` na barra inferior central.
  5. Clicar mais `2` vezes no mesmo botão `[Machado 2]` já autorizado.
- **Resultado esperado:** Passo 1 mostra apenas o anel dourado externo e `[Machado 1]` na HUD; Passo 2: zero movimento/tarefa criada; Passo 3: desmarca apenas aquela árvore (HUD some); Passo 4: autoriza madeira (laje verde com checkmark + selo mineral `×` acima com vão transparente de 6 px, ícone de machado acima das 2 árvores); Passo 5: não duplica tarefas nem reseta corte.
- **Sinais de reprovação:** Clique simples disparar trabalho automático; desmarcar fonte remover outras selecionadas indevidamente; selo `×` encostado/cortado; duplicação de tarefas.
- **Criticidade:** Crítica (`D1`).
- **Evidência recomendada:** Registro `PASS`/`FAIL` e anotação de fluidez do clique.
- **Observações:** `______________________________________________________________`
- **Resultado:** `[ ] PASS` · `[ ] FAIL` · `[ ] NÃO TESTADO`

---

### `M3` — Seleção heterogênea e controles RTS tradicionais
- **Objetivo:** Confirmar `Shift+clique`, `Shift+arraste`, arraste sem `Shift` dedicado a unidades e `Esc`.
- **Pré-condição:** Fontes e unidades visíveis no mapa.
- **Passos:**
  1. Fazer **arraste sem `Shift`** começando sobre uma árvore/pedra até englobar `Leader A` e/ou `Leader B`.
  2. Pressionar `Esc` para limpar seleção de unidades.
  3. Segurar `Shift` e fazer **arraste** (`Shift+arraste`) englobando árvores, pedras e arbustos ao mesmo tempo.
  4. Clicar apenas no botão `[Picareta N]` da HUD mantendo madeira e alimento ainda selecionados.
  5. Pressionar `Esc` e verificar o que acontece com a seleção e com a tarefa de pedra autorizada.
- **Resultado esperado:** Passo 1 seleciona **apenas habitantes** (caixa verde-oliva), nunca fontes; Passo 3 desenha caixa dourada e mostra os 3 ícones `[Machado N] [Picareta N] [Colheita N]` com contagens exatas; Passo 4 autoriza **somente pedra** mantendo a seleção heterogênea intacta; Passo 5 limpa a seleção visual (HUD some), mas a tarefa autorizada de pedra continua ativa com seu ícone acima das rochas.
- **Sinais de reprovação:** `Shift+arraste` selecionar unidades; arraste normal selecionar fontes; autorizar pedra apagar seleção de madeira/alimento; `Esc` cancelar tarefas autorizadas.
- **Criticidade:** Alta (`D1` / `R1-F02`).
- **Evidência recomendada:** Registro `PASS`/`FAIL`.
- **Observações:** `______________________________________________________________`
- **Resultado:** `[ ] PASS` · `[ ] FAIL` · `[ ] NÃO TESTADO`

---

### `M4` — Trabalho comunitário e distribuição
- **Objetivo:** Verificar múltiplas fontes autorizadas, distribuição entre os 2 protagonistas (1 atribuição por tarefa comunitária), continuidade e respeito às fontes não autorizadas.
- **Pré-condição:** Trabalhadores ociosos; estoque visível.
- **Passos:**
  1. Selecionar `3` árvores + `2` rochas com `Shift+arraste` e autorizar **somente madeira** `[Machado 3]`.
  2. Observar os `2` trabalhadores se distribuírem pelas árvores autorizadas.
  3. Deixar que completem ao menos uma tarefa enquanto outras árvores autorizadas continuam na fila.
- **Resultado esperado:** Cada trabalhador assume uma árvore autorizada distinta (nunca as rochas não autorizadas); ao concluir uma entrega, o trabalhador ocioso assume a próxima tarefa autorizada pendente.
- **Sinais de reprovação:** Trabalhador coletar fonte não autorizada; os 2 entrarem juntos na mesma tarefa comunitária ou permanecerem travados com tarefas pendentes elegíveis.
- **Criticidade:** Crítica (`D1` / `D3.2`).
- **Evidência recomendada:** Registro `PASS`/`FAIL`.
- **Observações:** `______________________________________________________________`
- **Resultado:** `[ ] PASS` · `[ ] FAIL` · `[ ] NÃO TESTADO`

---

### `M5` — Corte, derrubada e coleta física (`D3`)
- **Objetivo:** Validar o ciclo completo de derrubada da árvore (`STANDING → CHOPPING → FELLING → FALLEN → DEPLETED`), o corte combinado RTS (`1,5×`) e a atualização do estoque exclusivamente na entrega física.
- **Pré-condição:** Uma árvore intacta próxima ao acampamento (`WoodTree01`) e outra árvore para corte RTS em dupla (`WoodTree02`).
- **Passos:**
  1. Autorizar madeira em `WoodTree01` e acompanhar visualmente o corte (~2,5 s), a queda (~0,5 s), o recolhimento no tronco caído, a ida ao acampamento e o depósito na pilha física.
  2. Observar o painel `Acampamento` no canto superior direito **antes** e **depois** da entrega física.
  3. Selecionar ambos os protagonistas (`Leader A` + `Leader B`) e clicar com botão direito em `WoodTree02` (ordem RTS direta com 2 cortadores).
- **Resultado esperado:** Durante o corte e a queda o estoque no acampamento e a carga de madeira permanecem em `0` até `FALLEN`; a árvore tomba de forma contínua; somente após cair ocorrem extrações físicas e o contador no acampamento sobe quando o trabalhador descarrega fisicamente na zona do acampamento; no passo 3, os 2 trabalhadores cortam `WoodTree02` visivelmente mais rápido (`1,5×`).
- **Sinais de reprovação:** Madeira aparecer na mochila/acampamento antes de a árvore cair; árvore travar inclinada; estoque subir à distância sem entrega física no acampamento.
- **Criticidade:** Crítica (`D0-A03` / `D3`).
- **Evidência recomendada:** Confirmação visual do ciclo completo.
- **Observações:** `______________________________________________________________`
- **Resultado:** `[ ] PASS` · `[ ] FAIL` · `[ ] NÃO TESTADO`

---

### `M6` — Cancelamento seletivo (`D2`), reautorização (`D1-C`) e ordens pessoais
- **Objetivo:** Verificar selo `×`/`×N`, cancelamento pré-queda vs durante `FELLING`, reautorização explícita, entrega residual com carga e soberania de ordem pessoal *(preservando observação `HD3-06`)*.
- **Pré-condição:** Selecionar pelo menos `2` árvores e `1` rocha; autorizar ambas as categorias.
- **Passos:**
  1. Durante o corte **pré-queda** de uma árvore, clicar no selo mineral `×` acima de `[Machado]` na HUD. Verificar que a árvore retorna intacta ao estado `STANDING` e que a tarefa de pedra continua intacta.
  2. Reautorizar madeira, esperar a árvore entrar em **queda (`FELLING`)** e clicar novamente no selo `×` de madeira durante a queda.
  3. Verificar que a árvore **termina a queda até `FALLEN`**, mas nenhuma coleta acontece; em seguida clicar em `[Machado]` novamente para **reautorizar** a árvore caída e confirmar o recolhimento normal.
  4. Enquanto um trabalhador estiver indo/cortando uma tarefa comunitária, selecioná-lo e dar uma **ordem pessoal de movimento** (botão direito no chão distante). Observar que a ordem pessoal é obedecida imediatamente até chegar ao destino.
  5. *(Se houver carga já coletada)* cancelar a categoria durante o transporte para confirmar entrega residual legítima no acampamento sem retorno à fonte cancelada.
- **Resultado esperado:** Cancelamento seletivo nunca apaga outras categorias nem a seleção; pré-queda reseta corte sem extrair madeira; durante `FELLING` a queda conclui até `FALLEN` e pausa sem coleta até reautorização explícita pela HUD; ordem pessoal domina imediatamente sem sequestro comunitário *(nota `HD3-06`: ao **concluir** a ordem pessoal, se houver **outra** fonte autorizada pendente, o trabalhador pode assumi-la normalmente, pois a exclusão atual é por tarefa até `R-03B`)*.
- **Sinais de reprovação:** Selo `×` cancelar pedra junto; click-through para o mapa ao clicar em `×`; ordem comunitária sequestrar ordem pessoal ativa; trabalhador coletar árvore derrubada cancelada sem reautorização; perda de carga já extraída.
- **Criticidade:** Crítica (`D1` / `D2` / `D3`).
- **Evidência recomendada:** Registro `PASS`/`FAIL` e anotação sobre `HD3-06`.
- **Observações:** `______________________________________________________________`
- **Resultado:** `[ ] PASS` · `[ ] FAIL` · `[ ] NÃO TESTADO`

---

### `M7` — Coexistência com construção legada (`P-REC-1`) e interfaces
- **Objetivo:** Confirmar convivência entre HUD contextual, `TemporaryPlacementBar` (`[Construir]`), posicionamento de canteiro e controles RTS sem click-through.
- **Pré-condição:** Estoque com recursos entregues no passo `M5` (ou suficientes para um canteiro) e ao menos uma fonte selecionada (HUD contextual visível).
- **Passos:**
  1. Clicar no botão `[Construir]` (canto inferior direito) e entrar no modo de posicionamento de `Abrigo Básico`.
  2. Posicionar o canteiro em área válida fora do acampamento/fontes (confirmar clique esquerdo).
  3. Alternar entre clique nos botões da HUD contextual e da interface de construção sem mover unidades acidentalmente atrás dos painéis.
  4. Selecionar um trabalhador e enviá-lo ao canteiro para construir enquanto outra tarefa comunitária de coleta está autorizada.
- **Resultado esperado:** Sem click-through ao clicar nos painéis/botões/selo `×`; canteiro legado criado normalmente com reserva em pilhas e entrega/construção funcionais em coexistência com coleta comunitária. *(Nota conhecida `D4 V13`: se um aviso transitório de conclusão de coleta aparecer no topo-central exatamente ao entrar no modo de posicionamento, os dois banners temporários de topo podem se sobrepor brevemente até o toast expirar.)*
- **Sinais de reprovação:** Cliques na HUD atravessarem para o chão; sobreposição de painéis persistentes em `720p`; incapacidade de cancelar posicionamento ou falha no fluxo de construção legada.
- **Criticidade:** Alta (`P-REC-1` / `D1`).
- **Evidência recomendada:** Registro `PASS`/`FAIL`.
- **Observações:** `______________________________________________________________`
- **Resultado:** `[ ] PASS` · `[ ] FAIL` · `[ ] NÃO TESTADO`

---

### `M8` — Conservação, recursos mistos e encerramento limpo
- **Objetivo:** Observar madeira, pedra e alimentos em entregas múltiplas, saldo coerente no acampamento, limpeza completa de marcadores ao final e ausência de erros visuais.
- **Pré-condição:** Fontes de madeira, pedra e alimento disponíveis no mapa.
- **Passos:**
  1. Selecionar e autorizar pelo menos `1` fonte de cada categoria (`Madeira`, `Pedra`, `Alimentos`) e acompanhar múltiplas entregas até o término ou esgotamento de uma fonte.
  2. Pressionar `Esc` para limpar a seleção visual e verificar todas as fontes concluídas/canceladas.
  3. Fechar o jogo e inspecionar o console do PowerShell de origem.
- **Resultado esperado:** Contadores do painel `Acampamento` refletem fielmente as pilhas físicas visíveis no chão; marcadores de trabalho (`Machado`/`Picareta`/`Colheita`) e anéis somem completamente após conclusão/esgotamento/`Esc`; console encerra limpo sem erros GDScript ou avisos.
- **Sinais de reprovação:** Ícones ou anéis órfãos em fontes esgotadas/concluídas; divergência entre pilhas físicas no chão e totais do HUD; erro ou aviso no console ao fechar.
- **Criticidade:** Alta (`D0-A04` / `D4`).
- **Evidência recomendada:** Registro `PASS`/`FAIL` + saída limpa do console.
- **Observações:** `______________________________________________________________`
- **Resultado:** `[ ] PASS` · `[ ] FAIL` · `[ ] NÃO TESTADO`
