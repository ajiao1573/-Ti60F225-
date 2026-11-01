"""UART V1 codec. See ../docs/UART_PROTOCOL.md; no hardware dependencies."""
import re
import struct

VERSION = 1
MAX_PAYLOAD = 48
GET_STATUS, ACK, STATUS = 0x01, 0x80, 0x81
COMMANDS = {"edge": 0x10, "adjust": 0x11, "rescan": 0x12,
            "task": 0x13, "run": 0x14, "freeze": 0x20, "sample": 0x21, "clear": 0x22}
TASKS = {0: "车牌识别", 1: "豆子计数", 3: "零件检测"}
TASK_COMMANDS = {0: {"edge", "adjust", "rescan", "run", "task"},
                 1: {"freeze", "task"}, 3: {"sample", "clear", "task"}}
ERRORS = {1: "载荷或参数错误", 2: "固件不支持此功能", 3: "控制邮箱忙，请稍后再试"}
STATES = {0: "相机未就绪", 1: "搜索车牌", 2: "发现候选", 3: "抓取图像",
          4: "识别中", 5: "已锁定", 6: "已暂停"}
REJECTS = {0: "无", 1: "对比度不足", 2: "字符数量溢出", 3: "未分出六个字符",
           4: "字符排列不合格", 5: "字符识别未通过"}
LOCATIONS = {0: "无候选", 1: "候选有效", 2: "候选框过小", 3: "失败框冷却中"}


def crc8(data):
    crc = 0
    for value in data:
        crc ^= value
        for _ in range(8):
            crc = ((crc << 1) ^ (0x07 if crc & 0x80 else 0)) & 255
    return crc


def encode(seq, command, payload=b""):
    payload = bytes(payload)
    if len(payload) > MAX_PAYLOAD:
        raise ValueError("载荷超过48字节")
    body = bytes((VERSION, seq & 255, command, len(payload))) + payload
    return b"\xa5\x5a" + body + bytes((crc8(body),))


class Parser:
    """Incremental decoder, resynchronizing after noise, bad CRC or headers."""
    def __init__(self):
        self.buffer = bytearray()
        self.bad_frames = 0

    def feed(self, data):
        self.buffer.extend(data)
        packets = []
        while len(self.buffer) >= 2:
            start = self.buffer.find(b"\xa5\x5a")
            if start < 0:
                self.buffer[:] = self.buffer[-1:] if self.buffer[-1] == 0xa5 else b""
                break
            del self.buffer[:start]
            if len(self.buffer) < 6:
                break
            length = self.buffer[5]
            if self.buffer[2] != VERSION or length > MAX_PAYLOAD:
                self.bad_frames += 1
                del self.buffer[0]
                continue
            size = 7 + length
            if len(self.buffer) < size:
                break
            packet = self.buffer[:size]
            if crc8(packet[2:-1]) != packet[-1]:
                self.bad_frames += 1
                del self.buffer[0]
                continue
            packets.append((packet[3], packet[4], bytes(packet[6:-1])))
            del self.buffer[:size]
        return packets


def command_payload(name, value=None):
    if name not in COMMANDS:
        raise ValueError("不支持的控制命令")
    if name in ("rescan", "sample", "clear"):
        if value is not None:
            raise ValueError("该命令不接受参数")
        return COMMANDS[name], b""
    if type(value) is not int:
        raise ValueError("参数必须为整数")
    limits = {"edge": (0, 1023), "adjust": (0, 255), "run": (0, 1), "task": (0, 3), "freeze": (0, 1)}
    lo, hi = limits[name]
    if not lo <= value <= hi or (name == "task" and value not in TASKS):
        raise ValueError("不支持的任务" if name == "task" else f"参数范围：{lo}～{hi}")
    return COMMANDS[name], struct.pack("<H", value) if name == "edge" else bytes((value,))


def decode_status(payload):
    if len(payload) != 48:
        raise ValueError("状态包长度错误")
    if payload[0] != 1 or payload[45] != VERSION:
        raise ValueError("固件或协议版本不兼容")
    if payload[1] not in TASKS:
        raise ValueError("未知板端模式，不能显示为有效结果")
    if payload[1] != 0:
        return decode_measurement(payload)
    u16 = lambda offset: struct.unpack_from("<H", payload, offset)[0]
    flags = payload[3]
    raw_ascii = payload[8:14].decode("ascii", errors="replace")
    format_ok = re.fullmatch(r"(?:[A-Z]{3}[0-9]{3}|[A-Z]{2}[0-9]{4})", raw_ascii) is not None
    recognized = bool(flags & 32) and payload[2] == 5 and format_ok
    return {
        "firmware_major": payload[0], "protocol_version": payload[45], "task": payload[1], "task_name": TASKS[0],
        "result_valid": recognized, "result_id": struct.unpack_from("<I", payload, 32)[0],
        "state": payload[2], "state_name": STATES.get(payload[2], "未知状态"),
        "camera_ready": bool(flags & 1), "bbox_valid": bool(flags & 2),
        "roi_ready": bool(flags & 4), "low_contrast": bool(flags & 8),
        "overflow": bool(flags & 16), "ocr_valid": bool(flags & 32),
        "frozen": bool(flags & 64), "running": bool(flags & 128),
        "edge_threshold": u16(4), "char_adjust": payload[6], "char_offset": payload[6] - 128,
        "characters": payload[7], "ascii_diagnostic": raw_ascii,
        "recognized": recognized, "plate": raw_ascii if recognized else None,
        "reject_reason": payload[14], "reject_name": REJECTS.get(payload[14], "未知拒绝原因"),
        "location_reason": payload[15], "location_name": LOCATIONS.get(payload[15], "未知定位状态"),
        "bbox": {"x": u16(16), "y": u16(18), "width": u16(20), "height": u16(22)},
        "input_fps": u16(24), "edge_fps": u16(26),
        "underflow_frame": u16(28), "underflow_total": u16(30),
        "capture_frame_id": struct.unpack_from("<I", payload, 32)[0],
        "input_width": u16(36), "input_height": u16(38),
        "processing_width": u16(40), "processing_height": u16(42),
        "binary_threshold": payload[44], "capabilities": u16(46),
    }


def decode_measurement(p):
    u16 = lambda i: struct.unpack_from("<H", p, i)[0]
    task, flags = p[1], p[3]
    capability = 1 << task
    if not u16(46) & capability:
        raise ValueError("板端模式与功能位图不一致")
    ready, error = bool(flags & 1), bool(flags & 16)
    states = ({0: "相机未就绪", 1: "实时计数", 2: "分析中", 3: "已冻结", 4: "采集异常"} if task == 1 else
              {0: "相机未就绪", 1: "等待采样", 2: "检测中", 3: "OK", 4: "NG", 5: "INVALID"})
    valid = ready and not error and bool(flags & 32)
    valid = valid and (p[2] in (1, 2, 3) if task == 1 else p[2] in (3, 4, 5))
    s = {"task": task, "task_name": TASKS[task], "firmware_major": p[0], "protocol_version": p[45],
         "capabilities": u16(46), "state": p[2], "state_name": states.get(p[2], "未知状态"),
         "camera_ready": ready, "overflow": error, "result_valid": valid,
         "recognized": False, "plate": None, "frozen": bool(flags & 64), "running": bool(flags & 128),
         "result_id": struct.unpack_from("<I", p, 32)[0], "capture_frame_id": struct.unpack_from("<I", p, 32)[0],
         "input_width": u16(36), "input_height": u16(38), "processing_width": u16(40), "processing_height": u16(42),
         "input_fps": u16(24) if p[44] & 1 else None, "edge_fps": u16(26) if p[44] & 2 else None,
         "underflow_frame": u16(28) if p[44] & 4 else None, "underflow_total": u16(30) if p[44] & 4 else None,
         "threshold": u16(4), "detail_reason": p[7],
         "bbox": {"x": u16(16), "y": u16(18), "width": u16(20), "height": u16(22)}}
    if task == 1:
        s.update(count=u16(8) if valid else None, boxes=u16(10) if valid else None,
                 view=p[6] & 3, dark_target=bool(p[6] & 4), menu=bool(p[15]), error_status=p[14])
    else:
        names = {3: "OK", 4: "NG", 5: "INVALID"}
        s.update(classification=names.get(p[2]) if valid else None,
                 accumulator=struct.unpack_from("<i", p, 8)[0] if valid and p[2] in (3, 4) else None,
                 points=u16(12), scan_points=u16(30), scan_reason=p[14], numeric_reason=p[28], classifier_reason=p[7])
    return s
