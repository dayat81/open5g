/* Client-only UX simulation. No network requests, adapters, or product API. */
(() => {
  'use strict';
  const STORAGE_KEY = 'hidayat-5g-lab-ux-prototype-v1';
  const $ = (selector, root = document) => root.querySelector(selector);
  const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];
  const esc = (value) => String(value ?? '').replace(/[&<>"']/g, (c) => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const clone = (value) => JSON.parse(JSON.stringify(value));
  const time = () => new Intl.DateTimeFormat('id-ID',{hour:'2-digit',minute:'2-digit',second:'2-digit',hour12:false}).format(new Date());
  const defaults = () => ({
    role: 'student',
    intent: { apn:'internet', logical_slice:'slice-class-A', qci:6, arp_priority:5, preemption_capability:'not-preempt', preemption_vulnerability:'not-vulnerable', ambr_ul:50,ambr_dl:100,mbr_ul:20,mbr_dl:40,gbr_ul:5,gbr_dl:10,
      usage:{scope:'app',app_id:'video-conf',threshold:500,window_s:300},
      app_rules:[{match_type:'SNI',pattern:'meet.example',app_id:'video-conf',priority:10,enabled:true},{match_type:'IP',pattern:'203.0.113.0/24',app_id:'bulk-dl',priority:20,enabled:true},{match_type:'hostname',pattern:'cdn.example.org',app_id:'web-cdn',priority:30,enabled:false}] },
    desired_version: 3, applied_version: 2, observed_version: 2, etag: 'etag-a1c2-v3', lifecycle: 'saved', updated_at: null,
    applied_intent: {qci:6,arp_priority:5,ambr_ul:50,ambr_dl:100,apn:'internet'},
    job: { status:'active', id:'job-7f3a', version:2, at:null, freshness:'8s' }, stale:false, fallback_path:null, audit:[]
  });
  let state;
  try {
    state = JSON.parse(localStorage.getItem(STORAGE_KEY));
    if (!state?.intent?.app_rules || !state?.job) state = defaults();
  } catch (_) { state = defaults(); }
  let dirty = false;
  let lastFocus = null;
  function persist() { try { localStorage.setItem(STORAGE_KEY,JSON.stringify(state)); return true; } catch (_) { toast('Browser memblokir penyimpanan lokal; perubahan hanya berlaku sementara.','fail'); return false; } }
  function toast(message,tone='applied') {
    const node = document.createElement('div'); node.className=`toast ${tone}`; node.setAttribute('role',tone==='fail'?'alert':'status');
    const text = document.createElement('span'); text.textContent=message;
    const close = document.createElement('button'); close.type='button'; close.className='toast-dismiss'; close.setAttribute('aria-label','Tutup notifikasi'); close.textContent='×'; close.onclick=()=>node.remove();
    node.append(text,close); $('#toast-region').append(node); window.setTimeout(()=>node.remove(),7500);
  }
  function badge(text,kind='unknown') { return `<span class="badge ${kind}">${esc(text)}</span>`; }
  function lifecycleBadge() {
    const s=state.lifecycle;
    if(s==='active')return badge('Active*','lifecycle-active');
    if(s==='pushed')return badge('Pushed · RAA ACK','applied');
    if(s==='queued')return badge('Queued','unknown');
    if(s==='rejected'||s==='failed')return badge('Rejected','fail');
    if(s==='fallback_pending')return badge('Menunggu re-attach','stale');
    return badge('Draft tersimpan','intent');
  }
  function actor() { return state.role === 'instructor' ? 'instructor:rani' : 'student:hidayat'; }
  function audit(event,reason) {
    state.audit.unshift({actor:actor(),owner:'student:hidayat',group:'kelas-5g-a',event,reason,at:time()}); state.audit=state.audit.slice(0,8);
  }
  function renderChrome() {
    const role=$('#role-switch'); if(role)role.value=state.role;
    const lifecycle=$('#profile-lifecycle'); if(lifecycle)lifecycle.innerHTML=`${lifecycleBadge()}<span class="mono">${esc(state.lifecycle)}</span><span class="badge unknown">localStorage</span>`;
  }
  function modal(content, labelled='dialog-title') {
    lastFocus=document.activeElement;
    $('#modal-root').innerHTML=`<div class="modal-backdrop"><section class="proto-dialog" role="dialog" aria-modal="true" aria-labelledby="${labelled}"><div class="dialog-header"><div class="dialog-eyebrow">Prototype · simulasi client-side</div><button type="button" class="dialog-close" data-close-modal aria-label="Tutup dialog">×</button></div>${content}</section></div>`;
    document.body.style.overflow='hidden'; document.querySelector('.page').inert=true;
    const dialog=$('.proto-dialog'); dialog.setAttribute('role','dialog'); dialog.setAttribute('aria-modal','true'); dialog.setAttribute('aria-labelledby',labelled);
    $$('[data-close-modal]').forEach(b=>b.addEventListener('click',closeModal));
    $('.modal-backdrop').addEventListener('mousedown',(e)=>{if(e.target===$('.modal-backdrop'))closeModal();});
    $('.dialog-close').focus();
  }
  function closeModal() {
    document.body.style.overflow=''; document.querySelector('.page').inert=false; $('#modal-root').innerHTML='';
    if(lastFocus&&document.contains(lastFocus))lastFocus.focus();
  }
  document.addEventListener('keydown',(e)=>{
    const dialog=$('.proto-dialog'); if(!dialog)return;
    if(e.key==='Escape'){e.preventDefault();closeModal();return;}
    if(e.key==='Tab'){
      const focusables=$$('button:not([disabled]),a[href],input:not([disabled]),select:not([disabled]),[tabindex="0"]',dialog);
      if(!focusables.length)return;
      if(e.shiftKey&&document.activeElement===focusables[0]){e.preventDefault();focusables.at(-1).focus();}
      else if(!e.shiftKey&&document.activeElement===focusables.at(-1)){e.preventDefault();focusables[0].focus();}
    }
  });
  function instructorDemo() {
    modal(`<h2 id="dialog-title">Demo batas akses Instructor</h2><p>Pilih kepemilikan IMSI untuk melihat aturan <strong>group-bound</strong>. Actor Instructor tetap tercatat bersama owner.</p><div class="group-tab"><button type="button" class="btn secondary selected" id="ingroup-choice">kelas-5g-a · in-group</button><button type="button" class="btn secondary" id="outgroup-choice">kelas-5g-b · out-of-group</button></div><div id="group-result" class="audit-detail">${badge('In-group diizinkan','applied')}<br><code>actor=instructor:rani<br>owner=student:hidayat<br>group=kelas-5g-a</code><br>Edit/apply dapat dilanjutkan di editor; setiap perubahan diaudit.</div><p class="demo-note">Akses ini simulasi UI — tidak ada server authorization yang benar-benar dipanggil.</p><div class="modal-actions"><button type="button" class="btn secondary" data-close-modal>Tutup</button><button type="button" class="btn primary" id="use-instructor">Gunakan role Instructor</button></div>`);
    const setChoice=(out)=>{
      $('#outgroup-choice').classList.toggle('selected',out); $('#ingroup-choice').classList.toggle('selected',!out);
      $('#group-result').innerHTML=out?`${badge('HTTP 403 · no-access','fail')}<br><strong>cross_group_forbidden</strong><br><code>actor=instructor:rani<br>owner=student:kelas-b-02<br>requested_group=kelas-5g-b<br>reason=cross_group_forbidden<br>audit=immutable · contoh</code><br>Aksi ditolak. Tidak ada perubahan intent/applied yang dibuat.`:`${badge('In-group diizinkan','applied')}<br><code>actor=instructor:rani<br>owner=student:hidayat<br>group=kelas-5g-a</code><br>Edit/apply dapat dilanjutkan; audit actor + owner dibuat.`;
    };
    $('#ingroup-choice').onclick=()=>setChoice(false); $('#outgroup-choice').onclick=()=>setChoice(true);
    $('#use-instructor').onclick=()=>{state.role='instructor';persist();renderChrome();closeModal();toast('Role demo: Instructor. IMSI kelas-5g-a tetap in-group.');};
  }
  function resetDemo() {
    modal('<h2 id="dialog-title">Reset prototype?</h2><p>Semua draft, versi, apply job, dan audit simulasi di browser ini akan kembali ke kondisi awal.</p><div class="modal-actions"><button type="button" class="btn secondary" data-close-modal>Batal</button><button type="button" class="btn primary" id="confirm-reset">Reset demo</button></div>');
    $('#confirm-reset').onclick=()=>{const role=state.role;state=defaults();state.role=role;persist();dirty=false;closeModal();if(document.body.dataset.page==='editor')fillForm();renderAll();toast('Demo direset ke profil awal.');};
  }
  $('#role-switch').addEventListener('change',(e)=>{state.role=e.target.value;persist();renderAll();toast(`Role demo: ${state.role==='instructor'?'Instructor':'Student'}.`);});
  $('#reset-demo').addEventListener('click',resetDemo);
  $('#open-instructor').addEventListener('click',instructorDemo);

  const labels={apn:'APN',logical_slice:'logical_slice',qci:'QCI',arp_priority:'arp.priority',preemption_capability:'arp.preemption_capability',preemption_vulnerability:'arp.preemption_vulnerability',ambr_ul:'ambr_ul (Mbps)',ambr_dl:'ambr_dl (Mbps)',mbr_ul:'mbr_ul (Mbps)',mbr_dl:'mbr_dl (Mbps)',gbr_ul:'gbr_ul (Mbps)',gbr_dl:'gbr_dl (Mbps)'};
  function readForm() {
    const intent={...readForm.current,usage:{scope:$('#scope').value,app_id:$('#usage-app-id').value.trim(),threshold:Number($('#threshold').value),window_s:Number($('#window').value)},
      app_rules:$$('#rule-rows tr').map((tr)=>({match_type:$('[data-rule="match_type"]',tr).value,pattern:$('[data-rule="pattern"]',tr).value.trim(),app_id:$('[data-rule="app_id"]',tr).value.trim(),priority:Number($('[data-rule="priority"]',tr).value),enabled:$('[data-rule="enabled"]',tr).checked}))};
    $$('[data-intent]').forEach(el=>{intent[el.dataset.intent]=el.type==='number'?Number(el.value):el.value;}); return intent;
  }
  function currentIntent() { return document.body.dataset.page==='editor'?readForm():state.intent; }
  function differences() {
    const intent=currentIntent(); const diffs=[];
    Object.keys(labels).forEach(k=>{if(String(intent[k])!==String(state.applied_intent[k]??state.intent[k]))diffs.push({key:k,from:state.applied_intent[k]??'—',to:intent[k]});});
    const old=JSON.stringify(state.applied_rules_snapshot||[{match_type:'IP',pattern:'198.51.100.0/24',app_id:'previous-demo',priority:10,enabled:true}]);
    if(JSON.stringify(intent.app_rules)!==old)diffs.push({key:'app_rules (new PCC rule)',from:'rule sebelumnya',to:`${intent.app_rules.filter(r=>r.enabled).length} aktif / ${intent.app_rules.length} total`});
    return diffs;
  }
  function diffRows(diffs=differences()) {
    if(!diffs.length)return '<div class="diff-row"><dt>Tidak ada diff</dt><dd>Intent saat ini sama dengan baseline simulasi.</dd></div>';
    return diffs.map(d=>`<div class="diff-row"><dt>${esc(labels[d.key]||d.key)}</dt><dd>${esc(d.from)} → <strong>${esc(d.to)}</strong></dd></div>`).join('');
  }
  function evidence() {
    if(state.job.status!=='pushed')return;
    state.job.status='active'; state.lifecycle='active'; state.job.freshness='baru saja';
    state.applied_version=Math.max(state.applied_version,state.job.version); state.observed_version=state.job.version;
    state.intent=state.job.snapshot?clone(state.job.snapshot):state.intent;
    state.applied_intent={...state.applied_intent,...Object.fromEntries(Object.keys(labels).map(k=>[k,state.intent[k]]))};
    state.applied_rules_snapshot=clone(state.intent.app_rules);
    audit('session_evidence_received','session_evidence_simulated'); persist();dirty=false;
    if(document.body.dataset.page==='editor')fillForm(); renderAll();toast('Bukti sesi simulasi diterima: baru sekarang Active. Bukan karena RAA ACK.','measured');
  }
  function applySupported() {
    const operation=differences().find(d=>['qci','arp_priority','preemption_capability','preemption_vulnerability','ambr_ul','ambr_dl'].includes(d.key));
    if(operation){rejectModal(operation);return;}
    state.lifecycle='queued';state.job={status:'queued',id:`job-${Math.random().toString(16).slice(2,6)}`,version:state.desired_version,at:time(),freshness:'menunggu',snapshot:clone(currentIntent())};
    audit('apply_requested','gx_rar_new_pcc_rule_simulated');persist();renderAll();toast('apply_job queued (simulasi). Tidak ada permintaan jaringan.');
    window.setTimeout(()=>{
      if(state.job.status!=='queued')return;
      state.job.status='pushed';state.lifecycle='pushed';state.job.freshness='baru saja';state.job.at=time();
      audit('raa_ack_received','pushed_not_active');persist();renderAll();
      toast('RAA ACK → pushed. RAA ACK ≠ Active; klik “Simulasikan bukti sesi”.');
    },900);
  }
  function rejectModal(operation) {
    const ambr=['ambr_ul','ambr_dl'].includes(operation.key);
    const reason=ambr?'op=apn_ambr · capability=unsupported · stock Open5GS 2.8':`op=${operation.key==='qci'?'modify_qci_existing_bearer':'modify_arp_existing_bearer'} · capability=unsupported · stock Open5GS 2.8`;
    state.lifecycle='rejected';state.rejection_reason=reason;state.job.status='rejected';audit('apply_rejected',reason);persist();renderAll();
    modal(`<h2 id="dialog-title" class="reject-title">Immediate Apply ditolak</h2><p>Gx RAR untuk operasi ini tidak didukung. <strong>Tidak ada perubahan Applied</strong> dan tidak ada auto-restart core.</p><div class="reason-box">${esc(reason)}<br>reject-with-reason · bukan silent success</div><div class="warn-box">Fallback opsional: <strong>UE re-attach</strong>. Ini bukan jalur utama; sesi pengguna akan terputus sementara dalam skenario nyata.</div><label class="check-label"><input type="checkbox" id="reattach-confirm"><span>Saya memahami dan mengonfirmasi simulasi <strong>re-attach fallback</strong> untuk IMSI 510…789.</span></label><p class="confirm-footnote">Konfirmasi tidak mengaktifkan profil otomatis; bukti sesi baru tetap diperlukan.</p><div class="modal-actions"><button type="button" class="btn secondary" data-close-modal>Tutup</button><button type="button" class="btn primary" id="confirm-fallback" disabled>Confirm re-attach fallback</button></div>`);
    $('#reattach-confirm').onchange=(e)=>{$('#confirm-fallback').disabled=!e.target.checked;};
    $('#confirm-fallback').onclick=()=>{state.lifecycle='fallback_pending';state.fallback_path='reattach_fallback';state.job.status='pushed';state.job.version=state.desired_version;state.job.id=`job-${Math.random().toString(16).slice(2,6)}`;state.job.at=time();state.job.snapshot=clone(currentIntent());state.job.freshness='menunggu sesi baru';audit('reattach_fallback_confirmed','session_evidence_required');persist();closeModal();renderAll();toast('Fallback re-attach dikonfirmasi (simulasi). Menunggu bukti sesi baru — belum Active.');};
  }
  function applyModal() {
    const current=collect(); if(!valid(current,true))return;
    const diffs=differences();
    modal(`<h2 id="dialog-title">Confirm Apply via Gx RAR</h2><p>desired_version <span class="mono">v${state.desired_version}</span> · IMSI <span class="mono">510…789</span></p><div class="warn-box"><strong>RAA ACK ≠ Active.</strong> Apply hanya mensimulasikan queued → pushed. Status Active membutuhkan bukti sesi per operasi. <strong>Tidak ada auto-restart core.</strong></div><div class="diff-box"><div class="diff-heading">Review perubahan</div>${diffRows(diffs)}</div><p class="note">Kemampuan diperiksa per operasi. QCI/ARP existing bearer dan APN-AMBR akan masuk jalur reject. Mock data only — tidak ada PCRF/Open5GS yang dihubungi.</p><div class="modal-actions"><button type="button" class="btn secondary" data-close-modal>Batal</button><button type="button" class="btn primary" id="confirm-apply">Apply via Gx RAR</button></div>`);
    $('#confirm-apply').onclick=()=>{closeModal();applySupported();};
  }

  function renderStateCards() {
    const i=currentIntent(); const applied=state.applied_intent;
    $('#state-cards').innerHTML=`
      <div class="state-card intent"><h4><span class="dot intent"></span> Intent · desired_version v${state.desired_version}</h4><div class="row"><span>lifecycle</span><span>${lifecycleBadge()} <span class="mono">${state.lifecycle}</span></span></div><div class="row"><span>APN / slice</span><span class="mono">${esc(i.apn)} / ${esc(i.logical_slice)}</span></div><div class="row"><span>QCI / ARP</span><span class="mono">${i.qci} / pri=${i.arp_priority}</span></div><div class="row"><span>AMBR UL / DL</span><span class="mono">${i.ambr_ul} / ${i.ambr_dl} Mbps</span></div><div class="row"><span>app_rules</span><span class="mono">${i.app_rules.length} rows</span></div><div class="row"><span>version_etag</span><span class="mono">${state.etag}</span></div>${dirty?'<div class="note">Perubahan form belum disimpan — draft dan etag belum berubah.</div>':''}</div>
      <div class="state-card applied"><h4><span class="dot applied"></span> Applied · applied_version v${state.applied_version}</h4><div class="row"><span>apply_job</span><span class="mono">${esc(state.job.id)}</span></div><div class="row"><span>PCRF / Gx RAR</span><span>${badge(state.job.status,state.job.status==='active'?'lifecycle-active':state.job.status==='pushed'?'applied':state.job.status==='rejected'?'fail':'unknown')}</span></div><div class="row"><span>QCI / ARP</span><span class="mono">${applied.qci} / pri=${applied.arp_priority}</span></div><div class="row"><span>AMBR UL / DL</span><span class="mono">${applied.ambr_ul} / ${applied.ambr_dl} Mbps</span></div><div class="row"><span>subscriber DB / eBPF</span><span>${badge('unverified','unknown')}</span></div><div class="note"><strong>RAA ACK ≠ Active.</strong> Applied menunjukkan only pushed/installed simulasi. Fallback: ${state.fallback_path||'tidak digunakan'}. Tidak ada Restart core.</div></div>
      <div class="state-card measured"><h4><span class="dot measured"></span> Measured · observed_version v${state.observed_version}</h4><div class="row"><span>Bukti sesi</span><span>${state.job.status==='active'?badge('session evidence','measured'):badge('menunggu / unknown','unknown')}</span></div><div class="row"><span>UE IP / bearer</span><span class="mono">10.45.0.12 / ebi=5</span></div><div class="row"><span>QCI terukur</span><span class="mono">${state.job.status==='active'?state.intent.qci:6} · ${state.job.status==='active'?'fresh':'belum diverifikasi untuk versi ini'}</span></div><div class="row"><span>capture point</span><span class="mono">S1-U / SGi</span></div><div class="note">Freshness: ${state.stale?'stale (simulasi)':state.job.freshness}. Unknown/stale/missing tidak disamarkan sebagai 0 atau sukses.</div></div>`;
    $('#lifecycle-timeline').innerHTML=['saved','queued','pushed','active'].map((s,index)=>`<span class="tl-step ${state.lifecycle===s?'now':''}">${({saved:'Draft',queued:'Queued',pushed:'Pushed',active:'Active*'})[s]}<span class="tl-enum">${s}</span></span>${index<3?'<span class="tl-arrow">→</span>':''}`).join('');
    if(state.audit[0])$('#audit-latest').innerHTML=`<div class="audit-mini"><strong>Audit terakhir (contoh)</strong><code>${esc(state.audit[0].event)}<br>actor=${esc(state.audit[0].actor)}<br>owner=${esc(state.audit[0].owner)}<br>reason=${esc(state.audit[0].reason)}</code></div>`;else $('#audit-latest').innerHTML='';
  }
  function renderRules() {
    $('#rule-rows').innerHTML=state.intent.app_rules.map((r,i)=>`<tr><td><select data-rule="match_type" aria-label="Rule ${i+1} match_type">${['IP','hostname','SNI'].map(v=>`<option ${r.match_type===v?'selected':''}>${v}</option>`).join('')}</select></td><td><input class="rule-pattern mono" data-rule="pattern" aria-label="Rule ${i+1} pattern" value="${esc(r.pattern)}" required></td><td><input class="app-id mono" data-rule="app_id" aria-label="Rule ${i+1} app_id" value="${esc(r.app_id)}" required></td><td><input class="rule-number mono" data-rule="priority" aria-label="Rule ${i+1} priority" type="number" min="1" value="${r.priority}" required></td><td><input data-rule="enabled" aria-label="Rule ${i+1} enabled" type="checkbox" ${r.enabled?'checked':''}></td><td><button type="button" class="btn ghost rule-delete" data-delete-rule="${i}" aria-label="Hapus rule ${i+1}: ${esc(r.app_id)}">Hapus</button></td></tr>`).join('');
    $('#app-ids').innerHTML=state.intent.app_rules.map(r=>`<option value="${esc(r.app_id)}">`).join('');
  }
  function fillForm() {
    Object.entries(state.intent).forEach(([k,v])=>{const el=$(`[data-intent="${k}"]`);if(el)el.value=v;});
    Object.entries(state.intent.usage).forEach(([k,v])=>{const el=$(`[data-usage="${k}"]`);if(el)el.value=v;}); renderRules();
  }
  function updateScope() {const app=$('#scope').value==='app';$('#usage-app-id').disabled=!app;$('#usage-app-id').required=app;$('#app-id-required').textContent=app?'(wajib)':'(n/a untuk session)';if(!app)$('#usage-app-id').value='';}
  function validRates(report=false) {
    const ok=Number($('#gbr-ul').value)<=Number($('#mbr-ul').value)&&Number($('#gbr-dl').value)<=Number($('#mbr-dl').value);
    $('#rate-validation').innerHTML=ok?`Validasi GBR ≤ MBR: UL ${$('#gbr-ul').value} ≤ ${$('#mbr-ul').value} ✓ · DL ${$('#gbr-dl').value} ≤ ${$('#mbr-dl').value} ✓`:'<span class="badge fail">Validasi gagal</span> GBR tidak boleh melebihi MBR per arah.';
    ['gbr-ul','gbr-dl'].forEach(id=>$('#'+id).setAttribute('aria-invalid',String(!ok)));return ok;
  }
  function showFormError(message) {const el=$('#form-error');el.textContent=message;el.hidden=false;}
  function clearFormError() {$('#form-error').hidden=true;}
  function collect() { dirty=true; return readForm(); }
  function valid(intent,report=false) {
    const ok=validRates(report)&&$('#intent-form').checkValidity()&&intent.app_rules.length>0&&intent.app_rules.every(r=>r.pattern&&r.app_id&&r.priority>0)&&!(intent.usage.scope==='app'&&!intent.usage.app_id);
    if(report&&!ok)showFormError(intent.app_rules.length===0?'Minimal satu app_rule diperlukan.':'Periksa field wajib, app_id untuk usage scope=app, dan validasi GBR ≤ MBR.');else if(ok)clearFormError();return ok;
  }
  if(document.body.dataset.page==='editor') {
    readForm.current=clone(state.intent);fillForm();updateScope();
    $('#intent-form').addEventListener('input',(e)=>{collect();validRates();if(e.target.id==='scope')updateScope();renderStateCards();});
    $('#intent-form').addEventListener('change',(e)=>{collect();renderStateCards();if(e.target.id==='scope')updateScope();});
    $('#rule-rows').addEventListener('click',(e)=>{const btn=e.target.closest('[data-delete-rule]');if(!btn)return;const tr=btn.closest('tr');const name=$('[data-rule="app_id"]',tr).value;tr.remove();dirty=true;renderStateCards();toast(`app_rule ${name} dihapus dari form; Save draft untuk menyimpan.`);});
    $('#add-rule').addEventListener('click',()=>{const latest=collect();latest.app_rules.push({match_type:'IP',pattern:'192.0.2.0/24',app_id:'lab-stream',priority:latest.app_rules.length*10+10,enabled:true});state.intent=latest;renderRules();updateScope();dirty=true;renderStateCards();$('#rule-rows tr:last-child [data-rule="pattern"]').focus();});
    $('#intent-form').addEventListener('submit',(e)=>{e.preventDefault();const intent=collect();if(!valid(intent,true))return;state.intent=intent;state.desired_version++;state.etag=`etag-a1c2-v${state.desired_version}-${Math.random().toString(36).slice(2,6)}`;state.lifecycle='saved';state.updated_at=time();audit('draft_saved','local_client_only');persist();dirty=false;renderAll();toast(`Draft v${state.desired_version} tersimpan di localStorage. Belum Applied atau Active.`);});
    $('#open-apply').addEventListener('click',applyModal);
    $('#review-diff').addEventListener('click',()=>{collect();modal(`<h2 id="dialog-title">Review diff Intent</h2><p>Perbandingan dengan baseline Applied simulasi. Perubahan belum disimpan juga terlihat.</p><div class="diff-box"><div class="diff-heading">Field berubah</div>${diffRows()}</div><p class="note">Desired ≠ Applied. SIMPAN draft terlebih dahulu agar perubahan bertahan saat pindah halaman.</p><div class="modal-actions"><button type="button" class="btn primary" data-close-modal>Tutup</button></div>`);});
  }

  function miniLayer(kind,title,version,text,status) {return `<div class="mini-layer ${kind}"><header><h3>${title}</h3>${status}</header><p>v${version} · ${esc(text)}</p></div>`;}
  function renderOverview() {
    const i=state.intent,a=state.applied_intent,active=state.job.status==='active';
    const mismatch=state.desired_version!==state.applied_version;
    $('#kpis').innerHTML=`<div class="card"><div class="k">Active sessions · contoh</div><div class="v">2</div><div class="s">${active?'Bukti sesi tersedia':'Sesi berjalan; profil terbaru belum terbukti'}</div></div><div class="card"><div class="k">Desired version</div><div class="v">v${state.desired_version}</div><div class="s">${state.lifecycle} · ${state.etag}</div></div><div class="card ${mismatch?'mismatch':''}"><div class="k">Draft vs Active mismatch</div><div class="v">${mismatch?'1':'0'}</div><div class="s">desired v${state.desired_version} ≠ applied v${state.applied_version}</div></div><div class="card unknown"><div class="k">Unverified adapters</div><div class="v">1</div><div class="s">Semua adapter mock · bukan bukti lab</div></div>`;
    const status=state.job.status;
    $('#apply-status').innerHTML=`<div class="status-main"><span id="apply-version" class="mono">v${state.job.version}</span><div class="status-copy"><strong>510…789 · Gx RAR</strong><span>${status==='active'?'RAR/RAA diterima + bukti sesi diterima':status==='pushed'?'RAR/RAA ACK diterima — menunggu session evidence':status==='queued'?'apply_job masuk antrean simulasi':status==='rejected'?'Immediate apply ditolak; Applied tidak berubah':'Draft tersimpan lokal'}</span></div>${badge(status,status==='active'?'lifecycle-active':status==='pushed'?'applied':status==='rejected'?'fail':'unknown')}<span class="freshness">${state.stale?'stale':state.job.freshness} · ${esc(state.job.at||'14:02:12')}</span></div>`;
    $('#evidence-button').disabled=status!=='pushed';$('#evidence-button').textContent=status==='active'?'✓ Bukti sesi diterima':status==='pushed'?'Simulasikan bukti sesi':'Menunggu RAA ACK';
    $('#evidence-help').textContent=status==='pushed'?'Jeda antara pushed dan Active: klik tombol untuk memberikan bukti sesi simulasi. Tidak ada auto-activation.':status==='active'?'Active berasal dari session evidence simulasi, bukan dari RAA ACK saja.':'Simpan draft lalu Apply pada Editor untuk memulai simulasi.';
    $('#state-comparison').innerHTML=miniLayer('intent','Intent · desired',state.desired_version,`QCI ${i.qci} · AMBR ${i.ambr_ul}/${i.ambr_dl} Mbps · ${i.app_rules.length} rules`,badge(state.lifecycle,'intent'))+miniLayer('applied','Applied · pushed/installed',state.job.version||state.applied_version,`QCI ${a.qci} · AMBR ${a.ambr_ul}/${a.ambr_dl} Mbps · RAR job`,badge(state.job.status,status==='active'?'lifecycle-active':status==='pushed'?'applied':status==='rejected'?'fail':'unknown'))+miniLayer('measured','Measured · session evidence',state.observed_version,active?'Bukti sesi tersedia · S1-U/SGi · QCI terukur':'Belum ada bukti untuk versi ini — bukan failed',badge(active?'fresh':'unknown',active?'measured':'unknown'));
    $('#session-details').innerHTML=`<div class="row"><span>UE IP / APN</span><span class="mono">10.45.0.12 / internet</span></div><div class="row"><span>bearer / QCI</span><span class="mono">ebi=5 / ${active?state.intent.qci:6}${active?'':' (baseline)'}</span></div><div class="row"><span>S1-U TEID</span><span class="mono">0x1a2b · eNB ↔ SGW-U</span></div><div class="row"><span>PGW-C / PGW-U</span><span class="mono">pgw-c-01 / pgw-u-01</span></div><div class="row"><span>freshness</span><span>${state.stale?badge('stale','stale'):active?badge('fresh','measured'):badge('unknown','unknown')}</span></div>`;
    $('#pcc-rows').innerHTML=i.app_rules.map(r=>{
      const native=r.match_type==='IP';const measured=active&&r.enabled;
      return `<tr><td><strong class="mono">${esc(r.app_id)}</strong><br>${esc(r.match_type)} · <span class="mono">${esc(r.pattern)}</span><br>priority ${r.priority} · ${r.enabled?'enabled':'disabled'}</td><td><span class="prov">${native?'IPFilterRule':r.match_type==='SNI'?'eBPF':'unknown'}</span><br>${native?'contoh stock path':'classify ≠ enforcement'}</td><td>${badge('Decided','decided')}<br>rule dari Intent<br>belum bukti installed</td><td>${native&&status==='active'?badge('installed (contoh)','applied'):native?badge('pending / unverified','unknown'):badge('native PCC unverified','unsupported')}</td><td>${!r.enabled?badge('disabled','unknown'):measured?badge('observed','measured'):badge('missing ≠ failed','missing')}<br>${measured?'data contoh · fresh':'0 traffic bukan failed'}</td></tr>`;
    }).join('');
    const first=i.app_rules[0]||{app_id:'(empty)'};
    $('#usage-rows').innerHTML=`<tr><td class="mono">${esc(first.app_id)}</td><td class="mono">12.4 MB / 60s</td><td><span class="prov">eBPF</span> ebpf-exp-01</td><td class="mono">SGi · pgw-u-01</td><td>${state.stale?badge('stale','stale'):badge('8s · fresh','measured')}</td><td>0.82</td></tr><tr><td class="mono">bulk-dl</td><td class="mono">0 / 60s</td><td><span class="prov">PFCP</span> pfcp-sx-01</td><td class="mono">Sx</td><td>${badge('missing','missing')}</td><td>—</td></tr><tr><td class="mono">unknown traffic</td><td class="mono">3.1 MB / 60s</td><td><span class="prov">PFCP</span> pfcp-sx-01</td><td class="mono">S1-U</td><td>${badge('ambiguous','ambiguous')}</td><td>—</td></tr>`;
  }
  function renderAll() {renderChrome();if(document.body.dataset.page==='overview') {renderOverview();}else{['desired-version','applied-version','observed-version'].forEach((id,index)=>{$('#'+id).textContent=`v${[state.desired_version,state.applied_version,state.observed_version][index]}`;});$('#version-etag').textContent=state.etag;renderStateCards();}}
  $('#evidence-button')?.addEventListener('click',evidence);
  $('#mark-stale')?.addEventListener('click',()=>{state.stale=!state.stale;persist();renderAll();toast(state.stale?'Telemetry ditandai stale (simulasi). Bukan failed.':'Telemetry kembali fresh (simulasi).',state.stale?'applied':'measured');});
  $$('[data-instructor-demo]').forEach(b=>b.addEventListener('click',instructorDemo));
  renderAll();
})();
