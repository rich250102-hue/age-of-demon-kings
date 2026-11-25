// Panel Game Master d'Age of Demon Kings : page statique qui parle au serveur Nakama en HTTP.
// Toutes les vérifications (rôle, montants, dates) sont refaites côté serveur.
"use strict";

const ERRORS = {
  acces_refuse: "Ce compte n'a pas le rôle Game Master.",
  joueur_introuvable: "Aucun joueur avec ce nom ou cet identifiant.",
  motif_obligatoire: "Indiquez un motif (au moins 3 caractères).",
  montant_invalide: "Montant invalide (entre 0 et 100 000).",
  nom_invalide: "Nom invalide (1 à 60 caractères).",
  type_inconnu: "Type d'événement inconnu.",
  multiplicateur_invalide: "Le multiplicateur doit être entre 1 et 5.",
  dates_invalides: "La fin doit être après le début.",
  duree_trop_longue: "Un événement dure au plus 31 jours.",
  evenement_introuvable: "Cet événement n'existe plus.",
  trop_d_evenements: "Trop d'événements programmés (50 au maximum).",
  reseau: "Serveur injoignable.",
};
const ACTIONS = { don: "Don", evenement_cree: "Événement créé", evenement_modifie: "Événement modifié", evenement_supprime: "Événement supprimé" };

const $ = (sel) => document.querySelector(sel);
const state = { url: "", key: "", token: "", types: {}, resources: [], player: null, events: [] };

class ApiError extends Error {}

async function http(path, opts) {
  let res;
  try { res = await fetch(state.url + path, opts); } catch (e) { throw new ApiError("reseau"); }
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new ApiError(data.message || data.error || "http_" + res.status);
  return data;
}

async function rpc(name, payload = {}) {
  const data = await http("/v2/rpc/" + encodeURIComponent(name), {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: "Bearer " + state.token },
    body: JSON.stringify(JSON.stringify(payload)),
  });
  const inner = JSON.parse(data.payload || "{}");
  if (inner.ok === false) throw new ApiError(inner.error || "erreur");
  return inner;
}

function toast(text, isError = false) {
  const t = $("#toast");
  t.textContent = text;
  t.className = "show" + (isError ? " error" : "");
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => (t.className = ""), 3500);
}

function fail(e) {
  toast(ERRORS[e.message] || "Erreur : " + e.message, true);
}

const fmtDate = (ms) => new Date(ms).toLocaleString("fr-FR", { dateStyle: "short", timeStyle: "short" });
const toLocalInput = (ms) => { const d = new Date(ms - new Date(ms).getTimezoneOffset() * 60000); return d.toISOString().slice(0, 16); };
const el = (tag, props = {}, ...children) => { const n = Object.assign(document.createElement(tag), props); n.append(...children); return n; };

// --- Connexion ---------------------------------------------------------------

$("#login-form").addEventListener("submit", async (ev) => {
  ev.preventDefault();
  const f = new FormData(ev.target);
  state.url = String(f.get("url")).replace(/\/+$/, "");
  state.key = String(f.get("key"));
  try {
    const auth = await http("/v2/account/authenticate/email?create=true", {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: "Basic " + btoa(state.key + ":") },
      body: JSON.stringify({ email: f.get("email"), password: f.get("password") }),
    });
    state.token = auth.token;
    await enter();
  } catch (e) { state.token = ""; fail(e); }
});

async function enter() {
  const me = await rpc("gm_moi");
  state.types = me.types_evenement;
  state.resources = me.ressources;
  sessionStorage.setItem("aodk_gm", JSON.stringify({ url: state.url, key: state.key, token: state.token }));
  $("#whoami").textContent = me.gm.username + " · " + me.gm.role;
  $("#session").hidden = false;
  $("#login").hidden = true;
  $("#app").hidden = false;
  buildForms();
  await loadEvents();
}

$("#logout").addEventListener("click", () => { sessionStorage.removeItem("aodk_gm"); location.reload(); });

// --- Onglets -----------------------------------------------------------------

document.querySelectorAll(".tab").forEach((b) => b.addEventListener("click", () => {
  document.querySelectorAll(".tab").forEach((x) => x.classList.toggle("active", x === b));
  document.querySelectorAll(".tab-panel").forEach((p) => (p.hidden = p.id !== "tab-" + b.dataset.tab));
  if (b.dataset.tab === "journal") loadJournal().catch(fail);
  if (b.dataset.tab === "evenements") loadEvents().catch(fail);
}));

function buildForms() {
  const fields = $("#grant-fields");
  fields.replaceChildren(...state.resources.map((r) => el("label", {}, r, el("input", { name: r, type: "number", min: 0, max: 100000, value: 0 }))));
  $("#event-form select[name=type]").replaceChildren(...Object.entries(state.types).map(([k, v]) => el("option", { value: k, textContent: v })));
  resetEventForm();
}

// --- Joueurs -----------------------------------------------------------------

$("#search-form").addEventListener("submit", async (ev) => {
  ev.preventDefault();
  try { showPlayer(await rpc("gm_joueur", { recherche: new FormData(ev.target).get("q") })); }
  catch (e) { $("#player").hidden = true; fail(e); }
});

function showPlayer(res) {
  state.player = res.joueur;
  $("#player").hidden = false;
  $("#player-name").textContent = res.joueur.nom + (res.joueur.role !== "joueur" ? " (" + res.joueur.role + ")" : "");
  $("#player-id").textContent = "Identifiant : " + res.joueur.id;
  renderProfile(res.profil);
}

function renderProfile(profil) {
  $("#player-resources").replaceChildren(...Object.entries(profil.resources).map(([k, v]) => el("span", { className: "chip" }, k, el("b", { textContent: v }))));
  const counts = {};
  profil.bastion.forEach((b) => (counts[b.id] = (counts[b.id] || 0) + 1));
  const parts = Object.entries(counts).map(([k, n]) => n + " " + k);
  $("#player-bastion").textContent = "Bastion : " + (parts.length ? parts.join(", ") : "vide");
}

$("#grant-form").addEventListener("submit", async (ev) => {
  ev.preventDefault();
  const f = new FormData(ev.target);
  const ressources = {};
  state.resources.forEach((r) => { const v = Number(f.get(r)); if (v > 0) ressources[r] = v; });
  if (!Object.keys(ressources).length) return toast("Indiquez au moins un montant.", true);
  const summary = Object.entries(ressources).map(([k, v]) => v + " " + k).join(", ");
  if (!confirm("Donner " + summary + " à " + state.player.nom + " ?")) return;
  try {
    const res = await rpc("gm_donner", { joueur: state.player.id, ressources, motif: f.get("motif") });
    renderProfile(res.profil);
    ev.target.reset();
    toast("Don effectué : " + summary);
  } catch (e) { fail(e); }
});

// --- Événements --------------------------------------------------------------

function eventState(e, now) {
  if (now < e.debut) return ["avenir", "À venir"];
  if (now < e.fin) return ["actif", "En cours"];
  return ["termine", "Terminé"];
}

async function loadEvents() {
  const res = await rpc("gm_evenements");
  state.events = res.evenements;
  const rows = res.evenements.map((e) => {
    const [cls, label] = eventState(e, res.maintenant);
    const edit = el("button", { className: "ghost small", textContent: "Modifier", onclick: () => editEvent(e) });
    const del = el("button", { className: "danger small", textContent: "Supprimer", onclick: () => deleteEvent(e) });
    return el("tr", {},
      el("td", { textContent: e.nom }),
      el("td", { textContent: (state.types[e.type] || e.type) + " × " + e.multiplicateur }),
      el("td", { textContent: fmtDate(e.debut) }),
      el("td", { textContent: fmtDate(e.fin) }),
      el("td", {}, el("span", { className: "badge " + cls, textContent: label })),
      el("td", { className: "actions" }, edit, del));
  });
  $("#events tbody").replaceChildren(...rows);
  $("#events-empty").hidden = rows.length > 0;
}

function resetEventForm() {
  const f = $("#event-form");
  f.reset();
  f.id.value = "";
  const now = Date.now();
  f.debut.value = toLocalInput(now);
  f.fin.value = toLocalInput(now + 48 * 3600 * 1000);
  $("#event-form-title").textContent = "Nouvel événement";
  $("#event-cancel").hidden = true;
}

function editEvent(e) {
  const f = $("#event-form");
  f.id.value = e.id;
  f.nom.value = e.nom;
  f.type.value = e.type;
  f.multiplicateur.value = e.multiplicateur;
  f.debut.value = toLocalInput(e.debut);
  f.fin.value = toLocalInput(e.fin);
  $("#event-form-title").textContent = "Modifier « " + e.nom + " »";
  $("#event-cancel").hidden = false;
  f.scrollIntoView({ behavior: "smooth" });
}

$("#event-cancel").addEventListener("click", resetEventForm);

$("#event-form").addEventListener("submit", async (ev) => {
  ev.preventDefault();
  const f = ev.target;
  const evenement = {
    nom: f.nom.value, type: f.type.value, multiplicateur: Number(f.multiplicateur.value),
    debut: new Date(f.debut.value).getTime(), fin: new Date(f.fin.value).getTime(),
  };
  if (f.id.value) evenement.id = f.id.value;
  try {
    await rpc("gm_evenement_sauver", { evenement });
    toast(f.id.value ? "Événement modifié" : "Événement créé : il s'applique sans mise à jour du jeu");
    resetEventForm();
    await loadEvents();
  } catch (e) { fail(e); }
});

async function deleteEvent(e) {
  if (!confirm("Supprimer l'événement « " + e.nom + " » ?")) return;
  try { await rpc("gm_evenement_supprimer", { id: e.id }); toast("Événement supprimé"); await loadEvents(); }
  catch (err) { fail(err); }
}

// --- Journal -----------------------------------------------------------------

$("#journal-refresh").addEventListener("click", () => loadJournal().catch(fail));

function describe(entry) {
  const d = entry.details || {};
  if (entry.action === "don") return Object.entries(d.ressources || {}).map(([k, v]) => v + " " + k).join(", ") + " → " + d.joueur + " · motif : " + d.motif;
  return (d.nom || "") + (d.type ? " (" + (state.types[d.type] || d.type) + " × " + d.multiplicateur + ")" : "");
}

async function loadJournal() {
  const res = await rpc("gm_journal");
  const rows = res.entrees.map((e) => el("tr", {},
    el("td", { textContent: fmtDate(e.quand) }), el("td", { textContent: e.gm }),
    el("td", { textContent: ACTIONS[e.action] || e.action }), el("td", { textContent: describe(e) })));
  $("#journal tbody").replaceChildren(...rows);
  $("#journal-empty").hidden = rows.length > 0;
}

// --- Reprise de session -------------------------------------------------------

(async () => {
  const saved = JSON.parse(sessionStorage.getItem("aodk_gm") || "null");
  if (!saved) return;
  Object.assign(state, saved);
  try { await enter(); } catch (e) { sessionStorage.removeItem("aodk_gm"); state.token = ""; }
})();
