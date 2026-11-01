`timescale 1ns/1ps
// Same one-cycle, read-before-write contract as a synchronous inferred RAM.
// Wide, non-power-of-two line buffers are split into shallow banks so the
// mapper can select wide RAM10 modes instead of many underused deep slices.
module bean_banked_ram #(
    parameter WIDTH=16,DEPTH=2200,BANK_DEPTH=512
)(
    input clk,input read_en,input write_en,
    input [31:0] read_addr,input [31:0] write_addr,
    input [WIDTH-1:0] write_data,
    output [WIDTH-1:0] read_data
);
    localparam BANKS=(DEPTH+BANK_DEPTH-1)/BANK_DEPTH;
    generate if(WIDTH>=8 && DEPTH>BANK_DEPTH) begin: banked
        localparam BANK_BITS=$clog2(BANKS);
        wire [WIDTH-1:0] bank_q[0:BANKS-1];
        reg [BANK_BITS-1:0] selected_bank;
        always @(posedge clk) if(read_en)
            selected_bank<=read_addr/BANK_DEPTH;
        genvar b;
        for(b=0;b<BANKS;b=b+1) begin: bank
            localparam WORDS=(DEPTH-b*BANK_DEPTH<BANK_DEPTH)?DEPTH-b*BANK_DEPTH:BANK_DEPTH;
            reg [WIDTH-1:0] memory[0:WORDS-1];
            reg [WIDTH-1:0] q;
            always @(posedge clk) begin
                if(read_en && read_addr/BANK_DEPTH==b) q<=memory[read_addr%BANK_DEPTH];
                if(write_en && write_addr/BANK_DEPTH==b) memory[write_addr%BANK_DEPTH]<=write_data;
            end
            assign bank_q[b]=q;
        end
        assign read_data=bank_q[selected_bank];
    end else begin: unbanked
        reg [WIDTH-1:0] memory[0:DEPTH-1];
        reg [WIDTH-1:0] q;
        always @(posedge clk) begin
            if(read_en) q<=memory[read_addr];
            if(write_en) memory[write_addr]<=write_data;
        end
        assign read_data=q;
    end endgenerate
endmodule
