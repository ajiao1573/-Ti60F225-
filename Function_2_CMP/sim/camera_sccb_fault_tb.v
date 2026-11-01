`timescale 1ns/1ns
module camera_sccb_fault_tb;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,stuck=0,permanent=0;
    integer slot=0;
    wire scl,out,oe,done,error;
    wire [7:0] index,nacks,retries;
    wire reject=(dut.current_state==slot) && (permanent || retries==0);
    wire sda=stuck ? 1'b0 : oe ? out : reject;
    i2c_timing_ctrl_16bit #(.CLK_FREQ(10000),.I2C_FREQ(100),
        .STARTUP_CYCLES(10),.TIMEOUT_CYCLES(10000),.MAX_RETRIES(2)) dut(
        .clk(clk),.rst_n(rst_n),.i2c_sclk(scl),.i2c_sdat_IN(sda),
        .i2c_sdat_OUT(out),.i2c_sdat_OE(oe),.i2c_config_size(8'd2),
        .i2c_config_index(index),.i2c_config_data(32'h78300802),
        .i2c_config_done(done),.i2c_config_error(error),.nack_count_o(nacks),.retry_count_o(retries));
    task reset;
        begin rst_n=0;repeat(4) @(negedge clk);rst_n=1;end
    endtask
    integer i;
    initial begin
        for(i=3;i<=9;i=i+2) begin
            slot=i;reset;wait(done || error);
            if(error || index!=2 || nacks!=1 || retries!=1)
                $fatal(1,"ACK slot %0d retry/index failure",i);
        end
        permanent=1;slot=9;reset;wait(done || error);
        if(done || index!=0 || nacks!=3 || retries!=2)
            $fatal(1,"permanent data NACK falsely completed configuration");
        repeat(1000) @(negedge clk);
        if(index!=0 || oe || !scl) $fatal(1,"terminal error did not release bus");
        permanent=0;stuck=1;reset;wait(error);
        if(done || index!=0) $fatal(1,"stuck SDA falsely completed");
        stuck=0;slot=0;reset;wait(done || error);
        if(error || index!=2) $fatal(1,"reset recovery failed");
        $display("PASS SCCB faults: all four NACK slots retry same index, bounded permanent NACK, stuck-SDA timeout, bus release and reset recovery");
        $finish;
    end
    initial begin #2000000;$fatal(1,"SCCB fault test timeout");end
endmodule
