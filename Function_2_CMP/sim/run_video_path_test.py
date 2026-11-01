"""Test the real FIFO packing/RAM/control RTL with a portable reset-sync model.

Only the vendor encrypted reset synchronizer is replaced by its documented
ASYNC_STAGE/ACTIVE_LOW/RST_VALUE contract. FIFO datapath/control stay unchanged.
Run with --1080p to check a complete 1920x1080 frame.
"""
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
out = root / 'build/sim'
out.mkdir(parents=True, exist_ok=True)
sources = []
for name in ('W0_FIFO_8', 'R0_FIFO_16'):
    source = (root / f'ip/{name}/{name}.sv').read_text(encoding='utf-8')
    prefix = source.split('module `IP_MODULE_NAME(efx_asyncreg)')[0]
    model = '''module `IP_MODULE_NAME(efx_asyncreg) #(
        parameter ASYNC_STAGE=2, WIDTH=4, ACTIVE_LOW=1, RST_VALUE=0, OFF_ASSERTION=0
    )(input clk,reset_n,input [WIDTH-1:0] d_i,output [WIDTH-1:0] d_o);
        wire reset_active=ACTIVE_LOW ? !reset_n : reset_n;
        reg [WIDTH-1:0] sync_regs[0:ASYNC_STAGE-1];
        integer k;
        always @(posedge clk or posedge reset_active) begin
            if(reset_active) for(k=0;k<ASYNC_STAGE;k=k+1) sync_regs[k]<=RST_VALUE;
            else begin
                sync_regs[0]<=d_i;
                for(k=1;k<ASYNC_STAGE;k=k+1) sync_regs[k]<=sync_regs[k-1];
            end
        end
        assign d_o=sync_regs[ASYNC_STAGE-1];
    endmodule
    '''
    target = out / f'{name}_portable.sv'
    target.write_text(prefix + model, encoding='utf-8')
    sources.append(str(target))

if '--prepare-only' in sys.argv:
    print('Prepared portable FIFO reset synchronizer models.')
    raise SystemExit(0)
tool = root / 'build/tools/iverilog/app/bin'
target = out / 'axi_video_roundtrip_tb.vvp'
options = ['-Paxi_video_roundtrip_tb.HEIGHT=1080'] if '--1080p' in sys.argv else []
subprocess.run([str(tool/'iverilog.exe'), '-g2005-sv', '-pRECURSIVE_MOD_LIMIT=32', '-s', 'axi_video_roundtrip_tb',
                *options, '-o', str(target), *sources,
                str(root/'src/axi/axi4_ctrl.v'),str(root/'src/bean/video_frame_banks.v'),
                str(root/'sim/axi_video_roundtrip_tb.v')],check=True)
result = subprocess.run([str(tool/'vvp.exe'),str(target)],capture_output=True,text=True,timeout=600)
suffix = '_1080p' if options else ''
(out/f'axi_video_roundtrip{suffix}.log').write_text(result.stdout+result.stderr,encoding='utf-8')
print(result.stdout, result.stderr)
sys.exit(result.returncode)
