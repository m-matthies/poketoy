#!/usr/bin/env python3
"""Downloads the starter Pokémon's sprites and portraits from SpriteCollab into Resources/.

Only the sprite sheets PokeToy uses are kept (mirrors PetAnim.candidates in Sources/PokeToyCore/PetAnim.swift),
plus the portraits the emotion bubbles use. Run from the repository root: ./scripts/bundle-starters.py
"""
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
    with urllib.request.urlopen(BASE + path, timeout=30) as response:
        return response.read()


def save(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data)


def bundle_sprites(dex):
    xml = fetch(f"sprite/{dex}/AnimData.xml")
    anims = {}
    for anim in ET.fromstring(xml).iter("Anim"):
        name = anim.findtext("Name")
        anims[name] = anim.findtext("CopyOf") or name
    sheets = set()
    for candidates in CANDIDATES:
        chosen = next((anims[c] for c in candidates if c in anims), None)
        if chosen:
            sheets.add(chosen)
    save(f"Resources/Sprites/{dex}/AnimData.xml", xml)
    for sheet in sorted(sheets):
        save(f"Resources/Sprites/{dex}/{sheet}-Anim.png", fetch(f"sprite/{dex}/{sheet}-Anim.png"))
    print(f"{dex}: sprites {', '.join(sorted(sheets))}")


def bundle_portraits(dex):
    found = []
    for name in PORTRAITS:
        try:
            save(f"Resources/Portraits/{dex}/{name}.png", fetch(f"portrait/{dex}/{name}.png"))
            found.append(name)
        except urllib.error.HTTPError as error:
            if error.code != 404:
                raise
    print(f"{dex}: portraits {', '.join(found)}")


if __name__ == "__main__":
    for dex in sys.argv[1:] or STARTERS:
        bundle_sprites(dex)
        bundle_portraits(dex)
