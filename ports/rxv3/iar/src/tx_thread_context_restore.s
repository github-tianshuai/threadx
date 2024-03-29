;/**************************************************************************/
;/*                                                                        */
;/*       Copyright (c) Microsoft Corporation. All rights reserved.        */
;/*                                                                        */
;/*       This software is licensed under the Microsoft Software License   */
;/*       Terms for Microsoft Azure RTOS. Full text of the license can be  */
;/*       found in the LICENSE file at https://aka.ms/AzureRTOS_EULA       */
;/*       and in the root directory of this software.                      */
;/*                                                                        */
;/**************************************************************************/
;
;
;/**************************************************************************/
;/**************************************************************************/
;/**                                                                       */ 
;/** ThreadX Component                                                     */ 
;/**                                                                       */
;/**   Thread                                                              */
;/**                                                                       */
;/**************************************************************************/
;/**************************************************************************/
;
;
;#define TX_SOURCE_CODE
;
;
;/* Include necessary system files.  */
;
;#include "tx_api.h"
;#include "tx_thread.h"
;#include "tx_timer.h"
;
;
    extern __tx_thread_system_state
    extern __tx_thread_current_ptr
    extern __tx_thread_preempt_disable
    extern __tx_thread_execute_ptr
    extern __tx_timer_time_slice
    extern __tx_thread_schedule

    section .text:CODE:ROOT

;/**************************************************************************/ 
;/*                                                                        */ 
;/*  FUNCTION                                               RELEASE        */ 
;/*                                                                        */ 
;/*    _tx_thread_context_restore                           RXv3/IAR       */
;/*                                                           6.1.7        */
;/*  AUTHOR                                                                */ 
;/*                                                                        */ 
;/*    William E. Lamie, Microsoft Corporation                             */
;/*                                                                        */ 
;/*  DESCRIPTION                                                           */ 
;/*                                                                        */ 
;/*    This function restores the interrupt context if it is processing a  */ 
;/*    nested interrupt.  If not, it returns to the interrupt thread if no */ 
;/*    preemption is necessary.  Otherwise, if preemption is necessary or  */ 
;/*    if no thread was running, the function returns to the scheduler.    */ 
;/*                                                                        */ 
;/*  INPUT                                                                 */ 
;/*                                                                        */ 
;/*    None                                                                */ 
;/*                                                                        */ 
;/*  OUTPUT                                                                */ 
;/*                                                                        */ 
;/*    None                                                                */ 
;/*                                                                        */ 
;/*  CALLS                                                                 */ 
;/*                                                                        */ 
;/*    _tx_thread_schedule                   Thread scheduling routine     */ 
;/*                                                                        */ 
;/*  CALLED BY                                                             */ 
;/*                                                                        */ 
;/*    ISRs                                  Interrupt Service Routines    */ 
;/*                                                                        */ 
;/*  RELEASE HISTORY                                                       */ 
;/*                                                                        */ 
;/*    DATE              NAME                      DESCRIPTION             */ 
;/*                                                                        */ 
;/*  06-02-2021     William E. Lamie         Initial Version 6.1.7         */
;/*                                                                        */ 
;/**************************************************************************/ 
    public __tx_thread_context_restore

__tx_thread_context_restore:
;
;    /* Lockout interrupts.  */

     CLRPSW I                                 ; disable interrupts

;    /* Determine if interrupts are nested.  */
;    if (--_tx_thread_system_state)
;    {

     MOV.L    #__tx_thread_system_state, R1
     MOV.L    [R1], R2
     SUB      #1, R2
     MOV.L    R2,[R1]
     BEQ      __tx_thread_not_nested_restore 

;
;    /* Interrupts are nested.  */
;
;    /* Recover the saved registers from the interrupt stack
;       and return to the point of interrupt.  */
;
__tx_thread_nested_restore:
     POPC    FPSW                                ; restore FPU status   
     POPM    R14-R15             ; restore R14-R15
     POPM    R3-R5               ; restore R3-R5
     POPM    R1-R2               ; restore R1-R2
     RTE                         ; return to point of interrupt, restore PSW including IPL
;    }

__tx_thread_not_nested_restore:
;
;    /* Determine if a thread was interrupted and no preemption is required.  */
;    else if (((_tx_thread_current_ptr) && (_tx_thread_current_ptr == _tx_thread_execute_ptr) 
;               || (_tx_thread_preempt_disable))
;    {
    
     MOV.L    #__tx_thread_current_ptr, R1       ; Pickup current thread ptr address
     MOV.L    [R1], R2
     CMP      #0, R2
     BEQ      __tx_thread_idle_system_restore 
     
     MOV.L    #__tx_thread_preempt_disable, R3   ; pick up preempt disable flag
     MOV.L    [R3], R3
     CMP      #0, R3
     BNE      __tx_thread_no_preempt_restore     ; if pre-empt disable flag set, we simply return to the original point of interrupt regardless
     
     MOV.L    #__tx_thread_execute_ptr, R3       ; (_tx_thread_current_ptr != _tx_thread_execute_ptr)
     CMP      [R3], R2
     BNE      __tx_thread_preempt_restore        ; jump to pre-empt restoring
;
__tx_thread_no_preempt_restore:
     SETPSW  U                   ; user stack
	 POPC    FPSW                ; restore FPU status
     POPM    R14-R15             ; restore R14-R15
     POPM    R3-R5               ; restore R3-R5
     POPM    R1-R2               ; restore R1-R2
     RTE                         ; return to point of interrupt, restore PSW including IPL

;    }
;    else
;    {

__tx_thread_preempt_restore:

;    /* Save the remaining time-slice and disable it.  */
;    if (_tx_timer_time_slice)
;    {

     MOV.L    #__tx_timer_time_slice, R3        ; Pickup time-slice address
     MOV.L    [R3],R4                           ; Pickup actual time-slice
     CMP      #0, R4
     BEQ      __tx_thread_dont_save_ts          ; no time slice to save
;
;        _tx_thread_current_ptr -> tx_thread_time_slice =  _tx_timer_time_slice;
;        _tx_timer_time_slice =  0;
;
     MOV.L    R4,24[R2]                         ; Save thread's time slice
     MOV.L    #0,R4                             ; Clear value
     MOV.L    R4,[R3]                           ; Disable global time slice flag
;    }
__tx_thread_dont_save_ts:
;
;   /* Now store the remaining registers!   */

     SETPSW   U                                 ; user stack
     PUSHM    R6-R13
     
     MVFACGU   #0, A1, R4                       ; Save accumulators.
     MVFACHI   #0, A1, R5
     MVFACLO   #0, A1, R6
     PUSHM     R4-R6
     MVFACGU   #0, A0, R4
     MVFACHI   #0, A0, R5
     MVFACLO   #0, A0, R6
     PUSHM     R4-R6
     
     MOV.L    #1, R3                            ; indicate interrupt stack frame
     PUSH.L   R3

;
;    /* Clear the current task pointer.  */
;    _tx_thread_current_ptr =  TX_NULL;
;    R1 ->  _tx_thread_current_ptr
;    R2 -> *_tx_thread_current_ptr

     MOV.L   R0,8[R2]                        ; Save thread's stack pointer in thread control block
     MOV.L   #0,R2                           ; Build NULL value
     MOV.L   R2,[R1]                         ; Set current thread to NULL

;    /* Return to the scheduler.  */
;    _tx_thread_schedule();

__tx_thread_idle_system_restore:
     MVTC    #0, PSW                          ; reset interrupt priority level to 0
     BRA     __tx_thread_schedule             ; jump to scheduler
;    }
;
;}
;
    END
