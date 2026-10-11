// Иконки движков (стиль Ink): перенос docs/icons/engine_icons.js без изменения логики форм.
// ICONS[id](v) — элементы иконки; v = {h, t, m, d} в 0..1 (h — ручка 1.1, t — 1.2, m — 1.3,
// у 11–15 m — OUT→AUX, d — Decay 2.2). У элемента g — от каких параметров он зависит ('x' — ни от каких).
// iconSvg — SVG-строка: без hl все элементы класса w (белые), с hl — o (оранжевые, зависят от hl) и g (серые).
// Формулы перенесены как есть (компактная запись источника) — строгие проверки типов для них выключены.
// @ts-nocheck

export interface IconValues { h: number; t: number; m: number; d?: number; a?: boolean }
export type IconParam = 'h' | 't' | 'm' | 'd';
interface El { g: string; d?: string; c?: number[]; fill?: boolean; op?: number }

const TAU=Math.PI*2, clamp=(v,a=0,b=1)=>Math.max(a,Math.min(b,v)), f1=n=>n.toFixed(1);
const pts=(a:number[][])=>'M'+a.map(p=>f1(p[0])+' '+f1(p[1])).join('L');
const rnd=(seed:number)=>{let s=seed>>>0;return()=>{s+=0x6D2B79F5;let t=s;t=Math.imul(t^t>>>15,t|1);t^=t+Math.imul(t^t>>>7,t|61);return((t^t>>>14)>>>0)/4294967296;};};
const pol=(cx:number,cy:number,r:number,a:number)=>[cx+r*Math.cos(a*Math.PI/180),cy+r*Math.sin(a*Math.PI/180)];
const arc=(cx:number,cy:number,r:number,a0:number,a1:number)=>{const[x0,y0]=pol(cx,cy,r,a0),[x1,y1]=pol(cx,cy,r,a1);return`M${f1(x0)} ${f1(y0)}A${r} ${r} 0 ${Math.abs(a1-a0)>180?1:0} 1 ${f1(x1)} ${f1(y1)}`;};
const fx=(x0:number,x1:number,n:number,f:(x:number,u:number)=>number)=>{const a:number[][]=[];for(let i=0;i<=n;i++){const u=i/n,x=x0+(x1-x0)*u;a.push([x,f(x,u)]);}return a;};
const ring=(cx:number,cy:number,r:number,g:string,op?:number):El=>({g,c:[cx,cy,r],op});
const dot=(cx:number,cy:number,r:number,g:string):El=>({g,c:[cx,cy,r],fill:true});
const fold=(z:number)=>(2/Math.PI)*Math.asin(Math.sin(Math.PI/2*z));
const lerp=(a:number,b:number,u:number)=>a+(b-a)*u;

const CHORDS=[[0,12,24,36],[0,7,12,19],[0,5,7,12],[0,3,7,12],[0,3,7,10],[0,3,7,14],[0,3,7,17],[0,4,9,14],[0,4,7,14],[0,4,7,11],[0,4,7,12]];
const ICONS:Record<string,(v:IconValues)=>El[]>={
0:(v:IconValues):El[]=>{const L=26,w=0.1+0.4*v.t,r=0.5+0.45*v.m,L2=L*(1-0.25*v.h);
  const sq=fx(6,58,160,x=>{const p=((x-6)/L)%1;return p<w?10:28;});
  const saw=Lp=>fx(6,58,160,x=>{const p=((x-6)/Lp)%1,val=p<r?p/r:(1-p)/(1-r);return 54-16*val;});
  return[{g:'t',d:pts(sq)},{g:'h',d:pts(saw(L2)),op:.9},{g:'m',d:pts(saw(L))}];},
1:(v:IconValues):El[]=>{const b=(v.m-.5)*1.0;
  const c=fx(6,58,160,(x,u)=>{const a=Math.sin(TAU*1.5*u)+b,sh=(1-v.h)*a+v.h*Math.tanh(3*a),o=fold(sh*(0.8+2.4*v.t));return 32-20*clamp(o,-1,1);});
  return[{g:'x',d:'M6 32H58',op:.35},{g:'htm',d:pts(c)}];},
2:(v:IconValues):El[]=>{const r=1+v.h*3,I=v.t*5;
  const c=fx(24,60,160,(x,u)=>{const th=TAU*2*u,t2=th+I*Math.sin(r*th);return 32-20*Math.sin(t2+v.m*1.5*Math.sin(t2));});
  return[ring(11,16,5,'x'),ring(11,48,5,'x'),{g:'x',d:'M11 21V43',op:.6},{g:'m',d:arc(11,16,8.5,-90,-90+Math.max(20,v.m*300))},{g:'ht',d:pts(c)}];},
3:(v:IconValues):El[]=>{const s=0.07+0.2*v.m,env=u=>Math.exp(-Math.pow((u-.5)/s,2)),fr=3+v.t*12,t2=14+8+v.h*34;
  return[{g:'m',d:pts(fx(6,58,120,(x,u)=>24-18*env(u)))},{g:'m',d:pts(fx(6,58,120,(x,u)=>24+18*env(u)))},
  {g:'t',d:pts(fx(6,58,200,(x,u)=>24-18*env(u)*Math.sin(TAU*fr*u)))},
  {g:'x',d:'M6 58H58',op:.4},{g:'x',d:'M14 58V49'},{g:'h',d:`M${f1(t2)} 58V49`}];},
4:(v:IconValues):El[]=>{const nb=1+Math.round(v.h*3),sg=2.6-v.m*2.0,c0=v.t*11;let d='';const cs:number[]=[];for(let k=0;k<nb;k++)cs.push((c0+k*12/nb)%12);
  for(let i=0;i<12;i++){const x=6+i*4.73,hh=Math.max(...cs.map(c=>Math.exp(-Math.pow(i-c,2)/(2*sg*sg))));d+=`M${f1(x)} 58V${f1(58-2-44*hh)}`;}
  return[{g:'htm',d:d}];},
5:(v:IconValues):El[]=>{const sel=Math.min(4,Math.round(v.t*4)),bank=Math.min(3,Math.floor(v.h*4)),cx=10+v.m*40,els:El[]=[];let cy=32;
  for(let r=0;r<5;r++){const by=46-r*8,x0=8+r*3,fw=u=>by-6*(Math.sin(TAU*u)+Math.sin(2*TAU*u+r*1.3+.6)/2+Math.sin(3*TAU*u+r*.7+1.2)/3)/1.5;
    els.push({g:r===sel?'t':'x',d:pts(fx(x0,x0+34,80,(x,u)=>{if(!v.a)return fw(u);const y=fw(Math.floor(u*14)/14);return by+Math.round((y-by)/1.6)*1.6;})),op:r===sel?1:.55});
    if(r===sel){const u=clamp((cx-x0)/34,0,1);cy=fw(u);}}
  els.push({g:'m',d:`M${f1(cx)} 6V50`,op:.9},{g:'m',c:[cx,cy,2.2],fill:true});
  for(let i=0;i<4;i++){const x=18+i*10;els.push(i===bank?{g:'h',d:`M${x} 55h6v5h-6z`,fill:true}:{g:'x',d:`M${x} 55h6v5h-6z`,op:.6});}
  return els;},
6:(v:IconValues):El[]=>{const idx=Math.min(10,Math.floor(v.h*11)),k=Math.min(3,Math.floor(v.t*4));let n=CHORDS[idx].slice();
  for(let i=0;i<k;i++){n.sort((a,b)=>a-b);n.push(n.shift()+12);}n.sort((a,b)=>a-b);
  const els=n.map((nn,i)=>dot(10+i*7,56-nn,2.6,'ht'));
  let wv=fx(40,60,60,(x,u)=>{let s=0,nm=0;const p=2-1.6*v.m;for(let q=1;q<=6;q++){s+=Math.sin(TAU*q*u)/Math.pow(q,p);nm+=1/Math.pow(q,p);}return 32-12*s/nm*1.3;});
  els.push({g:'m',d:pts(wv)});return els;},
7:(v:IconValues):El[]=>{const m=v.m,e=2*Math.abs(m-.5),w=m<.5?6+ m/.5*7:13+(m-.5)/.5*9,hh=m<.5?8+m/.5*4:12-(m-.5)/.5*8,mode=Math.min(3,Math.floor(v.h*4));
  const mouth:number[][]=[];for(let i=0;i<=40;i++){const a=TAU*i/40;mouth.push([32+w*Math.cos(a),38+hh*Math.sin(a)]);}
  const els=[ring(32,32,27,'x',.5),dot(32-(5+v.t*9),20,2.2,'t'),dot(32+(5+v.t*9),20,2.2,'t'),{g:'m',d:pts(mouth)+'Z'}];
  for(let i=0;i<4;i++)els.push(i===mode?dot(25+i*5,55.5,1.5,'h'):ring(25+i*5,55.5,1.5,'x',.6));return els;},
8:(v:IconValues):El[]=>{const R=rnd(7),N=6+Math.round(v.t*28),els:El[]=[];const rx:number[]=[],ry:number[]=[];for(let i=0;i<40;i++){rx.push(R());ry.push(R());}
  for(let i=0;i<N;i++)els.push(ring(8+rx[i]*48,32+(ry[i]-.5)*2*(3+v.h*26),1.5+v.m*5.5,'htm',.9));return els;},
9:(v:IconValues):El[]=>{const R=rnd(3),sw=1.2+(1-v.t)*7;const ns:number[][]=[];let x=6;while(x<58){const y=49+(R()-.5)*18;ns.push([x,y],[Math.min(58,x+sw),y]);x+=sw;}
  const lp=u=>1/(1+Math.pow(u/.45,6)),hp=u=>1/(1+Math.pow(.45/(u+.01),6)),bp=u=>Math.exp(-Math.pow((u-.5)/.16,2));
  const cv=fx(6,58,120,(x,u)=>{let c;if(v.h<.5){const a=v.h/.5;c=(1-a)*lp(u)+a*bp(u);}else{const a=(v.h-.5)/.5;c=(1-a)*bp(u)+a*hp(u);}
    c+=v.m*.9*Math.exp(-Math.pow((u-.5)/.05,2));return Math.max(4,34-24*clamp(c,0,1.3));});
  return[{g:'t',d:pts(ns),op:.9},{g:'hm',d:pts(cv)}];},
10:(v:IconValues):El[]=>{const R=rnd(11),N=3+Math.round(v.t*20),rx:number[]=[],ry:number[]=[];for(let i=0;i<30;i++){rx.push(R());ry.push(R());}
  const els:El[]=[];for(let r=0;r<3;r++)els.push(ring(32,32,10+r*8,'m',clamp((.65-v.m)*3,0,1)*.8));
  const bo=clamp((v.m-.35)*3,0,1)*.8;els.push({g:'m',d:'M20 6V58M44 6V58',op:bo});
  for(let j=0;j<N;j++){const c=j%6,r=Math.floor(j/6);els.push(dot(clamp(10+c*8.8+(rx[j]-.5)*v.h*18,4,60),clamp(14+r*9+(ry[j]-.5)*v.h*10,4,60),1.7,'ht'));}return els;},
11:(v:IconValues):El[]=>{const B=.02+v.h*.25,p=2.2-1.8*v.t,dc=5.5-4.6*v.m;let nm=0;for(let k=1;k<=6;k++)nm+=1/Math.pow(k,p);
  const c=fx(12,58,240,(x,u)=>{let s=0;for(let k=1;k<=6;k++)s+=Math.sin(TAU*k*3*Math.sqrt(1+B*k*k)*u)/Math.pow(k,p);return 32-22*Math.exp(-u*dc)*s/nm;});
  return[{g:'x',d:'M8 22V42M8 32H12'},{g:'htm',d:pts(c)}];},
12:(v:IconValues):El[]=>{const p=.5+1.7*v.h,els:El[]=[],rt=[1,2,3,4,5].map(i=>Math.pow(i,p));
  for(let i=0;i<5;i++)els.push(ring(32,32,8+18*(rt[i]-rt[0])/(rt[4]-rt[0]),'hm',Math.exp(-i*(1.4-1.3*v.m)*.55)));
  const n=3+Math.round(v.t*9);let d='';for(let i=0;i<n;i++){const a=TAU*i/n,c=Math.cos(a),s=Math.sin(a);d+=`M${f1(32+c*1.8)} ${f1(32+s*1.8)}L${f1(32+c*5.5)} ${f1(32+s*5.5)}`;}
  els.push({g:'t',d:d});return els;},
13:(v:IconValues):El[]=>{const dr=1+3*v.h,dc=7-5.5*v.m,tn=Math.tanh(dr);
  const c=fx(6,58,240,(x,u)=>{const env=Math.exp(-u*dc),ph=TAU*(6.5*u+2.2*(1-Math.exp(-u*10))),y=Math.sin(ph)+v.t*.5*Math.sin(3*ph);return 32-22*Math.tanh(dr*env*y)/tn;});
  return[{g:'x',d:'M6 32H58',op:.35},{g:'htm',d:pts(c)}];},
14:(v:IconValues):El[]=>{const R=rnd(5),dc=7-5.5*v.m,ns:number[][]=[];for(let x=6;x<58;x+=1.4){const u=(x-6)/52;ns.push([x,32-22*v.h*Math.exp(-u*dc)*(R()-.5)*2]);}
  const tn=fx(6,58,240,(x,u)=>32-22*(1-v.h*.8)*Math.exp(-u*dc)*((1-v.t)*Math.sin(TAU*5*u)+v.t*Math.sin(TAU*8.3*u)));
  return[{g:'x',d:'M6 32H58',op:.35},{g:'hm',d:pts(ns),op:.85},{g:'tm',d:pts(tn)}];},
15:(v:IconValues):El[]=>{const R=rnd(9),yc=54-v.t*24;let d='';
  for(let i=0;i<14;i++){const x=8+i*3.7,env=Math.exp(-(i/13)*(5.5-4.6*v.m)),h=Math.min(yc-5,(3+22*env)*(1-v.h*.75*R()));d+=`M${f1(x)} ${f1(yc)}V${f1(yc-h)}`;}
  return[{g:'hm',d:d},{g:'t',d:`M6 ${f1(yc)}H58`,op:.8}];},
s:(v:IconValues):El[]=>{const R=rnd(21),xs=8+v.t*40,xe=Math.max(xs+8,24+v.m*34),els:El[]=[];let bars='';
  for(let i=0;i<16;i++){const x=8+i*3.2;if(x<xs||x>xe)bars+=`M${f1(x)} ${f1(32-3-10*R())}V${f1(32+3+10*R())}`;else R();}
  els.push({g:'x',d:bars,op:.5});
  els.push({g:'h',d:pts(fx(xs,xe,160,(x,u)=>32-16*Math.sin(TAU*(2+v.h*8)*u)*Math.sin(Math.PI*u)))});
  els.push({g:'t',d:`M${f1(xs)} 8V56`},{g:'m',d:`M${f1(xe)} 8V56`});return els;}
};

const dd=(v:IconValues)=>v.d==null?.5:v.d;
Object.assign(ICONS,{
11:(v:IconValues):El[]=>{const d=dd(v),x=v.m,B=.02+v.h*.25,p=2.2-1.8*v.t,dc=7-5.5*d,R=rnd(31),N=240,raw:number[]=[];let nm=0;
  for(let k=1;k<=6;k++)nm+=1/Math.pow(k,p);for(let i=0;i<=N;i++)raw.push(R()*2-1);
  const sm=Math.round(1+(1-v.t)*6),sn=i=>{let s=0,c=0;for(let j=-sm;j<=sm;j++){const k=i+j;if(k>=0&&k<=N){s+=raw[k];c++;}}return s/c*(1+sm*.5);};
  const c=fx(12,58,N,(x_,u)=>{let so=0;for(let k=1;k<=6;k++)so+=Math.sin(TAU*k*3*Math.sqrt(1+B*k*k)*u)/Math.pow(k,p);
    const out=Math.exp(-u*dc)*so/nm,ex=Math.exp(-u*26)*clamp(sn(Math.round(u*N))*1.2,-1,1);return 32-22*((1-x)*out+x*ex);});
  return[{g:'x',d:'M8 22V42M8 32H12'},{g:'htmd',d:pts(c)}];},
12:(v:IconValues):El[]=>{const d=dd(v),x=v.m,p=.5+1.7*v.h,rt=[1,2,3,4,5].map(i=>Math.pow(i,p)),els:El[]=[],R=rnd(2);
  for(let i=0;i<5;i++)els.push(ring(32,32,8+18*(rt[i]-rt[0])/(rt[4]-rt[0]),'hmd',Math.exp(-i*(1.4-1.3*d)*.55)*(1-x)));
  const n=3+Math.round(v.t*9),l=lerp(5.5,24,x);let s='';
  for(let i=0;i<n;i++){const a=TAU*i/n,c=Math.cos(a),sn=Math.sin(a);s+=`M${f1(32+c*1.8)} ${f1(32+sn*1.8)}L${f1(32+c*l)} ${f1(32+sn*l)}`;}
  els.push({g:'tm',d:s});
  const nd=Math.round(v.t*14*x);for(let i=0;i<nd;i++){const a=R()*TAU,r=12+R()*16;els.push(dot(32+r*Math.cos(a),32+r*Math.sin(a),1.1,'tm'));}
  return els;},
13:(v:IconValues):El[]=>{const d=dd(v),x=v.m,dr=1+3*v.h,dc=7-5.5*d,tn=Math.tanh(dr),g=1+2.5*v.t,dr2=1+v.h*1.2;
  const c=fx(6,58,260,(x_,u)=>{const ph=TAU*(6.5*u+2.2*(1-Math.exp(-u*10))),y=Math.sin(ph)+v.t*.5*Math.sin(3*ph),out=Math.tanh(dr*Math.exp(-u*dc)*y)/tn;
    const q=(6.5*u+3.4*(1-Math.exp(-u*7)))%1,tri=4*Math.abs(q-.5)-1,au=Math.tanh(g*tri)/Math.tanh(g),aux=Math.tanh(dr2*Math.exp(-u*dc*.8)*au)/Math.tanh(dr2);
    return 32-22*((1-x)*out+x*aux);});
  return[{g:'x',d:'M6 32H58',op:.35},{g:'htmd',d:pts(c)}];},
14:(v:IconValues):El[]=>{const d=dd(v),x=v.m,dc=7-5.5*d,R=rnd(5),N=130,raw:number[]=[];for(let i=0;i<=N;i++)raw.push(R()*2-1);
  const at=i=>raw[Math.max(0,Math.min(N,i))],sm=i=>(at(i)+at(i-1)+at(i+1)+at(i-2))/4*1.7,hp=i=>(at(i)-at(i-1))/1.3;
  const nz=fx(6,58,N,(x_,u)=>{const i=Math.round(u*N);return 32-22*v.h*Math.exp(-u*dc)*((1-x)*sm(i)+x*hp(i));});
  const tn=fx(6,58,260,(x_,u)=>{const e=Math.exp(-u*dc),m1=Math.sin(TAU*5*u)*e,m2=Math.sin(TAU*8.3*u+.5)*Math.exp(-u*dc*1.5),m3=Math.sin(TAU*12.1*u)*Math.exp(-u*dc*2.2),
    out=(1-v.t)*m1+v.t*(.7*m2+.5*m3),aux=((1-v.t)*Math.sin(TAU*5*u+2.2*Math.sin(TAU*7.3*u))+v.t*Math.sin(TAU*8.3*u+1.6*Math.sin(TAU*3.1*u)))*e;
    return 32-22*(1-v.h*.8)*((1-x)*out+x*aux);});
  return[{g:'x',d:'M6 32H58',op:.35},{g:'hmd',d:pts(nz),op:.85},{g:'tmd',d:pts(tn)}];},
15:(v:IconValues):El[]=>{const d=dd(v),x=v.m,R=rnd(9),yc=54-v.t*24;let s='',sq='';
  for(let i=0;i<14;i++){const xo=8+i*3.7,gi=Math.floor(i/4.7),xa=14+gi*18+((i%5)-2)*1.5,xx=lerp(xo,xa,x),env=Math.exp(-(i/13)*(5.5-4.6*d)),j=R(),j2=R(),
    ho=(3+22*env)*(1-v.h*.75*j)*(.8+.2*j2),ha=(3+22*env)*(1-v.h*.4*j),h=Math.min(yc-5,lerp(ho,ha,x));
    s+=`M${f1(xx)} ${f1(yc)}V${f1(yc-h)}`;sq+=`M${f1(xx-1.4)} ${f1(yc-h-2.8)}h2.8v2.8h-2.8z`;}
  const els=[{g:'htmd',d:s},{g:'t',d:`M6 ${f1(yc)}H58`,op:.8}];if(x>.05)els.push({g:'htmd',d:sq,op:x});return els;}
});

/** Иконки: 0–15 — движки Plaits, 's' — сэмпл. */
export const ICON_IDS = [...Array.from({ length: 16 }, (_, i) => String(i)), 's'];

const match = (g: string, hl: IconParam | null) => !!hl && g.indexOf(hl) >= 0;

export function iconSvg(id: string, v: IconValues, hl: IconParam | null, size: number): string {
  const parts: string[] = [];
  for (const e of ICONS[id](v)) {
    const cls = hl ? (match(e.g, hl) ? 'o' : 'g') : 'w';
    const op = e.op != null ? ` opacity="${e.op.toFixed(2)}"` : '';
    const fill = e.fill ? 'currentColor' : 'none';
    if (e.c) parts.push(`<circle class="${cls}" cx="${f1(e.c[0])}" cy="${f1(e.c[1])}" r="${e.c[2]}" fill="${fill}"${op}/>`);
    else parts.push(`<path class="${cls}" d="${e.d}" fill="${fill}"${op}/>`);
  }
  return `<svg viewBox="0 0 64 64" width="${size}" height="${size}" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">${parts.join('')}</svg>`;
}
