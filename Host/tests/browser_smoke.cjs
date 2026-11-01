// Requires an existing local Playwright + Edge installation; no downloads.
const {chromium} = require('playwright');
const {spawn,spawnSync} = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root=path.resolve(__dirname,'..');
const python=process.env.TI60_PYTHON || 'python';
const edge=process.env.TI60_EDGE || 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe';
const processes=[];
const results=[];
async function service(exe,args){
 const proc=spawn(exe,args,{cwd:root,windowsHide:true,env:{...process.env,PYTHONUTF8:'1'}}); processes.push(proc);
 let output=''; proc.stdout.on('data',b=>output+=b.toString()); proc.stderr.on('data',b=>output+=b.toString());
 return await new Promise((resolve,reject)=>{
  const timer=setInterval(()=>{const m=output.match(/http:\/\/127\.0\.0\.1:\d+\//);if(m){clearInterval(timer);clearTimeout(limit);resolve(m[0]);}},50);
  const limit=setTimeout(()=>{clearInterval(timer);reject(new Error('service startup timeout: '+output));},15000);
  proc.once('error',e=>{clearInterval(timer);clearTimeout(limit);reject(e);});
 });
}
async function waitText(page,selector,needle){await page.waitForFunction(([s,n])=>document.querySelector(s).textContent.includes(n),[selector,needle]);}
async function main(){
 const browser=await chromium.launch({headless:true,executablePath:edge});
 try{
  const page=await browser.newPage({viewport:{width:1440,height:1100},locale:'zh-CN'});
  const errors=[];page.on('pageerror',e=>errors.push(e.message));
  const url=await service(path.join(root,'dist','Ti60PlateControl.exe'),['--no-browser','--port','0']);
  await page.goto(url);await waitText(page,'#service','本地服务正常');
  assert.equal(await page.locator('.task.future:disabled').count(),4);
  assert.equal(await page.locator('#rescan').isDisabled(),true);
  assert.equal(await page.locator('#plate.valid').count(),0);
  assert.equal((await (await page.request.get(url+'api/ports')).json()).ports instanceof Array,true);
  await page.screenshot({path:path.join(__dirname,'ui_disconnected.png'),fullPage:true});
  results.push('PASS standalone EXE: Chinese page/assets, bundled serial enumeration, disconnected state, four disabled future tasks');
  const fixture=await service(python,[path.join(__dirname,'ui_fixture.py')]);
  await page.goto(fixture);await page.selectOption('#ports','COM_TEST_ONLY');await page.click('#connect');
  await waitText(page,'#boardBadge','应答正常');
  await page.fill('#edge','44');await page.click('#setEdge');
  await waitText(page,'#commandResult','ACK 成功');await waitText(page,'#edgeActual','44');
  await page.fill('#adjust','-5');await page.click('#setAdjust');await waitText(page,'#adjustActual','-5');
  await page.click('#pause');await waitText(page,'#state','已暂停');
  await page.click('#run');await waitText(page,'#state','搜索');
  await page.request.post(fixture+'__test/board',{data:{plate:'ABC123'}});
  await waitText(page,'#plate','ABC123');assert.equal(await page.locator('#plate.valid').count(),1);
  await page.request.post(fixture+'__test/board',{data:{plate:'??????'}});
  await page.waitForFunction(()=>!document.querySelector('#plate').classList.contains('valid'));
  await page.request.post(fixture+'__test/board',{data:{plate:'AB1234'}});await waitText(page,'#plate','AB1234');
  await page.click('#rescan');await page.waitForFunction(()=>!document.querySelector('#plate').classList.contains('valid'));
  await page.request.post(fixture+'__test/board',{data:{plate:'ABC123'}});await waitText(page,'#plate','ABC123');
  await page.request.post(fixture+'__test/board',{data:{silent:true}});await waitText(page,'#boardBadge','无有效应答');
  assert.equal(await page.locator('#plate.valid').count(),0);assert.equal(await page.locator('#rescan').isDisabled(),true);
  await page.click('#disconnect');await waitText(page,'#serialBadge','未连接');
  await page.click('#connect');await waitText(page,'#boardBadge','应答正常');
  await page.request.post(fixture+'__test/board',{data:{plate:'ABC123'}});await waitText(page,'#plate','ABC123');
  const fixtureProcess=processes[processes.length-1];
  spawnSync('taskkill',['/PID',String(fixtureProcess.pid),'/T','/F'],{windowsHide:true});
  await waitText(page,'#service','不可用');assert.equal(await page.locator('#plate.valid').count(),0);
  assert.deepEqual(errors,[]);
  results.push('PASS browser + TEST fake UART: connect, edge/ADJ readback, pause/run, both valid formats, invalid ASCII, rescan, silence, disconnect, local service lost; no JS errors');
  await page.setViewportSize({width:760,height:1000});await page.goto(url);await waitText(page,'#service','本地服务正常');
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);
  results.push('PASS 760px layout: no horizontal overflow');
 }finally{await browser.close();}
}
main().catch(e=>{results.push('FAIL '+e.stack);process.exitCode=1;}).finally(()=>{
 for(const proc of processes){if(proc.exitCode===null && proc.pid)spawnSync('taskkill',['/PID',String(proc.pid),'/T','/F'],{windowsHide:true});}
 fs.writeFileSync(path.join(__dirname,'browser_smoke.log'),results.join('\n')+'\n'); console.log(results.join('\n'));
});
