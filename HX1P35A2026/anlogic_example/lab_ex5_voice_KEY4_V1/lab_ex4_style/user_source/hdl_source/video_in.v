

module video_in #(parameter FRAME_WORDS=172800,LATENCY_ENABLE=0)(
    input wire         I_rst_n,

    input wire         I_camera_clk,
    input wire         I_camera_frame_start,
    input wire         I_camera_valid,
    input wire[127:0]  I_camera_data,
    input wire         I_mipi_rx_error,
    input wire I_capture_start,
    input wire [31:0] I_camera_time_us,

    input wire         I_ddr_clk,

    input wire         I_display_pause,
    input wire         I_video_out_rd_busy,
    output wire        O_video_in_wr_busy,
    output reg[1:0]    O_video_out_rp,     ///读指针
    output reg [127:0] O_bank_source_ids,
    output reg [3:0] O_bank_complete,
    output wire [127:0] O_bank_capture_us,
    output wire [3:0] O_bank_capture_valid,

    output reg         O_ddr_user_wr_en,
    output reg[24:0]   O_ddr_user_addr,
    output wire[127:0] O_ddr_user_wr_data,
    input wire         I_ddr_user_ready
);

    wire        S_fifo_rst;
    reg         S_camera_frame_start_extend; ///脉冲展宽，同步到ddr_clk时钟域
    reg[3:0]    S_extend_cnt;
    reg         S_camera_frame_start_extend_1d;
    reg         S_camera_frame_start_extend_2d;
    reg         S_camera_frame_start_extend_3d;
    wire        S_frame_start;
    reg[1:0]    S_video_in_wp;       ///写指针
    wire[8:0]   S_fifo_rd_num;      
    wire        S_fifo_rd_en;   
    wire        S_fifo_rd_valid;
    wire[127:0] S_fifo_rd_data; 
    reg         S_ddr_wr_valid;
    reg[9:0]    S_ddr_wr_cnt;
    reg [31:0] source_sequence;
    reg [17:0] frame_words;
    reg [1:0] metadata_bank;
    reg metadata_started;
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            O_bank_source_ids<=0;O_bank_complete<=0;source_sequence<=0;
            frame_words<=0;metadata_bank<=0;metadata_started<=0;
        end else if(S_frame_start) begin
            source_sequence<=source_sequence+1'b1;frame_words<=0;
            metadata_bank<=I_mipi_rx_error?(S_video_in_wp-2'd1):S_video_in_wp;
            metadata_started<=!I_mipi_rx_error;
            O_bank_complete[I_mipi_rx_error?(S_video_in_wp-2'd1):S_video_in_wp]<=0;
            O_bank_source_ids[(I_mipi_rx_error?(S_video_in_wp-2'd1):S_video_in_wp)*32+:32]<=source_sequence+1'b1;
        end else if(O_ddr_user_wr_en && metadata_started) begin
            if(frame_words<FRAME_WORDS) begin
                frame_words<=frame_words+1'b1;
                if(frame_words==FRAME_WORDS-1) O_bank_complete[metadata_bank]<=1;
            end else O_bank_complete[metadata_bank]<=0; // oversized frame
        end
    end

    generate if(LATENCY_ENABLE) begin: g_capture
        reg [31:0] capture_time,isp_sequence;
        reg capture_pending,capture_bad;
        wire candidate_valid=I_capture_start?!capture_pending:(capture_pending && !capture_bad);
        always @(posedge I_camera_clk or negedge I_rst_n) begin
            if(!I_rst_n)begin capture_time<=0;isp_sequence<=0;capture_pending<=0;capture_bad<=0;end
            else begin
                if(I_capture_start)begin capture_time<=I_camera_time_us;capture_pending<=1;if(capture_pending)capture_bad<=1;end
                if(I_camera_frame_start)begin isp_sequence<=isp_sequence+1'b1;capture_pending<=0;capture_bad<=0;end
            end
        end
        wire mail_valid;wire [64:0] mail;
        meter_cdc #(.WIDTH(65),.BUNDLED_DIRECT(1)) mailbox(.I_src_clk(I_camera_clk),.I_src_rst_n(I_rst_n),
            .I_valid(I_camera_frame_start),
            .I_data({isp_sequence+32'd1,candidate_valid,(I_capture_start?I_camera_time_us:capture_time)}),
            .I_dst_clk(I_ddr_clk),.I_dst_rst_n(I_rst_n),.O_valid(mail_valid),.O_data(mail));
        reg [127:0] bank_time;reg [3:0] bank_valid;
        reg pending;reg [64:0] pending_data;integer ti;
        wire [1:0] new_bank=I_mipi_rx_error?(S_video_in_wp-2'd1):S_video_in_wp;
        always @(posedge I_ddr_clk or negedge I_rst_n) begin
            if(!I_rst_n)begin bank_time<=0;bank_valid<=0;pending<=0;pending_data<=0;end
            else begin
                if(S_frame_start)bank_valid[new_bank]<=0;
                if(mail_valid)begin pending<=1;pending_data<=mail;end
                else if(pending)begin
                    for(ti=0;ti<4;ti=ti+1)begin
                        if(O_bank_source_ids[ti*32+:32]==pending_data[64:33] && !(S_frame_start && new_bank==ti))begin
                            bank_time[ti*32+:32]<=pending_data[31:0];bank_valid[ti]<=pending_data[32];pending<=0;
                        end
                    end
                end
            end
        end
        assign O_bank_capture_us=bank_time;assign O_bank_capture_valid=bank_valid;
    end else begin: g_no_capture
        assign O_bank_capture_us=0;assign O_bank_capture_valid=0;
    end endgenerate

    localparam IMAGE_BASE_ADDR_0 = 25'd0;
    localparam IMAGE_BASE_ADDR_1 = 25'd7000000;
    localparam IMAGE_BASE_ADDR_2 = 25'd14000000;
    localparam IMAGE_BASE_ADDR_3 = 25'd21000000;


    assign S_fifo_rst = S_camera_frame_start_extend_3d | !I_rst_n;

    // ISP_R2: SOF is allowed to coincide with the first packed word. The frame
    // reset crosses to DDR, is held for eight camera clocks, then the FIFO
    // releases reset in each domain. Preserve pixels until this has completed.
    // The board's DDR clock is faster than half the camera clock; 32 camera
    // clocks cover the reset stretch, CDC and FIFO reset-release synchronizers.
    localparam FRAME_GUARD_CYCLES=32;
    reg [127:0] camera_data_delay[0:FRAME_GUARD_CYCLES-1];
    reg [FRAME_GUARD_CYCLES-1:0] camera_valid_delay;
    integer delay_index;
    // No data reset: validity masks uninitialized storage and permits RAM/SRL
    // inference instead of resetting thousands of data bits.
    always @(posedge I_camera_clk) begin
        camera_data_delay[0] <= I_camera_data;
        for(delay_index=1;delay_index<FRAME_GUARD_CYCLES;delay_index=delay_index+1)
            camera_data_delay[delay_index] <= camera_data_delay[delay_index-1];
    end
    always @(posedge I_camera_clk or negedge I_rst_n) begin
        if(!I_rst_n) camera_valid_delay<=0;
        else camera_valid_delay<={camera_valid_delay[FRAME_GUARD_CYCLES-2:0],I_camera_valid};
    end

    // 以完整DDR写突发的占用标志仲裁，避免连续视频写入长期阻塞读通道。
    assign O_video_in_wr_busy = S_ddr_wr_valid;

    w128_d512_fifo U_w128_d512_fifo(
        .rst        ( S_fifo_rst         ),   

        .clkw       ( I_camera_clk       ),     
        .we         ( camera_valid_delay[FRAME_GUARD_CYCLES-1] ),
        .di         ( camera_data_delay[FRAME_GUARD_CYCLES-1]  ),
        .afull      (),
        .full_flag  (),
        .wrusedw    (),
 
        .clkr       ( I_ddr_clk          ),
        .re         ( S_fifo_rd_en       ), 
        .dout       ( O_ddr_user_wr_data ),  
        .rdusedw    ( S_fifo_rd_num      ),
        .valid      (), 
        .empty_flag (),
        .aempty     ()
    );


    always @(posedge I_camera_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            S_camera_frame_start_extend <= 1'b0;
        else
            if(I_camera_frame_start)
                S_camera_frame_start_extend <= 1'b1;
            else if(S_extend_cnt == 'd7)
                S_camera_frame_start_extend <= 1'b0;
            else
                S_camera_frame_start_extend <= S_camera_frame_start_extend;
    end

	
    always @ (posedge I_camera_clk or negedge I_rst_n) begin
        if(!I_rst_n) S_extend_cnt <= 0;
    	else if(S_camera_frame_start_extend)
        	S_extend_cnt <= S_extend_cnt + 'd1;
      	else
          	S_extend_cnt <= 'd0;
    end


    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_camera_frame_start_extend_1d<=0;
            S_camera_frame_start_extend_2d<=0;
            S_camera_frame_start_extend_3d<=0;
        end else begin
            S_camera_frame_start_extend_1d <= S_camera_frame_start_extend;
            S_camera_frame_start_extend_2d <= S_camera_frame_start_extend_1d;
            S_camera_frame_start_extend_3d <= S_camera_frame_start_extend_2d;
        end
    end

    assign S_frame_start = ~S_camera_frame_start_extend_3d & S_camera_frame_start_extend_2d;

	/*
		如果前一帧图像有误少行了，那么地址回退为之前的，覆盖有问题的那帧图像
	*/
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            S_video_in_wp <= 'd0;
        else
            if(I_display_pause)
                S_video_in_wp <= S_video_in_wp;
            else if(S_frame_start)
                begin
                    if(I_mipi_rx_error)
                        S_video_in_wp <= S_video_in_wp;
                    else
                        S_video_in_wp <= S_video_in_wp + 'd1;
                end
            else
                S_video_in_wp <= S_video_in_wp;
    end


    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            O_video_out_rp <= 'd0;
        else
            if(I_display_pause)
                O_video_out_rp <= O_video_out_rp;
            else if(S_frame_start)
                begin
                    case(S_video_in_wp)
                        'd0: O_video_out_rp <= 'd2;
                        'd1: O_video_out_rp <= 'd3;
                        'd2: O_video_out_rp <= 'd0;
                        'd3: O_video_out_rp <= 'd1;
                    endcase
                end
            else
                O_video_out_rp <= O_video_out_rp;
    end

    /*
        fifo的深度是512，实际的深度是510，因此需要注意每次读出的长度避免为256，否则连续两次读写会引起fifo读空，丢失数据
    */
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            S_ddr_wr_valid <= 1'b0;
        else
            if(S_ddr_wr_valid && I_ddr_user_ready && S_ddr_wr_cnt == 'd239)
                S_ddr_wr_valid <= 1'b0;
            else if(S_fifo_rd_num >= 'd240 && (!I_video_out_rd_busy) && (!S_fifo_rst))
                S_ddr_wr_valid <= 1'b1;
            else
                S_ddr_wr_valid <= S_ddr_wr_valid;
    end

    always @(posedge I_ddr_clk) begin
        if(S_ddr_wr_valid)
            begin
                if(I_ddr_user_ready)
                    S_ddr_wr_cnt <= S_ddr_wr_cnt + 'd1;
                else
                    S_ddr_wr_cnt <= S_ddr_wr_cnt;
            end
        else
            S_ddr_wr_cnt <= 'd0;
    end

    assign S_fifo_rd_en = S_ddr_wr_valid & I_ddr_user_ready;

    always @(posedge I_ddr_clk) begin
        O_ddr_user_wr_en <= S_fifo_rd_en;
    end

	/*
		如果前一帧图像有误少行了，那么地址回退为之前的，覆盖有问题的那帧图像
	*/
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            O_ddr_user_addr <= 1'b0;
        else
            if(S_frame_start && (!I_mipi_rx_error))
                begin
                    case(S_video_in_wp)
                        'd0: O_ddr_user_addr <= IMAGE_BASE_ADDR_0;
                        'd1: O_ddr_user_addr <= IMAGE_BASE_ADDR_1;
                        'd2: O_ddr_user_addr <= IMAGE_BASE_ADDR_2;
                        'd3: O_ddr_user_addr <= IMAGE_BASE_ADDR_3;
                    endcase
                end
			else if(S_frame_start && I_mipi_rx_error)
				begin
                	case(S_video_in_wp)
                        'd0: O_ddr_user_addr <= IMAGE_BASE_ADDR_3;
                        'd1: O_ddr_user_addr <= IMAGE_BASE_ADDR_0;
                        'd2: O_ddr_user_addr <= IMAGE_BASE_ADDR_1;
                        'd3: O_ddr_user_addr <= IMAGE_BASE_ADDR_2;
                    endcase
                end
            else if(O_ddr_user_wr_en)
                O_ddr_user_addr <= O_ddr_user_addr + 'd8;
            else    
                O_ddr_user_addr <= O_ddr_user_addr;
    end

    
endmodule
