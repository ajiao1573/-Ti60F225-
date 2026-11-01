`timescale 1ns/1ns
// 1920x1080 RGB565, nominal 15 fps, 24MHz XVCLK, automatic DVP PCLK.
// OV5640 specification v2.1 table 2-1 and figure 2-3 clock tree;
// native non-binned window matches the supplied 1080p register reference.
// 42MHz SCLK / (2500 HTS * 1120 VTS) = 15 fps, two bytes/pixel.
module I2C_OV5640_19201080_Config #(
    parameter IMAGE_FLIP=8'h46, IMAGE_MIRROR=8'h06
)(
    input [7:0] LUT_INDEX,
    output reg [23:0] LUT_DATA,
    output [7:0] LUT_SIZE
);
    wire [23:0] base_data;
    wire [7:0] base_size;
    I2C_OV5640_1280720_Config base(
        .LUT_INDEX(LUT_INDEX),.LUT_DATA(base_data),.LUT_SIZE(base_size));
    assign LUT_SIZE=8'd255;
    always @* begin
        LUT_DATA=base_data;
        case(LUT_INDEX)
            // Match the working board's wake-before-mode-change sequence.
            // 0x5025=0 is already the reset default; reuse that optional ISP
            // entry so the 255-entry SCCB index never wraps.
            8'd206: LUT_DATA=24'h300802;
            8'd207: LUT_DATA=24'h303521;
            8'd208: LUT_DATA=24'h303669;
            8'd209: LUT_DATA={16'h3820, IMAGE_FLIP};
            8'd210: LUT_DATA={16'h3821, IMAGE_MIRROR};
            8'd211: LUT_DATA=24'h381411;
            8'd212: LUT_DATA=24'h381511;
            8'd213: LUT_DATA=24'h380001;
            8'd214: LUT_DATA=24'h380150;
            8'd215: LUT_DATA=24'h380201;
            8'd216: LUT_DATA=24'h3803b2;
            8'd217: LUT_DATA=24'h380408;
            8'd218: LUT_DATA=24'h3805ef;
            8'd219: LUT_DATA=24'h380605;
            8'd220: LUT_DATA=24'h3807f1;
            8'd221: LUT_DATA=24'h380807;
            8'd222: LUT_DATA=24'h380980;
            8'd223: LUT_DATA=24'h380a04;
            8'd224: LUT_DATA=24'h380b38;
            8'd225: LUT_DATA=24'h380c09;
            8'd226: LUT_DATA=24'h380dc4;
            8'd227: LUT_DATA=24'h380e04;
            8'd228: LUT_DATA=24'h380f60;
            8'd229: LUT_DATA=24'h381304;
            8'd230: LUT_DATA=24'h361804;
            8'd231: LUT_DATA=24'h36122b;
            8'd232: LUT_DATA=24'h370912;
            8'd233: LUT_DATA=24'h370c00;
            8'd234: LUT_DATA=24'h3a0078;
            8'd235: LUT_DATA=24'h3a0204;
            8'd236: LUT_DATA=24'h3a0360;
            8'd237: LUT_DATA=24'h3a1404;
            8'd238: LUT_DATA=24'h3a1560;
            8'd239: LUT_DATA=24'h3a0800;
            8'd240: LUT_DATA=24'h3a09a8;
            8'd241: LUT_DATA=24'h3a0a00;
            8'd242: LUT_DATA=24'h3a0b8c;
            8'd243: LUT_DATA=24'h3a0e06;
            8'd244: LUT_DATA=24'h3a0d08;
            8'd245: LUT_DATA=24'h400406;
            8'd246: LUT_DATA=24'h30021c;
            8'd247: LUT_DATA=24'h3006c3;
            8'd248: LUT_DATA=24'h460b37;
            // Let DVP derive its byte clock from the RGB565 output format,
            // matching the working 720p path and the native 1080p reference.
            8'd249: LUT_DATA=24'h460c20;
            8'd250: LUT_DATA=24'h382404;
            8'd251: LUT_DATA=24'h500183;
            8'd252: LUT_DATA=24'h350300;
            8'd253: LUT_DATA=24'h474021;
            8'd254: LUT_DATA=24'h300802;
            default: if(LUT_INDEX>=207) LUT_DATA=0;
        endcase
    end
endmodule
