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
const RAIDS: { [id: string]: RaidDef } = {
  "raid_1": {
    "name": "Raid des diablotins",
    "core_hp": 500,
    "waves": [
      {
        "tick": 0,
        "count": 4,
        "hp": 40,
        "damage": 5,
        "speed_ticks": 3
      },
      {
        "tick": 40,
        "count": 6,
        "hp": 40,
        "damage": 5,
        "speed_ticks": 3
      },
      {
        "tick": 90,
        "count": 3,
        "hp": 120,
        "damage": 12,
        "speed_ticks": 4
      }
    ],
    "loot_on_win": {
      "or": 60,
      "bois": 30,
      "pierre": 30
    },
    "max_loss_ratio": 0.2
  }
};
const MONSTERS: { [id: string]: MonsterDef } = {
  "diablotin": {
    "name": "Diablotin",
    "hp": 60,
    "attack": 6,
    "defense": 1,
    "speed": 3.2,
    "aggro_range": 8,
    "attack_range": 1.6,
    "attack_interval": 1.4,
    "gold": [
      3,
      6
    ],
    "scale": 0.7,
    "respawn": 8,
    "max_kills_per_minute": 40,
    "color": "#a63d8f"
  },
  "molosse": {
    "name": "Molosse corrompu",
    "hp": 140,
    "attack": 11,
    "defense": 3,
    "speed": 4,
    "aggro_range": 10,
    "attack_range": 1.8,
    "attack_interval": 1.6,
    "gold": [
      8,
      14
    ],
    "scale": 1,
    "respawn": 14,
    "max_kills_per_minute": 15,
    "color": "#5b2a6e"
  },
  "gardien": {
    "name": "Gardien de la forêt",
    "hp": 1200,
    "attack": 22,
    "defense": 6,
    "speed": 2.6,
    "aggro_range": 12,
    "attack_range": 2.6,
    "attack_interval": 2,
    "gold": [
      120,
      160
    ],
    "scale": 2,
    "respawn": -1,
    "max_kills_per_minute": 1,
    "color": "#3d1450",
    "boss": true
  }
};
