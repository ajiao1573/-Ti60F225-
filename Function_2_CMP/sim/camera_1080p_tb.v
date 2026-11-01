`timescale 1ns/1ps
module camera_1080p_tb;
    reg [7:0] index=0;
    wire [23:0] data,base;
    wire [7:0] size,unused_size;
    reg [7:0] regs[0:65535];
    I2C_OV5640_19201080_Config dut(.LUT_INDEX(index),.LUT_DATA(data),.LUT_SIZE(size));
    I2C_OV5640_1280720_Config original(.LUT_INDEX(index),.LUT_DATA(base),.LUT_SIZE(unused_size));
    integer i;
    initial begin
        for(i=0;i<255;i=i+1) begin
            index=i;#1;
            if(i<206 && data!==base) $fatal(1,"camera base register changed at %0d",i);
            if(i==206 && data!==24'h300802) $fatal(1,"camera must wake before PLL/mode programming");
            regs[data[23:8]]=data[7:0];
        end
        if(size!=255 || data!==24'h300802) $fatal(1,"camera LUT length/final wakeup");
        if({regs[16'h3808],regs[16'h3809]}!==16'd1920 ||
           {regs[16'h380a],regs[16'h380b]}!==16'd1080 ||
           {regs[16'h380c],regs[16'h380d]}!==16'd2500 ||
           {regs[16'h380e],regs[16'h380f]}!==16'd1120) $fatal(1,"camera native geometry/timing");
        if(regs[16'h4300]!==8'h61 || regs[16'h501f]!==8'h01 ||
           regs[16'h3814]!==8'h11 || regs[16'h3815]!==8'h11 ||
           regs[16'h3820]!==8'h46 || regs[16'h3821]!==8'h06) $fatal(1,"RGB565/non-binned orientation");
        if(regs[16'h3035]!==8'h21 || regs[16'h3036]!==8'h69 ||
           regs[16'h460c]!==8'h20 || regs[16'h3824]!==8'h04 || regs[16'h4740]!==8'h21)
            $fatal(1,"camera clock/sync");
        if({regs[16'h3a08],regs[16'h3a09]}!==16'd168 ||
           {regs[16'h3a0a],regs[16'h3a0b]}!==16'd140) $fatal(1,"15fps anti-banding steps");
        $display("PASS 255-entry native 1920x1080 RGB565 camera table, non-binned flip, clock, banding and final wakeup");
        $finish;
    end
endmodule
