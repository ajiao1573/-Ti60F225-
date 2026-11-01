`timescale 1ns/1ps
// Continuous raster window. LINE_TOTAL includes horizontal blanking.
// Synchronous RAM reads; RGB, coordinates and sync travel with the CENTER
// pixel, never with the bottom/right corner of the spatial window.
module bean_window #(
    parameter K=3, BITS=1, META_BITS=51, LINE_TOTAL=1650
)(
    input clk, input rst_n,
    input [BITS-1:0] data_i, input [META_BITS-1:0] meta_i,
    output reg [K*K*BITS-1:0] window_o,
    output [META_BITS-1:0] meta_o
);
    localparam DELAY=(K/2)*LINE_TOTAL+K/2+1;
    wire [BITS-1:0] q[0:K-1];
    reg [BITS-1:0] current_pixel;
    assign q[0]=current_pixel;
    reg [BITS-1:0] left[0:K*(K-1)-1];
    wire [META_BITS-1:0] meta_q;
    integer column, column_d, meta_ptr, warm;
    integer r,c;
    genvar line;
    generate for(line=0;line<K-1;line=line+1) begin: line_ram
        bean_banked_ram #(.WIDTH(BITS),.DEPTH(LINE_TOTAL)) row_storage(
            .clk(clk),.read_en(rst_n),.write_en(rst_n),.read_addr(column),
            .write_addr(line==0?column:column_d),.write_data(line==0?data_i:q[line]),
            .read_data(q[line+1]));
    end endgenerate
    bean_banked_ram #(.WIDTH(META_BITS),.DEPTH(DELAY)) metadata_storage(
        .clk(clk),.read_en(rst_n),.write_en(rst_n),.read_addr(meta_ptr),.write_addr(meta_ptr),
        .write_data(meta_i),.read_data(meta_q));
    assign meta_o=(warm==DELAY+1) ? meta_q : {{(META_BITS-3){1'b0}},3'b011};
    always @(posedge clk) begin
        if(rst_n) begin
            current_pixel<=data_i;
            for(r=0;r<K;r=r+1) begin
                left[r*(K-1)]<=q[r];
                for(c=1;c<K-1;c=c+1)
                    left[r*(K-1)+c]<=left[r*(K-1)+c-1];
                for(c=0;c<K;c=c+1) begin
                    if(c==K-1) window_o[(r*K+c)*BITS+:BITS]<=q[r];
                    else window_o[(r*K+c)*BITS+:BITS]<=left[r*(K-1)+K-2-c];
                end
            end
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin column<=0; column_d<=0; meta_ptr<=0; warm<=0; end
        else begin
            column_d<=column;
            column<=(column==LINE_TOTAL-1)?0:column+1;
            meta_ptr<=(meta_ptr==DELAY-1)?0:meta_ptr+1;
            if(warm<DELAY+1) warm<=warm+1;
        end
    end
endmodule
