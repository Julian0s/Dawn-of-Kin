# Dawn of Kin — regras permanentes de engenharia para o Antigravity

## Fonte de verdade e escopo
- Ler `Dawn_of_Kin_GDD_v1.0.md` antes de propor qualquer alteração. Respeitar os marcadores **DECIDIDO**, **PROPOSTA** e **ABERTO**; não converter hipóteses em funcionalidades obrigatórias.
- Projeto: jogo single-player em Godot 4.x/GDScript, RTS isométrico 3D.
- Estado atual do projeto: **T1 — Fundação RTS CONCLUÍDA** (marcada com tag Git `t1-complete` no commit `2808799`). A fase **T2 — Trabalho e Recursos** concluiu toda a implementação técnica, validação global e correções de polimento (`T2.0` a `T2.6` + `B1`), consolidada na branch `review/t2-closeout-candidate` e aguardando aceite formal definitivo do proprietário (não declarar a T2 oficialmente encerrada sem autorização expressa). **T2.0–T2.5.1** implementadas e testadas automaticamente; **T2.6** implementou validação global, correções de concorrência/navegação e executor segmentado (`.\tools\run_tests.ps1 -Segmented`, totalizando **182/182 testes aprovados em 27 suítes, 6.469 asserções e 0 erros/avisos**). **Ajuste B1** unificou a velocidade sem carga em `4,8 m/s` em ordens de movimento e de coleta, com redução proporcional por peso. Nos testes manuais em 14/11/2026, o proprietário informou aprovação de todos os 21 itens (A1–F2) do protocolo `docs/testing/T2_manual_test_protocol.md`, tendo testado e confirmado a correção B1 ("testei esta correto"). Nos benchmarks em `1920×1080` (Intel UHD Graphics 620, `gl_compatibility`), sob tomada CA (B1.1) a mediana de $p95$ foi `9,757 ms` (`147,33 FPS`, 0 quadros `> 100 ms`, aprovado), enquanto sob bateria DC (B1) foi `33,038 ms` (`55,80 FPS`, 0 quadros `> 100 ms`), registrada como limitação física de consumo em bateria (a diferença de energia não possui comprovação causal física definitiva sem telemetria síncrona; a aprovação em CA não equivale a aprovação universal em DC). Não implementar código de etapas futuras (`T3` a `T8`) sem autorização específica prévia do usuário.
- Avaliar o workspace real: conferir arquivos, versão instalada do Godot, renderer, hardware disponível, plugins e estado do Git antes de propor arquitetura.
- Obrigação de confrontar relatórios com documentação e código real: nunca afirmar que testes foram executados ou que arquivos estão sincronizados sem validação e evidência concreta.
- Trabalho estritamente incremental: submeter análise e plano revisável para aprovação explícita antes de criar ou alterar código.

## Qualidade antes da velocidade
- Priorizar corretude, robustez, legibilidade, extensibilidade responsável e boa experiência de jogo. Entrega rápida, por si só, não é critério de sucesso.
- Para alterações não triviais: primeiro análise e plano revisável; aguardar aprovação explícita antes de criar ou alterar código.
- Dividir o plano aprovado em incrementos pequenos com objetivo, arquivos afetados, riscos, teste e critério de aceite para cada incremento.
- Nunca simular conclusão: diferenciar **implementado**, **testado automaticamente**, **testado visualmente/manual**, **não verificado** e **bloqueado**.
- Se um teste falhar, diagnosticar causa raiz e corrigir sem ocultar avisos, desabilitar funcionalidades ou remover testes para aparentar sucesso.
- Não criar código monolítico ou 'god scripts'; separar câmera, seleção, ordens e navegação quando houver justificativa clara. Evitar abstrações, extensões e recursos futuros não necessários à T1.
- Usar GDScript tipado quando útil, nomes consistentes, responsabilidades claras, tratamento de estados inválidos e recursos reutilizáveis. Não inventar dependências nem adicionar plugins sem aprovação.
- Não mascarar funcionalidades ausentes com placeholders anunciados como recursos prontos. Assets temporários são aceitáveis se declarados e facilmente substituíveis.
- Nunca substituir silenciosamente um comportamento aprovado por uma implementação mais fácil. Se houver trade-off de qualidade, expor opções e solicitar decisão.

## Git e alterações seguras
- Antes de cada etapa, verificar `git status` e listar arquivos a modificar. Não apagar nem sobrescrever trabalho existente sem identificar e justificar.
- Criar checkpoints/commits pequenos após etapas aprovadas, preservando histórico e sem usar comandos destrutivos (`reset --hard`, `clean -fd`, force push) sem autorização explícita.
- Manter documentação mínima e útil: decisões arquiteturais, instruções para executar/testar e pendências reais.

## Validação e aceitação
- Executar importação/validação do projeto pela CLI da Godot quando possível; abrir e executar a cena no editor para verificar comportamento visual quando o ambiente permitir.
- Rodar testes automatizados relevantes para lógica isolável; testes headless **não substituem** testes visuais e de interação do mouse no jogo real.
- Para T1 verificar: câmera isométrica utilizável, seleção e feedback visual, seleção do outro personagem, ordens por clique direito, chegada ao destino, ausência de travamentos em cliques inválidos e navegação consistente com obstáculos previstos.
- Medir desempenho no hardware disponível quando possível. Nunca afirmar FPS ou compatibilidade sem medição. Se não for possível fazer teste visual ou de desempenho, declarar a lacuna e fornecer protocolo manual de verificação.
- Ao encerrar cada incremento: indicar arquivos alterados, decisões técnicas e justificativa, comandos/testes executados e resultados, limites, bugs conhecidos e o próximo pequeno incremento proposto. Interromper para revisão antes de expandir escopo.
