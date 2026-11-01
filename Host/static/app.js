"use strict";
const $ = id => document.getElementById(id);
const text = (id, value) => { $(id).textContent = value ?? "—"; };
const badge = (id, value, kind = "") => { text(id, value); $(id).className = "badge " + kind; };
const modes = {
  0: {name:"车牌自动识别", title:"车牌识别结果", en:"PLATE RECOGNITION", caption:"识别号码", control:"识别参数", prefix:"plate", path:"Function_1_CMP/output/lens_corrected/Ti60_Demo.bit", pills:["自动定位", "六字符识别"]},
  1: {name:"豆子计数", title:"豆子计数结果", en:"OBJECT COUNTING", caption:"通过筛选的目标", control:"计数参数读回", prefix:"bean", path:"Function_2_CMP/output/host_web/Ti60_Demo.bit", pills:["连通域分析", "冻结帧计数"]},
  3: {name:"零件检测测试", title:"零件检测结果", en:"PART INSPECTION", caption:"外轮廓分类", control:"检测配置", prefix:"part", path:"Function_3/output/host_web/Ti60_Demo.bit", pills:["13 维特征", "试验模式"]}
};
let latest = null, selected = 0, detected = null, commandBusy = false;
function notice(message, error = false) { text("notice", message); $("notice").className = "notice" + (error ? " error" : ""); }
async function api(path, data) {
  const abort = new AbortController(), timer = setTimeout(() => abort.abort(), data === undefined ? 1800 : 4500);
  try {
    const response = await fetch(path, {cache:"no-store", signal:abort.signal, ...(data === undefined ? {} : {method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(data)})});
    const body = await response.json(); if (!response.ok) throw new Error(body.error || "请求失败"); return body;
  } catch (error) { if (error.name === "AbortError") throw new Error("本地服务请求超时，操作结果尚未确认"); throw error; }
  finally { clearTimeout(timer); }
}
function rows(id, items) {
  $(id).replaceChildren(...items.map(([label, value]) => {
    const row = document.createElement("div"), dt = document.createElement("dt"), dd = document.createElement("dd");
    dt.textContent = label; dd.textContent = value ?? "—"; row.append(dt, dd); return row;
  }));
}
function selectMode(task) {
  if (commandBusy) return;
  selected = task; text("commandResult", "尚未发送控制命令。");
  if (latest) render(latest);
}
function metric(index, label, value, unit = "") {
  text("metricLabel" + index, label); text("metricUnit" + index, unit);
  text(["inputFps", "edgeFps", "und", "total"][index - 1], value);
}
function render(data) {
  latest = data;
  const fresh = !!(data.connected && data.responding && data.status), actual = fresh ? data.status.task : null;
  if (actual !== null && actual !== detected) { selected = actual; detected = actual; text("commandResult", "板端模式已识别，结果与控制已切换。"); }
  if (!data.connected || !data.responding) detected = null;
  const mode = modes[selected], same = fresh && actual === selected, s = same ? data.status : null;
  document.body.dataset.mode = selected;
  [0,1,3].forEach(task => {
    const el = document.querySelector(`[data-task="${task}"]`);
    el.classList.toggle("active", selected === task); el.setAttribute("aria-pressed", String(selected === task));
    el.querySelector(".mode-indicator").textContent = fresh && actual === task ? "● 板端当前" : "查看";
    el.disabled = commandBusy;
    $(modes[task].prefix + "Actions").hidden = task !== selected;
    $(modes[task].prefix + "Parameters").hidden = task !== selected;
  });
  text("resultTitle", mode.title); text("resultEyebrow", mode.en); text("resultCaption", mode.caption); text("controlTitle", mode.control);
  text("resultPill1", mode.pills[0]); text("resultPill2", mode.pills[1]); text("firmwarePath", mode.path);
  text("firmwareName", fresh ? modes[actual].name : "尚未识别");
  $("followBoard").hidden = !fresh || same;
  text("modeHelp", fresh && !same ? `当前板端为${modes[actual].name}。加载下列配套位流后将自动切换；当前页不显示其他模式结果。` : "独立位流自动识别。更换位流后，本页跟随板端切换。");
  $("connect").disabled = data.connected || commandBusy; $("disconnect").disabled = !data.connected || commandBusy; $("ports").disabled = data.connected;
  document.querySelectorAll(".command").forEach(b => b.disabled = !same || commandBusy);
  if (same && selected === 3) $("samplePart").disabled = commandBusy || data.sample_pending || !s.camera_ready || s.state === 2;
  badge("serialBadge", data.connected ? `${data.port} 已打开` : "串口未连接", data.connected ? "good" : "");
  badge("boardBadge", fresh ? "板端应答正常" : data.connected ? "板端无有效应答" : "等待板端应答", fresh ? "good" : data.connected ? "warn" : "");
  badge("state", same && data.sample_pending ? "检测中" : s?.state_name ?? (fresh ? "等待对应位流" : "等待有效状态"), s?.result_valid ? (s.classification === "NG" || s.classification === "INVALID" ? "warn" : "good") : "");
  let value = fresh ? "等待对应位流" : data.connected ? "等待应答" : "等待连接", hint = fresh ? "请加载本模式配套位流，随后自动读取结果。" : "连接开发板后读取真实结果。";
  let detail = [], secondary = null, extra = "HDMI";
  text("idLabel", selected === 0 ? "抓取帧编号" : selected === 1 ? "分析批次" : "采样编号");
  text("secondaryLabel", selected === 0 ? "字符数量" : selected === 1 ? "已标注目标" : "ACC 分值");
  text("extraLabel", selected === 3 ? "筛选后点数" : "图像输出");
  if (s) {
    if (selected === 0) {
      const diagnosis = recognitionDiagnosis(s, true); value = diagnosis.label; hint = diagnosis.hint; secondary = s.characters;
      const b = s.bbox;
      detail = [["定位状态",s.location_name],["未通过原因",s.reject_name],["候选 / 抓帧框",`${b.x}, ${b.y} · ${b.width} × ${b.height}`],["二值参考阈值",s.binary_threshold],["冻结 / ROI",`${s.frozen ? "已冻结" : "实时"} / ${s.roi_ready ? "就绪" : "未就绪"}`],["对比度 / 字符溢出",`${s.low_contrast ? "LOW" : "正常"} / ${s.overflow ? "OVER" : "正常"}`]];
    } else if (selected === 1) {
      value = s.result_valid ? String(s.count) : s.overflow ? "计数异常" : s.camera_ready ? "分析中" : "相机未就绪";
      hint = s.result_valid ? (s.frozen ? "冻结帧计数已完成，绿框与数量来自同一次分析。" : "实时分析结果；冻结后可核对每个目标。") : "等待完整有效帧；错误与重算期间不显示旧数量。";
      secondary = s.boxes; detail = [["显示视图",["RAW","BINARY","RESULT"][s.view]], ["冻结状态",s.frozen ? "已冻结" : "实时"],["计数有效",s.result_valid ? "有效" : "未完成"],["图像错误",s.overflow ? "ERROR" : "正常"],["错误状态字",`0x${s.error_status.toString(16).padStart(2,"0")}`],["板端菜单",s.menu ? "调参中" : "关闭"]];
    } else {
      value = s.result_valid ? s.classification : s.state === 2 || data.sample_pending ? "检测中" : s.camera_ready ? "等待采样" : "相机未就绪";
      hint = s.classification === "INVALID" ? "拟合或特征无效，本次不作 OK / NG 判断。检查下方原因与采样点。" : s.result_valid ? "该结果对应本次采样，ACC 为固定整数分类器输出。" : "等待画面稳定后点击采样检测，或短按板上 KEY+。";
      secondary = s.accumulator; extra = s.points;
      detail = [["原始扫描点",s.scan_points],["筛选后点数",s.points],["扫描原因码",s.scan_reason],["数值核原因码",s.numeric_reason],["分类器原因码",s.classifier_reason],["检测结果",s.classification]];
    }
    detail.push(["相机状态",s.camera_ready ? "已就绪" : "未就绪"],["输入 / 处理尺寸",`${s.input_width}×${s.input_height} / ${s.processing_width}×${s.processing_height}`],["固件 / 协议",`V${s.firmware_major} / V${s.protocol_version}`]);
  }
  text("plate", value); $("plate").className = "result-value" + (s?.result_valid ? " valid" : "") + (s?.classification === "NG" ? " ng" : s?.classification === "INVALID" ? " invalid" : "");
  text("resultHint", hint); text("frameId", selected === 3 && data.sample_pending ? null : s?.result_id); text("secondaryValue", secondary); text("extraValue", selected === 3 && data.sample_pending ? null : extra);
  text("edgeActual", s?.edge_threshold); text("adjustActual", s?.char_offset);
  if (selected === 0) { metric(1,"相机输入",s?.input_fps,"fps");metric(2,"Canny 接受帧",s?.edge_fps,"fps");metric(3,"本帧欠载",s?.underflow_frame,"UND");metric(4,"累计欠载",s?.underflow_total,"TOT"); }
  if (selected === 1) { metric(1,"目标数量",s?.count,"个");metric(2,"已标注",s?.boxes,"个");metric(3,"阈值",s?.threshold);metric(4,"分析批次",s?.result_id); }
  if (selected === 3) { metric(1,"原始点数",s?.scan_points);metric(2,"筛选后点数",s?.points);metric(3,"采样编号",s?.result_id);metric(4,"数值核原因",s?.numeric_reason); }
  rows("diagnostics", detail.length ? detail : [["板端状态",same ? "等待数据" : "无当前模式数据"]]);
  rows("beanReadbacks",[["灰度阈值",selected === 1 ? s?.threshold : null],["目标极性",selected === 1 && s ? s.dark_target ? "深色目标" : "浅色目标" : null],["显示视图",selected === 1 && s ? ["RAW","BINARY","RESULT"][s.view] : null],["ROI",selected === 1 && s ? `${s.bbox.x},${s.bbox.y} / ${s.bbox.width}×${s.bbox.height}` : null]]);
  document.querySelector(".workspace").classList.toggle("stale", !same);
  text("freshness",same ? `${((data.status_age_ms || 0)/1000).toFixed(1)} 秒前更新` : "无当前模式有效数据");
  if (data.error) notice(data.error,true);
  else if (fresh && !same) notice(`当前板端为${modes[actual].name}；此页等待${mode.name}位流。`,true);
  else if (same) notice(`已识别${mode.name}位流 · 所有结果来自板端实际读回。`);
  else notice(data.connected ? "串口已打开，等待配套位流的有效状态；旧版豆子/零件固件需要更新。" : "连接开发板后，自动识别已加载位流并进入对应模式。");
  text("service","本地服务正常 · 无网络依赖");
}
async function waitReadback(field,value,task) {
  for(let i=0;i<10;i++) { await new Promise(r=>setTimeout(r,250));const d=await api("/api/state");if(!d.responding || d.status?.task!==task)throw new Error("等待读回时板端模式或连接已改变");if(d.status[field]===value)return; }
  throw new Error("参数尚未在板端生效");
}
async function control(name,value) {
  if(commandBusy || !latest?.responding || latest.status.task!==selected)return;
  const task=selected;commandBusy=true;render(latest);text("commandResult","正在发送，等待板端 ACK…");
  try {
    let result;
    if(name==="defaults") { await api("/api/command",{command:"edge",value:27});await waitReadback("edge_threshold",27,task);result=await api("/api/command",{command:"adjust",value:128});await waitReadback("char_adjust",128,task); }
    else result=await api("/api/command",{command:name,...(value===undefined?{}:{value})});
    text("commandResult",result.readback_error ? "板端已接收，读回失败："+result.readback_error : name==="defaults" ? "默认参数已读回：阈值 27、字符偏移 0。" : result.applied === true ? "板端 ACK 成功，实际状态已读回。" : "板端 ACK 成功，等待后续状态确认执行结果。");
    $("commandResult").className="command-result"+(result.readback_error?" error":"");
  } catch(e) { text("commandResult","控制未确认："+e.message);$("commandResult").className="command-result error"; }
  finally {commandBusy=false;await pollOnce();}
}
async function ports() {
  try { const old=$("ports").value,d=await api("/api/ports");$("ports").replaceChildren();for(const item of d.ports){const o=document.createElement("option");o.value=item.port;o.textContent=`${item.port} · ${item.description}`;$("ports").append(o);}if(!d.ports.length){const o=document.createElement("option");o.value="";o.textContent="未发现串口，请连接设备后刷新";$("ports").append(o);}else if(d.ports.some(p=>p.port===old))$("ports").value=old; }catch(e){notice(e.message,true);}
}
$("refresh").onclick=ports;
$("connect").onclick=async()=>{if(!$("ports").value)return notice("请选择开发板串口",true);try{render(await api("/api/connect",{port:$("ports").value}));}catch(e){notice(e.message,true);}};
$("disconnect").onclick=async()=>{try{render(await api("/api/disconnect",{}));}catch(e){notice(e.message,true);}};
document.querySelectorAll(".mode").forEach(b=>b.onclick=()=>selectMode(Number(b.dataset.task)));
$("followBoard").onclick=()=>{if(detected!==null)selectMode(detected);};
for(const [id,name,value] of [["rescan","rescan"],["run","run",1],["pause","run",0],["defaults","defaults"],["freezeBean","freeze",1],["resumeBean","freeze",0],["samplePart","sample"],["clearPart","clear"]])$(id).onclick=()=>control(name,value);
for(const [id,input,name,lo,hi,offset] of [["setEdge","edge","edge",0,1023,0],["setAdjust","adjust","adjust",-128,127,128]])$(id).onclick=()=>{const raw=$(input).value.trim(),v=Number(raw);if(!raw || !Number.isInteger(v) || v<lo || v>hi)return notice(`请输入 ${lo}～${hi} 的整数`,true);control(name,v+offset);};
async function pollOnce(){try{render(await api("/api/state"));}catch(e){render({connected:false,responding:false,status:null,error:"本地服务已断开，请重新运行启动程序"});text("service","本地服务不可用");}}
async function polling(){await pollOnce();setTimeout(polling,200);}
render({connected:false,responding:false,status:null});ports();polling();
