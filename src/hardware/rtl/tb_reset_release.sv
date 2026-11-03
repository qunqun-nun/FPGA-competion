`timescale 1ns/1ps
module tb_reset_release;
reg c100=0,c300=0,c600=0;
always #5 c100=~c100;
always #1.666667 c300=~c300;
always #0.833333 c600=~c600;
reg extn=0,auxn=1,locked=0,dbg=0;
wire [2:0] icn,pern;
design_1_proc_sys_reset_0_0 r100(.slowest_sync_clk(c100),.ext_reset_in(extn),.aux_reset_in(auxn),.dcm_locked(locked),.mb_debug_sys_rst(dbg),.interconnect_aresetn(icn[0]),.peripheral_aresetn(pern[0]));
design_1_dpu_rst_300_0 r300(.slowest_sync_clk(c300),.ext_reset_in(extn),.aux_reset_in(auxn),.dcm_locked(locked),.mb_debug_sys_rst(dbg),.interconnect_aresetn(icn[1]),.peripheral_aresetn(pern[1]));
design_1_dpu_rst_600_0 r600(.slowest_sync_clk(c600),.ext_reset_in(extn),.aux_reset_in(auxn),.dcm_locked(locked),.mb_debug_sys_rst(dbg),.interconnect_aresetn(icn[2]),.peripheral_aresetn(pern[2]));
task check(input bit released,input string label_text);
begin
 #20000;
 if(icn !== {3{released}} || pern !== {3{released}}) $fatal(1,"%s icn=%b pern=%b",label_text,icn,pern);
 $display("PASS %s icn=%b pern=%b",label_text,icn,pern);
end endtask
initial begin
 check(0,"external reset holds all domains");
 extn=1;check(0,"clock unlocked holds all domains");
 locked=1;check(1,"aux high releases 100/300/600 MHz");
 auxn=0;check(0,"old aux low reproduces fault");
 auxn=1;check(1,"aux high recovers");
 extn=0;check(0,"external reset reasserts");
 extn=1;check(1,"external reset recovery");
 locked=0;check(0,"loss of lock reasserts");
 locked=1;check(1,"relock recovery");
 dbg=1;check(0,"debug reset reasserts");
 dbg=0;check(1,"debug reset recovery");
 $display("RESET_NETLIST_TEST_PASS");$finish;
end
initial begin #300000;$fatal(1,"timeout");end
endmodule
