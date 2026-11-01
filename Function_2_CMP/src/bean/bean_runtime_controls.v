`timescale 1ns/1ps
`include "bean/bean_config.vh"
// K1: normal release freezes/resumes; menu tap adds, hold subtracts/repeats.
// K2: release enters menu/selects next field; 1s hold exits the menu.
// Both keys are synchronized/debounced. Overlapping presses are consumed.
module bean_runtime_controls #(
    parameter CLOCK_HZ=74400000,DEBOUNCE_CYCLES=1488000,
    parameter IMAGE_WIDTH=1920,IMAGE_HEIGHT=1080,
    parameter THRESHOLD=112,DARK_OBJECT=1,DEBUG_BINARY=0,
    parameter ROI_X0=96,ROI_Y0=72,ROI_X1=1824,ROI_Y1=1008,
    parameter MIN_AREA=36,MAX_AREA=11250,
    parameter MIN_WIDTH=5,MIN_HEIGHT=5,MAX_WIDTH=240,MAX_HEIGHT=240
)(input clk,rst_n,key1_n_i,key2_n_i,
  output reg [`BEAN_CFG_BITS-1:0] config_o,
  output reg menu_o,output reg [3:0] field_o,output reg [1:0] step_o,
  output reg freeze_toggle_o,freeze_set_o);
    // Shared 10ms enable keeps gesture counters small; no generated clock.
    localparam TICK_CYCLES=CLOCK_HZ<100?1:CLOCK_HZ/100;
    localparam MINUS_DELAY=50,REPEAT_DELAY=12,EXIT_DELAY=100;
    wire tick;
    generate if(TICK_CYCLES<=1) begin assign tick=1'b1;end
    else begin: prescaler
        reg [$clog2(TICK_CYCLES)-1:0] counter;
        assign tick=counter==TICK_CYCLES-1;
        always @(posedge clk or negedge rst_n)
            if(!rst_n) counter<=0;
            else if(tick) counter<=0;
            else counter<=counter+1'b1;
    end endgenerate
    wire press1,release1,held1,press2,release2,held2;
    key_debounce #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) key1(
        .clk(clk),.rst_n(rst_n),.key_n_i(key1_n_i),.press_o(press1),.release_o(release1),.held_o(held1));
    key_debounce #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) key2(
        .clk(clk),.rst_n(rst_n),.key_n_i(key2_n_i),.press_o(press2),.release_o(release2),.held_o(held2));
    localparam KEY1_BITS=$clog2(MINUS_DELAY+1),KEY2_BITS=$clog2(EXIT_DELAY+1);
    reg [KEY1_BITS-1:0] duration1;
    reg [KEY2_BITS-1:0] duration2;
    reg minus_started,key2_exited,overlap;
    wire blocked=overlap || (held1 && held2);
    wire subtract_now=tick && menu_o && held1 && !press1 && !blocked &&
        duration1>=(minus_started?REPEAT_DELAY-1:MINUS_DELAY-1);
    wire add_now=menu_o && release1 && !minus_started && !blocked;
    reg [19:0] old_value,low_limit,high_limit,increment,new_value;
    wire minus=subtract_now;
    always @* begin
        increment=step_o==0?1:step_o==1?8:step_o==2?32:256;
        old_value=0;low_limit=0;high_limit=255;
        case(field_o)
            0: begin old_value={18'b0,config_o[`BC_VIEW]};high_limit=2;end
            1: old_value={12'b0,config_o[`BC_THRESHOLD]};
            2: begin old_value={19'b0,config_o[`BC_DARK]};high_limit=1;end
            3: begin old_value={8'b0,config_o[`BC_X0]};high_limit={8'b0,config_o[`BC_X1]}-2;end
            4: begin old_value={8'b0,config_o[`BC_Y0]};high_limit={8'b0,config_o[`BC_Y1]}-2;end
            5: begin old_value={8'b0,config_o[`BC_X1]};low_limit={8'b0,config_o[`BC_X0]}+2;high_limit=IMAGE_WIDTH;end
            6: begin old_value={8'b0,config_o[`BC_Y1]};low_limit={8'b0,config_o[`BC_Y0]}+2;high_limit=IMAGE_HEIGHT;end
            7: begin old_value=config_o[`BC_MIN_AREA];low_limit=1;high_limit=config_o[`BC_MAX_AREA];end
            8: begin old_value=config_o[`BC_MAX_AREA];low_limit=config_o[`BC_MIN_AREA];high_limit=(IMAGE_WIDTH/2)*(IMAGE_HEIGHT/2);end
            9: begin old_value={8'b0,config_o[`BC_MIN_W]};low_limit=1;high_limit={8'b0,config_o[`BC_MAX_W]};end
            10:begin old_value={8'b0,config_o[`BC_MIN_H]};low_limit=1;high_limit={8'b0,config_o[`BC_MAX_H]};end
            11:begin old_value={8'b0,config_o[`BC_MAX_W]};low_limit={8'b0,config_o[`BC_MIN_W]};high_limit=IMAGE_WIDTH/2;end
            12:begin old_value={8'b0,config_o[`BC_MAX_H]};low_limit={8'b0,config_o[`BC_MIN_H]};high_limit=IMAGE_HEIGHT/2;end
            default:begin old_value={18'b0,step_o};high_limit=3;end
        endcase
        if(field_o==0 || field_o==2 || field_o==13) increment=1;
        if(field_o>=3 && field_o<=6 && increment<2) increment=2;
        if(field_o==0 || field_o==2 || field_o==13) begin
            if(minus) new_value=old_value==0?high_limit:old_value-1'b1;
            else new_value=old_value==high_limit?0:old_value+1'b1;
        end else if(minus) new_value=old_value<low_limit+increment?low_limit:old_value-increment;
        else new_value=old_value+increment>high_limit?high_limit:old_value+increment;
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            config_o<={MAX_HEIGHT[11:0],MAX_WIDTH[11:0],MIN_HEIGHT[11:0],MIN_WIDTH[11:0],
                MAX_AREA[19:0],MIN_AREA[19:0],ROI_Y1[11:0],ROI_X1[11:0],ROI_Y0[11:0],ROI_X0[11:0],
                (DEBUG_BINARY?2'd1:2'd2),DARK_OBJECT[0],THRESHOLD[7:0]};
            duration1<=0;duration2<=0;minus_started<=0;key2_exited<=0;overlap<=0;
            menu_o<=0;field_o<=1;step_o<=0;freeze_toggle_o<=0;freeze_set_o<=0;
        end else begin
            freeze_toggle_o<=0;freeze_set_o<=0;
            if(held1 && held2) overlap<=1;
            else if(!held1 && !held2 && !release1 && !release2) overlap<=0;
            if(press1 || release1) begin duration1<=0;minus_started<=0;end
            else if(tick && held1 && menu_o && !blocked && duration1<MINUS_DELAY) duration1<=duration1+1'b1;
            if(subtract_now) begin minus_started<=1;duration1<=0;end
            if(press2) begin duration2<=0;key2_exited<=0;end
            else if(tick && held2 && duration2<EXIT_DELAY) duration2<=duration2+1'b1;
            if(!blocked) begin
                if(release1 && !menu_o) freeze_toggle_o<=1;
                if(tick && menu_o && held2 && !press2 && duration2>=EXIT_DELAY-1 && !key2_exited) begin
                    menu_o<=0;key2_exited<=1;
                end else if(release2 && !key2_exited) begin
                    if(!menu_o) begin menu_o<=1;freeze_set_o<=1;end
                    else field_o<=field_o==13?0:field_o+1'b1;
                end
                if(add_now || subtract_now) case(field_o)
                    0:config_o[`BC_VIEW]<=new_value[1:0];
                    1:config_o[`BC_THRESHOLD]<=new_value[7:0];
                    2:config_o[`BC_DARK]<=new_value[0];
                    3:config_o[`BC_X0]<=new_value[11:0];
                    4:config_o[`BC_Y0]<=new_value[11:0];
                    5:config_o[`BC_X1]<=new_value[11:0];
                    6:config_o[`BC_Y1]<=new_value[11:0];
                    7:config_o[`BC_MIN_AREA]<=new_value;
                    8:config_o[`BC_MAX_AREA]<=new_value;
                    9:config_o[`BC_MIN_W]<=new_value[11:0];
                    10:config_o[`BC_MIN_H]<=new_value[11:0];
                    11:config_o[`BC_MAX_W]<=new_value[11:0];
                    12:config_o[`BC_MAX_H]<=new_value[11:0];
                    13:step_o<=new_value[1:0];
                endcase
            end
        end
    end
endmodule
