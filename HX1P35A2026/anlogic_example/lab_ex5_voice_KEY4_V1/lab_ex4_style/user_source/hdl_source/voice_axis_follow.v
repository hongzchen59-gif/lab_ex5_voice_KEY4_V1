// Sampled image feedback. Runs independently of the CPU/audio processing.
// Only a new committed result frame refreshes the watchdog, not CDC repeats.
module voice_axis_follow #(
    parameter CLK_HZ=50000000,CONTROL_MS=20,TARGET_TIMEOUT_MS=500,
    parameter CENTER_X=640,CENTER_Y=360,DEAD_X=32,DEAD_Y=40,TILT_START_Y=64,
    parameter TILT_SETTLE_MS=80
)(
    input wire clk,rst_n,enabled,follow_mode,pan_reverse,tilt_reverse,
    input wire [31:0] command,input wire command_toggle,
    input wire track_update,input wire [31:0] track_xy,track_info,
    input wire [15:0] track_frame,
    output reg update,cancel,
    output reg signed [15:0] pan_delta,servo_delta,
    output wire fresh,output wire [31:0] age,
    output reg [15:0] expected_epoch
);
    reg [15:0] ms_div,age_ms;
    reg [7:0] control_ms;
    reg [15:0] last_frame,x,y;
    reg have_target,seen_command;
    reg [7:0] operation;
    // One bounded tilt correction per fresh visual result, with a Schmitt
    // dead zone and two consecutive frames to start/reverse the direction.
    reg [1:0] tilt_direction,tilt_previous_side;
    reg tilt_pending;
    reg signed [15:0] tilt_frame_delta;
    reg [7:0] tilt_settle_ms;
    wire ms_tick=ms_div==CLK_HZ/1000-1;
    wire command_event=command_toggle!=seen_command;
    wire [15:0] frame_y=track_xy[31:16];
    wire signed [15:0] tilt_step=(frame_y<CENTER_Y-160 || frame_y>CENTER_Y+160)?16'sd8:
                                (frame_y<CENTER_Y-80 || frame_y>CENTER_Y+80)?16'sd5:16'sd3;
    wire [1:0] tilt_side=frame_y<CENTER_Y-DEAD_Y &&
        ((fresh && tilt_direction==1) || frame_y<CENTER_Y-TILT_START_Y)?2'd1:
        frame_y>CENTER_Y+DEAD_Y &&
        ((fresh && tilt_direction==2) || frame_y>CENTER_Y+TILT_START_Y)?2'd2:2'd0;
    wire packet_ok=track_info[8] && track_info[7:0]==1 &&
        track_info[31:16]==expected_epoch && track_xy[15:0]<1280 && track_xy[31:16]<720;
    wire new_result=track_update && packet_ok && (track_frame!=last_frame || !have_target);
    assign fresh=have_target && age_ms<TARGET_TIMEOUT_MS && operation==1;
    assign age={16'd0,age_ms};
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            ms_div<=0;control_ms<=0;age_ms<=TARGET_TIMEOUT_MS;
            last_frame<=0;x<=0;y<=0;have_target<=0;seen_command<=0;
            expected_epoch<=0;operation<=0;update<=0;cancel<=0;
            pan_delta<=0;servo_delta<=0;
            tilt_direction<=0;tilt_previous_side<=0;tilt_pending<=0;tilt_frame_delta<=0;
            tilt_settle_ms<=0;
        end else begin
            update<=0;cancel<=0;
            if(!enabled || !follow_mode || !fresh)begin
                tilt_direction<=0;tilt_previous_side<=0;tilt_pending<=0;
            end
            // A brief loss/new SELECT must not bypass the mechanical settling
            // interval. Only manual/disarmed mode releases this interval.
            if(!enabled || !follow_mode)tilt_settle_ms<=0;
            if(ms_tick)begin
                ms_div<=0;
                if(age_ms<TARGET_TIMEOUT_MS)age_ms<=age_ms+1'b1;
                if(tilt_settle_ms!=0)tilt_settle_ms<=tilt_settle_ms-1'b1;
                if(control_ms==CONTROL_MS-1)control_ms<=0;
                else control_ms<=control_ms+1'b1;
            end else ms_div<=ms_div+1'b1;
            if(command_event) begin
                seen_command<=command_toggle;expected_epoch<=expected_epoch+1'b1;
                operation<=command[7:0];have_target<=0;age_ms<=TARGET_TIMEOUT_MS;
                cancel<=1;
                tilt_direction<=0;tilt_previous_side<=0;tilt_pending<=0;
            end else begin
                if(track_update) begin
                    if(!packet_ok) begin
                        if(have_target)cancel<=1;
                        have_target<=0;
                        tilt_direction<=0;tilt_previous_side<=0;tilt_pending<=0;
                    end else if(track_frame!=last_frame || !have_target) begin
                        have_target<=1;age_ms<=0;last_frame<=track_frame;
                        x<=track_xy[15:0];y<=track_xy[31:16];
                        if(enabled && follow_mode)begin
                            tilt_pending<=1;tilt_previous_side<=tilt_side;
                            if(fresh && tilt_side!=0 && tilt_side==tilt_previous_side)begin
                                tilt_direction<=tilt_side;
                                tilt_frame_delta<=(tilt_side==1)?
                                    (tilt_reverse?-tilt_step:tilt_step):
                                    (tilt_reverse?tilt_step:-tilt_step);
                            end else begin tilt_direction<=0;tilt_frame_delta<=0;end
                        end
                    end
                end
                if(enabled && follow_mode && operation==1 && ms_tick && control_ms==CONTROL_MS-1) begin
                    if(fresh && !(track_update && !packet_ok) && age_ms<TARGET_TIMEOUT_MS-1) begin
                        update<=1;
                        // Positive pan pulses: clockwise viewed from above.
                        if(x>CENTER_X+DEAD_X)
                            pan_delta<=pan_reverse?-(x>CENTER_X+160?16'sd2:16'sd1):(x>CENTER_X+160?16'sd2:16'sd1);
                        else if(x<CENTER_X-DEAD_X)
                            pan_delta<=pan_reverse?(x<CENTER_X-160?16'sd2:16'sd1):-(x<CENTER_X-160?16'sd2:16'sd1);
                        else pan_delta<=0;
                        // A simultaneous new result is staged for the next
                        // tick instead of consuming a superseded correction.
                        if(tilt_pending && !new_result && tilt_settle_ms==0)begin
                            servo_delta<=tilt_frame_delta;tilt_pending<=0;
                            if(tilt_frame_delta!=0)tilt_settle_ms<=TILT_SETTLE_MS;
                        end else servo_delta<=0;
                    end else cancel<=1;
                end
            end
        end
    end
endmodule
