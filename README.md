# Pokemon Gamification

An **unlocked, unprefixed** Salesforce package that gamifies LSC's managed package (LSC1): a background reward engine grants employees in-game **Currency** + **XP** for real work (Cases, Tickets, Service Requests, Time Worked, optionally Projects), and an opt-in app lets them spend Currency on Poké Balls, catch wild Pokemon across biomes, build a Pokedex, and spend XP to level Pokemon.

> Separate project by design — the live LSC org code stays in `../LSC/force-app` (read-only reference + the home of the 5 reward-engine trigger hooks). This repo is **only** the new package.

## The package — LSC - Poke

| | |
|---|---|
| **Package** | `LSC - Poke` (Unlocked, no namespace) — Id `0HoHs000000L2DcKAK` |
| **Version** | `0.1.2-1` — Id `04tHs000000iTAtIAM` (**Released** — promoted 07/21/2026, 96% coverage; supersedes `0.1.1-1` and `0.1.0-2`) |
| **Dev Hub** | `tempdevHub` — **never `garrettLscProd`** |
| **Install key + links** | [`docs/INSTALL_PRIVATE.md`](docs/INSTALL_PRIVATE.md) — local-only, git-ignored |
| **Where to see it in the hub** | Nowhere in the org UI — 2GP packages are `Package2` Tooling-API records, so the CLI is the only window (`sf package list -v tempdevHub`, or `sf data query -q "SELECT Id, Name FROM Package2" -t -o tempdevHub`); Setup → Package Manager lists only 1GP packages (empty on this hub) and the App Launcher has no Packages entry |

```bash
# CLI install (sandbox or prod — 0.1.2-1 is Released; key in docs/INSTALL_PRIVATE.md)
sf package install -p 04tHs000000iTAtIAM -k '<install key>' -o <orgAlias> -w 15
# Promote a FUTURE version before it can install to prod (human-gated; create it with -c —
# only coverage-computed versions are promotable)
sf package version promote -p "LSC - Poke@<version>" -v tempdevHub
# See the package / its versions on the hub
sf package version list -p "LSC - Poke" -v tempdevHub
```

## Status
**Phase 1 (the player-facing game) and Phase 2a (the reward engine) are complete, deployed, and packaged** — `force-app/` is the source of truth, and version `0.1.2-1` (Released) captures all of it. The remaining work is **Phase 2b: subscriber rollout** (install → admin-created rule rows → the 5 one-line trigger hooks in the LSC repo → pilot). The complete rollout guide — checklist, rule matrix, and live-verified trigger facts — is an internal doc kept local, out of version control.

Dev/test happens in the **`lscPokemonUnlocked`** scratch org (the CLI default `target-org`). It has **no LSC1 installed** — nothing in the package names an LSC object — and it **expires 2026-07-20**; the package version outlives it, so nothing is lost when it does.

## Dev loop
```bash
# Validate first, then deploy — changed components only, RunSpecifiedTests with the touched tests
sf project deploy validate -m "ApexClass:PokemonRewardEngine" -l RunSpecifiedTests -t PokemonRewardEngine_Test -o lscPokemonUnlocked
sf project deploy start    -m "ApexClass:PokemonRewardEngine" -l RunSpecifiedTests -t PokemonRewardEngine_Test -o lscPokemonUnlocked

# Whole-package operations go through the single manifest (Phase 1 + 2a merged)
sf project deploy start -x manifest/pokemonProject.xml -o lscPokemonUnlocked

# Regenerate the species seed anytime (defaults to Dex #1–493)
python3 scripts/generateSpeciesSeed.py
```
Deploys from this repo routinely report **phantom source-tracking conflicts** — verify once that the org copy is unchanged (Tooling API body diff), then re-run with `--ignore-conflicts`.

## Apex (6 classes + 5 tests)
| Class | Purpose |
|---|---|
| `pokemonGameController` | Thin `@AuraEnabled` surface — onboarding, biome encounters, catch, power-up, mart, trade, release, rename, set rival. Server-authoritative economy. |
| `pokemonGameHelper` | Shared mechanics for the controller — record builders, `FOR UPDATE` locks, settings accessors, weighted encounters, encrypted single-use encounter tokens. |
| `pokemonCatchLogic` | Pure catch-probability, shiny, and growth-curve math. No SOQL/DML/callout. |
| `PokemonSpeciesService` | Reads the species catalog from the `pokemonSpeciesSeed` static resource; returns species by Pokedex number. |
| `pokemonTrainerOrgHelper` | Before-trigger helper for `Pokemon_Trainer__c` — clamps currency/XP/ball/stone counts non-negative, stamps `Trainer_Key__c` from the owner. |
| `PokemonRewardEngine` | Object-agnostic, config-driven reward engine — one `run()` call a subscriber adds to their own after-triggers; owner-only, kill-switched, never rethrows. |

Tests: `pokemonGameController_Test` (covers controller + helper), `pokemonCatchLogic_Test`, `PokemonSpeciesService_Test`, `pokemonTrainerOrgHelper_Test`, `PokemonRewardEngine_Test`.

## Layout
```
docs/pokemon-field-guide.html     the field guide — Program overview, how-to with screenshots,
                                    under-the-hood engineering (standalone, self-contained)
sfdx-project.json                 unlocked package "LSC - Poke", no namespace, package version aliases
config/project-scratch-def.json   scratch org definition
manifest/pokemonProject.xml       THE manifest (Phase 1 + 2a merged) — every member resolves to a file
                                    on disk; deploys clean (NO reward-rule rows ship; subscribers create them)
scripts/                          generateSpeciesSeed.py (seed from PokeAPI), generateBiomePools.py,
                                    generateTallGrass.py
refs/                             git-ignored local mirror of ../LSC/force-app (home of the 5 hook triggers);
                                    known stale — re-sync: cp -R ../LSC/force-app/main/default/. refs/
force-app/main/default/           the package source
  applications/    Pokemon_Home
  classes/         the 6 classes + 5 tests above
  customMetadata/  Pokemon_Settings.Default + the 6 biomes (Verdant Meadow, Azure Shore, Rocky Cavern,
                     Scorched Summit, Mystic Mirage, Spectral Graveyard)
  cspTrustedSites/ PokeAPI (connect-src), PokeApiSprites (img-src)
  flexipages/      Trainer_Hub, Biomes, Poke_Mart
  globalValueSets/ Pokemon_Type
  layouts/         Pokemon__c, Pokemon_Trainer__c
  lwc/             professorOakOnboarding, trainerDashboard, biomeExplorer, wildEncounterModal,
                     pokeMartContainer, pokemonCard, pokemonApiService, pokemonBasics
  objects/         Pokemon_Trainer__c, Pokemon__c + Pokemon_Settings__mdt, Pokemon_Biome__mdt,
                     Pokemon_Reward_Rule__mdt
  permissionsets/  Pokemon_Full_Access — the ONLY perm set (app visibility + objects + classes;
                     rival eligibility keys off holding it)
  staticresources/ pokemonSpeciesSeed.json (Gen 1–4, #1–493), ball + evolution-stone icons,
                     professorOak.png, tallGrassSway.gif
  tabs/            Trainer_Hub, Biomes, Poke_Mart, Pokemon__c, Pokemon_Trainer__c
  triggers/        pokemonTrainerOrgTrigger — the only packaged trigger (source-object hooks are
                     subscriber-owned; see the PokemonRewardEngine header)
```

## Standards
Model new code on the existing classes and components under `force-app/` — match their structure, naming, and idiom. Descriptive, self-documenting variables; minimal comments; targeted changes.
