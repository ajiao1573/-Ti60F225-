// Uses test-only serial fixture. Production has no simulated result endpoint.
const {chromium}=require('playwright');
const {spawn,spawnSync}=require('node:child_process');
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..');
async function main(){
 const proc=spawn(process.env.TI60_PYTHON||'python',[path.join(__dirname,'ui_fixture.py')],{cwd:root,windowsHide:true,env:{...process.env,PYTHONUTF8:'1'}});
 let output='';proc.stdout.on('data',b=>output+=b);proc.stderr.on('data',b=>output+=b);
 const prod=spawn(path.join(root,'dist/Ti60PlateControl.exe'),['--no-browser','--port','0'],{cwd:root,windowsHide:true});
 let prodOutput='';prod.stdout.on('data',b=>prodOutput+=b);prod.stderr.on('data',b=>prodOutput+=b);
 let browser;
 try{
  const url=await new Promise((resolve,reject)=>{let elapsed=0;const timer=setInterval(()=>{const match=output.match(/http:\/\/127\.0\.0\.1:\d+\//);if(match){clearInterval(timer);resolve(match[0]);}else if((elapsed+=50)>10000){clearInterval(timer);reject(new Error(output));}},50);});
  browser=await chromium.launch({headless:true,executablePath:process.env.TI60_EDGE||'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe'});
  const page=await browser.newPage({viewport:{width:1440,height:1080},locale:'zh-CN'}),errors=[];
  page.on('pageerror',e=>errors.push(e.message));
  const prodURL=await new Promise((resolve,reject)=>{let n=0;const t=setInterval(()=>{const m=prodOutput.match(/http:\/\/127\.0\.0\.1:\d+\//);if(m){clearInterval(t);resolve(m[0]);}else if(++n>200){clearInterval(t);reject(new Error('EXE startup: '+prodOutput));}},50);});
  await page.goto(prodURL);await page.waitForSelector('.mode');assert.equal(await page.locator('.mode').count(),3);assert(await page.locator('#rescan').isDisabled());
  assert.equal((await (await page.request.get(prodURL+'api/health')).json()).service,'ti60-vision-control');
  assert.equal((await page.request.post(prodURL+'__test/board',{data:{task:1}})).status(),404);
  assert(Array.isArray((await (await page.request.get(prodURL+'api/ports')).json()).ports));
  await page.screenshot({path:path.join(__dirname,'web_disconnected.png'),fullPage:true});
  const waitText=async(id,text)=>page.waitForFunction(([id,text])=>document.getElementById(id).textContent.includes(text),[id,text]);
  const inject=async(data)=>{const r=await page.request.post(url+'__test/board',{data});assert.equal(r.status(),200);};
  await page.goto(url);await waitText('service','正常');assert(await page.locator('#rescan').isDisabled());
  await page.selectOption('#ports','COM_TEST_ONLY');await page.click('#connect');await waitText('boardBadge','正常');
  await inject({plate:'AUY359'});await waitText('plate','AUY359');
  await page.screenshot({path:path.join(__dirname,'web_plate.png'),fullPage:true});
  await page.fill('#edge','44');await page.click('#setEdge');await waitText('edgeActual','44');
  await page.click('[data-task="1"]');await waitText('plate','等待对应位流');assert(await page.locator('#freezeBean').isDisabled());assert(!(await page.locator('#plate').textContent()).includes('AUY359'));
  await inject({task:1,count:0});await waitText('resultTitle','豆子');await waitText('plate','0');assert.equal(await page.locator('body').getAttribute('data-mode'),'1');
  await inject({task:1,count:128});await waitText('plate','128');
  await page.screenshot({path:path.join(__dirname,'web_beans.png'),fullPage:true});
  await page.click('#resumeBean');await waitText('state','实时');await page.click('#freezeBean');await waitText('state','冻结');
  await inject({task:3,state:3,acc:-5325003});await waitText('plate','OK');await waitText('secondaryValue','-5325003');
  assert.equal(await page.locator('body').getAttribute('data-mode'),'3');
  await page.waitForFunction(()=>!document.getElementById('samplePart').disabled);
  await page.screenshot({path:path.join(__dirname,'web_parts.png'),fullPage:true});
  await page.click('#samplePart');await waitText('plate','检测中');assert.equal(await page.locator('#secondaryValue').textContent(),'—');
  await inject({task:3,state:4,kind:1,acc:17086369,result_id:8});await waitText('plate','NG');
  await inject({task:3,state:5,kind:2});await waitText('plate','INVALID');assert.equal(await page.locator('#secondaryValue').textContent(),'—');
  for(const width of [1920,1440,1366,1024,800,760,390]){
   await page.setViewportSize({width,height:1000});
   for(const task of [0,1,3]){
    await page.click(`[data-task="${task}"]`);
    assert(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth),`horizontal overflow ${width}/${task}`);
   }
  }
  await page.setViewportSize({width:390,height:844});await page.screenshot({path:path.join(__dirname,'web_mobile.png'),fullPage:true});
  await page.click('[data-task="0"]');await page.click('#followBoard');await inject({task:3,state:3});await waitText('plate','OK');
  await inject({silent:true});await waitText('boardBadge','无有效');assert(!(await page.locator('#plate').textContent()).includes('OK'));assert(await page.locator('#samplePart').isDisabled());
  await inject({silent:false,plate:'AB1234'});await waitText('plate','AB1234');assert.equal(await page.locator('body').getAttribute('data-mode'),'0');
  await page.click('#disconnect');await waitText('plate','等待连接');
  assert.deepEqual(errors,[]);
  fs.writeFileSync(path.join(__dirname,'browser_multimode.log'),'PASS: plate/bean/part auto identity; zero count; signed ACC; INVALID; command/readback; mismatch suppression; stale clearing; 7 viewport widths × 3 modes; no JS errors.\n');
  console.log(fs.readFileSync(path.join(__dirname,'browser_multimode.log'),'utf8'));
 }finally{if(browser)await browser.close();proc.kill();if(prod.pid)spawnSync('taskkill',['/PID',String(prod.pid),'/T','/F'],{windowsHide:true,stdio:'ignore',timeout:5000});prod.kill();prod.stdout.destroy();prod.stderr.destroy();prod.unref();}
}
main().catch(e=>{console.error(e);process.exitCode=1;});
