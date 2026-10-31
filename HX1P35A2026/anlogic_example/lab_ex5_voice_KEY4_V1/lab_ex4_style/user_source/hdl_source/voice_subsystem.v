module voice_subsystem(
    input wire sys_clk, rst_n, mic_sd, uart_rx,record_key_n,
    input wire [3:0] voice_keys_n,
    output wire mic_sck,mic_ws,uart_tx,
    output wire axis_step,axis_dir,axis_en,servo_pwm,
    output wire [49:0] motion_state,
    input wire pixel_clk,pixel_rst_n,
    input wire [1:0] detect_status,input wire [2:0] detect_count,
    input wire [319:0] detect_objects,input wire [15:0] detect_frame_id
);
    wire core_clk,pll_locked;
    reg [3:0] reset_pipe;
    reg [3:0] core_reset_pipe;
    wire reset_n=reset_pipe[3];
    wire core_reset_n=core_reset_pipe[3];
    voice_core_pll u_pll(.refclk(sys_clk),.reset(~rst_n),.lock(pll_locked),.core_clk(core_clk));
    always @(posedge sys_clk or negedge rst_n) begin
        if(!rst_n) reset_pipe<=0;
        else if(!pll_locked) reset_pipe<=0;
        else reset_pipe<={reset_pipe[2:0],1'b1};
    end
    always @(posedge core_clk or negedge reset_n) begin
        if(!reset_n) core_reset_pipe<=0;
        else core_reset_pipe<={core_reset_pipe[2:0],1'b1};
    end
    wire hclk,hready,hwrite;
    (* async_reg="true" *) reg [1:0] hreset_pipe;
    always @(posedge hclk or negedge reset_n) begin
        if(!reset_n)hreset_pipe<=0;else hreset_pipe<={hreset_pipe[0],1'b1};
    end
    wire [1:0] htrans,hresp;
    wire [30:0] haddr;
    wire [2:0] hsize;
    wire [31:0] hwdata,hrdata;
    wire req,wr,error;
    wire [19:0] addr;
    wire [31:0] wdata,rdata;
    // Existing vendor-generated physical MCU wrapper; PAD JTAG, not Fabric JTAG.
    MCU_f9f874759a41 #(.MCU_JTAG_SEL("0"),.MCU_RESET_VECTOR(32'h20e00000),
        .AHB_FREQ("150.0"),.MCU_DPLL_POST_DIV(4)) u_mcu(
        .core_clk(core_clk),.timer_clk(sys_clk),.core_reset(~core_reset_n),
        .por_reset(~core_reset_n),.nmi(1'b0),.clic_irq(23'd0),
        .jtag_tck(1'b0),.jtag_tms(1'b0),.jtag_tdi(1'b0),.jtag_tdo(),
        .uart0_rx(uart_rx),.uart0_tx(uart_tx),.uart1_rx(1'b1),.uart1_tx(),
        .gpio0_in(1'b0),.gpio1_in(1'b0),.gpio2_in(1'b0),.gpio3_in(1'b0),
        .gpio4_in(1'b0),.gpio5_in(1'b0),.gpio6_in(1'b0),.gpio7_in(1'b0),
        .qspi1_d0_in(1'b0),.qspi1_d1_in(1'b0),.qspi1_d2_in(1'b0),.qspi1_d3_in(1'b0),
        .ahb_clk(hclk),.htrans(htrans),.hwrite(hwrite),.haddr(haddr),.hsize(hsize),
        .hwdata(hwdata),.hrdata(hrdata),.hresp(hresp),.hready(hready),
        .apb_clk(sys_clk),.apb_rst(~reset_n),.prdata(32'd0),.pready(1'b1),.pslverr(1'b0));
    voice_ahb_bridge u_bus(.hclk(hclk),.hreset_n(hreset_pipe[1]),.htrans(htrans),
        .hwrite(hwrite),.haddr(haddr),.hsize(hsize),.hwdata(hwdata),
        .hready(hready),.hresp(hresp),.hrdata(hrdata),
        .clk(sys_clk),.reset_n(reset_n),.req(req),.wr(wr),.addr(addr),
        .wdata(wdata),.rdata(rdata),.error(error));
    wire [31:0] command,track_xy,track_info;
    wire command_toggle,command_ack;
    wire [79:0] telemetry;
    wire telemetry_update;
    wire [15:0] track_frame;
    wire [49:0] motion_src;
    meter_cdc #(.WIDTH(50),.BUNDLED_DIRECT(1)) u_motion_state(.I_src_clk(sys_clk),.I_src_rst_n(reset_n),
        .I_valid(1'b1),.I_data(motion_src),.I_dst_clk(pixel_clk),.I_dst_rst_n(pixel_rst_n),
        .O_valid(),.O_data(motion_state));
    voice_peripheral u_audio(.clk(sys_clk),.rst_n(reset_n),.mic_sd(mic_sd),.record_key_n(record_key_n),
        .voice_keys_n(voice_keys_n),
        .mic_sck(mic_sck),.mic_ws(mic_ws),.req(req),.wr(wr),.addr(addr),
        .axis_step(axis_step),.axis_dir(axis_dir),.axis_en(axis_en),.servo_pwm(servo_pwm),
        .axis_motion_state(motion_src),
        .wdata(wdata),.rdata(rdata),.error(error),.command(command),
        .command_toggle(command_toggle),.command_ack(command_ack),
        .track_xy(telemetry[31:0]),.track_info(telemetry[63:32]),.track_valid(1'b1),
        .track_update(telemetry_update),.track_frame(telemetry[79:64]));
    voice_target_select u_select(.clk(pixel_clk),.rst_n(pixel_rst_n),
        .command(command),.command_toggle(command_toggle),.command_ack(command_ack),
        .status(detect_status),.count(detect_count),.objects(detect_objects),
        .frame_id(detect_frame_id),.xy(track_xy),.info(track_info),.result_frame_id(track_frame));
    meter_cdc #(.WIDTH(80)) u_telemetry(.I_src_clk(pixel_clk),.I_src_rst_n(pixel_rst_n),
        .I_valid(1'b1),.I_data({track_frame,track_info,track_xy}),.I_dst_clk(sys_clk),
        .I_dst_rst_n(reset_n),.O_valid(telemetry_update),.O_data(telemetry));
endmodule
