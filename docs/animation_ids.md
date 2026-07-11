# Animation IDs (SkyTemple)

Toda espécie precisa dessas animações pra ser jogável ou aparecer como inimiga em masmorras (fonte: [SkyTemple Wiki - Animation ID](https://wiki.skytemple.org/index.php/Animation_ID)).

| Animation ID | Nome | Condição em que toca |
|---|---|---|
| 0 | Walk | Movimento básico entre tiles. Também toca ao mover no overworld. |
| 1 | Attack | Animação básica de ataque, toca ao usar um golpe ou o ataque regular. |
| 5 | Sleep | Ao ser afetado por Sleep ou nascer dormindo. |
| 6 | Hurt | Ao tomar dano de um ataque ou efeito de status. |
| 7 | Idle | Toca sem nenhum input, tanto em masmorras quanto no overworld. |
| 8 | Swing | Usado por golpes como Faint Attack, Thief e Flame Wheel. |
| 9 | Double | Usado por golpes como Double Team, Agility e o Evasion Orb. |
| 10 | Hop | Usado por golpes como Dig e Bounce. |
| 11 | Charge | Usado por golpes como Glare, Detect e Bulk Up. |
| 12 | Rotate | Usado ao arremessar itens ou por muitos golpes. |

## Referências relacionadas

- Tabela de efeitos de movimento (VFX): [List of Effect Animations](https://wiki.skytemple.org/index.php/List_of_Effect_Animations) — mapeia Effect ID / WAN File ID / ponto de anexação / descrição pra cada golpe.
- Assets locais de VFX: `D:\Assets\move_VFX\<id>` (pastas numeradas por ID, difícil de navegar) e `D:\Assets\RawAsset\Particle` (arquivos com nomes legíveis, ex: `Vine_Whip.Dir1.png`) — nem todo golpe está nas duas pastas, então vale checar as duas.
