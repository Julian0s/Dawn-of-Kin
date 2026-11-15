# Protocolo de Testes Manuais — T3.2 (Validação Espacial, Área Reservada e Prévia sem Grid)

**Escopo:** Validação visual e interativa da etapa **T3.2** em `src/main/main.tscn` (`TestMap`), contemplando prévia 3D contínua sem grid, proteção dinâmica da `CampStorageZone` (D6), feedback de hover/rejeição/confirmação simulada, cancelamento e compatibilidade total com câmera e controles RTS.<br>
**Limites intencionais da T3.2 (não esperar nesta etapa):**
- A confirmação com botão esquerdo (`LMB`) executa a validação completa (incluindo NavMesh candidata isolada) e exibe apenas um pulso visual temporário + mensagem provisória de confirmação. **Não** instancia `ConstructionSite` nem edifícios reais, **não** altera estoque/reservas e **não** modifica a `WorldNavigation` ativa (essas entregas pertencem à T3.3+).
- A barra inferior direita `Prévia T3.2 (teste temporário)` e o banner superior são controles provisórios exclusivos para validar a T3.2 antes do catálogo e inspetor definitivos da T3.5.

---

## 1. Pré-requisitos e Comandos

Executar na raiz do worktree/repositório:

1. Janela `1280x720`:
   ```powershell
   .\tools\run_game.ps1 -Resolution "1280x720" -FailOnWarnings
   ```
2. Janela `1920x1080`:
   ```powershell
   .\tools\run_game.ps1 -Resolution "1920x1080" -FailOnWarnings
   ```

---

## 2. Checklist de Verificação Manual

### A. Ativação da Prévia, Proporções e Visual sem Grid
- **A1 — Ativação por botão e atalho (`F6` / `F7`):**
  - Ação: Clicar em `Abrigo 4×4 [F6]` (ou pressionar `F6`) e depois em `Depósito 5×4 [F7]` (ou pressionar `F7`).
  - Evidência esperada: O modo de posicionamento ativa sem travar o jogo; a prévia 3D alterna visivelmente de escala (`4×4 m` para `Abrigo Básico` com cobertura inclinada vs. `5×4 m` para `Depósito Rústico` retangular); o botão `Cancelar` fica visível e nenhum botão retém foco de teclado (`Tab`/`Espaço`).
  - Resultado: `[x] aprovado  [ ] reprovado  [ ] não testado`
  - Campo de observações opcionais: `Nenhuma.`

- **A2 — Movimento contínuo sem grid e estética discreta:**
  - Ação: Mover o mouse lentamente sobre o chão aberto (`(-6, 0, 1.5)` ou planície norte além do muro `z = -6`).
  - Evidência esperada: A silhueta translúcida acompanha o cursor de forma contínua e fluida (sem "saltos" em grade fixa), sem sombras projetadas duplicadas no chão, sem grade visual/neon excessivo, acompanhando o pan/zoom da câmera mesmo com o mouse parado.
  - Resultado: `[x] aprovado  [ ] reprovado  [ ] não testado`
  - Campo de observações opcionais: `Nenhuma.`

### B. Regras Espaciais, D6 e Terreno
- **B1 — Área reservada dinâmica do acampamento (D6):**
  - Ação: Passar a prévia gradualmente sobre o centro e as bordas da zona marcada `"Acampamento"` (`CampStorageZone`).
  - Evidência esperada: Mesmo tocando apenas uma quina ou faixa parcial da área reservada, a prévia muda imediatamente para vermelho discreto e o banner exibe motivo legível (`"Posição inválida: área reservada para pilhas do acampamento."`). Ao afastar logo após a borda externa em chão livre, retorna para verde.
  - Resultado: `[x] aprovado  [ ] reprovado  [ ] não testado`
  - Campo de observações opcionais: `Nenhuma.`

- **B2 — Obstáculos, fontes naturais e personagens:**
  - Ação: Passar a prévia sobre o muro `WallWithGap`, pedras, árvores naturais (`WoodTree01/02`), rochas (`StoneRock01/02`), arbustos (`FoodBush01/02`) e sobre os personagens `LeaderA` / `LeaderB`.
  - Evidência esperada: Em todos esses casos a prévia fica vermelha com texto de motivo correspondente (obstáculo, recurso natural ou trabalhador na área).
  - Resultado: `[x] aprovado  [ ] reprovado  [ ] não testado`
  - Campo de observações opcionais: `Nenhuma.`

- **B3 — Rampa inclinada, borda de platô e corredor estreito:**
  - Ação: Passar a prévia sobre a rampa à direita (`(9, 0.8, -14)`), na quina do platô (desnível entre `y = 2` e `y = 0`) e dentro do recinto fechado (`(-16, 0, 12)`).
  - Evidência esperada: Todos ficam inválidos em vermelho (terreno irregular/desnível ou perímetro inacessível); tentar posicionar dentro do vão `WallWithGap` caso estreite demais o acesso/corredor falha com motivo legível ao confirmar.
  - Resultado: `[x] aprovado  [ ] reprovado  [ ] não testado`
  - Campo de observações opcionais: `Nenhuma.`

### C. Confirmação Simulada e Cancelamento
- **C1 — Clique esquerdo em posição inválida:**
  - Ação: Com a prévia vermelha (por ex., sobre `CampStorageZone` ou `WoodTree01`), clicar com o botão esquerdo (`LMB`).
  - Evidência esperada: O modo de construção **permanece ativo**, a prévia continua seguindo o cursor e o banner reforça o motivo da rejeição.
  - Resultado: `[x] aprovado  [ ] reprovado  [ ] não testado`
  - Campo de observações opcionais: `Nenhuma.`

- **C2 — Clique esquerdo em posição válida:**
  - Ação: Posicionar a prévia verde em terreno livre e clicar com o botão esquerdo (`LMB`).
  - Evidência esperada: Executa a validação candidata com sucesso, exibe breve pulso de confirmação e banner verde temporário (`"Posição validada..."`), encerra o modo de posicionamento e devolve o controle normal sem criar canteiro/obstáculo/pilha nem alterar o HUD de estoque.
  - Resultado: `[x] aprovado  [ ] reprovado  [ ] não testado`
  - Campo de observações opcionais: `Nenhuma.`

- **C3 — Cancelamento por `RMB` e `Esc` sem efeito colateral RTS:**
  - Ação: Selecionar `LeaderA`; ativar a prévia (`F6`) e clicar com botão direito (`RMB`) no chão. Repetir ativando (`F7`) e pressionando `Esc`.
  - Evidência esperada: A prévia fecha imediatamente nos dois casos; `LeaderA` **permanece selecionado**, **não** recebe ordem de movimento nem de coleta no clique direito de cancelamento, e o estoque/pilhas continuam intactos.
  - Resultado: `[x] aprovado  [ ] reprovado  [ ] não testado`
  - Campo de observações opcionais: `Nenhuma.`

### D. Integração com Câmera, Controles RTS e Layout
- **D1 — Câmera isométrica durante prévia ativa:**
  - Ação: Com a prévia ativa, testar `WASD`, setas direcionais, arraste com botão do meio do mouse (`MMB`), zoom por rolagem (`Scroll`) e `Edge Scrolling` encostando o cursor na borda real da janela.
  - Evidência esperada: Todos os movimentos de câmera permanecem responsivos e fluidos enquanto a prévia continua atualizando corretamente no terreno.
  - Resultado: `[x] aprovado  [ ] reprovado  [ ] não testado`
  - Campo de observações opcionais: `Nenhuma.`

- **D2 — Controles RTS e navegação antes e depois:**
  - Ação: Após cancelar ou confirmar uma prévia, testar clique esquerdo em unidade, seleção em caixa (arraste `LMB`), clique direito de movimento e clique direito para coletar árvore/pedra/arbusto.
  - Evidência esperada: Seleção, caixa de seleção, ordens de movimento, coleta e rotas pelo vão do muro continuam idênticos à T2.
  - Resultado: `[x] aprovado  [ ] reprovado  [ ] não testado`
  - Campo de observações opcionais: `Nenhuma.`

- **D3 — Layout do HUD e console limpos em `1280x720` e `1920x1080`:**
  - Ação: Com `LeaderA` selecionado (painel inferior esquerdo visível) e prévia ativa (banner superior + barra inferior direita temporária visíveis), verificar em `1280x720` e `1920x1080`.
  - Evidência esperada: Nenhuma sobreposição entre painéis de canto, texto legível, cliques fora dos botões passam direto para o mundo, e 0 `ERROR`/`WARNING` no terminal ao sair.
  - Resultado: `[x] aprovado  [ ] reprovado  [ ] não testado`
  - Campo de observações opcionais: `Nenhuma.`

---

## 3. Resumo Final do Avaliador
- **Resoluções testadas:** `1280×720 e 1920×1080`
- **Veredito geral:** `[x] Aprovado  [ ] Aprovado com ressalvas  [ ] Reprovado  [ ] Aguardando execução manual`
- **Observações gerais opcionais:** `Aprovado pelo proprietário em 15/11/2026 em ambas as resoluções, sem reprovações nem ressalvas (11/11 itens A1–D3 aprovados manualmente).`
