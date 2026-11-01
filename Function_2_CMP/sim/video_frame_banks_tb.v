`timescale 1ns/1ps
module video_frame_banks_tb;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0,wd=0,rs=0,request=0;
    wire [1:0] wb,rb;
    wire frozen;
    video_frame_banks dut(.clk(clk),.rst_n(rst_n),.write_done_i(wd),.read_start_i(rs),
        .freeze_request_i(request),.write_bank_o(wb),.read_bank_o(rb),.frozen_o(frozen));
    integer i,tag=0,j;
    integer memory_tag[0:3];
    reg completed[0:3];
    reg [1:0] old_rb;
    reg old_frozen;
    integer frozen_tag;
    reg [31:0] random_state=32'h5640cafe;
    reg [1:0] wb_before;
    task tick;
        begin
            old_rb=rb; old_frozen=frozen; wb_before=wb;
            if(wd) begin tag=tag+1; memory_tag[wb]=tag; completed[wb]=1; end
            @(negedge clk);
            if(wb==rb) $fatal(1,"camera writer collided with reader");
            if(!rs && (rb!=old_rb || frozen!=old_frozen)) $fatal(1,"mid-frame bank/ack change");
            if(rs && dut.reader_valid && !completed[rb]) $fatal(1,"selected incomplete bank");
            if(frozen && !old_frozen) frozen_tag=memory_tag[rb];
            if(frozen && old_frozen && (rb!=old_rb || memory_tag[rb]!=frozen_tag))
                $fatal(1,"frozen picture changed/was overwritten");
        end
    endtask
    initial begin
        for(j=0;j<4;j=j+1) begin completed[j]=0; memory_tag[j]=0; end
        repeat(4) @(negedge clk); rst_n=1;
        // Freeze before the first camera frame: do not acknowledge stale RAM.
        request=1; repeat(4) tick;
        rs=1; tick; rs=0;
        if(frozen) $fatal(1,"froze an uninitialized frame");
        wd=1; rs=1; tick; wd=0; rs=0;
        if(!frozen || rb!=0) $fatal(1,"early freeze failed to select first complete frame");
        for(i=0;i<30;i=i+1) begin wd=1; rs=(i%3==0); tick; end
        wd=0; rs=0; request=0; repeat(4) tick;
        if(!frozen) $fatal(1,"resume happened outside frame boundary");
        rs=1; tick; rs=0;
        if(frozen) $fatal(1,"resume not acknowledged");
        // Cover every combination of read/write events and freeze requests.
        for(i=0;i<3000;i=i+1) begin
            random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
            wd=random_state[0]; rs=random_state[4];
            if(i%41==0) request=~request;
            tick;
        end
        $display("PASS DDR frame banks: early freeze, full-frame boundary, writer protection, simultaneous events and resume");
        $finish;
    end
endmodule
