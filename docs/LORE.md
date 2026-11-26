# Game Design Document (GDD): The Final War of Stellarium (PAP TGPSI)

## 1. Visão Geral & Inspirações
- **Título Oficial:** *The Final War of Stellarium*
- **Contexto:** Projeto oficial de Prova de Aptidão Profissional (PAP) — Curso Técnico de Gestão e Programação de Sistemas Informáticos (TGPSI), ETPC.
- **Género:** Jogo 2D de Estratégia por Turnos com temática de fantasia medieval.
- **Estilo Visual & Técnico:** 2D leve e funcional, viável para desenvolvimento a solo dentro dos prazos da PAP, priorizando a lógica e a programação sobre a complexidade gráfica.
- **Principais Inspirações:**
  - *Conquest of Elysium 5*: Mundo dinâmico e vivo, eventos sistémicos e lore emergente.
  - *Total War: Warhammer 3*: Comando de exércitos, diplomacia e geopolítica de fantasia.

### 1.1. Divisão Estrutural do Desenvolvimento & Estado Atual (Enquadramento da PAP)
Para assegurar a viabilidade técnica e o cumprimento rigoroso dos prazos da PAP (em conformidade com o parecer do orientador), o desenvolvimento divide-se em patamares claros de entrega:

* **Fase 1: MVP Funcional Concluído (Base Sólida em Godot 4.7.2):**
  1. **Mapa Procedural com Shader:** Geração procedural de 21 províncias conectadas com relevo e biomas via `terrain.gdshader`.
  2. **Turnos Simultâneos & Resolução por Snapshot:** O jogador e o bot planeiam em simultâneo sem vantagens de primeiro movimento; a resolução de batalhas ocorre com destinos baralhados por seed.
  3. **Mecânicas Anti-Snowball:**
     - *Home Guard (Milícia Defensiva):* 1 a 2 tropas de milícia que defendem sem custo de manutenção e regeneram passivamente (até 4 nas capitais).
     - *Conquest Unrest:* Províncias recém-conquistadas passam 2 turnos sem gerar ouro, manpower ou recrutar.
     - *Penalidade de Perda de Capital:* Perder a capital aplica penalidade temporária (+30% recrutamento, -25% rendimento por 3 turnos) em vez de derrota imediata.
     - *Doutrina de Guarnição:* Sistema de separação de tropas ao marchar (`SpinBox` para o jogador; regras escalonadas para o bot).
  4. **IA com Behaviour Trees (LimboAI v1.8.1):** Bot orientado a tarefas com sequência de recrutamento, ataque e avanço territorial.
  5. **HUD de Campanha Total War:** Barra superior com recursos e tooltips dinâmicos, dock inferior de província, gaveta retrátil de ordens com setas vetoriais no mapa e relatório pós-batalha com foco de câmara.
  6. **Persistência & Localização:** Save/Load atómico em JSON (com auto-save) e suporte bilingue instantâneo (PT/EN) em runtime.
  7. **Calibração Headless:** Ferramenta de simulação automática (`balance_sim.gd`) com 60 sementes fixas e nenhuma facção acima de ~55% de vitórias.

* **Fase 1.5: Aprofundamento Tático Imediato (Concluído):**
  1. **Tipos de Província & Terrenos Diversificados:** Províncias com vantagens táticas e rendimentos diferenciados (montanhas defensivas, portos fluviais/costeiros ricos em ouro, planícies agrícolas com elevado manpower, florestas e fortalezas).
  2. **Roster Militar Especializado & Cerco:** Inclusão de unidades de choque, longo alcance e unidades pesadas de **Cerco** (catapultas arcanas e obuses móveis) com bónus de assalto a cidades fortificadas.
  3. **Menu de Previsão de Batalha (Estilo Total War):** Painel de rácio de poder (*Power Ratio*), estimativa de baixas e visualização de modificadores de terreno antes da confirmação da ordem de ataque.
  4. **Personalidade de IA por Fação:** Especialização da árvore de decisão no LimboAI (doutrina militar agressiva e tecnológica dos Elfos vs resiliência e recrutamento rápido dos Humanos).
  5. **Midgame & Condições de Vitória Dinâmicas:** Manter 70% das províncias transitáveis por três resoluções consecutivas vence a guerra; a conquista total continua a vencer de imediato e a eliminação continua a ser derrota.

* **Fase 2: Visão de Expansão (Backlog Pós-Aprofundamento):**
  - Batalhas táticas em tempo real numa grelha detalhada, heróis com magias ativas no campo, colapso de moral dinâmico e deserção, sistema diplomático com índice de credibilidade, decretos políticos e a 3ª fação (Ratos - Enxame Tóxico).

---

## 2. Estrutura de Jogo & Fluxo de Combate

### A. Mapa-Mundo & Turnos Simultâneos
- **Planeamento Simultâneo:** Em cada turno, o jogador e os bots planeiam e colocam ordens numa fila (`Order Queue`) sem conhecerem as jogadas do adversário.
- **Ciclo de Fases:** `PLAYER_PLANNING` -> `BOT_PLANNING` -> `RESOLUTION` -> `NEXT_TURN`.
- **Resolução Neutra por Snapshot:** Ao terminar o planeamento, o motor congela um *snapshot* do tabuleiro:
  1. Recrutamentos entram primeiro na guarnição e defendem de imediato (mas não podem marchar no mesmo turno).
  2. Todos os exércitos partem da sua origem em simultâneo; o contingente não destacado permanece como guarnição defensiva.
  3. Os combates são resolvidos numa ordem aleatória de destinos gerada pela seed, eliminando qualquer vantagem de primeiro atacante.
- **Doutrina de Guarnição & Separação de Tropas:** Ao emitir uma ordem de marcha, o jogador escolhe exatamente quantos soldados destacar via selector numérico (`SpinBox`), assegurando que a província de origem não fica indefesa. O bot segue diretrizes escalonadas baseadas na proximidade da linha da frente (`Balance.GARRISON_*`).

### B. Interface Tática & Previsão de Batalha (Estilo Total War)
- **Menu Pré-Batalha (Combat Prediction / Power Ratio):** Ao selecionar um destino inimigo ou antes do embate ser resolvido, o jogo apresenta uma janela de estimativa tática contendo:
  - **Barra de Balanço de Poder (*Power Ratio*):** Comparação visual da força relativa dos dois exércitos (`att / (att + def)`).
  - **Modificadores de Terreno Visíveis:** Indicação clara de penalidades/vantagens (ex: defensores em montanhas recebem +25% de poder defensivo; penalidades de cavalaria em florestas/fortalezas).
  - **Estimativa de Baixas:** Previsão de perdas prováveis para o atacante e defensor, permitindo ao jogador recuar ou alterar ordens antes de confirmar.
- **Relatório Pós-Batalha com Foco de Câmara:** Conclusão de cada embate com resumo das baixas de tropas regulares e milícia, permitindo focar a câmara no território disputado.

### C. Resolução Numérica vs Encontros Táticos em Tempo Real
- **Resolução Numérica (Fase Atual):** Cálculo matemático rigoroso (`CombatResolver`) que pondera ataque, defesa, bónus de relevo/terreno, absorção prioritária da milícia (*Home Guard*) e fator aleatório controlado (0.9 a 1.1) para evitar determinismo estéril.
- **Batalhas Manuais 1v1 (Fase de Expansão):** Instância tática com grelha detalhada, permitindo comando direto de flanqueamento, timing de disparos e manobras em tempo real.

### D. Heróis & Sistema de Moral
- **Liderança Obrigatória:** Todo o exército requer um **Herói** (figura poderosa da mesma espécie) para existir e marchar.
- **Pilar Moral:** O herói ancora a determinação das tropas. Se a moral colapsar sob pressão, baixas ou morte do líder, os soldados entram em pânico, debandam e desertam em pleno combate.

### E. Mecânicas Simétricas (Fair Play)
- Bots e nações controladas pelo computador utilizam exatamente a mesma API pública de ordens (`queue_move`, `queue_recruit`), pagam os mesmos custos de ouro e manpower, e sofrem as mesmas restrições de guarnição e manutenção que o jogador humano.

---

## 3. O Fim do Mundo (O Apocalipse Dinâmico)
- **Não é um temporizador passivo:** O apocalipse é a consequência direta das ações, avanços e rituais de certas raças do mundo.
- **Avisos Globais:** À medida que essas raças progridem nas suas agendas destrutivas, são emitidos avisos/anúncios mundiais a alertar para o fim que se aproxima.
- **Ameaça Externa:** O jogador não tem acesso direto a desencadear esse fim; o seu desafio é navegar diplomaticamente, expandir o seu poder e preparar-se militarmente para sobreviver ao cataclismo anunciado.

---

## 4. Raças & Regimes Políticos Iniciais

### 1. Humanos — A Democracia Medieval (e o Poder Presidencial de Guerra)
- **Regime:** Democracia representativa / conselho popular em plena estética medieval.
- **Origem do Regime:** O avanço da **magia de comunicação** encurtou distâncias continentais, permitindo a circulação instantânea de votos, notícias e assembleias entre cidades e feudos.
- **Poderes de Guerra (Mecânica Política):** Em tempos de paz, o parlamento/conselho debate as decisões; mas em **tempo de guerra, apenas o Presidente tem autoridade direta para decretar e passar leis**, eliminando a lentidão burocrática para responder às ameaças externas.

### 2. Elfos — A Ditadura Tecnológica (A Queda da Árvore da Vida)
- **Regime:** Ditadura militar e industrial autoritária.
- **A Queda da Magia Ancestral:** A outrora sagrada **Árvore da Vida** dos elfos foi mortalmente corrompida e envenenada pela poluição dos Ratos. Com a morte da árvore, a fonte primária de magia élfica secou.
- **A Viragem Tecnológica:** Desprovidos da sua magia e movidos por um ódio existencial, os elfos abraçaram a ciência mecânica, o vapor/energia e a **tecnologia bélica avançada**, centralizando a sociedade numa ditadura implacável focada na vingança e sobrevivência.

### 3. Ratos — Nobreza Tóxica e a Maldição Élfica
- **Regime:** Oligarquia / Aristocracia de "Ratos Nobres".
- **A Origem da Infertilidade (O Último Feitiço Élfico):** A catástrofe que condenou os ratos à extinção foi o **último grande feitiço dos elfos**, conjurado com as últimas gotas de mana da Árvore da Vida moribunda como retaliação. A maldição tornou a espécie inteira biologicamente infértil.
- **Sobrevivência por Conversão:** Para não se extinguirem, os ratos usam a sua **poluição extrema e mutagénios químicos** para converter prisioneiros de outras espécies em novos ratos.
- **A Casta Nobre Original:** Os ratos que nasceram antes da maldição (ou de linhagens puras iniciais) preservam a sua longevidade através de incubação em poluição densa e **engenharia genética** constante.

---

## 5. Habilidades & Mecânicas Únicas de Fação

### 1. Humanos (Democracia Medieval Mágica)
- **++ Magias nos Heróis:** Como a sociedade humana se especializou profundamente na magia, os seus Heróis possuem um leque mais vasto, versátil e potente de feitiços de suporte, dano e controlo de campo de batalha.
- **Recrutamento Rápido:** A rede de comunicações mágicas e a adesão cívica da democracia permitem mobilizar e treinar tropas em muito menos tempo do que os seus rivais.

### 2. Elfos (Ditadura Tecnológica)
- **++ Ouro (Eficiência Económica):** A sua infraestrutura tecnológica e controlo estatal ditatorial geram receitas de ouro significativamente superiores.
- **++ Manpower (Reserva Militar Fabril):** Automatização, disciplina de ferro e logística avançada garantem uma reserva massiva de mão de obra e capacidade de reposição de exércitos.

### 3. Ratos (Enxame Tóxico & Sociedades Subterrâneas)
- **Doutrina de Enxame (Swarm):** Acesso a unidades corpo a corpo muito baratas e fáceis de produzir em massa (fracas individualmente, mas esmagadoras em número para absorver dano e quebrar linhas).
- **Conversão Pós-Batalha:** No final de cada combate, uma percentagem das tropas sobreviventes do exército inimigo é capturada e mutada com poluição, sendo convertida em unidades rato para o jogador.
- **Sociedades Subterrâneas:** Capacidade de criar colónias e postos avançados subterrâneos ocultos por baixo das cidades de outras raças, operando nas sombras para drenar recursos, espalhar poluição ou preparar emboscadas.
- **Fraquezas & Balanceamento (Contra-medidas ao Efeito "Bola de Neve"):**
  - **Moral Frágil (Pânico em Cadeia):** As unidades de enxame têm moral baixíssima. Dano em área (magias humanas ou artilharia élfica) causa baixas rápidas que desencadeiam pânico coletivo e fuga em massa.
  - **Dependência Crítica do Herói:** Sem o Herói como âncora moral, o exército de ratos desmorona com extrema facilidade.
  - **Qualidade das Unidades Convertidas:** Inimigos convertidos tornam-se apenas infantaria básica ("Rato Mutado / Cobaia"), não herdando as estatísticas de elite da unidade original.
  - **Deteção Específica de Subcidades:** As sociedades subterrâneas são invisíveis e **só podem ser descobertas se a fação dona da cidade colocar fisicamente um Herói em cima da cidade** para inspecionar e expurgar a infestação.
  - **Rejeição Diplomática:** Outras fações desconfiam severamente da poluição e da captura de prisioneiros, gerando penalidades diplomáticas naturais.

---

## 6. Rosters de Unidades por Fação

### 6.0. Sistema de Arquétipos & Dinâmica de Cerco (Pedra-Papel-Tesoura)
Para dar profundidade tática e relevância às escolhas de recrutamento, as unidades organizam-se em arquétipos com vantagens mútuas:
1. **Infantaria de Linha (Melee):** Alta defesa e retenção de terreno. Absorve dano e protege retaguardas contra investidas diretas.
2. **Atiradores (Ranged):** Elevado ataque à distância. Dizimam infantaria pesada e frentes estáticas, mas são frágeis se interceptados.
3. **Choque & Flanqueio (Cavalaria / Veículos Ágeis):** Dano de investida devastador contra atiradores e flancos vulneráveis.
4. **Artilharia & Unidades de Cerco (Siege):**
   - **Especialização de Cerco:** Projetadas especificamente para romper capitais fortificadas, castelos e cordilheiras montanhosas. Ignoram ou neutralizam a defesa da milícia (*Home Guard*) e concedem bónus ofensivo maciço contra fortificações.
   - **Desvantagem Tática:** Elevado custo de ouro, alta manutenção e extrema vulnerabilidade quando atacadas em campo aberto sem infantaria de cobertura.

### 1. Humanos (A Democracia Mágica)
- **Sistema de Heróis:**
  - **Nomenclatura Diversificada:** Geração de nomes variados e multiculturais (estilo Estados Unidos), refletindo a diversidade e mobilidade cívica da democracia.
  - **Tiers de Heróis:**
    - *Heróis Padrão:* Oficiais e magos de campo com magias de suporte e comando tático geral.
    - *Heróis Especiais:* Comandantes lendários únicos com feitiços devastadores e bónus de moral superiores.
- **Infantaria de Linha (Corpo a Corpo):**
  - **Espadachins:** Unidade militar padrão, equilibrada, com escudos e boa retenção de linha.
  - **Golems Explosivos:** Constructos mágicos de choque que avançam contra as linhas inimigas e detonam com dano em área catastrófico (seja por comando ou ao morrerem).
- **Longo Alcance (Ranged & Cerco):**
  - **Besteiros:** Disparos perfurantes a média distância.
  - **Mosqueteiros Mágicos:** Infantaria de pólvora infundida com mana, causando alto impacto com projéteis arcanos.
  - **Catapulta Mágica:** Artilharia de longo alcance que lança projéteis encantados com dano explosivo em área.
- **Especialistas, Choque & Aéreo:**
  - **Cavalaria Real de Bestas Mágicas:** Em vez de cavalos normais, montam feras arcanas modificadas com **pedras mágicas alojadas dentro do corpo**, concedendo resistência sobrenatural e impacto de investida devastador.
  - **Wyvern:** Monstro voador de grande mobilidade capaz de sobrevoar as linhas inimigas, focar heróis ou flanquear baterias de artilharia.

---

### 2. Elfos (A Ditadura Tecnológica)
- **Sistema de Heróis (Hiper-Especializados & "Pecadores Eternos"):**
  - **Poucos mas Devastadores:** Devido à extrema especialização e ao foco obsessivo da ditadura, os Elfos têm uma quantidade reduzida de heróis disponíveis, mas cada um possui poder militar, estatísticas de combate e liderança esmagadoras.
  - **O Título "Pecador Eterno":** A maioria dos comandantes e generais carrega este título fúnebre — indivíduos que assumem para sempre a culpa de terem falhado na proteção da Árvore da Vida, dedicando a sua existência imortal a expiar essa falha através da disciplina militar cega e da vitória a qualquer custo.
- **Vanguarda Mecanizada & Construtos Melee:**
  - **Aranhas Mecânicas:** Autómatos ágeis de combate, letais em combate cerrado e capazes de ultrapassar barreiras para cercar e fatiar formações inimigas.
  - **Javalis Mecânicos:** Feras metálicas couraçadas a vapor/diesel que funcionam como aríetes vivos, arrebentando a primeira linha inimiga com blindagem pesada.
- **Longo Alcance & Artilharia Industrial:**
  - **Soldados com Armas de Fogo Modernas:** Em vez de arcos ou mosquetes lentos, empunham espingardas e fuzis de alta cadência e precisão industrial, criando barragens de chumbo impiedosas.
  - **Howitzers Móveis (Obuses de Campanha):** Artilharia pesada móvel que bombardeia posições defensivas a distâncias extremas e pode reposicionar-se durante a batalha.
- **Veículos Blindados & Fé Móvel:**
  - **Igreja da Árvore Sagrada Móvel:** Uma imensa basílica/catedral mecanizada sobre esteiras industriais, transportando relíquias sagradas da Árvore da Vida. Atua como pilar de suporte, amplificador de moral e centro de comando no campo.
  - **Zeppelins (Dirigíveis de Guerra):** Belonaves aéreas blindadas que dominam o espaço aéreo e descarregam bombas sobre o solo.
  - **Tanques & Motos de Combate:** Tanques de ferro maciço para esmagar infantaria e motos de combate ultrarrápidas para missões de flanco, caça a heróis e perseguição.
- **Mecânica Exclusiva: "Última Trincheira da Árvore Sagrada" (Defesa da Capital):**
  - Se qualquer fação invadir ou assediar a **Capital Élfica** (onde repousam os restos da Árvore Sagrada):
    - **Elfos Pecadores (Unidades Suicidas):** Milhares de cidadãos e soldados condenados oferecem-se em ataques suicidas com explosivos industriais.
    - **Moral Inquebrável:** A moral dos defensores **NÃO DESCE** sob circunstância alguma — lutam com fanatismo absoluto até à morte do último soldado, tornando a capital élfica num dos maiores pesadelos militares do jogo.

---

### 3. Ratos (O Enxame Tóxico & Nobreza Mutante)
- **Sistema de Heróis (Nobres Puros vs Abominações Mutantes):**
  - **Nobres Originais:** A maior parte dos heróis pertence à aristocracia dos ratos puros nascidos antes do cataclismo, preservados por poluição e engenharia genética. Focam-se em comando, expansão de colónias e liderança de enxames.
  - **Heróis Mutantes (Abominações):** O jogador/fação pode criar ou transfigurar heróis através de mutagénios extremos, gerando monstros colossais que já não se parecem com ratos. São terrores de combate individual, com dano maciço e habilidades de terror que drenam a moral inimiga.
- **Vanguarda de Enxame & Choque Rápido:**
  - **Escravos (Cobaias Convertidas):** Prisioneiros de guerra capturados de outras raças e mutados à força com poluição. Unidade extremamente barata e descartável, usada para sobrecarregar munição inimiga e proteger as linhas mais valiosas.
  - **Ratos a Javali:** Cavalaria grotesca e violenta com guerreiros ratos montados em javalis de combate, capazes de atropelar flancos e perseguir unidades em fuga.
- **Longo Alcance & Projéteis Químicos:**
  - **Minigunners de Lixo:** Soldados rato que operam metralhadoras rotativas artesanais de alta cadência, disparando rajadas devastadoras de estilhaços de sucata e fragmentos contaminados.
  - **Artilharia Tóxica:** Morteiros e catapultas que arremessam barris de lodo venenoso e gases corrosivos, contaminando grandes áreas do campo de batalha com dano contínuo.
- **Monstros, Infiltração & Unidades Suicidas:**
  - **Hydra Rato:** Monstruosidade titânica com múltiplas cabeças de rato em regeneração constante; causa pânico ao contacto e regenera vida enquanto devora soldados inimigos.
  - **Rato Assassino:** Especialista em furtividade corpo a corpo, capaz de se infiltrar nas linhas traseiras para emboscar e decapitar heróis ou operadores de artilharia inimigos.
  - **Rato Bola Suicida:** Tropas fanatizadas enroladas em esferas metálicas carregadas de químicos que rolam a alta velocidade contra as linhas inimigas, detonando em nuvens de contaminação e estilhaços.
- **Mecânica Exclusiva: "Infiltração Subterrânea Absoluta":**
  - As **Sociedades Subterrâneas** construídas sob as cidades de outras fações são 100% invisíveis na interface normal.
  - **Condição Única de Deteção:** **Apenas podem ser descobertas se o dono da cidade mover fisicamente um Herói para cima do nó dessa cidade** para conduzir uma inspeção/patrulha. Isso obriga os inimigos a desperdiçar turnos e heróis preciosos a patrulhar as suas próprias terras.

---

## 7. Economia & Recursos de Recrutamento

O sistema económico do jogo divide-se entre recursos de manutenção geral e recursos geográficos/estratégicos dedicados exclusivamente ao recrutamento militar:

### A. Recursos Globais (Comuns a Todas as Fações)
- **Ouro:** Moeda padrão gerada por cidades e comércio; utilizada para manutenção contínua de tropas, construção de infraestruturas e acordos diplomáticos.
- **Manpower (Mão de Obra):** Reserva populacional disponível para formar regimentos básicos; regenera por turno com base no crescimento das províncias.

### B. Recursos Específicos de Fação (Exclusivos para Recrutar Unidades)
Cada fação necessita de um recurso material ou biológico único para convocar as suas tropas especializadas, criando dependências geográficas e comportamentais distintas no mapa-mundo:

1. **Humanos — Cristais Aether:**
   - **Utilidade:** Alimentam as armas infundidas com mana, os núcleos dos Golems Explosivos e as gemas inseridas no corpo das bestas da Cavalaria Real.
   - **Obtenção Geográfica:** **Apenas podem ser minerados em Planícies**. A expansão territorial humana dá prioridade ao controlo de vales e planícies abertas.

2. **Elfos — Ferro:**
   - **Utilidade:** Matéria-prima industrial para blindagens, chassis de tanques, espingardas modernas, autómatos e howitzers móveis.
   - **Obtenção Geográfica:** **Minerado exclusivamente em Montanhas**. A ditadura militar élfica expande-se vigorosamente em direção a cordilheiras rochosas para erguer complexos mineiros e fundições.

3. **Ratos — Mutagéneo:**
   - **Utilidade:** Agente químico/biológico necessário para transformar escravos capturados em ratos, produzir projéteis químicos para artilharia e deformar monstros colossais como a Hydra Rato ou heróis abominação.
   - **Obtenção Bélica & Política:** Não depende de biomas de terreno. É obtido diretamente ao **derrotar exércitos inimigos** em combate (extração de biomassa e prisioneiros) ou através de **decisões e dilemas morais** no mapa-mundo.

### C. Tipos de Província, Terreno & Economia Geográfica Diferenciada
Para quebrar a homogeneidade do mapa e criar pólos estratégicos de disputa geopolítica, as províncias deixam de ser idênticas e passam a ter perfis económicos e táticos distintos:

1. **Planícies Agrícolas (Plains):**
   - *Economia:* Alto Manpower (+8/turno) e Aether (+2/turno). Ouro padrão (+12/turno).
   - *Tática:* Terreno plano sem bónus de relevo (Defesa 1.0x). Ideal para cargas de choque e manobras rápidas.
2. **Cordilheiras e Minas (Mountains):**
   - *Economia:* Depósitos de Ferro (+2/turno) e minérios (+20 Ouro/turno), mas baixo Manpower (+3/turno).
   - *Tática:* Forte bónus de relevo defensivo (+25% de poder aos defensores). Dificulta investidas de cavalaria e favorece posições defensivas prolongadas.
3. **Florestas Ancestrais (Forests):**
   - *Economia:* Recursos de madeira e caça equilibrados (+14 Ouro, +5 Manpower).
   - *Tática:* Cobertura vegetal que reduz a eficácia do dano à distância de atiradores e artilharia.
4. **Cidades Portuárias & Nós Fluviais (River / Coast Towns):**
   - *Economia:* Centros de comércio internacional com geração massiva de Ouro (+28 a +32 Ouro/turno), fundamentais para suportar o custo de manutenção de exércitos maiores.
   - *Tática:* Pontos de estrangulamento vitais; o controlo destas províncias dita a solvência financeira de uma nação.
5. **Fortalezas & Cidadelas de Fronteira (Castles / Anchors):**
   - *Economia:* Alto custo de manutenção de guarnição, mas essenciais para travar ofensivas inimigas.
   - *Tática:* Milícia territorial (*Home Guard*) reforçada (capacidade até 4 unidades defensivas gratuitas). Sofrer um assalto direto sem **Unidades de Cerco** resulta em taxas de baixas catastróficas para o atacante.

---

## 8. Sistema de Moral & Liderança do Herói em Combate (Tempo Real)

A estabilidade psicológica das tropas é o pilar central das batalhas táticas em tempo real:

### A. Influência Global do Herói (Todo o Campo de Batalha)
- A presença e comando do **Herói aplicam-se globalmente a todo o mapa de combate** (sem restrição de pequenos raios ou auras circulares).
- As tropas podem manobrar em flancos distantes sem sofrerem penalidades de distância, mantendo a coesão geral enquanto o Herói estiver vivo e em combate.
- **Vulnerabilidade Estratégica:** Se o Herói for eliminado ou forçado a fugir, a perda da âncora moral causa um choque catastrófico imediato em todas as unidades do exército.

### B. Fatores de Quebra de Moral
A determinação de um batalhão sofre desgaste dinâmico perante situações de choque táctico:
1. **Baixas Rápidas & Dano Concentrado:** Bombardeamentos de artilharia, explosões de Golems, magias em área ou rajadas de metralhadora/minigun que dizimam múltiplos soldados em poucos segundos.
2. **Posicionamento Táctico Desfavorável:** Sofrer cargas de flanco, ser atacado pelas costas ou ficar completamente cercado por formações inimigas.
3. **Morte do Comandante:** Queda do Herói do exército, reduzindo a moral de todas as forças sobreviventes e despoletando fugas em cadeia.

### C. Patamares de Moral por Unidade & Fuga Definitiva da Batalha
- **Estatísticas de Moral Diferenciadas:** Cada tipo de unidade possui um limiar base de coragem distinto:
  - *Moral Baixa / Descartável:* Escravos e infantaria básica de Ratos (entram em pânico com extrema rapidez).
  - *Moral Moderada:* Soldados regulares Humanos e artilharia.
  - *Moral Elevada / Fanática:* Cavalaria Real, guardas élficos e defensores da Capital Élfica (onde a moral é inquebrável).
- **Mecânica de Deserção:** Quando a barra de moral de uma unidade se esgota (atinge 0):
  - A unidade entra em pânico incontrolável e debanda em direção aos limites do campo.
  - **Desaparece da batalha até ao seu fim:** Não é possível reagrupá-la durante esse confronto. A unidade fica indisponível até à resolução final do combate no mapa-mundo.

---

### D. HUD de Combate Tático (Diegética & Personalizada por Fação)

Para reforçar a identidade visual e temática de cada civilização, o ecrã de combate tático em tempo real adota uma interface gráfica (UI/HUD) com estética e materiais específicos:

1. **Estilo Visual & Temática da HUD por Fação:**
   - **Humanos (Democracia Mágica):** **Holograma Arcano / Mágico**. Painéis translúcidos em azul ciano e ouro, com círculos e runas mágicas projetadas por cristais Aether, emanando um *glow* suave.
   - **Elfos (Ditadura Tecnológica):** **Holograma Industrial / Ecrã Tático Militar**. Linhas angulares, grelhas geométricas, scanlines e miras cibernéticas em tons âmbar/laranja industrial e vermelho de alerta (estética militar a diesel-vapor).
   - **Ratos (Oligarquia Tóxica):** **Painel Mecânico de Sucata & Lodo (Visão Top-Down)**. Placas de ferro enferrujado rebitadas, tubos de vidro com líquido mutagénico verde borbulhante e manómetros mecânicos com agulhas oscilantes.

2. **O Centro de Comando do Herói (Painel Inferior):**
   - **Retrato do Herói (Token Animado):** Mostra o líder militar em campo; se a moral atingir a zona de perigo (<25%), o retrato pisca em alerta.
   - **Barra de Vida & Barra de Mana/Energia do Herói:** A mana/energia alimenta a ativação de feitiços e habilidades ativas de comando em tempo real.
   - **Barra Global de Moral do Exército:** Indicador unificado da estabilidade psicológica de todas as tropas sob o comando do herói, com divisor vermelho no patamar de pânico (25%).
   - **Barra de Magias & Poderes Ativos (Atalhos Q, W, E):** Três a quatro slots de habilidades com tempo de recarga (*cooldown*) e custo de mana/energia:
     - *Exemplo Humano:* Mísseis Arcanos (Q), Decreto de Emergência Moral (W), Tempestade de Aether (E).
     - *Exemplo Élfico:* Barragem de Metralha (Q), Sobrecarga Mecânica (W), Voto de Expiação (E).
     - *Exemplo Rato:* Nuvem Caústica (Q), Frenesim do Enxame (W), Rugido de Terror Desmoralizador (E).
   - **Painel de Ordens Táticas Rápidas:** Botões com atalhos de teclado para movimentar em formação (A), atacar/focar alvo (S), posição defensiva (D) e ordem de retirada geral (R).

3. **Arquitetura de Implementação em Godot 4.x:**
   - Utilização de um único componente mestre reutilizável (`CombatHUD.tscn`), variando dinamicamente apenas o `Theme` (`.tres`), texturas de painéis e shaders de pós-processamento (holograma vs metal/sucata) com base na fação do jogador.

---

## 9. Governos, Sistema de Leis & Eventos de Fim do Mundo

O sistema político de cada fação dita a forma como as decisões de estado são tomadas e como o apocalipse pode ser despoletado no mapa-mundo:

### A. Mecânicas Políticas por Regime de Fação

1. **Humanos (Democracia & Poderes de Emergência):**
   - *Tempo de Paz:* Leis civis e económicas requerem tempo de deliberação parlamentar ou consenso social.
   - *Tempo de Guerra:* Ativação do Estado de Emergência — **apenas o Presidente tem autoridade direta para passar leis instantaneamente**, permitindo militarização acelerada para enfrentar ameaças externas.

2. **Elfos (Ditadura Teocrática Baseada na Fé):**
   - As leis não dependem de parlamentos nem de diplomacia interna; são **decretadas com base na Fé na Árvore Sagrada e no Dever de Expiação**.
   - A população aceita os decretos como imperativos religiosos sagrados contra o seu "pecado eterno", conferindo obediência total às reformas bélicas e industriais.

3. **Ratos (Oligarquia & Poder Político):**
   - Os clãs e castas aristocráticas operam através de uma moeda de **Poder Político**.
   - O jogador/bot acumula Poder Político (através do prestígio das famílias nobres, controlo das subcidades e terror) e consome essa influência para impor novas diretrizes aos clãs de ratos.

---

### B. Categorias de Leis

1. **Leis Gerais:**
   - Acessíveis a qualquer nação (ex: conscrição militar, taxas de impostos sobre o ouro, racionamento de mantimentos, mobilização industrial).
2. **Leis Exclusivas de Fação:**
   - Reformas profundas associadas à identidade única de cada raça (ex: mutações genéticas forçadas nos ratos, automação fabril extrema nos elfos, fundação de academias de teurgia nos humanos).
3. **Leis de Fim do Mundo (Projetos Apocalípticos):**
   - Leis monumentais de fim de jogo que alteram o destino do planeta.
   - **Exemplo Central (Elfos):** A lei de **"Reviver a Árvore da Vida"**. Quando os Elfos acumulam os recursos necessários e aprovam este decreto de fé suprema, inicia-se o **Evento de Fim do Mundo**: a restauração da árvore começa a consumir o mundo ou a purgar os seres corruptos, soando os avisos apocalípticos globais para todas as outras fações tentarem detê-los antes que o cataclismo se complete.

---

### C. Condições de Vitória & Pacing da Campanha (Faseamento da Guerra)
Para evitar que a campanha degenere numa conquista monótona de pintura de mapa (*map-painting*), o jogo adota um ritmo em fases com múltiplas condições de desfecho:
1. **Fase Inicial (Early Game — Expansão & Consolidação):** Conquista rápida de províncias neutras vizinhas, assegurando nós fluviais/costeiros para estabilidade financeira e biomas específicos para recursos de recrutamento (Aether/Ferro).
2. **Fase Intermédia (Midgame — Choque de Impérios & Cerco):** Estagnação das frentes convencionais devido à resistência de guarnições territoriais (*Home Guard*) e fortalezas montanhosas, obrigando à introdução de **Unidades de Cerco**, choque e manobras táticas com previsão detalhada de baixas.
3. **Condições de Vitória Plurais:**
   - **Dominação Militar Completa:** Conquista de todos os territórios do mapa.
   - **Controlo de Capitais Estratégicas:** Capturar e manter a Capital adversária durante 3 a 5 turnos consecutivos após superar a penalidade de ocupação.
   - **Resolução do Fim do Mundo:** Ativação bem-sucedida do ritual apocalíptico da sua fação ou destruição da capital conspiradora durante a Grande Coligação de sobrevivência.

---

## 10. Diplomacia, Sistema de Credibilidade & Alianças de Fim do Mundo

A diplomacia rege as relações entre fações no mapa-mundo por turnos, equilibrando liberdade de agressão com consequências reputacionais:

### A. Ações Diplomáticas Padrão
- **Tratados Bilaterais:** Pactos de Não-Agressão (PNA), Alianças Militares, Acordos de Comércio (geração mútua de Ouro) e Permissões de Acesso Militar.
- **Resolução de Guerras:** Propostas de Cessar-Fogo, Tratados de Paz e exigência de Reparações/Tributos monetários ou materiais.

### B. Sistema de Credibilidade & Confiança Internacional
- **Liberdade Táctica Total:** Qualquer fação pode declarar guerra ou atacar outra em qualquer turno, por qualquer motivo ou sem aviso prévio.
- **O Custo da Traição (Métrica de Credibilidade):**
  - Declarar guerras injustificadas, quebrar pactos ativos ou apunhalar aliados pelas costas reduz drasticamente a **Credibilidade** da fação perante o mundo.
  - **Penalidades por Baixa Credibilidade:**
    - Nenhuma outra fação confiará em assinar novos acordos ou tratados comerciais.
    - Facilidade acrescida para os vizinhos formarem coligações defensivas contra ti.
    - Deterioração passiva das opiniões diplomáticas em todos os turnos.

### C. Alianças de Sobrevivência & Guerra Total do Fim do Mundo
- Quando os Elfos (ou qualquer fação que venha a possuir um projeto apocalíptico) aprovam a lei de **Reviver a Árvore da Vida** e iniciam a contagem decrescente do cataclismo:
  1. **Guerra Automática Mundial:** Todas as nações restantes no mapa declaram automaticamente **Guerra Total** contra os Elfos.
  2. **Aliança Temporária de Sobrevivência:** Todas as rivalidades históricas e guerras em curso entre as restantes raças são congeladas; cria-se uma **Grande Coligação Automática** (ex: Humanos e Ratos marcham lado a lado) com o único objetivo militar de assaltar a capital élfica e destruir a Árvore Sagrada antes que o evento se complete.

---

## 11. Stack Técnica & Arquitetura de Software
- **Engine:** Godot Engine 4.7.2-stable.
- **Linguagem Principal:** 100% GDScript com tipagem estática rigorosa para todo o ecossistema do jogo (núcleo de simulação, mapa, combate, HUD e persistência).
- **Inteligência Artificial (IA):** **LimboAI v1.8.1 (GDExtension)** — bot orquestrado por árvores de comportamento compostas por tarefas modulares (`BTRecruitTask`, `BTAttackTask`, `BTAdvanceTask`), com suporte a árvores especializadas por perfil de fação.
- **Renderização Procedural & Shaders:** GLSL / Godot Shader Language (`terrain.gdshader`) aplicado sobre texturas de campos procedurais (RGB: elevação, humidade e temperatura) com relevo sombreado (*hill-shading*) e biomas dinâmicos.
- **Interface Gráfica (UI/UX):** Arquitetura inspirada na saga *Total War* gerida por um sistema centralizado de estilos (`UiStyle`), glifos procedurais em tempo real (`UiIcon`), sistema de localização dinâmica bilingue (PT/EN) e escala responsiva para ecrãs 16:9 (1152x648).
- **Testes Automatizados & Calibração Headless:** Scripts de execução CLI (`godot --headless`) para validação de integridade topológica (`worldgen_sweep.gd`) e aferição estatística de equilíbrio em lote de 20 partidas simuladas (`balance_sim.gd`).
