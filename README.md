# FS25_PalletSystem

Mod Farming Simulator 25 qui oblige les productions (`ProductionPoint`) et les
bâtiments d'animaux (`Husbandry`) à consommer une palette vide avant de
pouvoir faire apparaître une palette pleine du produit fini.

Farming Simulator 25 mod that requires productions (`ProductionPoint`) and
animal husbandry buildings (`Husbandry`) to consume an empty pallet before
spawning a full pallet of the finished product.

**[🇫🇷 Français](#français) | [🇬🇧 English](#english)**

---

<a name="français"></a>
## 🇫🇷 Français

### Sommaire

- [Fonctionnement](#fonctionnement)
- [Prérequis](#prérequis)
- [Installation](#installation)
- [Réglages](#réglages)
- [Commandes console](#commandes-console)
- [Compatibilité](#compatibilité)
- [Structure du projet](#structure-du-projet)
- [Roadmap / travaux en cours](#roadmap--travaux-en-cours)
- [Signaler un bug](#signaler-un-bug)
- [Licence](#licence)

### Fonctionnement

Le mod s'accroche sur `PalletSpawner:spawnPallet` et
`PalletSpawner:getOrSpawnPallet`, partagés par les usines et les bâtiments
d'animaux. Avant qu'une palette pleine soit créée, une unité du fillType
`EMPTYPALLET` doit être consommée dans la zone de spawn du bâtiment. Ce
fillType doit être fourni par un mod séparé ("fabricant" de palettes vides) —
`FS25_PalletSystem` ne le crée pas lui-même.

### Prérequis

- Farming Simulator 25
- Un mod tiers définissant le fillType `EMPTYPALLET` (palette-conteneur
  livrable sur les zones de spawn). Sans ce mod, `FS25_PalletSystem` se met
  automatiquement en mode transparent : aucune production n'est bloquée.

### Installation

1. Récupère le dossier `FS25_PalletSystem` (ou le zip publié dans les
   [Releases](../../releases) une fois disponibles).
2. Place-le dans `Documents/My Games/FarmingSimulator2025/mods/`.
3. Active le mod dans le sélecteur de mods au lancement d'une partie.

### Réglages

Deux interrupteurs indépendants, accessibles depuis l'onglet **Réglages** du
jeu ou par commande console :

| Réglage | Défaut | Effet |
|---|---|---|
| Animaux (husbandry) | désactivé | Oblige les bâtiments d'élevage à recevoir une palette vide |
| Usines (production) | désactivé | Oblige les usines de transformation à recevoir une palette vide |

Chaque bâtiment peut aussi être désactivé individuellement via
`psToggleSpawner`, indépendamment du réglage global de son type.

Les réglages sont persistés par sauvegarde dans
`modSettings/palletSystem.xml` (et non dans le dossier de la sauvegarde, qui
est réinitialisé par le jeu à chaque sauvegarde).

### Commandes console

| Commande | Usage | Effet |
|---|---|---|
| `psToggleHusbandry` | `psToggleHusbandry [0\|1]` | Active/désactive l'obligation pour les bâtiments d'animaux |
| `psToggleProduction` | `psToggleProduction [0\|1]` | Active/désactive l'obligation pour les usines |
| `psList` | `psList [farmId]` | Liste les bâtiments détectés, leur type, ferme et état |
| `psToggleSpawner` | `psToggleSpawner <numero> [0\|1]` | Active/désactive l'obligation pour un bâtiment précis |
| `psCheckFile` | `psCheckFile` | Diagnostic du fichier de réglages |

### Compatibilité

- **FS25_ProductionStorageControl (PSC)** : détecté automatiquement au
  runtime (aucune dépendance XML nécessaire). Le spawn manuel via PSC
  respecte la même obligation de palette vide que le spawn natif.

### Structure du projet

```
FS25_PalletSystem/
├── modDesc.xml
├── icon_palletSystem.dds
├── LICENSE.md
├── README.md
└── scripts/
    ├── PalletSystem.lua
    └── PalletSystemRefund.lua
```

La localisation (français/anglais) est intégrée directement dans
`modDesc.xml` — il n'y a pas de fichiers de traduction séparés.

### Roadmap / travaux en cours

- [ ] Confirmation en jeu du système de remboursement (`PalletSystemRefund.lua`)
- [ ] Mécanique de réduction de coût de production (champs `costsPerActiveHour`
      / `costsPerActiveMonth` / `costsPerActiveMinute` confirmés lisibles,
      logique non encore implémentée)
- [ ] Vérification de fonctions API incertaines (`getUserProfileAppPath()`,
      `createFolder()`, enregistrement `XMLSchema.new()`) face aux sources
      réelles du jeu

### Signaler un bug

Les retours de la communauté sont les bienvenus via l'onglet
[Issues](../../issues). Merci d'indiquer :

- la version du jeu et la liste des mods actifs (en particulier le mod
  fournissant `EMPTYPALLET`),
- les étapes pour reproduire le problème,
- un extrait pertinent du `log.txt`.

### Licence

Tous droits réservés. Consultation et usage en jeu libres ; redistribution,
reupload, portage ou intégration dans un autre mod interdits sans
autorisation écrite préalable de l'auteur. Voir le fichier
[`LICENSE.md`](LICENSE.md) (texte complet, bilingue) pour le détail exact de
ce qui est permis et interdit.

---

<a name="english"></a>
## 🇬🇧 English

### Table of contents

- [How it works](#how-it-works)
- [Requirements](#requirements)
- [Installation-en](#installation-en)
- [Settings](#settings)
- [Console commands](#console-commands)
- [Compatibility](#compatibility)
- [Project structure](#project-structure)
- [Roadmap / work in progress](#roadmap--work-in-progress)
- [Reporting a bug](#reporting-a-bug)
- [License](#license)

### How it works

The mod hooks into `PalletSpawner:spawnPallet` and
`PalletSpawner:getOrSpawnPallet`, shared by production buildings and animal
husbandry buildings. Before a full pallet is created, one unit of the
`EMPTYPALLET` fillType must be consumed within the building's spawn zone.
This fillType must be provided by a separate mod (an empty-pallet
"manufacturer") — `FS25_PalletSystem` does not create it itself.

### Requirements

- Farming Simulator 25
- A third-party mod defining the `EMPTYPALLET` fillType (a pallet container
  that can be delivered to spawn zones). Without this mod,
  `FS25_PalletSystem` automatically switches to transparent mode: no
  production is blocked.

### Installation-en

1. Get the `FS25_PalletSystem` folder (or the zip published in
   [Releases](../../releases) once available).
2. Place it in `Documents/My Games/FarmingSimulator2025/mods/`.
3. Enable the mod in the mod selector when starting a savegame.

### Settings

Two independent toggles, available from the game's **Settings** tab or via
console commands:

| Setting | Default | Effect |
|---|---|---|
| Husbandry | disabled | Requires animal buildings to receive an empty pallet |
| Production | disabled | Requires production buildings to receive an empty pallet |

Each building can also be disabled individually via `psToggleSpawner`,
independently of its type's global setting.

Settings are persisted per savegame in `modSettings/palletSystem.xml` (not
in the savegame folder, which the game wipes on every save).

### Console commands

| Command | Usage | Effect |
|---|---|---|
| `psToggleHusbandry` | `psToggleHusbandry [0\|1]` | Toggles the requirement for animal buildings |
| `psToggleProduction` | `psToggleProduction [0\|1]` | Toggles the requirement for production buildings |
| `psList` | `psList [farmId]` | Lists detected buildings, their type, farm, and state |
| `psToggleSpawner` | `psToggleSpawner <number> [0\|1]` | Toggles the requirement for a specific building |
| `psCheckFile` | `psCheckFile` | Diagnostics for the settings file |

### Compatibility

- **FS25_ProductionStorageControl (PSC)**: detected automatically at
  runtime (no XML dependency required). Manual spawning via PSC respects
  the same empty-pallet requirement as native spawning.

### Project structure

```
FS25_PalletSystem/
├── modDesc.xml
├── icon_palletSystem.dds
├── LICENSE.md
├── README.md
└── scripts/
    ├── PalletSystem.lua
    └── PalletSystemRefund.lua
```

Localization (French/English) is embedded directly in `modDesc.xml` — there
are no separate translation files.

### Roadmap / work in progress

- [ ] In-game confirmation of the refund system (`PalletSystemRefund.lua`)
- [ ] Production cost reduction mechanic (`costsPerActiveHour` /
      `costsPerActiveMonth` / `costsPerActiveMinute` fields confirmed
      readable, logic not yet implemented)
- [ ] Verification of uncertain API functions (`getUserProfileAppPath()`,
      `createFolder()`, `XMLSchema.new()` registration) against real game
      source files

### Reporting a bug

Community feedback is welcome via the [Issues](../../issues) tab. Please
include:

- the game version and the list of active mods (especially the mod
  providing `EMPTYPALLET`),
- steps to reproduce the issue,
- a relevant excerpt from `log.txt`.

### License

All rights reserved. Browsing and in-game use are free; redistribution,
reuploading, porting, or incorporation into another mod are prohibited
without the author's prior written permission. See [`LICENSE.md`](LICENSE.md)
(full bilingual text) for the exact details of what is permitted and
prohibited.
