const HUD_URL = window.HUD_URL;
const NONCE   = window.CSRF_NONCE;
const lang    = window.LANG || "en";

const texts = {
// Topic label dictionary (display only; KVP stores stable codes)
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
    freebies: "Ingyenes cuccok keresése",
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
    how: "세컨드 라이프가 어떻게 작동하는지",
    exploring: "세상을 탐험하기",
    meeting: "사람 만나기 / 친구 찾기",
    freebies: "무료 아이템 찾기",
    avatar: "아바타 가능성"
  }
};


const t = texts[lang] || texts.en;

const app = document.getElementById("app");
app.innerHTML = `
  <h1>${t.title}</h1>
  <p>${t.instructions}</p>
  <form id="helpform">
    ${Object.keys(t.topics).map(code =>
      `<label><input type="checkbox" name="topic" value="${code}"> ${t.topics[code]}</label>`
    ).join("<br>")}
    <br><button type="submit">${t.submit}</button>
  </form>
  <div id="result"></div>
`;

document.getElementById("helpform").addEventListener("submit", async e=>{
  e.preventDefault();
  const topics = [...document.querySelectorAll("input[name=topic]:checked")].map(i=>i.value);
  if (topics.length === 0) {
    document.getElementById("result").textContent = "⚠️ Please select at least one topic.";
    return;
  }
  try {
    const res = await fetch(`${HUD_URL}?action=submit&nonce=${encodeURIComponent(NONCE)}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ topics })
    });
    const j = await res.json();
    document.getElementById("result").textContent =
      j.status === "ok" ? "✅ Request sent!" : `❌ Failed: ${j.status}`;
  } catch (err) {
    document.getElementById("result").textContent = "❌ Error sending request.";
  }
});
