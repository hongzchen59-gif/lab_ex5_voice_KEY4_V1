// AXIS_FOLLOW_R5: slightly larger tilt steps; retain settling and hysteresis.
// X42: 3.3V common-cathode STEP/DIR, En menu H (high enables).
// S20F: 50Hz PWM; start disabled, 1500us center, 1000..2000us working range.
module voice_axis_control #(
    parameter CLK_HZ=50000000,
    parameter PAN_LIMIT=1024,
    parameter STEP_PERIOD_US=10000,
    parameter STEP_HIGH_US=10,
    parameter DIR_SETUP_US=20,
    parameter SERVO_PERIOD_US=20000,
    parameter SERVO_CENTER_US=1500,
    parameter SERVO_MIN_US=1000,
    parameter SERVO_MAX_US=2000,
    parameter FOLLOW_TIMEOUT_MS=500,FOLLOW_CONTROL_MS=20,FOLLOW_TILT_SETTLE_MS=80
)(
    input wire clk,rst_n,
    input wire button_stop,button_disable,
    input wire mmio_wr,input wire [1:0] mmio_reg,input wire [31:0] wdata,
    input wire [31:0] command,input wire command_toggle,
    input wire track_update,input wire [31:0] track_xy,track_info,
    input wire [15:0] track_frame,
    output reg step,dir,enabled,
    output wire servo_pwm,
    output wire [31:0] status,position,target,servo_target,servo_current,control,track_age
);
    localparam IDLE=0,SETUP=1,HIGH=2,LOW=3;
    reg [1:0] state;
    reg [15:0] us_div,step_wait,servo_phase;
    reg signed [15:0] pan_position,pan_target;
    reg [15:0] servo_us,servo_active_us;
    reg seen_command,limit_hit,write_rejected;
    reg follow_mode,pan_reverse,tilt_reverse;
    reg button_hold;
    wire auto_update,auto_cancel,track_fresh;
    wire signed [15:0] auto_pan,auto_servo;
    wire [15:0] expected_epoch;
    voice_axis_follow #(.CLK_HZ(CLK_HZ),.CONTROL_MS(FOLLOW_CONTROL_MS),
        .TARGET_TIMEOUT_MS(FOLLOW_TIMEOUT_MS),.TILT_SETTLE_MS(FOLLOW_TILT_SETTLE_MS)) u_follow(
        .clk(clk),.rst_n(rst_n),.enabled(enabled),.follow_mode(follow_mode),
        .pan_reverse(pan_reverse),.tilt_reverse(tilt_reverse),
        .command(command),.command_toggle(command_toggle),.track_update(track_update),
        .track_xy(track_xy),.track_info(track_info),.track_frame(track_frame),
        .update(auto_update),.cancel(auto_cancel),.pan_delta(auto_pan),
        .servo_delta(auto_servo),.fresh(track_fresh),.age(track_age),.expected_epoch(expected_epoch));
    wire us_tick=us_div==CLK_HZ/1000000-1;
    wire command_event=command_toggle!=seen_command;
    wire positive=pan_target>pan_position;
    wire signed [32:0] pan_sum=$signed({wdata[31],wdata})+
        $signed({{17{pan_target[15]}},pan_target});
    wire signed [32:0] servo_sum=$signed({wdata[31],wdata})+
        $signed({17'd0,servo_us});
    wire signed [16:0] auto_pan_sum=$signed({pan_position[15],pan_position})+$signed({auto_pan[15],auto_pan});
    wire signed [16:0] auto_servo_sum=$signed({1'b0,servo_us})+$signed({auto_servo[15],auto_servo});
    assign servo_pwm=enabled && servo_phase<servo_active_us;
    // [0] enabled, [1] movement outstanding, [2] STEP high,
    // [3] limit clamp sticky, [4] write rejected sticky. Clear sticky flags by
    // writing the enable register. No position feedback from the driver.
    assign status={24'd0,button_hold,track_fresh,follow_mode,write_rejected,limit_hit,step,
                   (enabled && pan_target!=pan_position),enabled};
    assign control={28'd0,tilt_reverse,pan_reverse,follow_mode,enabled};
    assign position={{16{pan_position[15]}},pan_position};
    assign target={{16{pan_target[15]}},pan_target};
    assign servo_target={16'd0,servo_us};
    assign servo_current={16'd0,servo_active_us};
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            us_div<=0;state<=IDLE;step_wait<=0;step<=0;dir<=0;enabled<=0;
            pan_position<=0;pan_target<=0;servo_phase<=SERVO_PERIOD_US-1;
            servo_us<=SERVO_CENTER_US;servo_active_us<=SERVO_CENTER_US;
            seen_command<=0;limit_hit<=0;write_rejected<=0;
            follow_mode<=0;pan_reverse<=0;tilt_reverse<=0;
            button_hold<=0;
        end else begin
            if(us_tick)us_div<=0;else us_div<=us_div+1'b1;
            if(command_event)seen_command<=command_toggle;
            if(mmio_wr && mmio_reg==0 && !button_stop && !button_disable) begin
                follow_mode<=wdata[1] && wdata[0];pan_reverse<=wdata[2];tilt_reverse<=wdata[3];
                if(wdata[0])button_hold<=0;
            end
            if(button_stop || button_disable)begin button_hold<=1;follow_mode<=0;end
            // Enable/disarm has priority over command and pulse generation.
            if(button_disable || (mmio_wr && mmio_reg==0 && (!enabled || !wdata[0]) && !button_stop)) begin
                enabled<=!button_disable && wdata[0];limit_hit<=0;write_rejected<=0;
                pan_target<=pan_position;step<=0;state<=IDLE;step_wait<=0;
                servo_phase<=SERVO_PERIOD_US-1;
                servo_active_us<=servo_us;
                if(button_disable)begin servo_us<=servo_active_us;servo_active_us<=servo_active_us;end
            end else begin
                if(us_tick && enabled) begin
                    if(servo_phase==SERVO_PERIOD_US-1) begin
                        servo_phase<=0;servo_active_us<=servo_us;
                    end else servo_phase<=servo_phase+1'b1;
                end
                if(button_stop)begin
                    pan_target<=pan_position;servo_us<=servo_active_us;
                end else if(command_event) begin
                    // Every target switch/STOP cancels pending manual motion.
                    // HOME returns to the software origin, not a physical limit.
                    if(enabled && !button_hold && command[7:0]==3) begin
                        pan_target<=0;servo_us<=SERVO_CENTER_US;
                    end else begin
                        pan_target<=pan_position;servo_us<=servo_active_us;
                    end
                end else if(mmio_wr) begin
                    if(!enabled || ((follow_mode || button_hold) && mmio_reg!=0))write_rejected<=1;
                    else case(mmio_reg)
                        // Repeated enable must not restart/truncate a PWM frame.
                        0: begin
                            limit_hit<=0;write_rejected<=0;
                            if(control[3:1]!=wdata[3:1])begin pan_target<=pan_position;servo_us<=servo_active_us;end
                        end
                        1: begin
                            if(pan_sum>PAN_LIMIT)begin pan_target<=PAN_LIMIT;limit_hit<=1;end
                            else if(pan_sum< -PAN_LIMIT)begin pan_target<= -PAN_LIMIT;limit_hit<=1;end
                            else pan_target<=pan_sum[15:0];
                        end
                        2: begin
                            if(servo_sum>SERVO_MAX_US)begin servo_us<=SERVO_MAX_US;limit_hit<=1;end
                            else if(servo_sum<SERVO_MIN_US)begin servo_us<=SERVO_MIN_US;limit_hit<=1;end
                            else servo_us<=servo_sum[15:0];
                        end
                        3: begin
                            if(pan_target==pan_position && state!=HIGH) begin
                                pan_position<=0;pan_target<=0;
                            end else write_rejected<=1;
                        end
                    endcase
                end else if(follow_mode && auto_cancel && command[7:0]==1) begin
                    pan_target<=pan_position;servo_us<=servo_active_us;
                end else if(enabled && follow_mode && !button_hold && auto_update && track_fresh) begin
                    if(auto_pan_sum>PAN_LIMIT)begin pan_target<=PAN_LIMIT;limit_hit<=1;end
                    else if(auto_pan_sum< -PAN_LIMIT)begin pan_target<= -PAN_LIMIT;limit_hit<=1;end
                    else pan_target<=auto_pan_sum[15:0];
                    if(auto_servo_sum>SERVO_MAX_US)begin servo_us<=SERVO_MAX_US;limit_hit<=1;end
                    else if(auto_servo_sum<SERVO_MIN_US)begin servo_us<=SERVO_MIN_US;limit_hit<=1;end
                    else servo_us<=auto_servo_sum[15:0];
                end
                if(!enabled)begin step<=0;state<=IDLE;end
                else if(us_tick) begin
                    case(state)
                        IDLE: if(!button_stop && !button_hold && !command_event && !mmio_wr && !(follow_mode && auto_cancel && command[7:0]==1) && pan_target!=pan_position) begin
                            dir<=positive;step_wait<=DIR_SETUP_US;state<=SETUP;
                        end
                        SETUP: begin
                            if(button_stop || button_hold || command_event || mmio_wr || (follow_mode && auto_cancel && command[7:0]==1) || pan_target==pan_position)state<=IDLE;
                            else if(dir!=positive)begin dir<=positive;step_wait<=DIR_SETUP_US;end
                            else if(step_wait>1)step_wait<=step_wait-1'b1;
                            else begin
                                step<=1;state<=HIGH;step_wait<=STEP_HIGH_US;
                                if(dir)pan_position<=pan_position+1'b1;
                                else pan_position<=pan_position-1'b1;
                            end
                        end
                        HIGH: begin
                            // STOP completes the pulse already issued.
                            if(step_wait>1)step_wait<=step_wait-1'b1;
                            else begin step<=0;state<=LOW;step_wait<=STEP_PERIOD_US-STEP_HIGH_US;end
                        end
                        LOW: begin
                            if(step_wait>1)step_wait<=step_wait-1'b1;
                            else state<=IDLE;
                        end
                        default: begin step<=0;state<=IDLE;end
                    endcase
                end
            end
        end
    end
endmodule
