/* pf-mechanicjob • NUI (iPad layout) */
const $  = sel => document.querySelector(sel);
const $$ = sel => document.querySelectorAll(sel);

const root     = $('#root');
const pay      = $('#pay');
const btnClose = $('#btnClose');

const state = {
  open:false,
  view:'home',
  npcEnabled:false,
  dash:{ jobsNew:[], jobsActive:[], stock:[], profile:{xp:0,rank:1}, thresholds:[0,200,500,900,1400] },
  pay:{ open:false, invoice:null },
  mgmt:{
    canEdit:false,
    branding:null,
    catalog:{},
    employees:[],
    metrics:null,
    npcOn:false,
    headcount:{on:0,total:0}
  },
  mgmtTab:'overview',
  earn:null
};

const NUI = (a,p)=>fetch(`https://${GetParentResourceName()}/${a}`,{method:'POST',body:JSON.stringify(p||{})});

/* ================== RENDER ================== */
function show(v){
  $$('.view').forEach(el=>el.classList.add('hidden'));
  const el = $('#view-'+v);
  if (el) el.classList.remove('hidden');
}
function money(v){ return '$'+(Number(v||0).toFixed(2)); }
function pad2(n){ return String(n).padStart(2,'0'); }

function render(){
  root.style.display = state.open ? 'grid' : 'none';

  show(state.view);

  // HOME KPIs if we have earnings cached
  if (state.earn){
    $('#hLocal').textContent = money(state.earn.today_local||0);
    $('#hCust').textContent  = money(state.earn.today_customer||0);
    $('#hWeek').textContent  = money(state.earn.week||0);
    $('#hMonth').textContent = money(state.earn.month||0);
  }

  if (state.view==='npc')  renderNPC();
  if (state.view==='pos')  renderPOS();
  if (state.view==='mgr')  renderMgmt();
  if (state.view==='earn') renderEarnings();

  pay.style.display = state.pay.open ? 'grid' : 'none';
}

/* ================== HOME NAV ================== */
$('#app-npc').onclick      = ()=>{ state.view='npc';  render(); };
$('#app-pos').onclick      = ()=>{ state.view='pos';  render(); };
$('#app-gar').onclick      = ()=>{ state.view='gar';  render(); };
$('#app-lead').onclick     = ()=>{ state.view='lead'; render(); };
$('#app-mgr').onclick      = ()=>{ state.view='mgr';  NUI('pf_mech:mgmt:get',{}); render(); };
$('#app-settings').onclick = ()=>{ state.view='earn'; NUI('pf_mech:earnings:get',{}); render(); };

$('#btnHome').onclick = ()=>{ state.view='home'; render(); };
btnClose.onclick = ()=> NUI('close');

document.addEventListener('keydown',e=>{
  if (e.key === 'Escape' && state.open) NUI('close');
});

/* ================== NPC ================== */
function countdownStr(iso){
  const d  = new Date(iso);
  if (isNaN(d.getTime())) return 'N/A';
  const ms = d - new Date(); if (ms<=0) return 'Expired';
  const s  = Math.floor(ms/1000);
  const mm = Math.floor(s/60), ss = s%60;
  return `${pad2(mm)}:${pad2(ss)}`;
}
function refreshDeadlines(){
  $$('#listNew [data-deadline]').forEach(el=>{
    el.textContent = countdownStr(el.getAttribute('data-deadline'));
  });
}
setInterval(refreshDeadlines, 1000);

function jobCardNew(j){
  const left = j.deadline_at ? countdownStr(j.deadline_at) : 'N/A';
  return `<div class="line"><div>${(j.type||'job').toUpperCase()} • ${j.plate||''}</div><div class="muted" data-deadline="${j.deadline_at||''}">${left}</div></div>
          <div class="row gap end"><button class="btn" data-accept="${j.id}">Accept</button></div>`;
}
function jobCardActive(j){
  return `<div class="line"><div>${(j.type||'job').toUpperCase()} • ${j.plate||''}</div><div class="muted">${j.status||''}</div></div>
          <div class="row gap end"><button class="btn-lite" data-cancel="${j.id}">Cancel</button><button class="btn" data-finish="${j.id}">Finish</button></div>`;
}
function renderNPC(){
  const p  = state.dash.profile||{xp:0,rank:1};
  $('#rankLabel').textContent = `Rank ${p.rank||1}`;
  const th = state.dash.thresholds||[];
  let cur = Number(p.xp||0), prev=0, next=th[1]||200;
  for (let i=0;i<th.length;i++){ if (cur>=th[i]) { prev=th[i]; next=th[i+1]||th[i]; } }
  const fill = next===prev ? 100 : Math.max(0, Math.min(100, Math.round(100*(cur-prev)/Math.max(1,(next-prev)))));
  $('#rankFill').style.width = fill+'%';

  $('#listNew').innerHTML    = (state.dash.jobsNew||[]).map(j=>`<div class="card">${jobCardNew(j)}</div>`).join('');
  $('#listActive').innerHTML = (state.dash.jobsActive||[]).map(j=>`<div class="card">${jobCardActive(j)}</div>`).join('');
  $('#stockList').innerHTML  = (state.dash.stock||[]).map(s=>`<div class="line"><div>${s.part_id}</div><div>${s.qty}</div></div>`).join('');
}
$('#btnToggleNPC').onclick=()=>{
  state.npcEnabled=!state.npcEnabled;
  NUI('toggleNPC',{enabled:state.npcEnabled});
};
$('#listNew').addEventListener('click',e=>{
  const id=e.target?.getAttribute('data-accept'); if(id) NUI('acceptJob',{id:Number(id)});
});
$('#listActive').addEventListener('click',e=>{
  const f=e.target?.getAttribute('data-finish'); if(f) NUI('finishJob',{id:Number(f)});
  const c=e.target?.getAttribute('data-cancel'); if(c) NUI('cancelJob',{id:Number(c)});
});

/* ================== POS ================== */
const Catalog = { currentCat:null, data:{} };
const Cart = [];

function renderPOS(){
  const cats = Object.keys(Catalog.data||{});
  const seg  = $('#posCats'); seg.innerHTML='';
  cats.forEach((c,idx)=>{
    const b = document.createElement('button');
    b.className = 'seg-btn'+(Catalog.currentCat===c||(!Catalog.currentCat&&idx===0)?' active':'');
    b.textContent=c;
    b.onclick=()=>{ Catalog.currentCat=c; renderPOS(); };
    seg.appendChild(b);
  });
  if (!Catalog.currentCat && cats.length) Catalog.currentCat = cats[0];

  const items = (Catalog.data[Catalog.currentCat]||[]);
  const grid  = $('#posItems'); grid.innerHTML='';
  items.forEach(it=>{
    const el=document.createElement('div'); el.className='item';
    el.innerHTML = `<div class="title">${it.label}</div><div class="price">${money(it.price)}</div>
                    <div class="row gap end"><button class="btn" data-add="${it.id}">Add</button></div>`;
    grid.appendChild(el);
  });

  grid.onclick = (e)=>{
    const id = e.target?.getAttribute('data-add'); if(!id) return;
    const item = items.find(x=>String(x.id)===String(id)); if(!item) return;
    addToCart({ id, label:item.label, price:Number(item.price)||0, qty:1 });
  };

  renderCart();
}

function addToCart(it){
  const row = Cart.find(r=>String(r.id)===String(it.id));
  if (row) row.qty += it.qty;
  else Cart.push({...it});
  renderCart();
}
function renderCart(){
  const box = $('#cartList'); box.innerHTML='';
  let sub=0;
  Cart.forEach(r=>{
    const el=document.createElement('div'); el.className='line';
    el.innerHTML = `<div>${r.label} × ${r.qty}</div><div>${money(r.price*r.qty)}</div>`;
    box.appendChild(el);
    sub += r.price*r.qty;
  });
  $('#sub').textContent = money(sub);
  const tax=sub*0.085; $('#tax').textContent=money(tax);
  $('#tot').textContent = money(sub+tax);
}
$('#cartClear').onclick  = ()=>{ Cart.length=0; renderCart(); };
$('#cartReceipt').onclick= ()=>{};
$('#cartPay').onclick    = ()=>{ NUI('pos:requestCharge',{ targetSrc:0, cart:{items:Cart} }); };

/* ================== MANAGEMENT ================== */
function renderMgmt(){
  // tabs switching handled by event listener below
  if (state.mgmtTab==='overview'){
    const m = state.mgmt.metrics||{todayTotal:0,monthTotal:0,todayOrders:0,weeklyBars:[]};
    $('#kpiToday').textContent  = money(m.todayTotal||0);
    $('#kpiMonth').textContent  = money(m.monthTotal||0);
    $('#kpiOrders').textContent = Number(m.todayOrders||0);

    const bars = $('#barsWeekly'); bars.innerHTML='';
    (m.weeklyBars||[]).forEach(b=>{
      const col=document.createElement('div'); col.className='barcol';
      const rect=document.createElement('div'); rect.className='barrect';
      rect.style.height = Math.max(4,Math.min(100,Math.round((b.total||0)/10)))+'px';
      const day=document.createElement('div'); day.className='barday'; day.textContent = (b.day||'').slice(5);
      col.appendChild(rect); col.appendChild(day); bars.appendChild(col);
    });

    const stat=$('#mgrStatus'); stat.innerHTML='';
    const li1=document.createElement('div'); li1.className='line';
    li1.innerHTML=`<div>Local Jobs</div><div>${state.mgmt.npcOn?'Enabled':'Disabled'}</div>`; stat.appendChild(li1);

    const hc=state.mgmt.headcount||{on:0,total:0};
    const li2=document.createElement('div'); li2.className='line';
    li2.innerHTML=`<div>Employees on duty</div><div>${hc.on} / ${hc.total}</div>`; stat.appendChild(li2);

    $('#mgrStock').innerHTML = (state.dash.stock||[]).map(s=>`<div class="line"><div>${s.part_id}</div><div>${s.qty}</div></div>`).join('');
  }

  if (state.mgmtTab==='customize'){
    const b = state.mgmt.branding || { name:'Mechanic Shop', primary:'#0BA378', secondary:'#0B2E44', logo:'', open:1 };
    $('#bName').value      = b.name||'';
    $('#bPrimary').value   = b.primary||'#0BA378';
    $('#bSecondary').value = b.secondary||'#0B2E44';
    $('#bLogo').value      = b.logo||'';
    $('#bOpen').checked    = !!(Number(b.open||0)===1);
    $('#brandLogo').src    = b.logo||'';
    $('#brandName').textContent = b.name||'';
    document.documentElement.style.setProperty('--accent',  b.primary||'#0BA378');
    document.documentElement.style.setProperty('--accent2', b.secondary||'#0B2E44');
    $('#btnBrandSave').disabled = !state.mgmt.canEdit;
    $('#mgrRole').textContent = state.mgmt.canEdit ? 'Manager' : 'Read-only';
  }

  if (state.mgmtTab==='catalog'){
    const wrap = $('#mgrPrices'); wrap.innerHTML='';
    const cat  = state.mgmt.catalog || {};
    // Labor fee first (synthetic)
    const lf = document.createElement('div'); lf.className='card';
    const laborPrice = (cat.Labor && cat.Labor[0] && cat.Labor[0].price) || 0;
    lf.innerHTML = `<div class="line"><div>Labor Fee</div><div><input type="number" min="0" value="${laborPrice}" style="width:110px"></div></div>
                    <div class="row gap end"><button class="btn" data-saveprice="labor_fee" ${state.mgmt.canEdit?'':'disabled'}>Save</button></div>`;
    wrap.appendChild(lf);

    Object.keys(cat).forEach(k=>{
      if (k==='Labor') return;
      (cat[k]||[]).forEach(it=>{
        const el=document.createElement('div'); el.className='card';
        el.innerHTML=`<div class="line"><div>${it.label}</div>
                      <div><input type="number" min="0" value="${Number(it.price||0)}" style="width:110px"></div></div>
                      <div class="row gap end"><button class="btn" data-saveprice="${it.id}" ${state.mgmt.canEdit?'':'disabled'}>Save</button></div>`;
        wrap.appendChild(el);
      });
    });
  }

  if (state.mgmtTab==='employees'){
    const list = $('#mgrEmpList'); list.innerHTML='';
    const canEdit = state.mgmt.canEdit;
    (state.mgmt.employees||[]).forEach(e=>{
      const row=document.createElement('div'); row.className='card';
      row.innerHTML=`<div class="line"><div>${e.name} ${e.online?'<span style="color:#7dfd7d">●</span>':''}</div><div>Grade ${e.grade}</div></div>
                     <div class="line">
                       <input class="g-in" type="number" min="0" value="${e.grade||0}" style="width:80px" ${canEdit?'':'disabled'} title="Rank">
                       <input class="s-in" type="number" min="0" value="${e.salary||0}" style="width:90px" ${canEdit?'':'disabled'} title="Salary">
                       <input class="a-in" type="text" value="${e.avatar||''}" style="width:220px" ${canEdit?'':'disabled'} placeholder="Avatar URL">
                       <button class="btn" data-saveemp="${e.cid}" ${canEdit?'':'disabled'}>Save</button>
                     </div>`;
      list.appendChild(row);
    });
  }
}

const tabBar = $('#mgrTabs');
if (tabBar){
  tabBar.addEventListener('click',e=>{
    const btn=e.target.closest('.tab'); if(!btn) return;
    $$('#mgrTabs .tab').forEach(b=>b.classList.remove('active'));
    btn.classList.add('active');
    state.mgmtTab = btn.getAttribute('data-tab');
    $$('.mgr-pane').forEach(p=>p.classList.add('hidden'));
    $('#mgrPane-'+state.mgmtTab).classList.remove('hidden');
    renderMgmt();
  });
}

$('#btnBrandSave').onclick=()=>{
  if ($('#btnBrandSave').disabled) return;
  NUI('pf_mech:mgmt:saveBranding',{
    name: $('#bName').value,
    primary_color:  $('#bPrimary').value,
    secondary_color:$('#bSecondary').value,
    logo: $('#bLogo').value,
    open: $('#bOpen').checked
  });
};
$('#mgrPrices').addEventListener('click',e=>{
  const id=e.target?.getAttribute('data-saveprice'); if(!id) return;
  if (e.target.disabled) return;
  const card=e.target.closest('.card');
  const price=Number(card.querySelector('input[type=number]').value||0);
  const label=card.querySelector('.line > div').textContent.trim();
  NUI('pf_mech:mgmt:updatePrice',{ item_id:id, label, price });
});
$('#mgrEmpList').addEventListener('click',e=>{
  const cid=e.target?.getAttribute('data-saveemp'); if(!cid) return;
  if (e.target.disabled) return;
  const card=e.target.closest('.card');
  const grade = Number(card.querySelector('.g-in').value||0);
  const salary= Number(card.querySelector('.s-in').value||0);
  const avatar= card.querySelector('.a-in').value||'';
  NUI('pf_mech:mgmt:updateEmployee',{ cid, grade, salary, avatar });
});

/* ================== DOCK ================== */
$('#dock').addEventListener('click',e=>{
  const btn = e.target.closest('.dock-item'); if(!btn) return;
  state.view = btn.getAttribute('data-open') || 'home';
  if (state.view==='mgr') NUI('pf_mech:mgmt:get',{});     // just in case
  if (state.view==='earn') NUI('pf_mech:earnings:get',{}); 
  render();
});

/* ================== PAYMENT MODAL ================== */
$('#payCash').onclick = ()=>{ if(!state.pay.invoice)return; NUI('pos:customerPay',{invoiceId:state.pay.invoice.id,method:'cash',accept:true}); };
$('#payCard').onclick = ()=>{ if(!state.pay.invoice)return; NUI('pos:customerPay',{invoiceId:state.pay.invoice.id,method:'card',accept:true}); };
$('#payDecl').onclick = ()=>{ if(!state.pay.invoice)return; NUI('pos:customerPay',{invoiceId:state.pay.invoice.id,method:'card',accept:false}); };

/* ================== MESSAGES ================== */
window.addEventListener('message',(e)=>{
  const {action,payload}=e.data||{};
  switch(action){
    case 'open': {
      state.open=true; root.style.display='grid'; document.body.classList.add('open');
      state.view='home'; state.pay={open:false,invoice:null}; render();
      NUI('jobs:refresh',{}); break;
    }
    case 'close': {
      state.open=false; root.style.display='none'; document.body.classList.remove('open');
      state.pay={open:false,invoice:null}; render(); break;
    }
    case 'jobs:update':
      if(payload){
        state.dash.jobsNew    = payload.jobsNew    || [];
        state.dash.jobsActive = payload.jobsActive || [];
        state.dash.profile    = payload.profile    || {xp:0,rank:1};
        state.dash.thresholds = payload.thresholds || state.dash.thresholds;
      }
      if(state.view==='npc') renderNPC();
      break;

    case 'stock:update':
      if(payload) state.dash.stock=payload.stock||[];
      if(state.view==='npc' || state.view==='mgr') render();
      break;

    case 'pos:payPrompt':
      state.pay.open=true; state.pay.invoice=payload||null; render(); break;
    case 'pay:close':
      state.pay.open=false; state.pay.invoice=null; render(); break;

    /* Management payload */
    case 'pf_mech:mgmt:get:resp':
      if(payload){
        state.mgmt.canEdit   = !!payload.canEdit;
        state.mgmt.branding  = payload.branding || null;
        state.mgmt.metrics   = payload.metrics  || null;
        state.mgmt.catalog   = payload.catalog  || {};
        state.mgmt.employees = payload.employees|| [];
        state.mgmt.npcOn     = !!payload.npcOn;
        state.mgmt.headcount = payload.headcount || {on:0,total:0};
        Catalog.data = state.mgmt.catalog || {};
      }
      if(state.view==='mgr') renderMgmt();
      if(state.view==='pos') renderPOS();
      break;

    case 'pf_mech:npcState':
      state.npcEnabled = !!(payload && payload.on);
      state.mgmt.npcOn = state.npcEnabled;
      if (state.view==='npc' || state.view==='mgr') render();
      break;

    /* Employee earnings */
    case 'pf_mech:earnings:resp':
      if (payload){
        state.earn = payload;
        if (state.view==='earn' || state.view==='home') render();
      }
      break;

    /* In-game clock */
    case 'clock':
      if (payload){
        const h=pad2(payload.h||0), m=pad2(payload.m||0);
        $('#clock').textContent=`${h}:${m}`;
      }
      break;

    case 'toast':
      console.log('[MechanicOS]', payload?.text || '');
      break;
  }
});
