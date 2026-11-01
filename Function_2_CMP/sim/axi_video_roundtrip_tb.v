`timescale 1ns/1ps
module axi_video_roundtrip_tb;
    parameter HEIGHT=32;
    localparam WIDTH=1920, BYTES=WIDTH*HEIGHT*2;
    reg aclk=0,pclk=0,rclk=0;
    always #5.208333 aclk=~aclk;
    always #5.952381 pclk=~pclk;
    always #6.720430 rclk=~rclk;
    reg rst=1,vs=1,wen=0,rvs=0,ren=0;
    reg [7:0] din=0;
    wire [15:0] dout;
    wire [31:0] awaddr,araddr;
    wire awvalid,wvalid,wlast,arvalid;
    wire [127:0] wdata;
    reg awready=0,wready=0,bvalid=0,arready=0,rvalid=0,rlast=0;
    reg [127:0] rdata=0;
    wire bready,rready;
    axi4_ctrl #(.C_W_WIDTH(8),.C_R_WIDTH(16),.C_ID_LEN(4),.C_RD_END_ADDR(BYTES)) dut(
        .axi_clk(aclk),.axi_reset(rst),
        .axi_awaddr(awaddr),.axi_awvalid(awvalid),.axi_awready(awready),
        .axi_wdata(wdata),.axi_wvalid(wvalid),.axi_wready(wready),.axi_wlast(wlast),
        .axi_bid(4'd0),.axi_bresp(2'd0),.axi_bvalid(bvalid),.axi_bready(bready),
        .axi_araddr(araddr),.axi_arvalid(arvalid),.axi_arready(arready),
        .axi_rid(4'd0),.axi_rdata(rdata),.axi_rresp(2'd0),
        .axi_rlast(rlast),.axi_rvalid(rvalid),.axi_rready(rready),
        .freeze_request_i(1'b0),
        .wframe_pclk(pclk),.wframe_vsync(vs),.wframe_data_en(wen),.wframe_data(din),
        .rframe_pclk(rclk),.rframe_vsync(rvs),.rframe_data_en(ren),.rframe_data(dout));
    reg [127:0] memory[0:1048575];
    reg [127:0] pending_data[0:127];
    integer cycles=0,nb=0,wr_addr=0,wa_delay=0,resp_delay=0;
    integer read_addr=0,read_beat=0,writes=0,reads=0,j;
    reg have_aw=0,have_wlast=0,reading=0;
    reg [31:0] aw_saved,ar_saved;
    reg aw_stall=0,ar_stall=0;
    function [15:0] pixel;
        input integer n;
        begin pixel=((n%WIDTH)&31)<<11 | (((n/WIDTH)*7+(n%WIDTH)/31)&63)<<5 | ((n*3+n/WIDTH)&31); end
    endfunction
    // A memory slave with independent AW/W stalls and delayed B. W data may
    // arrive before AW, matching AXI's independent channels.
    always @(posedge aclk) if(!rst) begin
        cycles=cycles+1;
        if(aw_stall && (!awvalid || awaddr!==aw_saved)) $fatal(1,"AW instability");
        if(ar_stall && (!arvalid || araddr!==ar_saved)) $fatal(1,"AR instability");
        aw_stall=awvalid&&!awready;aw_saved=awaddr;
        ar_stall=arvalid&&!arready;ar_saved=araddr;
        if(awvalid&&awready) begin
            if(have_aw) $fatal(1,"multiple outstanding AW");
            wr_addr=awaddr/16; have_aw=1;
            if(awaddr%2048!=0 || (awaddr%4194304)!=(writes*2048)) $fatal(1,"write stride");
        end
        if(wvalid&&wready) begin
            pending_data[nb]=wdata;
            if(wlast !== (nb==127)) $fatal(1,"write burst length");
            nb=nb+1;
            if(wlast) have_wlast=1;
        end
        if(bvalid&&bready) bvalid<=0;
        if(have_aw&&have_wlast) begin
            for(j=0;j<128;j=j+1) memory[wr_addr+j]=pending_data[j];
            writes=writes+1;nb=0;have_aw=0;have_wlast=0;resp_delay=17;
        end
        if(resp_delay>0) begin
            resp_delay=resp_delay-1;
            if(resp_delay==0) bvalid<=1;
        end
        // First AW is stalled longer than a whole W burst.
        if(awvalid) wa_delay=wa_delay+1; else wa_delay=0;
        awready <= awvalid && wa_delay>(writes==0?180:5);
        wready <= cycles%7!=0;
        arready <= !reading && cycles%5!=0;
        if(arvalid&&arready) begin
            read_addr=araddr/16;read_beat=0;reading=1;arready<=0;
        end
        if(rvalid&&rready) begin
            if(rlast) begin reading=0;reads=reads+1;end
            read_beat=read_beat+1;
        end
        rvalid<=0;rlast<=0;
        if(reading && cycles%9!=0) begin
            rdata<=memory[read_addr+read_beat];
            rvalid<=1; rlast<=(read_beat==127);
        end
    end
    integer x,y,n=0,received=0;
    reg [15:0] pix;
    always @(posedge rclk) if(ren) begin
        if(dut.w_rfifo_empty) $fatal(1,"display FIFO underflow at pixel %0d",received);
        if(dout!==pixel(received)) $fatal(1,"pixel %0d got %h expected %h",received,dout,pixel(received));
        received=received+1;
    end
    initial begin
        repeat(10) @(negedge aclk);rst=0;
        repeat(100) @(negedge pclk);
        for(y=0;y<HEIGHT;y=y+1) begin
            for(x=0;x<WIDTH;x=x+1) begin
                pix=pixel(n); n=n+1;
                wen=1;din=pix[15:8];@(negedge pclk);
                din=pix[7:0];@(negedge pclk);
            end
            wen=0;repeat(1160) @(negedge pclk);
        end
        vs=0;wait(dut.frame_banks.have_frame);
        if(writes!=BYTES/2048) $fatal(1,"frame burst count %0d",writes);
        @(negedge rclk);rvs=1;
        repeat(10) @(negedge rclk);rvs=0;
        reads=0;
        // VSync-to-active blanking gives ample prefetch time.
        repeat(3000) @(negedge rclk);
        for(y=0;y<HEIGHT;y=y+1) begin
            ren=1;repeat(WIDTH) @(negedge rclk);ren=0;
            repeat(280) @(negedge rclk);
        end
        if(received!=WIDTH*HEIGHT || reads!=BYTES/2048)
            $fatal(1,"incomplete display pixels=%0d reads=%0d expected=%0d",received,reads,BYTES/2048);
        $display("PASS RGB565 DDR roundtrip: %0dx%0d, %0d bytes, %0d bursts, every pixel checked; 84/96/74.4MHz; AW/W/R stalls",WIDTH,HEIGHT,BYTES,writes);
        $finish;
    end
    initial begin #200000000; $fatal(1,"roundtrip timeout");end
endmodule
