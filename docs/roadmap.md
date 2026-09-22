# Mystery Tactics — Beta Roadmap (Draft)

**Target:** October 1, 2026 — 100 units, 3 gyms, 1 fully built boss battle
**Today:** September 3, 2026 — **4 weeks out**
**Status:** rough draft. Revisit and re-scope once we've had the "what's missing / what to cut" pass.

## Where we actually stand today

I counted directly from the project files rather than guessing:

- **Species with a real, custom-built moveset: ~40**, across 15 evolution lines — Bulbasaur, Caterpie/Butterfree, Weedle/Beedrill, Rattata/Raticate, Spearow/Fearow, Pichu/Pikachu/Raichu, Venonat/Venomoth, Mankey/Primeape/Annihilape, Horsea/Seadra/Kingdra, Togepi/Togetic/Togekiss, Swinub/Piloswine/Mamoswine, Larvitar/Pupitar/Tyranitar, Mudkip/Marshtomp/Swampert, Shroomish/Breloom, Corphish/Crawdaunt.
- **Cyndaquil/Quilava/Typhlosion** — one of the 3 starters, still mid-redesign (some moves still placeholder/batch-copied, not yet redone one-at-a-time).
- **~454 other species** exist only as raw imported data (name/sprite/base stats) with zero custom moves — pure stubs, essentially untouched.
- **Gyms: 1 of 3.** Misty (Barias Gym) is fully wired — manual battle map, team, badge grant, rematch gating. Gyms 2 and 3 have **no groundwork at all**: no towns, no routes, no wild-encounter areas, no leader NPCs. The whole overworld today is just Archis Town + Route 1 + the Barias gym area.
- **Boss: engine done, Suicune not finished.** Spawning, capture, boss-ability tier, weather field (Northwind Field), and Suicune's full kit (Pressure/Updraft/moves) are built — but it's blocked on your boss-loadout pick, so it isn't a "fully made" battle yet.

## The gap

| Target | Have | Need |
|---|---|---|
| 100 units | ~40 done (+3 mid-progress) | ~57-60 more, from scratch |
| 3 gyms | 1 done | 2 more, including towns/routes/leaders — not just battles |
| 1 boss | engine built, unit blocked | unblock + finish 1 battle |

**Reality check on pace:** the ~40 species/15 families done so far took about 6 weeks (since 2026-07-22), *shared* with heavy engine work (boss system, PC menu overhaul, deploy/weight rework, manual battle maps, etc.). Pure species throughput was roughly 2-3 families a week when focused. Hitting 60 more species in 4 weeks needs about **5 families a week — nearly double our best pace so far** — and that's before counting 2 gyms' worth of new maps/routes/leaders. I'm drafting toward the deadline as asked, but this is the single biggest risk in the plan below; flagging it now so it's not a surprise later.

Also worth remembering going in: species work happens one family at a time with your input each round (no batch-copying from mainline) — so the weekly species targets below assume we can keep that fast back-and-forth cadence up throughout.

## Week-by-week draft

### Week 1 — Sep 3 to Sep 9
- **Unblock Suicune**: get your boss-loadout pick, finish wiring it, do a full test battle. Goal: boss battle #1 fully playable by end of week.
- **Finish Cyndaquil line properly** (Quilava/Typhlosion too) — it's a starter, shouldn't ship half-placeholder.
- **Species sprint, batch 1**: 4-5 new families (~12-15 species). Candidates to consider: the other partially-stubbed starter-adjacent lines (Charmander, Squirtle, Totodile, Torchic all currently have leftover placeholder data, not real movesets) plus whatever route/gym-2 roster we land on.
- **Scope gym 2's location**: pick where it lives, what route connects it, roughly what type/theme.

### Week 2 — Sep 10 to Sep 16
- **Species sprint, batch 2**: 5 families (~15 species).
- **Build gym 2's world**: new town/route tiles, new `EncounterArea`, gym interior map, leader NPC + team + badge — mirroring how Barias/Misty was built.
- **Gym 2 playtest**: walk in, fight, get the badge, confirm rematch-gating works (same class of bug we just fixed for Misty).

### Week 3 — Sep 17 to Sep 23
- **Species sprint, batch 3**: 5 families (~15 species).
- **Scope + build gym 3's world**: same steps as gym 2.
- Start folding newly-finished species into gym leader teams and wild encounter tables as they come online, rather than leaving that for the end.

### Week 4 — Sep 24 to Sep 30
- **Species sprint, batch 4 (buffer)**: whatever's left to hit or get close to 100 — this week doubles as catch-up if earlier weeks slipped.
- **Gym 3 finish + playtest.**
- **Full playthrough pass**: starter → gym 1 → gym 2 → gym 3 → boss, on a fresh save, hunting for soft-locks, balance disasters, and the kind of bug that only shows up end-to-end.
- **Cut list**: if we're short on units, decide here what ships at 80-90 instead of 100 rather than finding out on the 30th.

### October 1 — Beta cut
Freeze content, tag/back up the build, do a final smoke test.

## Open questions for you
- Gym 2 and 3 themes/locations/leaders — need your input before Week 1's "scope gym 2" task can really start.
- Suicune's boss loadout — blocking item, first thing to resolve.
- Which of the ~57-60 remaining families to prioritize, in order — per our usual "surface next family, get a beat" workflow, so this list will grow week by week rather than being fixed today.
