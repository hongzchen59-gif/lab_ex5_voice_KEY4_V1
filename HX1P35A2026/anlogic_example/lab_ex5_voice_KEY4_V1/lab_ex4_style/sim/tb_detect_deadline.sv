`timescale 1ns/1ps
module tb_detect_deadline;
    reg clk=0,rst_n=0,start=0;wire busy;wire [1:0] status;wire [2:0] count;wire [319:0] objects;
    always #5 clk=~clk;
    detect_components #(.BUDGET(200)) dut(.I_clk(clk),.I_rst_n(rst_n),.I_start(start),.I_complete(1'b1),.I_frame_id(16'd1),
        .O_read_addr(),.I_read_data(2'd0),.O_status(status),.O_count(count),.O_objects(objects),.O_frame_id(),.O_busy(busy),.O_cycles());
    initial begin
        repeat(4)@(negedge clk);rst_n=1;start=1;@(negedge clk);start=0;
        repeat(205)@(negedge clk);
        if(busy || status!=2 || count!=0 || objects!=0)$fatal(1,"watchdog did not terminate and invalidate");
        $display(" PASS: tb_detect_deadline watchdog terminates RAM task and invalidates results");$finish;
    end
endmodule
