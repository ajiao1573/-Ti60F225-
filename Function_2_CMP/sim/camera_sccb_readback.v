`timescale 1ns/1ps
// Diagnostic only. Poll the sensor's actual 0x3808..0x380B registers after
// the normal writer is idle, using STOP-separated SCCB register reads.
module camera_sccb_readback #(
    parameter CLOCK_HZ=96000000, BUS_HZ=50000
)(input clk,rst_n,enable,input sda_i,
   output reg scl_o,output reg sda_drive_low_o,
   output reg [15:0] image_width_o,image_height_o,
   output reg [7:0] nack_count_o);
    localparam WAIT=0,START_A=1,START_B=2,START_C=3,
        WRITE_BIT=4,WRITE_ACK=5,READ_BIT=6,READ_NACK=7,
        STOP_A=8,STOP_B=9,STOP_C=10;
    localparam DIV=CLOCK_HZ/(BUS_HZ*4);
    reg [15:0] divider=0;
    reg [10:0] gap=0;
    reg [3:0] state=WAIT;
    reg [1:0] phase=0,byte_index=0,register_index=0;
    reg [2:0] bit_index=7;
    reg [7:0] tx=8'h78,rx=0;
    (* async_reg="true" *) reg sda_meta=1,sda_sync=1;
    always @(posedge clk) begin sda_meta<=sda_i;sda_sync<=sda_meta;end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            scl_o<=1;sda_drive_low_o<=0;divider<=0;gap<=0;state<=WAIT;
            phase<=0;byte_index<=0;register_index<=0;bit_index<=7;
            tx<=8'h78;rx<=0;image_width_o<=0;image_height_o<=0;nack_count_o<=0;
        end else if(!enable) begin
            scl_o<=1;sda_drive_low_o<=0;divider<=0;gap<=0;state<=WAIT;
        end else if(divider!=DIV-1) divider<=divider+1'b1;
        else begin
            divider<=0;
            case(state)
                WAIT: begin
                    scl_o<=1;sda_drive_low_o<=0;
                    if(gap!=0) gap<=gap-1'b1;
                    else begin byte_index<=0;tx<=8'h78;state<=START_A;end
                end
                START_A: begin scl_o<=1;sda_drive_low_o<=0;state<=START_B;end
                START_B: begin scl_o<=1;sda_drive_low_o<=1;state<=START_C;end
                START_C: begin scl_o<=0;phase<=0;bit_index<=7;state<=WRITE_BIT;end
                WRITE_BIT: begin
                    phase<=phase+1'b1;
                    case(phase)
                        0: begin scl_o<=0;sda_drive_low_o<=!tx[bit_index];end
                        1: scl_o<=1;
                        3: begin
                            scl_o<=0;
                            if(bit_index==0) state<=WRITE_ACK;
                            else bit_index<=bit_index-1'b1;
                        end
                    endcase
                end
                WRITE_ACK: begin
                    phase<=phase+1'b1;
                    case(phase)
                        0: begin scl_o<=0;sda_drive_low_o<=0;end
                        1: scl_o<=1;
                        2: if(sda_sync&&nack_count_o!=255) nack_count_o<=nack_count_o+1'b1;
                        3: begin
                            scl_o<=0;bit_index<=7;
                            case(byte_index)
                                0: begin byte_index<=1;tx<=8'h38;state<=WRITE_BIT;end
                                1: begin byte_index<=2;tx<=8'h08+register_index;state<=WRITE_BIT;end
                                2: state<=STOP_A;
                                3: begin rx<=0;state<=READ_BIT;end
                            endcase
                        end
                    endcase
                end
                READ_BIT: begin
                    phase<=phase+1'b1;
                    case(phase)
                        0: begin scl_o<=0;sda_drive_low_o<=0;end
                        1: scl_o<=1;
                        2: rx<={rx[6:0],sda_sync};
                        3: begin
                            scl_o<=0;
                            if(bit_index==0) state<=READ_NACK;
                            else bit_index<=bit_index-1'b1;
                        end
                    endcase
                end
                READ_NACK: begin
                    phase<=phase+1'b1;
                    sda_drive_low_o<=0;
                    if(phase==1) scl_o<=1;
                    if(phase==3) begin scl_o<=0;state<=STOP_A;end
                end
                STOP_A: begin scl_o<=0;sda_drive_low_o<=1;state<=STOP_B;end
                STOP_B: begin scl_o<=1;sda_drive_low_o<=1;state<=STOP_C;end
                STOP_C: begin
                    scl_o<=1;sda_drive_low_o<=0;
                    if(byte_index==2) begin byte_index<=3;tx<=8'h79;state<=START_A;end
                    else begin
                        case(register_index)
                            0: image_width_o[15:8]<=rx;
                            1: image_width_o[7:0]<=rx;
                            2: image_height_o[15:8]<=rx;
                            3: image_height_o[7:0]<=rx;
                        endcase
                        register_index<=register_index+1'b1;gap<=1000;state<=WAIT;
                    end
                end
                default: state<=WAIT;
            endcase
        end
    end
endmodule
