# Definitional proc to organize widgets for parameters.
proc init_gui { IPINST } {
  ipgui::add_param $IPINST -name "Component_Name"
  #Adding Page
  set Page_0 [ipgui::add_page $IPINST -name "Page 0"]
  ipgui::add_param $IPINST -name "DATAMOVER_RESET_CYCLES" -parent ${Page_0}
  ipgui::add_param $IPINST -name "DRAIN_TIMEOUT_CYCLES" -parent ${Page_0}
  ipgui::add_param $IPINST -name "PIPELINE_RESET_CYCLES" -parent ${Page_0}


}

proc update_PARAM_VALUE.DATAMOVER_RESET_CYCLES { PARAM_VALUE.DATAMOVER_RESET_CYCLES } {
	# Procedure called to update DATAMOVER_RESET_CYCLES when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.DATAMOVER_RESET_CYCLES { PARAM_VALUE.DATAMOVER_RESET_CYCLES } {
	# Procedure called to validate DATAMOVER_RESET_CYCLES
	return true
}

proc update_PARAM_VALUE.DRAIN_TIMEOUT_CYCLES { PARAM_VALUE.DRAIN_TIMEOUT_CYCLES } {
	# Procedure called to update DRAIN_TIMEOUT_CYCLES when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.DRAIN_TIMEOUT_CYCLES { PARAM_VALUE.DRAIN_TIMEOUT_CYCLES } {
	# Procedure called to validate DRAIN_TIMEOUT_CYCLES
	return true
}

proc update_PARAM_VALUE.PIPELINE_RESET_CYCLES { PARAM_VALUE.PIPELINE_RESET_CYCLES } {
	# Procedure called to update PIPELINE_RESET_CYCLES when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.PIPELINE_RESET_CYCLES { PARAM_VALUE.PIPELINE_RESET_CYCLES } {
	# Procedure called to validate PIPELINE_RESET_CYCLES
	return true
}


proc update_MODELPARAM_VALUE.PIPELINE_RESET_CYCLES { MODELPARAM_VALUE.PIPELINE_RESET_CYCLES PARAM_VALUE.PIPELINE_RESET_CYCLES } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.PIPELINE_RESET_CYCLES}] ${MODELPARAM_VALUE.PIPELINE_RESET_CYCLES}
}

proc update_MODELPARAM_VALUE.DATAMOVER_RESET_CYCLES { MODELPARAM_VALUE.DATAMOVER_RESET_CYCLES PARAM_VALUE.DATAMOVER_RESET_CYCLES } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.DATAMOVER_RESET_CYCLES}] ${MODELPARAM_VALUE.DATAMOVER_RESET_CYCLES}
}

proc update_MODELPARAM_VALUE.DRAIN_TIMEOUT_CYCLES { MODELPARAM_VALUE.DRAIN_TIMEOUT_CYCLES PARAM_VALUE.DRAIN_TIMEOUT_CYCLES } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.DRAIN_TIMEOUT_CYCLES}] ${MODELPARAM_VALUE.DRAIN_TIMEOUT_CYCLES}
}

