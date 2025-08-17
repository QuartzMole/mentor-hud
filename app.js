(async function () {
  const app = document.getElementById('app');

  function rowTemplate(r) {
    const where = `${r.region} @ ${r.pos}`;
    const age   = r.age_s ? `${r.age_s}s ago` : '';
    return `
      <li data-id="${r.id}">
        <div><strong>${r.name}</strong> — ${r.msg}</div>
        <div>${where} <small>${age}</small></div>
        <div>
          <button class="accept" data-id="${r.id}">Accept</button>
        </div>
      </li>`;
  }

  async function load() {
    const res = await fetch(`${window.HUD_URL}?action=requests`, { method: 'GET' });
    const data = await res.json(); // [{id,name,msg,region,pos,age_s}, ...]
    app.innerHTML = `<ul class="req-list">${data.map(rowTemplate).join('')}</ul>`;
    wire();
  }

  async function accept(reqId) {
    const url = `${window.HUD_URL}?action=accept&req=${encodeURIComponent(reqId)}&nonce=${encodeURIComponent(window.CSRF_NONCE)}`;
    const res = await fetch(url, { method: 'POST' });
    const j = await res.json(); // {status:"accepted"|"already_taken"|...}
    const li = app.querySelector(`li[data-id="${reqId}"]`);
    if (!li) return;
    if (j.status === 'accepted') {
      li.innerHTML = `<div>✅ Taken by you.</div>`;
    } else if (j.status === 'already_taken') {
      li.innerHTML = `<div>⚠️ Already taken by someone else.</div>`;
    } else {
      li.innerHTML = `<div>❌ ${j.status || 'error'}</div>`;
    }
  }

  function wire() {
    app.querySelectorAll('button.accept').forEach(btn => {
      btn.addEventListener('click', () => accept(btn.dataset.id));
    });
  }

  await load();
  // Optional: auto-refresh the list every 10–15s:
  setInterval(load, 15000);
})();
