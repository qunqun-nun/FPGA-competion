
/***************************** Include Files *******************************/
#include "pl_sys_ctrl.h"
#include "xparameters.h"
#include "stdio.h"
#include "xil_io.h"

/************************** Constant Definitions ***************************/
/************************** Function Definitions ***************************/
/**
 *
 * Run a self-test on the driver/device. Note this may be a destructive test if
 * resets of the device are performed.
 *
 * If the hardware system is not built correctly, this function may never
 * return to the caller.
 *
 * @param   baseaddr_p is the base address of the PL_SYS_CTRLinstance to be worked on.
 *
 * @return
 *
 *    - XST_SUCCESS   if all self-test code passed
 *    - XST_FAILURE   if any self-test code failed
 *
 * @note    Caching must be turned off for this function to work.
 * @note    Self test may fail if data memory and device are not on the same bus.
 *
 */
XStatus PL_SYS_CTRL_Reg_SelfTest(void * baseaddr_p)
{
	u32 baseaddr;
	u32 saved_ctrl;

	baseaddr = (u32) baseaddr_p;

	xil_printf("******************************\n\r");
	xil_printf("* User Peripheral Self Test\n\r");
	xil_printf("******************************\n\n\r");

	xil_printf("Control register test...\n\r");
	saved_ctrl = PL_SYS_CTRL_mReadReg(baseaddr, PL_SYS_CTRL_CTRL_OFFSET);
	PL_SYS_CTRL_mWriteReg(baseaddr, PL_SYS_CTRL_CTRL_OFFSET,
		PL_SYS_CTRL_CTRL_ENABLE_MASK);
	if ((PL_SYS_CTRL_mReadReg(baseaddr, PL_SYS_CTRL_CTRL_OFFSET) &
		PL_SYS_CTRL_CTRL_ENABLE_MASK) == 0U) {
		xil_printf("Error: CTRL.enable did not read back as one\n\r");
		PL_SYS_CTRL_mWriteReg(baseaddr, PL_SYS_CTRL_CTRL_OFFSET, saved_ctrl);
		return XST_FAILURE;
	}
	PL_SYS_CTRL_mWriteReg(baseaddr, PL_SYS_CTRL_CTRL_OFFSET,
		saved_ctrl & PL_SYS_CTRL_CTRL_ENABLE_MASK);

	if (PL_SYS_CTRL_mReadReg(baseaddr, PL_SYS_CTRL_VERSION_OFFSET) !=
		0x00020000U) {
		xil_printf("Error: unexpected interface version\n\r");
		return XST_FAILURE;
	}

	xil_printf("   - control and version register test passed\n\n\r");

	return XST_SUCCESS;
}
