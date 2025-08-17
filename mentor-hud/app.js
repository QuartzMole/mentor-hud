/* mentor-hud/app.js — Mentor HUD UI (drop-in)
   Expects LSL wrapper to inject:
     window.HUD_URL, window.CSRF_NONCE
*/

// ---------- Config from wrapper (with browser-test fallbacks) ----------
const HUD_URL = window.HUD_URL || "http://localhost:8001";
const NONCE   = window.CSRF_NONCE || "test-mentor-nonce";

// ---------- Topic labels (display only; KVP stores stable codes) ----------
// Languages per llGetAgentLanguage: en, da, de, es, fr, it, hu, nl, pl, pt, ru, tr, uk, zh, ja, ko
const topicLabels = {
  en: {
    how: "How Second Life works",
    exploring: "Exploring the world",
    meeting: "Meeting people/finding friends",
    freebies: "Finding freebies",
    avatar: "Avatar possibilities"
  },
  da: {
    how: "Hvordan Second Life fungerer",
    exploring: "Udforske verdenen",
    meeting: "Møde folk / finde venner",
    freebies: "Finde gratis ting",
    avatar: "Avatar-muligheder"
  },
  de: {
    how: "Wie Second Life funktioniert",
    exploring: "Die Welt erkunden",
    meeting: "Leute treffen / Freunde finden",
    freebies: "Freebies finden",
    avatar: "Avatar-Möglichkeiten"
  },
  es: {
    how: "Cómo funciona Second Life",
    exploring: "Explorar el mundo",
    meeting: "Conocer gente / encontrar amigos",
    freebies: "Encontrar artículos gratis",
    avatar: "Posibilidades del avatar"
  },
  fr: {
    how: "Comment fonctionne Second Life",
    exploring: "Explorer le monde",
    meeting: "Rencontrer des gens / se faire des amis",
    freebies: "Trouver des objets gratuits",
    avatar: "Possibilités de l’avatar"
  },
  it: {
    how: "Come funziona Second Life",
    exploring: "Esplorare il mondo",
    meeting: "Incontrare persone / trovare amici",
    freebies: "Trovare oggetti gratuiti",
    avatar: "Possibilità dell’avatar"
  },
  hu: {
    how: "Hogyan működik a Second Life",
    exploring: "A világ felfedezése",
    meeting: "Ismerkedés / barátok keresése",
    freebies: "Ingyenes dolgok keresése",
    avatar: "Avatar-lehetőségek"
  },
  nl: {
    how: "Hoe Second Life werkt",
    exploring: "De wereld verkennen",
    meeting: "Mensen ontmoeten / vrienden vinden",
    freebies: "Gratis spullen vinden",
    avatar: "Avatar-mogelijkheden"
  },
  pl: {
    how: "Jak działa Second Life",
    exploring: "Odkrywanie świata",
    meeting: "Poznawanie ludzi / szukanie przyjaciół",
    freebies: "Znajdowanie darmowych rzeczy",
    avatar: "Możliwości awatara"
  },
  pt: {
    how: "Como o Second Life funciona",
    exploring: "Explorar o mundo",
    meeting: "Conhecer pessoas / fazer amigos",
    freebies: "Encontrar itens gratuitos",
    avatar: "Possibilidades do avatar"
  },
  ru: {
    how: "Как работает Second Life",
    exploring: "Исследование мира",
    meeting: "Знакомства / поиск друзей",
    freebies: "Поиск бесплатных вещей",
    avatar: "Возможности аватара"
  },
  tr: {
    how: "Second Life nasıl çalışır",
    exploring: "Dünyayı keşfetmek",
    meeting: "İnsanlarla tanışma / arkadaş bulma",
    freebies: "Ücretsiz eşyalar bulma",
    avatar: "Avatar olanakları"
  },
  uk: {
    how: "Як працює Second Life",
    exploring: "Дослідження світу",
    meeting: "Знайомства / пошук друзів",
    freebies: "Пошук безкоштовних речей",
    avatar: "Можливості аватара"
  },
  zh: {
    how: "Second Life 如何运作",
    exploring: "探索世界",
    meeting: "结识他人 / 交朋友",
    freebies: "寻找免费物品",
    avatar: "化身的可能性"
  },
  ja: {
    how: "Second Life の仕組み",
    exploring: "世界を探検する",
    meeting: "人と出会う／友達を見つける",
    freebies: "フリー品を見つける",
    avatar: "アバターの可能性"
  },
  ko: {
    how: "세컨드 라이프 작동 방식",
    exploring: "세상을 탐험하기",
    meeting: "사람 만나기 / 친구 찾기",
    freebies: "무료 아이템 찾기",
    avatar: "아바타 가능성"
  }
};

// Choose labels by mentor UI language (fallback to English)
const mentorLang = (navigator.language || "en").slice(0, 2).toLowerCase();
const labels = topicLabels[mentorLang] || topicLabels.en;

// ---------- DOM refs ----------
const listEl    = document.getElementById("list");
const statusEl  = document.getElementById("status");
const btnRefresh = document.getElementById("refresh");
const chkAuto    = document.getElementById("autorefresh");

let timer = null;

// ---------- Helpers ----------
function fmtAge(iso) {
  if (!iso) return "";
  const then = new Date(iso).getTime();
  if (Number.isNaN(then)) return "";
  const s = Math.max(0, Math.floor((Date.now() - then) / 1000));
  if (s < 60) return `${s}s ago`;
  const m = Math.floor(s / 60);
  if (m < 60) return `${m}m ago`;
  const h = Math.floor(m / 60);
  return `${h}h ago`;
}

function renderItem(r) {
  // Map topic codes -> localized labels
  const topics = Array.isArray(r.topics)
    ? r.topics.map(code => (labels[code] || code)).join(", ")
    : "";

  const age   = r.age_s ? `${r.age_s}s ago` : fmtAge(r.created_at);
  const where = r.region && r.pos ? `${r.region} @ ${r.pos}` : (r.region || "");
  const who   = r.requestor_name || r.name || r.requestor_id || "Resident";
  const langBadge = r.lang ? `<span class="badge">${String(r.lang).toUpperCase()}</span>` : "";

  return `
    <li class="card" data-id="${r.id}">
      <div class="row">
        <div class="who"><strong>${who}</strong> ${langBadge}</div>
        <div class="age">${age || ""}</div>
      </div>
      ${r.msg ? `<div class="msg">${r.msg}</div>` : ""}
      <div class="meta">
        ${where ? `<span>${where}</span>` : ""}
        ${topics ? `<span>• ${topics}</span>` : ""}
      </div>
      <div class="actions">
        <button class="accept" data-id="${r.id}">Accept</button>
      </div>
    </li>
  `;
}

// ---------- Data I/O ----------
async function loadList() {
  try {
    statusEl.textContent = "Loading…";
    const res = await fetch(`${HUD_URL}?action=requests`, { method: "GET" });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json(); // [{ id, requestor_name, msg, region, pos, topics[], lang, created_at, age_s }, ...]
    if (!Array.isArray(data)) throw new Error("Bad payload");

    listEl.innerHTML = data.length
      ? data.map(renderItem).join("")
      : `<li class="empty">No open requests.</li>`;

    wireAccept();
    statusEl.textContent = "";
  } catch (e) {
    console.error(e);
    statusEl.textContent = "Failed to load requests.";
  }
}

function wireAccept() {
  listEl.querySelectorAll("button.accept").forEach(btn => {
    btn.addEventListener("click", () => accept(btn.dataset.id, btn));
  });
}

async function accept(reqId, btnEl) {
  if (!reqId) return;
  try {
    btnEl.disabled = true;
    btnEl.textContent = "Claiming…";
    const url = `${HUD_URL}?action=accept&req=${encodeURIComponent(reqId)}&nonce=${encodeURIComponent(NONCE)}`;
    const res = await fetch(url, { method: "POST" });
    const j = await res.json();
    const li = listEl.querySelector(`li[data-id="${reqId}"]`);
    if (!li) return;

    if (j.status === "accepted") {
      li.querySelector(".actions").innerHTML = `<span class="ok">✅ Taken by you</span>`;
      li.classList.add("taken");
    } else if (j.status === "already_taken") {
      li.querySelector(".actions").innerHTML = `<span class="warn">⚠️ Already taken</span>`;
      li.classList.add("faded");
    } else if (j.status === "missing") {
      li.querySelector(".actions").innerHTML = `<span class="warn">⚠️ Request no longer available</span>`;
      li.classList.add("faded");
    } else {
      li.querySelector(".actions").innerHTML = `<span class="err">❌ ${j.status || "Error"}</span>`;
      btnEl.disabled = false;
      btnEl.textContent = "Accept";
    }
  } catch (e) {
    console.error(e);
    if (btnEl) { btnEl.disabled = false; btnEl.textContent = "Accept"; }
    statusEl.textContent = "Claim failed.";
  }
}

// ---------- Wire up UI ----------
document.getElementById("refresh").addEventListener("click", loadList);
document.getElementById("autorefresh").addEventListener("change", () => {
  if (chkAuto.checked) {
    timer = setInterval(loadList, 15000);
  } else if (timer) {
    clearInterval(timer);
    timer = null;
  }
});

// Initial load
loadList();
timer = setInterval(loadList, 15000);
