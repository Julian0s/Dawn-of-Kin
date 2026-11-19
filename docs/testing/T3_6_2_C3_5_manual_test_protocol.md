# Protocolo Complementar de Testes Manuais — T3.6.2-C3.5
## Integração opt-in da coleta com proveniência ao ciclo real dos trabalhadores

**Status de execução manual C3.5:** **PENDENTE DE VALIDAÇÃO PELO PROPRIETÁRIO** *(nenhum item manual abaixo foi executado em janela interativa pelo agente; todos os testes executados pelo agente nesta candidata foram automatizados em Godot 4.7.2 headless).*

**Status preservado da C3.4.3:** Os **6 itens manuais (M1–M6)** do protocolo [T3_6_2_C3_4_3_manual_test_protocol.md](T3_6_2_C3_4_3_manual_test_protocol.md) permanecem integralmente **PENDENTES / NÃO TESTADOS** e **não** devem ser marcados como aprovados sem execução visual real.

**Escopo:** Protocolo complementar para inspeção visual e interativa da etapa **T3.6.2-C3.5** em `src/main/main.tscn` (`TestMap`), preservando integralmente o fluxo legado por padrão e sem qualquer adição de controles permanentes ao HUD do jogo.

**Separação entre fluxo normal e harness removível:**
- O jogo normal (`.\tools\run_game.ps1`) mantém **modo legado** por padrão (`use_provenance_transactions = false`, `use_selective_provenance = false`) e não altera `CommandController` nem o HUD permanente.
- Para testar o fluxo **opt-in** da C3.5 interativamente, utilize o harness de desenvolvimento isolado e removível [t3_6_2_c3_4_3_manual_harness.gd](../../tests/visual/t3_6_2_c3_4_3_manual_harness.gd), ampliado com os atalhos `Ctrl+8` e `Ctrl+9`.

---

## 1. Como iniciar o cenário

Executar na raiz do worktree `C:\Projetos\Dawn_of_Kin_wt_t3_4_5`:

### 1.1 Verificação rápida de não-regressão no fluxo legado normal
```powershell
.\tools\run_game.ps1 -Resolution "1280x720" -FailOnWarnings
```

### 1.2 Cenário opt-in C3.5 com harness removível e telemetria no console
```powershell
& "C:\Users\alexa\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe" --path "C:\Projetos\Dawn_of_Kin_wt_t3_4_5" --resolution 1280x720 --script "res://tests/visual/t3_6_2_c3_4_3_manual_harness.gd"
```

### Atalhos disponíveis no harness removível (atuam sobre a unidade selecionada com `LMB`)
- `Ctrl+1` — Habilita proveniência opt-in na unidade selecionada (exige mochila vazia).
- `Ctrl+2` — Adiciona carga de teste `FREE_GATHERED` (`4 madeiras`).
- `Ctrl+3` — Cria Obras A e B (se ainda não existirem) e carrega carga mista (`2 madeiras SITE_RESERVED` da Obra B + `3 alimentos FREE_GATHERED`).
- `Ctrl+4` — Emite `DeliverToCampOrder` seletivo conservador (`requested_lots = []`, apenas lotes livres).
- `Ctrl+5` — Emite `DeliverToCampOrder` seletivo explícito para o lote `SITE_RESERVED` da Obra B.
- `Ctrl+6` — Emite `ConstructOrder` opt-in para a Obra A.
- `Ctrl+7` — Imprime no console estoque do acampamento, peso/capacidade da unidade, lotes concretos restantes e estado/totais da `GatherResourceOrder`.
- `Ctrl+8` — **[C3.5]** Emite `GatherResourceOrder` opt-in (`use_provenance_transactions = true`) na árvore de madeira disponível mais próxima.
- `Ctrl+9` — **[C3.5]** Emite `GatherResourceOrder` opt-in (`use_provenance_transactions = true`) no arbusto de alimento disponível mais próximo.

---

## 2. Roteiro Complementar de Verificação Manual (C3.5)

### M7 — Coleta física com proveniência, surgimento de lotes, redução da fonte, caminhada carregada e pilha no acampamento
- **Como executar:**
  1. Iniciar o harness removível (Seção 1.2).
  2. Selecionar `LeaderA` com `LMB` e pressionar `Ctrl+1` para habilitar proveniência (`prov=true`).
  3. Pressionar `Ctrl+7` para anotar `wood_fisico`/`wood_livre` iniciais.
  4. Pressionar `Ctrl+8` para iniciar `GatherResourceOrder` opt-in na árvore mais próxima.
  5. Pressionar `Ctrl+7` uma vez durante a fase `WORKING` (logo após os primeiros golpes / queda da árvore) e mais uma vez durante a fase `TRANSPORTING` (enquanto a unidade caminha rumo ao acampamento).
  6. Aguardar a unidade chegar fisicamente à `CampStorageZone` e pressionar `Ctrl+7`.
- **Evidência esperada:**
  - `LeaderA` caminha fisicamente até a árvore, reserva o slot, executa a preparação/trabalho e anima a queda da árvore normalmente na primeira extração.
  - Em `Ctrl+7` durante o trabalho/transporte: surgem lotes `FREE_GATHERED` (`lot:gather:...`) na mochila com peso exato (`2` por madeira) e `src_rest` da árvore diminui na mesma quantidade exata.
  - Durante a caminhada de retorno (`TRANSPORTING`), a unidade desacelera conforme o peso e o estoque do acampamento **não** aumenta antes da chegada física.
  - Ao chegar ao acampamento: a pilha de madeira do acampamento aumenta visualmente e no HUD, os lotes `FREE_GATHERED` saem da mochila e a unidade retorna à árvore se ainda restar madeira.
- **Resultado:** `[ ] aprovado  [ ] reprovado  [x] não testado`
- **Observações:** `Pendente de execução pelo proprietário.`

### M8 — Cancelamento durante a coleta (antes e após a primeira extração)
- **Como executar:**
  1. **Subcaso A (antes de extrair):** Selecionar `LeaderA` (`prov=true`), movê-la para longe das árvores com `RMB`, pressionar `Ctrl+8` e, ainda durante a caminhada ou fase inicial antes do primeiro corte, clicar com `RMB` no chão livre ou selecionar outro ponto para cancelar. Pressionar `Ctrl+7`.
  2. **Subcaso B (após ao menos 1 extração):** Pressionar `Ctrl+8`, aguardar a unidade realizar pelo menos uma extração (conferir surgimento do lote com `Ctrl+7`), e antes de encher a mochila ou durante a preparação do próximo ciclo clicar com `RMB` no chão para interromper. Pressionar `Ctrl+7`.
- **Evidência esperada:**
  - Subcaso A: `0` lotes criados, fonte com estoque original intacto, `src_slots = 0` (slot liberado), `0` crédito no acampamento.
  - Subcaso B: a ordem encerra como `CANCELLED` (`failure=replaced`), o lote `FREE_GATHERED` já extraído permanece intacto na mochila, `src_slots = 0`, `0` crédito antecipado no acampamento e nenhuma extração atrasada ocorre depois da interrupção.
- **Resultado:** `[ ] aprovado  [ ] reprovado  [x] não testado`
- **Observações:** `Pendente de execução pelo proprietário.`

### M9 — Cancelamento durante o transporte de retorno ao acampamento
- **Como executar:**
  1. Com `LeaderA` (`prov=true`), iniciar coleta com `Ctrl+8` e aguardar entrar em `TRANSPORTING` (caminhando carregada rumo ao acampamento).
  2. No meio do trajeto até o acampamento, clicar com `RMB` no terreno livre para substituir por movimento manual.
  3. Após a unidade chegar ao ponto clicado, pressionar `Ctrl+7`.
  4. Em seguida, pressionar `Ctrl+4` para concluir manualmente o retorno seletivo ao acampamento e conferir `Ctrl+7`.
- **Evidência esperada:**
  - Ao cancelar com `RMB`: a entrega é abortada sem erro, o acampamento **não** recebe os recursos, o slot da fonte continua livre (`0`) e todos os lotes `FREE_GATHERED` permanecem intactos na mochila.
  - Após `Ctrl+4`: os lotes preservados chegam fisicamente ao acampamento e entram no estoque sem perda nem duplicação.
- **Resultado:** `[ ] aprovado  [ ] reprovado  [x] não testado`
- **Observações:** `Pendente de execução pelo proprietário.`

### M10 — Coleta e descarga seletiva com carga mista (`SITE_RESERVED` + `FREE_GATHERED`) e comportamento anti-loop
- **Como executar:**
  1. Esvaziar cargas livres anteriores (`Ctrl+4`), afastar `LeaderA` (`prov=true`) do acampamento e pressionar `Ctrl+3` para preparar carga mista (`2 madeiras SITE_RESERVED` da Obra B + `3 alimentos FREE_GATHERED`).
  2. Pressionar `Ctrl+7` e anotar `Obra B res`, `wood_livre`, `food_livre` e o lote `SITE_RESERVED` na mochila.
  3. Pressionar `Ctrl+9` para coletar alimento adicional no arbusto mais próximo com proveniência habilitada.
  4. Observar a coleta até encher a capacidade restante ou esgotar o espaço, seguida da caminhada de volta ao acampamento e descarga automática; ao final, pressionar `Ctrl+7`.
- **Evidência esperada:**
  - `LeaderA` coleta apenas o que cabe na capacidade residual sem ultrapassar `20/20`, caminha até o acampamento e descarrega **somente** os lotes `FREE_GATHERED` (alimentos iniciais + coletados), creditando exclusivamente `food_livre`.
  - Os `2 madeiras SITE_RESERVED` da Obra B permanecem intactos na mochila (mesmo `lot_id`, `origin=SITE_RESERVED`, `site_id` da Obra B), sem conversão em madeira livre e sem alterar a reserva/claim da Obra B.
  - Se em outra rodada a carga `SITE_RESERVED` ocupar quase toda a mochila deixando capacidade inferior ao peso do recurso alvo, a unidade não entra em loop de ida e volta ao acampamento.
- **Resultado:** `[ ] aprovado  [ ] reprovado  [x] não testado`
- **Observações:** `Pendente de execução pelo proprietário.`

---

## 3. Critérios de Reprovação Visual/Manual

Considere qualquer item **REPROVADO** se observar:
1. Estoque do acampamento aumentando antes da chegada física da unidade carregada.
2. Árvore, arbusto ou pedra sem decremento correspondente aos lotes criados ou contagem duplicada após animação de queda.
3. Lote `SITE_RESERVED` sendo descarregado em pilha livre ou convertido em `FREE_GATHERED`.
4. Unidade repetindo viagens ao acampamento sem carga livre elegível (loop com carga residual reservada).
5. Slot de trabalhador preso na fonte após cancelamento ou conclusão.
6. Qualquer `ERROR`, `SCRIPT ERROR` ou `WARNING` no console do Godot.

---

## 4. Resumo do Avaliador

- **C3.4.3 — Itens manuais pendentes (M1–M6):** `0/6` executados manualmente (`PENDENTES` em [T3_6_2_C3_4_3_manual_test_protocol.md](T3_6_2_C3_4_3_manual_test_protocol.md)).
- **C3.5 — Itens manuais complementares (M7–M10):** `0/4` executados manualmente (`PENDENTES` neste protocolo).
- **Veredito manual:** `[ ] Aprovado  [ ] Aprovado com ressalvas  [ ] Reprovado  [x] Aguardando execução manual`
- **Observações do proprietário:** `Pendente.`
