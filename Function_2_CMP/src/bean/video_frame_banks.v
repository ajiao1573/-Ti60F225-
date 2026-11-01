`timescale 1ns/1ps
// Four DDR frame banks. A frozen reader keeps its bank; the camera continues
// writing the other banks. Both freeze and resume apply only at reader SOF.
module video_frame_banks (
    input clk, input rst_n,
    input write_done_i, input read_start_i,
    input freeze_request_i,
    output reg [1:0] write_bank_o, output reg [1:0] read_bank_o,
    output reg frozen_o
);
    (* async_reg = "true" *) reg freeze_meta, freeze_sync;
    reg [1:0] latest_bank;
    reg have_frame, reader_valid;
    wire [1:0] candidate = write_bank_o+2'd1;
    wire [1:0] next_bank = candidate == read_bank_o ? write_bank_o+2'd2 : candidate;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin freeze_meta<=0; freeze_sync<=0; end
        else begin freeze_meta<=freeze_request_i; freeze_sync<=freeze_meta; end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_bank_o<=0; read_bank_o<=2; latest_bank<=0;
            have_frame<=0; reader_valid<=0; frozen_o<=0;
        end else begin
            if (write_done_i) begin
                latest_bank<=write_bank_o; have_frame<=1;
                write_bank_o<=next_bank;
            end
            if (read_start_i) begin
                // An early press must first select a completed camera frame.
                frozen_o<=freeze_sync && (reader_valid || have_frame || write_done_i);
                if (!(freeze_sync && reader_valid) && (have_frame || write_done_i)) begin
                    read_bank_o<=write_done_i ? write_bank_o : latest_bank;
                    reader_valid<=1;
                end
            end
        end
    end
endmodule
