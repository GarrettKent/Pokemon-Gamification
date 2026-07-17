#!/usr/bin/env python3
# Title: generateBiomePools
# Created By: Garrett Kent - 06/20/2026
# Purpose: Build-time, API-conscious generator for the tiered encounter pools written into the three
#          Pokemon_Biome custom-metadata records. Reads ONLY the local pokemonSpeciesSeed.json (no PokeAPI
#          calls), buckets each biome's theme-matching species into common/uncommon/rare by captureRate,
#          deterministically caps each tier, excludes legendaries/mythicals, and rewrites the
#          Encounters_Json__c value (compact single-line) plus Grass_Patch_Count__c=4 in each md-meta.xml.
#          The tier thresholds, caps, selection, themes, and entry shape mirror the Apex controller exactly.
# Usage:   python3 generateBiomePools.py

import json, os, re

_HERE = os.path.dirname(os.path.abspath(__file__))
_DEFAULT = os.path.join(_HERE, "..", "force-app", "main", "default")
SEED = os.path.normpath(os.path.join(_DEFAULT, "staticresources", "pokemonSpeciesSeed.json"))
META_DIR = os.path.normpath(os.path.join(_DEFAULT, "customMetadata"))

GRASS_PATCH_COUNT = 4

# Tier thresholds on captureRate (shared byte-for-byte in meaning with the Apex TierForCaptureRate).
def tier_for_capture_rate(capture_rate):
    if capture_rate >= 120:
        return "common"
    if capture_rate >= 45:
        return "uncommon"
    return "rare"

# Per-tier pool caps.
TIER_CAPS = {"common": 50, "uncommon": 25, "rare": 5}

# Biome theme type-sets: a species qualifies if its type1 OR type2 is in the set.
BIOME_THEMES = {
    "Verdant_Meadow": {"grass", "bug", "normal", "flying"},
    "Rocky_Cavern": {"rock", "ground", "steel", "fighting", "poison", "dark"},
    "Azure_Shore": {"water", "ice", "flying", "normal"}
}


def load_seed():
    with open(SEED) as fh:
        return json.load(fh)


def biome_candidates(seed, theme_types):
    # Returns species dicts (with dex + captureRate + tier) whose type1/type2 hits the theme,
    # excluding legendaries and mythicals.
    candidates = []
    for dex_key, entry in seed.items():
        if entry.get("isLegendary") or entry.get("isMythical"):
            continue
        type1 = entry.get("type1")
        type2 = entry.get("type2")
        if type1 not in theme_types and type2 not in theme_types:
            continue
        capture_rate = entry["captureRate"]
        candidates.append({
            "dex": int(dex_key),
            "captureRate": capture_rate,
            "tier": tier_for_capture_rate(capture_rate)
        })
    return candidates


def select_tier(candidates, tier):
    members = [c for c in candidates if c["tier"] == tier]
    cap = TIER_CAPS[tier]
    if tier == "rare":
        # The rarest / most prized: lowest captureRate first, then dex ascending.
        members.sort(key=lambda c: (c["captureRate"], c["dex"]))
    else:
        # common / uncommon: highest captureRate first, then dex ascending.
        members.sort(key=lambda c: (-c["captureRate"], c["dex"]))
    return members[:cap]


def build_pool(seed, theme_types):
    candidates = biome_candidates(seed, theme_types)
    raw_counts = {
        "common": sum(1 for c in candidates if c["tier"] == "common"),
        "uncommon": sum(1 for c in candidates if c["tier"] == "uncommon"),
        "rare": sum(1 for c in candidates if c["tier"] == "rare")
    }
    common = select_tier(candidates, "common")
    uncommon = select_tier(candidates, "uncommon")
    rare = select_tier(candidates, "rare")
    # Ordered: common (cr desc) first, then uncommon, then rare.
    ordered = common + uncommon + rare
    entries = [{"dex": c["dex"], "tier": c["tier"]} for c in ordered]
    selected_counts = {"common": len(common), "uncommon": len(uncommon), "rare": len(rare)}
    return entries, raw_counts, selected_counts


def replace_value(xml, field, new_value, type_attr):
    # Replace the <value> inside the <values> block whose <field> matches, preserving everything else.
    pattern = re.compile(
        r"(<values>\s*<field>" + re.escape(field) + r"</field>\s*<value[^>]*>)(.*?)(</value>)",
        re.DOTALL
    )
    replacement = lambda m: '%s%s%s' % (
        re.sub(r'xsi:type="[^"]*"', 'xsi:type="%s"' % type_attr, m.group(1)),
        new_value,
        m.group(3)
    )
    updated, count = pattern.subn(replacement, xml)
    if count != 1:
        raise RuntimeError("expected exactly 1 '%s' value block, found %d" % (field, count))
    return updated


def write_biome(biome_name, entries):
    path = os.path.join(META_DIR, "Pokemon_Biome.%s.md-meta.xml" % biome_name)
    with open(path) as fh:
        xml = fh.read()
    encounters = json.dumps(entries, separators=(",", ":"))
    xml = replace_value(xml, "Encounters_Json__c", encounters, "xsd:string")
    xml = replace_value(xml, "Grass_Patch_Count__c", str(GRASS_PATCH_COUNT), "xsd:double")
    with open(path, "w") as fh:
        fh.write(xml)
    return path


def build():
    seed = load_seed()
    print("Loaded %d species from %s" % (len(seed), SEED))
    for biome_name, theme_types in BIOME_THEMES.items():
        entries, raw_counts, selected_counts = build_pool(seed, theme_types)
        path = write_biome(biome_name, entries)
        print("\n%s (theme: %s)" % (biome_name, ", ".join(sorted(theme_types))))
        print("  candidates -> common %d / uncommon %d / rare %d" %
              (raw_counts["common"], raw_counts["uncommon"], raw_counts["rare"]))
        print("  selected   -> common %d / uncommon %d / rare %d (total %d)" %
              (selected_counts["common"], selected_counts["uncommon"], selected_counts["rare"], len(entries)))
        print("  wrote %s (Grass_Patch_Count__c=%d)" % (path, GRASS_PATCH_COUNT))
    print("\nDONE")


if __name__ == "__main__":
    build()
