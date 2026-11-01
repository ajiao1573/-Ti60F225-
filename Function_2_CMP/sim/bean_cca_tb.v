`timescale 1ns/1ps
module bean_cca_tb;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0, frame_start=0, sample_valid=0, sample_mask=0;
    reg [11:0] x=0,y=0;
    wire [15:0] count;
    wire valid,error,busy,done;
    bean_cca #(.WIDTH(32),.HEIGHT(24),.LABEL_BITS(5),
        .MIN_AREA(3),.MAX_AREA(120),.MIN_WIDTH(2),.MIN_HEIGHT(2),
        .MAX_WIDTH(20),.MAX_HEIGHT(20),.ROI_X0(0),.ROI_Y0(0),.ROI_X1(32),.ROI_Y1(24)) dut (
        .clk(clk),.rst_n(rst_n),.frame_start_i(frame_start),.restart_i(1'b0),
        .sample_valid_i(sample_valid),.sample_mask_i(sample_mask),.sample_x_i(x),.sample_y_i(y),
        .count_o(count),.valid_o(valid),.overflow_o(error),.busy_o(busy),.done_o(done));
    integer fd,rc,cases,case_id,expect_count,expect_error,xx,yy,bit_value,cycles;
    reg [15:0] previous_count;
    initial begin
        fd=$fopen("build/sim/cca_vectors.txt","r");
        if (!fd) $fatal(1,"missing vectors");
        repeat(4) @(negedge clk); rst_n=1;
        rc=$fscanf(fd,"%d",cases);
        for(case_id=0;case_id<cases;case_id=case_id+1) begin
            rc=$fscanf(fd,"%d %d",expect_count,expect_error);
            previous_count=count;
            @(negedge clk); frame_start=1;
            @(negedge clk); frame_start=0;
            for(yy=0;yy<24;yy=yy+1) begin
                for(xx=0;xx<32;xx=xx+1) begin
                    rc=$fscanf(fd,"%d",bit_value);
                    if(rc != 1) $fatal(1,"bad vector");
                    @(negedge clk); sample_valid=1; sample_mask=bit_value; x=xx; y=yy;
                    @(negedge clk); sample_valid=0;
                end
            end
            cycles=0;
            while(!done && cycles<100000) begin
                @(negedge clk); cycles=cycles+1;
                // A new display frame during processing must not interrupt CCA.
                frame_start=(cycles%1000 == 0);
            end
            frame_start=0;
            if(!done) $fatal(1,"CCA timeout case %0d state %0d",case_id,dut.state);
            if(error !== expect_error[0] || valid !== !expect_error[0])
                $fatal(1,"flags case %0d count=%0d valid=%b error=%b expected_error=%0d",case_id,count,valid,error,expect_error);
            if(!expect_error && count !== expect_count)
                $fatal(1,"count case %0d got %0d expected %0d",case_id,count,expect_count);
            if(expect_error && count !== previous_count)
                $fatal(1,"overflow must hold previous count");
            $display("PASS CCA case %0d count=%0d error=%b cycles=%0d",case_id,count,error,cycles);
            repeat(3) @(negedge clk);
        end
        // Incomplete capture must not publish a partial count.
        frame_start=1; @(negedge clk); frame_start=0;
        sample_valid=1; x=0; y=0; sample_mask=1;
        @(negedge clk); sample_valid=0;
        frame_start=1; @(negedge clk); frame_start=0;
        repeat(2) @(negedge clk);
        if(valid || !error) $fatal(1,"incomplete frame accepted");
        // Asynchronous reset during capture, then a successful fresh frame.
        rst_n=0; repeat(2) @(negedge clk); rst_n=1;
        frame_start=1; @(negedge clk); frame_start=0;
        for(yy=0;yy<24;yy=yy+1) for(xx=0;xx<32;xx=xx+1) begin
            sample_valid=1; sample_mask=0; x=xx; y=yy;
            @(negedge clk); sample_valid=0; @(negedge clk);
        end
        cycles=0;
        while(!done && cycles<100000) begin @(negedge clk); cycles=cycles+1; end
        if(!done || !valid || error || count!=0) $fatal(1,"reset recovery failed");
        $display("PASS CCA regression, incomplete-frame rejection and reset recovery");
        $finish;
    end
    initial begin #200000000; $fatal(1,"global timeout"); end
endmodule
