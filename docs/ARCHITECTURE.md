# Architecture

## Principes

1. **Règles pures, séparées de l'affichage.** `Wallet`, `CombatRules`, `Cooldowns`, `BastionGrid` et `RaidSim` ne dépendent d'aucune scène. Elles sont testées sans écran et pourront tourner côté serveur.
2. **Raid déterministe.** `RaidSim` avance par pas de 0,1 s avec une graine. Le même bastion et la même graine donnent toujours le même résultat, ce qui permet au serveur de rejouer et vérifier un raid.
3. **Données d'abord.** Tout l'équilibrage est en JSON (`client/data`). Le serveur génère `game_data.ts` à partir de ces fichiers, donc client et serveur ne divergent pas.
4. **Serveur faisant autorité.** Les ressources et le bastion sont écrits par le serveur avec un contrôle de version (pas de double dépense).
5. **Mobile et PC à égalité.** Même client, mêmes règles ; le tactile et le clavier pilotent les mêmes actions. Ciblage assisté pour que le doigt ne soit pas désavantagé face à la souris.

## Client (Godot 4.7)

| Dossier | Rôle |
|---|---|
| `src/core` | Autoloads : `GameData` (lecture JSON), `EventBus` (signaux globaux), `Profile` (sauvegarde locale) |
| `src/gameplay` | Règles pures et entités `Hero`, `Monster` |
| `src/bastion` | `BastionGrid`, `RaidSim`, scène du bastion |
| `src/world` | Caméra isométrique, formes low-poly, scène de forêt |
| `src/ui` | HUD, joystick tactile `TouchStick` |

Renderer « mobile » pour viser les téléphones d'entrée de gamme.

## Serveur (Nakama 3.35, runtime JavaScript)

Module TypeScript compilé en un seul fichier ES5 (`build/index.js`).

| RPC | Rôle |
|---|---|
| `sante` | Vérifie que le serveur répond |
| `profil_lire` | Crée ou lit l'état du joueur |
| `bastion_placer` / `bastion_retirer` | Construction vérifiée (case, coût), remboursement de 50 % |
| `gm_donner` | Game Master : don de ressources, rôle `gm` ou `admin` exigé, motif obligatoire, journalisé |

Vérifié le 25/11/2026 sur un vrai Nakama 3.35 + PostgreSQL 16 : authentification appareil et RPC appelées en HTTP.

## Prochaines étapes techniques

- Brancher le client sur le serveur (client Nakama pour Godot).
- Rejouer les raids côté serveur avec `RaidSim` porté en TypeScript.
- Panel Game Master web (événements pilotés par les données).
- Test sur un vrai téléphone Android d'entrée de gamme.
