# Mapa e províncias

**Status:** implemented · **Updated:** 2026-11-21 · [GDD](../../GDD.md)

O mapa é gerado por seed e divide-se em 21 províncias com terreno, dono, guarnição e milícia próprios. Isto serve os pilares "O terreno decide" e "Contra a bola de neve": o valor de uma província depende do bioma, e fortalezas travam avanços.

## Rules

1. `MapFactory` cria um `MapState` a partir de uma seed; `WorldGenerator` produz o campo de elevação/humidade/temperatura, rios, a gráfica de províncias e a classificação de terreno e fortaleza.
2. O grafo tem sempre 21 províncias ligadas, com âncoras garantidas: duas capitais, fortalezas e um nó fluvial. O bloco inicial de cada facção é ligado, com 5 a 8 províncias.
3. Há cinco terrenos — Planície, Floresta, Costa, Montanha e Terras Altas (*Highlands*) — e fortaleza é um papel sobreposto ao terreno, não um bioma extra.
3b. As províncias montanhosas mais altas são **picos intransponíveis**: a geração remove todas as arestas que tocam um pico, e nenhuma ordem pode entrar ou sair dele. As capitais e os passos fortificados ficam isentos; se remover um pico desligasse o continente, a geração usa menos picos. A vitória total conta apenas províncias transitáveis.
4. O rendimento usa os valores base do terreno, mais bónus de capital e modificador de facção; um recurso de facção é produzido por turno conforme o terreno.
5. Fortalezas custam 4 de ouro por turno mesmo durante agitação, e somam +0,25 à defesa.
6. `MapView` desenha e faz hit-test; nunca altera o estado do jogo.

## Numbers

| Nome | Valor | Unidade | Observação |
|---|---|---|---|
| Grelha / tamanho do mundo | 288×162 / 1152×648 | células de 4 px / px | invariante de worldgen |
| Províncias | 21 | províncias | grafo ligado |
| Ouro/manpower: planície | 13 / 10 | por turno | `TERRAIN_INCOME` |
| Ouro/manpower: floresta | 12 / 6 | por turno | `TERRAIN_INCOME` |
| Ouro/manpower: costa | 20 / 2 | por turno | `TERRAIN_INCOME` |
| Ouro/manpower: montanha | 19 / 4 | por turno | `TERRAIN_INCOME` |
| Ouro/manpower: terras altas | 14 / 5 | por turno | `TERRAIN_INCOME` |
| Defesa: terras altas | 1,5 | × | `TERRAIN_DEFENSE` |
| Picos intransponíveis | até 6 | províncias | `PEAK_PROVINCE_FRACTION` / `PEAK_MAX_PROVINCES` |
| Terras altas | até 12 | províncias | `HIGHLANDS_PROVINCE_FRACTION` / `HIGHLANDS_MAX_PROVINCES` |
| Bónus de capital | +8 / +2 | ouro / manpower por turno | `CAPITAL_GOLD_BONUS` |
| Recurso de facção | +2 | por turno | Humanos: Aether em planície/floresta/costa; Elfos: Ferro em montanha |
| Manutenção de fortaleza | 4 | ouro por turno | `FORTRESS_UPKEEP_GOLD` |
| Ouro/manpower iniciais | 120 / 24 | — | `STARTING_GOLD` / `STARTING_MANPOWER` |
| Tropas iniciais: capital / segunda província | 5 / 2 | tropas | `CAPITAL_STARTING_TROOPS` |

## Edge cases

- Uma província capturada fica 2 passos de resolução sem produzir nem recrutar.
- A milícia neutra de uma fortaleza capturada mantém-se e regenera; outras províncias neutras começam vazias.
- O lore propõe costa 28–32 de ouro e montanha 20; os valores acima são os do código, medidos em `balance_sim.gd`.

## History

- 2026-11-21: documentado a partir de `balance.gd`, `map_factory.gd` e `world_generator.gd`.
