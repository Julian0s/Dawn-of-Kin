# Protocolo de Testes Manuais — T3.6.2-C3.4.3
## Integração opt-in da descarga seletiva às ordens de trabalhadores

**Status de execução manual:** **PENDENTE DE VALIDAÇÃO PELO PROPRIETÁRIO** *(nenhum item manual abaixo foi executado em janela interativa pelo agente; todos os testes executados pelo agente foram automatizados em Godot 4.7.2 headless).*

**Escopo:** Validação visual, interativa e econômica da etapa **T3.6.2-C3.4.3** em `src/main/main.tscn` (`TestMap`), preservando integralmente o fluxo legado por padrão e sem adicionar nenhum controle permanente ao HUD do jogo.

**Separação entre fluxo normal e harness removível:**
- O jogo normal (`.\tools\run_game.ps1`) mantém **modo legado** por padrão (`use_selective_provenance = false`, `use_provenance_transactions = false`) e não possui novos botões permanentes de HUD.
- Para validar o modo **opt-in** sem modificar `src/main/main.tscn` nem a interface permanente, utilize o harness de desenvolvimento isolado e removível [t3_6_2_c3_4_3_manual_harness.gd](../../tests/visual/t3_6_2_c3_4_3_manual_harness.gd).

---

## 1. Como iniciar o cenário

Executar na raiz do worktree `C:\Projetos\Dawn_of_Kin_wt_t3_4_5`:

### 1.1 Cenário legado padrão (verificação de não-regressão)
```powershell
.\tools\run_game.ps1 -Resolution "1280x720" -FailOnWarnings
```

### 1.2 Cenário opt-in com harness removível (com console visível para inspeção de lotes)
```powershell
& "C:\Users\alexa\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe" --path "C:\Projetos\Dawn_of_Kin_wt_t3_4_5" --resolution 1280x720 --script "res://tests/visual/t3_6_2_c3_4_3_manual_harness.gd"
```

Ao carregar o `TestMap`, aguarde a mensagem no console confirmando que o harness está pronto e que o acampamento recebeu `12 madeiras` e `8 pedras` iniciais.

### Atalhos exclusivos do harness removível (atuam sobre a unidade selecionada)
- `Ctrl+1` — Habilita proveniência opt-in na unidade selecionada (exige mochila vazia).
- `Ctrl+2` — Adiciona carga de teste `FREE_GATHERED` (`4 madeiras`).
- `Ctrl+3` — Cria Obras A e B (se ainda não existirem) e carrega carga mista (`2 madeiras SITE_RESERVED` da Obra B + `3 alimentos FREE_GATHERED`).
- `Ctrl+4` — Emite `DeliverToCampOrder` seletivo conservador (`requested_lots = []`, apenas lotes livres).
- `Ctrl+5` — Emite `DeliverToCampOrder` seletivo explícito para o lote `SITE_RESERVED` da Obra B.
- `Ctrl+6` — Emite `ConstructOrder` opt-in para a Obra A (`force_transporter = true`, `use_provenance_transactions = true`).
- `Ctrl+7` — Imprime no console o diagnóstico completo de estoque físico/livre/reservado, peso, lotes concretos restantes e status da última ordem.

---

## 2. Roteiro passo a passo e Checklist de Verificação Manual

### M1 — Compatibilidade legada por padrão (sem opt-in)
- **Como executar:**
  1. Abrir o jogo normal via `.\tools\run_game.ps1 -Resolution "1280x720" -FailOnWarnings`.
  2. Selecionar `LeaderA` com clique esquerdo (`LMB`), ordenar coleta (`RMB` em uma árvore `WoodTree` ou arbusto `FoodBush`) e observar o retorno automático ao acampamento.
  3. Criar um canteiro (`Abrigo Básico`) e enviar `LeaderA` com `RMB` sobre o canteiro.
- **Evidência esperada:**
  - Coleta, transporte, descarga no acampamento e construção funcionam normalmente sem qualquer mudança de comportamento, sem habilitar proveniência automaticamente e com `0` erros/avisos no console.
- **Resultado:** `[ ] aprovado  [ ] reprovado  [x] não testado`
- **Observações:** `Pendente de execução pelo proprietário.`

### M2 — Seleção de unidade e habilitação controlada do modo opt-in
- **Como executar:**
  1. Iniciar o harness removível (Seção 1.2).
  2. Clicar com `LMB` sobre `LeaderA` para selecioná-la.
  3. (Opcional — teste negativo) Mover `LeaderA` para coletar 1 unidade em modo legado, depois pressionar `Ctrl+1`.
  4. Com a mochila vazia, selecionar `LeaderA` e pressionar `Ctrl+1`, em seguida `Ctrl+7`.
- **Evidência esperada:**
  - Com mochila não vazia legada, `enable_provenance` retorna `false` sem converter nem perder a carga legada.
  - Com mochila vazia, `Ctrl+1` habilita proveniência (`prov=true`) e `Ctrl+7` exibe `Lotes restantes={}`.
- **Resultado:** `[ ] aprovado  [ ] reprovado  [x] não testado`
- **Observações:** `Pendente de execução pelo proprietário.`

### M3 — Carga livre, caminhada física real, chegada ao acampamento e conferência de estoque
- **Como executar:**
  1. Com `LeaderA` selecionada (`prov=true`), movê-la com `RMB` para um ponto distante do acampamento (ex.: próximo às árvores a oeste/sul).
  2. Pressionar `Ctrl+2` para adicionar `4 madeiras FREE_GATHERED` e pressionar `Ctrl+7` para anotar o estoque inicial do acampamento (`wood_fisico`, `wood_livre`) e o peso na mochila (`8/20`).
  3. Pressionar `Ctrl+4` para ordenar o retorno seletivo conservador ao acampamento.
  4. Durante o trajeto (enquanto `LeaderA` ainda caminha), pressionar `Ctrl+7` uma vez e observar o HUD do acampamento.
  5. Aguardar `LeaderA` chegar fisicamente à zona de armazenamento do acampamento e pressionar `Ctrl+7`.
- **Evidência esperada:**
  - `LeaderA` caminha fisicamente no terreno em estado `TRANSPORTING` (desacelerada proporcionalmente pelo peso).
  - **Durante o caminho:** o estoque do acampamento **não** aumenta (nenhum crédito antecipado).
  - **Ao chegar ao acampamento:** a pilha física no acampamento cresce/surge visualmente, o estoque livre de madeira sobe exatamente `+4`, a mochila zera (`peso=0/20`, `Lotes restantes={}`) e a ordem encerra com `status=2` (`SUCCEEDED`) e `failure=`.
- **Resultado:** `[ ] aprovado  [ ] reprovado  [x] não testado`
- **Observações:** `Pendente de execução pelo proprietário.`

### M4 — Interrupção manual durante a caminhada (preservação de carga e origem)
- **Como executar:**
  1. Com `LeaderA` longe do acampamento (`prov=true`), pressionar `Ctrl+2` (`4 madeiras FREE_GATHERED`) e depois `Ctrl+4` para iniciar o retorno.
  2. Enquanto `LeaderA` está no meio do caminho (antes de chegar ao acampamento), clicar com `RMB` em um ponto de chão livre longe do acampamento para emitir um `MoveOrder` manual.
  3. Aguardar `LeaderA` chegar ao ponto clicado e pressionar `Ctrl+7`.
- **Evidência esperada:**
  - O retorno ao acampamento é interrompido imediatamente (`status=4` / `CANCELLED`, motivo `replaced`); `LeaderA` caminha para o novo destino clicado.
  - Nenhum recurso é creditado ao acampamento; os `4 madeiras` e seu `lot_id` original `FREE_GATHERED` permanecem intactos na mochila.
- **Resultado:** `[ ] aprovado  [ ] reprovado  [x] não testado`
- **Observações:** `Pendente de execução pelo proprietário.`

### M5 — Carga mista (`FREE_GATHERED` + `SITE_RESERVED`), conferência de lotes restantes e restauração explícita da Obra B
- **Como executar:**
  1. Esvaziar eventual carga livre (`Ctrl+4`) e mover `LeaderA` para longe do acampamento.
  2. Pressionar `Ctrl+3` para preparar carga mista (`2 madeiras SITE_RESERVED` da Obra B ativa + `3 alimentos FREE_GATHERED`). Pressionar `Ctrl+7` e anotar `wood_livre`, `food_livre` e `Obra B res`.
  3. Pressionar `Ctrl+4` (retorno seletivo conservador). Aguardar chegada ao acampamento e pressionar `Ctrl+7`.
  4. Afastar `LeaderA` do acampamento com `RMB` e pressionar `Ctrl+5` (retorno seletivo explícito do lote reservado da Obra B). Aguardar chegada e pressionar `Ctrl+7`.
- **Evidência esperada:**
  - Após `Ctrl+4`: **somente** os `3 alimentos FREE_GATHERED` entram no estoque livre do acampamento (`food_livre +3`). A ordem termina com sucesso parcial (`status=2`) **sem** exigir mochila vazia; os `2 madeiras SITE_RESERVED` permanecem na mochila com seu `lot_id` e origem originais, `wood_livre` não muda e `Obra B res` não é alterada nem convertida em livre.
  - Após `Ctrl+5`: `LeaderA` caminha ao acampamento e devolve os `2 madeiras` diretamente para a reserva física da Obra B (`Obra B res` aumenta `+2`, `wood_livre` permanece inalterado, mochila fica vazia).
- **Resultado:** `[ ] aprovado  [ ] reprovado  [x] não testado`
- **Observações:** `Pendente de execução pelo proprietário.`

### M6 — Integração `ConstructOrder` opt-in (retorno automático do livre, continuidade da Obra A e proteção contra loop com carga da Obra B)
- **Como executar:**
  1. Com `LeaderA` longe do acampamento (`prov=true`), pressionar `Ctrl+3` (carga mista: `2 madeiras SITE_RESERVED` da Obra B + `3 alimentos FREE_GATHERED`).
  2. Pressionar `Ctrl+6` para emitir `ConstructOrder` opt-in para a Obra A (que precisa de `3 pedras`).
  3. Observar todo o trajeto visualmente até `LeaderA` ficar `IDLE`, e pressionar `Ctrl+7`.
- **Evidência esperada:**
  - `LeaderA` caminha primeiro até o acampamento e descarrega **somente** os `3 alimentos FREE_GATHERED` (preservando os `2 madeiras` da Obra B).
  - **Sem entrar em loop:** após descarregar os alimentos, `LeaderA` não repete retorno ao acampamento mesmo com a mochila não vazia; em vez disso, coleta as `3 pedras` reservadas da Obra A, leva até a Obra A, entrega somente as `3 pedras` da Obra A e encerra com sucesso.
  - Ao final (`Ctrl+7`): Obra A tem `buf={&"stone": 3}` (nunca recebeu madeira da Obra B); `LeaderA` continua carregando intactos os `2 madeiras` da Obra B com `lot_id` preservado.
- **Resultado:** `[ ] aprovado  [ ] reprovado  [x] não testado`
- **Observações:** `Pendente de execução pelo proprietário.`

---

## 3. Como identificar uma falha durante o teste manual

Considere o item **REPROVADO** caso ocorra qualquer um dos sinais abaixo:
1. Estoque do acampamento ou da obra mudar **antes** de a unidade chegar fisicamente ao destino (teletransporte / crédito antecipado).
2. Lote `SITE_RESERVED` de uma obra ser convertido em estoque livre ou entregue a outra obra.
3. Ordem seletiva parcial falhar apenas porque ainda restam lotes não selecionados na mochila, ou entrar em repetição infinita indo e voltando ao acampamento.
4. Interrupção manual (`RMB`) apagar recursos da mochila, alterar `lot_id`/origem ou disparar descarga atrasada depois de cancelada.
5. Qualquer mensagem `ERROR`, `SCRIPT ERROR` ou `WARNING` no console do Godot, travamento de movimento ou divergência de conservação (`estoque_fisico + mochilas + buffers_obras != total_inicial`).

---

## 4. Resumo do Avaliador

- **Testes automatizados headless executados pelo agente:** Sim (ver `docs/testing/T3_6_2_C3_4_3_candidate_report.md`).
- **Testes manuais em cena jogável executados pelo agente:** Não (0/6 — pendente de execução interativa pelo proprietário).
- **Veredito manual:** `[ ] Aprovado  [ ] Aprovado com ressalvas  [ ] Reprovado  [x] Aguardando execução manual`
- **Observações do proprietário:** `Pendente.`
