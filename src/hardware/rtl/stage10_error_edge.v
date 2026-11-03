`timescale 1ns/1ps

// Convert a held error level into one recovery event per assertion.
module stage10_error_edge (
    input  wire aclk,
    input  wire aresetn,
    input  wire error_level,
    output reg  error_pulse
);
    reg error_level_d;

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            error_level_d <= 1'b0;
            error_pulse   <= 1'b0;
        end else begin
            error_pulse   <= error_level && !error_level_d;
            error_level_d <= error_level;
        end
    end
endmodule
