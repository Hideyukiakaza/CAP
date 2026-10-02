; Copyright 2026 Devadath A A (aka Hideyukiakaza)
;
; Licensed under the Apache License, Version 2.0 (the "License");
; you may not use this file except in compliance with the License.
; You may obtain a copy of the License at
;
;     http://www.apache.org/licenses/LICENSE-2.0
;
; Unless required by applicable law or agreed to in writing, software
; distributed under the License is distributed on an "AS IS" BASIS,
; WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
; See the License for the specific language governing permissions and
; limitations under the License.

; src/codegen/target.inc - Target Architecture Definitions for CAP v0.1

%define TARGET_X86_64       0
%define TARGET_ARM64        1
%define TARGET_FREESTANDING 2
%define TARGET_NO_BOOT_STUB 3
%define TARGET_BOOT_THIN    4

; ELF Machine codes
%define EM_X86_64  0x3E
%define EM_AARCH64 0xB7
