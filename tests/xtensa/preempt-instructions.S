/* GNU MMIO load,post-load progress,RFE and store for opt-in preemption. */
.text
.begin no-transform
l32i a4,a1,0
movi a2,42
rfe
s32i a4,a1,0
.end no-transform
