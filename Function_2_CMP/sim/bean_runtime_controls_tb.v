`timescale 1ns/1ps
`include "bean/bean_config.vh"
module bean_runtime_controls_tb;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,key1_n=1,key2_n=1;
    wire [`BEAN_CFG_BITS-1:0] cfg;
    wire menu,toggle,set_freeze;
    wire [3:0] field;
    wire [1:0] step;
    integer toggles=0,sets=0,i,before_value,before_field;
    reg [`BEAN_CFG_BITS-1:0] saved;
    bean_runtime_controls #(.CLOCK_HZ(100),.DEBOUNCE_CYCLES(3),.IMAGE_WIDTH(64),.IMAGE_HEIGHT(48),
        .ROI_X0(4),.ROI_Y0(4),.ROI_X1(60),.ROI_Y1(44),.MIN_AREA(3),.MAX_AREA(120),
        .MIN_WIDTH(2),.MIN_HEIGHT(2),.MAX_WIDTH(20),.MAX_HEIGHT(20)) dut(
        .clk(clk),.rst_n(rst_n),.key1_n_i(key1_n),.key2_n_i(key2_n),.config_o(cfg),.menu_o(menu),
        .field_o(field),.step_o(step),.freeze_toggle_o(toggle),.freeze_set_o(set_freeze));
    always @(posedge clk) begin
        if(toggle) toggles=toggles+1;
        if(set_freeze) sets=sets+1;
        if(rst_n && (cfg[`BC_X0]>=cfg[`BC_X1] || cfg[`BC_Y0]>=cfg[`BC_Y1] ||
            cfg[`BC_X1]>64 || cfg[`BC_Y1]>48 || cfg[`BC_X0]%2 || cfg[`BC_X1]%2 ||
            cfg[`BC_Y0]%2 || cfg[`BC_Y1]%2 || cfg[`BC_MIN_AREA]>cfg[`BC_MAX_AREA] ||
            cfg[`BC_MIN_W]>cfg[`BC_MAX_W] || cfg[`BC_MIN_H]>cfg[`BC_MAX_H]))
            $fatal(1,"invalid configuration escaped controller");
    end
    task gesture;
        input integer key,cycles;
        begin
            if(key==1) key1_n=0;else key2_n=0;
            repeat(cycles) @(negedge clk);
            if(key==1) key1_n=1;else key2_n=1;
            repeat(12) @(negedge clk);
        end
    endtask
    task select_field;
        input integer target;
        begin while(field!=target) gesture(2,15);end
    endtask
    initial begin
        repeat(5) @(negedge clk);rst_n=1;
        key1_n=0;@(negedge clk);key1_n=1;repeat(12) @(negedge clk);
        key2_n=0;@(negedge clk);key2_n=1;repeat(12) @(negedge clk);
        if(toggles || menu || sets) $fatal(1,"key bounce accepted");
        gesture(1,15);gesture(1,350);
        if(toggles!=2 || menu) $fatal(1,"K1 normal tap/hold must toggle exactly once");
        gesture(2,15);
        if(!menu || sets!=1 || toggles!=2 || field!=1) $fatal(1,"K2 entry/default threshold/freeze");
        gesture(1,15);if(cfg[`BC_THRESHOLD]!=113) $fatal(1,"threshold tap increment");
        gesture(1,55);if(cfg[`BC_THRESHOLD]!=112) $fatal(1,"single long decrement or spurious release addition");
        key1_n=0;repeat(95) @(negedge clk);
        before_value=cfg[`BC_THRESHOLD];
        if(before_value!=108) $fatal(1,"repeat subtract cadence: %0d",before_value);
        key1_n=1;repeat(12) @(negedge clk);
        if(cfg[`BC_THRESHOLD]!=before_value) $fatal(1,"long release generated addition");
        gesture(2,15);if(field!=2 || !menu || sets!=1) $fatal(1,"K2 next field");
        gesture(1,15);if(cfg[`BC_DARK]!=0) $fatal(1,"polarity");
        gesture(2,15);gesture(1,15);if(cfg[`BC_X0]!=6) $fatal(1,"ROI even step");
        for(i=0;i<80;i=i+1) gesture(1,15);
        if(cfg[`BC_X0]!=58) $fatal(1,"ROI upper clamp");
        gesture(1,500);
        if(cfg[`BC_X0]!=0) $fatal(1,"ROI repeat lower clamp");
        select_field(13);gesture(1,15);if(step!=1) $fatal(1,"step selection");
        select_field(1);before_value=cfg[`BC_THRESHOLD];gesture(1,15);
        if(cfg[`BC_THRESHOLD]!=before_value+8) $fatal(1,"step applied to threshold");
        gesture(1,500);if(cfg[`BC_THRESHOLD]!=0) $fatal(1,"threshold lower clamp");
        for(i=0;i<40;i=i+1) gesture(1,15);
        if(cfg[`BC_THRESHOLD]!=255) $fatal(1,"threshold upper clamp");
        select_field(0);gesture(1,15);if(cfg[`BC_VIEW]!=0) $fatal(1,"forward view wrap");
        gesture(1,55);if(cfg[`BC_VIEW]!=2) $fatal(1,"reverse view wrap");
        // Reject overlapping keys through both staggered releases, in either order.
        saved=cfg;before_field=field;
        key1_n=0;repeat(10) @(negedge clk);key2_n=0;repeat(150) @(negedge clk);
        key1_n=1;repeat(20) @(negedge clk);key2_n=1;repeat(12) @(negedge clk);
        if(cfg!=saved || field!=before_field || !menu || toggles!=2 || sets!=1) $fatal(1,"overlap caused an action");
        key2_n=0;repeat(10) @(negedge clk);key1_n=0;repeat(150) @(negedge clk);
        key2_n=1;repeat(20) @(negedge clk);key1_n=1;repeat(12) @(negedge clk);
        if(cfg!=saved || field!=before_field || !menu || toggles!=2) $fatal(1,"reverse overlap caused an action");
        key2_n=0;repeat(110) @(negedge clk);
        if(menu || toggles!=2) $fatal(1,"K2 must exit at 1s without waiting for release");
        repeat(300) @(negedge clk);key2_n=1;repeat(12) @(negedge clk);
        if(menu || sets!=1 || field!=before_field) $fatal(1,"exit release reentered/advanced");
        gesture(1,15);if(toggles!=3) $fatal(1,"K1 resume after exit");
        gesture(2,15);if(!menu || sets!=2 || field!=before_field) $fatal(1,"menu did not remember selection");
        gesture(2,15);if(field!=1) $fatal(1,"field wrap");
        gesture(2,120);gesture(2,350);
        if(!menu || sets!=3 || toggles!=3) $fatal(1,"normal long K2 must enter only once on release");
        $display("PASS dual keys: debounce, K1 freeze/resume, K2 menu/next/1s exit, tap add, hold subtract/repeat/no release add, field/enum wrap, remembered selection, step/clamps and overlapping-key suppression");
        $finish;
    end
    initial begin #2000000;$fatal(1,"controls timeout");end
endmodule
