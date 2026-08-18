---
name: Bug report
about: Create a report to help us improve
title: ''
labels: ''
assignees: ''

---

name: "🐛 Rapport de bug"
description: "Signaler un problème rencontré avec FS25_PalletSystem"
title: "[Bug] "
labels: ["bug"]
body:
  - type: markdown
    attributes:
      value: |
        Merci de prendre le temps de remonter ce bug. Avant de continuer,
        vérifie rapidement dans le README la section "Roadmap / travaux en
        cours" : certains comportements (système de remboursement, migration
        de sauvegarde, remise de coût) sont encore en développement et déjà
        connus comme incomplets.

  - type: input
    id: game-version
    attributes:
      label: Version de Farming Simulator 25
      placeholder: "ex. 1.4.0.0"
    validations:
      required: true

  - type: input
    id: mod-version
    attributes:
      label: Version de FS25_PalletSystem
      description: Numéro de release, tag, ou date/commit si compilé depuis le dépôt
      placeholder: "ex. v1.2.0"
    validations:
      required: true

  - type: input
    id: emptypallet-mod
    attributes:
      label: Mod fournissant le fillType EMPTYPALLET
      description: Nom et version du mod "fabricant" de palettes vides utilisé
      placeholder: "ex. FS25_EmptyPalletPack v1.0"
    validations:
      required: true

  - type: dropdown
    id: building-type
    attributes:
      label: Type de bâtiment concerné
      options:
        - Usine (ProductionPoint)
        - Bâtiment animaux (Husbandry)
        - Les deux
        - Non applicable / autre
    validations:
      required: true

  - type: checkboxes
    id: active-settings
    attributes:
      label: Réglages actifs au moment du bug
      options:
        - label: Obligation "Usines" activée
        - label: Obligation "Animaux" activée
        - label: Bâtiment concerné désactivé individuellement (psToggleSpawner)
        - label: FS25_ProductionStorageControl (PSC) installé et actif

  - type: dropdown
    id: session-type
    attributes:
      label: Mode de jeu
      options:
        - Solo
        - Multijoueur — hôte
        - Multijoueur — client
    validations:
      required: false

  - type: textarea
    id: repro-steps
    attributes:
      label: Étapes pour reproduire
      description: Liste numérotée, la plus précise possible
      placeholder: |
        1. ...
        2. ...
        3. ...
    validations:
      required: true

  - type: textarea
    id: expected
    attributes:
      label: Comportement attendu
    validations:
      required: true

  - type: textarea
    id: actual
    attributes:
      label: Comportement observé
    validations:
      required: true

  - type: textarea
    id: log
    attributes:
      label: Extrait pertinent du log.txt
      description: Colle les lignes autour du problème (recherche "PalletSystem" ou "PS-" dans le fichier)
      render: shell
    validations:
      required: false

  - type: checkboxes
    id: confirmations
    attributes:
      label: Avant d'envoyer
      options:
        - label: J'ai vérifié qu'aucune Issue existante ne décrit déjà ce problème
          required: true
        - label: J'ai testé, si possible, sans autres mods de gameplay pour isoler le problème
          required: false
