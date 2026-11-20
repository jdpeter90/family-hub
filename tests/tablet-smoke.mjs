import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const html=fs.readFileSync('tablet.html','utf8');
const shared=fs.readFileSync('tablet-shared.js','utf8');
const client=fs.readFileSync('v3-client.js','utf8');

new vm.Script(shared,{filename:'tablet-shared.js'});
new vm.Script(client,{filename:'v3-client.js'});
const inline=[...html.matchAll(/<script(?![^>]*\bsrc\b)[^>]*>([\s\S]*?)<\/script>/gi)];
assert.equal(inline.length,1,'Expected one inline tablet app script');
new vm.Script(inline[0][1],{filename:'tablet.html inline'});
assert.ok(html.includes('<script src="./tablet-shared.js"></script>'),'Shared script must load');
assert.ok(html.includes("FamilyHubShared.render(store)"),'Shared data must render');
for(const table of ['events','meals','groceries','chore_assignments','chore_completions']){
 assert.ok(html.includes("'"+table+"'"),'Missing table '+table);
}
const ids=[...html.matchAll(/\bid="([^"]+)"/g)].map(m=>m[1]);
assert.equal(new Set(ids).size,ids.length,'Duplicate HTML id');
for(const id of ['hubClock','homeDate','homeEvents','factText','factQuestion','factCategory',
 'calGrid','calSelectedEvents','calMonth','mealList','groceryList','kidButtons','childDashboard',
 'tasks','rewardShop','requests','loginForm','signOut','familyRefresh']){
 assert.ok(ids.includes(id),'Missing HTML element: '+id);
}
for(const section of ['home','calendar','chores','meals','groceries']){
 assert.ok(html.includes('data-hub-section="'+section+'"'),'Missing section '+section);
}
assert.ok(!html.includes('service_role'),'Do not put privileged keys in HTML');

const elems=new Map();
const get=id=>{
 if(!elems.has(id))elems.set(id,{
  id,textContent:'',innerHTML:'',hidden:false,
  classList:{add(){},remove(){},toggle(){}},
  addEventListener(){},setAttribute(){},getAttribute(){return '';}
 });
 return elems.get(id);
};
const today='2026-11-20';
const fakeFamily={
 localToday:()=>today,
 dayOfWeek:()=>5
};
const ctx={
 window:{FamilyHubV3:fakeFamily},FamilyHubV3:fakeFamily,
 document:{getElementById:get,querySelectorAll:()=>[]},
 Date,Math,Intl,Number,String,Array,Object,Set,Map,
 setInterval(){},
};
vm.createContext(ctx);
new vm.Script(shared).runInContext(ctx);
assert.equal(typeof ctx.window.FamilyHubShared.render,'function');
ctx.window.FamilyHubShared.init();
ctx.window.FamilyHubShared.render({
 events:[{title:'<img src=x onerror=alert(1)>',starts_at:'2026-11-20T18:00:00Z',assigned_to:'Family',description:'FH_ALL_DAY'}],
 meals:[{day_of_week:5,meal_name:'Spaghetti'}],
 groceries:[{item_name:'Milk',quantity:'2',completed:false},{item_name:'Bread',completed:true}]
});
assert.match(get('homeEvents').innerHTML,/&lt;img/,'Event title must be escaped');
assert.doesNotMatch(get('homeEvents').innerHTML,/<img/,'No executable event HTML');
assert.match(get('todayMeal').textContent,/Spaghetti/);
assert.match(get('groceryList').innerHTML,/Milk/);
assert.match(get('groceryList').innerHTML,/Bread/);
assert.match(get('calGrid').innerHTML,/\bcal-day\b/);
assert.match(get('factText').textContent,/./,'Daily discovery text must render');
console.log('PASS: tablet JavaScript parses; required UI exists; calendar, discovery, meals and groceries render and escape content.');
