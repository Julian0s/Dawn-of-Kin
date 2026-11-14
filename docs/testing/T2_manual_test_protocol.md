# Protocolo de Testes Manuais — T2 (Economia Inicial, Transporte, Estoque e HUD)

**Versão:** 1.1 (Consolidada pós-T2.6-B1)<br>
**Escopo:** Validação manual da etapa **T2** (`T2.0` a `T2.6` + `B1`) em `src/main/main.tscn` (`TestMap`).<br>
**Estado:** Executado e relatado como aprovado pelo proprietário em 14/11/2026 (aguardando aceite formal definitivo de encerramento do marco).<br>
> **Nota de integridade:** Os registros abaixo refletem a execução interativa informada diretamente pelo proprietário, distinguindo-se das validações automatizadas executadas pelo Antigravity.

---

## 1. Pré-requisitos e Comandos

1. Executar na raiz do repositório (`C:\Projetos\Dawn of Kin`):
   - Modo padrão janela `1280x720`:
     ```powershell
     .\tools\run_game.ps1 -Resolution "1280x720" -FailOnWarnings
     ```
   - Modo resolução alvo `1920x1080`:
     ```powershell
     .\tools\run_game.ps1 -Resolution "1920x1080" -FailOnWarnings
     ```
2. Para observar **deterioração centralizada** em poucos segundos sem esperar `180 s` (alimentos) ou `420 s` (madeira) em tempo real, usar o cenário visual dedicado (não altera o jogo normal nem adiciona botões de debug à interface):
   ```powershell
   .\tools\run_game.ps1 -Resolution "1280x720" -ExtraArgs "--script","res://tests/visual/scenario_t2_decay.gd" -FailOnWarnings
   ```
   > Nesse cenário, o `EconomyClockController` acelera a passagem do tempo econômico após a primeira entrega de alimentos e madeira no acampamento, permitindo acompanhar no HUD e nas pilhas físicas a redução progressiva até o desaparecimento das pilhas deterioradas (enquanto pedra permanece intacta).

---

## 2. Valores de Referência em `TestMap`

| Recurso | Fontes no `TestMap` | Estoque inicial da fonte | Extração por ciclo | Tempo por operação | Peso unitário | Início da deterioração |
|---|---|---:|---:|---:|---:|---|
| **Madeira** | `wood_tree_01`, `wood_tree_02` | 24 un | 2 un | 2,5 s | 2 | 420 s simulados (depois a cada 120 s) |
| **Pedra** | `stone_rock_01`, `stone_rock_02` | 18 un | 1 un | 3,5 s | 3 | Não deteriora |
| **Alimentos** | `food_bush_01`, `food_bush_02` | 30 un | 2 un | 1,5 s | 1 | 180 s simulados (depois a cada 45 s) |

Capacidade efetiva padrão de carga de cada protagonista: **20** (sem bônus de mochila/ferramenta no início do jogo).

---

## 3. Checklist de Aceitação Manual T2

### A. Reconhecimento Visual, Equipamento Inicial e Ritmo
- [x] **A1:** Ao iniciar `main.tscn`, os dois protagonistas começam sem ferramentas ou mochilas visíveis acopladas ao corpo.
- [x] **A2:** Árvores (`Madeira`), rochas (`Pedra`) e arbustos (`Alimentos`) são visualmente distintos entre si, dos obstáculos estáticos e dos personagens.
- [x] **A3:** Ao selecionar um protagonista e clicar com o botão direito em uma fonte, ele navega ao redor de obstáculos até uma vaga válida e entra em estado `Trabalhando`.
- [x] **A4:** Durante a coleta, percebe-se ritmo distinto entre Alimentos (~1,5 s), Madeira (~2,5 s) e Pedra (~3,5 s), com feedback visual provisório de trabalho.

### B. Transporte, Peso, Conservação e Pilhas Físicas
- [x] **B1:** Conforme o personagem carrega peso próximo ao limite, sua velocidade de deslocamento cai visivelmente em comparação à marcha sem carga. *(Apontamento do proprietário em 14/11/2026: a velocidade ao ir coletar sem carga diferia da caminhada normal por clique direito. Corrigido em B1 no commit `8f53a3f`, retestado visualmente e expressamente confirmado pelo proprietário: "testei esta correto".)*
- [x] **B2 — Conservação de Pedra:** Ao encher com **6 pedras** (`Peso transportado: 18 / 20`, `90%`), o trabalhador retorna ao acampamento e credita exatamente **+6** em Pedra no estoque coletivo.
- [x] **B3 — Conservação de Madeira:** Ao encher com **10 madeiras** (`Peso transportado: 20 / 20`, `100%`), o trabalhador retorna ao acampamento e credita exatamente **+10** em Madeira no estoque coletivo.
- [x] **B4 — Conservação de Alimentos:** Ao encher com **20 alimentos** (`Peso transportado: 20 / 20`, `100%`), o trabalhador retorna ao acampamento e credita exatamente **+20** em Alimentos no estoque coletivo.
- [x] **B5:** O crédito no estoque só acontece no momento da descarga física na zona do acampamento (`CampStorageZone`), formando ou incrementando pilhas físicas no chão sem sobreposição grosseira.

### C. Concorrência, Interrupção e Esgotamento
- [x] **C1:** Dois protagonistas selecionados e ordenados para a mesma fonte trabalham simultaneamente em vagas distintas sem travar na navegação/RVO.
- [x] **C2:** Quando uma fonte possui carga restante menor que a extração dupla (último saldo), ambos não duplicam recursos ao finalizar simultaneamente.
- [x] **C3:** Clicar com o botão direito no chão durante o `Trabalhando` ou `Transportando` interrompe o trabalho e move o personagem mantendo a carga já coletada intacta.
- [x] **C4:** Quando uma fonte se esgota durante a coleta com carga parcial no inventário individual, o trabalhador retorna automaticamente ao acampamento para entregar o saldo parcial; cliques direitos futuros na fonte esgotada não travam nem iniciam coleta falsa.

### D. Interface HUD (T2.5 / T2.5.1) e Controles RTS
- [x] **D1:** Painel superior direito exibe quantidades de `Madeira`, `Pedra` e `Alimentos` sincronizadas ao vivo com as pilhas do acampamento e estado `Armazenamento: exposto`.
- [x] **D2:** Painel inferior esquerdo (seleção única) diferencia claramente `Peso transportado: X / Y`, barra/porcentagem por peso e quantidades individuais em unidades (`Madeira: X un`, `Pedra: X un`, `Alimentos: X un`).
- [x] **D3:** Seleção múltipla dos dois personagens mostra resumo compacto (`2 selecionados`) e volta aos detalhes completos ao clicar em um único personagem.
- [x] **D4:** Em `1280x720` e `1920x1080`, nenhum painel do HUD invade excessivamente o centro da tela nem bloqueia cliques esquerdos, caixa de seleção ou clique direito sob a área dos painéis.

### E. Deterioração Centralizada (`scenario_t2_decay.gd`)
- [x] **E1:** Ao executar `.\tools\run_game.ps1 -Resolution "1280x720" -ExtraArgs "--script","res://tests/visual/scenario_t2_decay.gd" -FailOnWarnings`, após o depósito inicial, o estoque de **Alimentos** e depois **Madeira** decresce progressivamente enquanto **Pedra** permanece constante.
- [x] **E2:** Quando uma pilha física atinge `0`, a instância da pilha desaparece do chão e o contador do HUD acompanha exatamente a perda até `0`, sem erros ou avisos no console.

### F. Regressão T1 & Limites Visuais Conhecidos
- [x] **F1:** Câmera isométrica (`WASD` e setas, Edge Scrolling na borda real do viewport, arraste pelo botão do meio do mouse e zoom por scroll) e seleção/ordens RTS da T1 permanecem fluidos durante coleta e transporte simultâneos.
- [x] **F2:** Avaliador ciente dos itens visuais provisórios já registrados da T2.4.3 (oscilação corporal simples no feedback de trabalho, pilhas geométricas provisórias no chão e ausência de feedback sonoro ou animação dedicada de coleta).

---

## 4. Registro de Avaliação

- **Status da Verificação Manual:** Todos os 21 itens (A1 a F2) foram executados e relatados como aprovados pelo proprietário em 14/11/2026.
- **Histórico de Correção B1:** Observada divergência de velocidade em B1; corrigida tecnicamente no commit `8f53a3f`; retestada e confirmada pelo proprietário ("testei esta correto").
- **Situação Formal do Marco:** Aguardando assinatura/aceite formal de encerramento da T2 pelo proprietário na consolidação `review/t2-closeout-candidate`.
