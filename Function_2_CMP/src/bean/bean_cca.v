`timescale 1ns/1ps
`include "bean/bean_config.vh"
// Buffered 8-connected component analysis, no input backpressure required.
// Capture one complete mask, skip frames while busy, publish only at the end.
// Parents always decrease on union. A descending reduction therefore merges
// every provisional component into its final root without a second pixel pass.
module bean_cca #(
    parameter RUNTIME_ENABLE=0,
    parameter WIDTH = 640, HEIGHT = 360,
    parameter LABEL_BITS = 10,
    parameter MIN_AREA = 16, MAX_AREA = 5000,
    parameter MIN_WIDTH = 3, MIN_HEIGHT = 3,
    parameter MAX_WIDTH = 160, MAX_HEIGHT = 160,
    parameter ROI_X0 = 32, ROI_Y0 = 24,
    parameter ROI_X1 = 608, ROI_Y1 = 336,
    parameter REJECT_BORDER = 1, BORDER_GUARD = 0
)(
    input [`BEAN_CFG_BITS-1:0] config_i,
    input clk, input rst_n, input frame_start_i, input restart_i,
    input sample_valid_i, input sample_mask_i,
    input [11:0] sample_x_i, input [11:0] sample_y_i,
    output reg [15:0] count_o,
    output reg valid_o, output reg overflow_o,
    output busy_o, output reg done_o,
    output reg object_valid_o,output reg [11:0] object_xmin_o,object_xmax_o,object_ymin_o,object_ymax_o
);
    wire [11:0] cfg_roi_x0=RUNTIME_ENABLE ? (config_i[`BC_X0]>>1) : ROI_X0;
    wire [11:0] cfg_roi_y0=RUNTIME_ENABLE ? (config_i[`BC_Y0]>>1) : ROI_Y0;
    wire [11:0] cfg_roi_x1=RUNTIME_ENABLE ? (config_i[`BC_X1]>>1) : ROI_X1;
    wire [11:0] cfg_roi_y1=RUNTIME_ENABLE ? (config_i[`BC_Y1]>>1) : ROI_Y1;
    wire [19:0] cfg_min_area=RUNTIME_ENABLE ? config_i[`BC_MIN_AREA] : MIN_AREA;
    wire [19:0] cfg_max_area=RUNTIME_ENABLE ? config_i[`BC_MAX_AREA] : MAX_AREA;
    wire [11:0] cfg_min_width=RUNTIME_ENABLE ? config_i[`BC_MIN_W] : MIN_WIDTH;
    wire [11:0] cfg_min_height=RUNTIME_ENABLE ? config_i[`BC_MIN_H] : MIN_HEIGHT;
    wire [11:0] cfg_max_width=RUNTIME_ENABLE ? config_i[`BC_MAX_W] : MAX_WIDTH;
    wire [11:0] cfg_max_height=RUNTIME_ENABLE ? config_i[`BC_MAX_H] : MAX_HEIGHT;
    localparam MAX_LABEL = (1 << LABEL_BITS)-1;
    localparam IDLE=0, CAPTURE=1, CLEAR_LINE=2, PIX_READ=3, PIX_WAIT=4,
        RIGHT_READ=5, RIGHT_WAIT=6, ROOT_START=7, ROOT_READ=8, ROOT_WAIT=9,
        CHOOSE=10, NEW_LABEL=11, NEW_STATS=12, UNION=13,
        STAT_READ=14, STAT_WAIT=15, STAT_WRITE=16, STORE=17,
        STORE_BG=18, ADVANCE=19, FINAL_READ=20, FINAL_WAIT=21,
        MERGE_READ=22, MERGE_WAIT=23, MERGE_WRITE=24, FINAL_NEXT=25,
        PUBLISH=26, FAIL=27;
    reg [4:0] state;
    assign busy_o = state != IDLE;
    reg mask_mem [0:WIDTH*HEIGHT-1];
    reg [LABEL_BITS-1:0] line_mem [0:WIDTH-1];
    reg [LABEL_BITS-1:0] parent_mem [0:MAX_LABEL];
    // {touch_border, area[19:0], xmin[11:0], xmax, ymin, ymax}
    reg [68:0] stats_mem [0:MAX_LABEL];
    reg mask_q;
    reg [LABEL_BITS-1:0] line_q, parent_q;
    reg [68:0] stats_q;
    reg mask_we, line_we, parent_we, stats_we;
    reg [19:0] mask_ra, mask_wa;
    reg [11:0] line_ra, line_wa;
    reg [LABEL_BITS-1:0] parent_ra, parent_wa, stats_ra, stats_wa;
    reg mask_wd;
    reg [LABEL_BITS-1:0] line_wd, parent_wd;
    reg [68:0] stats_wd;
    // Synchronous reads and unreset RAM arrays for synthesis.
    always @(posedge clk) begin
        mask_q <= mask_mem[mask_ra];
        line_q <= line_mem[line_ra];
        parent_q <= parent_mem[parent_ra];
        stats_q <= stats_mem[stats_ra];
        if (mask_we) mask_mem[mask_wa] <= mask_wd;
        if (line_we) line_mem[line_wa] <= line_wd;
        if (parent_we) parent_mem[parent_wa] <= parent_wd;
        if (stats_we) stats_mem[stats_wa] <= stats_wd;
    end
    reg [11:0] x, y, clear_x;
    reg [19:0] address;
    reg [LABEL_BITS:0] next_label;
    reg [LABEL_BITS-1:0] left_label, old_up_left, old_up;
    reg [LABEL_BITS-1:0] n0,n1,n2,n3, r0,r1,r2,r3;
    reg [1:0] neighbor;
    reg [LABEL_BITS-1:0] cursor, minimum, chosen, final_index, final_parent;
    reg pixel_mask;
    reg [68:0] pixel_stats, child_stats, parent_stats;
    reg [15:0] count_acc;
    reg [19:0] capture_next;
    wire [31:0] capture_address_full = sample_y_i * WIDTH + sample_x_i;
    wire [19:0] capture_address = capture_address_full[19:0];
    wire [LABEL_BITS:0] last_label = next_label - 1'b1;
    wire [LABEL_BITS-1:0] current_neighbor = neighbor == 0 ? n0 :
        neighbor == 1 ? n1 : neighbor == 2 ? n2 : n3;
    wire [LABEL_BITS-1:0] current_root = neighbor == 0 ? r0 :
        neighbor == 1 ? r1 : neighbor == 2 ? r2 : r3;
    wire touches_border = x <= cfg_roi_x0+BORDER_GUARD || x >= cfg_roi_x1-1-BORDER_GUARD ||
                          y <= cfg_roi_y0+BORDER_GUARD || y >= cfg_roi_y1-1-BORDER_GUARD;
    wire [12:0] box_width = {1'b0,stats_q[35:24]} - {1'b0,stats_q[47:36]} + 13'd1;
    wire [12:0] box_height = {1'b0,stats_q[11:0]} - {1'b0,stats_q[23:12]} + 13'd1;
    wire accepted = stats_q[67:48] >= cfg_min_area && stats_q[67:48] <= cfg_max_area &&
        box_width >= cfg_min_width && box_width <= cfg_max_width &&
        box_height >= cfg_min_height && box_height <= cfg_max_height &&
        (!REJECT_BORDER || !stats_q[68]);
    function [68:0] add_pixel;
        input [68:0] s;
        input [11:0] px,py;
        input border;
        begin
            add_pixel = {s[68] | border, s[67:48] + 20'd1,
                (px < s[47:36] ? px : s[47:36]),
                (px > s[35:24] ? px : s[35:24]),
                (py < s[23:12] ? py : s[23:12]),
                (py > s[11:0] ? py : s[11:0])};
        end
    endfunction
    function [68:0] merge_stats;
        input [68:0] a,b;
        begin
            merge_stats = {a[68] | b[68], a[67:48] + b[67:48],
                (a[47:36] < b[47:36] ? a[47:36] : b[47:36]),
                (a[35:24] > b[35:24] ? a[35:24] : b[35:24]),
                (a[23:12] < b[23:12] ? a[23:12] : b[23:12]),
                (a[11:0] > b[11:0] ? a[11:0] : b[11:0])};
        end
    endfunction
    always @* begin
        mask_we=0; mask_ra=address; mask_wa=capture_address; mask_wd=sample_mask_i;
        line_we=0; line_ra=x; line_wa=x; line_wd=chosen;
        parent_we=0; parent_ra=cursor; parent_wa=chosen; parent_wd=chosen;
        stats_we=0; stats_ra=chosen; stats_wa=chosen; stats_wd=0;
        case (state)
            CAPTURE: mask_we = sample_valid_i && capture_address == capture_next &&
                               sample_x_i < WIDTH && sample_y_i < HEIGHT;
            CLEAR_LINE: begin line_we=1; line_wa=clear_x; line_wd=0; end
            RIGHT_READ: line_ra = x == WIDTH-1 ? x : x+12'd1;
            NEW_LABEL: parent_we=1;
            NEW_STATS: begin stats_we=1; stats_wd={touches_border,20'd1,x,x,y,y}; end
            UNION: begin
                parent_we=current_root != 0 && current_root != chosen;
                parent_wa=current_root;
            end
            STAT_WRITE: begin stats_we=1; stats_wd=add_pixel(pixel_stats,x,y,touches_border); end
            STORE: line_we=1;
            STORE_BG: begin line_we=1; line_wd=0; end
            FINAL_READ: begin parent_ra=final_index; stats_ra=final_index; end
            MERGE_READ: stats_ra=final_parent;
            MERGE_WRITE: begin
                stats_we=1; stats_wa=final_parent;
                stats_wd=merge_stats(child_stats,parent_stats);
            end
        endcase
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; count_o<=0; valid_o<=0; overflow_o<=0; done_o<=0;object_valid_o<=0;object_xmin_o<=0;object_xmax_o<=0;object_ymin_o<=0;object_ymax_o<=0;
            x<=0; y<=0; clear_x<=0; address<=0; next_label<=1;
            left_label<=0; old_up_left<=0; old_up<=0;
            n0<=0; n1<=0; n2<=0; n3<=0; r0<=0; r1<=0; r2<=0; r3<=0;
            neighbor<=0; cursor<=0; minimum<=0; chosen<=0;
            final_index<=0; final_parent<=0; pixel_mask<=0;
            pixel_stats<=0; child_stats<=0; parent_stats<=0;
            count_acc<=0; capture_next<=0;
        end else if (restart_i) begin
            // Old live-frame work is invalid after freeze/resume. The next
            // complete capture overwrites RAM, so no RAM reset is required.
            state<=IDLE; count_o<=0; valid_o<=0; overflow_o<=0; done_o<=0;object_valid_o<=0;
        end else begin
            done_o<=0;object_valid_o<=0;
            case (state)
                IDLE: if (frame_start_i) begin capture_next<=0; state<=CAPTURE; end
                CAPTURE: begin
                    if (frame_start_i) state<=FAIL; // missing/incomplete source frame
                    else if (sample_valid_i) begin
                        if (capture_address != capture_next || sample_x_i >= WIDTH || sample_y_i >= HEIGHT)
                            state<=FAIL;
                        else if (capture_next == WIDTH*HEIGHT-1) begin
                            clear_x<=0; next_label<=1; count_acc<=0; state<=CLEAR_LINE;
                        end else capture_next<=capture_next+20'd1;
                    end
                end
                CLEAR_LINE: if (clear_x == WIDTH-1) begin
                    x<=0; y<=0; address<=0; left_label<=0; old_up_left<=0; state<=PIX_READ;
                end else clear_x<=clear_x+12'd1;
                PIX_READ: state<=PIX_WAIT;
                PIX_WAIT: begin
                    pixel_mask<=mask_q; old_up<=line_q;
                    n0<=left_label; n1<=old_up_left; n2<=line_q;
                    state<=RIGHT_READ;
                end
                RIGHT_READ: state<=RIGHT_WAIT;
                RIGHT_WAIT: begin
                    n3<=x == WIDTH-1 ? 0 : line_q;
                    neighbor<=0; minimum<=0; r0<=0; r1<=0; r2<=0; r3<=0;
                    state<=pixel_mask ? ROOT_START : STORE_BG;
                end
                ROOT_START: begin
                    if (current_neighbor == 0) begin
                        if (neighbor == 3) state<=CHOOSE;
                        else neighbor<=neighbor+2'd1;
                    end else begin cursor<=current_neighbor; state<=ROOT_READ; end
                end
                ROOT_READ: state<=ROOT_WAIT;
                ROOT_WAIT: begin
                    if (parent_q == cursor) begin
                        case(neighbor)
                            0:r0<=cursor; 1:r1<=cursor; 2:r2<=cursor; 3:r3<=cursor;
                        endcase
                        if (minimum == 0 || cursor < minimum) minimum<=cursor;
                        if (neighbor == 3) state<=CHOOSE;
                        else begin neighbor<=neighbor+2'd1; state<=ROOT_START; end
                    end else if (parent_q == 0 || parent_q > cursor) state<=FAIL;
                    else begin cursor<=parent_q; state<=ROOT_READ; end
                end
                CHOOSE: begin
                    neighbor<=0;
                    if (minimum == 0) begin
                        if (next_label > MAX_LABEL) state<=FAIL;
                        else begin
                            chosen<=next_label[LABEL_BITS-1:0];
                            next_label<=next_label+1'b1; state<=NEW_LABEL;
                        end
                    end else begin chosen<=minimum; state<=UNION; end
                end
                NEW_LABEL: state<=NEW_STATS;
                NEW_STATS: state<=STORE;
                UNION: if (neighbor == 3) state<=STAT_READ;
                       else neighbor<=neighbor+2'd1;
                STAT_READ: state<=STAT_WAIT;
                STAT_WAIT: begin pixel_stats<=stats_q; state<=STAT_WRITE; end
                STAT_WRITE: state<=STORE;
                STORE: begin left_label<=chosen; old_up_left<=old_up; state<=ADVANCE; end
                STORE_BG: begin left_label<=0; old_up_left<=old_up; state<=ADVANCE; end
                ADVANCE: begin
                    if (x == WIDTH-1 && y == HEIGHT-1) begin
                        final_index<=last_label[LABEL_BITS-1:0];
                        state<=next_label == 1 ? PUBLISH : FINAL_READ;
                    end else begin
                        address<=address+20'd1;
                        if (x == WIDTH-1) begin
                            x<=0; y<=y+12'd1; left_label<=0; old_up_left<=0;
                        end else x<=x+12'd1;
                        state<=PIX_READ;
                    end
                end
                FINAL_READ: state<=FINAL_WAIT;
                FINAL_WAIT: begin
                    if (parent_q == final_index) begin
                        if (accepted) begin
                            count_acc<=count_acc+16'd1;object_valid_o<=1;
                            object_xmin_o<=stats_q[47:36];object_xmax_o<=stats_q[35:24];
                            object_ymin_o<=stats_q[23:12];object_ymax_o<=stats_q[11:0];
                        end
                        state<=FINAL_NEXT;
                    end else if (parent_q == 0 || parent_q > final_index) state<=FAIL;
                    else begin
                        final_parent<=parent_q; child_stats<=stats_q; state<=MERGE_READ;
                    end
                end
                MERGE_READ: state<=MERGE_WAIT;
                MERGE_WAIT: begin parent_stats<=stats_q; state<=MERGE_WRITE; end
                MERGE_WRITE: state<=FINAL_NEXT;
                FINAL_NEXT: if (final_index == 1) state<=PUBLISH;
                            else begin final_index<=final_index-1'b1; state<=FINAL_READ; end
                PUBLISH: begin
                    count_o<=count_acc; valid_o<=1; overflow_o<=0; done_o<=1; state<=IDLE;
                end
                FAIL: begin valid_o<=0; overflow_o<=1; done_o<=1; state<=IDLE; end
                default: state<=IDLE;
            endcase
        end
    end
endmodule
