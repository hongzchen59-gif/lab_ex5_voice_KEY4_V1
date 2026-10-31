// Bounded, RAM-based RLE connected-component analysis. The same scan is replayed
// after root flattening for component-specific width profiles (no label image).
module detect_components #(
    parameter integer WIDTH=320,HEIGHT=180,MIN_SIDE=16,MIN_AREA=96,
    parameter integer MAX_RUNS=64,MAX_LABELS=128,BUDGET=1000000
)(
    input wire I_clk,I_rst_n,I_start,I_complete,
    input wire [15:0] I_frame_id,
    output reg [15:0] O_read_addr, input wire [1:0] I_read_data,
    output reg [1:0] O_status, output reg [2:0] O_count,
    output reg [319:0] O_objects,output reg [15:0] O_frame_id,
    output reg O_busy,output reg [19:0] O_cycles
);
    localparam IDLE=0,INIT=1,SCAN=2,SCAN_WAIT=3,SCAN_GET=4,CLOSE=5,ROW_READY=6,
      CUR_REQ=7,CUR_WAIT=8,CUR_GET=9,PREV_REQ=10,PREV_WAIT=11,PREV_GET=12,
      FIND_REQ=13,FIND_WAIT=14,FIND_GET=15,HAVE_PREV=16,HAVE_CUR=17,
      UNION1=18,UNION2=19,MERGE_A=20,MERGE_A_WAIT=21,MERGE_A_GET=22,
      MERGE_B=23,MERGE_B_WAIT=24,MERGE_B_GET=25,PREV_NEXT=26,
      FINAL_RUN=27,ADD_REQ=28,ADD_WAIT=29,ADD_GET=30,RUN_NEXT=31,ROW_NEXT=32,
      CAND_REQ=33,CAND_WAIT=34,CAND_GET=35,MAP_START=36,MAP_GET=37,
      REINIT=38,SHAPE_LOAD=39,SHAPE_CALC=40,SHAPE_CLASS=41,
      BCD_X=42,BCD_Y=43,OBJECT_NEXT=44,DONE=45,FAIL=46,SHAPE_MULT=47;
    localparam [8:0] LAST_X=WIDTH-1;
    reg [5:0] state,find_return;
    reg [7:0] init_idx,next_label,cand_idx,map_idx,query,root;
    reg [3:0] root_rank,find_depth;
    reg replay;
    reg [15:0] frame_id,scan_addr;
    reg [8:0] sx,run_start;
    reg [7:0] sy;
    reg [1:0] active_color;
    reg run_bank;
    reg [6:0] cur_count,prev_count,run_idx,prev_idx,prev_base;
    reg [8:0] cx0,cx1;
    reg [1:0] cc;
    reg [7:0] cur_root,prev_root,winner,loser;
    reg [3:0] prev_rank,winner_rank;
    reg rank_inc;

    // 0 is background; 1..MAX_LABELS are temporary labels.
    reg [11:0] parents[0:MAX_LABELS];
    reg [7:0] final_map[0:MAX_LABELS];
    reg [100:0] regions[0:MAX_LABELS];
    reg [27:0] runs[0:127];
    reg [7:0] pa,sa;
    reg [6:0] ra;
    reg [11:0] pq;
    reg [100:0] sq,saved_region;
    reg [27:0] rq;
    reg pw,sw,rw;
    reg [7:0] pwa,swa;
    reg [6:0] rwa;
    reg [11:0] pwd;
    reg [100:0] swd;
    reg [27:0] rwd;
    always @(posedge I_clk) begin
        pq<=parents[pa];sq<=regions[sa];rq<=runs[ra];
        if(pw)parents[pwa]<=pwd;
        if(sw)regions[swa]<=swd;
        if(rw)runs[rwa]<=rwd;
    end
    reg [100:0] selected[0:3];
    reg [7:0] selected_root[0:3];
    reg [8:0] profile[0:19];
    reg [7:0] sample_y[0:19];
    reg [2:0] total;
    reg [1:0] min_slot,obj_idx;
    integer k,j;
    always @(*) begin
        min_slot=0;
        if(selected[1][15:0]<selected[min_slot][15:0])min_slot=1;
        if(selected[2][15:0]<selected[min_slot][15:0])min_slot=2;
        if(selected[3][15:0]<selected[min_slot][15:0])min_slot=3;
    end
    wire [9:0] run_length={1'b0,cx1}-{1'b0,cx0}+1'b1;
    wire [9:0] scan_w={1'b0,sq[33:25]}-{1'b0,sq[24:16]}+1'b1;
    wire [8:0] scan_h={1'b0,sq[49:42]}-{1'b0,sq[41:34]}+1'b1;
    function [100:0] merged;
        input [100:0] a,b;
        begin
            merged[15:0]=a[15:0]+b[15:0];
            merged[24:16]=(a[24:16]<b[24:16])?a[24:16]:b[24:16];
            merged[33:25]=(a[33:25]>b[33:25])?a[33:25]:b[33:25];
            merged[41:34]=(a[41:34]<b[41:34])?a[41:34]:b[41:34];
            merged[49:42]=(a[49:42]>b[49:42])?a[49:42]:b[49:42];
            merged[74:50]=a[74:50]+b[74:50];
            merged[98:75]=a[98:75]+b[98:75];
            merged[100:99]=a[100:99];
        end
    endfunction
    function [100:0] added;
        input [100:0] a; input [8:0] x0,x1;input [7:0] yy;input [1:0] col;
        reg [9:0] len,xends;
        reg [24:0] xsum;
        reg [23:0] ysum;
        begin
            len={1'b0,x1}-{1'b0,x0}+1;
            xends={1'b0,x0}+{1'b0,x1};
            xsum=(len*xends)>>1;ysum=len*yy;
            added[15:0]=a[15:0]+len;
            added[24:16]=(a[15:0]==0 || x0<a[24:16])?x0:a[24:16];
            added[33:25]=(a[15:0]==0 || x1>a[33:25])?x1:a[33:25];
            added[41:34]=(a[15:0]==0 || yy<a[41:34])?yy:a[41:34];
            added[49:42]=(a[15:0]==0 || yy>a[49:42])?yy:a[49:42];
            added[74:50]=a[74:50]+xsum;added[98:75]=a[98:75]+ysum;
            added[100:99]=col;
        end
    endfunction
    reg [100:0] object_stat;
    reg [9:0] ww;
    reg [8:0] hh,p0,p1,p2,p3,p4;
    reg [31:0] box_area,area100,rel_y,area_h;
    reg [1:0] shape;
    reg [27:0] bcd_work;
    reg [3:0] bcd_step;
    reg [15:0] bcd_x;
    reg [319:0] object_buffer;
    // Explicit shift/add prevents the mapper from spending DSPs on constants.
    function [31:0] scale;
        input [31:0] value;input [6:0] factor;integer bit_idx;
        begin scale=0;for(bit_idx=0;bit_idx<7;bit_idx=bit_idx+1)
            if(factor[bit_idx])scale=scale+(value<<bit_idx);end
    endfunction
    wire [8:0] height_span=hh-9'd1;
    wire [10:0] bx0={object_stat[24:16],2'b00};
    wire [10:0] bx1={object_stat[33:25],2'b11};
    wire [9:0] by0={object_stat[41:34],2'b00};
    wire [9:0] by1={object_stat[49:42],2'b11};
    wire [11:0] center_x=({3'b0,object_stat[24:16]}+{3'b0,object_stat[33:25]})*2+1;
    wire [11:0] center_y=({4'b0,object_stat[41:34]}+{4'b0,object_stat[49:42]})*2+1;
    function [27:0] dabble;
        input [27:0] v;reg [27:0] t;integer n;
        begin t=v;for(n=0;n<4;n=n+1)if(t[12+n*4 +:4]>=5)t[12+n*4 +:4]=t[12+n*4 +:4]+3;dabble=t<<1;end
    endfunction
    wire [27:0] bcd_next=dabble(bcd_work);
    wire symmetric=(p0<=p4+ww/5+2 && p4<=p0+ww/5+2 && p1<=p3+ww/5+2 && p3<=p1+ww/5+2);
    wire centered=(scale(rel_y,10)>=scale(area_h,3) && scale(rel_y,10)<=scale(area_h,7));
    wire rising=(p0<=p1+2 && p1<=p2+2 && p2<=p3+2 && p3<=p4+2 &&
                  p4>=p0+ww/2 && scale(p0,3)<=ww+3 && scale(p4,3)>=ww*2 && rel_y*2>=area_h);
    wire falling=(p4<=p3+2 && p3<=p2+2 && p2<=p1+2 && p1<=p0+2 &&
                  p0>=p4+ww/2 && scale(p4,3)<=ww+3 && scale(p0,3)>=ww*2 && rel_y*2<=area_h);

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            state<=IDLE;O_busy<=0;O_status<=0;O_count<=0;O_objects<=0;O_frame_id<=0;O_cycles<=0;
            pw<=0;sw<=0;rw<=0;pa<=0;sa<=0;ra<=0;O_read_addr<=0;
            pwa<=0;swa<=0;rwa<=0;pwd<=0;swd<=0;rwd<=0;
            init_idx<=0;next_label<=1;cand_idx<=1;map_idx<=1;query<=0;root<=0;root_rank<=0;find_depth<=0;find_return<=IDLE;
            replay<=0;frame_id<=0;scan_addr<=0;sx<=0;sy<=0;run_start<=0;active_color<=0;run_bank<=0;
            cur_count<=0;prev_count<=0;run_idx<=0;prev_idx<=0;prev_base<=0;
            cx0<=0;cx1<=0;cc<=0;cur_root<=0;prev_root<=0;winner<=0;loser<=0;
            prev_rank<=0;winner_rank<=0;rank_inc<=0;saved_region<=0;total<=0;obj_idx<=0;
            object_stat<=0;ww<=0;hh<=0;p0<=0;p1<=0;p2<=0;p3<=0;p4<=0;
            box_area<=0;area100<=0;rel_y<=0;area_h<=0;shape<=0;bcd_work<=0;bcd_step<=0;bcd_x<=0;object_buffer<=0;
            for(k=0;k<4;k=k+1)begin selected[k]<=0;selected_root[k]<=0;end
            for(k=0;k<20;k=k+1)begin profile[k]<=0;sample_y[k]<=0;end
        end else begin
            pw<=0;sw<=0;rw<=0;
            if(O_busy)O_cycles<=O_cycles+1'b1;
            if(I_start) begin
                // New capture has hard ownership priority over an old task.
                if(O_busy || !I_complete)begin O_status<=O_busy?2'd2:2'd0;O_count<=0;O_objects<=0;end
                O_busy<=I_complete;state<=I_complete?INIT:IDLE;init_idx<=0;replay<=0;
                O_cycles<=0;frame_id<=I_frame_id;total<=0;object_buffer<=0;
                for(k=0;k<4;k=k+1)begin selected[k]<=0;selected_root[k]<=0;end
                for(k=0;k<20;k=k+1)profile[k]<=0;
            end else if(O_busy && O_cycles>=BUDGET)begin
                state<=IDLE;O_busy<=0;O_status<=2;O_count<=0;O_objects<=0;O_frame_id<=frame_id;
            end else case(state)
                IDLE:;
                INIT,REINIT:begin
                    pw<=1;pwa<=init_idx;pwd<={4'd0,init_idx};
                    if(!replay)begin sw<=1;swa<=init_idx;swd<=0;end
                    if(init_idx==MAX_LABELS)begin
                        sx<=0;sy<=0;scan_addr<=0;active_color<=0;cur_count<=0;prev_count<=0;
                        next_label<=1;run_bank<=0;state<=SCAN;
                    end else init_idx<=init_idx+1'b1;
                end
                SCAN:begin
                    if(sx==WIDTH)state<=CLOSE;
                    else begin O_read_addr<=scan_addr;state<=SCAN_WAIT;end
                end
                SCAN_WAIT:state<=SCAN_GET;
                SCAN_GET:begin
                    if(I_read_data!=active_color)begin
                        if(active_color!=0)begin
                            if(cur_count>=MAX_RUNS)state<=FAIL;
                            else begin rw<=1;rwa<={run_bank,cur_count[5:0]};rwd<={8'd0,active_color,(sx-9'd1),run_start};cur_count<=cur_count+1'b1;end
                        end
                        active_color<=I_read_data;run_start<=sx;
                    end
                    sx<=sx+1'b1;scan_addr<=scan_addr+1'b1;
                    if(!(I_read_data!=active_color && active_color!=0 && cur_count>=MAX_RUNS))state<=SCAN;
                end
                CLOSE:begin
                    state<=ROW_READY;
                    if(active_color!=0)begin
                        if(cur_count>=MAX_RUNS)state<=FAIL;
                        else begin rw<=1;rwa<={run_bank,cur_count[5:0]};rwd<={8'd0,active_color,LAST_X,run_start};cur_count<=cur_count+1'b1;end
                    end
                end
                ROW_READY:begin run_idx<=0;prev_base<=0;state<=(cur_count==0)?ROW_NEXT:CUR_REQ;end
                CUR_REQ:begin ra<={run_bank,run_idx[5:0]};state<=CUR_WAIT;end
                CUR_WAIT:state<=CUR_GET;
                CUR_GET:begin cx0<=rq[8:0];cx1<=rq[17:9];cc<=rq[19:18];cur_root<=0;prev_idx<=prev_base;state<=PREV_REQ;end
                PREV_REQ:begin
                    if(prev_idx>=prev_count)state<=FINAL_RUN;
                    else begin ra<={~run_bank,prev_idx[5:0]};state<=PREV_WAIT;end
                end
                PREV_WAIT:state<=PREV_GET;
                PREV_GET:begin
                    if({1'b0,rq[17:9]}+1<cx0)begin prev_idx<=prev_idx+1'b1;prev_base<=prev_idx+1'b1;state<=PREV_REQ;end
                    else if(rq[8:0]>{1'b0,cx1}+1)state<=FINAL_RUN;
                    else if(rq[19:18]!=cc)state<=PREV_NEXT;
                    else begin query<=rq[27:20];find_depth<=0;find_return<=HAVE_PREV;state<=FIND_REQ;end
                end
                FIND_REQ:begin pa<=query;state<=FIND_WAIT;end
                FIND_WAIT:state<=FIND_GET;
                FIND_GET:begin
                    if(pq[7:0]==query)begin root<=query;root_rank<=pq[11:8];state<=find_return;end
                    else if(find_depth>=8 || pq[7:0]==0 || pq[7:0]>MAX_LABELS)state<=FAIL;
                    else begin query<=pq[7:0];find_depth<=find_depth+1'b1;state<=FIND_REQ;end
                end
                HAVE_PREV:begin
                    if(cur_root==0)begin cur_root<=root;state<=PREV_NEXT;end
                    else begin prev_root<=root;prev_rank<=root_rank;query<=cur_root;find_depth<=0;find_return<=HAVE_CUR;state<=FIND_REQ;end
                end
                HAVE_CUR:begin
                    if(root==prev_root)begin cur_root<=root;state<=PREV_NEXT;end
                    else begin
                        winner<=(root_rank>=prev_rank)?root:prev_root;
                        loser<=(root_rank>=prev_rank)?prev_root:root;
                        winner_rank<=(root_rank>=prev_rank)?root_rank:prev_rank;
                        rank_inc<=(root_rank==prev_rank);state<=UNION1;
                    end
                end
                UNION1:begin pw<=1;pwa<=loser;pwd<={4'd0,winner};cur_root<=winner;state<=UNION2;end
                UNION2:begin
                    if(rank_inc)begin pw<=1;pwa<=winner;pwd<={(winner_rank+4'd1),winner};end
                    state<=replay?PREV_NEXT:MERGE_A;
                end
                MERGE_A:begin sa<=winner;state<=MERGE_A_WAIT;end
                MERGE_A_WAIT:state<=MERGE_A_GET;
                MERGE_A_GET:begin saved_region<=sq;state<=MERGE_B;end
                MERGE_B:begin sa<=loser;state<=MERGE_B_WAIT;end
                MERGE_B_WAIT:state<=MERGE_B_GET;
                MERGE_B_GET:begin sw<=1;swa<=winner;swd<=merged(saved_region,sq);state<=PREV_NEXT;end
                PREV_NEXT:begin prev_idx<=prev_idx+1'b1;state<=PREV_REQ;end
                FINAL_RUN:begin
                    if(cur_root==0)begin
                        if(next_label>MAX_LABELS)state<=FAIL;
                        else begin cur_root<=next_label;next_label<=next_label+1'b1;state<=ADD_REQ;end
                    end else state<=ADD_REQ;
                end
                ADD_REQ:begin
                    rw<=1;rwa<={run_bank,run_idx[5:0]};rwd<={cur_root,cc,cx1,cx0};
                    if(replay)begin
                        for(k=0;k<4;k=k+1)for(j=0;j<5;j=j+1)
                            if(selected[k][15:0]!=0 && final_map[cur_root]==selected_root[k] && sy==sample_y[k*5+j])
                                profile[k*5+j]<=profile[k*5+j]+run_length;
                        state<=RUN_NEXT;
                    end else begin sa<=cur_root;state<=ADD_WAIT;end
                end
                ADD_WAIT:state<=ADD_GET;
                ADD_GET:begin sw<=1;swa<=cur_root;swd<=added(sq,cx0,cx1,sy,cc);state<=RUN_NEXT;end
                RUN_NEXT:begin
                    run_idx<=run_idx+1'b1;state<=(run_idx+1>=cur_count)?ROW_NEXT:CUR_REQ;
                end
                ROW_NEXT:begin
                    if(sy==HEIGHT-1)begin cand_idx<=1;obj_idx<=0;state<=replay?SHAPE_LOAD:CAND_REQ;end
                    else begin sy<=sy+1'b1;sx<=0;active_color<=0;prev_count<=cur_count;cur_count<=0;run_bank<=~run_bank;state<=SCAN;end
                end
                CAND_REQ:begin
                    if(cand_idx>=next_label)begin map_idx<=1;state<=MAP_START;end
                    else begin sa<=cand_idx;pa<=cand_idx;state<=CAND_WAIT;end
                end
                CAND_WAIT:state<=CAND_GET;
                CAND_GET:begin
                    if(pq[7:0]==cand_idx && sq[15:0]>=MIN_AREA && scan_w>=MIN_SIDE && scan_h>=MIN_SIDE &&
                       scan_w<=scan_h*4 && scan_h<=scan_w*4 && sq[24:16]!=0 && sq[33:25]!=WIDTH-1 &&
                       sq[41:34]!=0 && sq[49:42]!=HEIGHT-1)begin
                        if(total<5)total<=total+1'b1;
                        if(sq[15:0]>selected[min_slot][15:0])begin selected[min_slot]<=sq;selected_root[min_slot]<=cand_idx;end
                    end
                    cand_idx<=cand_idx+1'b1;state<=CAND_REQ;
                end
                MAP_START:begin
                    if(map_idx>=next_label)begin
                        init_idx<=0;replay<=1;state<=REINIT;
                        for(k=0;k<4;k=k+1)for(j=0;j<5;j=j+1)
                            case(j)
                                0:sample_y[k*5+j]<=selected[k][41:34]+(({1'b0,selected[k][49:42]}-selected[k][41:34])>>3);
                                1:sample_y[k*5+j]<=selected[k][41:34]+(({1'b0,selected[k][49:42]}-selected[k][41:34])>>2);
                                2:sample_y[k*5+j]<=selected[k][41:34]+(({1'b0,selected[k][49:42]}-selected[k][41:34])>>1);
                                3:sample_y[k*5+j]<=selected[k][41:34]+(scale(({1'b0,selected[k][49:42]}-selected[k][41:34]),6)>>3);
                                4:sample_y[k*5+j]<=selected[k][41:34]+(scale(({1'b0,selected[k][49:42]}-selected[k][41:34]),7)>>3);
                            endcase
                    end else begin query<=map_idx;find_depth<=0;find_return<=MAP_GET;state<=FIND_REQ;end
                end
                MAP_GET:begin final_map[map_idx]<=root;map_idx<=map_idx+1'b1;state<=MAP_START;end
                SHAPE_LOAD:begin
                    object_stat<=selected[obj_idx];
                    p0<=profile[obj_idx*5];p1<=profile[obj_idx*5+1];p2<=profile[obj_idx*5+2];p3<=profile[obj_idx*5+3];p4<=profile[obj_idx*5+4];
                    state<=(selected[obj_idx][15:0]==0)?OBJECT_NEXT:SHAPE_CALC;
                end
                SHAPE_CALC:begin
                    ww<={1'b0,object_stat[33:25]}-object_stat[24:16]+1;
                    hh<={1'b0,object_stat[49:42]}-object_stat[41:34]+1;
                    state<=SHAPE_MULT;
                end
                SHAPE_MULT:begin
                    box_area<=ww*hh;
                    area100<=scale(object_stat[15:0],100);
                    rel_y<=object_stat[98:75]-object_stat[15:0]*object_stat[41:34];
                    area_h<=object_stat[15:0]*height_span;state<=SHAPE_CLASS;
                end
                SHAPE_CLASS:begin
                    shape<=0;
                    if(area100>=scale(box_area,88) && centered && p0*4>=scale(ww,3) && p1*4>=scale(ww,3) && p2*4>=scale(ww,3) && p3*4>=scale(ww,3) && p4*4>=scale(ww,3))shape<=3;
                    else if(area100>=scale(box_area,64) && area100<=scale(box_area,87) && ww*4>=scale(hh,3) && hh*4>=scale(ww,3) && centered && symmetric &&
                        scale(p2,5)>=ww*4 && scale(p0,5)>=ww*2 && scale(p4,5)>=ww*2 && scale(p0,10)<=ww*9 && scale(p4,10)<=ww*9 && scale(p1,3)>=ww*2 && scale(p3,3)>=ww*2)shape<=1;
                    else if(area100>=scale(box_area,35) && area100<=scale(box_area,65) && (rising || falling) && p2*4>=ww && p2*4<=scale(ww,3))shape<=2;
                    bcd_work<={16'd0,center_x};bcd_step<=0;state<=BCD_X;
                end
                BCD_X:begin
                    bcd_work<=bcd_next;bcd_step<=bcd_step+1'b1;
                    if(bcd_step==11)begin bcd_x<=bcd_next[27:12];bcd_work<={16'd0,center_y};bcd_step<=0;state<=BCD_Y;end
                end
                BCD_Y:begin
                    bcd_work<=bcd_next;bcd_step<=bcd_step+1'b1;
                    if(bcd_step==11)begin
                        object_buffer[obj_idx*80 +:80]<={2'd0,bcd_next[27:12],bcd_x,shape,object_stat[100:99],by1,by0,bx1,bx0};state<=OBJECT_NEXT;
                    end
                end
                OBJECT_NEXT:begin obj_idx<=obj_idx+1'b1;state<=(obj_idx==3)?DONE:SHAPE_LOAD;end
                DONE:begin O_objects<=object_buffer;O_count<=total;O_status<=1;O_frame_id<=frame_id;O_busy<=0;state<=IDLE;end
                FAIL:begin O_objects<=0;O_count<=0;O_status<=2;O_frame_id<=frame_id;O_busy<=0;state<=IDLE;end
                default:state<=FAIL;
            endcase
        end
    end
endmodule
