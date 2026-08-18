# FS25_PalletSystem

Mod Farming Simulator 25 qui oblige les productions (`ProductionPoint`) et les
bâtiments d'animaux (`Husbandry`) à consommer une palette vide avant de
pouvoir faire apparaître une palette pleine du produit fini.

## Sommaire

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

## Fonctionnement

Le mod s'accroche sur `PalletSpawner:spawnPallet` et
`PalletSpawner:getOrSpawnPallet`, partagés par les usines et les bâtiments
d'animaux. Avant qu'une palette pleine soit créée, une unité du fillType
`EMPTYPALLET` doit être consommée dans la zone de spawn du bâtiment. Ce
fillType doit être fourni par un mod séparé ("fabricant" de palettes vides) —
`FS25_PalletSystem` ne le crée pas lui-même.

## Prérequis

- Farming Simulator 25
- Un mod tiers définissant le fillType `EMPTYPALLET` (palette-conteneur
  livrable sur les zones de spawn). Sans ce mod, `FS25_PalletSystem` se met
  automatiquement en mode transparent : aucune production n'est bloquée.

## Installation

1. Récupère le dossier `FS25_PalletSystem` (ou le zip publié dans les
   [Releases](../../releases) une fois disponibles).
2. Place-le dans `Documents/My Games/FarmingSimulator2025/mods/`.
3. Active le mod dans le sélecteur de mods au lancement d'une partie.

## Réglages

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

## Commandes console

| Commande | Usage | Effet |
|---|---|---|
| `psToggleHusbandry` | `psToggleHusbandry [0\|1]` | Active/désactive l'obligation pour les bâtiments d'animaux |
| `psToggleProduction` | `psToggleProduction [0\|1]` | Active/désactive l'obligation pour les usines |
| `psList` | `psList [farmId]` | Liste les bâtiments détectés, leur type, ferme et état |
| `psToggleSpawner` | `psToggleSpawner <numero> [0\|1]` | Active/désactive l'obligation pour un bâtiment précis |
| `psCheckFile` | `psCheckFile` | Diagnostic du fichier de réglages |

## Compatibilité

- **FS25_ProductionStorageControl (PSC)** : détecté automatiquement au
  runtime (aucune dépendance XML nécessaire). Le spawn manuel via PSC
  respecte la même obligation de palette vide que le spawn natif.

## Structure du projet

```
FS25_PalletSystem/
├── modDesc.xml
├── icon_palletSystem.dds
├── scripts/
│   ├── PalletSystem.lua
│   └── PalletSystemRefund.lua


```

## Roadmap / travaux en cours

- [ ] Confirmation en jeu du système de remboursement (`PalletSystemRefund.lua`)
- [ ] Mécanique de réduction de coût de production (champs `costsPerActiveHour`
      / `costsPerActiveMonth` / `costsPerActiveMinute` confirmés lisibles,
      logique non encore implémentée)
- [ ] Vérification de fonctions API incertaines (`getUserProfileAppPath()`,
      `createFolder()`, enregistrement `XMLSchema.new()`) face aux sources
      réelles du jeu

## Signaler un bug

Les retours de la communauté sont les bienvenus via l'onglet
[Issues](../../issues). Merci d'indiquer :

- la version du jeu et la liste des mods actifs (en particulier le mod
  fournissant `EMPTYPALLET`),
- les étapes pour reproduire le problème,
- un extrait pertinent du `log.txt`.

## Licence

À définir.
