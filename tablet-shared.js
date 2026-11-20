/* Family Hub v3.1: the tablet's read-only shared family dashboard.
   Authorization is enforced by Supabase RLS, not by hidden buttons. */
(function(global){
'use strict';
const $=id=>document.getElementById(id);
const esc=s=>String(s==null?'':s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const weekdays=['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'];
let data={events:[],meals:[],groceries:[]};
let currentTab='home', selectedDay=FamilyHubV3.localToday(), factOffset=0;
const today=FamilyHubV3.localToday();
const monthView=new Date(Number(today.slice(0,4)),Number(today.slice(5,7))-1,1);
let lastFactDay='';
var discoveryFacts=[["Space", "Sunlight takes about 8 minutes and 20 seconds to reach Earth.", "If the Sun suddenly went dark, when would we notice?"], ["Animals", "An octopus has three hearts and blue blood.", "Why might an animal need more than one heart?"], ["Science", "Sound cannot travel through the vacuum of space because it needs matter to carry vibrations.", "How do astronauts communicate?"], ["Earth", "Earth’s continents move a few centimeters each year as tectonic plates shift.", "What could happen where plates meet?"], ["Ocean", "The deepest known part of the ocean is Challenger Deep in the Mariana Trench.", "What challenges would a submarine face there?"], ["Animals", "Honeybees use a waggle dance to tell other bees where food is located.", "How else do animals communicate?"], ["Space", "Venus takes longer to rotate once than it takes to orbit the Sun.", "What would a day feel like on Venus?"], ["Nature", "A mature tree can move hundreds of liters of water from roots to leaves on a warm day.", "Where does that water go?"], ["Human Body", "Your heart beats roughly 100,000 times in a typical day.", "How could you estimate your own daily heartbeats?"], ["Animals", "Sharks existed hundreds of millions of years before the first dinosaurs.", "Why have sharks survived for so long?"], ["Math", "A googol is the number 1 followed by 100 zeros.", "Could you write a googol on one sheet of paper?"], ["Space", "The Moon moves about 3.8 centimeters farther from Earth each year.", "How might scientists measure that distance?"], ["Weather", "Lightning heats the air so rapidly that the expanding air creates thunder.", "Why do we see lightning before hearing thunder?"], ["Animals", "Some sea turtles can sense Earth’s magnetic field to help them navigate.", "How would you find your way without a map?"], ["History", "The Great Wall of China was built in sections over many centuries, not all at once.", "Why would people build such long walls?"], ["Plants", "Sunflowers are made of many tiny flowers packed together in one flower head.", "Can you spot the small flowers up close?"], ["Space", "Saturn is less dense than water, although no ocean is big enough to float it.", "What does density mean?"], ["Science", "Ice floats because water expands as it freezes, making ice less dense than liquid water.", "Why is floating ice important for lake animals?"], ["Animals", "A group of flamingos is sometimes called a flamboyance.", "What other unusual animal group names do you know?"], ["Earth", "Antarctica is the driest continent by average precipitation.", "How can a place full of ice be a desert?"], ["Engineering", "A bridge can expand and contract as temperatures change.", "Why do builders leave expansion joints?"], ["Space", "Mars has the tallest known volcano in the solar system: Olympus Mons.", "Why can volcanoes grow so large on Mars?"], ["Animals", "Dolphins breathe air and must come to the surface even when sleeping.", "How might they rest safely?"], ["Food", "Popcorn pops when water inside the kernel turns into steam and pressure builds.", "What would happen if a kernel had no water?"], ["Science", "A rainbow appears when sunlight is refracted, reflected, and dispersed inside water droplets.", "Where should the Sun be when you look for a rainbow?"], ["History", "Ancient Romans used concrete in structures that have lasted nearly 2,000 years.", "What makes some building materials last longer?"], ["Nature", "Some fungi form underground partnerships with tree roots, trading nutrients for sugars.", "How can different living things help each other?"], ["Animals", "A hummingbird can fly backward by changing how its wings move.", "What makes its flight different from an airplane?"], ["Space", "Jupiter has more than twice the mass of all the other planets combined.", "How does Jupiter compare with Earth in size?"], ["Human Body", "Your brain uses electrical and chemical signals to communicate between nerve cells.", "How fast do you think those signals travel?"], ["Engineering", "Triangles are used in many bridges because their shape resists changing under load.", "Can you build a strong bridge from paper triangles?"], ["Animals", "Axolotls can regrow lost limbs and some other body tissues.", "Why are scientists interested in studying them?"], ["Earth", "The Pacific Ocean is larger than all of Earth’s land area combined.", "How would you compare their areas on a globe?"], ["Science", "A magnet has north and south poles; cutting it in half makes two smaller magnets.", "Can you make a magnet with only one pole?"], ["Nature", "The rings in a tree trunk can help scientists estimate its age and past growing conditions.", "What might a very narrow ring tell us?"]];
function dateKey(date){
 if(!(date instanceof Date)||!Number.isFinite(date.getTime()))return '';
 return date.getFullYear()+'-'+String(date.getMonth()+1).padStart(2,'0')+'-'+String(date.getDate()).padStart(2,'0');
}
function eventDate(e){return new Date(e.starts_at);}
function eventDay(e){return dateKey(eventDate(e));}
function eventTime(e){
 if(e.description==='FH_ALL_DAY')return 'All day';
 const d=eventDate(e);return Number.isFinite(d.getTime())?d.toLocaleTimeString([],{hour:'numeric',minute:'2-digit'}):'';
}
function eventList(items){
 if(!items.length)return '<p class="muted">Nothing scheduled.</p>';
 return items.map(e=>{
  const owner=e.assigned_to||'Family';
  const detail=e.description&&e.description!=='FH_ALL_DAY'?' · '+e.description:'';
  return '<div class="shared-item"><span class="shared-event-time">'+esc(eventDay(e))+' · '+esc(eventTime(e))+'</span>'+
   '<strong>'+esc(e.title)+'</strong><span class="muted small">'+esc(owner+detail)+'</span></div>';
 }).join('');
}
function eventsOn(date){
 return (data.events||[]).filter(e=>eventDay(e)===date)
  .sort((a,b)=>String(a.starts_at).localeCompare(String(b.starts_at)));
}
function showFact(){
 const now=new Date(),day=Math.floor(Date.UTC(now.getFullYear(),now.getMonth(),now.getDate())/86400000);
 const f=discoveryFacts[((day+factOffset)%discoveryFacts.length+discoveryFacts.length)%discoveryFacts.length];
 $('factCategory').textContent=f[0];$('factText').textContent=f[1];
 $('factQuestion').textContent='Think about it: '+f[2];
 lastFactDay=dateKey(now);
}
function clock(){
 const now=new Date();
 $('hubClock').textContent=now.toLocaleTimeString([],{hour:'numeric',minute:'2-digit'});
 if(lastFactDay!==dateKey(now))showFact();
}
function renderHome(){
 const now=FamilyHubV3.localToday();
 $('homeDate').textContent=new Date(now+'T12:00:00').toLocaleDateString(undefined,{weekday:'long',month:'long',day:'numeric',year:'numeric'});
 const future=(data.events||[]).filter(e=>eventDay(e)>=now)
  .sort((a,b)=>String(a.starts_at).localeCompare(String(b.starts_at))).slice(0,6);
 $('homeEvents').innerHTML=eventList(future);
 const todaysMeals=(data.meals||[]).filter(m=>Number(m.day_of_week)===FamilyHubV3.dayOfWeek(now));
 $('todayMeal').textContent=todaysMeals.length?todaysMeals.map(x=>x.meal_name).join(' · '):'No dinner planned yet.';
 const remaining=(data.groceries||[]).filter(g=>!g.completed).length;
 $('grocerySummary').textContent=remaining+' item'+(remaining===1?'':'s')+' left on your grocery list';
}
function renderCalendar(){
 const yr=monthView.getFullYear(),mo=monthView.getMonth();
 $('calMonth').textContent=monthView.toLocaleDateString(undefined,{month:'long',year:'numeric'});
 const offset=new Date(yr,mo,1).getDay(),days=new Date(yr,mo+1,0).getDate();
 const cells=[];
 for(let j=0;j<offset;j++)cells.push('<div class="calendar-placeholder" aria-hidden="true"></div>');
 for(let d=1;d<=days;d++){
  const iso=dateKey(new Date(yr,mo,d)),events=eventsOn(iso);
  const names=events.slice(0,2).map(e=>'<span class="day-event">'+esc(e.title)+'</span>').join('');
  cells.push('<button type="button" class="cal-day'+(iso===selectedDay?' selected':'')+(iso===FamilyHubV3.localToday()?' is-today':'')+
   '" data-calendar-day="'+iso+'" aria-label="'+esc(new Date(yr,mo,d).toLocaleDateString(undefined,{month:'long',day:'numeric'}))+
   ', '+events.length+' event'+(events.length===1?'':'s')+'"><span class="day-number">'+d+'</span>'+names+
   (events.length>2?'<span class="day-more">+'+(events.length-2)+' more</span>':'')+'</button>');
 }
 $('calGrid').innerHTML=cells.join('');
 $('calSelectedTitle').textContent=new Date(selectedDay+'T12:00:00').toLocaleDateString(undefined,{weekday:'long',month:'long',day:'numeric'});
 $('calSelectedEvents').innerHTML=eventList(eventsOn(selectedDay));
}
function renderMeals(){
 const now=FamilyHubV3.localToday(),weekday=FamilyHubV3.dayOfWeek(now);
 const rows=weekdays.map((name,i)=>{
  const meals=(data.meals||[]).filter(m=>Number(m.day_of_week)===i);
  return '<div class="meal-row'+(weekday===i?' today-row':'')+'"><span class="meal-day">'+name+(weekday===i?' · Today':'')+
    '</span><span>'+esc(meals.map(x=>x.meal_name).join(' · ')||'Not planned')+'</span></div>';
 }).join('');
 $('mealList').innerHTML=rows;
}
function renderGroceries(){
 const groceries=(data.groceries||[]).slice().sort((a,b)=>Number(!!a.completed)-Number(!!b.completed));
 $('groceryList').innerHTML=groceries.length?groceries.map(g=>'<div class="grocery-row'+(g.completed?' complete':'')+'">'+
  '<span aria-hidden="true">'+(g.completed?'☑':'☐')+'</span><span>'+esc(g.item_name)+
  (g.quantity?' <span class="muted small">('+esc(g.quantity)+')</span>':'')+'</span></div>').join(''):
  '<p class="muted">The grocery list is empty.</p>';
}
function setTab(tab){
 if(!['home','calendar','chores','meals','groceries'].includes(tab))return;
 currentTab=tab;
 document.querySelectorAll('[data-hub-tab]').forEach(b=>{
  const active=b.getAttribute('data-hub-tab')===tab;
  b.classList.toggle('active',active);
  b.setAttribute('aria-selected',String(active));
 });
 document.querySelectorAll('[data-hub-section]').forEach(s=>{s.hidden=s.getAttribute('data-hub-section')!==tab;});
 if(tab==='calendar')renderCalendar();
}
function render(next){
 data=next||data;
 renderHome();renderCalendar();renderMeals();renderGroceries();
}
function init(){
 document.querySelectorAll('[data-hub-tab]').forEach(b=>b.addEventListener('click',()=>setTab(b.getAttribute('data-hub-tab'))));
 document.querySelectorAll('[data-go-tab]').forEach(b=>b.addEventListener('click',()=>setTab(b.getAttribute('data-go-tab'))));
 $('calPrev').addEventListener('click',()=>{monthView.setMonth(monthView.getMonth()-1);selectedDay=dateKey(monthView);renderCalendar();});
 $('calNext').addEventListener('click',()=>{monthView.setMonth(monthView.getMonth()+1);selectedDay=dateKey(monthView);renderCalendar();});
 $('calNow').addEventListener('click',()=>{const now=FamilyHubV3.localToday();monthView.setFullYear(Number(now.slice(0,4)),Number(now.slice(5,7))-1,1);selectedDay=now;renderCalendar();});
 $('calGrid').addEventListener('click',e=>{
  const b=e.target.closest('button[data-calendar-day]');
  if(b){selectedDay=b.getAttribute('data-calendar-day');renderCalendar();}
 });
 $('nextFact').addEventListener('click',()=>{factOffset++;showFact();});
 showFact();clock();setInterval(clock,30000);setTab('home');
}
global.FamilyHubShared={init,render,setTab};
})(window);
