# Protocolo de Testes Manuais — T3.3 (Canteiro de Obra e Suprimento Físico)

**Escopo:** Validação visual, interativa e econômica da etapa **T3.3** em `src/main/main.tscn` (`TestMap`), contemplando criação transacional de canteiro (`ConstructionSite`), reserva imediata no estoque do acampamento, inspeção no painel provisório (`TemporarySitePanel`), transporte físico e descarregamento por trabalhadores, regra D9 de organização (1 transportador + até 2 construtores) e bloqueio de sobreposição em novas prévias.<br>
**Limites intencionais da T3.3 (não esperar nesta etapa):**
- Ao atingir `100%` de suprimento físico no buffer (`"Estado: Suprido e pronto para construção (T3.4)"`), **não** há consumo do buffer em progresso de construção, **não** há transformação em edifício concluído e **não** há rebake da malha de navegação ativa (`T3.4`).
- `TemporarySitePanel` é uma interface provisória exclusiva de validação da T3.3, a ser substituída pelo catálogo/inspetor definitivos na `T3.5`.
- **Não** existe cancelamento/reembolso de canteiro (`T3.6`), depósito físico utilizável (`T3.7`) nem salvamento/persistência (`T3.8`).

---

## 1. Pré-requisitos e Comandos

Executar na raiz do worktree `C:\Projetos\Dawn_of_Kin_wt_t3_3_construction`:

1. Janela `1280x720`:
   ```powershell
   .\tools\run_game.ps1 -Resolution "1280x720" -FailOnWarnings
   ```
2. Janela `1920x1080`:
   ```powershell
   .\tools\run_game.ps1 -Resolution "1920x1080" -FailOnWarnings
   ```

> **Preparação inicial no mapa (`TestMap`):** O acampamento começa com `0` de madeira/pedra. Primeiro, envie `LeaderA` / `LeaderB` para coletar madeira (`WoodTree01/02`) e pedra (`StoneRock01/02`) até acumular pilhas no acampamento suficientes para testar a criação do `Abrigo Básico` (`12 Madeira, 6 Pedra`) ou `Depósito Rústico` (`18 Madeira, 10 Pedra`).

---

## 2. Checklist de Verificação Manual

### A. Criação Transacional de Canteiro e Rejeição por Estoque
- **A1 — Rejeição segura com estoque livre insuficiente:**
  - Ação: Com estoque livre no acampamento abaixo de `12 Madeira / 6 Pedra`, pressionar `F6` (ou clicar em `Abrigo 4×4 [F6]`) e confirmar com botão esquerdo (`LMB`) em chão livre válido.
  - Evidência esperada: A criação do canteiro é rejeitada sem travamentos; o banner exibe `"Não foi possível criar canteiro: Abrigo Básico"` com motivo claro de insuficiência; nenhum `ConstructionSite` aparece no terreno e o estoque do acampamento não muda nem fica negativo.
  - Resultado: `[ ] aprovado  [ ] reprovado  [x] não testado`
  - Campo de observações opcionais: ``

- **A2 — Criação de canteiro e reserva imediata no HUD:**
  - Ação: Coletar madeira e pedra suficientes no acampamento (ex.: `>= 12 Madeira` e `>= 6 Pedra`), ativar `Abrigo 4×4 [F6]` e confirmar com `LMB` em posição válida livre (ex.: próximo a `(-6, 0, 1.5)`).
  - Evidência esperada: Surge a base discreta do canteiro (`FoundationVisual`, sem sombras projetadas estranhas); o banner informa `"Canteiro criado: Abrigo Básico (...)"`; o HUD do acampamento preserva o físico e abate imediatamente `12 Madeira` e `6 Pedra` do **livre** (passando para **reservado**); e o painel provisório do canteiro abre mostrando `Buf 0/12 | Res 12 | Tr 0 | Falt 0` (madeira) e `Buf 0/6 | Res 6 | Tr 0 | Falt 0` (pedra).
  - Resultado: `[ ] aprovado  [ ] reprovado  [x] não testado`
  - Campo de observações opcionais: ``

### B. Seleção, Inspeção e Designação RTS
- **B1 — Inspeção por clique esquerdo (`LMB`) e botões do painel provisório:**
  - Ação: Clicar em `Fechar` no painel do canteiro; clicar em chão vazio ou unidade; em seguida clicar com `LMB` sobre a base do canteiro e testar também selecionar um trabalhador e clicar em `Designar selecionados (1)`.
  - Evidência esperada: O painel fecha ao clicar `Fechar`, reabre ao clicar com `LMB` no canteiro, não bloqueia cliques fora do painel, e `Designar selecionados` envia imediatamente as unidades selecionadas sem exigir clique direito adicional.
  - Resultado: `[ ] aprovado  [ ] reprovado  [x] não testado`
  - Campo de observações opcionais: ``

- **B2 — Ciclo físico completo com 1 trabalhador (saque na pilha, peso e entrega):**
  - Ação: Com um canteiro criado (`Abrigo Básico`) e pilhas reservadas no acampamento, selecionar `LeaderA` e clicar com botão direito (`RMB`) sobre o canteiro. Observar até concluir todas as viagens.
  - Evidência esperada: `LeaderA` caminha até uma pilha física específica que contém recursos reservados, reduz a pilha física ao retirar conforme capacidade/peso da mochila (desacelerando proporcionalmente enquanto carregado), leva ao perímetro do canteiro e descarrega no buffer (`Buf` sobe em passos reais, `Res`/`Tr` atualizam). Ao atingir `Buf 12/12` e `Buf 6/6`, o painel muda para `"Estado: Suprido e pronto para construção (T3.4)"` e **não** inicia barra de progresso nem transforma em edifício concluído.
  - Resultado: `[ ] aprovado  [x] reprovado  [ ] não testado`
  - Campo de observações opcionais: `Reprovado na T3.3-R1 com canteiro no platô próximo à rampa (personagem preso na lateral da rampa e suprimento incompleto). Corrigido em código e validado em janela real na T3.3-R2 (docs/testing/T3_3_R2_plateau_navigation_diagnostic.md); aguardando reteste manual pelo proprietário.`

### C. Organização de Trabalhadores (Regra D9), Concorrência e Interrupções
- **C1 — Regra D9 com 2 trabalhadores (1 transportador + 1 construtor em espera):**
  - Ação: Em um canteiro ainda não suprido, selecionar `LeaderA` e `LeaderB` simultaneamente e clicar com `RMB` no canteiro.
  - Evidência esperada: O painel lista 1 trabalhador como `Transportador` (ou equivalente em transporte) e 1 como `Construtor` (aguardando posicionado no perímetro do canteiro sem invadir o interior da base).
  - Resultado: `[ ] aprovado  [ ] reprovado  [x] não testado`
  - Campo de observações opcionais: ``

- **C2 — Promoção automática ao interromper o transportador:**
  - Ação: Durante o transporte do cenário C1 (enquanto ainda faltam recursos no buffer), selecionar apenas o trabalhador que está como transportador e dar uma ordem de movimento (`RMB` no chão distante).
  - Evidência esperada: O trabalhador interrompido abandona a tarefa de obra mantendo intacta eventual carga na mochila (sem apagar recursos); o construtor que estava em espera é promovido automaticamente a transportador e continua o suprimento do canteiro até completar o buffer.
  - Resultado: `[ ] aprovado  [ ] reprovado  [x] não testado`
  - Campo de observações opcionais: ``

- **C3 — Interrupção com mochila carregada e devolução de recurso incompatível:**
  - Ação: Com um trabalhador carregando fruta/alimento (coletado de arbusto `FoodBush01`) na mochila, clicar com `RMB` sobre um canteiro que só requer madeira e pedra; depois testar interromper um transportador carregando madeira no meio da caminhada e redirecioná-lo ao canteiro novamente.
  - Evidência esperada: Ao receber ordem no canteiro com recurso incompatível (alimento), o trabalhador devolve com segurança o alimento à zona de acampamento antes de iniciar coleta para a obra (sem apagar o alimento). Ao interromper e retomar transporte de madeira para o mesmo canteiro, a madeira já na mochila é entregue corretamente ao buffer sem perda nem duplicação.
  - Resultado: `[ ] aprovado  [ ] reprovado  [x] não testado`
  - Campo de observações opcionais: ``

- **C4 — Limite D9 com 3 e 4 trabalhadores (`1 transportador + até 2 construtores` e recusa do 4º):**
  - Ação: (Requer instância/cenário com 3–4 unidades, já que `TestMap` padrão inicia com 2 protagonistas; na cena padrão confirmar ao menos a legenda `(máx. constr.: 2)` no painel.) Designar 3 e depois tentar designar um 4º trabalhador ao mesmo canteiro.
  - Evidência esperada: Com 3 trabalhadores designados, exatamente 1 atua como transportador e 2 como construtores em espera no perímetro (`max_builders = 2`); ao tentar designar um 4º trabalhador enquanto todas as vagas estão ocupadas, o canteiro recusa a vaga excedente (`no_worker_slot`) sem expulsar os já alocados. *(Nota: já coberto de forma automatizada em `test_t3_3_construction_site.gd::test_05` e `test_t3_3_construction_logistics.gd::test_03`.)*
  - Resultado: `[ ] aprovado  [ ] reprovado  [x] não testado`
  - Campo de observações opcionais: ``

### D. Regras Espaciais, Câmera e Higiene
- **D1 — Bloqueio de sobreposição sobre canteiro existente:**
  - Ação: Com um `ConstructionSite` ativo no terreno, pressionar `F6` ou `F7` e arrastar a prévia sobre o canteiro já existente (e logo ao lado sem sobrepor).
  - Evidência esperada: Sobre o canteiro existente a prévia fica vermelha e rejeita confirmação; ao lado em área livre válida permite confirmar normalmente.
  - Resultado: `[ ] aprovado  [ ] reprovado  [x] não testado`
  - Campo de observações opcionais: ``

- **D2 — Câmera, seleção em caixa, console e resoluções (`1280x720` e `1920x1080`):**
  - Ação: Repetir criação, inspeção e transporte nas duas resoluções (`1280x720` e `1920x1080`), operando pan/zoom (`WASD`, setas, `MMB`, `Scroll`, `Edge Scroll`) e seleção em caixa (`LMB` drag) sem fechar o painel provisório.
  - Evidência esperada: Nenhuma sobreposição visual crítica nos painéis de canto, cliques no mundo e arrastes não travam por filtros de UI, e 0 `ERROR`/`WARNING` no console ao encerrar o jogo.
  - Resultado: `[ ] aprovado  [ ] reprovado  [x] não testado`
  - Campo de observações opcionais: ``

---

## 3. Resumo Final do Avaliador
- **Resoluções testadas:** `Pendente (reteste após T3.3-R2)`
- **Veredito geral:** `[ ] Aprovado  [ ] Aprovado com ressalvas  [x] Reprovado  [ ] Aguardando execução manual`
- **Observações gerais opcionais:** `Item B2 reprovado na rodada manual da T3.3-R1 (navegação lateral da rampa no platô e interrupção do abastecimento); itens seguintes (C1–D2) permanecem pendentes. Correções da T3.3-R2 implementadas e verificadas em reprodução renderizada (`docs/testing/T3_3_R2_plateau_navigation_diagnostic.md`); aguardando reteste manual de B2 e prosseguimento de C1–D2 pelo proprietário.`
