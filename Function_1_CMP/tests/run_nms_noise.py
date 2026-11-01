"""Both RTL paths checked against independent models; measure temporal flicker."""
from pathlib import Path
import ast,random,json
from run_canny import simulate,write_hex,RTL,local_link,OUT
source=ast.parse(Path('tests/run_sobel_noise.py').read_text())
context={'local_link':local_link}
exec(compile(ast.Module(body=[n for n in source.body if isinstance(n,ast.FunctionDef) and n.name=='oracle'],type_ignores=[]),'oracle','exec'),context)
oracle=context['oracle']
w,h=64,48;n=w*h;rng=random.Random(8819)
fixtures=[]
for scene in ('flat','step'):
 for frame in range(24):
  image=[max(0,min(255,(128 if scene=='flat' else 80 if x<w//2 else 180)+rng.randint(-40,40))) for y in range(h) for x in range(w)]
  fixtures.append((scene,image))
inputs=[];old=[];new=[];old_classes=[];new_classes=[];modes=[];report={}
for mode in (2,3):
 for scene,image in fixtures:
  _,oe,oc=oracle(image,w,h,mode,72,True,False)
  _,ne,nc=oracle(image,w,h,mode,72,True,True)
  modes.append(mode);inputs+=image;old+=oe;new+=ne;old_classes+=oc;new_classes+=nc
 for scene in ('flat','step'):
  f=[i for i,(kind,_) in enumerate(fixtures) if kind==scene]
  offset=(mode-2)*len(fixtures)
  before=[old[(offset+i)*n:(offset+i+1)*n] for i in f]
  after=[new[(offset+i)*n:(offset+i+1)*n] for i in f]
  bg=[y*w+x for y in range(5,h-5) for x in range(5,w-5) if scene=='flat' or abs(x-w//2)>5]
  def stats(fs):return dict(false_edges=sum(bool(im[i]) for im in fs for i in bg),flicker=sum(a[i]!=b[i] for a,b in zip(fs,fs[1:]) for i in bg),edge_rows=sum(any(im[y*w+x] for x in range(w//2-3,w//2+4)) for im in fs for y in range(5,h-5)))
  a,b=stats(before),stats(after)
  assert b['flicker']<a['flicker'] and b['false_edges']<a['false_edges'],(mode,scene,a,b)
  if scene=='step':assert b['edge_rows']==24*(h-10),(mode,a,b)
  report[f'{mode}_{scene}']={'before':a,'after':b,'flicker_reduction_percent':round((1-b['flicker']/a['flicker'])*100,2)}
ip=write_hex('nms_noise_input',inputs);op=write_hex('nms_noise_before',old);np=write_hex('nms_noise_after',new)
ocp=write_hex('nms_noise_old_classes',old_classes);ncp=write_hex('nms_noise_new_classes',new_classes)
tb=f"""
module tb;
 reg clk=0;always #5 clk=~clk;reg rst=0,v=0,s=0,e=0;reg [7:0] data=0;reg [1:0] mode=2;
 wire bv,av,bs,asop,be,ae,bb,ab,bgv,agv;wire [7:0] bd,ad;
 canny_frame #(.WIDTH({w}),.HEIGHT({h}),.RUNTIME_MODES(1),.SOBEL_MAX_ENABLE(1),.ROBUST_NMS(0)) baseline(
 .clk(clk),.rst_n(rst),.capture_ready(1'b1),.in_valid(v),.in_sop(s),.in_eop(e),.in_data(data),.threshold(10'd72),.algorithm(mode),
 .busy(bb),.gray_valid(bgv),.edge_valid(bv),.edge_sop(bs),.edge_eop(be),.edge_data(bd));
 canny_frame #(.WIDTH({w}),.HEIGHT({h}),.RUNTIME_MODES(1),.SOBEL_MAX_ENABLE(1),.ROBUST_NMS(1)) enhanced(
 .clk(clk),.rst_n(rst),.capture_ready(1'b1),.in_valid(v),.in_sop(s),.in_eop(e),.in_data(data),.threshold(10'd72),.algorithm(mode),
 .busy(ab),.gray_valid(agv),.edge_valid(av),.edge_sop(asop),.edge_eop(ae),.edge_data(ad));
 reg [7:0] input_mem[0:{len(inputs)-1}],old_mem[0:{len(old)-1}],new_mem[0:{len(new)-1}];
 reg [1:0] old_class[0:{len(old_classes)-1}],new_class[0:{len(new_classes)-1}];
 integer f,i,ec=0,gc=0,ticks=0;
 always @(posedge clk) if(rst) begin
  ticks=ticks+1;if(ticks>{len(inputs)*3}) $fatal(1,"timeout");
  if(bv!==av || bgv!==agv || bb!==ab || bs!==asop || be!==ae) $fatal(1,"NMS changed stream timing");
  if(bgv) begin
   if(baseline.classification!==old_class[gc] || enhanced.classification!==new_class[gc]) $fatal(1,"classification mismatch %0d",gc);
   gc=gc+1;
  end
  if(av) begin
   if(bd!==old_mem[ec] || ad!==new_mem[ec]) $fatal(1,"NMS edge mismatch %0d",ec);
   ec=ec+1;
  end
 end
 initial begin
  $readmemh("{ip}",input_mem);$readmemh("{op}",old_mem);$readmemh("{np}",new_mem);
  $readmemh("{ocp}",old_class);$readmemh("{ncp}",new_class);
  repeat(8) @(negedge clk);rst=1;
  for(f=0;f<{len(modes)};f=f+1) begin
   wait(!ab);mode=f<{len(fixtures)} ? 2 : 3;
   for(i=0;i<{n};i=i+1) begin
    @(negedge clk);v=1;s=i==0;e=i=={n-1};data=input_mem[f*{n}+i];
    if(i%31==30) begin @(negedge clk);v=0;s=0;e=0;end
   end
   @(negedge clk);v=0;s=0;e=0;wait(ec==(f+1)*{n});repeat(12) @(negedge clk);
  end
  $display("PASS NMS noise: {len(modes)} frames, both RTL oracles, identical latency/throughput, flat field and noisy edge");$finish;
 end
endmodule
"""
simulate('nms_noise',tb,RTL)
(OUT/'nms_noise_metrics.json').write_text(json.dumps(report,indent=2))
print(json.dumps(report,indent=2))
