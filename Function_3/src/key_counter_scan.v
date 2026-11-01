`timescale 1ns/1ns

// Active-low debounce, short-release events and one long-press event per hold.
// Chords are suppressed until all keys are released. A long press never also
// reports a short-release event. LONG_PRESS_CYCLES follows the input clock.
module key_counter_scan #(
    parameter KEY_WIDTH = 2,
    parameter integer DELAY_TOP = 1_000_000,
    parameter integer LONG_PRESS_CYCLES = 100_000_000
)(
    input                       clk,
    input                       rst_n,
    input      [KEY_WIDTH-1:0]  key_data,
    output reg                  key_flag,
    output reg [KEY_WIDTH-1:0]  key_value,
    output reg                  long_flag,
    output reg [KEY_WIDTH-1:0]  long_value
);

reg [KEY_WIDTH-1:0] key_sync_0;
reg [KEY_WIDTH-1:0] key_sync_1;
reg [KEY_WIDTH-1:0] key_stable;
reg [KEY_WIDTH-1:0] pressed_keys;
reg [19:0]          delay_cnt;
reg [KEY_WIDTH-1:0] debounce_candidate;
localparam HOLD_WIDTH=($clog2(LONG_PRESS_CYCLES+1)<1)?1:$clog2(LONG_PRESS_CYCLES+1);
reg [HOLD_WIDTH-1:0] hold_count;
reg long_sent,chord;
wire [KEY_WIDTH-1:0] gesture_keys=pressed_keys | ~key_sync_1;
wire gesture_is_chord=(gesture_keys & (gesture_keys-1'b1))!=0;
wire stable_change=(key_sync_1!=key_stable) &&
                   (key_sync_1==debounce_candidate) && (delay_cnt==DELAY_TOP-1);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        key_sync_0 <= {KEY_WIDTH{1'b1}};
        key_sync_1 <= {KEY_WIDTH{1'b1}};
    end else begin
        key_sync_0 <= key_data;
        key_sync_1 <= key_sync_0;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        delay_cnt <= 20'd0;
        key_stable <= {KEY_WIDTH{1'b1}};
        debounce_candidate <= {KEY_WIDTH{1'b1}};
    end else if(key_sync_1!=debounce_candidate) begin
        debounce_candidate<=key_sync_1;
        delay_cnt<=20'd0;
    end else if (key_sync_1 != key_stable) begin
        if (stable_change) begin
            key_stable <= key_sync_1;
            delay_cnt <= 20'd0;
        end else begin
            delay_cnt <= delay_cnt + 1'b1;
        end
    end else begin
        delay_cnt <= 20'd0;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pressed_keys <= {KEY_WIDTH{1'b0}};
        key_value <= {KEY_WIDTH{1'b0}};
        key_flag <= 1'b0;
        long_flag<=0;long_value<=0;hold_count<=0;long_sent<=0;chord<=0;
    end else begin
        key_flag <= 1'b0;
        long_flag<=0;
        // Act on the same cycle on which a new debounced state is accepted.
        if (stable_change) begin
            hold_count<=0;
            if (key_sync_1 == {KEY_WIDTH{1'b1}}) begin
                if (pressed_keys != {KEY_WIDTH{1'b0}} && !long_sent && !chord) begin
                    key_value <= pressed_keys;
                    key_flag <= 1'b1;
                end
                pressed_keys <= {KEY_WIDTH{1'b0}};
                long_sent<=0;chord<=0;
            end else begin
                pressed_keys <= gesture_keys;
                if(gesture_is_chord) chord<=1;
            end
        end else if(key_stable!={KEY_WIDTH{1'b1}} &&
                    key_sync_1==key_stable && !chord && !long_sent) begin
            // Fire only AFTER one full second of the debounced held state.
            if(hold_count==LONG_PRESS_CYCLES) begin
                long_flag<=1;long_value<=pressed_keys;long_sent<=1;
            end else hold_count<=hold_count+1'b1;
        end
    end
end

endmodule
