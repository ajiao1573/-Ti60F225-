`timescale 1ns/1ps
module camera_sccb_readback_tb;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0;
    wire scl,drive_low;
    tri1 sda;
    reg slave_low=0,active=0,read_mode=0,read_pending=0;
    wire [15:0] width,height;
    wire [7:0] nacks;
    assign sda=drive_low?1'b0:1'bz;
    assign sda=slave_low?1'b0:1'bz;
    camera_sccb_readback #(.CLOCK_HZ(1000000),.BUS_HZ(10000)) dut(
        .clk(clk),.rst_n(rst_n),.enable(1'b1),.sda_i(sda),
        .scl_o(scl),.sda_drive_low_o(drive_low),
        .image_width_o(width),.image_height_o(height),.nack_count_o(nacks));
    integer bits=0,bytes=0,read_bits=0;
    reg [7:0] shift=0;
    reg [15:0] address=0;
    reg [7:0] response;
    always @* case(address)
        16'h3808:response=8'h07;
        16'h3809:response=8'h80;
        16'h380a:response=8'h04;
        16'h380b:response=8'h38;
        default:response=8'hff;
    endcase
    always @(negedge sda) if(scl) begin
        active=1;read_mode=0;read_pending=0;bits=0;bytes=0;read_bits=0;shift=0;
    end
    always @(posedge sda) if(scl) begin active=0;slave_low=0;end
    always @(posedge scl) if(active) begin
        if(read_mode) read_bits=read_bits+1;
        else if(bits<8) begin
            shift={shift[6:0],sda};bits=bits+1;
            if(bits==8) begin
                if(bytes==0) begin
                    if(shift!=8'h78&&shift!=8'h79) $fatal(1,"SCCB slave address %h",shift);
                    read_pending=shift==8'h79;
                end else if(bytes==1) address[15:8]=shift;
                else if(bytes==2) address[7:0]=shift;
                bytes=bytes+1;
            end
        end else begin
            bits=0;
            if(read_pending) begin read_mode=1;read_bits=0;end
        end
    end
    always @(negedge scl) begin
        if(!active) slave_low=0;
        else if(read_mode) slave_low=read_bits<8 ? !response[7-read_bits] : 0;
        else slave_low=bits==8;
    end
    initial begin
        repeat(5) @(negedge clk);rst_n=1;
        wait(height==1080);
        if(width!=1920||nacks!=0) $fatal(1,"readback width=%0d height=%0d NACKs=%0d",width,height,nacks);
        $display("PASS SCCB readback: STOP-separated 16-bit register address/read, 1920x1080, zero NACKs");
        $finish;
    end
    initial begin #5000000;$fatal(1,"readback timeout width=%0d height=%0d NACKs=%0d",width,height,nacks);end
endmodule
