const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const {recognitionDiagnosis} = require('../static/diagnosis.js');
const elements = new Map();
function element(id) {
  if (!elements.has(id)) elements.set(id, {textContent:'', className:'', value:'',
    addEventListener(){}, classList:{toggle(){},add(){}}});
  return elements.get(id);
}
const status = {camera_ready:true,state:1,state_name:'搜索车牌',recognized:false,
  reject_reason:3,reject_name:'未分出六个字符',characters:1,capture_frame_id:476944,
  bbox_valid:false,bbox:{x:0,y:20,width:424,height:152},edge_threshold:70,
  char_adjust:83,char_offset:-45};
const state = {connected:true,responding:true,status,status_age_ms:20};
const writes=[];
const context = vm.createContext({recognitionDiagnosis,AbortController,setTimeout,clearTimeout,
  document:{getElementById:element,querySelector:element,querySelectorAll:()=>[]},
  fetch:async(path,options)=>{
    let result=state;
    if(options.method==='POST') {
      const request=JSON.parse(options.body); writes.push(request);
      status[request.command==='edge'?'edge_threshold':'char_adjust']=request.value;
      result={acknowledged:true,applied:false};
    }
    return {ok:true,json:async()=>result};
  }});
vm.runInContext(fs.readFileSync(require.resolve('../static/app.js'),'utf8').replace('ports(); polling();',''),context);
context.testState=state;
vm.runInContext('render(testState)',context);
assert.equal(element('plate').textContent,'未分出六个字符');
assert.match(element('resultHint').textContent,/1 个字符/);
assert.match(element('bbox').textContent,/最近抓帧框（非当前定位）/);
assert.equal(element('plate').className,'plate');
vm.runInContext('control("defaults")',context).then(()=>{
  assert.deepEqual(writes,[{command:'edge',value:27},{command:'adjust',value:128}]);
  assert.equal(element('edge').value,'27'); assert.equal(element('adjust').value,'0');
  assert.equal(status.edge_threshold,27); assert.equal(status.char_adjust,128);
  const livePath = process.argv[2];
  if (livePath) {
    context.testState=JSON.parse(fs.readFileSync(path.resolve(livePath),'utf8'));
    vm.runInContext('render(testState)',context);
    assert.ok(context.testState.responding && context.testState.status.recognized);
    assert.equal(element('plate').textContent,context.testState.status.plate);
    assert.equal(element('plate').className,'plate valid');
    console.log('PASS actual UI render of captured live board result '+element('plate').textContent);
  }
  console.log('PASS actual UI render of live failure and sequential default-parameter restore');
}).catch(error=>{console.error(error);process.exitCode=1;});
