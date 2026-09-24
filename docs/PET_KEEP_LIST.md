# ServerStorage pet keep-list

Playable pet models are direct children of the flat `ServerStorage.Pets.Active` folder. The current release uses the following 34 model names.

## Current release assets

- `Bunny`
- `Fox`
- `Compass`
- `Ruler`
- `Stopwatch`
- `Scale`
- `MeasuringMug`
- `Tape`
- `MagnifyingGlass`
- `Microscope`
- `Ice Cream Kitty`
- `Dragon`
- `Water Dragon`
- `Fairy`
- `Glowing Bear`
- `Unicorn`
- `Galactic Queen`
- `Helios`
- `Dark Dragon`
- `Abyss Demon`
- `Abyssal Cerberus`
- `Evolved Abyssal Hydra`
- `Oceanic Kitty`
- `Oceanic Star`
- `Oceanic Winged Lord`
- `Evolved Oceanic Trio`
- `Sun Cat`
- `Sun Doubull`
- `Sun Flare`
- `Evolved Solis`
- `Universal Megalodon`
- `Universal Phoenix`
- `Universal Leviathan`
- `Universal Yatagarasu`

These assets cover all current egg shops, mystery blocks, the Golden Deal, daily rewards, AFK offers and NPC cosmetics.

## Legacy save compatibility

`CosmeticCatalog` still accepts these 33 old IDs so existing owners keep their saved pets. Their models are not currently obtainable. Delete them only if there are no production saves containing them, or if losing their visuals is acceptable:

- Cat
- Owl
- Phoenix
- Slime
- Bee
- Panda
- Tiger
- Griffin
- Spirit
- Golem
- Hydra
- Kitsune
- Celestial
- Infinity
- Dog
- Bear
- Bull
- Alien
- Deer
- Lizard
- Rabbit
- Spider
- Winged Fairy
- Dark Fairy
- Abyssal Hydra
- Oceanic Bunny
- Oceanic Fox
- Oceanic Diamond
- Evolved Oceanic Diamond
- Sun Bunny
- Sun Fox
- Universal Hybrid
- Frog

Everything under `ServerStorage.Pets.InActive` is ignored by both the main game and AFK preview publisher. It can be retained as an archive or deleted without being loaded at runtime.
