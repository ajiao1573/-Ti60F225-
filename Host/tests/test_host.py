"""Synthetic UART fixtures only: production never exposes a fake device."""
import json
from pathlib import Path
import struct
import sys
import threading
import time
import unittest
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "vendor"))
from protocol import Parser, encode, crc8, decode_status, command_payload
from controller import Controller, LinkError
from app import make_server


def status_payload(state=1, flags=129, plate=b"??????", edge=27, adjust=128):
    p = bytearray(48)
    p[0:8] = bytes((1, 0, state, flags, edge & 255, edge >> 8, adjust, 6))
    p[8:14] = plate
    p[14:16] = bytes((0, 1))
    for offset, value in [(16,101),(18,70),(20,260),(22,98),(24,30),(26,29),(28,0),(30,2),
                          (36,1920),(38,1080),(40,848),(42,477),(46,1)]:
        struct.pack_into("<H", p, offset, value)
    struct.pack_into("<I", p, 32, 0x12345678)
    p[44], p[45] = 109, 1
    return p


class FakeSerial:
    def __init__(self, port):
        self.port, self.is_open = port, True
        self.rx, self.parser = bytearray(), Parser()
        self.payload, self.requests = status_payload(), []
        self.silent = self.fail_read = self.wrong_seq = False
        self.ack_error = self.delay_apply = 0
        self.pending = None

    def reset_input_buffer(self): self.rx.clear()
    def close(self): self.is_open = False

    def write(self, raw):
        for seq, cmd, payload in self.parser.feed(raw):
            self.requests.append((seq, cmd, payload))
            if self.silent: continue
            if cmd == 1:
                if self.pending:
                    name, value, remaining = self.pending
                    if remaining <= 0:
                        self.apply(name, value); self.pending = None
                    else: self.pending = name, value, remaining - 1
                response = encode(seq, 0x81, self.payload)
            else:
                response = encode(seq, 0x80, bytes((cmd, self.ack_error)))
                if not self.ack_error:
                    if self.delay_apply: self.pending = cmd, payload, self.delay_apply
                    else: self.apply(cmd, payload)
            if self.wrong_seq: response = encode((seq + 1) & 255, response[4], response[6:-1])
            self.rx.extend(response)
        return len(raw)

    def apply(self, cmd, payload):
        if cmd == 0x10: self.payload[4:6] = payload
        elif cmd == 0x11: self.payload[6] = payload[0]
        elif cmd == 0x12:
            self.payload[2], self.payload[3] = 1, 129
            self.payload[8:14] = b"??????"
        elif cmd == 0x14:
            self.payload[2] = 1 if payload[0] else 6
            self.payload[3] = (self.payload[3] | 128) if payload[0] else (self.payload[3] & 127)

    def read(self, size):
        if self.fail_read: raise OSError("test unplug")
        n = min(3, size, len(self.rx))  # Deliberately fragment all replies.
        data = bytes(self.rx[:n]); del self.rx[:n]
        if not data: time.sleep(0.002)
        return data


def wait_until(predicate, timeout=1.5):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if predicate(): return
        time.sleep(0.005)
    raise AssertionError("condition did not become true")


class ProtocolTests(unittest.TestCase):
    def test_crc_standard_vector(self):
        self.assertEqual(crc8(b"123456789"), 0xF4)

    def test_all_fragment_sizes_and_coalesced_frames(self):
        expected = [(254,0x10,b"\xff\x03"),(255,0x12,b""),(0,0x81,bytes(status_payload()))]
        data = b"noise\xa5junk" + b"".join(encode(*p) for p in expected)
        for chunk in range(1,len(data)+1):
            parser, got = Parser(), []
            for pos in range(0,len(data),chunk): got.extend(parser.feed(data[pos:pos+chunk]))
            self.assertEqual(got,expected)

    def test_bad_crc_length_version_and_resync(self):
        bad = bytearray(encode(1,0x10,b"\xa5\x5a")); bad[-1] ^= 0x80
        parser = Parser()
        data = bad + b"\xa5\x5a\x01\x02\x81\xff" + b"\xa5\x5a\x02\x02\x81\x00\x00"
        self.assertEqual(parser.feed(data+encode(9,0x80,b"\x10\x00")),[(9,0x80,b"\x10\x00")])
        self.assertGreaterEqual(parser.bad_frames,3)

    def test_status_offsets_and_endianness(self):
        s = decode_status(status_payload(5,255,b"ABC123",1023,0))
        self.assertEqual(s["plate"],"ABC123")
        self.assertEqual(s["edge_threshold"],1023); self.assertEqual(s["char_offset"],-128)
        self.assertEqual(s["bbox"],{"x":101,"y":70,"width":260,"height":98})
        self.assertEqual(s["capture_frame_id"],0x12345678)
        self.assertEqual((s["input_width"],s["input_height"],s["processing_width"],s["processing_height"]),(1920,1080,848,477))
        self.assertEqual((s["underflow_total"],s["binary_threshold"],s["capabilities"]),(2,109,1))

    def test_invalid_ascii_or_flags_never_success(self):
        for state,flags,plate in [(5,255,b"??????"),(5,255,b"A1B2C3"),(5,255,b"\xffBC123"),
                                  (1,255,b"ABC123"),(5,223,b"ABC123")]:
            s=decode_status(status_payload(state,flags,plate))
            self.assertFalse(s["recognized"]); self.assertIsNone(s["plate"])
        self.assertEqual(decode_status(status_payload(5,255,b"AB1234"))["plate"],"AB1234")

    def test_incompatible_status_rejected(self):
        for offset in [0,45]:
            p=status_payload(); p[offset]=2
            with self.assertRaises(ValueError): decode_status(p)
        with self.assertRaises(ValueError): decode_status(b"x"*47)

    def test_all_command_boundaries(self):
        for name,lo,hi in [("edge",0,1023),("adjust",0,255),("run",0,1),("task",0,3),("freeze",0,1)]:
            for value in [lo,hi]: command_payload(name,value)
            for value in [lo-1,hi+1,"0",None,True,1.1]:
                with self.assertRaises(ValueError): command_payload(name,value)
        self.assertEqual(command_payload("edge",1023),(0x10,b"\xff\x03"))
        self.assertEqual(command_payload("rescan"),(0x12,b""))
        with self.assertRaises(ValueError): command_payload("rescan",0)
        with self.assertRaises(ValueError): command_payload("count",1)


class ControllerTests(unittest.TestCase):
    def setUp(self):
        def factory(port):
            self.fake=FakeSerial(port); return self.fake
        self.controller=Controller(factory,timeout=.08,poll_interval=.04,stale_after=.12)
        self.controller.connect("COM_TEST")
        wait_until(lambda:self.controller.snapshot()["responding"])

    def tearDown(self): self.controller.close()

    def test_delayed_readback_eventually_updates_last_command(self):
        self.fake.delay_apply = 3
        first = self.controller.command("adjust", 128 + 17)
        self.assertFalse(first["applied"])
        wait_until(lambda: self.controller.snapshot()["status"]["char_adjust"] == 145)
        command = self.controller.snapshot()["last_command"]
        self.assertTrue(command["applied"])
        self.assertEqual(command["readback"], 145)

    def test_open_port_is_not_reply(self):
        self.controller.disconnect()
        self.assertFalse(self.controller.snapshot()["responding"])
        # Hold the status worker so connect state can be observed without a race.
        self.controller.stop_event.set(); self.controller.thread.join()
        self.controller.connect("COM_TEST")
        s=self.controller.snapshot()
        self.assertTrue(s["connected"]); self.assertFalse(s["responding"])
        self.assertIsNone(s["status"])

    def test_controls_and_result_then_rescan(self):
        for command,value,expected in [("edge",333,333),("adjust",140,140),("run",0,False),("run",1,True)]:
            result=self.controller.command(command,value)
            self.assertTrue(result["acknowledged"]); self.assertTrue(result["applied"])
            self.assertEqual(result["readback"],expected)
        self.fake.payload=status_payload(5,255,b"AB1234")
        wait_until(lambda:self.controller.snapshot()["status"]["recognized"])
        self.assertEqual(self.controller.snapshot()["status"]["plate"],"AB1234")
        self.controller.command("rescan")
        self.assertFalse(self.controller.snapshot()["status"]["recognized"])

    def test_ack_is_not_applied(self):
        self.fake.delay_apply=3
        result=self.controller.command("edge",321)
        self.assertTrue(result["acknowledged"]); self.assertFalse(result["applied"])
        self.assertEqual(result["readback"],27)
        wait_until(lambda:self.controller.snapshot()["status"]["edge_threshold"]==321)

    def test_busy_wrong_sequence_and_no_automatic_retry(self):
        self.fake.ack_error=3
        with self.assertRaisesRegex(LinkError,"控制邮箱忙"): self.controller.command("rescan")
        self.assertEqual(sum(cmd==0x12 for _,cmd,_ in self.fake.requests),1)
        self.fake.ack_error=0; self.fake.wrong_seq=True
        with self.assertRaisesRegex(LinkError,"应答超时"): self.controller.command("edge",10)
        self.assertFalse(self.controller.snapshot()["last_command"]["acknowledged"])

    def test_stale_and_unplug_clear_success(self):
        self.fake.payload=status_payload(5,255,b"ABC123")
        wait_until(lambda:self.controller.snapshot()["status"]["recognized"])
        self.fake.silent=True
        wait_until(lambda:not self.controller.snapshot()["responding"])
        self.assertFalse(self.controller.snapshot()["status"]["recognized"])
        self.assertIsNone(self.controller.snapshot()["status"]["plate"])
        self.fake.fail_read=True
        wait_until(lambda:not self.controller.snapshot()["connected"])
        self.assertIsNone(self.controller.snapshot()["status"])

    def test_bad_crc_does_not_publish_then_recovery(self):
        self.fake.silent=True
        bad=bytearray(encode((self.controller.seq+1)&255,0x81,status_payload(5,255,b"ABC123"))); bad[-1]^=1
        self.fake.rx.extend(bad)
        wait_until(lambda:not self.controller.snapshot()["responding"])
        self.assertGreater(self.controller.snapshot()["crc_or_header_errors"],0)
        self.fake.silent=False
        wait_until(lambda:self.controller.snapshot()["responding"])
        self.assertFalse(self.controller.snapshot()["status"]["recognized"])

    def test_sequence_wrap(self):
        self.controller.seq=254
        result=self.controller.command("edge",1023)  # ACK seq255, readback seq0.
        self.assertTrue(result["applied"])
        self.assertIn(0,[seq for seq,_,_ in self.fake.requests])


class HttpTests(unittest.TestCase):
    def setUp(self):
        def factory(port): self.fake=FakeSerial(port); return self.fake
        self.controller=Controller(factory,timeout=.08,poll_interval=.04)
        self.server=make_server(self.controller,0,lambda:[{"port":"COM_TEST","description":"测试设备"}])
        self.thread=threading.Thread(target=self.server.serve_forever,kwargs={"poll_interval":.01},daemon=True)
        self.thread.start(); self.base=f"http://127.0.0.1:{self.server.server_port}"

    def tearDown(self):
        self.server.shutdown(); self.server.server_close(); self.thread.join(); self.controller.close()

    def request(self,path,data=None,headers=None):
        hdr={"Content-Type":"application/json"} if data is not None else {}; hdr.update(headers or {})
        req=urllib.request.Request(self.base+path,json.dumps(data).encode() if data is not None else None,headers=hdr)
        try:
            with urllib.request.urlopen(req,timeout=2) as response:
                raw=response.read()
                return response.status,json.loads(raw) if response.headers["Content-Type"].startswith("application/json") else raw.decode()
        except urllib.error.HTTPError as exc: return exc.code,json.loads(exc.read())

    def test_fake_uart_http_end_to_end(self):
        self.assertEqual(self.request("/api/ports")[1]["ports"][0]["port"],"COM_TEST")
        self.assertFalse(self.request("/api/state")[1]["connected"])
        self.assertEqual(self.request("/api/connect",{"port":"COM_TEST"})[0],200)
        wait_until(lambda:self.request("/api/state")[1]["responding"])
        code,result=self.request("/api/command",{"command":"adjust","value":133})
        self.assertEqual(code,200); self.assertTrue(result["applied"])
        self.assertEqual(self.request("/api/state")[1]["status"]["char_offset"],5)
        self.fake.payload=status_payload(5,255,b"ABC123")
        wait_until(lambda:self.request("/api/state")[1]["status"]["plate"]=="ABC123")
        self.assertEqual(self.request("/api/command",{"command":"rescan"})[0],200)
        self.assertIsNone(self.request("/api/state")[1]["status"]["plate"])
        self.assertFalse(self.request("/api/disconnect",{})[1]["connected"])
        self.assertEqual(self.request("/api/command",{"command":"edge","value":27})[0],502)

    def test_invalid_commands_and_cross_origin_never_reach_serial(self):
        self.request("/api/connect",{"port":"COM_TEST"})
        for request in [{"command":"task","value":1},{"command":"run","value":True},{"command":"edge","value":1024},
                        {"command":"adjust","value":-1},{"command":"rescan","value":7},{"command":"fake"}]:
            self.assertEqual(self.request("/api/command",request)[0],400)
        self.assertEqual(self.request("/api/command",{"command":"rescan"},{"Origin":"https://example.com"})[0],403)
        self.assertEqual(self.request("/api/state",headers={"Host":"other.example"})[0],403)
        self.assertFalse(any(cmd!=1 for _,cmd,_ in self.fake.requests))

    def test_offline_ui_no_demo(self):
        status,html=self.request("/")
        self.assertEqual(status,200); self.assertIn('lang="zh-CN"',html)
        self.assertEqual(html.count('data-task='),3)
        for asset in ["/","/app.js","/style.css"]:
            text=self.request(asset)[1]
            self.assertNotIn("cdn.",text); self.assertNotIn("https://",text)
        self.assertEqual(self.request("/api/demo",{})[0],404)


if __name__=="__main__": unittest.main(verbosity=2)
