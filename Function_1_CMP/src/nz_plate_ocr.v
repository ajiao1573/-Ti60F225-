`ifndef NZ_PLATE_OCR_V
`define NZ_PLATE_OCR_V
// Sequential per-glyph matching. Only character templates are stored; plate
// numbers are assembled from six independent matches under LLDDDD/LLLDDD.
module nz_plate_ocr #(parameter MAX_ERROR=145,MIN_MARGIN=5)(
 input clk,rst_n,input glyph_valid,input [3:0] glyph_char,
 input [4:0] glyph_x,glyph_y,input glyph_bit,input start,
 output reg busy,done,valid,output reg [47:0] ascii
);
 `include "src/nz_ocr_template_config.vh"
 localparam TW=($clog2(NZ_TEMPLATE_COUNT)<1 ? 1 : $clog2(NZ_TEMPLATE_COUNT));
 localparam IDLE=0,INIT=1,READ=2,ACC=3,SAVE=4,FINISH=5;
 reg [2:0] state,char_index;
 reg [4:0] row_index;
 reg [TW-1:0] template_index;
 reg [19:0] template_rows[0:NZ_TEMPLATE_COUNT*32-1];
 reg [7:0] template_codes[0:NZ_TEMPLATE_COUNT-1];
 reg [19:0] glyph_rows[0:191];
 reg [19:0] row_shift,template_q,glyph_q;
 reg [7:0] code_q;
 initial begin
  $readmemh("src/nz_ocr_rows.hex",template_rows);
  $readmemh("src/nz_ocr_codes.hex",template_codes);
 end
 always @(posedge clk) begin
  if(glyph_valid && glyph_char<6) begin
   row_shift<={row_shift[18:0],glyph_bit};
   if(glyph_x==19) glyph_rows[{glyph_char[2:0],glyph_y}]<={row_shift[18:0],glyph_bit};
  end
  if(state==READ) begin
   template_q<=template_rows[{template_index,row_index}];
   glyph_q<=glyph_rows[{char_index,row_index}];code_q<=template_codes[template_index];
  end
 end
 function [2:0] pop5;
  input [4:0] v;
  begin pop5={2'd0,v[0]}+{2'd0,v[1]}+{2'd0,v[2]}+{2'd0,v[3]}+{2'd0,v[4]};end
 endfunction
 function [4:0] pop20;
  input [19:0] v;
  begin pop20=({2'd0,pop5(v[4:0])}+{2'd0,pop5(v[9:5])})+
              ({2'd0,pop5(v[14:10])}+{2'd0,pop5(v[19:15])});end
 endfunction
 reg [9:0] error,best_letter,best_digit,second_letter,second_digit;
 reg [7:0] letter_code,digit_code;
 // Flat score banks avoid Efinity small multi-read RAM flattening bugs.
 reg [59:0] letter_error,digit_error,letter_margin,digit_margin;
 reg [47:0] letters,digits;
 wire [9:0] trial_error=error+{5'd0,pop20(template_q^glyph_q)};
 wire is_letter=code_q>=65 && code_q<=90;
 reg [47:0] selected_ascii;
 reg selected_valid,select_digit;
 reg [9:0] selected_error,other_error,selected_margin;
 integer i;
 always @* begin
  selected_ascii=0;selected_valid=1;select_digit=0;
  selected_error=0;other_error=0;selected_margin=0;
  for(i=0;i<6;i=i+1) begin
   select_digit=(i>=3) || (i==2 && digit_error[2*10+:10]<letter_error[2*10+:10]);
   selected_ascii[47-i*8-:8]=select_digit ? digits[i*8+:8] : letters[i*8+:8];
   selected_error=select_digit ? digit_error[i*10+:10] : letter_error[i*10+:10];
   other_error=select_digit ? letter_error[i*10+:10] : digit_error[i*10+:10];
   selected_margin=select_digit ? digit_margin[i*10+:10] : letter_margin[i*10+:10];
   if(selected_error>MAX_ERROR || selected_margin<MIN_MARGIN ||
      {1'b0,selected_error}>{1'b0,other_error}+11'd24) selected_valid=0;
  end
  if((letter_error[2*10+:10]>digit_error[2*10+:10] ? letter_error[2*10+:10]-digit_error[2*10+:10] : digit_error[2*10+:10]-letter_error[2*10+:10])<MIN_MARGIN)
   selected_valid=0;
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   state<=IDLE;busy<=0;done<=0;valid<=0;ascii<=48'h3f3f3f3f3f3f;
   char_index<=0;row_index<=0;template_index<=0;error<=0;
   best_letter<=1023;best_digit<=1023;second_letter<=1023;second_digit<=1023;
   letter_code<=63;digit_code<=63;
  end else begin
   done<=0;
   case(state)
    IDLE:if(start) begin busy<=1;valid<=0;char_index<=0;state<=INIT;end
    INIT:begin
     best_letter<=1023;best_digit<=1023;second_letter<=1023;second_digit<=1023;
     letter_code<=63;digit_code<=63;template_index<=0;row_index<=0;error<=0;state<=READ;
    end
    READ:state<=ACC;
    ACC:begin
     if(row_index==31) begin
      if(is_letter) begin
       if(trial_error<best_letter) begin
        if(code_q!=letter_code) second_letter<=best_letter;
        best_letter<=trial_error;letter_code<=code_q;
       end else if(code_q!=letter_code && trial_error<second_letter) second_letter<=trial_error;
      end else begin
       if(trial_error<best_digit) begin
        if(code_q!=digit_code) second_digit<=best_digit;
        best_digit<=trial_error;digit_code<=code_q;
       end else if(code_q!=digit_code && trial_error<second_digit) second_digit<=trial_error;
      end
      row_index<=0;error<=0;
      if(template_index==NZ_TEMPLATE_COUNT-1) state<=SAVE;
      else begin template_index<=template_index+1'b1;state<=READ;end
     end else begin row_index<=row_index+1'b1;error<=trial_error;state<=READ;end
    end
    SAVE:begin
     letters[char_index*8+:8]<=letter_code;digits[char_index*8+:8]<=digit_code;
     letter_error[char_index*10+:10]<=best_letter;digit_error[char_index*10+:10]<=best_digit;
     letter_margin[char_index*10+:10]<=second_letter-best_letter;digit_margin[char_index*10+:10]<=second_digit-best_digit;
     if(char_index==5) state<=FINISH;
     else begin char_index<=char_index+1'b1;state<=INIT;end
    end
    FINISH:begin
     ascii<=selected_valid ? selected_ascii : 48'h3f3f3f3f3f3f;
     valid<=selected_valid;busy<=0;done<=1;state<=IDLE;
    end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
`endif
