// Raster-rate line memories include horizontal blanking, allowing a centered
// window to flush its last row/column without changing frame geometry.
module rgb_window_3x3 #(
    parameter integer H_TOTAL=1650
)(
    input wire I_clk, input wire I_rst_n,
    input wire [30:0] I_pixel,
    output reg [215:0] O_window,
    output reg [30:0] O_center,
    output reg O_window_valid
);
    function integer clog2;
        input integer n;
        integer v;
        begin v=n-1; clog2=0; while(v>0) begin clog2=clog2+1; v=v>>1; end
            if(clog2<1) clog2=1;
        end
    endfunction
    localparam integer AW=clog2(H_TOTAL);
    (* ram_style="bram" *) reg [30:0] line1 [0:H_TOTAL-1];
    (* ram_style="bram" *) reg [24:0] line2 [0:H_TOTAL-1];
    reg [AW-1:0] addr, addr_d;
    reg write_valid;
    reg [30:0] pixel_d, mid_q;
    reg [24:0] top_q;
    reg [24:0] top_1,top_2,bot_1,bot_2;
    reg [30:0] mid_1,mid_2;
    reg [AW+1:0] warm_count;
    reg warm, frame_started;
    // No reset/clear on memory or its read ports: infer synchronous ERAM.
    always @(posedge I_clk) begin
        mid_q<=line1[addr]; top_q<=line2[addr];
        if(write_valid) begin
            line1[addr_d]<=pixel_d;
            line2[addr_d]<={mid_q[26],mid_q[23:0]};
        end
    end
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            addr<=0; addr_d<=0; pixel_d<=0; write_valid<=0;
            top_1<=0;top_2<=0;mid_1<=0;mid_2<=0;bot_1<=0;bot_2<=0;
            warm_count<=0;warm<=0;frame_started<=0;
            O_window<=0;O_center<=0;O_window_valid<=0;
        end else begin
            addr <= (addr==H_TOTAL-1) ? 0 : addr+1'b1;
            addr_d<=addr;pixel_d<=I_pixel;write_valid<=1;
            if(!warm) begin
                if(warm_count==2*H_TOTAL+3) warm<=1;
                else warm_count<=warm_count+1'b1;
            end
            top_2<=top_1;top_1<=top_q;
            mid_2<=mid_1;mid_1<=mid_q;
            bot_2<=bot_1;bot_1<={pixel_d[26],pixel_d[23:0]};
            O_window<={top_2[23:0],top_1[23:0],top_q[23:0],
                       mid_2[23:0],mid_1[23:0],mid_q[23:0],
                       bot_2[23:0],bot_1[23:0],pixel_d[23:0]};
            if(warm && mid_1[27]) frame_started<=1;
            if(warm && (frame_started || mid_1[27])) O_center<=mid_1;
            else O_center<=0;
            O_window_valid<=warm && (frame_started || mid_1[27]) &&
                top_2[24] && top_1[24] && top_q[24] &&
                mid_2[26] && mid_1[26] && mid_q[26] &&
                bot_2[24] && bot_1[24] && pixel_d[26];
        end
    end
endmodule

