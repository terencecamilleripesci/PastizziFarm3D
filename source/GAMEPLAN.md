# PASTIZZI MASTER 3D — Game Plan v3 (2026-07-04)
**Coin Master's exact loop, rebuilt in 3D Malta, on our existing Godot base.**
Engine: Godot 4.7 (MIT) · Base: pastizzi-farm-3d project (grid engine, rigged characters, diorama village scene)

---

## 1. COIN MASTER MECHANICS — verified reference (accuracy first)

| Mechanic | How the real Coin Master works |
|---|---|
| **Spins (energy)** | Regenerate 5/hour up to a 50-spin meter (excess from rewards is banked beyond cap). Daily links/gifts add more. |
| **Slot symbols** | 3× coin sack = coins · 3× hammer = ATTACK · 3× pig = RAID · 3× shield = +1 shield · 3× energy = +spins. Partial matches pay small coins. |
| **Bet multiplier** | Spend N spins on one pull → ALL rewards ×N (coins, raid loot, event points). High bets (×400+) event-gated. |
| **Shields** | Stack max 5. Each blocks one attack (attacker still gets consolation coins). |
| **Attack** | Hit one building in another player's village → it loses a star; victim pays to repair. Revenge option. |
| **Raid** | Matched vs "the Coin Master" (a rich player). Dig 3 of 4 X-spots on their village; some spots hold big % of their unbanked coins. |
| **Villages** | Each = 5 buildings × 5 star levels, bought with coins (escalating). Complete all 25 stars → travel to next village (game has 605). Completion bonus. |
| **Pets** | Foxy (digs the 4th raid spot), Tiger (bonus attack loot, works vs shields), Rhino (auto-blocks attacks). Hatch, feed (timed food), level up. |
| **Cards** | 9-card themed sets from chests (3 chest tiers, bought with coins, contents scale with village number). Set completion = huge spin/pet rewards. Duplicates traded socially. |
| **Events** | Rotating: Attack Madness, Raid Madness, Bet Blast, Village Master, tournaments — multiply one verb for a day. THE retention engine. |
| **Monetization** | IAP spin/coin bundles + piggy bank; minimal ads. Whale-driven. |

Sources: Grokipedia Coin Master page, Level Winner & VMOS strategy guides, Playbite bet-multiplier explainer (July 2026).

---

## 2. OUR TRANSLATION — "Pastizzi Master 3D"

**One island = one Maltese village diorama in full 3D** (we already render this).
Progression = restore Malta, village by village: Birgu → Marsaxlokk → Mdina → Valletta → Sliema → Mosta → Rabat → Gozo…

| Coin Master | Ours (3D Malta) |
|---|---|
| Village 5 buildings | Bakery (il-Forn), Church (il-Knisja), Tower (it-Torri), Boat+dock (il-Luzzu), Market stall (il-Monti) — matches our diorama art |
| Stars | Each building 5 levels — visual upgrades in 3D: scaffolding → basic → painted → decorated → gold festa lights |
| Slot machine | Our VIVA IL-FESTA machine as a 3D prop in the scene; camera zooms to it; reels = 🪙 sack / 🔨 hammer / 🦊 ħalliel (thief) / 🛡 luzzu-eye shield / ⚡ pastizz energy |
| Attack | Camera flies to an NPC island → cannon fires at one building → star knocked off with debris physics |
| Raid | Sail to "Il-Kaptan"'s island → 3 of 4 dig spots on his beach → treasure chest bursts |
| Shields | Luzzu Eye of Osiris shields, stack 5 |
| Pets | Kelb tal-Fenek (attack +), Cat (raid + digs 4th spot), Qanfud/hedgehog (defense). We already own dog/animals + proven Meshy character pipeline |
| Cards | "Il-Ġabra Maltija" — 9-card sets: Festi, Ikel (food), Knejjes, Luzzijiet, Widien… from chests |
| The Coin Master | "Il-Kaptan" NPC roster at launch; real players once backend lands |

**Differentiator vs Coin Master:** the village is REAL 3D you orbit/zoom (they're flat renders), Maltese identity, and (later) our farm mini-game as a coin faucet — kept parked until core loop ships.

---

## 3. WHAT WE ALREADY HAVE (base audit — honest)

✅ Godot 4.7 + web & (untested) Android export toolchain on the Pi
✅ 3D diorama island scene (village.gd) matching the art style
✅ Grid engine + save system + camera + day/night (farm.gd — parked, reusable)
✅ Rigged animated characters (farmer boy/girl: walk/idle/harvest) + 16 props/animals
✅ Slot machine DESIGN + prize logic (from Crush v93 — port logic to GDScript)
✅ Meshy pipeline recipe (meshy-5 + t-pose toggle + 18k) — 512 credits
✅ GitHub Pages hosting + versioned deploy discipline

❌ To build: spin meter/regen, bet multiplier, star-purchase UI, attack/raid sequences, shields, NPC villages, pets, cards/chests, events config, IAP, backend

❌ New Meshy assets needed (~8, one at a time with approval): church, coastal tower, fountain, cannon, treasure chest, thief character, 2 pet variants (~250 cr)

---

## 4. MILESTONES (each = deployable build)

**M1 — THE LOOP (v3.0)** ← START HERE
Slot (spin meter 50, 5/hr regen, bet ×1–×10) → coins → buy building stars (5×5, escalating costs) → 3D building visibly upgrades → village complete → sail-away cinematic → next village (5 villages seeded). Local save. Web build for testing.

**M2 — THE VERBS (v3.1)**
ATTACK (NPC islands, cannon sequence, star damage, repair costs) + RAID (Il-Kaptan, dig 3-of-4) + shields (stack 5, block sequence) + revenge list. NPC villages = our diorama with procedural variation.

**M3 — THE HOOKS (v3.2)**
Pets (hatch/feed/level, 3 powers) + chests & card sets (9-card, set rewards) + rotating events (JSON-config: Attack Madness ×2, Raid Madness, Bet Blast) + daily gift.

**M4 — THE BUSINESS (v3.3)**
Native Android export (Gradle on Pi or cloud build), Godot Play Billing IAP (spin/coin packs + piggy bank), AdMob rewarded ads (+10 spins), Supabase backend: real player villages for attack/raid + leaderboard.

**M5 — SHIP (v1.0 store)**
ElevenLabs Maltese voice/SFX, 20+ villages content, tutorial, Play Store listing (rating: simulated gambling = YES → Teen), soft-launch Malta.

---

## 5. RULES OF ENGAGEMENT (learned the hard way)
- ONE Meshy character/prop at a time → draft → boss approves → refine/rig
- `pose_mode:"t-pose"` + `ai_model:"meshy-5"` + 18k polys + simple prompts, NO pose words
- Every deploy = versioned pfNNN files + redirect index.html + bump title version
- Test headless before every hand-off; verify live URL 200
- Boss approves each milestone before the next begins
