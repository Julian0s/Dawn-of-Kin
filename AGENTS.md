# Dawn of Kin — regras permanentes de engenharia para o Antigravity

## Fonte de verdade e escopo
- Ler `Dawn_of_Kin_GDD_v1.0.md` antes de propor qualquer alteração. Respeitar os marcadores **DECIDIDO**, **PROPOSTA** e **ABERTO**; não converter hipóteses em funcionalidades obrigatórias.
- Projeto: jogo single-player em Godot 4.x/GDScript, RTS isométrico 3D.
- Estado atual do projeto: **T1 — Fundação RTS CONCLUÍDA** (marcada com tag Git `t1-complete` no commit `2808799`). A fase **T2 — Trabalho e Recursos** concluiu a preparação técnica até **T2.6** (ainda não aprovada definitivamente nem encerrada sem o aceite manual final): **T2.0–T2.5.1** implementadas, testadas automaticamente e aprovadas em testes manuais parciais; **T2.6** implementada com validação global, correções de corrida em teste/navegação, executor segmentado (`.\tools\run_tests.ps1 -Segmented`), benchmark representativo (`tests/perf/t2_perf_benchmark.gd`) e protocolo `docs/testing/T2_manual_test_protocol.md`. A suíte automatizada completa em processo único excede `240 s` (~`251 s` por simulação real em headless 60 Hz; usar `-Segmented` para cobertura disjunta completa). Nos benchmarks em bateria (`Equilibrado`, Intel UHD Graphics 620, `1920x1080`), tanto T1 quanto T2 marcaram `0` quadros `> 100 ms`, mas excederam `p95 <= 16,7 ms` (`35,435 ms` T1 vs `33,766 ms` T2). Aguardando execução manual final de `T2_manual_test_protocol.md`; não implementar código de etapas futuras (`T3` a `T8`) sem autorização específica prévia do usuário.
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
