// ISP_R1: frame-held neutral-pixel white balance, four RGB888 pixels/beat.
// Exclude colored targets, shadows and highlights from the gray-world estimate.
module awb #(
    parameter IMG_HEIGHT=1080, IMG_WIDTH=1920,
    parameter MIN_NEUTRAL=(IMG_HEIGHT*IMG_WIDTH/256),
    parameter GAIN_MIN=192, GAIN_MAX=512, GAIN_STEP=8
)(
    input wire I_clk,I_rst_n,I_tlast,I_tuser,
    input wire [95:0] I_tdata,
    input wire I_tvalid, output wire I_tready,
    output reg O_tlast,O_tuser,output reg [95:0] O_tdata,
    output reg O_tvalid,input wire O_tready
);
    localparam FRAME_BEATS=IMG_HEIGHT*IMG_WIDTH/4;
    wire [7:0] r=I_tdata[23:16],g=I_tdata[15:8],b=I_tdata[7:0];
    wire [7:0] hi=(r>g)?((r>b)?r:b):((g>b)?g:b);
    wire [7:0] lo=(r<g)?((r<b)?r:b):((g<b)?g:b);
    wire neutral=(lo>=16 && hi<=224 && {1'b0,hi}<={lo,1'b0});
    reg [31:0] sum_r,sum_g,sum_b;
    reg [23:0] beats,neutrals;
    reg started;
    reg [9:0] gain_r,gain_b,pending_r,pending_b;
    wire estimate=I_tuser && started && beats==FRAME_BEATS && neutrals>=MIN_NEUTRAL;
    wire done_r,done_b;
    wire [39:0] ratio_r,ratio_b;
    awb_frame_div div_r(I_clk,I_rst_n,estimate,{sum_g,8'b0},sum_r,done_r,ratio_r);
    awb_frame_div div_b(I_clk,I_rst_n,estimate,{sum_g,8'b0},sum_b,done_b,ratio_b);
    function [9:0] limited_gain;
        input [39:0] ratio;input [9:0] current;
        reg [9:0] target;
        begin
            if(ratio<GAIN_MIN) target=GAIN_MIN;
            else if(ratio>GAIN_MAX) target=GAIN_MAX;
            else target=ratio[9:0];
            if(target>current+GAIN_STEP) limited_gain=current+GAIN_STEP;
            else if(target+GAIN_STEP<current) limited_gain=current-GAIN_STEP;
            else limited_gain=target;
        end
    endfunction
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            sum_r<=0;sum_g<=0;sum_b<=0;beats<=0;neutrals<=0;started<=0;
            gain_r<=256;gain_b<=256;pending_r<=256;pending_b<=256;
        end else begin
            if(done_r && done_b) begin
                pending_r<=limited_gain(ratio_r,gain_r);
                pending_b<=limited_gain(ratio_b,gain_b);
            end
            if(I_tuser) begin
                gain_r<=pending_r;gain_b<=pending_b;started<=1;
                sum_r<=0;sum_g<=0;sum_b<=0;beats<=0;neutrals<=0;
            end
            if(I_tvalid && (started || I_tuser)) begin
                beats<=(I_tuser?24'd0:beats)+1'b1;
                if(neutral) begin
                    sum_r<=(I_tuser?32'd0:sum_r)+r;
                    sum_g<=(I_tuser?32'd0:sum_g)+g;
                    sum_b<=(I_tuser?32'd0:sum_b)+b;
                    neutrals<=(I_tuser?24'd0:neutrals)+1'b1;
                end
            end
        end
    end
    reg [17:0] pr[0:3],pb[0:3];reg [7:0] pg[0:3];
    reg v1,s1,l1;
    wire [9:0] apply_r=I_tuser?pending_r:gain_r;
    wire [9:0] apply_b=I_tuser?pending_b:gain_b;
    function [7:0] saturate;
        input [17:0] value;
        begin saturate=(|value[17:16])?8'd255:value[15:8];end
    endfunction
    integer i;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            v1<=0;s1<=0;l1<=0;O_tvalid<=0;O_tuser<=0;O_tlast<=0;O_tdata<=0;
            for(i=0;i<4;i=i+1) begin pr[i]<=0;pb[i]<=0;pg[i]<=0;end
        end else begin
            v1<=I_tvalid;s1<=I_tuser;l1<=I_tlast;
            O_tvalid<=v1;O_tuser<=s1;O_tlast<=l1;
            for(i=0;i<4;i=i+1) begin
                pr[i]<=I_tdata[i*24+16+:8]*apply_r;
                pg[i]<=I_tdata[i*24+8+:8];
                pb[i]<=I_tdata[i*24+:8]*apply_b;
                O_tdata[i*24+:24]<=v1?{saturate(pr[i]),pg[i],saturate(pb[i])}:24'd0;
            end
        end
    end
    assign I_tready=O_tready;
endmodule

// Unsigned restoring division, once/frame. Operands latched at start.
module awb_frame_div(input wire clk,rst_n,start,input wire [39:0] numerator,
    input wire [31:0] denominator,output reg done,output reg [39:0] quotient);
    reg [39:0] work;reg [32:0] remainder;reg [31:0] divisor;
    reg [5:0] left;wire [33:0] trial={remainder,work[39]};
    wire subtract=(trial>={2'b0,divisor});
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin done<=0;quotient<=0;work<=0;remainder<=0;divisor<=1;left<=0;end
        else begin
            done<=0;
            if(start && left==0) begin
                work<=numerator;divisor<=denominator;remainder<=0;left<=40;
            end else if(left!=0) begin
                remainder<=subtract?(trial-{2'b0,divisor}):trial;
                work<={work[38:0],subtract};left<=left-1'b1;
                if(left==1) begin quotient<={work[38:0],subtract};done<=1;end
            end
        end
    end
endmodule
