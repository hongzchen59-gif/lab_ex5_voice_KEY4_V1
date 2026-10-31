module video_style_core #(
    parameter integer H_TOTAL=1650,
    parameter integer EDGE_THRESHOLD=80
)(
    input wire I_clk, input wire I_rst_n,
    input wire [30:0] I_pixel,
    output reg [30:0] O_pixel,output reg O_effect_ready
);
    wire [215:0] win;
    wire [30:0] center;
    wire win_valid;
    rgb_window_3x3 #(.H_TOTAL(H_TOTAL)) u_window(
        .I_clk(I_clk),.I_rst_n(I_rst_n),.I_pixel(I_pixel),
        .O_window(win),.O_center(center),.O_window_valid(win_valid));
    function [7:0] gray;
        input [23:0] rgb;
        reg [9:0] sum;
        begin sum={2'b0,rgb[23:16]}+{1'b0,rgb[15:8],1'b0}+{2'b0,rgb[7:0]};
            gray=sum[9:2];end
    endfunction
    // Shared luminance quantization: never lower fill luminance.
    function [7:0] quant_up;
        input [7:0] y;
        begin
            if(y<16)quant_up=y;
            else if(y>=240)quant_up=255;
            else quant_up={y[7:4],4'b0}+8'd16;
        end
    endfunction
    function [32:0] candidate_chroma;
        input [23:0] p;
        reg [7:0] y,hi,lo;
        reg signed [10:0] r,g,b;
        begin
            y=gray(p);
            hi=p[23:16]>p[15:8]?p[23:16]:p[15:8];if(p[7:0]>hi)hi=p[7:0];
            lo=p[23:16]<p[15:8]?p[23:16]:p[15:8];if(p[7:0]<lo)lo=p[7:0];
            r=$signed({3'b0,p[23:16]});g=$signed({3'b0,p[15:8]});b=$signed({3'b0,p[7:0]});
            if(y>=32 && y<=208 && hi-lo>=32)begin
                r=r+((r-$signed({3'b0,y}))>>>3);
                g=g+((g-$signed({3'b0,y}))>>>3);
                b=b+((b-$signed({3'b0,y}))>>>3);
            end
            candidate_chroma={r,g,b};
        end
    endfunction
    // {common positive lift, base RGB}. No per-channel clipping/hue rotation.
    function [31:0] prepare_fill;
        input [32:0] candidate;
        input [23:0] original;
        input [7:0] target;
        reg signed [10:0] r,g,b;
        reg [23:0] base,cand_rgb;
        reg [7:0] maximum,minimum,cand_y,lift;
        reg [8:0] needed,room;
        begin
            base=original;
            maximum=original[23:16]>original[15:8]?original[23:16]:original[15:8];
            if(original[7:0]>maximum)maximum=original[7:0];
            minimum=original[23:16]<original[15:8]?original[23:16]:original[15:8];
            if(original[7:0]<minimum)minimum=original[7:0];
            needed={1'b0,target}-{1'b0,gray(original)};
            room=9'd255-{1'b0,maximum};
            lift=needed<=room?needed[7:0]:room[7:0];
            r=$signed(candidate[32:22]);g=$signed(candidate[21:11]);b=$signed(candidate[10:0]);
            if(minimum<=8 && maximum>=224)lift=0;
            else if(r>=0 && r<=255 && g>=0 && g<=255 && b>=0 && b<=255)begin
                cand_rgb={r[7:0],g[7:0],b[7:0]};cand_y=gray(cand_rgb);
                maximum=r[7:0]>g[7:0]?r[7:0]:g[7:0];if(b[7:0]>maximum)maximum=b[7:0];
                needed={1'b0,target}-{1'b0,cand_y};room=9'd255-{1'b0,maximum};
                if(target>=cand_y && needed<=room)begin base=cand_rgb;lift=needed[7:0];end
            end
            prepare_fill={lift,base};
        end
    endfunction
    reg [30:0] meta [0:5];
    reg [5:0] valid_pipe;
    reg [7:0] lum [0:8];
    reg [10:0] gx_pos,gx_neg,gy_pos,gy_neg;
    reg [10:0] abs_gx,abs_gy;
    reg [11:0] magnitude;
    reg edge_d,edge_dd;
    reg [23:0] toon_color,toon_final;
    reg [32:0] chroma_candidate;
    reg [31:0] fill_plan;
    reg [7:0] target_luma,target_d;
    reg [3:0] curve_0,curve_1,curve_2;
    reg [1:0] normal_dir;
    reg sign_x,sign_y;
    reg toon_ink;
    integer i,c;
    reg effect_seen;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n)begin effect_seen<=0;O_effect_ready<=0;end
        else if(meta[5][27])begin O_effect_ready<=effect_seen;effect_seen<=0;end
        else if(meta[5][26] && meta[5][30:29]==2 && valid_pipe[5])effect_seen<=1;
    end
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            O_pixel<=0;valid_pipe<=0;toon_color<=0;toon_final<=0;toon_ink<=0;chroma_candidate<=0;fill_plan<=0;target_luma<=0;target_d<=0;curve_0<=0;curve_1<=0;curve_2<=0;normal_dir<=0;sign_x<=0;sign_y<=0;gx_pos<=0;gx_neg<=0;gy_pos<=0;gy_neg<=0;
            abs_gx<=0;abs_gy<=0;magnitude<=0;edge_d<=0;edge_dd<=0;
            for(i=0;i<6;i=i+1) meta[i]<=0;
            for(i=0;i<9;i=i+1) lum[i]<=0;
        end else begin
            meta[0]<=center;valid_pipe<={valid_pipe[4:0],win_valid};
            for(i=1;i<6;i=i+1) meta[i]<=meta[i-1];
            for(i=0;i<9;i=i+1) lum[i]<=gray(win[215-i*24 -: 24]);
            target_luma<=quant_up(lum[4]);target_d<=target_luma;
            chroma_candidate<=candidate_chroma(meta[1][23:0]);
            fill_plan<=prepare_fill(chroma_candidate,meta[2][23:0],target_d);
            for(c=0;c<3;c=c+1)
                toon_color[23-c*8 -:8]<=fill_plan[23-c*8 -:8]+fill_plan[31:24];
            // One-sided structural outline; linear shading is not ink.
            curve_0[0]<={1'b0,lum[4],1'b0}>({2'b0,lum[3]}+{2'b0,lum[5]}+10'd16);
            curve_0[1]<={1'b0,lum[4],1'b0}>({2'b0,lum[1]}+{2'b0,lum[7]}+10'd16);
            curve_0[2]<={1'b0,lum[4],1'b0}>({2'b0,lum[0]}+{2'b0,lum[8]}+10'd16);
            curve_0[3]<={1'b0,lum[4],1'b0}>({2'b0,lum[2]}+{2'b0,lum[6]}+10'd16);
            curve_1<=curve_0;curve_2<=curve_1;
            if({1'b0,abs_gx}>{abs_gy,1'b0})normal_dir<=0;
            else if({1'b0,abs_gy}>{abs_gx,1'b0})normal_dir<=1;
            else normal_dir<=(sign_x==sign_y)?2'd3:2'd2;
            toon_ink<=(magnitude>=256) && curve_2[normal_dir];
            toon_final<=toon_ink?24'h000000:toon_color;
            gx_pos<={3'b0,lum[2]}+{2'b0,lum[5],1'b0}+{3'b0,lum[8]};
            gx_neg<={3'b0,lum[0]}+{2'b0,lum[3],1'b0}+{3'b0,lum[6]};
            gy_pos<={3'b0,lum[0]}+{2'b0,lum[1],1'b0}+{3'b0,lum[2]};
            gy_neg<={3'b0,lum[6]}+{2'b0,lum[7],1'b0}+{3'b0,lum[8]};
            abs_gx<=(gx_pos>=gx_neg)?gx_pos-gx_neg:gx_neg-gx_pos;
            abs_gy<=(gy_pos>=gy_neg)?gy_pos-gy_neg:gy_neg-gy_pos;
            sign_x<=(gx_pos<gx_neg);sign_y<=(gy_pos<gy_neg);
            magnitude<={1'b0,abs_gx}+{1'b0,abs_gy};
            edge_d<=(magnitude>=EDGE_THRESHOLD);edge_dd<=edge_d;
            O_pixel[30:24]<=meta[5][30:24];
            if(!meta[5][26]) O_pixel[23:0]<=0;
            else case(meta[5][30:29])
                2'd0: O_pixel[23:0]<=meta[5][23:0];
                2'd1: O_pixel[23:0]<=(edge_dd && valid_pipe[5])?24'hffffff:24'h000000;
                2'd2: begin
                    if(!valid_pipe[5]) O_pixel[23:0]<=meta[5][23:0];
                    else O_pixel[23:0]<=toon_final;
                end
                2'd3: O_pixel[23:0]<=meta[5][23:0]; // DETECT base image
            endcase
        end
    end
endmodule
