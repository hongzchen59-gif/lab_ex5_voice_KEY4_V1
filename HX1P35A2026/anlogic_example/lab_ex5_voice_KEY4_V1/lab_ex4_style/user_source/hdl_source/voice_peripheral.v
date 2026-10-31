// CPU-visible Fabric window at 0x80000000, 32-bit accesses only.
// +0x1000..1fff: 2048 PCM16 samples, packed two per word, CPU read-only.
// +0x10000..1bfff: 48 KiB word RAM for feature/template enrollment (volatile).
module voice_peripheral #(parameter KEY_DEBOUNCE=1000000,BUTTON_CLK_HZ=50000000,BUTTON_DEBOUNCE_MS=20,
    parameter WORK_INIT_FILE="../data/voice_templates.mem")(
    input wire clk,rst_n,mic_sd,record_key_n,
    input wire [3:0] voice_keys_n,
    output wire mic_sck,mic_ws,
    output wire axis_step,axis_dir,axis_en,servo_pwm,
    output wire [49:0] axis_motion_state,
    input wire req,wr,input wire [19:0] addr,input wire [31:0] wdata,
    output wire [31:0] rdata,output reg error,
    output reg [31:0] command,output reg command_toggle,
    input wire command_ack,
    input wire [31:0] track_xy,track_info,
    input wire track_valid,track_update,input wire [15:0] track_frame
);
    wire ready,sample_valid;
    wire [31:0] axis_status,axis_position,axis_target,servo_target,servo_current;
    wire [31:0] axis_control,axis_track_age;
    assign axis_motion_state={axis_en,(axis_status[1]|axis_status[2]),axis_target[15:0],servo_target[15:0],servo_current[15:0]};
    wire axis_wr=req && wr && addr>=20'h00030 && addr<=20'h0003c;
    wire [3:0] button_level_n,button_press;
    reg [3:0] button_pending;
    voice_button_inputs #(.CLK_HZ(BUTTON_CLK_HZ),.DEBOUNCE_MS(BUTTON_DEBOUNCE_MS)) u_buttons(
        .clk(clk),.rst_n(rst_n),.keys_n(voice_keys_n),.level_n(button_level_n),.press(button_press));
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)button_pending<=0;
        else button_pending<=(button_pending & ~((req && wr && addr==20'h00058)?wdata[3:0]:4'd0)) | button_press;
    end
    voice_axis_control u_axis(.clk(clk),.rst_n(rst_n),
        .button_stop(~button_level_n[2]),.button_disable(~button_level_n[3]),
        .mmio_wr(axis_wr),.mmio_reg(addr[3:2]),.wdata(wdata),
        .command(command),.command_toggle(command_toggle),
        .track_update(track_update),.track_xy(track_xy),.track_info(track_info),.track_frame(track_frame),
        .step(axis_step),.dir(axis_dir),.enabled(axis_en),.servo_pwm(servo_pwm),
        .status(axis_status),.position(axis_position),.target(axis_target),
        .servo_target(servo_target),.servo_current(servo_current),.control(axis_control),.track_age(axis_track_age));
    wire signed [15:0] sample_data;
    voice_i2s_rx u_rx(.clk(clk),.rst_n(rst_n),.sd(mic_sd),
        .sck(mic_sck),.ws(mic_ws),.ready(ready),.valid(sample_valid),.pcm(sample_data));
    (* ram_style="bram" *) reg [31:0] pcm_ram[0:1023];
    (* ram_style="bram" *) reg [31:0] work_ram[0:12287];
    initial $readmemh(WORK_INIT_FILE,work_ram);
    reg [31:0] pcm_q,work_q,reg_data;
    (* async_reg="true" *) reg [1:0] key_sync;
    reg key_level;
    reg [19:0] key_count;
    reg [15:0] first_sample;
    reg [10:0] sample_index;
    reg [1:0] bank_ready;
    reg capture,overflow;
    reg [31:0] sample_count,block_sequence;
    (* async_reg="true" *) reg [1:0] ack_sync;
    wire busy=command_toggle!=ack_sync[1];
    wire pcm_select=(addr>=20'h01000 && addr<20'h02000);
    wire work_select=(addr>=20'h10000 && addr<20'h1c000);
    assign rdata=pcm_select?pcm_q:(work_select?work_q:reg_data);
    // Separate synchronous RAM process: no array/output reset and no scalar
    // register mux on the RAM output. This is required for TD ERAM inference.
    always @(posedge clk) begin
        if(req && pcm_select) pcm_q<=pcm_ram[addr[11:2]];
        if(req && work_select) begin
            work_q<=work_ram[addr[15:2]];
            if(wr) work_ram[addr[15:2]]<=wdata;
        end
        if(sample_valid && capture && !bank_ready[sample_index[10]] && sample_index[0])
            pcm_ram[sample_index[10:1]]<={sample_data,first_sample};
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin key_sync<=3;key_level<=1;key_count<=0;end
        else begin
            key_sync<={key_sync[0],record_key_n};
            if(key_sync[1]==key_level)key_count<=0;
            else if(key_count==KEY_DEBOUNCE-1)begin key_level<=key_sync[1];key_count<=0;end
            else key_count<=key_count+1'b1;
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            first_sample<=0;sample_index<=0;bank_ready<=0;capture<=0;overflow<=0;
            sample_count<=0;block_sequence<=0;command<=0;command_toggle<=0;ack_sync<=0;
            reg_data<=0;error<=0;
        end else begin
            ack_sync<={ack_sync[0],command_ack};error<=0;
            // RAM is never reset; bank_ready and explicit template initialization
            // govern validity. Write ACK is followed by readback in firmware.
            if(sample_valid && capture) begin
                if(bank_ready[sample_index[10]]) begin capture<=0;overflow<=1;end
                else begin
                    sample_count<=sample_count+1'b1;
                    sample_index<=sample_index+1'b1;
                    if(!sample_index[0]) first_sample<=sample_data;
                    if(sample_index[9:0]==10'd1023) begin
                        bank_ready[sample_index[10]]<=1;
                        block_sequence<=block_sequence+1'b1;
                    end
                end
            end
            if(req) begin
                if(pcm_select) begin
                    if(wr) error<=1;
                end else if(work_select) begin
                end else case(addr)
                    20'h00000: reg_data<=32'h564f4938; // VOI8: preset templates and four external buttons
                    20'h00004: reg_data<=32'd15625;
                    20'h00008: begin
                        reg_data<={31'd0,capture};
                        if(wr) begin
                            capture<=wdata[0] && ready;sample_index<=0;sample_count<=0;
                            bank_ready<=0;overflow<=0;block_sequence<=0;
                        end
                    end
                    20'h0000c: reg_data<={25'd0,!key_level,busy,overflow,bank_ready,capture,ready};
                    20'h00010: reg_data<=sample_count;
                    20'h00014: reg_data<=block_sequence;
                    20'h00018: begin
                        reg_data<=0;
                        // Consumer cannot release the bank being filled. A release
                        // collision at end-of-block is rejected (never clears new data).
                        if(wr) begin
                            if(wdata[0] && bank_ready[0]) bank_ready[0]<=0;
                            if(wdata[1] && bank_ready[1]) bank_ready[1]<=0;
                        end
                    end
                    20'h00020: begin
                        reg_data<=command;
                        if(wr) begin
                            if(busy) error<=1;
                            else begin command<=wdata;command_toggle<=~command_toggle;end
                        end
                    end
                    20'h00024: reg_data<={31'd0,busy};
                    20'h00028: reg_data<=track_valid?track_xy:0;
                    20'h0002c: reg_data<=track_valid?track_info:0;
                    20'h00030: reg_data<=axis_control;
                    20'h00034: reg_data<=axis_target;
                    20'h00038: reg_data<=servo_target;
                    20'h0003c: reg_data<=0;
                    20'h00040: begin reg_data<=axis_status;if(wr)error<=1;end
                    20'h00044: begin reg_data<=axis_position;if(wr)error<=1;end
                    20'h00048: begin reg_data<=servo_current;if(wr)error<=1;end
                    20'h0004c: begin reg_data<=32'h41584931;if(wr)error<=1;end
                    20'h00050: begin reg_data<=axis_track_age;if(wr)error<=1;end
                    20'h00054: begin reg_data<={16'd0,track_frame};if(wr)error<=1;end
                    20'h00058: reg_data<={28'd0,button_pending}; // press events, write-one-clear
                    20'h0005c: begin reg_data<={28'd0,~button_level_n};if(wr)error<=1;end
                    default: begin reg_data<=0;error<=1;end
                endcase
            end
        end
    end
endmodule
