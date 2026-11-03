module pl_osd_engine #(
    parameter integer COORD_WIDTH = 12,
    parameter integer RGB_WIDTH = 24,
    parameter integer LINE_WIDTH = 2
) (
    input  logic                         pixel_active,
    input  logic [COORD_WIDTH-1:0]       pixel_x,
    input  logic [COORD_WIDTH-1:0]       pixel_y,
    input  logic [RGB_WIDTH-1:0]          pixel_rgb_in,
    output logic [RGB_WIDTH-1:0]          pixel_rgb_out,
    input  logic [3:0]                    box_count,
    input  logic [8*COORD_WIDTH-1:0]      box_x_flat,
    input  logic [8*COORD_WIDTH-1:0]      box_y_flat,
    input  logic [8*COORD_WIDTH-1:0]      box_w_flat,
    input  logic [8*COORD_WIDTH-1:0]      box_h_flat,
    input  logic [8*RGB_WIDTH-1:0]        box_color_flat
);

    integer i;
    logic found_edge;
    logic [COORD_WIDTH-1:0] box_x;
    logic [COORD_WIDTH-1:0] box_y;
    logic [COORD_WIDTH-1:0] box_w;
    logic [COORD_WIDTH-1:0] box_h;
    logic [COORD_WIDTH-1:0] offset_x;
    logic [COORD_WIDTH-1:0] offset_y;
    logic [RGB_WIDTH-1:0] box_color;
    logic inside_box;

    always_comb begin
        pixel_rgb_out = pixel_rgb_in;
        found_edge = 1'b0;
        box_x = '0;
        box_y = '0;
        box_w = '0;
        box_h = '0;
        offset_x = '0;
        offset_y = '0;
        box_color = '0;
        inside_box = 1'b0;

        if (pixel_active) begin
            for (i = 0; i < 8; i = i + 1) begin
                if ((i < box_count) && !found_edge) begin
                    box_x = box_x_flat[i*COORD_WIDTH +: COORD_WIDTH];
                    box_y = box_y_flat[i*COORD_WIDTH +: COORD_WIDTH];
                    box_w = box_w_flat[i*COORD_WIDTH +: COORD_WIDTH];
                    box_h = box_h_flat[i*COORD_WIDTH +: COORD_WIDTH];
                    box_color = box_color_flat[i*RGB_WIDTH +: RGB_WIDTH];

                    inside_box =
                        (box_w != 0) && (box_h != 0) &&
                        (pixel_x >= box_x) && (pixel_y >= box_y) &&
                        ((pixel_x - box_x) < box_w) &&
                        ((pixel_y - box_y) < box_h);
                    offset_x = pixel_x - box_x;
                    offset_y = pixel_y - box_y;

                    if (inside_box &&
                        ((offset_x < LINE_WIDTH) ||
                         ((box_w - offset_x) <= LINE_WIDTH) ||
                         (offset_y < LINE_WIDTH) ||
                         ((box_h - offset_y) <= LINE_WIDTH))) begin
                        pixel_rgb_out = box_color;
                        found_edge = 1'b1;
                    end
                end
            end
        end
    end

endmodule
