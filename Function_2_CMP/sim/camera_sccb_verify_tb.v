`timescale 1ns/1ps
module camera_sccb_verify_tb;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0;
    wire scl,drive_low;
    tri1 sda;
    reg slave_low=0,active=0,read_mode=0,read_pending=0;
    wire done,error; wire [7:0] retries,failure;
    reg enable=0,stuck=0;integer mode=0;
    assign sda=drive_low?1'b0:1'bz;
    assign sda=(slave_low || stuck)?1'b0:1'bz;
    camera_sccb_verify #(.CLOCK_HZ(1000000),.BUS_HZ(10000),.MAX_RETRIES(2),.TIMEOUT_CYCLES(20000)) dut(
        .clk(clk),.rst_n(rst_n),.enable(enable),.sda_i(sda),
        .scl_o(scl),.sda_drive_low_o(drive_low),.done_o(done),.error_o(error),
        .failure_index_o(failure),.retry_count_o(retries));
    integer bits=0,bytes=0,read_bits=0;
    reg [7:0] shift=0;
    reg [15:0] address=0;
    reg [7:0] response;
    always @* case(address)
        16'h300a:response=(mode==2 || (mode==1 && retries==0)) ? 8'h00 : 8'h56;
        16'h300b:response=8'h40;
        16'h4300:response=8'h61;
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
        else slave_low=bits==8 && mode!=3;
    end
    task reset;
        begin
            enable=0;rst_n=0;active=0;slave_low=0;
            repeat(5) @(negedge clk);rst_n=1;
            repeat(100) @(negedge clk);
            if(done || error) $fatal(1,"readback ran before writer relinquished bus");
            enable=1;
        end
    endtask
    initial begin
        reset;wait(done || error);
        if(error || retries) $fatal(1,"valid register set rejected");
        mode=1;reset;wait(done || error);
        if(error || retries!=1) $fatal(1,"transient readback mismatch not retried");
        mode=2;reset;wait(done || error);
        if(done || retries!=2 || failure!=0) $fatal(1,"wrong chip ID accepted");
        mode=3;reset;wait(done || error);
        if(done || retries!=2) $fatal(1,"readback NACK accepted");
        mode=0;stuck=1;reset;wait(error);
        if(done || drive_low || !scl) $fatal(1,"stuck readback bus not released");
        stuck=0;reset;wait(done || error);
        if(error) $fatal(1,"readback reset recovery failed");
        $display("PASS SCCB verify: writer arbitration, chip ID/geometry/RGB565 readback, mismatch retry, NACK exhaustion, stuck-bus timeout and reset recovery");
        $finish;
    end
    initial begin #10000000;$fatal(1,"readback verification timeout");end
endmodule
