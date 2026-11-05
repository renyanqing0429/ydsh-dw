// 临时自测：mock 一个最小 DOM，跑一遍看板的渲染脚本，确认无运行时异常且各容器都产出了内容
const fs = require('fs');
const path = require('path');
const html = fs.readFileSync(path.join(__dirname, 'index.html'), 'utf8');
const m = html.match(/<script>([\s\S]*?)<\/script>/);
if (!m) { console.log('NO SCRIPT FOUND'); process.exit(1); }

const store = {};
global.document = {
  getElementById: id => store[id] || (store[id] = { innerHTML: '' })
};

try {
  eval(m[1]);
} catch (e) {
  console.log('RUNTIME ERROR:', e.message);
  console.log(e.stack.split('\n').slice(0, 4).join('\n'));
  process.exit(1);
}

const ids = ['badges','kpis','trend','trend-note','donut','donut-legend','cat-bars','prov-bars',
             'rfm-dual','funnel','funnel-note','prod-bars','scatter','store-note','rfm-table',
             'foot-left','foot-right'];
let bad = 0;
ids.forEach(id => {
  const len = store[id] ? store[id].innerHTML.length : 0;
  const flag = len > 20 ? 'ok ' : 'EMPTY';
  if (len <= 20) bad++;
  console.log(String(len).padStart(6), flag, id);
});
console.log(bad === 0 ? '\nALL RENDER OK' : '\n' + bad + ' EMPTY CONTAINERS');
