const $ = s => document.querySelector(s);
const state = {words:[], recent:new Set(), logs:[], running:false, frozen:false, timer:null, mag:0, motion:0, entropy:0, voices:[]};

async function loadDictionary(){
  const r = await fetch('assets/dictionary.txt', {cache:'force-cache'});
  const t = await r.text();
  state.words = t.split(/\r?\n/).filter(Boolean);
  $('#source').textContent = state.words.length.toLocaleString() + '-ENTRY WORD BANK';
  $('#status').textContent = 'FIELD LAB // READY';
}
function secure32(){
  const a = new Uint32Array(1); crypto.getRandomValues(a); return a[0] / 4294967296;
}
function hashNoise(){
  const s = `${performance.now()}|${Date.now()}|${state.mag}|${state.motion}|${Math.random()}|${navigator.userAgent}`;
  let h = 2166136261;
  for(let i=0;i<s.length;i++){h ^= s.charCodeAt(i); h = Math.imul(h,16777619);}
  return (h>>>0)/4294967296;
}
function weightedIndex(){
  const mode = $('#mode').value;
  let r = secure32();
  r = (r + hashNoise() + state.entropy) % 1;
  if(mode === 'rare') r = Math.pow(r, .62);
  if(mode === 'paranormal') r = (r*.78 + secure32()*.22) % 1;
  return Math.floor(r * state.words.length);
}
function scan(){
  if(!state.words.length || state.frozen) return;
  let word;
  for(let i=0;i<40;i++){
    word = state.words[weightedIndex()];
    if(!state.recent.has(word) || state.recent.size > state.words.length-50) break;
  }
  state.recent.add(word);
  if(state.recent.size > 150) state.recent.delete(state.recent.values().next().value);
  $('#word').textContent = word;
  $('#source').textContent = `SCAN // ${new Date().toLocaleTimeString()} // ${$('#mode').value.toUpperCase()}`;
  state.entropy = (secure32() + hashNoise())/2;
  $('#entropy').textContent = Math.round(state.entropy*1000) + '‰';
  $('#entbar').style.width = (state.entropy*100)+'%';
  if(navigator.vibrate) navigator.vibrate(18);
}
function speak(){
  const text = $('#word').textContent;
  if(!text || text==='READY') return;
  speechSynthesis.cancel();
  const u = new SpeechSynthesisUtterance(text);
  u.rate=.78; u.pitch=.82; u.volume=.95;
  speechSynthesis.speak(u);
}
function addLog(){
  const w=$('#word').textContent;
  if(!w || w==='READY') return;
  state.logs.unshift({word:w,time:new Date().toLocaleTimeString()});
  renderLog();
}
function renderLog(){
  const box=$('#log');
  if(!state.logs.length){box.innerHTML='<div class="tiny">No logged words.</div>';return;}
  box.innerHTML=state.logs.map((x,i)=>`<div class="entry"><b>${escapeHtml(x.word)}</b><span class="tiny">${x.time}</span></div>`).join('');
}
function escapeHtml(s){return s.replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[c]));}

async function requestSensors(){
  try{
    if(typeof DeviceMotionEvent!=='undefined' && typeof DeviceMotionEvent.requestPermission==='function'){
      const p=await DeviceMotionEvent.requestPermission(); if(p!=='granted') return;
    }
    window.addEventListener('devicemotion', e=>{
      const a=e.accelerationIncludingGravity || e.acceleration;
      if(a){const x=a.x||0,y=a.y||0,z=a.z||0; state.motion=Math.min(1,Math.abs(Math.sqrt(x*x+y*y+z*z)-9.81)/10);}
      $('#motion').textContent=Math.round(state.motion*100)+'%';
      $('#motionbar').style.width=(state.motion*100)+'%';
    });
  }catch(e){}
  // Magnetometer API is supported only on some browsers/devices.
  try{
    if('Magnetometer' in window){
      const m=new Magnetometer({frequency:10});
      m.addEventListener('reading',()=>{
        const x=m.x||0,y=m.y||0,z=m.z||0;
        state.mag=Math.sqrt(x*x+y*y+z*z);
        $('#mag').textContent=state.mag.toFixed(1)+' µT';
        $('#magbar').style.width=Math.min(100,state.mag/2)+'%';
      });
      m.addEventListener('error',()=>$('#mag').textContent='N/A');
      m.start();
    } else $('#mag').textContent='N/A';
  }catch(e){$('#mag').textContent='N/A';}
}
function updateTimer(){
  clearInterval(state.timer); state.timer=null;
  const ms=Number($('#interval').value);
  if(ms && state.running) state.timer=setInterval(scan,ms);
}
$('#start').onclick=async()=>{
  if(!state.running){
    state.running=true; state.frozen=false; $('#start').textContent='END SESSION'; $('#status').textContent='FIELD LAB // ACTIVE';
    await requestSensors(); scan(); updateTimer();
  }else{
    state.running=false; clearInterval(state.timer); state.timer=null; $('#start').textContent='START SESSION'; $('#status').textContent='FIELD LAB // READY';
  }
};
$('#scan').onclick=scan; $('#speak').onclick=speak; $('#logBtn').onclick=addLog;
$('#freeze').onclick=()=>{state.frozen=!state.frozen; $('#freeze').textContent=state.frozen?'UNFREEZE':'FREEZE';};
$('#clear').onclick=()=>{state.logs=[];renderLog();};
$('#interval').onchange=updateTimer;
loadDictionary().catch(()=>{ $('#word').textContent='LOAD ERROR'; $('#status').textContent='DICTIONARY UNAVAILABLE'; });

if('serviceWorker' in navigator) navigator.serviceWorker.register('sw.js').catch(()=>{});
