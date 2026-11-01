`ifndef TI60_CANNY_HYSTERESIS_V
`define TI60_CANNY_HYSTERESIS_V
// Exact 8-connected hysteresis using 64 pixels per block-RAM word.
// The two bit planes are candidate (weak OR strong) and accepted (strong).
// Cached neighborhood propagation plus logarithmic horizontal closure replace
// individual pixel/neighbor reads. Sweeps alternate until no word changes;
// there is NO radius, iteration limit, or connectivity approximation.
module canny_hysteresis #(parameter WIDTH=848,HEIGHT=636, BLOCK_BITS=64)(
 input clk,input rst_n,input in_valid,input in_eop,input [1:0] in_class,
 output busy,output reg out_valid,output reg out_sop,output reg out_eop,
 output reg [7:0] out_data,output reg [31:0] sweep_count
);
 localparam B=BLOCK_BITS;
 localparam WORDS=(WIDTH+B-1)/B,DEPTH=WORDS*HEIGHT;
 localparam AW=($clog2(DEPTH)<1)?1:$clog2(DEPTH);
 localparam XW=($clog2(WORDS)<1)?1:$clog2(WORDS);
 localparam YW=($clog2(HEIGHT)<1)?1:$clog2(HEIGHT);
 localparam PW=($clog2(WIDTH)<1)?1:$clog2(WIDTH);
 localparam [AW-1:0] ROW=WORDS,ONE=1;
 localparam LAST_BITS=WIDTH-(WORDS-1)*B;
 localparam CAPTURE=0,CENTER_REQ=1,CENTER_TEST=2,NEIGH_REQ=3,
            NEIGH_TEST=4,SEED=5,CLOSE=6,COMMIT=7,ADVANCE=8,
            OUT_REQ=9,OUT_LOAD=10,OUT_SEND=11;
 reg [3:0] state;
 // bit i is pixel word_x*B+i; high bits of each row's last word are zero.
 reg [2*B-1:0] map[0:DEPTH-1];
 reg [2*B-1:0] rd_data;
 reg [AW-1:0] write_addr,pos;
 reg [XW-1:0] x;
 reg [YW-1:0] y;
 reg [PW-1:0] capture_x;
 reg [$clog2(B)-1:0] pack_bit,out_bit;
 reg [B-1:0] pack_candidate,pack_strong;
 reg [B-1:0] candidate,original,accepted,output_word;
 reg [B-1:0] left_run,right_run;
 reg [$clog2(B)-1:0] closure_shift;
 reg [3*B-1:0] above,middle,below;
 reg [3:0] neighbor,neighbor_q;
 reg neighbor_valid_q;
 reg reverse,changed,any_weak,any_strong;
 reg neighborhood_cached,fast_neighbors;
 reg [AW-1:0] rd_addr;
 reg neighbor_inside;
 wire [B-1:0] bit_mask={{(B-1){1'b0}},1'b1}<<pack_bit;
 wire [B-1:0] next_candidate=pack_candidate | (in_class!=0 ? bit_mask : {B{1'b0}});
 wire [B-1:0] next_strong=pack_strong | (in_class==2 ? bit_mask : {B{1'b0}});
 wire pack_end=pack_bit==B-1 || capture_x==WIDTH-1;
 wire output_prefetch=state==OUT_SEND && pos!=DEPTH-1 &&
                     (x!=WORDS-1 || LAST_BITS>=2) &&
                     out_bit==(x==WORDS-1 ? LAST_BITS-2 : B-2);
 always @* begin
  rd_addr=pos;neighbor_inside=1;
  if(output_prefetch) rd_addr=pos+ONE;
  else if(state==NEIGH_REQ) begin
   case(neighbor)
    0:begin rd_addr=pos-ROW-ONE;neighbor_inside=x!=0 && y!=0;end
    1:begin rd_addr=pos-ROW;neighbor_inside=y!=0;end
    2:begin rd_addr=pos-ROW+ONE;neighbor_inside=x!=WORDS-1 && y!=0;end
    3:begin rd_addr=pos-ONE;neighbor_inside=x!=0;end
    5:begin rd_addr=pos+ONE;neighbor_inside=x!=WORDS-1;end
    6:begin rd_addr=pos+ROW-ONE;neighbor_inside=x!=0 && y!=HEIGHT-1;end
    7:begin rd_addr=pos+ROW;neighbor_inside=y!=HEIGHT-1;end
    8:begin rd_addr=pos+ROW+ONE;neighbor_inside=x!=WORDS-1 && y!=HEIGHT-1;end
    default:begin rd_addr=pos;neighbor_inside=0;end
   endcase
  end
 end
 wire rd_en=state==CENTER_REQ || state==OUT_REQ || output_prefetch || (state==NEIGH_REQ && neighbor_inside);
 wire capture_write=state==CAPTURE && in_valid && pack_end;
 wire wr_en=capture_write || state==COMMIT;
 wire [AW-1:0] wr_addr=capture_write ? write_addr : pos;
 wire [2*B-1:0] wr_data=capture_write ? {next_candidate,next_strong} : {candidate,accepted};
 always @(posedge clk) begin
  if(rd_en) rd_data<=map[rd_addr];
  if(wr_en) map[wr_addr]<=wr_data;
 end
 wire [B-1:0] seeds=above[2*B-1:B] | above[2*B:B+1] | above[2*B-2:B-1] |
                      below[2*B-1:B] | below[2*B:B+1] | below[2*B-2:B-1] |
                      middle[2*B:B+1] | middle[2*B-2:B-1];
 // Parallel-prefix reachability: shifts 1,2,4,... connect complete candidate
 // runs in log2(B) cycles. Run masks prevent jumping across background gaps.
 // Adjacent-word connectivity still converges through exact full-frame sweeps.
 wire [B-1:0] closure=accepted | (left_run & (accepted<<closure_shift)) |
                                             (right_run & (accepted>>closure_shift));
 assign busy=state!=CAPTURE;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   state<=CAPTURE;write_addr<=0;pos<=0;x<=0;y<=0;capture_x<=0;
   pack_bit<=0;out_bit<=0;pack_candidate<=0;pack_strong<=0;
   candidate<=0;original<=0;accepted<=0;output_word<=0;
   left_run<=0;right_run<=0;closure_shift<=1;
   above<=0;middle<=0;below<=0;neighbor<=0;neighbor_q<=0;neighbor_valid_q<=0;
   reverse<=0;changed<=0;any_weak<=0;any_strong<=0;
   neighborhood_cached<=0;fast_neighbors<=0;
   out_valid<=0;out_sop<=0;out_eop<=0;out_data<=0;sweep_count<=0;
  end else begin
   out_valid<=0;out_sop<=0;out_eop<=0;
   // Issue a different neighbor word each cycle; consume the synchronous
   // RAM result on the next cycle. Invalid neighbors stay zero.
   neighbor_q<=neighbor;
   neighbor_valid_q<=state==NEIGH_REQ && neighbor_inside;
   if(neighbor_valid_q) begin
    case(neighbor_q)
     0:above[B-1:0]<=rd_data[B-1:0];
     1:above[2*B-1:B]<=rd_data[B-1:0];
     2:above[3*B-1:2*B]<=rd_data[B-1:0];
     3:middle[B-1:0]<=rd_data[B-1:0];
     5:middle[3*B-1:2*B]<=rd_data[B-1:0];
     6:below[B-1:0]<=rd_data[B-1:0];
     7:below[2*B-1:B]<=rd_data[B-1:0];
     8:below[3*B-1:2*B]<=rd_data[B-1:0];
    endcase
   end
   case(state)
    CAPTURE:if(in_valid) begin
     if(in_class==1) any_weak<=1;
     if(in_class==2) any_strong<=1;
     if(capture_x==WIDTH-1) capture_x<=0;else capture_x<=capture_x+1'b1;
     if(pack_end) begin
      write_addr<=write_addr+1'b1;pack_bit<=0;pack_candidate<=0;pack_strong<=0;
     end else begin
      pack_bit<=pack_bit+1'b1;pack_candidate<=next_candidate;pack_strong<=next_strong;
     end
     if(in_eop) begin
     write_addr<=0;pos<=0;x<=0;y<=0;reverse<=0;changed<=0;sweep_count<=0;
      neighborhood_cached<=0;
      // No seed or no weak candidate: connectivity is already resolved.
      if((!any_strong && in_class!=2) || (!any_weak && in_class!=1)) state<=OUT_REQ;
      else state<=CENTER_REQ;
      any_weak<=0;any_strong<=0;
     end
    end
    CENTER_REQ:state<=CENTER_TEST;
    CENTER_TEST:begin
     candidate<=rd_data[2*B-1:B];original<=rd_data[B-1:0];
     if((rd_data[2*B-1:B] & ~rd_data[B-1:0])==0) begin
      neighborhood_cached<=0;state<=ADVANCE;
     end
     else begin
      fast_neighbors<=neighborhood_cached;
      if(neighborhood_cached) begin
       // Reuse the two overlapping columns of the previous neighborhood.
       // Its center is the just-committed accepted word, not its old seeds.
       if(reverse) begin
        above<={above[2*B-1:0],{B{1'b0}}};
        below<={below[2*B-1:0],{B{1'b0}}};
        middle<={accepted,rd_data[B-1:0],{B{1'b0}}};neighbor<=0;
       end else begin
        above<={{B{1'b0}},above[3*B-1:B]};
        below<={{B{1'b0}},below[3*B-1:B]};
        middle<={{B{1'b0}},rd_data[B-1:0],accepted};neighbor<=2;
       end
      end else begin
       above<=0;below<=0;middle<={{B{1'b0}},rd_data[B-1:0],{B{1'b0}}};neighbor<=0;
      end
      neighborhood_cached<=1;state<=NEIGH_REQ;
     end
    end
    NEIGH_REQ:begin
     if(neighbor==8 || (fast_neighbors && reverse && neighbor==6)) state<=NEIGH_TEST;
     else if(fast_neighbors) neighbor<=neighbor+3;
     else if(neighbor==3) neighbor<=5;
     else neighbor<=neighbor+1'b1;
    end
    NEIGH_TEST:state<=SEED; // consume final synchronous response
    SEED:begin
     accepted<=original | (candidate & seeds);
     left_run<=candidate;right_run<=candidate;closure_shift<=1;state<=CLOSE;
    end
    CLOSE:begin
     accepted<=closure;
     left_run<=left_run & (left_run<<closure_shift);
     right_run<=right_run & (right_run>>closure_shift);
     closure_shift<=closure_shift<<1;
     if(closure==accepted || closure_shift>=B/2) begin
      if(closure!=original) begin changed<=1;state<=COMMIT;end
      else state<=ADVANCE;
     end
    end
    COMMIT:state<=ADVANCE;
    ADVANCE:begin
     if((!reverse && x==WORDS-1) || (reverse && x==0)) neighborhood_cached<=0;
     if((!reverse && pos==DEPTH-1) || (reverse && pos==0)) begin
      if(sweep_count!=32'hffffffff) sweep_count<=sweep_count+1'b1;
      if(!changed) begin pos<=0;x<=0;y<=0;state<=OUT_REQ;end
      else begin reverse<=!reverse;changed<=0;state<=CENTER_REQ;end
     end else begin
      pos<=reverse ? pos-1'b1 : pos+1'b1;
      if(reverse) begin
       if(x==0) begin x<=WORDS-1;y<=y-1'b1;end else x<=x-1'b1;
      end else begin
       if(x==WORDS-1) begin x<=0;y<=y+1'b1;end else x<=x+1'b1;
      end
      state<=CENTER_REQ;
     end
    end
    OUT_REQ:state<=OUT_LOAD;
    OUT_LOAD:begin output_word<=rd_data[B-1:0];out_bit<=0;state<=OUT_SEND;end
    OUT_SEND:begin
     out_valid<=1;out_sop<=pos==0 && out_bit==0;
     out_eop<=pos==DEPTH-1 && out_bit==LAST_BITS-1;
     out_data<=output_word[out_bit] ? 8'hff : 8'h00;
     if(out_bit==B-1 || (x==WORDS-1 && out_bit==LAST_BITS-1)) begin
      if(pos==DEPTH-1) state<=CAPTURE;
      else begin
       pos<=pos+1'b1;
       if(x==WORDS-1) begin x<=0;y<=y+1'b1;end else x<=x+1'b1;
       if(x!=WORDS-1 || LAST_BITS>=2) begin
        output_word<=rd_data;out_bit<=0;state<=OUT_SEND;
       end else state<=OUT_REQ;
      end
     end else out_bit<=out_bit+1'b1;
    end
    default:state<=CAPTURE;
   endcase
  end
 end
endmodule
`endif
