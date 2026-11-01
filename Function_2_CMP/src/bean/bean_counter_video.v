`timescale 1ns/1ps
`include "bean/bean_config.vh"
// All processing is in the existing display pixel clock domain.
module bean_counter_video #(
    parameter RUNTIME_ENABLE=0,OBJECTS_ENABLE=0,MAX_OBJECTS=128,
    parameter IMAGE_WIDTH=1280, IMAGE_HEIGHT=720,
    parameter THRESHOLD=112, DARK_OBJECT=1, DEBUG_BINARY=0,
    parameter ROI_X0=64, ROI_Y0=48, ROI_X1=1216, ROI_Y1=672,
    parameter MIN_AREA=16, MAX_AREA=5000,
    parameter MIN_WIDTH=3, MIN_HEIGHT=3, MAX_WIDTH=160, MAX_HEIGHT=160,
    parameter LABEL_BITS=10, REJECT_BORDER=1,
    parameter CONTOUR_ENABLE=1, LINE_TOTAL=1650, DENOISE_ENABLE=0, DENOISE_SMOOTH=1,
    parameter DENOISE_MEDIAN_SIZE=5
)(
    input [`BEAN_CFG_BITS-1:0] config_i,
    input menu_i,input [3:0] field_i,input [1:0] step_i,
    input clk, input rst_n,
    input [23:0] rgb_i, input de_i, input hs_i, input vs_i,
    input source_error_i,input source_ready_i,
    input frozen_i, // acknowledged DDR reader bank is pinned, pixel domain
    output [23:0] rgb_o, output de_o, output hs_o, output vs_o,
    output [15:0] count_o, output result_valid_o, output overflow_o, output busy_o,
    output [`BEAN_CFG_BITS-1:0] telemetry_config_o,output [15:0] telemetry_boxes_o,output reg [31:0] telemetry_id_o
);
    wire [23:0] source_rgb;
    wire source_de,source_hs,source_vs;
    generate if(DENOISE_ENABLE) begin: denoise_enabled
        wire [23:0] median_rgb;
        wire median_de,median_hs,median_vs;
        if(DENOISE_MEDIAN_SIZE==5) begin: median5_enabled
        bean_rgb_median5 #(.IMAGE_WIDTH(IMAGE_WIDTH),.IMAGE_HEIGHT(IMAGE_HEIGHT),
            .LINE_TOTAL(LINE_TOTAL)) denoise(
            .clk(clk),.rst_n(rst_n),.rgb_i(rgb_i),.de_i(de_i),.hs_i(hs_i),.vs_i(vs_i),
            .rgb_o(median_rgb),.de_o(median_de),.hs_o(median_hs),.vs_o(median_vs));
        end else begin: median3_enabled
        bean_rgb_median #(.IMAGE_WIDTH(IMAGE_WIDTH),.IMAGE_HEIGHT(IMAGE_HEIGHT),
            .LINE_TOTAL(LINE_TOTAL)) denoise(
            .clk(clk),.rst_n(rst_n),.rgb_i(rgb_i),.de_i(de_i),.hs_i(hs_i),.vs_i(vs_i),
            .rgb_o(median_rgb),.de_o(median_de),.hs_o(median_hs),.vs_o(median_vs));
        end
        if(DENOISE_SMOOTH) begin: smooth_enabled
            bean_rgb_smooth #(.IMAGE_WIDTH(IMAGE_WIDTH),.IMAGE_HEIGHT(IMAGE_HEIGHT),
                .LINE_TOTAL(LINE_TOTAL)) smooth(
                .clk(clk),.rst_n(rst_n),.rgb_i(median_rgb),.de_i(median_de),.hs_i(median_hs),.vs_i(median_vs),
                .rgb_o(source_rgb),.de_o(source_de),.hs_o(source_hs),.vs_o(source_vs));
        end else begin: smooth_disabled
            assign {source_rgb,source_de,source_hs,source_vs}={median_rgb,median_de,median_hs,median_vs};
        end
    end else begin: denoise_disabled
        assign {source_rgb,source_de,source_hs,source_vs}={rgb_i,de_i,hs_i,vs_i};
    end endgenerate
    reg [11:0] x,y;
    reg de_d,vs_d;
    wire frame_start=vs_d && !source_vs;
    localparam [`BEAN_CFG_BITS-1:0] DEFAULT_CONFIG={MAX_HEIGHT[11:0],MAX_WIDTH[11:0],MIN_HEIGHT[11:0],MIN_WIDTH[11:0],
        MAX_AREA[19:0],MIN_AREA[19:0],ROI_Y1[11:0],ROI_X1[11:0],ROI_Y0[11:0],ROI_X0[11:0],
        (DEBUG_BINARY?2'd1:2'd2),DARK_OBJECT[0],THRESHOLD[7:0]};
    reg [`BEAN_CFG_BITS-1:0] active_config;
    wire config_change=RUNTIME_ENABLE && frame_start && config_i!=active_config;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) active_config<=DEFAULT_CONFIG;
        else if(config_change) active_config<=config_i;
    end
    // Reconstruct coordinates from the same DE that qualifies rgb_i. This
    // avoids lcd_driver's request-ahead coordinates being one pixel early.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin x<=0; y<=0; de_d<=0; vs_d<=1; end
        else begin
            de_d<=source_de; vs_d<=source_vs;
            if (frame_start) begin x<=0; y<=0; end
            else if (source_de) x<=x+12'd1;
            else begin
                x<=0;
                if (de_d) y<=y+12'd1;
            end
        end
    end
    wire [23:0] pre_rgb;
    wire pre_de,pre_hs,pre_vs;
    wire [11:0] pre_x,pre_y,sample_x,sample_y,filter_x,filter_y;
    wire sample_valid,sample_mask,filter_valid,filter_mask,done;
    reg frozen_d, frozen_count_done;
    reg source_error_d,source_ready_d;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin source_error_d<=0;source_ready_d<=0;end
        else begin source_error_d<=source_error_i;source_ready_d<=source_ready_i;end
    end
    wire restart_analysis = config_change || frozen_i != frozen_d || source_error_d!=source_error_i || source_ready_d!=source_ready_i;
    wire restart_cca=restart_analysis || source_error_i || !source_ready_i;
    wire cca_valid;
    assign result_valid_o=cca_valid && source_ready_i && !source_error_i;
    wire analyze_frame_start = frame_start &&
        (!frozen_i || (!frozen_count_done && !done));
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin frozen_d<=0; frozen_count_done<=0; end
        else begin
            frozen_d<=frozen_i;
            if (restart_cca) frozen_count_done<=0;
            else if (frozen_i && done) frozen_count_done<=1;
        end
    end
    bean_preprocess #(
        .RUNTIME_ENABLE(RUNTIME_ENABLE),
        .THRESHOLD(THRESHOLD),.DARK_OBJECT(DARK_OBJECT),.DEBUG_BINARY(DEBUG_BINARY),
        .ROI_X0(ROI_X0),.ROI_Y0(ROI_Y0),.ROI_X1(ROI_X1),.ROI_Y1(ROI_Y1)
    ) preprocess (
        .config_i(active_config),
        .clk(clk),.rst_n(rst_n),.rgb_i(source_rgb),.de_i(source_de),.hs_i(source_hs),.vs_i(source_vs),
        .x_i(x),.y_i(y),.rgb_o(pre_rgb),.de_o(pre_de),.hs_o(pre_hs),.vs_o(pre_vs),
        .x_o(pre_x),.y_o(pre_y),.sample_valid_o(sample_valid),.sample_mask_o(sample_mask),
        .sample_x_o(sample_x),.sample_y_o(sample_y)
    );
    binary_filter_3x3 #(
        .RUNTIME_ENABLE(RUNTIME_ENABLE),
        .WIDTH(IMAGE_WIDTH/2),.ROI_X0(ROI_X0/2),.ROI_Y0(ROI_Y0/2),
        .ROI_X1(ROI_X1/2),.ROI_Y1(ROI_Y1/2)
    ) filter (
        .config_i(active_config),
        .clk(clk),.rst_n(rst_n),.valid_i(sample_valid),.mask_i(sample_mask),
        .x_i(sample_x),.y_i(sample_y),.valid_o(filter_valid),.mask_o(filter_mask),
        .x_o(filter_x),.y_o(filter_y)
    );
    wire object_valid;
    wire [11:0] object_xmin,object_xmax,object_ymin,object_ymax;
    bean_cca #(
        .RUNTIME_ENABLE(RUNTIME_ENABLE),
        .WIDTH(IMAGE_WIDTH/2),.HEIGHT(IMAGE_HEIGHT/2),.LABEL_BITS(LABEL_BITS),
        .MIN_AREA(MIN_AREA),.MAX_AREA(MAX_AREA),
        .MIN_WIDTH(MIN_WIDTH),.MIN_HEIGHT(MIN_HEIGHT),.MAX_WIDTH(MAX_WIDTH),.MAX_HEIGHT(MAX_HEIGHT),
        .ROI_X0(ROI_X0/2),.ROI_Y0(ROI_Y0/2),.ROI_X1(ROI_X1/2),.ROI_Y1(ROI_Y1/2),
        // Guard the causal filter's shift and its discarded leading columns.
        .REJECT_BORDER(REJECT_BORDER),.BORDER_GUARD(2)
    ) cca (
        .config_i(active_config),
        .clk(clk),.rst_n(rst_n),.frame_start_i(analyze_frame_start),.restart_i(restart_cca),
        .sample_valid_i(filter_valid),.sample_mask_i(filter_mask),.sample_x_i(filter_x),.sample_y_i(filter_y),
        .count_o(count_o),.valid_o(cca_valid),.overflow_o(overflow_o),.busy_o(busy_o),.done_o(done),.object_valid_o(object_valid),
        .object_xmin_o(object_xmin),.object_xmax_o(object_xmax),.object_ymin_o(object_ymin),.object_ymax_o(object_ymax)
    );
    wire [23:0] contour_rgb;
    wire contour_de,contour_hs,contour_vs;
    wire [11:0] contour_x,contour_y;
    generate if(CONTOUR_ENABLE && !DEBUG_BINARY) begin: contour_enabled
        bean_contour #(.RUNTIME_ENABLE(RUNTIME_ENABLE),.LINE_TOTAL(LINE_TOTAL),.THRESHOLD(THRESHOLD),.DARK_OBJECT(DARK_OBJECT),
            .INPUT_DENOISED(DENOISE_ENABLE),
            .ROI_X0(ROI_X0),.ROI_Y0(ROI_Y0),.ROI_X1(ROI_X1),.ROI_Y1(ROI_Y1)) contour (
            .config_i(active_config),
            .clk(clk),.rst_n(rst_n),.rgb_i(pre_rgb),.de_i(pre_de),.hs_i(pre_hs),.vs_i(pre_vs),
            .x_i(pre_x),.y_i(pre_y),.rgb_o(contour_rgb),.de_o(contour_de),
            .hs_o(contour_hs),.vs_o(contour_vs),.x_o(contour_x),.y_o(contour_y));
    end else begin: contour_disabled
        assign contour_rgb=pre_rgb;
        assign {contour_x,contour_y,contour_de,contour_hs,contour_vs}=
            {pre_x,pre_y,pre_de,pre_hs,pre_vs};
    end endgenerate
    wire [23:0] annotated_rgb;
    wire annotated_de,annotated_hs,annotated_vs,display_ready,box_limit;
    wire [11:0] annotated_x,annotated_y;
    wire [15:0] boxes_visible;
    generate if(OBJECTS_ENABLE) begin: objects_enabled
        bean_objects #(.MAX_OBJECTS(MAX_OBJECTS),.IMAGE_WIDTH(IMAGE_WIDTH),.IMAGE_HEIGHT(IMAGE_HEIGHT)) objects(
            .clk(clk),.rst_n(rst_n),.restart_i(restart_cca),.frozen_i(frozen_i),
            .done_i(done),.valid_i(result_valid_o),.display_ready_i(display_ready),.view_i(active_config[`BC_VIEW]),
            .object_valid_i(object_valid),.xmin_i(object_xmin),.xmax_i(object_xmax),.ymin_i(object_ymin),.ymax_i(object_ymax),
            .rgb_i(contour_rgb),.de_i(contour_de),.hs_i(contour_hs),.vs_i(contour_vs),.x_i(contour_x),.y_i(contour_y),
            .rgb_o(annotated_rgb),.de_o(annotated_de),.hs_o(annotated_hs),.vs_o(annotated_vs),.x_o(annotated_x),.y_o(annotated_y),
            .limit_o(box_limit),.visible_count_o(boxes_visible));
    end else begin: objects_disabled
        assign {annotated_rgb,annotated_de,annotated_hs,annotated_vs,annotated_x,annotated_y}=
            {contour_rgb,contour_de,contour_hs,contour_vs,contour_x,contour_y};
        assign box_limit=0;assign boxes_visible=0;
    end endgenerate
    assign telemetry_config_o=active_config;
    assign telemetry_boxes_o=boxes_visible;
    always @(posedge clk or negedge rst_n)
      if(!rst_n)telemetry_id_o<=0;
      else if(done && result_valid_o && !overflow_o)telemetry_id_o<=telemetry_id_o+1'b1;
    bean_osd #(.RUNTIME_ENABLE(RUNTIME_ENABLE),.ROI_X0(ROI_X0),.ROI_Y0(ROI_Y0),.ROI_X1(ROI_X1),.ROI_Y1(ROI_Y1)) osd (
        .config_i(active_config),.menu_i(menu_i),.field_i(field_i),.step_i(step_i),.box_limit_i(box_limit),
        .display_ready_o(display_ready),
        .clk(clk),.rst_n(rst_n),.rgb_i(annotated_rgb),.de_i(annotated_de),.hs_i(annotated_hs),.vs_i(annotated_vs),
        .x_i(annotated_x),.y_i(annotated_y),.count_i(count_o),.result_valid_i(result_valid_o),
        .error_i(overflow_o || source_error_i),.busy_i(busy_o),.done_i(done),
        .frozen_i(frozen_i && frozen_count_done),.invalidate_i(restart_analysis),
        .rgb_o(rgb_o),.de_o(de_o),.hs_o(hs_o),.vs_o(vs_o)
    );
endmodule
