// help-hud/app.js  — Resident Help HUD UI
// Expects the LSL wrapper to inject:
//   window.HUD_URL, window.CSRF_NONCE, window.LANG (e.g. "en","de",...)
// Falls back gracefully if not present.


// ---- DIAGNOSTIC PARSER + HARD-LOCK TO HTTP ----
function qpGet(key) {
  var s = window.location.search || "";
  var re = new RegExp("[?&]" + key + "=([^&#]*)", "i");
  var m = re.exec(s);
  return m ? decodeURIComponent(m[1].replace(/\+/g, " ")) : null;
}

var injectedHUD = window.HUD_URL || null;   // wrapper-injected (preferred)
var queryHUD    = qpGet("cb");              // old style via ?cb=
var chosenHUD   = injectedHUD || queryHUD || "http://localhost:8000";

// HARD RULE: never use https for the cap (prevents ERR_CERT_AUTHORITY_INVALID)
chosenHUD = chosenHUD.replace(/^https:\/\//i, "http://");

const HUD_URL = chosenHUD;
// force precedence: URL ?nonce=  → injected window.CSRF_NONCE → test default
const NONCE = (qpGet("nonce") || window.CSRF_NONCE || "test-nonce");

const lang    = (window.LANG || qpGet("lang") || "en").toLowerCase();

// ---- tiny on-page debug banner so you can see what it chose ----
window.addEventListener("DOMContentLoaded", () => {
  var dbg = document.getElementById("result");
  if (dbg) {
    dbg.textContent =
      `Origin=${location.origin} | HUD_URL=${HUD_URL} | ` +
      `injectedHUD=${injectedHUD ?? "nil"} | queryHUD=${queryHUD ?? "nil"} | nonce=${NONCE}`;
  }
});


// Translation dictionary: labels only. The values sent back are stable codes.
const texts = {
  en: {
    title: "Request Mentor Help",
    instructions: "Please choose one or more topics where you need help.",
    topics: {
      how: "How Second Life works",
      exploring: "Exploring the world",
      meeting: "Meeting people/finding friends",
      freebies: "Finding freebies",
      avatar: "Avatar possibilities"
    },
    submit: "Submit",
    needOne: "Please select at least one topic.",
    sent: "Request sent!"
  },
  da: {
    title: "Anmod om mentorhjælp",
    instructions: "Vælg et eller flere emner, hvor du har brug for hjælp.",
    topics: {
      how: "Hvordan Second Life fungerer",
      exploring: "Udforske verdenen",
      meeting: "Møde folk / finde venner",
      freebies: "Finde gratis ting",
      avatar: "Avatar-muligheder"
    },
    submit: "Send",
    needOne: "Vælg mindst ét emne.",
    sent: "Anmodning sendt!"
  },
  de: {
    title: "Mentorenhilfe anfordern",
    instructions: "Bitte wählen Sie ein oder mehrere Themen aus, bei denen Sie Hilfe benötigen.",
    topics: {
      how: "Wie Second Life funktioniert",
      exploring: "Die Welt erkunden",
      meeting: "Leute treffen / Freunde finden",
      freebies: "Freebies finden",
      avatar: "Avatar-Möglichkeiten"
    },
    submit: "Absenden",
    needOne: "Bitte wähle mindestens ein Thema.",
    sent: "Anfrage gesendet!"
  },
  es: {
    title: "Solicitar ayuda de un mentor",
    instructions: "Elige uno o más temas en los que necesites ayuda.",
    topics: {
      how: "Cómo funciona Second Life",
      exploring: "Explorar el mundo",
      meeting: "Conocer gente / encontrar amigos",
      freebies: "Encontrar artículos gratis",
      avatar: "Posibilidades del avatar"
    },
    submit: "Enviar",
    needOne: "Selecciona al menos un tema.",
    sent: "¡Solicitud enviada!"
  },
  fr: {
    title: "Demander l’aide d’un mentor",
    instructions: "Choisissez un ou plusieurs sujets pour lesquels vous avez besoin d’aide.",
    topics: {
      how: "Comment fonctionne Second Life",
      exploring: "Explorer le monde",
      meeting: "Rencontrer des gens / se faire des amis",
      freebies: "Trouver des objets gratuits",
      avatar: "Possibilités de l’avatar"
    },
    submit: "Envoyer",
    needOne: "Veuillez sélectionner au moins un sujet.",
    sent: "Demande envoyée !"
  },
  it: {
    title: "Richiedi aiuto a un mentor",
    instructions: "Scegli uno o più argomenti per cui hai bisogno di aiuto.",
    topics: {
      how: "Come funziona Second Life",
      exploring: "Esplorare il mondo",
      meeting: "Conoscere persone / trovare amici",
      freebies: "Trovare oggetti gratuiti",
      avatar: "Possibilità dell’avatar"
    },
    submit: "Invia",
    needOne: "Seleziona almeno un argomento.",
    sent: "Richiesta inviata!"
  },
  hu: {
    title: "Mentor segítség kérése",
    instructions: "Válassz egy vagy több témát, ahol segítségre van szükséged.",
    topics: {
      how: "Hogyan működik a Second Life",
      exploring: "A világ felfedezése",
      meeting: "Ismerkedés / barátok keresése",
      freebies: "Ingyenes dolgok keresése",
      avatar: "Avatar lehetőségek"
    },
    submit: "Küldés",
    needOne: "Válassz legalább egy témát.",
    sent: "Kérés elküldve!"
  },
  nl: {
    title: "Mentorhulp aanvragen",
    instructions: "Kies één of meer onderwerpen waarbij je hulp nodig hebt.",
    topics: {
      how: "Hoe Second Life werkt",
      exploring: "De wereld verkennen",
      meeting: "Mensen ontmoeten / vrienden vinden",
      freebies: "Gratis spullen vinden",
      avatar: "Avatar-mogelijkheden"
    },
    submit: "Verzenden",
    needOne: "Selecteer minstens één onderwerp.",
    sent: "Verzoek verzonden!"
  },
  pl: {
    title: "Poproś o pomoc mentora",
    instructions: "Wybierz jeden lub więcej tematów, w których potrzebujesz pomocy.",
    topics: {
      how: "Jak działa Second Life",
      exploring: "Odkrywanie świata",
      meeting: "Poznawanie ludzi / szukanie przyjaciół",
      freebies: "Wyszukiwanie darmowych rzeczy",
      avatar: "Możliwości awatara"
    },
    submit: "Wyślij",
    needOne: "Wybierz co najmniej jeden temat.",
    sent: "Prośba wysłana!"
  },
  pt: {
    title: "Solicitar ajuda de um mentor",
    instructions: "Escolha um ou mais tópicos nos quais precisa de ajuda.",
    topics: {
      how: "Como o Second Life funciona",
      exploring: "Explorar o mundo",
      meeting: "Conhecer pessoas / fazer amigos",
      freebies: "Encontrar itens gratuitos",
      avatar: "Possibilidades do avatar"
    },
    submit: "Enviar",
    needOne: "Selecione pelo menos um tópico.",
    sent: "Pedido enviado!"
  },
  ru: {
    title: "Запросить помощь наставника",
    instructions: "Выберите одну или несколько тем, по которым вам нужна помощь.",
    topics: {
      how: "Как работает Second Life",
      exploring: "Исследование мира",
      meeting: "Знакомства / поиск друзей",
      freebies: "Поиск бесплатных вещей",
      avatar: "Возможности аватара"
    },
    submit: "Отправить",
    needOne: "Выберите хотя бы одну тему.",
    sent: "Запрос отправлен!"
  },
  tr: {
    title: "Mentor yardımı iste",
    instructions: "Yardıma ihtiyaç duyduğun konuları seç.",
    topics: {
      how: "Second Life nasıl çalışır",
      exploring: "Dünyayı keşfetmek",
      meeting: "İnsanlarla tanışma / arkadaş bulma",
      freebies: "Ücretsiz eşyalar bulma",
      avatar: "Avatar olanakları"
    },
    submit: "Gönder",
    needOne: "En az bir konu seç.",
    sent: "İstek gönderildi!"
  },
  uk: {
    title: "Запит на допомогу ментора",
    instructions: "Оберіть одну чи кілька тем, у яких вам потрібна допомога.",
    topics: {
      how: "Як працює Second Life",
      exploring: "Дослідження світу",
      meeting: "Знайомства / пошук друзів",
      freebies: "Пошук безкоштовних речей",
      avatar: "Можливості аватара"
    },
    submit: "Надіслати",
    needOne: "Виберіть щонайменше одну тему.",
    sent: "Запит надіслано!"
  },
  zh: {
    title: "请求导师帮助",
    instructions: "请选择一个或多个需要帮助的主题。",
    topics: {
      how: "Second Life 如何运作",
      exploring: "探索世界",
      meeting: "结识他人 / 交朋友",
      freebies: "寻找免费物品",
      avatar: "化身的可能性"
    },
    submit: "提交",
    needOne: "请至少选择一个主题。",
    sent: "请求已发送！"
  },
  ja: {
    title: "メンターへの支援依頼",
    instructions: "支援が必要なトピックを1つ以上選択してください。",
    topics: {
      how: "Second Life の仕組み",
      exploring: "世界を探検する",
      meeting: "人と出会う／友達を見つける",
      freebies: "フリー品を見つける",
      avatar: "アバターの可能性"
    },
    submit: "送信",
    needOne: "少なくとも1つ選択してください。",
    sent: "依頼を送信しました！"
  },
  ko: {
    title: "멘토 도움 요청",
    instructions: "도움이 필요한 주제를 하나 이상 선택하세요.",
    topics: {
      how: "세컨드 라이프 작동 방식",
      exploring: "세상을 탐험하기",
      meeting: "사람 만나기 / 친구 찾기",
      freebies: "무료 아이템 찾기",
      avatar: "아바타 가능성"
    },
    submit: "제출",
    needOne: "최소 하나의 주제를 선택하세요.",
    sent: "요청이 전송되었습니다!"
  }
};

// Fallback to English if language missing
const t = texts[lang] || texts.en;

// Render UI
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

document.getElementById("helpform").addEventListener("submit", async (e) => {
  e.preventDefault();
  const topics = [...document.querySelectorAll("input[name=topic]:checked")].map(i => i.value);

  if (topics.length === 0) {
    document.getElementById("result").textContent = "⚠️ " + (texts[lang]||texts.en).needOne;
    return;
  }

  // Show exactly where we’re about to post
  const dbg = document.getElementById("result");
  if (dbg) dbg.textContent = `Posting (HTTP nav) to: ${HUD_URL}?action=submit`;

  try {
    // Use navigation POST to avoid CORS/mixed-content issues.
    const form = document.createElement("form");
    form.method = "POST";
    form.action = `${HUD_URL}?action=submit`; // HARD-LOCKED HTTP URL

    const payload = document.createElement("input");
    payload.type = "hidden";
    payload.name = "json";
    payload.value = JSON.stringify({ nonce: NONCE, topics });
    form.appendChild(payload);

    // optional: echo field so your LSL can confirm reachability in owner chat
    const echo = document.createElement("input");
    echo.type = "hidden";
    echo.name = "echo";
    echo.value = "ping";
    form.appendChild(echo);

    document.body.appendChild(form);
    form.submit(); // triggers LSL http_request (POST) on the cap
  } catch (err) {
    if (dbg) dbg.textContent = "❌ Network error.";
  }
});
