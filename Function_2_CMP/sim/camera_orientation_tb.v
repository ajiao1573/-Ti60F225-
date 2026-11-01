`timescale 1ns/1ps
module camera_orientation_tb;
    reg [7:0] index;
    wire [23:0] data;
    wire [7:0] size;
    I2C_OV5640_1280720_Config #(.IMAGE_FLIP(8'h46),.IMAGE_MIRROR(4'h1)) dut(
        .LUT_INDEX(index),.LUT_DATA(data),.LUT_SIZE(size));
    initial begin
        index=211; #1;
        if(data!==24'h382046) $fatal(1,"vertical flip register wrong");
        index=212; #1;
        if(data!==24'h382101 || !data[0]) $fatal(1,"horizontal mirror/binning register wrong");
        if(size!=252) $fatal(1,"configuration table size changed");
        $display("PASS camera 180-degree correction registers, preserved binning and LUT size");
        $finish;
    end
endmodule
