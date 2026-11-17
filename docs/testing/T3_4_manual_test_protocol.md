# T3.4 — Protocolo manual do proprietário

Status: **NÃO EXECUTADO / AGUARDANDO HOMOLOGAÇÃO**. Testes automatizados e benchmark não preenchem estes campos.

Registrar antes da execução: data, SHA candidato, Godot, hardware, alimentação CA/DC, resolução e renderer. Executar a candidata T3.4.5, com Godot 4.7.2 / Compatibility / Jolt, sem integrar na main. Reiniciar a cena entre cenários quando necessário.

Preparação: coletar e descarregar fisicamente pelo menos 12 madeiras e 6 pedras por Abrigo Básico; confirmar o saldo livre antes de posicionar. F6 abre a prévia do abrigo, F7 a do depósito; usar a confirmação da prévia e RMB no canteiro para atribuir trabalhadores. Usar os controles temporários de Worker3/Worker4 no painel de testes quando necessário; são ferramentas de desenvolvimento, sem efeito na população canônica. O Depósito Rústico ainda não oferece armazenamento protegido.

## M-A1 — Um trabalhador

**Procedimento:** criar um Abrigo Básico e atribuir somente um líder desde o início. Observar viagens, buffer, montagem e conclusão.

**Esperado:** transporta primeiro os reservados acessíveis; depois monta com o buffer disponível, até 100%. Um único edifício aparece, o canteiro desaparece, os materiais não reaparecem no estoque e o trabalhador fica IDLE.

**Resultado: [ ] Aprovado  [ ] Reprovado**

**Observações opcionais do proprietário:** ______________________________

## M-A2 — Dois trabalhadores

**Procedimento:** atribuir os dois líderes a um abrigo desde 0%. Acompanhar o construtor enquanto o outro transporta. Observar a última entrega.

**Esperado:** 1 transporta e 1 monta em paralelo com suprimento parcial. Após a última entrega, o transportador assume o segundo slot; a taxa agregada passa de 1 para 2 segundos-construtor por segundo. Conclusão única, sem perda ou segundo consumo.

**Resultado: [ ] Aprovado  [ ] Reprovado**

**Observações opcionais do proprietário:** ______________________________

## M-A3 — Três trabalhadores e recusa do quarto

**Procedimento:** adicionar Worker3 e Worker4 pelos controles temporários. Atribuir LeaderA, LeaderB e Worker3 à mesma obra, e tentar atribuir Worker4. Observar a conclusão do transporte.

**Esperado:** 1 transportador e 2 construtores; o quarto é recusado com `no_worker_slot`, sem expulsar os outros. Ao terminar o suprimento, o transportador fica livre; permanecem no máximo dois construtores.

**Resultado: [ ] Aprovado  [ ] Reprovado**

**Observações opcionais do proprietário:** ______________________________

## M-B1 — Falta de material e retomada

**Procedimento:** atribuir 2 trabalhadores. Antes de entregar pedra suficiente, redirecionar o transportador por RMB no terreno. Deixar o construtor alcançar o limite financiado pelo buffer; depois reatribuir o transportador ao canteiro, preservando suas cargas.

**Esperado:** pausa em `PAUSED_STARVED` / `WAITING_FOR_MATERIALS`, sem saldo negativo ou movimento de montagem fictício. Novas entregas despertam o construtor e preservam exatamente o progresso e o consumo anterior. Este cenário usa reservas já existentes; não pressupõe a futura interface definitiva de complementação T3.5.

**Resultado: [ ] Aprovado  [ ] Reprovado**

**Observações opcionais do proprietário:** ______________________________

## M-B2 — Interrupção e retomada

**Procedimento:** próximo a 50%, anotar progresso, materiais incorporados e buffer. Dar uma ordem de movimento ao construtor, observar a pausa e reatribuí-lo à obra.

**Esperado:** slot liberado corretamente, sem apagar progresso, buffer ou carga. A montagem retoma do valor anterior e não cobra novamente os materiais já incorporados.

**Resultado: [ ] Aprovado  [ ] Reprovado**

**Observações opcionais do proprietário:** ______________________________

## M-C1 — Contorno físico e proteção contra sobreposição

**Procedimento:** concluir um abrigo. Durante a transição, tentar comandar uma unidade através de sua área. Após o rebake, ordenar um destino do outro lado. Abrir F6/F7 e tentar confirmar uma nova obra sobre o edifício. Repetir com duas obras terminando próximas no tempo.

**Esperado:** durante o rebake, comandos afetados são rejeitados e unidades em trânsito aguardam sem bater na parede; rotas distantes continuam funcionando. Após sincronizar, as unidades contornam o prédio. A prévia e a confirmação rejeitam sobreposição, sem criar reservas. Cada obra gera apenas um edifício.

**Resultado: [ ] Aprovado  [ ] Reprovado**

**Observações opcionais do proprietário:** ______________________________

## M-C2 — Platô e rampa

**Procedimento:** posicionar e concluir um abrigo no platô, próximo à rampa, usando uma posição aceita pela validação de conectividade; manter livre a saída estreita da rampa. Ordenar uma unidade da base para além do prédio e depois retornar à base.

**Esperado:** sobe e desce pela rampa, permanece entre os curbs laterais, contorna o edifício e não atravessa paredes nem cai pelas bordas. Posições que fecham a conectividade devem ser recusadas pela prévia.

**Resultado: [ ] Aprovado  [ ] Reprovado**

**Observações opcionais do proprietário:** ______________________________

## M-D1 — Resolução dinâmica 1280×720 ↔ 1920×1080

**Procedimento:** durante montagem ativa, redimensionar a janela pelo sistema/editor para 1280×720 e 1920×1080, sem reiniciar a cena; repetir durante a conclusão. Registrar os tamanhos efetivos e observar HUD, prévia e enquadramento.

**Esperado:** informações legíveis e corretamente posicionadas, sem controles fora da janela, confirmação indevida, reinício ou erros no console. A execução do benchmark em resolução fixa não substitui este cenário.

**Resultado: [ ] Aprovado  [ ] Reprovado**

**Observações opcionais do proprietário:** ______________________________

## Registro final

SHA: __________________ Data: __________________ Hardware/CA/DC: __________________

Godot/renderer/resoluções efetivas: ______________________________________________

Resultado do proprietário e eventuais itens a repetir: ____________________________

Nenhum campo preenchido por um agente equivale à aprovação expressa do proprietário.
