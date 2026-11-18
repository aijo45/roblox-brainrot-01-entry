# Brainrot Bay — make.fun roblox-brainrot-01

A 3D Roblox brainrot game in the genre Steal a Brainrot began, built for
make.fun's "Make the best AI Roblox brainrot game" bounty
(roblox-brainrot-01). The player walks a real 3D bay under a 3D camera,
catches absurd meme-born characters off a conveyor, carries them home to
a base, and watches cash tick up every second — while other players try
to steal them and a Meme Wave sweeps the map.

## The cast

Twelve original characters across six rarities, each with a name, a
quirk, a buy price and a $/s rate (see `src/shared/BrainrotData.luau`):

| Rarity | Characters | $/s (base) |
| --- | --- | --- |
| Common | Sir Quacksalot, Noodle Wizard | 1–2 |
| Rare | Captain Pickle, DJ Toaster | 6–10 |
| Epic | Professor Banana, Couch Potato King | 25–40 |
| Legendary | Grandma Rocket, Toilet Tornado | 100–160 |
| Mythic | CEO of Naps, Infinite Sandwich | 400–650 |
| Brainrot God | The Algorithm, Skibidi Supreme | 2,000–5,000 |

Mutations roll on spawn — Golden (x2, 8%), Diamond (x5, 3%), Rainbow
(x10, 1%) — and multiply both the rate and the price.

## The loop

1. **Catch** — brainrots walk the conveyor down the middle of the bay.
   Touch one to buy it (cash only, no Robux), then it rides above your
   head.
2. **Carry home** — walk it onto your base platform and it takes a
   pedestal (6 per base, 8 bases) and starts earning $/s.
3. **Steal** — touch another player's placed brainrot to steal it and
   run it to your base. The owner can tag you to make you drop it.
   Lock your base for 20s with the LOCK button or the L key (60s
   cooldown).
4. **Survive the Meme Wave** — every 100s a red wall sweeps the map.
   Only your own base platform is safe; anyone caught outside is swept
   back to spawn and drops what they carry.
5. **Rebirth** — at $50,000 total earned, rebirth (R key or the button)
   resets cash and brainrots for +50% earnings, stacking each time.

The HUD (top right, clear of Roblox's own buttons) shows cash, $/s,
rebirths and the wave countdown; the left panel shows the whole rarity
ladder with prices and rates; the bottom bar holds the lock and rebirth
buttons.

## Build

```sh
/home/hatch/workspace/tools/rojo/rojo build default.project.json --output game.rbxl
mkdir -p out && MAKEFUN_OUTPUT_DIR=out node main.ts
```

`main.ts` (Node 22, stdlib only) copies `game.rbxl`, `src/`,
`screenshots/` and `PLAY.json` to the output dir and writes
`dossier.json` with the kit's vendored `vendor/makefun-roblox.ts`.

## Publish (needs the Roblox account owner)

This Linux machine has no Roblox Studio, so publishing is a manual
step, exactly as for the roblox-game-01 entry:

1. Open `game.rbxl` in Roblox Studio (signed in to the @paijo-x
   account's Roblox account), play-test it, then File > Publish to
   Roblox As > create a new experience "Brainrot Bay".
2. On the Creator Dashboard: add a description (including your make.fun
   play code), a genre, answer the content questions, and set the
   experience Public.
3. Upload the experience icon (512x512) and the thumbnail — the
   thumbnail must be the same picture as `screenshots/1-thumbnail.jpg`.
4. Fill in `PLAY.json` with the real `place_id` and `universe_id` from
   the published experience, commit, and submit.

## Screenshots

`screenshots/` holds renders of the game's actual layout (conveyor,
bases, HUD, wave) drawn to match what the Luau builds. They are not
Roblox Studio captures — this machine cannot run Studio. Replace them
with real Studio captures before submitting if Studio is available.
