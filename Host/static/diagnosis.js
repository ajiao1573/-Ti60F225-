"use strict";
// Interpret board telemetry without promoting rejected ASCII to a result.
function recognitionDiagnosis(s, fresh) {
  if (!fresh || !s) return {label:"等待识别", hint:"等待开发板返回有效状态；不显示历史号码为当前结果"};
  if (!s.camera_ready) return {label:"相机未就绪", hint:"检查摄像头连接、初始化及输入尺寸，当前没有可供识别的有效画面。"};
  if (s.recognized) return {label:s.plate, hint:"板端识别有效 · 号码已锁定"};
  if (s.state === 6) return {label:"识别已暂停", hint:"点击启动识别继续。"};
  if (s.state === 3 || s.state === 4) return {label:"正在识别", hint:"已定位候选区域，正在抓帧、分割字符或等待图像提交。"};
  if (s.reject_reason) {
    const hints = {
      1:"牌面与字符对比度不足；避免手机反光、过曝和失焦。",
      2:"分出了过多区域；检查候选框是否包含手机界面、边框或背景文字。",
      3:`最近一次只分出 ${s.characters} 个字符，需要 6 个。检查候选框是否覆盖完整车牌；手机图片建议先占画面宽度的 30%～50%，完整居中。`,
      4:"字符高度、排列或黑字白底条件未通过；保持车牌正视、完整入镜。",
      5:"字符已进入模板匹配，但置信度未通过；请改善清晰度，当前不会将候选号码当作成功结果。"
    };
    return {label:s.reject_name || "识别未通过", hint:`最近抓帧 ${s.capture_frame_id}：${hints[s.reject_reason] || s.reject_name} 正在继续搜索。`};
  }
  if (s.location_reason === 2) return {label:"候选区域过小", hint:"适当放大完整车牌，避免字符像素不足。"};
  if (s.bbox_valid) return {label:"已发现候选", hint:"已找到候选区域，等待后续帧抓取；候选框不代表识别成功。"};
  return {label:"尚未定位车牌", hint:"尚未找到符合条件的候选区域。请完整居中展示车牌，避免手机边框或其他文字占据画面。"};
}
if (typeof module !== "undefined") module.exports = {recognitionDiagnosis};
