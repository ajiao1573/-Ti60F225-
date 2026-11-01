`timescale 1ns/1ps
module bean_objects_tb;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,restart=0,frozen=1,done=0,valid=1,display_ready=0,object_valid=0;
    reg [1:0] view=2;
    reg [11:0] xmin=0,xmax=0,ymin=0,ymax=0,x=0,y=0;
    reg vs=1,de=0;
    wire [23:0] rgb;
    wire [15:0] visible;
    wire limit;
    bean_objects #(.MAX_OBJECTS(128)) dut(
        .clk(clk),.rst_n(rst_n),.restart_i(restart),.frozen_i(frozen),.done_i(done),.valid_i(valid),
        .display_ready_i(display_ready),.view_i(view),.object_valid_i(object_valid),
        .xmin_i(xmin),.xmax_i(xmax),.ymin_i(ymin),.ymax_i(ymax),
        .rgb_i(24'h123456),.de_i(de),.hs_i(1'b1),.vs_i(vs),.x_i(x),.y_i(y),
        .rgb_o(rgb),.de_o(),.hs_o(),.vs_o(),.x_o(),.y_o(),.limit_o(limit),.visible_count_o(visible));
    task frame;
        begin vs=0;repeat(4) @(negedge clk);vs=1;repeat(4) @(negedge clk);end
    endtask
    task pixel;
        input integer px,py;
        input [23:0] expected;
        begin
            x=px;y=py;de=1;repeat(3) @(negedge clk);
            if(rgb!==expected) $fatal(1,"object pixel %0d,%0d got=%h expected=%h",px,py,rgb,expected);
        end
    endtask
    integer i,bx,by;
    initial begin
        repeat(5) @(negedge clk);rst_n=1;
        for(i=0;i<128;i=i+1) begin
            bx=i==127?1880:40+(i%8)*220;
            by=i==127?1040:40+(i/8)*56;
            xmin=bx/2+1;xmax=(bx+40)/2;ymin=by/2+1;ymax=(by+40)/2;
            object_valid=1;@(negedge clk);
        end
        object_valid=0;done=1;@(negedge clk);done=0;
        frame;if(visible || limit) $fatal(1,"boxes appeared before matching count publication");
        display_ready=1;frame;
        if(visible!=128 || limit) $fatal(1,"128-object capacity failed");
        for(i=0;i<128;i=i+1) begin
            bx=i==127?1880:40+(i%8)*220;
            by=i==127?1040:40+(i/8)*56;
            pixel(bx,by,24'h00ff00);pixel(bx+39,by+39,24'h00ff00);
            pixel(bx+1,by+20,24'h00ff00);pixel(bx+2,by+20,24'h123456);
            pixel(bx+15,by+20,24'h123456);
        end
        // IDs 1 and 128 have independently known top-row strokes.
        pixel(44,24,24'h80ff00);pixel(40,24,24'h123456);
        pixel(1884,1024,24'h80ff00);pixel(1894,1024,24'h80ff00);pixel(1906,1024,24'h80ff00);
        xmin=1;xmax=10;ymin=1;ymax=10;object_valid=1;@(negedge clk);object_valid=0;
        done=1;@(negedge clk);done=0;frame;
        if(!limit || visible!=128) $fatal(1,"129th object wrapped or silently disappeared");
        pixel(40,40,24'h00ff00);
        restart=1;@(negedge clk);restart=0;frame;
        if(visible) $fatal(1,"restart retained old boxes");
        object_valid=1;@(negedge clk);object_valid=0;valid=0;done=1;@(negedge clk);done=0;frame;
        if(visible) $fatal(1,"failed result exposed partial boxes");
        frozen=0;frame;if(visible) $fatal(1,"live stale boxes");
        $display("PASS accepted objects: all 128 boxes, IDs 1/128, 2px edges, 1080p last pixel, count-aligned publication, overflow/no-wrap and failure/live invalidation");
        $finish;
    end
    initial begin #1000000;$fatal(1,"objects timeout");end
endmodule
