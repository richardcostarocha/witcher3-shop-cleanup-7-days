# Limpeza de Loja em 7 dias | Shop Cleanup in 7 Days

The Witcher 3 mod by **yero_gamer**, version **0.4.9**.

[Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3818384556) · [Português](README.pt-BR.md) · [Development](docs/DEVELOPMENT.md)

Merchants resell items registered when you sell to them. After seven in-game days, talk to that merchant: registered units leave their stock and the merchant receives 125% of the amount originally paid, rounded down. The player receives only the original sale payment.

## Features

- Each merchant has an independent round. Later sales join an existing pending round; buyback cancels the repurchased units.
- A pause-menu dashboard groups waiting rounds and ready rounds that require a shop visit. Records follow the loaded save.
- Saved last-seen location references use a nearby discovered fast-travel signpost and region.
- Manual cancellation, with confirmation, clears a shop's pending round without removing stock or granting resale income.
- Keira's pending round is cancelled upon her actual death while this version is active. Earlier deaths are not detected retroactively.
- The Kaer Trolde harbor herbalist is excluded from new rounds because the game recreates his merchant instance. Normal trading remains available. Old orphaned entries can be cancelled manually.

Only items recorded by the mod are processed. Original stock, protected items, recipes/maps and sales made before installation are not forcibly cleared. The dashboard does not complete unloaded merchants automatically; visit the shop to finish a ready round. A last-seen reference is not live tracking.

## Install and develop

Subscribe through Steam Workshop and restart after synchronization. Removal is through unsubscribing. Stock/crown changes already saved remain in the save. Complete the desired pending rounds before removing the mod. Keep a single active copy.

`mods/modLojasRenovadas7Dias/content/scripts/` contains all eight source scripts. Local checks and packaging require Python 3.10+ and Node.js 18+, with no third-party packages:

```sh
python tools/project.py verify
python tests/run.py
python tools/project.py build
```

The default build is a folder in `dist/`, not an installer or an automatic upload. See [development instructions](docs/DEVELOPMENT.md). The food mod is optional and [independent](https://github.com/richardcostarocha/witcher3-food-extra-potion).

Other mods replacing the same merchant/NPC, game, dialogue, shop or pause-menu scripts may need merging. Tests cover the transaction logic with mocks; native behavior was checked in the author's game for rounds, buyback, multiple merchants, save/load, manual cancellation, Keira and saved location references. No large-merchant-count performance benchmark or general crash fix is claimed.
