#!/usr/bin/env python3
"""Bundles SpriteCollab sprites and portraits into Resources/ so they ship with the app.

By default: every species SpriteCollab marks as fully complete (base forms), plus the four starters. Only the sprite
sheets PokeToy uses are kept (mirrors PetAnim.candidates in Sources/PokeToyCore/PetAnim.swift), plus the portraits the
emotion bubbles use. Also writes Resources/Sprites/names.json ({"0025": "Pikachu", …}) so names work offline.

Run from the repository root: ./scripts/bundle-sprites.py            (all complete species)
                              ./scripts/bundle-sprites.py 0025 0133  (just these)
Files already present are skipped, so it can be re-run to fill gaps.
"""
import concurrent.futures
import json
import os
import sys
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET

BASE = "https://raw.githubusercontent.com/PMDCollab/SpriteCollab/master/"
STARTERS = ["0025", "0004", "0007", "0001"]
# PetAnim.candidates: the first one a sprite has is used.
CANDIDATES = [
    ["Idle", "Walk"], ["Walk", "Idle"], ["Sleep", "EventSleep", "Laying", "Idle", "Walk"],
    ["Hop", "Pose", "Idle", "Walk"], ["Hurt", "Idle", "Walk"], ["Eat", "Nod", "Idle", "Walk"],
    ["Nod", "Pose", "Hop", "Idle", "Walk"], ["Attack", "Swing", "Hop", "Idle", "Walk"],
    ["Cringe", "Pain", "Hurt", "Idle", "Walk"], ["Sit", "Idle", "Walk"], ["Wake", "Idle", "Walk"],
    ["Shoot", "Charge", "Attack", "Idle", "Walk"],
]
# Emotion.portraitNames, all of them.
PORTRAITS = ["Normal", "Happy", "Joyous", "Sad", "Teary-Eyed", "Crying", "Angry", "Determined", "Surprised",
             "Stunned", "Pain", "Dizzy"]


def fetch(path):
    with urllib.request.urlopen(BASE + path, timeout=60) as response:
        return response.read()


def save(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data)


def bundle_sprites(dex):
    xml_path = f"Resources/Sprites/{dex}/AnimData.xml"
    xml = open(xml_path, "rb").read() if os.path.exists(xml_path) else fetch(f"sprite/{dex}/AnimData.xml")
    anims = {}
    for anim in ET.fromstring(xml).iter("Anim"):
        name = anim.findtext("Name")
        anims[name] = anim.findtext("CopyOf") or name
    sheets = set()
    for candidates in CANDIDATES:
        chosen = next((anims[c] for c in candidates if c in anims), None)
        if chosen:
            sheets.add(chosen)
    for sheet in sorted(sheets):
        target = f"Resources/Sprites/{dex}/{sheet}-Anim.png"
        if not os.path.exists(target):
            save(target, fetch(f"sprite/{dex}/{sheet}-Anim.png"))
    save(xml_path, xml)  # written last: marks the set as complete


def bundle_portraits(dex):
    for name in PORTRAITS:
        target = f"Resources/Portraits/{dex}/{name}.png"
        if os.path.exists(target):
            continue
        try:
            save(target, fetch(f"portrait/{dex}/{name}.png"))
        except urllib.error.HTTPError as error:
            if error.code != 404:
                raise


def bundle(dex):
    bundle_sprites(dex)
    bundle_portraits(dex)
    return dex


def credit_names():
    """Credit id -> display name, from SpriteCollab's credit_names.txt (contact details are never used)."""
    names = {}
    for line in fetch("credit_names.txt").decode("utf-8").splitlines()[1:]:
        parts = line.split("\t")
        if len(parts) >= 2 and parts[0].strip():
            names[parts[1].strip()] = parts[0].strip()  # by Discord id
            names[parts[0].strip()] = parts[0].strip()  # by name
    return names


def artists(credit, known):
    """The people credited for a sprite or portrait set, by name; ids without a name stay anonymous."""
    if not credit:
        return []
    people = [credit.get("primary")] + list(credit.get("secondary") or [])
    result = []
    for person in people:
        if not person:
            continue
        name = known.get(person) or ("an unnamed contributor" if person.startswith("<@") else person)
        if name not in result:
            result.append(name)
    return result


def write_credits(tracker):
    """Resources/CREDITS.md: source, license and the artists of every bundled Pokémon."""
    known = credit_names()
    bundled = sorted(d for d in os.listdir("Resources/Sprites") if d.isdigit())
    lines = [
        "# Sprite and portrait credits",
        "",
        "The Pokémon sprites and portraits bundled with PokeToy (`Resources/Sprites`, `Resources/Portraits`) come from",
        "[PMDCollab SpriteCollab](https://sprites.pmdcollab.org/) ([GitHub](https://github.com/PMDCollab/SpriteCollab))",
        "and are licensed under [Creative Commons Attribution-NonCommercial 4.0 International (CC BY-NC 4.0)]"
        "(https://creativecommons.org/licenses/by-nc/4.0/) by their artists. Only the animation sheets and portraits",
        "PokeToy uses are included, unmodified. They may not be used commercially.",
        "",
        "Pokémon and Pokémon character names are trademarks of Nintendo, Creatures Inc. and GAME FREAK inc.",
        "PokeToy is an unofficial, non-commercial fan project and is not affiliated with or endorsed by them.",
        "",
        "| # | Pokémon | Sprites by | Portraits by |",
        "|---|---|---|---|",
    ]
    for dex in bundled:
        node = tracker.get(dex, {})
        sprites = ", ".join(artists(node.get("sprite_credit"), known)) or "—"
        portraits = ", ".join(artists(node.get("portrait_credit"), known)) or "—"
        lines.append(f"| {dex} | {node.get('name', dex)} | {sprites} | {portraits} |")
    with open("Resources/CREDITS.md", "w") as f:
        f.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    tracker = json.loads(fetch("tracker.json"))
    names_path = "Resources/Sprites/names.json"
    names = json.load(open(names_path)) if os.path.exists(names_path) else {}
    if sys.argv[1:]:
        wanted = sys.argv[1:]
    else:
        complete = [dex for dex, node in tracker.items() if dex != "0000" and node.get("sprite_complete", 0) >= 2]
        wanted = sorted(set(complete) | set(STARTERS))
    failed = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        futures = {pool.submit(bundle, dex): dex for dex in wanted}
        for count, future in enumerate(concurrent.futures.as_completed(futures), 1):
            dex = futures[future]
            try:
                future.result()
                names[dex] = tracker.get(dex, {}).get("name", names.get(dex, f"Pokémon #{dex}"))
            except Exception as error:  # noqa: BLE001 — report and carry on
                failed.append(dex)
                print(f"  {dex}: {error}", file=sys.stderr)
            if count % 20 == 0 or count == len(wanted):
                print(f"{count}/{len(wanted)} done")
    with open(names_path, "w") as f:
        json.dump(dict(sorted(names.items())), f, ensure_ascii=False, indent=0)
    write_credits(tracker)
    if failed:
        print(f"failed: {' '.join(sorted(failed))} — run again to retry", file=sys.stderr)
        sys.exit(1)
