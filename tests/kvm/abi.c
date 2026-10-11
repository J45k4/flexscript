// Build-time assertions against Linux headers; not used by the monitor.
#include <linux/kvm.h>
#include <stddef.h>
#define CHECK(a,b) _Static_assert((a)==(b), #a)
CHECK(KVM_GET_API_VERSION,0xae00);
CHECK(KVM_CREATE_VM,0xae01);
CHECK(KVM_CREATE_VCPU,0xae41);
CHECK(KVM_SET_TSS_ADDR,0xae47);
CHECK(KVM_GET_VCPU_MMAP_SIZE,0xae04);
CHECK(KVM_SET_USER_MEMORY_REGION,0x4020ae46);
CHECK(KVM_GET_SUPPORTED_CPUID,0xc008ae05);
CHECK(KVM_SET_CPUID2,0x4008ae90);
CHECK(KVM_GET_SREGS,0x8138ae83);
CHECK(KVM_SET_SREGS,0x4138ae84);
CHECK(KVM_SET_REGS,0x4090ae82);
CHECK(KVM_RUN,0xae80);
CHECK(sizeof(struct kvm_segment),24);
CHECK(sizeof(struct kvm_sregs),312);
CHECK(sizeof(struct kvm_regs),144);
CHECK(sizeof(struct kvm_userspace_memory_region),32);
CHECK(sizeof(struct kvm_cpuid_entry2),40);
CHECK(offsetof(struct kvm_sregs,cr0),224);
CHECK(offsetof(struct kvm_sregs,cr4),248);
CHECK(offsetof(struct kvm_sregs,efer),264);
CHECK(offsetof(struct kvm_regs,rsp),48);
CHECK(offsetof(struct kvm_regs,rip),128);
CHECK(offsetof(struct kvm_regs,rflags),136);
CHECK(offsetof(struct kvm_run,exit_reason),8);
CHECK(offsetof(struct kvm_run,io),32);
CHECK(offsetof(struct kvm_run,io.count),36);
CHECK(offsetof(struct kvm_run,io.data_offset),40);
CHECK(KVM_EXIT_IO,2);
CHECK(KVM_EXIT_HLT,5);
int main(void) {return 0;}
