# Protocolo de Testes Manuais — T2 (Economia Inicial, Transporte, Estoque e HUD)

**Versão:** 1.0  
**Escopo:** Encerramento técnico da etapa **T2** (`T2.0` a `T2.6`) em `src/main/main.tscn` (`TestMap`).  
**Estado:** Aguardando execução e assinatura manual do proprietário.  
> **Nota:** Nenhum item abaixo deve ser marcado como `[x]` sem execução visual e interativa real pelo avaliador.

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
- [ ] Ao iniciar `main.tscn`, os dois protagonistas começam sem ferramentas ou mochilas visíveis acopladas ao corpo.
- [ ] Árvores (`Madeira`), rochas (`Pedra`) e arbustos (`Alimentos`) são visualmente distintos entre si, dos obstáculos estáticos e dos personagens.
- [ ] Ao selecionar um protagonista e clicar com o botão direito em uma fonte, ele navega ao redor de obstáculos até uma vaga válida e entra em estado `Trabalhando`.
- [ ] Durante a coleta, percebe-se ritmo distinto entre Alimentos (~1,5 s), Madeira (~2,5 s) e Pedra (~3,5 s), com feedback visual provisório de trabalho.

### B. Transporte, Peso, Conservação e Pilhas Físicas
- [ ] Conforme o personagem carrega peso próximo ao limite, sua velocidade de deslocamento cai visivelmente em comparação à marcha sem carga.
- [ ] **Conservação de Pedra:** Ao encher com **6 pedras** (`Peso transportado: 18 / 20`, `90%`), o trabalhador retorna ao acampamento e credita exatamente **+6** em Pedra no estoque coletivo.
- [ ] **Conservação de Madeira:** Ao encher com **10 madeiras** (`Peso transportado: 20 / 20`, `100%`), o trabalhador retorna ao acampamento e credita exatamente **+10** em Madeira no estoque coletivo.
- [ ] **Conservação de Alimentos:** Ao encher com **20 alimentos** (`Peso transportado: 20 / 20`, `100%`), o trabalhador retorna ao acampamento e credita exatamente **+20** em Alimentos no estoque coletivo.
- [ ] O crédito no estoque só acontece no momento da descarga física na zona do acampamento (`CampStorageZone`), formando ou incrementando pilhas físicas no chão sem sobreposição grosseira.

### C. Concorrência, Interrupção e Esgotamento
- [ ] Dois protagonistas selecionados e ordenados para a mesma fonte trabalham simultaneamente em vagas distintas sem travar na navegação/RVO.
- [ ] Quando uma fonte possui carga restante menor que a extração dupla (último saldo), ambos não duplicam recursos ao finalizar simultaneamente.
- [ ] Clicar com o botão direito no chão durante o `Trabalhando` ou `Transportando` interrompe o trabalho e move o personagem mantendo a carga já coletada intacta.
- [ ] Quando uma fonte se esgota durante a coleta com carga parcial no inventário individual, o trabalhador retorna automaticamente ao acampamento para entregar o saldo parcial; cliques direitos futuros na fonte esgotada não travam nem iniciam coleta falsa.

### D. Interface HUD (T2.5 / T2.5.1) e Controles RTS
- [ ] Painel superior direito exibe quantidades de `Madeira`, `Pedra` e `Alimentos` sincronizadas ao vivo com as pilhas do acampamento e estado `Armazenamento: exposto`.
- [ ] Painel inferior esquerdo (seleção única) diferencia claramente `Peso transportado: X / Y`, barra/porcentagem por peso e quantidades individuais em unidades (`Madeira: X un`, `Pedra: X un`, `Alimentos: X un`).
- [ ] Seleção múltipla dos dois personagens mostra resumo compacto (`2 selecionados`) e volta aos detalhes completos ao clicar em um único personagem.
- [ ] Em `1280x720` e `1920x1080`, nenhum painel do HUD invade excessivamente o centro da tela nem bloqueia cliques esquerdos, caixa de seleção ou clique direito sob a área dos painéis.

### E. Deterioração Centralizada (`scenario_t2_decay.gd`)
- [ ] Ao executar `.\tools\run_game.ps1 -Resolution "1280x720" -ExtraArgs "--script","res://tests/visual/scenario_t2_decay.gd" -FailOnWarnings`, após o depósito inicial, o estoque de **Alimentos** e depois **Madeira** decresce progressivamente enquanto **Pedra** permanece constante.
- [ ] Quando uma pilha física atinge `0`, a instância da pilha desaparece do chão e o contador do HUD acompanha exatamente a perda até `0`, sem erros ou avisos no console.

### F. Regressão T1 & Limites Visuais Conhecidos
- [ ] Câmera isométrica (`WASD`/setas, bordas se ativo, zoom por scroll e rotação controlada) e comandos da T1 permanecem fluidos durante coleta e transporte simultâneos.
- [ ] Avaliador ciente dos itens visuais provisórios já registrados da T2.4.3 (oscilação corporal simples no feedback de trabalho, pilhas geométricas provisórias no chão e ausência de feedback sonoro ou animação dedicada de coleta).

---

**Resultado Final do Avaliador:** `[ ] APROVADO` / `[ ] REPROVADO`  
**Observações:** ________________________________________________________________________
