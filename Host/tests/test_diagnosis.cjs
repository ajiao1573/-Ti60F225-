const assert = require('node:assert/strict');
const {recognitionDiagnosis: diagnosis} = require('../static/diagnosis.js');
const s = {camera_ready:true, state:1, recognized:false, reject_reason:3,
  reject_name:'未分出六个字符', characters:1, capture_frame_id:476944,
  ascii_diagnostic:'ABC123', plate:null, bbox_valid:false, location_reason:3};
assert.equal(diagnosis(s,true).label, '未分出六个字符');
assert.match(diagnosis(s,true).hint, /1 个字符/);
assert.match(diagnosis(s,true).hint, /476944/);
assert.ok(!diagnosis(s,true).label.includes('ABC123'));
assert.equal(diagnosis(s,false).label, '等待识别');
assert.equal(diagnosis({...s,camera_ready:false},true).label, '相机未就绪');
assert.equal(diagnosis({...s,state:6},true).label, '识别已暂停');
assert.equal(diagnosis({...s,state:4},true).label, '正在识别');
assert.equal(diagnosis({...s,recognized:true,plate:'AUY359',state:5},true).label, 'AUY359');
assert.equal(diagnosis({...s,reject_reason:0,location_reason:0},true).label, '尚未定位车牌');
assert.equal(diagnosis({...s,reject_reason:0,location_reason:2},true).label, '候选区域过小');
console.log('PASS live segmentation failure, stale/paused/capture/success and no-candidate diagnosis');
