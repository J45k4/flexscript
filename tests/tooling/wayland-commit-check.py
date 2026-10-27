#!/usr/bin/env python3
"""CPU-only negative controls for presentation/frame-count evidence."""
import sys, unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'scripts'))
from wayland_commit_check import presentation_commits

def feedback(proxy=3):
    return f'wp_presentation#1.feedback(wl_surface#2, new id wp_presentation_feedback#{proxy})'

class CommitEvidence(unittest.TestCase):
    def test_buffer_can_be_attached_before_feedback(self):
        wire = '\n'.join(['wl_surface#2.attach(wl_buffer#9, 0, 0)', feedback(),
                          'wl_surface#2.commit()', 'wp_presentation_feedback#3.presented(0)'])
        row = presentation_commits(wire, 1, 2)
        self.assertEqual(row['presented_buffer_commits'], 1)
        self.assertEqual(row['feedback'][0]['buffer'], 9)

    def test_empty_commit_cannot_borrow_a_later_attachment(self):
        wire = '\n'.join([feedback(), 'wl_surface#2.commit()',
                          'wl_surface#2.attach(wl_buffer#9, 0, 0)', 'wl_surface#2.commit()',
                          'wp_presentation_feedback#3.presented(0)'])
        with self.assertRaises(AssertionError): presentation_commits(wire, 1, 2)

    def test_two_feedbacks_on_one_commit_are_not_two_frames(self):
        wire = '\n'.join([feedback(3), feedback(4), 'wl_surface#2.attach(wl_buffer#9, 0, 0)',
                          'wl_surface#2.commit()', 'wp_presentation_feedback#3.presented(0)',
                          'wp_presentation_feedback#4.presented(0)'])
        with self.assertRaises(AssertionError): presentation_commits(wire, 1, 2)

    def test_cursor_or_other_surface_cannot_supply_the_buffer(self):
        wire = '\n'.join([feedback(), 'wl_surface#7.attach(wl_buffer#9, 0, 0)',
                          'wl_surface#7.commit()', 'wl_surface#2.commit()',
                          'wp_presentation_feedback#3.presented(0)'])
        with self.assertRaises(AssertionError): presentation_commits(wire, 1, 2)

    def test_proxy_and_buffer_reuse_still_require_distinct_commits(self):
        frame = '\n'.join([feedback(), 'wl_surface#2.attach(wl_buffer#9, 0, 0)',
                           'wl_surface#2.commit()', 'wp_presentation_feedback#3.presented(0)'])
        row = presentation_commits(frame + '\n' + frame, 1, 2)
        self.assertEqual(row['presented_buffer_commits'], 2)
        self.assertEqual([r['tag'] for r in row['feedback']], [1, 2])
        self.assertEqual([r['commit'] for r in row['feedback']], [1, 2])

    def test_discarded_or_cancelled_feedback_is_not_a_completed_frame(self):
        wire = '\n'.join([feedback(3), 'wl_surface#2.attach(nil, 0, 0)',
                          'wl_surface#2.commit()', 'wp_presentation_feedback#3.discarded()',
                          feedback(4), 'wp_presentation_feedback#4.destroy()'])
        row = presentation_commits(wire, 1, 2)
        self.assertEqual(row['presented_buffer_commits'], 0)
        self.assertEqual([r['status'] for r in row['feedback']], [2, 3])

if __name__ == '__main__': unittest.main()
