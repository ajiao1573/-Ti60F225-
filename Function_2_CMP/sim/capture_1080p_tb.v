`timescale 1ns/1ps
module capture_1080p_tb;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0,vs=0,href=0;
    reg [7:0] data=0;
    wire ovs,ohref,ode;
    wire [7:0] out_data;
    Sensor_Image_XYCrop #(.IMAGE_HSIZE_SOURCE(3840),.IMAGE_VSIZE_SOURCE(1080),
        .IMAGE_HSIZE_TARGET(3840),.IMAGE_YSIZE_TARGET(1080),.PIXEL_DATA_WIDTH(8)) dut(
        .clk(clk),.rst_n(rst_n),.image_in_vsync(vs),.image_in_href(href),.image_in_de(href),.image_in_data(data),
        .image_out_vsync(ovs),.image_out_href(ohref),.image_out_de(ode),.image_out_data(out_data));
    integer x,y,received=0;
    always @(posedge clk) begin
        #1;
        if(rst_n && ohref && ode) begin
            if(out_data !== received[7:0]) $fatal(1,"1080p crop byte mismatch %0d",received);
            received=received+1;
        end
    end
    initial begin
        repeat(5) @(negedge clk);rst_n=1;
        repeat(5) @(negedge clk);vs=1;
        for(y=0;y<1080;y=y+1) begin
            for(x=0;x<3840;x=x+1) begin
                href=1;data=(y*3840+x)%256;@(negedge clk);
            end
            href=0;repeat(64) @(negedge clk);
        end
        vs=0;repeat(5) @(negedge clk);
        if(received!=4147200) $fatal(1,"native byte count %0d",received);
        $display("PASS 1080p DVP crop: all 4147200 RGB565 bytes, 3840-byte lines, last row/column preserved");
        $finish;
    end
endmodule
