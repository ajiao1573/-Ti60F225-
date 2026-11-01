`timescale 1ns/1ps
// Exercise independent AXI address/data/response backpressure. The old writer
// advanced its address as soon as WLAST transferred, before AW was accepted.
module axi_video_write_tb;
    reg clk=0; always #5 clk=~clk;
    reg rst=1, vs=1, en=0;
    reg [7:0] data=0;
    reg awready=0, wready=1, bvalid=0;
    wire [31:0] awaddr;
    wire awvalid,wvalid,wlast;
    wire [127:0] wdata;
    axi4_ctrl #(.C_W_WIDTH(8),.C_R_WIDTH(16),.C_ID_LEN(4),.C_RD_END_ADDR(2048)) dut(
        .axi_clk(clk),.axi_reset(rst),
        .axi_awaddr(awaddr),.axi_awvalid(awvalid),.axi_awready(awready),
        .axi_wdata(wdata),.axi_wvalid(wvalid),.axi_wready(wready),.axi_wlast(wlast),
        .axi_bid(4'd0),.axi_bresp(2'd0),.axi_bvalid(bvalid),
        .axi_arready(1'b0),.axi_rid(4'd0),.axi_rdata(128'd0),
        .axi_rresp(2'd0),.axi_rlast(1'b0),.axi_rvalid(1'b0),
        .freeze_request_i(1'b0),
        .wframe_pclk(clk),.wframe_vsync(vs),.wframe_data_en(en),.wframe_data(data),
        .rframe_pclk(clk),.rframe_vsync(1'b0),.rframe_data_en(1'b0));
    integer i,beats=0;
    reg [31:0] held_addr;
    reg stalled=0;
    always @(posedge clk) if(!rst) begin
        if(stalled && (!awvalid || awaddr!==held_addr))
            $fatal(1,"AW address/valid changed under backpressure: %h -> %h",held_addr,awaddr);
        stalled=awvalid && !awready;
        held_addr=awaddr;
        if(wvalid && wready) begin
            beats=beats+1;
            if(wlast !== (beats==128)) $fatal(1,"WLAST/beat count");
        end
    end
    initial begin
        repeat(5) @(negedge clk); rst=0;
        repeat(80) @(negedge clk);
        for(i=0;i<2048;i=i+1) begin en=1;data=i;@(negedge clk);end
        en=0;vs=0;
        wait(beats==128);
        repeat(15) @(negedge clk);
        awready=1;@(negedge clk);awready=0;
        repeat(10) @(negedge clk);
        if(dut.r_wframe_inc || dut.frame_banks.have_frame)
            $fatal(1,"published a frame before DDR write response");
        bvalid=1;@(negedge clk);bvalid=0;
        repeat(15) @(negedge clk);
        if(!dut.frame_banks.have_frame || beats!=128)
            $fatal(1,"completed frame not published");
        $display("PASS AXI write: stalled AW stable after WLAST; publish only after write response");
        $finish;
    end
    initial begin #100000; $fatal(1,"timeout"); end
endmodule

// FIFO contract models: isolate the AXI scheduler from encrypted IP models.
module W0_FIFO_8(input wr_clk_i,wr_en_i,input [7:0] wdata,input a_rst_i,
    input rd_clk_i,rd_en_i,output [127:0] rdata,output prog_empty_o,empty_o,full_o);
    assign full_o=0;
    integer bytes=0,reads=0;
    always @(posedge wr_clk_i or posedge a_rst_i)
        if(a_rst_i) bytes<=0; else if(wr_en_i) bytes<=bytes+1;
    always @(posedge rd_clk_i or posedge a_rst_i)
        if(a_rst_i) reads<=0; else if(rd_en_i) reads<=reads+1;
    assign prog_empty_o=(bytes/16-reads)<128;
    assign empty_o=(bytes/16==reads);
    assign rdata=128'd0;
endmodule
module R0_FIFO_16(input wr_clk_i,wr_en_i,input [127:0] wdata,input a_rst_i,
    input rd_clk_i,rd_en_i,output [15:0] rdata,
    output prog_full_o,empty_o,almost_empty_o,full_o);
    assign full_o=0;
    assign rdata=0;
    assign prog_full_o=1;
    assign empty_o=1;
    assign almost_empty_o=1;
endmodule
