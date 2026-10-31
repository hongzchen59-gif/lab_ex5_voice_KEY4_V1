// Luminance-guided 3x3 RGB smoothing, fixed-rate pipeline, common mode latency.
module edge_preserve #(parameter H_TOTAL=1650)(
    input wire I_clk,I_rst_n,input wire [30:0] I_pixel,
    output reg [30:0] O_pixel,output reg O_effect_ready
);
    wire [215:0] win;wire [30:0] center;wire window_valid;
    rgb_window_3x3 #(.H_TOTAL(H_TOTAL)) window(.I_clk(I_clk),.I_rst_n(I_rst_n),
        .I_pixel(I_pixel),.O_window(win),.O_center(center),.O_window_valid(window_valid));
    function [7:0] gray;
        input [23:0] p;reg [9:0] s;
        begin s={2'b0,p[23:16]}+{1'b0,p[15:8],1'b0}+{2'b0,p[7:0]};gray=s[9:2];end
    endfunction
    function [7:0] difference;
        input [7:0] a,b;
        begin difference=(a>=b)?a-b:b-a;end
    endfunction
    function colors_near;
        input [23:0] a,b;input [7:0] limit;
        begin colors_near=difference(a[23:16],b[23:16])<=limit &&
            difference(a[15:8],b[15:8])<=limit && difference(a[7:0],b[7:0])<=limit;end
    endfunction
    function [3:0] spatial;
        input integer n;
        begin case(n) 4:spatial=4;1,3,5,7:spatial=2;default:spatial=1;endcase end
    endfunction
    function [11:0] weighted;
        input [7:0] p;input [3:0] w;
        begin case(w)
            1:weighted={4'b0,p};2:weighted={3'b0,p,1'b0};
            4:weighted={2'b0,p,2'b0};8:weighted={1'b0,p,3'b0};default:weighted=0;
        endcase end
    endfunction
    // ceil(2^20 / d). Positive error is <0.008 LSB over the legal sum range;
    // adding half an LSB therefore gives exact round-half-up division here.
    function [17:0] reciprocal;
        input [5:0] d;
        begin case(d)
            8:reciprocal=131072;9:reciprocal=116509;10:reciprocal=104858;
            11:reciprocal=95326;12:reciprocal=87382;13:reciprocal=80660;
            14:reciprocal=74899;15:reciprocal=69906;16:reciprocal=65536;
            17:reciprocal=61681;18:reciprocal=58255;19:reciprocal=55189;
            20:reciprocal=52429;21:reciprocal=49933;22:reciprocal=47663;
            23:reciprocal=45591;24:reciprocal=43691;25:reciprocal=41944;
            26:reciprocal=40330;27:reciprocal=38837;28:reciprocal=37450;
            29:reciprocal=36158;30:reciprocal=34953;31:reciprocal=33826;
            32:reciprocal=32768;default:reciprocal=131072;
        endcase end
    endfunction
    reg [30:0] meta[0:5];reg [5:0] valid;
    reg [7:0] lum[0:8];reg [23:0] rgb0[0:8],rgb1[0:8];
    reg [3:0] weights[0:8];
    reg [11:0] rows[0:8];reg [4:0] weight_rows[0:2];
    reg [12:0] sums[0:2],sums_d[0:2];reg [5:0] weight_sum;
    reg [17:0] inv;reg [30:0] products[0:2];
    integer i,c,r;
    reg effect_seen;
    // Frame-level evidence that the smoothing window was actually selected.
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n)begin effect_seen<=0;O_effect_ready<=0;end
        else if(meta[5][27])begin O_effect_ready<=effect_seen;effect_seen<=0;end
        else if(meta[5][26] && meta[5][30:29]==2 && valid[5])effect_seen<=1;
    end
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            O_pixel<=0;valid<=0;weight_sum<=8;inv<=131072;
            for(i=0;i<6;i=i+1) meta[i]<=0;
            for(i=0;i<9;i=i+1) begin lum[i]<=0;rgb0[i]<=0;rgb1[i]<=0;weights[i]<=0;rows[i]<=0;end
            for(i=0;i<3;i=i+1) begin weight_rows[i]<=0;sums[i]<=0;sums_d[i]<=0;products[i]<=0;end
        end else begin
            meta[0]<=center;valid<={valid[4:0],window_valid};
            for(i=1;i<6;i=i+1) meta[i]<=meta[i-1];
            // Stage 0: colors and guide; stage 1: range/spatial weights.
            for(i=0;i<9;i=i+1) begin
                lum[i]<=gray(win[215-i*24 -:24]);rgb0[i]<=win[215-i*24 -:24];rgb1[i]<=rgb0[i];
                if(difference(lum[i],lum[4])<=12 && colors_near(rgb0[i],rgb0[4],24)) weights[i]<=spatial(i)<<1;
                else if(difference(lum[i],lum[4])<=32 && colors_near(rgb0[i],rgb0[4],48)) weights[i]<=spatial(i);
                else weights[i]<=0;
            end
            // Stages 2/3: balanced horizontal then vertical sums.
            for(r=0;r<3;r=r+1) begin
                weight_rows[r]<={1'b0,weights[r*3]}+{1'b0,weights[r*3+1]}+{1'b0,weights[r*3+2]};
                for(c=0;c<3;c=c+1)
                    rows[r*3+c]<=weighted(rgb1[r*3][23-c*8 -:8],weights[r*3])+
                        weighted(rgb1[r*3+1][23-c*8 -:8],weights[r*3+1])+
                        weighted(rgb1[r*3+2][23-c*8 -:8],weights[r*3+2]);
            end
            weight_sum<={1'b0,weight_rows[0]}+{1'b0,weight_rows[1]}+{1'b0,weight_rows[2]};
            for(c=0;c<3;c=c+1) begin
                sums[c]<={1'b0,rows[c]}+{1'b0,rows[c+3]}+{1'b0,rows[c+6]};
                sums_d[c]<=sums[c];
                products[c]<=sums_d[c]*inv+31'd524288;
            end
            inv<=reciprocal(weight_sum);
            // All modes share the same 7-stage path; only KEY3 selects smoothing.
            O_pixel<=meta[5];
            if(meta[5][30:29]==2 && valid[5]) begin
                for(c=0;c<3;c=c+1) O_pixel[23-c*8 -:8]<=products[c][27:20];
            end
        end
    end
endmodule
