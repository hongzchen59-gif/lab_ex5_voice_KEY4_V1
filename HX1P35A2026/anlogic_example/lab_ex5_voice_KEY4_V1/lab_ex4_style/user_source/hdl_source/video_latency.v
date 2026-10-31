// One shared microsecond counter. Gray encoding is registered and changes only
// once/us; each receiving domain uses two synchronizer stages before decoding.
module video_timebase #(parameter CLK_HZ=50000000,parameter [31:0] INITIAL_US=0)(
    input wire sys_clk,sys_rst_n,camera_clk,camera_rst_n,pixel_clk,pixel_rst_n,
    output wire [31:0] camera_us,pixel_us
);
    reg [7:0] divider;reg [31:0] time_us,time_gray;
    wire [31:0] gray_bus=time_gray;
    (* async_reg="true" *) reg [31:0] camera_meta,camera_sync,pixel_meta,pixel_sync;
    function [31:0] decode;
        input [31:0] g;reg [31:0] b;
        begin b=g;b=b^(b>>16);b=b^(b>>8);b=b^(b>>4);b=b^(b>>2);decode=b^(b>>1);end
    endfunction
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if(!sys_rst_n) begin divider<=0;time_us<=INITIAL_US;time_gray<=INITIAL_US^(INITIAL_US>>1);end
        else if(divider==CLK_HZ/1000000-1) begin
            divider<=0;time_us<=time_us+1'b1;time_gray<=(time_us+32'd1)^((time_us+32'd1)>>1);
        end else divider<=divider+1'b1;
    end
    always @(posedge camera_clk or negedge camera_rst_n)
        if(!camera_rst_n) begin camera_meta<=INITIAL_US^(INITIAL_US>>1);camera_sync<=INITIAL_US^(INITIAL_US>>1);end
        else begin camera_meta<=gray_bus;camera_sync<=camera_meta;end
    always @(posedge pixel_clk or negedge pixel_rst_n)
        if(!pixel_rst_n) begin pixel_meta<=INITIAL_US^(INITIAL_US>>1);pixel_sync<=INITIAL_US^(INITIAL_US>>1);end
        else begin pixel_meta<=gray_bus;pixel_sync<=pixel_meta;end
    assign camera_us=decode(camera_sync);assign pixel_us=decode(pixel_sync);
endmodule

// Capture-to-HDMI first valid pixel, per unique source. Time values share the
// common counter above. Unsigned subtraction also handles its ~71.6min wrap.
module video_latency #(parameter MAX_US=1000000,STALE_US=500000)(
    input wire clk,rst_n,input wire [31:0] now_us,
    input wire input_sof,output_sof,output_de,
    input wire [31:0] source_id,capture_us,input wire source_valid,capture_valid,
    output reg [1:0] status,output reg history_valid,
    output reg [15:0] latency_bcd,min_bcd,max_bcd,
    output reg [31:0] measured_source,output reg [19:0] measured_us,output reg update
);
    reg [31:0] frame_id,frame_capture,last_source,last_progress;
    reg frame_valid,armed,stats_seen;
    reg [19:0] min_us,max_us;
    wire [31:0] delta=now_us-frame_capture;
    wire [19:0] next_min=(!stats_seen || delta<min_us)?delta[19:0]:min_us;
    wire [19:0] next_max=(!stats_seen || delta>max_us)?delta[19:0]:max_us;
    reg [4:0] left;
    reg [19:0] bin_l,bin_n,bin_x,convert_us;
    reg [31:0] convert_id;
    reg [23:0] work_l,work_n,work_x,adjust_l,adjust_n,adjust_x;
    integer i;
    always @(*) begin
        adjust_l=work_l;adjust_n=work_n;adjust_x=work_x;
        for(i=0;i<6;i=i+1) begin
            if(work_l[i*4+:4]>=5)adjust_l[i*4+:4]=work_l[i*4+:4]+4'd3;
            if(work_n[i*4+:4]>=5)adjust_n[i*4+:4]=work_n[i*4+:4]+4'd3;
            if(work_x[i*4+:4]>=5)adjust_x[i*4+:4]=work_x[i*4+:4]+4'd3;
        end
    end
    wire [23:0] shift_l={adjust_l[22:0],bin_l[19]};
    wire [23:0] shift_n={adjust_n[22:0],bin_n[19]};
    wire [23:0] shift_x={adjust_x[22:0],bin_x[19]};
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            frame_id<=0;frame_capture<=0;frame_valid<=0;last_source<=0;last_progress<=0;
            armed<=0;stats_seen<=0;min_us<=0;max_us<=0;status<=0;history_valid<=0;
            latency_bcd<=0;min_bcd<=0;max_bcd<=0;measured_source<=0;measured_us<=0;update<=0;
            left<=0;bin_l<=0;bin_n<=0;bin_x<=0;work_l<=0;work_n<=0;work_x<=0;convert_id<=0;convert_us<=0;
        end else begin
            update<=0;
            if(input_sof) begin frame_id<=source_id;frame_capture<=capture_us;frame_valid<=source_valid && capture_valid;end
            if(left!=0) begin
                work_l<=shift_l;work_n<=shift_n;work_x<=shift_x;
                bin_l<=bin_l<<1;bin_n<=bin_n<<1;bin_x<=bin_x<<1;left<=left-1'b1;
                if(left==1) begin
                    // Six BCD microsecond digits; dropping two digits is /100.
                    latency_bcd<=shift_l[23:8];min_bcd<=shift_n[23:8];max_bcd<=shift_x[23:8];
                    measured_source<=convert_id;measured_us<=convert_us;history_valid<=1;update<=1;
                end
            end
            if(output_sof && output_de) begin
                if(!frame_valid) begin armed<=0;status<=stats_seen?2'd3:2'd0;end
                else if(!armed) begin
                    armed<=1;last_source<=frame_id;last_progress<=now_us;status<=0;
                end else if(frame_id!=last_source) begin
                    last_source<=frame_id;last_progress<=now_us;
                    if(delta<MAX_US && left==0) begin
                        stats_seen<=1;min_us<=next_min;max_us<=next_max;status<=1;
                        bin_l<=delta[19:0];bin_n<=next_min;bin_x<=next_max;
                        work_l<=0;work_n<=0;work_x<=0;left<=20;convert_id<=frame_id;convert_us<=delta[19:0];
                    end else begin status<=3;armed<=0;end
                end else if(now_us-last_progress>=STALE_US)status<=2;
            end
        end
    end
endmodule
