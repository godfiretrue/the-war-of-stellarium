# The Final War of Stellarium — Documento de Design de Jogo

**Versão:** 0.1 · **Atualizado:** 2026-11-21 · [Funcionalidades](#feature-index) · [Decisões](#decisions) · [Registo](#change-log) · [Arquitetura](ARCHITECTURE.md) · [Lore](LORE.md)

## Resumo

O jogador comanda uma das duas nações de um continente de 21 províncias gerado por seed: a democracia mágica dos Humanos ou a ditadura tecnológica dos Elfos. Em cada turno planeia ordens em segredo, escolhe quantas tropas destaca de cada origem e disputa províncias cujo terreno e fortificações decidem o resultado. O desafio não é apenas pintar o mapa: a milícia, a agitação pós-conquista e a penalidade por perder a capital travam o efeito bola de neve. A campanha termina quando uma facção possui todas as províncias ou não possui nenhuma.

O enredo completo — incluindo a Árvore da Vida corrompida, o Apocalipse dinâmico, os Ratos e as visões de Fase 2 — vive em [LORE.md](LORE.md). Este GDD descreve o que o jogo faz hoje e mapeia o que vem a seguir.

| | |
|---|---|
| Género e câmara | Estratégia 2D por turnos; mapa fixo 1152×648 |
| Público | Jogadores de estratégia que gostam de decisões de campanha e simulação; 12+ `[ASSUMPTION]` |
| Plataformas e input | PC desktop, teclado, rato e gamepad (navegação por foco no HUD) |
| Sessão | Uma campanha até conquista total ou domínio sustentado; duração medida pelo `balance_sim.gd` |
| Motor | Godot 4.7.2-stable, GDScript, LimboAI v1.8.1 |
| Âmbito | MVP PAP e Fase 1.5 concluídos; Fase 2 fora do âmbito |
| Referências | *Conquest of Elysium 5* (mundo dinâmico, lore emergente); *Total War: Warhammer 3* (comando de exércitos, geopolítica de fantasia) |

## Pilares

1. **Simultaneidade sem vantagem.** Jogador e bot planeiam sem ver o adversário e a resolução baralha destinos por seed; ninguém ataca "primeiro".
2. **O terreno decide.** Planícies dão manpower, montanhas dão defesa e ferro, costas dão ouro; expandir sem logística quebra.
3. **Contra a bola de neve.** Milícia gratuita, agitação de 2 turnos e penalidade de capital impedem que uma vitória inicial decida a partida.
4. **Simetria de regras.** Bot e jogador usam a mesma API de ordens, pagam os mesmos custos e sofrem as mesmas restrições.

## Ciclo de jogo

```
Explorar províncias neutras → ganhar ouro, manpower e recurso de facção → recrutar e destacar tropas
→ resolver todas as ordens em simultâneo → enfrentar milícia, fortalezas e agitação → reavaliar a frente
```

- **Segundos:** selecionar origem e destino, definir tropas destacadas, confirmar ordens na gaveta.
- **Minutos:** resolução do turno, relatório de batalha, foco de câmara na província disputada.
- **Sessão e entre sessões:** vitória/derrota, save atómico com auto-save, idioma PT/EN trocado em runtime.

## Feature index

| Feature | Status | Scope | Summary | Docs |
|---|---|---|---|---|
| Resolução de turnos e ordens | implemented | MVP | Fases simultâneas, fila de ordens validada, resolução por snapshot | [design](features/turn-resolution/design.md) |
| Combate e unidades | implemented | MVP + Fase 1.5 | Fórmula numérica, terreno, milícia, 12 tipos de unidade com papéis, contra-ataques e cerco | [design](features/combat-and-units/design.md) |
| Mapa e províncias | implemented | MVP + Fase 1.5 | 21 províncias, cinco terrenos (com Terras Altas), fortalezas, picos intransponíveis | [design](features/map-and-provinces/design.md) |
| Névoa de guerra e emboscadas | implemented | Fase 1.5 | Visão de próprias + vizinhas, memória de terreno, guarnição escondida que embosca | [design](features/fog-and-ambush/design.md) |
| Bot e árvore de comportamento | implemented | MVP | LimboAI orquestra decisões em `BotController` | [arquitetura](ARCHITECTURE.md) |
| HUD de campanha | implemented | MVP | Recursos, ordens, dock de província, relatório de batalha | [arquitetura](ARCHITECTURE.md) |
| Save e localização | implemented | MVP + Fase 1.5 | JSON atómico versão 8, textos PT/EN via `Loc` | [arquitetura](ARCHITECTURE.md) |
| Tipos de unidade e cerco | implemented | Fase 1.5 | Seis unidades por facção, ciclo de contra-ataques e cerco a fortalezas/Terras Altas | [design](features/combat-and-units/design.md) |
| Menu de previsão de batalha | implemented | Fase 1.5 | Rácio de poder, baixas estimadas e intervalo, com névoa respeitada | [design](features/combat-and-units/design.md#previsão-de-batalha) |
| Personalidade da IA por facção | implemented | Fase 1.5 | Doutrina por facção: Humanos preferem cavalaria e emboscam uma vez; Elfos leem terreno fortificado, preferem tropas à distância e emboscam com mais frequência | [arquitetura](ARCHITECTURE.md) |
| Vitória dinâmica e meio de jogo | implemented | Fase 1.5 | 70% das províncias transitáveis por três resoluções seguidas, com progresso no HUD | [design](features/dynamic-victory/design.md) |
| Navegação por gamepad | implemented | Fase 1.5 | Vizinhos de foco em loop e atalhos ativos com botão focado | [arquitetura](ARCHITECTURE.md) |
| Segunda camada de economia | idea | Fase 2 | Edifícios, distritos, manutenção e conversão de recursos | — |
| Visão de Fase 2 | idea | Fase 2 | Batalhas em tempo real, heróis, moral, diplomacia, leis, Apocalipse, Ratos | [lore](LORE.md) |

## Marcos

1. **M1, MVP jogável:** mapa, turnos simultâneos, combate, bot, HUD, save e PT/EN · pronto quando Novo Jogo e Continuar arrancam e `balance_sim.gd` corre 60 seeds sem falhas de fila.
2. **M1.5, aprofundamento tático:** unidades de cerco, previsão de batalha, personalidade por facção e vitória dinâmica · concluído: cada item está jogável e o simulador voltou a medir a divisão de vitórias em 60 sementes.

## Decisions

| ID | Date | Decision | Alternatives considered | Why | Affects |
|---|---|---|---|---|---|
| D-001 | 2026-11-21 | Os números do código são a verdade; os valores do lore são intenção de design | adotar os valores do lore | são os valores que o jogo executa | [combate](features/combat-and-units/design.md) e [mapa](features/map-and-provinces/design.md) |
| D-002 | 2026-11-21 | Fase 2 fica documentada, mas fora da implementação | implementar já heróis, moral, diplomacia e Ratos | prazos da PAP e regra de projeto | [visão de Fase 2](LORE.md) |
| D-003 | 2026-11-21 | Documentação em português, alinhada com o lore e o quadro Trello | documentação em inglês | o lore e o quadro estão em português | este GDD e a arquitetura |

## Open questions

- **Suposições a confirmar:** plataforma apenas PC, público 12+, idioma da documentação, sessão de ~76 turnos.
- **Riscos:** o lore afirma 55% Humanos / 45% Elfos; em 60 seeds (`41000..41059`, mundo 2×) o simulador mede 52% / 48% depois do rosário de 12 unidades, todos terminados, sem falhas de fila. A janela antiga de 20 seeds dava outro resultado, pelo que alterações de regras são comparadas sempre com a base de 60 jogos. A Fase 2 tenta expandir o escopo além da PAP.

## Change log

**0.2 (2026-11-25):** Terras Altas como quinto bioma, picos intransponíveis, névoa de guerra e ordem de emboscada; save passa à versão 7.

**0.1 (2026-11-21):** primeiro rascunho a partir do lore fornecido e do código.
