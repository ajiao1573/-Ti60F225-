"""Bounded live rescans; require a new capture ID so stale locks never count."""
import argparse,json,time,urllib.request
from pathlib import Path

def request(server,path,data=None):
    body=None if data is None else json.dumps(data).encode()
    req=urllib.request.Request(server+path,data=body,headers={'Content-Type':'application/json'})
    with urllib.request.urlopen(req,timeout=3) as response:return json.load(response)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output',type=Path)
    parser.add_argument('--expected',required=True)
    parser.add_argument('--server',default='http://127.0.0.1:8765')
    parser.add_argument('--trials',type=int,default=5)
    parser.add_argument('--timeout',type=float,default=4)
    args=parser.parse_args()
    results=[]
    for index in range(args.trials):
        before=request(args.server,'/api/state')
        if not(before['connected'] and before['responding']):raise RuntimeError('board is not responding')
        previous=before['status']['capture_frame_id']
        start=time.monotonic()
        request(args.server,'/api/command',{'command':'rescan'})
        samples=[];accepted=None
        while time.monotonic()-start<args.timeout:
            data=request(args.server,'/api/state');status=data.get('status')
            if data.get('responding') and status:
                sample=dict(seconds=round(time.monotonic()-start,3),**status)
                samples.append(sample)
                if status['recognized'] and status['capture_frame_id']!=previous:
                    accepted=sample;break
            time.sleep(.1)
        row=dict(trial=index+1,recognized=accepted is not None,
                 plate=accepted['plate'] if accepted else None,
                 correct=accepted is not None and accepted['plate']==args.expected,
                 seconds=accepted['seconds'] if accepted else None,samples=samples)
        results.append(row)
        print(json.dumps({k:v for k,v in row.items() if k!='samples'}),flush=True)
    report=dict(expected=args.expected,trials=results,
                correct=sum(r['correct'] for r in results),recognized=sum(r['recognized'] for r in results),
                note='One user-held phone image; not road accuracy. Host polling bounds timing precision.')
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

if __name__=='__main__':main()
