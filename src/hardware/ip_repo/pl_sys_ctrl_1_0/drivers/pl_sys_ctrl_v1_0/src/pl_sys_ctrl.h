
#ifndef PL_SYS_CTRL_H
#define PL_SYS_CTRL_H


/****************** Include Files ********************/
#include "xil_types.h"
#include "xstatus.h"

#define PL_SYS_CTRL_CTRL_OFFSET                   0x00U
#define PL_SYS_CTRL_STATUS_OFFSET                 0x04U
#define PL_SYS_CTRL_FRAME_CNT_OFFSET              0x08U
#define PL_SYS_CTRL_ERR_CODE_OFFSET               0x0CU
#define PL_SYS_CTRL_REQUEST_SEQ_OFFSET            0x10U
#define PL_SYS_CTRL_REQUEST_FRAME_ID_OFFSET       0x14U
#define PL_SYS_CTRL_REQUEST_BUFFER_ID_OFFSET      0x18U
#define PL_SYS_CTRL_REQUEST_GENERATION_OFFSET     0x1CU
#define PL_SYS_CTRL_REQUEST_REASON_OFFSET         0x20U
#define PL_SYS_CTRL_REQUEST_STATUS_OFFSET         0x24U
#define PL_SYS_CTRL_REQUEST_TIMESTAMP_OFFSET      0x28U
#define PL_SYS_CTRL_RESULT_SHADOW_FRAME_ID_OFFSET 0x30U
#define PL_SYS_CTRL_RESULT_SHADOW_BUFFER_ID_OFFSET 0x34U
#define PL_SYS_CTRL_RESULT_SHADOW_GENERATION_OFFSET 0x38U
#define PL_SYS_CTRL_RESULT_SHADOW_BBOX_X_OFFSET   0x3CU
#define PL_SYS_CTRL_RESULT_SHADOW_BBOX_Y_OFFSET   0x40U
#define PL_SYS_CTRL_RESULT_SHADOW_BBOX_W_OFFSET   0x44U
#define PL_SYS_CTRL_RESULT_SHADOW_BBOX_H_OFFSET   0x48U
#define PL_SYS_CTRL_RESULT_SHADOW_CONFIDENCE_OFFSET 0x4CU
#define PL_SYS_CTRL_RESULT_SHADOW_STATUS_OFFSET   0x50U
#define PL_SYS_CTRL_RESULT_COMMIT_OFFSET          0x54U
#define PL_SYS_CTRL_RESULT_SEQ_OFFSET             0x58U
#define PL_SYS_CTRL_RESULT_STATUS_OFFSET          0x5CU
#define PL_SYS_CTRL_IRQ_STATUS_OFFSET             0x60U
#define PL_SYS_CTRL_IRQ_ACK_OFFSET                0x64U
#define PL_SYS_CTRL_IRQ_ENABLE_OFFSET             0x68U
#define PL_SYS_CTRL_version_OFFSET                0x6CU
#define PL_SYS_CTRL_SCHED_COMPLETED_FRAMES_OFFSET 0x70U
#define PL_SYS_CTRL_STALE_FRAMES_OFFSET           0x74U
#define PL_SYS_CTRL_DROPPED_FRAMES_OFFSET         0x78U
#define PL_SYS_CTRL_STALE_RESULTS_OFFSET          0x7CU
#define PL_SYS_CTRL_BUFFER_CONFLICTS_OFFSET       0x80U
#define PL_SYS_CTRL_FRAMES_ABORTED_OFFSET         0x84U
#define PL_SYS_CTRL_BUFFER_STATE_OFFSET           0x88U
#define PL_SYS_CTRL_ERROR_SOURCE_OFFSET           0x8CU
#define PL_SYS_CTRL_PROF_CTRL_OFFSET               0x90U
#define PL_SYS_CTRL_PROF_CYCLE_LO_OFFSET           0x94U
#define PL_SYS_CTRL_PROF_CYCLE_HI_OFFSET           0x98U
#define PL_SYS_CTRL_LAST_FRAME_CYCLES_OFFSET       0x9CU
#define PL_SYS_CTRL_MAX_FRAME_CYCLES_OFFSET        0xA0U
#define PL_SYS_CTRL_LAST_DPU_LATENCY_OFFSET        0xA4U
#define PL_SYS_CTRL_MAX_DPU_LATENCY_OFFSET         0xA8U
#define PL_SYS_CTRL_LAST_RESULT_FRAME_AGE_OFFSET   0xACU
#define PL_SYS_CTRL_MAX_RESULT_FRAME_AGE_OFFSET    0xB0U
#define PL_SYS_CTRL_DPU_TIMEOUT_COUNT_OFFSET       0xB4U
#define PL_SYS_CTRL_PROF_STATUS_OFFSET             0xB8U
#define PL_SYS_CTRL_PROFILED_FRAMES_OFFSET         0xBCU
#define PL_SYS_CTRL_PROFILED_REQUESTS_OFFSET       0xC0U
#define PL_SYS_CTRL_PROFILED_RESULTS_OFFSET        0xC4U
#define PL_SYS_CTRL_RECOVERY_CTRL_OFFSET           0xC8U
#define PL_SYS_CTRL_RECOVERY_STATUS_OFFSET         0xCCU
#define PL_SYS_CTRL_RECOVERY_REASON_OFFSET         0xD0U
#define PL_SYS_CTRL_RECOVERY_COUNT_OFFSET          0xD4U
#define PL_SYS_CTRL_DPU_TIMEOUT_RECOVERIES_OFFSET  0xD8U
#define PL_SYS_CTRL_DATAMOVER_RECOVERIES_OFFSET    0xDCU
#define PL_SYS_CTRL_PROTOCOL_RECOVERIES_OFFSET     0xE0U
#define PL_SYS_CTRL_VIDEO_INPUT_CTRL_OFFSET         0xE4U
#define PL_SYS_CTRL_VIDEO_INPUT_STATUS_OFFSET       0xE8U
#define PL_SYS_CTRL_VIDEO_INPUT_ERR_CODE_OFFSET     0xECU
#define PL_SYS_CTRL_VIDEO_INPUT_FRAME_CNT_OFFSET    0xF0U
#define PL_SYS_CTRL_VIDEO_INPUT_SWITCH_REJECTS_OFFSET 0xF4U

#define PL_SYS_CTRL_CTRL_ENABLE_MASK              0x00000001U
#define PL_SYS_CTRL_CTRL_SOFT_RESET_MASK          0x00000002U
#define PL_SYS_CTRL_CTRL_CLEAR_ERROR_MASK         0x00000004U
#define PL_SYS_CTRL_PROF_CLEAR_STATS_MASK          0x00000001U
#define PL_SYS_CTRL_PROF_SNAPSHOT_STATS_MASK       0x00000002U
#define PL_SYS_CTRL_RECOVERY_CLEAR_STATUS_MASK     0x00000001U
#define PL_SYS_CTRL_RECOVERY_SOFTWARE_TRIGGER_MASK 0x00000002U
#define PL_SYS_CTRL_VIDEO_SOURCE_SELECT_MASK        0x00000001U
#define PL_SYS_CTRL_VIDEO_STATUS_ACTIVE_SOURCE_MASK 0x00000001U
#define PL_SYS_CTRL_VIDEO_STATUS_FRAME_ACTIVE_MASK  0x00000002U
#define PL_SYS_CTRL_VIDEO_STATUS_ERROR_STICKY_MASK  0x00000004U


/**************************** Type Definitions *****************************/
/**
 *
 * Write a value to a PL_SYS_CTRL register. A 32 bit write is performed.
 * If the component is implemented in a smaller width, only the least
 * significant data is written.
 *
 * @param   BaseAddress is the base address of the PL_SYS_CTRLdevice.
 * @param   RegOffset is the register offset from the base to write to.
 * @param   Data is the data written to the register.
 *
 * @return  None.
 *
 * @note
 * C-style signature:
 * 	void PL_SYS_CTRL_mWriteReg(u32 BaseAddress, unsigned RegOffset, u32 Data)
 *
 */
#define PL_SYS_CTRL_mWriteReg(BaseAddress, RegOffset, Data) \
  	Xil_Out32((BaseAddress) + (RegOffset), (u32)(Data))

/**
 *
 * Read a value from a PL_SYS_CTRL register. A 32 bit read is performed.
 * If the component is implemented in a smaller width, only the least
 * significant data is read from the register. The most significant data
 * will be read as 0.
 *
 * @param   BaseAddress is the base address of the PL_SYS_CTRL device.
 * @param   RegOffset is the register offset from the base to write to.
 *
 * @return  Data is the data from the register.
 *
 * @note
 * C-style signature:
 * 	u32 PL_SYS_CTRL_mReadReg(u32 BaseAddress, unsigned RegOffset)
 *
 */
#define PL_SYS_CTRL_mReadReg(BaseAddress, RegOffset) \
    Xil_In32((BaseAddress) + (RegOffset))

/************************** Function Prototypes ****************************/
/**
 *
 * Run a self-test on the driver/device. Note this may be a destructive test if
 * resets of the device are performed.
 *
 * If the hardware system is not built correctly, this function may never
 * return to the caller.
 *
 * @param   baseaddr_p is the base address of the PL_SYS_CTRL instance to be worked on.
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
XStatus PL_SYS_CTRL_Reg_SelfTest(void * baseaddr_p);

#endif // PL_SYS_CTRL_H
