// MOTION_R1: source-frame-aware hardware frame difference; pixel clock domain.
module video_motion #(
    parameter WIDTH=1280,HEIGHT=720,DIFF_THRESHOLD=12,MIN_CELLS=12,
    parameter SETTLE_CYCLES=22500000
)(
    input wire I_clk,I_rst_n,input wire [30:0] I_pixel,
    input wire [31:0] I_source_id,input wire I_source_valid,
    input wire [49:0] I_axis_state,
    output reg [2:0] O_status,output reg [13:0] O_cells,
    output reg [15:0] O_events,output reg [41:0] O_bbox,
    output reg O_done,output reg [31:0] O_result_source
);
    wire sof=I_pixel[27];wire enabled=I_pixel[30:29]==3;
    reg [49:0] last_axis;reg [24:0] settle;
    wire axis_event=(I_axis_state[49] || last_axis[49]) && I_axis_state!=last_axis;
    wire inhibit=axis_event || settle!=0 || (I_axis_state[49] && I_axis_state[48]);
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin last_axis<=0;settle<=0;end
        else begin
            last_axis<=I_axis_state;
            if(axis_event || (I_axis_state[49] && I_axis_state[48])) settle<=SETTLE_CYCLES;
            else if(settle!=0) settle<=settle-1'b1;
        end
    end
    reg [31:0] last_source;reg seen_source,prev_valid,run_frame,warm_frame,pending_analysis;
    reg active;reg [1:0] on_count,off_count;
    wire fresh=I_source_valid && (!seen_source || I_source_id!=last_source);
    wire gap=seen_source && I_source_id!=last_source+32'd1;
    wire start=sof && enabled && fresh && !inhibit && !pending_analysis;
    wire bv,bd,bgood;wire [7:0] gray;wire [13:0] ba;wire [7:0] bx;wire [6:0] by;
    motion_reduce #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) reduce(.clk(I_clk),.rst_n(I_rst_n),
        .pixel(I_pixel),.enable(run_frame),.valid(bv),.gray(gray),.addr(ba),.bx(bx),.by(by),.done(bd),.good(bgood));
    wire mv,md,mgood,mask;wire [13:0] ma;
    motion_difference #(.CELLS(WIDTH*HEIGHT/64),.THRESHOLD(DIFF_THRESHOLD)) diff(
        .clk(I_clk),.rst_n(I_rst_n),.valid(bv),.gray(gray),.addr(ba),
        .compare_enable(!warm_frame),.frame_done(bd),.frame_good(bgood),
        .mask_valid(mv),.mask(mask),.mask_addr(ma),.done(md),.good(mgood));
    wire stats_done,stats_good,global_change;wire [13:0] cells;wire [41:0] bbox;
    motion_filter_stats #(.DW(WIDTH/8),.DH(HEIGHT/8)) stats(.clk(I_clk),.rst_n(I_rst_n),
        .start(start),.mask_valid(mv),.mask(mask),.mask_addr(ma),.frame_done(md),.frame_good(mgood),
        .done(stats_done),.good(stats_good),.global_change(global_change),.cells(cells),.bbox(bbox));
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            last_source<=0;seen_source<=0;prev_valid<=0;run_frame<=0;warm_frame<=1;pending_analysis<=0;
            active<=0;on_count<=0;off_count<=0;O_status<=0;O_cells<=0;O_events<=0;O_bbox<=0;O_done<=0;O_result_source<=0;
        end else begin
            O_done<=0;
            if(sof) begin
                run_frame<=0;
                if(!enabled) begin
                    seen_source<=0;prev_valid<=0;pending_analysis<=0;
                    active<=0;on_count<=0;off_count<=0;O_status<=0;O_cells<=0;O_events<=0;O_bbox<=0;
                end else if(!I_source_valid) begin
                    prev_valid<=0;pending_analysis<=0;active<=0;on_count<=0;off_count<=0;O_status<=0;O_cells<=0;O_bbox<=0;
                end else if(fresh) begin
                    last_source<=I_source_id;seen_source<=1;
                    if(pending_analysis) begin
                        prev_valid<=0;pending_analysis<=0;active<=0;on_count<=0;off_count<=0;O_status<=6;O_bbox<=0;O_cells<=0;
                    end else if(!inhibit) begin
                        run_frame<=1;pending_analysis<=1;warm_frame<=!prev_valid || gap;
                        if(!prev_valid || gap) begin
                            prev_valid<=0;active<=0;on_count<=0;off_count<=0;O_status<=1;O_bbox<=0;O_cells<=0;
                        end
                    end
                end
            end
            if(stats_done && pending_analysis) begin
                O_done<=1;O_result_source<=last_source;pending_analysis<=0;O_cells<=cells;
                if(!stats_good || global_change) begin
                    prev_valid<=0;active<=0;on_count<=0;off_count<=0;O_bbox<=0;O_status<=stats_good?5:6;
                end else if(warm_frame) begin
                    prev_valid<=1;active<=0;on_count<=0;off_count<=0;O_status<=2;O_bbox<=0;O_cells<=0;
                end else begin
                    prev_valid<=1;
                    if(cells>=MIN_CELLS) begin
                        off_count<=0;O_bbox<=bbox;
                        if(active || on_count>=1) begin
                            O_status<=3;on_count<=0;
                            if(!active && O_events!=65535) O_events<=O_events+1'b1;
                            active<=1;
                        end else begin on_count<=on_count+1'b1;O_status<=2;end
                    end else begin
                        on_count<=0;
                        if(active && off_count<2) begin off_count<=off_count+1'b1;O_status<=3;end
                        else begin active<=0;off_count<=0;O_status<=2;O_bbox<=0;end
                    end
                end
            end
            if(inhibit && enabled) begin
                run_frame<=0;pending_analysis<=0;prev_valid<=0;active<=0;on_count<=0;off_count<=0;
                O_status<=4;O_cells<=0;O_bbox<=0;
            end
        end
    end
endmodule

module motion_reduce #(parameter WIDTH=1280,HEIGHT=720)(
    input wire clk,rst_n,input wire [30:0] pixel,input wire enable,
    output reg valid,output reg [7:0] gray,output reg [13:0] addr,
    output reg [7:0] bx,output reg [6:0] by,output reg done,good
);
    localparam DW=WIDTH/8;
    reg [30:0] p;reg [7:0] lum;
    wire [9:0] weighted={2'b0,pixel[23:16]}+{1'b0,pixel[15:8],1'b0}+{2'b0,pixel[7:0]}+10'd2;
    always @(posedge clk) begin p<=pixel;lum<=weighted[9:2];end
    reg [10:0] x;reg [9:0] y;reg started,run,bad;reg [19:0] count;
    reg [10:0] row_sum;
    reg [13:0] block_index;
    reg [13:0] partial[0:DW-1];reg [13:0] partial_q;
    wire sof=p[27],de=p[26],eol=p[28];
    wire [10:0] cx=sof?0:x;wire [9:0] cy=sof?0:y;
    wire use_frame=sof?enable:run;
    wire [10:0] horizontal=(cx[2:0]==0?11'd0:row_sum)+lum;
    wire [13:0] total=(cy[2:0]==0?14'd0:partial_q)+horizontal;
    always @(posedge clk) begin
        if(de && use_frame && cx<WIDTH && cy<HEIGHT) begin
            if(cx[2:0]==0) partial_q<=partial[cx>>3];
            if(cx[2:0]==7) partial[cx>>3]<=total;
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            x<=0;y<=0;started<=0;run<=0;bad<=0;count<=0;row_sum<=0;block_index<=0;
            valid<=0;gray<=0;addr<=0;bx<=0;by<=0;done<=0;good<=0;
        end else begin
            valid<=0;done<=0;
            if(sof) begin x<=0;y<=0;started<=1;run<=enable;bad<=0;count<=0;addr<=0;row_sum<=0;block_index<=0;end
            if(de && (started || sof)) begin
                if(eol) begin x<=0;y<=cy+1'b1;end else begin x<=cx+1'b1;y<=cy;end
                count<=(sof?20'd0:count)+1'b1;
                if(cx>=WIDTH || cy>=HEIGHT || eol!=(cx==WIDTH-1)) bad<=1;
                if(use_frame && cx<WIDTH && cy<HEIGHT) begin
                    row_sum<=horizontal;
                    if(cx[2:0]==7 && cy[2:0]==7) begin
                        valid<=1;gray<=(total+14'd32)>>6;bx<=cx>>3;by<=cy>>3;
                        addr<=block_index;block_index<=block_index+1'b1;
                    end
                end
                if(use_frame && cx==WIDTH-1 && cy==HEIGHT-1) begin
                    done<=1;good<=!bad && eol && count==WIDTH*HEIGHT-1;
                end
            end
        end
    end
endmodule

module motion_difference #(parameter CELLS=14400,THRESHOLD=12)(
    input wire clk,rst_n,valid,input wire [7:0] gray,input wire [13:0] addr,
    input wire compare_enable,frame_done,frame_good,
    output reg mask_valid,mask,output reg [13:0] mask_addr,output reg done,good
);
    reg [7:0] previous[0:CELLS-1];reg [7:0] old_q,new_q;
    reg [13:0] addr_q;reg vq,eq,dq,gq;
    wire [7:0] delta=old_q>new_q?old_q-new_q:new_q-old_q;
    always @(posedge clk) begin
        if(valid) begin old_q<=previous[addr];new_q<=gray;addr_q<=addr;end
        if(vq) previous[addr_q]<=new_q;
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin vq<=0;eq<=0;dq<=0;gq<=0;mask_valid<=0;mask<=0;mask_addr<=0;done<=0;good<=0;end
        else begin
            vq<=valid;eq<=compare_enable;dq<=frame_done;gq<=frame_good;
            mask_valid<=vq;mask<=eq && delta>=THRESHOLD;mask_addr<=addr_q;done<=dq;good<=gq;
        end
    end
endmodule

// Store one binary grid, then scan its padded raster in vertical blanking.
// 162*92 clocks at 75MHz is <200us, within the 720p vertical blank interval.
module motion_filter_stats #(parameter DW=160,DH=90)(
    input wire clk,rst_n,start,mask_valid,mask,input wire [13:0] mask_addr,
    input wire frame_done,frame_good,
    output reg done,good,global_change,output reg [13:0] cells,output reg [41:0] bbox
);
    (* ram_style="bram" *) reg bitmap[0:DW*DH-1];
    reg line1[0:DW+1],line2[0:DW+1];
    reg [13:0] raw_cells,active_cells;reg scanning;
    reg [7:0] sx,qx;reg [6:0] sy,qy;reg qvalid,read_q;
    reg [13:0] scan_addr;
    reg [2:0] top,mid,bot;
    reg [7:0] xmin,xmax;reg [6:0] ymin,ymax;
    wire in_grid=sx>=1 && sx<=DW && sy>=1 && sy<=DH;
    wire bit_q=(qx>=1 && qx<=DW && qy>=1 && qy<=DH)?read_q:1'b0;
    wire a=line1[qx],b=line2[qx];
    wire [3:0] votes={3'd0,top[1]}+{3'd0,top[0]}+{3'd0,b}+
        {3'd0,mid[1]}+{3'd0,mid[0]}+{3'd0,a}+
        {3'd0,bot[1]}+{3'd0,bot[0]}+{3'd0,bit_q};
    wire keep=qx>=2 && qy>=2 && mid[0] && votes>=3;
    wire [7:0] ox=qx-2;wire [6:0] oy=qy-2;
    wire [13:0] next_cells=active_cells+keep;
    wire [7:0] nxmin=(keep && ox<xmin)?ox:xmin,nxmax=(keep && ox>xmax)?ox:xmax;
    wire [6:0] nymin=(keep && oy<ymin)?oy:ymin,nymax=(keep && oy>ymax)?oy:ymax;
    always @(posedge clk) begin
        if(mask_valid) bitmap[mask_addr]<=mask;
        if(scanning && in_grid) read_q<=bitmap[scan_addr];
        if(qvalid) begin line1[qx]<=bit_q;line2[qx]<=a;end
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            raw_cells<=0;active_cells<=0;scanning<=0;sx<=0;sy<=0;qx<=0;qy<=0;qvalid<=0;scan_addr<=0;
            top<=0;mid<=0;bot<=0;xmin<=255;xmax<=0;ymin<=127;ymax<=0;
            done<=0;good<=0;global_change<=0;cells<=0;bbox<=0;
        end else begin
            done<=0;qvalid<=scanning;qx<=sx;qy<=sy;
            if(start) raw_cells<=0;
            else if(mask_valid && mask) raw_cells<=raw_cells+1'b1;
            if(frame_done) begin
                if(frame_good) begin
                    scanning<=1;sx<=0;sy<=0;active_cells<=0;scan_addr<=0;
                    xmin<=255;xmax<=0;ymin<=127;ymax<=0;top<=0;mid<=0;bot<=0;
                end else begin done<=1;good<=0;cells<=0;bbox<=0;global_change<=0;end
            end
            if(scanning) begin
                if(in_grid) scan_addr<=scan_addr+1'b1;
                if(sx==DW+1) begin sx<=0;sy<=sy+1'b1;if(sy==DH+1) scanning<=0;end
                else sx<=sx+1'b1;
            end
            if(qvalid) begin
                top<=qx==0?{2'b0,b}:{top[1:0],b};
                mid<=qx==0?{2'b0,a}:{mid[1:0],a};
                bot<=qx==0?{2'b0,bit_q}:{bot[1:0],bit_q};
                if(keep) begin active_cells<=next_cells;xmin<=nxmin;xmax<=nxmax;ymin<=nymin;ymax<=nymax;end
                if(qx==DW+1 && qy==DH+1) begin
                    done<=1;good<=1;cells<=next_cells;global_change<=raw_cells>=DW*DH*3/5;
                    bbox<=next_cells==0?42'd0:{nymax,3'b111,nymin,3'b000,nxmax,3'b111,nxmin,3'b000};
                end
            end
        end
    end
endmodule
