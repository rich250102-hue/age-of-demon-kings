// Fichier généré par scripts/gen_data.js depuis client/data. Ne pas modifier à la main.
const BUILDINGS: { [id: string]: BuildingDef } = {
  "tour": {
    "name": "Tour d'archers",
    "cost": {
      "or": 40,
      "bois": 20
    },
    "hp": 200,
    "damage": 9,
    "range": 3.5,
    "fire_interval": 6,
    "blocks": true
  },
  "mur": {
    "name": "Mur",
    "cost": {
      "or": 10,
      "pierre": 10
    },
    "hp": 300,
    "damage": 0,
    "range": 0,
    "fire_interval": 0,
    "blocks": true
  },
  "piege": {
    "name": "Piège à pointes",
    "cost": {
      "or": 25
    },
    "hp": 1,
    "damage": 30,
    "range": 0,
    "fire_interval": 0,
    "blocks": false
  }
};
