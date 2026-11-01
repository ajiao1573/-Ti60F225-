"""One serial owner; commands and 5 Hz status requests never interleave."""
import copy
import threading
import time

from protocol import ACK, STATUS, GET_STATUS, ERRORS, TASK_COMMANDS, Parser, encode, decode_status, command_payload


class LinkError(Exception):
    pass


def open_serial(port):
    import serial
    device = serial.Serial(port=None, baudrate=115200, bytesize=8, parity="N", stopbits=1,
                           timeout=0.03, write_timeout=0.4, rtscts=False, dsrdtr=False)
    device.dtr = False
    device.rts = False
    device.port = port
    device.open()
    return device


def serial_ports():
    from serial.tools import list_ports
    return [{"port": p.device, "description": p.description} for p in list_ports.comports()]


class Controller:
    def __init__(self, factory=open_serial, timeout=0.55, poll_interval=0.2, stale_after=1.2):
        self.factory, self.timeout, self.poll_interval, self.stale_after = factory, timeout, poll_interval, stale_after
        self.io_lock = threading.Lock()
        self.lock = threading.Lock()
        self.stop_event = threading.Event()
        self.device = None
        self.parser = Parser()
        self.seq = 0
        self.port = None
        self.status = None
        self.last_status = 0.0
        self.last_error = ""
        self.last_command = None
        self.connected = False
        self.sample_pending_id = None
        self.thread = threading.Thread(target=self._poll, daemon=True, name="serial-status")
        self.thread.start()

    def snapshot(self):
        with self.lock:
            age = time.monotonic() - self.last_status if self.last_status else None
            fresh = self.connected and age is not None and age < self.stale_after
            status = copy.deepcopy(self.status)
            pending = self.sample_pending_id is not None
            if status and pending and status["task"] == 3:
                status.update(result_valid=False, classification=None, accumulator=None)
            # Last received telemetry may be displayed as stale, never as current success.
            if status and not fresh:
                status["recognized"] = False
                status["plate"] = None
                status["result_valid"] = False
                for field in ("count", "boxes", "classification", "accumulator"):
                    if field in status: status[field] = None
            return {"connected": self.connected, "responding": bool(fresh), "port": self.port,
                    "status_age_ms": round(age * 1000) if age is not None else None,
                    "status": status, "error": self.last_error, "last_command": copy.deepcopy(self.last_command),
                    "crc_or_header_errors": self.parser.bad_frames, "baudrate": 115200, "sample_pending": pending}

    def connect(self, port):
        if not isinstance(port, str) or not port.strip() or len(port) > 128:
            raise ValueError("请选择串口")
        with self.io_lock:
            self._disconnect()
            try:
                self.device = self.factory(port.strip())
                self.device.reset_input_buffer()
            except Exception as exc:
                self._disconnect()
                with self.lock:
                    self.last_error = f"无法打开串口：{exc}"
                raise LinkError(self.last_error) from exc
            self.parser = Parser()
            with self.lock:
                self.port, self.connected = port.strip(), True
                self.status, self.last_status, self.last_error, self.last_command = None, 0, "", None
        return self.snapshot()

    def _disconnect(self):
        if self.device is not None:
            try:
                self.device.close()
            except Exception:
                pass
        self.device = None
        with self.lock:
            self.connected = False
            self.sample_pending_id = None
            self.status, self.last_status = None, 0

    def disconnect(self):
        with self.io_lock:
            self._disconnect()
            with self.lock:
                self.port, self.last_error, self.last_command = None, "", None
        return self.snapshot()

    def _exchange(self, command, payload, reply):
        if self.device is None:
            raise LinkError("尚未连接串口")
        self.seq = (self.seq + 1) & 255
        seq = self.seq
        packet = encode(seq, command, payload)
        try:
            if self.device.write(packet) != len(packet):
                raise OSError("串口未完整发送命令")
            deadline = time.monotonic() + self.timeout
            while time.monotonic() < deadline:
                for rx_seq, rx_cmd, body in self.parser.feed(self.device.read(128)):
                    if rx_seq == seq and rx_cmd == reply:
                        return body
        except Exception as exc:
            self._disconnect()
            raise LinkError(f"串口读写失败：{exc}") from exc
        raise LinkError("板端应答超时；请检查位流、串口和接线")

    def _get_status(self):
        status = decode_status(self._exchange(GET_STATUS, b"", STATUS))
        with self.lock:
            if self.status and self.status["task"] != status["task"]:
                self.last_command = None
                self.sample_pending_id = None
            if (self.sample_pending_id is not None and status["task"] == 3
                    and status["result_id"] != self.sample_pending_id and status["state"] != 2):
                self.sample_pending_id = None
            self.status, self.last_status, self.last_error = status, time.monotonic(), ""
            # ACK can precede the camera frame boundary. Reconcile on every
            # subsequent poll, not just the first (usually premature) readback.
            command = self.last_command
            if command and command.get("acknowledged"):
                field = {"edge": "edge_threshold", "adjust": "char_adjust",
                         "run": "running", "task": "task", "freeze": "frozen"}.get(command["command"])
                if field:
                    command["readback"] = status[field]
                    command["applied"] = status[field] == command["requested"]
                    command.pop("readback_error", None)
        return status

    def command(self, name, value=None):
        code, payload = command_payload(name, value)
        with self.io_lock:
            try:
                # Re-read identity before every action, including after a JTAG reload.
                # The status worker and commands share this lock.
                status = self._get_status()
                if name not in TASK_COMMANDS[status["task"]]:
                    raise ValueError("当前位流不支持该模式的操作，请加载对应位流")
                if name == "task" and value != status["task"]:
                    raise ValueError("独立位流不能通过串口切换，请加载对应位流；网页会自动识别")
                if name == "sample" and (self.sample_pending_id is not None or status["state"] == 2):
                    raise ValueError("上一次采样尚未完成，请等待结果或先清除 / 取消")
                if name == "sample" and not status["camera_ready"]:
                    raise ValueError("相机未就绪，暂不能采样")
                ack = self._exchange(code, payload, ACK)
                if len(ack) != 2 or ack[0] != code:
                    raise LinkError("板端ACK载荷错误")
                if ack[1]:
                    raise LinkError(ERRORS.get(ack[1], f"板端错误码{ack[1]}"))
                with self.lock:
                    if name == "sample": self.sample_pending_id = status["result_id"]
                    elif name == "clear": self.sample_pending_id = None
                result = {"command": name, "requested": value, "acknowledged": True,
                          "message": "板端已接收；实际参数以状态读回为准"}
                with self.lock:
                    self.last_command = result.copy()
                # A successful ACK is not an application-at-frame-boundary guarantee.
                try:
                    status = self._get_status()
                    field = {"edge": "edge_threshold", "adjust": "char_adjust", "run": "running", "task": "task", "freeze": "frozen"}.get(name)
                    result["readback"] = status.get(field) if field else None
                    result["applied"] = (status.get(field) == value) if field else None
                except (LinkError, ValueError) as exc:
                    result["readback"], result["applied"] = None, None
                    result["readback_error"] = str(exc)
                    with self.lock:
                        self.last_error = str(exc)
                with self.lock:
                    self.last_command = result.copy()
                return result
            except (LinkError, ValueError) as exc:
                with self.lock:
                    self.last_error = str(exc)
                    self.last_command = {"command": name, "requested": value, "acknowledged": False, "message": str(exc)}
                raise

    def _poll(self):
        while not self.stop_event.is_set():
            start = time.monotonic()
            with self.io_lock:
                if self.device is not None:
                    try:
                        self._get_status()
                    except (LinkError, ValueError) as exc:
                        with self.lock:
                            self.last_error = str(exc)
            self.stop_event.wait(max(0.01, self.poll_interval - (time.monotonic() - start)))

    def close(self):
        self.stop_event.set()
        self.thread.join(timeout=self.timeout + 0.5)
        self.disconnect()
