// Measure a fixed power-of-two grid; consume FOUR 8-bit samples per valid beat.
// Counters advance on valid, not on gaps between RAW bursts. SOF may precede DE.
module frame_meter #(
    parameter GROUPS_PER_LINE=320, LINES=720,
    parameter X_START=32, X_END=288, Y_START=104, Y_END=616,
    parameter X_SKIP_BITS=2, Y_SKIP_BITS=3, SAMPLE_GROUP_LOG2=12, HAS_PEAKS=0
)(
    input wire I_clk,I_rst_n,I_sof,I_valid,
    input wire [31:0] I_samples,
    input wire [31:0] I_peaks,
    output reg [7:0] O_highlights,
    output reg [7:0] O_mean,
    output reg O_valid
);
    localparam SUM_W=SAMPLE_GROUP_LOG2+10;
    reg [11:0] x,y;
    reg [SUM_W-1:0] sum;
    reg [SAMPLE_GROUP_LOG2:0] count;
    reg started;
    reg [SAMPLE_GROUP_LOG2+2:0] highlights;
    wire [31:0] peaks=HAS_PEAKS?I_peaks:I_samples;
    wire [2:0] high_count={2'b0,(peaks[31:24]>=240)}+{2'b0,(peaks[23:16]>=240)}+
        {2'b0,(peaks[15:8]>=240)}+{2'b0,(peaks[7:0]>=240)};
    wire [SAMPLE_GROUP_LOG2+10:0] high_scaled={highlights,8'b0}>>(SAMPLE_GROUP_LOG2+2);
    wire [11:0] cx=I_sof?12'd0:x, cy=I_sof?12'd0:y;
    wire selected=(cx>=X_START && cx<X_END && cy>=Y_START && cy<Y_END) &&
        ((cx & ((1<<X_SKIP_BITS)-1))==0) && ((cy & ((1<<Y_SKIP_BITS)-1))==0);
    wire [9:0] group_sum={2'b0,I_samples[31:24]}+{2'b0,I_samples[23:16]}+
        {2'b0,I_samples[15:8]}+{2'b0,I_samples[7:0]};
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin x<=0;y<=0;sum<=0;count<=0;started<=0;O_mean<=0;O_valid<=0;highlights<=0;O_highlights<=0;end
        else begin
            O_valid<=0;
            if(I_sof) begin
                if(started && count==(1<<SAMPLE_GROUP_LOG2)) begin
                    O_mean<=sum[SUM_W-1 -:8];O_valid<=1;
                    O_highlights<=high_scaled[8]?8'd255:high_scaled[7:0];
                end
                started<=1;x<=0;y<=0;sum<=0;count<=0;highlights<=0;
            end
            if(I_valid && (started || I_sof)) begin
                if(cx==GROUPS_PER_LINE-1) begin x<=0;y<=cy+1'b1;end
                else begin x<=cx+1'b1;y<=cy;end
                if(selected) begin
                    sum<=(I_sof?{SUM_W{1'b0}}:sum)+group_sum;
                    count<=(I_sof?{(SAMPLE_GROUP_LOG2+1){1'b0}}:count)+1'b1;
                    highlights<=(I_sof?0:highlights)+high_count;
                end
            end
        end
    end
endmodule
