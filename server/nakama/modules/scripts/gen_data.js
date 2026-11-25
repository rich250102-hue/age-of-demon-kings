// Copie les données d'équilibrage du client vers le serveur, pour n'avoir qu'une seule source de vérité.
const fs = require("fs");
const path = require("path");
const dataDir = path.join(__dirname, "../../../../client/data");
const buildings = JSON.parse(fs.readFileSync(path.join(dataDir, "buildings.json"), "utf8"));
const out = `// Fichier généré par scripts/gen_data.js depuis client/data. Ne pas modifier à la main.
const BUILDINGS: { [id: string]: BuildingDef } = ${JSON.stringify(buildings, null, 2)};
`;
fs.writeFileSync(path.join(__dirname, "../src/game_data.ts"), out);
console.log("game_data.ts généré (" + Object.keys(buildings).length + " bâtiments)");
