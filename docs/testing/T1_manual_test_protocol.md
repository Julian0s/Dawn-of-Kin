# Dawn of Kin — Protocolo de Teste Manual da T1

Execute este roteiro interativo em janela real para validar ergonomia, resposta do mouse, leitura visual e comportamento em tempo real antes de aprovar formalmente o marco **T1**.

## Como iniciar

No PowerShell, na raiz `C:\Projetos\Dawn of Kin`:

```powershell
.\tools\run_game.ps1 -Resolution "1920x1080"
```

Pressione **F3** a qualquer momento para alternar o overlay de debug (FPS, frame time, física, draw calls).

---

## Checklist de Verificação Manual

Marque `[ ]` como `[x]` após testar e registre observações na coluna de notas.

### 1. Câmera RTS e Edge Scrolling (AC-04)
- [ ] **Pan por teclado (`WASD` / `Setas`):** movimento suave no plano isométrico em todas as direções, respeitando os limites do mapa (a câmera não sai do mapa).
- [ ] **Pan por arraste (botão do meio):** segurar e arrastar desloca a câmera de forma fluida sem saltos bruscos.
- [ ] **Zoom (roda do mouse):** aproxima e afasta suavemente entre os limites mínimo e máximo.
- [ ] **Edge Scrolling (~6 px da borda):** aproximar o cursor a ~6 pixels físicos das bordas da janela inicia o deslocamento; manter o cursor dentro da área útil (inclusive perto de seleções) **não** dispara movimento involuntário.
- [ ] **Sensação geral:** câmera responde de forma consistente e previsível em diferentes níveis de zoom.
- **Observações / Defeitos:** `________________________________________________`

### 2. Personagens e Feedback Visual (AC-05, AC-07)
- [ ] **Distinção visual:** `LeaderA` e `LeaderB` são claramente distinguíveis por **cor e silhueta/forma** tanto no zoom mínimo quanto no zoom máximo.
- [ ] **Hover:** passar o mouse sobre um personagem destaca o indicador de hover sem alterar a seleção atual.
- [ ] **Anel de seleção:** visível sob o(s) personagem(ns) selecionado(s) em todos os níveis de zoom.
- **Observações / Defeitos:** `________________________________________________`

### 3. Seleção Individual e por Caixa (AC-06, AC-07)
- [ ] **Seleção individual:** clique esquerdo em `LeaderA` seleciona apenas `LeaderA`; clique esquerdo em `LeaderB` transfere a seleção para `LeaderB`.
- [ ] **Shift+clique:** alterna inclusão/remoção na seleção sem duplicar unidades.
- [ ] **Seleção por caixa:** arrastar o botão esquerdo desenha o retângulo da caixa em qualquer uma das 4 direções e seleciona as unidades dentro da área ao soltar.
- [ ] **Shift+arraste:** adiciona unidades da caixa à seleção existente sem removê-las.
- [ ] **Limpeza de seleção:** clique esquerdo no chão vazio (sem Shift) limpa a seleção; `Shift+clique` no chão preserva a seleção; tecla `Esc` limpa a seleção (ou cancela caixa em andamento).
- [ ] **Clique vs arraste:** pequenos movimentos acidentais dentro do limiar não disparam caixa; arrastes reais não disparam clique simples.
- **Observações / Defeitos:** `________________________________________________`

### 4. Comandos de Movimento e Marcador de Destino (AC-08, AC-11)
- [ ] **Movimento individual:** selecionar `LeaderA` e clicar com o botão direito no terreno move apenas `LeaderA`; o mesmo para `LeaderB`.
- [ ] **Movimento em grupo:** selecionar ambos e clicar com o botão direito move os dois simultaneamente; ambos chegam separados sem sobreposição.
- [ ] **Preservação da seleção:** clique direito de movimento nunca limpa nem troca a seleção atual.
- [ ] **Marcador de destino:** aparece no ponto comandado (ou no slot ajustado) e desaparece automaticamente após o pulso.
- [ ] **Spam e cliques inválidos:** clicar rapidamente várias vezes no terreno, clicar no céu/fora do mapa ou em topo de parede não trava nem gera comportamento errático.
- **Observações / Defeitos:** `________________________________________________`

### 5. Separação Dinâmica (RVO) e Destinos Ocupados (T1.9)
- [ ] **Cruzamento frontal:** enviar `LeaderA` e `LeaderB` em direções opostas na mesma linha; ambos desviam suavemente sem atravessar um ao outro e chegam aos destinos.
- [ ] **Cruzamento diagonal:** enviar ambos em trajetórias cruzadas a 45°/90°; ambos se evitam sem oscilações bruscas.
- [ ] **Unidade parada (`IDLE`):** enviar um protagonista passando direto pela posição do outro parado; o parado permanece imóvel enquanto o outro contorna.
- [ ] **Mesmo destino consecutivo / clique sobre aliado:** com um protagonista parado em um ponto (ou indo até lá), clicar com o botão direito exatamente sobre esse ponto/aliado envia o segundo protagonista para um slot livre próximo sem colisão permanente.
- **Observações / Defeitos:** `________________________________________________`

### 6. Obstáculos, Cercado Fechado, Rampa e Platô (AC-09, AC-10, AC-12)
- [ ] **Parede com vão (`WallGap`):** ordenar movimento através da parede faz as unidades contornarem pelo vão sem atravessar colisores.
- [ ] **Cercado fechado (`ClosedEnclosure`):** clicar dentro do cercado fechado move a unidade até o ponto alcançável mais próximo na borda externa e para limpa e definitivamente em `IDLE` sem ficar tentando atravessar a parede.
- [ ] **Rampa e platô:** ordenar subida e descida pela rampa até o platô elevado; unidades acompanham a inclinação sem flutuar, afundar ou cair da borda durante desvios em grupo.
- **Observações / Defeitos:** `________________________________________________`

---

## Parecer Final do Usuário

- **Data da execução:** `____/____/2026`
- **Resolução testada:** `____________`
- **Resultado geral (AC-16):** `[ ] Aprovado` / `[ ] Reprovado (ajustes necessários)`
- **Resumo de pendências ou defeitos encontrados:**
  - `____________________________________________________________________`
