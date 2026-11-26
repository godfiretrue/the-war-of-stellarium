# Névoa de guerra e emboscadas

**Status:** implemented · **Updated:** 2026-11-25 · [GDD](../../GDD.md)

O mapa é totalmente conhecido, mas os exércitos não: cada facção vê as suas províncias e as vizinhas, e lembra-se do terreno que já explorou. Uma guarnição escondida numa posição importante desaparece dessa informação e pode emboscar quem entrar nela. Serve os pilares "Simultaneidade sem vantagem" e "O terreno decide".

## Rules

1. `GameState.is_province_visible()` é a única fonte de inteligência: províncias próprias e vizinhas. `is_province_explored()` acrescenta a memória de terreno (`explored` por facção).
2. Uma emboscada própria (ou apenas enfileirada) é invisível ao inimigo mesmo a partir de uma província adjacente. O bot lê o mesmo filtro através de `visible_troops()` e `visible_defense_power()`.
3. `queue_ambush()` esconde uma guarnição em cidades, fortalezas ou ermos. Num ermo a emboscada é especialmente eficaz: ninguém espera um exército em terreno que não defende. Não pode haver outra ordem da mesma província no turno. Marchar no turno seguinte encerra a emboscada.
4. As ordens de emboscada entram em vigor depois do compromisso de ambos os lados e antes de qualquer combate, na resolução por snapshot.
5. Se um exército inimigo entrar na província, `CombatResolver` aplica ×1,5 ao poder defensor e ×1,25 às baixas do atacante. O resultado inclui `ambush` e a emboscada é consumida, mesmo que a defesa resista.
6. Captura, disputa e cancelamento também removem a emboscada. O HUD mostra o badge na província própria e a linha "Emboscada" no relatório de batalha.

## Numbers

| Nome | Valor | Unidade | Observação |
|---|---|---|---|
| Raio de visão | 1 | província | própria + vizinhas |
| Multiplicador defensivo da emboscada | 1,5 | × | `AMBUSH_DEFENSE_MULTIPLIER` |
| Multiplicador de baixas do atacante | 1,25 | × | `AMBUSH_ATTACKER_LOSS_MULTIPLIER` |
| Emboscadas por turno do bot | 1–2 | ordens | apenas em stalled fronts |

## Edge cases

- Picos intransponíveis não têm vizinhos e nunca são explorados; ficam como terra incógnita no mapa.
- Um save antigo (versão 6) é recusado: a geração mudou e os ids de província não correspondem.
- A vitória total ignora os picos intransponíveis, que ninguém pode conquistar.

## History

- 2026-11-25: primeira versão, com névoa simétrica e ordem de emboscada.
