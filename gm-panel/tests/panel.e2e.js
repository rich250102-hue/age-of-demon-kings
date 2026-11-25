// Test de bout en bout du panel GM (Chromium via Playwright).
// Prérequis : serveur Nakama + module, panel servi en local, un compte gm@aodk.test (mot de passe motdepasse-gm)
// avec le rôle admin, et un joueur nommé joueur_test. Voir gm-panel/README.md.
const { chromium } = require("playwright");
(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1200, height: 900 }, deviceScaleFactor: 1 });
  const errors = [];
  page.on("pageerror", (e) => errors.push(e.message));
  page.on("dialog", (d) => d.accept());
  const check = (c, label) => console.log((c ? "  OK    " : "  ECHEC ") + label);
  await page.goto(process.env.PANEL_URL || "http://127.0.0.1:8088/");
  // Compte sans rôle : refusé
  await page.fill("input[name=email]", "intrus@aodk.test");
  await page.fill("input[name=password]", "motdepasse-x");
  await page.click("#login-form button");
  await page.waitForSelector("#toast.show");
  check((await page.textContent("#toast")).includes("rôle Game Master"), "un compte sans rôle GM est refusé");
  check(await page.isHidden("#app"), "le panel reste fermé");
  // GM
  await page.fill("input[name=email]", "gm@aodk.test");
  await page.fill("input[name=password]", "motdepasse-gm");
  await page.click("#login-form button");
  await page.waitForSelector("#app:not([hidden])");
  check((await page.textContent("#whoami")).includes("richard_gm"), "connexion GM");
  await page.fill("#search-form input", "joueur_test");
  await page.click("#search-form button");
  await page.waitForSelector("#player:not([hidden])");
  const goldOf = async () => Number((await page.textContent("#player-resources")).match(/or(\d+)/)[1]);
  const before = await goldOf();
  check(before >= 0 && (await page.textContent("#player-name")).includes("joueur_test"), "fiche joueur affichée (" + before + " or)");
  await page.fill("#grant-fields input[name=or]", "250");
  await page.fill("#grant-form input[name=motif]", "compensation test");
  await page.click("#grant-form button");
  await page.waitForFunction((b) => document.querySelector("#player-resources").textContent.includes("or" + (b + 250)), before);
  check((await goldOf()) === before + 250, "don de 250 or appliqué");
  await page.screenshot({ path: (process.env.CAPTURES || ".") + "/gm_joueurs.png" });
  // Événement
  await page.click("button[data-tab=evenements]");
  await page.fill("#event-form input[name=nom]", "Week-end de l'or");
  await page.selectOption("#event-form select[name=type]", "bonus_or_chasse");
  await page.fill("#event-form input[name=multiplicateur]", "2");
  await page.click("#event-form button[type=submit]");
  await page.waitForSelector("#events tbody tr");
  check((await page.textContent("#events tbody")).includes("En cours"), "événement créé et en cours");
  await page.screenshot({ path: (process.env.CAPTURES || ".") + "/gm_evenements.png" });
  // Journal
  await page.click("button[data-tab=journal]");
  await page.waitForSelector("#journal tbody tr");
  const j = await page.textContent("#journal tbody");
  check(j.includes("Don") && j.includes("Événement créé"), "journal : don et événement tracés");
  await page.screenshot({ path: (process.env.CAPTURES || ".") + "/gm_journal.png" });
  check(errors.length === 0, "aucune erreur JavaScript " + errors.join(" | "));
  await browser.close();
})();
