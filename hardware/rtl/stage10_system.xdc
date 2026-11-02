# Stage 10 uses only the Zynq UltraScale+ PS-generated pl_clk0 clock.
# The clock is created and propagated by the processing-system IP.
# Do not add a duplicate create_clock or broad set_false_path here.
# Future external video clocks must add targeted CDC constraints only after
# their actual ports and XPM synchronization structures exist.
