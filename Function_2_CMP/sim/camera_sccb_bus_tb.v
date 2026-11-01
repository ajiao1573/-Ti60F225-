`timescale 1ns/1ns
module camera_sccb_bus_tb;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0;
    wire scl,sout,oe;
    wire sda=oe ? sout : 1'b0;
    wire [7:0] index,size;
    wire [23:0] data,expected;
    reg [7:0] expected_index=8'hff;
    wire done;
    i2c_timing_ctrl_16bit #(.CLK_FREQ(100000),.I2C_FREQ(1000)) dut(
        .clk(clk),.rst_n(rst_n),.i2c_sclk(scl),.i2c_sdat_IN(sda),
        .i2c_sdat_OUT(sout),.i2c_sdat_OE(oe),.i2c_config_size(size),
        .i2c_config_index(index),.i2c_config_data({8'h78,data}),.i2c_config_done(done));
    I2C_OV5640_19201080_Config lut(.LUT_INDEX(index),.LUT_DATA(data),.LUT_SIZE(size));
    I2C_OV5640_19201080_Config reference(.LUT_INDEX(expected_index),.LUT_DATA(expected));
    reg active=0;
    reg [31:0] word=0;
    integer bit_count=0,clock_count=0,transactions=0,reset_gaps=0;
    time reset_stop=0;
    always @(negedge sda) if(rst_n&&scl) begin
        if(active) $fatal(1,"unexpected repeated START");
        if(reset_stop!=0) begin
            if($time-reset_stop < 5000) $fatal(1,"camera software reset did not settle for 5ms in scaled clock");
            reset_gaps=reset_gaps+1;reset_stop=0;
        end
        active=1;bit_count=0;clock_count=0;word=0;
    end
    always @(posedge scl) if(active) begin
        if(clock_count%9!=8) begin word={word[30:0],sda};bit_count=bit_count+1;end
        clock_count=clock_count+1;
    end
    always @(posedge sda) if(rst_n&&scl&&active) begin
        // STOP may raise SCL once with SDA low before releasing it; no data
        // clock after the four ACK slots belongs to the transaction.
        if(bit_count<32) $fatal(1,"incomplete SCCB transaction %0d bits=%0d",transactions,bit_count);
        if(clock_count>36) word=word>>1;
        if(word!=={8'h78,expected})
            $fatal(1,"SCCB transaction %0d got %h expected %h",transactions,word,{8'h78,expected});
        if(word==32'h78300882) reset_stop=$time;
        active=0;transactions=transactions+1;expected_index=expected_index+1'b1;
    end
    initial begin
        expected_index=0;
        repeat(5) @(negedge clk);rst_n=1;
        wait(done);repeat(200) @(negedge clk);
        if(transactions!=255 || reset_gaps!=1) $fatal(1,"SCCB transaction count %0d",transactions);
        $display("PASS actual SCCB bus: all 255 slave/register/data transactions decoded correctly, software reset settling interval checked");
        $finish;
    end
    initial begin #200000000; $fatal(1,"SCCB timeout");end
endmodule
