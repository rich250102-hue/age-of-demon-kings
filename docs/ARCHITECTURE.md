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
| `butin_monstre` | Or d'un monstre vaincu : montant tiré par le serveur, victoires par minute plafonnées par type (`max_kills_per_minute`) |
| `raid_lancer` | Le serveur choisit la graine, simule le raid, applique butin ou pillage ; le client rejoue la même graine pour l'afficher |
| `evenements_actifs` | Événements en cours, affichés par le jeu |
| `gm_moi`, `gm_joueur` | Panel GM : identité du GM, recherche d'un joueur et de son profil |
| `gm_donner` | Don de ressources, motif obligatoire, journalisé |
| `gm_evenements`, `gm_evenement_sauver`, `gm_evenement_supprimer` | Événements datés (bonus d'or de chasse, bonus de butin de raid), validés et journalisés |
| `gm_journal` | Les 100 dernières actions GM |

Toutes les RPC `gm_*` exigent le rôle `gm` ou `admin` dans les métadonnées du compte. Une RPC ne lève jamais d'exception vers le client : elle renvoie `{ok: false, error: code}` (et `erreur_serveur` sans trace pour un bug). Nakama impose que chaque RPC enregistrée soit une fonction déclarée au niveau global ; un test unitaire reproduit cette règle.

Vérifié le 25/11/2026 sur un vrai Nakama 3.35 + PostgreSQL 16 : authentification appareil et RPC appelées en HTTP.

## Client et serveur

- `Profile` (autoload) porte toutes les actions qui modifient le joueur : `place_building`, `remove_building`, `loot_monster`, `launch_raid`. Hors ligne, les règles tournent localement ; en ligne, chaque action passe par une RPC et le client n'applique que la réponse du serveur.
- `NakamaClient` : client HTTP minimal (authentification appareil + RPC), sans extension externe.
- Raid identique des deux côtés : générateur `DetRng` (xorshift32) et distances entières, portés à l'identique en GDScript et en TypeScript. Des valeurs de référence communes sont vérifiées par les deux suites de tests.
- Limite assumée : le combat en forêt se joue encore sur le client. Le serveur borne le butin, mais ne vérifie pas encore le combat lui-même.

## Prochaines étapes techniques

- Panel GM : sanctions (bannissement), messages à tous les joueurs, nouveaux types d'événements (Faille, invasion).
- Test sur un vrai téléphone Android d'entrée de gamme.
