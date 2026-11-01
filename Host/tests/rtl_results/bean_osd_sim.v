`timescale 1ns/1ps
`include "bean/bean_config.vh"
// Frame-stable count overlay. Status: WAIT (no result), BUSY (new analysis),
// READY (valid result), ERROR (overflow/incomplete mask; count hidden).
module bean_osd #(
    parameter RUNTIME_ENABLE=0,
    parameter ROI_X0=64, ROI_Y0=48, ROI_X1=1216, ROI_Y1=672
)(
    input [`BEAN_CFG_BITS-1:0] config_i,
    input menu_i,input [3:0] field_i,input [1:0] step_i,input box_limit_i,
    output display_ready_o,
    input clk, input rst_n,
    input [23:0] rgb_i,
    input de_i, input hs_i, input vs_i,
    input [11:0] x_i, input [11:0] y_i,
    input [15:0] count_i,
    input result_valid_i, input error_i, input busy_i, input done_i,
    input frozen_i, input invalidate_i,
    output reg [23:0] rgb_o,
    output reg de_o, output reg hs_o, output reg vs_o
);
    reg [`BEAN_CFG_BITS-1:0] runtime_config;
    reg runtime_menu,runtime_limit;
    reg [3:0] runtime_field;
    reg [1:0] runtime_step;
    reg [19:0] param_binary;
    reg [23:0] param_shift,param_bcd;
    reg [4:0] param_left;
    reg [23:0] param_adjusted;
    integer pi;
    function [19:0] field_value;
        input [`BEAN_CFG_BITS-1:0] cfg;
        input [3:0] selected;
        input [1:0] step;
        begin case(selected)
            0:field_value={18'b0,cfg[`BC_VIEW]};
            1:field_value={12'b0,cfg[`BC_THRESHOLD]};
            2:field_value={19'b0,cfg[`BC_DARK]};
            3:field_value={8'b0,cfg[`BC_X0]};4:field_value={8'b0,cfg[`BC_Y0]};
            5:field_value={8'b0,cfg[`BC_X1]};6:field_value={8'b0,cfg[`BC_Y1]};
            7:field_value=cfg[`BC_MIN_AREA];8:field_value=cfg[`BC_MAX_AREA];
            9:field_value={8'b0,cfg[`BC_MIN_W]};10:field_value={8'b0,cfg[`BC_MIN_H]};
            11:field_value={8'b0,cfg[`BC_MAX_W]};12:field_value={8'b0,cfg[`BC_MAX_H]};
            default:field_value=step==0?1:step==1?8:step==2?32:256;
        endcase end
    endfunction
    function [31:0] field_tag;
        input [3:0] selected;
        begin case(selected)
            0:field_tag="VIEW";1:field_tag="THR ";2:field_tag="DARK";
            3:field_tag="X0  ";4:field_tag="Y0  ";5:field_tag="X1  ";6:field_tag="Y1  ";
            7:field_tag="MINA";8:field_tag="MAXA";9:field_tag="MINW";10:field_tag="MINH";
            11:field_tag="MAXW";12:field_tag="MAXH";default:field_tag="STEP";
        endcase end
    endfunction
    wire [11:0] cfg_x0=RUNTIME_ENABLE?runtime_config[`BC_X0]:ROI_X0;
    wire [11:0] cfg_y0=RUNTIME_ENABLE?runtime_config[`BC_Y0]:ROI_Y0;
    wire [11:0] cfg_x1=RUNTIME_ENABLE?runtime_config[`BC_X1]:ROI_X1;
    wire [11:0] cfg_y1=RUNTIME_ENABLE?runtime_config[`BC_Y1]:ROI_Y1;
    reg vs_d;
    reg displayed_valid, displayed_error, displayed_busy, displayed_frozen;
    assign display_ready_o=displayed_valid && displayed_frozen && !displayed_error;
    always @* begin
        param_adjusted=param_shift;
        for(pi=0;pi<6;pi=pi+1)
            if(param_shift[pi*4+:4]>=5) param_adjusted[pi*4+:4]=param_shift[pi*4+:4]+4'd3;
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            runtime_config<=0;runtime_menu<=0;runtime_limit<=0;runtime_field<=0;runtime_step<=0;
            param_binary<=0;param_shift<=0;param_bcd<=0;param_left<=0;
        end else if(RUNTIME_ENABLE) begin
            if(vs_d && !vs_i) begin
                runtime_config<=config_i;runtime_menu<=menu_i;runtime_limit<=box_limit_i;
                runtime_field<=field_i;runtime_step<=step_i;
                param_binary<=field_value(config_i,field_i,step_i);param_shift<=0;param_left<=20;
            end else if(param_left!=0) begin
                param_binary<={param_binary[18:0],1'b0};param_shift<={param_adjusted[22:0],param_binary[19]};
                param_left<=param_left-1'b1;
                if(param_left==1) param_bcd<={param_adjusted[22:0],param_binary[19]};
            end
        end
    end
    reg [15:0] binary_shift, bcd_shift, pending_bcd, displayed_bcd;
    reg [4:0] convert_left;

    reg [15:0] bcd_adjusted;
    integer k;
    always @* begin
        bcd_adjusted=bcd_shift;
        for (k=0;k<4;k=k+1)
            if (bcd_shift[k*4 +: 4] >= 5)
                bcd_adjusted[k*4 +: 4]=bcd_shift[k*4 +: 4]+4'd3;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vs_d<=1; binary_shift<=0; bcd_shift<=0; pending_bcd<=0;
            displayed_bcd<=0; convert_left<=0;
            displayed_valid<=0; displayed_error<=0; displayed_busy<=0; displayed_frozen<=0;
        end else begin
            vs_d<=vs_i;
            if (invalidate_i) begin
                // DDR acknowledges freeze/resume in vertical blanking. Hide
                // the old live count before showing a newly pinned image.
                binary_shift<=0; bcd_shift<=0; pending_bcd<=0; convert_left<=0;
                displayed_valid<=0; displayed_error<=0; displayed_busy<=1; displayed_frozen<=0;
            end else begin
            if (done_i && result_valid_i) begin
                binary_shift<=count_i; bcd_shift<=0; convert_left<=16;
            end else if (convert_left != 0) begin
                bcd_shift<={bcd_adjusted[14:0],binary_shift[15]};
                binary_shift<={binary_shift[14:0],1'b0};
                convert_left<=convert_left-1'b1;
                if (convert_left == 1) pending_bcd<={bcd_adjusted[14:0],binary_shift[15]};
            end
            // A completed BCD conversion and its valid flag are sampled together.
            if (vs_d && !vs_i && convert_left == 0 && !done_i) begin
                displayed_bcd<=pending_bcd; displayed_valid<=result_valid_i;
                displayed_error<=error_i; displayed_busy<=busy_i;
                displayed_frozen<=frozen_i;
            end
            end
        end
    end
    function [34:0] font;
        input [7:0] ch;
        begin
            case(ch)
                "0":font={5'b01110,5'b10001,5'b10011,5'b10101,5'b11001,5'b10001,5'b01110};
                "1":font={5'b00100,5'b01100,5'b00100,5'b00100,5'b00100,5'b00100,5'b01110};
                "2":font={5'b01110,5'b10001,5'b00001,5'b00010,5'b00100,5'b01000,5'b11111};
                "3":font={5'b11110,5'b00001,5'b00001,5'b01110,5'b00001,5'b00001,5'b11110};
                "4":font={5'b00010,5'b00110,5'b01010,5'b10010,5'b11111,5'b00010,5'b00010};
                "5":font={5'b11111,5'b10000,5'b10000,5'b11110,5'b00001,5'b00001,5'b11110};
                "6":font={5'b01110,5'b10000,5'b10000,5'b11110,5'b10001,5'b10001,5'b01110};
                "7":font={5'b11111,5'b00001,5'b00010,5'b00100,5'b01000,5'b01000,5'b01000};
                "8":font={5'b01110,5'b10001,5'b10001,5'b01110,5'b10001,5'b10001,5'b01110};
                "9":font={5'b01110,5'b10001,5'b10001,5'b01111,5'b00001,5'b00001,5'b01110};
                "A":font={5'b01110,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001};
                "B":font={5'b11110,5'b10001,5'b10001,5'b11110,5'b10001,5'b10001,5'b11110};
                "C":font={5'b01110,5'b10001,5'b10000,5'b10000,5'b10000,5'b10001,5'b01110};
                "D":font={5'b11110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b11110};
                "E":font={5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b11111};
                "I":font={5'b01110,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b01110};
                "H":font={5'b10001,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001};
                "L":font={5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b11111};
                "N":font={5'b10001,5'b11001,5'b11001,5'b10101,5'b10011,5'b10011,5'b10001};
                "O":font={5'b01110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
                "R":font={5'b11110,5'b10001,5'b10001,5'b11110,5'b10100,5'b10010,5'b10001};
                "S":font={5'b01111,5'b10000,5'b10000,5'b01110,5'b00001,5'b00001,5'b11110};
                "T":font={5'b11111,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100};
                "U":font={5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
                "W":font={5'b10001,5'b10001,5'b10001,5'b10101,5'b10101,5'b10101,5'b01010};
                "Y":font={5'b10001,5'b10001,5'b01010,5'b00100,5'b00100,5'b00100,5'b00100};
                ":":font={5'b00000,5'b00100,5'b00100,5'b00000,5'b00100,5'b00100,5'b00000};
                "-":font={5'b00000,5'b00000,5'b00000,5'b11111,5'b00000,5'b00000,5'b00000};
                "F":font={5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b10000};
                "G":font={5'b01110,5'b10001,5'b10000,5'b10111,5'b10001,5'b10001,5'b01110};
                "K":font={5'b10001,5'b10010,5'b10100,5'b11000,5'b10100,5'b10010,5'b10001};
                "M":font={5'b10001,5'b11011,5'b10101,5'b10101,5'b10001,5'b10001,5'b10001};
                "P":font={5'b11110,5'b10001,5'b10001,5'b11110,5'b10000,5'b10000,5'b10000};
                "V":font={5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01010,5'b00100};
                "X":font={5'b10001,5'b10001,5'b01010,5'b00100,5'b01010,5'b10001,5'b10001};
                "+":font={5'b00000,5'b00100,5'b00100,5'b11111,5'b00100,5'b00100,5'b00000};
                ".":font={5'b00000,5'b00000,5'b00000,5'b00000,5'b00000,5'b00110,5'b00110};
                default:font=0;
            endcase
        end
    endfunction
    reg [7:0] ch;
    reg [34:0] glyph;
    reg text_pixel, panel, border;
    integer cx,cy,cell_index;
    reg [23:0] mixed_rgb;
    reg [31:0] tag;
    reg [19:0] step_bcd;
    reg [255:0] hint;
    reg [47:0] view_name;
    always @* begin
        ch=" "; cx=0; cy=0; cell_index=0;
        tag=field_tag(runtime_field);
        step_bcd=runtime_step==0?20'h00001:runtime_step==1?20'h00008:runtime_step==2?20'h00032:20'h00256;
        view_name=runtime_config[`BC_VIEW]==0?"RAW   ":runtime_config[`BC_VIEW]==1?"BINARY":"RESULT";
        hint=0;
        panel=x_i>=24 && x_i<250 && y_i>=8 && y_i<64;
        if (x_i>=32 && x_i<230 && y_i>=16 && y_i<37) begin
            cell_index=(x_i-32)/18; cx=((x_i-32)%18)/3; cy=(y_i-16)/3;
            case(cell_index)
                0:ch="C"; 1:ch="O"; 2:ch="U"; 3:ch="N"; 4:ch="T"; 5:ch=":";
                7:ch=displayed_valid ? 8'd48+{4'b0,displayed_bcd[15:12]} : "-";
                8:ch=displayed_valid ? 8'd48+{4'b0,displayed_bcd[11:8]} : "-";
                9:ch=displayed_valid ? 8'd48+{4'b0,displayed_bcd[7:4]} : "-";
                10:ch=displayed_valid ? 8'd48+{4'b0,displayed_bcd[3:0]} : "-";
            endcase
        end else if (x_i>=32 && x_i<92 && y_i>=44 && y_i<58) begin
            cell_index=(x_i-32)/12; cx=((x_i-32)%12)/2; cy=(y_i-44)/2;
            if (displayed_error) begin
                case(cell_index) 0:ch="E"; 1:ch="R"; 2:ch="R"; 3:ch="O"; 4:ch="R"; endcase
            end else if (!displayed_valid) begin
                case(cell_index) 0:ch="W"; 1:ch="A"; 2:ch="I"; 3:ch="T"; endcase
            end else if (displayed_frozen) begin
                case(cell_index) 0:ch="H"; 1:ch="O"; 2:ch="L"; 3:ch="D"; endcase
            end else if (displayed_busy) begin
                case(cell_index) 0:ch="B"; 1:ch="U"; 2:ch="S"; 3:ch="Y"; endcase
            end else begin
                case(cell_index) 0:ch="R"; 1:ch="E"; 2:ch="A"; 3:ch="D"; 4:ch="Y"; endcase
            end
        end
        if(RUNTIME_ENABLE && x_i>=288 && x_i<672) begin
            cell_index=(x_i-288)/12;cx=((x_i-288)%12)/2;
            if(y_i>=12 && y_i<26) begin
                panel=1;cy=(y_i-12)/2;ch=" ";
                if(cell_index<4) ch=tag[31-cell_index*8-:8];
                else if(cell_index==4 || cell_index==16) ch=":";
                else if(cell_index>=5 && cell_index<11) ch=8'd48+{4'b0,param_bcd[23-(cell_index-5)*4-:4]};
                else if(cell_index>=12 && cell_index<16) begin
                    case(cell_index) 12:ch="S";13:ch="T";14:ch="E";15:ch="P";endcase
                end else if(cell_index>=17 && cell_index<22) ch=8'd48+{4'b0,step_bcd[19-(cell_index-17)*4-:4]};
                else if(cell_index>=24 && cell_index<30) ch=view_name[47-(cell_index-24)*8-:8];
            end else if(y_i>=30 && y_i<44) begin
                panel=1;cy=(y_i-30)/2;
                hint=runtime_menu?"K1:+ HOLD:- K2:NEXT 1S:EXIT     ":"K1:FREEZE K2:MENU               ";
                ch=hint[255-cell_index*8-:8];
            end else if(y_i>=46 && y_i<60) begin
                panel=1;cy=(y_i-46)/2;
                hint=runtime_limit?"BOX LIMIT:128                   ":displayed_frozen?"BOXES:HOLD                      ":"BOXES:FREEZE TO SHOW            ";
                ch=hint[255-cell_index*8-:8];
            end
        end
        glyph=font(ch); text_pixel=0;
        if (cx<5 && cy<7) text_pixel=glyph[34-cy*5-cx];
        border=x_i>=cfg_x0 && x_i<cfg_x1 && y_i>=cfg_y0 && y_i<cfg_y1 &&
            (x_i<cfg_x0+2 || x_i>=cfg_x1-2 || y_i<cfg_y0+2 || y_i>=cfg_y1-2);
        mixed_rgb=rgb_i;
        if (border) mixed_rgb=24'h00ff00;
        if (panel) mixed_rgb=text_pixel ?
            (displayed_error ? 24'hff4040 : displayed_valid ? 24'hffff00 : 24'hffffff) : 24'h101010;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin rgb_o<=0; de_o<=0; hs_o<=1; vs_o<=1; end
        else begin rgb_o<=de_i ? mixed_rgb : 24'b0; de_o<=de_i; hs_o<=hs_i; vs_o<=vs_i; end
    end
endmodule
