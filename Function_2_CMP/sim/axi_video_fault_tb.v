`timescale 1ns/1ps
module axi_video_fault_tb;
    reg clk=0;always #5 clk=~clk;
    reg rst=1,vs=1,en=0,rvs=0,ren=0,inject_full=0;
    reg awready=1,wready=1,arready=1;
    reg bvalid=0,rvalid=0,rlast=0;
    reg [1:0] bresp=0,rresp=0;
    reg [3:0] bid=0,rid=0;
    wire awvalid,wvalid,wlast,arvalid,error,reset_request,ready;
    wire [31:0] awaddr,araddr;
    wire [7:0] status;
    wire [15:0] werrors,rerrors,ferrors;
    integer bmode=0,rmode=0,beats=0,delay_b=0,rb=0;
    reg reading=0;
    axi4_ctrl #(.C_W_WIDTH(8),.C_R_WIDTH(16),.C_ID_LEN(4),
        .C_RD_END_ADDR(2048),.AXI_TIMEOUT_CYCLES(256)) dut(
        .axi_clk(clk),.axi_reset(rst),
        .axi_awaddr(awaddr),.axi_awvalid(awvalid),.axi_awready(awready),
        .axi_wvalid(wvalid),.axi_wready(wready),.axi_wlast(wlast),
        .axi_bid(bid),.axi_bresp(bresp),.axi_bvalid(bvalid),
        .axi_araddr(araddr),.axi_arvalid(arvalid),.axi_arready(arready),
        .axi_rid(rid),.axi_rdata(128'h1234),.axi_rresp(rresp),.axi_rlast(rlast),.axi_rvalid(rvalid),
        .wframe_pclk(clk),.wframe_vsync(vs),.wframe_data_en(en),.wframe_data(8'd0),
        .rframe_pclk(clk),.rframe_vsync(rvs),.rframe_data_en(ren),
        .freeze_request_i(1'b0),.video_error_o(error),.frame_ready_o(ready),
        .reset_request_o(reset_request),.error_status_o(status),
        .write_error_count_o(werrors),.read_error_count_o(rerrors),.fifo_error_count_o(ferrors));
    always @(posedge clk) begin
        if(rst) begin
            bvalid<=0;delay_b=0;beats=0;reading=0;rvalid<=0;rlast<=0;rb=0;
        end else begin
            bvalid<=0;
            if(wvalid && wready) begin
                beats=beats+1;
                if(bmode==5 && beats==8) begin bvalid<=1;bid<=0;bresp<=0;end
                if(wlast && bmode!=4) delay_b=4;
            end
            if(delay_b>0) begin
                delay_b=delay_b-1;
                if(delay_b==0) begin
                    bvalid<=1;bid<=bmode==3 ? 4'd1 : 4'd0;
                    bresp<=bmode==1 ? 2'b10 : bmode==2 ? 2'b11 : 2'b00;
                end
            end
            rvalid<=0;rlast<=0;
            if(arvalid && arready) begin reading=1;rb=0;end
            if(rvalid) begin
                rb=rb+1;
                if(rlast) reading=0;
            end
            if(reading && rmode!=5) begin
                rvalid<=1;rid<=rmode==2 ? 1 : 0;rresp<=rmode==1 ? 2'b10 : 0;
                rlast<=rmode==4 ? 0 : rb==(rmode==3 ? 7 : 127);
            end
        end
    end
    task reset;
        begin
            rst=1;en=0;vs=1;rvs=0;ren=0;awready=1;wready=1;arready=1;
            repeat(5) @(negedge clk);rst=0;repeat(100) @(negedge clk);
        end
    endtask
    task frame;
        input integer bytes;
        begin
            vs=1;repeat(100) @(negedge clk);
            en=1;repeat(bytes) @(negedge clk);en=0;vs=0;
            repeat(450) @(negedge clk);
        end
    endtask
    task read_frame;
        begin
            rvs=1;repeat(10) @(negedge clk);rvs=0;
            repeat(450) @(negedge clk);
        end
    endtask
    integer i;
    reg [31:0] stalled_ar;
    initial begin
        for(i=1;i<=3;i=i+1) begin
            bmode=i;rmode=0;reset;frame(2048);
            if(dut.have_frame || !error || werrors!=1 || !status[0])
                $fatal(1,"bad BRESP/BID frame published mode=%0d",i);
            bmode=0;frame(2048);
            if(!dut.have_frame || error) $fatal(1,"next complete write frame did not recover");
        end
        bmode=5;reset;frame(2048);
        if(dut.have_frame || !error || werrors==0) $fatal(1,"premature B response frame published");
        bmode=0;reset;frame(1024);
        if(dut.have_frame || !error || !status[4]) $fatal(1,"short frame published");
        frame(2048);
        if(!dut.have_frame || error) $fatal(1,"short-frame recovery");
        for(i=1;i<=3;i=i+1) begin
            rmode=i;reset;frame(2048);read_frame;
            if(!error || rerrors==0 || !status[1]) $fatal(1,"read fault ignored mode=%0d",i);
            rmode=0;read_frame;
            if(error) $fatal(1,"read fault did not recover on next frame");
        end
        bmode=0;rmode=0;reset;
        inject_full=1;en=1;repeat(2) @(negedge clk);en=0;inject_full=0;
        frame(2048);
        if(dut.have_frame || !error || ferrors==0) $fatal(1,"camera FIFO overflow frame published");
        frame(2048);
        if(!dut.have_frame || error) $fatal(1,"camera overflow recovery failed");
        rmode=4;read_frame;
        if(!reset_request || !status[5]) $fatal(1,"missing RLAST did not request shared reset");
        bmode=4;rmode=0;reset;frame(2048);
        if(!reset_request || !status[3] || dut.have_frame) $fatal(1,"missing B watchdog");
        bmode=0;reset;frame(2048);
        rmode=5;read_frame;
        if(!reset_request || !status[3]) $fatal(1,"missing R watchdog");
        rmode=0;reset;frame(2048);arready=0;
        rvs=1;repeat(10) @(negedge clk);rvs=0;wait(arvalid);
        stalled_ar=araddr;
        // A new display boundary must not alter an outstanding AR command.
        rvs=1;repeat(10) @(negedge clk);rvs=0;
        repeat(140) @(negedge clk);
        if(!arvalid || araddr!==stalled_ar) $fatal(1,"AR changed across stalled frame boundary");
        arready=1;repeat(300) @(negedge clk);
        if(reset_request || error) $fatal(1,"old burst was not drained across frame boundary");
        reset;frame(2048);arready=0;
        rvs=1;repeat(10) @(negedge clk);rvs=0;repeat(100) @(negedge clk);
        ren=1;repeat(2) @(negedge clk);ren=0;repeat(10) @(negedge clk);
        if(!error || ferrors==0) $fatal(1,"FIFO underflow not reported");
        arready=1;rmode=0;repeat(150) @(negedge clk);read_frame;
        if(error) $fatal(1,"underflow recovery failed");
        $display("PASS AXI faults: SLVERR/DECERR/BID, short-frame rejection, RRESP/RID/RLAST, missing B/R watchdog, stable AR across VSync, underflow and next-frame recovery");
        $finish;
    end
    initial begin #2000000;$fatal(1,"AXI fault test timeout");end
endmodule

module W0_FIFO_8(input wr_clk_i,wr_en_i,input [7:0] wdata,input a_rst_i,
    input rd_clk_i,rd_en_i,output [127:0] rdata,output prog_empty_o,empty_o,full_o);
    integer bytes=0,reads=0;
    always @(posedge wr_clk_i or posedge a_rst_i)
        if(a_rst_i) bytes<=0;else if(wr_en_i && !full_o) bytes<=bytes+1;
    always @(posedge rd_clk_i or posedge a_rst_i)
        if(a_rst_i) reads<=0;else if(rd_en_i) reads<=reads+1;
    assign full_o=axi_video_fault_tb.inject_full,prog_empty_o=(bytes/16-reads)<128,empty_o=(bytes/16==reads),rdata=0;
endmodule
module R0_FIFO_16(input wr_clk_i,wr_en_i,input [127:0] wdata,input a_rst_i,
    input rd_clk_i,rd_en_i,output [15:0] rdata,output prog_full_o,empty_o,almost_empty_o,full_o);
    integer writes=0,reads=0;
    always @(posedge wr_clk_i or posedge a_rst_i)
        if(a_rst_i) writes<=0;else if(wr_en_i) writes<=writes+1;
    always @(posedge rd_clk_i or posedge a_rst_i)
        if(a_rst_i) reads<=0;else if(rd_en_i && !empty_o) reads<=reads+1;
    assign full_o=0,prog_full_o=writes>=128,empty_o=writes*8==reads,almost_empty_o=empty_o,rdata=0;
endmodule

