`timescale 1ns/1ps
module tb_voice_tilt_rate;
    reg clk=0,rst_n=0,mmio_wr=0,command_toggle=0,track_update=0;
    always #250 clk=~clk;
    reg [1:0] mmio_reg=0;
    reg [31:0] wdata=0,command=0,track_xy=0,track_info=0;
    reg [15:0] frame=0;
    wire step,dir,enabled,pwm;
    wire [31:0] status,position,target,servo_target,servo_current,control,age;
    voice_axis_control #(.CLK_HZ(2000000),.FOLLOW_TIMEOUT_MS(200)) dut(
        .button_stop(1'b0),.button_disable(1'b0),
        .clk(clk),.rst_n(rst_n),.mmio_wr(mmio_wr),.mmio_reg(mmio_reg),.wdata(wdata),
        .command(command),.command_toggle(command_toggle),.track_update(track_update),
        .track_xy(track_xy),.track_info(track_info),.track_frame(frame),
        .step(step),.dir(dir),.enabled(enabled),.servo_pwm(pwm),.status(status),
        .position(position),.target(target),.servo_target(servo_target),
        .servo_current(servo_current),.control(control),.track_age(age));
    task wr(input [1:0] r,input [31:0] d);
        begin @(negedge clk);mmio_reg=r;wdata=d;mmio_wr=1;
            @(negedge clk);mmio_wr=0;repeat(3)@(negedge clk);end
    endtask
    task packet(input bit valid,input [15:0] y,input bit advance);
        begin @(negedge clk);if(advance)frame=frame+1'b1;
            track_xy={y,16'd640};track_info={16'd1,7'd0,valid,8'd1};track_update=1;
            @(negedge clk);track_update=0;repeat(3)@(negedge clk);end
    endtask
    integer previous_servo=1500,delta,changes=0,held,n;
    time last_change=0;
    reg check_changes=0;
    always @(negedge clk) begin
        if(check_changes && status[5] && status[6] && servo_target!=previous_servo)begin
            delta=$signed(servo_target)-previous_servo;
            if(delta>8 || delta< -8)$fatal(1,"large automatic tilt jump %0d",delta);
            if(last_change!=0 && $time-last_change<80000000)
                $fatal(1,"tilt corrections too close: %0t",$time-last_change);
            last_change=$time;changes=changes+1;
        end
        previous_servo=servo_target;
    end
    initial begin
        #2000;rst_n=1;wr(0,1);wr(2,200);@(posedge pwm);#1000;
        if(servo_current!=1700)$fatal(1,"manual pose setup");
        @(negedge clk);command=32'h00010101;command_toggle=~command_toggle;
        repeat(3)@(negedge clk);wr(0,3);check_changes=1;
        // Centered detections at high frame rate must not move either axis,
        // even when follow is enabled from an off-center mechanical setpoint.
        for(n=0;n<20;n=n+1)begin packet(1,360,1);#10000000;end
        if(servo_target!=1700 || servo_current!=1700 || position!=0 || changes!=0)
            $fatal(1,"centered target moved on follow enable");
        for(n=0;n<22;n=n+1)begin
            packet(1,100,1);#10000000;
            if(n==4)begin packet(0,100,1);#1000000;end
        end
        if(changes<2 || changes>3 || servo_target<=1700 || servo_target>1724)
            $fatal(1,"persistent error response changes=%0d target=%0d",changes,servo_target);
        held=servo_target;
        for(n=0;n<20;n=n+1)begin packet(1,620,1);#10000000;end
        if(servo_target>=held)$fatal(1,"rate-limited reversal failed");
        // Drain the one permitted correction, then keep delivering one frame.
        packet(1,360,1);#30000000;held=servo_target;
        for(n=0;n<25;n=n+1)begin packet(1,360,0);#10000000;end
        if(servo_target!=held || status[6] || age<200)$fatal(1,"frozen result moved tilt or refreshed timeout");
        last_change=0;
        packet(1,620,1);#25000000;
        if(servo_target!=held)$fatal(1,"reacquisition skipped direction confirmation");
        packet(1,620,1);#25000000;
        if(servo_target!=held-8)$fatal(1,"reacquisition failed to make one small step");
        $display("VOICE TILT RATE PASS: centered enable holds pose, max 8us jump, >=80ms spacing including brief loss, sustained error, reversal, frozen result and reacquisition");
        $finish;
    end
    initial begin #2000000000;$fatal(1,"tilt rate test timeout");end
endmodule
