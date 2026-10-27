"""Independent association of presentation feedback with buffer commits.

This checks protocol ordering, not pixels inside the buffer or physical scanout.
Only presented outcomes must have a distinct commit with a non-null attachment;
discarded/cancelled feedback is retained without counting it as a completed frame.
"""
import re

def presentation_commits(wire, manager, surface):
    active, records, pending = {}, [], []
    attachment = None
    commits = 0
    for line in wire.splitlines():
        match = re.search(rf'wp_presentation#{manager}\.feedback\(wl_surface#{surface}, new id wp_presentation_feedback#(\d+)\)', line)
        if match:
            proxy = int(match[1])
            assert proxy not in active, ('Feedback proxy reused while active', proxy)
            row = dict(tag=len(records)+1, proxy=proxy, status=None, commit=None, buffer=None)
            records.append(row); active[proxy] = row; pending.append(row)
        match = re.search(rf'wl_surface#{surface}\.attach\(([^,]+),', line)
        if match:
            buffer = re.fullmatch(r'wl_buffer#(\d+)', match[1].strip())
            attachment = int(buffer[1]) if buffer else None
        if re.search(rf'wl_surface#{surface}\.commit\(\)', line):
            commits += 1
            for row in pending:
                row.update(commit=commits, buffer=attachment)
            pending.clear(); attachment = None
        match = re.search(r'wp_presentation_feedback#(\d+)\.(presented|discarded|destroy)\(', line)
        if match and int(match[1]) in active:
            row = active.pop(int(match[1]))
            row['status'] = dict(presented=1, discarded=2, destroy=3)[match[2]]
            if row in pending:
                pending.remove(row)
    presented = [row for row in records if row['status'] == 1]
    assert all(row['commit'] is not None and row['buffer'] is not None for row in presented), ('Presented feedback associated with an empty/no commit', presented)
    assert len({row['commit'] for row in presented}) == len(presented), ('Multiple completed frames counted from one surface commit', presented)
    return dict(surface=surface, manager=manager, commits=commits,
                feedback=records, presented_buffer_commits=len(presented),
                pixels_inside_buffer_verified=False, physical_scanout_verified=False)
