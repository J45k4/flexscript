import "../call-frame.flex";
import "call-local-spans.flex";
import "call-frame-memory.flex";

// Milestone-1 call-entry state link. The initialized-state bundle
// (entry-initialized.flex) derives the writable buffer extents and their
// separation from the checked shared-startup stages. This bundle connects
// that initialized state to the production accepted entry stage: the
// selected-span premises of the checked vm_enter_accepted contract follow
// from the initialized buffers plus the bounded call geometry, and the
// production transition then installs the first frame record and advances
// the cursors. The saved-field values are carried by the checked source
// contracts of vm_install_call_frame and vm_enter_accepted. Parser
// establishment of the record values and the full vm_enter guard composition
// remain separate obligations.

// The accepted entry stage under the initialized-state buffer grants. This
// root is checked before the entry root below it, so the entry root consumes
// its checked contract instead of re-inlining the accepted transition.
requires writable_bytes(vm_stack,524288);
requires writable_bytes(vm_local_memory,8388608);
requires writable_bytes(vm_frames,40960);
requires disjoint_bytes(vm_stack,524288,vm_local_memory,8388608);
requires disjoint_bytes(vm_frames,40960,vm_local_memory,8388608);
requires vm_depth == 0;
requires vm_sp >= 0 && vm_sp <= 524288;
requires vm_local_base >= 0 && vm_local_base <= vm_local_top;
requires vm_local_top >= 0 && vm_local_top <= 8388608;
requires pc >= 0 && pc <= 268435440 && (pc & 15) == 0;
requires count >= 0 && count <= slots && slots <= 4096 && count*8 <= vm_sp;
requires local_length == slots*8 && local_length >= 0 && local_length <= 32768;
requires vm_local_top+local_length <= 8388608;
requires readable_bytes(vm_stack+(vm_sp-count*8),count*8);
requires writable_bytes(vm_local_memory+vm_local_top,local_length);
requires disjoint_bytes(vm_stack+(vm_sp-count*8),count*8,vm_local_memory+vm_local_top,local_length);
requires writable_bytes(vm_frames+vm_depth*40,40);
requires disjoint_bytes(vm_frames+vm_depth*40,40,vm_local_memory+vm_local_top,local_length);
modifies vm_depth,vm_sp,vm_pc,vm_local_base,vm_local_top,bytes(vm_frames+vm_depth*40,40),bytes(vm_local_memory+vm_local_top,local_length);
ensures result == 1;
ensures vm_depth == old(vm_depth)+1;
ensures vm_sp == old(vm_sp)-count*8;
ensures vm_pc == pc+16;
ensures vm_local_base == old(vm_local_top);
ensures vm_local_top == old(vm_local_top)+local_length;
fn entry_accepted_from_initialized(index,return_pc,pc,count,slots,local_length) {
    proof {
        assert slots*8 == local_length;
        assert slots*8 >= 0 && slots*8 <= 32768;
        vm_call_destination_span(vm_local_memory,vm_local_top,slots);
        vm_call_spans_separated(vm_stack,vm_local_memory,vm_sp,vm_local_top,count,slots);
        vm_saved_record_separate_from_copy(vm_frames,vm_local_memory,vm_depth,vm_local_top,slots);
    }
    return vm_enter_accepted(index,return_pc,pc,count,slots);
}

// The selected-span premises of the accepted entry stage, derived from the
// initialized guest buffers and the bounded call geometry by the checked
// span lemmas. The entry root below consumes these conclusions.
requires writable_bytes(vm_stack,524288);
requires writable_bytes(vm_local_memory,8388608);
requires writable_bytes(vm_frames,40960);
requires disjoint_bytes(vm_stack,524288,vm_local_memory,8388608);
requires disjoint_bytes(vm_frames,40960,vm_local_memory,8388608);
requires vm_depth == 0;
requires vm_sp >= 0 && vm_sp <= 524288;
requires vm_local_base >= 0 && vm_local_base <= vm_local_top;
requires vm_local_top >= 0 && vm_local_top <= 8388608;
requires count >= 0 && count <= slots && slots <= 4096 && count*8 <= vm_sp;
requires local_length == slots*8 && local_length >= 0 && local_length <= 32768;
requires vm_local_top+local_length <= 8388608;
modifies nothing;
ensures readable_bytes(vm_stack+(vm_sp-count*8),count*8);
ensures writable_bytes(vm_local_memory+vm_local_top,local_length);
ensures disjoint_bytes(vm_stack+(vm_sp-count*8),count*8,vm_local_memory+vm_local_top,local_length);
ensures writable_bytes(vm_frames+vm_depth*40,40);
ensures disjoint_bytes(vm_frames+vm_depth*40,40,vm_local_memory+vm_local_top,local_length);
fn entry_selected_spans_from_initialized(count,slots,local_length) {
    proof {
        assert count >= 0;
        assert count <= slots;
        assert slots <= 4096;
        assert count*8 <= vm_sp;
        assert vm_local_top+local_length <= 8388608;
        vm_call_argument_span(vm_stack,vm_sp,count);
        vm_call_destination_span(vm_local_memory,vm_local_top,slots);
        vm_call_spans_separated(vm_stack,vm_local_memory,vm_sp,vm_local_top,count,slots);
        call_frame_record_writable(vm_frames,vm_depth);
        vm_saved_record_separate_from_copy(vm_frames,vm_local_memory,vm_depth,vm_local_top,slots);
    }
    return 0;
}

// The first complete call entry on the initialized state. The count and slot
// values are the production function-record loads; the accepted stage runs
// with the selected spans stated in its checked contract's exact form, which
// the derivation root above establishes from the initialized buffers. The
// record's values are premises; parser establishment remains open.
requires writable_bytes(vm_stack,524288);
requires writable_bytes(vm_local_memory,8388608);
requires writable_bytes(vm_frames,40960);
requires disjoint_bytes(vm_stack,524288,vm_local_memory,8388608);
requires disjoint_bytes(vm_frames,40960,vm_local_memory,8388608);
requires vm_depth == 0;
requires vm_sp >= 0 && vm_sp <= 524288;
requires vm_local_base >= 0 && vm_local_base <= vm_local_top;
requires vm_local_top >= 0 && vm_local_top <= 8388608;
requires index >= 0 && index < function_count && function_count >= 0;
requires readable_bytes(functions+index*32,32);
requires !(output_size<16 || load64(functions+index*32+16)<0 || load64(functions+index*32+16)>output_size-16 || (load64(functions+index*32+16)&15)!=0);
requires readable_bytes(output+load64(functions+index*32+16),16);
requires load64(output+load64(functions+index*32+16)) == 18;
requires count == load64(functions+index*32+24);
requires slots == load64(output+load64(functions+index*32+16)+8);
requires count >= 0 && count <= slots && slots <= 4096 && count*8 <= vm_sp;
requires vm_local_top+slots*8 <= 8388608;
requires readable_bytes(vm_stack+(vm_sp-count*8),count*8);
requires writable_bytes(vm_local_memory+vm_local_top,slots*8);
requires disjoint_bytes(vm_stack+(vm_sp-count*8),count*8,vm_local_memory+vm_local_top,slots*8);
requires writable_bytes(vm_frames+vm_depth*40,40);
requires disjoint_bytes(vm_frames+vm_depth*40,40,vm_local_memory+vm_local_top,slots*8);
requires load64(functions+index*32+16) <= 268435440;
modifies vm_error,vm_depth,vm_sp,vm_local_base,vm_local_top,vm_pc,bytes(vm_frames+vm_depth*40,40),bytes(vm_local_memory+vm_local_top,slots*8);
ensures result == 1 && vm_error == old(vm_error);
ensures vm_depth == old(vm_depth)+1;
ensures vm_sp == old(vm_sp)-count*8;
ensures vm_local_base == old(vm_local_top);
ensures vm_local_top == old(vm_local_top)+slots*8;
ensures vm_pc == old(load64(functions+index*32+16))+16;
fn enter_from_initialized_state(index,return_pc,count,slots) {
    return entry_accepted_from_initialized(
        index,return_pc,
        load64(functions+index*32+16),count,slots,slots*8);
}
