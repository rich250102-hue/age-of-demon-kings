# Panel Game Master

Page web statique (HTML, CSS, JavaScript, sans dépendance) qui pilote le jeu à travers le serveur Nakama.
Toutes les vérifications sont refaites par le serveur : le panel ne peut rien faire qu'un compte GM n'ait le droit de faire.

## Fonctions

- **Joueurs** : recherche par nom d'utilisateur ou identifiant, ressources et bastion, don de ressources avec motif obligatoire.
- **Événements** : création, modification et suppression d'événements datés. Ils s'appliquent sans mise à jour du jeu.
  - `Or des monstres multiplié` : multiplie l'or des monstres.
  - `Butin des raids multiplié` : multiplie le butin des raids gagnés.
  - Multiplicateur entre 1 et 5, durée de 31 jours au plus, 50 événements au plus.
- **Journal** : chaque action GM (qui, quoi, quand, motif), les 500 dernières sont conservées.

## Lancer en local

```
cd gm-panel
python3 -m http.server 8088
```

Ouvrir http://127.0.0.1:8088, indiquer l'adresse du serveur (par défaut http://127.0.0.1:7350), un e-mail et un mot de passe.
La première connexion crée le compte, sans droits.

## Donner le rôle Game Master

Dans la console Nakama (http://127.0.0.1:7351) : Accounts > choisir le compte > Metadata, mettre `{"role": "admin"}` (ou `"gm"`), enregistrer.
Seul quelqu'un qui a accès à la console du serveur peut donc créer un GM.

## Test de bout en bout

```
PANEL_URL=http://127.0.0.1:8088/ CAPTURES=/tmp node gm-panel/tests/panel.e2e.js
```

## En production

Servir ces trois fichiers en HTTPS (n'importe quel hébergement statique), changer la clé serveur `defaultkey`,
et restreindre l'accès à la console Nakama.
