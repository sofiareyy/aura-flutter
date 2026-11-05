// Correr con: node test/js/aura_analytics_test.js web/aura-analytics.js
// Simula un navegador (cookies, localStorage, URL) y prueba el embudo de GA4.
const fs=require('fs'), assert=require('assert');
const src=fs.readFileSync(process.argv[2],'utf8');
function correr({search='',hash='',cookie='',store={}}){
  const ls={getItem:k=>k in store?store[k]:null,setItem:(k,v)=>{store[k]=String(v)}};
  const hits=[];
  const window={location:{search,hash,pathname:'/',origin:'https://somosaurapass.com',href:'https://somosaurapass.com/'+search+hash,protocol:'https:'},localStorage:ls,dataLayer:[]};
  const jar={}; cookie.split(';').map(c=>c.trim()).filter(Boolean).forEach(c=>{const i=c.indexOf('=');jar[c.slice(0,i)]=c.slice(i+1)});
  const document={get cookie(){return Object.entries(jar).map(([k,v])=>k+'='+v).join('; ')},set cookie(v){const kv=v.split(';')[0];const i=kv.indexOf('=');jar[kv.slice(0,i)]=kv.slice(i+1)},head:{appendChild(){}},createElement:()=>({}),addEventListener(){}};
  new Function('window','document','URLSearchParams',src)(window,document,URLSearchParams);
  window.gtag=(...a)=>hits.push(a);
  return {window,hits,store};
}
// 1. llega con campaña antes y después del #
let r=correr({search:'?utm_source=ig&utm_medium=paid&fbclid=AbCdEfGhIjKl',hash:'#/landing?utm_campaign=nov&utm_content=v1',cookie:'_ga=GA1.1.111.222; _ga_CLBKV39C1M=GS2.1.s1730000000$o3$g1'});
r.window.auraAnalytics.usuario('uid-1');
r.window.auraAnalytics.evento('ver_landing',{});
const ev=r.hits.find(h=>h[1]==='ver_landing')[2];
assert.equal(ev.utm_source,'ig'); assert.equal(ev.utm_campaign,'nov'); assert.equal(ev.utm_content,'v1'); assert.equal(ev.fbclid,'AbCdEfGhIjKl'); assert.equal(ev.user_id,'uid-1');
assert.ok(!JSON.stringify(ev).includes('@'));
const d=JSON.parse(r.window.auraAnalytics.datosCheckout());
assert.equal(d.client_id,'111.222'); assert.equal(d.session_id,'1730000000'); assert.equal(d.atribucion.utm_medium,'paid');
// 2. vuelve sin campaña: se conserva
let r2=correr({store:r.store,cookie:'_ga_CLBKV39C1M=GS1.1.1700000001.2.1.1700000100.0.0.0'});
r2.window.auraAnalytics.evento('ver_packs',{});
assert.equal(r2.hits.find(h=>h[1]==='ver_packs')[2].utm_source,'ig');
assert.equal(JSON.parse(r2.window.auraAnalytics.datosCheckout()).session_id,'1700000001');
// 3. vence a los 30 días
const viejo=JSON.parse(r.store.aura_atribucion); viejo.t=Date.now()-31*86400000; r.store.aura_atribucion=JSON.stringify(viejo);
let r3=correr({store:r.store}); r3.window.auraAnalytics.evento('x',{});
assert.equal(r3.hits.find(h=>h[1]==='x')[2].utm_source,undefined);
// 4. interna: no manda nada y queda apagado al recargar
r3.window.auraAnalytics.marcarInterna(); const n=r3.hits.length; r3.window.auraAnalytics.evento('y',{});
assert.equal(r3.hits.length,n);
let r4=correr({store:r3.store}); assert.equal(r4.window['ga-disable-G-CLBKV39C1M'],true);
assert.equal(r4.window.auraAnalytics.datosCheckout(),'{}');
console.log('ok');
