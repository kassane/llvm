; Regression test for the PlayStation 3 GameOS / lv2 target (ppc64-unknown-lv2),
; an ILP32-on-PPC64 configuration: 64-bit big-endian PowerPC ISA with 32-bit
; pointers (datalayout -p:32:32) and the ELFv1 ABI.
;
; Historically instruction selection aborted on this target because i32 address
; nodes could not feed the inherently 64-bit TOC / function-descriptor
; machinery:
;   * llvm-project#169283: Cannot select i64 = any_extend(PPCISD::TOC_ENTRY
;     ... TargetGlobalAddress:i32)  -- taking the address of a global.
;   * llvm-project#55456 : Cannot select PPCISD::CALL_NOP with an i32
;     TargetGlobalAddress         -- calling an external function.
; Dereferencing a global then hit an impossible GPRC->G8RC base-register copy.
;
; The fix materializes addresses in the 64-bit TOC width, truncates to the i32
; pointer width at the ABI edge, references call targets at the 64-bit
; relocation width, and addresses memory with the underlying 64-bit value --
; mirroring GCC's POINTERS_EXTEND_UNSIGNED handling on powerpc64-ps3-elf.

; RUN: llc -verify-machineinstrs -mtriple=ppc64-unknown-lv2 < %s | FileCheck %s

target datalayout = "E-m:e-p:32:32-Fi64-i64:64-i128:128-n32:64"
target triple = "ppc64-unknown-lv2"

@g = global i32 7
declare void @ext()

; Functions emit an ELFv1 function descriptor (OPD entry).
; CHECK: .section .opd,"aw",@progbits

; Taking the address of a global: TOC-indirect materialization (issue #169283).
; CHECK-LABEL: takeaddr:
; CHECK:       addis 3, 2, .LC0@toc@ha
; CHECK-NEXT:  ld 3, .LC0@toc@l(3)
; CHECK:       blr
define ptr @takeaddr() {
  ret ptr @g
}

; Calling an external function: bl + TOC-restore nop (issue #55456).
; CHECK-LABEL: docall:
; CHECK:       bl ext
; CHECK-NEXT:  nop
; CHECK:       blr
define void @docall() {
  call void @ext()
  ret void
}

; Loading through a global pointer: the i32 pointer is addressed via the full
; 64-bit TOC value, then the word is loaded (no impossible reg-class copy).
; CHECK-LABEL: loadg:
; CHECK:       addis 3, 2, .LC0@toc@ha
; CHECK-NEXT:  ld 3, .LC0@toc@l(3)
; CHECK-NEXT:  lwz 3, 0(3)
; CHECK:       blr
define i32 @loadg() {
  %v = load i32, ptr @g
  ret i32 %v
}
