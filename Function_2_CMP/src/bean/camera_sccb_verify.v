`timescale 1ns/1ps
// One-shot STOP-separated OV5640 reads after the configuration writer is idle.
// All four write ACKs and every read address ACK are checked. Each register
// has a bounded retry budget; done is asserted only when every value matches.
module camera_sccb_verify #(
    parameter CLOCK_HZ=96000000, BUS_HZ=50000,
    parameter IMAGE_WIDTH=1920, IMAGE_HEIGHT=1080,
    parameter MAX_RETRIES=3, TIMEOUT_CYCLES=CLOCK_HZ/10
)(input clk,rst_n,enable,input sda_i,
   output reg scl_o,output reg sda_drive_low_o,
   output reg done_o,error_o,
   output reg [7:0] failure_index_o,retry_count_o);
    localparam WAIT=0,START_A=1,START_B=2,START_C=3,
        WRITE_BIT=4,WRITE_ACK=5,READ_BIT=6,READ_NACK=7,
        STOP_A=8,STOP_B=9,STOP_C=10,CHECK=11;
    localparam DIV=CLOCK_HZ/(BUS_HZ*4);
    reg [15:0] divider;
    reg [31:0] watchdog;
    reg [3:0] state;
    reg [1:0] phase,byte_index;
    reg [2:0] bit_index,register_index;
    reg [7:0] tx,rx,attempts;
    reg transaction_bad;
    (* async_reg="true" *) reg sda_meta,sda_sync;
    reg [15:0] address;
    reg [7:0] expected;
    always @* case(register_index)
        0: begin address=16'h300a;expected=8'h56;end
        1: begin address=16'h300b;expected=8'h40;end
        2: begin address=16'h3808;expected=IMAGE_WIDTH>>8;end
        3: begin address=16'h3809;expected=IMAGE_WIDTH & 255;end
        4: begin address=16'h380a;expected=IMAGE_HEIGHT>>8;end
        5: begin address=16'h380b;expected=IMAGE_HEIGHT & 255;end
        default: begin address=16'h4300;expected=8'h61;end
    endcase
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin sda_meta<=1;sda_sync<=1;end
        else begin sda_meta<=sda_i;sda_sync<=sda_meta;end
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            scl_o<=1;sda_drive_low_o<=0;divider<=0;state<=WAIT;
            phase<=0;byte_index<=0;register_index<=0;bit_index<=7;
            tx<=8'h78;rx<=0;done_o<=0;error_o<=0;
            failure_index_o<=0;retry_count_o<=0;attempts<=0;
            transaction_bad<=0;watchdog<=0;
        end else if(!enable || done_o || error_o) begin
            scl_o<=1;sda_drive_low_o<=0;divider<=0;watchdog<=0;
        end else if(watchdog>=TIMEOUT_CYCLES-1) begin
            error_o<=1;failure_index_o<={5'b0,register_index};
            scl_o<=1;sda_drive_low_o<=0;
        end else begin
            watchdog<=watchdog+1'b1;
            if(divider!=DIV-1) divider<=divider+1'b1;
            else begin
                divider<=0;
                case(state)
                    WAIT: if(sda_sync) begin
                        byte_index<=0;tx<=8'h78;transaction_bad<=0;state<=START_A;
                    end
                    START_A: begin scl_o<=1;sda_drive_low_o<=0;state<=START_B;end
                    START_B: begin scl_o<=1;sda_drive_low_o<=1;state<=START_C;end
                    START_C: begin scl_o<=0;phase<=0;bit_index<=7;state<=WRITE_BIT;end
                    WRITE_BIT: begin
                        phase<=phase+1'b1;
                        case(phase)
                            0: begin scl_o<=0;sda_drive_low_o<=!tx[bit_index];end
                            1: scl_o<=1;
                            3: begin scl_o<=0;
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
                            2: if(sda_sync) transaction_bad<=1;
                            3: begin
                                scl_o<=0;bit_index<=7;
                                case(byte_index)
                                    0: begin byte_index<=1;tx<=address[15:8];state<=WRITE_BIT;end
                                    1: begin byte_index<=2;tx<=address[7:0];state<=WRITE_BIT;end
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
                            3: begin scl_o<=0;
                                if(bit_index==0) state<=READ_NACK;
                                else bit_index<=bit_index-1'b1;
                            end
                        endcase
                    end
                    READ_NACK: begin
                        phase<=phase+1'b1;sda_drive_low_o<=0;
                        if(phase==1) scl_o<=1;
                        if(phase==3) begin scl_o<=0;state<=STOP_A;end
                    end
                    STOP_A: begin scl_o<=0;sda_drive_low_o<=1;state<=STOP_B;end
                    STOP_B: begin scl_o<=1;sda_drive_low_o<=1;state<=STOP_C;end
                    STOP_C: begin
                        scl_o<=1;sda_drive_low_o<=0;
                        if(byte_index==2) begin byte_index<=3;tx<=8'h79;state<=START_A;end
                        else state<=CHECK;
                    end
                    CHECK: begin
                        watchdog<=0;
                        if(transaction_bad || rx!=expected) begin
                            if(attempts>=MAX_RETRIES) begin
                                error_o<=1;failure_index_o<={5'b0,register_index};
                            end else begin
                                attempts<=attempts+1'b1;state<=WAIT;
                                if(retry_count_o!=255) retry_count_o<=retry_count_o+1'b1;
                            end
                        end else begin
                            attempts<=0;
                            if(register_index==6) done_o<=1;
                            else begin register_index<=register_index+1'b1;state<=WAIT;end
                        end
                    end
                    default: begin error_o<=1;state<=WAIT;end
                endcase
            end
        end
    end
endmodule
