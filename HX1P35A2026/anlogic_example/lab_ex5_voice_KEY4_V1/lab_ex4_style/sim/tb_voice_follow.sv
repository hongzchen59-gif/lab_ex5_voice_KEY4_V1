`timescale 1ns/1ps
module tb_voice_follow;
    reg clk=0,rst_n=0,mmio_wr=0,command_toggle=0,track_update=0;
    always #250 clk=~clk;
    reg [1:0] mmio_reg=0;
    reg [31:0] wdata=0,command=0,track_xy=0,track_info=0;
    reg [15:0] track_frame=0;
    wire step,dir,enabled,pwm;
    wire [31:0] status,position,target,servo_target,servo_current,control,age;
    voice_axis_control #(.CLK_HZ(2000000),.PAN_LIMIT(16),.STEP_PERIOD_US(1000),
        .FOLLOW_TIMEOUT_MS(60),.FOLLOW_TILT_SETTLE_MS(0)) dut(
        .button_stop(1'b0),.button_disable(1'b0),
        .clk(clk),.rst_n(rst_n),.mmio_wr(mmio_wr),.mmio_reg(mmio_reg),.wdata(wdata),
        .command(command),.command_toggle(command_toggle),.track_update(track_update),
        .track_xy(track_xy),.track_info(track_info),.track_frame(track_frame),
        .step(step),.dir(dir),.enabled(enabled),.servo_pwm(pwm),.status(status),
        .position(position),.target(target),.servo_target(servo_target),
        .servo_current(servo_current),.control(control),.track_age(age));
    task wr(input [1:0] r,input [31:0] d);
        begin @(negedge clk);mmio_wr=1;mmio_reg=r;wdata=d;
            @(negedge clk);mmio_wr=0;repeat(3)@(negedge clk);end
    endtask
    task cmd(input [31:0] c);
        begin @(negedge clk);command=c;command_toggle=~command_toggle;
            repeat(3)@(negedge clk);end
    endtask
    task packet(input [15:0] epoch,input [15:0] frame,input bit valid,input [15:0] x,input [15:0] y);
        begin @(negedge clk);track_xy={y,x};track_info={epoch,7'd0,valid,8'd1};
            track_frame=frame;track_update=1;@(negedge clk);track_update=0;
            repeat(3)@(negedge clk);end
    endtask
    integer hold_pos,hold_servo,n;
    task check_tilt_rate(input [15:0] y,input integer delta,input [15:0] frame);
        begin
            wr(0,1);wr(2,1500-$signed(servo_target));
            @(posedge pwm);#1000;
            wr(0,3);packet(6,frame,1,640,y);#25000000;
            if(servo_target!=1500)$fatal(1,"tilt must wait for direction confirmation");
            packet(6,frame+1,1,640,y);#25000000;
            if($signed(servo_target)!=1500+delta)
                $fatal(1,"tilt response y=%0d expected=%0d actual=%0d",y,1500+delta,servo_target);
        end
    endtask
    initial begin
        #2000;rst_n=1;
        wr(0,1);cmd(32'h00010101);packet(1,1,1,1000,100);
        #25000000;if(position!=0 || servo_target!=1500)$fatal(1,"manual mode followed a target");
        wr(0,3);packet(1,2,1,1000,100);
        #25000000;
        if(servo_target!=1500)$fatal(1,"first frame must not start tilt");
        packet(1,3,1,1000,100);#25000000;
        if($signed(position)<=0 || servo_target<1508 || !status[5] || !status[6])$fatal(1,"right/up feedback");
        hold_servo=servo_target;
        // A reused coordinate must not integrate into repeated tilt movement.
        for(n=0;n<5;n=n+1)begin packet(1,3,1,1000,100);#5000000;end
        if(servo_target!=hold_servo)$fatal(1,"same frame repeatedly moved tilt");
        packet(1,4,1,640,360);#3000000;
        hold_pos=$signed(position);hold_servo=servo_target;#25000000;
        if($signed(position)!=hold_pos || servo_target!=hold_servo)$fatal(1,"dead zone drift");
        // Small alternating errors around the old R2 dead zone must not hunt.
        for(n=0;n<8;n=n+1)begin
            packet(1,5+n,1,640,n[0]?16'd410:16'd310);#25000000;
            if(servo_target!=hold_servo)$fatal(1,"center jitter started tilt");
        end
        packet(1,13,1,640,100);#25000000;
        if(servo_target!=hold_servo)$fatal(1,"single outlier started tilt");
        packet(1,14,1,640,100);#25000000;
        if(servo_target!=hold_servo+8)$fatal(1,"persistent error failed to start tilt");
        hold_servo=servo_target;
        packet(1,15,1,640,310);#25000000;
        if(servo_target!=hold_servo+3)$fatal(1,"hysteresis did not retain direction");
        packet(1,16,1,640,320);#25000000;hold_servo=servo_target;
        packet(1,17,1,640,310);#25000000;
        if(servo_target!=hold_servo)$fatal(1,"tilt restarted inside entry threshold");
        packet(1,18,1,640,100);#25000000;
        packet(1,19,1,640,100);#25000000;hold_servo=servo_target;
        packet(1,20,1,640,620);#25000000;
        if(servo_target!=hold_servo)$fatal(1,"single opposite frame reversed tilt");
        packet(1,21,1,640,620);#25000000;
        if(servo_target!=hold_servo-8)$fatal(1,"persistent opposite error did not reverse tilt");
        cmd(32'h00040301);packet(1,4,1,200,600);hold_pos=$signed(position);#25000000;
        if($signed(position)!=hold_pos || status[6])$fatal(1,"old epoch target reused");
        packet(2,5,1,200,600);#25000000;
        packet(2,6,1,200,600);hold_servo=servo_target;#25000000;
        if($signed(position)>=hold_pos || servo_target>=hold_servo)$fatal(1,"left/down feedback");
        packet(2,6,0,200,600);#30000;
        hold_pos=$signed(position);hold_servo=servo_target;#25000000;
        if($signed(position)!=hold_pos || servo_target!=hold_servo || status[6])$fatal(1,"target loss did not hold");
        packet(2,7,1,1000,100);
        // Repeated CDC delivery of one valid frame must not refresh the age.
        for(n=0;n<16;n=n+1)begin #5000000;packet(2,7,1,1000,100);end
        if(status[6] || age<60)$fatal(1,"frozen frame watchdog bypassed");
        hold_pos=$signed(position);hold_servo=servo_target;#25000000;
        if($signed(position)!=hold_pos || servo_target!=hold_servo)$fatal(1,"stale frame movement");
        packet(2,8,1,1000,100);#25000000;cmd(2);
        hold_pos=$signed(position);hold_servo=servo_target;#25000000;
        if($signed(position)!=hold_pos || servo_target!=hold_servo)$fatal(1,"STOP did not hold");
        cmd(3);#20000000;
        if(position!=0 || servo_target!=1500)$fatal(1,"HOME did not return software origin");
        wr(0,13);cmd(32'h00010101);wr(0,15);packet(5,9,1,1000,100);#25000000;
        packet(5,10,1,1000,100);
        #25000000;if($signed(position)>=0 || servo_target>=1500)$fatal(1,"direction inversion");
        // Keep fresh result frames arriving without CPU commands: axis continues.
        for(n=0;n<10;n=n+1)begin packet(5,11+n,1,1000,100);#20000000;end
        if($signed(position)!=-16 || !status[3])$fatal(1,"follow pan limit");
        wr(0,13);wr(2,32'hfffff000);
        // Mode changes hold the pulse already applied, so let this manual
        // target reach a PWM frame before asking the feedback loop to run.
        @(posedge pwm);#1000;
        wr(0,15);packet(5,30,1,1000,100);#25000000;
        packet(5,31,1,1000,100);#25000000;
        if(servo_target!=1000 || !status[3])$fatal(1,"follow servo limit target=%0d status=%h",servo_target,status);
        wr(1,8);if(!status[4])$fatal(1,"manual jog accepted in follow mode");
        cmd(32'h00010101);
        check_tilt_rate(100,8,40);check_tilt_rate(240,5,42);
        check_tilt_rate(290,3,44);check_tilt_rate(296,0,46);
        check_tilt_rate(424,0,48);check_tilt_rate(430,-3,50);
        check_tilt_rate(480,-5,52);check_tilt_rate(620,-8,54);
        wr(0,0);#2000000;
        if(enabled || step || pwm || status[5])$fatal(1,"follow disarm");
        $display("VOICE FOLLOW PASS: single correction per result, center jitter/outlier rejection, hysteresis, reversal confirmation, three-speed response, epoch/loss/frozen-frame handling, STOP/HOME, inversion, limits");
        $finish;
    end
    initial begin #2500000000;$fatal(1,"follow test timeout");end
endmodule
