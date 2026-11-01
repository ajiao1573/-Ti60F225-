"""Browser regression fixture, NOT a production service or hardware result."""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_host import FakeSerial, status_payload
from test_multimode import MultiSerial, measurement
from app import make_server
from controller import Controller

board = None
def factory(port):
    global board
    board = MultiSerial(port)
    board.delay_apply = 3
    return board

controller = Controller(factory, timeout=.08, poll_interval=.2, stale_after=.3)
server = make_server(controller,0,lambda:[{"port":"COM_TEST_ONLY","description":"自动化测试假串口，无开发板"}])
base_handler = server.RequestHandlerClass
class TestHandler(base_handler):
    def do_POST(self):
        if self.path == "/__test/board":
            data=json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            if data.get("silent") is not None: board.silent=data["silent"]
            if data.get("plate") is not None: board.payload=status_payload(5,255,data["plate"].encode("ascii"))
            if data.get("task") in (1,3):
                board.payload=measurement(task=data['task'],state=data.get('state',3),count=data.get('count',12),acc=data.get('acc',-5325003),kind=data.get('kind',0),result_id=data.get('result_id',7))
            return self.send(200,{"test_fixture":True})
        super().do_POST()
server.RequestHandlerClass=TestHandler
print(f"http://127.0.0.1:{server.server_port}/",flush=True)
try: server.serve_forever(poll_interval=.05)
finally: server.server_close(); controller.close()
