/* NPC jobs & list refresh fixes */
(() => {
  const NUI = (a, p) =>
    fetch(`https://${GetParentResourceName()}/${a}`, {
      method: "POST",
      body: JSON.stringify(p || {}),
    }).catch(() => {});
  const $ = (id) => document.getElementById(id);
  const on = (el, ev, fn) => el && el.addEventListener(ev, fn);

  const state = {
    app: "npc",
    dash: { jobsNew: [], jobsActive: [], profile: {}, thresholds: [] },
    pos: { Repairs: [], Cosmetics: [], Performance: [] },
    biz: { basics: {}, employees: [], allowed: false },
    npc: { enabled: false },
    cart: { items: [], subtotal: 0, tax: 0, total: 0 },
  };

  function show(app) {
    state.app = app;
    ["home", "npc", "pos", "boss"].forEach((k) => {
      $(k).style.display = k === app ? "block" : "none";
    });
    document.querySelectorAll(".dock-item.app").forEach((b) => {
      b.classList.toggle("active", b.dataset.app === app);
    });
  }
  document.querySelectorAll(".dock-item.app").forEach((a) =>
    a.addEventListener("click", () => show(a.dataset.app))
  );

  on($("closeBtn"), "click", () => NUI("close"));
  on($("npcToggle"), "click", () => {
    state.npc.enabled = !state.npc.enabled;
    $("npcToggle").textContent = state.npc.enabled ? "Stop NPC Jobs" : "Start NPC Jobs";
    NUI("toggleNPC", { enabled: state.npc.enabled });
  });

  // ----- rank bar -----
  function renderRank(profile, thresholds) {
    const rank = Number(profile?.rank || 1);
    const xp = Number(profile?.xp || 0);
    let pct = 0;
    if (Array.isArray(thresholds)) {
      const next = thresholds[rank];
      const prev = thresholds[rank - 1] ?? 0;
      if (typeof next === "number" && next > prev) {
        pct = Math.max(0, Math.min(100, Math.floor(((xp - prev) / (next - prev)) * 100)));
      } else if (next === undefined && xp >= prev) {
        pct = 100;
      }
    }
    $("rankbox").innerHTML = `Rank ${rank} <span class="bar"><span style="width:${pct}%"></span></span>`;
  }

  // ----- deadlines -----
  function parseMySQL(ts) {
    if (!ts) return NaN;
    if (typeof ts === "number") return ts;
    const iso = ("" + ts).trim().replace(" ", "T");
    const withZ = iso.endsWith("Z") ? iso : iso + "Z";
    const t = Date.parse(withZ);
    return Number.isNaN(t) ? Date.now() : t;
  }
  function fmtDeadline(utc) {
    const ms = parseMySQL(utc);
    return `<span data-exp="${ms}"></span>`;
  }
  function tickDeadlines() {
    const nodes = document.querySelectorAll("[data-exp]");
    const now = Date.now();
    nodes.forEach((n) => {
      const t = Number(n.dataset.exp || 0);
      const left = Math.max(0, Math.floor((t - now) / 1000));
      const m = Math.floor(left / 60),
        s = left % 60;
      n.textContent = `${m}:${String(s).padStart(2, "0")}`;
      if (left <= 0) n.closest(".card")?.remove();
    });
    setTimeout(tickDeadlines, 250);
  }

  // ----- jobs -----
  function renderJobs({ jobsNew = [], jobsActive = [], profile = {}, thresholds = [] } = {}) {
    state.dash.jobsNew = jobsNew;
    state.dash.jobsActive = jobsActive;
    state.dash.profile = profile;
    state.dash.thresholds = thresholds;

    $("newJobs").innerHTML = jobsNew
      .map(
        (j) => `<div class="card" data-job="${j.id}">
          <div class="row space">
            <div><b>${String(j.type || "").toUpperCase()}</b> • ${j.plate || ""}</div>
            <div class="tag">Req. Rank ${j.min_rank || 1} • Deadline: ${fmtDeadline(j.deadline_at)}</div>
          </div>
          <div class="row end">
            <button class="btn" data-act="accept" data-id="${j.id}" data-min="${j.min_rank || 1}">Accept</button>
          </div>
        </div>`
      )
      .join("");

    $("activeJobs").innerHTML = jobsActive
      .map(
        (j) => `<div class="card" data-job="${j.id}">
          <div class="row space">
            <div><b>${String(j.type || "").toUpperCase()}</b> • ${j.plate || ""}</div>
            <div class="tag">${j.status || ""}</div>
          </div>
          <div class="row end">
            <button class="btn-secondary" data-act="start" data-id="${j.id}">Start</button>
            <button class="btn" data-act="finish" data-id="${j.id}">Finish</button>
          </div>
        </div>`
      )
      .join("");

    renderRank(profile, thresholds);
    tickDeadlines();
  }

  document.body.addEventListener("click", async (e) => {
    const btn = e.target.closest("button[data-act]");
    if (!btn) return;

    const id = Number(btn.dataset.id);
    const act = btn.dataset.act;

    if (act === "accept") {
      const need = Number(btn.dataset.min || 1);
      const myRank = Number(state?.dash?.profile?.rank || 1);
      if (myRank < need) return;

      // Optimistic move to Active list
      const found = state.dash.jobsNew.find((j) => j.id === id);
      if (found) {
        found.status = "in_progress";
        state.dash.jobsActive.push(found);
        state.dash.jobsNew = state.dash.jobsNew.filter((j) => j.id !== id);
        renderJobs(state.dash);
      }

      await NUI("acceptJob", { id });
      await NUI("startJob", { id });
      NUI("jobs:refresh");
      return;
    }
    if (act === "start") return NUI("startJob", { id });
    if (act === "finish") {
      await NUI("finishJob", { id, quality: 80 });
      state.dash.jobsActive = state.dash.jobsActive.filter((j) => j.id !== id);
      renderJobs(state.dash);
      NUI("jobs:refresh");
    }
  });

  on($("orderOil"), "click", () => NUI("orderParts", { items: [{ part_id: "engine_oil", qty: 5 }] }));

  // ----- POS (minimal to keep working) -----
  function buildPOS(catalog) {
    const cats = Object.keys(catalog || {});
    const tabs = $("posTabs");
    tabs.innerHTML = cats.map((c, i) => `<button class="dock-item seg ${i===0?'active':''}" data-cat="${c}">${c}</button>`).join("");
    tabs.querySelectorAll("button").forEach((b,i)=>b.addEventListener("click",()=>{
      tabs.querySelectorAll("button").forEach(x=>x.classList.remove("active"));
      b.classList.add("active"); drawItems(cats[i]);
    }));
    state.pos = catalog; drawItems(cats[0]);
  }
  function drawItems(cat){
    const list = state.pos[cat] || [];
    $("posItems").innerHTML = list.map(it => `
      <div class="item" data-id="${it.id}" data-label="${it.label}" data-price="${Number(it.price)||0}">
        <div class="name">${it.label}</div>
        <div class="price">$${Number(it.price).toFixed(2)}</div>
      </div>`).join("");
  }
  $("posItems").addEventListener("click", (e)=>{
    const n = e.target.closest(".item"); if(!n) return;
    const id = n.dataset.id, label = n.dataset.label, price = Number(n.dataset.price)||0;
    const line = state.cart.items.find(x=>x.id===id); if(line) line.qty += 1; else state.cart.items.push({id,label,price,qty:1});
    refreshCart();
  });
  function refreshCart(){
    const list = $("cartList");
    list.innerHTML = state.cart.items.map((it,i)=>`<div class="cart-line"><div>${it.label} x${it.qty}</div><div>$${(it.qty*it.price).toFixed(2)}</div></div>`).join("");
    const s = state.cart.items.reduce((a,b)=>a + b.price*b.qty,0);
    const t = +(s * 0.085).toFixed(2); const g = +(s + t).toFixed(2);
    state.cart.subtotal = s; state.cart.tax = t; state.cart.total = g;
    $("sub").textContent = `$${s.toFixed(2)}`; $("tax").textContent = `$${t.toFixed(2)}`; $("tot").textContent = `$${g.toFixed(2)}`;
  }
  $("cartClear").onclick = () => { state.cart = { items:[], subtotal:0, tax:0, total:0 }; refreshCart(); };
  $("cartPay").onclick = async () => {
    if (!state.cart.items.length) return;
    try {
      const res = await fetch(`https://${GetParentResourceName()}/pos:getNearby`, { method:"POST", body:"{}" });
      const list = await res.json(); openPicker([{src:0,name:"Me (self)"}].concat(list||[]));
    } catch { openPicker([{src:0,name:"Me (self)"}]); }
  };
  function openPicker(rows){
    $("pickList").innerHTML = rows.map(r=>`<div class="cart-line"><div>${r.name}</div><div><button class="btn" data-pick="${r.src}">Charge</button></div></div>`).join("");
    $("picker").style.display = "flex";
  }
  $("pickCancel").onclick = () => ($("picker").style.display = "none");
  $("pickList").addEventListener("click",(e)=>{
    const b = e.target.closest("button[data-pick]"); if(!b) return;
    const targetSrc = Number(b.dataset.pick||0);
    $("picker").style.display = "none";
    NUI("pos:requestCharge", { targetSrc, cart: state.cart });
  });

  // ----- message bus -----
  function applyBrand(b){
    const root = document.documentElement;
    if (b?.primary) root.style.setProperty("--brand", b.primary);
    if (b?.secondary) root.style.setProperty("--btn", b.secondary);
  }

  window.addEventListener("message", (e) => {
    const { action, payload } = e.data || {};
    if (!action) return;

    if (action === "open") { $("wrap").style.display = "flex"; show("npc"); }
    if (action === "close") { $("wrap").style.display = "none"; }

    if (action === "jobs:update") renderJobs(payload);
    if (action === "stock:update") { 
      const stock = payload?.stock || [];
      $("stock").innerHTML = stock.map(s=>`<div class="row space"><div>${s.part_id}</div><div>${s.qty}</div></div>`).join("");
    }
    if (action === "pos:catalog") buildPOS(payload || {});
    if (action === "biz:info") { state.biz = payload || state.biz; applyBrand(state.biz.basics); }
    if (action === "pos:payPrompt") {
      const inv = payload || {};
      $("payPrompt").style.display = "flex";
      $("ppTitle").textContent = `${inv.businessName} • Served by ${inv.sellerName}`;
      $("ppItems").innerHTML = (inv.items || []).map(it=>`<div class="cart-line"><div>${it.label} x${it.qty||1}</div><div>$${((it.qty||1)*it.price).toFixed(2)}</div></div>`).join("");
      $("ppSub").textContent = `$${(inv.subtotal || 0).toFixed(2)}`;
      $("ppTax").textContent = `$${(inv.tax || 0).toFixed(2)}`;
      $("ppTot").textContent = `$${(inv.total || 0).toFixed(2)}`;
      $("payPrompt").dataset.id = inv.id;
    }
    if (action === "pay:close") $("payPrompt").style.display = "none";
    if (action === "toast") {
      // lightweight toast
      let box = document.getElementById("toastBox");
      if (!box) { box = document.createElement("div"); box.id="toastBox"; box.style.position="absolute"; box.style.left="50%"; box.style.top="14px"; box.style.transform="translateX(-50%)"; document.body.appendChild(box); }
      const d = document.createElement("div"); d.textContent = payload?.text || ""; d.style.padding="8px 12px"; d.style.margin="6px 0"; d.style.border="1px solid rgba(255,255,255,.1)"; d.style.borderRadius="10px"; d.style.background="rgba(16,22,28,.8)"; d.style.color="#e6edf3"; box.appendChild(d); setTimeout(()=>d.remove(), 2200);
    }
  });

  // ESC closes modals first, then tablet
  window.addEventListener("keydown", (e) => {
    if (e.key !== "Escape") return;
    if ($("picker").style.display === "flex") return ($("picker").style.display = "none");
    if ($("payPrompt").style.display === "flex") return ($("payPrompt").style.display = "none");
    NUI("close");
  });
})();
