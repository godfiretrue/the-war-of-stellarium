# The Final War of Stellarium — Relatório Técnico

**Norma de referência:** DOC.ETPC.028, Edição 2024/2025, Revisão 00 (13 de setembro de 2024)
**Versão do relatório:** 2.0 · **Atualizado:** 27 de novembro de 2026 · **Estado do projeto:** MVP e Fase 1.5 concluídos

---

## Capa e folha de rosto

Os elementos de identificação abaixo devem ser transferidos para a capa e para a folha de rosto quando o relatório for formatado em processador de texto, pela ordem prescrita pela norma:

| Elemento | Conteúdo |
|---|---|
| Escola / curso | Escola Técnico-Profissional de Cantanhede / `[curso a indicar]` |
| Título | The Final War of Stellarium — Relatório Técnico |
| Autor(es) | `[nome, ano, turma e número do(s) aluno(s)]` |
| Tipo de trabalho | Trabalho de Prova de Aptidão Profissional (PAP) / `[disciplina e orientador]` |
| Local e data | Cantanhede, `[ano letivo]` |

A capa deve conter o logótipo da escola e pode incluir uma imagem relacionada com o tema; a folha de rosto não deve conter imagens. Os agradecimentos e a epígrafe, quando incluídos, ocupam folhas separadas antes do índice.

---

## Índice

1. Introdução
2. Desenvolvimento
   1. Âmbito e stack tecnológico
   2. Arquitetura
   3. Geração procedural do mapa
   4. Resolução de turnos
   5. Combate, unidades e economia
   6. Adversário
   7. Interface
   8. Persistência e localização
   9. Verificação e equilíbrio
3. Conclusão
4. Bibliografia
5. Anexos

> Nota: em Word, o índice deve ser gerado automaticamente a partir dos estilos de título (Título 1, Título 2, Título 3) e atualizado em último lugar, antes da entrega. Os índices de quadros e figuras iniciam uma nova página e são também indicados no índice geral.

### Índice de quadros

- Quadro 1 — Stack tecnológico
- Quadro 2 — Fórmula de combate
- Quadro 3 — Regras de atrito
- Quadro 4 — Resultados de equilíbrio por configuração

---

## Introdução

O desenvolvimento de um jogo de estratégia por turnos coloca problemas de engenharia que não se resolvem apenas com regras de jogo: é necessário garantir que o estado da partida é reproduzível, que a inteligência artificial não dispõe de vantagens sobre o jogador e que o sistema pode ser medido sem depender da interface gráfica. *The Final War of Stellarium* foi construído sobre três decisões estruturantes — um modelo de dados sem referências à apresentação, uma resolução simultânea determinística baseada em snapshot e um conjunto de regras de atrito calibradas por simulação headless. O interesse do tema reside precisamente na tensão entre a complexidade das decisões de campanha e a simplicidade da implementação que as suporta.

O trabalho insere-se no âmbito da Prova de Aptidão Profissional, com um protótipo jogável em Godot e GDScript. Como enquadramento, o projeto adota a distinção entre o valor executado pelo código e o valor descrito no lore, tratando o primeiro como verdade operacional. O simulador de equilíbrio funciona como método de verificação: cada regra é introduzida sobre o mesmo conjunto de sementes, de modo a isolar o seu efeito.

Os objetivos deste relatório são: **caracterizar** a arquitetura e o estado de implementação do protótipo; **analisar** as decisões de geração procedural, resolução de turnos, combate e inteligência artificial; **avaliar** o equilíbrio obtido a partir de medições headless; e **identificar** as limitações técnicas que permanecem em aberto. As questões que orientam o trabalho são: de que modo a separação entre dados e interface permite a simulação completa de partidas; que mecanismos garantem a simultaneidade sem vantagem de facção; e que efeito tiveram as regras de atrito na distribuição de vitórias. As respostas são retomadas na Conclusão.

Quanto ao método, o relatório é um estudo de caso de um protótipo de software, baseado na análise do código, da documentação de funcionalidades e dos resultados dos scripts de verificação. O trabalho divide-se em nove secções de desenvolvimento, seguidas da conclusão, da bibliografia e de um anexo com os comandos de verificação.

---

## Desenvolvimento

### 1. Âmbito e stack tecnológico

**Quadro 1 — Stack tecnológico**

| Item | Valor |
|---|---|
| Motor | Godot 4.7.2-stable |
| Linguagem | GDScript, com tipagem estática |
| IA | LimboAI v1.8.1 (GDExtension) |
| Plataforma | PC desktop, escala 16:9 fixa de 1152×648 |
| Input | Teclado, rato e gamepad (vizinhos de foco) |
| Distribuição | PAP; exportação ainda por configurar |

O jogo cobre o MVP e a Fase 1.5. Heróis, feitiços, moral, diplomacia, leis, eventos de Apocalipse e a facção dos Ratos permanecem documentados no lore, mas fora do âmbito de implementação.

### 2. Arquitetura

#### 2.1 Separação entre estado e apresentação

`GameState` (`scripts/core/game_state.gd`) é a única fonte de verdade do mapa, dos estoques e das ordens. Não detém referências a nós da cena e todos os seus dados são identificadores e valores numéricos. Esta propriedade permite executar campanhas completas em modo headless, sem interface gráfica: o bot e o simulador utilizam exatamente a mesma API de enfileiramento de ordens que o jogador.

Os recursos de dados (`ProvinceData`, `UnitType`, `MapState`) seguem a mesma regra e nunca guardam referências a nós. `MapView` limita-se a renderizar e a converter cliques; `GameHUD` converte a interação do utilizador em ordens; a mutação de proprietários e guarnições ocorre exclusivamente em `GameState.resolve_turn()`.

#### 2.2 Máquina de fases

`TurnManager` (autoload) possui a máquina de estados e emite sinais, sem invocar diretamente o bot ou o HUD:

```
PLAYER_PLANNING → BOT_PLANNING → RESOLUTION → NEXT_TURN → PLAYER_PLANNING
```

O bot sinaliza o fim do seu planeamento com `finish_bot_planning()`, após o qual a resolução é executada. Esta separação reduz o ciclo headless a uma sequência de `bot.play_turn()` e duas chamadas ao gestor de turnos.

#### 2.3 Convenções transversais

- Todas as constantes de afinação residem em `scripts/data/balance.gd`.
- Todo o texto visível passa por `Loc`, com chave obrigatória nas tabelas `pt` e `en`; os valores de dados permanecem em inglês até ao momento da apresentação.
- `Settings` é o único escritor de `user://settings.cfg`; `SaveSystem` é o único escritor de `user://savegame.json`.
- A aleatoriedade é derivada da semente; os destinos das ordens são baralhados por semente, nunca por ordem de facção.
- Nenhum sistema lê a defesa de uma província alheia sem passar por `GameState.visible_troops()` / `visible_defense_power()`.
- `UiStyle` centraliza paleta, escalas de fonte e estilos; `UiIcon` fornece os glifos, evitando dependência de cobertura de emoji.

### 3. Geração procedural do mapa

`MapFactory.create_default_map(seed)` delega em `WorldGenerator.build(seed)` e produz um `MapState` completo. Todo o estado do mundo — terrenos, rios, fronteiras, nomes, cidades e proprietários iniciais — deriva da semente, pelo que uma gravação necessita de guardar apenas essa semente e os parâmetros da partida.

A grelha é de 288×162 células de 4 px sobre um mundo fixo de 1152×648. O pipeline é executado na seguinte ordem:

1. **Campos**: massa terrestre em elipse rodada com jitter de centro, proporção, baías e península opcional; cadeias montanhosas geradas por segmentos afunilados, nunca por manchas radiais; humidade com sombra de chuva a jusante da cadeia principal.
2. **Continuidade**: remoção de ilhas desligadas e garantia de piso terrestre sob as seis âncoras.
3. **Rios**: preenchimento de depressões com um epsilon incremental que preserva o gradiente; cálculo de drenagem pelo declive mais acentuado; conversão das células com drenagem suficiente em polilinhas suavizadas com largura proporcional ao volume acumulado.
4. **Províncias**: seis âncoras fixas — duas capitais (também fortalezas), três fortalezas adicionais e uma vila ribeirinha — e crescimento das restantes por BFS multi-fonte com semente, com repetição até o grafo ficar ligado.
5. **Classificação**: montanha > costa > floresta > planície, seguida de atribuição de nomes, cidades, proprietários, polígonos e da imagem de campos consumida pelo shader.

O mapa resultante possui 21 províncias, das quais dez cidades e fortalezas em escala 1×; o restante são ermos. Estes não produzem, não levantam milícia e não são palco de batalhas entre exércitos em trânsito: o seu proprietário é inferido da cidade de influência mais próxima. Foram acrescentadas as Terras Altas (quinto bioma, defesa ×1,5) e até seis picos intransponíveis, removidos do grafo e ignorados pelas condições de vitória.

O script `worldgen_sweep.gd` verifica 24 sementes em três escalas e aborta com código de erro se qualquer invariante falhar: contagem de províncias e cidades, presença e tipo das seis âncoras, conectividade, polígonos não vazios, rios mínimos, pelo menos três províncias por facção e ausência de milícia nos ermos.

### 4. Resolução de turnos

Ambas as facções planeiam sem observar o adversário e nenhuma ação de planeamento altera o tabuleiro: `queue_move()`, `queue_recruit()` e `queue_ambush()` apenas registam ordens, com validação e reserva de recursos no momento do enfileiramento. A resolução executa-se sobre uma fotografia do estado anterior a qualquer ordem:

1. Os reforços recrutados juntam-se à guarnição da sua província e defendem, mas não marcham, porque as ordens de movimento foram validadas antes da sua existência.
2. Todos os exércitos partem simultaneamente; o que fica na origem é a única defesa dessa província.
3. Os destinos são processados por uma ordem baralhada com a semente, eliminando a vantagem de quem atua primeiro.
4. A defesa é a guarnição da fotografia mais a milícia e os reforços chegados no mesmo turno.
5. Os sobreviventes regressam à origem apenas se a sua facção ainda a possuir depois de todas as capturas.

Casos especiais tratados explicitamente: troca de províncias entre dois exércitos, chegada simultânea a uma cidade sem defesa (batalha em campo num terreno temporário de planície) e captura da origem de um exército em marcha. Como a resolução depende apenas da semente, do número do turno e das ordens enfileiradas, a repetição de uma partida produz resultados idênticos. Este determinismo é a base de toda a medição de equilíbrio.

A ordem de precedência na verificação do fim de jogo é: eliminação, conquista total de cidades, sequência de domínio e desempate por guerra longa. A vitória dinâmica exige 70% das cidades durante três resoluções consecutivas; após 150 resoluções sem qualquer mudança de proprietário em cidades, vence quem tiver mais cidades, com o efetivo total como desempate.

### 5. Combate, unidades e economia

#### 5.1 Fórmula de combate

**Quadro 2 — Fórmula de combate**

| Grandeza | Cálculo |
|---|---|
| Ataque | Σ(ataque da unidade × contagem) |
| Defesa | (Σ(defesa da unidade × contagem) + milícia × 4) × multiplicador de terreno (+0,25 em fortaleza) |
| Multiplicadores | Planície 1,0 · Floresta 1,15 · Costa 1,0 · Montanha 1,35 · Terras Altas 1,5 |
| Fator aleatório | 0,9–1,1, controlado pela semente |
| Rácio | ataque / (ataque + defesa) |
| Baixas | atacante: `ceil(tropas × (1 − rácio) × 0,7)`; defensor: `ceil(tropas × rácio × 1,0)` |

As baixas incidem primeiro sobre a milícia e depois sobre a guarnição, uma tropa de cada vez por ordem estável de unidade. O catálogo contém doze unidades, seis por facção, organizadas em cinco funções (infantaria, arco, cavalaria, anti-cavalaria e armadura) mais cerco. Existe um ciclo de contra-ataques entre funções (+25% proporcionais à guarnição inimiga contra-atacada) e as unidades de cerco reduzem o bónus de fortaleza de +0,25 para +0,15, além de +25% de ataque em fortalezas e Terras Altas. A previsão de batalha calcula três cenários com a mesma fórmula, sem consumir aleatoriedade e sem revelar guarnições ocultas pela névoa.

#### 5.2 Economia e regras de atrito

As cidades e fortalezas geram ouro, manpower e recurso de facção; os exércitos consomem manutenção segundo `ceil(custo_médio / 15 × tropas^1,2)`. Os Humanos pagam 0,54× o custo de recrutamento e os Elfos recebem 1,15× de ouro e manpower. Para evitar que uma vantagem inicial decida a campanha, foram introduzidas as seguintes regras:

**Quadro 3 — Regras de atrito**

| Regra | Parâmetros | Efeito |
|---|---|---|
| Milícia local | máx. 2 por cidade, 4 na capital; regeneração 1/turno; defesa 4 | Defende sem marchar, sem manutenção e sem produção |
| Agitação pós-conquista | 2 resoluções | Sem rendimento e sem recrutamento |
| Penalização da perda da capital | 3 turnos | +30% no custo de recrutamento, −25% de rendimento |
| Doutrina de guarnição | 1 tropa no interior, 2 na fronteira, 3 na capital; tudo após estagnação | O bot deixa retaguarda ao avançar e compromete o efetivo quando a frente congela |
| Névoa e emboscada | visão de 1 província; defesa ×1,5; baixas do atacante ×1,25 | Inteligência limitada e guarnições ocultas que emboscam ao entrar |

A penalização da capital é mantida como regra de equidade, não como alavanca de equilíbrio: foi medido que não altera resultados no conjunto de sementes testado.

### 6. Adversário

A decisão do bot é orquestrada por uma árvore de comportamento do LimboAI construída em código, com três folhas GDScript (`BTRecruitTask`, `BTAttackTask`, `BTAdvanceTask`). A lógica de decisão propriamente dita reside em `BotController`, para evitar dependências circulares entre classes. A estrutura é deliberadamente pequena — recrutar, atacar e avançar — e ambas as folhas de ataque e avanço correm em cada turno. Numa versão anterior, um seletor exclusivo fazia com que uma única batalha disponível bloqueasse toda a expansão, gerando frentes congeladas e sementes sem fim. A correção consistiu em priorizar o ataque sobre o avanço e, após um número configurável de turnos sem batalha, atacar sem considerar as probabilidades.

O bot partilha com o jogador a validação, os custos e o filtro de visibilidade. A personalidade varia por facção: os Humanos privilegiam cavalaria e recorrem a uma emboscada por partida, enquanto os Elfos valorizam terreno fortificado, preferem tropas à distância e emboscam com maior frequência. O painel de novo jogo permite escolher a dificuldade, que ajusta o kit inicial do jogador e os limites de recrutamento e ataque do bot; `Normal` é a referência das medições.

### 7. Interface

A interface de campanha segue um padrão visual semelhante a Total War, com:

- barra superior com facção, recursos (com tooltips de rendimento e manutenção), número do turno, fase e menu (Guardar, Opções, Menu);
- gaveta de província na parte inferior com dados, cartões de unidade e ações de Recrutar e Marchar, com motivos de indisponibilidade nos tooltips;
- fila de ordens recolhível na margem esquerda, com uma linha por ordem, cancelamento individual e realce do destino no mapa;
- setas e distintivos desenhados no próprio mapa, com realce de vizinhos válidos no modo marcha e pré-visualização de batalha;
- relatório de batalha com uma linha por combate e foco de câmara temporário na província disputada;
- sobreposição de vitória/derrota e indicador de progresso da vitória dinâmica.

O mapa é composto por uma camada de terreno renderizada por shader, uma vista por província, um overlay vetorial de rios e ordens e uma camada de névoa. A conversão de cliques utiliza a mesma grelha que definiu as fronteiras, garantindo correspondência entre o ponto visível e a província selecionada. A ordem de desenho coloca as províncias selecionadas no nível 3, o overlay de ordens no 4 e os rótulos no 5. Os atalhos de teclado são processados no HUD e a navegação por gamepad é suportada por vizinhos de foco em ciclo, sem perder os atalhos quando um botão está focado.

### 8. Persistência e localização

`SaveSystem` grava `user://savegame.json` de forma atómica, através de um ficheiro temporário seguido de renomeação. A versão atual é a 9 e o conteúdo inclui semente, tamanho do mundo, dificuldade, estoques e proprietários das cidades. Os proprietários dos ermos são reconstruídos a partir da cidade de influência no carregamento. As versões 6 e anteriores são rejeitadas por incompatibilidade de identificadores gerados; a versão 8 é migrada com sequência de domínio a zero e dificuldade Normal. O auto-save ocorre no início do turno com a fila vazia, e o guardar manual é recusado enquanto existirem ordens pendentes.

A localização é integral em português e inglês e pode ser alterada a meio da partida a partir do painel de definições, também persistente entre sessões. Os ecrãs abertos reconstróem os seus textos em resposta ao sinal `changed`, sem recarregar a cena.

### 9. Verificação e equilíbrio

Quatro scripts headless compõem a suíte de verificação (ver Anexo A). O `balance_sim.gd` executa partidas bot contra bot através da API real do jogo, contabilizando falhas de fila, jogos por terminar e duração. Cada linha do quadro seguinte corresponde a uma execução completa sobre o mesmo conjunto de sementes, de modo a isolar o efeito de uma única regra.

**Quadro 4 — Resultados de equilíbrio por configuração**

| Configuração | Resultado |
|---|---|
| Base, sem regras de atrito | Elfos 19 / Humanos 1; 57,1 turnos |
| + milícia local | Elfos 15 / Humanos 5; 100,5 turnos |
| + penalização da capital | Idêntico à linha anterior |
| + agitação pós-conquista | Humanos 11 / Elfos 9; 52,4 turnos |
| + doutrina de guarnição (versão final em 20 sementes) | Humanos 9 / Elfos 11; 116,8 turnos |
| + economia de terreno e fortalezas (v0.5) | Humanos 9 / Elfos 11; 76,0 turnos |
| + Terras Altas, picos, névoa e emboscada (v0.7) | Humanos 13 / Elfos 7; 74,8 turnos |
| + ermos, economia de cidade e vitória dinâmica | Humanos 9 / Elfos 11; 87,3 turnos |
| **Referência atual, 60 sementes (`41000..41059`)** | **52% Humanos / 48% Elfos; todos terminados, sem falhas de fila** |

A milícia reduziu a taxa de vitória do lado dominante de 95% para 75% e quase duplicou a duração das guerras; a agitação de conquista foi a alavanca isolada mais forte, ao quebrar o ciclo "capturar cidade, recrutar no turno seguinte". A doutrina de guarnição revelou-se a mais volátil: reter tropas no ataque favorecia o lado mais rico e produzia impasses prolongados, enquanto comprometer todas as tropas favorecia o lado com recrutamento mais barato. A economia não é monotónica — aumentar o rendimento dos Elfos não aumenta necessariamente as suas vitórias, porque a escolha de unidades do bot depende do ouro disponível — pelo que qualquer ajuste deve ser reavaliado com o simulador e não por multiplicadores isolados.

---

## Conclusão

A separação entre o modelo de dados e a interface confirmou-se como a decisão com maior impacto no projeto: foi ela que permitiu executar campanhas completas sem janela gráfica e, por consequência, medir o equilíbrio com um simulador que usa a mesma API de ordens do jogador. A resolução simultânea por snapshot, com destinos baralhados por semente, respondeu à segunda questão: nenhum botão altera o tabuleiro durante o planeamento e nenhuma facção atua primeiro. A terceira questão tem resposta numérica — a introdução progressiva do atrito levou o protótipo de uma dominância de 95/5 para uma referência de 52% Humanos / 48% Elfos em 60 sementes, com todas as partidas terminadas e sem falhas de fila.

A avaliação global do trabalho é positiva no que respeita à coerência arquitetural e à disciplina de medição. Os pontos fortes concentram-se na reprodutibilidade, na simetria de regras entre jogador e bot e na existência de uma suíte headless que deteta regressões na geração e no carregamento. As dificuldades surgiram sobretudo na geração procedural — rios em espiral, ilhas desligadas e províncias alongadas — e na calibração da doutrina de guarnição, onde uma alteração pequena podia produzir impasses de centenas de turnos. A conclusão prática é que a afinação deve continuar a ser feita com o simulador e com o mesmo conjunto de sementes, nunca por multiplicadores isolados.

Permanecem em aberto a árvore de comportamento em código, a pixelação do planeta do menu, a configuração da exportação e a necessidade de uma amostra de sementes mais larga antes de novas alterações de números. Estes pontos não invalidam o estado jogável do protótipo, mas condicionam a sua apresentação final e a confiança estatística do equilíbrio medido.

---

## Bibliografia

A norma DOC.ETPC.028 recomenda a Norma Portuguesa NP 405 para documentos impressos e eletrónicos, admitindo a norma APA desde que não se misturem referências de ambas no mesmo trabalho. Segue NP 405, aplicada às fontes internas do projeto (consultadas a 27 de novembro de 2026):

- THE FINAL WAR OF STELLARIUM — *AI_CONTEXT: arquitetura, convenções e armadilhas*. [Em linha]. Disponível em: `AI_CONTEXT.md`.
- THE FINAL WAR OF STELLARIUM — *Arquitetura*. [Em linha]. Disponível em: `docs/ARCHITECTURE.md`.
- THE FINAL WAR OF STELLARIUM — *Documento de Design de Jogo*. [Em linha]. Disponível em: `docs/GDD.md`.
- THE FINAL WAR OF STELLARIUM — *Lore*. [Em linha]. Disponível em: `docs/LORE.md`.
- THE FINAL WAR OF STELLARIUM — *Combate e unidades*. [Em linha]. Disponível em: `docs/features/combat-and-units/design.md`.
- THE FINAL WAR OF STELLARIUM — *Mapa e províncias*. [Em linha]. Disponível em: `docs/features/map-and-provinces/design.md`.
- THE FINAL WAR OF STELLARIUM — *Névoa de guerra e emboscadas*. [Em linha]. Disponível em: `docs/features/fog-and-ambush/design.md`.
- THE FINAL WAR OF STELLARIUM — *Resolução de turnos*. [Em linha]. Disponível em: `docs/features/turn-resolution/design.md`.
- THE FINAL WAR OF STELLARIUM — *Vitória dinâmica*. [Em linha]. Disponível em: `docs/features/dynamic-victory/design.md`.

> Se forem acrescentadas citações de autores externos, devem ser referenciadas no corpo do texto entre parêntesis — por exemplo `(Silva, 1985: 145)` — e incluídas nesta lista por ordem alfabética do apelido.

---

## Anexos

### Anexo A — Comandos de verificação headless

```bash
godot --headless --path . --script res://scripts/tools/worldgen_sweep.gd
godot --headless --path . --script res://scripts/tools/balance_sim.gd -- 20
godot --headless --path . --script res://scripts/tools/loader_check.gd
godot --headless --path . --script res://scripts/tools/loader_continue_check.gd
```

O `worldgen_sweep.gd` verifica invariantes de geração; o `balance_sim.gd` corre 20 partidas bot contra bot, com 60 sementes na janela de referência atual; os dois scripts `loader` testam Novo Jogo e Continuar a partir do menu principal.

---

## Nota de formatação para entrega (DOC.ETPC.028)

A presente versão em Markdown preserva o conteúdo e a estrutura exigidos. Ao converter para processador de texto, aplicar:

- **Formato:** A4, folhas brancas e lisas, texto a preto, sem rasuras ou corretor; cada capítulo começa numa nova página; trabalho encadernado ou em dossiê quando entregue em papel.
- **Margens:** 2,5 cm em cima, em baixo e à direita; 3,5 cm à esquerda (zona de encadernação). Em folhas na horizontal: 2,5 cm à esquerda, à direita e em baixo; 3,5 cm em cima.
- **Tipo de letra:** Times New Roman, Arial, Cambria ou Calibri; corpo 11; títulos e subtítulos 13; notas de rodapé e conteúdo de quadros/tabelas 9.
- **Parágrafo:** espaçamento entre linhas 1,5; avanço de 1 linha no início de cada parágrafo; alinhamento justificado no texto corrido. No interior de quadros e tabelas usar espaçamento 1 ou 1,15.
- **Paginação:** iniciar a numeração na Introdução; as páginas anteriores são contadas mas não numeradas; em trabalhos de PAP, a numeração é romana antes da Introdução e árabe a partir dela; número no rodapé, inferior direito ou centro inferior.
- **Objetos:** todo o quadro, figura ou imagem tem legenda com número e título e, quando retirado de outra fonte, indicação da origem.
- **Citações:** transcrições com menos de 40 palavras vão entre aspas no corpo do texto, com indicação da página; transcrições longas são destacadas graficamente, sem aspas, com fonte e página; citações bibliográficas seguem sempre uma única norma (NP 405 neste documento).
