`timescale 1ns/1ps
// VF core K1: external 10k pull-up to VCCIO1A, switch to GND. One pulse per stable press.
module key_debounce #(
    parameter DEBOUNCE_CYCLES = 1488000 // 20 ms at the actual 74.4 MHz pixel PLL
)(
    input clk, input rst_n, input key_n_i,
    output reg press_o,output reg release_o,output held_o
);
    (* async_reg = "true" *) reg sync_meta, sync_key;
    reg stable_key;
    localparam COUNTER_BITS=DEBOUNCE_CYCLES<=1?1:$clog2(DEBOUNCE_CYCLES);
    reg [COUNTER_BITS-1:0] counter;
    assign held_o=~stable_key;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin sync_meta<=1; sync_key<=1; end
        else begin sync_meta<=key_n_i; sync_key<=sync_meta; end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin stable_key<=1; counter<=0; press_o<=0;release_o<=0; end
        else begin
            press_o<=0;release_o<=0;
            if (sync_key == stable_key) counter<=0;
            else if (counter == DEBOUNCE_CYCLES-1) begin
                counter<=0; stable_key<=sync_key;
                if (!sync_key) press_o<=1;
                else release_o<=1;
            end else counter<=counter+1'b1;
        end
    end
endmodule
