// NUI helper
const NUI = (a,p)=>fetch(`https://${GetParentResourceName()}/${a}`,{method:'POST',body:JSON.stringify(p||{})});

// DOM refs
const wrap = document.getElementById('wrap');
const rankbox = document.getElementById('rankbox');
const views = { home:$('#home'), npc:$('#npc'), pos:$('#pos'), boss:$('#boss') };
const newJobs = $('#newJobs'), activeJobs = $('#activeJobs'), stockDiv = $('#stock');
const npcToggle = $('#npcToggle');

const posTabs = $('#posTabs'), posItems = $('#posItems'), posBiz = $('#posBiz');
const cartList = $('#cartList'), subSpan = $('#sub'), taxSpan = $('#tax'), totSpan = $('#tot');

// Overlays
const payPrompt = $('#payPrompt');
const ppTitle = $('#ppTitle'), ppItems = $('#ppItems'), ppSub = $('#ppSub'), ppTax = $('#ppTax'), ppTot = $('#ppTot');

const picker = $('#picker'), pickList = $('#pickList');

// Tiny helpers
function $(id){ return document.getElementById(id.replace('#','')); }
function on(el, ev, fn){ el.addEventListener(ev, fn); }

// Global escape to hard-close
window.addEventListener('keydown', (e)=>{ if(e.key === 'Escape'){ NUI('close'); } });

// STATE
const TAX = 8.5;
let STATE = {
  open:false, app:'home',
  dash:null,
  pos:{ Repairs:[], Cosmetics:[], Performance:[] },
  biz:{},
  cart:{ items:[], subtotal:0, tax:0, total:0 }
};

// ROUTER
function show(app){
  STATE.app = app;
  for(const k in views){ views[k].style.display = k===app?'block':'none'; }
}
function goHome(){ show('home'); }
document.querySelectorAll('.app').forEach(a=>{ a.onclick=()=>show(a.dataset.app); });
document.querySelectorAll('.back').forEach(b=>on(b,'click',goHome));

// OPEN/CLOSE
on($('#closeBtn'),'click',()=>NUI('close'));

window.addEventListener('message', e=>{
  const { action, payload } = e.data || {};
  if(action==='open'){
    STATE.open=true; wrap.style.display='flex';
    STATE.dash = payload.dash||{};
    STATE.pos = payload.pos || STATE.pos;
    STATE.biz = payload.biz || {};
    posBiz.innerText = STATE.biz.name || 'Mechanic Shop';
    renderHome();
    renderJobs({ jobsNew:STATE.dash.jobsNew||[], jobsActive:STATE.dash.jobsActive||[] });
    renderStock({ stock:STATE.dash.stock||[] });
    renderRank(STATE.dash.profile||{}, STATE.dash.thresholds||[]);
    renderPOS();
    renderBoss();
    show('home');
  }
  if(action==='close'){ STATE.open=false; wrap.style.display='none'; }
  if(action==='jobs:update'){ renderJobs(payload); }
  if(action==='stock:update'){ renderStock(payload); }
  if(action==='pos:payPrompt'){ openPayPrompt(payload); }
});

// Rank bar
function pct(a,b){ if(!b||b<=0) return 0; return Math.max(0,Math.min(100, Math.floor((a/b)*100))); }
function renderRank(profile, thresholds){
  const xp = profile.xp||0, rank = profile.rank||1, nextNeed = profile.next_need || thresholds[rank] || null;
  const currNeed = thresholds[rank-1] || 0;
  const prog = nextNeed ? pct(xp-currNeed, nextNeed-currNeed) : 100;
  rankbox.innerHTML = `Rank ${rank} <span class="bar"><span style="width:${prog}%"></span></span>`;
}

// Jobs
function renderJobs({jobsNew=[], jobsActive=[]}){
  const fmtDeadline = (utc) => {
    if(!utc) return 'N/A';
    const d = new Date(utc+'Z');
    return `<span data-exp="${d.getTime()}"></span>`;
  };
  newJobs.innerHTML = jobsNew.map(j=>`<div class="card">
    <div class="row"><div><b>${j.type.toUpperCase()}</b> • ${j.plate}</div><div class="tag">Rank ${j.min_rank||1}+</div></div>
    <div>Deadline: ${fmtDeadline(j.deadline_at)}</div>
    <div class="row"><button class="btn" data-act="accept" data-id="${j.id}">Accept</button></div>
  </div>`).join('');
  activeJobs.innerHTML = jobsActive.map(j=>`<div class="card">
    <div class="row"><div><b>${j.type.toUpperCase()}</b> • ${j.plate}</div><div class="tag">${j.status}</div></div>
    <div class="row">
      <button class="btn-lite" data-act="start" data-id="${j.id}">Start</button>
      <button class="btn" data-act="finish" data-id="${j.id}">Finish</button>
    </div>
  </div>`).join('');
  tickDeadlines();
}
function tickDeadlines(){
  const nodes = document.querySelectorAll('[data-exp]');
  if(nodes.length===0) return;
  const tNow = Date.now();
  nodes.forEach(n=>{
    const t = Number(n.dataset.exp||0);
    const left = Math.max(0, Math.floor((t - tNow)/1000));
    const m = Math.floor(left/60), s = left%60;
    n.textContent = `${m}:${String(s).padStart(2,'0')}`;
    if(left<=0){ n.closest('.card')?.remove(); }
  });
  setTimeout(tickDeadlines, 250);
}
document.body.addEventListener('click', e=>{
  const btn = e.target.closest('button[data-act]');
  if(!btn) return;
  const id = Number(btn.dataset.id);
  const act = btn.dataset.act;
  if (act==='accept') NUI('acceptJob',{id});
  if (act==='start') NUI('startJob',{id});
  if (act==='finish'){ NUI('finishJob',{id,quality:80}); }
});

// Stock
function renderStock({stock=[]}){ stockDiv.innerHTML = stock.map(s=>`<div>${s.part_id}: ${s.qty}</div>`).join(''); }
on($('#orderOil'),'click',()=>NUI('orderParts',{items:[{part_id:'engine_oil',qty:5}]}));
let npcRunning=false; on(npcToggle,'click',()=>{ npcRunning=!npcRunning; npcToggle.textContent=npcRunning?'Stop':'Start'; NUI('toggleNPC',{enabled:npcRunning}); });

// POS
const cart=()=>STATE.cart;
function posSum(){
  const sub = cart().items.reduce((a,b)=>a + (b.price*b.qty), 0);
  const tax = +(sub * (TAX/100)).toFixed(2);
  const tot = +(sub + tax).toFixed(2);
  cart().subtotal=sub; cart().tax=tax; cart().total=tot;
  subSpan.textContent = `$${sub.toFixed(2)}`;
  taxSpan.textContent = `$${tax.toFixed(2)}`;
  totSpan.textContent = `$${tot.toFixed(2)}`;
}
function renderPOS(){
  const cats = Object.keys(STATE.pos);
  posTabs.innerHTML = cats.map((c,i)=>`<button class="btn${i===0?'':'-lite'}" data-cat="${c}">${c}</button>`).join('');
  posTabs.onclick=(e)=>{
    const b=e.target.closest('button[data-cat]'); if(!b) return;
    [...posTabs.children].forEach(x=>x.className='btn-lite'); b.className='btn';
    drawItems(b.dataset.cat);
  };
  drawItems(cats[0]||'Repairs');
  refreshCart();
}
function drawItems(cat){
  const items = STATE.pos[cat]||[];
  posItems.innerHTML = items.map(it=>`<div class="item" data-id="${it.id}" data-label="${it.label}" data-price="${it.price}">
    <div class="name">${it.label}</div><div class="price">$${Number(it.price).toFixed(2)}</div>
  </div>`).join('');
}
posItems.onclick=(e)=>{
  const n=e.target.closest('.item'); if(!n) return;
  const id=n.dataset.id, label=n.dataset.label, price=Number(n.dataset.price)||0;
  const line = cart().items.find(x=>x.id===id);
  if(line) line.qty+=1; else cart().items.push({id,label,price,qty:1,total:price});
  refreshCart();
};
function refreshCart(){
  cartList.innerHTML = cart().items.map((it,i)=>`<div class="cart-line" data-i="${i}">
    <div>${it.label} x${it.qty}</div><div>$${(it.qty*it.price).toFixed(2)}</div>
  </div>`).join('');
  posSum();
}
on($('#cartClear'),'click',()=>{ STATE.cart={items:[],subtotal:0,tax:0,total:0}; refreshCart(); });
on($('#cartReceipt'),'click',()=>{}); // receipt is issued after payment
on($('#cartHold'),'click',()=>{});     // not implemented in test build

// In-UI player picker (includes "Me")
on($('#cartPay'),'click',async()=>{
  if(cart().items.length===0) return;
  try{
    const res = await fetch(`https://${GetParentResourceName()}/pos:getNearby`,{method:'POST',body:'{}'});
    const list = await res.json();
    openPicker(list||[]);
  }catch(e){
    openPicker([]); // still allow charging self
  }
});

function openPicker(list){
  // always include self
  const rows = [{ src: 0, name: 'Me (charge myself)' }, ...list];
  pickList.innerHTML = rows.map(r=>`<div class="pick-line">
    <div>${r.name}</div>
    <button class="btn" data-pick="${r.src}">Charge</button>
  </div>`).join('');
  picker.style.display='flex';
}
on($('#pickCancel'),'click',()=>{ picker.style.display='none'; });
pickList.addEventListener('click',(e)=>{
  const b = e.target.closest('button[data-pick]'); if(!b) return;
  const targetSrc = Number(b.dataset.pick||0); // 0 means self
  picker.style.display='none';
  NUI('pos:requestCharge',{ targetSrc, cart: STATE.cart });
});

// CUSTOMER PAYMENT PROMPT (buyer side)
function openPayPrompt(inv){
  payPrompt.style.display='flex';
  ppTitle.textContent = `${inv.businessName} • Served by ${inv.sellerName}`;
  ppItems.innerHTML = (inv.items||[]).map(it=>`<div class="cart-line"><div>${it.label} x${it.qty||1}</div><div>$${(it.total||it.price||0).toFixed(2)}</div></div>`).join('');
  ppSub.textContent = `$${(inv.subtotal||0).toFixed(2)}`;
  ppTax.textContent = `$${(inv.tax||0).toFixed(2)}`;
  ppTot.textContent = `$${(inv.total||0).toFixed(2)}`;
  payPrompt.dataset.id = inv.id;
}
document.querySelectorAll('.pp-method .btn').forEach(b=>{
  b.onclick=()=>{ const id=payPrompt.dataset.id; NUI('pos:customerPay',{ invoiceId:id, method:b.dataset.pay, accept:true }); payPrompt.style.display='none'; };
});
on($('#ppDecline'),'click',()=>{ const id=payPrompt.dataset.id; NUI('pos:customerPay',{ invoiceId:id, method:'', accept:false }); payPrompt.style.display='none'; });

// Boss app renderers (unchanged from last drop)
const tabs = document.querySelectorAll('.boss-tabs .tab');
const panes = { general:$('#pane-general'), employees:$('#pane-employees'), pricing:$('#pane-pricing'), pos:$('#pane-pos'), finance:$('#pane-finance') };
tabs.forEach(t=>t.onclick=()=>{ tabs.forEach(x=>x.classList.remove('active')); t.classList.add('active'); const k=t.dataset.tab; for(const k2 in panes) panes[k2].style.display=(k2===k)?'flex':'none'; });

function renderHome(){}

function renderBoss(){
  $('#bizName').value = STATE.biz.name || 'Mechanic Shop';
  $('#colorPrimary').value = STATE.biz.primary || '#0BA378';
  $('#colorSecondary').value = STATE.biz.secondary || '#0B2E44';
  $('#logoUrl').value = STATE.biz.logo || '';
  $('#bizOpen').value = (STATE.biz.open?1:0);
  $('#logoPrev').src = STATE.biz.logo || '';

  const el = $('#empList'); const emps = STATE.biz.employees||[];
  el.innerHTML = emps.map(e=>`<div class="card"><h4>${e.name}</h4><div>Grade: ${e.grade}</div><div>Status: ${e.online?'Online':'Offline'}</div></div>`).join('');

  const pe = $('#priceEditor'); const cats = Object.keys(STATE.pos||{});
  pe.innerHTML = cats.map(c=>{
    const items = STATE.pos[c]||[];
    return `<div class="card"><h4>${c}</h4>` + items.map(it=>`
        <div class="row" style="gap:8px;margin:6px 0">
          <div style="flex:1">${it.label}</div>
          <input type="number" step="1" min="0" value="${it.price}" data-cat="${c}" data-id="${it.id}" style="width:110px;background:#0c1520;border:1px solid #1b2a3b;color:#dbe6f3;border-radius:8px;padding:6px">
          <button class="btn-lite" data-save="${c}|${it.id}|${it.label}">Save</button>
        </div>`).join('') + `</div>`;
  }).join('');
}
on($('#saveBiz'),'click',()=>{
  const basics = {
    name: $('#bizName').value.trim(),
    primary: $('#colorPrimary').value,
    secondary: $('#colorSecondary').value,
    logo: $('#logoUrl').value.trim(),
    open: $('#bizOpen').value === '1'
  };
  NUI('biz:updateBasics', basics);
});
on($('#priceEditor'),'click',(e)=>{
  const s = e.target.closest('button[data-save]'); if(!s) return;
  const [cat,id,label] = s.dataset.save.split('|');
  const inp = s.previousElementSibling;
  const price = Number(inp.value||0);
  NUI('biz:updatePrice', { category:cat, item:{ id, label, price } });
});
