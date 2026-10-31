`timescale 1ns/1ps
module tb_voice_axis;
    reg clk=0,rst_n=0,mmio_wr=0,command_toggle=0;
    always #250 clk=~clk; // 2MHz verifies the parameterized 1us enable.
    reg [1:0] mmio_reg=0;
    reg [31:0] wdata=0,command=0;
    reg button_stop=0,button_disable=0;
    wire step,dir,enabled,pwm;
    wire [31:0] status,position,target,servo_target,servo_current;
    voice_axis_control #(.CLK_HZ(2000000),.PAN_LIMIT(16),.STEP_PERIOD_US(1000)) dut(
        .button_stop(button_stop),.button_disable(button_disable),
        .clk(clk),.rst_n(rst_n),.mmio_wr(mmio_wr),.mmio_reg(mmio_reg),.wdata(wdata),
        .command(command),.command_toggle(command_toggle),.step(step),.dir(dir),
        .track_update(1'b0),.track_xy(32'd0),.track_info(32'd0),.track_frame(16'd0),
        .enabled(enabled),.servo_pwm(pwm),.status(status),.position(position),
        .target(target),.servo_target(servo_target),.servo_current(servo_current),.control(),.track_age());
    time dir_time=0,step_time=0,last_rise=0,pwm_rise=0,last_pwm=0;
    integer pulses=0,pwm_checks=0;
    always @(dir) dir_time=$time;
    always @(negedge enabled)begin last_pwm=0;pwm_rise=0;end
    always @(posedge step) begin
        if(!enabled)$fatal(1,"pulse while disabled");
        if($time-dir_time<20000)$fatal(1,"DIR setup too short");
        if(last_rise!=0 && $time-last_rise<1000000)$fatal(1,"STEP rate exceeded");
        step_time=$time;last_rise=$time;pulses=pulses+1;
    end
    always @(negedge step) if(rst_n && enabled && step_time!=0)
        if($time-step_time!=10000)$fatal(1,"STEP high width %0t",$time-step_time);
    always @(posedge pwm) begin
        if(!enabled)$fatal(1,"PWM while disabled");
        if(last_pwm!=0 && $time-last_pwm!=20000000)$fatal(1,"PWM period %0t",$time-last_pwm);
        pwm_rise=$time;last_pwm=$time;
    end
    always @(negedge pwm) if(rst_n && enabled && pwm_rise!=0) begin
        if($time-pwm_rise<1000000 || $time-pwm_rise>2000000)$fatal(1,"PWM width out of bounds");
        pwm_checks=pwm_checks+1;
    end
    task write_reg(input [1:0] r,input [31:0] d);
        begin @(negedge clk);mmio_reg=r;wdata=d;mmio_wr=1;
            @(negedge clk);mmio_wr=0;repeat(3)@(negedge clk);end
    endtask
    task send_command(input [31:0] c);
        begin @(negedge clk);command=c;command_toggle=~command_toggle;
            repeat(3)@(negedge clk);end
    endtask
    task reached(input integer value);
        integer timeout;
        begin
            timeout=0;
            while($signed(position)!=value && timeout<100000)begin @(negedge clk);timeout=timeout+1;end
            if(timeout==100000)$fatal(1,"position timeout: %0d expected %0d",$signed(position),value);
            wait(!step);repeat(4)@(negedge clk);
        end
    endtask
    integer stopped_at,count_at;
    initial begin
        #2000;rst_n=1;#600000;
        if(status!==0 || step || pwm)$fatal(1,"reset must disable all outputs");
        write_reg(1,8);if(!status[4] || position!=0)$fatal(1,"disabled write not rejected");
        write_reg(0,1);if(!enabled || status[4])$fatal(1,"enable/sticky clear");
        @(posedge pwm);#500000;write_reg(0,1);@(negedge pwm);
        if($time-pwm_rise!=1500000)$fatal(1,"repeated enable truncated PWM");
        if(servo_current!=1500)$fatal(1,"center pulse");
        write_reg(1,8);reached(8);if(pulses!=8)$fatal(1,"extra/missing STEP");
        write_reg(1,32767);reached(16);if(!status[3] || $signed(target)!=16)$fatal(1,"positive limit");
        write_reg(1,32'h80000000);reached(-16);if($signed(target)!=-16)$fatal(1,"negative limit/sign");
        write_reg(2,10000);if(servo_target!=2000)$fatal(1,"servo upper clamp");
        @(posedge pwm);#1000;if(servo_current!=2000)$fatal(1,"PWM frame latch");
        @(negedge pwm);if($time-pwm_rise!=2000000)$fatal(1,"servo 2000us pulse");
        write_reg(2,32'h80000000);if(servo_target!=1000)$fatal(1,"servo lower clamp/sign");
        @(posedge pwm);@(negedge pwm);
        if($time-pwm_rise!=1000000)$fatal(1,"servo 1000us pulse");
        write_reg(1,32);reached(-14);send_command(2);
        stopped_at=$signed(position);count_at=pulses;#4000000;
        if($signed(position)!=stopped_at || pulses!=count_at || !enabled)$fatal(1,"STOP hold");
        send_command(3);reached(0);
        if(servo_target!=1500)$fatal(1,"HOME center target");
        write_reg(1,4);reached(4);write_reg(3,1);
        if(position!=0 || target!=0)$fatal(1,"software origin");
        write_reg(1,8);reached(1);send_command(32'h00010101);
        stopped_at=$signed(position);#4000000;
        if($signed(position)!=stopped_at)$fatal(1,"SELECT must not auto-follow in jog firmware");
        write_reg(1,8);@(posedge step);#2000;button_stop=1;
        @(negedge step);stopped_at=$signed(position);count_at=pulses;#4000000;
        if($signed(position)!=stopped_at || pulses!=count_at || !status[7])$fatal(1,"button STOP during STEP high");
        button_stop=0;send_command(3);#4000000;
        if($signed(position)!=stopped_at)$fatal(1,"late HOME bypassed latched STOP");
        write_reg(1,8);if(!status[4])$fatal(1,"jog bypassed latched STOP");
        write_reg(0,1);if(status[7])$fatal(1,"explicit re-arm did not release STOP");
        write_reg(1,8);@(posedge step);#2000;button_disable=1;#1000;
        if(enabled || step || pwm)$fatal(1,"button DISABLE during STEP high");
        write_reg(0,1);if(enabled)$fatal(1,"DISABLE lost priority over enable");
        button_disable=0;write_reg(0,1);
        write_reg(0,0);#40000000;
        if(enabled || step || pwm)$fatal(1,"disarm outputs");
        rst_n=0;#1000;
        if(enabled || step || pwm || position!=0)$fatal(1,"reset recovery");
        if(pwm_checks<3)$fatal(1,"insufficient PWM checks");
        $display("VOICE AXIS PASS: reset/disarm, signed AHB-style writes, STEP count/width/rate/DIR setup, limits, frame-latched PWM, STOP/HOME/origin; pulses=%0d",pulses);
        $finish;
    end
    initial begin #300000000;$fatal(1,"axis test timeout");end
endmodule
