"""Independent wire-format and real Controller/HTTP tests for the three tasks."""
import struct
import time
import unittest
from test_host import status_payload, FakeSerial, wait_until
from protocol import decode_status, command_payload
from controller import Controller

def measurement(task=1, state=3, valid=True, count=12, acc=-5325003, kind=0, result_id=7):
    p=bytearray(48)
    p[:8]=bytes([1,task,state,1|128|(32 if valid else 0)|(64 if task==1 else 0),112 if task==1 else 27,0,6 if task==1 else 3,0])
    if task==1:
        struct.pack_into('<HH',p,8,count,min(count,128))
    else:
        struct.pack_into('<iH',p,8,acc,245);p[15]=kind
        struct.pack_into('<H',p,30,318)
    for off,value in [(16,96),(18,72),(20,1728),(22,936),(36,1920 if task==1 else 960),(38,1080 if task==1 else 720),(40,960),(42,540 if task==1 else 720),(46,1<<task)]:struct.pack_into('<H',p,off,value)
    struct.pack_into('<I',p,32,result_id);p[45]=1
    return p

class MultiProtocolTests(unittest.TestCase):
    def test_zero_large_count_and_unknown_metrics(self):
        for count in (0,128,129,65535):
            s=decode_status(measurement(count=count))
            self.assertEqual(s['count'],count);self.assertEqual(s['boxes'],min(count,128))
            self.assertIsNone(s['input_fps']);self.assertIsNone(s['underflow_frame'])
            self.assertFalse(s['recognized']);self.assertIsNone(s['plate'])
    def test_parts_signed_accumulator_and_invalid(self):
        for state,kind,acc,label in [(3,0,-5325003,'OK'),(4,1,0,'NG'),(4,1,17086369,'NG'),(5,2,-999,'INVALID')]:
            s=decode_status(measurement(3,state,acc=acc,kind=kind))
            self.assertEqual(s['classification'],label)
            self.assertEqual(s['accumulator'],acc if state!=5 else None)
            self.assertEqual((s['points'],s['scan_points']),(245,318))
    def test_not_ready_error_and_busy_never_publish_old_part_result(self):
        for state,flags in [(0,32),(2,161),(3,177),(3,128)]:
            p=measurement(3,state);p[3]=flags
            s=decode_status(p);self.assertFalse(s['result_valid']);self.assertIsNone(s['accumulator']);self.assertIsNone(s['classification'])
        p=measurement();p[3]|=16
        self.assertIsNone(decode_status(p)['count'])
    def test_wrong_identity_and_capabilities_rejected(self):
        for task in (2,4,255):
            p=measurement();p[1]=task
            with self.assertRaises(ValueError):decode_status(p)
        p=measurement();p[46]=1
        with self.assertRaises(ValueError):decode_status(p)
    def test_commands(self):
        self.assertEqual(command_payload('freeze',1),(0x20,b'\x01'))
        self.assertEqual(command_payload('sample'),(0x21,b''))
        self.assertEqual(command_payload('clear'),(0x22,b''))
        for name,val in [('task',2),('freeze',2),('sample',0),('clear',False)]:
            with self.assertRaises(ValueError):command_payload(name,val)

class MultiSerial(FakeSerial):
    def apply(self,cmd,payload):
        if self.payload[1]==0:return super().apply(cmd,payload)
        if cmd==0x20:
            self.payload[3]=(self.payload[3]|64) if payload[0] else (self.payload[3]&~64)
            self.payload[2]=3 if payload[0] else 1
        elif cmd==0x21:self.payload[2]=2;self.payload[3]&=~32
        elif cmd==0x22:self.payload[2]=1;self.payload[3]&=~32

class MultiControllerTests(unittest.TestCase):
    def setUp(self):
        def factory(port):self.fake=MultiSerial(port);return self.fake
        self.c=Controller(factory,timeout=.06,poll_interval=.02,stale_after=.1)
        self.c.connect('TEST');wait_until(lambda:self.c.snapshot()['responding'])
    def tearDown(self):self.c.close()
    def switch(self,payload):
        self.fake.payload=payload
        wait_until(lambda:self.c.snapshot()['status']['task']==payload[1])
    def test_firmware_change_clears_previous_command_and_results(self):
        self.c.command('edge',44)
        self.switch(measurement())
        s=self.c.snapshot();self.assertIsNone(s['last_command']);self.assertEqual(s['status']['count'],12);self.assertIsNone(s['status']['plate'])
        self.assertTrue(self.c.command('freeze',0)['applied'])
        self.switch(measurement(3,3))
        self.assertEqual(self.c.snapshot()['status']['classification'],'OK')
        self.c.command('sample');self.assertFalse(self.c.snapshot()['status']['result_valid'])
        self.c.command('clear');self.assertEqual(self.c.snapshot()['status']['state'],1)
    def test_cross_mode_commands_do_not_reach_uart(self):
        self.switch(measurement())
        for name,val in [('edge',27),('sample',None),('task',3)]:
            before=len(self.fake.requests)
            with self.assertRaises(ValueError):self.c.command(name,val)
            self.assertTrue(all(cmd==1 for _,cmd,_ in self.fake.requests[before:]))
    def test_identity_preflight_protects_switch_before_next_poll(self):
        self.fake.payload=measurement(3,3)
        before=len(self.fake.requests)
        with self.assertRaises(ValueError):self.c.command('edge',27)
        self.assertTrue(all(cmd==1 for _,cmd,_ in self.fake.requests[before:]))
    def test_disconnect_or_stale_clears_count_and_classification(self):
        for p,field in [(measurement(),'count'),(measurement(3,3),'classification')]:
            self.switch(p);self.fake.silent=True
            wait_until(lambda:not self.c.snapshot()['responding'])
            self.assertIsNone(self.c.snapshot()['status'][field]);self.assertFalse(self.c.snapshot()['status']['result_valid'])
            self.fake.silent=False;wait_until(lambda:self.c.snapshot()['responding'])
    def test_sample_ack_with_delayed_snapshot_cannot_duplicate_or_show_old_result(self):
        self.switch(measurement(3,3,result_id=7))
        self.fake.delay_apply=5
        self.c.command('sample')
        s=self.c.snapshot();self.assertTrue(s['sample_pending']);self.assertIsNone(s['status']['classification'])
        before=len(self.fake.requests)
        with self.assertRaises(ValueError):self.c.command('sample')
        self.assertTrue(all(cmd==1 for _,cmd,_ in self.fake.requests[before:]))
        self.fake.pending=None;self.fake.payload=measurement(3,4,kind=1,result_id=8)
        wait_until(lambda:not self.c.snapshot()['sample_pending'])
        self.assertEqual(self.c.snapshot()['status']['classification'],'NG')

if __name__=='__main__':unittest.main()
