-- Allow users to record useful feedback as well as problems.
alter table public.expression_feedback_events
  drop constraint if exists expression_feedback_events_primary_choice_check;

alter table public.expression_feedback_events
  add constraint expression_feedback_events_primary_choice_check
  check (primary_choice in (
    'helpful',
    'good_angle',
    'just_what_i_wanted',
    'no_change_needed',
    'incorrect',
    'not_helpful',
    'repetitive',
    'style_dislike',
    'other'
  ));
