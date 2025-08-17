const HUD_URL = window.HUD_URL;
const NONCE   = window.CSRF_NONCE;
const lang    = window.LANG || "en";

const texts = {
  en: {
    title: "Request Mentor Help",
    instructions: "Please choose one or more topics where you need help.",
    topics: { scripting:"Scripting", building:"Building", policy:"Policy" },
    submit: "Submit"
  },
  de: {
    title: "Mentorenhilfe anfordern",
    instructions: "Bitte wählen Sie ein oder mehrere Themen aus, bei denen Sie Hilfe benötigen.",
    topics: { scripting:"Skripting", building:"Bauen", policy:"Regeln" },
    submit: "Absenden"
  },
  fr: {
    title: "Demander l’aide d’un mentor",
    instructions: "Veuillez choisir un ou plusieurs sujets pour lesquels vous avez besoin d'aide.",
    topics: { scripting:"Programmation", building:"Construction", policy:"Règles" },
    submit: "Envoyer"
  }
  // add more languages as needed
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
