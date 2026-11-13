# Dawn of Kin — Protocolo de Teste Manual da T1

Roteiro interativo executado em janela real para validar ergonomia, resposta do mouse, leitura visual e comportamento em tempo real do marco **T1 — Fundação RTS**.

## Como iniciar

No PowerShell, na raiz `C:\Projetos\Dawn of Kin`:

```powershell
.\tools\run_game.ps1 -Resolution "1920x1080"
```

Pressione **F3** a qualquer momento para alternar o overlay de debug (FPS, frame time, física, draw calls).

---

## Checklist de Verificação Manual (Executado e Aprovado)

### 1. Câmera RTS e Edge Scrolling (AC-04)
- [x] **Pan por teclado (`WASD` / `Setas`):** movimento suave no plano isométrico em todas as direções, respeitando os limites do mapa (a câmera não sai do mapa).
- [x] **Pan por arraste (botão do meio):** segurar e arrastar desloca a câmera de forma fluida sem saltos bruscos.
- [x] **Zoom (roda do mouse):** aproxima e afasta suavemente entre os limites mínimo e máximo.
- [x] **Edge Scrolling (~6 px da borda):** aproximar o cursor a ~6 pixels físicos das bordas da janela inicia o deslocamento; manter o cursor dentro da área útil (inclusive perto de seleções) **não** dispara movimento involuntário.
- [x] **Sensação geral:** câmera responde de forma consistente e previsível em diferentes níveis de zoom.
- **Status:** Aprovado.

### 2. Personagens e Feedback Visual (AC-05, AC-07)
- [x] **Distinção visual:** `LeaderA` e `LeaderB` são claramente distinguíveis por **cor e silhueta/forma** tanto no zoom mínimo quanto no zoom máximo.
- [x] **Hover:** passar o mouse sobre um personagem destaca o indicador de hover sem alterar a seleção atual.
- [x] **Anel de seleção:** visível sob o(s) personagem(ns) selecionado(s) em todos os níveis de zoom.
- **Status:** Aprovado.
- **Nota técnica sobre observação de usuário:** O anel amarelo sob o personagem após o deslocamento é o `SelectionIndicator` intencional, indicando que a unidade permanece selecionada até clique no chão, troca de seleção ou `Esc`. O marcador pontual de clique de ordem (`DestinationMarker`) pulsa e desaparece de forma independente. Comportamento correto e aprovado.

### 3. Seleção Individual e por Caixa (AC-06, AC-07)
- [x] **Seleção individual:** clique esquerdo em `LeaderA` seleciona apenas `LeaderA`; clique esquerdo em `LeaderB` transfere a seleção para `LeaderB`.
- [x] **Shift+clique:** alterna inclusão/remoção na seleção sem duplicar unidades.
- [x] **Seleção por caixa:** arrastar o botão esquerdo desenha o retângulo da caixa em qualquer uma das 4 direções e seleciona as unidades dentro da área ao soltar.
- [x] **Shift+arraste:** adiciona unidades da caixa à seleção existente sem removê-las.
- [x] **Limpeza de seleção:** clique esquerdo no chão vazio (sem Shift) limpa a seleção; `Shift+clique` no chão preserva a seleção; tecla `Esc` limpa a seleção (ou cancela caixa em andamento).
- [x] **Clique vs arraste:** pequenos movimentos acidentais dentro do limiar não disparam caixa; arrastes reais não disparam clique simples.
- **Status:** Aprovado.

### 4. Comandos de Movimento e Marcador de Destino (AC-08, AC-11)
- [x] **Movimento individual:** selecionar `LeaderA` e clicar com o botão direito no terreno move apenas `LeaderA`; o mesmo para `LeaderB`.
- [x] **Movimento em grupo:** selecionar ambos e clicar com o botão direito move os dois simultaneamente; ambos chegam separados sem sobreposição.
- [x] **Preservação da seleção:** clique direito de movimento nunca limpa nem troca a seleção atual.
- [x] **Marcador de destino:** aparece no ponto comandado (ou no slot ajustado) e desaparece automaticamente após o pulso.
- [x] **Spam e cliques inválidos:** clicar rapidamente várias vezes no terreno, clicar no céu/fora do mapa ou em topo de parede não trava nem gera comportamento errático.
- **Status:** Aprovado.

### 5. Separação Dinâmica (RVO) e Destinos Ocupados (T1.9)
- [x] **Cruzamento frontal:** enviar `LeaderA` e `LeaderB` em direções opostas na mesma linha; ambos desviam suavemente sem atravessar um ao outro e chegam aos destinos.
- [x] **Cruzamento diagonal:** enviar ambos em trajetórias cruzadas a 45°/90°; ambos se evitam sem oscilações bruscas.
- [x] **Unidade parada (`IDLE`):** enviar um protagonista passando direto pela posição do outro parado; o parado permanece imóvel enquanto o outro contorna.
- [x] **Mesmo destino consecutivo / clique sobre aliado:** com um protagonista parado em um ponto (ou indo até lá), clicar com o botão direito exatamente sobre esse ponto/aliado envia o segundo protagonista para um slot livre próximo sem colisão permanente.
- **Status:** Aprovado.

### 6. Obstáculos, Cercado Fechado, Rampa e Platô (AC-09, AC-10, AC-12)
- [x] **Parede com vão (`WallGap`):** ordenar movimento através da parede faz as unidades contornarem pelo vão sem atravessar colisores.
- [x] **Cercado fechado (`ClosedEnclosure`):** clicar dentro do cercado fechado move a unidade até o ponto alcançável mais próximo na borda externa e para limpa e definitivamente em `IDLE` sem ficar tentando atravessar a parede.
- [x] **Rampa e platô:** ordenar subida e descida pela rampa até o platô elevado; unidades acompanham a inclinação sem flutuar, afundar ou cair da borda durante desvios em grupo.
- **Status:** Aprovado.

---

## Parecer Final do Usuário

- **Data da execução e aprovação:** 13/11/2026
- **Resolução testada:** 1920×1080
- **Grupos testados:** 9/9 grupos aprovados (Câmera, Seleção individual, Seleção por caixa, Movimento individual, Movimento em grupo, Obstáculos/comandos inválidos, Evasão RVO, Destinos ocupados/terreno, Visual e experiência geral).
- **Resultado geral (AC-16):** **Aprovado**
- **Observações:** A observação referente ao anel sob o personagem foi esclarecida como comportamento intencional do `SelectionIndicator` (permanece ativo enquanto a unidade for selecionada). Nenhuma correção de código necessária.
