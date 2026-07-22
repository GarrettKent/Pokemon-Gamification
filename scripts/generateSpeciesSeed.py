#!/usr/bin/env python3
# Title: generateSpeciesSeed
# Created By: Garrett Kent - 06/20/2026
# Purpose: One-time / regenerable build-time generator for pokemonSpeciesSeed.json.
#          Pulls /pokemon/{id} + /pokemon-species/{id} + the species evolution chain from PokeAPI
#          for a dex range, trims to the doc-01 seed shape, normalizes growthRate to the canonical 6,
#          captures level-up evolution (evolveLevel + evolvesToDex), stone/use-item evolution
#          (stoneEvolutions: {item -> evolvesToDex}), and friendship evolution (evolvesByFriendship),
#          validates every entry, and writes the seed + an anomaly report.
#          Values come from PokeAPI, never authored by hand. Honors fair-use (local cache).
# Usage:   python3 generateSpeciesSeed.py [START] [END]   (defaults 1 493 = Gen 1-4)

import json, os, subprocess, sys, time
from concurrent.futures import ThreadPoolExecutor, as_completed

START = int(sys.argv[1]) if len(sys.argv) > 1 else 1
END = int(sys.argv[2]) if len(sys.argv) > 2 else 493
WORKERS = 8
BASE = "https://pokeapi.co/api/v2"
CACHE = "/tmp/pokeseed_cache"
_HERE = os.path.dirname(os.path.abspath(__file__))
# Write the seed straight into its deploy home (the package static resource).
OUT = os.path.normpath(os.path.join(_HERE, "..", "force-app", "main", "default", "staticresources", "pokemonSpeciesSeed.json"))
REPORT = os.path.join(_HERE, "pokemonSpeciesSeed.report.txt")

os.makedirs(CACHE, exist_ok=True)

VALID_TYPES = {
    "normal", "fighting", "flying", "poison", "ground", "rock", "bug", "ghost",
    "steel", "fire", "water", "grass", "electric", "psychic", "ice", "dragon",
    "dark", "fairy"
}
# PokeAPI growth_rate.name -> canonical 6 used by the seed AND the Apex growth-curve constants.
GROWTH_MAP = {
    "fast": "fast",
    "medium": "medium",
    "medium-slow": "medium-slow",
    "slow": "slow",
    "slow-then-very-fast": "erratic",
    "fast-then-very-slow": "fluctuating"
}
VALID_GROWTH = set(GROWTH_MAP.values())


def curl(url, dest):
    if os.path.exists(dest) and os.path.getsize(dest) > 0:
        return
    last = ""
    for attempt in range(4):
        r = subprocess.run(
            ["curl", "-sS", "-fL", "--max-time", "30",
             "-H", "User-Agent: LSC-Pokemon-Seed/1.0 (one-time build pull)",
             url, "-o", dest],
            capture_output=True, text=True
        )
        if r.returncode == 0 and os.path.exists(dest) and os.path.getsize(dest) > 0:
            return
        last = r.stderr
        time.sleep(1.5 * (attempt + 1))
    raise RuntimeError("failed %s: %s" % (url, last))


def url_tail_id(url):
    return int(url.rstrip("/").split("/")[-1])


def fetch_one(i):
    curl("%s/pokemon/%d" % (BASE, i), "%s/pokemon_%d.json" % (CACHE, i))
    curl("%s/pokemon-species/%d" % (BASE, i), "%s/species_%d.json" % (CACHE, i))
    # The evolution chain lives on the species payload; cache it once per chain id (families share a chain).
    with open("%s/species_%d.json" % (CACHE, i)) as fh:
        sp = json.load(fh)
    chain_url = (sp.get("evolution_chain") or {}).get("url")
    if chain_url:
        chain_id = url_tail_id(chain_url)
        curl(chain_url, "%s/chain_%d.json" % (CACHE, chain_id))
    return i


def english_name(species):
    for n in species.get("names", []):
        if n.get("language", {}).get("name") == "en":
            return n.get("name")
    return species.get("name", "").capitalize()


def find_chain_node(node, species_name):
    if node.get("species", {}).get("name") == species_name:
        return node
    for child in node.get("evolves_to", []):
        found = find_chain_node(child, species_name)
        if found:
            return found
    return None


def level_up_evolution(node):
    # First level-up evolution (with a concrete min_level) reachable from this node, else (None, None).
    for child in node.get("evolves_to", []):
        for detail in child.get("evolution_details", []):
            if detail.get("trigger", {}).get("name") == "level-up" and detail.get("min_level"):
                return detail["min_level"], url_tail_id(child["species"]["url"])
    return None, None


def use_item_evolutions(node):
    # All stone (use-item) evolutions reachable from this node -> {item_name: evolvesToDex}.
    # Captures every Gen 1-4 use-item evolution; the Poke Mart stocks only a subset of stones.
    stoneEvolutions = {}
    for child in node.get("evolves_to", []):
        for detail in child.get("evolution_details", []):
            if detail.get("trigger", {}).get("name") == "use-item" and detail.get("item"):
                stoneEvolutions[detail["item"]["name"]] = url_tail_id(child["species"]["url"])
    return stoneEvolutions


def evolves_by_friendship(node):
    # True when this species evolves by high friendship: PokeAPI models these as a level-up trigger
    # carrying min_happiness (and no fixed min_level). Covers the Gen 1-4 friendship line
    # (Golbat -> Crobat, Chansey -> Blissey, the baby Pokemon, Eevee -> Espeon/Umbreon, ...).
    for child in node.get("evolves_to", []):
        for detail in child.get("evolution_details", []):
            if detail.get("trigger", {}).get("name") == "level-up" and detail.get("min_happiness"):
                return True
    return False


def build():
    errors = []
    with ThreadPoolExecutor(max_workers=WORKERS) as ex:
        futs = {ex.submit(fetch_one, i): i for i in range(START, END + 1)}
        for f in as_completed(futs):
            i = futs[f]
            try:
                f.result()
            except Exception as e:
                errors.append((i, str(e)))

    if errors:
        for i, e in sorted(errors):
            print("FETCH ERROR #%d: %s" % (i, e))
        raise SystemExit("Aborting: %d fetch errors" % len(errors))

    seed = {}
    anomalies = []
    evolvers = 0
    stone_evolvers = 0
    friendship_evolvers = 0
    for i in range(START, END + 1):
        with open("%s/pokemon_%d.json" % (CACHE, i)) as fh:
            pk = json.load(fh)
        with open("%s/species_%d.json" % (CACHE, i)) as fh:
            sp = json.load(fh)

        stats = {s["stat"]["name"]: s["base_stat"] for s in pk["stats"]}
        types = sorted(pk["types"], key=lambda t: t["slot"])
        type1 = types[0]["type"]["name"]
        type2 = types[1]["type"]["name"] if len(types) > 1 else None
        raw_growth = sp["growth_rate"]["name"]
        growth = GROWTH_MAP.get(raw_growth, raw_growth)

        entry = {
            "name": english_name(sp),
            "type1": type1,
        }
        if type2:
            entry["type2"] = type2
        entry.update({
            "hp": stats.get("hp"),
            "attack": stats.get("attack"),
            "defense": stats.get("defense"),
            "spAtk": stats.get("special-attack"),
            "spDef": stats.get("special-defense"),
            "speed": stats.get("speed"),
            "captureRate": sp.get("capture_rate"),
            "growthRate": growth
        })
        # Rarity flags from the species endpoint (only emitted when true, like type2).
        if sp.get("is_legendary"):
            entry["isLegendary"] = True
        if sp.get("is_mythical"):
            entry["isMythical"] = True

        # Level-up evolution (only emitted when this species evolves by leveling to a fixed level).
        chain_url = (sp.get("evolution_chain") or {}).get("url")
        if chain_url:
            chain_path = "%s/chain_%d.json" % (CACHE, url_tail_id(chain_url))
            if os.path.exists(chain_path):
                with open(chain_path) as fh:
                    chain = json.load(fh)
                node = find_chain_node(chain.get("chain", {}), sp.get("name"))
                if node:
                    evolve_level, evolves_to_dex = level_up_evolution(node)
                    if evolve_level:
                        entry["evolveLevel"] = evolve_level
                        entry["evolvesToDex"] = evolves_to_dex
                        evolvers += 1
                    stone_evos = use_item_evolutions(node)
                    if stone_evos:
                        entry["stoneEvolutions"] = stone_evos
                        stone_evolvers += 1
                    if evolves_by_friendship(node):
                        entry["evolvesByFriendship"] = True
                        friendship_evolvers += 1

        entry["image"] = "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/other/official-artwork/%d.png" % i

        # validation
        if type1 not in VALID_TYPES:
            anomalies.append("#%d %s: type1 '%s' not in 18-set" % (i, entry["name"], type1))
        if type2 and type2 not in VALID_TYPES:
            anomalies.append("#%d %s: type2 '%s' not in 18-set" % (i, entry["name"], type2))
        if growth not in VALID_GROWTH:
            anomalies.append("#%d %s: growthRate '%s' (raw '%s') not canonical" % (i, entry["name"], growth, raw_growth))
        for k in ("hp", "attack", "defense", "spAtk", "spDef", "speed"):
            if not isinstance(entry[k], int):
                anomalies.append("#%d %s: stat %s not int (%r)" % (i, entry["name"], k, entry[k]))
        cr = entry["captureRate"]
        if not isinstance(cr, int) or cr < 0 or cr > 255:
            anomalies.append("#%d %s: captureRate out of 0-255 (%r)" % (i, entry["name"], cr))
        if not entry["name"]:
            anomalies.append("#%d: empty name" % i)
        # flag non-ASCII names (correct, just worth noting: Nidoran, Mr. Mime, Ho-Oh, Farfetch'd...)
        try:
            entry["name"].encode("ascii")
        except UnicodeEncodeError:
            anomalies.append("#%d %s: non-ASCII display name (expected for some species)" % (i, entry["name"]))

        seed[str(i)] = entry

    ordered = {str(i): seed[str(i)] for i in range(START, END + 1)}
    with open(OUT, "w") as fh:
        json.dump(ordered, fh, ensure_ascii=False, indent=2)
        fh.write("\n")

    with open(REPORT, "w") as fh:
        fh.write("Species seed report (#%d-%d), %d entries\n" % (START, END, len(ordered)))
        fh.write("Level-up evolvers flagged: %d\n" % evolvers)
        fh.write("Stone (use-item) evolvers flagged: %d\n" % stone_evolvers)
        fh.write("Friendship evolvers flagged: %d\n" % friendship_evolvers)
        fh.write("Anomalies / items to confirm: %d\n" % len(anomalies))
        for a in anomalies:
            fh.write("  - %s\n" % a)

    size = os.path.getsize(OUT)
    print("WROTE %s (%d entries, %d bytes)" % (OUT, len(ordered), size))
    print("LEVEL-UP EVOLVERS: %d" % evolvers)
    print("STONE EVOLVERS: %d" % stone_evolvers)
    print("FRIENDSHIP EVOLVERS: %d" % friendship_evolvers)
    print("ANOMALIES: %d (see %s)" % (len(anomalies), REPORT))
    for a in anomalies:
        print("  - %s" % a)
    print("DONE")


if __name__ == "__main__":
    build()
